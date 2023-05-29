terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.67.0"
    }
  }
}

locals {
  tags = {
    Project = "perf"
  }
  root = "."
}

variable "ci_enabled" {
  type        = bool
  description = "Whether or not to create resources required to automate the setup in CI (e.g. IAM user, cleanup Lambda)"
  default     = false
}

variable "long_lived_enabled" {
  type        = bool
  description = "Whether or not to create long lived resources (in CI, used across runs; e.g. VPCs)"
  default     = true
}

variable "short_lived_enabled" {
  type        = bool
  description = "Whether or not to create short lived resources (in CI, specific to each run; e.g. EC2 instances)"
  default     = true
}

module "ci" {
  for_each = [var.ci_enabled ? [] : [
    {
      region = "us-west-2"
    }
  ]]

  source = "${local.root}/ci"
  region = each.value.region

  common_tags = local.tags
}

module "long_lived" {
  for_each = [var.long_lived_enabled ? [] : [
    {
      region = "us-west-2",
      ami    = "ami-0747e613a2a1ff483"
      }, {
      region = "us-east-1",
      ami    = "ami-06e46074ae430fba6"
    }
  ]]

  source = "${local.root}/long_lived"
  region = each.value.region
  ami    = each.value.ami

  common_tags = local.tags
}

module "short_lived" {
  for_each = [var.short_lived_enabled ? [] : [
    {
      region = "us-west-2"
      }, {
      region = "us-east-1"
    }
  ]]

  source = "${local.root}/short_lived"
  region = each.value.region

  common_tags = local.tags
}
