# Performance Tests

Pure-bash implementation of performance tests for libp2p implementations using the libp2p perf protocol.

## Overview

The perf test suite measures performance characteristics of libp2p implementations by running all combinations of:
- **Implementations**: rust-libp2p (v0.56), go-libp2p (v0.45), js-libp2p (v3.x), dotnet-libp2p (v1.0)
- **Transports**: tcp, quic-v1, webtransport, webrtc-direct, ws
- **Secure Channels**: noise, tls
- **Muxers**: yamux, mplex

Additionally, baseline tests measure raw protocol performance for comparison:
- **iperf**: TCP baseline (raw TCP throughput)
- **HTTPS**: Go stdlib HTTPS baseline
- **QUIC-Go**: QUIC baseline using quic-go library

## What It Measures

Each test runs a **dialer** (client) against a **listener** (server) using Docker containers and measures:

- **Upload Throughput**: How fast the dialer can send data to the listener (bytes/second)
- **Download Throughput**: How fast the dialer can receive data from the listener (bytes/second)
- **Latency**: Round-trip time for ping messages (milliseconds)
  - Statistical distribution: p50, p75, p90, p99, p999

Tests run multiple iterations (default: 10) to collect reliable statistical data. The dialer and listener coordinate via Redis for test synchronization.

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

# Number of iterations for upload/download tests (default: 10)
./run.sh --iterations 10

# Duration per iteration for throughput tests in seconds (default: 20)
./run.sh --duration 20

# Number of iterations for latency tests (default: 100)
./run.sh --latency-iterations 100

# Cache directory for test artifacts (default: /srv/cache)
./run.sh --cache-dir /srv/cache
```

**Note**: The `--iterations` flag controls both upload and download iterations. The framework measures throughput by transferring data over a time period and measuring bytes/second.

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
- `~all`: All implementations and baselines (equivalent to `~baselines|~images`)
- `~images`: All libp2p implementations (dotnet-v1.0, go-v0.45, js-v3.x, rust-v0.56)
- `~baselines`: All baseline tests (https, quic-go, iperf)
- `~rust`: rust-libp2p v0.56
- `~go`: go-libp2p v0.45
- `~js`: js-libp2p v3.x
- `~dotnet`: dotnet-libp2p v1.0
- `~failing`: Known failing implementations (go-v0.45, js-v3.x)
- `~none`: Nothing (equivalent to `!~all`)

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

## How Tests Work

The performance test framework executes tests through the following workflow:

### Test Execution Flow

1. **Initialization** (`perf/run.sh`)
   - Load configuration from `inputs.yaml` (if re-running from snapshot)
   - Parse command-line arguments (override inputs.yaml)
   - Initialize common variables and cache directories
   - Set perf-specific defaults (ITERATIONS=10, UPLOAD_BYTES=1GB, etc.)

2. **Test Matrix Generation** (`perf/lib/generate-tests.sh`)
   - Load test aliases from `images.yaml`
   - Expand filter strings (e.g., `~rust` → `rust-v0.56`)
   - Generate all test combinations: dialer × listener × transport × secure × muxer
   - Apply filtering (TEST_IGNORE, BASELINE_IGNORE, TRANSPORT_IGNORE, etc.)
   - Cache the test matrix for reuse (content-addressed by filters + images.yaml hash)

3. **Docker Image Building**
   - Build required Docker images from `images.yaml` definitions
   - Support both local builds (from `images/` directory) and GitHub snapshots
   - Skip already-built images unless `--force-image-rebuild` specified

4. **Test Execution** (`perf/lib/run-single-test.sh`)
   - Start global services (Redis for test coordination)
   - Run baseline tests sequentially (1 worker for accurate performance measurements)
   - Run main tests sequentially
   - For each test:
     - Generate docker-compose file with listener and dialer containers
     - Assign static networking (listener at predictable address)
     - Listener starts and registers its multiaddr in Redis
     - Dialer connects to listener via multiaddr from Redis
     - Dialer runs perf protocol tests and outputs results
     - Extract YAML results from dialer logs
   - Stop global services

5. **Results Collection**
   - Combine all individual test results into `results.yaml`
   - Generate results dashboard (`results.md` and `results.html`)
   - Generate box plots (if gnuplot available) showing throughput/latency distributions
   - Create test pass snapshot (if `--snapshot` flag set)

### Test Coordination

Tests use **Redis** for dialer/listener coordination:
- **Listener**: Starts first, publishes its multiaddr to Redis under a test-specific key
- **Dialer**: Waits for listener multiaddr, connects, runs perf protocol tests, outputs results
- **Test Key**: Each test gets a unique 8-character hash key for Redis namespace isolation

### Test Matrix Caching

The test matrix is cached based on a **TEST_RUN_KEY** computed from:
- Content hash of `images.yaml`
- All filter arguments (TEST_IGNORE, BASELINE_IGNORE, TRANSPORT_IGNORE, SECURE_IGNORE, MUXER_IGNORE)
- Debug flag

Cache location: `$CACHE_DIR/test-run-matrix/perf-<TEST_RUN_KEY>.yaml`

Use `--force-matrix-rebuild` to bypass cache and regenerate the matrix.

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

The `results.yaml` file contains metadata, summary statistics, and individual test results:

```yaml
metadata:
  testPass: perf-a3f7b21c-183045-14-01-2026
  startedAt: 2026-01-14T18:30:45Z
  completedAt: 2026-01-14T20:15:23Z
  duration: 6338s
  platform: x86_64
  os: Linux
  workerCount: 1

summary:
  totalBaselines: 3
  baselinesPassed: 3
  baselinesFailed: 0
  totalTests: 20
  testsPassed: 18
  testsFailed: 2
  totalAll: 23
  passedAll: 21
  failedAll: 2

baselineResults:
  - name: "iperf x iperf (tcp)"
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

testResults:
  - name: "rust-v0.56 x rust-v0.56 (tcp, noise, yamux)"
    status: pass
    upload:
      bytesPerSecond: 987654321
      iterationsCompleted: 10
    download:
      bytesPerSecond: 876543210
      iterationsCompleted: 10
    latency:
      p50: 2.34
      p75: 2.56
      p90: 2.78
      p99: 3.12
      p999: 3.89
```

**Status values**: `pass` (test completed successfully) or `fail` (test failed or timed out)

### Box Plots

If gnuplot is installed, box plots are generated showing distribution of results:
- Upload throughput across all tests
- Download throughput across all tests
- Latency across all tests

## Architecture and Scripts

### Directory Structure

```
perf/
├── run.sh                      # Main test runner (841 lines)
├── images.yaml                 # Implementation definitions and test aliases
├── README.md                   # This file
└── lib/
    ├── generate-tests.sh       # Test matrix generation with filtering
    ├── run-single-test.sh      # Individual test execution via docker-compose
    ├── generate-dashboard.sh   # Results dashboard (MD/HTML) generation
    ├── generate-boxplot.sh     # Box plot visualization generation
    └── setup-remote-server.sh  # Remote server setup (multi-machine testing)
```

### Key Scripts

**`perf/run.sh`** - Main entry point
- Handles bootstrapping, initialization, test execution, and results collection
- Coordinates all test phases from matrix generation to snapshot creation
- Supports both standalone runs and re-runs from snapshots

**`perf/lib/generate-tests.sh`** - Test matrix generator
- Expands filter aliases (e.g., `~rust` → `rust-v0.56`)
- Generates all test combinations: dialer × listener × transport × secure × muxer
- Applies filtering based on TEST_IGNORE, BASELINE_IGNORE, etc.
- Caches generated matrix for performance

**`perf/lib/run-single-test.sh`** - Individual test executor
- Generates docker-compose configuration for each test
- Coordinates listener/dialer via Redis
- Extracts results from dialer container logs
- Handles test timeouts and failures

**`perf/lib/generate-dashboard.sh`** - Results dashboard generator
- Creates markdown and HTML dashboards from results.yaml
- Generates summary statistics and detailed test listings
- Supports injection into README.md for CI/CD

**`perf/lib/generate-boxplot.sh`** - Box plot generator
- Creates box plot visualizations using gnuplot
- Generates separate plots for upload, download, and latency metrics
- Requires gnuplot to be installed

### Common Libraries (../lib/)

The perf test suite uses shared libraries from `lib/` directory:
- **lib-common-init.sh**: Variable initialization and cache directory setup
- **lib-filter-engine.sh**: Alias expansion and filter processing
- **lib-test-caching.sh**: Cache key computation and cache management
- **lib-image-building.sh**: Docker image building from local or GitHub sources
- **lib-global-services.sh**: Redis service management for test coordination
- **lib-output-formatting.sh**: Consistent terminal output formatting
- **lib-snapshot-creation.sh**: Snapshot generation for reproducibility
- **lib-inputs-yaml.sh**: inputs.yaml generation and loading

### Configuration Files

**`images.yaml`** - Defines implementations and test aliases
- **baselines**: Baseline implementations (iperf, https, quic-go)
- **implementations**: libp2p implementations (rust, go, js, dotnet)
- **test-aliases**: Reusable filter patterns for test selection

**`inputs.yaml`** - Generated at test run start (for reproducibility)
- Captures all environment variables
- Captures all command-line arguments
- Enables exact reproduction from snapshots

**`test-matrix.yaml`** - Generated test combinations (cached)
- Lists all selected baseline tests
- Lists all selected main tests
- Lists all ignored tests
- Contains test metadata (iterations, bytes, duration, etc.)

### Documentation

For comprehensive framework documentation, see:
- **[CLAUDE.md](../CLAUDE.md)** - Complete technical documentation
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

**Note**: Remote testing functionality is currently under development and commented out in the codebase (see perf/run.sh:416-443).

Performance tests can be extended to run distributed across multiple machines for more realistic network conditions. The planned architecture will:

1. Configure remote servers in `images.yaml`:
```yaml
servers:
  - id: remote-1
    type: remote
    hostname: "192.168.1.100"
    username: "perfuser"
    sshKey: "~/.ssh/perf_key"
    description: "Remote test server"
```

2. Assign implementations to specific servers:
```yaml
implementations:
  - id: rust-v0.56
    server: remote-1  # This implementation runs on remote-1
    ...
```

3. Use SSH for remote Docker operations

For now, all tests run locally using Docker networking. Multi-machine testing support will be added in a future update.

## Troubleshooting

### Common Issues

**Tests failing with timeout**
- Check container logs: `$TEST_PASS_DIR/logs/<test-name>.log`
- Increase test duration: `--duration 30`
- Enable debug mode: `--debug`

**Cache not working / Matrix regenerates every time**
- Check TEST_RUN_KEY in output (should be consistent for same configuration)
- Verify cache directory: `ls -la /srv/cache/test-run-matrix/`
- Force rebuild to clear corrupted cache: `--force-matrix-rebuild`

**Docker images not building**
- Check Docker daemon is running: `docker ps`
- Check available disk space: `df -h`
- Force rebuild: `--force-image-rebuild`
- Check build logs in terminal output

**Redis connection errors**
- Redis container may not have started properly
- Check: `docker ps | grep perf-redis`
- Check logs: `docker logs perf-redis`
- Ensure port 6379 is not already in use

**Filter not working as expected**
- Check filter expansion in test matrix generation output
- Verify aliases in images.yaml: `yq eval '.test-aliases' images.yaml`
- Use `--list-tests` to preview test selection before running

### Debug Mode

Enable comprehensive logging with `--debug`:

```bash
# Run with debug output
./run.sh --debug --test-ignore "!~rust"

# Or set environment variable
DEBUG=true ./run.sh --test-ignore "!~rust"
```

Debug mode shows:
- Detailed test execution steps
- Filter expansion details
- Docker commands being executed
- Redis coordination messages

### Viewing Test Logs

Individual test logs are stored in `$TEST_PASS_DIR/logs/`:

```bash
# Find your test pass directory
ls -lt /srv/cache/test-run/ | head

# View a specific test log
cat /srv/cache/test-run/perf-<key>-<timestamp>/logs/<test-name>.log

# Search for errors across all logs
grep -r "error" /srv/cache/test-run/perf-<key>-<timestamp>/logs/
```

### Checking Test Results

Results are available in multiple formats:

```bash
# YAML format (machine-readable)
cat $TEST_PASS_DIR/results.yaml

# Markdown dashboard (human-readable)
cat $TEST_PASS_DIR/results.md

# Individual test results
ls $TEST_PASS_DIR/results/
cat $TEST_PASS_DIR/results/<test-name>.yaml
```

## Quick Reference

### Most Common Commands

```bash
# Check what will run
./run.sh --list-tests

# Run only rust tests
./run.sh --test-ignore "!~rust"

# Run only baselines
./run.sh --baseline-ignore "!~baselines" --test-ignore "~images"

# Run with custom iterations and data size
./run.sh --iterations 20 --upload-bytes 5368709120

# Run and create snapshot for reproducibility
./run.sh --snapshot

# Re-run from a previous snapshot
cd /srv/cache/test-run/perf-<key>-<timestamp>/
./run.sh

# Debug a failing test
./run.sh --debug --test-ignore "!rust-v0.56"
```

### Performance Tips

1. **Use filtering** to reduce test time during development
2. **Cache is your friend** - matrix regeneration is expensive
3. **Use `--list-tests`** to verify selection before running
4. **Enable `--debug`** only when troubleshooting (verbose output)
5. **Create snapshots** for reproducible benchmark comparisons
6. **Lower iterations** for faster feedback during development: `--iterations 3`

### Exit Codes

- **0**: All tests passed
- **1**: One or more tests failed
- **Other**: Script error (check terminal output)

## Current Status

<!-- TEST_RESULTS_START -->
<!-- TEST_RESULTS_END -->
