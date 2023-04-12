#!/bin/bash

sudo yum update -y
sudo yum install docker -y
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker ec2-user

docker run -d --restart always --network host --entrypoint /app/server mxinden/libp2p-perf@sha256:f567b27347a8d222e88f3c0b160e0547023e88aa700dc5e4255d9fcdf3d08eb1 --secret-key-seed 0
