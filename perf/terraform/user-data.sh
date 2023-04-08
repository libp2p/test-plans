#!/bin/bash

sudo yum update -y
sudo yum install docker -y
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker ec2-user

docker run -d --restart always --network host mxinden/libp2p-perf
