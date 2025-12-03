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
└── test-runs/hole-punch-<timestamp>/  # Self-contained test pass directories
```

### 3. Hybrid Architecture

**Global Services** (started once, shared across all tests):
- **Redis** container for test coordination with key-based isolation
- Shared Docker network: `hole-punch-network` (renamed to redis-network in compose)

**Per-Test Services** (isolated, ephemeral):
- **Relay** container - libp2p relay server on WAN network (10.x.x.65)
  - Publishes multiaddr to Redis under `relay:{TEST_KEY}`
  - Each test gets fresh relay instance
- **Dialer Router** (NAT) - dual-homed gateway with 100ms delay
  - WAN side: 10.x.x.66
  - LAN side: 10.x.x.93 (gateway for dialer)
  - Performs SNAT: 10.x.x.92/30 → 10.x.x.66
- **Listener Router** (NAT) - dual-homed gateway with 100ms delay
  - WAN side: 10.x.x.67
  - LAN side: 10.x.x.129 (gateway for listener)
  - Performs SNAT: 10.x.x.128/30 → 10.x.x.67
- **Dialer** container - implementation under test (10.x.x.94)
  - Connects to Redis for coordination
  - Fetches relay multiaddr dynamically
- **Listener** container - implementation under test (10.x.x.130)
  - Connects to Redis for coordination
  - Fetches relay multiaddr dynamically
- Three isolated networks per test:
  - `wan`: 10.x.x.64/29 (public internet simulation, 6 IPs)
  - `lan-dialer`: 10.x.x.92/30 (private network, 2 IPs)
  - `lan-listener`: 10.x.x.128/30 (private network, 2 IPs)

**Benefits:**
- Realistic three-tier network topology (WAN + 2 LANs)
- True NAT simulation with automatic SNAT
- Fixed IP addresses for predictable routing
- Non-conflicting subnets via two-octet derivation
- Complete test isolation via Redis key namespacing + unique subnets
- Safe parallel execution (65,536 unique subnet combinations)
- Per-test relay ensures no state leakage

### Network Topology Detail

```
┌─────────────────────── WAN: 10.{S1}.{S2}.64/29 ──────────────────────────┐
│                                                                            │
│   ┌─────────────┐         ┌──────────┐         ┌─────────────┐          │
│   │ dialer-rtr  │         │  relay   │         │ listener-rtr│          │
│   │ .66         │◄───────►│  .65     │◄───────►│ .67         │          │
│   └──────┬──────┘         └────┬─────┘         └──────┬──────┘          │
│          │ NAT                  │                      │ NAT              │
└──────────┼──────────────────────┼──────────────────────┼─────────────────┘
           │                      │                      │
           │ LAN-Dialer           │ redis-network        │ LAN-Listener
           │ 10.{S1}.{S2}.92/30   │                      │ 10.{S1}.{S2}.128/30
           │ GW: .93              │                      │ GW: .129
           │                      │                      │
    ┌──────▼──────┐        ┌─────▼──────┐       ┌───────▼──────┐
    │   dialer    ├────────►│   Redis    │◄──────┤   listener   │
    │   .94       │        │  (Global)  │       │   .130       │
    └─────────────┘        └────────────┘       └──────────────┘
```

**Connection Flow:**
1. Test starts with unique TEST_KEY (hash of test name)
2. All containers receive TEST_KEY via environment variable
3. Relay publishes transport-specific multiaddr to `relay:{TEST_KEY}:{transport}` in Redis
4. Listener fetches relay multiaddr, connects to relay, publishes peer ID to `listener:{TEST_KEY}:peer_id`
5. Dialer fetches relay multiaddr and listener peer ID from Redis
6. Dialer connects to relay and initiates relay circuit to listener
7. DCutR protocol automatically negotiates hole punch over relay connection
8. Both peers attempt simultaneous connection through their NATs
9. NAT routers perform SNAT and add 100ms delay
10. Successful hole punch establishes direct P2P connection
11. Test coordination continues with namespaced Redis keys
12. Keys auto-expire after test completion (5 minute TTL)

**Network Delays:**
- Relay network interface: 25ms (applied at relay eth0)
- Each NAT router: 50ms per interface (100ms total RTT through router)
- Total RTT for relayed connection: ~350ms
  - Dialer → Router (50ms) → WAN (0ms) → Relay (25ms + 25ms) → WAN (0ms) → Router (50ms) → Listener
  - 50 + 25 + 25 + 50 = 150ms one-way, 300ms RTT
- Total RTT for direct connection: ~200ms after successful hole punch
  - Dialer → Router (50ms) → WAN (0ms) → Router (50ms) → Listener
  - 50 + 50 = 100ms one-way, 200ms RTT

### 4. Redis Key Isolation

Each test uses a unique key prefix to isolate Redis operations:

**Key Generation:**
```bash
TEST_KEY=$(echo -n "$TEST_NAME" | sha256sum | cut -c1-10)
# Example: "rust-v0.53 x rust-v0.53 (tcp)" → "a4be363ecc"
```

**Key Namespace:**
```
relay:{TEST_KEY}:tcp          # Relay TCP multiaddr (set by relay)
relay:{TEST_KEY}:quic         # Relay QUIC multiaddr (set by relay)
listener:{TEST_KEY}:peer_id   # Listener's peer ID (set by listener)
ready:{TEST_KEY}:dialer       # Dialer ready signal (optional)
ready:{TEST_KEY}:listener     # Listener ready signal (optional)
result:{TEST_KEY}:dialer      # Dialer test result (optional)
result:{TEST_KEY}:listener    # Listener test result (optional)
```

**DCutR Signaling Flow:**
1. Relay starts and publishes multiaddr to Redis:
   ```
   RPUSH relay:{TEST_KEY}:tcp "/ip4/10.x.x.65/tcp/4001/p2p/{relay_peer_id}"
   EXPIRE relay:{TEST_KEY}:tcp 300

   RPUSH relay:{TEST_KEY}:quic "/ip4/10.x.x.65/udp/4001/quic-v1/p2p/{relay_peer_id}"
   EXPIRE relay:{TEST_KEY}:quic 300
   ```

2. Listener starts, fetches relay multiaddr, and publishes its peer ID:
   ```
   # Fetch relay address (blocks until available)
   BLPOP relay:{TEST_KEY}:{transport} 30

   # Connect to relay, then publish own peer ID
   RPUSH listener:{TEST_KEY}:peer_id "{listener_peer_id}"
   EXPIRE listener:{TEST_KEY}:peer_id 300
   ```

3. Dialer fetches relay multiaddr and listener peer ID:
   ```
   # Fetch relay address
   BLPOP relay:{TEST_KEY}:{transport} 30

   # Fetch listener peer ID
   BLPOP listener:{TEST_KEY}:peer_id 30

   # Construct relay circuit address
   {relay_addr}/p2p-circuit/p2p/{listener_peer_id}

   # Connect via relay circuit - DCutR happens automatically
   ```

4. DCutR protocol exchanges observed addresses and coordinates hole punch
5. Direct P2P connection established after successful hole punch

**Benefits:**
- Complete isolation between concurrent tests
- No message crosstalk or race conditions
- Safe parallel test execution
- Automatic key expiration (5 minute TTL)

### 5. Two-Octet Subnet Isolation

Each test uses **two octets** from TEST_KEY for subnet derivation, providing 65,536 unique subnet sets:

**Derivation Algorithm:**
```bash
TEST_KEY=$(echo -n "$TEST_NAME" | sha256sum | cut -c1-10)

# Extract first 4 hex chars, add offset of 32 to avoid common ranges
SUBNET_ID_1=$(( (16#${TEST_KEY:0:2} + 32) % 256 ))
SUBNET_ID_2=$(( (16#${TEST_KEY:2:2} + 32) % 256 ))

WAN="10.${SUBNET_ID_1}.${SUBNET_ID_2}.64/29"
LAN_DIALER="10.${SUBNET_ID_1}.${SUBNET_ID_2}.92/30"
LAN_LISTENER="10.${SUBNET_ID_1}.${SUBNET_ID_2}.128/30"
```

**Why the +32 offset?**
- Most enterprise/home 10.x networks use: 10.0.0.x, 10.1.x.x, 10.10.x.x
- With +32 offset, our ranges start at 10.32.32.x
- Dramatically reduces overlap with existing networks
- Values wrap around via modulo 256 for even distribution

**IP Address Formulas:**
```bash
RELAY_IP="10.${SUBNET_ID_1}.${SUBNET_ID_2}.65"
DIALER_ROUTER_WAN="10.${SUBNET_ID_1}.${SUBNET_ID_2}.66"
DIALER_ROUTER_LAN="10.${SUBNET_ID_1}.${SUBNET_ID_2}.93"
LISTENER_ROUTER_WAN="10.${SUBNET_ID_1}.${SUBNET_ID_2}.67"
LISTENER_ROUTER_LAN="10.${SUBNET_ID_1}.${SUBNET_ID_2}.129"
DIALER="10.${SUBNET_ID_1}.${SUBNET_ID_2}.94"
LISTENER="10.${SUBNET_ID_1}.${SUBNET_ID_2}.130"
```

**Subnet Size Rationale:**
- WAN: /29 (6 usable IPs) - accommodates 3 hosts + future expansion
- LAN-Dialer: /30 (2 usable IPs) - minimal allocation (router + client)
- LAN-Listener: /30 (2 usable IPs) - minimal allocation (router + client)

**Collision Probability:**
- Total combinations: 65,536 (256 × 256)
- SHA-256 hash ensures even distribution
- For typical parallel execution:
  - 4 tests: 0.009% collision probability
  - 16 tests: 0.02% collision probability
  - 100 tests: 0.76% collision probability
- If collision occurs: Docker fails immediately (fail-fast)

### 6. Hash Functions

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

Defines all implementations, relay, and router configurations:

```yaml
# Test aliases for easy test selection
test-aliases:
  - alias: "rust"
    value: "rust-v0.53"

# Relay configuration - global libp2p relay server
relay:
  id: rust-relay-v0.53
  source:
    type: github
    repo: libp2p/rust-libp2p
    commit: b7914e407da34c99fb76dcc300b3d44b9af97fac
    dockerfile: hole-punching-tests/relay/Dockerfile
    buildContext: hole-punching-tests
  image: hole-punch-relay
  delayMs: 25

# Router/NAT configuration - simulates network address translation
routers:
  - id: nat-router-v1
    source:
      type: github
      repo: libp2p/rust-libp2p
      commit: b7914e407da34c99fb76dcc300b3d44b9af97fac
      dockerfile: hole-punching-tests/router/Dockerfile
      buildContext: hole-punching-tests
    image: hole-punch-router
    delayMs: 100

# Implementations to test
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

**Sections:**
- `test-aliases`: Reusable patterns for test selection (e.g., `~rust` expands to all rust versions)
- `relay`: Global relay server configuration (image, source, network delay)
- `routers`: NAT/router configuration for simulating network conditions
- `implementations`: Test implementations with supported transports

**Used by:**
- `build-images.sh` - to build Docker images for relay, routers, and implementations
- `generate-tests.sh` - to create test combinations from implementations
- `start-global-services.sh` - to start relay with correct configuration
- `run-single-test.sh` - to configure NAT routers for each test

### test-selection.yaml

Defines default test filters:

```yaml
test-select: []  # All tests by default
test-ignore:
  - experimental
  - flaky
```

**Priority:**
1. CLI args (`--test-select`, `--test-ignore`)
2. Global test-selection.yaml

**Note:** Per-language test-selection.yaml files are not used - test filtering is done at runtime via CLI args.

### test-matrix.yaml (Generated)

Output of test generation with full test list:

```yaml
metadata:
  generatedAt: 2025-11-09T12:34:56Z
  filter: rust-v0.53
  ignore: ""
  totalTests: 42
  ignoredTests: 3
  debug: false

tests:
  - name: rust-v0.53 x rust-v0.53 (tcp)
    dialer: rust-v0.53
    listener: rust-v0.53
    transport: tcp
    dialerSnapshot: snapshots/b7914e407d.zip
    listenerSnapshot: snapshots/b7914e407d.zip

ignoredTests:
  - name: rust-v0.53 x rust-v0.53 (experimental)
    dialer: rust-v0.53
    listener: rust-v0.53
    transport: experimental
    dialerSnapshot: snapshots/b7914e407d.zip
    listenerSnapshot: snapshots/b7914e407d.zip
```

### results.yaml (Output)

Structured test results:

```yaml
metadata:
  testPass: hole-punch-143022-09-11-2025
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
    handshakePlusOneRTTMs: 45.2
    pingRTTMs: 3.8
```

**Performance Metrics** (optional, extracted from logs):
- `handshakePlusOneRTTMs` - Handshake + one round trip time in milliseconds
- `pingRTTMs` - Ping round trip time in milliseconds

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

**Cache Key:** SHA-256(impls.yaml + test-selection.yaml + filter + ignore + debug)

```bash
cache_key=$({
    cat impls.yaml test-selection.yaml 2>/dev/null
    echo "$TEST_FILTER||$TEST_IGNORE||$DEBUG"
} | sha256sum | cut -d' ' -f1)

cache_file="$CACHE_DIR/test-matrix/${cache_key}.yaml"
```

**Double-pipe delimiter** (`||`) prevents ambiguous cache collisions:
- `"a|b" + "|c"` vs `"a" + "|b|c"` would be ambiguous with single pipe
- `"a||b" + "||c"` vs `"a" + "||b||c"` are clearly different

**Benefits:**
- Identical config = cached matrix
- Fast test runs when config unchanged
- Automatic invalidation on config change
- No cache collision edge cases

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

Each test pass creates a self-contained directory:

```
/srv/cache/test-runs/hole-punch-143022-09-11-2025/
├── re-run.sh              # Executable reproduction script
├── README.md              # Complete instructions
├── settings.yaml          # Snapshot metadata
├── impls.yaml             # Implementation config (captured)
├── test-selection.yaml    # Test selection (captured)
├── test-matrix.yaml       # Generated matrix
├── results.yaml           # Original test results
├── results.md             # Markdown dashboard
├── impls/                 # Implementation directories (copied)
├── scripts/               # All bash scripts (copied)
├── snapshots/             # GitHub source code archives
├── docker-images/         # Saved Docker images (tar.gz)
├── docker-compose/        # Generated compose files
└── logs/                  # Test execution logs
```

### re-run.sh

Enhanced reproduction script with validation:

```bash
#!/bin/bash
cd "$(dirname "$0")"
export CACHE_DIR="$(pwd)"

# Create re-run subdirectory with timestamp
RERUN_DIR="re-runs/$(date +%Y%m%d-%H%M%S)"
export TEST_PASS_DIR="$RERUN_DIR"

# Validate all GitHub snapshots are present
# (exits if any are missing)

# Load Docker images from snapshot
if [ -d docker-images ]; then
    for image in docker-images/*.tar.gz; do
        gunzip -c "$image" | docker load
    done
else
    bash scripts/build-images.sh
fi

# Start global services
bash scripts/start-global-services.sh

# Re-run tests in parallel
seq 0 $((test_count - 1)) | xargs -P "$WORKER_COUNT" -I {} bash -c 'run_test {}'

# Collect results to re-runs/TIMESTAMP/results.yaml

# Cleanup
bash scripts/stop-global-services.sh
```

**Key Features:**
- Validates snapshot integrity before running
- Loads saved Docker images for true reproducibility
- Saves new results to timestamped re-runs/ subdirectory
- Supports multiple re-runs from same snapshot

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

### 1. Parallel Test Execution
- Configurable worker pool via `--workers`
- Default: CPU count (`nproc`)
- File locking for safe concurrent writes

### 2. Content-Addressed Caching
- Never re-download same content
- Instant cache hits
- Double-pipe delimiter prevents collisions

### 3. Docker Layer Caching
- Automatic layer reuse
- Faster rebuilds
- Built-in Docker optimization

### 4. Hybrid Architecture
- Start Redis/Relay once
- Saves 4-6s per test
- Tests remain isolated

### 5. Snapshot Reuse
- Download once, use forever
- Supports offline testing
- Reproducible builds

### 6. Script Optimizations

**generate-tests.sh** - 10-30x faster:
- Pre-loads all implementations into associative arrays (O(1) lookups)
- Eliminates 400+ yq calls → ~20 yq calls
- Native bash string matching instead of grep
- ~60 seconds → 2-5 seconds

**generate-dashboard.sh** - 30-80x faster:
- Bulk TSV extraction (single yq call instead of 600+)
- Hash maps for O(1) test result lookups
- Replaced O(n³) algorithm with O(n²) + O(1)
- ~40,600 yq calls → 1 yq call
- ~10 seconds → 0.1-0.2 seconds

**Test Display** - 100-200x faster:
- Bulk name extraction instead of per-test queries
- 2 yq calls instead of 200+

**Overall Improvement:**
- Test orchestration overhead reduced by 10-40x
- Full test run: 5-15 minutes typical (4 workers, 20-50 tests)

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
