# Configs

The terraform configs defined in this directory are used to provision the infrastructure for the libp2p perf tests.

The configs are named after the type of backend they use. The defaults for what parts of infrastructure they provision differ between the two.

## local

Terraform state in this configuration will be stored locally. The defaults are configured for local development i.e. terraform apply will bring up ALL the infrastructure needed to run the perf tests. It will skip the steps required only for the CI environment.

## remote

Terraform state here will be stored remotely in an S3 bucket. The defaults are configured for the CI environment i.e. terraform apply will only bring up the long-lived infrastructure needed to run the perf tests in CI. It will skip launching EC2 instances because they will be brought up by the CI environment.
