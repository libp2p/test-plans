# libp2p perf testing

## Setup

1. `cd terraform`
2. Save your public SSH key as the file `./user.pub`.
3. `terraform init`
4. `terraform apply`

## Execute

1. `cd runner`
2. `npm ci`
3. `npm run start -- --client-public-ip $(terraform output -raw -state ../terraform/terraform.tfstate client_public_ip) --server-public-ip $(terraform output -raw -state ../terraform/terraform.tfstate server_public_ip)`

## Add benchmark binary

See `runner/src/versions.ts`.
