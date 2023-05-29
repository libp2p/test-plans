variable "region" {
  description = "The AWS region to create resources in"
}

variable "common_tags" {
  type        = map(string)
  description = "Common tags to apply to all resources"
}

provider "aws" {
  region = var.region

  default_tags {
    tags = var.common_tags
  }
}

resource "random_id" "perf" {
  byte_length = 8
}

resource "aws_key_pair" "perf" {
  key_name   = "perf-${random_id.perf.hex}"
  public_key = file("${path.module}/files/perf.pub")
}

resource "aws_instance" "perf" {
  launch_template = "perf-node"

  key_name = aws_key_pair.perf.key_name
}
