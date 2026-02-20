terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.67.0"
    }
  }
}

variable "region" {
  description = "The AWS region of the provider"
}

variable "ami" {
  description = "The Amazon Machine Image to use"
}

locals {
  availability_zone = "${var.region}a"
}

resource "aws_vpc" "perf" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "perf" {
  vpc_id                  = aws_vpc.perf.id
  cidr_block              = "10.0.0.0/16"
  availability_zone       = local.availability_zone
  map_public_ip_on_launch = true
}

resource "aws_internet_gateway" "perf" {
  vpc_id = aws_vpc.perf.id
}

resource "aws_route_table" "perf" {
  vpc_id = aws_vpc.perf.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.perf.id
  }
}

resource "aws_route_table_association" "perf" {
  subnet_id      = aws_subnet.perf.id
  route_table_id = aws_route_table.perf.id
}

resource "aws_security_group" "restricted_inbound" {
  name        = "restricted_inbound"
  description = "Allow SSH and port 4001 inbound traffic (TCP and UDP), allow all outbound traffic"
  vpc_id      = aws_vpc.perf.id

  # ICMP
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH (TCP)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 1
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 1
    to_port     = 65535
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_launch_template" "perf" {
  name          = "perf-node"
  image_id      = var.ami
  instance_type = "m5.xlarge"

  # Debug via:
  # - /var/log/cloud-init.log and
  # - /var/log/cloud-init-output.log
  user_data = filebase64("${path.module}/files/user-data.sh")

  instance_initiated_shutdown_behavior = "terminate"

  network_interfaces {
    subnet_id = aws_subnet.perf.id
    security_groups = [aws_security_group.restricted_inbound.id]
    delete_on_termination = true
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 100 # New root volume size in GiB
      volume_type           = "gp2"
      delete_on_termination = true
    }
  }

  update_default_version = true
}
