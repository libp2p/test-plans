# libp2p performance benchmarking

This project includes the following components:

- `terraform/`: a Terraform scripts to provision infrastructure
- `impl/`: implementations of the [libp2p perf protocol](https://github.com/libp2p/specs/blob/master/perf/perf.md) running on top of e.g. go-libp2p, rust-libp2p or Go's std-library https stack
- `runner/`: a set of scripts building and running the above implementations on the above infrastructure, reporting the results in `benchmark-results.json`

Benchmark results can be visualized with https://observablehq.com/@libp2p-workspace/performance-dashboard.

## Running via GitHub Action

1. Create a pull request with your changes on https://github.com/libp2p/test-plans/.
2. Trigger GitHub Action for branch on https://github.com/libp2p/test-plans/actions/workflows/perf.yml (see _Run workflow_ button).
3. Wait for action run to finish and to push a commit to your branch.
4. Visualize results on https://observablehq.com/@libp2p-workspace/performance-dashboard.

## Running with Terraform on AWS manually

### Pre-requisites

- Terraform 1.5.5 or later
- Node.js 18 or later
- [an AWS IAM user](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_users.html)
##
### Provision infrastructure

1. Ensure you ssh agent is running, you can check that via
```bash
   eval "$(ssh-agent -s)"
```
2. Save your public SSH key as the file `./terraform/modules/short_lived/files/perf.pub`; or generate a new key pair with `make ssh-keygen` and add it to your SSH agent with `make ssh-add`.
3. Change to the terraform local directory ```cd terraform/configs/local``` and initalize terraform ```terraform init```
4. `terraform apply` A terraform plan will be generated, type `yes` to continue. -To preview the plan, you can run `terraform plan`
5. Once that is finished, you can get the public IP addresses of the client and server with `terraform output client_ip` and `terraform output server_ip`. Set these to the environment variables via:
   1. `CLIENT_IP=$(terraform output -raw client_ip)`
   2. `SERVER_IP=$(terraform output -raw server_ip)`

**Notes**
- You may need to reset the infrastructure if you encounter any errors, you can do that by running `terraform destroy` and then `terraform apply`.
- While running terraform you may encounter the following error:
  ```bash
    Error: collecting instance settings: reading EC2 Launch Template versions: couldn't find resource
    │
    │   with module.short_lived_server[0].aws_instance.perf,
    │   on ../../modules/short_lived/main.tf line 15, in resource "aws_instance" "perf":
    │   15: resource "aws_instance" "perf" {
  ```
  If you set *TF_VAR* [`long_lived_enabled`](./terraform/configs/local/terraform.tf#L42) env variable to default to **true** terraform should spin up the long-lived resources that are required for the short-lived resources to be created.

- On some occassions the instances may run out of space, this [is a known issue](https://github.com/libp2p/test-plans/pull/249) which requires [the volume to be expanded](https://github.com/libp2p/test-plans/pull/249/files#diff-28d5c648894177b493aed0b03f92e21ff4d926ce824f50499080a33161d0c0baR111-R119)
- It's best to destroy the infrastructure after you're done with your testing, you can do that by running `terraform destroy`.

### Build and run libp2p implementations

Given you have provisioned your infrastructure, you can now build and run the libp2p implementations on the AWS instances.

1. `cd runner`
2. Install the depencies required for the runner `npm ci`
3. The amount of iterations that perf will run your implementation defaults to 10, but you can pass in another value `npm run start -- --client-public-ip $CLIENT_IP --server-public-ip $SERVER_IP --iterations 50`

### Deprovision infrastructure

1. `cd terraform/configs/local`
2. `terraform destroy`

## Adding a new implementation or a new version

1. Add the implementation to new subdirectory in [`impl/*`](./impl/).
    - For a new implementation, create a folder `impl/<your-implementation-name>/` e.g. `go-libp2p`
    - For a new version of an existing implementation, create a folder `impl/<your-implementation-name>/<your-implementation-version>`.
    - In that folder include a `Makefile` that builds an executable and stores it next to the `Makefile` under the name `perf`.
    - Requirements for the executable:
      - Running as a libp2p-perf server:
        - The perf server must not exit as it will be closed by the test runner.
        - The executable must accept the command flag `--run-server` which indicates it's running as server.
      - Running as a libp2p-perf client
        - Given that perf is a client driven set of benchmarks, the performance will be measured by the client.
          - Input via command line
            - `--server-address`
            - `--transport` (see [`runner/versions.ts`](./runner/src/versions.ts#L7-L43) for possible variants)
            - `--upload-bytes` number of bytes to upload per stream.
            - `--download-bytes` number of bytes to download per stream.
          - Output
            - Logging MUST go to `stderr`.
            - Measurement output is printed to **stdout** as JSON in the form of:
              ```json
              {"latency": 0.246442851}
              ```
              Note that the measurement includes the time to (1) establish the
              connection, (2) upload the bytes and (3) download the bytes.
2. For a new implementation, in [`impl/Makefile` include your implementation in the `all` target.](./impl/Makefile#L7)
3. For a new version, reference version in [`runner/src/versions.ts`](./runner/src/versions.ts#L7-L43).
