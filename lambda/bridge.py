import boto3
import base64
import gzip
import ast 
import os
import json
import datetime

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
        response = message["responseElements"]
        eventSource = message["eventSource"] 
        eventName = message['eventName'] 
        awsRegion = message["awsRegion"]
        instance = response["instancesSet"]["items"][0]
        imageId = instance["imageId"]
        instanceId = instance["instanceId"]
        instanceType = instance["instanceType"]
        instanceState = instance["instanceState"]["name"]
        latency = datetime.datetime.utcnow() - datetime.datetime.strptime(message["eventTime"],'%Y-%m-%dT%H:%M:%SZ')

        subject = f"AWS Notification  ({latency})"
        body = f"{eventSource} {eventName} in {awsRegion}\nImageId: {imageId}\nInstanceId: {instanceId}\nInstanceType: {instanceType}\nInstanceState: {instanceState}"
        notify(os.environ['EMAIL_FROM'], os.environ['EMAIL_TO'], subject, body)
    return data.decode('utf-8')