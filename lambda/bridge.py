import boto3
import base64
import gzip
import ast 
import os
import json

ses = boto3.client('ses')

def notify(from_address, to_address, subject, message):
    ses.send_email(
        Source = from_address, 
        Destination={'ToAddresses': [to_address],'CcAddresses': []}, 
        Message={ 'Subject': {'Data': subject },'Body': {'Text': {'Data': message }}}
    )

def handler(event, context):
    str = event["awslogs"]["data"]
    bytes = base64.b64decode(str)
    data = gzip.decompress(bytes)
    print(data.decode('utf-8'))
    events = ast.literal_eval(data.decode('utf-8'))
    for event in events["logEvents"]:
        message = json.loads(event["message"])
        txt = message["eventSource"] + " " + message['eventName'] + " in " + message["awsRegion"]
        notify(os.environ['EMAIL_FROM'], os.environ['EMAIL_TO'], txt, "AWS notification")
    return data.decode('utf-8')