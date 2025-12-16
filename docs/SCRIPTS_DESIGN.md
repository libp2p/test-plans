# Scripts Design Documentation

This document provides comprehensive documentation for all scripts used across the test-plans repository, including common scripts shared by all test suites and test-specific scripts for transport, hole-punch, and perf tests.

## Table of Contents

- [Overview](#overview)
- [Common Scripts](#common-scripts)
- [Common Libraries](#common-libraries)
- [Transport-Specific Scripts](#transport-specific-scripts)
- [Hole-Punch-Specific Scripts](#hole-punch-specific-scripts)
- [Perf-Specific Scripts](#perf-specific-scripts)
- [Architecture Patterns](#architecture-patterns)
- [Usage Examples](#usage-examples)

---

## Overview

The test-plans repository uses a unified bash-based script architecture that provides:
- **Pure bash orchestration** (no Node.js/npm/TypeScript dependencies)
- **YAML-based configuration** for all test definitions
- **Content-addressed caching** for optimal performance
- **Modular design** with shared common libraries
- **Test-specific customization** for different test types

### Script Organization

```
test-plans/
├── scripts/                          # Common scripts shared by all test suites
│   ├── build-single-image.sh        # Single Docker image builder
│   ├── check-dependencies.sh        # Dependency verification
│   ├── lib-image-building.sh        # Docker build functions
│   ├── lib-image-naming.sh          # Image naming conventions
│   ├── lib-remote-execution.sh      # SSH remote execution
│   ├── lib-snapshot-images.sh       # Docker image snapshots
│   ├── lib-test-aliases.sh          # Test alias expansion
│   ├── lib-test-caching.sh          # Test matrix caching
│   ├── lib-test-execution.sh        # Test execution helpers
│   ├── lib-test-filtering.sh        # Test filtering logic
│   └── update-readme-results.sh     # Results formatting
├── transport/scripts/                # Transport-specific scripts
├── hole-punch/scripts/               # Hole-punch-specific scripts
└── perf/scripts/                     # Perf-specific scripts
```

### Design Principles

1. **Never modify shared scripts** - Test-specific logic goes in test directories
2. **Use CACHE_DIR variable** - Never hardcode paths like `/srv/cache`
3. **Error handling** - All scripts use `set -euo pipefail`
4. **Content addressing** - All artifacts are content-hashed for deduplication
5. **Parallel execution** - Tests run in parallel with configurable workers

---

## Common Scripts

These scripts are located in the `scripts/` directory and are shared across all test suites.

### build-single-image.sh

**Purpose**: Builds a single Docker image from a YAML configuration file.

**Usage**:
```bash
./scripts/build-single-image.sh /srv/cache/build-yamls/docker-build-<name>.yaml
```

**Features**:
- Reads YAML configuration with build context, Dockerfile path, and source information
- Supports GitHub, local, and browser source types
- Handles source code downloading and caching
- Tags images with content-based naming
- Used by all test suite build orchestrators

**Input YAML Schema**:
```yaml
image_name: transport-interop-rust-v0.56
build_context: /srv/cache/snapshots/abc123/interop-tests
dockerfile: Dockerfile.native
source:
  type: github
  repo: libp2p/rust-libp2p
  commit: abc123...
```

**Exit Codes**:
- `0`: Build succeeded
- `1`: Build failed

### check-dependencies.sh

**Purpose**: Verifies all required system dependencies are installed and meet minimum versions.

**Usage**:
```bash
bash ../scripts/check-dependencies.sh
```

**Checks**:
- bash 4.0+
- docker 20.10+
- yq 4.0+
- wget
- unzip
- Docker Compose (auto-detects `docker compose` vs `docker-compose`)

**Side Effects**:
- Exports `DOCKER_COMPOSE_CMD` to `/tmp/docker-compose-cmd.txt`
- This file is read by test runners to determine the correct Docker Compose command

**Exit Codes**:
- `0`: All dependencies satisfied
- `1`: Missing or outdated dependencies

### update-readme-results.sh

**Purpose**: Updates README.md files with latest test results between comment markers.

**Usage**:
```bash
./scripts/update-readme-results.sh <readme-file> <results-file>
```

**Features**:
- Finds `<!-- TEST_RESULTS_START -->` and `<!-- TEST_RESULTS_END -->` markers
- Replaces content between markers with new results
- Preserves all other README content unchanged
- Used by CI/CD workflows to update documentation

**Example**:
```bash
./scripts/update-readme-results.sh transport/README.md transport/results.md
```

---

## Common Libraries

These bash libraries provide reusable functions for test-specific scripts. All libraries are sourced (not executed) and provide functions that can be called from test scripts.

### lib-test-aliases.sh

**Purpose**: Test alias expansion for simplified test selection.

**Functions**:

#### `load_aliases()`
Loads test aliases from `impls.yaml` into a global `ALIASES` associative array.

```bash
# Example impls.yaml content
test-aliases:
  - alias: "rust"
    value: "rust-v0.56|rust-v0.55|rust-v0.54"
  - alias: "go"
    value: "go-v0.45|go-v0.44"
```

#### `expand_aliases(input)`
Expands alias syntax in test selection strings.

**Supported Syntax**:
- `~alias` - Expands to alias value
- `!~alias` - Expands to all implementations NOT matching alias

**Examples**:
```bash
source lib-test-aliases.sh
load_aliases

# Expand to rust versions
result=$(expand_aliases "~rust")
# Returns: "rust-v0.56|rust-v0.55|rust-v0.54"

# Expand to everything EXCEPT rust
result=$(expand_aliases "!~rust")
# Returns: "go-v0.45|go-v0.44|python-v0.4|..." (all non-rust impls)
```

#### `get_all_impl_ids()`
Returns all implementation IDs as a pipe-separated string.

**Usage**:
```bash
all_impls=$(get_all_impl_ids)
# Returns: "rust-v0.56|go-v0.45|python-v0.4|..."
```

**Best Practice Pattern**:
To select ONLY tests in an alias (not just tests containing the alias):
```bash
--test-select '~rust' --test-ignore '!~rust'
```

This pattern works by:
1. `--test-select '~rust'` includes all rust implementations
2. `--test-ignore '!~rust'` ignores everything that is NOT rust
3. The intersection gives you exactly the rust tests

### lib-test-filtering.sh

**Purpose**: Test filtering logic for test matrix generation.

**Global Variables**:
- `SELECT_PATTERNS`: Array of patterns to include
- `IGNORE_PATTERNS`: Array of patterns to exclude

**Functions**:

#### `impl_matches_select(impl_id)`
Checks if an implementation ID matches any SELECT pattern.

**Parameters**:
- `impl_id`: Implementation ID to check

**Returns**:
- `0` (true): Matches select criteria
- `1` (false): Does not match

#### `matches_select(test_name)`
Checks if a test name matches any SELECT pattern.

**Parameters**:
- `test_name`: Full test name

**Returns**:
- `0` (true): Test should be included
- `1` (false): Test should be excluded

#### `should_ignore(test_name)`
Checks if a test name matches any IGNORE pattern.

**Parameters**:
- `test_name`: Full test name

**Returns**:
- `0` (true): Test should be ignored
- `1` (false): Test should not be ignored

#### `get_common(list1, list2)`
Finds common elements between two space-separated lists.

**Example**:
```bash
common=$(get_common "tcp ws quic" "ws quic webrtc")
# Returns: "ws quic"
```

**Usage Pattern**:
```bash
source lib-test-filtering.sh

# Setup filter patterns
IFS='|' read -ra SELECT_PATTERNS <<< "$TEST_SELECT"
IFS='|' read -ra IGNORE_PATTERNS <<< "$TEST_IGNORE"

# Check if test should be included
if matches_select "$test_name" && ! should_ignore "$test_name"; then
    # Add test to matrix
fi
```

### lib-test-caching.sh

**Purpose**: Test matrix caching to speed up repeated test runs.

**Functions**:

#### `compute_cache_key(test_select, test_ignore, debug)`
Computes a content-based cache key for test configuration.

**Parameters**:
- `test_select`: TEST_SELECT filter string
- `test_ignore`: TEST_IGNORE filter string
- `debug`: Debug mode flag ("true" or "false")

**Returns**: SHA256 hash (64 characters)

**Implementation**:
- Hashes impls.yaml content + parameters
- Uses double-pipe `||` delimiter to prevent collisions
- Example: `echo "$TEST_SELECT||$TEST_IGNORE||$DEBUG" | sha256sum`

**Example**:
```bash
cache_key=$(compute_cache_key "$TEST_SELECT" "$TEST_IGNORE" "false")
# Returns: "6b10a3ee4f7c9d2a..."
```

#### `check_and_load_cache(cache_key, cache_dir, output_dir)`
Checks for cached test matrix and loads it if found.

**Parameters**:
- `cache_key`: Cache key from `compute_cache_key()`
- `cache_dir`: Cache directory path (e.g., `/srv/cache`)
- `output_dir`: Output directory for test-matrix.yaml

**Returns**:
- `0`: Cache hit (matrix loaded to output_dir/test-matrix.yaml)
- `1`: Cache miss (need to generate)

**Performance**:
- Cache hit: ~50-200ms
- Cache miss: ~2-5 seconds (regeneration needed)

#### `save_to_cache(output_dir, cache_key, cache_dir)`
Saves generated test matrix to cache.

**Parameters**:
- `output_dir`: Directory containing test-matrix.yaml
- `cache_key`: Cache key
- `cache_dir`: Cache directory path

**Cache Structure**:
```
/srv/cache/test-matrix/
└── <sha256>.yaml    # Cached test matrix files
```

### lib-image-building.sh

**Purpose**: Docker image building functions for all source types.

**Functions**:
- `download_github_source()` - Downloads and caches GitHub repository snapshots
- `prepare_build_context()` - Prepares build context from various source types
- `build_docker_image()` - Orchestrates Docker build with proper tagging
- `handle_browser_source()` - Special handling for browser-based implementations

**Source Types Supported**:
- **github**: Downloads from GitHub repo at specific commit
- **local**: Uses local filesystem path
- **browser**: Browser-based implementations (Chromium, Firefox, WebKit)

**Caching Strategy**:
```
/srv/cache/snapshots/
└── <commit-sha>.zip    # Content-addressed source snapshots
```

### lib-image-naming.sh

**Purpose**: Standardized Docker image naming conventions.

**Functions**:
- `get_image_name()` - Generates standard image names
- `parse_image_tag()` - Extracts components from image tags

**Naming Pattern**:
```
<test-type>-<implementation-id>
Example: transport-interop-rust-v0.56
Example: hole-punch-linux
Example: perf-rust-v0.56
```

### lib-remote-execution.sh

**Purpose**: SSH-based remote build execution (primarily used by perf tests).

**Functions**:
- `setup_remote_server()` - Initializes remote server environment
- `execute_remote_build()` - Runs Docker build on remote server
- `sync_remote_image()` - Transfers built images back to local machine

**Requirements**:
- SSH key-based authentication
- Remote server with Docker installed
- User in docker group on remote server

**Configuration** (in impls.yaml):
```yaml
servers:
  - id: remote-1
    type: remote
    hostname: "192.168.1.100"
    username: "perfuser"

implementations:
  - id: rust-v0.56
    server: remote-1
```

### lib-snapshot-images.sh

**Purpose**: Docker image snapshot utilities for test reproducibility.

**Functions**:
- `save_docker_image()` - Saves image to tar.gz
- `load_docker_image()` - Loads image from tar.gz
- `snapshot_all_images()` - Creates snapshots of all test images

**Usage in Test Snapshots**:
```
/srv/cache/test-runs/<test-pass>/
├── docker-images/
│   ├── transport-interop-rust-v0.56.tar.gz
│   └── transport-interop-go-v0.45.tar.gz
```

### lib-test-execution.sh

**Purpose**: Common test execution helpers.

**Functions**:
- `setup_test_environment()` - Prepares test directories and networks
- `cleanup_test_resources()` - Cleans up containers and networks
- `parse_test_results()` - Extracts results from test output

---

## Transport-Specific Scripts

Located in `transport/scripts/`, these scripts implement transport interoperability testing.

### build-images.sh

**Purpose**: Build orchestrator for transport test implementations.

**Usage**:
```bash
cd transport
bash scripts/build-images.sh "rust-v0.56" "false"
```

**Parameters**:
1. `TEST_SELECT`: Filter for implementations to build (pipe-separated)
2. `DEBUG`: Debug mode flag ("true" or "false")

**Process**:
1. Reads `impls.yaml` for implementation definitions
2. Applies TEST_SELECT filtering
3. Generates build YAML files in `/srv/cache/build-yamls/`
4. Calls `build-single-image.sh` for each implementation
5. Reports build success/failure

**Build Matrix**:
- Each implementation produces ONE Docker image
- Image name format: `transport-interop-<impl-id>`
- Example: `transport-interop-rust-v0.56`

### generate-tests.sh

**Purpose**: Generates 3D test matrix for transport interoperability.

**Usage**:
```bash
cd transport
bash scripts/generate-tests.sh "$TEST_SELECT" "$TEST_IGNORE" "$DEBUG"
```

**Test Dimensions**:
1. **Dialer** (implementation acting as client)
2. **Listener** (implementation acting as server)
3. **Transport** (tcp, ws, wss)
4. **Secure Channel** (noise, tls)
5. **Muxer** (yamux, mplex)

**Special Cases**:
- **Standalone transports** (quic-v1, webrtc-direct, webtransport): No secure channel or muxer
- These transports provide all functionality in one protocol

**Test Matrix Generation**:
```
FOR each dialer in implementations:
  FOR each listener in implementations:
    FOR each transport in (dialer.transports ∩ listener.transports):
      IF transport is standalone:
        CREATE TEST: dialer x listener (transport)
      ELSE:
        FOR each secureChannel in (dialer.secureChannels ∩ listener.secureChannels):
          FOR each muxer in (dialer.muxers ∩ listener.muxers):
            CREATE TEST: dialer x listener (transport, secureChannel, muxer)
```

**Example Test Names**:
```
rust-v0.53 x go-v0.45 (tcp, noise, yamux)
rust-v0.53 x go-v0.45 (quic-v1)
rust-v0.53 x go-v0.45 (webrtc-direct)
```

**Output**:
- `test-matrix.yaml`: Complete test matrix
- Cached in `/srv/cache/test-matrix/<cache-key>.yaml`

**Performance**:
- Uses associative arrays for O(1) lookups
- Bulk TSV extraction (single yq call vs hundreds)
- Typical generation: ~2-5 seconds for 2000+ tests

### run-single-test.sh

**Purpose**: Executes a single transport interoperability test.

**Usage**:
```bash
bash scripts/run-single-test.sh <test-index>
```

**Parameters**:
- `test-index`: Index into test-matrix.yaml (0-based)

**Test Execution**:
1. Extract test details from test-matrix.yaml
2. Create isolated Docker network
3. Start listener container
4. Start dialer container
5. Wait for test completion
6. Capture results (pass/fail, duration, metrics)
7. Cleanup containers and network

**Container Architecture**:
```
Docker Network (10.0.0.0/24)
├── listener (10.0.0.2) - Listens for connection
└── dialer (10.0.0.3)   - Initiates connection
```

**Exit Codes**:
- `0`: Test passed
- `1`: Test failed

### generate-dashboard.sh

**Purpose**: Creates results.md markdown dashboard from results.yaml.

**Usage**:
```bash
bash scripts/generate-dashboard.sh
```

**Input**: `results.yaml` (structured test results)

**Output**: `results.md` (formatted markdown dashboard)

**Dashboard Sections**:
1. **Summary**: Total tests, pass/fail counts, pass rate
2. **Environment**: Platform, OS, workers, duration
3. **Timestamps**: Test start and completion times
4. **Test Results**: Detailed table of all test results
5. **Matrix View by Transport**: Dialer × Listener compatibility matrices

**Matrix Views**:
- Separate matrix for each transport combination
- Uses symbols for quick scanning (✅ pass, ❌ fail)
- Transport abbreviations in cells (t=tcp, q=quic, etc.)

**Performance Optimization**:
- Single yq call to extract all data
- Associative arrays for O(1) lookups
- 30-80x faster than previous Node.js implementation

### create-snapshot.sh

**Purpose**: Creates a self-contained, reproducible test snapshot.

**Usage**:
```bash
bash scripts/create-snapshot.sh
```

**Snapshot Contents**:
```
/srv/cache/test-runs/transport-HHMMSS-DD-MM-YYYY/
├── impls.yaml              # Test configuration
├── test-matrix.yaml        # Generated test combinations
├── results.yaml            # Test results
├── results.md              # Markdown dashboard
├── settings.yaml           # Snapshot metadata
├── scripts/                # All test scripts
├── snapshots/              # Source code snapshots
├── docker-images/          # Saved Docker images
├── docker-compose/         # Generated compose files
├── logs/                   # Test execution logs
├── re-run.sh               # Reproducibility script
└── README.md               # Snapshot documentation
```

**Features**:
- Fully self-contained (can run offline)
- Includes all source code and Docker images
- `re-run.sh` script for exact reproduction
- Supports `--force-rebuild` flag

---

## Hole-Punch-Specific Scripts

Located in `hole-punch/scripts/`, these scripts implement NAT hole punching tests with DCUtR protocol.

### build-images.sh

**Purpose**: Build orchestrator for hole-punch test implementations.

**Usage**:
```bash
cd hole-punch
bash scripts/build-images.sh "linux" "linux" "linux" "false"
```

**Parameters**:
1. `DIALER_SELECT`: Filter for dialer implementations
2. `LISTENER_SELECT`: Filter for listener implementations
3. `RELAY_SELECT`: Filter for relay implementations
4. `DEBUG`: Debug mode flag

**Build Matrix**:
Each test requires THREE types of images:
1. **Peer images**: For dialer and listener
2. **Relay images**: For relay service
3. **Router images**: For NAT routers

**Special Handling**:
- Linux-based implementations use standard libp2p relay
- Browser implementations require special handling

### generate-tests.sh

**Purpose**: Generates complex test matrix for hole punching scenarios.

**Usage**:
```bash
cd hole-punch
bash scripts/generate-tests.sh "$TEST_SELECT" "$TEST_IGNORE" "$DEBUG"
```

**Test Dimensions** (8D matrix):
1. **Dialer** (peer behind NAT)
2. **Listener** (peer behind NAT)
3. **Transport** (tcp, quic-v1)
4. **Secure Channel** (noise, tls)
5. **Muxer** (yamux, mplex)
6. **Relay** (relay implementation)
7. **Dialer Router** (NAT router implementation)
8. **Listener Router** (NAT router implementation)

**Example Test Names**:
```
linux x linux (tcp, noise, yamux) [relay: linux] - [dr: linux] - [lr: linux]
linux x linux (quic-v1) [relay: linux] - [dr: linux] - [lr: linux]
```

**Network Topology**:
Each test creates isolated networks:
```
WAN (10.{S1}.{S2}.64/29)
├── Relay (.65)
├── Dialer Router (.66)
└── Listener Router (.67)

LAN-Dialer (10.{S1}.{S2}.92/30)
└── Dialer (.94)

LAN-Listener (10.{S1}.{S2}.128/30)
└── Listener (.130)
```

**Subnet Isolation**:
- Uses deterministic subnet derivation from test name hash
- 65,536 unique subnet combinations (256²)
- Collision probability: ~0.02% for 16 parallel tests

### run-single-test.sh

**Purpose**: Executes a single hole punch test with full network topology.

**Usage**:
```bash
bash scripts/run-single-test.sh <test-index>
```

**Test Execution Flow**:
1. Extract test details from test-matrix.yaml
2. Compute unique subnet IDs from test name hash
3. Create three Docker networks (WAN + 2 LANs)
4. Start relay container on WAN
5. Start NAT router containers (dual-homed)
6. Start dialer and listener containers behind NAT
7. Configure Redis-based coordination
8. Wait for hole punching to complete
9. Verify direct connection established
10. Cleanup all containers and networks

**Redis Coordination**:
- Global Redis container shared across tests
- Per-test key namespacing using TEST_KEY
- Keys: `relay:{TEST_KEY}`, `listener:{TEST_KEY}`

**NAT Configuration**:
- SNAT rules for address translation
- Traffic shaping with 100ms delay
- Dual-homed routers connecting WAN and LAN

### start-global-services.sh

**Purpose**: Starts shared Redis service for test coordination.

**Usage**:
```bash
bash scripts/start-global-services.sh
```

**Services**:
- **Redis**: Shared coordination service
  - Network: `redis-network`
  - Container name: `redis-global`
  - Used for multiaddr exchange and peer discovery

**Lifecycle**:
- Started once before test run
- Shared across all tests with key namespacing
- Stopped after test run completes

### stop-global-services.sh

**Purpose**: Stops and removes shared services.

**Usage**:
```bash
bash scripts/stop-global-services.sh
```

**Cleanup**:
- Stops Redis container
- Removes Redis network
- Cleans up any orphaned resources

### generate-dashboard.sh

**Purpose**: Creates hole-punch results dashboard.

**Features**:
- Summary statistics
- Per-test results table
- Dialer × Listener compatibility matrix
- Test status indicators

### create-snapshot.sh

**Purpose**: Creates hole-punch test snapshot with all network configurations.

**Special Inclusions**:
- Network topology documentation
- Redis configuration
- NAT router configurations
- Subnet allocation details

---

## Perf-Specific Scripts

Located in `perf/scripts/`, these scripts implement performance benchmarking.

### build-images.sh

**Purpose**: Build orchestrator with remote server support.

**Usage**:
```bash
cd perf
bash scripts/build-images.sh "go-v0.45|rust-v0.56" "false"
```

**Parameters**:
1. `TEST_SELECT`: Filter for implementations to build
2. `DEBUG`: Debug mode flag

**Remote Build Support**:
- Checks implementation `server` configuration
- For remote servers: Executes build via SSH
- For local builds: Uses standard build process
- Transfers images between machines as needed

**Server Configuration** (in impls.yaml):
```yaml
servers:
  - id: remote-1
    type: remote
    hostname: "192.168.1.100"
    username: "perfuser"

implementations:
  - id: rust-v0.56
    server: remote-1    # Build and run on remote server
```

### generate-tests.sh

**Purpose**: Generates performance test matrix with baseline support.

**Usage**:
```bash
cd perf
bash scripts/generate-tests.sh
```

**Test Types**:
1. **Baseline tests**: Reference implementations (iperf, https, quic-go)
2. **Main tests**: libp2p implementation performance

**Test Selection**:
- `--test-select`: Main test implementations
- `--test-ignore`: Main test exclusions
- `--baseline-select`: Baseline implementations
- `--baseline-ignore`: Baseline exclusions

**Test Matrix Structure**:
```yaml
tests:
  - name: rust-v0.56 x rust-v0.56 (tcp, noise, yamux)
    type: main
    client: rust-v0.56
    server: rust-v0.56
    transport: tcp
    secureChannel: noise
    muxer: yamux
    iterations: 10

  - name: iperf x iperf (tcp)
    type: baseline
    client: iperf
    server: iperf
    iterations: 10
```

### run-single-test.sh

**Purpose**: Executes a single performance benchmark.

**Usage**:
```bash
bash scripts/run-single-test.sh <test-index>
```

**Test Execution**:
1. Start server container (listener)
2. Wait for server readiness
3. Start client container (dialer)
4. Run multiple iterations
5. Collect performance metrics:
   - Upload throughput (Gbps)
   - Download throughput (Gbps)
   - Latency (seconds)
6. Calculate statistics (min, Q1, median, Q3, max)
7. Cleanup containers

**Client-Server Model**:
```
Server Container (port 4001)
  ↓
Client Container
  ↓ measures
Upload/Download/Latency
```

**Iterations**:
- Default: 10 iterations per test
- Configurable via `--iterations` flag
- Statistical analysis across iterations

### run-baseline.sh

**Purpose**: Executes baseline performance tests.

**Usage**:
```bash
bash scripts/run-baseline.sh
```

**Baseline Implementations**:
- **iperf**: Raw TCP performance baseline
- **https**: Go standard library HTTPS
- **quic-go**: Go standard library QUIC

**Purpose**:
- Establish performance ceiling
- Compare libp2p overhead
- Validate test infrastructure

### lib-perf.sh

**Purpose**: Performance test-specific helper functions.

**Functions**:
- `start_perf_server()` - Starts server container
- `run_perf_client()` - Runs client benchmark
- `parse_perf_output()` - Extracts metrics from JSON output
- `calculate_statistics()` - Computes box plot statistics
- `handle_remote_execution()` - Manages remote test execution

**Remote Execution**:
For multi-machine testing:
1. Server runs on remote machine
2. Client runs on local machine
3. Network latency reflects real-world scenarios

### generate-dashboard.sh

**Purpose**: Creates performance results dashboard.

**Output Files**:
- `results.yaml`: Structured results
- `results.md`: Markdown dashboard
- `results.html`: HTML visualization

**Dashboard Sections**:
1. **Summary**: Test overview
2. **Main Test Results**: libp2p performance
3. **Baseline Results**: Reference performance
4. **Environment**: Test configuration
5. **Timestamps**: Test timing
6. **Box Plot Statistics**: Detailed statistics
7. **Test Results**: Individual test details

### generate-boxplot.sh

**Purpose**: Generates box plot visualizations using Python.

**Usage**:
```bash
bash scripts/generate-boxplot.sh
```

**Outputs**:
- `upload_boxplot.png`: Upload throughput distribution
- `download_boxplot.png`: Download throughput distribution
- `latency_boxplot.png`: Latency distribution

**Statistics**:
- Min, Q1, Median, Q3, Max
- Outlier detection
- Per-implementation comparison

**Requirements**:
- Python 3
- matplotlib
- numpy (for statistics)

### setup-remote-server.sh

**Purpose**: Initializes remote server for performance testing.

**Usage**:
```bash
bash scripts/setup-remote-server.sh <server-id>
```

**Setup Tasks**:
1. Verify SSH connectivity
2. Check Docker installation
3. Verify user in docker group
4. Test network connectivity
5. Verify port 4001 accessibility

### create-snapshot.sh

**Purpose**: Creates performance test snapshot.

**Special Inclusions**:
- Box plot images
- Iteration data for all tests
- Remote server configurations
- Performance statistics

---

## Architecture Patterns

### Content-Addressed Caching

All artifacts use content-based addressing for automatic deduplication:

```
/srv/cache/
├── snapshots/<commit-sha>.zip       # Git snapshots (SHA-1, 40 chars)
├── test-matrix/<sha256>.yaml        # Test matrices (SHA-256, 64 chars)
├── build-yamls/                     # Build configuration files
├── docker-images/                   # Docker image cache
└── test-runs/                       # Test pass snapshots
```

**Hash Functions**:
- **Git snapshots**: SHA-1 (from Git, 40 hex chars)
- **Docker images**: SHA-256 (64 hex chars, `sha256:` prefix stripped)
- **Content cache**: SHA-256 (64 hex chars)

**Cache Key Format**:
Uses double-pipe `||` delimiter to prevent ambiguous collisions:
```bash
cache_key=$(echo "$TEST_FILTER||$TEST_IGNORE||$DEBUG" | sha256sum | cut -d' ' -f1)
```

### Test Matrix Generation Pattern

All test suites follow the same pattern:

```bash
#!/usr/bin/env bash
set -euo pipefail

# 1. Source common libraries
source "../scripts/lib-test-aliases.sh"
source "../scripts/lib-test-filtering.sh"
source "../scripts/lib-test-caching.sh"

# 2. Load aliases and expand
load_aliases
TEST_SELECT=$(expand_aliases "$TEST_SELECT")
TEST_IGNORE=$(expand_aliases "$TEST_IGNORE")

# 3. Check cache
cache_key=$(compute_cache_key "$TEST_SELECT" "$TEST_IGNORE" "$DEBUG")
if check_and_load_cache "$cache_key" "$CACHE_DIR" "$TEST_PASS_DIR"; then
    echo "Cache hit!"
    exit 0
fi

# 4. Generate test matrix
# ... test-specific logic ...

# 5. Save to cache
save_to_cache "$TEST_PASS_DIR" "$cache_key" "$CACHE_DIR"
```

### Parallel Test Execution Pattern

All test suites use xargs for parallel execution:

```bash
# Define test execution function
run_test() {
    local test_index=$1

    # Extract test from matrix
    # Run test
    # Append results with file locking

    (
        flock -x 200
        cat >> results.yaml.tmp <<EOF
  - name: $test_name
    status: $status
EOF
    ) 200>/tmp/results.lock
}

# Export function and variables
export -f run_test
export CACHE_DIR TEST_PASS_DIR

# Run tests in parallel
seq 0 $((test_count - 1)) | xargs -P "$WORKER_COUNT" -I {} bash -c 'run_test {}'
```

**File Locking**:
- Uses `flock` for safe concurrent writes
- Lock file: `/tmp/results.lock`
- Prevents race conditions in results.yaml

### Image Build Orchestration Pattern

All test suites follow the same build pattern:

```bash
#!/usr/bin/env bash
# 1. Read impls.yaml
# 2. Apply filters
# 3. For each implementation:
#    a. Generate build YAML
#    b. Save to /srv/cache/build-yamls/
#    c. Call build-single-image.sh
# 4. Report build results
```

**Build YAML Structure**:
```yaml
image_name: transport-interop-rust-v0.56
build_context: /srv/cache/snapshots/abc123/interop-tests
dockerfile: Dockerfile.native
source:
  type: github
  repo: libp2p/rust-libp2p
  commit: abc123...
  dockerfile: interop-tests/Dockerfile.native
```

### Snapshot Creation Pattern

All test suites create reproducible snapshots:

```bash
#!/usr/bin/env bash
# 1. Create snapshot directory
# 2. Copy test configuration
# 3. Copy test results
# 4. Copy all scripts
# 5. Save Docker images
# 6. Copy source snapshots
# 7. Generate re-run.sh script
# 8. Create README.md
```

**Snapshot Structure**:
```
<test>-HHMMSS-DD-MM-YYYY/
├── impls.yaml              # Configuration
├── test-matrix.yaml        # Test combinations
├── results.yaml            # Test results
├── results.md              # Dashboard
├── settings.yaml           # Metadata
├── scripts/                # All scripts
├── snapshots/              # Source code
├── docker-images/          # Saved images
├── docker-compose/         # Compose files
├── logs/                   # Execution logs
├── re-run.sh               # Reproducibility
└── README.md               # Documentation
```

---

## Usage Examples

### Example 1: Running Transport Tests with Aliases

```bash
cd transport

# Run only rust implementations
./run_tests.sh --test-select '~rust' --test-ignore '!~rust' --workers 8

# Explanation:
# --test-select '~rust' expands to: rust-v0.56|rust-v0.55|rust-v0.54|rust-v0.53
# --test-ignore '!~rust' expands to: go-v0.45|python-v0.4|... (everything except rust)
# Result: Only rust x rust tests will run
```

### Example 2: Running Hole-Punch Tests with Debug

```bash
cd hole-punch

# Run specific implementation with debug logging
./run_tests.sh --test-select "linux" --debug --workers 4

# Debug mode:
# - Sets debug=true in container environment
# - Enables verbose logging
# - Useful for troubleshooting
```

### Example 3: Running Perf Tests with Baseline

```bash
cd perf

# Test rust against go baseline
./run_tests.sh \
    --test-select '~rust' --test-ignore '!~rust' \
    --baseline-select '~go' --baseline-ignore '!~go' \
    --iterations 5 \
    --workers 4

# This will:
# 1. Run go baseline tests (iperf, https, quic-go)
# 2. Run rust x rust tests
# 3. Compare rust performance against baseline
```

### Example 4: Building Images for Specific Implementation

```bash
cd transport

# Build only rust-v0.56 image
bash scripts/build-images.sh "rust-v0.56" "false"

# Build with debug symbols
bash scripts/build-images.sh "rust-v0.56" "true"
```

### Example 5: Creating a Test Snapshot

```bash
cd transport

# Run tests and create snapshot
./run_tests.sh --test-select "rust-v0.56" --snapshot

# Snapshot location
ls -l /srv/cache/test-runs/transport-HHMMSS-DD-MM-YYYY/

# Reproduce the test run
cd /srv/cache/test-runs/transport-HHMMSS-DD-MM-YYYY/
./re-run.sh
```

### Example 6: Using Test Aliases in impls.yaml

```yaml
# Define aliases in impls.yaml
test-aliases:
  - alias: "rust"
    value: "rust-v0.56|rust-v0.55|rust-v0.54|rust-v0.53"
  - alias: "go"
    value: "go-v0.45|go-v0.44|go-v0.43"
  - alias: "stable"
    value: "rust-v0.56|go-v0.45"

# Then use in commands:
./run_tests.sh --test-select '~stable'
./run_tests.sh --test-ignore '~rust'
./run_tests.sh --test-select '!~rust'  # Everything EXCEPT rust
```

### Example 7: Remote Perf Testing

```yaml
# Configure remote server in perf/impls.yaml
servers:
  - id: remote-1
    type: remote
    hostname: "192.168.1.100"
    username: "perfuser"

implementations:
  - id: rust-v0.56
    server: remote-1  # Run on remote server
    source:
      type: github
      repo: libp2p/rust-libp2p
      commit: abc123
```

```bash
cd perf

# Build and test on remote server
bash scripts/build-images.sh "rust-v0.56" "false"
./run_tests.sh --test-select "rust-v0.56"

# The scripts will:
# 1. Build Docker image on remote-1
# 2. Start server container on remote-1
# 3. Run client locally against remote server
# 4. Measure real network latency
```

### Example 8: Cache Management

```bash
# Check cache size
du -sh /srv/cache/*

# Clear test matrix cache (force regeneration)
rm -rf /srv/cache/test-matrix/*

# Clear source snapshots (force re-download)
rm -rf /srv/cache/snapshots/*

# Clear build YAMLs
rm -rf /srv/cache/build-yamls/*

# Keep test runs (these are valuable snapshots)
# Only delete if you're sure you don't need them
```

### Example 9: Debugging Failed Tests

```bash
cd transport

# Run single test with debug mode
./run_tests.sh --test-select "rust-v0.56 x go-v0.45" --debug

# Check logs
cat logs/rust-v0.56_x_go-v0.45_tcp_noise_yamux.log

# Check Docker Compose file
cat docker-compose/rust-v0.56_x_go-v0.45_tcp_noise_yamux.yaml

# Manually run the test
docker-compose -f docker-compose/rust-v0.56_x_go-v0.45_tcp_noise_yamux.yaml up
```

### Example 10: Custom Test Matrix

```bash
cd transport

# Generate test matrix without running tests
TEST_PASS_DIR=/tmp/my-test-matrix \
TEST_SELECT="rust-v0.56|go-v0.45" \
TEST_IGNORE="" \
DEBUG="false" \
bash scripts/generate-tests.sh

# Inspect generated matrix
yq eval '.tests[] | .name' /tmp/my-test-matrix/test-matrix.yaml

# Count tests
yq eval '.tests | length' /tmp/my-test-matrix/test-matrix.yaml
```

---

## Maintenance Guidelines

### When to Update Common Scripts

**Update common scripts when**:
- Bug fixes affect multiple test types
- New filtering features needed globally
- Performance improvements applicable to all
- Security issues need patching

**Keep test-specific when**:
- Logic unique to one test type
- Different network topologies
- Type-specific test execution
- Test-specific metrics collection

### Version Compatibility

Common libraries maintain backward compatibility:
1. Never remove functions (deprecate instead)
2. Add optional parameters (with defaults)
3. Document breaking changes in this file
4. Test all three test suites after changes

### Testing Common Script Changes

After modifying common scripts, test all suites:

```bash
# Test transport
cd transport
bash scripts/generate-tests.sh "rust-v0.56" "" "false"
./run_tests.sh --test-select "rust-v0.56" --workers 1 --check-deps

# Test hole-punch
cd hole-punch
bash scripts/generate-tests.sh "linux" "" "false"
./run_tests.sh --test-select "linux" --workers 1 --check-deps

# Test perf
cd perf
bash scripts/generate-tests.sh
./run_tests.sh --test-select "iperf" --workers 1 --check-deps
```

### Performance Monitoring

Monitor script performance:

```bash
# Time test generation
time bash scripts/generate-tests.sh

# Profile cache hit rate
grep "Cache hit" logs/*.log | wc -l
grep "Cache miss" logs/*.log | wc -l

# Monitor parallel execution efficiency
time ./run_tests.sh --workers 1 --test-select "rust-v0.56"
time ./run_tests.sh --workers 8 --test-select "rust-v0.56"
```

---

## Troubleshooting

### Common Issues and Solutions

#### "Command not found" errors

```bash
# Ensure scripts are executable
chmod +x scripts/*.sh
chmod +x transport/scripts/*.sh
chmod +x hole-punch/scripts/*.sh
chmod +x perf/scripts/*.sh
```

#### "ALIASES: unbound variable"

```bash
# Ensure load_aliases() is called before using alias functions
load_aliases  # Must be called first
expand_aliases "$TEST_SELECT"  # Now safe to use
```

#### Cache not working

```bash
# Check cache directory permissions
mkdir -p /srv/cache/test-matrix
chmod -R 755 /srv/cache
```

#### Docker build failures

```bash
# Clear Docker build cache
docker builder prune -af

# Rebuild without cache
./run_tests.sh --force-image-rebuild
```

#### Network conflicts (hole-punch tests)

```bash
# Check for conflicting networks
docker network ls | grep 10.

# Clean up orphaned networks
docker network prune -f
```

#### Redis connection failures (hole-punch tests)

```bash
# Restart Redis
cd hole-punch
bash scripts/stop-global-services.sh
bash scripts/start-global-services.sh

# Check Redis logs
docker logs redis-global
```

#### Remote build failures (perf tests)

```bash
# Test SSH connectivity
ssh -i ~/.ssh/perf_server perfuser@192.168.1.100 "echo 'Connected'"

# Check Docker on remote
ssh -i ~/.ssh/perf_server perfuser@192.168.1.100 "docker ps"

# Check remote disk space
ssh -i ~/.ssh/perf_server perfuser@192.168.1.100 "df -h"
```

---

## Best Practices

### 1. Always Use Aliases for Test Selection

**Good**:
```bash
./run_tests.sh --test-select '~rust' --test-ignore '!~rust'
```

**Bad**:
```bash
./run_tests.sh --test-select 'rust-v0.56|rust-v0.55|rust-v0.54'
```

**Why**: Aliases are maintained in impls.yaml and automatically stay up to date.

### 2. Use Content-Based Caching

**Good**:
```bash
# Let caching work automatically
./run_tests.sh --test-select "rust-v0.56"
./run_tests.sh --test-select "rust-v0.56"  # Cache hit!
```

**Bad**:
```bash
# Don't bypass cache unnecessarily
./run_tests.sh --test-select "rust-v0.56" --force-matrix-rebuild
```

### 3. Create Snapshots for Important Runs

**Good**:
```bash
./run_tests.sh --snapshot  # Creates reproducible snapshot
```

**Why**: Snapshots allow exact reproduction of test results.

### 4. Use Appropriate Worker Counts

**Good**:
```bash
# Use reasonable parallelism
./run_tests.sh --workers 8  # On 8-core machine
./run_tests.sh --workers 16  # On 16-core machine
```

**Bad**:
```bash
# Don't over-parallelize
./run_tests.sh --workers 100  # On 8-core machine
```

### 5. Check Dependencies Before Running

**Good**:
```bash
./run_tests.sh --check-deps  # Verify before running
./run_tests.sh --test-select "rust-v0.56"
```

### 6. Use Debug Mode for Troubleshooting

**Good**:
```bash
./run_tests.sh --test-select "rust-v0.56" --debug --workers 1
```

**Why**: Debug mode provides verbose logging and runs serially for easier debugging.

### 7. Keep Test-Specific Logic in Test Directories

**Good**:
```bash
# transport/scripts/custom-logic.sh
# Custom transport-specific function
```

**Bad**:
```bash
# scripts/transport-specific-function.sh
# Don't add test-specific logic to common scripts
```

---

## Future Enhancements

Planned improvements:

1. **Unified snapshot creation**: Common snapshot script for all test types
2. **Enhanced remote execution**: Better error handling and progress reporting
3. **Test retry logic**: Automatic retry for flaky tests
4. **Performance profiling**: Built-in performance monitoring
5. **Test parallelization hints**: Automatic worker count optimization
6. **Cache analytics**: Cache hit rate monitoring and reporting
7. **Health checks**: Pre-flight checks before test execution

---

**Last Updated**: 2025-12-16
**Version**: 2.0.0
