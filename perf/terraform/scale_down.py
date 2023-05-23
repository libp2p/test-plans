import boto3
import os
import json
import datetime

region = os.environ['AWS_REGION']
ec2 = boto3.client('ec2', region_name=region)
tags = os.environ['TAGS']
max_age_minutes = os.environ['MAX_AGE_MINUTES']


def is_lost(instance):
    return instance.launch_time.replace(tzinfo=None) < datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(minutes=max_age_minutes)


def lambda_handler(event, context):
    filter = [{'Name': 'instance-state-name', 'Values': ['running']}]
    filter = filter + [{
        'Name': 'tag:' + k,
        'Values': [v]
    } for k, v in tags.items()]
    instances = [i.id for i in ec2.describe_instances(
        Filters=filter) if is_lost(i)]
    print('found instances: ' + str(instances))
    ec2.stop_instances(InstanceIds=instances)
    print('stopped instances: ' + str(instances))
