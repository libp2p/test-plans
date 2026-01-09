# Performance Tests

Pure-bash implementation of performance tests for libp2p implementations.

## What This Test Does

Performance tests measure the throughput and latency of libp2p implementations
using the libp2p perf protocol. Tests run all combinations of:
- **Implementations**: rust-libp2p, go-libp2p, js-libp2p, dotnet-libp2p
- **Transports**: tcp, quic-v1, webtransport
- **Secure Channels**: noise, tls
- **Muxers**: yamux, mplex

Additionally, baseline tests measure raw protocol performance for comparison:
- **iperf3**: TCP baseline (raw TCP performance)
- **HTTPS**: Go stdlib HTTPS baseline
- **QUIC-Go**: QUIC baseline using quic-go library

## What It Measures

Each test runs a dialer (client) against a listener (server) and measures:

- **Upload Throughput**: How fast the dialer can send data to the listener (bytes/sec)
- **Download Throughput**: How fast the dialer can receive data from the listener (bytes/sec)
- **Latency**: Round-trip time for ping messages (milliseconds)

Tests run multiple iterations to collect statistical data (median, p50, p75, p90, p99, p999).

## When Tests Run

- **On Pull Requests**: Tests implementations changed in the PR
- **Daily Full Run**: Complete test matrix (all implementations)
- **Manual Trigger**: Via GitHub Actions workflow dispatch

## How to Run Tests

### Prerequisites

Check dependencies:
```bash
./run.sh --check-deps
```

Required: bash 4.0+, docker 20.10+, yq 4.0+, wget, unzip, gnuplot (optional, for box plots)

### Basic Usage

```bash
# Run all tests (all implementations + all baselines)
./run.sh

# Run specific implementation
./run.sh --test-ignore "!rust-v0.56"

# Skip specific tests
./run.sh --test-ignore "rust-v0.56"

# Run with custom parameters
./run.sh --iterations 20 --upload-bytes 5368709120 --download-bytes 5368709120

# Enable debug logging
./run.sh --debug
```

### Performance Test Parameters

Control test behavior with these options:

```bash
# Data transfer amounts (default: 1GB each)
./run.sh --upload-bytes 1073741824 --download-bytes 1073741824

# Number of iterations (default: 10)
./run.sh --iterations 10

# Duration per throughput iteration in seconds (default: 20)
./run.sh --duration 20

# Number of latency test iterations (default: 100)
./run.sh --latency-iterations 100
```

## Test Filtering

### Basic Filtering

Use pipe-separated patterns to filter tests:

```bash
# Test only rust and go implementations
./run.sh --test-ignore "!rust-v0.56|!go-v0.45"

# Ignore specific implementation
./run.sh --test-ignore "js-v3.x"

# Ignore specific transport protocols
./run.sh --transport-ignore "quic-v1|webtransport"

# Ignore specific secure channels
./run.sh --secure-ignore "tls"

# Ignore specific muxers
./run.sh --muxer-ignore "mplex"

# Ignore baseline tests
./run.sh --baseline-ignore "iperf"

# Combine filters
./run.sh --test-ignore "!~rust" --transport-ignore "quic-v1" --secure-ignore "tls"
```

### Alias Expansion

Use `~alias` syntax for convenient test selection:

```bash
# Test ONLY rust implementations (expands to all rust versions)
./run.sh --test-ignore "!~rust"

# Exclude all rust versions
./run.sh --test-ignore "~rust"

# Test ONLY go implementations
./run.sh --test-ignore "!~go"
```

**Available aliases** are defined in `images.yaml` under `test-aliases`:
- `~images`: All libp2p implementations
- `~baselines`: All baseline tests (iperf, https, quic-go)
- `~rust`: All rust-libp2p versions
- `~go`: All go-libp2p versions
- `~js`: All js-libp2p versions
- `~dotnet`: All dotnet-libp2p versions
- `~failing`: Known failing implementations

### Best Practice: Limit to Specific Alias

To test ONLY implementations in an alias (not just tests containing the alias pattern):

```bash
# Test ONLY rust implementations
./run.sh --test-ignore '!~rust'

# Test ONLY go implementations
./run.sh --test-ignore '!~go'

# Test ONLY baselines
./run.sh --baseline-ignore '!~baselines' --test-ignore '~images'
```

## Snapshot Generation

### Creating Snapshots

Generate a self-contained, reproducible test snapshot:

```bash
./run.sh --snapshot
```

This creates a snapshot directory in `/srv/cache/test-run/perf-HHMMSS-DD-MM-YYYY/` containing:
- Complete test configuration (images.yaml, test-matrix.yaml, inputs.yaml)
- All test results (results.yaml, results.md, box plots)
- All source code snapshots
- All Docker images (saved as tar.gz)
- All test scripts
- Re-run script for exact reproduction

### Reproducing from Snapshot

```bash
cd /srv/cache/test-run/perf-HHMMSS-DD-MM-YYYY/
./run.sh

# Force rebuild images from snapshots
./run.sh --force-image-rebuild
```

## Downloading Snapshots

Snapshots are available as GitHub Actions artifacts:

1. Go to [Actions tab](https://github.com/libp2p/test-plans/actions)
2. Select the workflow run
3. Download artifacts from the "Artifacts" section
4. Extract and run `./run.sh`

## Understanding Results

### Results Files

After a test run, results are in `${TEST_PASS_DIR}`:

- **results.yaml**: Complete test results in YAML format
- **results.md**: Markdown dashboard with summary and detailed results
- **results.html**: HTML dashboard (same content as markdown)
- **LATEST_TEST_RESULTS.md**: Detailed results with statistics
- **logs/**: Individual test logs
- **results/**: Individual test result YAML files
- **boxplots/**: Box plot visualizations (PNG, if gnuplot available)

### Result Format

Each test result includes:

```yaml
- name: "rust-v0.56 x rust-v0.56 (tcp, noise, yamux)"
  status: pass
  upload:
    bytesPerSecond: 1234567890
    iterationsCompleted: 10
  download:
    bytesPerSecond: 1234567890
    iterationsCompleted: 10
  latency:
    p50: 1.23
    p75: 1.45
    p90: 1.67
    p99: 2.01
    p999: 2.50
```

### Box Plots

If gnuplot is installed, box plots are generated showing distribution of results:
- Upload throughput across all tests
- Download throughput across all tests
- Latency across all tests

## Script Documentation

For detailed information about the scripts used in this test suite, see:
- **[CLAUDE.md](../CLAUDE.md)** - Comprehensive framework documentation
- **[docs/inputs-schema.md](../docs/inputs-schema.md)** - inputs.yaml specification

## Additional Options

```bash
# List all available implementations and baselines
./run.sh --list-images

# List tests that would be run (without running them)
./run.sh --test-ignore "!rust-v0.56" --list-tests

# Show ignored tests in addition to selected tests
./run.sh --test-ignore "rust-v0.56" --list-tests --show-ignored

# Force rebuild all Docker images
./run.sh --force-image-rebuild

# Force regenerate test matrix (bypass cache)
./run.sh --force-matrix-rebuild

# Skip confirmation prompts
./run.sh --yes

# Check dependencies only
./run.sh --check-deps
```

## Remote Testing

Performance tests can run distributed across multiple machines for more realistic
network conditions. Configure remote servers in `images.yaml`:

```yaml
servers:
  - id: remote-1
    type: remote
    hostname: "192.168.1.100"
    username: "perfuser"
    description: "Remote test server"
```

Then assign implementations to servers:

```yaml
implementations:
  - id: rust-v0.56
    server: remote-1  # This implementation runs on remote-1
    ...
```

See the [transport QUICKSTART.md](../transport/QUICKSTART.md) for SSH setup instructions.

## Current Status

<!-- TEST_RESULTS_START -->
<!-- TEST_RESULTS_END -->
