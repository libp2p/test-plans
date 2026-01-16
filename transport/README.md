# Transport Interoperability Tests

Pure-bash implementation of transport interoperability tests for libp2p implementations.

## Overview

The transport test suite verifies that different libp2p implementations can successfully communicate with each other across various protocol combinations. Tests run all combinations of:

**Implementations tested** (40+ variations):
- **rust-libp2p**: v0.53, v0.54, v0.55, v0.56
- **go-libp2p**: v0.38-v0.45 (8 versions)
- **js-libp2p**: v1.x, v2.x, v3.x (Node.js)
- **python**: py-libp2p v0.4
- **nim**: nim-libp2p v1.14
- **jvm**: jvm-libp2p v1.2
- **c**: c-libp2p v0.0.1
- **dotnet**: dotnet-libp2p v1.0
- **zig**: zig-libp2p v0.0.1
- **eth-p2p-z**: Ethereum P2P (Zig) v0.0.1
- **Browser implementations**: Chromium, Firefox, WebKit (with rust/js)

**Transport protocols**:
- **Standard**: tcp, ws (WebSocket), wss (WebSocket Secure)
- **Standalone** (include security/muxing): quic-v1, webrtc-direct, webtransport, webrtc

**Security and multiplexing**:
- **Secure Channels**: noise, tls
- **Muxers**: yamux, mplex

## What It Measures

Each test runs a **dialer** (client) against a **listener** (server) using Docker containers and measures:

- **Compatibility**: Can dialer and listener establish connections successfully?
- **Protocol Support**: Which transport/secure/muxer combinations work between implementations?
- **Handshake Performance**: Connection establishment time (milliseconds)
- **Ping Latency**: Round-trip time after connection establishment (milliseconds)

Tests verify basic connectivity by:
1. Listener starts and registers its multiaddr in Redis
2. Dialer retrieves multiaddr and attempts connection
3. Dialer sends ping request over the connection
4. Listener responds with pong
5. Results recorded as pass/fail with timing data

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

Required: bash 4.0+, docker 20.10+, yq 4.0+, wget, unzip

### Basic Usage

```bash
# Run all tests (WARNING: generates thousands of test combinations)
./run.sh

# Run specific implementation only
./run.sh --test-ignore "!rust-v0.56"

# Run subset of implementations
./run.sh --test-ignore "!~rust|!~go"

# Skip specific tests
./run.sh --test-ignore "rust-v0.56"

# Run with custom worker count (default: number of CPU cores)
./run.sh --workers 8

# Enable debug logging in test containers
./run.sh --debug
```

### Parallel Execution

Transport tests run in **parallel** (unlike perf tests which run sequentially):
- Default workers: `$(nproc)` (number of CPU cores)
- Override with `--workers N`
- Tests execute concurrently for faster completion
- Output is serialized using file locking to prevent interleaved messages

## Test Filtering

### Basic Filtering

Use pipe-separated patterns to filter tests:

```bash
# Test specific implementations
./run.sh --test-ignore "!rust-v0.56|!go-v0.45"

# Ignore specific transport protocols
./run.sh --transport-ignore "quic-v1|webrtc"

# Ignore specific secure channels
./run.sh --secure-ignore "tls"

# Ignore specific muxers
./run.sh --muxer-ignore "mplex"

# Combine filters
./run.sh --test-ignore "!~rust" --transport-ignore "quic-v1" --secure-ignore "tls"
```

### Alias Expansion

Use `~alias` syntax for convenient test selection:

```bash
# Test ONLY rust implementations (all versions)
./run.sh --test-ignore "!~rust"

# Test ONLY go implementations (all versions)
./run.sh --test-ignore "!~go"

# Test ONLY browser implementations
./run.sh --test-ignore "!~browsers"

# Exclude all rust versions
./run.sh --test-ignore "~rust"

# Test rust and go together
./run.sh --test-ignore "!~rust|!~go"
```

**Available aliases** are defined in `images.yaml` under `test-aliases`:
- `~all`: All implementations (equivalent to all language aliases combined)
- `~browsers`: All browser implementations (chromium/firefox/webkit with rust/js)
- `~rust-browsers`: Rust-based browser implementations
- `~js-browsers`: JavaScript-based browser implementations
- `~rust`: All rust-libp2p versions (v0.53-v0.56)
- `~go`: All go-libp2p versions (v0.38-v0.45)
- `~python`: Python implementation (v0.4)
- `~js`: All js-libp2p versions (v1.x, v2.x, v3.x)
- `~nim`: Nim implementation (v1.14)
- `~jvm`: JVM implementation (v1.2)
- `~c`: C implementation (v0.0.1)
- `~dotnet`: .NET implementation (v1.0)
- `~zig`: Zig implementation (v0.0.1)
- `~eth-p2p`: Ethereum P2P implementation (v0.0.1)
- `~failing`: Known failing implementations (currently empty)

### Best Practice: Test Specific Languages

For focused testing, use alias negation to test only specific implementations:

```bash
# Test ONLY rust implementations
./run.sh --test-ignore '!~rust'

# Test ONLY go implementations
./run.sh --test-ignore '!~go'

# Test ONLY browsers
./run.sh --test-ignore '!~browsers'

# Test rust + go interoperability
./run.sh --test-ignore '!~rust|!~go'
```

## How Tests Work

The transport test framework executes tests through the following workflow:

### Test Execution Flow

1. **Initialization** (`transport/run.sh`)
   - Load configuration from `inputs.yaml` (if re-running from snapshot)
   - Parse command-line arguments (override inputs.yaml)
   - Initialize common variables and cache directories
   - Set worker count (default: number of CPU cores)

2. **Test Matrix Generation** (`transport/lib/generate-tests.sh`)
   - Load test aliases from `images.yaml`
   - Expand filter strings (e.g., `~rust` → `rust-v0.53|rust-v0.54|rust-v0.55|rust-v0.56`)
   - Generate all test combinations: dialer × listener × transport × secure × muxer
   - Apply filtering (TEST_IGNORE, TRANSPORT_IGNORE, SECURE_IGNORE, MUXER_IGNORE)
   - Handle special cases:
     - Standalone transports (quic-v1, webtransport, webrtc-direct) don't need secure/muxer
     - dialOnly implementations can only be dialer, never listener
   - Cache the test matrix for reuse (content-addressed by filters + images.yaml hash)

3. **Docker Image Building**
   - Build required Docker images from `images.yaml` definitions
   - Support multiple source types:
     - GitHub repositories (with optional patches)
     - Local builds (from `impls/` directory)
     - Browser builds (special handling for Chromium, Firefox, WebKit)
   - Skip already-built images unless `--force-image-rebuild` specified

4. **Test Execution** (`transport/lib/run-single-test.sh`)
   - Start global services (Redis for test coordination)
   - Run tests in parallel using xargs with N workers
   - For each test:
     - Generate docker-compose file with listener and dialer containers
     - Use Redis for listener/dialer coordination
     - Listener starts and registers its multiaddr in Redis
     - Dialer waits for listener multiaddr, connects, sends ping
     - Listener responds with pong
     - Results (pass/fail, handshake time, ping latency) written to logs
     - Extract results from dialer logs
   - Stop global services

5. **Results Collection**
   - Combine all individual test results into `results.yaml`
   - Generate results dashboard (`results.md` and `results.html`)
   - Create test pass snapshot (if `--snapshot` flag set)

### Test Coordination

Tests use **Redis** for dialer/listener coordination:
- **Listener**: Starts first, publishes its multiaddr to Redis under a test-specific key
- **Dialer**: Waits for listener multiaddr, connects, runs ping test, outputs results
- **Test Key**: Each test gets a unique 8-character hash key for Redis namespace isolation

### Parallel Execution

Unlike perf tests, transport tests run in **parallel**:
- Multiple test workers (default: number of CPU cores)
- Tests execute concurrently via xargs -P
- Output serialization using flock prevents interleaved messages
- Significantly faster completion for large test matrices

### Test Matrix Caching

The test matrix is cached based on a **TEST_RUN_KEY** computed from:
- Content hash of `images.yaml`
- All filter arguments (TEST_IGNORE, TRANSPORT_IGNORE, SECURE_IGNORE, MUXER_IGNORE)
- Debug flag

Cache location: `$CACHE_DIR/test-run-matrix/transport-<TEST_RUN_KEY>.yaml`

Use `--force-matrix-rebuild` to bypass cache and regenerate the matrix.

### Special Implementation Types

**dialOnly implementations**: Some implementations can only dial connections, not listen:
- Browser implementations (chromium-*, firefox-*, webkit-*)
- These are excluded from listener role in test matrix generation
- Example: `chromium-rust-v0.56` can dial webtransport but cannot listen

**Standalone transports**: Some transports include security and multiplexing:
- quic-v1, webrtc-direct, webtransport
- These don't require separate secureChannel or muxer configuration
- Test matrix generates these without secure/muxer combinations

## Snapshot Generation

### Creating Snapshots

Generate a self-contained, reproducible test snapshot:

```bash
./run.sh --snapshot
```

This creates a snapshot directory in `/srv/cache/test-run/transport-<key>-HHMMSS-DD-MM-YYYY/` containing:
- Complete test configuration (images.yaml, test-matrix.yaml, inputs.yaml)
- All test results (results.yaml, results.md, results.html)
- All source code snapshots (downloaded from GitHub)
- All Docker images (saved as tar.gz)
- All test scripts (lib/ directory)
- Re-run script for exact reproduction

### Reproducing from Snapshot

```bash
cd /srv/cache/test-run/transport-<key>-HHMMSS-DD-MM-YYYY/
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
- **logs/**: Individual test logs
- **results/**: Individual test result YAML files
- **docker-compose/**: Generated docker-compose files for each test

### Result Format

The `results.yaml` file contains metadata, summary statistics, and individual test results:

```yaml
metadata:
  testPass: transport-b4c8d21a-183045-14-01-2026
  startedAt: 2026-01-14T18:30:45Z
  completedAt: 2026-01-14T20:15:23Z
  duration: 6338s
  platform: x86_64
  os: Linux
  workerCount: 8

summary:
  total: 1247
  passed: 1189
  failed: 58

tests:
  - name: "rust-v0.56 x go-v0.45 (tcp, noise, yamux)"
    status: pass
    handshakeTime: 23.45
    pingLatency: 1.23

  - name: "js-v3.x x rust-v0.56 (ws, noise, mplex)"
    status: fail
    error: "connection timeout"
```

**Status values**:
- `pass`: Connection established successfully, ping/pong completed
- `fail`: Connection failed, timeout, or protocol error

**Timing values** (in milliseconds):
- `handshakeTime`: Time to establish connection
- `pingLatency`: Round-trip time for ping/pong

## Architecture and Scripts

### Directory Structure

```
transport/
├── run.sh                      # Main test runner (694 lines)
├── images.yaml                 # Implementation definitions and test aliases
├── README.md                   # This file
└── lib/
    ├── generate-tests.sh       # Test matrix generation with filtering
    ├── run-single-test.sh      # Individual test execution via docker-compose
    └── generate-dashboard.sh   # Results dashboard (MD/HTML) generation
```

### Key Scripts

**`transport/run.sh`** - Main entry point
- Handles bootstrapping, initialization, test execution, and results collection
- Coordinates all test phases from matrix generation to snapshot creation
- Supports both standalone runs and re-runs from snapshots
- Manages parallel test execution via xargs

**`transport/lib/generate-tests.sh`** - Test matrix generator
- Expands filter aliases (e.g., `~rust` → all rust versions)
- Generates all test combinations: dialer × listener × transport × secure × muxer
- Handles special cases (standalone transports, dialOnly implementations)
- Applies filtering based on TEST_IGNORE, TRANSPORT_IGNORE, etc.
- Caches generated matrix for performance

**`transport/lib/run-single-test.sh`** - Individual test executor
- Generates docker-compose configuration for each test
- Coordinates listener/dialer via Redis
- Extracts results from dialer container logs
- Handles test timeouts and failures

**`transport/lib/generate-dashboard.sh`** - Results dashboard generator
- Creates markdown and HTML dashboards from results.yaml
- Generates summary statistics and detailed test listings
- Supports injection into README.md for CI/CD

### Common Libraries (../lib/)

The transport test suite uses shared libraries from `lib/` directory:
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
- **implementations**: All libp2p implementations (40+ variations)
- **test-aliases**: Reusable filter patterns for test selection
- **Special fields**:
  - `dialOnly`: List of transports that can only dial (e.g., browsers with wss)
  - `source.type`: github, local, or browser
  - `patchPath`/`patchFile`: Optional patches to apply before building

**`inputs.yaml`** - Generated at test run start (for reproducibility)
- Captures all environment variables
- Captures all command-line arguments
- Enables exact reproduction from snapshots

**`test-matrix.yaml`** - Generated test combinations (cached)
- Lists all selected tests
- Lists all ignored tests
- Contains test metadata (filters, debug flag, etc.)

### Documentation

For comprehensive framework documentation, see:
- **[CLAUDE.md](../CLAUDE.md)** - Complete technical documentation
- **[docs/inputs-schema.md](../docs/inputs-schema.md)** - inputs.yaml specification

## Additional Options

```bash
# List all available implementations
./run.sh --list-images

# List tests that would be run (without running them)
./run.sh --test-ignore "!rust-v0.56" --list-tests

# Show ignored tests in addition to selected tests
./run.sh --test-ignore "rust-v0.56" --list-tests --show-ignored

# Force rebuild all Docker images
./run.sh --force-image-rebuild

# Force regenerate test matrix (bypass cache)
./run.sh --force-matrix-rebuild

# Skip confirmation prompt
./run.sh --yes

# Check dependencies only
./run.sh --check-deps
```

## Troubleshooting

### Common Issues

**Tests failing with connection timeout**
- Check container logs: `$TEST_PASS_DIR/logs/<test-name>.log`
- Enable debug mode: `--debug` (adds DEBUG=true to container environment)
- Check if implementations support the transport/secure/muxer combination

**Cache not working / Matrix regenerates every time**
- Check TEST_RUN_KEY in output (should be consistent for same configuration)
- Verify cache directory: `ls -la /srv/cache/test-run-matrix/`
- Force rebuild to clear corrupted cache: `--force-matrix-rebuild`

**Docker images not building**
- Check Docker daemon is running: `docker ps`
- Check available disk space: `df -h`
- For GitHub sources, check network connectivity and rate limits
- Force rebuild: `--force-image-rebuild`
- Check build logs in terminal output

**Redis connection errors**
- Redis container may not have started properly
- Check: `docker ps | grep transport-redis`
- Check logs: `docker logs transport-redis`
- Ensure port 6379 is not already in use

**Filter not working as expected**
- Check filter expansion in test matrix generation output
- Verify aliases in images.yaml: `yq eval '.test-aliases' images.yaml`
- Use `--list-tests` to preview test selection before running

**Too many tests generated**
- Use filtering to reduce scope: `--test-ignore "!~rust"`
- Combine filters: `--test-ignore "!~rust" --transport-ignore "webrtc"`
- Test specific pairs: `--test-ignore "!rust-v0.56|!go-v0.45"`

**Browser tests failing**
- Browser implementations require special handling (Playwright, headless mode)
- Check browser-specific logs in test output
- Some browsers may not support certain transports (e.g., webkit doesn't support webtransport)

### Debug Mode

Enable comprehensive logging with `--debug`:

```bash
# Run with debug output
./run.sh --debug --test-ignore "!~rust"

# Or set environment variable
DEBUG=true ./run.sh --test-ignore "!~rust"
```

Debug mode:
- Sets DEBUG=true in container environment
- Implementations may output additional debug information
- Does not change terminal output verbosity (use test logs for details)

### Viewing Test Logs

Individual test logs are stored in `$TEST_PASS_DIR/logs/`:

```bash
# Find your test pass directory
ls -lt /srv/cache/test-run/ | head

# View a specific test log
cat /srv/cache/test-run/transport-<key>-<timestamp>/logs/<test-name>.log

# Search for errors across all logs
grep -r "error" /srv/cache/test-run/transport-<key>-<timestamp>/logs/

# Find all failed tests
grep -l "status: fail" /srv/cache/test-run/transport-<key>-<timestamp>/results/*.yaml
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

### Performance Optimization

**Reduce test execution time**:
1. Use filtering to test specific implementations
2. Increase worker count: `--workers 16` (if you have CPU cores available)
3. Use cache (don't use `--force-matrix-rebuild` unless needed)
4. Test specific transport combinations: `--transport-ignore "webrtc|webtransport"`

**Memory considerations**:
- Each test runs 2 Docker containers (dialer + listener)
- With high worker counts, many containers run simultaneously
- Monitor: `docker stats` during test execution
- Reduce workers if running out of memory: `--workers 2`

## Quick Reference

### Most Common Commands

```bash
# Check what will run
./run.sh --list-tests

# Run only rust tests
./run.sh --test-ignore "!~rust"

# Run rust + go interoperability
./run.sh --test-ignore "!~rust|!~go"

# Run only browser tests
./run.sh --test-ignore "!~browsers"

# Run with more workers (faster)
./run.sh --workers 16 --test-ignore "!~rust"

# Run and create snapshot for reproducibility
./run.sh --snapshot

# Re-run from a previous snapshot
cd /srv/cache/test-run/transport-<key>-<timestamp>/
./run.sh

# Debug a failing test
./run.sh --debug --test-ignore "!rust-v0.56|!go-v0.45" --transport-ignore "!tcp"
```

### Performance Tips

1. **Use filtering** to reduce test count - full matrix has thousands of tests
2. **Increase workers** if you have CPU/memory available: `--workers 16`
3. **Cache is your friend** - matrix regeneration is expensive for large matrices
4. **Use `--list-tests`** to verify selection before running
5. **Enable `--debug`** only when troubleshooting (doesn't affect CLI verbosity)
6. **Test incrementally** - start with small subset, expand as needed
7. **Parallel execution** is much faster than sequential

### Exit Codes

- **0**: All tests passed
- **1**: One or more tests failed
- **Other**: Script error (check terminal output)

## Current Status

<!-- TEST_RESULTS_START -->
<!-- TEST_RESULTS_END -->
