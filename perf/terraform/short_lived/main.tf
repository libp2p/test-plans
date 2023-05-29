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

resource "aws_instance" "perf" {
  launch_template = "perf-node"
}
