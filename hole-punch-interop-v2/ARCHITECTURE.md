# Architecture Documentation

## Design Principles

### 1. Simplicity First
- Pure bash scripts (no Node.js, Python, or Make)
- Single source of truth: `impls.yaml`
- Minimal dependencies: bash, git, docker, yq, wget, unzip
- No build systems (Makefiles removed)

### 2. Content-Addressed Storage
All artifacts are named by their content hash for automatic deduplication:

```
/srv/cache/
├── snapshots/<commit-sha>.zip     # Git SHA-1 (40 chars)
├── test-matrix/<sha256>.yaml      # SHA-256 (64 chars)
└── test-passes/<timestamp>.tar.gz # Timestamped snapshots
```

### 3. Hybrid Architecture

**Global Services** (started once, shared across all tests):
- Redis container for coordination
- Relay container for hole punching
- Shared Docker network: `hole-punch-network`

**Per-Test Services** (isolated, ephemeral):
- Dialer container (implementation under test)
- Listener container (implementation under test)
- Dialer Router (NAT simulation)
- Listener Router (NAT simulation)
- Isolated networks: `lan_dialer`, `lan_listener`

Benefits:
- Reduces container startup overhead (~4-6s per test)
- Tests remain isolated via unique networks
- Global services persist across all tests

### 4. Hash Functions

Following the "Opinions and Assumptions" from the plan:

| Type | Algorithm | Length | Prefix Stripped |
|------|-----------|--------|-----------------|
| Git snapshots | SHA-1 | 40 hex | N/A (native Git) |
| Docker images | SHA-256 | 64 hex | Yes (`sha256:`) |
| Cache keys | SHA-256 | 64 hex | N/A (generated) |

**Why strip prefixes?**
- Cleaner file names and identifiers
- Easier string manipulation in bash
- Each context knows its hash algorithm
- Modern systems don't need redundant prefixes

## Component Architecture

### Core Scripts

```
scripts/
├── build-images.sh           # Build all Docker images
├── check-dependencies.sh     # Verify system requirements
├── generate-tests.sh         # Generate test matrix
├── start-global-services.sh  # Start Redis + Relay
├── stop-global-services.sh   # Stop global services
├── run-single-test.sh        # Execute one test
├── generate-dashboard.sh     # Create results.md
└── create-snapshot.sh        # Create test snapshot
```

### Main Orchestrator

`run_tests.sh` coordinates the full pipeline:

```
1. Check dependencies (bash, docker, git, yq, etc.)
2. Build images (with caching)
3. Generate test matrix (with caching)
4. Start global services
5. Run tests in parallel (xargs)
6. Collect results → results.yaml
7. Generate dashboard → results.md
8. Optional: Create snapshot
9. Cleanup (trap on exit)
```

## Data Flow

```
impls.yaml
    ↓
[build-images.sh]
    ↓
Docker Images + image.yaml files
    ↓
[generate-tests.sh] + test-selection.yaml
    ↓
test-matrix.yaml (cached)
    ↓
[run-single-test.sh] × N (parallel)
    ↓
results.yaml + logs/
    ↓
[generate-dashboard.sh]
    ↓
results.md + results.html
    ↓
[create-snapshot.sh] (optional)
    ↓
self-contained .tar.gz
```

## Configuration Files

### impls.yaml (Source of Truth)

Defines all implementations and their properties:

```yaml
implementations:
  - id: rust-v0.53
    source:
      type: github
      repo: libp2p/rust-libp2p
      commit: b7914e407da34c99fb76dcc300b3d44b9af97fac
      dockerfile: hole-punching-tests/Dockerfile
    transports:
      - tcp
      - quic
```

**Used by:**
- `build-images.sh` - to build Docker images
- `generate-tests.sh` - to create test combinations

### test-selection.yaml Files

Define default test filters at different scopes:

**Global** (`test-selection.yaml`):
```yaml
test-filter: []  # All tests
test-ignore:
  - experimental
```

**Per-Language** (`impls/rust/test-selection.yaml`):
```yaml
test-filter:
  - rust-v0.53
test-ignore:
  - rust-v0.53 x rust-v0.53 (tcp)
```

**Priority:**
1. CLI args (`--test-filter`, `--test-ignore`)
2. Language-specific test-selection.yaml
3. Global test-selection.yaml

### test-matrix.yaml (Generated)

Output of test generation with full test list:

```yaml
metadata:
  generatedAt: 2025-11-09T12:34:56Z
  filter: [rust-v0.53]
  ignore: []
  totalTests: 42

tests:
  - name: rust-v0.53 x rust-v0.53 (tcp)
    dialer: rust-v0.53
    listener: rust-v0.53
    transport: tcp
    dialerSnapshot: snapshots/b7914e407d.zip
    listenerSnapshot: snapshots/b7914e407d.zip
```

### results.yaml (Output)

Structured test results:

```yaml
metadata:
  testPass: hole-punch-rust-143022-08-11-2025
  startedAt: 2025-11-09T14:30:22Z
  completedAt: 2025-11-09T14:45:18Z
  duration: 896s
  platform: x86_64
  os: Linux
  workerCount: 8

summary:
  total: 42
  passed: 40
  failed: 2

tests:
  - name: rust-v0.53 x go-v0.43 (tcp)
    status: pass
    exitCode: 0
    duration: 12s
    dialer: rust-v0.53
    listener: go-v0.43
    transport: tcp
```

## Caching Strategy

### 1. Snapshot Caching

**Cache Key:** Git commit SHA (40 chars)

```bash
snapshot_file="$CACHE_DIR/snapshots/$commit.zip"

if [ ! -f "$snapshot_file" ]; then
    wget -O "$snapshot_file" "https://github.com/$repo/archive/$commit.zip"
fi
```

**Benefits:**
- Never re-download same commit
- Identical across all test runs
- Permanent (commits don't change)

### 2. Test Matrix Caching

**Cache Key:** SHA-256(impls.yaml + test-selection.yaml + filters)

```bash
cache_key=$(cat impls.yaml impls/*/test-selection.yaml | \
    echo "$TEST_FILTER|$TEST_IGNORE" | \
    sha256sum | cut -d' ' -f1)

cache_file="$CACHE_DIR/test-matrix/${cache_key}.yaml"
```

**Benefits:**
- Identical config = cached matrix
- Fast test runs when config unchanged
- Automatic invalidation on config change

### 3. Docker Layer Caching

Uses Docker's built-in layer cache:

```bash
docker build -f $dockerfile -t $image_name .
```

**Benefits:**
- Automatic by Docker
- Layer deduplication
- No manual cache management needed

## Parallel Execution

Tests run in parallel using bash job control:

```bash
run_test() {
    local index=$1
    # Extract test details from test-matrix.yaml
    # Run test
    # Append to results (with file locking)
}

export -f run_test

seq 0 $((test_count - 1)) | \
    xargs -P "$WORKER_COUNT" -I {} bash -c 'run_test {}'
```

**File Locking:**
```bash
(
    flock -x 200
    cat >> results.yaml.tmp <<EOF
  - name: $name
    status: $status
EOF
) 200>/tmp/results.lock
```

## Test Isolation

Each test runs in complete isolation:

### Networks

- **Global**: `hole-punch-network` (connects to Redis/Relay)
- **Per-Test**: `lan_dialer`, `lan_listener` (isolated from other tests)

### Containers

```yaml
services:
  dialer:
    networks:
      - lan_dialer
    environment:
      - REDIS_ADDR=hole-punch-redis:6379

  listener:
    networks:
      - lan_listener
    environment:
      - REDIS_ADDR=hole-punch-redis:6379
```

Both can reach Redis (via global network attachment to routers), but tests are isolated from each other.

## Reproducibility: Snapshot System

### Snapshot Contents

```
hole-punch-rust-143022-08-11-2025/
├── re-run.sh              # Executable reproduction script
├── README.md              # Instructions
├── settings.yaml          # Metadata
├── impls.yaml             # Implementation config
├── test-selection.yaml    # Test selection
├── test-matrix.yaml       # Generated matrix
├── results.yaml           # Original results
├── results.md             # Dashboard
├── impls/                 # Implementation directories
├── scripts/               # All bash scripts
├── snapshots/             # Source code archives
├── docker-compose/        # Generated compose files
└── logs/                  # Test logs
```

### re-run.sh

```bash
#!/bin/bash
cd "$(dirname "$0")"
export CACHE_DIR="$(pwd)"

# Build images from local snapshots
bash scripts/build-images.sh

# Start services
bash scripts/start-global-services.sh

# Re-run tests
for each test in test-matrix.yaml; do
    bash scripts/run-single-test.sh ...
done

# Cleanup
bash scripts/stop-global-services.sh
```

### Portability

Snapshots work on any machine with:
- bash 4.0+
- docker 20.10+
- git 2.0+
- yq 4.0+
- wget, unzip

No network access needed (all source code included).

## Error Handling

All scripts use strict error handling:

```bash
set -euo pipefail
```

- `set -e` - Exit on error
- `set -u` - Error on undefined variable
- `set -o pipefail` - Catch errors in pipes

### Cleanup on Exit

```bash
cleanup() {
    echo "Stopping services..."
    bash scripts/stop-global-services.sh
}
trap cleanup EXIT
```

Ensures global services are always stopped, even on error.

## Performance Optimizations

1. **Parallel Test Execution**
   - Configurable worker pool
   - Default: CPU count

2. **Content-Addressed Caching**
   - Never re-download same content
   - Instant cache hits

3. **Docker Layer Caching**
   - Automatic layer reuse
   - Faster rebuilds

4. **Hybrid Architecture**
   - Start Redis/Relay once
   - Saves 4-6s per test

5. **Snapshot Reuse**
   - Download once, use forever
   - Supports offline testing

## Extensibility

### Adding New Languages

1. Create `impls/<language>/` directory
2. Add `test-selection.yaml`
3. Add implementations to `impls.yaml`
4. Run tests

### Adding New Transports

1. Update `transports` in `impls.yaml`
2. Test matrix auto-generates combinations
3. No code changes needed

### Custom Test Logic

Modify `scripts/run-single-test.sh` to change:
- Container configuration
- Environment variables
- Network topology
- Timeout behavior

## Comparison to Previous Design

| Aspect | Old (TypeScript) | New (Bash) |
|--------|------------------|------------|
| Dependencies | Node.js, npm, TypeScript, make | bash, docker, git, yq |
| Build System | Makefiles + npm scripts | Pure bash |
| Caching | TypeScript + S3 | Bash + local files |
| Config Format | JSON | YAML |
| Results Format | CSV | YAML |
| Test Selection | TypeScript logic | YAML + bash |
| Snapshot System | None | Full tar.gz archives |
| Parallel Execution | Custom TypeScript | xargs + bash |

**Lines of Code:**
- Old: ~2000 lines TypeScript
- New: ~1300 lines bash

**Simplification achieved!**
