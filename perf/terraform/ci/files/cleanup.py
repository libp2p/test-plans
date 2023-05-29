import boto3
import os
import json
import datetime

regions = json.loads(os.environ['REGIONS'])  # Assuming this is a JSON array
tags = json.loads(os.environ['TAGS'])  # Assuming this is a JSON object
max_age_minutes = int(os.environ['MAX_AGE_MINUTES']) # Assuming this is an integer

def lambda_handler(event, context):
    # iterate over all regions
    for region in regions:
        ec2 = boto3.client('ec2', region_name=region)

        now = datetime.datetime.now(datetime.timezone.utc)

        filters = [{'Name': 'instance-state-name', 'Values': ['running']}]
        filters = filters + [{
            'Name': 'tag:' + k,
            'Values': [v]
        } for k, v in tags.items()]

        response = ec2.describe_instances(Filters=filters)

        instances = []

        for reservation in response['Reservations']:
            for instance in reservation['Instances']:
                launch_time = instance['LaunchTime']
                instance_id = instance['InstanceId']

                print(
                    f'Instance ID: {instance_id} has been running since {launch_time}.')

                if launch_time < now - datetime.timedelta(minutes=max_age_minutes):
                    print(
                        f'Instance ID: {instance_id} has been running for more than {max_age_minutes} minutes.')
                    instances.append(instance_id)

        if instances:
            ec2.terminate_instances(InstanceIds=instances)
            print(f'Terminating instances: {instances}')
