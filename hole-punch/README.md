# Hole Punch Interoperability Tests

Pure-bash implementation of NAT hole punching interoperability tests for libp2p implementations using the **DCUtR** (Direct Connection Upgrade through Relay) protocol.

## Overview

The hole-punch test suite verifies that libp2p implementations can establish direct peer-to-peer connections through NAT (Network Address Translation) devices. Tests create realistic network topologies and measure DCUtR protocol functionality.

**Current implementations**:
- **rust-libp2p**: v0.56
- **Router**: Linux-based NAT router
- **Relay**: rust-libp2p v0.56 relay server

**Protocols tested**:
- **Transports**: tcp, quic-v1, webrtc-direct, ws (WebSocket)
- **Secure Channels**: noise, tls
- **Muxers**: yamux, mplex

## What This Test Does

Hole punch tests verify the complete DCUtR protocol workflow:

1. **Initial relay connection**: Dialer and listener both connect to a relay server
2. **Multiaddr exchange**: Peers exchange their addresses through the relay
3. **DCUtR protocol**: Peers coordinate hole punching via relay
4. **NAT traversal**: Peers simultaneously open connections through their respective NATs
5. **Connection upgrade**: Direct connection established, traffic switches from relay to direct
6. **Verification**: Test confirms direct connection is working

## What It Measures

Each test runs in an isolated network topology and measures:

- **Connection Success**: Can dialer and listener establish a direct connection through NAT?
- **Protocol Support**: Which transport/secure/muxer combinations support hole punching?
- **Handshake Time**: Time to establish the direct connection (milliseconds)
- **DCUtR Success Rate**: Percentage of successful hole punch attempts

Tests verify NAT traversal by:
1. Both peers start behind separate NAT routers
2. Both connect to relay server on WAN
3. DCUtR protocol coordination via relay
4. Simultaneous connection attempts through NATs
5. Direct connection established and verified

## Network Topology

Each test creates an **isolated Docker network** with realistic NAT simulation:

```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓   ┏━━━━━━━━━━━━━━━━━━━━┓
┃ Dialier LAN                ┃   ┃ Redis Network      ┃
┃ (10.x.x.96/27)             ┃   ┃ (10.5.0.0/21)      ┃
┃         ┌──────────────────┸───┸─┐                  ┃
┃         │ Dialer       (10.5.0.?)┼──────────┐       ┃
┃         │ (10.x.x.99)            │          │       ┃
┃         └──────┼───────────┰───┰─┘          │       ┃
┃         ┌──────┼───────┐   ┃   ┃            │       ┃
┗━━━━━━━━━┥ (10.x.x.98)  ┝━━━┛   ┃            │       ┃
          │ Dialier NAT  │       ┃            │       ┃
┏━━━━━━━━━┥ (10.x.x.66)  ┝━━━┓   ┃            │       ┃
┃ WAN     └──────┼───────┘   ┃   ┃            │       ┃
┃ (10.x.x.64/27) │           ┃   ┃            │       ┃
┃         ┌──────┼───────────┸───┸─┐   ┌──────┼─────┐ ┃
┃         │ Relay        (10.5.0.?)┼───┼ Redis      │ ┃
┃         │ (10.x.x.68)            │   │ (10.5.0.?) │ ┃
┃         └──────┼───────────┰───┰─┘   └──────┼─────┘ ┃
┃         ┌──────┼───────┐   ┃   ┃            │       ┃
┗━━━━━━━━━┥ (10.x.x.67)  ┝━━━┛   ┃            │       ┃
          │ Listener NAT │       ┃            │       ┃
┏━━━━━━━━━┥ (10.x.x.130) ┝━━━┓   ┃            │       ┃
┃         └──────┼───────┘   ┃   ┃            │       ┃
┃         ┌──────┼───────────┸───┸─┐          │       ┃
┃         │ (10.x.x.131)           │          │       ┃
┃         │ Listener     (10.5.0.?)┼──────────┘       ┃
┃         └──────────────────┰───┰─┘                  ┃
┃ Listener LAN               ┃   ┃                    ┃
┃ (10.x.x.128/27)            ┃   ┃                    ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛   ┗━━━━━━━━━━━━━━━━━━━━┛
```

**Network components**:
- **WAN Network**: Contains relay server and NAT routers
- **Dialer LAN**: Private network behind dialer's NAT
- **Listener LAN**: Private network behind listener's NAT
- **Redis**: Coordination service for multiaddr exchange (on WAN)

**Subnet allocation**:
- Subnets are calculated from test key to avoid collisions
- Each test gets unique WAN and LAN subnets
- Example: WAN=10.123.45.64/27, Dialer LAN=10.123.45.96/27, Listener LAN=10.123.45.128/27

**Network latency simulation** (optional, via tc):
- Relay server: Configurable latency
- NAT routers: Configurable latency
- Simulates real-world network conditions

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
# Run all tests
./run.sh

# Run specific implementation
./run.sh --test-ignore "!rust-v0.56"

# Skip specific transport
./run.sh --transport-ignore "quic-v1"

# Run with custom worker count (default: number of CPU cores)
./run.sh --workers 4

# Enable debug logging in test containers
./run.sh --debug
```

### Parallel Execution

Hole-punch tests run in **parallel** (like transport tests):
- Default workers: `$(nproc)` (number of CPU cores)
- Override with `--workers N`
- Tests execute concurrently for faster completion
- Each test creates isolated Docker networks to avoid collisions
- Output is serialized using file locking to prevent interleaved messages

## Test Filtering

Hole-punch tests support a powerful **two-stage filtering model** with both `--*-select` and `--*-ignore` options. Due to the complex network topology, hole-punch tests have additional filtering dimensions for relays and routers.

1. **SELECT** filters narrow from the complete list (empty = select all)
2. **IGNORE** filters remove from the selected set (empty = ignore none)

### Available Filter Dimensions

| Filter Type | SELECT Option | IGNORE Option | Description |
|------------|---------------|---------------|-------------|
| Implementation | `--impl-select` | `--impl-ignore` | Filter peer implementations |
| Relay | `--relay-select` | `--relay-ignore` | Filter relay server implementations |
| Router | `--router-select` | `--router-ignore` | Filter NAT router implementations |
| Transport | `--transport-select` | `--transport-ignore` | Filter transport protocols |
| Secure Channel | `--secure-select` | `--secure-ignore` | Filter secure channel protocols |
| Muxer | `--muxer-select` | `--muxer-ignore` | Filter multiplexer protocols |
| Test Name | `--test-select` | `--test-ignore` | Filter by complete test name/ID |

### Implementation Filtering

```bash
# SELECT: Run only rust implementations
./run.sh --impl-select "rust-v0.56"

# SELECT: Run multiple implementations (pipe-separated)
./run.sh --impl-select "rust-v0.56|go-v0.45"

# SELECT with alias: Run all rust versions
./run.sh --impl-select "~rust"

# IGNORE: Run all except rust
./run.sh --impl-ignore "~rust"

# COMBINED: Run rust and go, but exclude experimental
./run.sh --impl-select "~rust|~go" --impl-ignore "experimental"

# Preview selection before running
./run.sh --impl-select "~rust" --list-tests
```

### Relay Filtering (Hole-Punch Specific)

Hole-punch tests use relay servers for DCUtR coordination:

```bash
# SELECT: Test only with specific relay
./run.sh --relay-select "rust-v0.56"

# SELECT: Test with multiple relays
./run.sh --relay-select "rust-v0.56|go-v0.45"

# IGNORE: Skip specific relay implementation
./run.sh --relay-ignore "go-v0.45"

# IGNORE: Skip all except linux relay
./run.sh --relay-ignore "!linux"
```

### Router Filtering (Hole-Punch Specific)

Hole-punch tests use NAT routers to simulate real-world NAT traversal:

```bash
# SELECT: Test only with linux routers
./run.sh --router-select "linux"

# IGNORE: Skip specific router type
./run.sh --router-ignore "iptables-strict"

# COMBINED: Specific relay and router combination
./run.sh --relay-select "rust-v0.56" --router-select "linux"
```

### Transport Filtering

```bash
# SELECT: Test only TCP transport
./run.sh --transport-select "tcp"

# SELECT: Test TCP and QUIC
./run.sh --transport-select "tcp|quic-v1"

# IGNORE: Skip QUIC and WebRTC
./run.sh --transport-ignore "quic-v1|webrtc-direct"

# IGNORE: Skip all standalone transports
./run.sh --transport-ignore "quic-v1|webrtc-direct|webtransport"
```

### Secure Channel Filtering

```bash
# SELECT: Test only noise
./run.sh --secure-select "noise"

# IGNORE: Skip TLS
./run.sh --secure-ignore "tls"

# Note: Standalone transports (quic-v1, etc.) include their own security
```

### Muxer Filtering

```bash
# SELECT: Test only yamux
./run.sh --muxer-select "yamux"

# IGNORE: Skip mplex
./run.sh --muxer-ignore "mplex"

# Note: Standalone transports include their own muxing
```

### Test Name Filtering

Filter by complete test name (includes router/relay info):

```bash
# SELECT: Tests with rust as dialer
./run.sh --test-select "rust-v0.56 x"

# SELECT: Tests with specific router configuration
./run.sh --test-select "dr: linux"

# SELECT: Tests with specific relay
./run.sh --test-select "rly: rust-v0.56"

# IGNORE: Exclude specific test combinations
./run.sh --test-ignore "go-v0.45 x"

# IGNORE: Exclude tests with specific router
./run.sh --test-ignore "dr: iptables-strict"
```

### Alias Expansion

Use `~alias` syntax for convenient test selection:

```bash
# Expand to all rust versions
./run.sh --impl-select "~rust"

# Expand to all go versions
./run.sh --impl-select "~go"

# Negation: everything NOT matching rust
./run.sh --impl-ignore "~rust"
```

**Available aliases** are defined in `images.yaml` under `test-aliases`:
- `~rust`: rust-libp2p versions
- `~go`: go-libp2p versions
- `~failing`: Known failing implementations (may be empty)

### Combined Filtering Examples

```bash
# Rust implementations, TCP only, linux router
./run.sh --impl-select "~rust" \
         --transport-select "tcp" \
         --router-select "linux"

# Test hole punching with specific network config
./run.sh --impl-select "rust-v0.56" \
         --relay-select "rust-v0.56" \
         --router-select "linux" \
         --transport-select "tcp" \
         --secure-select "noise" \
         --muxer-select "yamux"

# All implementations, skip failing transports
./run.sh --transport-ignore "webrtc-direct" \
         --secure-ignore "tls"

# Quick smoke test: minimal configuration
./run.sh --impl-select "rust-v0.56" \
         --relay-select "linux" \
         --router-select "linux" \
         --transport-select "quic-v1"

# Cross-implementation hole punch tests
./run.sh --impl-select "~rust|~go" \
         --test-select "rust.*x go|go.*x rust"
```

### Verifying Test Selection

Always preview what tests will run before executing:

```bash
# List selected tests
./run.sh --impl-select "~rust" --list-tests

# Show both selected and ignored tests
./run.sh --impl-select "~rust" --list-tests --show-ignored

# Dry run with specific filters
./run.sh --impl-select "~rust" \
         --relay-select "linux" \
         --router-select "linux" \
         --list-tests
```

## How Tests Work

The hole-punch test framework executes tests through the following workflow:

### Test Execution Flow

1. **Initialization** (`hole-punch/run.sh`)
   - Load configuration from `inputs.yaml` (if re-running from snapshot)
   - Parse command-line arguments (override inputs.yaml)
   - Initialize common variables and cache directories
   - Set worker count (default: number of CPU cores)

2. **Test Matrix Generation** (`hole-punch/lib/generate-tests.sh`)
   - Load test aliases from `images.yaml`
   - Expand filter strings
   - Generate all test combinations: dialer × listener × relay × dialer_router × listener_router × transport × secure × muxer
   - Apply filtering (TEST_IGNORE, RELAY_IGNORE, ROUTER_IGNORE, TRANSPORT_IGNORE, SECURE_IGNORE, MUXER_IGNORE)
   - Handle standalone transports (quic-v1, webrtc-direct) that don't need secure/muxer
   - Cache the test matrix for reuse (content-addressed by filters + images.yaml hash)

3. **Docker Image Building**
   - Build required Docker images from `images.yaml` definitions
   - Build routers (NAT routers)
   - Build relays (relay servers)
   - Build implementations (peer implementations)
   - Skip already-built images unless `--force-image-rebuild` specified

4. **Test Execution** (`hole-punch/lib/run-single-test.sh`)
   - Start global services (Redis for test coordination)
   - Run tests in parallel using xargs with N workers
   - For each test:
     - Calculate unique subnet IDs from test key
     - Create isolated Docker networks (WAN, dialer LAN, listener LAN)
     - Generate docker-compose file with all 5 containers:
       - Dialer router (NAT)
       - Listener router (NAT)
       - Relay server (on WAN)
       - Dialer (behind NAT on dialer LAN)
       - Listener (behind NAT on listener LAN)
     - Configure routing and NAT rules
     - Start all containers
     - Relay, dialer, and listener coordinate via Redis
     - Dialer and listener connect to relay first
     - DCUtR protocol establishes direct connection through NATs
     - Verify direct connection is working
     - Extract results from logs
   - Stop global services

5. **Results Collection**
   - Combine all individual test results into `results.yaml`
   - Generate results dashboard (`results.md` and `results.html`)
   - Create test pass snapshot (if `--snapshot` flag set)

### Test Coordination

Tests use **Redis** and **multiaddr exchange**:
- **Relay**: Starts first on WAN, registers multiaddr in Redis
- **Dialer & Listener**: Both behind NATs on separate LANs
- **Initial connection**: Both connect to relay via their NAT routers
- **DCUtR protocol**: Coordination happens through relay
- **Hole punch**: Simultaneous connection attempts from both sides
- **Verification**: Direct connection established and tested
- **Test Key**: Each test gets a unique 8-character hash key for Redis namespace isolation

### Isolated Networks

Each test creates completely isolated networks:
- **Unique subnets**: Calculated from test key (e.g., 10.123.45.x/27)
- **No collisions**: Different tests use different subnets
- **Complete isolation**: Tests don't interfere with each other
- **Parallel safe**: Multiple tests can run simultaneously

### Test Matrix Caching

The test matrix is cached based on a **TEST_RUN_KEY** computed from:
- Content hash of `images.yaml`
- All filter arguments (TEST_IGNORE, RELAY_IGNORE, ROUTER_IGNORE, TRANSPORT_IGNORE, SECURE_IGNORE, MUXER_IGNORE)
- Debug flag

Cache location: `$CACHE_DIR/test-run-matrix/hole-punch-<TEST_RUN_KEY>.yaml`

Use `--force-matrix-rebuild` to bypass cache and regenerate the matrix.

## Snapshot Generation

### Creating Snapshots

Generate a self-contained, reproducible test snapshot:

```bash
./run.sh --snapshot
```

This creates a snapshot directory in `/srv/cache/test-run/hole-punch-<key>-HHMMSS-DD-MM-YYYY/` containing:
- Complete test configuration (images.yaml, test-matrix.yaml, inputs.yaml)
- All test results (results.yaml, results.md, results.html)
- All source code snapshots
- All Docker images (saved as tar.gz)
- All test scripts and network configurations
- Re-run script for exact reproduction

### Reproducing from Snapshot

```bash
cd /srv/cache/test-run/hole-punch-<key>-HHMMSS-DD-MM-YYYY/
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
  testPass: hole-punch-c5d3a9f2-050051-16-12-2025
  startedAt: 2025-12-16T05:00:51Z
  completedAt: 2025-12-16T05:01:08Z
  duration: 17s
  platform: x86_64
  os: Linux
  workerCount: 8

summary:
  total: 5
  passed: 5
  failed: 0

tests:
  - name: "rust-v0.56 x rust-v0.56 (tcp, noise, yamux) [dr: linux, rly: rust-v0.56, lr: linux]"
    status: pass
    handshakeTime: 1234.56
    dialerRouter: linux
    listenerRouter: linux
    relay: rust-v0.56

  - name: "rust-v0.56 x rust-v0.56 (quic-v1) [dr: linux, rly: rust-v0.56, lr: linux]"
    status: fail
    error: "DCUtR protocol timeout"
    dialerRouter: linux
    listenerRouter: linux
    relay: rust-v0.56
```

**Status values**:
- `pass`: Direct connection established successfully through NAT
- `fail`: Hole punch failed, timeout, or protocol error

**Timing values** (in milliseconds):
- `handshakeTime`: Time to establish direct connection through NAT

**Test name format**: Includes all network components:
- Format: `dialer x listener (transport, secure, muxer) [dr: router, rly: relay, lr: router]`
- Example: `rust-v0.56 x rust-v0.56 (tcp, noise, yamux) [dr: linux, rly: rust-v0.56, lr: linux]`

## Architecture and Scripts

### Directory Structure

```
hole-punch/
├── run.sh                      # Main test runner (706 lines)
├── images.yaml                 # Implementation definitions (peers, relays, routers)
├── README.md                   # This file
└── lib/
    ├── generate-tests.sh       # Test matrix generation with filtering
    ├── run-single-test.sh      # Individual test execution via docker-compose
    └── generate-dashboard.sh   # Results dashboard (MD/HTML) generation
```

### Key Scripts

**`hole-punch/run.sh`** - Main entry point
- Handles bootstrapping, initialization, test execution, and results collection
- Coordinates all test phases from matrix generation to snapshot creation
- Supports both standalone runs and re-runs from snapshots
- Manages parallel test execution via xargs

**`hole-punch/lib/generate-tests.sh`** - Test matrix generator
- Expands filter aliases
- Generates all test combinations: dialer × listener × relay × routers × transport × secure × muxer
- Handles standalone transports (quic-v1, webrtc-direct)
- Applies filtering based on all filter dimensions
- Caches generated matrix for performance

**`hole-punch/lib/run-single-test.sh`** - Individual test executor
- Calculates unique subnet IDs from test key
- Creates isolated Docker networks (WAN + 2 LANs)
- Generates docker-compose configuration with 5 containers
- Configures NAT routers and routing
- Coordinates test execution via Redis
- Extracts results from container logs
- Handles test timeouts and failures

**`hole-punch/lib/generate-dashboard.sh`** - Results dashboard generator
- Creates markdown and HTML dashboards from results.yaml
- Generates summary statistics and detailed test listings
- Supports injection into README.md for CI/CD

### Common Libraries (../lib/)

The hole-punch test suite uses shared libraries from `lib/` directory:
- **lib-common-init.sh**: Variable initialization and cache directory setup
- **lib-filter-engine.sh**: Alias expansion and filter processing
- **lib-test-caching.sh**: Cache key computation and cache management
- **lib-image-building.sh**: Docker image building from local sources
- **lib-global-services.sh**: Redis service management for test coordination
- **lib-output-formatting.sh**: Consistent terminal output formatting
- **lib-snapshot-creation.sh**: Snapshot generation for reproducibility
- **lib-inputs-yaml.sh**: inputs.yaml generation and loading

### Configuration Files

**`images.yaml`** - Defines implementations, relays, and routers
- **routers**: NAT router implementations (e.g., linux)
- **relays**: Relay server implementations (e.g., rust-v0.56)
- **implementations**: Peer implementations (e.g., rust-v0.56)
- **test-aliases**: Reusable filter patterns for test selection

**`inputs.yaml`** - Generated at test run start (for reproducibility)
- Captures all environment variables
- Captures all command-line arguments
- Enables exact reproduction from snapshots

**`test-matrix.yaml`** - Generated test combinations (cached)
- Lists all selected tests with full topology details
- Lists all ignored tests
- Contains test metadata (filters, debug flag, etc.)

### Documentation

For comprehensive framework documentation, see:
- **[CLAUDE.md](../CLAUDE.md)** - Complete technical documentation
- **[docs/inputs-schema.md](../docs/inputs-schema.md)** - inputs.yaml specification

## Additional Options

```bash
# List all available implementations, relays, and routers
./run.sh --list-images

# List tests that would be run (without running them)
./run.sh --test-ignore "!rust-v0.56" --list-tests

# Show ignored tests in addition to selected tests
./run.sh --list-tests --show-ignored

# Force rebuild all Docker images
./run.sh --force-image-rebuild

# Force regenerate test matrix (bypass cache)
./run.sh --force-matrix-rebuild

# Check dependencies only
./run.sh --check-deps

# Skip confirmation prompt
./run.sh --yes
```

## Troubleshooting

### Common Issues

**Tests failing with DCUtR timeout**
- Check container logs: `$TEST_PASS_DIR/logs/<test-name>.log`
- Enable debug mode: `--debug` (adds DEBUG=true to container environment)
- Verify NAT routers are functioning correctly
- Check if implementations support DCUtR protocol for the transport

**Network isolation failures**
- Subnets may collide if test keys are similar (very rare)
- Check Docker network conflicts: `docker network ls`
- Force rebuild test matrix: `--force-matrix-rebuild`

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
- Check: `docker ps | grep hole-punch-redis`
- Check logs: `docker logs hole-punch-redis`
- Ensure port 6379 is not already in use

**Router/NAT not working**
- Check router logs for iptables errors
- Verify container has NET_ADMIN capability
- Check routing table in router container: `docker exec <router> ip route`

**Relay not accessible**
- Check relay container is on WAN network
- Verify relay multiaddr is registered in Redis
- Check relay logs for connection errors

### Debug Mode

Enable comprehensive logging with `--debug`:

```bash
# Run with debug output
./run.sh --debug --test-ignore "!rust-v0.56"

# Or set environment variable
DEBUG=true ./run.sh --test-ignore "!rust-v0.56"
```

Debug mode:
- Sets DEBUG=true in container environment
- Implementations may output additional debug information
- Relay and router containers show verbose logging
- Does not change terminal output verbosity (use test logs for details)

### Viewing Test Logs

Individual test logs are stored in `$TEST_PASS_DIR/logs/`:

```bash
# Find your test pass directory
ls -lt /srv/cache/test-run/ | head

# View a specific test log
cat /srv/cache/test-run/hole-punch-<key>-<timestamp>/logs/<test-name>.log

# Search for errors across all logs
grep -r "error\|fail" /srv/cache/test-run/hole-punch-<key>-<timestamp>/logs/

# Find all failed tests
grep -l "status: fail" /srv/cache/test-run/hole-punch-<key>-<timestamp>/results/*.yaml
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

### Inspecting Network Topology

For debugging network issues:

```bash
# View docker-compose file for a specific test
cat $TEST_PASS_DIR/docker-compose/<test-slug>-compose.yaml

# List networks created by tests (may need cleanup)
docker network ls | grep "hole-punch"

# Inspect a specific network
docker network inspect <network-name>

# Check running containers during a test
docker ps | grep "hole-punch"
```

### Performance Optimization

**Reduce test execution time**:
1. Use filtering to test specific combinations
2. Increase worker count: `--workers 16` (if you have CPU/memory available)
3. Use cache (don't use `--force-matrix-rebuild` unless needed)
4. Test specific transports: `--transport-ignore "webrtc-direct|ws"`

**Memory considerations**:
- Each test runs 5 Docker containers (2 routers, 1 relay, 2 peers)
- With high worker counts, many containers run simultaneously
- Monitor: `docker stats` during test execution
- Reduce workers if running out of memory: `--workers 2`

## Quick Reference

### Most Common Commands

```bash
# Check what will run
./run.sh --list-tests

# Run all tests (currently only rust-v0.56)
./run.sh

# Run specific transport only
./run.sh --transport-ignore "!tcp"

# Run with more workers (faster)
./run.sh --workers 8

# Run and create snapshot for reproducibility
./run.sh --snapshot

# Re-run from a previous snapshot
cd /srv/cache/test-run/hole-punch-<key>-<timestamp>/
./run.sh

# Debug a failing test
./run.sh --debug --transport-ignore "!tcp"
```

### Performance Tips

1. **Use filtering** to reduce test count
2. **Increase workers** if you have CPU/memory available: `--workers 8`
3. **Cache is your friend** - matrix regeneration is expensive
4. **Use `--list-tests`** to verify selection before running
5. **Enable `--debug`** only when troubleshooting
6. **Parallel execution** is much faster than sequential
7. **Monitor resources** - each test uses 5 containers

### Exit Codes

- **0**: All tests passed
- **1**: One or more tests failed
- **Other**: Script error (check terminal output)

### Key Differences from Transport Tests

Hole-punch tests have unique characteristics:
- **More complex topology**: 5 containers per test (vs 2 for transport)
- **Isolated networks**: Each test gets unique subnets
- **NAT simulation**: Real iptables NAT rules in router containers
- **DCUtR protocol**: Tests hole punching, not just basic connectivity
- **Additional filters**: `--relay-ignore` and `--router-ignore`
- **Longer execution time**: More containers and complex networking

## Current Status

<!-- TEST_RESULTS_START -->
# Hole Punch Interoperability Test Results

## Test Pass: `hole-punch-030938-16-01-2026`

**Summary:**
- **Total Tests:** 5
- **Passed:** ✅ 5
- **Failed:** ❌ 0
- **Pass Rate:** 100.0%

**Environment:**
- **Platform:** x86_64
- **OS:** Linux
- **Workers:** 8
- **Duration:** 15s

**Timestamps:**
- **Started:** 2026-01-16T03:09:38Z
- **Completed:** 2026-01-16T03:09:53Z

---

## Test Results

| Test | Dialer | Listener | Transport | Status | Duration |
|------|--------|----------|-----------|--------|----------|
| linux x linux (tcp, noise, yamux) [dr: linux, rly: linux, lr: linux] | linux | linux | tcp | ✅ | 10s |
| linux x linux (tcp, noise, mplex) [dr: linux, rly: linux, lr: linux] | linux | linux | tcp | ✅ | 11s |
| linux x linux (tcp, tls, yamux) [dr: linux, rly: linux, lr: linux] | linux | linux | tcp | ✅ | 11s |
| linux x linux (tcp, tls, mplex) [dr: linux, rly: linux, lr: linux] | linux | linux | tcp | ✅ | 12s |
| linux x linux (quic-v1) [dr: linux, rly: linux, lr: linux] | linux | linux | quic-v1 | ✅ | 13s |

---

## Matrix View

| Dialer \ Listener | linux |
|---|---|
| **linux** | - |

---

## Legend

- ✅ Test passed
- ❌ Test failed
- **Transport abbreviations**: t=tcp, q=quic, w=ws, W=wss (first letter)
- Example: ✅t = TCP test passed, ❌q = QUIC test failed

---

*Generated: 2026-01-16T03:09:53Z*
<!-- TEST_RESULTS_END -->

