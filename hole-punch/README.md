# Hole Punch Interoperability Tests

Pure-bash implementation of NAT hole punching interoperability tests for libp2p implementations using the DCUtR (Direct Connection Upgrade through Relay) protocol.

## What This Test Does

Hole punch tests verify that libp2p implementations can establish direct peer-to-peer connections through NAT using:
- **Initial relay connection**: Peers connect through a relay server
- **DCUtR protocol**: Peers coordinate to establish direct connection
- **NAT traversal**: Peers simultaneously open connections through their respective NATs
- **Connection upgrade**: Traffic switches from relay to direct connection

## What It Measures

- **Compatibility**: Can dialer and listener establish direct connections through NAT?
- **Protocol Support**: Which transport/secure/muxer combinations support hole punching?
- **Success Rate**: Percentage of successful hole punch attempts
- **Connection Time**: Time to establish direct connection

## Network Topology

Each test creates an isolated network with:
- **WAN Network**: Relay server and two NAT routers
- **Two LAN Networks**: Dialer and listener behind their respective NATs
- **Redis Coordination**: Shared service for multiaddr exchange

Simulated network delays:
- Relay: 25ms latency
- NAT Routers: 100ms latency each

## When Tests Run

- **On Pull Requests**: Tests implementations changed in the PR
- **Daily Full Run**: Complete test matrix (all implementations)
- **Manual Trigger**: Via GitHub Actions workflow dispatch

## How to Run Tests

### Prerequisites

Check dependencies:
```bash
./run_tests.sh --check-deps
```

Required: bash 4.0+, docker 20.10+, yq 4.0+, wget, unzip

### Basic Usage

```bash
# Run all tests
./run_tests.sh --cache-dir /srv/cache --workers 4

# Run specific implementation
./run_tests.sh --test-select "linux" --workers 4

# Skip specific tests
./run_tests.sh --test-ignore "quic" --workers 2

# Enable debug logging
./run_tests.sh --debug --workers 2
```

## Test Filtering

### Basic Filtering

Use pipe-separated patterns:

```bash
# Select multiple implementations
./run_tests.sh --test-select "linux|chromium"

# Ignore specific protocols
./run_tests.sh --test-ignore "quic|tcp"

# Combine select and ignore
./run_tests.sh --test-select "linux" --test-ignore "quic"
```

### Alias Expansion

Use `~alias` syntax for convenient test selection:

```bash
# Expand to all rust versions
./run_tests.sh --test-select "~rust"

# Exclude all rust versions
./run_tests.sh --test-ignore "~rust"

# Select everything EXCEPT rust
./run_tests.sh --test-select "!~rust"
```

**Available aliases** are defined in `impls.yaml` under `test-aliases`.

### Best Practice: Limit to Specific Alias

To test ONLY implementations in an alias (not just tests containing the alias pattern):

```bash
# Test ONLY rust implementations
./run_tests.sh --test-select '~rust' --test-ignore '!~rust'

# Test ONLY linux implementations
./run_tests.sh --test-select '~linux' --test-ignore '!~linux'
```

**How it works**:
1. `--test-select '~rust'` includes all rust implementations
2. `--test-ignore '!~rust'` ignores everything that is NOT rust
3. The intersection gives you exactly the rust tests

## Snapshot Generation

### Creating Snapshots

Generate a self-contained, reproducible test snapshot:

```bash
./run_tests.sh --snapshot
```

This creates a snapshot directory in `/srv/cache/test-runs/hole-punch-HHMMSS-DD-MM-YYYY/` containing:
- Complete test configuration (impls.yaml, test-matrix.yaml)
- All test results (results.yaml, results.md)
- All source code snapshots
- All Docker images (saved as tar.gz)
- All test scripts and network configurations
- Re-run script for exact reproduction

### Reproducing from Snapshot

```bash
cd /srv/cache/test-runs/hole-punch-HHMMSS-DD-MM-YYYY/
./re-run.sh

# Force rebuild images from snapshots
./re-run.sh --force-rebuild
```

## Downloading Snapshots

Snapshots are available as GitHub Actions artifacts:

1. Go to [Actions tab](https://github.com/libp2p/test-plans/actions)
2. Select the workflow run
3. Download artifacts from the "Artifacts" section
4. Extract and run `./re-run.sh`

## Script Documentation

For detailed information about the scripts used in this test suite, see:
- **[docs/SCRIPTS_DESIGN.md](../docs/SCRIPTS_DESIGN.md)** - Comprehensive script documentation
- **[ARCHITECTURE.md](ARCHITECTURE.md)** - Network topology and design details

## Additional Options

```bash
# List all available implementations
./run_tests.sh --list-impls

# List tests that would be run (without running them)
./run_tests.sh --test-select "linux" --list-tests

# Force rebuild all Docker images
./run_tests.sh --force-image-rebuild

# Force regenerate test matrix (bypass cache)
./run_tests.sh --force-matrix-rebuild

# Check dependencies only
./run_tests.sh --check-deps

# Skip confirmation prompt
./run_tests.sh -y
```

## 

<!-- TEST_RESULTS_START -->
# Hole Punch Interoperability Test Results

## Test Pass: `hole-punch-050051-16-12-2025`

**Summary:**
- **Total Tests:** 5
- **Passed:** ✅ 5
- **Failed:** ❌ 0
- **Pass Rate:** 100.0%

**Environment:**
- **Platform:** x86_64
- **OS:** Linux
- **Workers:** 8
- **Duration:** 17s

**Timestamps:**
- **Started:** 2025-12-16T05:00:51Z
- **Completed:** 2025-12-16T05:01:08Z

---

## Test Results

| Test | Dialer | Listener | Transport | Status | Duration |
|------|--------|----------|-----------|--------|----------|
| linux x linux (tcp, noise, yamux) [dr: linux, rly: linux, lr: linux] | linux | linux | tcp | ✅ | 11s |
| linux x linux (tcp, tls, mplex) [dr: linux, rly: linux, lr: linux] | linux | linux | tcp | ✅ | 12s |
| linux x linux (tcp, tls, yamux) [dr: linux, rly: linux, lr: linux] | linux | linux | tcp | ✅ | 13s |
| linux x linux (quic-v1) [dr: linux, rly: linux, lr: linux] | linux | linux | quic-v1 | ✅ | 14s |
| linux x linux (tcp, noise, mplex) [dr: linux, rly: linux, lr: linux] | linux | linux | tcp | ✅ | 15s |

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

*Generated: 2025-12-16T05:01:08Z*
<!-- TEST_RESULTS_END -->

