# libp2p performance benchmarking

This project includes the following components:

- `terraform/`: a Terraform scripts to provision infrastructure
- `impl/`: implementations of the [libp2p perf protocol](https://github.com/libp2p/specs/pull/478) running on top of e.g. go-libp2p, rust-libp2p or Go's std-library https stack
- `runner/`: a set of scripts building and running the above implementations on the above infrastructure, reporting the results in `benchmark-results.json`

Benchmark results can be visualized with https://observablehq.com/@mxinden-workspace/libp2p-perf.

## Provision infrastructure

### Bootstrap

1. `cd terraform`
2. Save your public SSH key as the file `./regions/files/user.pub`.
3. `terraform init`
4. `terraform apply`

### Nodes

1. `SERVER_ID=$(make provision-server)`
2. `CLIENT_ID=$(make provision-client)`
3. `read SERVER_IP CLIENT_IP <<< $(SERVER_ID=$SERVER_ID CLIENT_ID=$CLIENT_ID make wait)`

## Build and run implementations

1. `cd runner`
2. `npm ci`
3. `npm run start -- --client-public-ip $CLIENT_IP --server-public-ip $SERVER_IP`

## Deprovision infrastructure

### Nodes

1. `CLIENT_ID=$CLIENT_ID make deprovision-client`
2. `SERVER_ID=$SERVER_ID make deprovision-server`

### Bootstrap

1. `cd terraform`
2. `terraform destroy`

## Adding a new implementation

1. Add implementation to `impl/`. Requirements for the binary:
  - Running as a libp2p-perf server
    - Command line flags
      - `--run-server`
      - `--secret-key-seed` unsigned integer to be used as a seed by libp2p-based implementations. Likely to go away in future iterations.
  - Running as a libp2p-perf client
      - Input via command line
        - `--server-ip-address`
        - `--transport` (see `runner/versions.ts` for possible variants)
        - `--upload-bytes` number of bytes to upload per stream.
        - `--download-bytes` number of bytes to upload per stream.
      - Output
        - Logging MUST go to stderr.
        - Measurement output is printed to stdout as JSON in the form of:
          ```json
          {"connectionEstablishedSeconds":0.246442851,"uploadSeconds":0.000002077,"downloadSeconds":0.060712241}
          ```

2. Reference implementation in `runner/src/versions.ts`.
