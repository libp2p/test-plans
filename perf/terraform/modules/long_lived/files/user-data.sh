#!/bin/bash

sudo yum install make -y

sudo yum -y install iperf3

# Bump UDP receive buffer size. See https://github.com/quic-go/quic-go/wiki/UDP-Receive-Buffer-Size.
sudo sysctl -w net.core.rmem_max=2500000
sudo sysctl -w net.core.wmem_max=2500000

# Set maximum TCP send and receive window to bandwidth-delay-product.
#
# With a bandwidth of 25 Gbit/s per machine and a ping of 60 ms between the two
# machines, the bandwidth-delay-product is ~178.81 MiB. Set send and receive
# window to 200 MiB.
sudo sysctl -w net.ipv4.tcp_rmem='4096 131072 200000000'
sudo sysctl -w net.ipv4.tcp_wmem='4096 20480 200000000'

sudo yum update -y
sudo yum install docker -y
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker ec2-user

# Taken from https://docs.aws.amazon.com/sdk-for-javascript/v2/developer-guide/setting-up-node-on-ec2-instance.html
curl -fsSL https://rpm.nodesource.com/setup_lts.x | sudo bash -
sudo yum install -y nodejs