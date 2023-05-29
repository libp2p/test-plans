terraform {
  backend "s3" {
    bucket         = "terraform-tfstate"
    key            = "github.com/libp2p/test-plans/perf/terraform/ci_config/terraform.tfstate"
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

module "ci" {
  source = "../ci"
}

module "long_lived_server" {
  source = "../long_lived"
}

module "long_lived_client" {
  source = "../long_lived"
}

module "short_lived_server" {
  source = "../short_lived"
}

module "short_lived_client" {
  source = "../short_lived"
}
