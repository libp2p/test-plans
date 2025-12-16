# libp2p Performance Benchmarking

Pure-bash implementation of performance benchmarking for libp2p implementations using the [libp2p perf protocol](https://github.com/libp2p/specs/blob/master/perf/perf.md).

## What This Test Does

Performance tests measure the throughput and latency of libp2p implementations:
- **Upload Throughput**: Data transfer rate from client to server (Gbps)
- **Download Throughput**: Data transfer rate from server to client (Gbps)
- **Latency**: Round-trip time for requests (seconds)

Tests compare libp2p implementations against baseline reference implementations (iperf, HTTPS, QUIC).

## What It Measures

- **Throughput Performance**: Upload and download speeds
- **Latency**: Connection establishment and request latency
- **Protocol Overhead**: Comparison with baseline implementations
- **Statistical Reliability**: Multiple iterations for confidence intervals

## Baseline vs Main Tests

- **Baseline Tests**: Reference implementations (iperf, https, quic-go) for performance ceiling
- **Main Tests**: libp2p implementations across transport/secure/muxer combinations

## When Tests Run

- **On Pull Requests**: Tests implementations changed in the PR
- **Scheduled Runs**: Nightly or weekly performance tracking
- **Manual Trigger**: Via GitHub Actions workflow dispatch

## How to Run Tests

### Prerequisites

Check dependencies:
```bash
./run_tests.sh --check-deps
```

Required: bash 4.0+, docker 20.10+, yq 4.0+, wget, unzip, python3 (for box plots)

### Basic Usage

```bash
# Run all tests with 3 iterations
./run_tests.sh --iterations 3

# Run specific implementation
./run_tests.sh --test-select "rust-v0.56" --iterations 5

# Run with baseline comparison
./run_tests.sh --test-select "rust-v0.56" --baseline-select "iperf" --iterations 3

# Enable debug logging
./run_tests.sh --debug --iterations 1
```

## Test Filtering

### Main Test Filtering

Control which libp2p implementations to test:

```bash
# Select specific implementations
./run_tests.sh --test-select "rust-v0.56|go-v0.45" --iterations 3

# Ignore specific implementations
./run_tests.sh --test-ignore "experimental" --iterations 3

# Use aliases
./run_tests.sh --test-select "~rust" --iterations 3
```

### Baseline Test Filtering

Control which baseline tests to run:

```bash
# Select specific baseline tests
./run_tests.sh --baseline-select "iperf" --iterations 3

# Select multiple baselines
./run_tests.sh --baseline-select "iperf|https" --iterations 3

# Ignore specific baselines
./run_tests.sh --baseline-ignore "quic-go" --iterations 3

# Use aliases for baselines
./run_tests.sh --baseline-select "~go" --iterations 3
```

### Alias Expansion

Use `~alias` syntax for convenient test selection:

```bash
# Expand to all rust versions
./run_tests.sh --test-select "~rust"

# Exclude all rust versions
./run_tests.sh --test-ignore "~rust"

# Select everything EXCEPT rust
./run_tests.sh --test-select "!~rust"
```

**Available aliases** are defined in `impls.yaml` under `test-aliases`.

### Best Practice: Limit to Specific Alias

To test ONLY implementations in an alias (not just tests containing the alias pattern):

```bash
# Test ONLY rust implementations with go baseline
./run_tests.sh \
    --test-select '~rust' --test-ignore '!~rust' \
    --baseline-select '~go' --baseline-ignore '!~go' \
    --iterations 5

# Test ONLY go implementations with iperf baseline
./run_tests.sh \
    --test-select '~go' --test-ignore '!~go' \
    --baseline-select 'iperf' \
    --iterations 5
```

**How it works**:
1. `--test-select '~rust'` includes all rust implementations
2. `--test-ignore '!~rust'` ignores everything that is NOT rust
3. `--baseline-select '~go'` includes all go baseline implementations
4. `--baseline-ignore '!~go'` ignores everything that is NOT go
5. The intersection gives you exactly the rust tests with go baselines

### Combined Filtering Examples

```bash
# Test rust against go baseline only
./run_tests.sh \
    --test-select "rust-v0.56" \
    --baseline-select "go-v0.45" \
    --iterations 5

# Test all rust versions, no baseline
./run_tests.sh \
    --test-select "~rust" \
    --baseline-ignore ".*" \
    --iterations 3

# Test specific implementation, all baselines
./run_tests.sh \
    --test-select "rust-v0.56" \
    --test-ignore "!rust-v0.56" \
    --iterations 5
```

## Multi-Machine Testing

Perf tests support running server and client on different machines for true network testing.

### Setup Remote Server

See **[QUICKSTART.md](QUICKSTART.md)** for detailed remote server setup instructions.

Quick setup:
1. Generate SSH key: `ssh-keygen -t ed25519 -f ~/.ssh/perf_server`
2. Copy to server: `ssh-copy-id -i ~/.ssh/perf_server.pub user@192.168.1.100`
3. Configure in `impls.yaml`:

```yaml
servers:
  - id: remote-1
    type: remote
    hostname: "192.168.1.100"
    username: "perfuser"

implementations:
  - id: rust-v0.56
    server: remote-1  # Run on remote machine
```

4. Run tests: `./run_tests.sh --test-select "rust-v0.56" --iterations 3`

## Snapshot Generation

### Creating Snapshots

Generate a self-contained, reproducible test snapshot:

```bash
./run_tests.sh --snapshot --iterations 5
```

This creates a snapshot directory in `/srv/cache/test-runs/perf-HHMMSS-DD-MM-YYYY/` containing:
- Complete test configuration (impls.yaml, test-matrix.yaml)
- All test results (results.yaml, results.md, results.html)
- Box plot images (upload_boxplot.png, download_boxplot.png, latency_boxplot.png)
- All source code snapshots
- All Docker images (saved as tar.gz)
- All test scripts
- Re-run script for exact reproduction

### Reproducing from Snapshot

```bash
cd /srv/cache/test-runs/perf-HHMMSS-DD-MM-YYYY/
./re-run.sh

# Force rebuild images from snapshots
./re-run.sh --force-rebuild
```

## Downloading Snapshots

Snapshots are available as GitHub Actions artifacts:

1. Go to [Actions tab](https://github.com/libp2p/test-plans/actions)
2. Select the workflow run
3. Download artifacts from the "Artifacts" section
4. Extract and run `./re-run.sh`

## Script Documentation

For detailed information about the scripts used in this test suite, see:
- **[docs/SCRIPTS_DESIGN.md](../docs/SCRIPTS_DESIGN.md)** - Comprehensive script documentation
- **[QUICKSTART.md](QUICKSTART.md)** - Quick start guide with remote setup
- **[README.md (AWS-based)](README.md#running-manually)** - Legacy AWS-based testing

## Additional Options

```bash
# List all available implementations
./run_tests.sh --list-impls

# List tests that would be run (without running them)
./run_tests.sh --test-select "rust-v0.56" --list-tests

# Set number of iterations (default: 10)
./run_tests.sh --iterations 20

# Force rebuild all Docker images
./run_tests.sh --force-image-rebuild

# Force regenerate test matrix (bypass cache)
./run_tests.sh --force-matrix-rebuild

# Check dependencies only
./run_tests.sh --check-deps
```

## 
## Latest Test Results

<!-- TEST_RESULTS_START -->
# Performance Test Results

**Test Pass:** perf-043902-16-12-2025
**Started:** 2025-12-16T04:39:02Z
**Completed:** 2025-12-16T05:00:27Z
**Duration:** 1285s
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
| rust-v0.56 x rust-v0.56 (tcp, noise, yamux) | 3.50 | 3.51 | 3.55 | 3.59 | 3.66 | 2 |
| rust-v0.56 x rust-v0.56 (tcp, noise, mplex) | 2.94 | 3.13 | 3.52 | 3.59 | 3.70 | 0 |
| rust-v0.56 x rust-v0.56 (tcp, tls, yamux) | 2.94 | 3.35 | 3.59 | 3.64 | 3.69 | 1 |
| rust-v0.56 x rust-v0.56 (tcp, tls, mplex) | 2.99 | 3.01 | 3.32 | 3.48 | 3.65 | 2 |
| rust-v0.56 x rust-v0.56 (quic-v1) | 1.60 | 1.72 | 1.79 | 1.94 | 2.17 | 1 |
| rust-v0.56 x dotnet-v1.0 (tcp, noise, yamux) | 0.94 | 0.94 | 0.94 | 0.94 | 0.94 | 0 |
| rust-v0.56 x dotnet-v1.0 (tcp, noise, mplex) | 0.86 | 0.91 | 0.96 | 1.00 | 1.02 | 0 |
| rust-v0.56 x dotnet-v1.0 (tcp, tls, yamux) | 0.96 | 0.96 | 0.96 | 0.96 | 0.96 | 0 |
| rust-v0.56 x dotnet-v1.0 (tcp, tls, mplex) | 0.87 | 0.89 | 0.91 | 0.95 | 1.00 | 0 |
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
| rust-v0.56 x rust-v0.56 (tcp, noise, yamux) | 3.53 | 3.56 | 3.58 | 3.59 | 3.59 | 2 |
| rust-v0.56 x rust-v0.56 (tcp, noise, mplex) | 3.49 | 3.52 | 3.54 | 3.55 | 3.55 | 3 |
| rust-v0.56 x rust-v0.56 (tcp, tls, yamux) | 3.53 | 3.55 | 3.57 | 3.60 | 3.65 | 2 |
| rust-v0.56 x rust-v0.56 (tcp, tls, mplex) | 3.49 | 3.55 | 3.59 | 3.64 | 3.71 | 0 |
| rust-v0.56 x rust-v0.56 (quic-v1) | 2.23 | 2.26 | 2.27 | 2.29 | 2.31 | 1 |
| rust-v0.56 x dotnet-v1.0 (tcp, noise, yamux) | 190.41 | 191.24 | 194.58 | 195.61 | 197.19 | 2 |
| rust-v0.56 x dotnet-v1.0 (tcp, noise, mplex) | 186.35 | 189.65 | 193.34 | 195.51 | 196.54 | 1 |
| rust-v0.56 x dotnet-v1.0 (tcp, tls, yamux) | 183.87 | 190.39 | 192.78 | 194.80 | 195.67 | 1 |
| rust-v0.56 x dotnet-v1.0 (tcp, tls, mplex) | 191.80 | 192.74 | 194.16 | 195.04 | 195.58 | 2 |
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
| rust-v0.56 x rust-v0.56 (tcp, noise, yamux) | 0.334 | 0.358 | 0.367 | 0.374 | 0.395 | 8 |
| rust-v0.56 x rust-v0.56 (tcp, noise, mplex) | 0.335 | 0.359 | 0.369 | 0.380 | 0.410 | 4 |
| rust-v0.56 x rust-v0.56 (tcp, tls, yamux) | 0.336 | 0.357 | 0.364 | 0.371 | 0.387 | 10 |
| rust-v0.56 x rust-v0.56 (tcp, tls, mplex) | 0.344 | 0.364 | 0.373 | 0.384 | 0.404 | 5 |
| rust-v0.56 x rust-v0.56 (quic-v1) | 0.356 | 0.379 | 0.384 | 0.394 | 0.417 | 1 |
| rust-v0.56 x dotnet-v1.0 (tcp, noise, yamux) | 87.742 | 87.915 | 87.957 | 88.045 | 88.224 | 17 |
| rust-v0.56 x dotnet-v1.0 (tcp, noise, mplex) | 87.680 | 87.884 | 87.954 | 88.028 | 88.237 | 11 |
| rust-v0.56 x dotnet-v1.0 (tcp, tls, yamux) | 87.707 | 87.898 | 87.954 | 88.028 | 88.215 | 13 |
| rust-v0.56 x dotnet-v1.0 (tcp, tls, mplex) | 87.760 | 87.893 | 87.942 | 88.013 | 88.134 | 14 |
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
