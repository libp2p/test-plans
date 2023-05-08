# libp2p performance benchmarking

This project includes the following components:

- `terraform/`: a Terraform scripts to provision infrastructure
- `impl/`: implementations of the [libp2p perf protocol](https://github.com/libp2p/specs/pull/478) running on top of e.g. go-libp2p, rust-libp2p or Go's std-library https stack
- `runner/`: a set of scripts building and running the above implementations on the above infrastructure, reporting the results in `benchmark-results.json`

Benchmark results can be visualized with https://observablehq.com/@mxinden-workspace/libp2p-perf.

## Provision infrastructure

1. `cd terraform`
2. Save your public SSH key as the file `./user.pub`.
3. `terraform init`
4. `terraform apply`

## Build and run implementations

1. `cd runner`
2. `npm ci`
3. `npm run start -- --client-public-ip $(terraform output -raw -state ../terraform/terraform.tfstate client_public_ip) --server-public-ip $(terraform output -raw -state ../terraform/terraform.tfstate server_public_ip)`

## Deprovision infrastructure

1. `cd terraform`
3. `terraform destroy`

## Adding a new implementation

1. Add implementation to `impl/`.
2. Reference implementation in `runner/src/versions.ts`.
