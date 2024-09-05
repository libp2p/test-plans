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
}

provider "aws" {
  alias  = "us-west-2"
  region = "us-west-2"
  default_tags {
    tags = local.tags
  }
}

provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1"
  default_tags {
    tags = local.tags
  }
}


variable "ci_enabled" {
  type        = bool
  description = "Whether or not to create resources required to automate the setup in CI (e.g. IAM user, cleanup Lambda)"
  default     = false
}

variable "long_lived_enabled" {
  type        = bool
  description = "Whether or not to create long lived resources (in CI, used across runs; e.g. VPCs)"
  default     = false
}

variable "short_lived_enabled" {
  type        = bool
  description = "Whether or not to create short lived resources (in CI, specific to each run; e.g. EC2 instances)"
  default     = true
}

module "ci" {
  count = var.ci_enabled ? 1 : 0

  source = "../../modules/ci"

  regions = ["us-west-2", "us-east-1"]
  tags = local.tags

  providers = {
    aws = aws.us-west-2
  }
}

module "long_lived_server" {
  count = var.long_lived_enabled ? 1 : 0

  source = "../../modules/long_lived"

  region = "us-west-2"
  ami    = "ami-002829755fa238bfa"

  providers = {
    aws = aws.us-west-2
  }
}

module "long_lived_client" {
  count = var.long_lived_enabled ? 1 : 0

  source = "../../modules/long_lived"

  region = "us-east-1"
  ami    = "ami-051f7e7f6c2f40dc1"

  providers = {
    aws = aws.us-east-1
  }
}

module "long_lived_relay" {
  count = var.long_lived_enabled ? 1 : 0

  source = "../../modules/long_lived"

  region = "us-east-1"
  ami    = "ami-051f7e7f6c2f40dc2" // TODO: what should this value be?

  providers = {
    aws = aws.us-east-1
  }
}

module "short_lived_server" {
  count = var.short_lived_enabled ? 1 : 0

  source = "../../modules/short_lived"

  providers = {
    aws = aws.us-west-2
  }

  depends_on = [module.long_lived_server]
}

module "short_lived_client" {
  count = var.short_lived_enabled ? 1 : 0

  source = "../../modules/short_lived"

  providers = {
    aws = aws.us-east-1
  }

  depends_on = [module.long_lived_client]
}

module "short_lived_relay" {
  count = var.short_lived_enabled ? 1 : 0

  source = "../../modules/short_lived"

  providers = {
    aws = aws.us-east-1
  }

  depends_on = [module.long_lived_relay]
}

output "client_ip" {
  value = var.short_lived_enabled ? module.short_lived_client[0].public_ip : null
}

output "server_ip" {
  value = var.short_lived_enabled ? module.short_lived_server[0].public_ip : null
}

output "relay_ip" {
  value = var.short_lived_enabled ? module.short_lived_relay[0].public_ip : null
}
