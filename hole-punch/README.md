# Hole Punch Interoperability Tests v2

Simplified, pure-bash implementation of hole punching interoperability tests for libp2p.

## Architecture

This test suite uses:
- **Pure bash** orchestration (no Node.js/npm)
- **YAML** for all configuration and data files
- **Content-addressed caching** under `/srv/cache/`
- **Hybrid architecture**: Global Redis + per-test relay/NAT/router containers
- **Two-octet subnet isolation**: Each test uses unique 10.x.x.x subnets (65,536 combinations)
- **Self-contained snapshots** for reproducibility

### Network Topology

Each test creates an **isolated three-tier network** with **unique subnets** derived from the test name hash:

**Subnet Derivation:**
```bash
TEST_KEY=$(echo -n "$TEST_NAME" | sha256sum | cut -c1-10)
SUBNET_ID_1=$(( (16#${TEST_KEY:0:2} + 32) % 256 ))
SUBNET_ID_2=$(( (16#${TEST_KEY:2:2} + 32) % 256 ))
```

**Network Allocation:**
- WAN: `10.${SUBNET_ID_1}.${SUBNET_ID_2}.64/29` (6 usable IPs)
- LAN-Dialer: `10.${SUBNET_ID_1}.${SUBNET_ID_2}.92/30` (2 usable IPs)
- LAN-Listener: `10.${SUBNET_ID_1}.${SUBNET_ID_2}.128/30` (2 usable IPs)

**Example:** Test "rust-v0.53 x rust-v0.53 (tcp)"
- TEST_KEY: `a4be363ecc`
- Hex: `a4` (164) + 32 = 196, `be` (190) + 32 = 222
- SUBNET_IDs: 196, 222
- WAN: `10.196.222.64/29`
- LAN-Dialer: `10.196.222.92/30`
- LAN-Listener: `10.196.222.128/30`

```
┌─────────────────── WAN: 10.{S1}.{S2}.64/29 ─────────────────┐
│                                                             │
│   ┌─────────────┐      ┌──────────┐      ┌──────────────┐   │
│   │ dialer-rtr  │      │  relay   │      │ listener-rtr │   │
│   │ .66         │◄────►│  .65     │◄────►│ .67          │   │
│   └──────┬──────┘      └────┬─────┘      └───────┬──────┘   │
│          │ NAT              │                    │ NAT      │
└──────────┼──────────────────┼────────────────────┼──────────┘
           │                  │                    │
           │ LAN-Dialer       │ redis-network      │ LAN-Listener
           │ 10.{S1}.{S2}.92/30                    │ 10.{S1}.{S2}.128/30
           │ GW: .93          │                    │ GW: .129
           │                  │                    │
    ┌──────▼──────┐      ┌────▼────┐       ┌───────▼──────┐
    │   dialer    ├─────►│  Redis  │◄──────┤   listener   │
    │   .94       │      │ (Global)│       │   .130       │
    └─────────────┘      └─────────┘       └──────────────┘
```

**Components:**
- **Relay**: Per-test libp2p relay on WAN (10.x.x.65, 25ms delay)
  - Publishes multiaddr to Redis: `relay:{TEST_KEY}`
- **NAT Routers**: Dual-homed gateways performing SNAT (100ms delay each)
  - Dialer Router: WAN .66 ↔ LAN .93
  - Listener Router: WAN .67 ↔ LAN .129
- **Redis**: Global coordination with per-test key namespacing
  - TEST_KEY: First 10 hex chars of SHA-256(test_name)
- **Dialer/Listener**: Test implementations behind NAT (.94 and .130)

**Collision Probability:**
- 65,536 unique subnet sets (256² combinations)
- Offset +32 avoids common 10.0.x.x and 10.10.x.x ranges
- For 16 parallel tests: 0.02% collision chance
- For 100 parallel tests: 0.76% collision chance

## Quick Start

```bash
# Install dependencies (Ubuntu/Debian)
sudo apt-get install docker.io git wget unzip

# Install yq
sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
sudo chmod +x /usr/local/bin/yq

# Run all tests
./run_tests.sh --cache-dir /srv/cache --workers 4

# Run specific tests
./run_tests.sh --test-select "rust-v0.56" --workers 8

# Run with debug output
./run_tests.sh --test-select "rust-v0.56" --debug

# Force rebuild all images
./run_tests.sh --force-rebuild --yes
```

## Directory Structure

```
hole-punch/
├── impls/                     # Implementation directories
│   ├── rust/
│   │   ├── v0.53/            # Contains Dockerfile (if custom build needed)
│   │   └── README.md
│   └── go/
│       └── README.md
├── scripts/                   # Bash scripts
│   ├── build-images.sh       # Reads impls.yaml, builds all images
│   ├── generate-tests.sh     # Generates test matrix with optimizations
│   ├── start-global-services.sh
│   ├── stop-global-services.sh
│   ├── run-single-test.sh
│   ├── create-snapshot.sh
│   ├── generate-dashboard.sh
│   └── check-dependencies.sh
├── impls.yaml                 # Implementation definitions (source of truth)
├── run_tests.sh              # Main orchestrator
└── README.md                  # This file
```

## Test Pass Directory Structure

Each test run creates a unique test pass directory with all results:

```
/srv/cache/test-runs/hole-punch-HHMMSS-DD-MM-YYYY/
├── impls.yaml                 # Captured configuration
├── test-matrix.yaml          # Generated test matrix
├── results.yaml              # Structured test results
├── results.md                # Markdown dashboard
├── settings.yaml             # Snapshot metadata
├── scripts/                  # All test scripts
├── snapshots/                # Source code snapshots
├── docker-images/            # Saved Docker images
├── docker-compose/           # Generated compose files
├── logs/                     # Test execution logs
├── re-run.sh                 # Reproducibility script (supports --force-rebuild)
└── README.md                 # Snapshot documentation
```

## Configuration Files

### impls.yaml
Defines all implementations to test with their source repositories and supported transports.

Each implementation can use one of two source types:
- **github**: Automatically fetches and builds from a GitHub repository (specified by `repo` and `commit`)
- **local**: Builds from a local directory clone (specified by `path`)

Switching an implementation from `github` to `local` type makes debugging easy:
```yaml
implementations:
  - id: rust-v0.56
    source:
      type: local
      path: /home/user/rust-libp2p  # Local clone for debugging
      commit: b7914e40  # Still tracked for documentation
    transports: [tcp, quic]
```

This allows you to:
- Make local code changes without committing
- Test modifications immediately without rebuilding from GitHub
- Debug issues with your IDE and local tooling
- Switch back to `github` type when done debugging

## Command-Line Options

```
Usage: ./run_tests.sh [options]

Options:
  --test-select VALUE    Filter tests (pipe-separated substrings)
  --test-ignore VALUE    Ignore tests (pipe-separated substrings)
  --workers VALUE        Number of parallel workers (default: nproc)
  --cache-dir VALUE      Cache directory (default: /srv/cache)
  --snapshot             Create test pass snapshot after completion
  --debug                Enable debug mode (sets debug=true in test containers)
  --force-rebuild        Force rebuilding of all docker images in the test pass
  -y, --yes              Skip confirmation prompt and run tests immediately
  --check-deps           Only check dependencies and exit
  --help                 Show help message

Examples:
  ./run_tests.sh --cache-dir /srv/cache --workers 4
  ./run_tests.sh --test-select "rust-v0.56" --workers 8
  ./run_tests.sh --test-ignore "tcp"
  ./run_tests.sh --test-select "rust-v0.56" --debug
  ./run_tests.sh --snapshot --workers 8
```

## Test Selection

Test selection uses pipe-separated substring matching:
- `--test-select "rust-v0.53|go-v0.43"` - Select tests matching either pattern
- `--test-ignore "tcp"` - Exclude tests containing "tcp"

Without CLI arguments, all tests are run. Use `--test-select` and `--test-ignore` to filter tests as needed.

## Content-Addressed Caching

All artifacts cached under `/srv/cache/`:
- `snapshots/<commitSha>.zip` - GitHub repository snapshots (git SHA-1)
- `test-matrix/<sha256>.yaml` - Test matrices (cached by filter+ignore+debug)
- `test-runs/hole-punch-<timestamp>/` - Complete test pass directories

Cache keys use double-pipe `||` delimiter to prevent ambiguous collisions:
```bash
cache_key=$(echo "$TEST_FILTER||$TEST_IGNORE||$DEBUG" | sha256sum | cut -d' ' -f1)
```

## Hash Functions

- **Git snapshots**: SHA-1 (40 hex chars, from Git)
- **Docker images**: SHA-256 (64 hex chars, `sha256:` prefix stripped)
- **Content cache**: SHA-256 (64 hex chars)

All hash algorithm prefixes are omitted from identifiers for simplicity.

## Dependencies

- bash 4.0+
- git 2.0+
- docker 20.10+
- yq 4.0+
- wget, unzip

**Note:** No Node.js, npm, or make required!

## Performance Characteristics

**Optimizations:**
- Pre-loaded associative arrays (O(1) lookups instead of O(n) searches)
- Bulk TSV extraction (single yq call instead of 100s)
- Content-addressed caching with double-pipe delimiter
- Parallel test execution with configurable workers

**Performance:**
- `generate-tests.sh`: 10-30x faster (~20 yq calls vs 400+)
- `generate-dashboard.sh`: 30-80x faster (1 yq call vs 40,600+)
- Test orchestration: 10-40x faster overall
- Typical full test run: 5-15 minutes (4 workers, 20-50 tests)

## Reproducibility

Each test pass is fully self-contained and reproducible:

```bash
cd /srv/cache/test-runs/hole-punch-HHMMSS-DD-MM-YYYY
./re-run.sh

# Force rebuild all images before re-running
./re-run.sh --force-rebuild
```

The snapshot includes:
- All source code snapshots
- All Docker images (saved as tar.gz)
- Complete configuration
- All scripts and tooling

The `--force-rebuild` flag forces rebuilding of all Docker images from the captured snapshots, useful when you need to ensure a clean build environment or verify reproducibility from scratch.

## Current Status

<!-- TEST_RESULTS_START -->
# Hole Punch Interoperability Test Results

## Test Pass: `hole-punch-030559-09-01-2026`

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
- **Started:** 2026-01-09T03:05:59Z
- **Completed:** 2026-01-09T03:06:14Z

---

## Test Results

| Test | Dialer | Listener | Transport | Status | Duration |
|------|--------|----------|-----------|--------|----------|
| linux x linux (quic-v1) [dr: linux, rly: linux, lr: linux] | linux | linux | quic-v1 | ✅ | 10s |
| linux x linux (tcp, tls, mplex) [dr: linux, rly: linux, lr: linux] | linux | linux | tcp | ✅ | 11s |
| linux x linux (tcp, noise, mplex) [dr: linux, rly: linux, lr: linux] | linux | linux | tcp | ✅ | 12s |
| linux x linux (tcp, tls, yamux) [dr: linux, rly: linux, lr: linux] | linux | linux | tcp | ✅ | 13s |
| linux x linux (tcp, noise, yamux) [dr: linux, rly: linux, lr: linux] | linux | linux | tcp | ✅ | 14s |

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

*Generated: 2026-01-09T03:06:14Z*
<!-- TEST_RESULTS_END -->

