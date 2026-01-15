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

**Test Pass:** perf-084551-15-01-2026
**Started:** 2026-01-15T08:45:51Z
**Completed:** 2026-01-15T09:09:30Z
**Duration:** 1419s
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
| rust-v0.56 x rust-v0.56 (tcp, noise, yamux) | 1.83 | 2.15 | 2.25 | 2.37 | 2.46 | 0 |
| rust-v0.56 x rust-v0.56 (tcp, noise, mplex) | 1.69 | 1.98 | 2.14 | 2.19 | 2.22 | 0 |
| rust-v0.56 x rust-v0.56 (tcp, tls, yamux) | 1.89 | 2.08 | 2.13 | 2.25 | 2.36 | 1 |
| rust-v0.56 x rust-v0.56 (tcp, tls, mplex) | 1.66 | 1.73 | 1.84 | 1.87 | 1.94 | 0 |
| rust-v0.56 x rust-v0.56 (quic-v1) | 1.34 | 1.36 | 1.37 | 1.38 | 1.40 | 0 |
| rust-v0.56 x dotnet-v1.0 (tcp, noise, yamux) | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0 |
| rust-v0.56 x dotnet-v1.0 (tcp, noise, mplex) | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0 |
| rust-v0.56 x dotnet-v1.0 (tcp, tls, yamux) | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0 |
| rust-v0.56 x dotnet-v1.0 (tcp, tls, mplex) | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0 |
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
| rust-v0.56 x rust-v0.56 (tcp, noise, yamux) | 1.98 | 2.08 | 2.17 | 2.22 | 2.24 | 0 |
| rust-v0.56 x rust-v0.56 (tcp, noise, mplex) | 2.10 | 2.16 | 2.22 | 2.27 | 2.42 | 0 |
| rust-v0.56 x rust-v0.56 (tcp, tls, yamux) | 2.10 | 2.17 | 2.23 | 2.36 | 2.57 | 0 |
| rust-v0.56 x rust-v0.56 (tcp, tls, mplex) | 1.63 | 1.94 | 2.24 | 2.42 | 2.52 | 0 |
| rust-v0.56 x rust-v0.56 (quic-v1) | 1.34 | 1.35 | 1.35 | 1.36 | 1.36 | 1 |
| rust-v0.56 x dotnet-v1.0 (tcp, noise, yamux) | 192.70 | 194.05 | 195.02 | 195.54 | 196.79 | 0 |
| rust-v0.56 x dotnet-v1.0 (tcp, noise, mplex) | 194.54 | 194.67 | 195.20 | 195.73 | 196.86 | 1 |
| rust-v0.56 x dotnet-v1.0 (tcp, tls, yamux) | 194.12 | 194.52 | 195.49 | 195.73 | 196.33 | 1 |
| rust-v0.56 x dotnet-v1.0 (tcp, tls, mplex) | 188.59 | 189.99 | 194.73 | 195.64 | 196.93 | 2 |
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
| rust-v0.56 x rust-v0.56 (tcp, noise, yamux) | 0.588 | 0.642 | 0.663 | 0.707 | 0.795 | 2 |
| rust-v0.56 x rust-v0.56 (tcp, noise, mplex) | 0.583 | 0.631 | 0.659 | 0.696 | 0.757 | 3 |
| rust-v0.56 x rust-v0.56 (tcp, tls, yamux) | 0.557 | 0.637 | 0.666 | 0.695 | 0.779 | 1 |
| rust-v0.56 x rust-v0.56 (tcp, tls, mplex) | 0.520 | 0.565 | 0.594 | 0.618 | 0.677 | 4 |
| rust-v0.56 x rust-v0.56 (quic-v1) | 0.566 | 0.624 | 0.653 | 0.684 | 0.765 | 3 |
| rust-v0.56 x dotnet-v1.0 (tcp, noise, yamux) | 87.925 | 87.964 | 87.977 | 87.993 | 88.014 | 9 |
| rust-v0.56 x dotnet-v1.0 (tcp, noise, mplex) | 87.925 | 87.965 | 87.982 | 88.002 | 88.028 | 16 |
| rust-v0.56 x dotnet-v1.0 (tcp, tls, yamux) | 87.929 | 87.963 | 87.980 | 87.991 | 88.021 | 14 |
| rust-v0.56 x dotnet-v1.0 (tcp, tls, mplex) | 87.890 | 87.957 | 87.989 | 88.102 | 88.118 | 23 |
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
