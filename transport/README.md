# Transport Interoperability Tests v2

Simplified, pure-bash implementation of transport interoperability tests for libp2p.

## Overview

This is the v2 implementation following the same simplification approach as hole-punch:
- **Pure bash** orchestration (no Node.js/npm/TypeScript)
- **YAML** for all configuration and data files
- **Content-addressed caching** under `/srv/cache/`
- **No Makefiles or make dependency**
- **Self-contained snapshots** for reproducibility

## Key Differences from Hole Punch Tests

### Test Matrix Structure

Transport interop tests cover **3 dimensions**:
1. **Transport**: tcp, ws, wss,
2. **Secure Channel**: noise, tls
3. **Muxer**: yamux, mplex

libp2p also supports protocols that provide transport, a secure channel, and muxing all in one:

- quic-v1
- webrtc-direct
- webtransport

### Test Combinations

Tests are generated as: `dialer x listener x transport x secure-channel x muxer`

Example: `rust-v0.53 x go-v0.35 (tcp, noise, yamux)`

Valid combinations of `transport`, `secure-channel`, and `muxer` are:

- tcp, noise, mplex
- tcp, noise, yamux
- tcp, tls, mplex
- tcp, tls, yamux
- ws, noise, mplex
- ws, noise, yamux
- ws, tls, mplex
- ws, tls, yamux
- wss, noise, mplex
- wss, noise, yamux
- wss, tls, mplex
- wss, tls, yamux
- quic-v1
- webrtc
- webrtc-direct 
- webtransport

### No Global Services

Unlike hole-punch tests, transport tests don't need:
- Redis coordination (tests are simpler)
- Relay service (direct connections)

Each test runs with just 2 containers: `dialer` and `listener`.

## Quick Start

```bash
# Check dependencies (bash, git, docker, yq, wget, unzip)
./run_tests.sh --check-deps

# Run all tests
./run_tests.sh --cache-dir /srv/cache --workers 8

# Run only rust tests
./run_tests.sh --test-select "rust" --workers 4

# Skip quic tests
./run_tests.sh --test-ignore "quic" --workers 4

# Enable debug output
./run_tests.sh --debug --workers 4
```

## Architecture

### Configuration Files

**impls.yaml**:
Defines all implementations with their source repositories and supported protocols.

Each implementation can use one of two source types:
- **github**: Automatically fetches and builds from a GitHub repository
- **local**: Builds from a local directory clone for debugging

```yaml
implementations:
  # GitHub source (production)
  - id: rust-v0.53
    source:
      type: github
      repo: libp2p/rust-libp2p
      commit: b7914e407da34c99fb76dcc300b3d44b9af97fac
      dockerfile: interop-tests/Dockerfile.native
    transports: [tcp, ws, quic-v1]
    secureChannels: [noise, tls]
    muxers: [yamux, mplex]

  # Local source (debugging)
  - id: rust-v0.56
    source:
      type: local
      path: /home/user/rust-libp2p  # Local clone
      commit: b7914e40  # Still tracked for documentation
      dockerfile: interop-tests/Dockerfile.native
    transports: [tcp, ws, quic-v1]
    secureChannels: [noise, tls]
    muxers: [yamux, mplex]
```

Switching to `local` type makes debugging easy:
- Make local code changes without committing
- Test modifications immediately
- Use your IDE and debugging tools
- Switch back to `github` when done

### Test Matrix Generation

The script generates all valid combinations:
```
FOR each dialer in implementations:
  FOR each listener in implementations:
    FOR each transport in (dialer.transports ∩ listener.transports):
      FOR each secureChannel in (dialer.secureChannels ∩ listener.secureChannels):
        FOR each muxer in (dialer.muxers ∩ listener.muxers):
          IF transport NOT IN standalone_transports:
            CREATE TEST: dialer x listener (transport, secureChannel, muxer)
          ELSE:
            CREATE TEST: dialer x listener (transport)
```

**Standalone transports** (no muxer/secure channel): quic-v1, webtransport, webrtc, webrtc-direct

### Scripts

```
scripts/
├── build-images.sh           # Build all Docker images from impls.yaml
├── check-dependencies.sh     # Verify system requirements
├── generate-tests.sh         # Generate test matrix (3D combinations)
├── run-single-test.sh        # Execute one test (2 containers)
├── generate-dashboard.sh     # Create results.md
└── create-snapshot.sh        # Create test snapshot
```

### Content-Addressed Caching

```
/srv/cache/
├── snapshots/<commit-sha>.zip       # Source code archives
├── test-matrix/<sha256>.yaml        # Generated test matrices
└── test-runs/<timestamp>.tar.gz   # Test snapshots
```

## Dependencies

- bash 4.0+
- docker 20.10+
- yq 4.0+
- wget
- unzip

**No Node.js, git, npm, TypeScript, or make required!**

## Test Execution

### Single Test

```bash
# Start containers
docker run dialer-image
docker run listener-image

# Both connect and run interop test
# Exit codes determine pass/fail
```

### Parallel Execution

```bash
# Uses xargs for parallel job control
seq 0 $((test_count - 1)) | xargs -P $WORKERS bash -c 'run_test {}'
```

### Results

**results.yaml**:
```yaml
metadata:
  testPass: transport-interop-full-143022-08-11-2025
  startedAt: 2025-11-09T14:30:22Z
  duration: 1234s

summary:
  total: 450
  passed: 445
  failed: 5

tests:
  - name: rust-v0.53 x go-v0.35 (tcp, noise, yamux)
    status: pass
    exitCode: 0
    duration: 8s
    dialer: rust-v0.53
    listener: go-v0.35
    transport: tcp
    secureChannel: noise
    muxer: yamux
```

**results.md**: Markdown dashboard with matrix view

## Adding Implementations

1. Add entry to `impls.yaml`:
   ```yaml
   - id: go-v0.35
     source:
       type: github
       repo: libp2p/go-libp2p
       commit: <full-commit-sha>
       dockerfile: interop-tests/Dockerfile
     transports: [tcp, quic-v1]
     secureChannels: [noise, tls]
     muxers: [yamux, mplex]
   ```

2. Run tests:
   ```bash
   ./run_tests.sh --test-select "go-v0.35"
   ```

3. For debugging, switch to local source:
   ```yaml
   - id: go-v0.35
     source:
       type: local
       path: /home/user/go-libp2p
       commit: <commit-sha>
       dockerfile: interop-tests/Dockerfile
     transports: [tcp, quic-v1]
     secureChannels: [noise, tls]
     muxers: [yamux, mplex]
   ```

   Then test with local changes:
   ```bash
   ./run_tests.sh --test-select "go-v0.35" --force-rebuild
   ```

## Current Status

<!-- TEST_RESULTS_START -->
# Transport Interoperability Test Results

## Test Pass: `transport-interop-023908-03-01-2026`

**Summary:**
- **Total Tests:** 2302
- **Passed:** ✅ 2255
- **Failed:** ❌ 47
- **Pass Rate:** 98.0%

**Environment:**
- **Platform:** x86_64
- **OS:** Linux
- **Workers:** 8
- **Duration:** 3794s

**Timestamps:**
- **Started:** 2026-01-03T02:39:08Z
- **Completed:** 2026-01-03T03:42:22Z

---

## Test Results

| Test | Dialer | Listener | Transport | Secure | Muxer | Status | Duration | Handshake+RTT (ms) | Ping RTT (ms) |
|------|--------|----------|-----------|--------|-------|--------|----------|-------------------|---------------|
| rust-v0.53 x rust-v0.53 (tcp, noise, mplex) | rust-v0.53 | rust-v0.53 | tcp | noise | mplex | ✅ | 3s | 90.591 | 0.111 |
| rust-v0.53 x rust-v0.53 (tcp, noise, yamux) | rust-v0.53 | rust-v0.53 | tcp | noise | yamux | ✅ | 3s | 137.567 | 43.911 |
| rust-v0.53 x rust-v0.53 (ws, noise, yamux) | rust-v0.53 | rust-v0.53 | ws | noise | yamux | ✅ | 3s | 269.622 | 87.908 |
| rust-v0.53 x rust-v0.53 (tcp, tls, mplex) | rust-v0.53 | rust-v0.53 | tcp | tls | mplex | ✅ | 5s | 49.043 | 0.264 |
| rust-v0.53 x rust-v0.53 (tcp, tls, yamux) | rust-v0.53 | rust-v0.53 | tcp | tls | yamux | ✅ | 5s | 188.251 | 87.966 |
| rust-v0.53 x rust-v0.53 (ws, tls, mplex) | rust-v0.53 | rust-v0.53 | ws | tls | mplex | ✅ | 6s | 265.342 | 87.759 |
| rust-v0.53 x rust-v0.53 (ws, tls, yamux) | rust-v0.53 | rust-v0.53 | ws | tls | yamux | ✅ | 6s | 268.449 | 87.698 |
| rust-v0.53 x rust-v0.53 (ws, noise, mplex) | rust-v0.53 | rust-v0.53 | ws | noise | mplex | ✅ | 6s | 267.852 | 91.59 |
| rust-v0.53 x rust-v0.53 (quic-v1) | rust-v0.53 | rust-v0.53 | quic-v1 | - | - | ✅ | 4s | 4.793 | 0.752 |
| rust-v0.53 x rust-v0.53 (webrtc-direct) | rust-v0.53 | rust-v0.53 | webrtc-direct | - | - | ✅ | 4s | 208.866 | 0.244 |
| rust-v0.53 x rust-v0.54 (ws, tls, mplex) | rust-v0.53 | rust-v0.54 | ws | tls | mplex | ✅ | 4s | 269.229 | 91.912 |
| rust-v0.53 x rust-v0.54 (ws, tls, yamux) | rust-v0.53 | rust-v0.54 | ws | tls | yamux | ✅ | 5s | 277.031 | 87.596 |
| rust-v0.53 x rust-v0.54 (ws, noise, mplex) | rust-v0.53 | rust-v0.54 | ws | noise | mplex | ✅ | 4s | 281.095 | 91.713 |
| rust-v0.53 x rust-v0.54 (tcp, tls, mplex) | rust-v0.53 | rust-v0.54 | tcp | tls | mplex | ✅ | 5s | 43.994 | 0.114 |
| rust-v0.53 x rust-v0.54 (ws, noise, yamux) | rust-v0.53 | rust-v0.54 | ws | noise | yamux | ✅ | 5s | 269.811 | 91.714 |
| rust-v0.53 x rust-v0.54 (tcp, tls, yamux) | rust-v0.53 | rust-v0.54 | tcp | tls | yamux | ✅ | 4s | 135.099 | 87.777 |
| rust-v0.53 x rust-v0.54 (tcp, noise, mplex) | rust-v0.53 | rust-v0.54 | tcp | noise | mplex | ✅ | 5s | 96.163 | 0.096 |
| rust-v0.53 x rust-v0.54 (quic-v1) | rust-v0.53 | rust-v0.54 | quic-v1 | - | - | ✅ | 5s | 4.55 | 0.449 |
| rust-v0.53 x rust-v0.54 (tcp, noise, yamux) | rust-v0.53 | rust-v0.54 | tcp | noise | yamux | ✅ | 5s | 135.984 | 44.009 |
| rust-v0.53 x rust-v0.54 (webrtc-direct) | rust-v0.53 | rust-v0.54 | webrtc-direct | - | - | ✅ | 4s | 211.878 | 0.205 |
| rust-v0.53 x rust-v0.55 (ws, tls, mplex) | rust-v0.53 | rust-v0.55 | ws | tls | mplex | ✅ | 5s | 138.189 | 40.797 |
| rust-v0.53 x rust-v0.55 (ws, tls, yamux) | rust-v0.53 | rust-v0.55 | ws | tls | yamux | ✅ | 4s | 136.807 | 42.849 |
| rust-v0.53 x rust-v0.55 (ws, noise, mplex) | rust-v0.53 | rust-v0.55 | ws | noise | mplex | ✅ | 5s | 131.038 | 43.466 |
| rust-v0.53 x rust-v0.55 (ws, noise, yamux) | rust-v0.53 | rust-v0.55 | ws | noise | yamux | ✅ | 4s | 132.242 | 43.429 |
| rust-v0.53 x rust-v0.55 (tcp, tls, mplex) | rust-v0.53 | rust-v0.55 | tcp | tls | mplex | ✅ | 4s | 4.821 | 0.308 |
| rust-v0.53 x rust-v0.55 (tcp, tls, yamux) | rust-v0.53 | rust-v0.55 | tcp | tls | yamux | ✅ | 5s | 48.842 | 45.941 |
| rust-v0.53 x rust-v0.55 (tcp, noise, mplex) | rust-v0.53 | rust-v0.55 | tcp | noise | mplex | ✅ | 4s | 42.657 | 0.101 |
| rust-v0.53 x rust-v0.55 (tcp, noise, yamux) | rust-v0.53 | rust-v0.55 | tcp | noise | yamux | ✅ | 5s | 87.207 | 44.073 |
| rust-v0.53 x rust-v0.55 (quic-v1) | rust-v0.53 | rust-v0.55 | quic-v1 | - | - | ✅ | 4s | 3.873 | 0.292 |
| rust-v0.53 x rust-v0.56 (ws, tls, mplex) | rust-v0.53 | rust-v0.56 | ws | tls | mplex | ✅ | 5s | 135.444 | 42.514 |
| rust-v0.53 x rust-v0.55 (webrtc-direct) | rust-v0.53 | rust-v0.55 | webrtc-direct | - | - | ✅ | 5s | 208.613 | 0.226 |
| rust-v0.53 x rust-v0.56 (ws, tls, yamux) | rust-v0.53 | rust-v0.56 | ws | tls | yamux | ✅ | 4s | 130.635 | 42.692 |
| rust-v0.53 x rust-v0.56 (ws, noise, mplex) | rust-v0.53 | rust-v0.56 | ws | noise | mplex | ✅ | 5s | 137.507 | 46.973 |
| rust-v0.53 x rust-v0.56 (ws, noise, yamux) | rust-v0.53 | rust-v0.56 | ws | noise | yamux | ✅ | 5s | 147.151 | 47.068 |
| rust-v0.53 x rust-v0.56 (tcp, tls, mplex) | rust-v0.53 | rust-v0.56 | tcp | tls | mplex | ✅ | 5s | 4.124 | 0.063 |
| rust-v0.53 x rust-v0.56 (tcp, tls, yamux) | rust-v0.53 | rust-v0.56 | tcp | tls | yamux | ✅ | 5s | 48.8 | 41.274 |
| rust-v0.53 x rust-v0.56 (tcp, noise, mplex) | rust-v0.53 | rust-v0.56 | tcp | noise | mplex | ✅ | 5s | 50.995 | 0.157 |
| rust-v0.53 x rust-v0.56 (quic-v1) | rust-v0.53 | rust-v0.56 | quic-v1 | - | - | ✅ | 5s | 6.008 | 0.903 |
| rust-v0.53 x rust-v0.56 (tcp, noise, yamux) | rust-v0.53 | rust-v0.56 | tcp | noise | yamux | ✅ | 5s | 89.247 | 43.432 |
| rust-v0.53 x rust-v0.56 (webrtc-direct) | rust-v0.53 | rust-v0.56 | webrtc-direct | - | - | ✅ | 5s | 206.925 | 0.297 |
| rust-v0.53 x go-v0.38 (ws, tls, yamux) | rust-v0.53 | go-v0.38 | ws | tls | yamux | ✅ | 5s | 91.536 | 1.214 |
| rust-v0.53 x go-v0.38 (ws, noise, yamux) | rust-v0.53 | go-v0.38 | ws | noise | yamux | ✅ | 5s | 131.071 | 41.685 |
| rust-v0.53 x go-v0.38 (tcp, noise, yamux) | rust-v0.53 | go-v0.38 | tcp | noise | yamux | ✅ | 4s | 2.265 | 0.144 |
| rust-v0.53 x go-v0.38 (tcp, tls, yamux) | rust-v0.53 | go-v0.38 | tcp | tls | yamux | ✅ | 5s | 3.441 | 0.236 |
| rust-v0.53 x go-v0.38 (quic-v1) | rust-v0.53 | go-v0.38 | quic-v1 | - | - | ✅ | 5s | 3.479 | 0.324 |
| rust-v0.53 x go-v0.39 (ws, tls, yamux) | rust-v0.53 | go-v0.39 | ws | tls | yamux | ✅ | 4s | 91.381 | 1.496 |
| rust-v0.53 x go-v0.38 (webrtc-direct) | rust-v0.53 | go-v0.38 | webrtc-direct | - | - | ✅ | 6s | 82.776 | 0.231 |
| rust-v0.53 x go-v0.39 (tcp, tls, yamux) | rust-v0.53 | go-v0.39 | tcp | tls | yamux | ✅ | 5s | 2.812 | 0.398 |
| rust-v0.53 x go-v0.39 (ws, noise, yamux) | rust-v0.53 | go-v0.39 | ws | noise | yamux | ✅ | 5s | 93.153 | 0.207 |
| rust-v0.53 x go-v0.39 (quic-v1) | rust-v0.53 | go-v0.39 | quic-v1 | - | - | ✅ | 5s | 8.778 | 0.339 |
| rust-v0.53 x go-v0.39 (tcp, noise, yamux) | rust-v0.53 | go-v0.39 | tcp | noise | yamux | ✅ | 5s | 6.754 | 2.836 |
| rust-v0.53 x go-v0.40 (ws, tls, yamux) | rust-v0.53 | go-v0.40 | ws | tls | yamux | ✅ | 5s | 87.977 | 0.209 |
| rust-v0.53 x go-v0.39 (webrtc-direct) | rust-v0.53 | go-v0.39 | webrtc-direct | - | - | ✅ | 5s | 132.763 | 0.187 |
| rust-v0.53 x go-v0.40 (tcp, tls, yamux) | rust-v0.53 | go-v0.40 | tcp | tls | yamux | ✅ | 5s | 47.802 | 0.496 |
| rust-v0.53 x go-v0.40 (tcp, noise, yamux) | rust-v0.53 | go-v0.40 | tcp | noise | yamux | ✅ | 5s | 3.31 | 0.368 |
| rust-v0.53 x go-v0.40 (ws, noise, yamux) | rust-v0.53 | go-v0.40 | ws | noise | yamux | ✅ | 5s | 96.436 | 0.281 |
| rust-v0.53 x go-v0.40 (quic-v1) | rust-v0.53 | go-v0.40 | quic-v1 | - | - | ✅ | 5s | 4.176 | 0.162 |
| rust-v0.53 x go-v0.41 (ws, noise, yamux) | rust-v0.53 | go-v0.41 | ws | noise | yamux | ✅ | 4s | 88.759 | 0.215 |
| rust-v0.53 x go-v0.41 (ws, tls, yamux) | rust-v0.53 | go-v0.41 | ws | tls | yamux | ✅ | 5s | 136.464 | 40.957 |
| rust-v0.53 x go-v0.41 (tcp, tls, yamux) | rust-v0.53 | go-v0.41 | tcp | tls | yamux | ✅ | 5s | 2.501 | 0.119 |
| rust-v0.53 x go-v0.41 (quic-v1) | rust-v0.53 | go-v0.41 | quic-v1 | - | - | ✅ | 4s | 5.929 | 0.213 |
| rust-v0.53 x go-v0.41 (tcp, noise, yamux) | rust-v0.53 | go-v0.41 | tcp | noise | yamux | ✅ | 5s | 52.55 | 47.444 |
| rust-v0.53 x go-v0.41 (webrtc-direct) | rust-v0.53 | go-v0.41 | webrtc-direct | - | - | ✅ | 4s | 12.202 | 0.454 |
| rust-v0.53 x go-v0.42 (ws, tls, yamux) | rust-v0.53 | go-v0.42 | ws | tls | yamux | ✅ | 4s | 93.286 | 0.338 |
| rust-v0.53 x go-v0.42 (ws, noise, yamux) | rust-v0.53 | go-v0.42 | ws | noise | yamux | ✅ | 4s | 135.273 | 42.23 |
| rust-v0.53 x go-v0.42 (tcp, tls, yamux) | rust-v0.53 | go-v0.42 | tcp | tls | yamux | ✅ | 4s | 2.482 | 0.136 |
| rust-v0.53 x go-v0.42 (tcp, noise, yamux) | rust-v0.53 | go-v0.42 | tcp | noise | yamux | ✅ | 5s | 50.66 | 47.338 |
| rust-v0.53 x go-v0.42 (quic-v1) | rust-v0.53 | go-v0.42 | quic-v1 | - | - | ✅ | 4s | 5.241 | 0.512 |
| rust-v0.53 x go-v0.42 (webrtc-direct) | rust-v0.53 | go-v0.42 | webrtc-direct | - | - | ✅ | 4s | 10.138 | 0.172 |
| rust-v0.53 x go-v0.43 (ws, tls, yamux) | rust-v0.53 | go-v0.43 | ws | tls | yamux | ✅ | 5s | 94.398 | 0.766 |
| rust-v0.53 x go-v0.43 (ws, noise, yamux) | rust-v0.53 | go-v0.43 | ws | noise | yamux | ✅ | 4s | 87.765 | 0.216 |
| rust-v0.53 x go-v0.43 (tcp, tls, yamux) | rust-v0.53 | go-v0.43 | tcp | tls | yamux | ✅ | 4s | 3.082 | 0.568 |
| rust-v0.53 x go-v0.43 (tcp, noise, yamux) | rust-v0.53 | go-v0.43 | tcp | noise | yamux | ✅ | 4s | 2.774 | 0.158 |
| rust-v0.53 x go-v0.43 (quic-v1) | rust-v0.53 | go-v0.43 | quic-v1 | - | - | ✅ | 4s | 6.182 | 0.858 |
| rust-v0.53 x go-v0.44 (ws, tls, yamux) | rust-v0.53 | go-v0.44 | ws | tls | yamux | ✅ | 3s | 138.606 | 46.599 |
| rust-v0.53 x go-v0.43 (webrtc-direct) | rust-v0.53 | go-v0.43 | webrtc-direct | - | - | ✅ | 5s | 105.083 | 0.274 |
| rust-v0.53 x go-v0.44 (tcp, tls, yamux) | rust-v0.53 | go-v0.44 | tcp | tls | yamux | ✅ | 3s | 50.52 | 45.06 |
| rust-v0.53 x go-v0.44 (ws, noise, yamux) | rust-v0.53 | go-v0.44 | ws | noise | yamux | ✅ | 5s | 94.26 | 1.019 |
| rust-v0.53 x go-v0.44 (tcp, noise, yamux) | rust-v0.53 | go-v0.44 | tcp | noise | yamux | ✅ | 4s | 6.661 | 0.18 |
| rust-v0.53 x go-v0.44 (quic-v1) | rust-v0.53 | go-v0.44 | quic-v1 | - | - | ✅ | 4s | 5.955 | 0.637 |
| rust-v0.53 x go-v0.44 (webrtc-direct) | rust-v0.53 | go-v0.44 | webrtc-direct | - | - | ✅ | 4s | 12.528 | 0.248 |
| rust-v0.53 x go-v0.45 (ws, noise, yamux) | rust-v0.53 | go-v0.45 | ws | noise | yamux | ✅ | 4s | 97.553 | 0.635 |
| rust-v0.53 x go-v0.45 (ws, tls, yamux) | rust-v0.53 | go-v0.45 | ws | tls | yamux | ✅ | 5s | 91.681 | 46.917 |
| rust-v0.53 x go-v0.45 (tcp, tls, yamux) | rust-v0.53 | go-v0.45 | tcp | tls | yamux | ✅ | 4s | 3.698 | 0.333 |
| rust-v0.53 x go-v0.45 (tcp, noise, yamux) | rust-v0.53 | go-v0.45 | tcp | noise | yamux | ✅ | 4s | 2.667 | 0.142 |
| rust-v0.53 x go-v0.45 (quic-v1) | rust-v0.53 | go-v0.45 | quic-v1 | - | - | ✅ | 4s | 4.864 | 0.43 |
| rust-v0.53 x go-v0.45 (webrtc-direct) | rust-v0.53 | go-v0.45 | webrtc-direct | - | - | ✅ | 5s | 214.813 | 0.242 |
| rust-v0.53 x python-v0.4 (ws, noise, mplex) | rust-v0.53 | python-v0.4 | ws | noise | mplex | ✅ | 4s | 99.214 | 1.073 |
| rust-v0.53 x python-v0.4 (ws, noise, yamux) | rust-v0.53 | python-v0.4 | ws | noise | yamux | ✅ | 4s | 100.059 | 1.473 |
| rust-v0.53 x python-v0.4 (tcp, noise, mplex) | rust-v0.53 | python-v0.4 | tcp | noise | mplex | ✅ | 4s | 16.128 | 0.875 |
| rust-v0.53 x python-v0.4 (tcp, noise, yamux) | rust-v0.53 | python-v0.4 | tcp | noise | yamux | ✅ | 5s | 10.933 | 1.01 |
| rust-v0.53 x python-v0.4 (quic-v1) | rust-v0.53 | python-v0.4 | quic-v1 | - | - | ✅ | 4s | 74.228 | 9.05 |
| rust-v0.53 x js-v1.x (ws, noise, mplex) | rust-v0.53 | js-v1.x | ws | noise | mplex | ✅ | 12s | 197.294 | 16.695 |
| rust-v0.53 x js-v1.x (ws, noise, yamux) | rust-v0.53 | js-v1.x | ws | noise | yamux | ✅ | 13s | 182.133 | 12.166 |
| rust-v0.53 x js-v1.x (tcp, noise, mplex) | rust-v0.53 | js-v1.x | tcp | noise | mplex | ✅ | 12s | 121.026 | 14.004 |
| rust-v0.53 x js-v1.x (tcp, noise, yamux) | rust-v0.53 | js-v1.x | tcp | noise | yamux | ✅ | 12s | 102.09 | 6.774 |
| rust-v0.53 x js-v2.x (ws, noise, mplex) | rust-v0.53 | js-v2.x | ws | noise | mplex | ✅ | 12s | 148.603 | 8.226 |
| rust-v0.53 x js-v2.x (ws, noise, yamux) | rust-v0.53 | js-v2.x | ws | noise | yamux | ✅ | 13s | 143.68 | 8.345 |
| rust-v0.53 x js-v2.x (tcp, noise, mplex) | rust-v0.53 | js-v2.x | tcp | noise | mplex | ✅ | 12s | 98.405 | 5.899 |
| rust-v0.53 x nim-v1.14 (ws, noise, mplex) | rust-v0.53 | nim-v1.14 | ws | noise | mplex | ✅ | 4s | 276.945 | 87.734 |
| rust-v0.53 x nim-v1.14 (ws, noise, yamux) | rust-v0.53 | nim-v1.14 | ws | noise | yamux | ✅ | 3s | 233.29 | 45.185 |
| rust-v0.53 x js-v2.x (tcp, noise, yamux) | rust-v0.53 | js-v2.x | tcp | noise | yamux | ✅ | 11s | 122.254 | 9.788 |
| rust-v0.53 x nim-v1.14 (tcp, noise, mplex) | rust-v0.53 | nim-v1.14 | tcp | noise | mplex | ✅ | 3s | 93.929 | 0.478 |
| rust-v0.53 x js-v3.x (ws, noise, mplex) | rust-v0.53 | js-v3.x | ws | noise | mplex | ✅ | 12s | 140.836 | 12.969 |
| rust-v0.53 x nim-v1.14 (tcp, noise, yamux) | rust-v0.53 | nim-v1.14 | tcp | noise | yamux | ✅ | 4s | 145.441 | 46.044 |
| rust-v0.53 x js-v3.x (ws, noise, yamux) | rust-v0.53 | js-v3.x | ws | noise | yamux | ✅ | 12s | 143.09 | 15.316 |
| rust-v0.53 x js-v3.x (tcp, noise, mplex) | rust-v0.53 | js-v3.x | tcp | noise | mplex | ✅ | 12s | 103.224 | 31.177 |
| rust-v0.53 x js-v3.x (tcp, noise, yamux) | rust-v0.53 | js-v3.x | tcp | noise | yamux | ✅ | 11s | 82.568 | 8.711 |
| rust-v0.53 x jvm-v1.2 (ws, tls, mplex) | rust-v0.53 | jvm-v1.2 | ws | tls | mplex | ✅ | 8s | 2587.113 | 13.405 |
| rust-v0.53 x jvm-v1.2 (ws, noise, mplex) | rust-v0.53 | jvm-v1.2 | ws | noise | mplex | ✅ | 8s | 1350.811 | 9.786 |
| rust-v0.53 x jvm-v1.2 (ws, tls, yamux) | rust-v0.53 | jvm-v1.2 | ws | tls | yamux | ✅ | 9s | 3438.165 | 47.734 |
| rust-v0.53 x jvm-v1.2 (ws, noise, yamux) | rust-v0.53 | jvm-v1.2 | ws | noise | yamux | ✅ | 9s | 1195.464 | 47.99 |
| rust-v0.53 x jvm-v1.2 (tcp, noise, mplex) | rust-v0.53 | jvm-v1.2 | tcp | noise | mplex | ✅ | 8s | 480.646 | 3.643 |
| rust-v0.53 x jvm-v1.2 (tcp, tls, mplex) | rust-v0.53 | jvm-v1.2 | tcp | tls | mplex | ✅ | 10s | 2097.59 | 3.93 |
| rust-v0.53 x jvm-v1.2 (tcp, tls, yamux) | rust-v0.53 | jvm-v1.2 | tcp | tls | yamux | ✅ | 9s | 1684.999 | 44.78 |
| rust-v0.53 x c-v0.0.1 (tcp, noise, mplex) | rust-v0.53 | c-v0.0.1 | tcp | noise | mplex | ✅ | 4s | 55.212 | 3.473 |
| rust-v0.53 x jvm-v1.2 (tcp, noise, yamux) | rust-v0.53 | jvm-v1.2 | tcp | noise | yamux | ✅ | 6s | 541.716 | 2.678 |
| rust-v0.53 x c-v0.0.1 (quic-v1) | rust-v0.53 | c-v0.0.1 | quic-v1 | - | - | ✅ | 3s | 24.346 | 0.289 |
| rust-v0.53 x c-v0.0.1 (tcp, noise, yamux) | rust-v0.53 | c-v0.0.1 | tcp | noise | yamux | ✅ | 5s | 103.999 | 0.464 |
| rust-v0.53 x zig-v0.0.1 (quic-v1) | rust-v0.53 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 3s | - | - |
| rust-v0.53 x dotnet-v1.0 (tcp, noise, yamux) | rust-v0.53 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 4s | 122.592 | 2.887 |
| rust-v0.53 x jvm-v1.2 (quic-v1) | rust-v0.53 | jvm-v1.2 | quic-v1 | - | - | ✅ | 7s | 945.757 | 5.709 |
| rust-v0.53 x eth-p2p-z-v0.0.1 (quic-v1) | rust-v0.53 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 4s | 2.967 | 0.162 |
| rust-v0.54 x rust-v0.53 (ws, tls, mplex) | rust-v0.54 | rust-v0.53 | ws | tls | mplex | ✅ | 4s | 284.35 | 91.854 |
| rust-v0.54 x rust-v0.53 (ws, tls, yamux) | rust-v0.54 | rust-v0.53 | ws | tls | yamux | ✅ | 4s | 266.283 | 87.653 |
| rust-v0.54 x rust-v0.53 (ws, noise, mplex) | rust-v0.54 | rust-v0.53 | ws | noise | mplex | ✅ | 4s | 273.194 | 91.891 |
| rust-v0.54 x rust-v0.53 (tcp, tls, mplex) | rust-v0.54 | rust-v0.53 | tcp | tls | mplex | ✅ | 4s | 46.008 | 42.329 |
| rust-v0.54 x rust-v0.53 (ws, noise, yamux) | rust-v0.54 | rust-v0.53 | ws | noise | yamux | ✅ | 4s | 263.275 | 87.792 |
| rust-v0.54 x rust-v0.53 (tcp, tls, yamux) | rust-v0.54 | rust-v0.53 | tcp | tls | yamux | ✅ | 4s | 138.594 | 87.696 |
| rust-v0.54 x rust-v0.53 (tcp, noise, mplex) | rust-v0.54 | rust-v0.53 | tcp | noise | mplex | ✅ | 4s | 88.043 | 0.213 |
| rust-v0.54 x rust-v0.53 (tcp, noise, yamux) | rust-v0.54 | rust-v0.53 | tcp | noise | yamux | ✅ | 4s | 134.64 | 43.944 |
| rust-v0.54 x rust-v0.53 (quic-v1) | rust-v0.54 | rust-v0.53 | quic-v1 | - | - | ✅ | 5s | 3.233 | 0.377 |
| rust-v0.54 x rust-v0.53 (webrtc-direct) | rust-v0.54 | rust-v0.53 | webrtc-direct | - | - | ✅ | 4s | 207.981 | 0.277 |
| rust-v0.54 x rust-v0.54 (ws, tls, mplex) | rust-v0.54 | rust-v0.54 | ws | tls | mplex | ✅ | 4s | 271.772 | 87.842 |
| rust-v0.54 x rust-v0.54 (ws, tls, yamux) | rust-v0.54 | rust-v0.54 | ws | tls | yamux | ✅ | 4s | 263.455 | 87.683 |
| rust-v0.54 x rust-v0.54 (ws, noise, mplex) | rust-v0.54 | rust-v0.54 | ws | noise | mplex | ✅ | 4s | 270.128 | 91.999 |
| rust-v0.54 x rust-v0.54 (ws, noise, yamux) | rust-v0.54 | rust-v0.54 | ws | noise | yamux | ✅ | 4s | 270.489 | 91.789 |
| rust-v0.54 x rust-v0.54 (tcp, tls, mplex) | rust-v0.54 | rust-v0.54 | tcp | tls | mplex | ✅ | 4s | 51.833 | 46.24 |
| rust-v0.54 x rust-v0.54 (tcp, noise, mplex) | rust-v0.54 | rust-v0.54 | tcp | noise | mplex | ✅ | 4s | 92.766 | 0.107 |
| rust-v0.54 x rust-v0.54 (tcp, tls, yamux) | rust-v0.54 | rust-v0.54 | tcp | tls | yamux | ✅ | 5s | 134.86 | 87.711 |
| rust-v0.54 x rust-v0.54 (tcp, noise, yamux) | rust-v0.54 | rust-v0.54 | tcp | noise | yamux | ✅ | 4s | 133.213 | 43.994 |
| rust-v0.54 x rust-v0.54 (quic-v1) | rust-v0.54 | rust-v0.54 | quic-v1 | - | - | ✅ | 5s | 2.737 | 0.2 |
| rust-v0.54 x rust-v0.55 (ws, tls, mplex) | rust-v0.54 | rust-v0.55 | ws | tls | mplex | ✅ | 4s | 138.754 | 46.624 |
| rust-v0.54 x rust-v0.54 (webrtc-direct) | rust-v0.54 | rust-v0.54 | webrtc-direct | - | - | ✅ | 5s | 207.455 | 0.178 |
| rust-v0.54 x rust-v0.55 (ws, tls, yamux) | rust-v0.54 | rust-v0.55 | ws | tls | yamux | ✅ | 5s | 92.26 | 0.16 |
| rust-v0.54 x rust-v0.55 (ws, noise, yamux) | rust-v0.54 | rust-v0.55 | ws | noise | yamux | ✅ | 4s | 137.419 | 42.655 |
| rust-v0.54 x rust-v0.55 (ws, noise, mplex) | rust-v0.54 | rust-v0.55 | ws | noise | mplex | ✅ | 5s | 130.773 | 43.185 |
| rust-v0.54 x rust-v0.55 (tcp, tls, yamux) | rust-v0.54 | rust-v0.55 | tcp | tls | yamux | ✅ | 4s | 44.133 | 40.643 |
| rust-v0.54 x rust-v0.55 (tcp, noise, mplex) | rust-v0.54 | rust-v0.55 | tcp | noise | mplex | ✅ | 3s | 45.774 | 0.064 |
| rust-v0.54 x rust-v0.55 (tcp, tls, mplex) | rust-v0.54 | rust-v0.55 | tcp | tls | mplex | ✅ | 6s | 2.805 | 0.036 |
| rust-v0.54 x rust-v0.55 (tcp, noise, yamux) | rust-v0.54 | rust-v0.55 | tcp | noise | yamux | ✅ | 4s | 43.128 | 0.082 |
| rust-v0.54 x rust-v0.55 (quic-v1) | rust-v0.54 | rust-v0.55 | quic-v1 | - | - | ✅ | 4s | 3.026 | 0.206 |
| rust-v0.54 x rust-v0.55 (webrtc-direct) | rust-v0.54 | rust-v0.55 | webrtc-direct | - | - | ✅ | 4s | 210.249 | 0.226 |
| rust-v0.54 x rust-v0.56 (ws, tls, mplex) | rust-v0.54 | rust-v0.56 | ws | tls | mplex | ✅ | 4s | 133.801 | 46.747 |
| rust-v0.54 x rust-v0.56 (ws, tls, yamux) | rust-v0.54 | rust-v0.56 | ws | tls | yamux | ✅ | 4s | 134.516 | 40.828 |
| rust-v0.54 x rust-v0.56 (ws, noise, yamux) | rust-v0.54 | rust-v0.56 | ws | noise | yamux | ✅ | 4s | 91.688 | 0.175 |
| rust-v0.54 x rust-v0.56 (ws, noise, mplex) | rust-v0.54 | rust-v0.56 | ws | noise | mplex | ✅ | 4s | 96.519 | 0.082 |
| rust-v0.54 x rust-v0.56 (tcp, tls, mplex) | rust-v0.54 | rust-v0.56 | tcp | tls | mplex | ✅ | 5s | 43.3 | 40.747 |
| rust-v0.54 x rust-v0.56 (tcp, tls, yamux) | rust-v0.54 | rust-v0.56 | tcp | tls | yamux | ✅ | 5s | 45.532 | 42.404 |
| rust-v0.54 x rust-v0.56 (tcp, noise, mplex) | rust-v0.54 | rust-v0.56 | tcp | noise | mplex | ✅ | 4s | 46.448 | 0.038 |
| rust-v0.54 x rust-v0.56 (tcp, noise, yamux) | rust-v0.54 | rust-v0.56 | tcp | noise | yamux | ✅ | 4s | 43.684 | 0.07 |
| rust-v0.54 x rust-v0.56 (quic-v1) | rust-v0.54 | rust-v0.56 | quic-v1 | - | - | ✅ | 4s | 2.808 | 0.255 |
| rust-v0.54 x go-v0.38 (ws, tls, yamux) | rust-v0.54 | go-v0.38 | ws | tls | yamux | ✅ | 4s | 90.806 | 0.917 |
| rust-v0.54 x rust-v0.56 (webrtc-direct) | rust-v0.54 | rust-v0.56 | webrtc-direct | - | - | ✅ | 5s | 282.673 | 0.364 |
| rust-v0.54 x go-v0.38 (ws, noise, yamux) | rust-v0.54 | go-v0.38 | ws | noise | yamux | ✅ | 5s | 88.899 | 0.119 |
| rust-v0.54 x go-v0.38 (tcp, tls, yamux) | rust-v0.54 | go-v0.38 | tcp | tls | yamux | ✅ | 4s | 7.324 | 4.18 |
| rust-v0.54 x go-v0.38 (tcp, noise, yamux) | rust-v0.54 | go-v0.38 | tcp | noise | yamux | ✅ | 4s | 2.547 | 0.679 |
| rust-v0.54 x go-v0.38 (quic-v1) | rust-v0.54 | go-v0.38 | quic-v1 | - | - | ✅ | 4s | 8.054 | 2.214 |
| rust-v0.54 x go-v0.38 (webrtc-direct) | rust-v0.54 | go-v0.38 | webrtc-direct | - | - | ✅ | 4s | 14.159 | 0.399 |
| rust-v0.54 x go-v0.39 (ws, tls, yamux) | rust-v0.54 | go-v0.39 | ws | tls | yamux | ✅ | 4s | 93.844 | 0.978 |
| rust-v0.54 x go-v0.39 (ws, noise, yamux) | rust-v0.54 | go-v0.39 | ws | noise | yamux | ✅ | 4s | 94.044 | 0.219 |
| rust-v0.54 x go-v0.39 (tcp, tls, yamux) | rust-v0.54 | go-v0.39 | tcp | tls | yamux | ✅ | 5s | 5.975 | 0.309 |
| rust-v0.54 x go-v0.39 (tcp, noise, yamux) | rust-v0.54 | go-v0.39 | tcp | noise | yamux | ✅ | 4s | 45.184 | 42.126 |
| rust-v0.54 x go-v0.39 (quic-v1) | rust-v0.54 | go-v0.39 | quic-v1 | - | - | ✅ | 5s | 5.786 | 0.459 |
| rust-v0.54 x go-v0.39 (webrtc-direct) | rust-v0.54 | go-v0.39 | webrtc-direct | - | - | ✅ | 4s | 7.62 | 0.26 |
| rust-v0.54 x go-v0.40 (ws, tls, yamux) | rust-v0.54 | go-v0.40 | ws | tls | yamux | ✅ | 4s | 95.168 | 0.179 |
| rust-v0.54 x go-v0.40 (tcp, tls, yamux) | rust-v0.54 | go-v0.40 | tcp | tls | yamux | ✅ | 4s | 5.67 | 0.851 |
| rust-v0.54 x go-v0.40 (ws, noise, yamux) | rust-v0.54 | go-v0.40 | ws | noise | yamux | ✅ | 5s | 133.66 | 41.233 |
| rust-v0.54 x go-v0.40 (tcp, noise, yamux) | rust-v0.54 | go-v0.40 | tcp | noise | yamux | ✅ | 4s | 2.352 | 0.152 |
| rust-v0.54 x go-v0.40 (quic-v1) | rust-v0.54 | go-v0.40 | quic-v1 | - | - | ✅ | 5s | 6.144 | 0.395 |
| rust-v0.54 x go-v0.40 (webrtc-direct) | rust-v0.54 | go-v0.40 | webrtc-direct | - | - | ✅ | 4s | 17.936 | 3.331 |
| rust-v0.54 x go-v0.41 (ws, tls, yamux) | rust-v0.54 | go-v0.41 | ws | tls | yamux | ✅ | 5s | 47.813 | 0.132 |
| rust-v0.54 x go-v0.41 (ws, noise, yamux) | rust-v0.54 | go-v0.41 | ws | noise | yamux | ✅ | 4s | 92.941 | 0.628 |
| rust-v0.54 x go-v0.41 (tcp, tls, yamux) | rust-v0.54 | go-v0.41 | tcp | tls | yamux | ✅ | 4s | 7.013 | 0.348 |
| rust-v0.54 x go-v0.41 (tcp, noise, yamux) | rust-v0.54 | go-v0.41 | tcp | noise | yamux | ✅ | 4s | 3.674 | 0.296 |
| rust-v0.54 x go-v0.41 (webrtc-direct) | rust-v0.54 | go-v0.41 | webrtc-direct | - | - | ✅ | 4s | 9.81 | 0.351 |
| rust-v0.54 x go-v0.41 (quic-v1) | rust-v0.54 | go-v0.41 | quic-v1 | - | - | ✅ | 5s | 4.324 | 0.251 |
| rust-v0.54 x go-v0.42 (ws, tls, yamux) | rust-v0.54 | go-v0.42 | ws | tls | yamux | ✅ | 5s | 88.132 | 0.431 |
| rust-v0.54 x go-v0.42 (tcp, tls, yamux) | rust-v0.54 | go-v0.42 | tcp | tls | yamux | ✅ | 4s | 3.379 | 0.345 |
| rust-v0.54 x go-v0.42 (ws, noise, yamux) | rust-v0.54 | go-v0.42 | ws | noise | yamux | ✅ | 6s | 91.985 | 1.393 |
| rust-v0.54 x go-v0.42 (tcp, noise, yamux) | rust-v0.54 | go-v0.42 | tcp | noise | yamux | ✅ | 5s | 2.799 | 0.366 |
| rust-v0.54 x go-v0.42 (quic-v1) | rust-v0.54 | go-v0.42 | quic-v1 | - | - | ✅ | 4s | 4.206 | 0.172 |
| rust-v0.54 x go-v0.42 (webrtc-direct) | rust-v0.54 | go-v0.42 | webrtc-direct | - | - | ✅ | 4s | 12.882 | 0.244 |
| rust-v0.54 x go-v0.43 (ws, tls, yamux) | rust-v0.54 | go-v0.43 | ws | tls | yamux | ✅ | 4s | 100.17 | 0.246 |
| rust-v0.54 x go-v0.43 (ws, noise, yamux) | rust-v0.54 | go-v0.43 | ws | noise | yamux | ✅ | 4s | 92.434 | 0.176 |
| rust-v0.54 x go-v0.43 (tcp, tls, yamux) | rust-v0.54 | go-v0.43 | tcp | tls | yamux | ✅ | 4s | 6.431 | 2.972 |
| rust-v0.54 x go-v0.43 (quic-v1) | rust-v0.54 | go-v0.43 | quic-v1 | - | - | ✅ | 4s | 3.919 | 0.229 |
| rust-v0.54 x go-v0.43 (tcp, noise, yamux) | rust-v0.54 | go-v0.43 | tcp | noise | yamux | ✅ | 4s | 2.565 | 0.216 |
| rust-v0.54 x go-v0.43 (webrtc-direct) | rust-v0.54 | go-v0.43 | webrtc-direct | - | - | ✅ | 4s | 6.777 | 0.161 |
| rust-v0.54 x go-v0.44 (ws, tls, yamux) | rust-v0.54 | go-v0.44 | ws | tls | yamux | ✅ | 5s | 92.393 | 0.492 |
| rust-v0.54 x go-v0.44 (ws, noise, yamux) | rust-v0.54 | go-v0.44 | ws | noise | yamux | ✅ | 4s | 93.162 | 0.318 |
| rust-v0.54 x go-v0.44 (tcp, tls, yamux) | rust-v0.54 | go-v0.44 | tcp | tls | yamux | ✅ | 4s | 46.421 | 42.533 |
| rust-v0.54 x go-v0.44 (tcp, noise, yamux) | rust-v0.54 | go-v0.44 | tcp | noise | yamux | ✅ | 4s | 3.937 | 0.761 |
| rust-v0.54 x go-v0.44 (quic-v1) | rust-v0.54 | go-v0.44 | quic-v1 | - | - | ✅ | 4s | 4.354 | 0.274 |
| rust-v0.54 x go-v0.44 (webrtc-direct) | rust-v0.54 | go-v0.44 | webrtc-direct | - | - | ✅ | 4s | 9.995 | 0.245 |
| rust-v0.54 x go-v0.45 (ws, tls, yamux) | rust-v0.54 | go-v0.45 | ws | tls | yamux | ✅ | 5s | 92.911 | 0.199 |
| rust-v0.54 x go-v0.45 (ws, noise, yamux) | rust-v0.54 | go-v0.45 | ws | noise | yamux | ✅ | 4s | 89.457 | 0.767 |
| rust-v0.54 x go-v0.45 (tcp, tls, yamux) | rust-v0.54 | go-v0.45 | tcp | tls | yamux | ✅ | 4s | 45.545 | 41.233 |
| rust-v0.54 x go-v0.45 (tcp, noise, yamux) | rust-v0.54 | go-v0.45 | tcp | noise | yamux | ✅ | 5s | 6.177 | 0.53 |
| rust-v0.54 x go-v0.45 (quic-v1) | rust-v0.54 | go-v0.45 | quic-v1 | - | - | ✅ | 4s | 6.02 | 0.116 |
| rust-v0.54 x go-v0.45 (webrtc-direct) | rust-v0.54 | go-v0.45 | webrtc-direct | - | - | ✅ | 5s | 7.633 | 0.197 |
| rust-v0.54 x python-v0.4 (ws, noise, mplex) | rust-v0.54 | python-v0.4 | ws | noise | mplex | ✅ | 5s | 148.84 | 47.55 |
| rust-v0.54 x python-v0.4 (ws, noise, yamux) | rust-v0.54 | python-v0.4 | ws | noise | yamux | ✅ | 5s | 102.516 | 1.225 |
| rust-v0.54 x python-v0.4 (tcp, noise, mplex) | rust-v0.54 | python-v0.4 | tcp | noise | mplex | ✅ | 4s | 15.586 | 0.641 |
| rust-v0.54 x python-v0.4 (tcp, noise, yamux) | rust-v0.54 | python-v0.4 | tcp | noise | yamux | ✅ | 5s | 12.815 | 0.69 |
| rust-v0.54 x python-v0.4 (quic-v1) | rust-v0.54 | python-v0.4 | quic-v1 | - | - | ✅ | 4s | 34.592 | 10.007 |
| rust-v0.54 x js-v1.x (ws, noise, mplex) | rust-v0.54 | js-v1.x | ws | noise | mplex | ✅ | 13s | 196.248 | 11.82 |
| rust-v0.54 x js-v1.x (ws, noise, yamux) | rust-v0.54 | js-v1.x | ws | noise | yamux | ✅ | 14s | 211.933 | 12.603 |
| rust-v0.54 x js-v1.x (tcp, noise, mplex) | rust-v0.54 | js-v1.x | tcp | noise | mplex | ✅ | 14s | 117.907 | 12.307 |
| rust-v0.54 x js-v1.x (tcp, noise, yamux) | rust-v0.54 | js-v1.x | tcp | noise | yamux | ✅ | 14s | 115.368 | 8.593 |
| rust-v0.54 x js-v2.x (ws, noise, mplex) | rust-v0.54 | js-v2.x | ws | noise | mplex | ✅ | 14s | 149.036 | 11.076 |
| rust-v0.54 x js-v2.x (ws, noise, yamux) | rust-v0.54 | js-v2.x | ws | noise | yamux | ✅ | 14s | 167.322 | 6.377 |
| rust-v0.54 x js-v2.x (tcp, noise, mplex) | rust-v0.54 | js-v2.x | tcp | noise | mplex | ✅ | 14s | 99.798 | 8.235 |
| rust-v0.54 x nim-v1.14 (ws, noise, mplex) | rust-v0.54 | nim-v1.14 | ws | noise | mplex | ✅ | 4s | 282.745 | 87.808 |
| rust-v0.54 x nim-v1.14 (ws, noise, yamux) | rust-v0.54 | nim-v1.14 | ws | noise | yamux | ✅ | 4s | 234.42 | 48.834 |
| rust-v0.54 x nim-v1.14 (tcp, noise, mplex) | rust-v0.54 | nim-v1.14 | tcp | noise | mplex | ✅ | 4s | 101.511 | 0.248 |
| rust-v0.54 x js-v2.x (tcp, noise, yamux) | rust-v0.54 | js-v2.x | tcp | noise | yamux | ✅ | 14s | 119.931 | 7.237 |
| rust-v0.54 x nim-v1.14 (tcp, noise, yamux) | rust-v0.54 | nim-v1.14 | tcp | noise | yamux | ✅ | 4s | 181.987 | 45.074 |
| rust-v0.54 x js-v3.x (ws, noise, mplex) | rust-v0.54 | js-v3.x | ws | noise | mplex | ✅ | 13s | 148.228 | 13.402 |
| rust-v0.54 x js-v3.x (ws, noise, yamux) | rust-v0.54 | js-v3.x | ws | noise | yamux | ✅ | 13s | 143.147 | 19.428 |
| rust-v0.54 x js-v3.x (tcp, noise, mplex) | rust-v0.54 | js-v3.x | tcp | noise | mplex | ✅ | 13s | 78.445 | 7.999 |
| rust-v0.54 x js-v3.x (tcp, noise, yamux) | rust-v0.54 | js-v3.x | tcp | noise | yamux | ✅ | 13s | 156.29 | 71.076 |
| rust-v0.54 x jvm-v1.2 (ws, noise, mplex) | rust-v0.54 | jvm-v1.2 | ws | noise | mplex | ✅ | 9s | 1439.816 | 15.438 |
| rust-v0.54 x jvm-v1.2 (ws, tls, mplex) | rust-v0.54 | jvm-v1.2 | ws | tls | mplex | ✅ | 12s | 4821.361 | 4.766 |
| rust-v0.54 x jvm-v1.2 (ws, noise, yamux) | rust-v0.54 | jvm-v1.2 | ws | noise | yamux | ✅ | 10s | 1649.654 | 49.721 |
| rust-v0.54 x jvm-v1.2 (ws, tls, yamux) | rust-v0.54 | jvm-v1.2 | ws | tls | yamux | ✅ | 12s | 4225.972 | 45.944 |
| rust-v0.54 x jvm-v1.2 (tcp, noise, mplex) | rust-v0.54 | jvm-v1.2 | tcp | noise | mplex | ✅ | 9s | 893.009 | 12.601 |
| rust-v0.54 x jvm-v1.2 (tcp, tls, mplex) | rust-v0.54 | jvm-v1.2 | tcp | tls | mplex | ✅ | 12s | 2920.621 | 4.59 |
| rust-v0.54 x jvm-v1.2 (tcp, tls, yamux) | rust-v0.54 | jvm-v1.2 | tcp | tls | yamux | ✅ | 11s | 2385.137 | 45.51 |
| rust-v0.54 x c-v0.0.1 (tcp, noise, mplex) | rust-v0.54 | c-v0.0.1 | tcp | noise | mplex | ✅ | 4s | 54.607 | 3.29 |
| rust-v0.54 x c-v0.0.1 (tcp, noise, yamux) | rust-v0.54 | c-v0.0.1 | tcp | noise | yamux | ✅ | 4s | 102.982 | 3.227 |
| rust-v0.54 x jvm-v1.2 (tcp, noise, yamux) | rust-v0.54 | jvm-v1.2 | tcp | noise | yamux | ✅ | 6s | 610.6 | 6.273 |
| rust-v0.54 x c-v0.0.1 (quic-v1) | rust-v0.54 | c-v0.0.1 | quic-v1 | - | - | ✅ | 5s | 12.449 | 2.874 |
| rust-v0.54 x dotnet-v1.0 (tcp, noise, yamux) | rust-v0.54 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 5s | 209.322 | 44.755 |
| rust-v0.54 x zig-v0.0.1 (quic-v1) | rust-v0.54 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 5s | - | - |
| rust-v0.54 x jvm-v1.2 (quic-v1) | rust-v0.54 | jvm-v1.2 | quic-v1 | - | - | ✅ | 8s | 1189.405 | 3.925 |
| rust-v0.54 x eth-p2p-z-v0.0.1 (quic-v1) | rust-v0.54 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 3s | 4.628 | 0.186 |
| rust-v0.55 x rust-v0.53 (ws, noise, mplex) | rust-v0.55 | rust-v0.53 | ws | noise | mplex | ✅ | 4s | 86.752 | 0.278 |
| rust-v0.55 x rust-v0.53 (ws, tls, yamux) | rust-v0.55 | rust-v0.53 | ws | tls | yamux | ✅ | 5s | 129.224 | 43.268 |
| rust-v0.55 x rust-v0.53 (ws, tls, mplex) | rust-v0.55 | rust-v0.53 | ws | tls | mplex | ✅ | 6s | 88.109 | 0.329 |
| rust-v0.55 x rust-v0.53 (ws, noise, yamux) | rust-v0.55 | rust-v0.53 | ws | noise | yamux | ✅ | 5s | 130.422 | 43.648 |
| rust-v0.55 x rust-v0.53 (tcp, tls, mplex) | rust-v0.55 | rust-v0.53 | tcp | tls | mplex | ✅ | 4s | 46.716 | 0.206 |
| rust-v0.55 x rust-v0.53 (tcp, tls, yamux) | rust-v0.55 | rust-v0.53 | tcp | tls | yamux | ✅ | 4s | 86.588 | 43.644 |
| rust-v0.55 x rust-v0.53 (tcp, noise, mplex) | rust-v0.55 | rust-v0.53 | tcp | noise | mplex | ✅ | 4s | 48.185 | 0.163 |
| rust-v0.55 x rust-v0.53 (tcp, noise, yamux) | rust-v0.55 | rust-v0.53 | tcp | noise | yamux | ✅ | 4s | 46.545 | 0.296 |
| rust-v0.55 x rust-v0.53 (quic-v1) | rust-v0.55 | rust-v0.53 | quic-v1 | - | - | ✅ | 4s | 7.122 | 1.21 |
| rust-v0.55 x rust-v0.53 (webrtc-direct) | rust-v0.55 | rust-v0.53 | webrtc-direct | - | - | ✅ | 4s | 287.405 | 0.208 |
| rust-v0.55 x rust-v0.54 (ws, tls, mplex) | rust-v0.55 | rust-v0.54 | ws | tls | mplex | ✅ | 5s | 89.065 | 0.452 |
| rust-v0.55 x rust-v0.54 (ws, tls, yamux) | rust-v0.55 | rust-v0.54 | ws | tls | yamux | ✅ | 4s | 139.091 | 43.638 |
| rust-v0.55 x rust-v0.54 (ws, noise, mplex) | rust-v0.55 | rust-v0.54 | ws | noise | mplex | ✅ | 5s | 92.307 | 0.265 |
| rust-v0.55 x rust-v0.54 (ws, noise, yamux) | rust-v0.55 | rust-v0.54 | ws | noise | yamux | ✅ | 4s | 144.546 | 47.718 |
| rust-v0.55 x rust-v0.54 (tcp, tls, yamux) | rust-v0.55 | rust-v0.54 | tcp | tls | yamux | ✅ | 3s | 87.568 | 42.579 |
| rust-v0.55 x rust-v0.54 (tcp, tls, mplex) | rust-v0.55 | rust-v0.54 | tcp | tls | mplex | ✅ | 5s | 51.613 | 0.591 |
| rust-v0.55 x rust-v0.54 (tcp, noise, mplex) | rust-v0.55 | rust-v0.54 | tcp | noise | mplex | ✅ | 5s | 2.242 | 0.052 |
| rust-v0.55 x rust-v0.54 (tcp, noise, yamux) | rust-v0.55 | rust-v0.54 | tcp | noise | yamux | ✅ | 4s | 93.069 | 43.706 |
| rust-v0.55 x rust-v0.54 (quic-v1) | rust-v0.55 | rust-v0.54 | quic-v1 | - | - | ✅ | 4s | 7.922 | 0.442 |
| rust-v0.55 x rust-v0.54 (webrtc-direct) | rust-v0.55 | rust-v0.54 | webrtc-direct | - | - | ✅ | 5s | 209.902 | 0.247 |
| rust-v0.55 x rust-v0.55 (ws, tls, mplex) | rust-v0.55 | rust-v0.55 | ws | tls | mplex | ✅ | 4s | 8.457 | 0.356 |
| rust-v0.55 x rust-v0.55 (ws, tls, yamux) | rust-v0.55 | rust-v0.55 | ws | tls | yamux | ✅ | 4s | 4.598 | 0.142 |
| rust-v0.55 x rust-v0.55 (ws, noise, yamux) | rust-v0.55 | rust-v0.55 | ws | noise | yamux | ✅ | 4s | 2.783 | 0.188 |
| rust-v0.55 x rust-v0.55 (ws, noise, mplex) | rust-v0.55 | rust-v0.55 | ws | noise | mplex | ✅ | 6s | 4.492 | 0.184 |
| rust-v0.55 x rust-v0.55 (tcp, tls, mplex) | rust-v0.55 | rust-v0.55 | tcp | tls | mplex | ✅ | 4s | 3.41 | 0.105 |
| rust-v0.55 x rust-v0.55 (tcp, tls, yamux) | rust-v0.55 | rust-v0.55 | tcp | tls | yamux | ✅ | 5s | 2.474 | 0.097 |
| rust-v0.55 x rust-v0.55 (tcp, noise, mplex) | rust-v0.55 | rust-v0.55 | tcp | noise | mplex | ✅ | 4s | 1.719 | 0.049 |
| rust-v0.55 x rust-v0.55 (tcp, noise, yamux) | rust-v0.55 | rust-v0.55 | tcp | noise | yamux | ✅ | 4s | 2.992 | 0.178 |
| rust-v0.55 x rust-v0.55 (quic-v1) | rust-v0.55 | rust-v0.55 | quic-v1 | - | - | ✅ | 4s | 2.773 | 0.162 |
| rust-v0.55 x rust-v0.56 (ws, tls, mplex) | rust-v0.55 | rust-v0.56 | ws | tls | mplex | ✅ | 4s | 4.568 | 0.086 |
| rust-v0.55 x rust-v0.55 (webrtc-direct) | rust-v0.55 | rust-v0.55 | webrtc-direct | - | - | ✅ | 4s | 209.214 | 0.471 |
| rust-v0.55 x rust-v0.56 (ws, tls, yamux) | rust-v0.55 | rust-v0.56 | ws | tls | yamux | ✅ | 4s | 6.644 | 0.157 |
| rust-v0.55 x rust-v0.56 (ws, noise, mplex) | rust-v0.55 | rust-v0.56 | ws | noise | mplex | ✅ | 5s | 3.182 | 0.484 |
| rust-v0.53 x go-v0.40 (webrtc-direct) | rust-v0.53 | go-v0.40 | webrtc-direct | - | - | ❌ | 195s | - | - |
| rust-v0.55 x rust-v0.56 (tcp, tls, mplex) | rust-v0.55 | rust-v0.56 | tcp | tls | mplex | ✅ | 5s | 4.229 | 0.073 |
| rust-v0.55 x rust-v0.56 (ws, noise, yamux) | rust-v0.55 | rust-v0.56 | ws | noise | yamux | ✅ | 5s | 8.407 | 0.148 |
| rust-v0.55 x rust-v0.56 (tcp, tls, yamux) | rust-v0.55 | rust-v0.56 | tcp | tls | yamux | ✅ | 4s | 5.442 | 0.185 |
| rust-v0.55 x rust-v0.56 (tcp, noise, mplex) | rust-v0.55 | rust-v0.56 | tcp | noise | mplex | ✅ | 4s | 2.298 | 0.054 |
| rust-v0.55 x rust-v0.56 (tcp, noise, yamux) | rust-v0.55 | rust-v0.56 | tcp | noise | yamux | ✅ | 5s | 5.588 | 0.169 |
| rust-v0.55 x rust-v0.56 (quic-v1) | rust-v0.55 | rust-v0.56 | quic-v1 | - | - | ✅ | 4s | 4.064 | 0.263 |
| rust-v0.55 x rust-v0.56 (webrtc-direct) | rust-v0.55 | rust-v0.56 | webrtc-direct | - | - | ✅ | 5s | 240.694 | 0.305 |
| rust-v0.55 x go-v0.38 (ws, tls, yamux) | rust-v0.55 | go-v0.38 | ws | tls | yamux | ✅ | 4s | 6.498 | 0.991 |
| rust-v0.55 x go-v0.38 (tcp, tls, yamux) | rust-v0.55 | go-v0.38 | tcp | tls | yamux | ✅ | 4s | 7.507 | 1.279 |
| rust-v0.55 x go-v0.38 (ws, noise, yamux) | rust-v0.55 | go-v0.38 | ws | noise | yamux | ✅ | 5s | 3.886 | 0.167 |
| rust-v0.55 x go-v0.38 (tcp, noise, yamux) | rust-v0.55 | go-v0.38 | tcp | noise | yamux | ✅ | 5s | 3.184 | 0.239 |
| rust-v0.55 x go-v0.38 (quic-v1) | rust-v0.55 | go-v0.38 | quic-v1 | - | - | ✅ | 4s | 11.789 | 0.353 |
| rust-v0.55 x go-v0.38 (webrtc-direct) | rust-v0.55 | go-v0.38 | webrtc-direct | - | - | ✅ | 5s | 13.199 | 0.352 |
| rust-v0.55 x go-v0.39 (ws, tls, yamux) | rust-v0.55 | go-v0.39 | ws | tls | yamux | ✅ | 4s | 4.215 | 0.234 |
| rust-v0.55 x go-v0.39 (ws, noise, yamux) | rust-v0.55 | go-v0.39 | ws | noise | yamux | ✅ | 5s | 3.271 | 0.189 |
| rust-v0.55 x go-v0.39 (tcp, noise, yamux) | rust-v0.55 | go-v0.39 | tcp | noise | yamux | ✅ | 4s | 14.568 | 0.93 |
| rust-v0.55 x go-v0.39 (tcp, tls, yamux) | rust-v0.55 | go-v0.39 | tcp | tls | yamux | ✅ | 6s | 6.513 | 0.261 |
| rust-v0.55 x go-v0.39 (quic-v1) | rust-v0.55 | go-v0.39 | quic-v1 | - | - | ✅ | 5s | 5.877 | 0.462 |
| rust-v0.55 x go-v0.39 (webrtc-direct) | rust-v0.55 | go-v0.39 | webrtc-direct | - | - | ✅ | 5s | 11.594 | 0.28 |
| rust-v0.55 x go-v0.40 (ws, tls, yamux) | rust-v0.55 | go-v0.40 | ws | tls | yamux | ✅ | 5s | 8.788 | 1.099 |
| rust-v0.55 x go-v0.40 (ws, noise, yamux) | rust-v0.55 | go-v0.40 | ws | noise | yamux | ✅ | 5s | 6.774 | 1.857 |
| rust-v0.55 x go-v0.40 (tcp, tls, yamux) | rust-v0.55 | go-v0.40 | tcp | tls | yamux | ✅ | 5s | 2.502 | 0.126 |
| rust-v0.55 x go-v0.40 (tcp, noise, yamux) | rust-v0.55 | go-v0.40 | tcp | noise | yamux | ✅ | 4s | 6.121 | 2.972 |
| rust-v0.55 x go-v0.40 (quic-v1) | rust-v0.55 | go-v0.40 | quic-v1 | - | - | ✅ | 4s | 4.67 | 0.232 |
| rust-v0.55 x go-v0.40 (webrtc-direct) | rust-v0.55 | go-v0.40 | webrtc-direct | - | - | ✅ | 5s | 15.729 | 0.536 |
| rust-v0.55 x go-v0.41 (ws, tls, yamux) | rust-v0.55 | go-v0.41 | ws | tls | yamux | ✅ | 5s | 3.821 | 0.175 |
| rust-v0.55 x go-v0.41 (ws, noise, yamux) | rust-v0.55 | go-v0.41 | ws | noise | yamux | ✅ | 5s | 3.458 | 0.804 |
| rust-v0.55 x go-v0.41 (tcp, tls, yamux) | rust-v0.55 | go-v0.41 | tcp | tls | yamux | ✅ | 5s | 7.782 | 0.312 |
| rust-v0.55 x go-v0.41 (tcp, noise, yamux) | rust-v0.55 | go-v0.41 | tcp | noise | yamux | ✅ | 5s | 2.952 | 0.188 |
| rust-v0.55 x go-v0.41 (quic-v1) | rust-v0.55 | go-v0.41 | quic-v1 | - | - | ✅ | 5s | 8.635 | 0.221 |
| rust-v0.55 x go-v0.41 (webrtc-direct) | rust-v0.55 | go-v0.41 | webrtc-direct | - | - | ✅ | 4s | 8.963 | 0.326 |
| rust-v0.55 x go-v0.42 (ws, tls, yamux) | rust-v0.55 | go-v0.42 | ws | tls | yamux | ✅ | 4s | 4.566 | 0.606 |
| rust-v0.55 x go-v0.42 (ws, noise, yamux) | rust-v0.55 | go-v0.42 | ws | noise | yamux | ✅ | 4s | 4.78 | 0.276 |
| rust-v0.55 x go-v0.42 (tcp, tls, yamux) | rust-v0.55 | go-v0.42 | tcp | tls | yamux | ✅ | 5s | 3.2 | 0.325 |
| rust-v0.55 x go-v0.42 (tcp, noise, yamux) | rust-v0.55 | go-v0.42 | tcp | noise | yamux | ✅ | 5s | 2.119 | 0.085 |
| rust-v0.55 x go-v0.42 (quic-v1) | rust-v0.55 | go-v0.42 | quic-v1 | - | - | ✅ | 4s | 11.746 | 0.467 |
| rust-v0.55 x go-v0.43 (ws, tls, yamux) | rust-v0.55 | go-v0.43 | ws | tls | yamux | ✅ | 4s | 3.14 | 0.305 |
| rust-v0.55 x go-v0.43 (ws, noise, yamux) | rust-v0.55 | go-v0.43 | ws | noise | yamux | ✅ | 5s | 3.416 | 0.619 |
| rust-v0.55 x go-v0.42 (webrtc-direct) | rust-v0.55 | go-v0.42 | webrtc-direct | - | - | ✅ | 6s | 14.488 | 0.368 |
| rust-v0.55 x go-v0.43 (tcp, tls, yamux) | rust-v0.55 | go-v0.43 | tcp | tls | yamux | ✅ | 5s | 2.875 | 0.221 |
| rust-v0.55 x go-v0.43 (tcp, noise, yamux) | rust-v0.55 | go-v0.43 | tcp | noise | yamux | ✅ | 5s | 4.813 | 0.246 |
| rust-v0.55 x go-v0.43 (quic-v1) | rust-v0.55 | go-v0.43 | quic-v1 | - | - | ✅ | 5s | 7.167 | 0.532 |
| rust-v0.55 x go-v0.43 (webrtc-direct) | rust-v0.55 | go-v0.43 | webrtc-direct | - | - | ✅ | 5s | 6.566 | 0.237 |
| rust-v0.55 x go-v0.44 (ws, tls, yamux) | rust-v0.55 | go-v0.44 | ws | tls | yamux | ✅ | 5s | 6.848 | 0.535 |
| rust-v0.55 x go-v0.44 (ws, noise, yamux) | rust-v0.55 | go-v0.44 | ws | noise | yamux | ✅ | 4s | 5.486 | 0.602 |
| rust-v0.55 x go-v0.44 (tcp, tls, yamux) | rust-v0.55 | go-v0.44 | tcp | tls | yamux | ✅ | 5s | 5.358 | 0.568 |
| rust-v0.55 x go-v0.44 (tcp, noise, yamux) | rust-v0.55 | go-v0.44 | tcp | noise | yamux | ✅ | 5s | 2.824 | 0.093 |
| rust-v0.55 x go-v0.44 (quic-v1) | rust-v0.55 | go-v0.44 | quic-v1 | - | - | ✅ | 5s | 4.692 | 0.753 |
| rust-v0.55 x go-v0.44 (webrtc-direct) | rust-v0.55 | go-v0.44 | webrtc-direct | - | - | ✅ | 5s | 213.154 | 0.324 |
| rust-v0.55 x go-v0.45 (ws, tls, yamux) | rust-v0.55 | go-v0.45 | ws | tls | yamux | ✅ | 4s | 3.061 | 0.312 |
| rust-v0.55 x go-v0.45 (ws, noise, yamux) | rust-v0.55 | go-v0.45 | ws | noise | yamux | ✅ | 5s | 5.165 | 0.913 |
| rust-v0.55 x go-v0.45 (tcp, tls, yamux) | rust-v0.55 | go-v0.45 | tcp | tls | yamux | ✅ | 5s | 6.766 | 0.414 |
| rust-v0.55 x go-v0.45 (tcp, noise, yamux) | rust-v0.55 | go-v0.45 | tcp | noise | yamux | ✅ | 4s | 10.354 | 0.347 |
| rust-v0.55 x go-v0.45 (quic-v1) | rust-v0.55 | go-v0.45 | quic-v1 | - | - | ✅ | 5s | 11.891 | 0.635 |
| rust-v0.55 x go-v0.45 (webrtc-direct) | rust-v0.55 | go-v0.45 | webrtc-direct | - | - | ✅ | 4s | 189.488 | 0.943 |
| rust-v0.55 x python-v0.4 (ws, noise, mplex) | rust-v0.55 | python-v0.4 | ws | noise | mplex | ✅ | 5s | 12.674 | 1.126 |
| rust-v0.55 x python-v0.4 (ws, noise, yamux) | rust-v0.55 | python-v0.4 | ws | noise | yamux | ✅ | 4s | 14.225 | 1.08 |
| rust-v0.55 x python-v0.4 (tcp, noise, mplex) | rust-v0.55 | python-v0.4 | tcp | noise | mplex | ✅ | 5s | 9.976 | 0.684 |
| rust-v0.55 x python-v0.4 (tcp, noise, yamux) | rust-v0.55 | python-v0.4 | tcp | noise | yamux | ✅ | 5s | 12.492 | 0.575 |
| rust-v0.55 x python-v0.4 (quic-v1) | rust-v0.55 | python-v0.4 | quic-v1 | - | - | ✅ | 5s | 38.37 | 6.938 |
| rust-v0.55 x js-v1.x (ws, noise, mplex) | rust-v0.55 | js-v1.x | ws | noise | mplex | ✅ | 17s | 123.575 | 12.243 |
| rust-v0.55 x js-v1.x (ws, noise, yamux) | rust-v0.55 | js-v1.x | ws | noise | yamux | ✅ | 18s | 135.364 | 13.838 |
| rust-v0.55 x js-v1.x (tcp, noise, mplex) | rust-v0.55 | js-v1.x | tcp | noise | mplex | ✅ | 18s | 107.906 | 10.44 |
| rust-v0.55 x js-v1.x (tcp, noise, yamux) | rust-v0.55 | js-v1.x | tcp | noise | yamux | ✅ | 18s | 121.867 | 11.966 |
| rust-v0.55 x js-v2.x (ws, noise, mplex) | rust-v0.55 | js-v2.x | ws | noise | mplex | ✅ | 19s | 133.486 | 12.69 |
| rust-v0.55 x js-v2.x (ws, noise, yamux) | rust-v0.55 | js-v2.x | ws | noise | yamux | ✅ | 18s | 118.922 | 12.599 |
| rust-v0.55 x js-v2.x (tcp, noise, mplex) | rust-v0.55 | js-v2.x | tcp | noise | mplex | ✅ | 18s | 104.516 | 28.677 |
| rust-v0.55 x js-v2.x (tcp, noise, yamux) | rust-v0.55 | js-v2.x | tcp | noise | yamux | ✅ | 17s | 91.791 | 6.324 |
| rust-v0.55 x nim-v1.14 (ws, noise, mplex) | rust-v0.55 | nim-v1.14 | ws | noise | mplex | ✅ | 4s | 154.048 | 47.758 |
| rust-v0.55 x nim-v1.14 (ws, noise, yamux) | rust-v0.55 | nim-v1.14 | ws | noise | yamux | ✅ | 5s | 103.306 | 2.981 |
| rust-v0.55 x nim-v1.14 (tcp, noise, mplex) | rust-v0.55 | nim-v1.14 | tcp | noise | mplex | ✅ | 5s | 65.032 | 0.227 |
| rust-v0.55 x nim-v1.14 (tcp, noise, yamux) | rust-v0.55 | nim-v1.14 | tcp | noise | yamux | ✅ | 4s | 108.845 | 1.072 |
| rust-v0.55 x js-v3.x (ws, noise, mplex) | rust-v0.55 | js-v3.x | ws | noise | mplex | ✅ | 15s | 131.299 | 19.05 |
| rust-v0.55 x js-v3.x (ws, noise, yamux) | rust-v0.55 | js-v3.x | ws | noise | yamux | ✅ | 16s | 160.325 | 27.326 |
| rust-v0.55 x js-v3.x (tcp, noise, mplex) | rust-v0.55 | js-v3.x | tcp | noise | mplex | ✅ | 16s | 104.921 | 16.901 |
| rust-v0.55 x js-v3.x (tcp, noise, yamux) | rust-v0.55 | js-v3.x | tcp | noise | yamux | ✅ | 18s | 175.976 | 22.848 |
| rust-v0.55 x jvm-v1.2 (ws, noise, mplex) | rust-v0.55 | jvm-v1.2 | ws | noise | mplex | ✅ | 10s | 1296.944 | 8.462 |
| rust-v0.55 x jvm-v1.2 (ws, tls, mplex) | rust-v0.55 | jvm-v1.2 | ws | tls | mplex | ✅ | 13s | 4499.154 | 4.063 |
| rust-v0.55 x jvm-v1.2 (ws, noise, yamux) | rust-v0.55 | jvm-v1.2 | ws | noise | yamux | ✅ | 10s | 1182.236 | 4.41 |
| rust-v0.55 x jvm-v1.2 (ws, tls, yamux) | rust-v0.55 | jvm-v1.2 | ws | tls | yamux | ✅ | 12s | 3418.866 | 5.603 |
| rust-v0.55 x jvm-v1.2 (tcp, tls, mplex) | rust-v0.55 | jvm-v1.2 | tcp | tls | mplex | ✅ | 11s | 3361.641 | 3.202 |
| rust-v0.55 x c-v0.0.1 (tcp, noise, mplex) | rust-v0.55 | c-v0.0.1 | tcp | noise | mplex | ✅ | 6s | 17.915 | 6.784 |
| rust-v0.55 x c-v0.0.1 (tcp, noise, yamux) | rust-v0.55 | c-v0.0.1 | tcp | noise | yamux | ✅ | 6s | 72.523 | 0.453 |
| rust-v0.55 x jvm-v1.2 (tcp, noise, mplex) | rust-v0.55 | jvm-v1.2 | tcp | noise | mplex | ✅ | 10s | 783.664 | 3.055 |
| rust-v0.55 x jvm-v1.2 (tcp, tls, yamux) | rust-v0.55 | jvm-v1.2 | tcp | tls | yamux | ✅ | 13s | 4000.971 | 7.978 |
| rust-v0.55 x jvm-v1.2 (tcp, noise, yamux) | rust-v0.55 | jvm-v1.2 | tcp | noise | yamux | ✅ | 11s | 1181.391 | 11.765 |
| rust-v0.55 x jvm-v1.2 (quic-v1) | rust-v0.55 | jvm-v1.2 | quic-v1 | - | - | ✅ | 11s | 624.319 | 7.271 |
| rust-v0.55 x c-v0.0.1 (quic-v1) | rust-v0.55 | c-v0.0.1 | quic-v1 | - | - | ✅ | 10s | 5023.79 | 0.482 |
| rust-v0.55 x zig-v0.0.1 (quic-v1) | rust-v0.55 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 5s | - | - |
| rust-v0.55 x dotnet-v1.0 (tcp, noise, yamux) | rust-v0.55 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 5s | 97.369 | 4.097 |
| rust-v0.55 x eth-p2p-z-v0.0.1 (quic-v1) | rust-v0.55 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 5s | 5.318 | 0.269 |
| rust-v0.56 x rust-v0.53 (ws, tls, mplex) | rust-v0.56 | rust-v0.53 | ws | tls | mplex | ✅ | 5s | 90.795 | 0.295 |
| rust-v0.56 x rust-v0.53 (ws, tls, yamux) | rust-v0.56 | rust-v0.53 | ws | tls | yamux | ✅ | 6s | 135.132 | 43.46 |
| rust-v0.56 x rust-v0.53 (ws, noise, mplex) | rust-v0.56 | rust-v0.53 | ws | noise | mplex | ✅ | 5s | 90.828 | 0.239 |
| rust-v0.56 x rust-v0.53 (ws, noise, yamux) | rust-v0.56 | rust-v0.53 | ws | noise | yamux | ✅ | 5s | 141.362 | 47.549 |
| rust-v0.56 x rust-v0.53 (tcp, tls, mplex) | rust-v0.56 | rust-v0.53 | tcp | tls | mplex | ✅ | 5s | 55.719 | 1.106 |
| rust-v0.56 x rust-v0.53 (tcp, tls, yamux) | rust-v0.56 | rust-v0.53 | tcp | tls | yamux | ✅ | 5s | 91.794 | 47.801 |
| rust-v0.56 x rust-v0.53 (tcp, noise, mplex) | rust-v0.56 | rust-v0.53 | tcp | noise | mplex | ✅ | 4s | 49.66 | 0.641 |
| rust-v0.56 x rust-v0.53 (tcp, noise, yamux) | rust-v0.56 | rust-v0.53 | tcp | noise | yamux | ✅ | 5s | 46.231 | 0.179 |
| rust-v0.56 x rust-v0.53 (quic-v1) | rust-v0.56 | rust-v0.53 | quic-v1 | - | - | ✅ | 5s | 3.327 | 0.326 |
| rust-v0.56 x rust-v0.54 (ws, tls, mplex) | rust-v0.56 | rust-v0.54 | ws | tls | mplex | ✅ | 4s | 94.383 | 0.318 |
| rust-v0.56 x rust-v0.53 (webrtc-direct) | rust-v0.56 | rust-v0.53 | webrtc-direct | - | - | ✅ | 6s | 410.162 | 0.316 |
| rust-v0.56 x rust-v0.54 (ws, tls, yamux) | rust-v0.56 | rust-v0.54 | ws | tls | yamux | ✅ | 5s | 133.46 | 43.5 |
| rust-v0.56 x rust-v0.54 (ws, noise, mplex) | rust-v0.56 | rust-v0.54 | ws | noise | mplex | ✅ | 6s | 88.082 | 0.325 |
| rust-v0.56 x rust-v0.54 (tcp, tls, mplex) | rust-v0.56 | rust-v0.54 | tcp | tls | mplex | ✅ | 5s | 48.378 | 0.786 |
| rust-v0.56 x rust-v0.54 (ws, noise, yamux) | rust-v0.56 | rust-v0.54 | ws | noise | yamux | ✅ | 5s | 96.261 | 0.226 |
| rust-v0.56 x rust-v0.54 (tcp, tls, yamux) | rust-v0.56 | rust-v0.54 | tcp | tls | yamux | ✅ | 5s | 93.288 | 43.793 |
| rust-v0.56 x rust-v0.54 (tcp, noise, mplex) | rust-v0.56 | rust-v0.54 | tcp | noise | mplex | ✅ | 5s | 46.598 | 2.186 |
| rust-v0.56 x rust-v0.54 (tcp, noise, yamux) | rust-v0.56 | rust-v0.54 | tcp | noise | yamux | ✅ | 5s | 5.043 | 0.513 |
| rust-v0.56 x rust-v0.54 (quic-v1) | rust-v0.56 | rust-v0.54 | quic-v1 | - | - | ✅ | 5s | 4.706 | 0.203 |
| rust-v0.56 x rust-v0.54 (webrtc-direct) | rust-v0.56 | rust-v0.54 | webrtc-direct | - | - | ✅ | 5s | 212.135 | 0.221 |
| rust-v0.56 x rust-v0.55 (ws, tls, mplex) | rust-v0.56 | rust-v0.55 | ws | tls | mplex | ✅ | 4s | 3.022 | 0.062 |
| rust-v0.56 x rust-v0.55 (ws, noise, mplex) | rust-v0.56 | rust-v0.55 | ws | noise | mplex | ✅ | 4s | 7.96 | 0.689 |
| rust-v0.56 x rust-v0.55 (ws, tls, yamux) | rust-v0.56 | rust-v0.55 | ws | tls | yamux | ✅ | 5s | 7.509 | 0.305 |
| rust-v0.56 x rust-v0.55 (ws, noise, yamux) | rust-v0.56 | rust-v0.55 | ws | noise | yamux | ✅ | 5s | 3.093 | 0.166 |
| rust-v0.56 x rust-v0.55 (tcp, tls, mplex) | rust-v0.56 | rust-v0.55 | tcp | tls | mplex | ✅ | 4s | 8.74 | 0.282 |
| rust-v0.56 x rust-v0.55 (tcp, tls, yamux) | rust-v0.56 | rust-v0.55 | tcp | tls | yamux | ✅ | 4s | 10.042 | 0.251 |
| rust-v0.56 x rust-v0.55 (tcp, noise, mplex) | rust-v0.56 | rust-v0.55 | tcp | noise | mplex | ✅ | 4s | 3.967 | 0.188 |
| rust-v0.56 x rust-v0.55 (tcp, noise, yamux) | rust-v0.56 | rust-v0.55 | tcp | noise | yamux | ✅ | 4s | 3.882 | 0.134 |
| rust-v0.56 x rust-v0.55 (quic-v1) | rust-v0.56 | rust-v0.55 | quic-v1 | - | - | ✅ | 4s | 6.196 | 1.117 |
| rust-v0.56 x rust-v0.55 (webrtc-direct) | rust-v0.56 | rust-v0.55 | webrtc-direct | - | - | ✅ | 5s | 208.773 | 0.279 |
| rust-v0.56 x rust-v0.56 (ws, tls, mplex) | rust-v0.56 | rust-v0.56 | ws | tls | mplex | ✅ | 4s | 3.107 | 0.098 |
| rust-v0.56 x rust-v0.56 (ws, tls, yamux) | rust-v0.56 | rust-v0.56 | ws | tls | yamux | ✅ | 5s | 2.99 | 0.162 |
| rust-v0.56 x rust-v0.56 (ws, noise, mplex) | rust-v0.56 | rust-v0.56 | ws | noise | mplex | ✅ | 5s | 4.654 | 0.136 |
| rust-v0.56 x rust-v0.56 (ws, noise, yamux) | rust-v0.56 | rust-v0.56 | ws | noise | yamux | ✅ | 5s | 2.72 | 0.143 |
| rust-v0.56 x rust-v0.56 (tcp, tls, yamux) | rust-v0.56 | rust-v0.56 | tcp | tls | yamux | ✅ | 5s | 3.298 | 0.121 |
| rust-v0.56 x rust-v0.56 (tcp, tls, mplex) | rust-v0.56 | rust-v0.56 | tcp | tls | mplex | ✅ | 6s | 4.381 | 0.042 |
| rust-v0.56 x rust-v0.56 (tcp, noise, mplex) | rust-v0.56 | rust-v0.56 | tcp | noise | mplex | ✅ | 6s | 7.033 | 0.105 |
| rust-v0.56 x rust-v0.56 (tcp, noise, yamux) | rust-v0.56 | rust-v0.56 | tcp | noise | yamux | ✅ | 5s | 2.627 | 0.082 |
| rust-v0.56 x rust-v0.56 (quic-v1) | rust-v0.56 | rust-v0.56 | quic-v1 | - | - | ✅ | 5s | 8.135 | 0.297 |
| rust-v0.56 x rust-v0.56 (webrtc-direct) | rust-v0.56 | rust-v0.56 | webrtc-direct | - | - | ✅ | 4s | 209.494 | 0.356 |
| rust-v0.56 x go-v0.38 (ws, tls, yamux) | rust-v0.56 | go-v0.38 | ws | tls | yamux | ✅ | 5s | 3.178 | 0.325 |
| rust-v0.56 x go-v0.38 (tcp, tls, yamux) | rust-v0.56 | go-v0.38 | tcp | tls | yamux | ✅ | 4s | 11.267 | 3.213 |
| rust-v0.56 x go-v0.38 (ws, noise, yamux) | rust-v0.56 | go-v0.38 | ws | noise | yamux | ✅ | 6s | 10.865 | 0.592 |
| rust-v0.56 x go-v0.38 (tcp, noise, yamux) | rust-v0.56 | go-v0.38 | tcp | noise | yamux | ✅ | 5s | 2.87 | 0.221 |
| rust-v0.56 x go-v0.38 (quic-v1) | rust-v0.56 | go-v0.38 | quic-v1 | - | - | ✅ | 5s | 4.104 | 0.24 |
| rust-v0.56 x go-v0.38 (webrtc-direct) | rust-v0.56 | go-v0.38 | webrtc-direct | - | - | ✅ | 5s | 31.804 | 0.522 |
| rust-v0.56 x go-v0.39 (ws, tls, yamux) | rust-v0.56 | go-v0.39 | ws | tls | yamux | ✅ | 5s | 4.272 | 0.322 |
| rust-v0.56 x go-v0.39 (tcp, tls, yamux) | rust-v0.56 | go-v0.39 | tcp | tls | yamux | ✅ | 5s | 6.046 | 0.649 |
| rust-v0.56 x go-v0.39 (ws, noise, yamux) | rust-v0.56 | go-v0.39 | ws | noise | yamux | ✅ | 5s | 5.909 | 0.308 |
| rust-v0.56 x go-v0.39 (tcp, noise, yamux) | rust-v0.56 | go-v0.39 | tcp | noise | yamux | ✅ | 5s | 9.596 | 0.216 |
| rust-v0.56 x go-v0.39 (quic-v1) | rust-v0.56 | go-v0.39 | quic-v1 | - | - | ✅ | 5s | 5.474 | 0.571 |
| rust-v0.56 x go-v0.39 (webrtc-direct) | rust-v0.56 | go-v0.39 | webrtc-direct | - | - | ✅ | 5s | 177.544 | 1.606 |
| rust-v0.56 x go-v0.40 (ws, tls, yamux) | rust-v0.56 | go-v0.40 | ws | tls | yamux | ✅ | 5s | 7.717 | 0.659 |
| rust-v0.56 x go-v0.40 (ws, noise, yamux) | rust-v0.56 | go-v0.40 | ws | noise | yamux | ✅ | 5s | 2.566 | 0.231 |
| rust-v0.56 x go-v0.40 (tcp, tls, yamux) | rust-v0.56 | go-v0.40 | tcp | tls | yamux | ✅ | 5s | 11.794 | 0.408 |
| rust-v0.56 x go-v0.40 (quic-v1) | rust-v0.56 | go-v0.40 | quic-v1 | - | - | ✅ | 4s | 4.759 | 0.267 |
| rust-v0.56 x go-v0.40 (tcp, noise, yamux) | rust-v0.56 | go-v0.40 | tcp | noise | yamux | ✅ | 5s | 3.616 | 0.29 |
| rust-v0.56 x go-v0.40 (webrtc-direct) | rust-v0.56 | go-v0.40 | webrtc-direct | - | - | ✅ | 5s | 21.664 | 2.669 |
| rust-v0.56 x go-v0.41 (ws, tls, yamux) | rust-v0.56 | go-v0.41 | ws | tls | yamux | ✅ | 4s | 6.418 | 0.49 |
| rust-v0.56 x go-v0.41 (tcp, tls, yamux) | rust-v0.56 | go-v0.41 | tcp | tls | yamux | ✅ | 4s | 3.371 | 0.452 |
| rust-v0.56 x go-v0.41 (ws, noise, yamux) | rust-v0.56 | go-v0.41 | ws | noise | yamux | ✅ | 5s | 2.586 | 0.209 |
| rust-v0.56 x go-v0.41 (tcp, noise, yamux) | rust-v0.56 | go-v0.41 | tcp | noise | yamux | ✅ | 5s | 4.064 | 0.134 |
| rust-v0.56 x go-v0.41 (quic-v1) | rust-v0.56 | go-v0.41 | quic-v1 | - | - | ✅ | 5s | 6.459 | 0.51 |
| rust-v0.56 x go-v0.42 (ws, tls, yamux) | rust-v0.56 | go-v0.42 | ws | tls | yamux | ✅ | 4s | 4.871 | 0.178 |
| rust-v0.56 x go-v0.41 (webrtc-direct) | rust-v0.56 | go-v0.41 | webrtc-direct | - | - | ✅ | 5s | 38.295 | 0.31 |
| rust-v0.56 x go-v0.42 (tcp, tls, yamux) | rust-v0.56 | go-v0.42 | tcp | tls | yamux | ✅ | 4s | 4.537 | 0.345 |
| rust-v0.56 x go-v0.42 (ws, noise, yamux) | rust-v0.56 | go-v0.42 | ws | noise | yamux | ✅ | 6s | 7.43 | 1.604 |
| rust-v0.56 x go-v0.42 (tcp, noise, yamux) | rust-v0.56 | go-v0.42 | tcp | noise | yamux | ✅ | 5s | 2.949 | 0.232 |
| rust-v0.56 x go-v0.42 (webrtc-direct) | rust-v0.56 | go-v0.42 | webrtc-direct | - | - | ✅ | 5s | 14.084 | 0.446 |
| rust-v0.56 x go-v0.42 (quic-v1) | rust-v0.56 | go-v0.42 | quic-v1 | - | - | ✅ | 5s | 5.42 | 0.265 |
| rust-v0.56 x go-v0.43 (ws, noise, yamux) | rust-v0.56 | go-v0.43 | ws | noise | yamux | ✅ | 4s | 4.724 | 0.632 |
| rust-v0.56 x go-v0.43 (ws, tls, yamux) | rust-v0.56 | go-v0.43 | ws | tls | yamux | ✅ | 6s | 8.094 | 0.803 |
| rust-v0.56 x go-v0.43 (tcp, tls, yamux) | rust-v0.56 | go-v0.43 | tcp | tls | yamux | ✅ | 5s | 7.749 | 0.296 |
| rust-v0.56 x go-v0.43 (tcp, noise, yamux) | rust-v0.56 | go-v0.43 | tcp | noise | yamux | ✅ | 4s | 7.63 | 3.5 |
| rust-v0.56 x go-v0.43 (quic-v1) | rust-v0.56 | go-v0.43 | quic-v1 | - | - | ✅ | 5s | 6.647 | 0.27 |
| rust-v0.56 x go-v0.43 (webrtc-direct) | rust-v0.56 | go-v0.43 | webrtc-direct | - | - | ✅ | 4s | 92.575 | 1.134 |
| rust-v0.56 x go-v0.44 (ws, tls, yamux) | rust-v0.56 | go-v0.44 | ws | tls | yamux | ✅ | 5s | 5.373 | 0.259 |
| rust-v0.56 x go-v0.44 (ws, noise, yamux) | rust-v0.56 | go-v0.44 | ws | noise | yamux | ✅ | 5s | 3.7 | 0.257 |
| rust-v0.56 x go-v0.44 (tcp, tls, yamux) | rust-v0.56 | go-v0.44 | tcp | tls | yamux | ✅ | 5s | 7.366 | 2.075 |
| rust-v0.56 x go-v0.44 (tcp, noise, yamux) | rust-v0.56 | go-v0.44 | tcp | noise | yamux | ✅ | 5s | 8.887 | 0.395 |
| rust-v0.56 x go-v0.44 (quic-v1) | rust-v0.56 | go-v0.44 | quic-v1 | - | - | ✅ | 5s | 5.87 | 0.3 |
| rust-v0.56 x go-v0.44 (webrtc-direct) | rust-v0.56 | go-v0.44 | webrtc-direct | - | - | ✅ | 5s | 11.088 | 0.41 |
| rust-v0.56 x go-v0.45 (ws, tls, yamux) | rust-v0.56 | go-v0.45 | ws | tls | yamux | ✅ | 5s | 4.342 | 0.258 |
| rust-v0.56 x go-v0.45 (ws, noise, yamux) | rust-v0.56 | go-v0.45 | ws | noise | yamux | ✅ | 4s | 8.702 | 3.369 |
| rust-v0.56 x go-v0.45 (tcp, tls, yamux) | rust-v0.56 | go-v0.45 | tcp | tls | yamux | ✅ | 5s | 5.794 | 0.669 |
| rust-v0.56 x go-v0.45 (tcp, noise, yamux) | rust-v0.56 | go-v0.45 | tcp | noise | yamux | ✅ | 4s | 4.41 | 0.238 |
| rust-v0.56 x go-v0.45 (quic-v1) | rust-v0.56 | go-v0.45 | quic-v1 | - | - | ✅ | 4s | 13.817 | 0.582 |
| rust-v0.56 x go-v0.45 (webrtc-direct) | rust-v0.56 | go-v0.45 | webrtc-direct | - | - | ✅ | 4s | 134.515 | 1.218 |
| rust-v0.56 x python-v0.4 (ws, noise, yamux) | rust-v0.56 | python-v0.4 | ws | noise | yamux | ✅ | 4s | 18.88 | 1.427 |
| rust-v0.56 x python-v0.4 (ws, noise, mplex) | rust-v0.56 | python-v0.4 | ws | noise | mplex | ✅ | 5s | 20.886 | 1.241 |
| rust-v0.56 x python-v0.4 (tcp, noise, mplex) | rust-v0.56 | python-v0.4 | tcp | noise | mplex | ✅ | 5s | 20.399 | 1.625 |
| rust-v0.56 x python-v0.4 (tcp, noise, yamux) | rust-v0.56 | python-v0.4 | tcp | noise | yamux | ✅ | 5s | 12.812 | 1.171 |
| rust-v0.56 x python-v0.4 (quic-v1) | rust-v0.56 | python-v0.4 | quic-v1 | - | - | ✅ | 5s | 38.568 | 6.045 |
| rust-v0.56 x js-v1.x (ws, noise, mplex) | rust-v0.56 | js-v1.x | ws | noise | mplex | ✅ | 18s | 127.551 | 14.588 |
| rust-v0.56 x js-v1.x (ws, noise, yamux) | rust-v0.56 | js-v1.x | ws | noise | yamux | ✅ | 20s | 140.266 | 13.213 |
| rust-v0.56 x js-v1.x (tcp, noise, mplex) | rust-v0.56 | js-v1.x | tcp | noise | mplex | ✅ | 19s | 125.604 | 10.122 |
| rust-v0.56 x js-v1.x (tcp, noise, yamux) | rust-v0.56 | js-v1.x | tcp | noise | yamux | ✅ | 19s | 102.27 | 11.258 |
| rust-v0.56 x js-v2.x (ws, noise, yamux) | rust-v0.56 | js-v2.x | ws | noise | yamux | ✅ | 19s | 142.738 | 15.007 |
| rust-v0.56 x js-v2.x (ws, noise, mplex) | rust-v0.56 | js-v2.x | ws | noise | mplex | ✅ | 21s | 162.571 | 13.1 |
| rust-v0.56 x js-v2.x (tcp, noise, mplex) | rust-v0.56 | js-v2.x | tcp | noise | mplex | ✅ | 19s | 142.23 | 6.803 |
| rust-v0.56 x js-v2.x (tcp, noise, yamux) | rust-v0.56 | js-v2.x | tcp | noise | yamux | ✅ | 20s | 100.515 | 11.739 |
| rust-v0.56 x nim-v1.14 (ws, noise, mplex) | rust-v0.56 | nim-v1.14 | ws | noise | mplex | ✅ | 5s | 159.46 | 43.603 |
| rust-v0.56 x nim-v1.14 (ws, noise, yamux) | rust-v0.56 | nim-v1.14 | ws | noise | yamux | ✅ | 4s | 110.187 | 3.819 |
| rust-v0.56 x nim-v1.14 (tcp, noise, mplex) | rust-v0.56 | nim-v1.14 | tcp | noise | mplex | ✅ | 5s | 67.557 | 1.031 |
| rust-v0.56 x nim-v1.14 (tcp, noise, yamux) | rust-v0.56 | nim-v1.14 | tcp | noise | yamux | ✅ | 5s | 112.334 | 1.517 |
| rust-v0.56 x js-v3.x (ws, noise, mplex) | rust-v0.56 | js-v3.x | ws | noise | mplex | ✅ | 16s | 194.568 | 23.773 |
| rust-v0.56 x js-v3.x (ws, noise, yamux) | rust-v0.56 | js-v3.x | ws | noise | yamux | ✅ | 18s | 224.977 | 24.875 |
| rust-v0.56 x js-v3.x (tcp, noise, mplex) | rust-v0.56 | js-v3.x | tcp | noise | mplex | ✅ | 18s | 121.894 | 32.797 |
| rust-v0.56 x js-v3.x (tcp, noise, yamux) | rust-v0.56 | js-v3.x | tcp | noise | yamux | ✅ | 19s | 159.362 | 34.132 |
| rust-v0.56 x jvm-v1.2 (ws, tls, mplex) | rust-v0.56 | jvm-v1.2 | ws | tls | mplex | ✅ | 13s | 4633.743 | 9.622 |
| rust-v0.56 x jvm-v1.2 (ws, tls, yamux) | rust-v0.56 | jvm-v1.2 | ws | tls | yamux | ✅ | 13s | 4050.937 | 4.925 |
| rust-v0.56 x jvm-v1.2 (ws, noise, mplex) | rust-v0.56 | jvm-v1.2 | ws | noise | mplex | ✅ | 12s | 1932.744 | 11.222 |
| rust-v0.56 x jvm-v1.2 (ws, noise, yamux) | rust-v0.56 | jvm-v1.2 | ws | noise | yamux | ✅ | 13s | 1536.539 | 8.405 |
| rust-v0.56 x jvm-v1.2 (tcp, tls, mplex) | rust-v0.56 | jvm-v1.2 | tcp | tls | mplex | ✅ | 10s | 1969.719 | 1.88 |
| rust-v0.56 x jvm-v1.2 (tcp, noise, mplex) | rust-v0.56 | jvm-v1.2 | tcp | noise | mplex | ✅ | 9s | 1158.561 | 4.289 |
| rust-v0.56 x c-v0.0.1 (tcp, noise, mplex) | rust-v0.56 | c-v0.0.1 | tcp | noise | mplex | ✅ | 6s | 17.833 | 0.156 |
| rust-v0.56 x c-v0.0.1 (tcp, noise, yamux) | rust-v0.56 | c-v0.0.1 | tcp | noise | yamux | ✅ | 6s | 71.744 | 4.167 |
| rust-v0.56 x jvm-v1.2 (tcp, tls, yamux) | rust-v0.56 | jvm-v1.2 | tcp | tls | yamux | ✅ | 11s | 3204.505 | 6.462 |
| rust-v0.56 x jvm-v1.2 (tcp, noise, yamux) | rust-v0.56 | jvm-v1.2 | tcp | noise | yamux | ✅ | 10s | 1140.066 | 11.399 |
| rust-v0.56 x dotnet-v1.0 (tcp, noise, yamux) | rust-v0.56 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 5s | 214.375 | 21.296 |
| rust-v0.56 x zig-v0.0.1 (quic-v1) | rust-v0.56 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 3s | - | - |
| rust-v0.56 x jvm-v1.2 (quic-v1) | rust-v0.56 | jvm-v1.2 | quic-v1 | - | - | ✅ | 12s | 1656.786 | 6.581 |
| rust-v0.56 x eth-p2p-z-v0.0.1 (quic-v1) | rust-v0.56 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 4s | 5.403 | 0.311 |
| go-v0.38 x rust-v0.53 (tcp, tls, yamux) | go-v0.38 | rust-v0.53 | tcp | tls | yamux | ✅ | 4s | 89.226 | 43.142 |
| go-v0.38 x rust-v0.53 (tcp, noise, yamux) | go-v0.38 | rust-v0.53 | tcp | noise | yamux | ✅ | 5s | 94.369 | 41.612 |
| go-v0.38 x rust-v0.53 (ws, tls, yamux) | go-v0.38 | rust-v0.53 | ws | tls | yamux | ✅ | 4s | 234.083 | 47.885 |
| go-v0.38 x rust-v0.53 (ws, noise, yamux) | go-v0.38 | rust-v0.53 | ws | noise | yamux | ✅ | 5s | 183.069 | 42.664 |
| go-v0.38 x rust-v0.53 (quic-v1) | go-v0.38 | rust-v0.53 | quic-v1 | - | - | ✅ | 4s | 8.653 | 0.37 |
| go-v0.38 x rust-v0.53 (webrtc-direct) | go-v0.38 | rust-v0.53 | webrtc-direct | - | - | ✅ | 5s | 410.372 | 0.337 |
| go-v0.38 x rust-v0.54 (tcp, noise, yamux) | go-v0.38 | rust-v0.54 | tcp | noise | yamux | ✅ | 3s | 94.555 | 45.596 |
| go-v0.38 x rust-v0.54 (tcp, tls, yamux) | go-v0.38 | rust-v0.54 | tcp | tls | yamux | ✅ | 5s | 97.493 | 46.813 |
| rust-v0.56 x c-v0.0.1 (quic-v1) | rust-v0.56 | c-v0.0.1 | quic-v1 | - | - | ❌ | 15s | - | - |
| go-v0.38 x rust-v0.54 (ws, noise, yamux) | go-v0.38 | rust-v0.54 | ws | noise | yamux | ✅ | 4s | 187.15 | 45.899 |
| go-v0.38 x rust-v0.54 (ws, tls, yamux) | go-v0.38 | rust-v0.54 | ws | tls | yamux | ✅ | 6s | 177.797 | 42.675 |
| go-v0.38 x rust-v0.54 (quic-v1) | go-v0.38 | rust-v0.54 | quic-v1 | - | - | ✅ | 5s | 14.005 | 0.421 |
| go-v0.38 x rust-v0.54 (webrtc-direct) | go-v0.38 | rust-v0.54 | webrtc-direct | - | - | ✅ | 6s | 430.386 | 2.096 |
| go-v0.38 x rust-v0.55 (tcp, tls, yamux) | go-v0.38 | rust-v0.55 | tcp | tls | yamux | ✅ | 5s | 9.177 | 0.776 |
| go-v0.38 x rust-v0.55 (tcp, noise, yamux) | go-v0.38 | rust-v0.55 | tcp | noise | yamux | ✅ | 5s | 10.543 | 0.738 |
| go-v0.38 x rust-v0.55 (ws, tls, yamux) | go-v0.38 | rust-v0.55 | ws | tls | yamux | ✅ | 5s | 4.932 | 0.374 |
| go-v0.38 x rust-v0.55 (ws, noise, yamux) | go-v0.38 | rust-v0.55 | ws | noise | yamux | ✅ | 5s | 9.215 | 2.27 |
| go-v0.38 x rust-v0.55 (quic-v1) | go-v0.38 | rust-v0.55 | quic-v1 | - | - | ✅ | 5s | 9.639 | 0.499 |
| go-v0.38 x rust-v0.55 (webrtc-direct) | go-v0.38 | rust-v0.55 | webrtc-direct | - | - | ✅ | 5s | 416.381 | 0.736 |
| go-v0.38 x rust-v0.56 (tcp, tls, yamux) | go-v0.38 | rust-v0.56 | tcp | tls | yamux | ✅ | 5s | 6.724 | 0.474 |
| go-v0.38 x rust-v0.56 (ws, tls, yamux) | go-v0.38 | rust-v0.56 | ws | tls | yamux | ✅ | 4s | 6.45 | 0.287 |
| go-v0.38 x rust-v0.56 (tcp, noise, yamux) | go-v0.38 | rust-v0.56 | tcp | noise | yamux | ✅ | 5s | 7.83 | 0.5 |
| go-v0.38 x rust-v0.56 (ws, noise, yamux) | go-v0.38 | rust-v0.56 | ws | noise | yamux | ✅ | 5s | 10.147 | 0.381 |
| go-v0.38 x rust-v0.56 (quic-v1) | go-v0.38 | rust-v0.56 | quic-v1 | - | - | ✅ | 5s | 8.328 | 0.769 |
| go-v0.38 x go-v0.38 (tcp, tls, yamux) | go-v0.38 | go-v0.38 | tcp | tls | yamux | ✅ | 5s | 8.458 | 0.78 |
| go-v0.38 x go-v0.38 (tcp, noise, yamux) | go-v0.38 | go-v0.38 | tcp | noise | yamux | ✅ | 4s | 7.625 | 1.961 |
| go-v0.38 x go-v0.38 (ws, tls, yamux) | go-v0.38 | go-v0.38 | ws | tls | yamux | ✅ | 4s | 10.824 | 0.577 |
| go-v0.38 x go-v0.38 (ws, noise, yamux) | go-v0.38 | go-v0.38 | ws | noise | yamux | ✅ | 4s | 12.648 | 1.269 |
| go-v0.38 x go-v0.38 (wss, tls, yamux) | go-v0.38 | go-v0.38 | wss | tls | yamux | ✅ | 4s | 26.153 | 4.512 |
| go-v0.38 x go-v0.38 (quic-v1) | go-v0.38 | go-v0.38 | quic-v1 | - | - | ✅ | 4s | 10.866 | 1.214 |
| go-v0.38 x go-v0.38 (wss, noise, yamux) | go-v0.38 | go-v0.38 | wss | noise | yamux | ✅ | 5s | 8.498 | 0.463 |
| go-v0.38 x rust-v0.56 (webrtc-direct) | go-v0.38 | rust-v0.56 | webrtc-direct | - | - | ❌ | 10s | - | - |
| go-v0.38 x go-v0.38 (webtransport) | go-v0.38 | go-v0.38 | webtransport | - | - | ✅ | 5s | 13.322 | 0.353 |
| go-v0.38 x go-v0.39 (tcp, tls, yamux) | go-v0.38 | go-v0.39 | tcp | tls | yamux | ✅ | 5s | 6.005 | 0.227 |
| go-v0.38 x go-v0.38 (webrtc-direct) | go-v0.38 | go-v0.38 | webrtc-direct | - | - | ✅ | 5s | 211.406 | 0.512 |
| go-v0.38 x go-v0.39 (tcp, noise, yamux) | go-v0.38 | go-v0.39 | tcp | noise | yamux | ✅ | 4s | 7.987 | 0.611 |
| go-v0.38 x go-v0.39 (ws, tls, yamux) | go-v0.38 | go-v0.39 | ws | tls | yamux | ✅ | 4s | 9.172 | 0.388 |
| go-v0.38 x go-v0.39 (ws, noise, yamux) | go-v0.38 | go-v0.39 | ws | noise | yamux | ✅ | 5s | 8.7 | 0.666 |
| go-v0.38 x go-v0.39 (wss, tls, yamux) | go-v0.38 | go-v0.39 | wss | tls | yamux | ✅ | 5s | 12.294 | 0.739 |
| go-v0.38 x go-v0.39 (wss, noise, yamux) | go-v0.38 | go-v0.39 | wss | noise | yamux | ✅ | 5s | 18.351 | 0.596 |
| go-v0.38 x go-v0.39 (quic-v1) | go-v0.38 | go-v0.39 | quic-v1 | - | - | ✅ | 5s | 11.035 | 0.406 |
| go-v0.38 x go-v0.39 (webtransport) | go-v0.38 | go-v0.39 | webtransport | - | - | ✅ | 5s | 12.19 | 0.621 |
| go-v0.38 x go-v0.39 (webrtc-direct) | go-v0.38 | go-v0.39 | webrtc-direct | - | - | ✅ | 4s | 213.599 | 1.268 |
| go-v0.38 x go-v0.40 (tcp, tls, yamux) | go-v0.38 | go-v0.40 | tcp | tls | yamux | ✅ | 5s | 8.438 | 0.445 |
| go-v0.38 x go-v0.40 (ws, tls, yamux) | go-v0.38 | go-v0.40 | ws | tls | yamux | ✅ | 5s | 9.647 | 0.554 |
| go-v0.38 x go-v0.40 (tcp, noise, yamux) | go-v0.38 | go-v0.40 | tcp | noise | yamux | ✅ | 6s | 26.21 | 3.319 |
| go-v0.38 x go-v0.40 (ws, noise, yamux) | go-v0.38 | go-v0.40 | ws | noise | yamux | ✅ | 5s | 19.756 | 2.198 |
| go-v0.38 x go-v0.40 (wss, tls, yamux) | go-v0.38 | go-v0.40 | wss | tls | yamux | ✅ | 4s | 13.683 | 0.336 |
| go-v0.38 x go-v0.40 (wss, noise, yamux) | go-v0.38 | go-v0.40 | wss | noise | yamux | ✅ | 4s | 11.483 | 1.709 |
| go-v0.38 x go-v0.40 (quic-v1) | go-v0.38 | go-v0.40 | quic-v1 | - | - | ✅ | 5s | 12.039 | 0.453 |
| go-v0.38 x go-v0.40 (webtransport) | go-v0.38 | go-v0.40 | webtransport | - | - | ✅ | 4s | 8.939 | 0.321 |
| go-v0.38 x go-v0.40 (webrtc-direct) | go-v0.38 | go-v0.40 | webrtc-direct | - | - | ✅ | 5s | 210.46 | 0.363 |
| go-v0.38 x go-v0.41 (tcp, noise, yamux) | go-v0.38 | go-v0.41 | tcp | noise | yamux | ✅ | 4s | 11.537 | 3.196 |
| go-v0.38 x go-v0.41 (tcp, tls, yamux) | go-v0.38 | go-v0.41 | tcp | tls | yamux | ✅ | 5s | 6.341 | 1.113 |
| go-v0.38 x go-v0.41 (ws, tls, yamux) | go-v0.38 | go-v0.41 | ws | tls | yamux | ✅ | 4s | 9.385 | 0.283 |
| go-v0.38 x go-v0.41 (ws, noise, yamux) | go-v0.38 | go-v0.41 | ws | noise | yamux | ✅ | 5s | 7.352 | 1.175 |
| go-v0.38 x go-v0.41 (wss, tls, yamux) | go-v0.38 | go-v0.41 | wss | tls | yamux | ✅ | 5s | 17.48 | 1.466 |
| go-v0.38 x go-v0.41 (quic-v1) | go-v0.38 | go-v0.41 | quic-v1 | - | - | ✅ | 5s | 12.88 | 0.602 |
| go-v0.38 x go-v0.41 (webtransport) | go-v0.38 | go-v0.41 | webtransport | - | - | ✅ | 5s | 19.975 | 1.584 |
| go-v0.38 x go-v0.41 (wss, noise, yamux) | go-v0.38 | go-v0.41 | wss | noise | yamux | ✅ | 6s | 14.712 | 0.973 |
| go-v0.38 x go-v0.42 (tcp, tls, yamux) | go-v0.38 | go-v0.42 | tcp | tls | yamux | ✅ | 4s | 8.005 | 0.294 |
| go-v0.38 x go-v0.41 (webrtc-direct) | go-v0.38 | go-v0.41 | webrtc-direct | - | - | ✅ | 5s | 215.826 | 0.816 |
| go-v0.38 x go-v0.42 (ws, tls, yamux) | go-v0.38 | go-v0.42 | ws | tls | yamux | ✅ | 5s | 16.577 | 1.817 |
| go-v0.38 x go-v0.42 (tcp, noise, yamux) | go-v0.38 | go-v0.42 | tcp | noise | yamux | ✅ | 5s | 14.246 | 1.7 |
| go-v0.38 x go-v0.42 (ws, noise, yamux) | go-v0.38 | go-v0.42 | ws | noise | yamux | ✅ | 5s | 19.398 | 0.365 |
| go-v0.38 x go-v0.42 (wss, tls, yamux) | go-v0.38 | go-v0.42 | wss | tls | yamux | ✅ | 5s | 14.426 | 0.521 |
| go-v0.38 x go-v0.42 (quic-v1) | go-v0.38 | go-v0.42 | quic-v1 | - | - | ✅ | 4s | 14.618 | 0.48 |
| go-v0.38 x go-v0.42 (webtransport) | go-v0.38 | go-v0.42 | webtransport | - | - | ✅ | 4s | 14.355 | 0.385 |
| go-v0.38 x go-v0.42 (wss, noise, yamux) | go-v0.38 | go-v0.42 | wss | noise | yamux | ✅ | 6s | 7.455 | 0.564 |
| go-v0.38 x go-v0.42 (webrtc-direct) | go-v0.38 | go-v0.42 | webrtc-direct | - | - | ✅ | 4s | 212.031 | 1.158 |
| go-v0.38 x go-v0.43 (tcp, noise, yamux) | go-v0.38 | go-v0.43 | tcp | noise | yamux | ✅ | 4s | 9.226 | 1.514 |
| go-v0.38 x go-v0.43 (tcp, tls, yamux) | go-v0.38 | go-v0.43 | tcp | tls | yamux | ✅ | 5s | 9.411 | 1.126 |
| go-v0.38 x go-v0.43 (ws, tls, yamux) | go-v0.38 | go-v0.43 | ws | tls | yamux | ✅ | 4s | 12.041 | 1.374 |
| go-v0.38 x go-v0.43 (ws, noise, yamux) | go-v0.38 | go-v0.43 | ws | noise | yamux | ✅ | 5s | 15.744 | 2.744 |
| go-v0.38 x go-v0.43 (wss, tls, yamux) | go-v0.38 | go-v0.43 | wss | tls | yamux | ✅ | 5s | 20.985 | 2.636 |
| go-v0.38 x go-v0.43 (wss, noise, yamux) | go-v0.38 | go-v0.43 | wss | noise | yamux | ✅ | 5s | 17.081 | 2.214 |
| go-v0.38 x go-v0.43 (quic-v1) | go-v0.38 | go-v0.43 | quic-v1 | - | - | ✅ | 5s | 8.648 | 0.422 |
| go-v0.38 x go-v0.43 (webtransport) | go-v0.38 | go-v0.43 | webtransport | - | - | ✅ | 4s | 9.73 | 0.418 |
| go-v0.38 x go-v0.43 (webrtc-direct) | go-v0.38 | go-v0.43 | webrtc-direct | - | - | ✅ | 5s | 26.61 | 4.778 |
| go-v0.38 x go-v0.44 (tcp, noise, yamux) | go-v0.38 | go-v0.44 | tcp | noise | yamux | ✅ | 4s | 6.416 | 0.566 |
| go-v0.38 x go-v0.44 (tcp, tls, yamux) | go-v0.38 | go-v0.44 | tcp | tls | yamux | ✅ | 5s | 8.629 | 0.429 |
| go-v0.38 x go-v0.44 (ws, tls, yamux) | go-v0.38 | go-v0.44 | ws | tls | yamux | ✅ | 5s | 11.145 | 0.514 |
| go-v0.38 x go-v0.44 (ws, noise, yamux) | go-v0.38 | go-v0.44 | ws | noise | yamux | ✅ | 4s | 7.134 | 0.525 |
| go-v0.38 x go-v0.44 (wss, noise, yamux) | go-v0.38 | go-v0.44 | wss | noise | yamux | ✅ | 5s | 16.951 | 0.638 |
| go-v0.38 x go-v0.44 (wss, tls, yamux) | go-v0.38 | go-v0.44 | wss | tls | yamux | ✅ | 6s | 20.51 | 0.745 |
| go-v0.38 x go-v0.44 (quic-v1) | go-v0.38 | go-v0.44 | quic-v1 | - | - | ✅ | 5s | 19.373 | 1.078 |
| go-v0.38 x go-v0.44 (webtransport) | go-v0.38 | go-v0.44 | webtransport | - | - | ✅ | 5s | 13.218 | 0.54 |
| go-v0.38 x go-v0.44 (webrtc-direct) | go-v0.38 | go-v0.44 | webrtc-direct | - | - | ✅ | 5s | 170.162 | 0.249 |
| go-v0.38 x go-v0.45 (tcp, tls, yamux) | go-v0.38 | go-v0.45 | tcp | tls | yamux | ✅ | 4s | 7.059 | 0.227 |
| go-v0.38 x go-v0.45 (tcp, noise, yamux) | go-v0.38 | go-v0.45 | tcp | noise | yamux | ✅ | 4s | 6.367 | 0.372 |
| go-v0.38 x go-v0.45 (ws, tls, yamux) | go-v0.38 | go-v0.45 | ws | tls | yamux | ✅ | 5s | 8.118 | 0.301 |
| go-v0.38 x go-v0.45 (ws, noise, yamux) | go-v0.38 | go-v0.45 | ws | noise | yamux | ✅ | 4s | 13.788 | 2.345 |
| go-v0.38 x go-v0.45 (wss, noise, yamux) | go-v0.38 | go-v0.45 | wss | noise | yamux | ✅ | 4s | 17.324 | 1.129 |
| go-v0.38 x go-v0.45 (wss, tls, yamux) | go-v0.38 | go-v0.45 | wss | tls | yamux | ✅ | 5s | 15.883 | 0.504 |
| go-v0.38 x go-v0.45 (quic-v1) | go-v0.38 | go-v0.45 | quic-v1 | - | - | ✅ | 5s | 7.857 | 0.348 |
| go-v0.38 x go-v0.45 (webtransport) | go-v0.38 | go-v0.45 | webtransport | - | - | ✅ | 5s | 9.155 | 0.721 |
| go-v0.38 x go-v0.45 (webrtc-direct) | go-v0.38 | go-v0.45 | webrtc-direct | - | - | ✅ | 5s | 259.22 | 1.776 |
| go-v0.38 x python-v0.4 (tcp, noise, yamux) | go-v0.38 | python-v0.4 | tcp | noise | yamux | ✅ | 5s | 26.935 | 3.224 |
| go-v0.38 x python-v0.4 (ws, noise, yamux) | go-v0.38 | python-v0.4 | ws | noise | yamux | ✅ | 5s | 30.118 | 5.546 |
| go-v0.38 x python-v0.4 (wss, noise, yamux) | go-v0.38 | python-v0.4 | wss | noise | yamux | ✅ | 5s | 36.563 | 5.306 |
| go-v0.38 x python-v0.4 (quic-v1) | go-v0.38 | python-v0.4 | quic-v1 | - | - | ✅ | 6s | 64.954 | 15.964 |
| go-v0.38 x nim-v1.14 (tcp, noise, yamux) | go-v0.38 | nim-v1.14 | tcp | noise | yamux | ✅ | 5s | 178.375 | 54.978 |
| go-v0.38 x nim-v1.14 (ws, noise, yamux) | go-v0.38 | nim-v1.14 | ws | noise | yamux | ✅ | 5s | 257.351 | 43.633 |
| go-v0.38 x js-v1.x (tcp, noise, yamux) | go-v0.38 | js-v1.x | tcp | noise | yamux | ✅ | 18s | 228.934 | 26.391 |
| go-v0.38 x js-v1.x (ws, noise, yamux) | go-v0.38 | js-v1.x | ws | noise | yamux | ✅ | 19s | 178.86 | 15.886 |
| go-v0.38 x js-v2.x (tcp, noise, yamux) | go-v0.38 | js-v2.x | tcp | noise | yamux | ✅ | 20s | 126.895 | 18.293 |
| go-v0.38 x js-v2.x (ws, noise, yamux) | go-v0.38 | js-v2.x | ws | noise | yamux | ✅ | 20s | 160.158 | 30.934 |
| go-v0.38 x jvm-v1.2 (tcp, noise, yamux) | go-v0.38 | jvm-v1.2 | tcp | noise | yamux | ✅ | 10s | 895.987 | 26.838 |
| go-v0.38 x js-v3.x (tcp, noise, yamux) | go-v0.38 | js-v3.x | tcp | noise | yamux | ✅ | 20s | 178.869 | 14.939 |
| go-v0.38 x js-v3.x (ws, noise, yamux) | go-v0.38 | js-v3.x | ws | noise | yamux | ✅ | 20s | 104.671 | 22.763 |
| go-v0.38 x jvm-v1.2 (tcp, tls, yamux) | go-v0.38 | jvm-v1.2 | tcp | tls | yamux | ✅ | 13s | 3148.264 | 19.399 |
| go-v0.38 x c-v0.0.1 (tcp, noise, yamux) | go-v0.38 | c-v0.0.1 | tcp | noise | yamux | ✅ | 6s | 121.236 | 56.813 |
| go-v0.38 x c-v0.0.1 (quic-v1) | go-v0.38 | c-v0.0.1 | quic-v1 | - | - | ✅ | 5s | 42.582 | 28.812 |
| go-v0.38 x jvm-v1.2 (ws, noise, yamux) | go-v0.38 | jvm-v1.2 | ws | noise | yamux | ✅ | 10s | 1652.192 | 26.582 |
| go-v0.38 x dotnet-v1.0 (tcp, noise, yamux) | go-v0.38 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 7s | 497.993 | 46.621 |
| go-v0.38 x zig-v0.0.1 (quic-v1) | go-v0.38 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 6s | - | - |
| go-v0.38 x jvm-v1.2 (ws, tls, yamux) | go-v0.38 | jvm-v1.2 | ws | tls | yamux | ✅ | 13s | 3582.524 | 23.367 |
| go-v0.38 x eth-p2p-z-v0.0.1 (quic-v1) | go-v0.38 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 8.736 | 0.17 |
| go-v0.38 x jvm-v1.2 (quic-v1) | go-v0.38 | jvm-v1.2 | quic-v1 | - | - | ✅ | 11s | 590.116 | 8.271 |
| go-v0.39 x rust-v0.53 (tcp, tls, yamux) | go-v0.39 | rust-v0.53 | tcp | tls | yamux | ✅ | 5s | 133.499 | 42.977 |
| go-v0.39 x rust-v0.53 (tcp, noise, yamux) | go-v0.39 | rust-v0.53 | tcp | noise | yamux | ✅ | 5s | 139.084 | 43.754 |
| go-v0.39 x rust-v0.53 (ws, tls, yamux) | go-v0.39 | rust-v0.53 | ws | tls | yamux | ✅ | 5s | 177.533 | 42.334 |
| go-v0.39 x rust-v0.53 (ws, noise, yamux) | go-v0.39 | rust-v0.53 | ws | noise | yamux | ✅ | 6s | 224.407 | 47.663 |
| go-v0.39 x rust-v0.53 (quic-v1) | go-v0.39 | rust-v0.53 | quic-v1 | - | - | ✅ | 5s | 5.08 | 0.247 |
| go-v0.39 x rust-v0.54 (tcp, tls, yamux) | go-v0.39 | rust-v0.54 | tcp | tls | yamux | ✅ | 5s | 89.698 | 41.451 |
| go-v0.39 x rust-v0.53 (webrtc-direct) | go-v0.39 | rust-v0.53 | webrtc-direct | - | - | ✅ | 6s | 411.054 | 0.348 |
| go-v0.39 x rust-v0.54 (tcp, noise, yamux) | go-v0.39 | rust-v0.54 | tcp | noise | yamux | ✅ | 6s | 101.597 | 42.339 |
| go-v0.39 x rust-v0.54 (ws, tls, yamux) | go-v0.39 | rust-v0.54 | ws | tls | yamux | ✅ | 5s | 226.298 | 43.619 |
| go-v0.39 x rust-v0.54 (ws, noise, yamux) | go-v0.39 | rust-v0.54 | ws | noise | yamux | ✅ | 5s | 230.01 | 43.348 |
| go-v0.39 x rust-v0.54 (quic-v1) | go-v0.39 | rust-v0.54 | quic-v1 | - | - | ✅ | 5s | 5.212 | 0.465 |
| go-v0.39 x rust-v0.54 (webrtc-direct) | go-v0.39 | rust-v0.54 | webrtc-direct | - | - | ✅ | 6s | 412.318 | 0.463 |
| go-v0.39 x rust-v0.55 (ws, tls, yamux) | go-v0.39 | rust-v0.55 | ws | tls | yamux | ✅ | 5s | 7.391 | 0.671 |
| go-v0.39 x rust-v0.55 (tcp, tls, yamux) | go-v0.39 | rust-v0.55 | tcp | tls | yamux | ✅ | 6s | 11.34 | 0.424 |
| go-v0.39 x rust-v0.55 (tcp, noise, yamux) | go-v0.39 | rust-v0.55 | tcp | noise | yamux | ✅ | 6s | 7.924 | 0.346 |
| go-v0.39 x rust-v0.55 (ws, noise, yamux) | go-v0.39 | rust-v0.55 | ws | noise | yamux | ✅ | 6s | 10.32 | 1.035 |
| go-v0.39 x rust-v0.55 (quic-v1) | go-v0.39 | rust-v0.55 | quic-v1 | - | - | ✅ | 4s | 17.004 | 1.964 |
| go-v0.39 x rust-v0.56 (tcp, tls, yamux) | go-v0.39 | rust-v0.56 | tcp | tls | yamux | ✅ | 4s | 7.455 | 0.581 |
| go-v0.39 x rust-v0.55 (webrtc-direct) | go-v0.39 | rust-v0.55 | webrtc-direct | - | - | ✅ | 6s | 418.211 | 0.498 |
| go-v0.39 x rust-v0.56 (tcp, noise, yamux) | go-v0.39 | rust-v0.56 | tcp | noise | yamux | ✅ | 4s | 7.435 | 0.521 |
| go-v0.39 x rust-v0.56 (ws, noise, yamux) | go-v0.39 | rust-v0.56 | ws | noise | yamux | ✅ | 5s | 9.935 | 0.21 |
| go-v0.39 x rust-v0.56 (ws, tls, yamux) | go-v0.39 | rust-v0.56 | ws | tls | yamux | ✅ | 5s | 9.428 | 0.393 |
| go-v0.39 x rust-v0.56 (quic-v1) | go-v0.39 | rust-v0.56 | quic-v1 | - | - | ✅ | 4s | 4.834 | 0.26 |
| go-v0.39 x go-v0.38 (tcp, tls, yamux) | go-v0.39 | go-v0.38 | tcp | tls | yamux | ✅ | 5s | 7.635 | 1.107 |
| go-v0.39 x go-v0.38 (tcp, noise, yamux) | go-v0.39 | go-v0.38 | tcp | noise | yamux | ✅ | 4s | 10.85 | 1.047 |
| go-v0.39 x go-v0.38 (ws, tls, yamux) | go-v0.39 | go-v0.38 | ws | tls | yamux | ✅ | 5s | 6.182 | 0.486 |
| go-v0.39 x go-v0.38 (ws, noise, yamux) | go-v0.39 | go-v0.38 | ws | noise | yamux | ✅ | 4s | 19.238 | 4.036 |
| go-v0.39 x go-v0.38 (quic-v1) | go-v0.39 | go-v0.38 | quic-v1 | - | - | ✅ | 4s | 18.013 | 3.671 |
| go-v0.39 x rust-v0.56 (webrtc-direct) | go-v0.39 | rust-v0.56 | webrtc-direct | - | - | ❌ | 10s | - | - |
| go-v0.39 x go-v0.38 (wss, tls, yamux) | go-v0.39 | go-v0.38 | wss | tls | yamux | ✅ | 6s | 12.635 | 0.333 |
| go-v0.39 x go-v0.38 (wss, noise, yamux) | go-v0.39 | go-v0.38 | wss | noise | yamux | ✅ | 5s | 7.677 | 0.202 |
| go-v0.39 x go-v0.38 (webtransport) | go-v0.39 | go-v0.38 | webtransport | - | - | ✅ | 5s | 6.392 | 0.308 |
| go-v0.39 x go-v0.38 (webrtc-direct) | go-v0.39 | go-v0.38 | webrtc-direct | - | - | ✅ | 5s | 213.99 | 0.391 |
| go-v0.39 x go-v0.39 (tcp, tls, yamux) | go-v0.39 | go-v0.39 | tcp | tls | yamux | ✅ | 4s | 13.153 | 0.199 |
| go-v0.39 x go-v0.39 (tcp, noise, yamux) | go-v0.39 | go-v0.39 | tcp | noise | yamux | ✅ | 4s | 9.793 | 0.448 |
| go-v0.39 x go-v0.39 (ws, tls, yamux) | go-v0.39 | go-v0.39 | ws | tls | yamux | ✅ | 5s | 12.014 | 0.303 |
| go-v0.39 x go-v0.39 (ws, noise, yamux) | go-v0.39 | go-v0.39 | ws | noise | yamux | ✅ | 5s | 17.96 | 4.158 |
| go-v0.39 x go-v0.39 (wss, noise, yamux) | go-v0.39 | go-v0.39 | wss | noise | yamux | ✅ | 5s | 15.042 | 4.219 |
| go-v0.39 x go-v0.39 (quic-v1) | go-v0.39 | go-v0.39 | quic-v1 | - | - | ✅ | 5s | 5.608 | 0.244 |
| go-v0.39 x go-v0.39 (wss, tls, yamux) | go-v0.39 | go-v0.39 | wss | tls | yamux | ✅ | 5s | 20.285 | 0.747 |
| go-v0.39 x go-v0.39 (webtransport) | go-v0.39 | go-v0.39 | webtransport | - | - | ✅ | 5s | 5.831 | 0.294 |
| go-v0.39 x go-v0.40 (tcp, tls, yamux) | go-v0.39 | go-v0.40 | tcp | tls | yamux | ✅ | 5s | 7.806 | 1.428 |
| go-v0.39 x go-v0.39 (webrtc-direct) | go-v0.39 | go-v0.39 | webrtc-direct | - | - | ✅ | 5s | 218.628 | 0.889 |
| go-v0.39 x go-v0.40 (tcp, noise, yamux) | go-v0.39 | go-v0.40 | tcp | noise | yamux | ✅ | 4s | 6.838 | 1.136 |
| go-v0.39 x go-v0.40 (ws, tls, yamux) | go-v0.39 | go-v0.40 | ws | tls | yamux | ✅ | 5s | 7.569 | 0.641 |
| go-v0.39 x go-v0.40 (ws, noise, yamux) | go-v0.39 | go-v0.40 | ws | noise | yamux | ✅ | 5s | 11.343 | 0.52 |
| go-v0.39 x go-v0.40 (wss, tls, yamux) | go-v0.39 | go-v0.40 | wss | tls | yamux | ✅ | 4s | 18.268 | 2.716 |
| go-v0.39 x go-v0.40 (wss, noise, yamux) | go-v0.39 | go-v0.40 | wss | noise | yamux | ✅ | 5s | 19.228 | 4.831 |
| go-v0.39 x go-v0.40 (quic-v1) | go-v0.39 | go-v0.40 | quic-v1 | - | - | ✅ | 5s | 7.851 | 0.46 |
| go-v0.39 x go-v0.40 (webtransport) | go-v0.39 | go-v0.40 | webtransport | - | - | ✅ | 4s | 9.228 | 0.426 |
| go-v0.39 x go-v0.40 (webrtc-direct) | go-v0.39 | go-v0.40 | webrtc-direct | - | - | ✅ | 5s | 214.084 | 0.916 |
| go-v0.39 x go-v0.41 (tcp, tls, yamux) | go-v0.39 | go-v0.41 | tcp | tls | yamux | ✅ | 5s | 11.464 | 0.511 |
| go-v0.39 x go-v0.41 (tcp, noise, yamux) | go-v0.39 | go-v0.41 | tcp | noise | yamux | ✅ | 5s | 12.562 | 3.237 |
| go-v0.39 x go-v0.41 (ws, tls, yamux) | go-v0.39 | go-v0.41 | ws | tls | yamux | ✅ | 5s | 7.999 | 1.034 |
| go-v0.39 x go-v0.41 (ws, noise, yamux) | go-v0.39 | go-v0.41 | ws | noise | yamux | ✅ | 4s | 12.284 | 1.937 |
| go-v0.39 x go-v0.41 (wss, noise, yamux) | go-v0.39 | go-v0.41 | wss | noise | yamux | ✅ | 5s | 22.798 | 0.871 |
| go-v0.39 x go-v0.41 (wss, tls, yamux) | go-v0.39 | go-v0.41 | wss | tls | yamux | ✅ | 6s | 19.113 | 0.74 |
| go-v0.39 x go-v0.41 (quic-v1) | go-v0.39 | go-v0.41 | quic-v1 | - | - | ✅ | 5s | 9.692 | 0.377 |
| go-v0.39 x go-v0.41 (webtransport) | go-v0.39 | go-v0.41 | webtransport | - | - | ✅ | 5s | 23.176 | 0.496 |
| go-v0.39 x go-v0.42 (tcp, tls, yamux) | go-v0.39 | go-v0.42 | tcp | tls | yamux | ✅ | 5s | 7.783 | 1.196 |
| go-v0.39 x go-v0.41 (webrtc-direct) | go-v0.39 | go-v0.41 | webrtc-direct | - | - | ✅ | 6s | 217.608 | 2.469 |
| go-v0.39 x go-v0.42 (tcp, noise, yamux) | go-v0.39 | go-v0.42 | tcp | noise | yamux | ✅ | 5s | 8.383 | 0.827 |
| go-v0.39 x go-v0.42 (ws, tls, yamux) | go-v0.39 | go-v0.42 | ws | tls | yamux | ✅ | 5s | 6.947 | 2.244 |
| go-v0.39 x go-v0.42 (ws, noise, yamux) | go-v0.39 | go-v0.42 | ws | noise | yamux | ✅ | 4s | 7.53 | 0.443 |
| go-v0.39 x go-v0.42 (wss, tls, yamux) | go-v0.39 | go-v0.42 | wss | tls | yamux | ✅ | 6s | 23.001 | 2.196 |
| go-v0.39 x go-v0.42 (quic-v1) | go-v0.39 | go-v0.42 | quic-v1 | - | - | ✅ | 5s | 16.984 | 5.424 |
| go-v0.39 x go-v0.42 (wss, noise, yamux) | go-v0.39 | go-v0.42 | wss | noise | yamux | ✅ | 6s | 19.957 | 0.841 |
| go-v0.39 x go-v0.42 (webtransport) | go-v0.39 | go-v0.42 | webtransport | - | - | ✅ | 4s | 6.825 | 0.333 |
| go-v0.39 x go-v0.42 (webrtc-direct) | go-v0.39 | go-v0.42 | webrtc-direct | - | - | ✅ | 6s | 218.676 | 0.399 |
| go-v0.39 x go-v0.43 (tcp, noise, yamux) | go-v0.39 | go-v0.43 | tcp | noise | yamux | ✅ | 5s | 9.512 | 1.021 |
| go-v0.39 x go-v0.43 (tcp, tls, yamux) | go-v0.39 | go-v0.43 | tcp | tls | yamux | ✅ | 6s | 11.654 | 1.111 |
| go-v0.39 x go-v0.43 (ws, tls, yamux) | go-v0.39 | go-v0.43 | ws | tls | yamux | ✅ | 5s | 9.899 | 0.272 |
| go-v0.39 x go-v0.43 (ws, noise, yamux) | go-v0.39 | go-v0.43 | ws | noise | yamux | ✅ | 6s | 21.041 | 1.715 |
| go-v0.39 x go-v0.43 (wss, noise, yamux) | go-v0.39 | go-v0.43 | wss | noise | yamux | ✅ | 5s | 16.331 | 0.78 |
| go-v0.39 x go-v0.43 (quic-v1) | go-v0.39 | go-v0.43 | quic-v1 | - | - | ✅ | 5s | 8.33 | 0.473 |
| go-v0.39 x go-v0.43 (wss, tls, yamux) | go-v0.39 | go-v0.43 | wss | tls | yamux | ✅ | 6s | 14.296 | 0.362 |
| go-v0.39 x go-v0.43 (webtransport) | go-v0.39 | go-v0.43 | webtransport | - | - | ✅ | 5s | 18.509 | 0.454 |
| go-v0.39 x go-v0.44 (tcp, tls, yamux) | go-v0.39 | go-v0.44 | tcp | tls | yamux | ✅ | 5s | 13.323 | 0.417 |
| go-v0.39 x go-v0.43 (webrtc-direct) | go-v0.39 | go-v0.43 | webrtc-direct | - | - | ✅ | 5s | 214.553 | 0.827 |
| go-v0.39 x go-v0.44 (tcp, noise, yamux) | go-v0.39 | go-v0.44 | tcp | noise | yamux | ✅ | 4s | 12.432 | 0.44 |
| go-v0.39 x go-v0.44 (ws, tls, yamux) | go-v0.39 | go-v0.44 | ws | tls | yamux | ✅ | 5s | 12.238 | 1.758 |
| go-v0.39 x go-v0.44 (ws, noise, yamux) | go-v0.39 | go-v0.44 | ws | noise | yamux | ✅ | 4s | 10.244 | 0.28 |
| go-v0.39 x go-v0.44 (wss, tls, yamux) | go-v0.39 | go-v0.44 | wss | tls | yamux | ✅ | 4s | 15.035 | 0.525 |
| go-v0.39 x go-v0.44 (wss, noise, yamux) | go-v0.39 | go-v0.44 | wss | noise | yamux | ✅ | 4s | 8.171 | 0.322 |
| go-v0.39 x go-v0.44 (quic-v1) | go-v0.39 | go-v0.44 | quic-v1 | - | - | ✅ | 5s | 14.333 | 1.042 |
| go-v0.39 x go-v0.44 (webtransport) | go-v0.39 | go-v0.44 | webtransport | - | - | ✅ | 4s | 14.089 | 0.424 |
| go-v0.39 x go-v0.44 (webrtc-direct) | go-v0.39 | go-v0.44 | webrtc-direct | - | - | ✅ | 4s | 218.364 | 0.298 |
| go-v0.39 x go-v0.45 (tcp, tls, yamux) | go-v0.39 | go-v0.45 | tcp | tls | yamux | ✅ | 5s | 21.048 | 0.706 |
| go-v0.39 x go-v0.45 (tcp, noise, yamux) | go-v0.39 | go-v0.45 | tcp | noise | yamux | ✅ | 4s | 9.458 | 1.362 |
| go-v0.39 x go-v0.45 (ws, tls, yamux) | go-v0.39 | go-v0.45 | ws | tls | yamux | ✅ | 4s | 7.586 | 0.667 |
| go-v0.39 x go-v0.45 (ws, noise, yamux) | go-v0.39 | go-v0.45 | ws | noise | yamux | ✅ | 5s | 15.979 | 0.557 |
| go-v0.39 x go-v0.45 (quic-v1) | go-v0.39 | go-v0.45 | quic-v1 | - | - | ✅ | 4s | 21.773 | 4.086 |
| go-v0.39 x go-v0.45 (wss, noise, yamux) | go-v0.39 | go-v0.45 | wss | noise | yamux | ✅ | 5s | 18.44 | 1.838 |
| go-v0.39 x go-v0.45 (wss, tls, yamux) | go-v0.39 | go-v0.45 | wss | tls | yamux | ✅ | 6s | 12.659 | 0.694 |
| go-v0.39 x go-v0.45 (webtransport) | go-v0.39 | go-v0.45 | webtransport | - | - | ✅ | 5s | 13.64 | 0.647 |
| go-v0.39 x go-v0.45 (webrtc-direct) | go-v0.39 | go-v0.45 | webrtc-direct | - | - | ✅ | 5s | 31.775 | 1.608 |
| go-v0.39 x python-v0.4 (tcp, noise, yamux) | go-v0.39 | python-v0.4 | tcp | noise | yamux | ✅ | 5s | 16.086 | 3.863 |
| go-v0.39 x python-v0.4 (ws, noise, yamux) | go-v0.39 | python-v0.4 | ws | noise | yamux | ✅ | 5s | 29.03 | 4.698 |
| go-v0.39 x python-v0.4 (wss, noise, yamux) | go-v0.39 | python-v0.4 | wss | noise | yamux | ✅ | 5s | 38.722 | 7.012 |
| go-v0.39 x python-v0.4 (quic-v1) | go-v0.39 | python-v0.4 | quic-v1 | - | - | ✅ | 5s | 70.79 | 20.547 |
| go-v0.39 x nim-v1.14 (tcp, noise, yamux) | go-v0.39 | nim-v1.14 | tcp | noise | yamux | ✅ | 4s | 212.077 | 43.409 |
| go-v0.39 x nim-v1.14 (ws, noise, yamux) | go-v0.39 | nim-v1.14 | ws | noise | yamux | ✅ | 5s | 254.075 | 44.872 |
| go-v0.39 x js-v1.x (tcp, noise, yamux) | go-v0.39 | js-v1.x | tcp | noise | yamux | ✅ | 19s | 156.346 | 16.916 |
| go-v0.39 x js-v1.x (ws, noise, yamux) | go-v0.39 | js-v1.x | ws | noise | yamux | ✅ | 19s | 166.13 | 19.223 |
| go-v0.39 x js-v2.x (tcp, noise, yamux) | go-v0.39 | js-v2.x | tcp | noise | yamux | ✅ | 21s | 174.868 | 23.493 |
| go-v0.39 x jvm-v1.2 (tcp, noise, yamux) | go-v0.39 | jvm-v1.2 | tcp | noise | yamux | ✅ | 11s | 1377.57 | 22.438 |
| go-v0.39 x js-v3.x (tcp, noise, yamux) | go-v0.39 | js-v3.x | tcp | noise | yamux | ✅ | 20s | 104.646 | 14.885 |
| go-v0.39 x jvm-v1.2 (tcp, tls, yamux) | go-v0.39 | jvm-v1.2 | tcp | tls | yamux | ✅ | 13s | 3434.654 | 12.89 |
| go-v0.39 x js-v2.x (ws, noise, yamux) | go-v0.39 | js-v2.x | ws | noise | yamux | ✅ | 22s | 104.585 | 20.721 |
| go-v0.39 x js-v3.x (ws, noise, yamux) | go-v0.39 | js-v3.x | ws | noise | yamux | ✅ | 21s | 86.676 | 16.843 |
| go-v0.39 x c-v0.0.1 (tcp, noise, yamux) | go-v0.39 | c-v0.0.1 | tcp | noise | yamux | ✅ | 5s | 122.775 | 51.643 |
| go-v0.39 x c-v0.0.1 (quic-v1) | go-v0.39 | c-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 96.862 | 48.216 |
| go-v0.39 x dotnet-v1.0 (tcp, noise, yamux) | go-v0.39 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 6s | 598.537 | 44.055 |
| go-v0.39 x jvm-v1.2 (ws, noise, yamux) | go-v0.39 | jvm-v1.2 | ws | noise | yamux | ✅ | 10s | 1713.479 | 68.959 |
| go-v0.39 x zig-v0.0.1 (quic-v1) | go-v0.39 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 6s | - | - |
| go-v0.39 x eth-p2p-z-v0.0.1 (quic-v1) | go-v0.39 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 15.641 | 0.279 |
| go-v0.39 x jvm-v1.2 (ws, tls, yamux) | go-v0.39 | jvm-v1.2 | ws | tls | yamux | ✅ | 12s | 3652.271 | 15.765 |
| go-v0.39 x jvm-v1.2 (quic-v1) | go-v0.39 | jvm-v1.2 | quic-v1 | - | - | ✅ | 10s | 457.072 | 6.335 |
| go-v0.40 x rust-v0.53 (tcp, tls, yamux) | go-v0.40 | rust-v0.53 | tcp | tls | yamux | ✅ | 4s | 91.934 | 43.06 |
| go-v0.40 x rust-v0.53 (tcp, noise, yamux) | go-v0.40 | rust-v0.53 | tcp | noise | yamux | ✅ | 4s | 136.19 | 43.701 |
| go-v0.40 x rust-v0.53 (ws, tls, yamux) | go-v0.40 | rust-v0.53 | ws | tls | yamux | ✅ | 4s | 188.781 | 45.788 |
| go-v0.40 x rust-v0.53 (ws, noise, yamux) | go-v0.40 | rust-v0.53 | ws | noise | yamux | ✅ | 5s | 181.411 | 42.523 |
| go-v0.40 x rust-v0.53 (quic-v1) | go-v0.40 | rust-v0.53 | quic-v1 | - | - | ✅ | 4s | 28.933 | 5.584 |
| go-v0.40 x rust-v0.54 (tcp, tls, yamux) | go-v0.40 | rust-v0.54 | tcp | tls | yamux | ✅ | 5s | 142.986 | 47.723 |
| go-v0.40 x rust-v0.53 (webrtc-direct) | go-v0.40 | rust-v0.53 | webrtc-direct | - | - | ✅ | 6s | 412.489 | 0.822 |
| go-v0.40 x rust-v0.54 (tcp, noise, yamux) | go-v0.40 | rust-v0.54 | tcp | noise | yamux | ✅ | 5s | 88.121 | 41.663 |
| go-v0.40 x rust-v0.54 (ws, tls, yamux) | go-v0.40 | rust-v0.54 | ws | tls | yamux | ✅ | 5s | 176.211 | 43.172 |
| go-v0.40 x rust-v0.54 (ws, noise, yamux) | go-v0.40 | rust-v0.54 | ws | noise | yamux | ✅ | 5s | 185.74 | 43.059 |
| go-v0.40 x rust-v0.54 (quic-v1) | go-v0.40 | rust-v0.54 | quic-v1 | - | - | ✅ | 4s | 13.765 | 2.13 |
| go-v0.40 x rust-v0.55 (tcp, tls, yamux) | go-v0.40 | rust-v0.55 | tcp | tls | yamux | ✅ | 5s | 6.594 | 0.317 |
| go-v0.40 x rust-v0.55 (ws, tls, yamux) | go-v0.40 | rust-v0.55 | ws | tls | yamux | ✅ | 5s | 9.463 | 0.252 |
| go-v0.40 x rust-v0.55 (tcp, noise, yamux) | go-v0.40 | rust-v0.55 | tcp | noise | yamux | ✅ | 5s | 8.98 | 0.36 |
| go-v0.40 x rust-v0.54 (webrtc-direct) | go-v0.40 | rust-v0.54 | webrtc-direct | - | - | ✅ | 6s | 450.113 | 1.36 |
| go-v0.40 x rust-v0.55 (ws, noise, yamux) | go-v0.40 | rust-v0.55 | ws | noise | yamux | ✅ | 5s | 5.793 | 0.367 |
| go-v0.40 x rust-v0.55 (quic-v1) | go-v0.40 | rust-v0.55 | quic-v1 | - | - | ✅ | 4s | 5.98 | 0.267 |
| go-v0.40 x rust-v0.55 (webrtc-direct) | go-v0.40 | rust-v0.55 | webrtc-direct | - | - | ✅ | 4s | 420.275 | 0.608 |
| go-v0.40 x rust-v0.56 (tcp, tls, yamux) | go-v0.40 | rust-v0.56 | tcp | tls | yamux | ✅ | 5s | 9.351 | 0.386 |
| go-v0.40 x rust-v0.56 (tcp, noise, yamux) | go-v0.40 | rust-v0.56 | tcp | noise | yamux | ✅ | 4s | 5.78 | 0.319 |
| go-v0.40 x rust-v0.56 (ws, tls, yamux) | go-v0.40 | rust-v0.56 | ws | tls | yamux | ✅ | 5s | 10.254 | 0.758 |
| go-v0.40 x rust-v0.56 (ws, noise, yamux) | go-v0.40 | rust-v0.56 | ws | noise | yamux | ✅ | 4s | 11.18 | 0.376 |
| go-v0.40 x rust-v0.56 (quic-v1) | go-v0.40 | rust-v0.56 | quic-v1 | - | - | ✅ | 5s | 5.631 | 0.228 |
| go-v0.40 x go-v0.38 (tcp, tls, yamux) | go-v0.40 | go-v0.38 | tcp | tls | yamux | ✅ | 5s | 10.997 | 0.657 |
| go-v0.40 x go-v0.38 (tcp, noise, yamux) | go-v0.40 | go-v0.38 | tcp | noise | yamux | ✅ | 4s | 13.161 | 2.39 |
| go-v0.40 x go-v0.38 (ws, tls, yamux) | go-v0.40 | go-v0.38 | ws | tls | yamux | ✅ | 5s | 6.061 | 0.315 |
| go-v0.40 x go-v0.38 (ws, noise, yamux) | go-v0.40 | go-v0.38 | ws | noise | yamux | ✅ | 3s | 9.203 | 1.039 |
| go-v0.40 x go-v0.38 (wss, tls, yamux) | go-v0.40 | go-v0.38 | wss | tls | yamux | ✅ | 5s | 14.236 | 0.434 |
| go-v0.40 x go-v0.38 (quic-v1) | go-v0.40 | go-v0.38 | quic-v1 | - | - | ✅ | 5s | 8.536 | 0.759 |
| go-v0.40 x rust-v0.56 (webrtc-direct) | go-v0.40 | rust-v0.56 | webrtc-direct | - | - | ❌ | 10s | - | - |
| go-v0.40 x go-v0.38 (wss, noise, yamux) | go-v0.40 | go-v0.38 | wss | noise | yamux | ✅ | 6s | 8.302 | 0.206 |
| go-v0.40 x go-v0.38 (webtransport) | go-v0.40 | go-v0.38 | webtransport | - | - | ✅ | 5s | 8.727 | 0.425 |
| go-v0.40 x go-v0.38 (webrtc-direct) | go-v0.40 | go-v0.38 | webrtc-direct | - | - | ✅ | 5s | 208.677 | 0.235 |
| go-v0.40 x go-v0.39 (tcp, tls, yamux) | go-v0.40 | go-v0.39 | tcp | tls | yamux | ✅ | 4s | 7.091 | 1.1 |
| go-v0.40 x go-v0.39 (tcp, noise, yamux) | go-v0.40 | go-v0.39 | tcp | noise | yamux | ✅ | 5s | 8.34 | 0.962 |
| go-v0.40 x go-v0.39 (ws, tls, yamux) | go-v0.40 | go-v0.39 | ws | tls | yamux | ✅ | 5s | 6.658 | 0.347 |
| go-v0.40 x go-v0.39 (ws, noise, yamux) | go-v0.40 | go-v0.39 | ws | noise | yamux | ✅ | 5s | 29.972 | 1.046 |
| go-v0.40 x go-v0.39 (wss, tls, yamux) | go-v0.40 | go-v0.39 | wss | tls | yamux | ✅ | 5s | 20.795 | 0.861 |
| go-v0.40 x go-v0.39 (wss, noise, yamux) | go-v0.40 | go-v0.39 | wss | noise | yamux | ✅ | 6s | 18.909 | 1.766 |
| go-v0.40 x go-v0.39 (quic-v1) | go-v0.40 | go-v0.39 | quic-v1 | - | - | ✅ | 5s | 8.682 | 1.224 |
| go-v0.40 x go-v0.39 (webtransport) | go-v0.40 | go-v0.39 | webtransport | - | - | ✅ | 5s | 9.153 | 0.302 |
| go-v0.40 x go-v0.39 (webrtc-direct) | go-v0.40 | go-v0.39 | webrtc-direct | - | - | ✅ | 5s | 208.814 | 0.345 |
| go-v0.40 x go-v0.40 (tcp, tls, yamux) | go-v0.40 | go-v0.40 | tcp | tls | yamux | ✅ | 5s | 10.409 | 1.806 |
| go-v0.40 x go-v0.40 (tcp, noise, yamux) | go-v0.40 | go-v0.40 | tcp | noise | yamux | ✅ | 5s | 9.009 | 0.738 |
| go-v0.40 x go-v0.40 (ws, tls, yamux) | go-v0.40 | go-v0.40 | ws | tls | yamux | ✅ | 4s | 6.025 | 0.227 |
| go-v0.40 x go-v0.40 (ws, noise, yamux) | go-v0.40 | go-v0.40 | ws | noise | yamux | ✅ | 4s | 9.218 | 0.351 |
| go-v0.40 x go-v0.40 (wss, tls, yamux) | go-v0.40 | go-v0.40 | wss | tls | yamux | ✅ | 4s | 14.452 | 0.759 |
| go-v0.40 x go-v0.40 (wss, noise, yamux) | go-v0.40 | go-v0.40 | wss | noise | yamux | ✅ | 5s | 10.1 | 0.389 |
| go-v0.40 x go-v0.40 (quic-v1) | go-v0.40 | go-v0.40 | quic-v1 | - | - | ✅ | 5s | 12.451 | 1.633 |
| go-v0.40 x go-v0.40 (webtransport) | go-v0.40 | go-v0.40 | webtransport | - | - | ✅ | 6s | 10.089 | 0.372 |
| go-v0.40 x go-v0.40 (webrtc-direct) | go-v0.40 | go-v0.40 | webrtc-direct | - | - | ✅ | 5s | 212.969 | 0.338 |
| go-v0.40 x go-v0.41 (tcp, tls, yamux) | go-v0.40 | go-v0.41 | tcp | tls | yamux | ✅ | 5s | 6.739 | 0.668 |
| go-v0.40 x go-v0.41 (tcp, noise, yamux) | go-v0.40 | go-v0.41 | tcp | noise | yamux | ✅ | 5s | 9.902 | 3.395 |
| go-v0.40 x go-v0.41 (ws, tls, yamux) | go-v0.40 | go-v0.41 | ws | tls | yamux | ✅ | 5s | 6.674 | 1.105 |
| go-v0.40 x go-v0.41 (ws, noise, yamux) | go-v0.40 | go-v0.41 | ws | noise | yamux | ✅ | 4s | 5.178 | 0.241 |
| go-v0.40 x go-v0.41 (wss, tls, yamux) | go-v0.40 | go-v0.41 | wss | tls | yamux | ✅ | 4s | 12.592 | 0.534 |
| go-v0.40 x go-v0.41 (wss, noise, yamux) | go-v0.40 | go-v0.41 | wss | noise | yamux | ✅ | 5s | 13.78 | 1.865 |
| go-v0.40 x go-v0.41 (webtransport) | go-v0.40 | go-v0.41 | webtransport | - | - | ✅ | 4s | 15.16 | 0.661 |
| go-v0.40 x go-v0.41 (quic-v1) | go-v0.40 | go-v0.41 | quic-v1 | - | - | ✅ | 5s | 10.099 | 0.542 |
| go-v0.40 x go-v0.41 (webrtc-direct) | go-v0.40 | go-v0.41 | webrtc-direct | - | - | ✅ | 5s | 210.01 | 0.263 |
| go-v0.40 x go-v0.42 (tcp, tls, yamux) | go-v0.40 | go-v0.42 | tcp | tls | yamux | ✅ | 5s | 4.48 | 0.198 |
| go-v0.40 x go-v0.42 (tcp, noise, yamux) | go-v0.40 | go-v0.42 | tcp | noise | yamux | ✅ | 5s | 9.474 | 2.251 |
| go-v0.40 x go-v0.42 (ws, tls, yamux) | go-v0.40 | go-v0.42 | ws | tls | yamux | ✅ | 5s | 8.309 | 0.637 |
| go-v0.40 x go-v0.42 (ws, noise, yamux) | go-v0.40 | go-v0.42 | ws | noise | yamux | ✅ | 4s | 7.456 | 1.546 |
| go-v0.40 x go-v0.42 (wss, noise, yamux) | go-v0.40 | go-v0.42 | wss | noise | yamux | ✅ | 5s | 20.083 | 0.873 |
| go-v0.40 x go-v0.42 (wss, tls, yamux) | go-v0.40 | go-v0.42 | wss | tls | yamux | ✅ | 6s | 13.676 | 0.892 |
| go-v0.40 x go-v0.42 (quic-v1) | go-v0.40 | go-v0.42 | quic-v1 | - | - | ✅ | 5s | 16.844 | 0.504 |
| go-v0.40 x go-v0.42 (webtransport) | go-v0.40 | go-v0.42 | webtransport | - | - | ✅ | 4s | 15.881 | 1.43 |
| go-v0.40 x go-v0.42 (webrtc-direct) | go-v0.40 | go-v0.42 | webrtc-direct | - | - | ✅ | 5s | 209.612 | 0.281 |
| go-v0.40 x go-v0.43 (tcp, tls, yamux) | go-v0.40 | go-v0.43 | tcp | tls | yamux | ✅ | 5s | 11.452 | 2.634 |
| go-v0.40 x go-v0.43 (tcp, noise, yamux) | go-v0.40 | go-v0.43 | tcp | noise | yamux | ✅ | 5s | 8.017 | 0.353 |
| go-v0.40 x go-v0.43 (ws, tls, yamux) | go-v0.40 | go-v0.43 | ws | tls | yamux | ✅ | 5s | 7.691 | 0.372 |
| go-v0.40 x go-v0.43 (ws, noise, yamux) | go-v0.40 | go-v0.43 | ws | noise | yamux | ✅ | 4s | 6.564 | 0.765 |
| go-v0.40 x go-v0.43 (wss, tls, yamux) | go-v0.40 | go-v0.43 | wss | tls | yamux | ✅ | 5s | 16.802 | 0.665 |
| go-v0.40 x go-v0.43 (quic-v1) | go-v0.40 | go-v0.43 | quic-v1 | - | - | ✅ | 5s | 19.358 | 2.116 |
| go-v0.40 x go-v0.43 (wss, noise, yamux) | go-v0.40 | go-v0.43 | wss | noise | yamux | ✅ | 5s | 19.264 | 0.553 |
| go-v0.40 x go-v0.43 (webtransport) | go-v0.40 | go-v0.43 | webtransport | - | - | ✅ | 6s | 18.991 | 1.183 |
| go-v0.40 x go-v0.43 (webrtc-direct) | go-v0.40 | go-v0.43 | webrtc-direct | - | - | ✅ | 5s | 209.493 | 0.224 |
| go-v0.40 x go-v0.44 (tcp, tls, yamux) | go-v0.40 | go-v0.44 | tcp | tls | yamux | ✅ | 5s | 9.522 | 0.566 |
| go-v0.40 x go-v0.44 (tcp, noise, yamux) | go-v0.40 | go-v0.44 | tcp | noise | yamux | ✅ | 5s | 6.793 | 0.398 |
| go-v0.40 x go-v0.44 (ws, tls, yamux) | go-v0.40 | go-v0.44 | ws | tls | yamux | ✅ | 5s | 12.471 | 0.389 |
| go-v0.40 x go-v0.44 (ws, noise, yamux) | go-v0.40 | go-v0.44 | ws | noise | yamux | ✅ | 4s | 9.326 | 1.363 |
| go-v0.40 x go-v0.44 (wss, tls, yamux) | go-v0.40 | go-v0.44 | wss | tls | yamux | ✅ | 5s | 11.031 | 0.511 |
| go-v0.40 x go-v0.44 (wss, noise, yamux) | go-v0.40 | go-v0.44 | wss | noise | yamux | ✅ | 5s | 15.036 | 2.065 |
| go-v0.40 x go-v0.44 (quic-v1) | go-v0.40 | go-v0.44 | quic-v1 | - | - | ✅ | 5s | 10.625 | 0.439 |
| go-v0.40 x go-v0.44 (webtransport) | go-v0.40 | go-v0.44 | webtransport | - | - | ✅ | 5s | 32.222 | 3.254 |
| go-v0.40 x go-v0.44 (webrtc-direct) | go-v0.40 | go-v0.44 | webrtc-direct | - | - | ✅ | 5s | 13.899 | 0.403 |
| go-v0.40 x go-v0.45 (tcp, tls, yamux) | go-v0.40 | go-v0.45 | tcp | tls | yamux | ✅ | 5s | 11.214 | 0.663 |
| go-v0.40 x go-v0.45 (tcp, noise, yamux) | go-v0.40 | go-v0.45 | tcp | noise | yamux | ✅ | 5s | 8.788 | 1.117 |
| go-v0.40 x go-v0.45 (ws, tls, yamux) | go-v0.40 | go-v0.45 | ws | tls | yamux | ✅ | 6s | 8.021 | 0.476 |
| go-v0.40 x go-v0.45 (ws, noise, yamux) | go-v0.40 | go-v0.45 | ws | noise | yamux | ✅ | 4s | 10.749 | 0.445 |
| go-v0.40 x go-v0.45 (wss, tls, yamux) | go-v0.40 | go-v0.45 | wss | tls | yamux | ✅ | 5s | 12.569 | 0.372 |
| go-v0.40 x go-v0.45 (wss, noise, yamux) | go-v0.40 | go-v0.45 | wss | noise | yamux | ✅ | 5s | 16.739 | 0.847 |
| go-v0.40 x go-v0.45 (quic-v1) | go-v0.40 | go-v0.45 | quic-v1 | - | - | ✅ | 5s | 20.769 | 1.412 |
| go-v0.40 x go-v0.45 (webtransport) | go-v0.40 | go-v0.45 | webtransport | - | - | ✅ | 5s | 18.677 | 0.687 |
| go-v0.40 x go-v0.45 (webrtc-direct) | go-v0.40 | go-v0.45 | webrtc-direct | - | - | ✅ | 4s | 217.099 | 0.409 |
| go-v0.40 x python-v0.4 (tcp, noise, yamux) | go-v0.40 | python-v0.4 | tcp | noise | yamux | ✅ | 5s | 29.118 | 5.66 |
| go-v0.40 x python-v0.4 (ws, noise, yamux) | go-v0.40 | python-v0.4 | ws | noise | yamux | ✅ | 6s | 46.555 | 6.531 |
| go-v0.40 x python-v0.4 (quic-v1) | go-v0.40 | python-v0.4 | quic-v1 | - | - | ✅ | 5s | 69.278 | 8.861 |
| go-v0.40 x python-v0.4 (wss, noise, yamux) | go-v0.40 | python-v0.4 | wss | noise | yamux | ✅ | 6s | 27.49 | 3.1 |
| go-v0.40 x nim-v1.14 (tcp, noise, yamux) | go-v0.40 | nim-v1.14 | tcp | noise | yamux | ✅ | 5s | 190.203 | 55.636 |
| go-v0.40 x nim-v1.14 (ws, noise, yamux) | go-v0.40 | nim-v1.14 | ws | noise | yamux | ✅ | 5s | 258.059 | 43.579 |
| go-v0.40 x js-v1.x (tcp, noise, yamux) | go-v0.40 | js-v1.x | tcp | noise | yamux | ✅ | 19s | 136.004 | 16.665 |
| go-v0.40 x js-v1.x (ws, noise, yamux) | go-v0.40 | js-v1.x | ws | noise | yamux | ✅ | 19s | 183.184 | 22.388 |
| go-v0.40 x jvm-v1.2 (tcp, noise, yamux) | go-v0.40 | jvm-v1.2 | tcp | noise | yamux | ✅ | 10s | 1013.11 | 21.755 |
| go-v0.40 x js-v2.x (tcp, noise, yamux) | go-v0.40 | js-v2.x | tcp | noise | yamux | ✅ | 23s | 149.451 | 22.534 |
| go-v0.40 x js-v2.x (ws, noise, yamux) | go-v0.40 | js-v2.x | ws | noise | yamux | ✅ | 22s | 135.501 | 26.552 |
| go-v0.40 x js-v3.x (tcp, noise, yamux) | go-v0.40 | js-v3.x | tcp | noise | yamux | ✅ | 21s | 137.975 | 17.175 |
| go-v0.40 x js-v3.x (ws, noise, yamux) | go-v0.40 | js-v3.x | ws | noise | yamux | ✅ | 21s | 94.245 | 12.095 |
| go-v0.40 x jvm-v1.2 (tcp, tls, yamux) | go-v0.40 | jvm-v1.2 | tcp | tls | yamux | ✅ | 13s | 2791.095 | 5.789 |
| go-v0.40 x c-v0.0.1 (tcp, noise, yamux) | go-v0.40 | c-v0.0.1 | tcp | noise | yamux | ✅ | 5s | 127.348 | 53.208 |
| go-v0.40 x c-v0.0.1 (quic-v1) | go-v0.40 | c-v0.0.1 | quic-v1 | - | - | ✅ | 5s | 37.503 | 3.584 |
| go-v0.40 x dotnet-v1.0 (tcp, noise, yamux) | go-v0.40 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 6s | 575.443 | 54.318 |
| go-v0.40 x jvm-v1.2 (ws, noise, yamux) | go-v0.40 | jvm-v1.2 | ws | noise | yamux | ✅ | 10s | 1561.235 | 104.537 |
| go-v0.40 x zig-v0.0.1 (quic-v1) | go-v0.40 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 6s | - | - |
| go-v0.40 x jvm-v1.2 (ws, tls, yamux) | go-v0.40 | jvm-v1.2 | ws | tls | yamux | ✅ | 13s | 3785.004 | 23.067 |
| go-v0.40 x eth-p2p-z-v0.0.1 (quic-v1) | go-v0.40 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 21.606 | 0.232 |
| go-v0.40 x jvm-v1.2 (quic-v1) | go-v0.40 | jvm-v1.2 | quic-v1 | - | - | ✅ | 10s | 465.472 | 6.025 |
| go-v0.41 x rust-v0.53 (tcp, tls, yamux) | go-v0.41 | rust-v0.53 | tcp | tls | yamux | ✅ | 4s | 96.798 | 45.443 |
| go-v0.41 x rust-v0.53 (tcp, noise, yamux) | go-v0.41 | rust-v0.53 | tcp | noise | yamux | ✅ | 5s | 94.533 | 43.139 |
| go-v0.41 x rust-v0.53 (ws, tls, yamux) | go-v0.41 | rust-v0.53 | ws | tls | yamux | ✅ | 4s | 178.17 | 44.863 |
| go-v0.41 x rust-v0.53 (ws, noise, yamux) | go-v0.41 | rust-v0.53 | ws | noise | yamux | ✅ | 4s | 217.886 | 43.574 |
| go-v0.41 x rust-v0.53 (quic-v1) | go-v0.41 | rust-v0.53 | quic-v1 | - | - | ✅ | 5s | 7.772 | 0.267 |
| go-v0.41 x rust-v0.54 (tcp, tls, yamux) | go-v0.41 | rust-v0.54 | tcp | tls | yamux | ✅ | 5s | 99.287 | 42.387 |
| go-v0.41 x rust-v0.53 (webrtc-direct) | go-v0.41 | rust-v0.53 | webrtc-direct | - | - | ✅ | 5s | 411.833 | 0.87 |
| go-v0.41 x rust-v0.54 (tcp, noise, yamux) | go-v0.41 | rust-v0.54 | tcp | noise | yamux | ✅ | 4s | 97.224 | 46.496 |
| go-v0.41 x rust-v0.54 (ws, tls, yamux) | go-v0.41 | rust-v0.54 | ws | tls | yamux | ✅ | 4s | 183.471 | 42.911 |
| go-v0.41 x rust-v0.54 (ws, noise, yamux) | go-v0.41 | rust-v0.54 | ws | noise | yamux | ✅ | 5s | 229.338 | 43.781 |
| go-v0.41 x rust-v0.54 (quic-v1) | go-v0.41 | rust-v0.54 | quic-v1 | - | - | ✅ | 5s | 6.458 | 0.615 |
| go-v0.41 x rust-v0.54 (webrtc-direct) | go-v0.41 | rust-v0.54 | webrtc-direct | - | - | ✅ | 4s | 409.37 | 0.329 |
| go-v0.41 x rust-v0.55 (tcp, tls, yamux) | go-v0.41 | rust-v0.55 | tcp | tls | yamux | ✅ | 5s | 13.285 | 0.756 |
| go-v0.41 x rust-v0.55 (tcp, noise, yamux) | go-v0.41 | rust-v0.55 | tcp | noise | yamux | ✅ | 5s | 9.052 | 0.856 |
| go-v0.41 x rust-v0.55 (ws, tls, yamux) | go-v0.41 | rust-v0.55 | ws | tls | yamux | ✅ | 4s | 7.282 | 0.62 |
| go-v0.41 x rust-v0.55 (ws, noise, yamux) | go-v0.41 | rust-v0.55 | ws | noise | yamux | ✅ | 5s | 4.609 | 0.23 |
| go-v0.41 x rust-v0.55 (quic-v1) | go-v0.41 | rust-v0.55 | quic-v1 | - | - | ✅ | 4s | 7.008 | 0.246 |
| go-v0.41 x rust-v0.55 (webrtc-direct) | go-v0.41 | rust-v0.55 | webrtc-direct | - | - | ✅ | 6s | 432.312 | 2.084 |
| go-v0.41 x rust-v0.56 (tcp, tls, yamux) | go-v0.41 | rust-v0.56 | tcp | tls | yamux | ✅ | 5s | 12.835 | 0.59 |
| go-v0.41 x rust-v0.56 (tcp, noise, yamux) | go-v0.41 | rust-v0.56 | tcp | noise | yamux | ✅ | 4s | 8.701 | 1.695 |
| go-v0.41 x rust-v0.56 (ws, tls, yamux) | go-v0.41 | rust-v0.56 | ws | tls | yamux | ✅ | 4s | 10.387 | 0.46 |
| go-v0.41 x rust-v0.56 (ws, noise, yamux) | go-v0.41 | rust-v0.56 | ws | noise | yamux | ✅ | 4s | 9.838 | 0.753 |
| go-v0.41 x rust-v0.56 (quic-v1) | go-v0.41 | rust-v0.56 | quic-v1 | - | - | ✅ | 5s | 9.142 | 0.588 |
| go-v0.41 x go-v0.38 (tcp, tls, yamux) | go-v0.41 | go-v0.38 | tcp | tls | yamux | ✅ | 4s | 9.088 | 0.3 |
| go-v0.41 x go-v0.38 (tcp, noise, yamux) | go-v0.41 | go-v0.38 | tcp | noise | yamux | ✅ | 5s | 6.055 | 0.402 |
| go-v0.41 x go-v0.38 (ws, noise, yamux) | go-v0.41 | go-v0.38 | ws | noise | yamux | ✅ | 4s | 15.02 | 1.395 |
| go-v0.41 x go-v0.38 (ws, tls, yamux) | go-v0.41 | go-v0.38 | ws | tls | yamux | ✅ | 4s | 8.948 | 0.568 |
| go-v0.41 x go-v0.38 (wss, tls, yamux) | go-v0.41 | go-v0.38 | wss | tls | yamux | ✅ | 4s | 7.135 | 0.183 |
| go-v0.41 x go-v0.38 (quic-v1) | go-v0.41 | go-v0.38 | quic-v1 | - | - | ✅ | 4s | 15.281 | 0.631 |
| go-v0.41 x go-v0.38 (webtransport) | go-v0.41 | go-v0.38 | webtransport | - | - | ✅ | 4s | 13.923 | 0.679 |
| go-v0.41 x rust-v0.56 (webrtc-direct) | go-v0.41 | rust-v0.56 | webrtc-direct | - | - | ❌ | 11s | - | - |
| go-v0.41 x go-v0.38 (wss, noise, yamux) | go-v0.41 | go-v0.38 | wss | noise | yamux | ✅ | 7s | 14.31 | 0.758 |
| go-v0.41 x go-v0.38 (webrtc-direct) | go-v0.41 | go-v0.38 | webrtc-direct | - | - | ✅ | 5s | 212.563 | 0.499 |
| go-v0.41 x go-v0.39 (tcp, tls, yamux) | go-v0.41 | go-v0.39 | tcp | tls | yamux | ✅ | 4s | 11.525 | 0.675 |
| go-v0.41 x go-v0.39 (tcp, noise, yamux) | go-v0.41 | go-v0.39 | tcp | noise | yamux | ✅ | 5s | 7.158 | 0.357 |
| go-v0.41 x go-v0.39 (ws, tls, yamux) | go-v0.41 | go-v0.39 | ws | tls | yamux | ✅ | 5s | 11.49 | 0.367 |
| go-v0.41 x go-v0.39 (ws, noise, yamux) | go-v0.41 | go-v0.39 | ws | noise | yamux | ✅ | 4s | 15.03 | 0.651 |
| go-v0.41 x go-v0.39 (wss, tls, yamux) | go-v0.41 | go-v0.39 | wss | tls | yamux | ✅ | 4s | 20.811 | 0.689 |
| go-v0.41 x go-v0.39 (wss, noise, yamux) | go-v0.41 | go-v0.39 | wss | noise | yamux | ✅ | 5s | 18.738 | 1.785 |
| go-v0.41 x go-v0.39 (quic-v1) | go-v0.41 | go-v0.39 | quic-v1 | - | - | ✅ | 4s | 8.044 | 0.449 |
| go-v0.41 x go-v0.39 (webtransport) | go-v0.41 | go-v0.39 | webtransport | - | - | ✅ | 5s | 6.019 | 0.236 |
| go-v0.41 x go-v0.39 (webrtc-direct) | go-v0.41 | go-v0.39 | webrtc-direct | - | - | ✅ | 5s | 217.039 | 0.659 |
| go-v0.41 x go-v0.40 (tcp, tls, yamux) | go-v0.41 | go-v0.40 | tcp | tls | yamux | ✅ | 5s | 13.998 | 2.863 |
| go-v0.41 x go-v0.40 (tcp, noise, yamux) | go-v0.41 | go-v0.40 | tcp | noise | yamux | ✅ | 5s | 6.129 | 0.767 |
| go-v0.41 x go-v0.40 (ws, tls, yamux) | go-v0.41 | go-v0.40 | ws | tls | yamux | ✅ | 4s | 14.132 | 0.304 |
| go-v0.41 x go-v0.40 (ws, noise, yamux) | go-v0.41 | go-v0.40 | ws | noise | yamux | ✅ | 4s | 14.894 | 0.741 |
| go-v0.41 x go-v0.40 (quic-v1) | go-v0.41 | go-v0.40 | quic-v1 | - | - | ✅ | 4s | 13.241 | 0.507 |
| go-v0.41 x go-v0.40 (wss, noise, yamux) | go-v0.41 | go-v0.40 | wss | noise | yamux | ✅ | 5s | 18.9 | 2.086 |
| go-v0.41 x go-v0.40 (wss, tls, yamux) | go-v0.41 | go-v0.40 | wss | tls | yamux | ✅ | 6s | 12.848 | 0.289 |
| go-v0.41 x go-v0.40 (webtransport) | go-v0.41 | go-v0.40 | webtransport | - | - | ✅ | 5s | 6.54 | 0.365 |
| go-v0.41 x go-v0.40 (webrtc-direct) | go-v0.41 | go-v0.40 | webrtc-direct | - | - | ✅ | 5s | 216.883 | 1.071 |
| go-v0.41 x go-v0.41 (tcp, tls, yamux) | go-v0.41 | go-v0.41 | tcp | tls | yamux | ✅ | 5s | 11.364 | 1.476 |
| go-v0.41 x go-v0.41 (tcp, noise, yamux) | go-v0.41 | go-v0.41 | tcp | noise | yamux | ✅ | 5s | 8.297 | 0.547 |
| go-v0.41 x go-v0.41 (ws, tls, yamux) | go-v0.41 | go-v0.41 | ws | tls | yamux | ✅ | 5s | 15.277 | 1.41 |
| go-v0.41 x go-v0.41 (ws, noise, yamux) | go-v0.41 | go-v0.41 | ws | noise | yamux | ✅ | 4s | 16.603 | 1.205 |
| go-v0.41 x go-v0.41 (wss, tls, yamux) | go-v0.41 | go-v0.41 | wss | tls | yamux | ✅ | 6s | 19.202 | 0.412 |
| go-v0.41 x go-v0.41 (quic-v1) | go-v0.41 | go-v0.41 | quic-v1 | - | - | ✅ | 5s | 13.968 | 1.269 |
| go-v0.41 x go-v0.41 (wss, noise, yamux) | go-v0.41 | go-v0.41 | wss | noise | yamux | ✅ | 6s | 21.206 | 0.328 |
| go-v0.41 x go-v0.41 (webtransport) | go-v0.41 | go-v0.41 | webtransport | - | - | ✅ | 5s | 8.555 | 0.47 |
| go-v0.41 x go-v0.41 (webrtc-direct) | go-v0.41 | go-v0.41 | webrtc-direct | - | - | ✅ | 4s | 9.763 | 0.462 |
| go-v0.41 x go-v0.42 (tcp, tls, yamux) | go-v0.41 | go-v0.42 | tcp | tls | yamux | ✅ | 5s | 5.751 | 0.709 |
| go-v0.41 x go-v0.42 (tcp, noise, yamux) | go-v0.41 | go-v0.42 | tcp | noise | yamux | ✅ | 5s | 8.943 | 0.878 |
| go-v0.41 x go-v0.42 (ws, tls, yamux) | go-v0.41 | go-v0.42 | ws | tls | yamux | ✅ | 4s | 13.544 | 0.412 |
| go-v0.41 x go-v0.42 (ws, noise, yamux) | go-v0.41 | go-v0.42 | ws | noise | yamux | ✅ | 5s | 14.643 | 2.556 |
| go-v0.41 x go-v0.42 (wss, tls, yamux) | go-v0.41 | go-v0.42 | wss | tls | yamux | ✅ | 5s | 22.464 | 1.811 |
| go-v0.41 x go-v0.42 (wss, noise, yamux) | go-v0.41 | go-v0.42 | wss | noise | yamux | ✅ | 5s | 20.266 | 0.49 |
| go-v0.41 x go-v0.42 (webtransport) | go-v0.41 | go-v0.42 | webtransport | - | - | ✅ | 4s | 13.233 | 0.34 |
| go-v0.41 x go-v0.42 (quic-v1) | go-v0.41 | go-v0.42 | quic-v1 | - | - | ✅ | 5s | 10.877 | 0.437 |
| go-v0.41 x go-v0.42 (webrtc-direct) | go-v0.41 | go-v0.42 | webrtc-direct | - | - | ✅ | 6s | 216.785 | 0.742 |
| go-v0.41 x go-v0.43 (tcp, tls, yamux) | go-v0.41 | go-v0.43 | tcp | tls | yamux | ✅ | 5s | 20.413 | 2.735 |
| go-v0.41 x go-v0.43 (ws, tls, yamux) | go-v0.41 | go-v0.43 | ws | tls | yamux | ✅ | 4s | 7.523 | 0.601 |
| go-v0.41 x go-v0.43 (tcp, noise, yamux) | go-v0.41 | go-v0.43 | tcp | noise | yamux | ✅ | 5s | 7.306 | 0.74 |
| go-v0.41 x go-v0.43 (ws, noise, yamux) | go-v0.41 | go-v0.43 | ws | noise | yamux | ✅ | 5s | 15.868 | 1.219 |
| go-v0.41 x go-v0.43 (wss, tls, yamux) | go-v0.41 | go-v0.43 | wss | tls | yamux | ✅ | 5s | 20.086 | 4.326 |
| go-v0.41 x go-v0.43 (quic-v1) | go-v0.41 | go-v0.43 | quic-v1 | - | - | ✅ | 5s | 11.273 | 0.513 |
| go-v0.41 x go-v0.43 (wss, noise, yamux) | go-v0.41 | go-v0.43 | wss | noise | yamux | ✅ | 5s | 17.373 | 1.396 |
| go-v0.41 x go-v0.43 (webtransport) | go-v0.41 | go-v0.43 | webtransport | - | - | ✅ | 6s | 16.64 | 0.494 |
| go-v0.41 x go-v0.43 (webrtc-direct) | go-v0.41 | go-v0.43 | webrtc-direct | - | - | ✅ | 5s | 219.735 | 0.623 |
| go-v0.41 x go-v0.44 (tcp, tls, yamux) | go-v0.41 | go-v0.44 | tcp | tls | yamux | ✅ | 5s | 10.108 | 0.298 |
| go-v0.41 x go-v0.44 (tcp, noise, yamux) | go-v0.41 | go-v0.44 | tcp | noise | yamux | ✅ | 5s | 7.693 | 0.273 |
| go-v0.41 x go-v0.44 (ws, tls, yamux) | go-v0.41 | go-v0.44 | ws | tls | yamux | ✅ | 5s | 11.798 | 0.392 |
| go-v0.41 x go-v0.44 (ws, noise, yamux) | go-v0.41 | go-v0.44 | ws | noise | yamux | ✅ | 4s | 10.601 | 1.459 |
| go-v0.41 x go-v0.44 (wss, tls, yamux) | go-v0.41 | go-v0.44 | wss | tls | yamux | ✅ | 4s | 11.465 | 0.34 |
| go-v0.41 x go-v0.44 (wss, noise, yamux) | go-v0.41 | go-v0.44 | wss | noise | yamux | ✅ | 5s | 14.278 | 0.325 |
| go-v0.41 x go-v0.44 (quic-v1) | go-v0.41 | go-v0.44 | quic-v1 | - | - | ✅ | 5s | 16.357 | 1.023 |
| go-v0.41 x go-v0.44 (webtransport) | go-v0.41 | go-v0.44 | webtransport | - | - | ✅ | 5s | 16.692 | 1.878 |
| go-v0.41 x go-v0.44 (webrtc-direct) | go-v0.41 | go-v0.44 | webrtc-direct | - | - | ✅ | 5s | 210.953 | 0.38 |
| go-v0.41 x go-v0.45 (tcp, noise, yamux) | go-v0.41 | go-v0.45 | tcp | noise | yamux | ✅ | 5s | 5.098 | 0.245 |
| go-v0.41 x go-v0.45 (tcp, tls, yamux) | go-v0.41 | go-v0.45 | tcp | tls | yamux | ✅ | 5s | 4.945 | 0.551 |
| go-v0.41 x go-v0.45 (ws, tls, yamux) | go-v0.41 | go-v0.45 | ws | tls | yamux | ✅ | 5s | 8.799 | 0.462 |
| go-v0.41 x go-v0.45 (ws, noise, yamux) | go-v0.41 | go-v0.45 | ws | noise | yamux | ✅ | 5s | 7.872 | 0.547 |
| go-v0.41 x go-v0.45 (wss, tls, yamux) | go-v0.41 | go-v0.45 | wss | tls | yamux | ✅ | 5s | 15.286 | 1.125 |
| go-v0.41 x go-v0.45 (wss, noise, yamux) | go-v0.41 | go-v0.45 | wss | noise | yamux | ✅ | 4s | 13.961 | 3.323 |
| go-v0.41 x go-v0.45 (quic-v1) | go-v0.41 | go-v0.45 | quic-v1 | - | - | ✅ | 5s | 8.815 | 1.393 |
| go-v0.41 x go-v0.45 (webtransport) | go-v0.41 | go-v0.45 | webtransport | - | - | ✅ | 5s | 15.246 | 0.797 |
| go-v0.41 x go-v0.45 (webrtc-direct) | go-v0.41 | go-v0.45 | webrtc-direct | - | - | ✅ | 5s | 210.661 | 0.291 |
| go-v0.41 x python-v0.4 (tcp, noise, yamux) | go-v0.41 | python-v0.4 | tcp | noise | yamux | ✅ | 5s | 22.424 | 3.076 |
| go-v0.41 x python-v0.4 (ws, noise, yamux) | go-v0.41 | python-v0.4 | ws | noise | yamux | ✅ | 5s | 29.786 | 6.588 |
| go-v0.41 x python-v0.4 (wss, noise, yamux) | go-v0.41 | python-v0.4 | wss | noise | yamux | ✅ | 5s | 28.614 | 5.602 |
| go-v0.41 x python-v0.4 (quic-v1) | go-v0.41 | python-v0.4 | quic-v1 | - | - | ✅ | 5s | 84.541 | 17.8 |
| go-v0.41 x nim-v1.14 (tcp, noise, yamux) | go-v0.41 | nim-v1.14 | tcp | noise | yamux | ✅ | 5s | 180.564 | 54.984 |
| go-v0.41 x nim-v1.14 (ws, noise, yamux) | go-v0.41 | nim-v1.14 | ws | noise | yamux | ✅ | 5s | 243.294 | 43.607 |
| go-v0.41 x js-v1.x (tcp, noise, yamux) | go-v0.41 | js-v1.x | tcp | noise | yamux | ✅ | 20s | 132.807 | 13.545 |
| go-v0.41 x js-v1.x (ws, noise, yamux) | go-v0.41 | js-v1.x | ws | noise | yamux | ✅ | 21s | 207.022 | 23.582 |
| go-v0.41 x js-v2.x (tcp, noise, yamux) | go-v0.41 | js-v2.x | tcp | noise | yamux | ✅ | 21s | 147.071 | 20.126 |
| go-v0.41 x jvm-v1.2 (tcp, tls, yamux) | go-v0.41 | jvm-v1.2 | tcp | tls | yamux | ✅ | 13s | 3620.502 | 34.967 |
| go-v0.41 x jvm-v1.2 (tcp, noise, yamux) | go-v0.41 | jvm-v1.2 | tcp | noise | yamux | ✅ | 12s | 1377.752 | 17.401 |
| go-v0.41 x js-v3.x (tcp, noise, yamux) | go-v0.41 | js-v3.x | tcp | noise | yamux | ✅ | 21s | 116.735 | 9.973 |
| go-v0.41 x js-v2.x (ws, noise, yamux) | go-v0.41 | js-v2.x | ws | noise | yamux | ✅ | 23s | 154.28 | 28.759 |
| go-v0.41 x js-v3.x (ws, noise, yamux) | go-v0.41 | js-v3.x | ws | noise | yamux | ✅ | 22s | 219.154 | 16.282 |
| go-v0.41 x c-v0.0.1 (tcp, noise, yamux) | go-v0.41 | c-v0.0.1 | tcp | noise | yamux | ✅ | 6s | 126.373 | 55.893 |
| go-v0.41 x c-v0.0.1 (quic-v1) | go-v0.41 | c-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 68.885 | 43.773 |
| go-v0.41 x jvm-v1.2 (ws, noise, yamux) | go-v0.41 | jvm-v1.2 | ws | noise | yamux | ✅ | 9s | 1892.39 | 42.77 |
| go-v0.41 x dotnet-v1.0 (tcp, noise, yamux) | go-v0.41 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 6s | 503.59 | 51.496 |
| go-v0.41 x zig-v0.0.1 (quic-v1) | go-v0.41 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 6s | - | - |
| go-v0.41 x eth-p2p-z-v0.0.1 (quic-v1) | go-v0.41 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 11.298 | 0.205 |
| go-v0.41 x jvm-v1.2 (ws, tls, yamux) | go-v0.41 | jvm-v1.2 | ws | tls | yamux | ✅ | 12s | 3846.604 | 11.299 |
| go-v0.41 x jvm-v1.2 (quic-v1) | go-v0.41 | jvm-v1.2 | quic-v1 | - | - | ✅ | 11s | 607.957 | 9.341 |
| go-v0.42 x rust-v0.53 (tcp, tls, yamux) | go-v0.42 | rust-v0.53 | tcp | tls | yamux | ✅ | 4s | 94.439 | 43.748 |
| go-v0.42 x rust-v0.53 (tcp, noise, yamux) | go-v0.42 | rust-v0.53 | tcp | noise | yamux | ✅ | 5s | 93.903 | 41.775 |
| go-v0.42 x rust-v0.53 (ws, tls, yamux) | go-v0.42 | rust-v0.53 | ws | tls | yamux | ✅ | 5s | 177.645 | 42.618 |
| go-v0.42 x rust-v0.53 (ws, noise, yamux) | go-v0.42 | rust-v0.53 | ws | noise | yamux | ✅ | 4s | 310.752 | 51.08 |
| go-v0.42 x rust-v0.53 (quic-v1) | go-v0.42 | rust-v0.53 | quic-v1 | - | - | ✅ | 5s | 8.295 | 0.345 |
| go-v0.42 x rust-v0.53 (webrtc-direct) | go-v0.42 | rust-v0.53 | webrtc-direct | - | - | ✅ | 5s | 422.744 | 5.61 |
| go-v0.42 x rust-v0.54 (tcp, tls, yamux) | go-v0.42 | rust-v0.54 | tcp | tls | yamux | ✅ | 6s | 87.832 | 41.515 |
| go-v0.42 x rust-v0.54 (tcp, noise, yamux) | go-v0.42 | rust-v0.54 | tcp | noise | yamux | ✅ | 5s | 94.238 | 45.766 |
| go-v0.42 x rust-v0.54 (ws, tls, yamux) | go-v0.42 | rust-v0.54 | ws | tls | yamux | ✅ | 6s | 224.505 | 43.768 |
| go-v0.42 x rust-v0.54 (ws, noise, yamux) | go-v0.42 | rust-v0.54 | ws | noise | yamux | ✅ | 4s | 182.601 | 43.028 |
| go-v0.42 x rust-v0.54 (quic-v1) | go-v0.42 | rust-v0.54 | quic-v1 | - | - | ✅ | 5s | 8.876 | 0.89 |
| go-v0.42 x rust-v0.54 (webrtc-direct) | go-v0.42 | rust-v0.54 | webrtc-direct | - | - | ✅ | 5s | 422.156 | 0.556 |
| go-v0.42 x rust-v0.55 (tcp, tls, yamux) | go-v0.42 | rust-v0.55 | tcp | tls | yamux | ✅ | 4s | 9.009 | 0.523 |
| go-v0.42 x rust-v0.55 (tcp, noise, yamux) | go-v0.42 | rust-v0.55 | tcp | noise | yamux | ✅ | 5s | 78.693 | 0.243 |
| go-v0.42 x rust-v0.55 (ws, tls, yamux) | go-v0.42 | rust-v0.55 | ws | tls | yamux | ✅ | 5s | 9.516 | 1.437 |
| go-v0.42 x rust-v0.55 (ws, noise, yamux) | go-v0.42 | rust-v0.55 | ws | noise | yamux | ✅ | 5s | 10.362 | 1.214 |
| go-v0.42 x rust-v0.55 (quic-v1) | go-v0.42 | rust-v0.55 | quic-v1 | - | - | ✅ | 5s | 6.311 | 0.161 |
| go-v0.42 x rust-v0.55 (webrtc-direct) | go-v0.42 | rust-v0.55 | webrtc-direct | - | - | ✅ | 5s | 210.503 | 0.5 |
| go-v0.42 x rust-v0.56 (tcp, tls, yamux) | go-v0.42 | rust-v0.56 | tcp | tls | yamux | ✅ | 5s | 8.867 | 0.454 |
| go-v0.42 x rust-v0.56 (tcp, noise, yamux) | go-v0.42 | rust-v0.56 | tcp | noise | yamux | ✅ | 5s | 5.934 | 0.696 |
| go-v0.42 x rust-v0.56 (ws, tls, yamux) | go-v0.42 | rust-v0.56 | ws | tls | yamux | ✅ | 5s | 7.984 | 0.419 |
| go-v0.42 x rust-v0.56 (ws, noise, yamux) | go-v0.42 | rust-v0.56 | ws | noise | yamux | ✅ | 5s | 3.675 | 0.152 |
| go-v0.42 x rust-v0.56 (quic-v1) | go-v0.42 | rust-v0.56 | quic-v1 | - | - | ✅ | 4s | 13.193 | 1.272 |
| go-v0.42 x go-v0.38 (tcp, tls, yamux) | go-v0.42 | go-v0.38 | tcp | tls | yamux | ✅ | 4s | 12.841 | 1.145 |
| go-v0.42 x go-v0.38 (tcp, noise, yamux) | go-v0.42 | go-v0.38 | tcp | noise | yamux | ✅ | 5s | 6.216 | 0.289 |
| go-v0.42 x go-v0.38 (ws, tls, yamux) | go-v0.42 | go-v0.38 | ws | tls | yamux | ✅ | 4s | 8.007 | 0.299 |
| go-v0.42 x go-v0.38 (ws, noise, yamux) | go-v0.42 | go-v0.38 | ws | noise | yamux | ✅ | 4s | 6.857 | 1.316 |
| go-v0.42 x go-v0.38 (wss, tls, yamux) | go-v0.42 | go-v0.38 | wss | tls | yamux | ✅ | 5s | 14.337 | 0.673 |
| go-v0.42 x go-v0.38 (wss, noise, yamux) | go-v0.42 | go-v0.38 | wss | noise | yamux | ✅ | 5s | 14.282 | 0.495 |
| go-v0.42 x go-v0.38 (quic-v1) | go-v0.42 | go-v0.38 | quic-v1 | - | - | ✅ | 4s | 9.503 | 0.364 |
| go-v0.42 x go-v0.38 (webtransport) | go-v0.42 | go-v0.38 | webtransport | - | - | ✅ | 4s | 15.021 | 0.883 |
| go-v0.42 x rust-v0.56 (webrtc-direct) | go-v0.42 | rust-v0.56 | webrtc-direct | - | - | ❌ | 10s | - | - |
| go-v0.42 x go-v0.38 (webrtc-direct) | go-v0.42 | go-v0.38 | webrtc-direct | - | - | ✅ | 5s | 223.243 | 0.609 |
| go-v0.42 x go-v0.39 (tcp, tls, yamux) | go-v0.42 | go-v0.39 | tcp | tls | yamux | ✅ | 5s | 6.052 | 0.314 |
| go-v0.42 x go-v0.39 (tcp, noise, yamux) | go-v0.42 | go-v0.39 | tcp | noise | yamux | ✅ | 5s | 14.087 | 2.598 |
| go-v0.42 x go-v0.39 (ws, tls, yamux) | go-v0.42 | go-v0.39 | ws | tls | yamux | ✅ | 4s | 6.025 | 0.268 |
| go-v0.42 x go-v0.39 (ws, noise, yamux) | go-v0.42 | go-v0.39 | ws | noise | yamux | ✅ | 4s | 12.19 | 0.6 |
| go-v0.42 x go-v0.39 (wss, tls, yamux) | go-v0.42 | go-v0.39 | wss | tls | yamux | ✅ | 5s | 13.815 | 0.44 |
| go-v0.42 x go-v0.39 (quic-v1) | go-v0.42 | go-v0.39 | quic-v1 | - | - | ✅ | 4s | 11.024 | 0.432 |
| go-v0.42 x go-v0.39 (wss, noise, yamux) | go-v0.42 | go-v0.39 | wss | noise | yamux | ✅ | 6s | 12.115 | 0.674 |
| go-v0.42 x go-v0.39 (webtransport) | go-v0.42 | go-v0.39 | webtransport | - | - | ✅ | 5s | 16.291 | 3.107 |
| go-v0.42 x go-v0.39 (webrtc-direct) | go-v0.42 | go-v0.39 | webrtc-direct | - | - | ✅ | 5s | 226.029 | 1.337 |
| go-v0.42 x go-v0.40 (tcp, tls, yamux) | go-v0.42 | go-v0.40 | tcp | tls | yamux | ✅ | 4s | 5.14 | 0.837 |
| go-v0.42 x go-v0.40 (tcp, noise, yamux) | go-v0.42 | go-v0.40 | tcp | noise | yamux | ✅ | 4s | 9.078 | 0.65 |
| go-v0.42 x go-v0.40 (ws, tls, yamux) | go-v0.42 | go-v0.40 | ws | tls | yamux | ✅ | 5s | 11.84 | 0.86 |
| go-v0.42 x go-v0.40 (ws, noise, yamux) | go-v0.42 | go-v0.40 | ws | noise | yamux | ✅ | 5s | 12.153 | 2.93 |
| go-v0.42 x go-v0.40 (wss, tls, yamux) | go-v0.42 | go-v0.40 | wss | tls | yamux | ✅ | 5s | 20.068 | 0.726 |
| go-v0.42 x go-v0.40 (quic-v1) | go-v0.42 | go-v0.40 | quic-v1 | - | - | ✅ | 4s | 16.377 | 1.152 |
| go-v0.42 x go-v0.40 (webtransport) | go-v0.42 | go-v0.40 | webtransport | - | - | ✅ | 5s | 18.504 | 1.075 |
| go-v0.42 x go-v0.40 (wss, noise, yamux) | go-v0.42 | go-v0.40 | wss | noise | yamux | ✅ | 6s | 87.005 | 0.647 |
| go-v0.42 x go-v0.40 (webrtc-direct) | go-v0.42 | go-v0.40 | webrtc-direct | - | - | ✅ | 5s | 214.63 | 0.666 |
| go-v0.42 x go-v0.41 (tcp, tls, yamux) | go-v0.42 | go-v0.41 | tcp | tls | yamux | ✅ | 5s | 84.726 | 1.09 |
| go-v0.42 x go-v0.41 (tcp, noise, yamux) | go-v0.42 | go-v0.41 | tcp | noise | yamux | ✅ | 5s | 10.444 | 1.447 |
| go-v0.42 x go-v0.41 (ws, tls, yamux) | go-v0.42 | go-v0.41 | ws | tls | yamux | ✅ | 5s | 11.477 | 2.885 |
| go-v0.42 x go-v0.41 (ws, noise, yamux) | go-v0.42 | go-v0.41 | ws | noise | yamux | ✅ | 5s | 12.496 | 1.038 |
| go-v0.42 x go-v0.41 (wss, tls, yamux) | go-v0.42 | go-v0.41 | wss | tls | yamux | ✅ | 4s | 22.585 | 2.772 |
| go-v0.42 x go-v0.41 (quic-v1) | go-v0.42 | go-v0.41 | quic-v1 | - | - | ✅ | 4s | 9.79 | 0.549 |
| go-v0.42 x go-v0.41 (wss, noise, yamux) | go-v0.42 | go-v0.41 | wss | noise | yamux | ✅ | 6s | 21.345 | 0.43 |
| go-v0.42 x go-v0.41 (webtransport) | go-v0.42 | go-v0.41 | webtransport | - | - | ✅ | 5s | 15.677 | 0.399 |
| go-v0.42 x go-v0.41 (webrtc-direct) | go-v0.42 | go-v0.41 | webrtc-direct | - | - | ✅ | 4s | 14.511 | 0.321 |
| go-v0.42 x go-v0.42 (tcp, tls, yamux) | go-v0.42 | go-v0.42 | tcp | tls | yamux | ✅ | 4s | 8.771 | 0.319 |
| go-v0.42 x go-v0.42 (tcp, noise, yamux) | go-v0.42 | go-v0.42 | tcp | noise | yamux | ✅ | 4s | 16.328 | 1.465 |
| go-v0.42 x go-v0.42 (ws, tls, yamux) | go-v0.42 | go-v0.42 | ws | tls | yamux | ✅ | 5s | 16.274 | 2.391 |
| go-v0.42 x go-v0.42 (ws, noise, yamux) | go-v0.42 | go-v0.42 | ws | noise | yamux | ✅ | 5s | 10.712 | 0.56 |
| go-v0.42 x go-v0.42 (wss, tls, yamux) | go-v0.42 | go-v0.42 | wss | tls | yamux | ✅ | 4s | 30.302 | 0.702 |
| go-v0.42 x go-v0.42 (wss, noise, yamux) | go-v0.42 | go-v0.42 | wss | noise | yamux | ✅ | 5s | 11.872 | 0.358 |
| go-v0.42 x go-v0.42 (quic-v1) | go-v0.42 | go-v0.42 | quic-v1 | - | - | ✅ | 5s | 9.622 | 0.385 |
| go-v0.42 x go-v0.42 (webtransport) | go-v0.42 | go-v0.42 | webtransport | - | - | ✅ | 4s | 11.337 | 0.408 |
| go-v0.42 x go-v0.42 (webrtc-direct) | go-v0.42 | go-v0.42 | webrtc-direct | - | - | ✅ | 5s | 211.4 | 0.325 |
| go-v0.42 x go-v0.43 (tcp, tls, yamux) | go-v0.42 | go-v0.43 | tcp | tls | yamux | ✅ | 5s | 9.413 | 0.585 |
| go-v0.42 x go-v0.43 (tcp, noise, yamux) | go-v0.42 | go-v0.43 | tcp | noise | yamux | ✅ | 4s | 9.375 | 0.679 |
| go-v0.42 x go-v0.43 (ws, tls, yamux) | go-v0.42 | go-v0.43 | ws | tls | yamux | ✅ | 5s | 7.565 | 0.931 |
| go-v0.42 x go-v0.43 (ws, noise, yamux) | go-v0.42 | go-v0.43 | ws | noise | yamux | ✅ | 4s | 13.008 | 0.532 |
| go-v0.42 x go-v0.43 (wss, tls, yamux) | go-v0.42 | go-v0.43 | wss | tls | yamux | ✅ | 6s | 15.12 | 0.416 |
| go-v0.42 x go-v0.43 (quic-v1) | go-v0.42 | go-v0.43 | quic-v1 | - | - | ✅ | 4s | 8.94 | 0.66 |
| go-v0.42 x go-v0.43 (wss, noise, yamux) | go-v0.42 | go-v0.43 | wss | noise | yamux | ✅ | 6s | 18.894 | 0.463 |
| go-v0.42 x go-v0.43 (webtransport) | go-v0.42 | go-v0.43 | webtransport | - | - | ✅ | 5s | 16.744 | 0.438 |
| go-v0.42 x go-v0.43 (webrtc-direct) | go-v0.42 | go-v0.43 | webrtc-direct | - | - | ✅ | 5s | 21.112 | 0.756 |
| go-v0.42 x go-v0.44 (tcp, tls, yamux) | go-v0.42 | go-v0.44 | tcp | tls | yamux | ✅ | 5s | 10.092 | 0.399 |
| go-v0.42 x go-v0.44 (ws, tls, yamux) | go-v0.42 | go-v0.44 | ws | tls | yamux | ✅ | 4s | 8.333 | 0.982 |
| go-v0.42 x go-v0.44 (tcp, noise, yamux) | go-v0.42 | go-v0.44 | tcp | noise | yamux | ✅ | 5s | 6.642 | 0.845 |
| go-v0.42 x go-v0.44 (ws, noise, yamux) | go-v0.42 | go-v0.44 | ws | noise | yamux | ✅ | 5s | 9.879 | 0.789 |
| go-v0.42 x go-v0.44 (wss, tls, yamux) | go-v0.42 | go-v0.44 | wss | tls | yamux | ✅ | 5s | 16.704 | 0.902 |
| go-v0.42 x go-v0.44 (quic-v1) | go-v0.42 | go-v0.44 | quic-v1 | - | - | ✅ | 4s | 16.177 | 0.45 |
| go-v0.42 x go-v0.44 (wss, noise, yamux) | go-v0.42 | go-v0.44 | wss | noise | yamux | ✅ | 6s | 30.636 | 1.208 |
| go-v0.42 x go-v0.44 (webtransport) | go-v0.42 | go-v0.44 | webtransport | - | - | ✅ | 5s | 11.257 | 0.483 |
| go-v0.42 x go-v0.44 (webrtc-direct) | go-v0.42 | go-v0.44 | webrtc-direct | - | - | ✅ | 5s | 213.216 | 0.412 |
| go-v0.42 x go-v0.45 (tcp, tls, yamux) | go-v0.42 | go-v0.45 | tcp | tls | yamux | ✅ | 5s | 8.86 | 1.832 |
| go-v0.42 x go-v0.45 (tcp, noise, yamux) | go-v0.42 | go-v0.45 | tcp | noise | yamux | ✅ | 5s | 10.97 | 0.761 |
| go-v0.42 x go-v0.45 (ws, tls, yamux) | go-v0.42 | go-v0.45 | ws | tls | yamux | ✅ | 5s | 10.351 | 0.341 |
| go-v0.42 x go-v0.45 (ws, noise, yamux) | go-v0.42 | go-v0.45 | ws | noise | yamux | ✅ | 4s | 12.834 | 0.444 |
| go-v0.42 x go-v0.45 (wss, tls, yamux) | go-v0.42 | go-v0.45 | wss | tls | yamux | ✅ | 4s | 12.464 | 0.43 |
| go-v0.42 x go-v0.45 (wss, noise, yamux) | go-v0.42 | go-v0.45 | wss | noise | yamux | ✅ | 4s | 44.02 | 1.013 |
| go-v0.42 x go-v0.45 (quic-v1) | go-v0.42 | go-v0.45 | quic-v1 | - | - | ✅ | 5s | 13.769 | 0.572 |
| go-v0.42 x go-v0.45 (webtransport) | go-v0.42 | go-v0.45 | webtransport | - | - | ✅ | 5s | 10.383 | 0.471 |
| go-v0.42 x go-v0.45 (webrtc-direct) | go-v0.42 | go-v0.45 | webrtc-direct | - | - | ✅ | 5s | 213.022 | 0.38 |
| go-v0.42 x python-v0.4 (tcp, noise, yamux) | go-v0.42 | python-v0.4 | tcp | noise | yamux | ✅ | 6s | 50.293 | 4.957 |
| go-v0.42 x python-v0.4 (ws, noise, yamux) | go-v0.42 | python-v0.4 | ws | noise | yamux | ✅ | 5s | 25.167 | 3.416 |
| go-v0.42 x python-v0.4 (wss, noise, yamux) | go-v0.42 | python-v0.4 | wss | noise | yamux | ✅ | 5s | 31.355 | 5.511 |
| go-v0.42 x python-v0.4 (quic-v1) | go-v0.42 | python-v0.4 | quic-v1 | - | - | ✅ | 5s | 83.799 | 14.694 |
| go-v0.42 x nim-v1.14 (tcp, noise, yamux) | go-v0.42 | nim-v1.14 | tcp | noise | yamux | ✅ | 5s | 209.872 | 42.894 |
| go-v0.42 x nim-v1.14 (ws, noise, yamux) | go-v0.42 | nim-v1.14 | ws | noise | yamux | ✅ | 6s | 261.598 | 47.102 |
| go-v0.42 x js-v1.x (tcp, noise, yamux) | go-v0.42 | js-v1.x | tcp | noise | yamux | ✅ | 19s | 185.056 | 37.235 |
| go-v0.42 x js-v1.x (ws, noise, yamux) | go-v0.42 | js-v1.x | ws | noise | yamux | ✅ | 19s | 201.769 | 29.745 |
| go-v0.42 x js-v2.x (ws, noise, yamux) | go-v0.42 | js-v2.x | ws | noise | yamux | ✅ | 21s | 235.472 | 52.846 |
| go-v0.42 x jvm-v1.2 (tcp, noise, yamux) | go-v0.42 | jvm-v1.2 | tcp | noise | yamux | ✅ | 11s | 1170.54 | 29.957 |
| go-v0.42 x js-v2.x (tcp, noise, yamux) | go-v0.42 | js-v2.x | tcp | noise | yamux | ✅ | 22s | 197.8 | 26.929 |
| go-v0.42 x js-v3.x (tcp, noise, yamux) | go-v0.42 | js-v3.x | tcp | noise | yamux | ✅ | 22s | 144.096 | 9.64 |
| go-v0.42 x jvm-v1.2 (tcp, tls, yamux) | go-v0.42 | jvm-v1.2 | tcp | tls | yamux | ✅ | 14s | 3231.475 | 16.395 |
| go-v0.42 x js-v3.x (ws, noise, yamux) | go-v0.42 | js-v3.x | ws | noise | yamux | ✅ | 22s | 65.873 | 14.882 |
| go-v0.42 x c-v0.0.1 (tcp, noise, yamux) | go-v0.42 | c-v0.0.1 | tcp | noise | yamux | ✅ | 6s | 120.478 | 56.179 |
| go-v0.42 x c-v0.0.1 (quic-v1) | go-v0.42 | c-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 80.072 | 36.437 |
| go-v0.42 x jvm-v1.2 (ws, noise, yamux) | go-v0.42 | jvm-v1.2 | ws | noise | yamux | ✅ | 10s | 1442.771 | 101.7 |
| go-v0.42 x zig-v0.0.1 (quic-v1) | go-v0.42 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 5s | - | - |
| go-v0.42 x jvm-v1.2 (ws, tls, yamux) | go-v0.42 | jvm-v1.2 | ws | tls | yamux | ✅ | 12s | 3256.611 | 8.537 |
| go-v0.42 x dotnet-v1.0 (tcp, noise, yamux) | go-v0.42 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 7s | 461.609 | 46.598 |
| go-v0.42 x eth-p2p-z-v0.0.1 (quic-v1) | go-v0.42 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 12.791 | 0.196 |
| go-v0.42 x jvm-v1.2 (quic-v1) | go-v0.42 | jvm-v1.2 | quic-v1 | - | - | ✅ | 10s | 477.188 | 8.879 |
| go-v0.43 x rust-v0.53 (tcp, tls, yamux) | go-v0.43 | rust-v0.53 | tcp | tls | yamux | ✅ | 4s | 94.392 | 41.378 |
| go-v0.43 x rust-v0.53 (tcp, noise, yamux) | go-v0.43 | rust-v0.53 | tcp | noise | yamux | ✅ | 4s | 102.866 | 47.844 |
| go-v0.43 x rust-v0.53 (quic-v1) | go-v0.43 | rust-v0.53 | quic-v1 | - | - | ✅ | 4s | 12.033 | 0.408 |
| go-v0.43 x rust-v0.53 (ws, tls, yamux) | go-v0.43 | rust-v0.53 | ws | tls | yamux | ✅ | 5s | 180.187 | 0.952 |
| go-v0.43 x rust-v0.53 (ws, noise, yamux) | go-v0.43 | rust-v0.53 | ws | noise | yamux | ✅ | 5s | 180.122 | 44.699 |
| go-v0.43 x rust-v0.54 (tcp, tls, yamux) | go-v0.43 | rust-v0.54 | tcp | tls | yamux | ✅ | 5s | 91.601 | 42.091 |
| go-v0.43 x rust-v0.53 (webrtc-direct) | go-v0.43 | rust-v0.53 | webrtc-direct | - | - | ✅ | 5s | 409.64 | 0.323 |
| go-v0.43 x rust-v0.54 (tcp, noise, yamux) | go-v0.43 | rust-v0.54 | tcp | noise | yamux | ✅ | 5s | 103.026 | 44.771 |
| go-v0.43 x rust-v0.54 (ws, noise, yamux) | go-v0.43 | rust-v0.54 | ws | noise | yamux | ✅ | 5s | 231.567 | 43.753 |
| go-v0.43 x rust-v0.54 (ws, tls, yamux) | go-v0.43 | rust-v0.54 | ws | tls | yamux | ✅ | 5s | 227.324 | 47.576 |
| go-v0.43 x rust-v0.54 (quic-v1) | go-v0.43 | rust-v0.54 | quic-v1 | - | - | ✅ | 4s | 7.149 | 0.34 |
| go-v0.43 x rust-v0.54 (webrtc-direct) | go-v0.43 | rust-v0.54 | webrtc-direct | - | - | ✅ | 6s | 423.627 | 1.433 |
| go-v0.43 x rust-v0.55 (tcp, tls, yamux) | go-v0.43 | rust-v0.55 | tcp | tls | yamux | ✅ | 5s | 12.725 | 0.499 |
| go-v0.43 x rust-v0.55 (ws, tls, yamux) | go-v0.43 | rust-v0.55 | ws | tls | yamux | ✅ | 5s | 14.473 | 1.155 |
| go-v0.43 x rust-v0.55 (tcp, noise, yamux) | go-v0.43 | rust-v0.55 | tcp | noise | yamux | ✅ | 6s | 48.321 | 0.292 |
| go-v0.43 x rust-v0.55 (ws, noise, yamux) | go-v0.43 | rust-v0.55 | ws | noise | yamux | ✅ | 5s | 3.57 | 0.503 |
| go-v0.43 x rust-v0.55 (quic-v1) | go-v0.43 | rust-v0.55 | quic-v1 | - | - | ✅ | 5s | 7.605 | 0.456 |
| go-v0.43 x rust-v0.55 (webrtc-direct) | go-v0.43 | rust-v0.55 | webrtc-direct | - | - | ✅ | 5s | 414.147 | 0.608 |
| go-v0.43 x rust-v0.56 (tcp, tls, yamux) | go-v0.43 | rust-v0.56 | tcp | tls | yamux | ✅ | 5s | 7.662 | 0.209 |
| go-v0.43 x rust-v0.56 (tcp, noise, yamux) | go-v0.43 | rust-v0.56 | tcp | noise | yamux | ✅ | 4s | 7.293 | 0.157 |
| go-v0.43 x rust-v0.56 (ws, tls, yamux) | go-v0.43 | rust-v0.56 | ws | tls | yamux | ✅ | 4s | 12.225 | 0.464 |
| go-v0.43 x rust-v0.56 (ws, noise, yamux) | go-v0.43 | rust-v0.56 | ws | noise | yamux | ✅ | 5s | 6.78 | 0.549 |
| go-v0.43 x rust-v0.56 (quic-v1) | go-v0.43 | rust-v0.56 | quic-v1 | - | - | ✅ | 5s | 6.13 | 0.353 |
| go-v0.43 x go-v0.38 (tcp, tls, yamux) | go-v0.43 | go-v0.38 | tcp | tls | yamux | ✅ | 5s | 9.113 | 1.096 |
| go-v0.43 x go-v0.38 (tcp, noise, yamux) | go-v0.43 | go-v0.38 | tcp | noise | yamux | ✅ | 5s | 18.538 | 3.28 |
| go-v0.43 x go-v0.38 (ws, tls, yamux) | go-v0.43 | go-v0.38 | ws | tls | yamux | ✅ | 4s | 8.399 | 0.527 |
| go-v0.43 x go-v0.38 (ws, noise, yamux) | go-v0.43 | go-v0.38 | ws | noise | yamux | ✅ | 4s | 10.57 | 0.849 |
| go-v0.43 x go-v0.38 (quic-v1) | go-v0.43 | go-v0.38 | quic-v1 | - | - | ✅ | 4s | 12.7 | 1.641 |
| go-v0.43 x go-v0.38 (wss, tls, yamux) | go-v0.43 | go-v0.38 | wss | tls | yamux | ✅ | 6s | 21.773 | 0.957 |
| go-v0.43 x go-v0.38 (webtransport) | go-v0.43 | go-v0.38 | webtransport | - | - | ✅ | 5s | 16.539 | 0.574 |
| go-v0.43 x go-v0.38 (wss, noise, yamux) | go-v0.43 | go-v0.38 | wss | noise | yamux | ✅ | 6s | 7.621 | 0.228 |
| go-v0.43 x rust-v0.56 (webrtc-direct) | go-v0.43 | rust-v0.56 | webrtc-direct | - | - | ❌ | 10s | - | - |
| go-v0.43 x go-v0.38 (webrtc-direct) | go-v0.43 | go-v0.38 | webrtc-direct | - | - | ✅ | 5s | 14.506 | 0.648 |
| go-v0.43 x go-v0.39 (tcp, tls, yamux) | go-v0.43 | go-v0.39 | tcp | tls | yamux | ✅ | 5s | 7.828 | 1.118 |
| go-v0.43 x go-v0.39 (tcp, noise, yamux) | go-v0.43 | go-v0.39 | tcp | noise | yamux | ✅ | 4s | 7.687 | 1.132 |
| go-v0.43 x go-v0.39 (ws, tls, yamux) | go-v0.43 | go-v0.39 | ws | tls | yamux | ✅ | 5s | 21.01 | 2.119 |
| go-v0.43 x go-v0.39 (ws, noise, yamux) | go-v0.43 | go-v0.39 | ws | noise | yamux | ✅ | 5s | 9.624 | 0.696 |
| go-v0.43 x go-v0.39 (wss, tls, yamux) | go-v0.43 | go-v0.39 | wss | tls | yamux | ✅ | 5s | 18.83 | 0.947 |
| go-v0.43 x go-v0.39 (quic-v1) | go-v0.43 | go-v0.39 | quic-v1 | - | - | ✅ | 5s | 7.545 | 0.287 |
| go-v0.43 x go-v0.39 (wss, noise, yamux) | go-v0.43 | go-v0.39 | wss | noise | yamux | ✅ | 6s | 7.67 | 0.339 |
| go-v0.43 x go-v0.39 (webtransport) | go-v0.43 | go-v0.39 | webtransport | - | - | ✅ | 4s | 9.198 | 0.354 |
| go-v0.43 x go-v0.39 (webrtc-direct) | go-v0.43 | go-v0.39 | webrtc-direct | - | - | ✅ | 4s | 213.602 | 0.926 |
| go-v0.43 x go-v0.40 (tcp, tls, yamux) | go-v0.43 | go-v0.40 | tcp | tls | yamux | ✅ | 5s | 10.263 | 0.814 |
| go-v0.43 x go-v0.40 (tcp, noise, yamux) | go-v0.43 | go-v0.40 | tcp | noise | yamux | ✅ | 5s | 7.346 | 2.1 |
| go-v0.43 x go-v0.40 (ws, tls, yamux) | go-v0.43 | go-v0.40 | ws | tls | yamux | ✅ | 5s | 10.318 | 0.287 |
| go-v0.43 x go-v0.40 (ws, noise, yamux) | go-v0.43 | go-v0.40 | ws | noise | yamux | ✅ | 4s | 8.65 | 1.364 |
| go-v0.43 x go-v0.40 (wss, tls, yamux) | go-v0.43 | go-v0.40 | wss | tls | yamux | ✅ | 5s | 8.861 | 0.208 |
| go-v0.43 x go-v0.40 (wss, noise, yamux) | go-v0.43 | go-v0.40 | wss | noise | yamux | ✅ | 5s | 16.197 | 0.358 |
| go-v0.43 x go-v0.40 (quic-v1) | go-v0.43 | go-v0.40 | quic-v1 | - | - | ✅ | 5s | 22.373 | 4.728 |
| go-v0.43 x go-v0.40 (webtransport) | go-v0.43 | go-v0.40 | webtransport | - | - | ✅ | 5s | 10.362 | 0.572 |
| go-v0.43 x go-v0.40 (webrtc-direct) | go-v0.43 | go-v0.40 | webrtc-direct | - | - | ✅ | 5s | 223.852 | 1.154 |
| go-v0.43 x go-v0.41 (tcp, tls, yamux) | go-v0.43 | go-v0.41 | tcp | tls | yamux | ✅ | 5s | 41.915 | 1.585 |
| go-v0.43 x go-v0.41 (tcp, noise, yamux) | go-v0.43 | go-v0.41 | tcp | noise | yamux | ✅ | 5s | 9.2 | 0.401 |
| go-v0.43 x go-v0.41 (ws, tls, yamux) | go-v0.43 | go-v0.41 | ws | tls | yamux | ✅ | 5s | 53.282 | 1.083 |
| go-v0.43 x go-v0.41 (ws, noise, yamux) | go-v0.43 | go-v0.41 | ws | noise | yamux | ✅ | 5s | 5.162 | 0.342 |
| go-v0.43 x go-v0.41 (wss, tls, yamux) | go-v0.43 | go-v0.41 | wss | tls | yamux | ✅ | 6s | 20.893 | 0.44 |
| go-v0.43 x go-v0.41 (wss, noise, yamux) | go-v0.43 | go-v0.41 | wss | noise | yamux | ✅ | 5s | 19.26 | 0.777 |
| go-v0.43 x go-v0.41 (quic-v1) | go-v0.43 | go-v0.41 | quic-v1 | - | - | ✅ | 6s | 18.161 | 0.772 |
| go-v0.43 x go-v0.41 (webtransport) | go-v0.43 | go-v0.41 | webtransport | - | - | ✅ | 5s | 14.41 | 0.532 |
| go-v0.43 x go-v0.41 (webrtc-direct) | go-v0.43 | go-v0.41 | webrtc-direct | - | - | ✅ | 5s | 212.443 | 0.464 |
| go-v0.43 x go-v0.42 (tcp, tls, yamux) | go-v0.43 | go-v0.42 | tcp | tls | yamux | ✅ | 5s | 21.356 | 0.331 |
| go-v0.43 x go-v0.42 (tcp, noise, yamux) | go-v0.43 | go-v0.42 | tcp | noise | yamux | ✅ | 4s | 10.926 | 1.308 |
| go-v0.43 x go-v0.42 (ws, tls, yamux) | go-v0.43 | go-v0.42 | ws | tls | yamux | ✅ | 5s | 8.958 | 0.732 |
| go-v0.43 x go-v0.42 (ws, noise, yamux) | go-v0.43 | go-v0.42 | ws | noise | yamux | ✅ | 5s | 18.889 | 0.616 |
| go-v0.43 x go-v0.42 (wss, noise, yamux) | go-v0.43 | go-v0.42 | wss | noise | yamux | ✅ | 5s | 24.784 | 1.531 |
| go-v0.43 x go-v0.42 (quic-v1) | go-v0.43 | go-v0.42 | quic-v1 | - | - | ✅ | 4s | 15.964 | 4.199 |
| go-v0.43 x go-v0.42 (wss, tls, yamux) | go-v0.43 | go-v0.42 | wss | tls | yamux | ✅ | 6s | 15.46 | 2.505 |
| go-v0.43 x go-v0.42 (webtransport) | go-v0.43 | go-v0.42 | webtransport | - | - | ✅ | 5s | 21.854 | 1.012 |
| go-v0.43 x go-v0.42 (webrtc-direct) | go-v0.43 | go-v0.42 | webrtc-direct | - | - | ✅ | 4s | 217.381 | 1.434 |
| go-v0.43 x go-v0.43 (tcp, tls, yamux) | go-v0.43 | go-v0.43 | tcp | tls | yamux | ✅ | 4s | 5.723 | 0.445 |
| go-v0.43 x go-v0.43 (tcp, noise, yamux) | go-v0.43 | go-v0.43 | tcp | noise | yamux | ✅ | 4s | 6.012 | 0.276 |
| go-v0.43 x go-v0.43 (ws, tls, yamux) | go-v0.43 | go-v0.43 | ws | tls | yamux | ✅ | 4s | 11.665 | 2.11 |
| go-v0.43 x go-v0.43 (ws, noise, yamux) | go-v0.43 | go-v0.43 | ws | noise | yamux | ✅ | 5s | 18.064 | 1.031 |
| go-v0.43 x go-v0.43 (wss, tls, yamux) | go-v0.43 | go-v0.43 | wss | tls | yamux | ✅ | 5s | 15.049 | 0.385 |
| go-v0.43 x go-v0.43 (wss, noise, yamux) | go-v0.43 | go-v0.43 | wss | noise | yamux | ✅ | 5s | 7.225 | 0.174 |
| go-v0.43 x go-v0.43 (quic-v1) | go-v0.43 | go-v0.43 | quic-v1 | - | - | ✅ | 5s | 11.828 | 0.301 |
| go-v0.43 x go-v0.43 (webtransport) | go-v0.43 | go-v0.43 | webtransport | - | - | ✅ | 4s | 74.957 | 0.421 |
| go-v0.43 x go-v0.43 (webrtc-direct) | go-v0.43 | go-v0.43 | webrtc-direct | - | - | ✅ | 5s | 225.337 | 3.604 |
| go-v0.43 x go-v0.44 (tcp, tls, yamux) | go-v0.43 | go-v0.44 | tcp | tls | yamux | ✅ | 5s | 7.676 | 0.658 |
| go-v0.43 x go-v0.44 (tcp, noise, yamux) | go-v0.43 | go-v0.44 | tcp | noise | yamux | ✅ | 4s | 7.474 | 0.506 |
| go-v0.43 x go-v0.44 (ws, tls, yamux) | go-v0.43 | go-v0.44 | ws | tls | yamux | ✅ | 4s | 8.907 | 0.368 |
| go-v0.43 x go-v0.44 (ws, noise, yamux) | go-v0.43 | go-v0.44 | ws | noise | yamux | ✅ | 5s | 5.945 | 0.524 |
| go-v0.43 x go-v0.44 (quic-v1) | go-v0.43 | go-v0.44 | quic-v1 | - | - | ✅ | 4s | 27.418 | 1.744 |
| go-v0.43 x go-v0.44 (wss, noise, yamux) | go-v0.43 | go-v0.44 | wss | noise | yamux | ✅ | 6s | 21.145 | 1.466 |
| go-v0.43 x go-v0.44 (wss, tls, yamux) | go-v0.43 | go-v0.44 | wss | tls | yamux | ✅ | 6s | 13.9 | 0.42 |
| go-v0.43 x go-v0.44 (webtransport) | go-v0.43 | go-v0.44 | webtransport | - | - | ✅ | 5s | 11.76 | 0.198 |
| go-v0.43 x go-v0.44 (webrtc-direct) | go-v0.43 | go-v0.44 | webrtc-direct | - | - | ✅ | 4s | 18.989 | 0.926 |
| go-v0.43 x go-v0.45 (tcp, tls, yamux) | go-v0.43 | go-v0.45 | tcp | tls | yamux | ✅ | 5s | 11.186 | 0.731 |
| go-v0.43 x go-v0.45 (tcp, noise, yamux) | go-v0.43 | go-v0.45 | tcp | noise | yamux | ✅ | 5s | 8.514 | 1.463 |
| go-v0.43 x go-v0.45 (ws, tls, yamux) | go-v0.43 | go-v0.45 | ws | tls | yamux | ✅ | 5s | 5.94 | 0.829 |
| go-v0.43 x go-v0.45 (ws, noise, yamux) | go-v0.43 | go-v0.45 | ws | noise | yamux | ✅ | 4s | 12.679 | 0.38 |
| go-v0.43 x go-v0.45 (quic-v1) | go-v0.43 | go-v0.45 | quic-v1 | - | - | ✅ | 5s | 27.94 | 9.642 |
| go-v0.43 x go-v0.45 (wss, tls, yamux) | go-v0.43 | go-v0.45 | wss | tls | yamux | ✅ | 6s | 32.758 | 1.276 |
| go-v0.43 x go-v0.45 (webtransport) | go-v0.43 | go-v0.45 | webtransport | - | - | ✅ | 5s | 30.045 | 1.485 |
| go-v0.43 x go-v0.45 (wss, noise, yamux) | go-v0.43 | go-v0.45 | wss | noise | yamux | ✅ | 6s | 20.95 | 1.794 |
| go-v0.43 x go-v0.45 (webrtc-direct) | go-v0.43 | go-v0.45 | webrtc-direct | - | - | ✅ | 5s | 211.916 | 0.671 |
| go-v0.43 x python-v0.4 (tcp, noise, yamux) | go-v0.43 | python-v0.4 | tcp | noise | yamux | ✅ | 5s | 27.605 | 2.784 |
| go-v0.43 x python-v0.4 (ws, noise, yamux) | go-v0.43 | python-v0.4 | ws | noise | yamux | ✅ | 5s | 31.385 | 5.756 |
| go-v0.43 x python-v0.4 (wss, noise, yamux) | go-v0.43 | python-v0.4 | wss | noise | yamux | ✅ | 5s | 27.803 | 4.103 |
| go-v0.43 x python-v0.4 (quic-v1) | go-v0.43 | python-v0.4 | quic-v1 | - | - | ✅ | 6s | 78.229 | 6.724 |
| go-v0.43 x nim-v1.14 (tcp, noise, yamux) | go-v0.43 | nim-v1.14 | tcp | noise | yamux | ✅ | 5s | 222.811 | 43.647 |
| go-v0.43 x nim-v1.14 (ws, noise, yamux) | go-v0.43 | nim-v1.14 | ws | noise | yamux | ✅ | 5s | 246.227 | 43.592 |
| go-v0.43 x js-v1.x (tcp, noise, yamux) | go-v0.43 | js-v1.x | tcp | noise | yamux | ✅ | 19s | 137.646 | 15.765 |
| go-v0.43 x js-v1.x (ws, noise, yamux) | go-v0.43 | js-v1.x | ws | noise | yamux | ✅ | 21s | 174.675 | 16.301 |
| go-v0.43 x js-v3.x (tcp, noise, yamux) | go-v0.43 | js-v3.x | tcp | noise | yamux | ✅ | 20s | 122.771 | 20.32 |
| go-v0.43 x js-v2.x (tcp, noise, yamux) | go-v0.43 | js-v2.x | tcp | noise | yamux | ✅ | 22s | 207.639 | 38.63 |
| go-v0.43 x js-v2.x (ws, noise, yamux) | go-v0.43 | js-v2.x | ws | noise | yamux | ✅ | 22s | 261.081 | 25.84 |
| go-v0.43 x jvm-v1.2 (tcp, noise, yamux) | go-v0.43 | jvm-v1.2 | tcp | noise | yamux | ✅ | 10s | 938.382 | 12.304 |
| go-v0.43 x jvm-v1.2 (tcp, tls, yamux) | go-v0.43 | jvm-v1.2 | tcp | tls | yamux | ✅ | 13s | 2951.826 | 14.83 |
| go-v0.43 x js-v3.x (ws, noise, yamux) | go-v0.43 | js-v3.x | ws | noise | yamux | ✅ | 22s | 138.276 | 19.902 |
| go-v0.43 x c-v0.0.1 (tcp, noise, yamux) | go-v0.43 | c-v0.0.1 | tcp | noise | yamux | ✅ | 5s | 124.149 | 51.259 |
| go-v0.43 x c-v0.0.1 (quic-v1) | go-v0.43 | c-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 20.434 | 0.913 |
| go-v0.43 x dotnet-v1.0 (tcp, noise, yamux) | go-v0.43 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 6s | 540.453 | 44.644 |
| go-v0.43 x zig-v0.0.1 (quic-v1) | go-v0.43 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 6s | - | - |
| go-v0.43 x jvm-v1.2 (ws, noise, yamux) | go-v0.43 | jvm-v1.2 | ws | noise | yamux | ✅ | 11s | 1439.654 | 68.242 |
| go-v0.43 x eth-p2p-z-v0.0.1 (quic-v1) | go-v0.43 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 7s | 20.338 | 0.859 |
| go-v0.43 x jvm-v1.2 (ws, tls, yamux) | go-v0.43 | jvm-v1.2 | ws | tls | yamux | ✅ | 12s | 3943.839 | 9.898 |
| go-v0.43 x jvm-v1.2 (quic-v1) | go-v0.43 | jvm-v1.2 | quic-v1 | - | - | ✅ | 11s | 448.884 | 8.909 |
| go-v0.44 x rust-v0.53 (tcp, tls, yamux) | go-v0.44 | rust-v0.53 | tcp | tls | yamux | ✅ | 5s | 99.176 | 46.065 |
| go-v0.44 x rust-v0.53 (tcp, noise, yamux) | go-v0.44 | rust-v0.53 | tcp | noise | yamux | ✅ | 4s | 133.768 | 43.644 |
| go-v0.44 x rust-v0.53 (ws, tls, yamux) | go-v0.44 | rust-v0.53 | ws | tls | yamux | ✅ | 5s | 228.803 | 43.776 |
| go-v0.44 x rust-v0.53 (quic-v1) | go-v0.44 | rust-v0.53 | quic-v1 | - | - | ✅ | 5s | 16.454 | 1.549 |
| go-v0.44 x rust-v0.53 (ws, noise, yamux) | go-v0.44 | rust-v0.53 | ws | noise | yamux | ✅ | 5s | 227.094 | 40.749 |
| go-v0.44 x rust-v0.54 (tcp, tls, yamux) | go-v0.44 | rust-v0.54 | tcp | tls | yamux | ✅ | 4s | 88.59 | 41.968 |
| go-v0.44 x rust-v0.53 (webrtc-direct) | go-v0.44 | rust-v0.53 | webrtc-direct | - | - | ✅ | 6s | 409.499 | 0.376 |
| go-v0.44 x rust-v0.54 (tcp, noise, yamux) | go-v0.44 | rust-v0.54 | tcp | noise | yamux | ✅ | 6s | 91.141 | 40.36 |
| go-v0.44 x rust-v0.54 (ws, tls, yamux) | go-v0.44 | rust-v0.54 | ws | tls | yamux | ✅ | 5s | 182.084 | 41.491 |
| go-v0.44 x rust-v0.54 (ws, noise, yamux) | go-v0.44 | rust-v0.54 | ws | noise | yamux | ✅ | 5s | 180.494 | 44.713 |
| go-v0.44 x rust-v0.54 (quic-v1) | go-v0.44 | rust-v0.54 | quic-v1 | - | - | ✅ | 5s | 15.558 | 1.36 |
| go-v0.44 x rust-v0.55 (tcp, tls, yamux) | go-v0.44 | rust-v0.55 | tcp | tls | yamux | ✅ | 4s | 8.877 | 0.822 |
| go-v0.44 x rust-v0.54 (webrtc-direct) | go-v0.44 | rust-v0.54 | webrtc-direct | - | - | ✅ | 5s | 417.519 | 0.477 |
| go-v0.44 x rust-v0.55 (tcp, noise, yamux) | go-v0.44 | rust-v0.55 | tcp | noise | yamux | ✅ | 4s | 21.355 | 0.683 |
| go-v0.44 x rust-v0.55 (ws, tls, yamux) | go-v0.44 | rust-v0.55 | ws | tls | yamux | ✅ | 6s | 18.201 | 5.427 |
| go-v0.44 x rust-v0.55 (ws, noise, yamux) | go-v0.44 | rust-v0.55 | ws | noise | yamux | ✅ | 5s | 16.897 | 0.542 |
| go-v0.44 x rust-v0.55 (quic-v1) | go-v0.44 | rust-v0.55 | quic-v1 | - | - | ✅ | 5s | 11.279 | 1.068 |
| go-v0.44 x rust-v0.55 (webrtc-direct) | go-v0.44 | rust-v0.55 | webrtc-direct | - | - | ✅ | 5s | 229.643 | 1.016 |
| go-v0.44 x rust-v0.56 (tcp, tls, yamux) | go-v0.44 | rust-v0.56 | tcp | tls | yamux | ✅ | 5s | 7.978 | 0.426 |
| go-v0.44 x rust-v0.56 (tcp, noise, yamux) | go-v0.44 | rust-v0.56 | tcp | noise | yamux | ✅ | 5s | 8.652 | 2.906 |
| go-v0.44 x rust-v0.56 (ws, tls, yamux) | go-v0.44 | rust-v0.56 | ws | tls | yamux | ✅ | 4s | 8.828 | 0.321 |
| go-v0.44 x rust-v0.56 (ws, noise, yamux) | go-v0.44 | rust-v0.56 | ws | noise | yamux | ✅ | 5s | 18.267 | 2.398 |
| go-v0.44 x rust-v0.56 (quic-v1) | go-v0.44 | rust-v0.56 | quic-v1 | - | - | ✅ | 5s | 8.513 | 0.319 |
| go-v0.44 x go-v0.38 (tcp, noise, yamux) | go-v0.44 | go-v0.38 | tcp | noise | yamux | ✅ | 4s | 13.488 | 0.515 |
| go-v0.44 x go-v0.38 (tcp, tls, yamux) | go-v0.44 | go-v0.38 | tcp | tls | yamux | ✅ | 5s | 11.732 | 0.83 |
| go-v0.44 x go-v0.38 (ws, tls, yamux) | go-v0.44 | go-v0.38 | ws | tls | yamux | ✅ | 5s | 10.764 | 1.5 |
| go-v0.44 x go-v0.38 (ws, noise, yamux) | go-v0.44 | go-v0.38 | ws | noise | yamux | ✅ | 5s | 10.393 | 0.255 |
| go-v0.44 x go-v0.38 (wss, tls, yamux) | go-v0.44 | go-v0.38 | wss | tls | yamux | ✅ | 4s | 19.439 | 0.751 |
| go-v0.44 x go-v0.38 (quic-v1) | go-v0.44 | go-v0.38 | quic-v1 | - | - | ✅ | 4s | 8.769 | 0.339 |
| go-v0.44 x go-v0.38 (wss, noise, yamux) | go-v0.44 | go-v0.38 | wss | noise | yamux | ✅ | 5s | 12.793 | 0.524 |
| go-v0.44 x go-v0.38 (webtransport) | go-v0.44 | go-v0.38 | webtransport | - | - | ✅ | 3s | 19.752 | 2.008 |
| go-v0.44 x rust-v0.56 (webrtc-direct) | go-v0.44 | rust-v0.56 | webrtc-direct | - | - | ❌ | 10s | - | - |
| go-v0.44 x go-v0.38 (webrtc-direct) | go-v0.44 | go-v0.38 | webrtc-direct | - | - | ✅ | 6s | 218.468 | 0.63 |
| go-v0.44 x go-v0.39 (tcp, noise, yamux) | go-v0.44 | go-v0.39 | tcp | noise | yamux | ✅ | 5s | 12.189 | 2.071 |
| go-v0.44 x go-v0.39 (tcp, tls, yamux) | go-v0.44 | go-v0.39 | tcp | tls | yamux | ✅ | 6s | 12.058 | 0.964 |
| go-v0.44 x go-v0.39 (ws, tls, yamux) | go-v0.44 | go-v0.39 | ws | tls | yamux | ✅ | 5s | 44.147 | 5.474 |
| go-v0.44 x go-v0.39 (ws, noise, yamux) | go-v0.44 | go-v0.39 | ws | noise | yamux | ✅ | 4s | 16.167 | 0.49 |
| go-v0.44 x go-v0.39 (wss, tls, yamux) | go-v0.44 | go-v0.39 | wss | tls | yamux | ✅ | 5s | 14.926 | 0.583 |
| go-v0.44 x go-v0.39 (wss, noise, yamux) | go-v0.44 | go-v0.39 | wss | noise | yamux | ✅ | 5s | 18.297 | 1.85 |
| go-v0.44 x go-v0.39 (quic-v1) | go-v0.44 | go-v0.39 | quic-v1 | - | - | ✅ | 5s | 9.933 | 0.69 |
| go-v0.44 x go-v0.39 (webtransport) | go-v0.44 | go-v0.39 | webtransport | - | - | ✅ | 5s | 21.283 | 0.462 |
| go-v0.44 x go-v0.40 (tcp, tls, yamux) | go-v0.44 | go-v0.40 | tcp | tls | yamux | ✅ | 4s | 9.867 | 0.827 |
| go-v0.44 x go-v0.39 (webrtc-direct) | go-v0.44 | go-v0.39 | webrtc-direct | - | - | ✅ | 5s | 216.521 | 0.354 |
| go-v0.44 x go-v0.40 (tcp, noise, yamux) | go-v0.44 | go-v0.40 | tcp | noise | yamux | ✅ | 5s | 12.519 | 0.499 |
| go-v0.44 x go-v0.40 (ws, tls, yamux) | go-v0.44 | go-v0.40 | ws | tls | yamux | ✅ | 5s | 4.013 | 0.17 |
| go-v0.44 x go-v0.40 (ws, noise, yamux) | go-v0.44 | go-v0.40 | ws | noise | yamux | ✅ | 4s | 10.428 | 1.39 |
| go-v0.44 x go-v0.40 (wss, tls, yamux) | go-v0.44 | go-v0.40 | wss | tls | yamux | ✅ | 5s | 20.557 | 1.181 |
| go-v0.44 x go-v0.40 (wss, noise, yamux) | go-v0.44 | go-v0.40 | wss | noise | yamux | ✅ | 5s | 22.057 | 1.294 |
| go-v0.44 x go-v0.40 (quic-v1) | go-v0.44 | go-v0.40 | quic-v1 | - | - | ✅ | 4s | 11.56 | 0.682 |
| go-v0.44 x go-v0.40 (webtransport) | go-v0.44 | go-v0.40 | webtransport | - | - | ✅ | 5s | 16.672 | 0.757 |
| go-v0.44 x go-v0.40 (webrtc-direct) | go-v0.44 | go-v0.40 | webrtc-direct | - | - | ✅ | 4s | 212.392 | 0.331 |
| go-v0.44 x go-v0.41 (tcp, tls, yamux) | go-v0.44 | go-v0.41 | tcp | tls | yamux | ✅ | 5s | 11.072 | 0.774 |
| go-v0.44 x go-v0.41 (tcp, noise, yamux) | go-v0.44 | go-v0.41 | tcp | noise | yamux | ✅ | 5s | 11.646 | 3.58 |
| go-v0.44 x go-v0.41 (ws, tls, yamux) | go-v0.44 | go-v0.41 | ws | tls | yamux | ✅ | 5s | 8.505 | 0.293 |
| go-v0.44 x go-v0.41 (ws, noise, yamux) | go-v0.44 | go-v0.41 | ws | noise | yamux | ✅ | 5s | 11.576 | 1.129 |
| go-v0.44 x go-v0.41 (wss, tls, yamux) | go-v0.44 | go-v0.41 | wss | tls | yamux | ✅ | 5s | 25.387 | 0.414 |
| go-v0.44 x go-v0.41 (quic-v1) | go-v0.44 | go-v0.41 | quic-v1 | - | - | ✅ | 4s | 9.664 | 0.967 |
| go-v0.44 x go-v0.41 (wss, noise, yamux) | go-v0.44 | go-v0.41 | wss | noise | yamux | ✅ | 6s | 28.1 | 1.723 |
| go-v0.44 x go-v0.41 (webtransport) | go-v0.44 | go-v0.41 | webtransport | - | - | ✅ | 5s | 11.507 | 0.403 |
| go-v0.44 x go-v0.41 (webrtc-direct) | go-v0.44 | go-v0.41 | webrtc-direct | - | - | ✅ | 5s | 11.405 | 0.34 |
| go-v0.44 x go-v0.42 (tcp, tls, yamux) | go-v0.44 | go-v0.42 | tcp | tls | yamux | ✅ | 5s | 8.004 | 0.748 |
| go-v0.44 x go-v0.42 (tcp, noise, yamux) | go-v0.44 | go-v0.42 | tcp | noise | yamux | ✅ | 4s | 24.113 | 1.157 |
| go-v0.44 x go-v0.42 (ws, tls, yamux) | go-v0.44 | go-v0.42 | ws | tls | yamux | ✅ | 5s | 7.552 | 1.1 |
| go-v0.44 x go-v0.42 (ws, noise, yamux) | go-v0.44 | go-v0.42 | ws | noise | yamux | ✅ | 5s | 12.262 | 0.989 |
| go-v0.44 x go-v0.42 (quic-v1) | go-v0.44 | go-v0.42 | quic-v1 | - | - | ✅ | 4s | 12.615 | 2.922 |
| go-v0.44 x go-v0.42 (wss, tls, yamux) | go-v0.44 | go-v0.42 | wss | tls | yamux | ✅ | 5s | 24.665 | 2.377 |
| go-v0.44 x go-v0.42 (wss, noise, yamux) | go-v0.44 | go-v0.42 | wss | noise | yamux | ✅ | 6s | 15.515 | 0.782 |
| go-v0.44 x go-v0.42 (webtransport) | go-v0.44 | go-v0.42 | webtransport | - | - | ✅ | 5s | 11.185 | 0.387 |
| go-v0.44 x go-v0.42 (webrtc-direct) | go-v0.44 | go-v0.42 | webrtc-direct | - | - | ✅ | 4s | 217.227 | 0.787 |
| go-v0.44 x go-v0.43 (tcp, tls, yamux) | go-v0.44 | go-v0.43 | tcp | tls | yamux | ✅ | 5s | 14.338 | 2.87 |
| go-v0.44 x go-v0.43 (tcp, noise, yamux) | go-v0.44 | go-v0.43 | tcp | noise | yamux | ✅ | 4s | 9.703 | 1.063 |
| go-v0.44 x go-v0.43 (ws, tls, yamux) | go-v0.44 | go-v0.43 | ws | tls | yamux | ✅ | 4s | 14.86 | 2.704 |
| go-v0.44 x go-v0.43 (ws, noise, yamux) | go-v0.44 | go-v0.43 | ws | noise | yamux | ✅ | 5s | 12.707 | 1.854 |
| go-v0.44 x go-v0.43 (wss, tls, yamux) | go-v0.44 | go-v0.43 | wss | tls | yamux | ✅ | 5s | 15.738 | 0.374 |
| go-v0.44 x go-v0.43 (quic-v1) | go-v0.44 | go-v0.43 | quic-v1 | - | - | ✅ | 4s | 50.675 | 0.511 |
| go-v0.44 x go-v0.43 (wss, noise, yamux) | go-v0.44 | go-v0.43 | wss | noise | yamux | ✅ | 6s | 10.745 | 0.272 |
| go-v0.44 x go-v0.43 (webtransport) | go-v0.44 | go-v0.43 | webtransport | - | - | ✅ | 4s | 15.163 | 1.101 |
| go-v0.44 x go-v0.43 (webrtc-direct) | go-v0.44 | go-v0.43 | webrtc-direct | - | - | ✅ | 5s | 17.285 | 0.573 |
| go-v0.44 x go-v0.44 (tcp, noise, yamux) | go-v0.44 | go-v0.44 | tcp | noise | yamux | ✅ | 4s | 11.992 | 0.884 |
| go-v0.44 x go-v0.44 (tcp, tls, yamux) | go-v0.44 | go-v0.44 | tcp | tls | yamux | ✅ | 5s | 20.106 | 4.425 |
| go-v0.44 x go-v0.44 (ws, tls, yamux) | go-v0.44 | go-v0.44 | ws | tls | yamux | ✅ | 5s | 15.381 | 1.27 |
| go-v0.44 x go-v0.44 (ws, noise, yamux) | go-v0.44 | go-v0.44 | ws | noise | yamux | ✅ | 6s | 15.797 | 1.581 |
| go-v0.44 x go-v0.44 (wss, tls, yamux) | go-v0.44 | go-v0.44 | wss | tls | yamux | ✅ | 5s | 97.216 | 2.184 |
| go-v0.44 x go-v0.44 (wss, noise, yamux) | go-v0.44 | go-v0.44 | wss | noise | yamux | ✅ | 5s | 13.383 | 1.131 |
| go-v0.44 x go-v0.44 (quic-v1) | go-v0.44 | go-v0.44 | quic-v1 | - | - | ✅ | 5s | 7.811 | 1.421 |
| go-v0.44 x go-v0.44 (webtransport) | go-v0.44 | go-v0.44 | webtransport | - | - | ✅ | 4s | 11.78 | 0.503 |
| go-v0.44 x go-v0.45 (tcp, tls, yamux) | go-v0.44 | go-v0.45 | tcp | tls | yamux | ✅ | 4s | 16.999 | 3.313 |
| go-v0.44 x go-v0.44 (webrtc-direct) | go-v0.44 | go-v0.44 | webrtc-direct | - | - | ✅ | 5s | 214.199 | 0.378 |
| go-v0.44 x go-v0.45 (tcp, noise, yamux) | go-v0.44 | go-v0.45 | tcp | noise | yamux | ✅ | 5s | 12.389 | 0.931 |
| go-v0.44 x go-v0.45 (ws, tls, yamux) | go-v0.44 | go-v0.45 | ws | tls | yamux | ✅ | 5s | 9.842 | 0.241 |
| go-v0.44 x go-v0.45 (ws, noise, yamux) | go-v0.44 | go-v0.45 | ws | noise | yamux | ✅ | 4s | 17.56 | 3.841 |
| go-v0.44 x go-v0.45 (wss, noise, yamux) | go-v0.44 | go-v0.45 | wss | noise | yamux | ✅ | 5s | 23.547 | 0.972 |
| go-v0.44 x go-v0.45 (wss, tls, yamux) | go-v0.44 | go-v0.45 | wss | tls | yamux | ✅ | 5s | 15.662 | 0.229 |
| go-v0.44 x go-v0.45 (quic-v1) | go-v0.44 | go-v0.45 | quic-v1 | - | - | ✅ | 5s | 13.067 | 0.482 |
| go-v0.44 x go-v0.45 (webtransport) | go-v0.44 | go-v0.45 | webtransport | - | - | ✅ | 4s | 19.155 | 0.43 |
| go-v0.44 x go-v0.45 (webrtc-direct) | go-v0.44 | go-v0.45 | webrtc-direct | - | - | ✅ | 4s | 14.202 | 0.573 |
| go-v0.44 x python-v0.4 (tcp, noise, yamux) | go-v0.44 | python-v0.4 | tcp | noise | yamux | ✅ | 4s | 23.696 | 2.437 |
| go-v0.44 x python-v0.4 (ws, noise, yamux) | go-v0.44 | python-v0.4 | ws | noise | yamux | ✅ | 6s | 39.826 | 11.12 |
| go-v0.44 x python-v0.4 (wss, noise, yamux) | go-v0.44 | python-v0.4 | wss | noise | yamux | ✅ | 5s | 42.149 | 4.697 |
| go-v0.44 x python-v0.4 (quic-v1) | go-v0.44 | python-v0.4 | quic-v1 | - | - | ✅ | 6s | 105.915 | 20.989 |
| go-v0.44 x nim-v1.14 (tcp, noise, yamux) | go-v0.44 | nim-v1.14 | tcp | noise | yamux | ✅ | 5s | 207.26 | 42.282 |
| go-v0.44 x nim-v1.14 (ws, noise, yamux) | go-v0.44 | nim-v1.14 | ws | noise | yamux | ✅ | 5s | 251.824 | 43.61 |
| go-v0.44 x js-v1.x (tcp, noise, yamux) | go-v0.44 | js-v1.x | tcp | noise | yamux | ✅ | 19s | 175.574 | 16.752 |
| go-v0.44 x js-v1.x (ws, noise, yamux) | go-v0.44 | js-v1.x | ws | noise | yamux | ✅ | 19s | 191.882 | 15.216 |
| go-v0.44 x js-v2.x (tcp, noise, yamux) | go-v0.44 | js-v2.x | tcp | noise | yamux | ✅ | 21s | 163.482 | 24.858 |
| go-v0.44 x js-v2.x (ws, noise, yamux) | go-v0.44 | js-v2.x | ws | noise | yamux | ✅ | 20s | 180.325 | 27.91 |
| go-v0.44 x jvm-v1.2 (tcp, noise, yamux) | go-v0.44 | jvm-v1.2 | tcp | noise | yamux | ✅ | 11s | 1254.866 | 26.98 |
| go-v0.44 x js-v3.x (tcp, noise, yamux) | go-v0.44 | js-v3.x | tcp | noise | yamux | ✅ | 21s | 213.48 | 29.566 |
| go-v0.44 x js-v3.x (ws, noise, yamux) | go-v0.44 | js-v3.x | ws | noise | yamux | ✅ | 20s | 207.309 | 17.288 |
| go-v0.44 x jvm-v1.2 (tcp, tls, yamux) | go-v0.44 | jvm-v1.2 | tcp | tls | yamux | ✅ | 13s | 2759.416 | 6.268 |
| go-v0.44 x c-v0.0.1 (tcp, noise, yamux) | go-v0.44 | c-v0.0.1 | tcp | noise | yamux | ✅ | 5s | 120.807 | 52.814 |
| go-v0.44 x c-v0.0.1 (quic-v1) | go-v0.44 | c-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 98.633 | 49.217 |
| go-v0.44 x jvm-v1.2 (ws, noise, yamux) | go-v0.44 | jvm-v1.2 | ws | noise | yamux | ✅ | 10s | 1461.435 | 14.227 |
| go-v0.44 x zig-v0.0.1 (quic-v1) | go-v0.44 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 6s | - | - |
| go-v0.44 x dotnet-v1.0 (tcp, noise, yamux) | go-v0.44 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 7s | 488.714 | 52.308 |
| go-v0.44 x eth-p2p-z-v0.0.1 (quic-v1) | go-v0.44 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 7s | 26.751 | 0.329 |
| go-v0.44 x jvm-v1.2 (ws, tls, yamux) | go-v0.44 | jvm-v1.2 | ws | tls | yamux | ✅ | 13s | 3397.48 | 21.845 |
| go-v0.44 x jvm-v1.2 (quic-v1) | go-v0.44 | jvm-v1.2 | quic-v1 | - | - | ✅ | 12s | 852.963 | 15.305 |
| go-v0.45 x rust-v0.53 (tcp, tls, yamux) | go-v0.45 | rust-v0.53 | tcp | tls | yamux | ✅ | 4s | 95.149 | 45.635 |
| go-v0.45 x rust-v0.53 (tcp, noise, yamux) | go-v0.45 | rust-v0.53 | tcp | noise | yamux | ✅ | 4s | 95.445 | 42.072 |
| go-v0.45 x rust-v0.53 (ws, tls, yamux) | go-v0.45 | rust-v0.53 | ws | tls | yamux | ✅ | 4s | 176.936 | 43.111 |
| go-v0.45 x rust-v0.53 (quic-v1) | go-v0.45 | rust-v0.53 | quic-v1 | - | - | ✅ | 4s | 10.694 | 0.927 |
| go-v0.45 x rust-v0.53 (ws, noise, yamux) | go-v0.45 | rust-v0.53 | ws | noise | yamux | ✅ | 5s | 184.761 | 41.082 |
| go-v0.45 x rust-v0.53 (webrtc-direct) | go-v0.45 | rust-v0.53 | webrtc-direct | - | - | ✅ | 5s | 427.294 | 2.292 |
| go-v0.45 x rust-v0.54 (tcp, tls, yamux) | go-v0.45 | rust-v0.54 | tcp | tls | yamux | ✅ | 5s | 92.391 | 42.482 |
| go-v0.45 x rust-v0.54 (tcp, noise, yamux) | go-v0.45 | rust-v0.54 | tcp | noise | yamux | ✅ | 5s | 90.82 | 40.466 |
| go-v0.45 x rust-v0.54 (ws, tls, yamux) | go-v0.45 | rust-v0.54 | ws | tls | yamux | ✅ | 5s | 228.655 | 47.596 |
| go-v0.45 x rust-v0.54 (quic-v1) | go-v0.45 | rust-v0.54 | quic-v1 | - | - | ✅ | 4s | 9.891 | 0.381 |
| go-v0.45 x rust-v0.54 (ws, noise, yamux) | go-v0.45 | rust-v0.54 | ws | noise | yamux | ✅ | 6s | 229.274 | 43.45 |
| go-v0.45 x rust-v0.55 (tcp, tls, yamux) | go-v0.45 | rust-v0.55 | tcp | tls | yamux | ✅ | 4s | 9.464 | 1.054 |
| go-v0.45 x rust-v0.55 (tcp, noise, yamux) | go-v0.45 | rust-v0.55 | tcp | noise | yamux | ✅ | 4s | 15.499 | 1.425 |
| go-v0.45 x rust-v0.54 (webrtc-direct) | go-v0.45 | rust-v0.54 | webrtc-direct | - | - | ✅ | 6s | 622.735 | 0.616 |
| go-v0.45 x rust-v0.55 (ws, tls, yamux) | go-v0.45 | rust-v0.55 | ws | tls | yamux | ✅ | 5s | 14.515 | 0.837 |
| go-v0.45 x rust-v0.55 (ws, noise, yamux) | go-v0.45 | rust-v0.55 | ws | noise | yamux | ✅ | 4s | 5.413 | 0.214 |
| go-v0.45 x rust-v0.55 (quic-v1) | go-v0.45 | rust-v0.55 | quic-v1 | - | - | ✅ | 5s | 6.151 | 0.211 |
| go-v0.45 x rust-v0.55 (webrtc-direct) | go-v0.45 | rust-v0.55 | webrtc-direct | - | - | ✅ | 5s | 423.354 | 0.775 |
| go-v0.45 x rust-v0.56 (tcp, tls, yamux) | go-v0.45 | rust-v0.56 | tcp | tls | yamux | ✅ | 6s | 8.682 | 0.727 |
| go-v0.45 x rust-v0.56 (tcp, noise, yamux) | go-v0.45 | rust-v0.56 | tcp | noise | yamux | ✅ | 5s | 10.335 | 0.449 |
| go-v0.45 x rust-v0.56 (ws, tls, yamux) | go-v0.45 | rust-v0.56 | ws | tls | yamux | ✅ | 4s | 8.942 | 0.727 |
| go-v0.45 x rust-v0.56 (ws, noise, yamux) | go-v0.45 | rust-v0.56 | ws | noise | yamux | ✅ | 5s | 10.537 | 0.45 |
| go-v0.45 x rust-v0.56 (quic-v1) | go-v0.45 | rust-v0.56 | quic-v1 | - | - | ✅ | 5s | 6.064 | 0.279 |
| go-v0.45 x go-v0.38 (tcp, tls, yamux) | go-v0.45 | go-v0.38 | tcp | tls | yamux | ✅ | 5s | 10.783 | 0.355 |
| go-v0.45 x go-v0.38 (tcp, noise, yamux) | go-v0.45 | go-v0.38 | tcp | noise | yamux | ✅ | 4s | 7.493 | 0.403 |
| go-v0.45 x go-v0.38 (ws, tls, yamux) | go-v0.45 | go-v0.38 | ws | tls | yamux | ✅ | 5s | 14.758 | 0.595 |
| go-v0.45 x go-v0.38 (ws, noise, yamux) | go-v0.45 | go-v0.38 | ws | noise | yamux | ✅ | 4s | 10.699 | 0.331 |
| go-v0.45 x go-v0.38 (wss, noise, yamux) | go-v0.45 | go-v0.38 | wss | noise | yamux | ✅ | 5s | 23.673 | 2.032 |
| go-v0.45 x go-v0.38 (wss, tls, yamux) | go-v0.45 | go-v0.38 | wss | tls | yamux | ✅ | 5s | 37.367 | 6.159 |
| go-v0.45 x go-v0.38 (quic-v1) | go-v0.45 | go-v0.38 | quic-v1 | - | - | ✅ | 4s | 6.495 | 0.386 |
| go-v0.45 x rust-v0.56 (webrtc-direct) | go-v0.45 | rust-v0.56 | webrtc-direct | - | - | ❌ | 10s | - | - |
| go-v0.45 x go-v0.38 (webtransport) | go-v0.45 | go-v0.38 | webtransport | - | - | ✅ | 5s | 21.793 | 2.405 |
| go-v0.45 x go-v0.38 (webrtc-direct) | go-v0.45 | go-v0.38 | webrtc-direct | - | - | ✅ | 4s | 226.23 | 2.309 |
| go-v0.45 x go-v0.39 (tcp, tls, yamux) | go-v0.45 | go-v0.39 | tcp | tls | yamux | ✅ | 5s | 10.996 | 1.023 |
| go-v0.45 x go-v0.39 (tcp, noise, yamux) | go-v0.45 | go-v0.39 | tcp | noise | yamux | ✅ | 5s | 9.628 | 1.26 |
| go-v0.45 x go-v0.39 (ws, tls, yamux) | go-v0.45 | go-v0.39 | ws | tls | yamux | ✅ | 5s | 18.542 | 7.354 |
| go-v0.45 x go-v0.39 (ws, noise, yamux) | go-v0.45 | go-v0.39 | ws | noise | yamux | ✅ | 4s | 14.184 | 4.111 |
| go-v0.45 x go-v0.39 (wss, tls, yamux) | go-v0.45 | go-v0.39 | wss | tls | yamux | ✅ | 5s | 21.164 | 2.041 |
| go-v0.45 x go-v0.39 (wss, noise, yamux) | go-v0.45 | go-v0.39 | wss | noise | yamux | ✅ | 5s | 8.701 | 0.22 |
| go-v0.45 x go-v0.39 (quic-v1) | go-v0.45 | go-v0.39 | quic-v1 | - | - | ✅ | 5s | 19.788 | 0.794 |
| go-v0.45 x go-v0.39 (webtransport) | go-v0.45 | go-v0.39 | webtransport | - | - | ✅ | 5s | 12.043 | 0.322 |
| go-v0.45 x go-v0.39 (webrtc-direct) | go-v0.45 | go-v0.39 | webrtc-direct | - | - | ✅ | 5s | 221.265 | 0.882 |
| go-v0.45 x go-v0.40 (tcp, tls, yamux) | go-v0.45 | go-v0.40 | tcp | tls | yamux | ✅ | 5s | 13.671 | 3.37 |
| go-v0.45 x go-v0.40 (tcp, noise, yamux) | go-v0.45 | go-v0.40 | tcp | noise | yamux | ✅ | 5s | 6.501 | 0.251 |
| go-v0.45 x go-v0.40 (ws, tls, yamux) | go-v0.45 | go-v0.40 | ws | tls | yamux | ✅ | 4s | 21.327 | 0.403 |
| go-v0.45 x go-v0.40 (wss, tls, yamux) | go-v0.45 | go-v0.40 | wss | tls | yamux | ✅ | 4s | 9.502 | 0.494 |
| go-v0.45 x go-v0.40 (ws, noise, yamux) | go-v0.45 | go-v0.40 | ws | noise | yamux | ✅ | 6s | 14.966 | 1.699 |
| go-v0.45 x go-v0.40 (quic-v1) | go-v0.45 | go-v0.40 | quic-v1 | - | - | ✅ | 5s | 12.415 | 1.492 |
| go-v0.45 x go-v0.40 (wss, noise, yamux) | go-v0.45 | go-v0.40 | wss | noise | yamux | ✅ | 5s | 21.048 | 0.439 |
| go-v0.45 x go-v0.40 (webtransport) | go-v0.45 | go-v0.40 | webtransport | - | - | ✅ | 5s | 15.836 | 1.654 |
| go-v0.45 x go-v0.41 (tcp, tls, yamux) | go-v0.45 | go-v0.41 | tcp | tls | yamux | ✅ | 5s | 8.673 | 0.671 |
| go-v0.45 x go-v0.40 (webrtc-direct) | go-v0.45 | go-v0.40 | webrtc-direct | - | - | ✅ | 5s | 238.994 | 2.404 |
| go-v0.45 x go-v0.41 (ws, tls, yamux) | go-v0.45 | go-v0.41 | ws | tls | yamux | ✅ | 4s | 6.219 | 1.017 |
| go-v0.45 x go-v0.41 (tcp, noise, yamux) | go-v0.45 | go-v0.41 | tcp | noise | yamux | ✅ | 5s | 13.183 | 0.876 |
| go-v0.45 x go-v0.41 (ws, noise, yamux) | go-v0.45 | go-v0.41 | ws | noise | yamux | ✅ | 5s | 21.994 | 2.31 |
| go-v0.45 x go-v0.41 (wss, noise, yamux) | go-v0.45 | go-v0.41 | wss | noise | yamux | ✅ | 5s | 14.344 | 1.189 |
| go-v0.45 x go-v0.41 (wss, tls, yamux) | go-v0.45 | go-v0.41 | wss | tls | yamux | ✅ | 6s | 21.337 | 1.937 |
| go-v0.45 x go-v0.41 (quic-v1) | go-v0.45 | go-v0.41 | quic-v1 | - | - | ✅ | 6s | 14.361 | 1.459 |
| go-v0.45 x go-v0.41 (webtransport) | go-v0.45 | go-v0.41 | webtransport | - | - | ✅ | 5s | 10.238 | 0.419 |
| go-v0.45 x go-v0.41 (webrtc-direct) | go-v0.45 | go-v0.41 | webrtc-direct | - | - | ✅ | 5s | 215.777 | 0.364 |
| go-v0.45 x go-v0.42 (tcp, tls, yamux) | go-v0.45 | go-v0.42 | tcp | tls | yamux | ✅ | 4s | 7.89 | 2.64 |
| go-v0.45 x go-v0.42 (ws, tls, yamux) | go-v0.45 | go-v0.42 | ws | tls | yamux | ✅ | 4s | 9.847 | 0.59 |
| go-v0.45 x go-v0.42 (tcp, noise, yamux) | go-v0.45 | go-v0.42 | tcp | noise | yamux | ✅ | 5s | 9.064 | 1.089 |
| go-v0.45 x go-v0.42 (ws, noise, yamux) | go-v0.45 | go-v0.42 | ws | noise | yamux | ✅ | 4s | 19.771 | 0.387 |
| go-v0.45 x go-v0.42 (quic-v1) | go-v0.45 | go-v0.42 | quic-v1 | - | - | ✅ | 4s | 16.258 | 2.185 |
| go-v0.45 x go-v0.42 (wss, tls, yamux) | go-v0.45 | go-v0.42 | wss | tls | yamux | ✅ | 5s | 13.867 | 0.475 |
| go-v0.45 x go-v0.42 (webtransport) | go-v0.45 | go-v0.42 | webtransport | - | - | ✅ | 5s | 12.076 | 0.481 |
| go-v0.45 x go-v0.42 (wss, noise, yamux) | go-v0.45 | go-v0.42 | wss | noise | yamux | ✅ | 6s | 15.179 | 0.269 |
| go-v0.45 x go-v0.42 (webrtc-direct) | go-v0.45 | go-v0.42 | webrtc-direct | - | - | ✅ | 5s | 219.595 | 0.685 |
| go-v0.45 x go-v0.43 (tcp, tls, yamux) | go-v0.45 | go-v0.43 | tcp | tls | yamux | ✅ | 4s | 8.625 | 0.378 |
| go-v0.45 x go-v0.43 (tcp, noise, yamux) | go-v0.45 | go-v0.43 | tcp | noise | yamux | ✅ | 5s | 10.162 | 0.27 |
| go-v0.45 x go-v0.43 (ws, tls, yamux) | go-v0.45 | go-v0.43 | ws | tls | yamux | ✅ | 4s | 7.732 | 0.39 |
| go-v0.45 x go-v0.43 (ws, noise, yamux) | go-v0.45 | go-v0.43 | ws | noise | yamux | ✅ | 5s | 7.372 | 0.425 |
| go-v0.45 x go-v0.43 (wss, tls, yamux) | go-v0.45 | go-v0.43 | wss | tls | yamux | ✅ | 5s | 19.82 | 1.542 |
| go-v0.45 x go-v0.43 (quic-v1) | go-v0.45 | go-v0.43 | quic-v1 | - | - | ✅ | 4s | 20.925 | 1.02 |
| go-v0.45 x go-v0.43 (webtransport) | go-v0.45 | go-v0.43 | webtransport | - | - | ✅ | 5s | 12.698 | 0.34 |
| go-v0.45 x go-v0.43 (wss, noise, yamux) | go-v0.45 | go-v0.43 | wss | noise | yamux | ✅ | 6s | 12.735 | 0.369 |
| go-v0.45 x go-v0.43 (webrtc-direct) | go-v0.45 | go-v0.43 | webrtc-direct | - | - | ✅ | 5s | 211.778 | 0.254 |
| go-v0.45 x go-v0.44 (tcp, tls, yamux) | go-v0.45 | go-v0.44 | tcp | tls | yamux | ✅ | 5s | 10.186 | 0.682 |
| go-v0.45 x go-v0.44 (tcp, noise, yamux) | go-v0.45 | go-v0.44 | tcp | noise | yamux | ✅ | 5s | 60.511 | 0.349 |
| go-v0.45 x go-v0.44 (ws, tls, yamux) | go-v0.45 | go-v0.44 | ws | tls | yamux | ✅ | 5s | 14.766 | 1.002 |
| go-v0.45 x go-v0.44 (ws, noise, yamux) | go-v0.45 | go-v0.44 | ws | noise | yamux | ✅ | 5s | 14.681 | 0.466 |
| go-v0.45 x go-v0.44 (wss, tls, yamux) | go-v0.45 | go-v0.44 | wss | tls | yamux | ✅ | 5s | 24.286 | 1.071 |
| go-v0.45 x go-v0.44 (wss, noise, yamux) | go-v0.45 | go-v0.44 | wss | noise | yamux | ✅ | 5s | 10.471 | 0.238 |
| go-v0.45 x go-v0.44 (quic-v1) | go-v0.45 | go-v0.44 | quic-v1 | - | - | ✅ | 5s | 13.578 | 0.5 |
| go-v0.45 x go-v0.44 (webtransport) | go-v0.45 | go-v0.44 | webtransport | - | - | ✅ | 4s | 17.731 | 0.75 |
| go-v0.45 x go-v0.44 (webrtc-direct) | go-v0.45 | go-v0.44 | webrtc-direct | - | - | ✅ | 6s | 225.004 | 1.316 |
| go-v0.45 x go-v0.45 (tcp, tls, yamux) | go-v0.45 | go-v0.45 | tcp | tls | yamux | ✅ | 5s | 15.884 | 1.042 |
| go-v0.45 x go-v0.45 (tcp, noise, yamux) | go-v0.45 | go-v0.45 | tcp | noise | yamux | ✅ | 5s | 9.463 | 0.534 |
| go-v0.45 x go-v0.45 (ws, tls, yamux) | go-v0.45 | go-v0.45 | ws | tls | yamux | ✅ | 5s | 12.812 | 2.304 |
| go-v0.45 x go-v0.45 (ws, noise, yamux) | go-v0.45 | go-v0.45 | ws | noise | yamux | ✅ | 5s | 8.274 | 0.927 |
| go-v0.45 x go-v0.45 (wss, noise, yamux) | go-v0.45 | go-v0.45 | wss | noise | yamux | ✅ | 5s | 16.888 | 2.806 |
| go-v0.45 x go-v0.45 (wss, tls, yamux) | go-v0.45 | go-v0.45 | wss | tls | yamux | ✅ | 6s | 22.172 | 0.515 |
| go-v0.45 x go-v0.45 (quic-v1) | go-v0.45 | go-v0.45 | quic-v1 | - | - | ✅ | 5s | 15.192 | 0.695 |
| go-v0.45 x go-v0.45 (webtransport) | go-v0.45 | go-v0.45 | webtransport | - | - | ✅ | 5s | 16.621 | 2.557 |
| go-v0.45 x go-v0.45 (webrtc-direct) | go-v0.45 | go-v0.45 | webrtc-direct | - | - | ✅ | 4s | 222.974 | 1.09 |
| go-v0.45 x python-v0.4 (tcp, noise, yamux) | go-v0.45 | python-v0.4 | tcp | noise | yamux | ✅ | 5s | 28.987 | 3.684 |
| go-v0.45 x python-v0.4 (ws, noise, yamux) | go-v0.45 | python-v0.4 | ws | noise | yamux | ✅ | 5s | 33.526 | 4.15 |
| go-v0.45 x python-v0.4 (wss, noise, yamux) | go-v0.45 | python-v0.4 | wss | noise | yamux | ✅ | 5s | 30.408 | 4.556 |
| go-v0.45 x python-v0.4 (quic-v1) | go-v0.45 | python-v0.4 | quic-v1 | - | - | ✅ | 5s | 96.552 | 18.29 |
| go-v0.45 x nim-v1.14 (tcp, noise, yamux) | go-v0.45 | nim-v1.14 | tcp | noise | yamux | ✅ | 5s | 209.932 | 47.458 |
| go-v0.45 x nim-v1.14 (ws, noise, yamux) | go-v0.45 | nim-v1.14 | ws | noise | yamux | ✅ | 5s | 245.082 | 43.98 |
| go-v0.45 x js-v1.x (tcp, noise, yamux) | go-v0.45 | js-v1.x | tcp | noise | yamux | ✅ | 21s | 199.67 | 20.883 |
| go-v0.45 x js-v1.x (ws, noise, yamux) | go-v0.45 | js-v1.x | ws | noise | yamux | ✅ | 21s | 230.091 | 27.82 |
| go-v0.45 x jvm-v1.2 (tcp, noise, yamux) | go-v0.45 | jvm-v1.2 | tcp | noise | yamux | ✅ | 11s | 1201.197 | 32.34 |
| go-v0.45 x js-v3.x (tcp, noise, yamux) | go-v0.45 | js-v3.x | tcp | noise | yamux | ✅ | 22s | 130.695 | 22.998 |
| go-v0.45 x jvm-v1.2 (tcp, tls, yamux) | go-v0.45 | jvm-v1.2 | tcp | tls | yamux | ✅ | 14s | 3863.463 | 18.062 |
| go-v0.45 x js-v2.x (ws, noise, yamux) | go-v0.45 | js-v2.x | ws | noise | yamux | ✅ | 23s | 167.453 | 20.707 |
| go-v0.45 x js-v2.x (tcp, noise, yamux) | go-v0.45 | js-v2.x | tcp | noise | yamux | ✅ | 24s | 120.924 | 21.724 |
| go-v0.45 x js-v3.x (ws, noise, yamux) | go-v0.45 | js-v3.x | ws | noise | yamux | ✅ | 23s | 128.925 | 13.428 |
| go-v0.45 x c-v0.0.1 (tcp, noise, yamux) | go-v0.45 | c-v0.0.1 | tcp | noise | yamux | ✅ | 6s | 128.846 | 54.276 |
| go-v0.45 x c-v0.0.1 (quic-v1) | go-v0.45 | c-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 105.271 | 53.122 |
| go-v0.45 x jvm-v1.2 (ws, noise, yamux) | go-v0.45 | jvm-v1.2 | ws | noise | yamux | ✅ | 9s | 1541.143 | 27.823 |
| go-v0.45 x dotnet-v1.0 (tcp, noise, yamux) | go-v0.45 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 6s | 483.778 | 48.013 |
| go-v0.45 x zig-v0.0.1 (quic-v1) | go-v0.45 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 6s | - | - |
| go-v0.45 x jvm-v1.2 (ws, tls, yamux) | go-v0.45 | jvm-v1.2 | ws | tls | yamux | ✅ | 11s | 3616.298 | 10.51 |
| go-v0.45 x eth-p2p-z-v0.0.1 (quic-v1) | go-v0.45 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 7s | 15.554 | 0.839 |
| go-v0.45 x jvm-v1.2 (quic-v1) | go-v0.45 | jvm-v1.2 | quic-v1 | - | - | ✅ | 11s | 580.395 | 13.721 |
| python-v0.4 x rust-v0.53 (tcp, noise, mplex) | python-v0.4 | rust-v0.53 | tcp | noise | mplex | ✅ | 4s | - | - |
| python-v0.4 x rust-v0.53 (tcp, noise, yamux) | python-v0.4 | rust-v0.53 | tcp | noise | yamux | ✅ | 5s | - | - |
| python-v0.4 x rust-v0.53 (quic-v1) | python-v0.4 | rust-v0.53 | quic-v1 | - | - | ✅ | 5s | - | - |
| python-v0.4 x rust-v0.54 (tcp, noise, mplex) | python-v0.4 | rust-v0.54 | tcp | noise | mplex | ✅ | 5s | - | - |
| python-v0.4 x rust-v0.54 (tcp, noise, yamux) | python-v0.4 | rust-v0.54 | tcp | noise | yamux | ✅ | 6s | - | - |
| python-v0.4 x rust-v0.54 (quic-v1) | python-v0.4 | rust-v0.54 | quic-v1 | - | - | ✅ | 4s | - | - |
| python-v0.4 x rust-v0.55 (tcp, noise, mplex) | python-v0.4 | rust-v0.55 | tcp | noise | mplex | ✅ | 3s | - | - |
| python-v0.4 x rust-v0.53 (ws, noise, mplex) | python-v0.4 | rust-v0.53 | ws | noise | mplex | ✅ | 11s | - | - |
| python-v0.4 x rust-v0.55 (tcp, noise, yamux) | python-v0.4 | rust-v0.55 | tcp | noise | yamux | ✅ | 3s | - | - |
| python-v0.4 x rust-v0.53 (ws, noise, yamux) | python-v0.4 | rust-v0.53 | ws | noise | yamux | ✅ | 11s | - | - |
| python-v0.4 x rust-v0.54 (ws, noise, mplex) | python-v0.4 | rust-v0.54 | ws | noise | mplex | ✅ | 10s | - | - |
| python-v0.4 x rust-v0.54 (ws, noise, yamux) | python-v0.4 | rust-v0.54 | ws | noise | yamux | ✅ | 10s | - | - |
| python-v0.4 x rust-v0.55 (quic-v1) | python-v0.4 | rust-v0.55 | quic-v1 | - | - | ✅ | 5s | - | - |
| python-v0.4 x rust-v0.56 (tcp, noise, mplex) | python-v0.4 | rust-v0.56 | tcp | noise | mplex | ✅ | 5s | - | - |
| python-v0.4 x rust-v0.56 (tcp, noise, yamux) | python-v0.4 | rust-v0.56 | tcp | noise | yamux | ✅ | 4s | - | - |
| python-v0.4 x rust-v0.56 (quic-v1) | python-v0.4 | rust-v0.56 | quic-v1 | - | - | ✅ | 4s | - | - |
| python-v0.4 x go-v0.38 (tcp, noise, yamux) | python-v0.4 | go-v0.38 | tcp | noise | yamux | ✅ | 4s | - | - |
| python-v0.4 x rust-v0.55 (ws, noise, mplex) | python-v0.4 | rust-v0.55 | ws | noise | mplex | ✅ | 14s | - | - |
| python-v0.4 x go-v0.38 (quic-v1) | python-v0.4 | go-v0.38 | quic-v1 | - | - | ✅ | 3s | - | - |
| python-v0.4 x go-v0.39 (tcp, noise, yamux) | python-v0.4 | go-v0.39 | tcp | noise | yamux | ✅ | 4s | - | - |
| python-v0.4 x rust-v0.55 (ws, noise, yamux) | python-v0.4 | rust-v0.55 | ws | noise | yamux | ✅ | 15s | - | - |
| python-v0.4 x rust-v0.56 (ws, noise, mplex) | python-v0.4 | rust-v0.56 | ws | noise | mplex | ✅ | 15s | - | - |
| python-v0.4 x go-v0.39 (quic-v1) | python-v0.4 | go-v0.39 | quic-v1 | - | - | ✅ | 3s | - | - |
| python-v0.4 x go-v0.40 (tcp, noise, yamux) | python-v0.4 | go-v0.40 | tcp | noise | yamux | ✅ | 4s | - | - |
| python-v0.4 x rust-v0.56 (ws, noise, yamux) | python-v0.4 | rust-v0.56 | ws | noise | yamux | ✅ | 15s | - | - |
| python-v0.4 x go-v0.40 (quic-v1) | python-v0.4 | go-v0.40 | quic-v1 | - | - | ✅ | 3s | - | - |
| python-v0.4 x go-v0.41 (tcp, noise, yamux) | python-v0.4 | go-v0.41 | tcp | noise | yamux | ✅ | 3s | - | - |
| python-v0.4 x go-v0.38 (ws, noise, yamux) | python-v0.4 | go-v0.38 | ws | noise | yamux | ✅ | 43s | - | - |
| python-v0.4 x go-v0.38 (wss, noise, yamux) | python-v0.4 | go-v0.38 | wss | noise | yamux | ✅ | 43s | - | - |
| python-v0.4 x go-v0.41 (quic-v1) | python-v0.4 | go-v0.41 | quic-v1 | - | - | ✅ | 3s | - | - |
| python-v0.4 x go-v0.42 (tcp, noise, yamux) | python-v0.4 | go-v0.42 | tcp | noise | yamux | ✅ | 3s | - | - |
| python-v0.4 x go-v0.39 (ws, noise, yamux) | python-v0.4 | go-v0.39 | ws | noise | yamux | ✅ | 43s | - | - |
| python-v0.4 x go-v0.39 (wss, noise, yamux) | python-v0.4 | go-v0.39 | wss | noise | yamux | ✅ | 44s | - | - |
| python-v0.4 x go-v0.42 (quic-v1) | python-v0.4 | go-v0.42 | quic-v1 | - | - | ✅ | 3s | - | - |
| python-v0.4 x go-v0.43 (tcp, noise, yamux) | python-v0.4 | go-v0.43 | tcp | noise | yamux | ✅ | 3s | - | - |
| python-v0.4 x go-v0.40 (ws, noise, yamux) | python-v0.4 | go-v0.40 | ws | noise | yamux | ✅ | 44s | - | - |
| python-v0.4 x go-v0.40 (wss, noise, yamux) | python-v0.4 | go-v0.40 | wss | noise | yamux | ✅ | 44s | - | - |
| python-v0.4 x go-v0.43 (quic-v1) | python-v0.4 | go-v0.43 | quic-v1 | - | - | ✅ | 3s | - | - |
| python-v0.4 x go-v0.44 (tcp, noise, yamux) | python-v0.4 | go-v0.44 | tcp | noise | yamux | ✅ | 3s | - | - |
| python-v0.4 x go-v0.41 (ws, noise, yamux) | python-v0.4 | go-v0.41 | ws | noise | yamux | ✅ | 43s | - | - |
| python-v0.4 x go-v0.41 (wss, noise, yamux) | python-v0.4 | go-v0.41 | wss | noise | yamux | ✅ | 43s | - | - |
| python-v0.4 x go-v0.44 (quic-v1) | python-v0.4 | go-v0.44 | quic-v1 | - | - | ✅ | 3s | - | - |
| python-v0.4 x go-v0.45 (tcp, noise, yamux) | python-v0.4 | go-v0.45 | tcp | noise | yamux | ✅ | 3s | - | - |
| python-v0.4 x go-v0.42 (ws, noise, yamux) | python-v0.4 | go-v0.42 | ws | noise | yamux | ✅ | 43s | - | - |
| python-v0.4 x go-v0.42 (wss, noise, yamux) | python-v0.4 | go-v0.42 | wss | noise | yamux | ✅ | 43s | - | - |
| python-v0.4 x go-v0.45 (quic-v1) | python-v0.4 | go-v0.45 | quic-v1 | - | - | ✅ | 3s | - | - |
| python-v0.4 x python-v0.4 (tcp, noise, mplex) | python-v0.4 | python-v0.4 | tcp | noise | mplex | ✅ | 3s | - | - |
| python-v0.4 x go-v0.43 (ws, noise, yamux) | python-v0.4 | go-v0.43 | ws | noise | yamux | ✅ | 43s | - | - |
| python-v0.4 x python-v0.4 (tcp, noise, yamux) | python-v0.4 | python-v0.4 | tcp | noise | yamux | ✅ | 3s | - | - |
| python-v0.4 x python-v0.4 (ws, noise, mplex) | python-v0.4 | python-v0.4 | ws | noise | mplex | ✅ | 4s | - | - |
| python-v0.4 x go-v0.43 (wss, noise, yamux) | python-v0.4 | go-v0.43 | wss | noise | yamux | ✅ | 44s | - | - |
| python-v0.4 x python-v0.4 (ws, noise, yamux) | python-v0.4 | python-v0.4 | ws | noise | yamux | ✅ | 4s | - | - |
| python-v0.4 x python-v0.4 (wss, noise, mplex) | python-v0.4 | python-v0.4 | wss | noise | mplex | ✅ | 4s | - | - |
| python-v0.4 x python-v0.4 (wss, noise, yamux) | python-v0.4 | python-v0.4 | wss | noise | yamux | ✅ | 4s | - | - |
| python-v0.4 x python-v0.4 (quic-v1) | python-v0.4 | python-v0.4 | quic-v1 | - | - | ✅ | 4s | - | - |
| python-v0.4 x go-v0.44 (ws, noise, yamux) | python-v0.4 | go-v0.44 | ws | noise | yamux | ✅ | 45s | - | - |
| python-v0.4 x go-v0.44 (wss, noise, yamux) | python-v0.4 | go-v0.44 | wss | noise | yamux | ✅ | 44s | - | - |
| python-v0.4 x go-v0.45 (ws, noise, yamux) | python-v0.4 | go-v0.45 | ws | noise | yamux | ✅ | 43s | - | - |
| python-v0.4 x go-v0.45 (wss, noise, yamux) | python-v0.4 | go-v0.45 | wss | noise | yamux | ✅ | 44s | - | - |
| python-v0.4 x js-v1.x (tcp, noise, mplex) | python-v0.4 | js-v1.x | tcp | noise | mplex | ✅ | 16s | - | - |
| python-v0.4 x js-v1.x (tcp, noise, yamux) | python-v0.4 | js-v1.x | tcp | noise | yamux | ✅ | 16s | - | - |
| python-v0.4 x js-v2.x (tcp, noise, mplex) | python-v0.4 | js-v2.x | tcp | noise | mplex | ✅ | 17s | - | - |
| python-v0.4 x js-v2.x (tcp, noise, yamux) | python-v0.4 | js-v2.x | tcp | noise | yamux | ✅ | 17s | - | - |
| python-v0.4 x js-v3.x (tcp, noise, mplex) | python-v0.4 | js-v3.x | tcp | noise | mplex | ✅ | 13s | - | - |
| python-v0.4 x js-v1.x (ws, noise, mplex) | python-v0.4 | js-v1.x | ws | noise | mplex | ✅ | 29s | - | - |
| python-v0.4 x js-v1.x (ws, noise, yamux) | python-v0.4 | js-v1.x | ws | noise | yamux | ✅ | 28s | - | - |
| python-v0.4 x js-v3.x (tcp, noise, yamux) | python-v0.4 | js-v3.x | tcp | noise | yamux | ✅ | 13s | - | - |
| python-v0.4 x nim-v1.14 (tcp, noise, mplex) | python-v0.4 | nim-v1.14 | tcp | noise | mplex | ✅ | 3s | - | - |
| python-v0.4 x nim-v1.14 (tcp, noise, yamux) | python-v0.4 | nim-v1.14 | tcp | noise | yamux | ✅ | 4s | - | - |
| python-v0.4 x jvm-v1.2 (tcp, noise, mplex) | python-v0.4 | jvm-v1.2 | tcp | noise | mplex | ✅ | 4s | - | - |
| python-v0.4 x jvm-v1.2 (tcp, noise, yamux) | python-v0.4 | jvm-v1.2 | tcp | noise | yamux | ✅ | 5s | - | - |
| python-v0.4 x js-v2.x (ws, noise, mplex) | python-v0.4 | js-v2.x | ws | noise | mplex | ✅ | 195s | - | - |
| python-v0.4 x js-v2.x (ws, noise, yamux) | python-v0.4 | js-v2.x | ws | noise | yamux | ✅ | 196s | - | - |
| python-v0.4 x jvm-v1.2 (quic-v1) | python-v0.4 | jvm-v1.2 | quic-v1 | - | - | ✅ | 4s | - | - |
| python-v0.4 x c-v0.0.1 (tcp, noise, yamux) | python-v0.4 | c-v0.0.1 | tcp | noise | yamux | ✅ | 3s | - | - |
| python-v0.4 x js-v3.x (ws, noise, mplex) | python-v0.4 | js-v3.x | ws | noise | mplex | ✅ | 191s | - | - |
| python-v0.4 x js-v3.x (ws, noise, yamux) | python-v0.4 | js-v3.x | ws | noise | yamux | ✅ | 191s | - | - |
| python-v0.4 x nim-v1.14 (ws, noise, mplex) | python-v0.4 | nim-v1.14 | ws | noise | mplex | ✅ | 182s | - | - |
| python-v0.4 x nim-v1.14 (ws, noise, yamux) | python-v0.4 | nim-v1.14 | ws | noise | yamux | ✅ | 183s | - | - |
| python-v0.4 x c-v0.0.1 (quic-v1) | python-v0.4 | c-v0.0.1 | quic-v1 | - | - | ✅ | 3s | - | - |
| python-v0.4 x dotnet-v1.0 (tcp, noise, yamux) | python-v0.4 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 4s | - | - |
| python-v0.4 x eth-p2p-z-v0.0.1 (quic-v1) | python-v0.4 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 3s | - | - |
| js-v1.x x rust-v0.53 (tcp, noise, mplex) | js-v1.x | rust-v0.53 | tcp | noise | mplex | ✅ | 9s | 91 | 15 |
| python-v0.4 x jvm-v1.2 (ws, noise, mplex) | python-v0.4 | jvm-v1.2 | ws | noise | mplex | ✅ | 184s | - | - |
| js-v1.x x rust-v0.53 (tcp, noise, yamux) | js-v1.x | rust-v0.53 | tcp | noise | yamux | ✅ | 8s | 94 | 20 |
| python-v0.4 x jvm-v1.2 (ws, noise, yamux) | python-v0.4 | jvm-v1.2 | ws | noise | yamux | ✅ | 185s | - | - |
| js-v1.x x rust-v0.53 (ws, noise, mplex) | js-v1.x | rust-v0.53 | ws | noise | mplex | ✅ | 8s | 204 | 17 |
| js-v1.x x rust-v0.53 (ws, noise, yamux) | js-v1.x | rust-v0.53 | ws | noise | yamux | ✅ | 9s | 203 | 28 |
| js-v1.x x rust-v0.54 (tcp, noise, yamux) | js-v1.x | rust-v0.54 | tcp | noise | yamux | ✅ | 11s | 124 | 29 |
| js-v1.x x rust-v0.54 (tcp, noise, mplex) | js-v1.x | rust-v0.54 | tcp | noise | mplex | ✅ | 12s | 120 | 27 |
| js-v1.x x rust-v0.54 (ws, noise, mplex) | js-v1.x | rust-v0.54 | ws | noise | mplex | ✅ | 11s | 210 | 18 |
| js-v1.x x rust-v0.54 (ws, noise, yamux) | js-v1.x | rust-v0.54 | ws | noise | yamux | ✅ | 12s | 211 | 35 |
| js-v1.x x rust-v0.55 (tcp, noise, mplex) | js-v1.x | rust-v0.55 | tcp | noise | mplex | ✅ | 11s | 51 | 17 |
| js-v1.x x rust-v0.55 (tcp, noise, yamux) | js-v1.x | rust-v0.55 | tcp | noise | yamux | ✅ | 11s | 58 | 23 |
| python-v0.4 x c-v0.0.1 (tcp, noise, mplex) | python-v0.4 | c-v0.0.1 | tcp | noise | mplex | ✅ | 34s | - | - |
| js-v1.x x rust-v0.55 (ws, noise, mplex) | js-v1.x | rust-v0.55 | ws | noise | mplex | ✅ | 13s | 120 | 39 |
| python-v0.4 x zig-v0.0.1 (quic-v1) | python-v0.4 | zig-v0.0.1 | quic-v1 | - | - | ❌ | 36s | - | - |
| js-v1.x x rust-v0.55 (ws, noise, yamux) | js-v1.x | rust-v0.55 | ws | noise | yamux | ✅ | 14s | 118 | 42 |
| js-v1.x x rust-v0.56 (tcp, noise, yamux) | js-v1.x | rust-v0.56 | tcp | noise | yamux | ✅ | 14s | 72 | 30 |
| js-v1.x x rust-v0.56 (tcp, noise, mplex) | js-v1.x | rust-v0.56 | tcp | noise | mplex | ✅ | 15s | 69 | 27 |
| js-v1.x x rust-v0.56 (ws, noise, mplex) | js-v1.x | rust-v0.56 | ws | noise | mplex | ✅ | 15s | 112 | 38 |
| js-v1.x x rust-v0.56 (ws, noise, yamux) | js-v1.x | rust-v0.56 | ws | noise | yamux | ✅ | 14s | 100 | 34 |
| js-v1.x x go-v0.38 (tcp, noise, yamux) | js-v1.x | go-v0.38 | tcp | noise | yamux | ✅ | 12s | 58 | 19 |
| js-v1.x x go-v0.38 (ws, noise, yamux) | js-v1.x | go-v0.38 | ws | noise | yamux | ✅ | 15s | 157 | 46 |
| js-v1.x x go-v0.38 (wss, noise, yamux) | js-v1.x | go-v0.38 | wss | noise | yamux | ✅ | 17s | 189 | 36 |
| js-v1.x x go-v0.39 (tcp, noise, yamux) | js-v1.x | go-v0.39 | tcp | noise | yamux | ✅ | 17s | 100 | 39 |
| js-v1.x x go-v0.39 (ws, noise, yamux) | js-v1.x | go-v0.39 | ws | noise | yamux | ✅ | 17s | 106 | 34 |
| js-v1.x x go-v0.39 (wss, noise, yamux) | js-v1.x | go-v0.39 | wss | noise | yamux | ✅ | 16s | 195 | 34 |
| js-v1.x x go-v0.40 (ws, noise, yamux) | js-v1.x | go-v0.40 | ws | noise | yamux | ✅ | 17s | 67 | 18 |
| js-v1.x x go-v0.40 (tcp, noise, yamux) | js-v1.x | go-v0.40 | tcp | noise | yamux | ✅ | 17s | 55 | 18 |
| js-v1.x x go-v0.40 (wss, noise, yamux) | js-v1.x | go-v0.40 | wss | noise | yamux | ✅ | 17s | 134 | 28 |
| js-v1.x x go-v0.41 (tcp, noise, yamux) | js-v1.x | go-v0.41 | tcp | noise | yamux | ✅ | 17s | 129 | 45 |
| js-v1.x x go-v0.41 (ws, noise, yamux) | js-v1.x | go-v0.41 | ws | noise | yamux | ✅ | 17s | 142 | 50 |
| js-v1.x x go-v0.41 (wss, noise, yamux) | js-v1.x | go-v0.41 | wss | noise | yamux | ✅ | 18s | 215 | 42 |
| js-v1.x x go-v0.42 (ws, noise, yamux) | js-v1.x | go-v0.42 | ws | noise | yamux | ✅ | 18s | 130 | 50 |
| js-v1.x x go-v0.42 (tcp, noise, yamux) | js-v1.x | go-v0.42 | tcp | noise | yamux | ✅ | 19s | 97 | 31 |
| js-v1.x x go-v0.43 (tcp, noise, yamux) | js-v1.x | go-v0.43 | tcp | noise | yamux | ✅ | 18s | 117 | 38 |
| js-v1.x x go-v0.42 (wss, noise, yamux) | js-v1.x | go-v0.42 | wss | noise | yamux | ✅ | 19s | 171 | 35 |
| js-v1.x x go-v0.43 (ws, noise, yamux) | js-v1.x | go-v0.43 | ws | noise | yamux | ✅ | 18s | 55 | 19 |
| js-v1.x x go-v0.43 (wss, noise, yamux) | js-v1.x | go-v0.43 | wss | noise | yamux | ✅ | 17s | 255 | 45 |
| js-v1.x x go-v0.44 (tcp, noise, yamux) | js-v1.x | go-v0.44 | tcp | noise | yamux | ✅ | 18s | 114 | 40 |
| js-v1.x x go-v0.44 (ws, noise, yamux) | js-v1.x | go-v0.44 | ws | noise | yamux | ✅ | 18s | 124 | 45 |
| js-v1.x x go-v0.44 (wss, noise, yamux) | js-v1.x | go-v0.44 | wss | noise | yamux | ✅ | 19s | 204 | 40 |
| js-v1.x x go-v0.45 (ws, noise, yamux) | js-v1.x | go-v0.45 | ws | noise | yamux | ✅ | 18s | 127 | 39 |
| js-v1.x x go-v0.45 (tcp, noise, yamux) | js-v1.x | go-v0.45 | tcp | noise | yamux | ✅ | 19s | 127 | 40 |
| js-v1.x x go-v0.45 (wss, noise, yamux) | js-v1.x | go-v0.45 | wss | noise | yamux | ✅ | 18s | 215 | 25 |
| js-v1.x x python-v0.4 (tcp, noise, mplex) | js-v1.x | python-v0.4 | tcp | noise | mplex | ✅ | 19s | 76 | 31 |
| js-v1.x x python-v0.4 (tcp, noise, yamux) | js-v1.x | python-v0.4 | tcp | noise | yamux | ✅ | 22s | 142 | 57 |
| js-v1.x x python-v0.4 (ws, noise, mplex) | js-v1.x | python-v0.4 | ws | noise | mplex | ✅ | 24s | 163 | 50 |
| js-v1.x x python-v0.4 (ws, noise, yamux) | js-v1.x | python-v0.4 | ws | noise | yamux | ✅ | 24s | 181 | 57 |
| js-v1.x x python-v0.4 (wss, noise, mplex) | js-v1.x | python-v0.4 | wss | noise | mplex | ✅ | 24s | 275 | 52 |
| js-v1.x x python-v0.4 (wss, noise, yamux) | js-v1.x | python-v0.4 | wss | noise | yamux | ✅ | 25s | 249 | 56 |
| js-v1.x x js-v1.x (tcp, noise, mplex) | js-v1.x | js-v1.x | tcp | noise | mplex | ✅ | 25s | 160 | 60 |
| js-v1.x x js-v1.x (tcp, noise, yamux) | js-v1.x | js-v1.x | tcp | noise | yamux | ✅ | 25s | 153 | 36 |
| js-v1.x x js-v1.x (ws, noise, mplex) | js-v1.x | js-v1.x | ws | noise | mplex | ✅ | 25s | 189 | 54 |
| js-v1.x x js-v1.x (ws, noise, yamux) | js-v1.x | js-v1.x | ws | noise | yamux | ✅ | 30s | 432 | 130 |
| js-v1.x x js-v2.x (tcp, noise, mplex) | js-v1.x | js-v2.x | tcp | noise | mplex | ✅ | 35s | 237 | 103 |
| js-v1.x x js-v2.x (tcp, noise, yamux) | js-v1.x | js-v2.x | tcp | noise | yamux | ✅ | 35s | 331 | 114 |
| js-v1.x x js-v2.x (ws, noise, mplex) | js-v1.x | js-v2.x | ws | noise | mplex | ✅ | 36s | 331 | 84 |
| js-v1.x x js-v2.x (ws, noise, yamux) | js-v1.x | js-v2.x | ws | noise | yamux | ✅ | 37s | 303 | 102 |
| js-v1.x x js-v3.x (tcp, noise, mplex) | js-v1.x | js-v3.x | tcp | noise | mplex | ✅ | 36s | 212 | 54 |
| js-v1.x x js-v3.x (tcp, noise, yamux) | js-v1.x | js-v3.x | tcp | noise | yamux | ✅ | 35s | 193 | 53 |
| js-v1.x x js-v3.x (ws, noise, mplex) | js-v1.x | js-v3.x | ws | noise | mplex | ✅ | 35s | 238 | 96 |
| js-v1.x x js-v3.x (ws, noise, yamux) | js-v1.x | js-v3.x | ws | noise | yamux | ✅ | 25s | 341 | 91 |
| js-v1.x x nim-v1.14 (tcp, noise, mplex) | js-v1.x | nim-v1.14 | tcp | noise | mplex | ✅ | 25s | 295 | 79 |
| js-v1.x x nim-v1.14 (tcp, noise, yamux) | js-v1.x | nim-v1.14 | tcp | noise | yamux | ✅ | 24s | 284 | 65 |
| js-v1.x x nim-v1.14 (ws, noise, mplex) | js-v1.x | nim-v1.14 | ws | noise | mplex | ✅ | 23s | 383 | 69 |
| js-v1.x x nim-v1.14 (ws, noise, yamux) | js-v1.x | nim-v1.14 | ws | noise | yamux | ✅ | 25s | 297 | 53 |
| js-v1.x x jvm-v1.2 (tcp, noise, mplex) | js-v1.x | jvm-v1.2 | tcp | noise | mplex | ✅ | 24s | 948 | 65 |
| js-v1.x x jvm-v1.2 (tcp, noise, yamux) | js-v1.x | jvm-v1.2 | tcp | noise | yamux | ✅ | 24s | 789 | 80 |
| js-v1.x x jvm-v1.2 (ws, noise, mplex) | js-v1.x | jvm-v1.2 | ws | noise | mplex | ❌ | 29s | - | - |
| js-v1.x x jvm-v1.2 (ws, noise, yamux) | js-v1.x | jvm-v1.2 | ws | noise | yamux | ❌ | 23s | - | - |
| js-v1.x x c-v0.0.1 (tcp, noise, mplex) | js-v1.x | c-v0.0.1 | tcp | noise | mplex | ✅ | 18s | 115 | 24 |
| js-v1.x x c-v0.0.1 (tcp, noise, yamux) | js-v1.x | c-v0.0.1 | tcp | noise | yamux | ✅ | 19s | 188 | 96 |
| js-v1.x x dotnet-v1.0 (tcp, noise, yamux) | js-v1.x | dotnet-v1.0 | tcp | noise | yamux | ✅ | 19s | 426 | 113 |
| js-v2.x x rust-v0.53 (tcp, noise, mplex) | js-v2.x | rust-v0.53 | tcp | noise | mplex | ✅ | 20s | 179 | 44 |
| js-v2.x x rust-v0.53 (tcp, noise, yamux) | js-v2.x | rust-v0.53 | tcp | noise | yamux | ✅ | 20s | 204 | 47 |
| js-v2.x x rust-v0.53 (ws, noise, mplex) | js-v2.x | rust-v0.53 | ws | noise | mplex | ✅ | 20s | 317 | 87 |
| js-v2.x x rust-v0.53 (ws, noise, yamux) | js-v2.x | rust-v0.53 | ws | noise | yamux | ✅ | 19s | 363 | 90 |
| js-v2.x x rust-v0.54 (tcp, noise, mplex) | js-v2.x | rust-v0.54 | tcp | noise | mplex | ✅ | 21s | 205 | 49 |
| js-v2.x x rust-v0.54 (tcp, noise, yamux) | js-v2.x | rust-v0.54 | tcp | noise | yamux | ✅ | 22s | 210 | 47 |
| js-v2.x x rust-v0.54 (ws, noise, mplex) | js-v2.x | rust-v0.54 | ws | noise | mplex | ✅ | 21s | 397 | 104 |
| js-v2.x x rust-v0.54 (ws, noise, yamux) | js-v2.x | rust-v0.54 | ws | noise | yamux | ✅ | 22s | 333 | 98 |
| js-v2.x x rust-v0.55 (tcp, noise, mplex) | js-v2.x | rust-v0.55 | tcp | noise | mplex | ✅ | 21s | 127 | 38 |
| js-v2.x x rust-v0.55 (tcp, noise, yamux) | js-v2.x | rust-v0.55 | tcp | noise | yamux | ✅ | 21s | 131 | 46 |
| js-v2.x x rust-v0.55 (ws, noise, mplex) | js-v2.x | rust-v0.55 | ws | noise | mplex | ✅ | 20s | 148 | 44 |
| js-v2.x x rust-v0.55 (ws, noise, yamux) | js-v2.x | rust-v0.55 | ws | noise | yamux | ✅ | 20s | 223 | 52 |
| js-v2.x x rust-v0.56 (tcp, noise, mplex) | js-v2.x | rust-v0.56 | tcp | noise | mplex | ✅ | 22s | 147 | 48 |
| js-v2.x x rust-v0.56 (tcp, noise, yamux) | js-v2.x | rust-v0.56 | tcp | noise | yamux | ✅ | 21s | 185 | 74 |
| js-v2.x x rust-v0.56 (ws, noise, mplex) | js-v2.x | rust-v0.56 | ws | noise | mplex | ✅ | 22s | 159 | 50 |
| js-v2.x x rust-v0.56 (ws, noise, yamux) | js-v2.x | rust-v0.56 | ws | noise | yamux | ✅ | 23s | 197 | 48 |
| js-v2.x x go-v0.38 (tcp, noise, yamux) | js-v2.x | go-v0.38 | tcp | noise | yamux | ✅ | 22s | 139 | 59 |
| js-v2.x x go-v0.38 (ws, noise, yamux) | js-v2.x | go-v0.38 | ws | noise | yamux | ✅ | 21s | 147 | 49 |
| js-v2.x x go-v0.38 (wss, noise, yamux) | js-v2.x | go-v0.38 | wss | noise | yamux | ✅ | 21s | 231 | 51 |
| js-v2.x x go-v0.39 (tcp, noise, yamux) | js-v2.x | go-v0.39 | tcp | noise | yamux | ✅ | 19s | 170 | 70 |
| js-v2.x x go-v0.39 (ws, noise, yamux) | js-v2.x | go-v0.39 | ws | noise | yamux | ✅ | 21s | 178 | 56 |
| js-v2.x x go-v0.39 (wss, noise, yamux) | js-v2.x | go-v0.39 | wss | noise | yamux | ✅ | 22s | 272 | 61 |
| js-v2.x x go-v0.40 (tcp, noise, yamux) | js-v2.x | go-v0.40 | tcp | noise | yamux | ✅ | 21s | 208 | 67 |
| js-v2.x x go-v0.40 (ws, noise, yamux) | js-v2.x | go-v0.40 | ws | noise | yamux | ✅ | 21s | 150 | 52 |
| js-v2.x x go-v0.40 (wss, noise, yamux) | js-v2.x | go-v0.40 | wss | noise | yamux | ✅ | 21s | 275 | 54 |
| js-v2.x x go-v0.41 (tcp, noise, yamux) | js-v2.x | go-v0.41 | tcp | noise | yamux | ✅ | 22s | 124 | 49 |
| js-v2.x x go-v0.41 (ws, noise, yamux) | js-v2.x | go-v0.41 | ws | noise | yamux | ✅ | 21s | 153 | 41 |
| js-v2.x x go-v0.41 (wss, noise, yamux) | js-v2.x | go-v0.41 | wss | noise | yamux | ✅ | 20s | 280 | 54 |
| js-v2.x x go-v0.42 (tcp, noise, yamux) | js-v2.x | go-v0.42 | tcp | noise | yamux | ✅ | 22s | 163 | 54 |
| js-v2.x x go-v0.42 (ws, noise, yamux) | js-v2.x | go-v0.42 | ws | noise | yamux | ✅ | 22s | 194 | 61 |
| js-v2.x x go-v0.43 (tcp, noise, yamux) | js-v2.x | go-v0.43 | tcp | noise | yamux | ✅ | 22s | 150 | 54 |
| js-v2.x x go-v0.42 (wss, noise, yamux) | js-v2.x | go-v0.42 | wss | noise | yamux | ✅ | 23s | 277 | 54 |
| js-v2.x x go-v0.43 (ws, noise, yamux) | js-v2.x | go-v0.43 | ws | noise | yamux | ✅ | 22s | 157 | 55 |
| js-v2.x x go-v0.43 (wss, noise, yamux) | js-v2.x | go-v0.43 | wss | noise | yamux | ✅ | 22s | 247 | 51 |
| js-v2.x x go-v0.44 (tcp, noise, yamux) | js-v2.x | go-v0.44 | tcp | noise | yamux | ✅ | 22s | 127 | 49 |
| js-v2.x x go-v0.44 (ws, noise, yamux) | js-v2.x | go-v0.44 | ws | noise | yamux | ✅ | 21s | 137 | 55 |
| js-v2.x x go-v0.44 (wss, noise, yamux) | js-v2.x | go-v0.44 | wss | noise | yamux | ✅ | 22s | 283 | 61 |
| js-v2.x x go-v0.45 (tcp, noise, yamux) | js-v2.x | go-v0.45 | tcp | noise | yamux | ✅ | 23s | 235 | 63 |
| js-v2.x x go-v0.45 (ws, noise, yamux) | js-v2.x | go-v0.45 | ws | noise | yamux | ✅ | 22s | 209 | 54 |
| js-v2.x x go-v0.45 (wss, noise, yamux) | js-v2.x | go-v0.45 | wss | noise | yamux | ✅ | 23s | 279 | 58 |
| js-v2.x x python-v0.4 (tcp, noise, mplex) | js-v2.x | python-v0.4 | tcp | noise | mplex | ✅ | 23s | 117 | 39 |
| js-v2.x x python-v0.4 (tcp, noise, yamux) | js-v2.x | python-v0.4 | tcp | noise | yamux | ✅ | 23s | 145 | 46 |
| js-v2.x x python-v0.4 (ws, noise, mplex) | js-v2.x | python-v0.4 | ws | noise | mplex | ✅ | 22s | 142 | 43 |
| js-v2.x x python-v0.4 (ws, noise, yamux) | js-v2.x | python-v0.4 | ws | noise | yamux | ✅ | 22s | 213 | 69 |
| js-v2.x x python-v0.4 (wss, noise, mplex) | js-v2.x | python-v0.4 | wss | noise | mplex | ✅ | 32s | 525 | 92 |
| js-v2.x x python-v0.4 (wss, noise, yamux) | js-v2.x | python-v0.4 | wss | noise | yamux | ✅ | 34s | 447 | 90 |
| js-v2.x x js-v1.x (tcp, noise, mplex) | js-v2.x | js-v1.x | tcp | noise | mplex | ✅ | 35s | 230 | 68 |
| js-v2.x x js-v1.x (tcp, noise, yamux) | js-v2.x | js-v1.x | tcp | noise | yamux | ✅ | 37s | 314 | 113 |
| js-v2.x x js-v1.x (ws, noise, mplex) | js-v2.x | js-v1.x | ws | noise | mplex | ✅ | 36s | 322 | 108 |
| js-v2.x x js-v1.x (ws, noise, yamux) | js-v2.x | js-v1.x | ws | noise | yamux | ✅ | 36s | 329 | 84 |
| js-v2.x x js-v2.x (tcp, noise, mplex) | js-v2.x | js-v2.x | tcp | noise | mplex | ✅ | 36s | 206 | 93 |
| js-v2.x x js-v2.x (tcp, noise, yamux) | js-v2.x | js-v2.x | tcp | noise | yamux | ✅ | 35s | 173 | 57 |
| js-v2.x x js-v2.x (ws, noise, mplex) | js-v2.x | js-v2.x | ws | noise | mplex | ✅ | 33s | 414 | 123 |
| js-v2.x x js-v2.x (ws, noise, yamux) | js-v2.x | js-v2.x | ws | noise | yamux | ✅ | 35s | 354 | 119 |
| js-v2.x x js-v3.x (tcp, noise, yamux) | js-v2.x | js-v3.x | tcp | noise | yamux | ✅ | 34s | 299 | 124 |
| js-v2.x x js-v3.x (tcp, noise, mplex) | js-v2.x | js-v3.x | tcp | noise | mplex | ✅ | 35s | 232 | 78 |
| js-v2.x x nim-v1.14 (tcp, noise, mplex) | js-v2.x | nim-v1.14 | tcp | noise | mplex | ✅ | 33s | 220 | 42 |
| js-v2.x x js-v3.x (ws, noise, mplex) | js-v2.x | js-v3.x | ws | noise | mplex | ✅ | 36s | 169 | 47 |
| js-v2.x x js-v3.x (ws, noise, yamux) | js-v2.x | js-v3.x | ws | noise | yamux | ✅ | 35s | 199 | 68 |
| js-v2.x x nim-v1.14 (tcp, noise, yamux) | js-v2.x | nim-v1.14 | tcp | noise | yamux | ✅ | 34s | 189 | 22 |
| js-v2.x x nim-v1.14 (ws, noise, mplex) | js-v2.x | nim-v1.14 | ws | noise | mplex | ✅ | 27s | 361 | 60 |
| js-v2.x x nim-v1.14 (ws, noise, yamux) | js-v2.x | nim-v1.14 | ws | noise | yamux | ✅ | 25s | 392 | 73 |
| js-v2.x x jvm-v1.2 (tcp, noise, mplex) | js-v2.x | jvm-v1.2 | tcp | noise | mplex | ✅ | 26s | 1418 | 90 |
| js-v2.x x jvm-v1.2 (tcp, noise, yamux) | js-v2.x | jvm-v1.2 | tcp | noise | yamux | ✅ | 26s | 1139 | 134 |
| js-v2.x x c-v0.0.1 (tcp, noise, mplex) | js-v2.x | c-v0.0.1 | tcp | noise | mplex | ✅ | 25s | 139 | 23 |
| js-v2.x x jvm-v1.2 (ws, noise, mplex) | js-v2.x | jvm-v1.2 | ws | noise | mplex | ✅ | 29s | 1620 | 401 |
| js-v2.x x c-v0.0.1 (tcp, noise, yamux) | js-v2.x | c-v0.0.1 | tcp | noise | yamux | ✅ | 25s | 193 | 108 |
| js-v2.x x jvm-v1.2 (ws, noise, yamux) | js-v2.x | jvm-v1.2 | ws | noise | yamux | ✅ | 28s | 1945 | 308 |
| js-v2.x x dotnet-v1.0 (tcp, noise, yamux) | js-v2.x | dotnet-v1.0 | tcp | noise | yamux | ✅ | 21s | 432 | 116 |
| js-v3.x x rust-v0.53 (tcp, noise, mplex) | js-v3.x | rust-v0.53 | tcp | noise | mplex | ✅ | 19s | 195 | 11 |
| js-v3.x x rust-v0.53 (tcp, noise, yamux) | js-v3.x | rust-v0.53 | tcp | noise | yamux | ✅ | 22s | 228 | 4 |
| js-v3.x x rust-v0.53 (ws, noise, mplex) | js-v3.x | rust-v0.53 | ws | noise | mplex | ✅ | 22s | 305 | 6 |
| js-v3.x x rust-v0.53 (ws, noise, yamux) | js-v3.x | rust-v0.53 | ws | noise | yamux | ✅ | 22s | 224 | 6 |
| js-v3.x x rust-v0.54 (tcp, noise, mplex) | js-v3.x | rust-v0.54 | tcp | noise | mplex | ✅ | 21s | 160 | 5 |
| js-v3.x x rust-v0.54 (tcp, noise, yamux) | js-v3.x | rust-v0.54 | tcp | noise | yamux | ✅ | 21s | 160 | 4 |
| js-v3.x x rust-v0.54 (ws, noise, mplex) | js-v3.x | rust-v0.54 | ws | noise | mplex | ✅ | 21s | 192 | 4 |
| js-v3.x x rust-v0.54 (ws, noise, yamux) | js-v3.x | rust-v0.54 | ws | noise | yamux | ✅ | 19s | 286 | 5 |
| js-v3.x x rust-v0.55 (tcp, noise, mplex) | js-v3.x | rust-v0.55 | tcp | noise | mplex | ✅ | 21s | 130 | 17 |
| js-v3.x x rust-v0.55 (tcp, noise, yamux) | js-v3.x | rust-v0.55 | tcp | noise | yamux | ✅ | 21s | 143 | 6 |
| js-v3.x x rust-v0.55 (ws, noise, mplex) | js-v3.x | rust-v0.55 | ws | noise | mplex | ✅ | 22s | 151 | 9 |
| js-v3.x x rust-v0.55 (ws, noise, yamux) | js-v3.x | rust-v0.55 | ws | noise | yamux | ✅ | 22s | 144 | 5 |
| js-v3.x x rust-v0.56 (tcp, noise, mplex) | js-v3.x | rust-v0.56 | tcp | noise | mplex | ✅ | 21s | 136 | 15 |
| js-v3.x x rust-v0.56 (tcp, noise, yamux) | js-v3.x | rust-v0.56 | tcp | noise | yamux | ✅ | 21s | 116 | 16 |
| js-v3.x x rust-v0.56 (ws, noise, mplex) | js-v3.x | rust-v0.56 | ws | noise | mplex | ✅ | 20s | 132 | 5 |
| js-v3.x x rust-v0.56 (ws, noise, yamux) | js-v3.x | rust-v0.56 | ws | noise | yamux | ✅ | 19s | 209 | 24 |
| js-v3.x x go-v0.38 (tcp, noise, yamux) | js-v3.x | go-v0.38 | tcp | noise | yamux | ✅ | 21s | 143 | 19 |
| js-v3.x x go-v0.38 (ws, noise, yamux) | js-v3.x | go-v0.38 | ws | noise | yamux | ✅ | 22s | 182 | 14 |
| js-v3.x x go-v0.38 (wss, noise, yamux) | js-v3.x | go-v0.38 | wss | noise | yamux | ✅ | 22s | 255 | 33 |
| js-v3.x x go-v0.39 (tcp, noise, yamux) | js-v3.x | go-v0.39 | tcp | noise | yamux | ✅ | 22s | 123 | 12 |
| js-v3.x x go-v0.39 (ws, noise, yamux) | js-v3.x | go-v0.39 | ws | noise | yamux | ✅ | 22s | 139 | 16 |
| js-v3.x x go-v0.40 (tcp, noise, yamux) | js-v3.x | go-v0.40 | tcp | noise | yamux | ✅ | 22s | 138 | 12 |
| js-v3.x x go-v0.39 (wss, noise, yamux) | js-v3.x | go-v0.39 | wss | noise | yamux | ✅ | 22s | 222 | 16 |
| js-v3.x x go-v0.40 (ws, noise, yamux) | js-v3.x | go-v0.40 | ws | noise | yamux | ✅ | 20s | 203 | 15 |
| js-v3.x x go-v0.40 (wss, noise, yamux) | js-v3.x | go-v0.40 | wss | noise | yamux | ✅ | 20s | 244 | 21 |
| js-v3.x x go-v0.41 (tcp, noise, yamux) | js-v3.x | go-v0.41 | tcp | noise | yamux | ✅ | 21s | 127 | 2 |
| js-v3.x x go-v0.41 (ws, noise, yamux) | js-v3.x | go-v0.41 | ws | noise | yamux | ✅ | 22s | 181 | 20 |
| js-v3.x x go-v0.41 (wss, noise, yamux) | js-v3.x | go-v0.41 | wss | noise | yamux | ✅ | 21s | 233 | 34 |
| js-v3.x x go-v0.42 (tcp, noise, yamux) | js-v3.x | go-v0.42 | tcp | noise | yamux | ✅ | 22s | 134 | 16 |
| js-v3.x x go-v0.42 (ws, noise, yamux) | js-v3.x | go-v0.42 | ws | noise | yamux | ✅ | 21s | 151 | 3 |
| js-v3.x x go-v0.42 (wss, noise, yamux) | js-v3.x | go-v0.42 | wss | noise | yamux | ✅ | 21s | 245 | 3 |
| js-v3.x x go-v0.43 (tcp, noise, yamux) | js-v3.x | go-v0.43 | tcp | noise | yamux | ✅ | 20s | 154 | 13 |
| js-v3.x x go-v0.43 (ws, noise, yamux) | js-v3.x | go-v0.43 | ws | noise | yamux | ✅ | 20s | 169 | 16 |
| js-v3.x x go-v0.43 (wss, noise, yamux) | js-v3.x | go-v0.43 | wss | noise | yamux | ✅ | 21s | 238 | 32 |
| js-v3.x x go-v0.44 (tcp, noise, yamux) | js-v3.x | go-v0.44 | tcp | noise | yamux | ✅ | 22s | 128 | 15 |
| js-v3.x x go-v0.44 (ws, noise, yamux) | js-v3.x | go-v0.44 | ws | noise | yamux | ✅ | 22s | 147 | 15 |
| js-v3.x x go-v0.44 (wss, noise, yamux) | js-v3.x | go-v0.44 | wss | noise | yamux | ✅ | 22s | 244 | 31 |
| js-v3.x x go-v0.45 (tcp, noise, yamux) | js-v3.x | go-v0.45 | tcp | noise | yamux | ✅ | 21s | 143 | 12 |
| js-v3.x x go-v0.45 (ws, noise, yamux) | js-v3.x | go-v0.45 | ws | noise | yamux | ✅ | 22s | 142 | 13 |
| js-v3.x x go-v0.45 (wss, noise, yamux) | js-v3.x | go-v0.45 | wss | noise | yamux | ✅ | 21s | 264 | 2 |
| js-v3.x x python-v0.4 (tcp, noise, mplex) | js-v3.x | python-v0.4 | tcp | noise | mplex | ✅ | 21s | 139 | 4 |
| js-v3.x x python-v0.4 (tcp, noise, yamux) | js-v3.x | python-v0.4 | tcp | noise | yamux | ✅ | 27s | 164 | 7 |
| js-v3.x x python-v0.4 (ws, noise, mplex) | js-v3.x | python-v0.4 | ws | noise | mplex | ✅ | 26s | 184 | 7 |
| js-v3.x x python-v0.4 (ws, noise, yamux) | js-v3.x | python-v0.4 | ws | noise | yamux | ✅ | 27s | 179 | 5 |
| js-v3.x x python-v0.4 (wss, noise, mplex) | js-v3.x | python-v0.4 | wss | noise | mplex | ✅ | 28s | 261 | 6 |
| js-v3.x x python-v0.4 (wss, noise, yamux) | js-v3.x | python-v0.4 | wss | noise | yamux | ✅ | 28s | 268 | 6 |
| js-v3.x x js-v1.x (tcp, noise, mplex) | js-v3.x | js-v1.x | tcp | noise | mplex | ✅ | 27s | 193 | 7 |
| js-v3.x x js-v1.x (tcp, noise, yamux) | js-v3.x | js-v1.x | tcp | noise | yamux | ✅ | 28s | 260 | 10 |
| js-v3.x x js-v1.x (ws, noise, mplex) | js-v3.x | js-v1.x | ws | noise | mplex | ✅ | 30s | 411 | 38 |
| js-v3.x x js-v1.x (ws, noise, yamux) | js-v3.x | js-v1.x | ws | noise | yamux | ✅ | 38s | 436 | 18 |
| js-v3.x x js-v2.x (tcp, noise, mplex) | js-v3.x | js-v2.x | tcp | noise | mplex | ✅ | 40s | 277 | 6 |
| js-v3.x x js-v2.x (tcp, noise, yamux) | js-v3.x | js-v2.x | tcp | noise | yamux | ✅ | 41s | 255 | 44 |
| js-v3.x x js-v2.x (ws, noise, mplex) | js-v3.x | js-v2.x | ws | noise | mplex | ✅ | 41s | 262 | 14 |
| js-v3.x x js-v2.x (ws, noise, yamux) | js-v3.x | js-v2.x | ws | noise | yamux | ✅ | 40s | 370 | 7 |
| js-v3.x x js-v3.x (tcp, noise, mplex) | js-v3.x | js-v3.x | tcp | noise | mplex | ✅ | 40s | 209 | 5 |
| js-v3.x x js-v3.x (tcp, noise, yamux) | js-v3.x | js-v3.x | tcp | noise | yamux | ✅ | 37s | 215 | 41 |
| js-v3.x x js-v3.x (ws, noise, mplex) | js-v3.x | js-v3.x | ws | noise | mplex | ✅ | 33s | 272 | 16 |
| js-v3.x x js-v3.x (ws, noise, yamux) | js-v3.x | js-v3.x | ws | noise | yamux | ✅ | 28s | 238 | 11 |
| js-v3.x x nim-v1.14 (tcp, noise, mplex) | js-v3.x | nim-v1.14 | tcp | noise | mplex | ✅ | 27s | 251 | 5 |
| js-v3.x x nim-v1.14 (tcp, noise, yamux) | js-v3.x | nim-v1.14 | tcp | noise | yamux | ✅ | 25s | 264 | 5 |
| js-v3.x x nim-v1.14 (ws, noise, mplex) | js-v3.x | nim-v1.14 | ws | noise | mplex | ✅ | 27s | 263 | 11 |
| js-v3.x x nim-v1.14 (ws, noise, yamux) | js-v3.x | nim-v1.14 | ws | noise | yamux | ✅ | 26s | 258 | 7 |
| js-v3.x x jvm-v1.2 (tcp, noise, mplex) | js-v3.x | jvm-v1.2 | tcp | noise | mplex | ✅ | 27s | 955 | 4 |
| js-v3.x x jvm-v1.2 (tcp, noise, yamux) | js-v3.x | jvm-v1.2 | tcp | noise | yamux | ✅ | 28s | 1358 | 148 |
| js-v3.x x jvm-v1.2 (ws, noise, mplex) | js-v3.x | jvm-v1.2 | ws | noise | mplex | ✅ | 25s | 1269 | 7 |
| nim-v1.14 x rust-v0.53 (tcp, noise, mplex) | nim-v1.14 | rust-v0.53 | tcp | noise | mplex | ✅ | 5s | 291.0 | 4.0 |
| nim-v1.14 x rust-v0.53 (tcp, noise, yamux) | nim-v1.14 | rust-v0.53 | tcp | noise | yamux | ✅ | 4s | 320.0 | 3.0 |
| nim-v1.14 x rust-v0.53 (ws, noise, mplex) | nim-v1.14 | rust-v0.53 | ws | noise | mplex | ✅ | 5s | 464.0 | 43.0 |
| nim-v1.14 x rust-v0.53 (ws, noise, yamux) | nim-v1.14 | rust-v0.53 | ws | noise | yamux | ✅ | 5s | 450.0 | 43.0 |
| nim-v1.14 x rust-v0.54 (tcp, noise, mplex) | nim-v1.14 | rust-v0.54 | tcp | noise | mplex | ✅ | 5s | 285.0 | 2.0 |
| nim-v1.14 x rust-v0.54 (tcp, noise, yamux) | nim-v1.14 | rust-v0.54 | tcp | noise | yamux | ✅ | 5s | 319.0 | 3.0 |
| nim-v1.14 x rust-v0.54 (ws, noise, mplex) | nim-v1.14 | rust-v0.54 | ws | noise | mplex | ✅ | 6s | 454.0 | 43.0 |
| js-v3.x x c-v0.0.1 (tcp, noise, mplex) | js-v3.x | c-v0.0.1 | tcp | noise | mplex | ✅ | 19s | 130 | 3 |
| js-v3.x x jvm-v1.2 (ws, noise, yamux) | js-v3.x | jvm-v1.2 | ws | noise | yamux | ✅ | 21s | 1495 | 109 |
| nim-v1.14 x rust-v0.54 (ws, noise, yamux) | nim-v1.14 | rust-v0.54 | ws | noise | yamux | ✅ | 5s | 470.0 | 44.0 |
| js-v3.x x c-v0.0.1 (tcp, noise, yamux) | js-v3.x | c-v0.0.1 | tcp | noise | yamux | ✅ | 20s | 176 | 11 |
| nim-v1.14 x rust-v0.55 (tcp, noise, mplex) | nim-v1.14 | rust-v0.55 | tcp | noise | mplex | ✅ | 5s | 184.0 | 0.0 |
| js-v3.x x dotnet-v1.0 (tcp, noise, yamux) | js-v3.x | dotnet-v1.0 | tcp | noise | yamux | ✅ | 18s | 298 | 19 |
| nim-v1.14 x rust-v0.55 (tcp, noise, yamux) | nim-v1.14 | rust-v0.55 | tcp | noise | yamux | ✅ | 5s | 183.0 | 0.0 |
| nim-v1.14 x rust-v0.55 (ws, noise, mplex) | nim-v1.14 | rust-v0.55 | ws | noise | mplex | ✅ | 4s | 187.0 | 42.0 |
| nim-v1.14 x rust-v0.55 (ws, noise, yamux) | nim-v1.14 | rust-v0.55 | ws | noise | yamux | ✅ | 4s | 197.0 | 0.0 |
| nim-v1.14 x rust-v0.56 (tcp, noise, mplex) | nim-v1.14 | rust-v0.56 | tcp | noise | mplex | ✅ | 5s | 151.0 | 0.0 |
| nim-v1.14 x rust-v0.56 (tcp, noise, yamux) | nim-v1.14 | rust-v0.56 | tcp | noise | yamux | ✅ | 5s | 178.0 | 0.0 |
| nim-v1.14 x rust-v0.56 (ws, noise, mplex) | nim-v1.14 | rust-v0.56 | ws | noise | mplex | ✅ | 5s | 187.0 | 42.0 |
| nim-v1.14 x rust-v0.56 (ws, noise, yamux) | nim-v1.14 | rust-v0.56 | ws | noise | yamux | ✅ | 5s | 182.0 | 0.0 |
| nim-v1.14 x go-v0.38 (tcp, noise, yamux) | nim-v1.14 | go-v0.38 | tcp | noise | yamux | ✅ | 4s | 199.0 | 0.0 |
| nim-v1.14 x go-v0.38 (ws, noise, yamux) | nim-v1.14 | go-v0.38 | ws | noise | yamux | ✅ | 5s | 243.0 | 0.0 |
| nim-v1.14 x go-v0.39 (tcp, noise, yamux) | nim-v1.14 | go-v0.39 | tcp | noise | yamux | ✅ | 5s | 198.0 | 0.0 |
| nim-v1.14 x go-v0.39 (ws, noise, yamux) | nim-v1.14 | go-v0.39 | ws | noise | yamux | ✅ | 4s | 241.0 | 0.0 |
| nim-v1.14 x go-v0.40 (tcp, noise, yamux) | nim-v1.14 | go-v0.40 | tcp | noise | yamux | ✅ | 4s | 205.0 | 0.0 |
| nim-v1.14 x go-v0.40 (ws, noise, yamux) | nim-v1.14 | go-v0.40 | ws | noise | yamux | ✅ | 5s | 248.0 | 0.0 |
| nim-v1.14 x go-v0.41 (tcp, noise, yamux) | nim-v1.14 | go-v0.41 | tcp | noise | yamux | ✅ | 5s | 148.0 | 0.0 |
| nim-v1.14 x go-v0.41 (ws, noise, yamux) | nim-v1.14 | go-v0.41 | ws | noise | yamux | ✅ | 5s | 250.0 | 0.0 |
| nim-v1.14 x go-v0.42 (tcp, noise, yamux) | nim-v1.14 | go-v0.42 | tcp | noise | yamux | ✅ | 5s | 139.0 | 0.0 |
| nim-v1.14 x go-v0.42 (ws, noise, yamux) | nim-v1.14 | go-v0.42 | ws | noise | yamux | ✅ | 4s | 247.0 | 0.0 |
| nim-v1.14 x go-v0.43 (tcp, noise, yamux) | nim-v1.14 | go-v0.43 | tcp | noise | yamux | ✅ | 5s | 192.0 | 0.0 |
| nim-v1.14 x go-v0.43 (ws, noise, yamux) | nim-v1.14 | go-v0.43 | ws | noise | yamux | ✅ | 5s | 248.0 | 0.0 |
| nim-v1.14 x go-v0.44 (tcp, noise, yamux) | nim-v1.14 | go-v0.44 | tcp | noise | yamux | ✅ | 6s | 194.0 | 1.0 |
| nim-v1.14 x go-v0.44 (ws, noise, yamux) | nim-v1.14 | go-v0.44 | ws | noise | yamux | ✅ | 5s | 259.0 | 0.0 |
| nim-v1.14 x go-v0.45 (tcp, noise, yamux) | nim-v1.14 | go-v0.45 | tcp | noise | yamux | ✅ | 5s | 144.0 | 0.0 |
| nim-v1.14 x go-v0.45 (ws, noise, yamux) | nim-v1.14 | go-v0.45 | ws | noise | yamux | ✅ | 5s | 253.0 | 0.0 |
| nim-v1.14 x python-v0.4 (tcp, noise, mplex) | nim-v1.14 | python-v0.4 | tcp | noise | mplex | ✅ | 6s | 156.0 | 1.0 |
| nim-v1.14 x python-v0.4 (tcp, noise, yamux) | nim-v1.14 | python-v0.4 | tcp | noise | yamux | ✅ | 5s | 181.0 | 2.0 |
| nim-v1.14 x python-v0.4 (ws, noise, mplex) | nim-v1.14 | python-v0.4 | ws | noise | mplex | ✅ | 5s | 218.0 | 1.0 |
| nim-v1.14 x python-v0.4 (ws, noise, yamux) | nim-v1.14 | python-v0.4 | ws | noise | yamux | ✅ | 5s | 221.0 | 2.0 |
| nim-v1.14 x js-v1.x (tcp, noise, mplex) | nim-v1.14 | js-v1.x | tcp | noise | mplex | ✅ | 21s | 293.0 | 1.0 |
| nim-v1.14 x js-v1.x (ws, noise, mplex) | nim-v1.14 | js-v1.x | ws | noise | mplex | ✅ | 21s | 313.0 | 2.0 |
| nim-v1.14 x js-v1.x (tcp, noise, yamux) | nim-v1.14 | js-v1.x | tcp | noise | yamux | ✅ | 22s | 279.0 | 3.0 |
| nim-v1.14 x js-v1.x (ws, noise, yamux) | nim-v1.14 | js-v1.x | ws | noise | yamux | ✅ | 22s | 287.0 | 3.0 |
| nim-v1.14 x js-v2.x (tcp, noise, mplex) | nim-v1.14 | js-v2.x | tcp | noise | mplex | ✅ | 21s | 260.0 | 2.0 |
| nim-v1.14 x js-v2.x (tcp, noise, yamux) | nim-v1.14 | js-v2.x | tcp | noise | yamux | ✅ | 22s | 286.0 | 3.0 |
| nim-v1.14 x js-v2.x (ws, noise, mplex) | nim-v1.14 | js-v2.x | ws | noise | mplex | ✅ | 22s | 336.0 | 2.0 |
| nim-v1.14 x js-v2.x (ws, noise, yamux) | nim-v1.14 | js-v2.x | ws | noise | yamux | ✅ | 21s | 289.0 | 4.0 |
| nim-v1.14 x nim-v1.14 (tcp, noise, mplex) | nim-v1.14 | nim-v1.14 | tcp | noise | mplex | ✅ | 5s | 388.0 | 1.0 |
| nim-v1.14 x nim-v1.14 (tcp, noise, yamux) | nim-v1.14 | nim-v1.14 | tcp | noise | yamux | ✅ | 5s | 385.0 | 1.0 |
| nim-v1.14 x nim-v1.14 (ws, noise, mplex) | nim-v1.14 | nim-v1.14 | ws | noise | mplex | ✅ | 5s | 386.0 | 1.0 |
| nim-v1.14 x nim-v1.14 (ws, noise, yamux) | nim-v1.14 | nim-v1.14 | ws | noise | yamux | ✅ | 5s | 391.0 | 1.0 |
| nim-v1.14 x js-v3.x (tcp, noise, mplex) | nim-v1.14 | js-v3.x | tcp | noise | mplex | ✅ | 19s | 280.0 | 6.0 |
| nim-v1.14 x jvm-v1.2 (tcp, noise, mplex) | nim-v1.14 | jvm-v1.2 | tcp | noise | mplex | ✅ | 10s | 1515.0 | 5.0 |
| nim-v1.14 x js-v3.x (tcp, noise, yamux) | nim-v1.14 | js-v3.x | tcp | noise | yamux | ✅ | 20s | 214.0 | 4.0 |
| nim-v1.14 x jvm-v1.2 (tcp, noise, yamux) | nim-v1.14 | jvm-v1.2 | tcp | noise | yamux | ✅ | 12s | 1306.0 | 7.0 |
| nim-v1.14 x js-v3.x (ws, noise, mplex) | nim-v1.14 | js-v3.x | ws | noise | mplex | ✅ | 21s | 326.0 | 10.0 |
| nim-v1.14 x js-v3.x (ws, noise, yamux) | nim-v1.14 | js-v3.x | ws | noise | yamux | ✅ | 20s | 341.0 | 6.0 |
| nim-v1.14 x jvm-v1.2 (ws, noise, mplex) | nim-v1.14 | jvm-v1.2 | ws | noise | mplex | ✅ | 12s | 1313.0 | 4.0 |
| nim-v1.14 x jvm-v1.2 (ws, noise, yamux) | nim-v1.14 | jvm-v1.2 | ws | noise | yamux | ✅ | 11s | 1046.0 | 2.0 |
| nim-v1.14 x c-v0.0.1 (tcp, noise, mplex) | nim-v1.14 | c-v0.0.1 | tcp | noise | mplex | ✅ | 5s | 184.0 | 0.0 |
| nim-v1.14 x c-v0.0.1 (tcp, noise, yamux) | nim-v1.14 | c-v0.0.1 | tcp | noise | yamux | ✅ | 4s | 295.0 | 1.0 |
| nim-v1.14 x dotnet-v1.0 (tcp, noise, yamux) | nim-v1.14 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 5s | 430.0 | 5.0 |
| jvm-v1.2 x rust-v0.53 (tcp, noise, mplex) | jvm-v1.2 | rust-v0.53 | tcp | noise | mplex | ✅ | 14s | - | - |
| jvm-v1.2 x rust-v0.53 (tcp, noise, yamux) | jvm-v1.2 | rust-v0.53 | tcp | noise | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x rust-v0.53 (tcp, tls, mplex) | jvm-v1.2 | rust-v0.53 | tcp | tls | mplex | ✅ | 17s | - | - |
| jvm-v1.2 x rust-v0.53 (tcp, tls, yamux) | jvm-v1.2 | rust-v0.53 | tcp | tls | yamux | ✅ | 18s | - | - |
| jvm-v1.2 x rust-v0.53 (ws, noise, mplex) | jvm-v1.2 | rust-v0.53 | ws | noise | mplex | ✅ | 15s | - | - |
| jvm-v1.2 x rust-v0.53 (ws, noise, yamux) | jvm-v1.2 | rust-v0.53 | ws | noise | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x rust-v0.53 (ws, tls, yamux) | jvm-v1.2 | rust-v0.53 | ws | tls | yamux | ✅ | 18s | - | - |
| jvm-v1.2 x rust-v0.53 (ws, tls, mplex) | jvm-v1.2 | rust-v0.53 | ws | tls | mplex | ✅ | 19s | - | - |
| jvm-v1.2 x rust-v0.53 (quic-v1) | jvm-v1.2 | rust-v0.53 | quic-v1 | - | - | ✅ | 14s | - | - |
| jvm-v1.2 x rust-v0.54 (tcp, tls, mplex) | jvm-v1.2 | rust-v0.54 | tcp | tls | mplex | ✅ | 15s | - | - |
| jvm-v1.2 x rust-v0.54 (tcp, noise, mplex) | jvm-v1.2 | rust-v0.54 | tcp | noise | mplex | ✅ | 15s | - | - |
| jvm-v1.2 x rust-v0.54 (tcp, tls, yamux) | jvm-v1.2 | rust-v0.54 | tcp | tls | yamux | ✅ | 16s | - | - |
| jvm-v1.2 x rust-v0.54 (tcp, noise, yamux) | jvm-v1.2 | rust-v0.54 | tcp | noise | yamux | ✅ | 14s | - | - |
| jvm-v1.2 x rust-v0.54 (ws, noise, mplex) | jvm-v1.2 | rust-v0.54 | ws | noise | mplex | ✅ | 14s | - | - |
| jvm-v1.2 x rust-v0.54 (ws, tls, mplex) | jvm-v1.2 | rust-v0.54 | ws | tls | mplex | ✅ | 16s | - | - |
| jvm-v1.2 x rust-v0.54 (ws, tls, yamux) | jvm-v1.2 | rust-v0.54 | ws | tls | yamux | ✅ | 16s | - | - |
| jvm-v1.2 x rust-v0.54 (ws, noise, yamux) | jvm-v1.2 | rust-v0.54 | ws | noise | yamux | ✅ | 12s | - | - |
| jvm-v1.2 x rust-v0.54 (quic-v1) | jvm-v1.2 | rust-v0.54 | quic-v1 | - | - | ✅ | 14s | - | - |
| jvm-v1.2 x rust-v0.55 (tcp, noise, mplex) | jvm-v1.2 | rust-v0.55 | tcp | noise | mplex | ✅ | 13s | - | - |
| jvm-v1.2 x rust-v0.55 (tcp, tls, mplex) | jvm-v1.2 | rust-v0.55 | tcp | tls | mplex | ✅ | 15s | - | - |
| jvm-v1.2 x rust-v0.55 (tcp, tls, yamux) | jvm-v1.2 | rust-v0.55 | tcp | tls | yamux | ✅ | 16s | - | - |
| jvm-v1.2 x rust-v0.55 (tcp, noise, yamux) | jvm-v1.2 | rust-v0.55 | tcp | noise | yamux | ✅ | 14s | - | - |
| jvm-v1.2 x rust-v0.55 (ws, tls, mplex) | jvm-v1.2 | rust-v0.55 | ws | tls | mplex | ✅ | 15s | - | - |
| jvm-v1.2 x rust-v0.55 (ws, tls, yamux) | jvm-v1.2 | rust-v0.55 | ws | tls | yamux | ✅ | 16s | - | - |
| jvm-v1.2 x rust-v0.55 (ws, noise, mplex) | jvm-v1.2 | rust-v0.55 | ws | noise | mplex | ✅ | 12s | - | - |
| jvm-v1.2 x rust-v0.55 (ws, noise, yamux) | jvm-v1.2 | rust-v0.55 | ws | noise | yamux | ✅ | 12s | - | - |
| jvm-v1.2 x rust-v0.55 (quic-v1) | jvm-v1.2 | rust-v0.55 | quic-v1 | - | - | ✅ | 14s | - | - |
| jvm-v1.2 x rust-v0.56 (tcp, tls, mplex) | jvm-v1.2 | rust-v0.56 | tcp | tls | mplex | ✅ | 15s | - | - |
| jvm-v1.2 x rust-v0.56 (tcp, noise, mplex) | jvm-v1.2 | rust-v0.56 | tcp | noise | mplex | ✅ | 13s | - | - |
| jvm-v1.2 x rust-v0.56 (tcp, tls, yamux) | jvm-v1.2 | rust-v0.56 | tcp | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x rust-v0.56 (tcp, noise, yamux) | jvm-v1.2 | rust-v0.56 | tcp | noise | yamux | ✅ | 12s | - | - |
| jvm-v1.2 x rust-v0.56 (ws, tls, mplex) | jvm-v1.2 | rust-v0.56 | ws | tls | mplex | ✅ | 14s | - | - |
| jvm-v1.2 x rust-v0.56 (ws, noise, mplex) | jvm-v1.2 | rust-v0.56 | ws | noise | mplex | ✅ | 13s | - | - |
| jvm-v1.2 x rust-v0.56 (ws, tls, yamux) | jvm-v1.2 | rust-v0.56 | ws | tls | yamux | ✅ | 14s | - | - |
| jvm-v1.2 x rust-v0.56 (ws, noise, yamux) | jvm-v1.2 | rust-v0.56 | ws | noise | yamux | ✅ | 12s | - | - |
| jvm-v1.2 x go-v0.38 (tcp, noise, yamux) | jvm-v1.2 | go-v0.38 | tcp | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x rust-v0.56 (quic-v1) | jvm-v1.2 | rust-v0.56 | quic-v1 | - | - | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.38 (tcp, tls, yamux) | jvm-v1.2 | go-v0.38 | tcp | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.38 (ws, tls, yamux) | jvm-v1.2 | go-v0.38 | ws | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.38 (ws, noise, yamux) | jvm-v1.2 | go-v0.38 | ws | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x go-v0.38 (quic-v1) | jvm-v1.2 | go-v0.38 | quic-v1 | - | - | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.39 (tcp, tls, yamux) | jvm-v1.2 | go-v0.39 | tcp | tls | yamux | ✅ | 14s | - | - |
| jvm-v1.2 x go-v0.39 (tcp, noise, yamux) | jvm-v1.2 | go-v0.39 | tcp | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x go-v0.39 (ws, noise, yamux) | jvm-v1.2 | go-v0.39 | ws | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x go-v0.39 (ws, tls, yamux) | jvm-v1.2 | go-v0.39 | ws | tls | yamux | ✅ | 16s | - | - |
| jvm-v1.2 x go-v0.39 (quic-v1) | jvm-v1.2 | go-v0.39 | quic-v1 | - | - | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.40 (tcp, noise, yamux) | jvm-v1.2 | go-v0.40 | tcp | noise | yamux | ✅ | 14s | - | - |
| jvm-v1.2 x go-v0.40 (tcp, tls, yamux) | jvm-v1.2 | go-v0.40 | tcp | tls | yamux | ✅ | 16s | - | - |
| jvm-v1.2 x go-v0.40 (ws, noise, yamux) | jvm-v1.2 | go-v0.40 | ws | noise | yamux | ✅ | 12s | - | - |
| jvm-v1.2 x go-v0.40 (ws, tls, yamux) | jvm-v1.2 | go-v0.40 | ws | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.40 (quic-v1) | jvm-v1.2 | go-v0.40 | quic-v1 | - | - | ✅ | 14s | - | - |
| jvm-v1.2 x go-v0.41 (tcp, noise, yamux) | jvm-v1.2 | go-v0.41 | tcp | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x go-v0.41 (tcp, tls, yamux) | jvm-v1.2 | go-v0.41 | tcp | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.41 (ws, noise, yamux) | jvm-v1.2 | go-v0.41 | ws | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x go-v0.41 (ws, tls, yamux) | jvm-v1.2 | go-v0.41 | ws | tls | yamux | ✅ | 16s | - | - |
| jvm-v1.2 x go-v0.41 (quic-v1) | jvm-v1.2 | go-v0.41 | quic-v1 | - | - | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.42 (tcp, tls, yamux) | jvm-v1.2 | go-v0.42 | tcp | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.42 (tcp, noise, yamux) | jvm-v1.2 | go-v0.42 | tcp | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x go-v0.42 (ws, tls, yamux) | jvm-v1.2 | go-v0.42 | ws | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.42 (ws, noise, yamux) | jvm-v1.2 | go-v0.42 | ws | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x go-v0.42 (quic-v1) | jvm-v1.2 | go-v0.42 | quic-v1 | - | - | ✅ | 14s | - | - |
| jvm-v1.2 x go-v0.43 (tcp, noise, yamux) | jvm-v1.2 | go-v0.43 | tcp | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x go-v0.43 (tcp, tls, yamux) | jvm-v1.2 | go-v0.43 | tcp | tls | yamux | ✅ | 16s | - | - |
| jvm-v1.2 x go-v0.43 (ws, tls, yamux) | jvm-v1.2 | go-v0.43 | ws | tls | yamux | ✅ | 16s | - | - |
| jvm-v1.2 x go-v0.43 (ws, noise, yamux) | jvm-v1.2 | go-v0.43 | ws | noise | yamux | ✅ | 14s | - | - |
| jvm-v1.2 x go-v0.43 (quic-v1) | jvm-v1.2 | go-v0.43 | quic-v1 | - | - | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.44 (tcp, noise, yamux) | jvm-v1.2 | go-v0.44 | tcp | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x go-v0.44 (tcp, tls, yamux) | jvm-v1.2 | go-v0.44 | tcp | tls | yamux | ✅ | 16s | - | - |
| jvm-v1.2 x go-v0.44 (ws, tls, yamux) | jvm-v1.2 | go-v0.44 | ws | tls | yamux | ✅ | 14s | - | - |
| jvm-v1.2 x go-v0.44 (ws, noise, yamux) | jvm-v1.2 | go-v0.44 | ws | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x go-v0.44 (quic-v1) | jvm-v1.2 | go-v0.44 | quic-v1 | - | - | ✅ | 16s | - | - |
| jvm-v1.2 x go-v0.45 (tcp, noise, yamux) | jvm-v1.2 | go-v0.45 | tcp | noise | yamux | ✅ | 14s | - | - |
| jvm-v1.2 x go-v0.45 (tcp, tls, yamux) | jvm-v1.2 | go-v0.45 | tcp | tls | yamux | ✅ | 16s | - | - |
| jvm-v1.2 x go-v0.45 (ws, tls, yamux) | jvm-v1.2 | go-v0.45 | ws | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.45 (ws, noise, yamux) | jvm-v1.2 | go-v0.45 | ws | noise | yamux | ✅ | 14s | - | - |
| jvm-v1.2 x python-v0.4 (tcp, noise, mplex) | jvm-v1.2 | python-v0.4 | tcp | noise | mplex | ❌ | 11s | - | - |
| jvm-v1.2 x python-v0.4 (tcp, noise, yamux) | jvm-v1.2 | python-v0.4 | tcp | noise | yamux | ❌ | 11s | - | - |
| jvm-v1.2 x go-v0.45 (quic-v1) | jvm-v1.2 | go-v0.45 | quic-v1 | - | - | ✅ | 16s | - | - |
| jvm-v1.2 x python-v0.4 (ws, noise, mplex) | jvm-v1.2 | python-v0.4 | ws | noise | mplex | ❌ | 10s | - | - |
| jvm-v1.2 x python-v0.4 (ws, noise, yamux) | jvm-v1.2 | python-v0.4 | ws | noise | yamux | ❌ | 12s | - | - |
| jvm-v1.2 x python-v0.4 (quic-v1) | jvm-v1.2 | python-v0.4 | quic-v1 | - | - | ❌ | 19s | - | - |
| jvm-v1.2 x js-v1.x (tcp, noise, mplex) | jvm-v1.2 | js-v1.x | tcp | noise | mplex | ✅ | 32s | - | - |
| jvm-v1.2 x js-v1.x (tcp, noise, yamux) | jvm-v1.2 | js-v1.x | tcp | noise | yamux | ✅ | 33s | - | - |
| jvm-v1.2 x js-v1.x (ws, noise, yamux) | jvm-v1.2 | js-v1.x | ws | noise | yamux | ✅ | 32s | - | - |
| jvm-v1.2 x js-v1.x (ws, noise, mplex) | jvm-v1.2 | js-v1.x | ws | noise | mplex | ✅ | 33s | - | - |
| jvm-v1.2 x js-v2.x (tcp, noise, mplex) | jvm-v1.2 | js-v2.x | tcp | noise | mplex | ✅ | 32s | - | - |
| jvm-v1.2 x js-v2.x (tcp, noise, yamux) | jvm-v1.2 | js-v2.x | tcp | noise | yamux | ✅ | 32s | - | - |
| jvm-v1.2 x js-v2.x (ws, noise, mplex) | jvm-v1.2 | js-v2.x | ws | noise | mplex | ✅ | 30s | - | - |
| jvm-v1.2 x js-v2.x (ws, noise, yamux) | jvm-v1.2 | js-v2.x | ws | noise | yamux | ✅ | 26s | - | - |
| jvm-v1.2 x nim-v1.14 (tcp, noise, mplex) | jvm-v1.2 | nim-v1.14 | tcp | noise | mplex | ✅ | 15s | - | - |
| jvm-v1.2 x nim-v1.14 (tcp, noise, yamux) | jvm-v1.2 | nim-v1.14 | tcp | noise | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x nim-v1.14 (ws, noise, mplex) | jvm-v1.2 | nim-v1.14 | ws | noise | mplex | ✅ | 14s | - | - |
| jvm-v1.2 x js-v3.x (tcp, noise, mplex) | jvm-v1.2 | js-v3.x | tcp | noise | mplex | ✅ | 26s | - | - |
| jvm-v1.2 x nim-v1.14 (ws, noise, yamux) | jvm-v1.2 | nim-v1.14 | ws | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x js-v3.x (tcp, noise, yamux) | jvm-v1.2 | js-v3.x | tcp | noise | yamux | ✅ | 27s | - | - |
| jvm-v1.2 x js-v3.x (ws, noise, mplex) | jvm-v1.2 | js-v3.x | ws | noise | mplex | ✅ | 27s | - | - |
| jvm-v1.2 x js-v3.x (ws, noise, yamux) | jvm-v1.2 | js-v3.x | ws | noise | yamux | ✅ | 27s | - | - |
| jvm-v1.2 x jvm-v1.2 (tcp, tls, mplex) | jvm-v1.2 | jvm-v1.2 | tcp | tls | mplex | ✅ | 19s | - | - |
| jvm-v1.2 x jvm-v1.2 (tcp, noise, mplex) | jvm-v1.2 | jvm-v1.2 | tcp | noise | mplex | ✅ | 19s | - | - |
| jvm-v1.2 x jvm-v1.2 (tcp, tls, yamux) | jvm-v1.2 | jvm-v1.2 | tcp | tls | yamux | ✅ | 22s | - | - |
| jvm-v1.2 x jvm-v1.2 (tcp, noise, yamux) | jvm-v1.2 | jvm-v1.2 | tcp | noise | yamux | ✅ | 22s | - | - |
| jvm-v1.2 x jvm-v1.2 (ws, noise, mplex) | jvm-v1.2 | jvm-v1.2 | ws | noise | mplex | ✅ | 23s | - | - |
| jvm-v1.2 x jvm-v1.2 (ws, noise, yamux) | jvm-v1.2 | jvm-v1.2 | ws | noise | yamux | ✅ | 23s | - | - |
| jvm-v1.2 x jvm-v1.2 (ws, tls, mplex) | jvm-v1.2 | jvm-v1.2 | ws | tls | mplex | ✅ | 29s | - | - |
| jvm-v1.2 x jvm-v1.2 (ws, tls, yamux) | jvm-v1.2 | jvm-v1.2 | ws | tls | yamux | ✅ | 28s | - | - |
| jvm-v1.2 x c-v0.0.1 (tcp, noise, mplex) | jvm-v1.2 | c-v0.0.1 | tcp | noise | mplex | ✅ | 17s | - | - |
| jvm-v1.2 x c-v0.0.1 (tcp, noise, yamux) | jvm-v1.2 | c-v0.0.1 | tcp | noise | yamux | ❌ | 13s | - | - |
| jvm-v1.2 x jvm-v1.2 (quic-v1) | jvm-v1.2 | jvm-v1.2 | quic-v1 | - | - | ✅ | 22s | - | - |
| c-v0.0.1 x rust-v0.53 (tcp, noise, mplex) | c-v0.0.1 | rust-v0.53 | tcp | noise | mplex | ✅ | 6s | 67.000 | 1.000 |
| jvm-v1.2 x c-v0.0.1 (quic-v1) | jvm-v1.2 | c-v0.0.1 | quic-v1 | - | - | ✅ | 17s | - | - |
| c-v0.0.1 x rust-v0.53 (tcp, noise, yamux) | c-v0.0.1 | rust-v0.53 | tcp | noise | yamux | ✅ | 6s | 76.000 | 1.000 |
| jvm-v1.2 x dotnet-v1.0 (tcp, noise, yamux) | jvm-v1.2 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 14s | - | - |
| c-v0.0.1 x rust-v0.53 (quic-v1) | c-v0.0.1 | rust-v0.53 | quic-v1 | - | - | ✅ | 7s | 47.000 | 1.000 |
| jvm-v1.2 x zig-v0.0.1 (quic-v1) | jvm-v1.2 | zig-v0.0.1 | quic-v1 | - | - | ❌ | 12s | - | - |
| c-v0.0.1 x rust-v0.54 (tcp, noise, mplex) | c-v0.0.1 | rust-v0.54 | tcp | noise | mplex | ✅ | 5s | 64.000 | 1.000 |
| c-v0.0.1 x rust-v0.54 (tcp, noise, yamux) | c-v0.0.1 | rust-v0.54 | tcp | noise | yamux | ✅ | 4s | 64.000 | 1.000 |
| c-v0.0.1 x rust-v0.55 (tcp, noise, mplex) | c-v0.0.1 | rust-v0.55 | tcp | noise | mplex | ✅ | 4s | 19.000 | 0.000 |
| c-v0.0.1 x rust-v0.55 (tcp, noise, yamux) | c-v0.0.1 | rust-v0.55 | tcp | noise | yamux | ✅ | 4s | 59.000 | 0.000 |
| jvm-v1.2 x eth-p2p-z-v0.0.1 (quic-v1) | jvm-v1.2 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 15s | - | - |
| c-v0.0.1 x rust-v0.54 (quic-v1) | c-v0.0.1 | rust-v0.54 | quic-v1 | - | - | ✅ | 6s | 29.000 | 1.000 |
| c-v0.0.1 x rust-v0.56 (tcp, noise, mplex) | c-v0.0.1 | rust-v0.56 | tcp | noise | mplex | ✅ | 4s | 24.000 | 0.000 |
| c-v0.0.1 x rust-v0.56 (tcp, noise, yamux) | c-v0.0.1 | rust-v0.56 | tcp | noise | yamux | ✅ | 4s | 60.000 | 0.000 |
| c-v0.0.1 x rust-v0.55 (quic-v1) | c-v0.0.1 | rust-v0.55 | quic-v1 | - | - | ✅ | 6s | 31.000 | 1.000 |
| c-v0.0.1 x go-v0.38 (tcp, noise, yamux) | c-v0.0.1 | go-v0.38 | tcp | noise | yamux | ✅ | 5s | 114.000 | 1.000 |
| c-v0.0.1 x go-v0.39 (tcp, noise, yamux) | c-v0.0.1 | go-v0.39 | tcp | noise | yamux | ✅ | 4s | 116.000 | 1.000 |
| c-v0.0.1 x rust-v0.56 (quic-v1) | c-v0.0.1 | rust-v0.56 | quic-v1 | - | - | ✅ | 7s | 34.000 | 0.000 |
| c-v0.0.1 x go-v0.40 (tcp, noise, yamux) | c-v0.0.1 | go-v0.40 | tcp | noise | yamux | ✅ | 5s | 139.000 | 1.000 |
| c-v0.0.1 x go-v0.41 (tcp, noise, yamux) | c-v0.0.1 | go-v0.41 | tcp | noise | yamux | ✅ | 4s | 115.000 | 0.000 |
| c-v0.0.1 x go-v0.42 (tcp, noise, yamux) | c-v0.0.1 | go-v0.42 | tcp | noise | yamux | ✅ | 4s | 121.000 | 0.000 |
| c-v0.0.1 x go-v0.43 (tcp, noise, yamux) | c-v0.0.1 | go-v0.43 | tcp | noise | yamux | ✅ | 3s | 119.000 | 0.000 |
| c-v0.0.1 x go-v0.44 (tcp, noise, yamux) | c-v0.0.1 | go-v0.44 | tcp | noise | yamux | ✅ | 5s | 135.000 | 1.000 |
| c-v0.0.1 x go-v0.38 (quic-v1) | c-v0.0.1 | go-v0.38 | quic-v1 | - | - | ✅ | 19s | 117.000 | 2.000 |
| c-v0.0.1 x go-v0.39 (quic-v1) | c-v0.0.1 | go-v0.39 | quic-v1 | - | - | ✅ | 19s | 180.000 | 2.000 |
| c-v0.0.1 x go-v0.45 (tcp, noise, yamux) | c-v0.0.1 | go-v0.45 | tcp | noise | yamux | ✅ | 4s | 124.000 | 1.000 |
| c-v0.0.1 x go-v0.40 (quic-v1) | c-v0.0.1 | go-v0.40 | quic-v1 | - | - | ✅ | 20s | 139.000 | 1.000 |
| c-v0.0.1 x go-v0.41 (quic-v1) | c-v0.0.1 | go-v0.41 | quic-v1 | - | - | ✅ | 19s | 153.000 | 0.000 |
| c-v0.0.1 x go-v0.42 (quic-v1) | c-v0.0.1 | go-v0.42 | quic-v1 | - | - | ✅ | 19s | 124.000 | 2.000 |
| c-v0.0.1 x python-v0.4 (tcp, noise, mplex) | c-v0.0.1 | python-v0.4 | tcp | noise | mplex | ✅ | 5s | 24.000 | 0.000 |
| c-v0.0.1 x python-v0.4 (tcp, noise, yamux) | c-v0.0.1 | python-v0.4 | tcp | noise | yamux | ✅ | 6s | 238.000 | 2.000 |
| c-v0.0.1 x python-v0.4 (quic-v1) | c-v0.0.1 | python-v0.4 | quic-v1 | - | - | ✅ | 6s | 275.000 | 17.000 |
| c-v0.0.1 x go-v0.44 (quic-v1) | c-v0.0.1 | go-v0.44 | quic-v1 | - | - | ✅ | 19s | 143.000 | 0.000 |
| c-v0.0.1 x go-v0.45 (quic-v1) | c-v0.0.1 | go-v0.45 | quic-v1 | - | - | ✅ | 20s | 134.000 | 1.000 |
| c-v0.0.1 x js-v1.x (tcp, noise, mplex) | c-v0.0.1 | js-v1.x | tcp | noise | mplex | ✅ | 19s | 96.000 | 1.000 |
| c-v0.0.1 x nim-v1.14 (tcp, noise, mplex) | c-v0.0.1 | nim-v1.14 | tcp | noise | mplex | ✅ | 5s | 126.000 | 1.000 |
| c-v0.0.1 x js-v1.x (tcp, noise, yamux) | c-v0.0.1 | js-v1.x | tcp | noise | yamux | ✅ | 21s | 410.000 | 4.000 |
| c-v0.0.1 x js-v2.x (tcp, noise, mplex) | c-v0.0.1 | js-v2.x | tcp | noise | mplex | ✅ | 23s | 112.000 | 9.000 |
| c-v0.0.1 x js-v2.x (tcp, noise, yamux) | c-v0.0.1 | js-v2.x | tcp | noise | yamux | ✅ | 21s | 330.000 | 3.000 |
| c-v0.0.1 x nim-v1.14 (tcp, noise, yamux) | c-v0.0.1 | nim-v1.14 | tcp | noise | yamux | ✅ | 6s | 286.000 | 2.000 |
| c-v0.0.1 x js-v3.x (tcp, noise, mplex) | c-v0.0.1 | js-v3.x | tcp | noise | mplex | ✅ | 22s | 91.000 | 3.000 |
| c-v0.0.1 x js-v3.x (tcp, noise, yamux) | c-v0.0.1 | js-v3.x | tcp | noise | yamux | ✅ | 21s | 307.000 | 2.000 |
| c-v0.0.1 x jvm-v1.2 (tcp, noise, mplex) | c-v0.0.1 | jvm-v1.2 | tcp | noise | mplex | ✅ | 9s | 948.000 | 4.000 |
| c-v0.0.1 x c-v0.0.1 (tcp, noise, mplex) | c-v0.0.1 | c-v0.0.1 | tcp | noise | mplex | ✅ | 5s | 28.000 | 12.000 |
| c-v0.0.1 x jvm-v1.2 (tcp, noise, yamux) | c-v0.0.1 | jvm-v1.2 | tcp | noise | yamux | ❌ | 10s | - | - |
| c-v0.0.1 x c-v0.0.1 (tcp, noise, yamux) | c-v0.0.1 | c-v0.0.1 | tcp | noise | yamux | ✅ | 6s | 387.000 | 1.000 |
| c-v0.0.1 x c-v0.0.1 (quic-v1) | c-v0.0.1 | c-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 95.000 | 45.000 |
| c-v0.0.1 x dotnet-v1.0 (tcp, noise, yamux) | c-v0.0.1 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 6s | 466.000 | 7.000 |
| c-v0.0.1 x jvm-v1.2 (quic-v1) | c-v0.0.1 | jvm-v1.2 | quic-v1 | - | - | ✅ | 12s | 2776.000 | 2.000 |
| c-v0.0.1 x eth-p2p-z-v0.0.1 (quic-v1) | c-v0.0.1 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 4s | 126.000 | 4.000 |
| dotnet-v1.0 x rust-v0.53 (tcp, noise, yamux) | dotnet-v1.0 | rust-v0.53 | tcp | noise | yamux | ✅ | 5s | - | - |
| dotnet-v1.0 x rust-v0.54 (tcp, noise, yamux) | dotnet-v1.0 | rust-v0.54 | tcp | noise | yamux | ✅ | 5s | - | - |
| dotnet-v1.0 x rust-v0.55 (tcp, noise, yamux) | dotnet-v1.0 | rust-v0.55 | tcp | noise | yamux | ✅ | 6s | - | - |
| dotnet-v1.0 x rust-v0.56 (tcp, noise, yamux) | dotnet-v1.0 | rust-v0.56 | tcp | noise | yamux | ✅ | 5s | - | - |
| dotnet-v1.0 x go-v0.38 (tcp, noise, yamux) | dotnet-v1.0 | go-v0.38 | tcp | noise | yamux | ✅ | 6s | - | - |
| dotnet-v1.0 x go-v0.39 (tcp, noise, yamux) | dotnet-v1.0 | go-v0.39 | tcp | noise | yamux | ✅ | 6s | - | - |
| dotnet-v1.0 x go-v0.40 (tcp, noise, yamux) | dotnet-v1.0 | go-v0.40 | tcp | noise | yamux | ✅ | 6s | - | - |
| dotnet-v1.0 x go-v0.42 (tcp, noise, yamux) | dotnet-v1.0 | go-v0.42 | tcp | noise | yamux | ✅ | 5s | - | - |
| dotnet-v1.0 x go-v0.41 (tcp, noise, yamux) | dotnet-v1.0 | go-v0.41 | tcp | noise | yamux | ✅ | 7s | - | - |
| dotnet-v1.0 x go-v0.43 (tcp, noise, yamux) | dotnet-v1.0 | go-v0.43 | tcp | noise | yamux | ✅ | 6s | - | - |
| dotnet-v1.0 x go-v0.44 (tcp, noise, yamux) | dotnet-v1.0 | go-v0.44 | tcp | noise | yamux | ✅ | 6s | - | - |
| c-v0.0.1 x zig-v0.0.1 (quic-v1) | c-v0.0.1 | zig-v0.0.1 | quic-v1 | - | - | ❌ | 20s | - | - |
| dotnet-v1.0 x go-v0.45 (tcp, noise, yamux) | dotnet-v1.0 | go-v0.45 | tcp | noise | yamux | ✅ | 6s | - | - |
| dotnet-v1.0 x python-v0.4 (tcp, noise, yamux) | dotnet-v1.0 | python-v0.4 | tcp | noise | yamux | ✅ | 5s | - | - |
| dotnet-v1.0 x nim-v1.14 (tcp, noise, yamux) | dotnet-v1.0 | nim-v1.14 | tcp | noise | yamux | ✅ | 8s | - | - |
| dotnet-v1.0 x c-v0.0.1 (tcp, noise, yamux) | dotnet-v1.0 | c-v0.0.1 | tcp | noise | yamux | ✅ | 8s | - | - |
| dotnet-v1.0 x dotnet-v1.0 (tcp, noise, yamux) | dotnet-v1.0 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 7s | - | - |
| dotnet-v1.0 x js-v1.x (tcp, noise, yamux) | dotnet-v1.0 | js-v1.x | tcp | noise | yamux | ❌ | 15s | - | - |
| dotnet-v1.0 x jvm-v1.2 (tcp, noise, yamux) | dotnet-v1.0 | jvm-v1.2 | tcp | noise | yamux | ✅ | 12s | - | - |
| dotnet-v1.0 x js-v2.x (tcp, noise, yamux) | dotnet-v1.0 | js-v2.x | tcp | noise | yamux | ❌ | 16s | - | - |
| zig-v0.0.1 x rust-v0.53 (quic-v1) | zig-v0.0.1 | rust-v0.53 | quic-v1 | - | - | ✅ | 5s | - | - |
| dotnet-v1.0 x js-v3.x (tcp, noise, yamux) | dotnet-v1.0 | js-v3.x | tcp | noise | yamux | ❌ | 17s | - | - |
| zig-v0.0.1 x rust-v0.54 (quic-v1) | zig-v0.0.1 | rust-v0.54 | quic-v1 | - | - | ✅ | 4s | - | - |
| zig-v0.0.1 x rust-v0.55 (quic-v1) | zig-v0.0.1 | rust-v0.55 | quic-v1 | - | - | ✅ | 4s | - | - |
| zig-v0.0.1 x rust-v0.56 (quic-v1) | zig-v0.0.1 | rust-v0.56 | quic-v1 | - | - | ✅ | 4s | - | - |
| zig-v0.0.1 x go-v0.38 (quic-v1) | zig-v0.0.1 | go-v0.38 | quic-v1 | - | - | ✅ | 4s | - | - |
| zig-v0.0.1 x go-v0.39 (quic-v1) | zig-v0.0.1 | go-v0.39 | quic-v1 | - | - | ✅ | 4s | - | - |
| zig-v0.0.1 x go-v0.40 (quic-v1) | zig-v0.0.1 | go-v0.40 | quic-v1 | - | - | ✅ | 4s | - | - |
| zig-v0.0.1 x go-v0.41 (quic-v1) | zig-v0.0.1 | go-v0.41 | quic-v1 | - | - | ✅ | 4s | - | - |
| zig-v0.0.1 x go-v0.42 (quic-v1) | zig-v0.0.1 | go-v0.42 | quic-v1 | - | - | ✅ | 5s | - | - |
| zig-v0.0.1 x go-v0.43 (quic-v1) | zig-v0.0.1 | go-v0.43 | quic-v1 | - | - | ✅ | 4s | - | - |
| zig-v0.0.1 x go-v0.44 (quic-v1) | zig-v0.0.1 | go-v0.44 | quic-v1 | - | - | ✅ | 4s | - | - |
| zig-v0.0.1 x go-v0.45 (quic-v1) | zig-v0.0.1 | go-v0.45 | quic-v1 | - | - | ✅ | 5s | - | - |
| zig-v0.0.1 x zig-v0.0.1 (quic-v1) | zig-v0.0.1 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 5s | - | - |
| zig-v0.0.1 x eth-p2p-z-v0.0.1 (quic-v1) | zig-v0.0.1 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 5s | - | - |
| eth-p2p-z-v0.0.1 x rust-v0.53 (quic-v1) | eth-p2p-z-v0.0.1 | rust-v0.53 | quic-v1 | - | - | ✅ | 5s | - | - |
| eth-p2p-z-v0.0.1 x rust-v0.54 (quic-v1) | eth-p2p-z-v0.0.1 | rust-v0.54 | quic-v1 | - | - | ✅ | 5s | - | - |
| zig-v0.0.1 x jvm-v1.2 (quic-v1) | zig-v0.0.1 | jvm-v1.2 | quic-v1 | - | - | ✅ | 11s | - | - |
| eth-p2p-z-v0.0.1 x rust-v0.55 (quic-v1) | eth-p2p-z-v0.0.1 | rust-v0.55 | quic-v1 | - | - | ✅ | 4s | - | - |
| eth-p2p-z-v0.0.1 x rust-v0.56 (quic-v1) | eth-p2p-z-v0.0.1 | rust-v0.56 | quic-v1 | - | - | ✅ | 4s | - | - |
| zig-v0.0.1 x python-v0.4 (quic-v1) | zig-v0.0.1 | python-v0.4 | quic-v1 | - | - | ✅ | 15s | - | - |
| eth-p2p-z-v0.0.1 x go-v0.38 (quic-v1) | eth-p2p-z-v0.0.1 | go-v0.38 | quic-v1 | - | - | ✅ | 5s | - | - |
| eth-p2p-z-v0.0.1 x go-v0.39 (quic-v1) | eth-p2p-z-v0.0.1 | go-v0.39 | quic-v1 | - | - | ✅ | 4s | - | - |
| zig-v0.0.1 x c-v0.0.1 (quic-v1) | zig-v0.0.1 | c-v0.0.1 | quic-v1 | - | - | ❌ | 15s | - | - |
| eth-p2p-z-v0.0.1 x go-v0.40 (quic-v1) | eth-p2p-z-v0.0.1 | go-v0.40 | quic-v1 | - | - | ✅ | 5s | - | - |
| eth-p2p-z-v0.0.1 x go-v0.41 (quic-v1) | eth-p2p-z-v0.0.1 | go-v0.41 | quic-v1 | - | - | ✅ | 4s | - | - |
| eth-p2p-z-v0.0.1 x go-v0.42 (quic-v1) | eth-p2p-z-v0.0.1 | go-v0.42 | quic-v1 | - | - | ✅ | 4s | - | - |
| eth-p2p-z-v0.0.1 x go-v0.43 (quic-v1) | eth-p2p-z-v0.0.1 | go-v0.43 | quic-v1 | - | - | ✅ | 5s | - | - |
| eth-p2p-z-v0.0.1 x go-v0.44 (quic-v1) | eth-p2p-z-v0.0.1 | go-v0.44 | quic-v1 | - | - | ✅ | 4s | - | - |
| eth-p2p-z-v0.0.1 x go-v0.45 (quic-v1) | eth-p2p-z-v0.0.1 | go-v0.45 | quic-v1 | - | - | ✅ | 5s | - | - |
| eth-p2p-z-v0.0.1 x python-v0.4 (quic-v1) | eth-p2p-z-v0.0.1 | python-v0.4 | quic-v1 | - | - | ✅ | 5s | - | - |
| eth-p2p-z-v0.0.1 x c-v0.0.1 (quic-v1) | eth-p2p-z-v0.0.1 | c-v0.0.1 | quic-v1 | - | - | ✅ | 5s | - | - |
| eth-p2p-z-v0.0.1 x eth-p2p-z-v0.0.1 (quic-v1) | eth-p2p-z-v0.0.1 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 5s | - | - |
| eth-p2p-z-v0.0.1 x jvm-v1.2 (quic-v1) | eth-p2p-z-v0.0.1 | jvm-v1.2 | quic-v1 | - | - | ✅ | 9s | - | - |
| chromium-js-v1.x x rust-v0.53 (webrtc-direct) | chromium-js-v1.x | rust-v0.53 | webrtc-direct | - | - | ✅ | 23s | 369 | 48 |
| chromium-js-v1.x x rust-v0.54 (webrtc-direct) | chromium-js-v1.x | rust-v0.54 | webrtc-direct | - | - | ✅ | 24s | 351 | 25 |
| chromium-js-v1.x x rust-v0.55 (webrtc-direct) | chromium-js-v1.x | rust-v0.55 | webrtc-direct | - | - | ✅ | 24s | 271 | 25 |
| chromium-js-v1.x x rust-v0.56 (webrtc-direct) | chromium-js-v1.x | rust-v0.56 | webrtc-direct | - | - | ✅ | 23s | 271 | 26 |
| chromium-js-v1.x x go-v0.38 (webtransport) | chromium-js-v1.x | go-v0.38 | webtransport | - | - | ✅ | 22s | 137 | 35 |
| chromium-js-v1.x x go-v0.38 (wss, noise, yamux) | chromium-js-v1.x | go-v0.38 | wss | noise | yamux | ✅ | 21s | 174 | 40 |
| chromium-js-v1.x x go-v0.38 (webrtc-direct) | chromium-js-v1.x | go-v0.38 | webrtc-direct | - | - | ✅ | 23s | 328 | 46 |
| chromium-js-v1.x x go-v0.39 (webtransport) | chromium-js-v1.x | go-v0.39 | webtransport | - | - | ✅ | 23s | 300 | 50 |
| chromium-js-v1.x x go-v0.39 (wss, noise, yamux) | chromium-js-v1.x | go-v0.39 | wss | noise | yamux | ✅ | 24s | 309 | 59 |
| chromium-js-v1.x x go-v0.39 (webrtc-direct) | chromium-js-v1.x | go-v0.39 | webrtc-direct | - | - | ✅ | 24s | 219 | 25 |
| chromium-js-v1.x x go-v0.40 (webtransport) | chromium-js-v1.x | go-v0.40 | webtransport | - | - | ✅ | 23s | 123 | 32 |
| chromium-js-v1.x x go-v0.40 (wss, noise, yamux) | chromium-js-v1.x | go-v0.40 | wss | noise | yamux | ✅ | 23s | 212 | 51 |
| chromium-js-v1.x x go-v0.40 (webrtc-direct) | chromium-js-v1.x | go-v0.40 | webrtc-direct | - | - | ✅ | 24s | 263 | 48 |
| chromium-js-v1.x x go-v0.41 (webtransport) | chromium-js-v1.x | go-v0.41 | webtransport | - | - | ✅ | 24s | 248 | 74 |
| chromium-js-v1.x x go-v0.41 (wss, noise, yamux) | chromium-js-v1.x | go-v0.41 | wss | noise | yamux | ✅ | 24s | 314 | 64 |
| chromium-js-v1.x x go-v0.42 (webtransport) | chromium-js-v1.x | go-v0.42 | webtransport | - | - | ✅ | 23s | 167 | 49 |
| chromium-js-v1.x x go-v0.41 (webrtc-direct) | chromium-js-v1.x | go-v0.41 | webrtc-direct | - | - | ✅ | 24s | 352 | 60 |
| chromium-js-v1.x x go-v0.42 (wss, noise, yamux) | chromium-js-v1.x | go-v0.42 | wss | noise | yamux | ✅ | 23s | 155 | 37 |
| c-v0.0.1 x go-v0.43 (quic-v1) | c-v0.0.1 | go-v0.43 | quic-v1 | - | - | ❌ | 194s | - | - |
| chromium-js-v1.x x go-v0.42 (webrtc-direct) | chromium-js-v1.x | go-v0.42 | webrtc-direct | - | - | ✅ | 21s | 320 | 46 |
| chromium-js-v1.x x go-v0.43 (webtransport) | chromium-js-v1.x | go-v0.43 | webtransport | - | - | ✅ | 23s | 207 | 57 |
| chromium-js-v1.x x go-v0.43 (wss, noise, yamux) | chromium-js-v1.x | go-v0.43 | wss | noise | yamux | ✅ | 22s | 301 | 80 |
| chromium-js-v1.x x go-v0.43 (webrtc-direct) | chromium-js-v1.x | go-v0.43 | webrtc-direct | - | - | ✅ | 23s | 258 | 19 |
| chromium-js-v1.x x go-v0.44 (webtransport) | chromium-js-v1.x | go-v0.44 | webtransport | - | - | ✅ | 22s | 180 | 39 |
| chromium-js-v1.x x go-v0.44 (wss, noise, yamux) | chromium-js-v1.x | go-v0.44 | wss | noise | yamux | ✅ | 22s | 199 | 45 |
| chromium-js-v1.x x go-v0.44 (webrtc-direct) | chromium-js-v1.x | go-v0.44 | webrtc-direct | - | - | ✅ | 21s | 259 | 25 |
| chromium-js-v1.x x go-v0.45 (webtransport) | chromium-js-v1.x | go-v0.45 | webtransport | - | - | ✅ | 26s | 224 | 51 |
| chromium-js-v1.x x go-v0.45 (wss, noise, yamux) | chromium-js-v1.x | go-v0.45 | wss | noise | yamux | ✅ | 28s | 372 | 84 |
| chromium-js-v1.x x python-v0.4 (wss, noise, mplex) | chromium-js-v1.x | python-v0.4 | wss | noise | mplex | ✅ | 28s | 324 | 60 |
| chromium-js-v1.x x go-v0.45 (webrtc-direct) | chromium-js-v1.x | go-v0.45 | webrtc-direct | - | - | ✅ | 29s | 376 | 27 |
| chromium-js-v1.x x python-v0.4 (wss, noise, yamux) | chromium-js-v1.x | python-v0.4 | wss | noise | yamux | ✅ | 29s | 308 | 77 |
| chromium-js-v1.x x chromium-js-v1.x (webrtc) | chromium-js-v1.x | chromium-js-v1.x | webrtc | - | - | ✅ | 31s | 759 | 56 |
| chromium-js-v1.x x chromium-js-v2.x (webrtc) | chromium-js-v1.x | chromium-js-v2.x | webrtc | - | - | ✅ | 32s | 1548 | 134 |
| chromium-js-v1.x x webkit-js-v1.x (webrtc) | chromium-js-v1.x | webkit-js-v1.x | webrtc | - | - | ✅ | 37s | 854 | 59 |
| chromium-js-v2.x x rust-v0.53 (webrtc-direct) | chromium-js-v2.x | rust-v0.53 | webrtc-direct | - | - | ✅ | 36s | 414 | 79 |
| chromium-js-v1.x x firefox-js-v1.x (webrtc) | chromium-js-v1.x | firefox-js-v1.x | webrtc | - | - | ✅ | 42s | 1036 | 88 |
| chromium-js-v1.x x webkit-js-v2.x (webrtc) | chromium-js-v1.x | webkit-js-v2.x | webrtc | - | - | ✅ | 39s | 707 | 74 |
| chromium-js-v2.x x rust-v0.54 (webrtc-direct) | chromium-js-v2.x | rust-v0.54 | webrtc-direct | - | - | ✅ | 35s | 263 | 23 |
| chromium-js-v1.x x firefox-js-v2.x (webrtc) | chromium-js-v1.x | firefox-js-v2.x | webrtc | - | - | ✅ | 42s | 717 | 94 |
| chromium-js-v2.x x rust-v0.55 (webrtc-direct) | chromium-js-v2.x | rust-v0.55 | webrtc-direct | - | - | ✅ | 31s | 262 | 33 |
| eth-p2p-z-v0.0.1 x zig-v0.0.1 (quic-v1) | eth-p2p-z-v0.0.1 | zig-v0.0.1 | quic-v1 | - | - | ❌ | 195s | - | - |
| chromium-js-v2.x x rust-v0.56 (webrtc-direct) | chromium-js-v2.x | rust-v0.56 | webrtc-direct | - | - | ✅ | 25s | 364 | 37 |
| chromium-js-v2.x x go-v0.38 (webtransport) | chromium-js-v2.x | go-v0.38 | webtransport | - | - | ✅ | 25s | 247 | 79 |
| chromium-js-v2.x x go-v0.38 (webrtc-direct) | chromium-js-v2.x | go-v0.38 | webrtc-direct | - | - | ✅ | 26s | 308 | 45 |
| chromium-js-v2.x x go-v0.38 (wss, noise, yamux) | chromium-js-v2.x | go-v0.38 | wss | noise | yamux | ✅ | 26s | 323 | 72 |
| chromium-js-v2.x x go-v0.39 (webtransport) | chromium-js-v2.x | go-v0.39 | webtransport | - | - | ✅ | 26s | 165 | 40 |
| chromium-js-v2.x x go-v0.39 (wss, noise, yamux) | chromium-js-v2.x | go-v0.39 | wss | noise | yamux | ✅ | 26s | 234 | 53 |
| chromium-js-v2.x x go-v0.39 (webrtc-direct) | chromium-js-v2.x | go-v0.39 | webrtc-direct | - | - | ✅ | 24s | 202 | 47 |
| chromium-js-v2.x x go-v0.40 (webtransport) | chromium-js-v2.x | go-v0.40 | webtransport | - | - | ✅ | 27s | 300 | 74 |
| chromium-js-v2.x x go-v0.40 (wss, noise, yamux) | chromium-js-v2.x | go-v0.40 | wss | noise | yamux | ✅ | 29s | 322 | 97 |
| chromium-js-v2.x x go-v0.40 (webrtc-direct) | chromium-js-v2.x | go-v0.40 | webrtc-direct | - | - | ✅ | 30s | 358 | 70 |
| chromium-js-v2.x x go-v0.41 (webtransport) | chromium-js-v2.x | go-v0.41 | webtransport | - | - | ✅ | 29s | 279 | 94 |
| chromium-js-v2.x x go-v0.41 (wss, noise, yamux) | chromium-js-v2.x | go-v0.41 | wss | noise | yamux | ✅ | 28s | 357 | 103 |
| chromium-js-v2.x x go-v0.42 (webtransport) | chromium-js-v2.x | go-v0.42 | webtransport | - | - | ✅ | 28s | 130 | 29 |
| chromium-js-v2.x x go-v0.41 (webrtc-direct) | chromium-js-v2.x | go-v0.41 | webrtc-direct | - | - | ✅ | 29s | 214 | 23 |
| chromium-js-v2.x x go-v0.42 (wss, noise, yamux) | chromium-js-v2.x | go-v0.42 | wss | noise | yamux | ✅ | 28s | 209 | 43 |
| chromium-js-v2.x x go-v0.42 (webrtc-direct) | chromium-js-v2.x | go-v0.42 | webrtc-direct | - | - | ✅ | 28s | 339 | 64 |
| chromium-js-v2.x x go-v0.43 (webtransport) | chromium-js-v2.x | go-v0.43 | webtransport | - | - | ✅ | 29s | 219 | 56 |
| chromium-js-v2.x x go-v0.43 (wss, noise, yamux) | chromium-js-v2.x | go-v0.43 | wss | noise | yamux | ✅ | 28s | 352 | 106 |
| chromium-js-v2.x x go-v0.43 (webrtc-direct) | chromium-js-v2.x | go-v0.43 | webrtc-direct | - | - | ✅ | 29s | 366 | 56 |
| chromium-js-v2.x x go-v0.44 (webtransport) | chromium-js-v2.x | go-v0.44 | webtransport | - | - | ✅ | 29s | 301 | 63 |
| chromium-js-v2.x x go-v0.44 (wss, noise, yamux) | chromium-js-v2.x | go-v0.44 | wss | noise | yamux | ✅ | 28s | 248 | 60 |
| chromium-js-v2.x x go-v0.44 (webrtc-direct) | chromium-js-v2.x | go-v0.44 | webrtc-direct | - | - | ✅ | 29s | 257 | 39 |
| chromium-js-v2.x x go-v0.45 (webtransport) | chromium-js-v2.x | go-v0.45 | webtransport | - | - | ✅ | 28s | 173 | 32 |
| chromium-js-v2.x x go-v0.45 (wss, noise, yamux) | chromium-js-v2.x | go-v0.45 | wss | noise | yamux | ✅ | 40s | 495 | 175 |
| chromium-js-v2.x x python-v0.4 (wss, noise, yamux) | chromium-js-v2.x | python-v0.4 | wss | noise | yamux | ✅ | 39s | 543 | 185 |
| chromium-js-v2.x x python-v0.4 (wss, noise, mplex) | chromium-js-v2.x | python-v0.4 | wss | noise | mplex | ✅ | 41s | 386 | 75 |
| chromium-js-v2.x x go-v0.45 (webrtc-direct) | chromium-js-v2.x | go-v0.45 | webrtc-direct | - | - | ✅ | 41s | 441 | 46 |
| chromium-js-v2.x x chromium-js-v1.x (webrtc) | chromium-js-v2.x | chromium-js-v1.x | webrtc | - | - | ✅ | 42s | 1071 | 95 |
| chromium-js-v2.x x chromium-js-v2.x (webrtc) | chromium-js-v2.x | chromium-js-v2.x | webrtc | - | - | ✅ | 42s | 992 | 105 |
| chromium-js-v2.x x firefox-js-v1.x (webrtc) | chromium-js-v2.x | firefox-js-v1.x | webrtc | - | - | ✅ | 46s | 1392 | 86 |
| chromium-js-v2.x x firefox-js-v2.x (webrtc) | chromium-js-v2.x | firefox-js-v2.x | webrtc | - | - | ✅ | 47s | 1528 | 124 |
| chromium-js-v2.x x webkit-js-v1.x (webrtc) | chromium-js-v2.x | webkit-js-v1.x | webrtc | - | - | ✅ | 35s | 1474 | 151 |
| chromium-js-v2.x x webkit-js-v2.x (webrtc) | chromium-js-v2.x | webkit-js-v2.x | webrtc | - | - | ✅ | 38s | 1231 | 65 |
| firefox-js-v1.x x rust-v0.53 (webrtc-direct) | firefox-js-v1.x | rust-v0.53 | webrtc-direct | - | - | ✅ | 40s | 1504 | 77 |
| firefox-js-v1.x x rust-v0.54 (webrtc-direct) | firefox-js-v1.x | rust-v0.54 | webrtc-direct | - | - | ✅ | 40s | 1467 | 61 |
| firefox-js-v1.x x rust-v0.55 (webrtc-direct) | firefox-js-v1.x | rust-v0.55 | webrtc-direct | - | - | ✅ | 40s | 1382 | 31 |
| firefox-js-v1.x x rust-v0.56 (webrtc-direct) | firefox-js-v1.x | rust-v0.56 | webrtc-direct | - | - | ✅ | 39s | 1416 | 65 |
| firefox-js-v1.x x go-v0.38 (webtransport) | firefox-js-v1.x | go-v0.38 | webtransport | - | - | ❌ | 35s | - | - |
| firefox-js-v1.x x go-v0.38 (wss, noise, yamux) | firefox-js-v1.x | go-v0.38 | wss | noise | yamux | ✅ | 34s | 270 | 143 |
| firefox-js-v1.x x go-v0.38 (webrtc-direct) | firefox-js-v1.x | go-v0.38 | webrtc-direct | - | - | ✅ | 30s | 419 | 81 |
| firefox-js-v1.x x go-v0.39 (webtransport) | firefox-js-v1.x | go-v0.39 | webtransport | - | - | ❌ | 32s | - | - |
| firefox-js-v1.x x go-v0.39 (wss, noise, yamux) | firefox-js-v1.x | go-v0.39 | wss | noise | yamux | ✅ | 33s | 376 | 163 |
| firefox-js-v1.x x go-v0.39 (webrtc-direct) | firefox-js-v1.x | go-v0.39 | webrtc-direct | - | - | ✅ | 32s | 419 | 102 |
| firefox-js-v1.x x go-v0.40 (webtransport) | firefox-js-v1.x | go-v0.40 | webtransport | - | - | ❌ | 32s | - | - |
| firefox-js-v1.x x go-v0.40 (wss, noise, yamux) | firefox-js-v1.x | go-v0.40 | wss | noise | yamux | ✅ | 32s | 341 | 157 |
| firefox-js-v1.x x go-v0.40 (webrtc-direct) | firefox-js-v1.x | go-v0.40 | webrtc-direct | - | - | ✅ | 32s | 418 | 82 |
| firefox-js-v1.x x go-v0.41 (webtransport) | firefox-js-v1.x | go-v0.41 | webtransport | - | - | ❌ | 30s | - | - |
| firefox-js-v1.x x go-v0.41 (wss, noise, yamux) | firefox-js-v1.x | go-v0.41 | wss | noise | yamux | ✅ | 32s | 428 | 166 |
| firefox-js-v1.x x go-v0.41 (webrtc-direct) | firefox-js-v1.x | go-v0.41 | webrtc-direct | - | - | ✅ | 32s | 385 | 119 |
| firefox-js-v1.x x go-v0.42 (webtransport) | firefox-js-v1.x | go-v0.42 | webtransport | - | - | ❌ | 32s | - | - |
| firefox-js-v1.x x go-v0.42 (wss, noise, yamux) | firefox-js-v1.x | go-v0.42 | wss | noise | yamux | ✅ | 33s | 325 | 135 |
| firefox-js-v1.x x go-v0.42 (webrtc-direct) | firefox-js-v1.x | go-v0.42 | webrtc-direct | - | - | ✅ | 32s | 326 | 70 |
| firefox-js-v1.x x go-v0.43 (webtransport) | firefox-js-v1.x | go-v0.43 | webtransport | - | - | ❌ | 32s | - | - |
| firefox-js-v1.x x go-v0.43 (wss, noise, yamux) | firefox-js-v1.x | go-v0.43 | wss | noise | yamux | ✅ | 31s | 260 | 106 |
| firefox-js-v1.x x go-v0.43 (webrtc-direct) | firefox-js-v1.x | go-v0.43 | webrtc-direct | - | - | ✅ | 31s | 158 | 29 |
| firefox-js-v1.x x go-v0.44 (webtransport) | firefox-js-v1.x | go-v0.44 | webtransport | - | - | ❌ | 30s | - | - |
| firefox-js-v1.x x go-v0.44 (wss, noise, yamux) | firefox-js-v1.x | go-v0.44 | wss | noise | yamux | ✅ | 32s | 343 | 151 |
| firefox-js-v1.x x go-v0.44 (webrtc-direct) | firefox-js-v1.x | go-v0.44 | webrtc-direct | - | - | ✅ | 32s | 298 | 84 |
| firefox-js-v1.x x go-v0.45 (webtransport) | firefox-js-v1.x | go-v0.45 | webtransport | - | - | ❌ | 32s | - | - |
| firefox-js-v1.x x go-v0.45 (wss, noise, yamux) | firefox-js-v1.x | go-v0.45 | wss | noise | yamux | ✅ | 33s | 369 | 149 |
| firefox-js-v1.x x go-v0.45 (webrtc-direct) | firefox-js-v1.x | go-v0.45 | webrtc-direct | - | - | ✅ | 33s | 525 | 103 |
| firefox-js-v1.x x python-v0.4 (wss, noise, mplex) | firefox-js-v1.x | python-v0.4 | wss | noise | mplex | ✅ | 34s | 285 | 93 |
| firefox-js-v1.x x python-v0.4 (wss, noise, yamux) | firefox-js-v1.x | python-v0.4 | wss | noise | yamux | ✅ | 33s | 356 | 157 |
| firefox-js-v1.x x chromium-js-v1.x (webrtc) | firefox-js-v1.x | chromium-js-v1.x | webrtc | - | - | ✅ | 50s | 2270 | 211 |
| firefox-js-v1.x x chromium-js-v2.x (webrtc) | firefox-js-v1.x | chromium-js-v2.x | webrtc | - | - | ✅ | 53s | 2525 | 237 |
| firefox-js-v1.x x webkit-js-v2.x (webrtc) | firefox-js-v1.x | webkit-js-v2.x | webrtc | - | - | ✅ | 51s | 1791 | 180 |
| firefox-js-v1.x x firefox-js-v1.x (webrtc) | firefox-js-v1.x | firefox-js-v1.x | webrtc | - | - | ✅ | 55s | 2055 | 245 |
| firefox-js-v1.x x webkit-js-v1.x (webrtc) | firefox-js-v1.x | webkit-js-v1.x | webrtc | - | - | ✅ | 54s | 1825 | 358 |
| firefox-js-v1.x x firefox-js-v2.x (webrtc) | firefox-js-v1.x | firefox-js-v2.x | webrtc | - | - | ✅ | 56s | 1280 | 115 |
| firefox-js-v2.x x rust-v0.53 (webrtc-direct) | firefox-js-v2.x | rust-v0.53 | webrtc-direct | - | - | ✅ | 54s | 1453 | 59 |
| firefox-js-v2.x x rust-v0.54 (webrtc-direct) | firefox-js-v2.x | rust-v0.54 | webrtc-direct | - | - | ✅ | 54s | 1463 | 51 |
| firefox-js-v2.x x rust-v0.55 (webrtc-direct) | firefox-js-v2.x | rust-v0.55 | webrtc-direct | - | - | ✅ | 35s | 1481 | 76 |
| firefox-js-v2.x x rust-v0.56 (webrtc-direct) | firefox-js-v2.x | rust-v0.56 | webrtc-direct | - | - | ✅ | 36s | 1512 | 55 |
| firefox-js-v2.x x go-v0.38 (webtransport) | firefox-js-v2.x | go-v0.38 | webtransport | - | - | ❌ | 34s | - | - |
| firefox-js-v2.x x go-v0.38 (wss, noise, yamux) | firefox-js-v2.x | go-v0.38 | wss | noise | yamux | ✅ | 34s | 311 | 151 |
| firefox-js-v2.x x go-v0.39 (webtransport) | firefox-js-v2.x | go-v0.39 | webtransport | - | - | ❌ | 34s | - | - |
| firefox-js-v2.x x go-v0.38 (webrtc-direct) | firefox-js-v2.x | go-v0.38 | webrtc-direct | - | - | ✅ | 35s | 343 | 57 |
| firefox-js-v2.x x go-v0.39 (wss, noise, yamux) | firefox-js-v2.x | go-v0.39 | wss | noise | yamux | ✅ | 33s | 227 | 105 |
| firefox-js-v2.x x go-v0.39 (webrtc-direct) | firefox-js-v2.x | go-v0.39 | webrtc-direct | - | - | ✅ | 33s | 266 | 38 |
| firefox-js-v2.x x go-v0.40 (webtransport) | firefox-js-v2.x | go-v0.40 | webtransport | - | - | ❌ | 33s | - | - |
| firefox-js-v2.x x go-v0.40 (wss, noise, yamux) | firefox-js-v2.x | go-v0.40 | wss | noise | yamux | ✅ | 34s | 480 | 242 |
| firefox-js-v2.x x go-v0.40 (webrtc-direct) | firefox-js-v2.x | go-v0.40 | webrtc-direct | - | - | ✅ | 33s | 292 | 58 |
| firefox-js-v2.x x go-v0.41 (webtransport) | firefox-js-v2.x | go-v0.41 | webtransport | - | - | ❌ | 34s | - | - |
| firefox-js-v2.x x go-v0.41 (wss, noise, yamux) | firefox-js-v2.x | go-v0.41 | wss | noise | yamux | ✅ | 35s | 350 | 149 |
| firefox-js-v2.x x go-v0.41 (webrtc-direct) | firefox-js-v2.x | go-v0.41 | webrtc-direct | - | - | ✅ | 35s | 348 | 51 |
| firefox-js-v2.x x go-v0.42 (webtransport) | firefox-js-v2.x | go-v0.42 | webtransport | - | - | ❌ | 34s | - | - |
| firefox-js-v2.x x go-v0.42 (wss, noise, yamux) | firefox-js-v2.x | go-v0.42 | wss | noise | yamux | ✅ | 34s | 261 | 116 |
| firefox-js-v2.x x go-v0.42 (webrtc-direct) | firefox-js-v2.x | go-v0.42 | webrtc-direct | - | - | ✅ | 32s | 271 | 60 |
| firefox-js-v2.x x go-v0.43 (webtransport) | firefox-js-v2.x | go-v0.43 | webtransport | - | - | ❌ | 33s | - | - |
| firefox-js-v2.x x go-v0.43 (wss, noise, yamux) | firefox-js-v2.x | go-v0.43 | wss | noise | yamux | ✅ | 35s | 305 | 140 |
| firefox-js-v2.x x go-v0.43 (webrtc-direct) | firefox-js-v2.x | go-v0.43 | webrtc-direct | - | - | ✅ | 35s | 378 | 80 |
| firefox-js-v2.x x go-v0.44 (webtransport) | firefox-js-v2.x | go-v0.44 | webtransport | - | - | ❌ | 33s | - | - |
| firefox-js-v2.x x go-v0.44 (wss, noise, yamux) | firefox-js-v2.x | go-v0.44 | wss | noise | yamux | ✅ | 35s | 413 | 179 |
| firefox-js-v2.x x go-v0.45 (webtransport) | firefox-js-v2.x | go-v0.45 | webtransport | - | - | ❌ | 34s | - | - |
| firefox-js-v2.x x go-v0.44 (webrtc-direct) | firefox-js-v2.x | go-v0.44 | webrtc-direct | - | - | ✅ | 36s | 325 | 68 |
| firefox-js-v2.x x go-v0.45 (wss, noise, yamux) | firefox-js-v2.x | go-v0.45 | wss | noise | yamux | ✅ | 42s | 589 | 285 |
| firefox-js-v2.x x go-v0.45 (webrtc-direct) | firefox-js-v2.x | go-v0.45 | webrtc-direct | - | - | ✅ | 47s | 559 | 136 |
| firefox-js-v2.x x python-v0.4 (wss, noise, yamux) | firefox-js-v2.x | python-v0.4 | wss | noise | yamux | ✅ | 47s | 506 | 224 |
| firefox-js-v2.x x python-v0.4 (wss, noise, mplex) | firefox-js-v2.x | python-v0.4 | wss | noise | mplex | ✅ | 50s | 310 | 83 |
| firefox-js-v2.x x chromium-js-v1.x (webrtc) | firefox-js-v2.x | chromium-js-v1.x | webrtc | - | - | ✅ | 52s | 2254 | 223 |
| firefox-js-v2.x x chromium-js-v2.x (webrtc) | firefox-js-v2.x | chromium-js-v2.x | webrtc | - | - | ✅ | 53s | 1970 | 204 |
| firefox-js-v2.x x firefox-js-v1.x (webrtc) | firefox-js-v2.x | firefox-js-v1.x | webrtc | - | - | ✅ | 54s | 1791 | 403 |
| firefox-js-v2.x x firefox-js-v2.x (webrtc) | firefox-js-v2.x | firefox-js-v2.x | webrtc | - | - | ✅ | 55s | 1874 | 140 |
| firefox-js-v2.x x webkit-js-v1.x (webrtc) | firefox-js-v2.x | webkit-js-v1.x | webrtc | - | - | ✅ | 48s | 2015 | 298 |
| webkit-js-v1.x x rust-v0.53 (webrtc-direct) | webkit-js-v1.x | rust-v0.53 | webrtc-direct | - | - | ✅ | 33s | 544 | 81 |
| webkit-js-v1.x x rust-v0.54 (webrtc-direct) | webkit-js-v1.x | rust-v0.54 | webrtc-direct | - | - | ✅ | 33s | 680 | 88 |
| firefox-js-v2.x x webkit-js-v2.x (webrtc) | firefox-js-v2.x | webkit-js-v2.x | webrtc | - | - | ✅ | 41s | 1486 | 121 |
| webkit-js-v1.x x rust-v0.55 (webrtc-direct) | webkit-js-v1.x | rust-v0.55 | webrtc-direct | - | - | ✅ | 30s | 387 | 48 |
| webkit-js-v1.x x rust-v0.56 (webrtc-direct) | webkit-js-v1.x | rust-v0.56 | webrtc-direct | - | - | ✅ | 30s | 383 | 42 |
| webkit-js-v1.x x go-v0.38 (wss, noise, yamux) | webkit-js-v1.x | go-v0.38 | wss | noise | yamux | ✅ | 28s | 416 | 148 |
| webkit-js-v1.x x go-v0.38 (webrtc-direct) | webkit-js-v1.x | go-v0.38 | webrtc-direct | - | - | ✅ | 26s | 329 | 50 |
| webkit-js-v1.x x go-v0.39 (wss, noise, yamux) | webkit-js-v1.x | go-v0.39 | wss | noise | yamux | ✅ | 26s | 483 | 168 |
| webkit-js-v1.x x go-v0.39 (webrtc-direct) | webkit-js-v1.x | go-v0.39 | webrtc-direct | - | - | ✅ | 27s | 544 | 106 |
| webkit-js-v1.x x go-v0.40 (wss, noise, yamux) | webkit-js-v1.x | go-v0.40 | wss | noise | yamux | ✅ | 27s | 526 | 177 |
| webkit-js-v1.x x go-v0.40 (webrtc-direct) | webkit-js-v1.x | go-v0.40 | webrtc-direct | - | - | ✅ | 27s | 492 | 80 |
| webkit-js-v1.x x go-v0.41 (wss, noise, yamux) | webkit-js-v1.x | go-v0.41 | wss | noise | yamux | ✅ | 27s | 337 | 69 |
| webkit-js-v1.x x go-v0.41 (webrtc-direct) | webkit-js-v1.x | go-v0.41 | webrtc-direct | - | - | ✅ | 27s | 345 | 56 |
| webkit-js-v1.x x go-v0.42 (wss, noise, yamux) | webkit-js-v1.x | go-v0.42 | wss | noise | yamux | ✅ | 26s | 367 | 81 |
| webkit-js-v1.x x go-v0.42 (webrtc-direct) | webkit-js-v1.x | go-v0.42 | webrtc-direct | - | - | ✅ | 26s | 285 | 46 |
| webkit-js-v1.x x go-v0.43 (wss, noise, yamux) | webkit-js-v1.x | go-v0.43 | wss | noise | yamux | ✅ | 26s | 547 | 192 |
| webkit-js-v1.x x go-v0.43 (webrtc-direct) | webkit-js-v1.x | go-v0.43 | webrtc-direct | - | - | ✅ | 28s | 510 | 143 |
| webkit-js-v1.x x go-v0.44 (wss, noise, yamux) | webkit-js-v1.x | go-v0.44 | wss | noise | yamux | ✅ | 27s | 664 | 194 |
| webkit-js-v1.x x go-v0.44 (webrtc-direct) | webkit-js-v1.x | go-v0.44 | webrtc-direct | - | - | ✅ | 26s | 505 | 101 |
| webkit-js-v1.x x go-v0.45 (wss, noise, yamux) | webkit-js-v1.x | go-v0.45 | wss | noise | yamux | ✅ | 28s | 493 | 156 |
| webkit-js-v1.x x go-v0.45 (webrtc-direct) | webkit-js-v1.x | go-v0.45 | webrtc-direct | - | - | ✅ | 27s | 520 | 93 |
| webkit-js-v1.x x python-v0.4 (wss, noise, mplex) | webkit-js-v1.x | python-v0.4 | wss | noise | mplex | ✅ | 28s | 335 | 75 |
| webkit-js-v1.x x python-v0.4 (wss, noise, yamux) | webkit-js-v1.x | python-v0.4 | wss | noise | yamux | ✅ | 26s | 373 | 100 |
| webkit-js-v1.x x chromium-js-v1.x (webrtc) | webkit-js-v1.x | chromium-js-v1.x | webrtc | - | - | ✅ | 41s | 2563 | 327 |
| webkit-js-v1.x x chromium-js-v2.x (webrtc) | webkit-js-v1.x | chromium-js-v2.x | webrtc | - | - | ✅ | 46s | 1836 | 186 |
| webkit-js-v1.x x webkit-js-v1.x (webrtc) | webkit-js-v1.x | webkit-js-v1.x | webrtc | - | - | ✅ | 46s | 1508 | 163 |
| webkit-js-v1.x x webkit-js-v2.x (webrtc) | webkit-js-v1.x | webkit-js-v2.x | webrtc | - | - | ✅ | 48s | 1047 | 89 |
| webkit-js-v1.x x firefox-js-v1.x (webrtc) | webkit-js-v1.x | firefox-js-v1.x | webrtc | - | - | ✅ | 51s | 1074 | 121 |
| webkit-js-v2.x x rust-v0.53 (webrtc-direct) | webkit-js-v2.x | rust-v0.53 | webrtc-direct | - | - | ✅ | 47s | 1466 | 67 |
| webkit-js-v2.x x rust-v0.54 (webrtc-direct) | webkit-js-v2.x | rust-v0.54 | webrtc-direct | - | - | ✅ | 47s | 1431 | 62 |
| webkit-js-v1.x x firefox-js-v2.x (webrtc) | webkit-js-v1.x | firefox-js-v2.x | webrtc | - | - | ✅ | 52s | 1007 | 130 |
| webkit-js-v2.x x rust-v0.55 (webrtc-direct) | webkit-js-v2.x | rust-v0.55 | webrtc-direct | - | - | ✅ | 30s | 1548 | 107 |
| webkit-js-v2.x x rust-v0.56 (webrtc-direct) | webkit-js-v2.x | rust-v0.56 | webrtc-direct | - | - | ✅ | 30s | 1496 | 87 |
| webkit-js-v2.x x go-v0.38 (wss, noise, yamux) | webkit-js-v2.x | go-v0.38 | wss | noise | yamux | ✅ | 28s | 450 | 103 |
| webkit-js-v2.x x go-v0.38 (webrtc-direct) | webkit-js-v2.x | go-v0.38 | webrtc-direct | - | - | ✅ | 29s | 551 | 123 |
| webkit-js-v2.x x go-v0.39 (wss, noise, yamux) | webkit-js-v2.x | go-v0.39 | wss | noise | yamux | ✅ | 28s | 484 | 109 |
| webkit-js-v2.x x go-v0.39 (webrtc-direct) | webkit-js-v2.x | go-v0.39 | webrtc-direct | - | - | ✅ | 28s | 300 | 25 |
| webkit-js-v2.x x go-v0.40 (wss, noise, yamux) | webkit-js-v2.x | go-v0.40 | wss | noise | yamux | ✅ | 29s | 277 | 72 |
| webkit-js-v2.x x go-v0.40 (webrtc-direct) | webkit-js-v2.x | go-v0.40 | webrtc-direct | - | - | ✅ | 28s | 286 | 38 |
| webkit-js-v2.x x go-v0.41 (wss, noise, yamux) | webkit-js-v2.x | go-v0.41 | wss | noise | yamux | ✅ | 26s | 556 | 165 |
| webkit-js-v2.x x go-v0.42 (wss, noise, yamux) | webkit-js-v2.x | go-v0.42 | wss | noise | yamux | ✅ | 28s | 473 | 134 |
| webkit-js-v2.x x go-v0.41 (webrtc-direct) | webkit-js-v2.x | go-v0.41 | webrtc-direct | - | - | ✅ | 30s | 424 | 60 |
| webkit-js-v2.x x go-v0.42 (webrtc-direct) | webkit-js-v2.x | go-v0.42 | webrtc-direct | - | - | ✅ | 29s | 496 | 87 |
| webkit-js-v2.x x go-v0.43 (wss, noise, yamux) | webkit-js-v2.x | go-v0.43 | wss | noise | yamux | ✅ | 29s | 529 | 152 |
| webkit-js-v2.x x go-v0.43 (webrtc-direct) | webkit-js-v2.x | go-v0.43 | webrtc-direct | - | - | ✅ | 29s | 422 | 35 |
| webkit-js-v2.x x go-v0.44 (wss, noise, yamux) | webkit-js-v2.x | go-v0.44 | wss | noise | yamux | ✅ | 29s | 339 | 74 |
| webkit-js-v2.x x go-v0.44 (webrtc-direct) | webkit-js-v2.x | go-v0.44 | webrtc-direct | - | - | ✅ | 28s | 338 | 35 |
| webkit-js-v2.x x go-v0.45 (wss, noise, yamux) | webkit-js-v2.x | go-v0.45 | wss | noise | yamux | ✅ | 29s | 604 | 174 |
| webkit-js-v2.x x go-v0.45 (webrtc-direct) | webkit-js-v2.x | go-v0.45 | webrtc-direct | - | - | ✅ | 41s | 722 | 138 |
| webkit-js-v2.x x python-v0.4 (wss, noise, mplex) | webkit-js-v2.x | python-v0.4 | wss | noise | mplex | ✅ | 44s | 730 | 136 |
| webkit-js-v2.x x python-v0.4 (wss, noise, yamux) | webkit-js-v2.x | python-v0.4 | wss | noise | yamux | ✅ | 44s | 1028 | 298 |
| webkit-js-v2.x x chromium-js-v1.x (webrtc) | webkit-js-v2.x | chromium-js-v1.x | webrtc | - | - | ✅ | 46s | 1675 | 66 |
| webkit-js-v2.x x chromium-js-v2.x (webrtc) | webkit-js-v2.x | chromium-js-v2.x | webrtc | - | - | ✅ | 46s | 1255 | 81 |
| webkit-js-v2.x x firefox-js-v1.x (webrtc) | webkit-js-v2.x | firefox-js-v1.x | webrtc | - | - | ✅ | 49s | 1617 | 151 |
| chromium-rust-v0.53 x rust-v0.53 (webrtc-direct) | chromium-rust-v0.53 | rust-v0.53 | webrtc-direct | - | - | ✅ | 8s | 335.1 | 6.5 |
| chromium-rust-v0.53 x rust-v0.53 (ws, noise, mplex) | chromium-rust-v0.53 | rust-v0.53 | ws | noise | mplex | ✅ | 7s | 439.0 | 0.6 |
| webkit-js-v2.x x firefox-js-v2.x (webrtc) | webkit-js-v2.x | firefox-js-v2.x | webrtc | - | - | ✅ | 51s | 1516 | 76 |
| chromium-rust-v0.53 x rust-v0.53 (ws, noise, yamux) | chromium-rust-v0.53 | rust-v0.53 | ws | noise | yamux | ✅ | 7s | 360.9 | 14.9 |
| webkit-js-v2.x x webkit-js-v1.x (webrtc) | webkit-js-v2.x | webkit-js-v1.x | webrtc | - | - | ✅ | 40s | 1015 | 140 |
| chromium-rust-v0.53 x rust-v0.54 (webrtc-direct) | chromium-rust-v0.53 | rust-v0.54 | webrtc-direct | - | - | ✅ | 7s | 263.9 | 0.5 |
| chromium-rust-v0.53 x rust-v0.54 (ws, noise, mplex) | chromium-rust-v0.53 | rust-v0.54 | ws | noise | mplex | ✅ | 6s | 479.099 | 0.7 |
| chromium-rust-v0.53 x rust-v0.54 (ws, noise, yamux) | chromium-rust-v0.53 | rust-v0.54 | ws | noise | yamux | ✅ | 7s | 352.699 | 17.6 |
| chromium-rust-v0.53 x rust-v0.55 (webrtc-direct) | chromium-rust-v0.53 | rust-v0.55 | webrtc-direct | - | - | ✅ | 6s | 301.2 | 0.6 |
| chromium-rust-v0.53 x rust-v0.55 (ws, noise, mplex) | chromium-rust-v0.53 | rust-v0.55 | ws | noise | mplex | ✅ | 6s | 444.5 | 0.4 |
| chromium-rust-v0.53 x rust-v0.55 (ws, noise, yamux) | chromium-rust-v0.53 | rust-v0.55 | ws | noise | yamux | ✅ | 6s | 321.799 | 3.399 |
| chromium-rust-v0.53 x rust-v0.56 (webrtc-direct) | chromium-rust-v0.53 | rust-v0.56 | webrtc-direct | - | - | ✅ | 7s | 284.6 | 0.199 |
| chromium-rust-v0.53 x rust-v0.56 (ws, noise, mplex) | chromium-rust-v0.53 | rust-v0.56 | ws | noise | mplex | ✅ | 6s | 432.7 | 0.699 |
| chromium-rust-v0.53 x rust-v0.56 (ws, noise, yamux) | chromium-rust-v0.53 | rust-v0.56 | ws | noise | yamux | ✅ | 7s | 341.7 | 8.8 |
| chromium-rust-v0.53 x go-v0.38 (webtransport) | chromium-rust-v0.53 | go-v0.38 | webtransport | - | - | ✅ | 6s | 70.099 | 0.699 |
| webkit-js-v2.x x webkit-js-v2.x (webrtc) | webkit-js-v2.x | webkit-js-v2.x | webrtc | - | - | ✅ | 26s | 392 | 25 |
| chromium-rust-v0.53 x go-v0.38 (webrtc-direct) | chromium-rust-v0.53 | go-v0.38 | webrtc-direct | - | - | ✅ | 6s | 171.6 | 5.3 |
| chromium-rust-v0.53 x go-v0.38 (ws, noise, yamux) | chromium-rust-v0.53 | go-v0.38 | ws | noise | yamux | ✅ | 6s | 330.9 | 4.8 |
| chromium-rust-v0.53 x go-v0.39 (webtransport) | chromium-rust-v0.53 | go-v0.39 | webtransport | - | - | ✅ | 6s | 91.4 | 0.6 |
| chromium-rust-v0.53 x go-v0.39 (webrtc-direct) | chromium-rust-v0.53 | go-v0.39 | webrtc-direct | - | - | ✅ | 6s | 193.399 | 0.1 |
| chromium-rust-v0.53 x go-v0.39 (ws, noise, yamux) | chromium-rust-v0.53 | go-v0.39 | ws | noise | yamux | ✅ | 6s | 357.7 | 21.0 |
| chromium-rust-v0.53 x go-v0.40 (webtransport) | chromium-rust-v0.53 | go-v0.40 | webtransport | - | - | ✅ | 6s | 116.3 | 1.0 |
| chromium-rust-v0.53 x go-v0.40 (webrtc-direct) | chromium-rust-v0.53 | go-v0.40 | webrtc-direct | - | - | ✅ | 5s | 197.0 | 2.3 |
| chromium-rust-v0.53 x go-v0.40 (ws, noise, yamux) | chromium-rust-v0.53 | go-v0.40 | ws | noise | yamux | ✅ | 5s | 335.6 | 10.7 |
| chromium-rust-v0.53 x go-v0.41 (webtransport) | chromium-rust-v0.53 | go-v0.41 | webtransport | - | - | ✅ | 6s | 95.5 | 1.2 |
| chromium-rust-v0.53 x go-v0.41 (webrtc-direct) | chromium-rust-v0.53 | go-v0.41 | webrtc-direct | - | - | ✅ | 5s | 141.2 | 0.2 |
| chromium-rust-v0.53 x go-v0.41 (ws, noise, yamux) | chromium-rust-v0.53 | go-v0.41 | ws | noise | yamux | ✅ | 5s | 331.299 | 6.0 |
| chromium-rust-v0.53 x go-v0.42 (webtransport) | chromium-rust-v0.53 | go-v0.42 | webtransport | - | - | ✅ | 6s | 96.0 | 2.699 |
| chromium-rust-v0.53 x go-v0.42 (webrtc-direct) | chromium-rust-v0.53 | go-v0.42 | webrtc-direct | - | - | ✅ | 5s | 214.0 | 0.1 |
| chromium-rust-v0.53 x go-v0.42 (ws, noise, yamux) | chromium-rust-v0.53 | go-v0.42 | ws | noise | yamux | ✅ | 5s | 325.0 | 2.899 |
| chromium-rust-v0.53 x go-v0.43 (webtransport) | chromium-rust-v0.53 | go-v0.43 | webtransport | - | - | ✅ | 5s | 102.5 | 0.299 |
| chromium-rust-v0.53 x go-v0.44 (webtransport) | chromium-rust-v0.53 | go-v0.44 | webtransport | - | - | ✅ | 5s | 83.4 | 1.9 |
| chromium-rust-v0.53 x go-v0.43 (ws, noise, yamux) | chromium-rust-v0.53 | go-v0.43 | ws | noise | yamux | ✅ | 6s | 334.4 | 10.5 |
| chromium-rust-v0.53 x go-v0.44 (webrtc-direct) | chromium-rust-v0.53 | go-v0.44 | webrtc-direct | - | - | ✅ | 5s | 145.3 | 0.2 |
| chromium-rust-v0.53 x go-v0.44 (ws, noise, yamux) | chromium-rust-v0.53 | go-v0.44 | ws | noise | yamux | ✅ | 5s | 321.4 | 1.899 |
| chromium-rust-v0.53 x go-v0.45 (webtransport) | chromium-rust-v0.53 | go-v0.45 | webtransport | - | - | ✅ | 5s | 90.699 | 0.9 |
| chromium-rust-v0.53 x go-v0.45 (webrtc-direct) | chromium-rust-v0.53 | go-v0.45 | webrtc-direct | - | - | ✅ | 5s | 145.3 | 0.1 |
| chromium-rust-v0.53 x go-v0.45 (ws, noise, yamux) | chromium-rust-v0.53 | go-v0.45 | ws | noise | yamux | ✅ | 6s | 344.699 | 9.9 |
| chromium-rust-v0.53 x python-v0.4 (ws, noise, yamux) | chromium-rust-v0.53 | python-v0.4 | ws | noise | yamux | ✅ | 5s | 335.6 | 7.3 |
| chromium-rust-v0.53 x js-v1.x (ws, noise, mplex) | chromium-rust-v0.53 | js-v1.x | ws | noise | mplex | ✅ | 17s | 444.5 | 0.5 |
| chromium-rust-v0.53 x js-v1.x (ws, noise, yamux) | chromium-rust-v0.53 | js-v1.x | ws | noise | yamux | ✅ | 17s | 347.6 | 15.2 |
| chromium-rust-v0.53 x js-v2.x (ws, noise, mplex) | chromium-rust-v0.53 | js-v2.x | ws | noise | mplex | ✅ | 18s | 423.3 | 0.6 |
| chromium-rust-v0.53 x js-v2.x (ws, noise, yamux) | chromium-rust-v0.53 | js-v2.x | ws | noise | yamux | ✅ | 18s | 333.9 | 7.299 |
| chromium-rust-v0.53 x js-v3.x (ws, noise, mplex) | chromium-rust-v0.53 | js-v3.x | ws | noise | mplex | ✅ | 17s | 418.9 | 1.1 |
| chromium-rust-v0.53 x js-v3.x (ws, noise, yamux) | chromium-rust-v0.53 | js-v3.x | ws | noise | yamux | ✅ | 17s | 331.7 | 6.1 |
| chromium-rust-v0.53 x nim-v1.14 (ws, noise, mplex) | chromium-rust-v0.53 | nim-v1.14 | ws | noise | mplex | ✅ | 5s | 421.2 | 0.3 |
| chromium-rust-v0.53 x nim-v1.14 (ws, noise, yamux) | chromium-rust-v0.53 | nim-v1.14 | ws | noise | yamux | ✅ | 5s | 328.099 | 6.7 |
| chromium-rust-v0.54 x rust-v0.53 (webrtc-direct) | chromium-rust-v0.54 | rust-v0.53 | webrtc-direct | - | - | ✅ | 5s | 245.5 | 0.1 |
| chromium-rust-v0.54 x rust-v0.53 (ws, noise, mplex) | chromium-rust-v0.54 | rust-v0.53 | ws | noise | mplex | ✅ | 4s | 424.2 | 0.3 |
| chromium-rust-v0.53 x jvm-v1.2 (ws, noise, yamux) | chromium-rust-v0.53 | jvm-v1.2 | ws | noise | yamux | ✅ | 7s | 754.3 | 32.2 |
| chromium-rust-v0.54 x rust-v0.54 (webrtc-direct) | chromium-rust-v0.54 | rust-v0.54 | webrtc-direct | - | - | ✅ | 4s | 158.6 | 0.0 |
| chromium-rust-v0.54 x rust-v0.53 (ws, noise, yamux) | chromium-rust-v0.54 | rust-v0.53 | ws | noise | yamux | ✅ | 5s | 320.4 | 1.8 |
| chromium-rust-v0.54 x rust-v0.54 (ws, noise, mplex) | chromium-rust-v0.54 | rust-v0.54 | ws | noise | mplex | ✅ | 4s | 422.5 | 0.3 |
| chromium-rust-v0.54 x rust-v0.54 (ws, noise, yamux) | chromium-rust-v0.54 | rust-v0.54 | ws | noise | yamux | ✅ | 4s | 319.1 | 1.9 |
| chromium-rust-v0.54 x rust-v0.55 (webrtc-direct) | chromium-rust-v0.54 | rust-v0.55 | webrtc-direct | - | - | ✅ | 5s | 192.7 | 0.1 |
| chromium-rust-v0.54 x rust-v0.55 (ws, noise, mplex) | chromium-rust-v0.54 | rust-v0.55 | ws | noise | mplex | ✅ | 4s | 414.7 | 0.3 |
| chromium-rust-v0.54 x rust-v0.55 (ws, noise, yamux) | chromium-rust-v0.54 | rust-v0.55 | ws | noise | yamux | ✅ | 4s | 316.8 | 1.6 |
| chromium-rust-v0.54 x rust-v0.56 (webrtc-direct) | chromium-rust-v0.54 | rust-v0.56 | webrtc-direct | - | - | ✅ | 3s | 203.9 | 0.1 |
| chromium-rust-v0.54 x rust-v0.56 (ws, noise, mplex) | chromium-rust-v0.54 | rust-v0.56 | ws | noise | mplex | ✅ | 4s | 418.4 | 0.2 |
| chromium-rust-v0.54 x rust-v0.56 (ws, noise, yamux) | chromium-rust-v0.54 | rust-v0.56 | ws | noise | yamux | ✅ | 4s | 318.5 | 2.0 |
| chromium-rust-v0.54 x go-v0.38 (webtransport) | chromium-rust-v0.54 | go-v0.38 | webtransport | - | - | ✅ | 3s | 35.0 | 0.2 |
| chromium-rust-v0.54 x go-v0.38 (webrtc-direct) | chromium-rust-v0.54 | go-v0.38 | webrtc-direct | - | - | ✅ | 3s | 130.1 | 0.1 |
| chromium-rust-v0.54 x go-v0.38 (ws, noise, yamux) | chromium-rust-v0.54 | go-v0.38 | ws | noise | yamux | ✅ | 4s | 318.4 | 3.4 |
| chromium-rust-v0.54 x go-v0.39 (webtransport) | chromium-rust-v0.54 | go-v0.39 | webtransport | - | - | ✅ | 3s | 58.5 | 0.8 |
| chromium-rust-v0.54 x go-v0.39 (webrtc-direct) | chromium-rust-v0.54 | go-v0.39 | webrtc-direct | - | - | ✅ | 4s | 110.5 | 0.4 |
| chromium-rust-v0.54 x go-v0.39 (ws, noise, yamux) | chromium-rust-v0.54 | go-v0.39 | ws | noise | yamux | ✅ | 4s | 324.0 | 2.6 |
| chromium-rust-v0.54 x go-v0.40 (webtransport) | chromium-rust-v0.54 | go-v0.40 | webtransport | - | - | ✅ | 4s | 50.1 | 0.2 |
| chromium-rust-v0.54 x go-v0.40 (webrtc-direct) | chromium-rust-v0.54 | go-v0.40 | webrtc-direct | - | - | ✅ | 4s | 154.9 | 0.1 |
| chromium-rust-v0.54 x go-v0.41 (webtransport) | chromium-rust-v0.54 | go-v0.41 | webtransport | - | - | ✅ | 3s | 41.6 | 0.3 |
| chromium-rust-v0.54 x go-v0.40 (ws, noise, yamux) | chromium-rust-v0.54 | go-v0.40 | ws | noise | yamux | ✅ | 4s | 318.5 | 1.5 |
| chromium-rust-v0.54 x go-v0.41 (webrtc-direct) | chromium-rust-v0.54 | go-v0.41 | webrtc-direct | - | - | ✅ | 4s | 149.9 | 0.0 |
| chromium-rust-v0.54 x go-v0.41 (ws, noise, yamux) | chromium-rust-v0.54 | go-v0.41 | ws | noise | yamux | ✅ | 5s | 322.9 | 3.4 |
| chromium-rust-v0.54 x go-v0.42 (webtransport) | chromium-rust-v0.54 | go-v0.42 | webtransport | - | - | ✅ | 4s | 43.8 | 0.5 |
| chromium-rust-v0.54 x go-v0.42 (webrtc-direct) | chromium-rust-v0.54 | go-v0.42 | webrtc-direct | - | - | ✅ | 4s | 112.3 | 0.1 |
| chromium-rust-v0.54 x go-v0.42 (ws, noise, yamux) | chromium-rust-v0.54 | go-v0.42 | ws | noise | yamux | ✅ | 4s | 317.7 | 2.8 |
| chromium-rust-v0.54 x go-v0.43 (webtransport) | chromium-rust-v0.54 | go-v0.43 | webtransport | - | - | ✅ | 4s | 51.9 | 0.3 |
| chromium-rust-v0.54 x go-v0.43 (webrtc-direct) | chromium-rust-v0.54 | go-v0.43 | webrtc-direct | - | - | ✅ | 4s | 137.7 | 0.0 |
| chromium-rust-v0.54 x go-v0.43 (ws, noise, yamux) | chromium-rust-v0.54 | go-v0.43 | ws | noise | yamux | ✅ | 4s | 322.1 | 4.8 |
| chromium-rust-v0.54 x go-v0.44 (webtransport) | chromium-rust-v0.54 | go-v0.44 | webtransport | - | - | ✅ | 4s | 59.4 | 0.6 |
| chromium-rust-v0.54 x go-v0.44 (webrtc-direct) | chromium-rust-v0.54 | go-v0.44 | webrtc-direct | - | - | ✅ | 4s | 114.7 | 0.1 |
| chromium-rust-v0.54 x go-v0.44 (ws, noise, yamux) | chromium-rust-v0.54 | go-v0.44 | ws | noise | yamux | ✅ | 4s | 320.9 | 5.6 |
| chromium-rust-v0.54 x go-v0.45 (webtransport) | chromium-rust-v0.54 | go-v0.45 | webtransport | - | - | ✅ | 4s | 47.1 | 0.1 |
| chromium-rust-v0.54 x go-v0.45 (webrtc-direct) | chromium-rust-v0.54 | go-v0.45 | webrtc-direct | - | - | ✅ | 3s | 129.0 | 0.1 |
| chromium-rust-v0.54 x go-v0.45 (ws, noise, yamux) | chromium-rust-v0.54 | go-v0.45 | ws | noise | yamux | ✅ | 4s | 320.3 | 3.9 |
| chromium-rust-v0.54 x python-v0.4 (ws, noise, yamux) | chromium-rust-v0.54 | python-v0.4 | ws | noise | yamux | ✅ | 4s | 320.6 | 4.1 |
| chromium-rust-v0.54 x js-v1.x (ws, noise, mplex) | chromium-rust-v0.54 | js-v1.x | ws | noise | mplex | ✅ | 12s | 422.7 | 0.3 |
| chromium-rust-v0.54 x python-v0.4 (ws, noise, mplex) | chromium-rust-v0.54 | python-v0.4 | ws | noise | mplex | ✅ | 15s | 10419.9 | 0.7 |
| chromium-rust-v0.54 x js-v1.x (ws, noise, yamux) | chromium-rust-v0.54 | js-v1.x | ws | noise | yamux | ✅ | 12s | 341.5 | 8.5 |
| chromium-rust-v0.54 x js-v2.x (ws, noise, mplex) | chromium-rust-v0.54 | js-v2.x | ws | noise | mplex | ✅ | 13s | 423.7 | 0.4 |
| chromium-rust-v0.54 x js-v2.x (ws, noise, yamux) | chromium-rust-v0.54 | js-v2.x | ws | noise | yamux | ✅ | 12s | 330.5 | 5.7 |
| chromium-rust-v0.54 x nim-v1.14 (ws, noise, mplex) | chromium-rust-v0.54 | nim-v1.14 | ws | noise | mplex | ✅ | 4s | 418.0 | 0.5 |
| chromium-rust-v0.54 x nim-v1.14 (ws, noise, yamux) | chromium-rust-v0.54 | nim-v1.14 | ws | noise | yamux | ✅ | 4s | 334.0 | 5.9 |
| chromium-rust-v0.54 x jvm-v1.2 (ws, noise, yamux) | chromium-rust-v0.54 | jvm-v1.2 | ws | noise | yamux | ✅ | 6s | 636.7 | 16.7 |
| chromium-rust-v0.54 x js-v3.x (ws, noise, mplex) | chromium-rust-v0.54 | js-v3.x | ws | noise | mplex | ✅ | 13s | 415.1 | 0.3 |
| chromium-rust-v0.54 x js-v3.x (ws, noise, yamux) | chromium-rust-v0.54 | js-v3.x | ws | noise | yamux | ✅ | 14s | 316.2 | 2.6 |
| chromium-rust-v0.54 x jvm-v1.2 (ws, noise, mplex) | chromium-rust-v0.54 | jvm-v1.2 | ws | noise | mplex | ✅ | 17s | 11335.8 | 1.6 |
| chromium-rust-v0.53 x go-v0.43 (webrtc-direct) | chromium-rust-v0.53 | go-v0.43 | webrtc-direct | - | - | ❌ | 184s | - | - |
| chromium-rust-v0.53 x python-v0.4 (ws, noise, mplex) | chromium-rust-v0.53 | python-v0.4 | ws | noise | mplex | ❌ | 184s | - | - |
| chromium-rust-v0.53 x jvm-v1.2 (ws, noise, mplex) | chromium-rust-v0.53 | jvm-v1.2 | ws | noise | mplex | ❌ | 184s | - | - |

---

## Matrix View by Transport + Secure Channel + Muxer

### quic-v1

| Dialer \ Listener | c-v0.0.1 | eth-p2p-z-v0.0.1 | go-v0.38 | go-v0.39 | go-v0.40 | go-v0.41 | go-v0.42 | go-v0.43 | go-v0.44 | go-v0.45 | jvm-v1.2 | python-v0.4 | rust-v0.53 | rust-v0.54 | rust-v0.55 | rust-v0.56 | zig-v0.0.1 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **c-v0.0.1** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **eth-p2p-z-v0.0.1** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **go-v0.38** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.39** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.40** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.41** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.42** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.43** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.44** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.45** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **jvm-v1.2** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **python-v0.4** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **rust-v0.53** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **rust-v0.54** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **rust-v0.55** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **rust-v0.56** | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **zig-v0.0.1** | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

### tcp + noise + mplex

| Dialer \ Listener | c-v0.0.1 | js-v1.x | js-v2.x | js-v3.x | jvm-v1.2 | nim-v1.14 | python-v0.4 | rust-v0.53 | rust-v0.54 | rust-v0.55 | rust-v0.56 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **c-v0.0.1** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **js-v1.x** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **js-v2.x** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **js-v3.x** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **jvm-v1.2** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ |
| **nim-v1.14** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **python-v0.4** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **rust-v0.53** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **rust-v0.54** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **rust-v0.55** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **rust-v0.56** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

### tcp + noise + yamux

| Dialer \ Listener | c-v0.0.1 | dotnet-v1.0 | go-v0.38 | go-v0.39 | go-v0.40 | go-v0.41 | go-v0.42 | go-v0.43 | go-v0.44 | go-v0.45 | js-v1.x | js-v2.x | js-v3.x | jvm-v1.2 | nim-v1.14 | python-v0.4 | rust-v0.53 | rust-v0.54 | rust-v0.55 | rust-v0.56 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **c-v0.0.1** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **dotnet-v1.0** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.38** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.39** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.40** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.41** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.42** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.43** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.44** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.45** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **js-v1.x** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **js-v2.x** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **js-v3.x** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **jvm-v1.2** | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ |
| **nim-v1.14** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **python-v0.4** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **rust-v0.53** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **rust-v0.54** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **rust-v0.55** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **rust-v0.56** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

### tcp + tls + mplex

| Dialer \ Listener | jvm-v1.2 | rust-v0.53 | rust-v0.54 | rust-v0.55 | rust-v0.56 |
|---|---|---|---|---|---|
| **jvm-v1.2** | ✅ | ✅ | ✅ | ✅ | ✅ |
| **rust-v0.53** | ✅ | ✅ | ✅ | ✅ | ✅ |
| **rust-v0.54** | ✅ | ✅ | ✅ | ✅ | ✅ |
| **rust-v0.55** | ✅ | ✅ | ✅ | ✅ | ✅ |
| **rust-v0.56** | ✅ | ✅ | ✅ | ✅ | ✅ |

### tcp + tls + yamux

| Dialer \ Listener | go-v0.38 | go-v0.39 | go-v0.40 | go-v0.41 | go-v0.42 | go-v0.43 | go-v0.44 | go-v0.45 | jvm-v1.2 | rust-v0.53 | rust-v0.54 | rust-v0.55 | rust-v0.56 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **go-v0.38** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.39** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.40** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.41** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.42** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.43** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.44** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.45** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **jvm-v1.2** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **rust-v0.53** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **rust-v0.54** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **rust-v0.55** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **rust-v0.56** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

### webrtc-direct

| Dialer \ Listener | go-v0.38 | go-v0.39 | go-v0.40 | go-v0.41 | go-v0.42 | go-v0.43 | go-v0.44 | go-v0.45 | rust-v0.53 | rust-v0.54 | rust-v0.55 | rust-v0.56 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **chromium-js-v1.x** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **chromium-js-v2.x** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **chromium-rust-v0.53** | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **chromium-rust-v0.54** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **firefox-js-v1.x** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **firefox-js-v2.x** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.38** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **go-v0.39** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **go-v0.40** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **go-v0.41** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **go-v0.42** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **go-v0.43** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **go-v0.44** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **go-v0.45** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **rust-v0.53** | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **rust-v0.54** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **rust-v0.55** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **rust-v0.56** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **webkit-js-v1.x** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **webkit-js-v2.x** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

### webrtc

| Dialer \ Listener | chromium-js-v1.x | chromium-js-v2.x | firefox-js-v1.x | firefox-js-v2.x | webkit-js-v1.x | webkit-js-v2.x |
|---|---|---|---|---|---|---|
| **chromium-js-v1.x** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **chromium-js-v2.x** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **firefox-js-v1.x** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **firefox-js-v2.x** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **webkit-js-v1.x** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **webkit-js-v2.x** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

### webtransport

| Dialer \ Listener | go-v0.38 | go-v0.39 | go-v0.40 | go-v0.41 | go-v0.42 | go-v0.43 | go-v0.44 | go-v0.45 |
|---|---|---|---|---|---|---|---|---|
| **chromium-js-v1.x** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **chromium-js-v2.x** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **chromium-rust-v0.53** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **chromium-rust-v0.54** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **firefox-js-v1.x** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **firefox-js-v2.x** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **go-v0.38** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.39** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.40** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.41** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.42** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.43** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.44** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.45** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

### wss + noise + mplex

| Dialer \ Listener | python-v0.4 |
|---|---|
| **chromium-js-v1.x** | ✅ |
| **chromium-js-v2.x** | ✅ |
| **firefox-js-v1.x** | ✅ |
| **firefox-js-v2.x** | ✅ |
| **js-v1.x** | ✅ |
| **js-v2.x** | ✅ |
| **js-v3.x** | ✅ |
| **python-v0.4** | ✅ |
| **webkit-js-v1.x** | ✅ |
| **webkit-js-v2.x** | ✅ |

### wss + noise + yamux

| Dialer \ Listener | go-v0.38 | go-v0.39 | go-v0.40 | go-v0.41 | go-v0.42 | go-v0.43 | go-v0.44 | go-v0.45 | python-v0.4 |
|---|---|---|---|---|---|---|---|---|---|
| **chromium-js-v1.x** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **chromium-js-v2.x** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **firefox-js-v1.x** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **firefox-js-v2.x** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.38** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.39** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.40** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.41** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.42** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.43** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.44** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.45** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **js-v1.x** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **js-v2.x** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **js-v3.x** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **python-v0.4** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **webkit-js-v1.x** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **webkit-js-v2.x** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

### wss + tls + yamux

| Dialer \ Listener | go-v0.38 | go-v0.39 | go-v0.40 | go-v0.41 | go-v0.42 | go-v0.43 | go-v0.44 | go-v0.45 |
|---|---|---|---|---|---|---|---|---|
| **go-v0.38** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.39** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.40** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.41** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.42** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.43** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.44** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.45** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

### ws + noise + mplex

| Dialer \ Listener | js-v1.x | js-v2.x | js-v3.x | jvm-v1.2 | nim-v1.14 | python-v0.4 | rust-v0.53 | rust-v0.54 | rust-v0.55 | rust-v0.56 |
|---|---|---|---|---|---|---|---|---|---|---|
| **chromium-rust-v0.53** | ✅ | ✅ | ✅ | ❌ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ |
| **chromium-rust-v0.54** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **js-v1.x** | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **js-v2.x** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **js-v3.x** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **jvm-v1.2** | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ |
| **nim-v1.14** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **python-v0.4** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **rust-v0.53** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **rust-v0.54** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **rust-v0.55** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **rust-v0.56** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

### ws + noise + yamux

| Dialer \ Listener | go-v0.38 | go-v0.39 | go-v0.40 | go-v0.41 | go-v0.42 | go-v0.43 | go-v0.44 | go-v0.45 | js-v1.x | js-v2.x | js-v3.x | jvm-v1.2 | nim-v1.14 | python-v0.4 | rust-v0.53 | rust-v0.54 | rust-v0.55 | rust-v0.56 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **chromium-rust-v0.53** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **chromium-rust-v0.54** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.38** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.39** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.40** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.41** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.42** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.43** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.44** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.45** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **js-v1.x** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **js-v2.x** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **js-v3.x** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **jvm-v1.2** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ |
| **nim-v1.14** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **python-v0.4** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **rust-v0.53** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **rust-v0.54** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **rust-v0.55** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **rust-v0.56** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

### ws + tls + mplex

| Dialer \ Listener | jvm-v1.2 | rust-v0.53 | rust-v0.54 | rust-v0.55 | rust-v0.56 |
|---|---|---|---|---|---|
| **jvm-v1.2** | ✅ | ✅ | ✅ | ✅ | ✅ |
| **rust-v0.53** | ✅ | ✅ | ✅ | ✅ | ✅ |
| **rust-v0.54** | ✅ | ✅ | ✅ | ✅ | ✅ |
| **rust-v0.55** | ✅ | ✅ | ✅ | ✅ | ✅ |
| **rust-v0.56** | ✅ | ✅ | ✅ | ✅ | ✅ |

### ws + tls + yamux

| Dialer \ Listener | go-v0.38 | go-v0.39 | go-v0.40 | go-v0.41 | go-v0.42 | go-v0.43 | go-v0.44 | go-v0.45 | jvm-v1.2 | rust-v0.53 | rust-v0.54 | rust-v0.55 | rust-v0.56 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **go-v0.38** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.39** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.40** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.41** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.42** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.43** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.44** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.45** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **jvm-v1.2** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **rust-v0.53** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **rust-v0.54** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **rust-v0.55** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **rust-v0.56** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |


---

## Legend

- ✅ Test passed
- ❌ Test failed
- **-** No test run for this combination
- Each table shows results for a specific transport + secure channel + muxer combination
- Standalone transports (quic-v1, webrtc-direct, webtransport) have one table each
- Non-standalone transports (tcp, ws) have multiple tables (one per secure+muxer combo)
- Dialers are shown on the Y-axis (rows)
- Listeners are shown on the X-axis (columns)

---

*Generated: 2026-01-03T03:42:26Z*
<!-- TEST_RESULTS_END -->

