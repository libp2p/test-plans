# libp2p perf testing

## Setup

1. Safe your SSH key as a file, e.g. `./mxinden.pub`.
2. Optionally update the reference to the ssh key in `terraform.tf`:
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
3. `terraform apply`

## Execute

1. `ssh ec2-user@$(terraform output -raw client_public_ip) sudo docker run --tty --rm --entrypoint perf-client mxinden/libp2p-perf --server-address /ip4/$(terraform output -raw server_public_ip)/tcp/4001`
