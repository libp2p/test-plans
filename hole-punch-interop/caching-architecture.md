# Hole-Punch Interop: Comprehensive Caching & Snapshot Architecture

## Overview

This document describes a comprehensive caching and reproducibility system for the hole-punch-interop tests. The design maximizes caching for speed, enables complete debugging, and creates self-contained test pass snapshots that can be re-run on any machine.

---

## Opinions and Assumptions

### Hash Functions and Identifiers

This architecture uses content-addressed storage throughout but **omits hash algorithm prefixes** from all identifiers for simplicity.

**Git Commit SHAs (SHA-1, 40 hex chars)**:
- Format: `b7914e407da34c99fb76dcc300b3d44b9af97fac`
- Used for: Repository snapshot filenames in `/srv/cache/snapshots/`
- Extracted via: `git rev-parse HEAD`

**Docker Image IDs (SHA-256, 64 hex chars)**:
- Format: `1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef`
- Used for: Container image identification in results.yaml and image.yaml
- Extracted via: `docker image inspect <name> -f '{{.Id}}' | cut -d':' -f2`
- **Note**: The `sha256:` prefix is always stripped

**Content Cache Keys (SHA-256, 64 hex chars)**:
- Format: `abc123def456...` (full 64 characters)
- Used for: Makefiles, test-matrix, docker-compose filenames
- Generated via: `sha256sum <file> | cut -d' ' -f1`

**Rationale**: Hash algorithm prefixes add no value in this system. Each identifier type has a known hash function, and omitting prefixes simplifies string handling, file naming, and YAML parsing.

---

## Cache Directory Structure

All cached data lives under `/srv/cache` with content-addressed naming:

```
/srv/cache/
├── snapshots/
│   ├── <commitSha>.zip              # GitHub repo snapshots (e.g., b7914e407d.zip)
│   └── <commitSha>.zip.metadata     # Download metadata (URL, timestamp, size)
├── makefiles/
│   └── <sha256>.makefile            # Cached Makefiles
├── docker-images/
│   └── <imageID>.tar.gz             # Exported Docker images (optional optimization)
├── test-matrix/
│   └── <sha256>.yaml                # Generated test matrices
├── docker-compose/
│   └── <sha256>.yaml                # Generated docker-compose files
└── test-passes/
    └── hole-punch-<kind>-<timestamp>.zip  # Complete test pass snapshots
```

---

## File Format Changes

### 1. test-ignore.txt → test-selection.yaml

**Before** (`impl/rust/test-ignore.txt`):
```
rust-v0.53|rust-v0.54  # Skip tests between these versions
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
- Full test pass (no impl filter): Uses `hole-punch-interop/test-selection.yaml`
- Impl-specific test pass (changes in `impl/rust/`): Uses `impl/rust/test-selection.yaml`
- Custom CLI args override defaults:
  - `--test-filter` provided → use it, apply default `test-ignore` unless also overridden
  - `--test-ignore` provided → use it instead of default
  - Workflow checkboxes can force empty strings to bypass defaults

### 2. test-matrix.txt → test-matrix.yaml

**Before** (`test-matrix.txt`):
```
rust-v0.53|rust-v0.53|tcp
rust-v0.53|go-v0.43|quic
```

**After** (`test-matrix.yaml`):
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

  - name: rust-v0.53 x go-v0.43 (quic)
    dialer: rust-v0.53
    listener: go-v0.43
    transport: quic
    dialerSnapshot: snapshots/b7914e407d.zip
    listenerSnapshot: snapshots/abc123def4.zip
```

### 3. results.csv → results.yaml

**Before** (`results.csv`):
```csv
test_name,exit_code,rtt_ms
rust-v0.53 x go-v0.43 (tcp),0,198
```

**After** (`results.yaml`):
```yaml
metadata:
  testPass: hole-punch-rust-143022-08-11-2025
  startedAt: 2025-11-08T14:30:22Z
  completedAt: 2025-11-08T14:45:18Z
  duration: 896s
  platform: x86_64
  os: Linux
  workerCount: 8

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
    dialerRouter:
      imageID: router123456router123456router123456router123456router123456router12
    listenerRouter:
      imageID: router123456router123456router123456router123456router123456router12
    relay:
      imageID: relay789abcrelay789abcrelay789abcrelay789abcrelay789abcrelay789abc
    logFile: logs/rust-v0.53_x_go-v0.43_tcp.log

  - name: rust-v0.53 x rust-v0.54 (quic)
    status: fail
    exitCode: 1
    rttMs: null
    duration: 8.7s
    dockerCompose: docker-compose/f6e5d4c3b2a1.yaml
    error: "Connection timeout after 30s"
    logFile: logs/rust-v0.53_x_rust-v0.54_quic.log
```

### 4. dashboard.md → results.md

Same markdown format, just renamed for consistency with `results.yaml`.

---

## Hybrid Architecture: Global Services

### Global Services (Started Once)

```bash
# scripts/start-global-services.sh

# 1. Start Redis (coordination bus)
docker network create hole-punch-network
docker run -d \
    --name hole-punch-redis \
    --network hole-punch-network \
    redis:7-alpine

# 2. Start Relay (shared relay server)
docker run -d \
    --name hole-punch-relay \
    --network hole-punch-network \
    -e REDIS_ADDR=hole-punch-redis:6379 \
    ${RELAY_IMAGE}
```

### Per-Test Services (via docker-compose)

Simplified compose file with only 4 containers:

```yaml
# docker-compose/<sha256>.yaml
services:
  dialer:
    image: ${DIALER_IMAGE}
    networks: [lan_dialer]
    environment:
      MODE: dial
      TRANSPORT: ${TRANSPORT}
      REDIS_ADDR: hole-punch-redis:6379
    external_links:
      - hole-punch-redis
      - hole-punch-relay

  listener:
    image: ${LISTENER_IMAGE}
    networks: [lan_listener]
    environment:
      MODE: listen
      TRANSPORT: ${TRANSPORT}
      REDIS_ADDR: hole-punch-redis:6379
    external_links:
      - hole-punch-redis
      - hole-punch-relay

  dialer_router:
    image: ${ROUTER_IMAGE}
    networks: [hole-punch-network, lan_dialer]
    cap_add: [NET_ADMIN]

  listener_router:
    image: ${ROUTER_IMAGE}
    networks: [hole-punch-network, lan_listener]
    cap_add: [NET_ADMIN]

networks:
  lan_dialer:
  lan_listener:
  hole-punch-network:
    external: true
```

---

## Content-Addressed Caching

### Snapshot Caching (Makefiles)

**Updated Makefile** (`impl/rust/v0.53/Makefile`):

```makefile
image_name := rust-v0.53
commitSha := b7914e407da34c99fb76dcc300b3d44b9af97fac
cache_dir := /srv/cache

all: image.yaml

# Download snapshot with caching
snapshot: $(cache_dir)/snapshots/$(commitSha).zip

$(cache_dir)/snapshots/$(commitSha).zip:
	@mkdir -p $(cache_dir)/snapshots
	@echo "Downloading snapshot $(commitSha)..."
	@wget -q -O $@ "https://github.com/libp2p/rust-libp2p/archive/$(commitSha).zip"
	@echo "url: https://github.com/libp2p/rust-libp2p/archive/$(commitSha).zip" > $@.metadata
	@echo "downloadedAt: $$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> $@.metadata
	@echo "size: $$(stat -f%z $@ 2>/dev/null || stat -c%s $@)" >> $@.metadata

# Extract snapshot (reuse if already extracted)
rust-libp2p-$(commitSha): $(cache_dir)/snapshots/$(commitSha).zip
	@if [ ! -d $@ ]; then \
		unzip -q $(cache_dir)/snapshots/$(commitSha).zip; \
	fi

# Build Docker image
image.yaml: rust-libp2p-$(commitSha)
	@# Cache this Makefile
	@mkdir -p $(cache_dir)/makefiles
	@MAKEFILE_HASH=$$(sha256sum Makefile | cut -d' ' -f1); \
	cp Makefile $(cache_dir)/makefiles/$$MAKEFILE_HASH.makefile

	@# Build image
	cd rust-libp2p-$(commitSha) && \
		docker build -f hole-punching-tests/Dockerfile -t $(image_name) .

	@# Generate image.yaml
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

### Test Matrix Caching

```bash
# scripts/generate-tests.sh

generate_test_matrix() {
    local filter="$1"
    local ignore="$2"

    # Compute cache key from impls.yaml + test-selection.yaml files
    local cache_key=$(cat impls.yaml impl/*/test-selection.yaml test-selection.yaml 2>/dev/null | \
        sha256sum | cut -d' ' -f1)

    local cache_file="/srv/cache/test-matrix/${cache_key}.yaml"

    # Check cache
    if [ -f "$cache_file" ]; then
        echo "Using cached test matrix: $cache_file"
        cp "$cache_file" test-matrix.yaml
        return 0
    fi

    # Generate test matrix
    generate_matrix_content > test-matrix.yaml

    # Cache it
    mkdir -p /srv/cache/test-matrix
    cp test-matrix.yaml "$cache_file"
}
```

### Docker-Compose Caching

```bash
# scripts/run-single-test.sh

generate_compose_file() {
    local dialer="$1"
    local listener="$2"
    local transport="$3"

    # Generate compose content
    local compose_content=$(cat <<EOF
services:
  dialer:
    image: ${dialer_image}
    networks: [lan_dialer]
    # ... rest of config
EOF
)

    # Compute hash
    local compose_hash=$(echo "$compose_content" | sha256sum | cut -d' ' -f1)
    local cache_file="/srv/cache/docker-compose/${compose_hash}.yaml"

    # Cache it
    mkdir -p /srv/cache/docker-compose
    echo "$compose_content" > "$cache_file"

    # Return path
    echo "$cache_file"
}
```

---

## Test Pass Snapshot Structure

Each test run creates a self-contained snapshot:

```
hole-punch-rust-143022-08-11-2025.zip
└── hole-punch-rust-143022-08-11-2025/
    ├── report.yaml                    # Main test report
    ├── results.md                     # Human-readable dashboard
    ├── test-matrix.yaml               # Tests that were run
    ├── output.log                     # Complete test pass log
    ├── settings.yaml                  # Test run configuration
    ├── re-run.sh                      # Script to re-run this test pass
    ├── scripts/                       # Helper scripts
    │   ├── build-images.sh
    │   ├── start-global-services.sh
    │   ├── stop-global-services.sh
    │   ├── run-single-test.sh
    │   └── generate-dashboard.sh
    ├── snapshots/                     # GitHub snapshots used
    │   ├── b7914e407d.zip
    │   └── abc123def4.zip
    ├── makefiles/                     # Makefiles used
    │   ├── abc123def4.makefile
    │   └── def456abc7.makefile
    ├── docker-compose/                # Generated compose files
    │   ├── a1b2c3d4e5f6.yaml
    │   └── f6e5d4c3b2a1.yaml
    └── logs/                          # Per-test logs
        ├── rust-v0.53_x_go-v0.43_tcp.log
        └── rust-v0.53_x_rust-v0.54_quic.log
```

### settings.yaml

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

### re-run.sh

```bash
#!/bin/bash
# Re-run this exact test pass

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Re-running test pass: hole-punch-rust-143022-08-11-2025"
echo "=================================================="

# Check dependencies
command -v docker >/dev/null 2>&1 || { echo "docker required"; exit 1; }
command -v yq >/dev/null 2>&1 || { echo "yq required"; exit 1; }
command -v make >/dev/null 2>&1 || { echo "make required"; exit 1; }

# Load settings
WORKER_COUNT=$(yq eval '.execution.workerCount' settings.yaml)
TEST_FILTER=$(yq eval '.filters.testFilter' settings.yaml)

echo "Settings:"
echo "  Worker Count: $WORKER_COUNT"
echo "  Test Filter: $TEST_FILTER"
echo ""

# 1. Build all images from cached snapshots
echo "Building Docker images from snapshots..."
bash scripts/build-images.sh --from-snapshot

# 2. Start global services
echo "Starting global services (Redis, Relay)..."
bash scripts/start-global-services.sh

# Ensure cleanup on exit
trap 'bash scripts/stop-global-services.sh' EXIT

# 3. Run tests using cached docker-compose files
echo "Running tests..."
while IFS= read -r test_entry; do
    test_name=$(echo "$test_entry" | yq eval '.name' -)
    compose_file=$(echo "$test_entry" | yq eval '.dockerCompose' -)

    echo "  Running: $test_name"
    bash scripts/run-single-test.sh "$compose_file" &

    # Limit parallel jobs
    if [ $(jobs -r | wc -l) -ge "$WORKER_COUNT" ]; then
        wait -n
    fi
done < <(yq eval '.tests[]' test-matrix.yaml -o=json -I=0)

# Wait for all tests to complete
wait

# 4. Generate results
echo "Generating results dashboard..."
bash scripts/generate-dashboard.sh

echo ""
echo "Test pass complete!"
echo "Results: results.yaml"
echo "Dashboard: results.md"
```

---

## Test Pass Creation

```bash
# scripts/create-snapshot.sh

create_test_pass_snapshot() {
    local kind="$1"  # full, rust, go, etc.
    local timestamp=$(date +%H%M%S-%d-%m-%Y)
    local snapshot_name="hole-punch-${kind}-${timestamp}"
    local snapshot_dir="/tmp/${snapshot_name}"

    echo "Creating test pass snapshot: ${snapshot_name}"

    # Create directory structure
    mkdir -p "$snapshot_dir"/{scripts,snapshots,makefiles,docker-compose,logs}

    # Copy main files
    cp report.yaml "$snapshot_dir/"
    cp results.md "$snapshot_dir/"
    cp test-matrix.yaml "$snapshot_dir/"
    cp output.log "$snapshot_dir/"

    # Create settings.yaml
    create_settings_yaml > "$snapshot_dir/settings.yaml"

    # Copy scripts
    cp scripts/*.sh "$snapshot_dir/scripts/"

    # Copy cached artifacts used in this test pass
    while IFS= read -r test; do
        # Copy snapshots
        snapshot=$(echo "$test" | yq eval '.dialer.snapshot' -)
        if [ -n "$snapshot" ] && [ -f "/srv/cache/$snapshot" ]; then
            cp "/srv/cache/$snapshot" "$snapshot_dir/snapshots/"
        fi

        # Copy makefiles
        makefile=$(echo "$test" | yq eval '.dialer.makefile' -)
        if [ -n "$makefile" ] && [ -f "/srv/cache/$makefile" ]; then
            cp "/srv/cache/$makefile" "$snapshot_dir/makefiles/"
        fi

        # Copy docker-compose
        compose=$(echo "$test" | yq eval '.dockerCompose' -)
        if [ -n "$compose" ] && [ -f "/srv/cache/$compose" ]; then
            cp "/srv/cache/$compose" "$snapshot_dir/docker-compose/"
        fi

        # Copy logs
        logfile=$(echo "$test" | yq eval '.logFile' -)
        if [ -n "$logfile" ] && [ -f "$logfile" ]; then
            cp "$logfile" "$snapshot_dir/logs/"
        fi
    done < <(yq eval '.tests[]' results.yaml -o=json -I=0)

    # Create re-run.sh
    create_rerun_script > "$snapshot_dir/re-run.sh"
    chmod +x "$snapshot_dir/re-run.sh"

    # Create zip archive
    cd /tmp
    zip -r "${snapshot_name}.zip" "${snapshot_name}" >/dev/null

    # Move to cache
    mkdir -p /srv/cache/test-passes
    mv "${snapshot_name}.zip" /srv/cache/test-passes/

    echo "Snapshot created: /srv/cache/test-passes/${snapshot_name}.zip"
    echo "Size: $(du -h /srv/cache/test-passes/${snapshot_name}.zip | cut -f1)"

    # Cleanup temp directory
    rm -rf "$snapshot_dir"
}
```

---

## Complete Test Flow

```bash
# run_tests.sh (main orchestrator)

#!/bin/bash
set -e

# Parse arguments
TEST_FILTER="${TEST_FILTER:-}"
TEST_IGNORE="${TEST_IGNORE:-}"
WORKER_COUNT="${WORKER_COUNT:-$(nproc)}"
KIND="full"  # full, rust, go, etc.

# Detect kind from git changes
if [ -n "$(git diff --name-only HEAD~1 | grep 'impl/rust/')" ]; then
    KIND="rust"
    TEST_FILTER="${TEST_FILTER:-rust}"
elif [ -n "$(git diff --name-only HEAD~1 | grep 'impl/go/')" ]; then
    KIND="go"
    TEST_FILTER="${TEST_FILTER:-go}"
fi

echo "Starting test pass: hole-punch-${KIND}"
echo "=========================================="

# 1. Build images
echo "Building Docker images..."
bash scripts/build-images.sh --filter="$TEST_FILTER"

# 2. Generate test matrix (with caching)
echo "Generating test matrix..."
bash scripts/generate-tests.sh --filter="$TEST_FILTER" --ignore="$TEST_IGNORE"

# 3. Start global services
echo "Starting global services..."
bash scripts/start-global-services.sh
trap 'bash scripts/stop-global-services.sh' EXIT

# 4. Run tests in parallel
echo "Running tests..."
bash scripts/run-tests-parallel.sh --workers="$WORKER_COUNT" | tee output.log

# 5. Generate results
echo "Generating results..."
bash scripts/generate-dashboard.sh

# 6. Create snapshot
echo "Creating test pass snapshot..."
bash scripts/create-snapshot.sh "$KIND"

echo ""
echo "Test pass complete!"
cat results.md
```

---

## Benefits Summary

### Caching Benefits
- **Snapshot downloads**: Only downloaded once per commit SHA
- **Test matrices**: Regenerated only when impls.yaml changes
- **Docker-compose files**: Reused across test runs with same config
- **Makefiles**: Versioned and tracked
- **Docker layer cache**: Automatic via Docker

### Debugging Benefits
- **Complete logs**: Every test has detailed logs
- **Reproducible**: Snapshot contains everything needed to re-run
- **Traceable**: Every artifact is content-addressed
- **Portable**: Works on any machine with basic dependencies

### CI Benefits
- **Fast subsequent runs**: Heavy caching at every level
- **Auditable**: Every test pass is archived
- **Debuggable**: Failed test passes can be re-run locally
- **Efficient**: No redundant downloads or builds

### Maintenance Benefits
- **YAML everywhere**: Consistent, readable configuration
- **Content-addressed**: No naming collisions
- **Self-documenting**: Snapshots contain all context
- **Simple**: Pure bash, no complex frameworks
