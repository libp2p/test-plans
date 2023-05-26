terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

module "server_region" {
  source = "./region"
  region = "us-west-2"
  ami = "ami-0747e613a2a1ff483"

  common_tags = {
    Project = "perf"
  }
}

module "client_region" {
  source = "./region"
  region = "us-east-1"
  ami = "ami-06e46074ae430fba6"

  common_tags = {
    Project = "perf"
  }
}

output "server_public_ip" {
  value       = module.server_region.node_public_ip
  description = "Public IP address of the server instance"
}

output "client_public_ip" {
  value       = module.client_region.node_public_ip
  description = "Public IP address of the client instance"
}
