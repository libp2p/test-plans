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
  region = "us-west-1"
  ami = "ami-09c5c62bac0d0634e"

  common_tags = {
    Project = "perf"
  }
}

module "client_region" {
  source = "./region"
  region = "us-east-1"
  ami = "ami-00c39f71452c08778"

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
