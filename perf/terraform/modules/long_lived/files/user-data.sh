#!/bin/bash

sudo yum install make -y

sudo yum -y install iperf3

# Bump UDP receive buffer size. See https://github.com/quic-go/quic-go/wiki/UDP-Receive-Buffer-Size.
sudo sysctl -w net.core.rmem_max=2500000

sudo yum update -y
sudo yum install docker -y
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker ec2-user
