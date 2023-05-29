terraform {
  backend "s3" {
    bucket         = "terraform-tfstate"
    key            = "github.com/libp2p/test-plans/perf/terraform/configs/ci/terraform.tfstate"
    region         = "us-west-2"
  }
}

variable "ci_enabled" {
  default     = true
}

variable "long_lived_enabled" {
  default     = true
}

variable "short_lived_enabled" {
  default     = false
}
