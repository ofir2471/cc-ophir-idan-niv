import json
import re
import io
import boto3
from flask import Response, Flask, render_template, request, redirect
from PIL import Image
from PIL.ExifTags import GPSTAGS
from datetime import datetime
import uuid

dynamodb = boto3.resource('dynamodb', 'eu-west-1')
dynm_table = dynamodb.Table('ParkingLotDB')

HOUR_CHARGE = 10
CHARGE_MINUTE_INCREMENTS = 15

app = Flask(__name__)


@app.route('/', methods=['GET'])
def index():
    return render_template('index.html')


@app.route('/entry', methods=['POST'])
def entry():
    raw_plate = request.files['plate']
    client = boto3.client('rekognition')
    buffer = raw_plate.read()
    parkingLot = request.form['parkingLot']
    ticket_id = str(uuid.uuid4())

    response = client.detect_text(Image={'Bytes': buffer})
    for text in response['TextDetections']:
        txt = text['DetectedText']
        plate = ''.join(re.findall('\d', txt))

        if len(plate) > 8 or len(plate) < 7:
            continue  # not a license plate
        dynm_table.put_item(
            Item={
                'ParkingLot': parkingLot,
                'Plate': plate,
                'TicketId': ticket_id,
                'EntryTime': datetime.strftime(datetime.now(), '%y-%m-%d %H:%M:%S')
            })
        return Response(mimetype='application/json',
                        response=json.dumps({'ticket ID': ticket_id}),
                        status=200)

    return Response(mimetype='application/json',
                    response="{'Error': 'No license plate found'}",
                    status=404)


@app.route('/exit', methods=['POST'])
def exit():
    ticket_id = request.form['ticketId']
    dynamo_response = dynm_table.get_item(Key={'TicketId': ticket_id})
    parking_details = dynamo_response.get('Item')
    entry_time = parking_details['EntryTime']
    plate = parking_details['Plate']
    parking_lot = parking_details['ParkingLot']
    entry_time = datetime.strptime(entry_time, '%y-%m-%d %H:%M:%S')
    total_time = datetime.now() - entry_time
    charge = calc_charge(total_time)

    return Response(mimetype='application/json',
                    response=json.dumps({'License Plate': plate,
                                         'Total Time': str(total_time),
                                         'Parking Lot': parking_lot,

                                         'Charge': charge}),
                    status=200)


def calc_charge(total_time):
    hours, remainder = divmod(total_time.total_seconds(), 3600)
    minutes = remainder // 60
    increments = minutes // CHARGE_MINUTE_INCREMENTS
    charge = HOUR_CHARGE * hours + increments * \
        (HOUR_CHARGE / (60 / CHARGE_MINUTE_INCREMENTS))
    return charge
