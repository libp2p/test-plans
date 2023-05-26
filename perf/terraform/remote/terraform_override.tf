terraform {
  backend "s3" {
    bucket         = "terraform-tfstate"
    key            = "github.com/libp2p/test-plans/perf/terraform/remote/terraform.tfstate"
    region         = "us-west-2"
  }
}

locals {
  root = ".."
}

variable "common_enabled" {
  type        = bool
  description = "Whether or not to create common resources"
  default     = true
}

variable "region_enabled" {
  type        = bool
  description = "Whether or not to create regional resources"
  default     = true
}

variable "ephemeral_enabled" {
  type        = bool
  description = "Whether or not to create ephemeral resources"
  default     = false
}
