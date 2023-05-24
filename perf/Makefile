ssh-keygen:
	ssh-keygen -t ed25519 -f ./terraform/region/files/user -N ''

ssh-add:
	ssh-add ./terraform/region/files/user

provision-server:
	aws ec2 run-instances --region=us-west-2 --launch-template LaunchTemplateName=perf-node --count 1 --query 'Instances[0].InstanceId' --output text

provision-client:
	aws ec2 run-instances --region=us-east-1 --launch-template LaunchTemplateName=perf-node --count 1 --query 'Instances[0].InstanceId' --output text

wait:
	aws ec2 wait instance-running --region us-west-2 --instance-ids "$(SERVER_ID)"
	aws ec2 wait instance-running --region us-east-1 --instance-ids "$(CLIENT_ID)"
	echo "$$(aws ec2 describe-instances --region us-west-2 --instance-ids "$(SERVER_ID)" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)" "$$(aws ec2 describe-instances --region us-east-1 --instance-ids "$(CLIENT_ID)" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)"

deprovision-server:
	aws ec2 terminate-instances --region=us-west-2 --instance-ids "$(SERVER_ID)"

deprovision-client:
	aws ec2 terminate-instances --region=us-east-1 --instance-ids "$(CLIENT_ID)"

# https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/serverless-sam-cli-install.html
scale-down:
	sam local invoke ScaleDown --template terraform/common/files/scale_down.yml --event terraform/common/files/scale_down.json
