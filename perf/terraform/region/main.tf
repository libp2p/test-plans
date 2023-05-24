variable "region" {
  description = "The AWS region to create resources in"
}

variable "ami" {
  description = "The Amazon Machine Image to use"
}

variable "common_tags" {
  type        = map(string)
  description = "Common tags to apply to all resources"
}

locals {
  availability_zone = "${var.region}a"
}

provider "aws" {
  region = var.region
}

resource "aws_vpc" "perf" {
  cidr_block = "10.0.0.0/16"

  tags = merge(var.common_tags, {
    Name = "perf"
  })
}

resource "aws_subnet" "perf" {
  vpc_id                  = aws_vpc.perf.id
  cidr_block              = "10.0.0.0/16"
  availability_zone       = local.availability_zone
  map_public_ip_on_launch = true

  tags = merge(var.common_tags, {
    Name = "perf"
  })
}

resource "aws_internet_gateway" "perf" {
  vpc_id = aws_vpc.perf.id

  tags = merge(var.common_tags, {
    Name = "perf-igw"
  })
}

resource "aws_route_table" "perf" {
  vpc_id = aws_vpc.perf.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.perf.id
  }

  tags = merge(var.common_tags, {
    Name = "perf-route-table"
  })
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

  tags = merge(var.common_tags, {
    Name = "restricted_inbound_sg"
  })
}

resource "aws_key_pair" "perf" {
  key_name   = "user-public-key"
  public_key = file("${path.module}/files/user.pub")
}

resource "aws_launch_template" "perf" {
  name = "perf-node"
  image_id = var.ami
  instance_type = "m5n.8xlarge"

  subnet_id = aws_subnet.perf.id

  key_name = aws_key_pair.perf.key_name

  vpc_security_group_ids = [aws_security_group.restricted_inbound.id]

  # Debug via:
  # - /var/log/cloud-init.log and
  # - /var/log/cloud-init-output.log
  user_data                   = file("${path.module}/files/user-data.sh")

  tag_specifications {
    resource_type = "instance"

    tags = merge(var.common_tags, {
      Name = "node"
    })
  }

  instance_initiated_shutdown_behavior = "terminate"
}
