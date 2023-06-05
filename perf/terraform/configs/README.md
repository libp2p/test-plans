# Configs

The terraform configs defined in this directory are used to provision the infrastructure for the libp2p perf tests.

The configs are named after the type of backend they use. The defaults for what parts of infrastructure they provision differ between the two.

## local

Terraform state in this configuration will be stored locally. The defaults are configured for a single performance benchmark run, i.e. `terraform apply` will bring up short-lived infrastructure only. It will skip long-lived infrastructure like the clean-up Lambda and the instance launch template.

## remote

Terraform state here will be stored remotely in an S3 bucket. `terraform apply` will only bring up the long-lived infrastructure needed to run the performance benchmarks It will skip short-lived infrastructure like launching EC2 instances.
