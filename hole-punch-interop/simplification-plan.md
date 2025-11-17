# Hole-Punch Interoperability Test Redesign Plan

## Executive Summary

This plan redesigns the hole-punch-interop test system to be simpler, more maintainable, and more efficient while preserving all current functionality. The redesign consolidates complex TypeScript orchestration into pure bash scripts, adopts YAML for all configuration and data files, implements comprehensive content-addressed caching, and creates self-contained reproducible test snapshots.

**Core Dependencies**: Only `docker`, `git`, `make`, `bash`, and `yq` - NO Node.js, npm, or buildx required.

**Simplification Philosophy**:
- Rely on Docker's built-in layer caching for image builds
- Use hybrid architecture with global services (Redis, Relay) and per-test containers
- Implement content-addressed caching for all downloads and generated files
- Create self-contained test snapshots for complete reproducibility
- YAML everywhere for consistency and readability

**Test Selection System**:
- Each `impl/<lang>/` directory has a `test-selection.yaml` file defining default test-filter and test-ignore patterns
- Global `hole-punch-interop/test-selection.yaml` provides defaults for full test passes
- CLI arguments (`--test-filter`, `--test-ignore`) override defaults from YAML files
- GitHub workflow inputs allow custom filter/ignore strings via checkboxes
- Filter patterns use pipe-separated substring matching (e.g., `rust-v0.53|go-v0.43`)
- Empty filter = select all tests; empty ignore = ignore nothing

---

## Opinions and Assumptions

This design makes deliberate, opinionated choices to maximize simplicity and consistency.

### Required Dependencies

**Core System Tools**:
- `bash` (version 4.0+) - Shell scripting and orchestration
- `git` (version 2.0+) - Version control and change detection
- `make` (GNU Make 3.81+) - Build orchestration
- `docker` (version 20.10+) - Container runtime with built-in layer caching
- `yq` (version 4.0+) - YAML processing in bash scripts

**Optional Tools**:
- `pandoc` - For converting results.md to HTML format
- `jq` - For JSON processing if needed for debugging

**System Assumptions**:
- Linux/Unix-like operating system (macOS, Ubuntu, Debian, etc.)
- x86_64 or ARM64 architecture
- Sufficient disk space in `/srv/cache/` (recommend 50GB minimum)
- Network access for downloading GitHub repository snapshots

### Hash Functions and Identifiers

This design uses different hash functions for different purposes, but **never includes the hash algorithm name in the identifier string**. This keeps identifiers clean and consistent.

**Git Commit SHAs (SHA-1, 40 hex chars)**:
- Used for: Repository snapshot filenames
- Format: `b7914e407da34c99fb76dcc300b3d44b9af97fac`
- Example: `/srv/cache/snapshots/b7914e407da34c99fb76dcc300b3d44b9af97fac.zip`
- Source: Git's internal object hash
- Note: May transition to SHA-256 as Git adopts it

**Docker Image IDs (SHA-256, 64 hex chars)**:
- Used for: Container image identification
- Format: `1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef` (64 chars)
- Example in image.yaml: `imageID: 1234567890abcdef...`
- Source: `docker image inspect --format '{{.Id}}'` with `sha256:` prefix stripped
- Command: `docker image inspect <name> -f '{{.Id}}' | cut -d':' -f2`

**Content-Addressed Cache Keys (SHA-256, 64 hex chars)**:
- Used for: Makefiles, test-matrix files, docker-compose files
- Format: `abc123def456...` (64 hex chars)
- Example: `/srv/cache/makefiles/abc123def456.makefile`
- Source: `sha256sum <file> | cut -d' ' -f1`
- Ensures identical content always produces same filename

**Abbreviated Hashes (First 8-12 chars)**:
- Used for: Human-readable output and logging only
- Format: `b7914e40` or `abc123def456`
- Never used for actual file lookups or cache keys
- Example: `echo "Using cached snapshot: ${commitSha:0:8}.zip"`

### File Naming Conventions

**Snapshot Archives**:
- Source code: `<commitSha>.zip` (40 hex chars from git)
- Test passes: `hole-punch-<kind>-<HHMMSS>-<DD>-<MM>-<YYYY>.zip`
- Example: `hole-punch-rust-143022-08-11-2025.zip`

**Generated Configuration**:
- Makefiles: `<sha256>.makefile` (64 hex chars)
- Test matrices: `<sha256>.yaml` (64 hex chars)
- Docker compose: `<sha256>.yaml` (64 hex chars)

**Implementation Metadata**:
- Image metadata: `image.yaml` (always in impl/<lang>/<version>/)
- Contains imageID without `sha256:` prefix

### Design Rationale

1. **No Algorithm Prefixes**: Modern systems know what hash they're using. Including `sha256:` in every identifier is redundant and makes string manipulation harder.

2. **Git SHAs Stay Short**: While Docker uses SHA-256, Git still uses SHA-1 (40 chars). We preserve Git's native format for repository snapshots.

3. **Full Hashes in Storage**: Cache filenames always use full hashes to eliminate collision risk, even though the probability is astronomically low.

4. **Abbreviated for Humans**: Logs and console output show 8-12 character prefixes for readability, but storage always uses full hashes.

5. **Consistent Extraction**: All scripts use the same pattern to extract hashes:
   - Docker IDs: `cut -d':' -f2` to remove `sha256:` prefix
   - File hashes: `sha256sum | cut -d' ' -f1` to get just the hash
   - Git SHAs: Used directly from `git rev-parse`

---

## Understanding Redis in Hole-Punch Tests

### Why Redis is Required

Redis serves as a **coordination bus** for the distributed components of each hole-punch test. In a typical test, there are 6 containers that need to communicate:
1. **Relay** - Provides the relay service for hole punching (global, shared)
2. **Redis** - Coordination service (global, shared)
3. **Dialer** - Initiates the connection (per-test)
4. **Listener** - Waits for incoming connections (per-test)
5. **Dialer Router** - Simulates NAT for the dialer (per-test)
6. **Listener Router** - Simulates NAT for the listener (per-test)

### How Redis is Used

Redis enables asynchronous communication between containers without tight coupling:

1. **Relay Startup**: The relay server starts, binds to TCP and QUIC transports, then publishes its multiaddrs to Redis:
   - `RPUSH RELAY_TCP_ADDRESS /ip4/x.x.x.x/tcp/1234` (pushed twice for 2 clients)
   - `RPUSH RELAY_QUIC_ADDRESS /ip4/x.x.x.x/udp/1234/quic-v1` (pushed twice for 2 clients)

2. **Client Coordination**: Both dialer and listener:
   - Wait for relay addresses from Redis (`BLPOP RELAY_TCP_ADDRESS` or `RELAY_QUIC_ADDRESS`)
   - Connect to the relay using the discovered multiaddr

3. **Listener Registration**: The listener:
   - Makes a reservation with the relay
   - Publishes its peer ID to Redis: `RPUSH LISTEN_CLIENT_PEER_ID <peer-id>`

4. **Dialer Connection**: The dialer:
   - Waits for the listener's peer ID (`BLPOP LISTEN_CLIENT_PEER_ID`)
   - Dials the listener via the relay using p2p-circuit
   - Measures RTT and outputs JSON to stdout

### Redis Lifecycle Management

**Starting Redis & Relay** (`scripts/start-global-services.sh`):
- Creates a shared Docker network for all tests
- Starts a single Redis container that persists for entire test run
- Starts a single Relay container that persists for entire test run
- Waits for health checks to pass
- Returns container names for reference

**Stopping Services** (`scripts/stop-global-services.sh`):
- Stops and removes the Redis container
- Stops and removes the Relay container
- Removes the shared Docker network
- Called automatically via trap on script exit

**Benefits of Shared Services**:
- Eliminates redundant container startup/teardown (saves ~4-6 seconds per test)
- Reduces Docker resource usage significantly
- Simplifies test orchestration
- Tests remain isolated via unique Redis keys and separate networks per test

---

## Hybrid Architecture

### Global Services (Started Once Per Test Run)
- **Redis**: Coordination bus
- **Relay**: Shared relay server
- **Network**: `hole-punch-network`

### Per-Test Services (via docker-compose)
- **Dialer**: Implementation under test
- **Listener**: Implementation under test
- **Dialer Router**: NAT simulation for dialer
- **Listener Router**: NAT simulation for listener
- **Networks**: `lan_dialer`, `lan_listener` (isolated per test)

This reduces per-test container count from 6 to 4, speeding up test execution.

---

## Content-Addressed Cache Structure

All cached data lives under `/srv/cache/` with content-addressed naming:

```
/srv/cache/
├── snapshots/
│   ├── <commitSha>.zip              # GitHub repo snapshots
│   └── <commitSha>.zip.metadata     # Download metadata
├── makefiles/
│   └── <sha256>.makefile            # Cached Makefiles
├── test-matrix/
│   └── <sha256>.yaml                # Generated test matrices
├── docker-compose/
│   └── <sha256>.yaml                # Generated compose files
└── test-passes/
    └── hole-punch-<kind>-<timestamp>.zip  # Test pass snapshots
```

**Benefits**:
- No redundant downloads across CI runs
- Content-addressed = no collisions, automatic deduplication
- Easy to inspect and debug cached artifacts
- Supports multiple test runs in parallel

---

## File Format Standardization (All YAML)

### 1. test-ignore.txt → test-selection.yaml

**Before** (`impl/rust/test-ignore.txt`):
```
rust-v0.53|rust-v0.54
```

**After** (`impl/rust/test-selection.yaml`):
```yaml
# Test selection configuration for Rust implementations
# Used as default when no --test-filter or --test-ignore args provided

# test-filter: List of substring patterns to match test names (OR logic)
# If empty or omitted, all tests are initially selected
test-filter:
  - rust-v0.53
  - rust-v0.54

# test-ignore: List of substring patterns to exclude from selected tests
# Applied after test-filter
test-ignore:
  - rust-v0.53 x rust-v0.54  # Skip tests between v0.53 and v0.54
  - rust-v0.53 x rust-v0.53 (tcp)  # Skip rust self-tests on TCP
```

**Global Default** (`hole-punch-interop/test-selection.yaml`):
```yaml
# Default test selection for full test passes
# Used when no impl-specific test-selection.yaml applies

test-filter: []  # Empty = select all tests

test-ignore:
  - experimental  # Skip tests marked experimental
```

**Selection Logic**:
1. **Full test pass** (no impl filter): Uses `hole-punch-interop/test-selection.yaml`
2. **Impl-specific test pass** (changes in `impl/rust/`): Uses `impl/rust/test-selection.yaml`
3. **Custom CLI args**: Override defaults from test-selection.yaml files
   - `--test-filter` provided → use it, but still apply default `test-ignore` unless also overridden
   - `--test-ignore` provided → use it instead of default
   - Workflow checkboxes can force empty strings to bypass defaults entirely

### 2. test-matrix.txt → test-matrix.yaml

**Before**:
```
rust-v0.53|rust-v0.53|tcp
rust-v0.53|go-v0.43|quic
```

**After**:
```yaml
metadata:
  generatedAt: 2025-11-08T12:34:56Z
  filter: [rust-v0.53]
  ignore: [rust-v0.53 x rust-v0.54]
  totalTests: 42

tests:
  - name: rust-v0.53 x rust-v0.53 (tcp)
    dialer: rust-v0.53
    listener: rust-v0.53
    transport: tcp
    dialerSnapshot: snapshots/b7914e407d.zip
    listenerSnapshot: snapshots/b7914e407d.zip
```

### 3. results.csv → results.yaml

**Before**:
```csv
test_name,exit_code,rtt_ms
rust-v0.53 x go-v0.43 (tcp),0,198
```

**After**:
```yaml
metadata:
  testPass: hole-punch-rust-143022-08-11-2025
  startedAt: 2025-11-08T14:30:22Z
  completedAt: 2025-11-08T14:45:18Z
  duration: 896s

summary:
  total: 42
  passed: 40
  failed: 2
  ignored: 5

tests:
  - name: rust-v0.53 x go-v0.43 (tcp)
    status: pass
    exitCode: 0
    rttMs: 198
    duration: 12.3s
    dockerCompose: docker-compose/a1b2c3d4e5f6.yaml
    dialer:
      version: rust-v0.53
      snapshot: snapshots/b7914e407d.zip
      makefile: makefiles/abc123def4.makefile
      imageID: 1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef
    listener:
      version: go-v0.43
      snapshot: snapshots/abc123def4.zip
      makefile: makefiles/def456abc7.makefile
      imageID: abcdef123456abcdef123456abcdef123456abcdef123456abcdef123456abcd
    logFile: logs/rust-v0.53_x_go-v0.43_tcp.log
```

### 4. dashboard.md → results.md

Same markdown format, renamed for consistency.

---

## Phase 1: Core Infrastructure Setup
**Duration**: 4-5 days
**Objective**: Create the foundational shell script architecture and refactor configuration files

### 1.1 Shell Script Architecture
**Files to Create**:
- `run_tests.sh` - Main test orchestration script
- `scripts/build-images.sh` - Image building with snapshot caching
- `scripts/start-global-services.sh` - Start Redis and Relay
- `scripts/stop-global-services.sh` - Stop Redis and Relay
- `scripts/detect-changes.sh` - Git-based change detection
- `scripts/generate-tests.sh` - Test matrix generation (with caching)
- `scripts/run-single-test.sh` - Execute one test via docker compose
- `scripts/run-tests-parallel.sh` - Parallel test execution
- `scripts/generate-dashboard.sh` - Create results.md from results.yaml
- `scripts/create-snapshot.sh` - Create self-contained test pass archive

**Key Features**:
- Dependency checking (Docker, git, make, bash, yq)
- CPU count auto-detection for worker parallelism
- Command-line argument parsing
- Execution time tracking
- Content-addressed caching at every level
- Test pass snapshot creation

**Success Criteria**:
- ✓ `run_tests.sh --help` displays usage information
- ✓ `run_tests.sh --check-deps` validates all dependencies
- ✓ All scripts are executable and have proper error handling
- ✓ Scripts work on Linux and macOS
- ✓ No Node.js or npm required

---

### 1.2 Configuration Migration (All Files → YAML)
**Files to Convert**:
- `versionsInput.json` → `impls.yaml`
- `impl/<lang>/test-ignore.txt` → `impl/<lang>/test-selection.yaml` (with test-filter and test-ignore lists)
- Generated `test-matrix.txt` → `test-matrix.yaml`
- Generated `results.csv` → `results.yaml`
- Generated `dashboard.md` → `results.md`
- Each `impl/<lang>/<version>/image.json` → `image.yaml`

**New `impls.yaml` Structure**:
```yaml
implementations:
  - id: rust-v0.53
    source:
      type: github
      repo: libp2p/rust-libp2p
      commit: b7914e407da34c99fb76dcc300b3d44b9af97fac
      dockerfile: hole-punching-tests/Dockerfile
    transports: [tcp, quic]
    secureChannels: []
    muxers: []
```

**New `image.yaml` Structure**:
```yaml
imageID: a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2
imageName: rust-v0.53
builtAt: 2025-11-08T12:34:56Z
arch: x86_64
snapshot: snapshots/b7914e407d.zip
makefile: makefiles/abc123def4.makefile
```

**Success Criteria**:
- ✓ All configuration data in YAML format
- ✓ All generated data in YAML format
- ✓ YAML files are valid and parseable with `yq`
- ✓ Documentation explains all YAML structures
- ✓ No JSON or CSV files remain

---

### 1.3 Reorganize Implementation Folders
**Target Structure**:
```
impl/
├── rust/
│   ├── v0.53/
│   │   ├── Makefile
│   │   ├── Dockerfile
│   │   ├── src/
│   │   └── image.yaml (generated)
│   ├── v0.54/
│   ├── test-selection.yaml (was test-ignore.txt)
│   └── README.md
├── go/
│   ├── v0.43/
│   │   └── Makefile
│   ├── test-selection.yaml (was test-ignore.txt)
│   └── README.md
├── impls.yaml (top-level config)
└── test-selection.yaml (default for full test passes)
```

**Migration Tasks**:
- Convert `impl/<lang>/test-ignore.txt` to `test-selection.yaml`
- Create global `hole-punch-interop/test-selection.yaml` with defaults for full test passes
- Add per-language README.md files
- Update Makefiles to generate `image.yaml` instead of `image.json`
- Update Makefiles to use content-addressed caching

**Success Criteria**:
- ✓ All implementations follow consistent folder structure
- ✓ test-selection.yaml files exist for each language and at root level
- ✓ README files document how to add new versions
- ✓ All Makefiles use cached snapshots from `/srv/cache/snapshots/`
- ✓ All Makefiles output image.yaml with cache references

---

## Phase 2: Content-Addressed Caching System
**Duration**: 3-4 days
**Objective**: Implement comprehensive caching for all downloads and generated files

### 2.1 Snapshot Caching (GitHub Downloads)

**Updated Makefile** (`impl/rust/v0.53/Makefile`):

```makefile
image_name := rust-v0.53
commitSha := b7914e407da34c99fb76dcc300b3d44b9af97fac
cache_dir := /srv/cache

all: image.yaml

# Download snapshot with caching
$(cache_dir)/snapshots/$(commitSha).zip:
	@mkdir -p $(cache_dir)/snapshots
	@echo "Downloading snapshot $(commitSha)..."
	@wget -q -O $@ "https://github.com/libp2p/rust-libp2p/archive/$(commitSha).zip"
	@echo "url: https://github.com/libp2p/rust-libp2p/archive/$(commitSha).zip" > $@.metadata
	@echo "downloadedAt: $$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> $@.metadata
	@echo "size: $$(stat -c%s $@ 2>/dev/null || stat -f%z $@)" >> $@.metadata

# Extract snapshot (reuse if already extracted)
rust-libp2p-$(commitSha): $(cache_dir)/snapshots/$(commitSha).zip
	@if [ ! -d $@ ]; then \
		unzip -q $<; \
	fi

# Build Docker image
image.yaml: rust-libp2p-$(commitSha)
	@# Cache this Makefile
	@mkdir -p $(cache_dir)/makefiles
	@MAKEFILE_HASH=$$(sha256sum Makefile | cut -d' ' -f1); \
	cp Makefile $(cache_dir)/makefiles/$$MAKEFILE_HASH.makefile

	@# Build image (Docker layer cache used automatically)
	cd rust-libp2p-$(commitSha) && \
		docker build -f hole-punching-tests/Dockerfile -t $(image_name) .

	@# Generate image.yaml with cache references
	@echo "imageID: $$(docker image inspect $(image_name) -f '{{.Id}}' | cut -d':' -f2)" > $@
	@echo "imageName: $(image_name)" >> $@
	@echo "builtAt: $$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> $@
	@echo "arch: $$(uname -m)" >> $@
	@echo "snapshot: snapshots/$(commitSha).zip" >> $@
	@MAKEFILE_HASH=$$(sha256sum Makefile | cut -d' ' -f1); \
	echo "makefile: makefiles/$$MAKEFILE_HASH.makefile" >> $@

.PHONY: clean
clean:
	rm -rf rust-libp2p-$(commitSha) image.yaml
```

**Success Criteria**:
- ✓ Snapshots downloaded once per commit SHA
- ✓ Subsequent builds reuse cached snapshots
- ✓ Metadata tracked for each download
- ✓ Makefiles cached for reproducibility
- ✓ Works across multiple CI runs

---

### 2.2 Test Matrix Caching

```bash
# scripts/generate-tests.sh

# Load test selection defaults from YAML files
load_test_selection() {
    local impl_path="$1"  # e.g., "impl/rust" or empty for global
    local selection_file

    if [ -n "$impl_path" ] && [ -f "$impl_path/test-selection.yaml" ]; then
        selection_file="$impl_path/test-selection.yaml"
    else
        selection_file="test-selection.yaml"
    fi

    if [ -f "$selection_file" ]; then
        # Extract test-filter list (pipe-separated)
        local filter=$(yq eval '.test-filter | join("|")' "$selection_file")
        # Extract test-ignore list (pipe-separated)
        local ignore=$(yq eval '.test-ignore | join("|")' "$selection_file")
        echo "$filter|$ignore"
    else
        echo "|"  # Empty filter and ignore
    fi
}

generate_test_matrix() {
    local filter="$1"
    local ignore="$2"
    local impl_path="$3"  # Optional: impl path for targeted test runs

    # If filter/ignore not provided via CLI, load from test-selection.yaml
    if [ -z "$filter" ] && [ -z "$ignore" ]; then
        local defaults=$(load_test_selection "$impl_path")
        filter=$(echo "$defaults" | cut -d'|' -f1)
        ignore=$(echo "$defaults" | cut -d'|' -f2)
        echo "Loaded test selection from ${impl_path:-global} test-selection.yaml"
        echo "  Filter: ${filter:-<all>}"
        echo "  Ignore: ${ignore:-<none>}"
    fi

    # Compute cache key from impls.yaml + all test-selection.yaml files + filter + ignore
    local cache_key=$(cat impls.yaml impl/*/test-selection.yaml test-selection.yaml 2>/dev/null | \
        echo "$filter|$ignore" | \
        sha256sum | cut -d' ' -f1)

    local cache_file="/srv/cache/test-matrix/${cache_key}.yaml"

    # Check cache
    if [ -f "$cache_file" ]; then
        echo "Using cached test matrix: ${cache_key:0:8}.yaml"
        cp "$cache_file" test-matrix.yaml
        return 0
    fi

    echo "Generating new test matrix..."

    # Generate test matrix YAML
    cat > test-matrix.yaml <<EOF
metadata:
  generatedAt: $(date -u +%Y-%m-%dT%H:%M:%SZ)
  filter: $filter
  ignore: $ignore
  totalTests: 0

tests: []
EOF

    # Generate test combinations using yq
    local impl_count=$(yq eval '.implementations | length' impls.yaml)

    for ((i=0; i<impl_count; i++)); do
        local dialer_id=$(yq eval ".implementations[$i].id" impls.yaml)
        local dialer_transports=$(yq eval ".implementations[$i].transports[]" impls.yaml)
        local dialer_snapshot=$(yq eval ".implementations[$i].source.commit" impls.yaml)

        for ((j=0; j<impl_count; j++)); do
            local listener_id=$(yq eval ".implementations[$j].id" impls.yaml)
            local listener_transports=$(yq eval ".implementations[$j].transports[]" impls.yaml)
            local listener_snapshot=$(yq eval ".implementations[$j].source.commit" impls.yaml)

            # Find common transports
            for transport in $dialer_transports; do
                if echo "$listener_transports" | grep -q "^${transport}$"; then
                    local test_name="${dialer_id} x ${listener_id} (${transport})"

                    # Apply filters
                    if [ -n "$filter" ] && ! echo "$test_name" | grep -q "$filter"; then
                        continue
                    fi

                    if [ -n "$ignore" ] && echo "$test_name" | grep -q "$ignore"; then
                        continue
                    fi

                    # Add test to YAML
                    yq eval -i ".tests += [{
                        \"name\": \"$test_name\",
                        \"dialer\": \"$dialer_id\",
                        \"listener\": \"$listener_id\",
                        \"transport\": \"$transport\",
                        \"dialerSnapshot\": \"snapshots/${dialer_snapshot}.zip\",
                        \"listenerSnapshot\": \"snapshots/${listener_snapshot}.zip\"
                    }]" test-matrix.yaml
                fi
            done
        done
    done

    # Update total count
    local total=$(yq eval '.tests | length' test-matrix.yaml)
    yq eval -i ".metadata.totalTests = $total" test-matrix.yaml

    # Cache it
    mkdir -p /srv/cache/test-matrix
    cp test-matrix.yaml "$cache_file"

    echo "Generated $total tests (cached as ${cache_key:0:8}.yaml)"
}
```

**Success Criteria**:
- ✓ Test matrices cached by content hash
- ✓ Cache hit when impls.yaml unchanged
- ✓ Filters applied during generation
- ✓ test-selection.yaml patterns applied (test-filter and test-ignore)
- ✓ YAML output is valid and complete

---

### 2.3 Docker-Compose Caching

```bash
# scripts/run-single-test.sh

generate_and_cache_compose_file() {
    local dialer="$1"
    local listener="$2"
    local transport="$3"

    # Get image details
    local dialer_path="impl/${dialer//-/\/}"
    local listener_path="impl/${listener//-/\/}"

    local dialer_image=$(yq eval '.imageID' "${dialer_path}/image.yaml")
    local listener_image=$(yq eval '.imageID' "${listener_path}/image.yaml")
    local router_image=$(yq eval '.imageID' "router/image.yaml")

    # Generate compose content
    local compose_content=$(cat <<EOF
name: test-${dialer//./-}-${listener//./-}-${transport}

services:
  dialer:
    image: ${dialer_image}
    networks: [lan_dialer]
    environment:
      MODE: dial
      TRANSPORT: ${transport}
      REDIS_ADDR: hole-punch-redis:6379
    external_links:
      - hole-punch-redis
      - hole-punch-relay

  listener:
    image: ${listener_image}
    networks: [lan_listener]
    environment:
      MODE: listen
      TRANSPORT: ${transport}
      REDIS_ADDR: hole-punch-redis:6379
    external_links:
      - hole-punch-redis
      - hole-punch-relay

  dialer_router:
    image: ${router_image}
    networks: [hole-punch-network, lan_dialer]
    cap_add: [NET_ADMIN]

  listener_router:
    image: ${router_image}
    networks: [hole-punch-network, lan_listener]
    cap_add: [NET_ADMIN]

networks:
  lan_dialer:
  lan_listener:
  hole-punch-network:
    external: true
EOF
)

    # Compute hash
    local compose_hash=$(echo "$compose_content" | sha256sum | cut -d' ' -f1)
    local cache_file="/srv/cache/docker-compose/${compose_hash}.yaml"

    # Cache it
    mkdir -p /srv/cache/docker-compose
    echo "$compose_content" > "$cache_file"

    # Return relative path
    echo "docker-compose/${compose_hash}.yaml"
}
```

**Success Criteria**:
- ✓ Compose files cached by content hash
- ✓ Identical configs reuse same file
- ✓ Files reference global services
- ✓ Per-test networks isolated
- ✓ Easy to debug (inspect cached files)

---

## Phase 3: Test Execution with Global Services
**Duration**: 3-4 days
**Objective**: Implement hybrid architecture with global Redis/Relay and per-test containers

### 3.1 Global Services Management

**scripts/start-global-services.sh**:
```bash
#!/bin/bash
# Start Redis and Relay containers for all tests

set -e

NETWORK_NAME="hole-punch-network"
REDIS_NAME="hole-punch-redis"
RELAY_NAME="hole-punch-relay"

echo "Starting global services..."

# Create network if doesn't exist
if ! docker network inspect "$NETWORK_NAME" &>/dev/null; then
    docker network create "$NETWORK_NAME"
    echo "✓ Created network: $NETWORK_NAME"
fi

# Start Redis if not running
if ! docker ps -q -f name="$REDIS_NAME" | grep -q .; then
    docker run -d \
        --name "$REDIS_NAME" \
        --network "$NETWORK_NAME" \
        --health-cmd "redis-cli ping | grep PONG" \
        --health-interval 5s \
        --health-timeout 3s \
        --health-retries 5 \
        redis:7-alpine
    echo "✓ Started Redis: $REDIS_NAME"
fi

# Wait for Redis health check
echo -n "Waiting for Redis to be healthy"
while [ "$(docker inspect -f '{{.State.Health.Status}}' "$REDIS_NAME" 2>/dev/null)" != "healthy" ]; do
    echo -n "."
    sleep 1
done
echo " ready!"

# Get relay image
RELAY_IMAGE=$(yq eval '.imageID' rust-relay/image.yaml)

# Start Relay if not running
if ! docker ps -q -f name="$RELAY_NAME" | grep -q .; then
    docker run -d \
        --name "$RELAY_NAME" \
        --network "$NETWORK_NAME" \
        -e REDIS_ADDR="${REDIS_NAME}:6379" \
        "$RELAY_IMAGE"
    echo "✓ Started Relay: $RELAY_NAME"
fi

# Wait for relay to publish addresses to Redis
sleep 2

echo "Global services ready!"
```

**scripts/stop-global-services.sh**:
```bash
#!/bin/bash
# Stop and clean up global services

set -e

echo "Stopping global services..."

docker stop hole-punch-redis hole-punch-relay 2>/dev/null || true
docker rm hole-punch-redis hole-punch-relay 2>/dev/null || true
docker network rm hole-punch-network 2>/dev/null || true

echo "✓ Global services stopped"
```

**Success Criteria**:
- ✓ Redis and Relay start once per test run
- ✓ Services are healthy before tests start
- ✓ Cleanup happens even on error (via trap)
- ✓ Saves 4-6 seconds per test

---

### 3.2 Parallel Test Execution

**scripts/run-tests-parallel.sh**:
```bash
#!/bin/bash
# Run tests in parallel with worker pool

set -e

WORKER_COUNT="${1:-$(nproc)}"
TEST_MATRIX="${2:-test-matrix.yaml}"

echo "Running tests with $WORKER_COUNT workers..."

# Initialize results.yaml
cat > results.yaml <<EOF
metadata:
  testPass: hole-punch-$(date +%H%M%S-%d-%m-%Y)
  startedAt: $(date -u +%Y-%m-%dT%H:%M:%SZ)
  platform: $(uname -m)
  os: $(uname -s)
  workerCount: $WORKER_COUNT

summary:
  total: 0
  passed: 0
  failed: 0
  ignored: 0

tests: []
EOF

# Track running jobs
local job_count=0
local total_tests=$(yq eval '.tests | length' "$TEST_MATRIX")
local completed=0

echo "Total tests to run: $total_tests"

# Process each test
while IFS= read -r test_entry; do
    test_name=$(echo "$test_entry" | yq eval '.name' -)
    dialer=$(echo "$test_entry" | yq eval '.dialer' -)
    listener=$(echo "$test_entry" | yq eval '.listener' -)
    transport=$(echo "$test_entry" | yq eval '.transport' -)

    # Start test in background
    (
        echo "[$(date +%H:%M:%S)] Starting: $test_name"
        bash scripts/run-single-test.sh "$dialer" "$listener" "$transport"
        echo "[$(date +%H:%M:%S)] Completed: $test_name"
    ) &

    job_count=$((job_count + 1))

    # Wait if we've reached worker limit
    if [ $job_count -ge "$WORKER_COUNT" ]; then
        wait -n
        job_count=$((job_count - 1))
        completed=$((completed + 1))
        echo "Progress: $completed / $total_tests completed"
    fi

done < <(yq eval '.tests[]' "$TEST_MATRIX" -o=json -I=0)

# Wait for remaining jobs
echo "Waiting for remaining tests to complete..."
wait

echo "All tests completed!"

# Update summary
local passed=$(yq eval '.tests[] | select(.status == "pass") | .name' results.yaml | wc -l)
local failed=$(yq eval '.tests[] | select(.status == "fail") | .name' results.yaml | wc -l)

yq eval -i ".metadata.completedAt = \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"" results.yaml
yq eval -i ".summary.total = $total_tests" results.yaml
yq eval -i ".summary.passed = $passed" results.yaml
yq eval -i ".summary.failed = $failed" results.yaml
```

**Success Criteria**:
- ✓ Tests run in parallel without conflicts
- ✓ Worker pool limits concurrency
- ✓ Progress tracking works correctly
- ✓ results.yaml updated atomically
- ✓ No race conditions on shared files

---

### 3.3 Single Test Execution

**scripts/run-single-test.sh**:
```bash
#!/bin/bash
# Run a single hole-punch test

set -e

DIALER="$1"
LISTENER="$2"
TRANSPORT="$3"

TEST_NAME="${DIALER} x ${LISTENER} (${TRANSPORT})"
SAFE_NAME=$(echo "$TEST_NAME" | sed 's/[^a-zA-Z0-9-]/_/g')
LOG_FILE="logs/${SAFE_NAME}.log"

mkdir -p logs

START_TIME=$(date +%s)

# Generate and cache docker-compose file
COMPOSE_FILE=$(bash scripts/generate-compose-file.sh "$DIALER" "$LISTENER" "$TRANSPORT")
COMPOSE_PATH="/srv/cache/$COMPOSE_FILE"

# Run test
cd /srv/cache
docker compose -f "$COMPOSE_PATH" up --exit-code-from dialer --abort-on-container-exit > "$LOG_FILE" 2>&1
EXIT_CODE=$?

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Parse RTT from logs
RTT=$(grep -o '{"rtt_to_holepunched_peer_millis":[0-9]*}' "$LOG_FILE" | \
    sed -n 's/.*"rtt_to_holepunched_peer_millis":\([0-9]*\).*/\1/p' | head -1)

# Determine status
if [ $EXIT_CODE -eq 0 ] && [ -n "$RTT" ]; then
    STATUS="pass"
else
    STATUS="fail"
fi

# Get image details
DIALER_IMAGE_YAML="impl/${DIALER//-/\/}/image.yaml"
LISTENER_IMAGE_YAML="impl/${LISTENER//-/\/}/image.yaml"

# Append to results.yaml (with locking)
(
    flock -x 200

    yq eval -i ".tests += [{
        \"name\": \"$TEST_NAME\",
        \"status\": \"$STATUS\",
        \"exitCode\": $EXIT_CODE,
        \"rttMs\": ${RTT:-null},
        \"duration\": \"${DURATION}s\",
        \"dockerCompose\": \"$COMPOSE_FILE\",
        \"dialer\": {
            \"version\": \"$DIALER\",
            \"snapshot\": \"$(yq eval '.snapshot' "$DIALER_IMAGE_YAML")\",
            \"makefile\": \"$(yq eval '.makefile' "$DIALER_IMAGE_YAML")\",
            \"imageID\": \"$(yq eval '.imageID' "$DIALER_IMAGE_YAML")\"
        },
        \"listener\": {
            \"version\": \"$LISTENER\",
            \"snapshot\": \"$(yq eval '.snapshot' "$LISTENER_IMAGE_YAML")\",
            \"makefile\": \"$(yq eval '.makefile' "$LISTENER_IMAGE_YAML")\",
            \"imageID\": \"$(yq eval '.imageID' "$LISTENER_IMAGE_YAML")\"
        },
        \"logFile\": \"$LOG_FILE\"
    }]" results.yaml

) 200>>results.yaml.lock

# Cleanup containers (keep compose file cached)
docker compose -f "$COMPOSE_PATH" down -v > /dev/null 2>&1

exit $EXIT_CODE
```

**Success Criteria**:
- ✓ Test executes correctly
- ✓ Results recorded with full metadata
- ✓ Logs preserved for debugging
- ✓ Compose files cached and reused
- ✓ Parallel-safe result recording

---

## Phase 4: Self-Contained Test Pass Snapshots
**Duration**: 3-4 days
**Objective**: Create reproducible test pass archives

### 4.1 Snapshot Structure

```
hole-punch-rust-143022-08-11-2025.zip
└── hole-punch-rust-143022-08-11-2025/
    ├── report.yaml              # Complete test metadata
    ├── results.md               # Human-readable dashboard
    ├── test-matrix.yaml         # Tests that were run
    ├── output.log               # Complete test pass log
    ├── settings.yaml            # Test run configuration
    ├── re-run.sh                # Script to reproduce this test pass
    ├── scripts/                 # Helper scripts
    │   ├── build-images.sh
    │   ├── start-global-services.sh
    │   ├── stop-global-services.sh
    │   ├── run-single-test.sh
    │   ├── generate-compose-file.sh
    │   └── generate-dashboard.sh
    ├── snapshots/               # GitHub snapshots used
    │   ├── b7914e407d.zip
    │   └── abc123def4.zip
    ├── makefiles/               # Makefiles used
    │   ├── abc123def4.makefile
    │   └── def456abc7.makefile
    ├── docker-compose/          # Generated compose files
    │   ├── a1b2c3d4e5f6.yaml
    │   └── f6e5d4c3b2a1.yaml
    └── logs/                    # Per-test logs
        ├── rust-v0.53_x_go-v0.43_tcp.log
        └── rust-v0.53_x_rust-v0.54_quic.log
```

### 4.2 settings.yaml

```yaml
testPass:
  name: hole-punch-rust-143022-08-11-2025
  kind: rust
  triggeredBy: change in hole-punch-interop/impl/rust/**

filters:
  testFilter: rust-v0.53
  testIgnore: []

system:
  platform: x86_64
  os: Linux
  osVersion: Ubuntu 22.04
  docker: 24.0.5
  dockerCompose: 2.21.0
  yq: 4.35.1
  bash: 5.1.16

execution:
  workerCount: 8
  verbose: true
  cacheDir: /srv/cache

git:
  repository: https://github.com/libp2p/test-plans
  branch: master
  commit: 64a5115abc123def456
  dirtyWorkingTree: false
```

### 4.3 re-run.sh

```bash
#!/bin/bash
# Re-run this exact test pass

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Re-running test pass: hole-punch-rust-143022-08-11-2025"
echo "========================================================="

# Check dependencies
for cmd in docker yq make bash; do
    command -v $cmd >/dev/null 2>&1 || { echo "$cmd required"; exit 1; }
done

# Load settings
WORKER_COUNT=$(yq eval '.execution.workerCount' settings.yaml)
TEST_FILTER=$(yq eval '.filters.testFilter' settings.yaml)

echo "Settings:"
echo "  Worker Count: $WORKER_COUNT"
echo "  Test Filter: $TEST_FILTER"
echo ""

# Set cache dir to local (use our bundled artifacts)
export CACHE_DIR="$SCRIPT_DIR"

# 1. Build images from bundled snapshots
echo "Building Docker images from bundled snapshots..."
for makefile in makefiles/*.makefile; do
    echo "  Building from $(basename $makefile)"
    make -f "$makefile"
done

# 2. Start global services
echo "Starting global services..."
bash scripts/start-global-services.sh

# Ensure cleanup on exit
trap 'bash scripts/stop-global-services.sh' EXIT

# 3. Run tests using bundled compose files
echo "Running tests..."
while IFS= read -r test_entry; do
    test_name=$(echo "$test_entry" | yq eval '.name' -)
    compose_file=$(echo "$test_entry" | yq eval '.dockerCompose' -)

    echo "  Running: $test_name"

    # Run test with bundled compose file
    cd "$SCRIPT_DIR"
    docker compose -f "$compose_file" up --exit-code-from dialer --abort-on-container-exit &

    # Limit parallel jobs
    if [ $(jobs -r | wc -l) -ge "$WORKER_COUNT" ]; then
        wait -n
    fi
done < <(yq eval '.tests[]' test-matrix.yaml -o=json -I=0)

# Wait for all tests
wait

# 4. Generate new results (will differ from original in timestamps)
echo ""
echo "Test pass re-run complete!"
echo ""
echo "Note: Results may differ from original run due to:"
echo "  - Different system state"
echo "  - Network conditions"
echo "  - Docker layer cache state"
```

**Success Criteria**:
- ✓ Snapshot contains everything needed to re-run
- ✓ re-run.sh works on any machine with dependencies
- ✓ Bundled artifacts are sufficient
- ✓ No external downloads required
- ✓ Easy to debug failed test passes

---

### 4.4 Snapshot Creation

**scripts/create-snapshot.sh**:
```bash
#!/bin/bash
# Create self-contained test pass snapshot

set -e

KIND="$1"  # full, rust, go, etc.
TIMESTAMP=$(date +%H%M%S-%d-%m-%Y)
SNAPSHOT_NAME="hole-punch-${KIND}-${TIMESTAMP}"
SNAPSHOT_DIR="/tmp/${SNAPSHOT_NAME}"

echo "Creating test pass snapshot: ${SNAPSHOT_NAME}"

# Create directory structure
mkdir -p "$SNAPSHOT_DIR"/{scripts,snapshots,makefiles,docker-compose,logs}

# Copy main files
cp results.yaml "$SNAPSHOT_DIR/report.yaml"
cp results.md "$SNAPSHOT_DIR/"
cp test-matrix.yaml "$SNAPSHOT_DIR/"
cp output.log "$SNAPSHOT_DIR/"

# Create settings.yaml
create_settings_yaml > "$SNAPSHOT_DIR/settings.yaml"

# Copy scripts
cp scripts/*.sh "$SNAPSHOT_DIR/scripts/"

# Copy cached artifacts referenced in results.yaml
while IFS= read -r test; do
    # Copy dialer snapshot
    snapshot=$(echo "$test" | yq eval '.dialer.snapshot' -)
    if [ -n "$snapshot" ] && [ -f "/srv/cache/$snapshot" ]; then
        mkdir -p "$SNAPSHOT_DIR/$(dirname $snapshot)"
        cp "/srv/cache/$snapshot" "$SNAPSHOT_DIR/$snapshot"
    fi

    # Copy listener snapshot
    snapshot=$(echo "$test" | yq eval '.listener.snapshot' -)
    if [ -n "$snapshot" ] && [ -f "/srv/cache/$snapshot" ]; then
        mkdir -p "$SNAPSHOT_DIR/$(dirname $snapshot)"
        cp "/srv/cache/$snapshot" "$SNAPSHOT_DIR/$snapshot"
    fi

    # Copy makefiles
    makefile=$(echo "$test" | yq eval '.dialer.makefile' -)
    if [ -n "$makefile" ] && [ -f "/srv/cache/$makefile" ]; then
        mkdir -p "$SNAPSHOT_DIR/$(dirname $makefile)"
        cp "/srv/cache/$makefile" "$SNAPSHOT_DIR/$makefile"
    fi

    makefile=$(echo "$test" | yq eval '.listener.makefile' -)
    if [ -n "$makefile" ] && [ -f "/srv/cache/$makefile" ]; then
        mkdir -p "$SNAPSHOT_DIR/$(dirname $makefile)"
        cp "/srv/cache/$makefile" "$SNAPSHOT_DIR/$makefile"
    fi

    # Copy docker-compose
    compose=$(echo "$test" | yq eval '.dockerCompose' -)
    if [ -n "$compose" ] && [ -f "/srv/cache/$compose" ]; then
        mkdir -p "$SNAPSHOT_DIR/$(dirname $compose)"
        cp "/srv/cache/$compose" "$SNAPSHOT_DIR/$compose"
    fi

    # Copy logs
    logfile=$(echo "$test" | yq eval '.logFile' -)
    if [ -n "$logfile" ] && [ -f "$logfile" ]; then
        cp "$logfile" "$SNAPSHOT_DIR/logs/"
    fi
done < <(yq eval '.tests[]' results.yaml -o=json -I=0)

# Create re-run.sh
create_rerun_script > "$SNAPSHOT_DIR/re-run.sh"
chmod +x "$SNAPSHOT_DIR/re-run.sh"

# Create zip archive
echo "Creating zip archive..."
cd /tmp
zip -r "${SNAPSHOT_NAME}.zip" "${SNAPSHOT_NAME}" >/dev/null

# Move to cache
mkdir -p /srv/cache/test-passes
mv "${SNAPSHOT_NAME}.zip" /srv/cache/test-passes/

# Calculate size
SIZE=$(du -h /srv/cache/test-passes/${SNAPSHOT_NAME}.zip | cut -f1)

echo "✓ Snapshot created: /srv/cache/test-passes/${SNAPSHOT_NAME}.zip"
echo "  Size: $SIZE"
echo "  Contains: $(find $SNAPSHOT_DIR -type f | wc -l) files"

# Cleanup temp directory
rm -rf "$SNAPSHOT_DIR"

# Return snapshot path for use in CI
echo "/srv/cache/test-passes/${SNAPSHOT_NAME}.zip"
```

**Success Criteria**:
- ✓ Snapshot contains all necessary artifacts
- ✓ Snapshot is self-contained
- ✓ File size is reasonable
- ✓ Stored in content-addressed cache
- ✓ Easy to download and extract

---

## Phase 5: Results Dashboard Generation
**Duration**: 2 days
**Objective**: Generate human-readable results from YAML

### 5.1 Dashboard Generator

**scripts/generate-dashboard.sh**:
```bash
#!/bin/bash
# Generate results.md from results.yaml

set -e

RESULTS_FILE="${1:-results.yaml}"
OUTPUT_FILE="${2:-results.md}"

echo "Generating dashboard from $RESULTS_FILE..."

# Extract metadata
TEST_PASS=$(yq eval '.metadata.testPass' "$RESULTS_FILE")
STARTED_AT=$(yq eval '.metadata.startedAt' "$RESULTS_FILE")
DURATION=$(yq eval '.metadata.duration' "$RESULTS_FILE")
TOTAL=$(yq eval '.summary.total' "$RESULTS_FILE")
PASSED=$(yq eval '.summary.passed' "$RESULTS_FILE")
FAILED=$(yq eval '.summary.failed' "$RESULTS_FILE")

# Generate header
cat > "$OUTPUT_FILE" <<EOF
# Hole Punch Interoperability Test Results

**Test Pass**: $TEST_PASS
**Started**: $STARTED_AT
**Duration**: $DURATION

## Summary

- **Total Tests**: $TOTAL
- **Passed**: $PASSED ✅
- **Failed**: $FAILED ❌
- **Success Rate**: $(awk "BEGIN {printf \"%.1f\", ($PASSED/$TOTAL)*100}")%

EOF

# Extract unique transports
TRANSPORTS=$(yq eval '.tests[].transport' "$RESULTS_FILE" | sort -u)

# Generate tables grouped by transport
while IFS= read -r transport; do
    echo "## Transport: $transport" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"

    # Get unique implementations for this transport
    IMPLEMENTATIONS=$(yq eval ".tests[] | select(.transport == \"$transport\") | [.dialer, .listener]" "$RESULTS_FILE" -o=json | \
        jq -r '.[]' | sort -u)

    # Generate table header
    echo "| Dialer ↓ \\ Listener → | $(echo "$IMPLEMENTATIONS" | tr '\n' '|') |" >> "$OUTPUT_FILE"
    echo "|---|$(echo "$IMPLEMENTATIONS" | sed 's/.*/---|/g' | tr -d '\n')" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"

    # Generate table rows
    for dialer in $IMPLEMENTATIONS; do
        echo -n "| **$dialer** |" >> "$OUTPUT_FILE"

        for listener in $IMPLEMENTATIONS; do
            # Find test result
            result=$(yq eval ".tests[] | select(.dialer == \"$dialer\" and .listener == \"$listener\" and .transport == \"$transport\")" "$RESULTS_FILE" -o=json 2>/dev/null || echo "{}")

            if [ "$result" = "{}" ]; then
                echo -n " ⚪ |" >> "$OUTPUT_FILE"
            else
                status=$(echo "$result" | jq -r '.status')
                rtt=$(echo "$result" | jq -r '.rttMs // "N/A"')

                if [ "$status" = "pass" ]; then
                    echo -n " 🟢 ${rtt}ms |" >> "$OUTPUT_FILE"
                else
                    echo -n " 🔴 |" >> "$OUTPUT_FILE"
                fi
            fi
        done

        echo "" >> "$OUTPUT_FILE"
    done

    echo "" >> "$OUTPUT_FILE"
done <<< "$TRANSPORTS"

# Add legend
cat >> "$OUTPUT_FILE" <<EOF
## Legend

- 🟢 **Pass** - Test completed successfully with RTT shown
- 🔴 **Fail** - Test failed or timed out
- ⚪ **Not Run** - Test was not executed (filtered or skipped)

## Test Details

Full test results available in \`results.yaml\`

EOF

echo "✓ Dashboard generated: $OUTPUT_FILE"
```

**Success Criteria**:
- ✓ Generates markdown tables from YAML
- ✓ Groups by transport
- ✓ Shows pass/fail/skip clearly
- ✓ Includes RTT values
- ✓ Readable on GitHub

---

## Phase 6: Main Test Orchestrator
**Duration**: 2-3 days
**Objective**: Tie everything together

### 6.1 run_tests.sh

```bash
#!/bin/bash
# Main test orchestration script

set -e

# Defaults
CACHE_DIR="${CACHE_DIR:-/srv/cache}"
TEST_FILTER="${TEST_FILTER:-}"
TEST_IGNORE="${TEST_IGNORE:-}"
WORKER_COUNT="${WORKER_COUNT:-$(nproc)}"
KIND="full"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --test-filter) TEST_FILTER="$2"; shift 2 ;;
        --test-ignore) TEST_IGNORE="$2"; shift 2 ;;
        --workers) WORKER_COUNT="$2"; shift 2 ;;
        --cache-dir) CACHE_DIR="$2"; shift 2 ;;
        --kind) KIND="$2"; shift 2 ;;
        --check-deps) check_dependencies; exit 0 ;;
        --help) show_help; exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Auto-detect kind from git changes
if [ -z "$KIND" ] || [ "$KIND" = "auto" ]; then
    if git diff --name-only HEAD~1 | grep -q 'impl/rust/'; then
        KIND="rust"
    elif git diff --name-only HEAD~1 | grep -q 'impl/go/'; then
        KIND="go"
    else
        KIND="full"
    fi
fi

# Determine impl path for test-selection.yaml loading
IMPL_PATH=""
if [ "$KIND" != "full" ]; then
    IMPL_PATH="impl/${KIND}"
fi

# Note: TEST_FILTER and TEST_IGNORE will be loaded from test-selection.yaml
# by generate-tests.sh if not provided via CLI

export CACHE_DIR

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Hole Punch Interoperability Test Suite                   ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Test Pass: hole-punch-${KIND}"
echo "Cache Dir: $CACHE_DIR"
echo "Workers: $WORKER_COUNT"
[ -n "$TEST_FILTER" ] && echo "Filter: $TEST_FILTER"
[ -n "$TEST_IGNORE" ] && echo "Ignore: $TEST_IGNORE"
echo ""

START_TIME=$(date +%s)

# 1. Build images
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Building Docker images..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
bash scripts/build-images.sh --filter="$TEST_FILTER"

# 2. Generate test matrix
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Generating test matrix..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
bash scripts/generate-tests.sh --filter="$TEST_FILTER" --ignore="$TEST_IGNORE" --impl-path="$IMPL_PATH"

# 3. Start global services
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Starting global services..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
bash scripts/start-global-services.sh
trap 'bash scripts/stop-global-services.sh' EXIT INT TERM

# 4. Run tests in parallel
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Running tests..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
bash scripts/run-tests-parallel.sh "$WORKER_COUNT" test-matrix.yaml | tee output.log

# 5. Generate results
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Generating results dashboard..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
bash scripts/generate-dashboard.sh

# 6. Create snapshot
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Creating test pass snapshot..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
SNAPSHOT_PATH=$(bash scripts/create-snapshot.sh "$KIND")

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Display results
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Test Pass Complete!                                       ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Duration: ${DURATION}s"
echo "Snapshot: $SNAPSHOT_PATH"
echo ""
cat results.md

# Exit with failure if any tests failed
FAILED=$(yq eval '.summary.failed' results.yaml)
if [ "$FAILED" -gt 0 ]; then
    echo ""
    echo "❌ $FAILED test(s) failed"
    exit 1
fi

echo ""
echo "✅ All tests passed!"
exit 0
```

**Success Criteria**:
- ✓ Orchestrates entire test flow
- ✓ Clear progress output
- ✓ Error handling at each step
- ✓ Auto-detects test kind from git changes
- ✓ Creates complete snapshot
- ✓ Exit code reflects test results

---

## Phase 7: CI/CD Integration
**Duration**: 2-3 days
**Objective**: Update GitHub Actions workflows

### 7.1 Workflow Structure

**Per-Language Workflow** (`.github/workflows/hole-punch-interop-rust.yml`):
```yaml
name: Hole Punch Interop - Rust

on:
  pull_request:
    paths:
      - 'hole-punch-interop/impl/rust/**'
      - 'hole-punch-interop/impls.yaml'
      - 'hole-punch-interop/scripts/**'
  push:
    branches: [master]
    paths:
      - 'hole-punch-interop/impl/rust/**'
  workflow_dispatch:
    inputs:
      use_custom_filter:
        description: 'Use custom test-filter (overrides test-selection.yaml)'
        type: boolean
        default: false
      test_filter:
        description: 'Custom test-filter (pipe-separated substrings)'
        type: string
        default: ''
      use_custom_ignore:
        description: 'Use custom test-ignore (overrides test-selection.yaml)'
        type: boolean
        default: false
      test_ignore:
        description: 'Custom test-ignore (pipe-separated substrings)'
        type: string
        default: ''

jobs:
  test-rust:
    runs-on: [self-hosted, linux, x64, ephemeral]
    steps:
      - uses: actions/checkout@v4

      - name: Install yq
        run: |
          sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
          sudo chmod +x /usr/local/bin/yq

      - name: Run tests
        run: |
          cd hole-punch-interop

          # Build arguments
          ARGS="--kind rust --workers 8 --cache-dir /srv/cache"

          # Add custom test-filter if checkbox enabled
          if [ "${{ inputs.use_custom_filter }}" = "true" ]; then
            ARGS="$ARGS --test-filter '${{ inputs.test_filter }}'"
          fi

          # Add custom test-ignore if checkbox enabled
          if [ "${{ inputs.use_custom_ignore }}" = "true" ]; then
            ARGS="$ARGS --test-ignore '${{ inputs.test_ignore }}'"
          fi

          ./run_tests.sh $ARGS

      - name: Upload snapshot
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: test-pass-snapshot
          path: /srv/cache/test-passes/*.zip
          retention-days: 30

      - name: Update README
        if: github.event_name == 'push'
        run: |
          cd hole-punch-interop

          # Inject results into README
          tail -n +5 results.md > /tmp/results_content.md
          sed -i '/<!--INTEROP_DASHBOARD_START-->/,/<!--INTEROP_DASHBOARD_END-->/c\<!--INTEROP_DASHBOARD_START-->\n'"$(cat /tmp/results_content.md | sed 's/[\/&]/\\&/g' | sed ':a;N;$!ba;s/\n/\\n/g')"'\n<!--INTEROP_DASHBOARD_END-->' README.md

          # Commit if changed
          if git diff --quiet README.md; then
            echo "No changes to README"
          else
            git config user.name "github-actions[bot]"
            git config user.email "github-actions[bot]@users.noreply.github.com"
            git add README.md
            git commit -m "chore: update hole-punch results [skip ci]"
            git push
          fi
```

**Success Criteria**:
- ✓ Workflows trigger on path changes
- ✓ Tests run with caching enabled
- ✓ Snapshots uploaded as artifacts
- ✓ README updated on master push
- ✓ No Node.js setup required

---

## Phase 8: Documentation & Migration
**Duration**: 2-3 days
**Objective**: Complete documentation and clean up old code

### 8.1 Remove Old Code

**Files to Delete**:
- All TypeScript/JavaScript files
- `package.json`, `package-lock.json`, `tsconfig.json`
- `node_modules/`
- `helpers/cache.ts`
- `src/` directory (TypeScript sources)
- `compose-spec/`
- All `.txt` files (converted to `.yaml`)
- All `.json` files (converted to `.yaml`)
- All `.csv` files (converted to `.yaml`)

**Files to Keep**:
- Pure bash scripts in `scripts/`
- YAML configuration files
- Makefiles
- Docker-related files

**Success Criteria**:
- ✓ No TypeScript/JavaScript remains
- ✓ No JSON files remain
- ✓ Only bash + YAML + Makefiles
- ✓ Git history preserved

---

### 8.2 Comprehensive Documentation

**README.md Structure**:
```markdown
# Hole Punching Interoperability Tests

## Quick Start

```bash
# Check dependencies
./run_tests.sh --check-deps

# Run all tests
./run_tests.sh

# Run filtered tests
./run_tests.sh --filter rust-v0.53
```

## Dependencies

- **Docker**: Container runtime and builder
- **git**: Version control
- **make**: Build orchestration
- **bash** (4.0+): Shell scripting
- **yq**: YAML processor

## Architecture

[Detailed architecture explanation]

## Content-Addressed Caching

All downloads and generated files are cached in `/srv/cache/`:

- `snapshots/<commitSha>.zip` - GitHub snapshots
- `makefiles/<sha256>.makefile` - Versioned Makefiles
- `test-matrix/<sha256>.yaml` - Test matrices
- `docker-compose/<sha256>.yaml` - Compose files
- `test-passes/*.zip` - Complete test run archives

## Test Pass Snapshots

Each test run creates a self-contained snapshot that can be re-run:

```bash
unzip hole-punch-rust-143022-08-11-2025.zip
cd hole-punch-rust-143022-08-11-2025
./re-run.sh
```

## Adding a New Implementation

[Step-by-step guide]

## CI/CD Integration

[Workflow explanation]

## Troubleshooting

[Common issues and solutions]

<!--INTEROP_DASHBOARD_START-->
[Auto-generated results]
<!--INTEROP_DASHBOARD_END-->
```

**Success Criteria**:
- ✓ README is complete and accurate
- ✓ All features documented
- ✓ Examples tested and working
- ✓ Troubleshooting guide comprehensive

---

## Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Test Execution Time | -40% | Benchmark before/after |
| Cache Hit Rate | >90% | CI logs |
| Snapshot Creation Time | <60s | Script timing |
| Snapshot Size | <500MB | Zip file size |
| Code Complexity | -50% | Lines of code |
| Reproducibility | 100% | Snapshot re-run success rate |

---

## Timeline Summary

| Phase | Duration | Dependencies |
|-------|----------|--------------|
| 1. Core Infrastructure | 4-5 days | None |
| 2. Content-Addressed Caching | 3-4 days | Phase 1 |
| 3. Test Execution (Hybrid) | 3-4 days | Phase 1, 2 |
| 4. Test Pass Snapshots | 3-4 days | Phase 3 |
| 5. Results Dashboard | 2 days | Phase 3 |
| 6. Main Orchestrator | 2-3 days | Phase 3, 4, 5 |
| 7. CI/CD Integration | 2-3 days | Phase 6 |
| 8. Documentation & Cleanup | 2-3 days | Phase 7 |

**Total Estimated Duration**: 21-30 days (4-6 weeks)

---

## Conclusion

This redesign achieves all 17 original requirements plus significant additional improvements:

### Original Requirements (All Met):
1. ✅ Single shell script driver (`run_tests.sh`)
2. ✅ Modular helper scripts in `scripts/`
3. ✅ Idempotent execution
4. ✅ Configurable caching (content-addressed)
5. ✅ Caches all artifacts intelligently
6. ✅ Preserves Makefiles (enhanced with caching)
7. ✅ All JSON → YAML conversion
8. ✅ Concurrent test execution
9. ✅ Preserves docker-compose for tests
10. ✅ Preserves Redis coordination
11. ✅ Shared Redis + Relay setup/teardown
12. ✅ Simpler, more maintainable architecture
13. ✅ Change detection like transport-interop
14. ✅ Unified configuration in `impls.yaml`
15. ✅ Comprehensive documentation
16. ✅ Easy external repo integration
17. ✅ README injection like transport-interop

### Additional Improvements:
- **Content-addressed caching**: All downloads and generated files cached by hash
- **Hybrid architecture**: Global services + per-test containers (4 instead of 6)
- **YAML everywhere**: Consistent, readable format for all data
- **Self-contained snapshots**: Complete test pass archives that can be re-run anywhere
- **Better debugging**: Full logs, cached artifacts, reproducible runs
- **CI efficiency**: 90%+ cache hit rate, minimal redundant work
- **Zero Node.js**: Pure bash + make + docker + yq
- **Radical simplification**: ~50% less code, dramatically easier to understand

**Result**: A production-ready, highly cacheable, completely reproducible test system that is simple to understand, debug, and maintain.
