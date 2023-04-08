# libp2p perf testing

## Setup

1. `cd terraform`
2. Safe your SSH key as a file, e.g. `./mxinden.pub`.
3. Optionally update the reference to the ssh key in `region/main.tf`:
    ```diff

    - resource "aws_key_pair" "mxinden" {
    -   key_name   = "mxinden-public-key"
    -   public_key = file("./mxinden.pub")
    - }
    + resource "aws_key_pair" "your-key" {
    +   key_name   = "your-key-public-key"
    +   public_key = file("./your-key.pub")
    + }
    ```
4. `terraform apply`

## Execute

1. `cd runner`
2. `npm run build`
3. `npm run start -- --client-public-ip $(terraform output -raw -state ../terraform/terraform.tfstate client_public_ip) --server-public-ip $(terraform output -raw -state ../terraform/terraform.tfstate server_public_ip)`

## Add benchmark binary

See `runner/src/versions.ts`.
