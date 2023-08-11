terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.67.0"
    }
  }
}

resource "aws_key_pair" "perf" {
  key_name_prefix   = "perf-"
  public_key = file("${path.module}/files/perf.pub")
}

resource "aws_instance" "perf" {
  tags = {
    Name = "perf-node"
  }

  launch_template {
    name = "perf-node"
    version = "1"
  }

  key_name = aws_key_pair.perf.key_name
}

output "public_ip" {
  value = aws_instance.perf.public_ip
}
