#!/usr/bin/env bash

# This script can be used to test the cleanup lambda.
# It requires the AWS CLI and SAM CLI to be installed.
# You can get SAM CLI at https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/serverless-sam-cli-install.html

sam local invoke Cleanup --template cleanup.yml --event cleanup.json
