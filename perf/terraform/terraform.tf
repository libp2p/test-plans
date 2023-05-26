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

variable "common_enabled" {
  type        = bool
  description = "Whether or not to create common resources"
  default     = false
}

variable "region_enabled" {
  type        = bool
  description = "Whether or not to create regional resources"
  default     = true
}

variable "ephemeral_enabled" {
  type        = bool
  description = "Whether or not to create ephemeral resources"
  default     = true
}

module "common" {
  for_each = [var.common_enabled ? [] : [
    {
      region = "us-west-2"
    }
  ]]

  source = "${local.root}/common"
  region = each.value.region

  common_tags = local.tags
}

module "region" {
  for_each = [var.region_enabled ? [] : [
    {
      region = "us-west-2",
      ami    = "ami-0747e613a2a1ff483"
      }, {
      region = "us-east-1",
      ami    = "ami-06e46074ae430fba6"
    }
  ]]

  source = "${local.root}/region"
  region = each.value.region
  ami    = each.value.ami

  common_tags = local.tags
}

module "ephemeral" {
  for_each = [var.ephemeral_enabled ? [] : [
    {
      region = "us-west-2"
      }, {
      region = "us-east-1"
    }
  ]]

  source = "${local.root}/ephemeral"
  region = each.value.region

  common_tags = local.tags
}
