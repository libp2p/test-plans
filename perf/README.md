# libp2p performance benchmarking

This project includes the following components:

- `terraform/`: Terraform scripts to provision AWS infrastructure
- `impl/`: implementations of the [libp2p perf protocol](https://github.com/libp2p/specs/blob/master/perf/perf.md) running on top of e.g. go-libp2p, rust-libp2p or Go's std-library https stack
- `runner/`: Node.js scripts for building and running tests on AWS infrastructure
- **NEW:** `scripts/`: Bash-based test runner for local/remote hardware (no AWS required)
- **NEW:** `impls/`: Dockerized implementations following hole-punch/transport patterns

Benchmark results can be visualized with https://observablehq.com/@libp2p-workspace/performance-dashboard.

## Quick Start (Bash-Based Tests - Recommended)

**NEW:** Run performance tests on your own hardware without AWS!

```bash
# Quick test on single machine
./run_tests.sh --test-select "go-libp2p" --iterations 3

# See QUICKSTART.md for detailed setup instructions
```

**Features:**
- ✅ No AWS account required
- ✅ Run on local hardware or remote servers
- ✅ Docker-based implementations
- ✅ Results in YAML, Markdown, and HTML formats
- ✅ Compatible with hole-punch/transport test patterns

See **[QUICKSTART.md](QUICKSTART.md)** for complete setup and usage instructions.

---

## Setup for Multi-Machine Testing

### SSH Key-Based Authentication

For remote server testing, setup passwordless SSH authentication between your test runner (Computer 1) and server (Computer 2):

#### 1. Generate SSH Key (Computer 1)

```bash
# Generate dedicated key for perf testing
ssh-keygen -t ed25519 -f ~/.ssh/perf_server -N ""
```

This creates two files:
- `~/.ssh/perf_server` - Private key (keep secure)
- `~/.ssh/perf_server.pub` - Public key (copy to server)

#### 2. Copy Public Key to Server (Computer 2)

```bash
# Replace with your server's username and IP/hostname
ssh-copy-id -i ~/.ssh/perf_server.pub perfuser@192.168.1.100
```

You'll be prompted for the password **once**. After this, SSH will use key-based authentication.

#### 3. Test Connection

```bash
# Should connect without password prompt
ssh -i ~/.ssh/perf_server perfuser@192.168.1.100 "echo 'Connection successful'"
```

#### 4. Configure in impls.yaml

Edit `perf/impls.yaml` to add your remote server:

```yaml
servers:
  - id: remote-1
    type: remote
    hostname: "192.168.1.100"    # Your Computer 2 IP/hostname
    username: "perfuser"          # SSH username on Computer 2
    description: "Remote server"

implementations:
  - id: rust-libp2p-v0.53
    # ... other configuration ...
    server: remote-1  # Use remote server for this implementation
```

#### 5. Server Requirements (Computer 2)

On the remote server, ensure:

- **Docker installed and running:**
  ```bash
  curl -fsSL https://get.docker.com | sh
  sudo usermod -aG docker $USER
  # Log out and back in
  ```

- **Port 4001 accessible** (default perf protocol port):
  ```bash
  sudo ufw allow 4001/tcp  # If firewall enabled
  ```

- **User in docker group** (run Docker without sudo):
  ```bash
  # Verify
  docker ps
  ```

See **[QUICKSTART.md](QUICKSTART.md)** for detailed troubleshooting and setup instructions.

---

## Running via GitHub Action (AWS-Based)

1. Create a pull request with your changes on https://github.com/libp2p/test-plans/.
2. Trigger GitHub Action for branch on https://github.com/libp2p/test-plans/actions/workflows/perf.yml (see _Run workflow_ button).
3. Wait for action run to finish and to push a commit to your branch.
4. Visualize results on https://observablehq.com/@libp2p-workspace/performance-dashboard.

## Running manually

### Prerequisites

- Terraform 1.5.4 or later
- Node.js 18 or later
- [an AWS IAM user](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_users.html)


### Provision infrastructure

1. Save your public SSH key as the file `./terraform/modules/short_lived/files/perf.pub`; or generate a new key pair with `make ssh-keygen` and add it to your SSH agent with `make ssh-add`.
2. `cd terraform/configs/local`
3. `terraform init`
4. `terraform apply`
5. `CLIENT_IP=$(terraform output -raw client_ip)`
6. `SERVER_IP=$(terraform output -raw server_ip)`

**Notes**
- While running terraform you may encounter the following error:
  ```bash
    Error: collecting instance settings: reading EC2 Launch Template versions: couldn't find resource
    │
    │   with module.short_lived_server[0].aws_instance.perf,
    │   on ../../modules/short_lived/main.tf line 15, in resource "aws_instance" "perf":
    │   15: resource "aws_instance" "perf" {
  ```
- This implies that you haven't deployed the long-lived infrastructure on your AWS account. To do so along with each short-lived deployment, you can set *TF_VAR* [`long_lived_enabled`](./terraform/configs/local/terraform.tf#L42) env variable to default to `true`. Terraform should then spin up the long-lived resources that are required for the short-lived resources to be created.

- It's best to destroy the infrastructure after you're done with your testing, you can do that by running `terraform destroy`.

### Build and run libp2p implementations

Given you have provisioned your infrastructure, you can now build and run the libp2p implementations on the AWS instances.

1. `cd runner`
2. `npm ci`
3. `npm run start -- --client-public-ip $CLIENT_IP --server-public-ip $SERVER_IP`
   * Note: The default number of iterations that perf will run is 10; desired iterations can be set with the  `--iterations <value>` option.

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
            - `--upload-bytes` number of bytes to upload per stream in 64KiB chunks.
            - `--download-bytes` number of bytes to download per stream in 64KiB chunks.
          - Output
            - Logging MUST go to `stderr`.
            - Measurement output is printed to `stdout` as JSON.
            - The output schema is:
               ``` typescript
               interface Data {
                 type: "intermediary" | "final";
                 timeSeconds: number;
                 uploadBytes: number;
                 downloadBytes: number;
               }
               ```
            - Every second the client must print the current progress to stdout. See example below. Note the `type: "intermediary"`.
               ``` json
               {
                 "type": "intermediary",
                 "timeSeconds": 1.004957645,
                 "uploadBytes": 73039872,
                 "downloadBytes": 0
               },
               ```
            - Before terminating the client must print a final summary. See example below. Note the `type: "final"`. Also note that the measurement includes the time to (1) establish the connection, (2) upload the bytes and (3) download the bytes.
               ``` json
               {
                 "type": "final",
                 "timeSeconds": 60.127230659,
                 "uploadBytes": 4382392320,
                 "downloadBytes": 0
               }
               ```
2. For a new implementation, in [`impl/Makefile` include your implementation in the `all` target.](./impl/Makefile#L7)
3. For a new version, reference version in [`runner/src/versions.ts`](./runner/src/versions.ts#L7-L43).

## Latest Test Results

<!-- TEST_RESULTS_START -->
# Performance Test Results

**Test Pass:** perf-024634-22-12-2025
**Started:** 2025-12-22T02:46:34Z
**Completed:** 2025-12-22T03:07:38Z
**Duration:** 1264s
**Platform:** x86_64 (Linux)

## Summary

- **Total Tests:** 23 (3 baseline + 20 main)
- **Passed:** 11 (47.8%)
- **Failed:** 12

### Baseline Results
- Total: 3
- Passed: 2
- Failed: 1

### Main Test Results
- Total: 20
- Passed: 9
- Failed: 11

## Box Plot Statistics

### Upload Throughput (Gbps)

| Test | Min | Q1 | Median | Q3 | Max | Outliers |
|------|-----|-------|--------|-------|-----|----------|
| rust-v0.56 x rust-v0.56 (tcp, noise, yamux) | 3.17 | 3.33 | 3.63 | 3.67 | 3.72 | 1 |
| rust-v0.56 x rust-v0.56 (tcp, noise, mplex) | 3.04 | 3.23 | 3.55 | 3.56 | 3.68 | 0 |
| rust-v0.56 x rust-v0.56 (tcp, tls, yamux) | 3.21 | 3.32 | 3.51 | 3.56 | 3.61 | 1 |
| rust-v0.56 x rust-v0.56 (tcp, tls, mplex) | 3.08 | 3.24 | 3.36 | 3.61 | 3.71 | 1 |
| rust-v0.56 x rust-v0.56 (quic-v1) | 0.88 | 0.98 | 1.12 | 1.57 | 2.16 | 0 |
| rust-v0.56 x dotnet-v1.0 (tcp, noise, yamux) | 0.91 | 0.91 | 0.91 | 0.91 | 0.91 | 0 |
| rust-v0.56 x dotnet-v1.0 (tcp, noise, mplex) | 0.86 | 0.90 | 0.94 | 0.97 | 1.00 | 0 |
| rust-v0.56 x dotnet-v1.0 (tcp, tls, yamux) | 0.89 | 0.91 | 0.94 | 0.96 | 0.99 | 0 |
| rust-v0.56 x dotnet-v1.0 (tcp, tls, mplex) | 0.89 | 0.90 | 0.91 | 0.92 | 0.93 | 0 |
| rust-v0.56 x dotnet-v1.0 (quic-v1) | null | null | null | null | null | 0 |
| dotnet-v1.0 x rust-v0.56 (tcp, noise, yamux) | null | null | null | null | null | 0 |
| dotnet-v1.0 x rust-v0.56 (tcp, noise, mplex) | null | null | null | null | null | 0 |
| dotnet-v1.0 x rust-v0.56 (tcp, tls, yamux) | null | null | null | null | null | 0 |
| dotnet-v1.0 x rust-v0.56 (tcp, tls, mplex) | null | null | null | null | null | 0 |
| dotnet-v1.0 x rust-v0.56 (quic-v1) | null | null | null | null | null | 0 |
| dotnet-v1.0 x dotnet-v1.0 (tcp, noise, yamux) | null | null | null | null | null | 0 |
| dotnet-v1.0 x dotnet-v1.0 (tcp, noise, mplex) | null | null | null | null | null | 0 |
| dotnet-v1.0 x dotnet-v1.0 (tcp, tls, yamux) | null | null | null | null | null | 0 |
| dotnet-v1.0 x dotnet-v1.0 (tcp, tls, mplex) | null | null | null | null | null | 0 |
| dotnet-v1.0 x dotnet-v1.0 (quic-v1) | null | null | null | null | null | 0 |

### Download Throughput (Gbps)

| Test | Min | Q1 | Median | Q3 | Max | Outliers |
|------|-----|-------|--------|-------|-----|----------|
| rust-v0.56 x rust-v0.56 (tcp, noise, yamux) | 3.51 | 3.59 | 3.60 | 3.65 | 3.69 | 0 |
| rust-v0.56 x rust-v0.56 (tcp, noise, mplex) | 3.51 | 3.55 | 3.61 | 3.63 | 3.64 | 1 |
| rust-v0.56 x rust-v0.56 (tcp, tls, yamux) | 3.50 | 3.51 | 3.53 | 3.57 | 3.58 | 1 |
| rust-v0.56 x rust-v0.56 (tcp, tls, mplex) | 3.54 | 3.55 | 3.57 | 3.58 | 3.62 | 3 |
| rust-v0.56 x rust-v0.56 (quic-v1) | 1.95 | 1.95 | 1.99 | 2.04 | 2.12 | 2 |
| rust-v0.56 x dotnet-v1.0 (tcp, noise, yamux) | 189.08 | 189.43 | 193.64 | 194.99 | 198.74 | 2 |
| rust-v0.56 x dotnet-v1.0 (tcp, noise, mplex) | 189.94 | 193.29 | 195.29 | 196.23 | 197.56 | 1 |
| rust-v0.56 x dotnet-v1.0 (tcp, tls, yamux) | 190.18 | 190.87 | 194.48 | 196.46 | 199.60 | 2 |
| rust-v0.56 x dotnet-v1.0 (tcp, tls, mplex) | 192.67 | 193.36 | 193.91 | 195.19 | 196.24 | 1 |
| rust-v0.56 x dotnet-v1.0 (quic-v1) | null | null | null | null | null | 0 |
| dotnet-v1.0 x rust-v0.56 (tcp, noise, yamux) | null | null | null | null | null | 0 |
| dotnet-v1.0 x rust-v0.56 (tcp, noise, mplex) | null | null | null | null | null | 0 |
| dotnet-v1.0 x rust-v0.56 (tcp, tls, yamux) | null | null | null | null | null | 0 |
| dotnet-v1.0 x rust-v0.56 (tcp, tls, mplex) | null | null | null | null | null | 0 |
| dotnet-v1.0 x rust-v0.56 (quic-v1) | null | null | null | null | null | 0 |
| dotnet-v1.0 x dotnet-v1.0 (tcp, noise, yamux) | null | null | null | null | null | 0 |
| dotnet-v1.0 x dotnet-v1.0 (tcp, noise, mplex) | null | null | null | null | null | 0 |
| dotnet-v1.0 x dotnet-v1.0 (tcp, tls, yamux) | null | null | null | null | null | 0 |
| dotnet-v1.0 x dotnet-v1.0 (tcp, tls, mplex) | null | null | null | null | null | 0 |
| dotnet-v1.0 x dotnet-v1.0 (quic-v1) | null | null | null | null | null | 0 |

### Latency (seconds)

| Test | Min | Q1 | Median | Q3 | Max | Outliers |
|------|-----|-------|--------|-------|-----|----------|
| rust-v0.56 x rust-v0.56 (tcp, noise, yamux) | 0.339 | 0.355 | 0.362 | 0.373 | 0.393 | 5 |
| rust-v0.56 x rust-v0.56 (tcp, noise, mplex) | 0.322 | 0.355 | 0.368 | 0.381 | 0.401 | 3 |
| rust-v0.56 x rust-v0.56 (tcp, tls, yamux) | 0.340 | 0.364 | 0.373 | 0.382 | 0.405 | 7 |
| rust-v0.56 x rust-v0.56 (tcp, tls, mplex) | 0.334 | 0.359 | 0.368 | 0.376 | 0.400 | 4 |
| rust-v0.56 x rust-v0.56 (quic-v1) | 0.347 | 0.368 | 0.376 | 0.385 | 0.410 | 2 |
| rust-v0.56 x dotnet-v1.0 (tcp, noise, yamux) | 87.727 | 87.926 | 87.961 | 88.074 | 88.250 | 19 |
| rust-v0.56 x dotnet-v1.0 (tcp, noise, mplex) | 87.809 | 87.906 | 87.958 | 87.997 | 88.130 | 19 |
| rust-v0.56 x dotnet-v1.0 (tcp, tls, yamux) | 87.782 | 87.912 | 87.959 | 88.006 | 88.119 | 15 |
| rust-v0.56 x dotnet-v1.0 (tcp, tls, mplex) | 87.826 | 87.903 | 87.951 | 87.997 | 88.123 | 15 |
| rust-v0.56 x dotnet-v1.0 (quic-v1) | null | null | null | null | null | 0 |
| dotnet-v1.0 x rust-v0.56 (tcp, noise, yamux) | null | null | null | null | null | 0 |
| dotnet-v1.0 x rust-v0.56 (tcp, noise, mplex) | null | null | null | null | null | 0 |
| dotnet-v1.0 x rust-v0.56 (tcp, tls, yamux) | null | null | null | null | null | 0 |
| dotnet-v1.0 x rust-v0.56 (tcp, tls, mplex) | null | null | null | null | null | 0 |
| dotnet-v1.0 x rust-v0.56 (quic-v1) | null | null | null | null | null | 0 |
| dotnet-v1.0 x dotnet-v1.0 (tcp, noise, yamux) | null | null | null | null | null | 0 |
| dotnet-v1.0 x dotnet-v1.0 (tcp, noise, mplex) | null | null | null | null | null | 0 |
| dotnet-v1.0 x dotnet-v1.0 (tcp, tls, yamux) | null | null | null | null | null | 0 |
| dotnet-v1.0 x dotnet-v1.0 (tcp, tls, mplex) | null | null | null | null | null | 0 |
| dotnet-v1.0 x dotnet-v1.0 (quic-v1) | null | null | null | null | null | 0 |

## Test Results

### https x https (https)
- Status: pass

### quic-go x quic-go (quic)
- Status: fail

### iperf x iperf (tcp)
- Status: pass

### rust-v0.56 x rust-v0.56 (tcp, noise, yamux)
- Status: pass

### rust-v0.56 x rust-v0.56 (tcp, noise, mplex)
- Status: pass

### rust-v0.56 x rust-v0.56 (tcp, tls, yamux)
- Status: pass

### rust-v0.56 x rust-v0.56 (tcp, tls, mplex)
- Status: pass

### rust-v0.56 x rust-v0.56 (quic-v1)
- Status: pass

### rust-v0.56 x dotnet-v1.0 (tcp, noise, yamux)
- Status: pass

### rust-v0.56 x dotnet-v1.0 (tcp, noise, mplex)
- Status: pass

### rust-v0.56 x dotnet-v1.0 (tcp, tls, yamux)
- Status: pass

### rust-v0.56 x dotnet-v1.0 (tcp, tls, mplex)
- Status: pass

### rust-v0.56 x dotnet-v1.0 (quic-v1)
- Status: fail

### dotnet-v1.0 x rust-v0.56 (tcp, noise, yamux)
- Status: fail

### dotnet-v1.0 x rust-v0.56 (tcp, noise, mplex)
- Status: fail

### dotnet-v1.0 x rust-v0.56 (tcp, tls, yamux)
- Status: fail

### dotnet-v1.0 x rust-v0.56 (tcp, tls, mplex)
- Status: fail

### dotnet-v1.0 x rust-v0.56 (quic-v1)
- Status: fail

### dotnet-v1.0 x dotnet-v1.0 (tcp, noise, yamux)
- Status: fail

### dotnet-v1.0 x dotnet-v1.0 (tcp, noise, mplex)
- Status: fail

### dotnet-v1.0 x dotnet-v1.0 (tcp, tls, yamux)
- Status: fail

### dotnet-v1.0 x dotnet-v1.0 (tcp, tls, mplex)
- Status: fail

### dotnet-v1.0 x dotnet-v1.0 (quic-v1)
- Status: fail

<!-- TEST_RESULTS_END -->
