terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}

locals {
  common_tags = {
    Project = "perf"
  }
}

resource "aws_vpc" "perf" {
  cidr_block = "10.0.0.0/16"

  tags = merge(local.common_tags, {
    Name = "perf"
  })
}

resource "aws_subnet" "perf" {
  vpc_id                  = aws_vpc.perf.id
  cidr_block              = "10.0.0.0/16"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "perf"
  })
}

resource "aws_internet_gateway" "perf" {
  vpc_id = aws_vpc.perf.id

  tags = merge(local.common_tags, {
    Name = "perf-igw"
  })
}

resource "aws_route_table" "perf" {
  vpc_id = aws_vpc.perf.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.perf.id
  }

  tags = merge(local.common_tags, {
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

  # SSH (TCP)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 4001
    to_port     = 4001
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 4001
    to_port     = 4001
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "restricted_inbound_sg"
  })
}

resource "aws_key_pair" "mxinden" {
  key_name   = "mxinden-public-key"
  public_key = file("./mxinden.pub")
}

resource "aws_instance" "server" {
  ami           = "ami-00c39f71452c08778"
  instance_type = "t2.micro"

  subnet_id = aws_subnet.perf.id

  key_name = aws_key_pair.mxinden.key_name

  vpc_security_group_ids = [aws_security_group.restricted_inbound.id]

  # Debug via:
  # - /var/log/cloud-init.log and
  # - /var/log/cloud-init-output.log
  user_data = file("${path.module}/server-user-data.sh")
  user_data_replace_on_change = true

  tags = merge(local.common_tags, {
    Name = "server"
  })
}

resource "aws_instance" "client" {
  ami           = "ami-00c39f71452c08778"
  instance_type = "t2.micro"

  subnet_id = aws_subnet.perf.id

  key_name = aws_key_pair.mxinden.key_name

  vpc_security_group_ids = [aws_security_group.restricted_inbound.id]

  # Debug via:
  # - /var/log/cloud-init.log and
  # - /var/log/cloud-init-output.log
  user_data = file("${path.module}/client-user-data.sh")
  user_data_replace_on_change = true

  tags = merge(local.common_tags, {
    Name = "client"
  })
}

output "server_public_ip" {
  value       = aws_instance.server.public_ip
  description = "Public IP address of the server instance"
}

output "client_public_ip" {
  value       = aws_instance.client.public_ip
  description = "Public IP address of the client instance"
}

