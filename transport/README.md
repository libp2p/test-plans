# Transport Interoperability Tests

Pure-bash implementation of transport interoperability tests for libp2p
implementations.

## What This Test Does

Transport interoperability tests verify that different libp2p implementations
can successfully communicate with each other across various combinations of:
- **Transports**: tcp, ws (WebSocket), wss (WebSocket Secure)
- **Secure Channels**: noise, tls
- **Muxers**: yamux, mplex

Additionally, tests cover standalone protocols that provide transport,
security, and multiplexing in one:
- quic-v1, webrtc-direct, webtransport

## What It Measures

- **Compatibility**: Can dialer and listener establish connections?
- **Protocol Support**: Which transport/secure/muxer combinations work?
- **Handshake Performance**: Connection establishment time
- **Ping Latency**: Round-trip time after connection

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

# Skip specific tests
./run.sh --test-ignore "rust-v0.56"

# Enable debug logging
./run.sh --debug
```

## Test Filtering

### Basic Filtering

Use pipe-separated patterns:

```bash
# Select multiple implementations
./run.sh --test-ignore "!rust-v0.56|!go-v0.45"

# Ignore specific transport protocols
./run.sh --transport-ignore "quic|webrtc"

# Combine them
./run.sh --test-ignore "!~rust" --transport-ignore "quic"
```

### Alias Expansion

Use `~alias` syntax for convenient test selection:

```bash
# Expand to all rust versions, ignores all tests except rust tests
./run.sh --test-ignore "!~rust"

# Exclude all rust versions
./run.sh --test-ignore "~rust"
```

**Available aliases** are defined in `impls.yaml` under `test-aliases`.

### Best Practice: Limit to Specific Alias

To test ONLY implementations in an alias (not just tests containing the alias pattern):

```bash
# Test ONLY rust implementations
./run.sh --test-ignore '!~rust'

# Test ONLY go implementations
./run.sh --test-ignore '!~go'
```

## Snapshot Generation

### Creating Snapshots

Generate a self-contained, reproducible test snapshot:

```bash
./run.sh --snapshot
```

This creates a snapshot directory in `/srv/cache/test-runs/transport-HHMMSS-DD-MM-YYYY/` containing:
- Complete test configuration (impls.yaml, test-matrix.yaml)
- All test results (results.yaml, results.md)
- All source code snapshots
- All Docker images (saved as tar.gz)
- All test scripts
- Re-run script for exact reproduction

### Reproducing from Snapshot

```bash
cd /srv/cache/test-runs/transport-HHMMSS-DD-MM-YYYY/
./run.sh

# Force rebuild images from snapshots
./run.sh --force-images-rebuild
```

## Downloading Snapshots

Snapshots are available as GitHub Actions artifacts:

1. Go to [Actions tab](https://github.com/libp2p/test-plans/actions)
2. Select the workflow run
3. Download artifacts from the "Artifacts" section
4. Extract and run `./run.sh`

## Script Documentation

For detailed information about the scripts used in this test suite, see:
- **[docs/SCRIPTS_DESIGN.md](../docs/SCRIPTS_DESIGN.md)** - Comprehensive script documentation

## Additional Options

```bash
# List all available implementations
./run.sh --list-images

# List tests that would be run (without running them)
./run.sh --test-ignore "!rust-v0.56" --list-tests

# Force rebuild all Docker images
./run.sh --force-image-rebuild

# Force regenerate test matrix (bypass cache)
./run.sh --force-matrix-rebuild

# Check dependencies only
./run.sh --check-deps
```

## Current Status

<!-- TEST_RESULTS_START -->
<!-- TEST_RESULTS_END -->
