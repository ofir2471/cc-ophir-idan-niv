# debug
# set -o xtrace

KEY_NAME="cloud-course-`date +'%N'`"
KEY_PEM="$KEY_NAME.pem"

echo "create key pair $KEY_PEM to connect to instances and save locally"
aws ec2 create-key-pair --key-name $KEY_NAME \
    | jq -r ".KeyMaterial" > $KEY_PEM

# secure the key pair
chmod 400 $KEY_PEM

SEC_GRP="my-sg-`date +'%N'`"

echo "setup firewall $SEC_GRP"
aws ec2 create-security-group   \
    --group-name $SEC_GRP       \
    --description "Access my instances" 

# figure out my ip
MY_IP=$(curl ipinfo.io/ip)
# debug
# set -o xtrace

KEY_NAME="cloud-course-`date +'%N'`"
KEY_PEM="$KEY_NAME.pem"

echo "creating dynamodb instance ParkingLotDB..."
aws dynamodb create-table \
    --table-name ParkingLotDB \
    --attribute-definitions \
        AttributeName=TicketId,AttributeType=S \
    --key-schema \
        AttributeName=TicketId,KeyType=HASH \
    --provisioned-throughput \
        ReadCapacityUnits=1,WriteCapacityUnits=1 \
    --table-class STANDARD

echo "Waiting for dynamodb creation..."
aws dynamodb describe-table --table-name ParkingLotDB | grep TableStatus

echo "Setting autoscaling..."
aws application-autoscaling register-scalable-target \
    --service-namespace dynamodb \
    --resource-id "table/ParkingLotDB" \
    --scalable-dimension "dynamodb:table:WriteCapacityUnits" \
    --min-capacity 1 \
    --max-capacity 10
aws application-autoscaling register-scalable-target \
    --service-namespace dynamodb \
    --resource-id "table/ParkingLotDB" \
    --scalable-dimension "dynamodb:table:ReadCapacityUnits" \
    --min-capacity 1 \
    --max-capacity 10
aws application-autoscaling describe-scalable-targets \
    --service-namespace dynamodb \
    --resource-id "table/ParkingLotDB"

echo "create key pair $KEY_PEM to connect to instances and save locally"
aws ec2 create-key-pair --key-name $KEY_NAME \
    | jq -r ".KeyMaterial" > $KEY_PEM

# secure the key pair
chmod 400 $KEY_PEM

SEC_GRP="my-sg-`date +'%N'`"

echo "setup firewall $SEC_GRP"
aws ec2 create-security-group   \
    --group-name $SEC_GRP       \
    --description "Access my instances" 

# figure out my ip
MY_IP=$(curl ipinfo.io/ip)
echo "My IP: $MY_IP"

echo "setup rule allowing SSH access to $MY_IP only"
aws ec2 authorize-security-group-ingress        \
    --group-name $SEC_GRP --port 22 --protocol tcp \
    --cidr $MY_IP/32

echo "setup rule allowing HTTP (port 3547) access to $MY_IP only"
aws ec2 authorize-security-group-ingress        \
    --group-name $SEC_GRP --port 3547 --protocol tcp \
    --cidr $MY_IP/32

UBUNTU_20_04_AMI="ami-08ca3fed11864d6bb"

echo "Creating Ubuntu 20.04 instance..."
RUN_INSTANCES=$(aws ec2 run-instances   \
    --image-id $UBUNTU_20_04_AMI        \
    --instance-type t2.micro            \
    --key-name $KEY_NAME                \
    --security-groups $SEC_GRP)

INSTANCE_ID=$(echo $RUN_INSTANCES | jq -r '.Instances[0].InstanceId')

echo "Waiting for instance creation..."
aws ec2 wait instance-running --instance-ids $INSTANCE_ID

PUBLIC_IP=$(aws ec2 describe-instances  --instance-ids $INSTANCE_ID | 
    jq -r '.Reservations[0].Instances[0].PublicIpAddress'
)

echo "New instance $INSTANCE_ID @ $PUBLIC_IP"

echo "deploying code to production"
scp -i $KEY_PEM -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=60" index.html ubuntu@$PUBLIC_IP:/home/ubuntu/
scp -i $KEY_PEM -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=60" app.py ubuntu@$PUBLIC_IP:/home/ubuntu/

echo "setup production environment"
ssh -i $KEY_PEM -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=10" ubuntu@$PUBLIC_IP <<EOF
    mkdir templates
    mv index.html templates/
    sudo apt-get update -y
    sudo apt-get upgrade -y
    sudo apt update -y
    sudo apt upgrade -y
    sudo apt install python3-wheel -y
    sudo apt install python3-pip -y
    sudo pip3 install --upgrade pip
    sudo pip3 install awscli
    sudo pip3 install flask boto3 pillow

    echo "Setup took $((EPOCHSECONDS - TIMESTART)) seconds"

    nohup flask run --host 0.0.0.0  &>/dev/null &
    exit
EOF

