import boto3
import base64
import gzip
import ast 

def handler(event, context):
    str = event["awslogs"]["data"]
    bytes = base64.b64decode(str)
    data = gzip.decompress(bytes)
    dict = ast.literal_eval(data.decode('utf-8'))
    print(data.decode('utf-8'))
    return data.decode('utf-8')