# Common Test Scripts Library

This directory contains shared bash scripts and libraries used by **all test suites**: perf, transport, and hole-punch.

---

## Overview

The lib/ directory provides reusable bash functions for:
- **Docker image building** (GitHub, local, browser sources)
- **Test matrix generation** with filtering and caching
- **Snapshot creation** for reproducible test runs
- **Output formatting** for consistent terminal UI
- **Cache management** for faster repeated runs
- **GitHub integration** for snapshot downloads
- **Global services** (Redis) coordination
- **Network isolation** for parallel test execution

**Total**: 19 scripts providing ~121KB of shared functionality

**Used By**:
- `perf/` - Performance benchmarking tests
- `transport/` - Transport interoperability tests
- `hole-punch/` - NAT hole punching tests

---

## Directory Structure

```
lib/
├── README.md                       # This file
│
├── build-single-image.sh           # YAML executor for Docker builds
├── check-dependencies.sh           # Dependency verification
│
├── lib-common-init.sh              # Common variable initialization
├── lib-filter-engine.sh            # Alias expansion and filtering
├── lib-generate-tests.sh           # Test generation utilities
├── lib-github-snapshots.sh         # GitHub snapshot management
├── lib-global-services.sh          # Global services (Redis)
├── lib-image-building.sh           # Docker image building functions
├── lib-image-naming.sh             # Image naming conventions
├── lib-inputs-yaml.sh              # inputs.yaml generation/loading
├── lib-output-formatting.sh        # Terminal output formatting
├── lib-remote-execution.sh         # Remote SSH execution
├── lib-snapshot-creation.sh        # Snapshot creation
├── lib-snapshot-images.sh          # Snapshot image management
├── lib-test-caching.sh             # Cache key and storage
├── lib-test-execution.sh           # Test execution coordination
├── lib-test-filtering.sh           # Test filtering utilities
├── lib-test-images.sh              # Image management utilities
│
├── test-filter-engine.sh           # Standalone filter engine tests
└── update-readme-results.sh        # Update README with test results
```

---

## Executable Scripts

### build-single-image.sh (2.7KB)

**Purpose**: Thin executor that builds a single Docker image from YAML parameters.

**Usage**:
```bash
./lib/build-single-image.sh <path-to-yaml-file>
```

**Features**:
- Loads build parameters from YAML using `yq`
- Validates required fields (imageName, sourceType, etc.)
- Checks if image already exists (skip if found, unless force rebuild)
- Delegates to appropriate build function based on sourceType
- Displays result with image ID

**Source Types Supported**:
- `github` - Download GitHub snapshot or clone with submodules
- `local` - Build from local filesystem
- `browser` - Build browser image (chromium, firefox, webkit)

**Example YAML**:
```yaml
imageName: perf-rust-v0.56
imageType: peer
sourceType: local
buildLocation: local
cacheDir: /srv/cache
forceRebuild: false
outputStyle: clean

local:
  path: images/rust/v0.56
  dockerfile: Dockerfile
```

**Called By**: `lib-image-building.sh:build_images_from_section()`
**Source**: lib/build-single-image.sh:1-108

---

### check-dependencies.sh (5.5KB)

**Purpose**: Verifies all required system dependencies are installed.

**Usage**:
```bash
./lib/check-dependencies.sh
```

**Checks**:
- bash 4.0+
- docker 20.10+
- yq 4.0+
- wget, unzip, zip
- docker compose (detects `docker compose` or `docker-compose`)

**Output**:
- Exports `DOCKER_COMPOSE_CMD` to environment and `/tmp/docker-compose-cmd.txt`
- Exit code 0 if all dependencies satisfied
- Exit code 1 if missing or outdated dependencies

**Features**:
- Color-coded output (green checkmarks, red X's)
- Shows installed versions vs required versions
- Auto-detects docker compose v2 plugin vs legacy command

**Called By**: perf/run.sh, other test runners
**Source**: lib/check-dependencies.sh:1-177

---

### test-filter-engine.sh (18.6KB)

**Purpose**: Standalone test script for the filter engine with comprehensive test cases.

**Usage**:
```bash
./lib/test-filter-engine.sh
```

**Tests**:
- Alias loading from YAML
- Simple alias expansion (`~rust` → `rust-v0.56|rust-v0.55`)
- Negation expansion (`!~rust` → all except rust)
- Recursive alias resolution
- Circular reference detection
- Filter string validation

**Exit Codes**:
- 0: All tests pass
- 1: One or more tests fail

**Source**: lib/test-filter-engine.sh:1-664

---

### update-readme-results.sh (1.9KB)

**Purpose**: Updates perf/README.md with latest test results.

**Usage**:
```bash
./lib/update-readme-results.sh <results-file>
```

**Features**:
- Extracts results table from results file
- Injects into README.md between markers
- Preserves rest of README content
- Used automatically by perf tests

**Called By**: perf test runner after test completion
**Source**: lib/update-readme-results.sh:1-60

---

## Library Scripts

### lib-common-init.sh (2.4KB)

**Purpose**: Common variable initialization for all test suites.

**Functions**:

#### `init_common_variables()`
Initializes standard variables with consistent defaults:
- `SHUTDOWN=false` - Shutdown flag
- `IMAGES_YAML=${TEST_ROOT}/images.yaml` - Images config
- `CACHE_DIR=/srv/cache` - Cache root
- `TEST_RUN_DIR=$CACHE_DIR/test-run` - Test run artifacts
- `TEST_IGNORE=""` - Test ignore filter
- `TRANSPORT_IGNORE=""`, `SECURE_IGNORE=""`, `MUXER_IGNORE=""` - Dimension filters
- `WORKER_COUNT=$(nproc)` - Parallel workers
- `DEBUG=false` - Debug mode
- `CHECK_DEPS=false`, `LIST_IMAGES=false`, `LIST_TESTS=false` - Flags
- `CREATE_SNAPSHOT=false`, `AUTO_YES=false` - Flags
- `FORCE_MATRIX_REBUILD=false`, `FORCE_IMAGE_REBUILD=false` - Rebuild flags

All variables are exported for child scripts.

#### `init_cache_dirs()`
Creates cache directory structure:
```
/srv/cache/
├── snapshots/
├── build-yamls/
├── test-run/
└── test-run-matrix/
```

#### `handle_shutdown()`
Sets `SHUTDOWN=true` for Ctrl+C handling.

**Usage**:
```bash
source "$SCRIPT_LIB_DIR/lib-common-init.sh"
init_common_variables
init_cache_dirs
```

**Called By**: All test runners (perf/run.sh, etc.)
**Source**: lib/lib-common-init.sh:1-87

---

### lib-filter-engine.sh (9.2KB)

**Purpose**: Recursive alias expansion and filtering with negation support.

**Functions**:

#### `load_aliases()`
Loads test aliases from images.yaml into global `ALIASES` associative array.

```yaml
# images.yaml
test-aliases:
  - alias: rust
    value: "rust-v0.56|rust-v0.55"
  - alias: go
    value: "go-v0.45|go-v0.44"
```

#### `expand_filter_string(filter_string, all_names_array)`
Expands filter string with alias resolution and negation.

**Syntax**:
- `~rust` → Expands to `rust-v0.56|rust-v0.55`
- `!~rust` → Expands to all names NOT matching rust
- `rust-v0.56|go-v0.45` → Literal pattern (no expansion)

**Features**:
- Recursive alias resolution (aliases can reference aliases)
- Circular reference detection
- Negation properly inverts after full expansion
- Deduplication of expanded values

**Example**:
```bash
source lib-filter-engine.sh
load_aliases

# Expand positive alias
expanded=$(expand_filter_string "~rust" all_image_ids)
# Result: "rust-v0.56|rust-v0.55"

# Expand negation
expanded=$(expand_filter_string "!~rust" all_image_ids)
# Result: "go-v0.45|js-v3.x|..." (everything except rust)
```

#### `print_filter_expansion(orig_var, exp_var, name, empty_msg)`
Pretty-prints filter expansion for user feedback.

**Called By**: perf/lib/generate-tests.sh
**Source**: lib/lib-filter-engine.sh:1-328

---

### lib-generate-tests.sh (1.3KB)

**Purpose**: Common test generation utilities.

**Functions**:

#### `is_standalone_transport(transport)`
Checks if transport is standalone (no secure channel/muxer needed).

**Standalone transports**:
- `quic`, `quic-v1`
- `webtransport`
- `webrtc`, `webrtc-direct`

**Returns**:
- 0 (true): Transport is standalone
- 1 (false): Transport requires secure channel and muxer

**Example**:
```bash
if is_standalone_transport "$transport"; then
  # Generate test without secure/muxer
else
  # Generate test with secure/muxer combinations
fi
```

**Called By**: perf/lib/generate-tests.sh
**Source**: lib/lib-generate-tests.sh:1-46

---

### lib-github-snapshots.sh (18.6KB)

**Purpose**: GitHub snapshot download and caching management.

**Functions**:

#### `download_github_snapshot(org, repo, commit, cache_dir)`
Downloads GitHub repository snapshot to cache.

**Process**:
1. Check if `$cache_dir/snapshots/$commit.zip` exists
2. If not, download from `https://github.com/$org/$repo/archive/$commit.zip`
3. Cache for future use

**Returns**: Path to snapshot file

#### `extract_github_snapshot(snapshot_file, extract_dir)`
Extracts snapshot to directory.

#### `cache_github_snapshot(org, repo, commit, cache_dir)`
High-level function combining download and cache.

**Cache Location**: `$CACHE_DIR/snapshots/<commit-hash>.zip`

**Called By**: lib-image-building.sh (GitHub builds)
**Source**: lib/lib-github-snapshots.sh:1-615

---

### lib-global-services.sh (3.0KB)

**Purpose**: Manages global Docker services (Redis) used for test coordination across all test suites.

**Functions**:

#### `start_redis_service(network_name, redis_name)`
Starts Redis container for listener/dialer coordination.

**Parameters**:
- `network_name`: Docker network name (e.g., "perf-network", "transport-network", "hole-punch-network")
- `redis_name`: Redis container name (e.g., "perf-redis", "transport-redis", "hole-punch-redis")

**Features**:
- Creates Docker network if it doesn't exist
- For perf-network: Creates with subnet 10.5.0.0/24 for static listener IP (10.5.0.10)
- For other networks: Creates without specific subnet
- Starts Redis container with name and network specified
- Waits for Redis to be ready
- Shared across all parallel tests

**Image**: redis:7-alpine
**Redis Config**: No persistence (`--save "" --appendonly no`)

#### `stop_redis_service(network_name, redis_name)`
Stops and removes Redis container and network.

**Parameters**:
- `network_name`: Docker network name to remove
- `redis_name`: Redis container name to stop

**Usage**:
```bash
source lib-global-services.sh

# For perf tests
start_redis_service "perf-network" "perf-redis"
# ... run tests ...
stop_redis_service "perf-network" "perf-redis"

# For transport tests
start_redis_service "transport-network" "transport-redis"
# ... run tests ...
stop_redis_service "transport-network" "transport-redis"

# For hole-punch tests
start_redis_service "hole-punch-network" "hole-punch-redis"
# ... run tests ...
stop_redis_service "hole-punch-network" "hole-punch-redis"
```

**Called By**:
- perf/run.sh (lines 563-669)
- transport/run.sh (lines 496-562)
- hole-punch/run.sh (lines 507-572)

**Source**: lib/lib-global-services.sh:1-101

---

### lib-image-building.sh (14.3KB)

**Purpose**: Docker image building functions for all source types.

**Functions**:

#### `build_images_from_section(section, filter, force_rebuild)`
Main orchestrator function that builds images from images.yaml section.

**Parameters**:
- `section`: "implementations" or "baselines"
- `filter`: Pipe-separated image IDs (optional)
- `force_rebuild`: true/false

**Process**:
1. Read images.yaml to get implementation count
2. Iterate each implementation
3. Apply filter (skip if not matching)
4. Check if image exists (skip if yes, unless force rebuild)
5. Generate build YAML at `$CACHE_DIR/build-yamls/docker-build-<type>-<id>.yaml`
6. Execute `build-single-image.sh`

#### `build_from_local(yaml_file, output_filter)`
Builds Docker image from local filesystem.

**Process**:
```bash
docker build -f "$local_path/$dockerfile" -t "$image_name" "$local_path"
```

#### `build_from_github(yaml_file, output_filter)`
Builds Docker image from GitHub snapshot (no submodules).

**Process**:
1. Download snapshot to cache
2. Extract to temp directory
3. Build Docker image
4. Cleanup temp directory

#### `build_from_github_with_submodules(yaml_file, output_filter)`
Builds Docker image from GitHub with submodules.

**Process**:
1. Clone repo with `git clone --depth 1`
2. Fetch specific commit
3. Initialize submodules recursively
4. Cache clone for future use
5. Build Docker image
6. Cleanup temp directory

#### `build_browser_image(yaml_file, output_filter)`
Builds browser-based image (chromium, firefox, webkit).

**Process**:
1. Verify base image exists
2. Tag base image for browser build
3. Build with `--build-arg BASE_IMAGE` and `--build-arg BROWSER`

#### `download_github_snapshot(repo, commit, cache_dir)`
Downloads GitHub snapshot to cache.

#### `extract_github_snapshot(snapshot_file, repo_name, commit)`
Extracts snapshot to temp directory.

#### `clone_github_repo_with_submodules(repo, commit, cache_dir)`
Clones repo with submodules, caches result.

#### `get_output_filter(style)`
Returns shell command for output filtering.

**Styles**:
- `clean` → `cat` (full output)
- `indented` → `sed 's/^/    /'` (4-space indent)
- `filtered` → `grep -E '^(#|Step|Successfully|ERROR)'` (compact)

**Called By**: perf/run.sh:554-555
**Source**: lib/lib-image-building.sh:1-491

---

### lib-image-naming.sh (2.4KB)

**Purpose**: Image naming convention utilities.

**Functions**:

#### `get_image_name(test_type, impl_id)`
Generates Docker image name from test type and implementation ID.

**Format**: `<test-type>-<impl-id>`

**Examples**:
- `get_image_name "perf" "rust-v0.56"` → `perf-rust-v0.56`
- `get_image_name "transport" "go-v0.45"` → `transport-go-v0.45`

**Called By**: Image building functions
**Source**: lib/lib-image-naming.sh:1-80

---

### lib-inputs-yaml.sh (3.4KB)

**Purpose**: Generate and modify inputs.yaml for reproducibility.

**Functions**:

#### `generate_inputs_yaml(output_file, test_type, original_args...)`
Generates inputs.yaml capturing all test run configuration.

**Parameters**:
- `output_file`: Where to write inputs.yaml
- `test_type`: "transport", "perf", or "hole-punch"
- `original_args`: Original command-line arguments array

**Output Structure**:
```yaml
testType: perf
commandLineArgs:
  - "--test-ignore"
  - "experimental"
environmentVariables:
  IMAGES_YAML: "./images.yaml"
  CACHE_DIR: "/srv/cache"
  TEST_RUN_DIR: "/srv/cache/test-run"
  DEBUG: "false"
  ITERATIONS: "10"
  # ... more variables
```

#### `modify_inputs_for_snapshot(snapshot_dir)`
Modifies inputs.yaml for snapshot context.

**Changes**:
- `IMAGES_YAML` → `./images.yaml`
- `CACHE_DIR` → `./`
- `TEST_RUN_DIR` → `./re-run`
- `SCRIPT_DIR` → `./lib`
- `SCRIPT_LIB_DIR` → `./lib`
- Removes `--snapshot` flag from commandLineArgs

**Usage**:
```bash
source lib-inputs-yaml.sh
generate_inputs_yaml "$TEST_PASS_DIR/inputs.yaml" "perf" "${ORIGINAL_ARGS[@]}"
```

**Called By**: perf/run.sh:389
**Source**: lib/lib-inputs-yaml.sh:1-112

---

### lib-output-formatting.sh (6.1KB)

**Purpose**: Consistent terminal output formatting with indentation support.

**Functions**:

#### `print_header(text)`
Prints section header with border:
```
===============================================================================
Building: perf-rust-v0.56
===============================================================================
```

#### `print_banner(text)`
Prints large ASCII art banner with libp2p logo.

#### `print_message(text)`, `print_success(text)`, `print_error(text)`
Prints formatted messages with icons:
- `print_message` → `→ Message`
- `print_success` → `✓ Success`
- `print_error` → `✗ Error`

#### `log_message(text)`, `log_success(text)`, `log_error(text)`, `log_debug(text)`
Logging variants that respect DEBUG flag.

#### `indent()`, `unindent()`
Manages indentation level for nested output.

**Example**:
```bash
print_header "Building Images"
indent
print_message "Building rust-v0.56"
indent
print_success "Built successfully"
unindent
print_message "Building go-v0.45"
unindent
```

Output:
```
===============================================================================
Building Images
===============================================================================
    → Building rust-v0.56
        ✓ Built successfully
    → Building go-v0.45
```

**Called By**: All scripts for consistent output
**Source**: lib/lib-output-formatting.sh:1-202

---

### lib-remote-execution.sh (5.3KB)

**Purpose**: Remote server execution via SSH for multi-machine testing.

**Status**: ⚠️ Code exists but **not currently used** - remote execution is commented out in all test runners.

**Functions**:

#### `test_ssh_connectivity(hostname, username, ssh_key)`
Tests SSH connection to remote server.

#### `build_on_remote(yaml_file, username, hostname, build_script)`
Executes build on remote server via SSH.

**Process**:
1. SCP YAML file to remote
2. SCP build script to remote
3. SCP libraries to remote
4. Execute build remotely via SSH
5. Stream output in real-time
6. Cleanup remote files

#### `copy_to_remote(local_path, remote_path, username, hostname)`
SCP file to remote server.

#### `exec_on_remote(command, username, hostname)`
Execute command on remote server.

**Future Use Cases**:
- Multi-machine performance testing
- Geographic distribution testing
- Cross-datacenter latency measurements
- Testing between different network environments

**Current Approach**: All tests run locally using Docker networking

**Source**: lib/lib-remote-execution.sh:1-157

**Note**: While the code infrastructure exists for remote execution (see perf/run.sh:416-443, transport/run.sh comments), it is not currently enabled. All test execution happens locally using Docker containers and networks.

---

### lib-snapshot-creation.sh (16.5KB)

**Purpose**: Creates reproducible test snapshots containing all artifacts.

**Functions**:

#### `create_snapshot(test_pass_dir, snapshot_name)`
Creates complete snapshot for test reproducibility.

**Snapshot Contents**:
- Test configuration (images.yaml, test-matrix.yaml, inputs.yaml)
- Test results (results.yaml, individual results)
- Logs (all test logs)
- Docker images (exported as .tar.gz)
- Framework scripts (lib/, test-specific scripts)
- Re-run script (run.sh for snapshot execution)
- GitHub snapshots (if used)

**Output**: ZIP file at `$TEST_PASS_DIR/snapshot-<name>.zip`

**Features**:
- Export Docker images to avoid registry dependencies
- Include all scripts for self-contained execution
- Modify inputs.yaml for snapshot context
- Generate run.sh script for re-execution

**Usage**:
```bash
create_snapshot "$TEST_PASS_DIR" "perf-results-2026-01-01"
```

**Called By**: perf/run.sh when `--snapshot` flag set
**Source**: lib/lib-snapshot-creation.sh:1-546

---

### lib-snapshot-images.sh (4.2KB)

**Purpose**: Docker image export/import for snapshots.

**Functions**:

#### `export_docker_images(test_pass_dir, image_list...)`
Exports Docker images to tar.gz files for snapshot.

**Process**:
```bash
docker save "$image_name" | gzip > "$test_pass_dir/images/$image_name.tar.gz"
```

#### `import_docker_images(snapshot_dir)`
Imports Docker images from snapshot.

**Process**:
```bash
docker load < "$snapshot_dir/images/$image_name.tar.gz"
```

**Called By**: lib-snapshot-creation.sh
**Source**: lib/lib-snapshot-images.sh:1-132

---

### lib-test-caching.sh (2.9KB)

**Purpose**: Test matrix caching for faster repeated runs.

**Functions**:

#### `compute_test_run_key(images_yaml, ...args)`
Computes 8-character cache key from images.yaml content and parameters.

**Process**:
```bash
# Hash: images.yaml content + all args joined with '|'
hash=$(printf '%s' "$contents$args" | sha256sum | cut -d ' ' -f1)
echo "${hash:0:8}"  # First 8 hex chars
```

**Example**:
```bash
TEST_RUN_KEY=$(compute_test_run_key \
  "$IMAGES_YAML" \
  "$TEST_IGNORE" \
  "$BASELINE_IGNORE" \
  "$TRANSPORT_IGNORE" \
  "$SECURE_IGNORE" \
  "$MUXER_IGNORE" \
  "$DEBUG" \
)
# Result: "a3f7b21c"
```

#### `compute_test_key(test_name)`
Computes 8-character key from test name.

#### `check_and_load_cache(cache_key, cache_dir, output_file, force_rebuild, test_type)`
Checks for cached file and loads if found.

**Returns**:
- 0: Cache hit
- 1: Cache miss or force rebuild

#### `save_to_cache(output_file, cache_key, cache_dir, test_type)`
Saves file to cache with computed key.

**Cache Locations**:
- Test matrices: `$CACHE_DIR/test-run-matrix/<type>-<key>.yaml`
- Docker compose: `$CACHE_DIR/test-docker-compose/<type>-<key>-<test>.yaml`

**Called By**: perf/lib/generate-tests.sh
**Source**: lib/lib-test-caching.sh:1-111

---

### lib-test-execution.sh (2.3KB)

**Purpose**: Test execution coordination.

**Functions**:

#### `run_tests_parallel(test_list, worker_count, run_function)`
Runs tests in parallel with specified worker count.

**Process**:
- Spawns worker processes
- Each worker calls `run_function` for assigned tests
- Waits for all workers to complete

#### `wait_for_test_completion(test_pid)`
Waits for specific test to complete.

**Called By**: Test runners for parallel execution
**Source**: lib/lib-test-execution.sh:1-73

---

### lib-test-filtering.sh (829 bytes)

**Purpose**: Test filtering utilities for matrix generation.

**Functions**:

#### `get_common(list1, list2)`
Finds common elements between two space-separated lists.

**Example**:
```bash
common=$(get_common "tcp ws quic" "ws quic webrtc")
# Result: "ws quic"
```

#### `is_standalone_transport(transport)`
Checks if transport is standalone (duplicate of lib-generate-tests.sh version).

**Called By**: Test matrix generation scripts
**Source**: lib/lib-test-filtering.sh:1-27

---

### lib-test-images.sh (6.1KB)

**Purpose**: Image management utilities for test configuration.

**Functions**:

#### `get_entity_ids(section)`
Gets all IDs from YAML section (implementations, baselines, etc.).

**Example**:
```bash
readarray -t impl_ids < <(get_entity_ids "implementations")
# Result: ["rust-v0.56", "go-v0.45", ...]
```

#### `get_transport_names(section)`
Gets all unique transport names from section.

#### `get_secure_names(section)`
Gets all unique secure channel names.

#### `get_muxer_names(section)`
Gets all unique muxer names.

#### `get_source_commit(section, impl_id)`
Gets GitHub commit hash for implementation.

**Called By**: perf/lib/generate-tests.sh
**Source**: lib/lib-test-images.sh:1-202

---

## Test Suite Integration

The library supports three distinct test suites with different execution models:

### Perf Tests (Sequential)
- **Worker Count**: 1 (sequential execution for accurate performance measurements)
- **Network**: Single `perf-network` with static IP for listener (10.5.0.10)
- **Sections**: `baselines` + `implementations`
- **Special Features**:
  - Upload/download throughput measurements
  - Latency testing with statistical distribution
  - Baseline comparisons (iperf, HTTPS, QUIC-Go)

### Transport Tests (Parallel)
- **Worker Count**: `$(nproc)` (parallel execution for speed)
- **Network**: Single `transport-network` with dynamic IPs
- **Sections**: `implementations` only
- **Special Features**:
  - dialOnly implementations (browsers can only dial, not listen)
  - Standalone transports (quic-v1, webtransport, webrtc-direct)
  - 40+ implementation variations including browsers

### Hole-Punch Tests (Parallel)
- **Worker Count**: `$(nproc)` (parallel execution for speed)
- **Network**: Isolated networks per test (WAN + 2 LANs)
  - WAN: 10.x.x.64/27
  - Dialer LAN: 10.x.x.96/27
  - Listener LAN: 10.x.x.128/27
- **Sections**: `routers` + `relays` + `implementations`
- **Special Features**:
  - 5 containers per test (2 routers, 1 relay, 2 peers)
  - NAT simulation with iptables
  - DCUtR protocol testing
  - Unique subnets calculated from test key

### Common Features
All test suites share:
- Redis coordination for multiaddr exchange
- Test matrix generation with filtering
- Cache management for faster runs
- Snapshot creation for reproducibility
- Consistent output formatting
- inputs.yaml for exact reproduction

---

## Usage Patterns

### Pattern 1: Initialize Common Variables

All test runners (perf, transport, hole-punch) start with:

```bash
# Example from perf/run.sh, transport/run.sh, hole-punch/run.sh
export TEST_ROOT="$(dirname "${BASH_SOURCE[0]}")"
export SCRIPT_DIR="${SCRIPT_DIR:-$(cd "${TEST_ROOT}/lib" && pwd)}"
export SCRIPT_LIB_DIR="${SCRIPT_LIB_DIR:-${SCRIPT_DIR}/../../lib}"

source "${SCRIPT_LIB_DIR}/lib-common-init.sh"
init_common_variables
init_cache_dirs

# Hook up ctrl+c handler
trap handle_shutdown INT
```

**Note**: Each test suite can override variables after initialization:
```bash
# perf/run.sh - Sequential execution
WORKER_COUNT=1  # Perf must run 1 test at a time

# transport/run.sh, hole-punch/run.sh - Parallel execution
WORKER_COUNT=$(nproc)  # Use all CPU cores
```

### Pattern 2: Build Docker Images

```bash
# Common pattern used by all test suites
source "${SCRIPT_LIB_DIR}/lib-image-building.sh"

export TEST_TYPE="<test-type>"  # "perf", "transport", or "hole-punch"
export IMAGES_YAML
export FORCE_IMAGE_REBUILD

# perf/run.sh - Baselines + Implementations
build_images_from_section "baselines" "${IMAGE_FILTER}" "${FORCE_IMAGE_REBUILD}"
build_images_from_section "implementations" "${IMAGE_FILTER}" "${FORCE_IMAGE_REBUILD}"

# transport/run.sh - Implementations only
build_images_from_section "implementations" "${IMAGE_FILTER}" "${FORCE_IMAGE_REBUILD}"

# hole-punch/run.sh - Routers + Relays + Implementations
build_images_from_section "routers" "${IMAGE_FILTER}" "${FORCE_IMAGE_REBUILD}"
build_images_from_section "relays" "${IMAGE_FILTER}" "${FORCE_IMAGE_REBUILD}"
build_images_from_section "implementations" "${IMAGE_FILTER}" "${FORCE_IMAGE_REBUILD}"
```

### Pattern 3: Generate Test Matrix with Caching

```bash
# perf/lib/generate-tests.sh
source "${SCRIPT_LIB_DIR}/lib-filter-engine.sh"
source "${SCRIPT_LIB_DIR}/lib-test-caching.sh"

# Load aliases
load_aliases

# Expand filters
EXPANDED_TEST_IGNORE=$(expand_filter_string "${TEST_IGNORE}" all_image_ids)

# Check cache
if check_and_load_cache "${TEST_RUN_KEY}" "${CACHE_DIR}/test-run-matrix" "${TEST_PASS_DIR}/test-matrix.yaml" "${FORCE_MATRIX_REBUILD}" "${TEST_TYPE}"; then
  exit 0  # Cache hit
fi

# Generate matrix
# ... matrix generation ...

# Save to cache
save_to_cache "${TEST_PASS_DIR}/test-matrix.yaml" "${TEST_RUN_KEY}" "${CACHE_DIR}/test-run-matrix" "${TEST_TYPE}"
```

### Pattern 4: Consistent Output Formatting

```bash
source "$SCRIPT_LIB_DIR/lib-output-formatting.sh"

print_banner "Performance Tests"
print_header "Building Images"
indent
print_message "Building rust-v0.56..."
print_success "Built successfully"
unindent
```

### Pattern 5: Create Snapshot

```bash
source "$SCRIPT_LIB_DIR/lib-snapshot-creation.sh"

if [ "$CREATE_SNAPSHOT" = true ]; then
  create_snapshot "$TEST_PASS_DIR" "perf-$(date +%Y-%m-%d)"
fi
```

---

## Performance Characteristics

### Caching Performance

**Test Matrix Caching** (lib-test-caching.sh):
- Cache miss: ~2-5 seconds (generation + write)
- Cache hit: ~50-200ms (read from disk)
- **Speedup**: 10-100x for repeated runs

**GitHub Snapshot Caching** (lib-github-snapshots.sh):
- Cache miss: ~5-30 seconds (download + extract)
- Cache hit: ~1-2 seconds (extract only)
- **Speedup**: 5-15x for repeated builds

**Docker Image Caching** (build-single-image.sh):
- Cache miss: ~30-300 seconds (build from scratch)
- Cache hit: ~0.1 seconds (existence check)
- **Speedup**: 300-3000x for existing images

### Memory Usage

**Filter Engine** (lib-filter-engine.sh):
- 100 implementations: ~1MB memory
- 1000 implementations: ~10MB memory
- Uses associative arrays for O(1) lookups

**Test Matrix Generation**:
- Streaming generation (doesn't load all tests in memory)
- Incremental writes to YAML file
- Memory usage: O(implementations) not O(tests)

---

## File Size Summary

| Category | Scripts | Total Size | Purpose |
|----------|---------|------------|---------|
| **Core Infrastructure** | 5 | 31KB | Common init, formatting, filtering |
| **Image Building** | 4 | 23KB | Docker build orchestration |
| **GitHub Integration** | 1 | 19KB | Snapshot downloads |
| **Snapshot Creation** | 2 | 21KB | Test reproducibility |
| **Test Execution** | 5 | 14KB | Matrix generation, caching, execution |
| **Utilities** | 2 | 13KB | Dependency checks, testing |
| **Total** | 19 | 121KB | Complete framework |

**Note**: Total size is ~121KB across all library scripts, supporting perf, transport, and hole-punch test suites.

---

## Dependencies

### Required System Tools
- bash 4.0+
- docker 20.10+
- yq 4.0+
- wget
- unzip, zip
- git (for GitHub submodules)

### Required Docker
- Docker daemon running
- docker compose (v2 plugin or legacy command)
- Sufficient disk space for images and caches

### Environment Variables
- `CACHE_DIR` - Cache root (default: `/srv/cache`)
- `TEST_RUN_DIR` - Test run artifacts (default: `$CACHE_DIR/test-run`)
- `SCRIPT_LIB_DIR` - Path to this lib/ directory
- `DEBUG` - Enable debug output (`true`/`false`)

---

## Troubleshooting

### "Command not found" errors

Ensure scripts are executable:
```bash
chmod +x lib/*.sh
```

### "ALIASES: unbound variable"

Call `load_aliases()` before using alias functions:
```bash
source lib-filter-engine.sh
load_aliases  # Must be called first
expand_filter_string "~rust" all_image_ids  # Now safe
```

### Cache not working

Check cache directory permissions:
```bash
mkdir -p /srv/cache
chmod -R 755 /srv/cache
ls -la /srv/cache  # Verify ownership
```

### Docker image builds failing

Check Docker daemon:
```bash
docker ps  # Should not error
docker info  # Show Docker status
```

Verify source paths exist:
```bash
ls -la perf/images/rust/v0.56/Dockerfile
```

### GitHub snapshot downloads failing

Check network connectivity:
```bash
wget https://github.com -O /dev/null
```

Check rate limits:
```bash
# GitHub has rate limits for unauthenticated requests
# Use authenticated requests if needed
```

---

## Testing Common Libraries

### Test Filter Engine

```bash
./lib/test-filter-engine.sh
```

Expected output:
```
Testing filter engine...
✓ Test 1: Load aliases
✓ Test 2: Simple expansion
✓ Test 3: Negation expansion
...
All tests passed!
```

### Test Image Building

```bash
# Create test YAML
cat > /tmp/test-build.yaml <<EOF
imageName: test-image
imageType: peer
sourceType: local
buildLocation: local
cacheDir: /srv/cache
forceRebuild: false
outputStyle: clean
local:
  path: perf/images/rust/v0.56
  dockerfile: Dockerfile
EOF

# Execute build
./lib/build-single-image.sh /tmp/test-build.yaml
```

### Test Cache Functions

```bash
source lib/lib-test-caching.sh

# Compute cache key
key=$(compute_test_run_key "perf/images.yaml" "test-ignore" "experimental")
echo "Cache key: $key"

# Should output 8-char hex string like: a3f7b21c
```

---

## Version History

### Current Version (2026-01-14)
- 19 scripts providing comprehensive framework
- **All test suites supported**: perf, transport, hole-punch
- Parameterized global services (network_name, redis_name)
- GitHub snapshot caching with submodule support
- Test matrix caching with content-addressed keys
- Snapshot creation for full reproducibility
- Consistent output formatting across all tests
- Parallel test execution support (transport, hole-punch)
- Sequential test execution support (perf)
- Remote execution support (code exists, not currently enabled)

### Previous Version (2026-01-01)
- 20 scripts (before consolidation)
- Initial multi-suite support
- Basic global services

### Earlier Version (2025-12-03)
- Limited to 3 scripts
- Basic alias expansion
- Simple test filtering
- Initial caching support

---

## Related Documentation

### Framework Documentation
- **[CLAUDE.md](../CLAUDE.md)** - Comprehensive codebase and framework guide
- **[docs/inputs-schema.md](../docs/inputs-schema.md)** - inputs.yaml specification and schema

### Test Suite Documentation
- **[perf/README.md](../perf/README.md)** - Performance benchmarking tests
- **[transport/README.md](../transport/README.md)** - Transport interoperability tests
- **[hole-punch/README.md](../hole-punch/README.md)** - NAT hole punching tests

### Additional Resources
- **Filter Engine**: See `test-filter-engine.sh` for comprehensive examples
- **Image Building**: See `build-single-image.sh` for YAML format
- **Caching System**: See `lib-test-caching.sh` for cache key computation

---

**Last Updated**: 2026-01-14
**Maintained By**: libp2p test-plans team
