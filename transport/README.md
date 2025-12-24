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

## Test Pass: `transport-interop-030232-24-12-2025`

**Summary:**
- **Total Tests:** 2302
- **Passed:** ✅ 2258
- **Failed:** ❌ 44
- **Pass Rate:** 98.1%

**Environment:**
- **Platform:** x86_64
- **OS:** Linux
- **Workers:** 8
- **Duration:** 3804s

**Timestamps:**
- **Started:** 2025-12-24T03:02:32Z
- **Completed:** 2025-12-24T04:05:56Z

---

## Test Results

| Test | Dialer | Listener | Transport | Secure | Muxer | Status | Duration | Handshake+RTT (ms) | Ping RTT (ms) |
|------|--------|----------|-----------|--------|-------|--------|----------|-------------------|---------------|
| rust-v0.53 x rust-v0.53 (tcp, tls, yamux) | rust-v0.53 | rust-v0.53 | tcp | tls | yamux | ✅ | 4s | 138.967 | 91.936 |
| rust-v0.53 x rust-v0.53 (ws, tls, mplex) | rust-v0.53 | rust-v0.53 | ws | tls | mplex | ✅ | 5s | 268.797 | 91.754 |
| rust-v0.53 x rust-v0.53 (ws, noise, mplex) | rust-v0.53 | rust-v0.53 | ws | noise | mplex | ✅ | 5s | 264.96 | 87.982 |
| rust-v0.53 x rust-v0.53 (ws, noise, yamux) | rust-v0.53 | rust-v0.53 | ws | noise | yamux | ✅ | 5s | 273.757 | 91.885 |
| rust-v0.53 x rust-v0.53 (ws, tls, yamux) | rust-v0.53 | rust-v0.53 | ws | tls | yamux | ✅ | 6s | 275.851 | 91.738 |
| rust-v0.53 x rust-v0.53 (tcp, noise, mplex) | rust-v0.53 | rust-v0.53 | tcp | noise | mplex | ✅ | 6s | 92.609 | 0.094 |
| rust-v0.53 x rust-v0.53 (tcp, tls, mplex) | rust-v0.53 | rust-v0.53 | tcp | tls | mplex | ✅ | 6s | 49.254 | 0.127 |
| rust-v0.53 x rust-v0.53 (tcp, noise, yamux) | rust-v0.53 | rust-v0.53 | tcp | noise | yamux | ✅ | 7s | 137.301 | 43.972 |
| rust-v0.53 x rust-v0.53 (quic-v1) | rust-v0.53 | rust-v0.53 | quic-v1 | - | - | ✅ | 4s | 3.056 | 0.375 |
| rust-v0.53 x rust-v0.53 (webrtc-direct) | rust-v0.53 | rust-v0.53 | webrtc-direct | - | - | ✅ | 4s | 213.596 | 0.347 |
| rust-v0.53 x rust-v0.54 (ws, tls, yamux) | rust-v0.53 | rust-v0.54 | ws | tls | yamux | ✅ | 5s | 275.498 | 91.676 |
| rust-v0.53 x rust-v0.54 (ws, tls, mplex) | rust-v0.53 | rust-v0.54 | ws | tls | mplex | ✅ | 6s | 269.982 | 91.803 |
| rust-v0.53 x rust-v0.54 (ws, noise, yamux) | rust-v0.53 | rust-v0.54 | ws | noise | yamux | ✅ | 6s | 276.003 | 91.58 |
| rust-v0.53 x rust-v0.54 (tcp, tls, mplex) | rust-v0.53 | rust-v0.54 | tcp | tls | mplex | ✅ | 5s | 49.403 | 0.095 |
| rust-v0.53 x rust-v0.54 (ws, noise, mplex) | rust-v0.53 | rust-v0.54 | ws | noise | mplex | ✅ | 6s | 270.659 | 91.89 |
| rust-v0.53 x rust-v0.54 (tcp, tls, yamux) | rust-v0.53 | rust-v0.54 | tcp | tls | yamux | ✅ | 6s | 139.496 | 95.837 |
| rust-v0.53 x rust-v0.54 (tcp, noise, mplex) | rust-v0.53 | rust-v0.54 | tcp | noise | mplex | ✅ | 5s | 90.586 | 0.136 |
| rust-v0.53 x rust-v0.54 (tcp, noise, yamux) | rust-v0.53 | rust-v0.54 | tcp | noise | yamux | ✅ | 5s | 134.109 | 43.956 |
| rust-v0.53 x rust-v0.54 (quic-v1) | rust-v0.53 | rust-v0.54 | quic-v1 | - | - | ✅ | 4s | 6.557 | 0.213 |
| rust-v0.53 x rust-v0.54 (webrtc-direct) | rust-v0.53 | rust-v0.54 | webrtc-direct | - | - | ✅ | 4s | 225.531 | 0.697 |
| rust-v0.53 x rust-v0.55 (ws, tls, mplex) | rust-v0.53 | rust-v0.55 | ws | tls | mplex | ✅ | 5s | 136.462 | 42.973 |
| rust-v0.53 x rust-v0.55 (ws, tls, yamux) | rust-v0.53 | rust-v0.55 | ws | tls | yamux | ✅ | 5s | 130.63 | 42.239 |
| rust-v0.53 x rust-v0.55 (ws, noise, mplex) | rust-v0.53 | rust-v0.55 | ws | noise | mplex | ✅ | 5s | 88.699 | 0.205 |
| rust-v0.53 x rust-v0.55 (tcp, tls, mplex) | rust-v0.53 | rust-v0.55 | tcp | tls | mplex | ✅ | 5s | 2.705 | 0.062 |
| rust-v0.53 x rust-v0.55 (ws, noise, yamux) | rust-v0.53 | rust-v0.55 | ws | noise | yamux | ✅ | 6s | 139.698 | 47.157 |
| rust-v0.53 x rust-v0.55 (tcp, tls, yamux) | rust-v0.53 | rust-v0.55 | tcp | tls | yamux | ✅ | 6s | 2.833 | 0.148 |
| rust-v0.53 x rust-v0.55 (tcp, noise, mplex) | rust-v0.53 | rust-v0.55 | tcp | noise | mplex | ✅ | 5s | 86.978 | 43.4 |
| rust-v0.53 x rust-v0.55 (quic-v1) | rust-v0.53 | rust-v0.55 | quic-v1 | - | - | ✅ | 4s | 5.534 | 0.266 |
| rust-v0.53 x rust-v0.55 (tcp, noise, yamux) | rust-v0.53 | rust-v0.55 | tcp | noise | yamux | ✅ | 5s | 47.545 | 0.093 |
| rust-v0.53 x rust-v0.55 (webrtc-direct) | rust-v0.53 | rust-v0.55 | webrtc-direct | - | - | ✅ | 4s | 212.368 | 0.366 |
| rust-v0.53 x rust-v0.56 (ws, tls, mplex) | rust-v0.53 | rust-v0.56 | ws | tls | mplex | ✅ | 4s | 133.42 | 45.651 |
| rust-v0.53 x rust-v0.56 (ws, tls, yamux) | rust-v0.53 | rust-v0.56 | ws | tls | yamux | ✅ | 5s | 133.266 | 42.574 |
| rust-v0.53 x rust-v0.56 (ws, noise, mplex) | rust-v0.53 | rust-v0.56 | ws | noise | mplex | ✅ | 5s | 95.824 | 0.267 |
| rust-v0.53 x rust-v0.56 (ws, noise, yamux) | rust-v0.53 | rust-v0.56 | ws | noise | yamux | ✅ | 5s | 88.059 | 0.346 |
| rust-v0.53 x rust-v0.56 (tcp, tls, mplex) | rust-v0.53 | rust-v0.56 | tcp | tls | mplex | ✅ | 4s | 3.311 | 0.163 |
| rust-v0.53 x rust-v0.56 (tcp, tls, yamux) | rust-v0.53 | rust-v0.56 | tcp | tls | yamux | ✅ | 6s | 2.57 | 0.09 |
| rust-v0.53 x rust-v0.56 (tcp, noise, mplex) | rust-v0.53 | rust-v0.56 | tcp | noise | mplex | ✅ | 5s | 47.933 | 0.066 |
| rust-v0.53 x rust-v0.56 (tcp, noise, yamux) | rust-v0.53 | rust-v0.56 | tcp | noise | yamux | ✅ | 4s | 45.149 | 0.086 |
| rust-v0.53 x rust-v0.56 (quic-v1) | rust-v0.53 | rust-v0.56 | quic-v1 | - | - | ✅ | 5s | 3.136 | 0.21 |
| rust-v0.53 x rust-v0.56 (webrtc-direct) | rust-v0.53 | rust-v0.56 | webrtc-direct | - | - | ✅ | 5s | 208.514 | 0.287 |
| rust-v0.53 x go-v0.38 (ws, tls, yamux) | rust-v0.53 | go-v0.38 | ws | tls | yamux | ✅ | 5s | 91.315 | 0.536 |
| rust-v0.53 x go-v0.38 (tcp, tls, yamux) | rust-v0.53 | go-v0.38 | tcp | tls | yamux | ✅ | 4s | 47.243 | 42.162 |
| rust-v0.53 x go-v0.38 (ws, noise, yamux) | rust-v0.53 | go-v0.38 | ws | noise | yamux | ✅ | 5s | 93.642 | 3.226 |
| rust-v0.53 x go-v0.38 (tcp, noise, yamux) | rust-v0.53 | go-v0.38 | tcp | noise | yamux | ✅ | 4s | 2.377 | 0.098 |
| rust-v0.53 x go-v0.38 (quic-v1) | rust-v0.53 | go-v0.38 | quic-v1 | - | - | ✅ | 5s | 3.467 | 0.154 |
| rust-v0.53 x go-v0.38 (webrtc-direct) | rust-v0.53 | go-v0.38 | webrtc-direct | - | - | ✅ | 4s | 87.891 | 0.549 |
| rust-v0.53 x go-v0.39 (ws, tls, yamux) | rust-v0.53 | go-v0.39 | ws | tls | yamux | ✅ | 5s | 89.751 | 0.274 |
| rust-v0.53 x go-v0.39 (tcp, tls, yamux) | rust-v0.53 | go-v0.39 | tcp | tls | yamux | ✅ | 4s | 45.813 | 41.815 |
| rust-v0.53 x go-v0.39 (ws, noise, yamux) | rust-v0.53 | go-v0.39 | ws | noise | yamux | ✅ | 6s | 87.569 | 0.216 |
| rust-v0.53 x go-v0.39 (tcp, noise, yamux) | rust-v0.53 | go-v0.39 | tcp | noise | yamux | ✅ | 5s | 4.081 | 0.233 |
| rust-v0.53 x go-v0.39 (quic-v1) | rust-v0.53 | go-v0.39 | quic-v1 | - | - | ✅ | 5s | 6.102 | 0.866 |
| rust-v0.53 x go-v0.39 (webrtc-direct) | rust-v0.53 | go-v0.39 | webrtc-direct | - | - | ✅ | 5s | 13.515 | 0.413 |
| rust-v0.53 x go-v0.40 (ws, tls, yamux) | rust-v0.53 | go-v0.40 | ws | tls | yamux | ✅ | 5s | 88.94 | 0.471 |
| rust-v0.53 x go-v0.40 (ws, noise, yamux) | rust-v0.53 | go-v0.40 | ws | noise | yamux | ✅ | 5s | 88.03 | 0.25 |
| rust-v0.53 x go-v0.40 (tcp, tls, yamux) | rust-v0.53 | go-v0.40 | tcp | tls | yamux | ✅ | 5s | 4.242 | 0.238 |
| rust-v0.53 x go-v0.40 (tcp, noise, yamux) | rust-v0.53 | go-v0.40 | tcp | noise | yamux | ✅ | 4s | 3.296 | 0.141 |
| rust-v0.53 x go-v0.40 (quic-v1) | rust-v0.53 | go-v0.40 | quic-v1 | - | - | ✅ | 4s | 11.669 | 0.507 |
| rust-v0.53 x go-v0.40 (webrtc-direct) | rust-v0.53 | go-v0.40 | webrtc-direct | - | - | ✅ | 4s | 11.623 | 0.328 |
| rust-v0.53 x go-v0.41 (ws, tls, yamux) | rust-v0.53 | go-v0.41 | ws | tls | yamux | ✅ | 5s | 93.24 | 0.198 |
| rust-v0.53 x go-v0.41 (ws, noise, yamux) | rust-v0.53 | go-v0.41 | ws | noise | yamux | ✅ | 5s | 89.298 | 0.44 |
| rust-v0.53 x go-v0.41 (tcp, tls, yamux) | rust-v0.53 | go-v0.41 | tcp | tls | yamux | ✅ | 5s | 5.054 | 0.749 |
| rust-v0.53 x go-v0.41 (tcp, noise, yamux) | rust-v0.53 | go-v0.41 | tcp | noise | yamux | ✅ | 4s | 2.681 | 0.387 |
| rust-v0.53 x go-v0.41 (quic-v1) | rust-v0.53 | go-v0.41 | quic-v1 | - | - | ✅ | 5s | 6.419 | 0.457 |
| rust-v0.53 x go-v0.41 (webrtc-direct) | rust-v0.53 | go-v0.41 | webrtc-direct | - | - | ✅ | 5s | 56.299 | 0.646 |
| rust-v0.53 x go-v0.42 (ws, tls, yamux) | rust-v0.53 | go-v0.42 | ws | tls | yamux | ✅ | 4s | 90.1 | 0.558 |
| rust-v0.53 x go-v0.42 (ws, noise, yamux) | rust-v0.53 | go-v0.42 | ws | noise | yamux | ✅ | 4s | 88.728 | 0.181 |
| rust-v0.53 x go-v0.42 (tcp, tls, yamux) | rust-v0.53 | go-v0.42 | tcp | tls | yamux | ✅ | 5s | 49.659 | 45.447 |
| rust-v0.53 x go-v0.42 (tcp, noise, yamux) | rust-v0.53 | go-v0.42 | tcp | noise | yamux | ✅ | 4s | 2.051 | 0.067 |
| rust-v0.53 x go-v0.42 (quic-v1) | rust-v0.53 | go-v0.42 | quic-v1 | - | - | ✅ | 5s | 6.128 | 0.284 |
| rust-v0.53 x go-v0.42 (webrtc-direct) | rust-v0.53 | go-v0.42 | webrtc-direct | - | - | ✅ | 4s | 10.841 | 0.403 |
| rust-v0.53 x go-v0.43 (ws, tls, yamux) | rust-v0.53 | go-v0.43 | ws | tls | yamux | ✅ | 5s | 96.73 | 0.332 |
| rust-v0.53 x go-v0.43 (ws, noise, yamux) | rust-v0.53 | go-v0.43 | ws | noise | yamux | ✅ | 5s | 92.034 | 3.998 |
| rust-v0.53 x go-v0.43 (tcp, tls, yamux) | rust-v0.53 | go-v0.43 | tcp | tls | yamux | ✅ | 6s | 7.972 | 1.077 |
| rust-v0.53 x go-v0.43 (tcp, noise, yamux) | rust-v0.53 | go-v0.43 | tcp | noise | yamux | ✅ | 5s | 6.254 | 0.349 |
| rust-v0.53 x go-v0.43 (quic-v1) | rust-v0.53 | go-v0.43 | quic-v1 | - | - | ✅ | 5s | 3.759 | 0.514 |
| rust-v0.53 x go-v0.43 (webrtc-direct) | rust-v0.53 | go-v0.43 | webrtc-direct | - | - | ✅ | 5s | 15.18 | 0.267 |
| rust-v0.53 x go-v0.44 (ws, noise, yamux) | rust-v0.53 | go-v0.44 | ws | noise | yamux | ✅ | 4s | 96.068 | 0.94 |
| rust-v0.53 x go-v0.44 (ws, tls, yamux) | rust-v0.53 | go-v0.44 | ws | tls | yamux | ✅ | 5s | 141.191 | 41.961 |
| rust-v0.53 x go-v0.44 (tcp, tls, yamux) | rust-v0.53 | go-v0.44 | tcp | tls | yamux | ✅ | 5s | 4.088 | 0.208 |
| rust-v0.53 x go-v0.44 (tcp, noise, yamux) | rust-v0.53 | go-v0.44 | tcp | noise | yamux | ✅ | 5s | 4.061 | 0.312 |
| rust-v0.53 x go-v0.44 (quic-v1) | rust-v0.53 | go-v0.44 | quic-v1 | - | - | ✅ | 4s | 10.24 | 0.463 |
| rust-v0.53 x go-v0.44 (webrtc-direct) | rust-v0.53 | go-v0.44 | webrtc-direct | - | - | ✅ | 4s | 31.768 | 0.318 |
| rust-v0.53 x go-v0.45 (ws, tls, yamux) | rust-v0.53 | go-v0.45 | ws | tls | yamux | ✅ | 5s | 90.609 | 43.214 |
| rust-v0.53 x go-v0.45 (ws, noise, yamux) | rust-v0.53 | go-v0.45 | ws | noise | yamux | ✅ | 5s | 88.532 | 0.312 |
| rust-v0.53 x go-v0.45 (tcp, tls, yamux) | rust-v0.53 | go-v0.45 | tcp | tls | yamux | ✅ | 5s | 6.232 | 1.005 |
| rust-v0.53 x go-v0.45 (tcp, noise, yamux) | rust-v0.53 | go-v0.45 | tcp | noise | yamux | ✅ | 4s | 6.235 | 1.572 |
| rust-v0.53 x go-v0.45 (quic-v1) | rust-v0.53 | go-v0.45 | quic-v1 | - | - | ✅ | 5s | 8.432 | 0.322 |
| rust-v0.53 x go-v0.45 (webrtc-direct) | rust-v0.53 | go-v0.45 | webrtc-direct | - | - | ✅ | 5s | 28.326 | 0.818 |
| rust-v0.53 x python-v0.4 (ws, noise, mplex) | rust-v0.53 | python-v0.4 | ws | noise | mplex | ✅ | 4s | 61.591 | 1.628 |
| rust-v0.53 x python-v0.4 (ws, noise, yamux) | rust-v0.53 | python-v0.4 | ws | noise | yamux | ✅ | 5s | 100.171 | 1.062 |
| rust-v0.53 x python-v0.4 (tcp, noise, mplex) | rust-v0.53 | python-v0.4 | tcp | noise | mplex | ✅ | 5s | 13.735 | 0.639 |
| rust-v0.53 x python-v0.4 (tcp, noise, yamux) | rust-v0.53 | python-v0.4 | tcp | noise | yamux | ✅ | 4s | 56.75 | 44.502 |
| rust-v0.53 x python-v0.4 (quic-v1) | rust-v0.53 | python-v0.4 | quic-v1 | - | - | ✅ | 5s | 41.773 | 6.429 |
| rust-v0.53 x js-v1.x (ws, noise, mplex) | rust-v0.53 | js-v1.x | ws | noise | mplex | ✅ | 16s | 230.001 | 17.781 |
| rust-v0.53 x js-v1.x (ws, noise, yamux) | rust-v0.53 | js-v1.x | ws | noise | yamux | ✅ | 18s | 213.529 | 16.61 |
| rust-v0.53 x js-v1.x (tcp, noise, yamux) | rust-v0.53 | js-v1.x | tcp | noise | yamux | ✅ | 17s | 146.23 | 10.598 |
| rust-v0.53 x js-v1.x (tcp, noise, mplex) | rust-v0.53 | js-v1.x | tcp | noise | mplex | ✅ | 17s | 143.846 | 11.814 |
| rust-v0.53 x js-v2.x (ws, noise, mplex) | rust-v0.53 | js-v2.x | ws | noise | mplex | ✅ | 18s | 195.728 | 15.49 |
| rust-v0.53 x js-v2.x (ws, noise, yamux) | rust-v0.53 | js-v2.x | ws | noise | yamux | ✅ | 17s | 233.809 | 17.847 |
| rust-v0.53 x js-v2.x (tcp, noise, mplex) | rust-v0.53 | js-v2.x | tcp | noise | mplex | ✅ | 18s | 184.202 | 48.426 |
| rust-v0.53 x js-v2.x (tcp, noise, yamux) | rust-v0.53 | js-v2.x | tcp | noise | yamux | ✅ | 17s | 126.754 | 7.022 |
| rust-v0.53 x nim-v1.14 (ws, noise, mplex) | rust-v0.53 | nim-v1.14 | ws | noise | mplex | ✅ | 5s | 287.543 | 87.743 |
| rust-v0.53 x nim-v1.14 (ws, noise, yamux) | rust-v0.53 | nim-v1.14 | ws | noise | yamux | ✅ | 5s | 242.125 | 50.47 |
| rust-v0.53 x nim-v1.14 (tcp, noise, mplex) | rust-v0.53 | nim-v1.14 | tcp | noise | mplex | ✅ | 4s | 144.796 | 0.9 |
| rust-v0.53 x nim-v1.14 (tcp, noise, yamux) | rust-v0.53 | nim-v1.14 | tcp | noise | yamux | ✅ | 4s | 189.855 | 45.284 |
| rust-v0.53 x js-v3.x (ws, noise, mplex) | rust-v0.53 | js-v3.x | ws | noise | mplex | ✅ | 15s | 205.133 | 31.785 |
| rust-v0.53 x js-v3.x (ws, noise, yamux) | rust-v0.53 | js-v3.x | ws | noise | yamux | ✅ | 16s | 198.456 | 20.556 |
| rust-v0.53 x js-v3.x (tcp, noise, yamux) | rust-v0.53 | js-v3.x | tcp | noise | yamux | ✅ | 18s | 181.908 | 47.989 |
| rust-v0.53 x js-v3.x (tcp, noise, mplex) | rust-v0.53 | js-v3.x | tcp | noise | mplex | ✅ | 18s | 175.094 | 54.467 |
| rust-v0.53 x jvm-v1.2 (ws, tls, mplex) | rust-v0.53 | jvm-v1.2 | ws | tls | mplex | ✅ | 12s | 4830.385 | 17.845 |
| rust-v0.53 x jvm-v1.2 (ws, noise, mplex) | rust-v0.53 | jvm-v1.2 | ws | noise | mplex | ✅ | 11s | 1973.019 | 55.398 |
| rust-v0.53 x jvm-v1.2 (ws, tls, yamux) | rust-v0.53 | jvm-v1.2 | ws | tls | yamux | ✅ | 12s | 4297.261 | 44.883 |
| rust-v0.53 x jvm-v1.2 (ws, noise, yamux) | rust-v0.53 | jvm-v1.2 | ws | noise | yamux | ✅ | 11s | 1094.491 | 45.772 |
| rust-v0.53 x jvm-v1.2 (tcp, tls, mplex) | rust-v0.53 | jvm-v1.2 | tcp | tls | mplex | ✅ | 10s | 1922.211 | 3.896 |
| rust-v0.53 x c-v0.0.1 (quic-v1) | rust-v0.53 | c-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 37.176 | 11.801 |
| rust-v0.53 x jvm-v1.2 (tcp, noise, mplex) | rust-v0.53 | jvm-v1.2 | tcp | noise | mplex | ✅ | 9s | 1111.279 | 58.296 |
| rust-v0.53 x c-v0.0.1 (tcp, noise, yamux) | rust-v0.53 | c-v0.0.1 | tcp | noise | yamux | ✅ | 6s | 118.308 | 5.914 |
| rust-v0.53 x jvm-v1.2 (tcp, tls, yamux) | rust-v0.53 | jvm-v1.2 | tcp | tls | yamux | ✅ | 12s | 3545.245 | 44.888 |
| rust-v0.53 x jvm-v1.2 (tcp, noise, yamux) | rust-v0.53 | jvm-v1.2 | tcp | noise | yamux | ✅ | 10s | 1105.077 | 4.206 |
| rust-v0.53 x jvm-v1.2 (quic-v1) | rust-v0.53 | jvm-v1.2 | quic-v1 | - | - | ✅ | 10s | 787.743 | 8.183 |
| rust-v0.53 x dotnet-v1.0 (tcp, noise, yamux) | rust-v0.53 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 5s | 120.865 | 9.344 |
| rust-v0.53 x zig-v0.0.1 (quic-v1) | rust-v0.53 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 4s | - | - |
| rust-v0.53 x eth-p2p-z-v0.0.1 (quic-v1) | rust-v0.53 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 5s | 3.848 | 0.183 |
| rust-v0.54 x rust-v0.53 (ws, tls, mplex) | rust-v0.54 | rust-v0.53 | ws | tls | mplex | ✅ | 4s | 267.573 | 91.751 |
| rust-v0.54 x rust-v0.53 (ws, noise, mplex) | rust-v0.54 | rust-v0.53 | ws | noise | mplex | ✅ | 5s | 286.387 | 95.927 |
| rust-v0.54 x rust-v0.53 (ws, tls, yamux) | rust-v0.54 | rust-v0.53 | ws | tls | yamux | ✅ | 5s | 271.64 | 91.632 |
| rust-v0.54 x rust-v0.53 (ws, noise, yamux) | rust-v0.54 | rust-v0.53 | ws | noise | yamux | ✅ | 5s | 270.513 | 87.653 |
| rust-v0.54 x rust-v0.53 (tcp, tls, mplex) | rust-v0.54 | rust-v0.53 | tcp | tls | mplex | ✅ | 4s | 45.87 | 0.101 |
| rust-v0.53 x c-v0.0.1 (tcp, noise, mplex) | rust-v0.53 | c-v0.0.1 | tcp | noise | mplex | ✅ | 14s | 10015.121 | 0.172 |
| rust-v0.54 x rust-v0.53 (tcp, tls, yamux) | rust-v0.54 | rust-v0.53 | tcp | tls | yamux | ✅ | 3s | 144.476 | 87.741 |
| rust-v0.54 x rust-v0.53 (tcp, noise, mplex) | rust-v0.54 | rust-v0.53 | tcp | noise | mplex | ✅ | 4s | 94.319 | 0.117 |
| rust-v0.54 x rust-v0.53 (quic-v1) | rust-v0.54 | rust-v0.53 | quic-v1 | - | - | ✅ | 4s | 9.555 | 1.164 |
| rust-v0.54 x rust-v0.53 (tcp, noise, yamux) | rust-v0.54 | rust-v0.53 | tcp | noise | yamux | ✅ | 5s | 135.937 | 44.89 |
| rust-v0.54 x rust-v0.54 (ws, tls, mplex) | rust-v0.54 | rust-v0.54 | ws | tls | mplex | ✅ | 4s | 262.555 | 88.544 |
| rust-v0.54 x rust-v0.53 (webrtc-direct) | rust-v0.54 | rust-v0.53 | webrtc-direct | - | - | ✅ | 5s | 254.292 | 0.479 |
| rust-v0.54 x rust-v0.54 (ws, tls, yamux) | rust-v0.54 | rust-v0.54 | ws | tls | yamux | ✅ | 6s | 267.659 | 91.706 |
| rust-v0.54 x rust-v0.54 (ws, noise, mplex) | rust-v0.54 | rust-v0.54 | ws | noise | mplex | ✅ | 4s | 268.895 | 88.048 |
| rust-v0.54 x rust-v0.54 (ws, noise, yamux) | rust-v0.54 | rust-v0.54 | ws | noise | yamux | ✅ | 5s | 268.666 | 93.763 |
| rust-v0.54 x rust-v0.54 (tcp, tls, mplex) | rust-v0.54 | rust-v0.54 | tcp | tls | mplex | ✅ | 6s | 50.635 | 0.098 |
| rust-v0.54 x rust-v0.54 (tcp, tls, yamux) | rust-v0.54 | rust-v0.54 | tcp | tls | yamux | ✅ | 5s | 139.813 | 95.897 |
| rust-v0.54 x rust-v0.54 (tcp, noise, mplex) | rust-v0.54 | rust-v0.54 | tcp | noise | mplex | ✅ | 4s | 89.351 | 0.13 |
| rust-v0.54 x rust-v0.54 (tcp, noise, yamux) | rust-v0.54 | rust-v0.54 | tcp | noise | yamux | ✅ | 4s | 130.935 | 43.908 |
| rust-v0.54 x rust-v0.54 (quic-v1) | rust-v0.54 | rust-v0.54 | quic-v1 | - | - | ✅ | 5s | 4.926 | 0.32 |
| rust-v0.54 x rust-v0.55 (ws, tls, mplex) | rust-v0.54 | rust-v0.55 | ws | tls | mplex | ✅ | 4s | 142.084 | 45.969 |
| rust-v0.54 x rust-v0.54 (webrtc-direct) | rust-v0.54 | rust-v0.54 | webrtc-direct | - | - | ✅ | 5s | 211.181 | 0.337 |
| rust-v0.54 x rust-v0.55 (ws, tls, yamux) | rust-v0.54 | rust-v0.55 | ws | tls | yamux | ✅ | 5s | 132.775 | 41.807 |
| rust-v0.54 x rust-v0.55 (ws, noise, yamux) | rust-v0.54 | rust-v0.55 | ws | noise | yamux | ✅ | 5s | 134.349 | 43.033 |
| rust-v0.54 x rust-v0.55 (ws, noise, mplex) | rust-v0.54 | rust-v0.55 | ws | noise | mplex | ✅ | 5s | 139.652 | 47.092 |
| rust-v0.54 x rust-v0.55 (tcp, tls, mplex) | rust-v0.54 | rust-v0.55 | tcp | tls | mplex | ✅ | 5s | 4.63 | 0.494 |
| rust-v0.54 x rust-v0.55 (tcp, noise, mplex) | rust-v0.54 | rust-v0.55 | tcp | noise | mplex | ✅ | 5s | 46.341 | 0.341 |
| rust-v0.54 x rust-v0.55 (tcp, tls, yamux) | rust-v0.54 | rust-v0.55 | tcp | tls | yamux | ✅ | 5s | 50.914 | 44.827 |
| rust-v0.54 x rust-v0.55 (tcp, noise, yamux) | rust-v0.54 | rust-v0.55 | tcp | noise | yamux | ✅ | 5s | 46.088 | 0.114 |
| rust-v0.54 x rust-v0.55 (quic-v1) | rust-v0.54 | rust-v0.55 | quic-v1 | - | - | ✅ | 4s | 3.284 | 0.248 |
| rust-v0.54 x rust-v0.55 (webrtc-direct) | rust-v0.54 | rust-v0.55 | webrtc-direct | - | - | ✅ | 5s | 265.891 | 0.342 |
| rust-v0.54 x rust-v0.56 (ws, tls, mplex) | rust-v0.54 | rust-v0.56 | ws | tls | mplex | ✅ | 5s | 134.16 | 46.019 |
| rust-v0.54 x rust-v0.56 (ws, tls, yamux) | rust-v0.54 | rust-v0.56 | ws | tls | yamux | ✅ | 4s | 138.456 | 42.35 |
| rust-v0.54 x rust-v0.56 (ws, noise, mplex) | rust-v0.54 | rust-v0.56 | ws | noise | mplex | ✅ | 5s | 139.279 | 43.142 |
| rust-v0.54 x rust-v0.56 (ws, noise, yamux) | rust-v0.54 | rust-v0.56 | ws | noise | yamux | ✅ | 5s | 139.109 | 47.208 |
| rust-v0.54 x rust-v0.56 (tcp, tls, mplex) | rust-v0.54 | rust-v0.56 | tcp | tls | mplex | ✅ | 4s | 44.919 | 41.667 |
| rust-v0.54 x rust-v0.56 (tcp, tls, yamux) | rust-v0.54 | rust-v0.56 | tcp | tls | yamux | ✅ | 5s | 46.916 | 44.162 |
| rust-v0.54 x rust-v0.56 (tcp, noise, mplex) | rust-v0.54 | rust-v0.56 | tcp | noise | mplex | ✅ | 4s | 87.598 | 43.057 |
| rust-v0.54 x rust-v0.56 (tcp, noise, yamux) | rust-v0.54 | rust-v0.56 | tcp | noise | yamux | ✅ | 5s | 95.82 | 47.889 |
| rust-v0.54 x rust-v0.56 (quic-v1) | rust-v0.54 | rust-v0.56 | quic-v1 | - | - | ✅ | 5s | 5.339 | 0.301 |
| rust-v0.54 x rust-v0.56 (webrtc-direct) | rust-v0.54 | rust-v0.56 | webrtc-direct | - | - | ✅ | 4s | 209.38 | 0.248 |
| rust-v0.54 x go-v0.38 (ws, tls, yamux) | rust-v0.54 | go-v0.38 | ws | tls | yamux | ✅ | 4s | 91.183 | 0.188 |
| rust-v0.54 x go-v0.38 (ws, noise, yamux) | rust-v0.54 | go-v0.38 | ws | noise | yamux | ✅ | 5s | 99.789 | 1.282 |
| rust-v0.54 x go-v0.38 (tcp, tls, yamux) | rust-v0.54 | go-v0.38 | tcp | tls | yamux | ✅ | 5s | 5.886 | 0.938 |
| rust-v0.54 x go-v0.38 (tcp, noise, yamux) | rust-v0.54 | go-v0.38 | tcp | noise | yamux | ✅ | 5s | 4.906 | 0.33 |
| rust-v0.54 x go-v0.38 (quic-v1) | rust-v0.54 | go-v0.38 | quic-v1 | - | - | ✅ | 5s | 4.44 | 0.236 |
| rust-v0.54 x go-v0.38 (webrtc-direct) | rust-v0.54 | go-v0.38 | webrtc-direct | - | - | ✅ | 5s | 77.533 | 0.579 |
| rust-v0.54 x go-v0.39 (ws, tls, yamux) | rust-v0.54 | go-v0.39 | ws | tls | yamux | ✅ | 6s | 96.01 | 0.527 |
| rust-v0.54 x go-v0.39 (tcp, tls, yamux) | rust-v0.54 | go-v0.39 | tcp | tls | yamux | ✅ | 4s | 5.02 | 0.236 |
| rust-v0.54 x go-v0.39 (ws, noise, yamux) | rust-v0.54 | go-v0.39 | ws | noise | yamux | ✅ | 5s | 96.034 | 0.802 |
| rust-v0.54 x go-v0.39 (tcp, noise, yamux) | rust-v0.54 | go-v0.39 | tcp | noise | yamux | ✅ | 5s | 4.937 | 1.017 |
| rust-v0.54 x go-v0.39 (quic-v1) | rust-v0.54 | go-v0.39 | quic-v1 | - | - | ✅ | 4s | 12.152 | 0.395 |
| rust-v0.54 x go-v0.39 (webrtc-direct) | rust-v0.54 | go-v0.39 | webrtc-direct | - | - | ✅ | 5s | 76.435 | 0.582 |
| rust-v0.54 x go-v0.40 (ws, tls, yamux) | rust-v0.54 | go-v0.40 | ws | tls | yamux | ✅ | 4s | 91.036 | 0.538 |
| rust-v0.54 x go-v0.40 (ws, noise, yamux) | rust-v0.54 | go-v0.40 | ws | noise | yamux | ✅ | 4s | 134.892 | 46.327 |
| rust-v0.54 x go-v0.40 (tcp, tls, yamux) | rust-v0.54 | go-v0.40 | tcp | tls | yamux | ✅ | 4s | 7.847 | 0.347 |
| rust-v0.54 x go-v0.40 (tcp, noise, yamux) | rust-v0.54 | go-v0.40 | tcp | noise | yamux | ✅ | 5s | 5.254 | 0.669 |
| rust-v0.54 x go-v0.40 (quic-v1) | rust-v0.54 | go-v0.40 | quic-v1 | - | - | ✅ | 4s | 4.315 | 0.274 |
| rust-v0.54 x go-v0.40 (webrtc-direct) | rust-v0.54 | go-v0.40 | webrtc-direct | - | - | ✅ | 5s | 13.128 | 0.667 |
| rust-v0.54 x go-v0.41 (ws, tls, yamux) | rust-v0.54 | go-v0.41 | ws | tls | yamux | ✅ | 5s | 134.777 | 41.627 |
| rust-v0.54 x go-v0.41 (tcp, tls, yamux) | rust-v0.54 | go-v0.41 | tcp | tls | yamux | ✅ | 4s | 3.914 | 1.056 |
| rust-v0.54 x go-v0.41 (ws, noise, yamux) | rust-v0.54 | go-v0.41 | ws | noise | yamux | ✅ | 5s | 131.553 | 40.963 |
| rust-v0.54 x go-v0.41 (tcp, noise, yamux) | rust-v0.54 | go-v0.41 | tcp | noise | yamux | ✅ | 4s | 46.13 | 41.6 |
| rust-v0.54 x go-v0.41 (quic-v1) | rust-v0.54 | go-v0.41 | quic-v1 | - | - | ✅ | 4s | 5.981 | 0.349 |
| rust-v0.54 x go-v0.41 (webrtc-direct) | rust-v0.54 | go-v0.41 | webrtc-direct | - | - | ✅ | 5s | 18.417 | 0.4 |
| rust-v0.54 x go-v0.42 (ws, tls, yamux) | rust-v0.54 | go-v0.42 | ws | tls | yamux | ✅ | 4s | 90.076 | 0.45 |
| rust-v0.54 x go-v0.42 (ws, noise, yamux) | rust-v0.54 | go-v0.42 | ws | noise | yamux | ✅ | 5s | 88.929 | 0.379 |
| rust-v0.54 x go-v0.42 (tcp, tls, yamux) | rust-v0.54 | go-v0.42 | tcp | tls | yamux | ✅ | 5s | 4.605 | 0.59 |
| rust-v0.54 x go-v0.42 (tcp, noise, yamux) | rust-v0.54 | go-v0.42 | tcp | noise | yamux | ✅ | 4s | 52.359 | 42.535 |
| rust-v0.54 x go-v0.42 (quic-v1) | rust-v0.54 | go-v0.42 | quic-v1 | - | - | ✅ | 5s | 8.77 | 0.545 |
| rust-v0.54 x go-v0.42 (webrtc-direct) | rust-v0.54 | go-v0.42 | webrtc-direct | - | - | ✅ | 4s | 18.815 | 0.357 |
| rust-v0.54 x go-v0.43 (ws, tls, yamux) | rust-v0.54 | go-v0.43 | ws | tls | yamux | ✅ | 4s | 95.308 | 0.364 |
| rust-v0.54 x go-v0.43 (ws, noise, yamux) | rust-v0.54 | go-v0.43 | ws | noise | yamux | ✅ | 5s | 134.005 | 41.9 |
| rust-v0.54 x go-v0.43 (tcp, tls, yamux) | rust-v0.54 | go-v0.43 | tcp | tls | yamux | ✅ | 4s | 9.399 | 0.258 |
| rust-v0.54 x go-v0.43 (tcp, noise, yamux) | rust-v0.54 | go-v0.43 | tcp | noise | yamux | ✅ | 5s | 2.856 | 0.12 |
| rust-v0.54 x go-v0.43 (quic-v1) | rust-v0.54 | go-v0.43 | quic-v1 | - | - | ✅ | 5s | 10.04 | 1.199 |
| rust-v0.54 x go-v0.43 (webrtc-direct) | rust-v0.54 | go-v0.43 | webrtc-direct | - | - | ✅ | 5s | 21.647 | 0.482 |
| rust-v0.54 x go-v0.44 (ws, tls, yamux) | rust-v0.54 | go-v0.44 | ws | tls | yamux | ✅ | 5s | 139.278 | 41.887 |
| rust-v0.54 x go-v0.44 (ws, noise, yamux) | rust-v0.54 | go-v0.44 | ws | noise | yamux | ✅ | 4s | 141.462 | 45.848 |
| rust-v0.54 x go-v0.44 (tcp, tls, yamux) | rust-v0.54 | go-v0.44 | tcp | tls | yamux | ✅ | 4s | 9.537 | 0.383 |
| rust-v0.54 x go-v0.44 (tcp, noise, yamux) | rust-v0.54 | go-v0.44 | tcp | noise | yamux | ✅ | 5s | 13.296 | 0.578 |
| rust-v0.54 x go-v0.44 (quic-v1) | rust-v0.54 | go-v0.44 | quic-v1 | - | - | ✅ | 5s | 19.78 | 5.1 |
| rust-v0.54 x go-v0.44 (webrtc-direct) | rust-v0.54 | go-v0.44 | webrtc-direct | - | - | ✅ | 4s | 20.941 | 0.28 |
| rust-v0.54 x go-v0.45 (ws, tls, yamux) | rust-v0.54 | go-v0.45 | ws | tls | yamux | ✅ | 4s | 97.819 | 1.241 |
| rust-v0.54 x go-v0.45 (ws, noise, yamux) | rust-v0.54 | go-v0.45 | ws | noise | yamux | ✅ | 4s | 90.43 | 0.994 |
| rust-v0.54 x go-v0.45 (tcp, tls, yamux) | rust-v0.54 | go-v0.45 | tcp | tls | yamux | ✅ | 5s | 52.076 | 42.707 |
| rust-v0.54 x go-v0.45 (tcp, noise, yamux) | rust-v0.54 | go-v0.45 | tcp | noise | yamux | ✅ | 5s | 6.841 | 0.178 |
| rust-v0.54 x go-v0.45 (quic-v1) | rust-v0.54 | go-v0.45 | quic-v1 | - | - | ✅ | 4s | 5.086 | 0.223 |
| rust-v0.54 x go-v0.45 (webrtc-direct) | rust-v0.54 | go-v0.45 | webrtc-direct | - | - | ✅ | 4s | 83.478 | 2.805 |
| rust-v0.54 x python-v0.4 (ws, noise, mplex) | rust-v0.54 | python-v0.4 | ws | noise | mplex | ✅ | 5s | 105.739 | 2.011 |
| rust-v0.54 x python-v0.4 (ws, noise, yamux) | rust-v0.54 | python-v0.4 | ws | noise | yamux | ✅ | 5s | 106.556 | 2.318 |
| rust-v0.54 x python-v0.4 (tcp, noise, yamux) | rust-v0.54 | python-v0.4 | tcp | noise | yamux | ✅ | 4s | 20.257 | 1.348 |
| rust-v0.54 x python-v0.4 (tcp, noise, mplex) | rust-v0.54 | python-v0.4 | tcp | noise | mplex | ✅ | 6s | 12.868 | 0.739 |
| rust-v0.54 x python-v0.4 (quic-v1) | rust-v0.54 | python-v0.4 | quic-v1 | - | - | ✅ | 5s | 82.106 | 10.486 |
| rust-v0.54 x js-v1.x (ws, noise, mplex) | rust-v0.54 | js-v1.x | ws | noise | mplex | ✅ | 20s | 216.886 | 13.813 |
| rust-v0.54 x js-v1.x (tcp, noise, mplex) | rust-v0.54 | js-v1.x | tcp | noise | mplex | ✅ | 19s | 137.075 | 22.401 |
| rust-v0.54 x js-v1.x (ws, noise, yamux) | rust-v0.54 | js-v1.x | ws | noise | yamux | ✅ | 20s | 283.876 | 14.795 |
| rust-v0.54 x js-v1.x (tcp, noise, yamux) | rust-v0.54 | js-v1.x | tcp | noise | yamux | ✅ | 19s | 139.513 | 12.068 |
| rust-v0.54 x js-v2.x (ws, noise, mplex) | rust-v0.54 | js-v2.x | ws | noise | mplex | ✅ | 19s | 215.193 | 17.665 |
| rust-v0.54 x js-v2.x (ws, noise, yamux) | rust-v0.54 | js-v2.x | ws | noise | yamux | ✅ | 20s | 215.287 | 16.806 |
| rust-v0.54 x js-v2.x (tcp, noise, mplex) | rust-v0.54 | js-v2.x | tcp | noise | mplex | ✅ | 20s | 129.555 | 9.016 |
| rust-v0.54 x js-v2.x (tcp, noise, yamux) | rust-v0.54 | js-v2.x | tcp | noise | yamux | ✅ | 19s | 167.4 | 65.308 |
| rust-v0.54 x nim-v1.14 (ws, noise, mplex) | rust-v0.54 | nim-v1.14 | ws | noise | mplex | ✅ | 4s | 300.716 | 91.696 |
| rust-v0.54 x nim-v1.14 (ws, noise, yamux) | rust-v0.54 | nim-v1.14 | ws | noise | yamux | ✅ | 5s | 252.084 | 45.971 |
| rust-v0.54 x nim-v1.14 (tcp, noise, mplex) | rust-v0.54 | nim-v1.14 | tcp | noise | mplex | ✅ | 5s | 112.344 | 4.073 |
| rust-v0.54 x nim-v1.14 (tcp, noise, yamux) | rust-v0.54 | nim-v1.14 | tcp | noise | yamux | ✅ | 4s | 143.999 | 45.329 |
| rust-v0.54 x js-v3.x (ws, noise, mplex) | rust-v0.54 | js-v3.x | ws | noise | mplex | ✅ | 17s | 220.25 | 28.393 |
| rust-v0.54 x js-v3.x (ws, noise, yamux) | rust-v0.54 | js-v3.x | ws | noise | yamux | ✅ | 19s | 259.679 | 43.968 |
| rust-v0.54 x js-v3.x (tcp, noise, mplex) | rust-v0.54 | js-v3.x | tcp | noise | mplex | ✅ | 20s | 167.109 | 18.65 |
| rust-v0.54 x js-v3.x (tcp, noise, yamux) | rust-v0.54 | js-v3.x | tcp | noise | yamux | ✅ | 20s | 135.962 | 21.853 |
| rust-v0.54 x jvm-v1.2 (ws, tls, mplex) | rust-v0.54 | jvm-v1.2 | ws | tls | mplex | ✅ | 14s | 4961.767 | 11.86 |
| rust-v0.54 x jvm-v1.2 (ws, noise, mplex) | rust-v0.54 | jvm-v1.2 | ws | noise | mplex | ✅ | 11s | 1283.287 | 46.833 |
| rust-v0.54 x jvm-v1.2 (ws, noise, yamux) | rust-v0.54 | jvm-v1.2 | ws | noise | yamux | ✅ | 12s | 1511.088 | 43.497 |
| rust-v0.54 x jvm-v1.2 (ws, tls, yamux) | rust-v0.54 | jvm-v1.2 | ws | tls | yamux | ✅ | 14s | 4177.152 | 43.617 |
| rust-v0.54 x jvm-v1.2 (tcp, tls, mplex) | rust-v0.54 | jvm-v1.2 | tcp | tls | mplex | ✅ | 11s | 3715.277 | 13.167 |
| rust-v0.54 x c-v0.0.1 (tcp, noise, mplex) | rust-v0.54 | c-v0.0.1 | tcp | noise | mplex | ✅ | 7s | 52.367 | 2.135 |
| rust-v0.54 x c-v0.0.1 (tcp, noise, yamux) | rust-v0.54 | c-v0.0.1 | tcp | noise | yamux | ✅ | 6s | 107.538 | 2.656 |
| rust-v0.54 x c-v0.0.1 (quic-v1) | rust-v0.54 | c-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 46.187 | 29.882 |
| rust-v0.54 x jvm-v1.2 (tcp, noise, mplex) | rust-v0.54 | jvm-v1.2 | tcp | noise | mplex | ✅ | 10s | 1209.05 | 3.443 |
| rust-v0.54 x jvm-v1.2 (tcp, tls, yamux) | rust-v0.54 | jvm-v1.2 | tcp | tls | yamux | ✅ | 12s | 3622.992 | 42.626 |
| rust-v0.54 x jvm-v1.2 (tcp, noise, yamux) | rust-v0.54 | jvm-v1.2 | tcp | noise | yamux | ✅ | 11s | 1033.449 | 3.462 |
| rust-v0.54 x jvm-v1.2 (quic-v1) | rust-v0.54 | jvm-v1.2 | quic-v1 | - | - | ✅ | 13s | 1719.597 | 8.005 |
| rust-v0.54 x dotnet-v1.0 (tcp, noise, yamux) | rust-v0.54 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 4s | 204.034 | 10.08 |
| rust-v0.54 x eth-p2p-z-v0.0.1 (quic-v1) | rust-v0.54 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 4s | 4.156 | 0.168 |
| rust-v0.54 x zig-v0.0.1 (quic-v1) | rust-v0.54 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 5s | - | - |
| rust-v0.55 x rust-v0.53 (ws, tls, mplex) | rust-v0.55 | rust-v0.53 | ws | tls | mplex | ✅ | 5s | 92.94 | 0.224 |
| rust-v0.55 x rust-v0.53 (ws, tls, yamux) | rust-v0.55 | rust-v0.53 | ws | tls | yamux | ✅ | 6s | 92.19 | 0.67 |
| rust-v0.55 x rust-v0.53 (ws, noise, mplex) | rust-v0.55 | rust-v0.53 | ws | noise | mplex | ✅ | 5s | 97.924 | 0.35 |
| rust-v0.55 x rust-v0.53 (ws, noise, yamux) | rust-v0.55 | rust-v0.53 | ws | noise | yamux | ✅ | 6s | 136.023 | 43.637 |
| rust-v0.55 x rust-v0.53 (tcp, tls, mplex) | rust-v0.55 | rust-v0.53 | tcp | tls | mplex | ✅ | 4s | 52.705 | 0.299 |
| rust-v0.55 x rust-v0.53 (tcp, noise, mplex) | rust-v0.55 | rust-v0.53 | tcp | noise | mplex | ✅ | 4s | 43.333 | 0.195 |
| rust-v0.55 x rust-v0.53 (tcp, tls, yamux) | rust-v0.55 | rust-v0.53 | tcp | tls | yamux | ✅ | 5s | 90.939 | 47.607 |
| rust-v0.55 x rust-v0.53 (tcp, noise, yamux) | rust-v0.55 | rust-v0.53 | tcp | noise | yamux | ✅ | 5s | 50.769 | 0.437 |
| rust-v0.55 x rust-v0.53 (quic-v1) | rust-v0.55 | rust-v0.53 | quic-v1 | - | - | ✅ | 4s | 9.181 | 1.318 |
| rust-v0.55 x rust-v0.54 (ws, tls, mplex) | rust-v0.55 | rust-v0.54 | ws | tls | mplex | ✅ | 4s | 89.661 | 0.417 |
| rust-v0.55 x rust-v0.53 (webrtc-direct) | rust-v0.55 | rust-v0.53 | webrtc-direct | - | - | ✅ | 6s | 305.892 | 0.217 |
| rust-v0.55 x rust-v0.54 (ws, tls, yamux) | rust-v0.55 | rust-v0.54 | ws | tls | yamux | ✅ | 4s | 131.014 | 43.55 |
| rust-v0.55 x rust-v0.54 (ws, noise, mplex) | rust-v0.55 | rust-v0.54 | ws | noise | mplex | ✅ | 5s | 92.264 | 0.362 |
| rust-v0.55 x rust-v0.54 (ws, noise, yamux) | rust-v0.55 | rust-v0.54 | ws | noise | yamux | ✅ | 5s | 135.644 | 43.268 |
| rust-v0.55 x rust-v0.54 (tcp, tls, mplex) | rust-v0.55 | rust-v0.54 | tcp | tls | mplex | ✅ | 5s | 49.126 | 0.575 |
| rust-v0.55 x rust-v0.54 (tcp, tls, yamux) | rust-v0.55 | rust-v0.54 | tcp | tls | yamux | ✅ | 4s | 91.853 | 47.695 |
| rust-v0.55 x rust-v0.54 (tcp, noise, mplex) | rust-v0.55 | rust-v0.54 | tcp | noise | mplex | ✅ | 5s | 46.859 | 0.166 |
| rust-v0.55 x rust-v0.54 (tcp, noise, yamux) | rust-v0.55 | rust-v0.54 | tcp | noise | yamux | ✅ | 5s | 50.228 | 0.346 |
| rust-v0.55 x rust-v0.54 (quic-v1) | rust-v0.55 | rust-v0.54 | quic-v1 | - | - | ✅ | 5s | 6.573 | 0.37 |
| rust-v0.55 x rust-v0.54 (webrtc-direct) | rust-v0.55 | rust-v0.54 | webrtc-direct | - | - | ✅ | 4s | 267.369 | 0.219 |
| rust-v0.55 x rust-v0.55 (ws, tls, mplex) | rust-v0.55 | rust-v0.55 | ws | tls | mplex | ✅ | 4s | 6.94 | 0.199 |
| rust-v0.55 x rust-v0.55 (ws, tls, yamux) | rust-v0.55 | rust-v0.55 | ws | tls | yamux | ✅ | 5s | 11.897 | 0.586 |
| rust-v0.55 x rust-v0.55 (ws, noise, mplex) | rust-v0.55 | rust-v0.55 | ws | noise | mplex | ✅ | 4s | 6.036 | 0.088 |
| rust-v0.55 x rust-v0.55 (ws, noise, yamux) | rust-v0.55 | rust-v0.55 | ws | noise | yamux | ✅ | 5s | 5.387 | 0.533 |
| rust-v0.55 x rust-v0.55 (tcp, tls, mplex) | rust-v0.55 | rust-v0.55 | tcp | tls | mplex | ✅ | 4s | 5.473 | 0.238 |
| rust-v0.55 x rust-v0.55 (tcp, tls, yamux) | rust-v0.55 | rust-v0.55 | tcp | tls | yamux | ✅ | 4s | 3.464 | 0.134 |
| rust-v0.55 x rust-v0.55 (tcp, noise, mplex) | rust-v0.55 | rust-v0.55 | tcp | noise | mplex | ✅ | 5s | 3.641 | 0.245 |
| rust-v0.55 x rust-v0.55 (tcp, noise, yamux) | rust-v0.55 | rust-v0.55 | tcp | noise | yamux | ✅ | 5s | 2.765 | 0.097 |
| rust-v0.55 x rust-v0.55 (quic-v1) | rust-v0.55 | rust-v0.55 | quic-v1 | - | - | ✅ | 4s | 3.248 | 0.228 |
| rust-v0.55 x rust-v0.56 (ws, tls, mplex) | rust-v0.55 | rust-v0.56 | ws | tls | mplex | ✅ | 4s | 6.556 | 0.617 |
| rust-v0.55 x rust-v0.55 (webrtc-direct) | rust-v0.55 | rust-v0.55 | webrtc-direct | - | - | ✅ | 6s | 480.678 | 0.483 |
| rust-v0.55 x rust-v0.56 (ws, tls, yamux) | rust-v0.55 | rust-v0.56 | ws | tls | yamux | ✅ | 5s | 5.452 | 0.356 |
| rust-v0.55 x rust-v0.56 (ws, noise, mplex) | rust-v0.55 | rust-v0.56 | ws | noise | mplex | ✅ | 5s | 2.207 | 0.086 |
| rust-v0.55 x rust-v0.56 (ws, noise, yamux) | rust-v0.55 | rust-v0.56 | ws | noise | yamux | ✅ | 5s | 5.171 | 0.248 |
| rust-v0.55 x rust-v0.56 (tcp, tls, mplex) | rust-v0.55 | rust-v0.56 | tcp | tls | mplex | ✅ | 4s | 6.133 | 0.386 |
| rust-v0.55 x rust-v0.56 (tcp, tls, yamux) | rust-v0.55 | rust-v0.56 | tcp | tls | yamux | ✅ | 5s | 5.992 | 0.171 |
| rust-v0.55 x rust-v0.56 (tcp, noise, mplex) | rust-v0.55 | rust-v0.56 | tcp | noise | mplex | ✅ | 5s | 3.176 | 0.081 |
| rust-v0.55 x rust-v0.56 (tcp, noise, yamux) | rust-v0.55 | rust-v0.56 | tcp | noise | yamux | ✅ | 4s | 2.469 | 0.097 |
| rust-v0.55 x rust-v0.56 (webrtc-direct) | rust-v0.55 | rust-v0.56 | webrtc-direct | - | - | ✅ | 4s | 280.668 | 0.353 |
| rust-v0.55 x go-v0.38 (ws, tls, yamux) | rust-v0.55 | go-v0.38 | ws | tls | yamux | ✅ | 5s | 9.661 | 1.044 |
| rust-v0.55 x rust-v0.56 (quic-v1) | rust-v0.55 | rust-v0.56 | quic-v1 | - | - | ✅ | 6s | 4.044 | 0.432 |
| rust-v0.55 x go-v0.38 (ws, noise, yamux) | rust-v0.55 | go-v0.38 | ws | noise | yamux | ✅ | 5s | 6.978 | 0.239 |
| rust-v0.55 x go-v0.38 (tcp, tls, yamux) | rust-v0.55 | go-v0.38 | tcp | tls | yamux | ✅ | 5s | 13.166 | 1.1 |
| rust-v0.55 x go-v0.38 (tcp, noise, yamux) | rust-v0.55 | go-v0.38 | tcp | noise | yamux | ✅ | 5s | 11.98 | 0.218 |
| rust-v0.55 x go-v0.38 (quic-v1) | rust-v0.55 | go-v0.38 | quic-v1 | - | - | ✅ | 5s | 7.814 | 0.906 |
| rust-v0.55 x go-v0.38 (webrtc-direct) | rust-v0.55 | go-v0.38 | webrtc-direct | - | - | ✅ | 4s | 8.455 | 0.584 |
| rust-v0.55 x go-v0.39 (ws, tls, yamux) | rust-v0.55 | go-v0.39 | ws | tls | yamux | ✅ | 5s | 14.555 | 1.205 |
| rust-v0.55 x go-v0.39 (ws, noise, yamux) | rust-v0.55 | go-v0.39 | ws | noise | yamux | ✅ | 4s | 13.026 | 3.877 |
| rust-v0.55 x go-v0.39 (tcp, tls, yamux) | rust-v0.55 | go-v0.39 | tcp | tls | yamux | ✅ | 5s | 5.914 | 1.513 |
| rust-v0.55 x go-v0.39 (tcp, noise, yamux) | rust-v0.55 | go-v0.39 | tcp | noise | yamux | ✅ | 5s | 3.579 | 0.659 |
| rust-v0.55 x go-v0.39 (quic-v1) | rust-v0.55 | go-v0.39 | quic-v1 | - | - | ✅ | 6s | 6.717 | 0.207 |
| rust-v0.55 x go-v0.39 (webrtc-direct) | rust-v0.55 | go-v0.39 | webrtc-direct | - | - | ✅ | 5s | 38.123 | 0.558 |
| rust-v0.55 x go-v0.40 (ws, tls, yamux) | rust-v0.55 | go-v0.40 | ws | tls | yamux | ✅ | 6s | 6.692 | 0.369 |
| rust-v0.55 x go-v0.40 (ws, noise, yamux) | rust-v0.55 | go-v0.40 | ws | noise | yamux | ✅ | 5s | 5.982 | 0.313 |
| rust-v0.55 x go-v0.40 (tcp, tls, yamux) | rust-v0.55 | go-v0.40 | tcp | tls | yamux | ✅ | 5s | 10.014 | 1.361 |
| rust-v0.55 x go-v0.40 (tcp, noise, yamux) | rust-v0.55 | go-v0.40 | tcp | noise | yamux | ✅ | 5s | 3.984 | 0.22 |
| rust-v0.55 x go-v0.40 (quic-v1) | rust-v0.55 | go-v0.40 | quic-v1 | - | - | ✅ | 5s | 8.519 | 0.346 |
| rust-v0.55 x go-v0.40 (webrtc-direct) | rust-v0.55 | go-v0.40 | webrtc-direct | - | - | ✅ | 4s | 91.192 | 0.547 |
| rust-v0.55 x go-v0.41 (ws, tls, yamux) | rust-v0.55 | go-v0.41 | ws | tls | yamux | ✅ | 5s | 7.146 | 0.576 |
| rust-v0.55 x go-v0.41 (ws, noise, yamux) | rust-v0.55 | go-v0.41 | ws | noise | yamux | ✅ | 4s | 4.074 | 0.194 |
| rust-v0.55 x go-v0.41 (tcp, noise, yamux) | rust-v0.55 | go-v0.41 | tcp | noise | yamux | ✅ | 4s | 3.733 | 0.257 |
| rust-v0.55 x go-v0.41 (tcp, tls, yamux) | rust-v0.55 | go-v0.41 | tcp | tls | yamux | ✅ | 5s | 7.72 | 0.387 |
| rust-v0.55 x go-v0.41 (quic-v1) | rust-v0.55 | go-v0.41 | quic-v1 | - | - | ✅ | 5s | 9.526 | 0.617 |
| rust-v0.55 x go-v0.41 (webrtc-direct) | rust-v0.55 | go-v0.41 | webrtc-direct | - | - | ✅ | 5s | 25.087 | 0.566 |
| rust-v0.55 x go-v0.42 (ws, tls, yamux) | rust-v0.55 | go-v0.42 | ws | tls | yamux | ✅ | 4s | 6.329 | 0.389 |
| rust-v0.55 x go-v0.42 (ws, noise, yamux) | rust-v0.55 | go-v0.42 | ws | noise | yamux | ✅ | 5s | 7.13 | 0.26 |
| rust-v0.55 x go-v0.42 (tcp, tls, yamux) | rust-v0.55 | go-v0.42 | tcp | tls | yamux | ✅ | 4s | 6.215 | 0.261 |
| rust-v0.55 x go-v0.42 (tcp, noise, yamux) | rust-v0.55 | go-v0.42 | tcp | noise | yamux | ✅ | 4s | 4.758 | 0.302 |
| rust-v0.55 x go-v0.42 (quic-v1) | rust-v0.55 | go-v0.42 | quic-v1 | - | - | ✅ | 4s | 15.747 | 0.371 |
| rust-v0.55 x go-v0.42 (webrtc-direct) | rust-v0.55 | go-v0.42 | webrtc-direct | - | - | ✅ | 4s | 15.432 | 0.66 |
| rust-v0.55 x go-v0.43 (ws, tls, yamux) | rust-v0.55 | go-v0.43 | ws | tls | yamux | ✅ | 5s | 5.482 | 0.903 |
| rust-v0.55 x go-v0.43 (ws, noise, yamux) | rust-v0.55 | go-v0.43 | ws | noise | yamux | ✅ | 5s | 9.745 | 2.009 |
| rust-v0.55 x go-v0.43 (tcp, tls, yamux) | rust-v0.55 | go-v0.43 | tcp | tls | yamux | ✅ | 5s | 3.605 | 0.252 |
| rust-v0.55 x go-v0.43 (tcp, noise, yamux) | rust-v0.55 | go-v0.43 | tcp | noise | yamux | ✅ | 5s | 9.019 | 0.322 |
| rust-v0.55 x go-v0.43 (quic-v1) | rust-v0.55 | go-v0.43 | quic-v1 | - | - | ✅ | 5s | 9.023 | 0.631 |
| rust-v0.55 x go-v0.43 (webrtc-direct) | rust-v0.55 | go-v0.43 | webrtc-direct | - | - | ✅ | 5s | 39.568 | 0.338 |
| rust-v0.55 x go-v0.44 (ws, tls, yamux) | rust-v0.55 | go-v0.44 | ws | tls | yamux | ✅ | 5s | 3.908 | 0.634 |
| rust-v0.55 x go-v0.44 (ws, noise, yamux) | rust-v0.55 | go-v0.44 | ws | noise | yamux | ✅ | 5s | 4.109 | 0.323 |
| rust-v0.55 x go-v0.44 (tcp, tls, yamux) | rust-v0.55 | go-v0.44 | tcp | tls | yamux | ✅ | 5s | 3.731 | 0.134 |
| rust-v0.55 x go-v0.44 (tcp, noise, yamux) | rust-v0.55 | go-v0.44 | tcp | noise | yamux | ✅ | 5s | 4.453 | 0.145 |
| rust-v0.55 x go-v0.44 (quic-v1) | rust-v0.55 | go-v0.44 | quic-v1 | - | - | ✅ | 5s | 6.216 | 0.579 |
| rust-v0.55 x go-v0.44 (webrtc-direct) | rust-v0.55 | go-v0.44 | webrtc-direct | - | - | ✅ | 5s | 16.656 | 0.75 |
| rust-v0.55 x go-v0.45 (ws, tls, yamux) | rust-v0.55 | go-v0.45 | ws | tls | yamux | ✅ | 5s | 6.485 | 0.779 |
| rust-v0.55 x go-v0.45 (tcp, tls, yamux) | rust-v0.55 | go-v0.45 | tcp | tls | yamux | ✅ | 4s | 11.876 | 0.87 |
| rust-v0.55 x go-v0.45 (ws, noise, yamux) | rust-v0.55 | go-v0.45 | ws | noise | yamux | ✅ | 6s | 13.996 | 0.822 |
| rust-v0.55 x go-v0.45 (tcp, noise, yamux) | rust-v0.55 | go-v0.45 | tcp | noise | yamux | ✅ | 5s | 6.27 | 1.194 |
| rust-v0.55 x go-v0.45 (quic-v1) | rust-v0.55 | go-v0.45 | quic-v1 | - | - | ✅ | 5s | 8.894 | 0.405 |
| rust-v0.55 x go-v0.45 (webrtc-direct) | rust-v0.55 | go-v0.45 | webrtc-direct | - | - | ✅ | 5s | 33.177 | 0.422 |
| rust-v0.55 x python-v0.4 (ws, noise, mplex) | rust-v0.55 | python-v0.4 | ws | noise | mplex | ✅ | 5s | 26.864 | 2.335 |
| rust-v0.55 x python-v0.4 (tcp, noise, mplex) | rust-v0.55 | python-v0.4 | tcp | noise | mplex | ✅ | 5s | 15.921 | 0.906 |
| rust-v0.55 x python-v0.4 (ws, noise, yamux) | rust-v0.55 | python-v0.4 | ws | noise | yamux | ✅ | 6s | 31.218 | 1.269 |
| rust-v0.55 x python-v0.4 (tcp, noise, yamux) | rust-v0.55 | python-v0.4 | tcp | noise | yamux | ✅ | 5s | 14.866 | 1.086 |
| rust-v0.55 x python-v0.4 (quic-v1) | rust-v0.55 | python-v0.4 | quic-v1 | - | - | ✅ | 4s | 75.659 | 7.755 |
| rust-v0.55 x js-v1.x (ws, noise, mplex) | rust-v0.55 | js-v1.x | ws | noise | mplex | ✅ | 20s | 127.956 | 13.641 |
| rust-v0.55 x js-v1.x (ws, noise, yamux) | rust-v0.55 | js-v1.x | ws | noise | yamux | ✅ | 20s | 137.456 | 16.902 |
| rust-v0.55 x js-v1.x (tcp, noise, mplex) | rust-v0.55 | js-v1.x | tcp | noise | mplex | ✅ | 20s | 116.692 | 11.938 |
| rust-v0.55 x js-v1.x (tcp, noise, yamux) | rust-v0.55 | js-v1.x | tcp | noise | yamux | ✅ | 21s | 120.214 | 12.364 |
| rust-v0.55 x js-v2.x (ws, noise, mplex) | rust-v0.55 | js-v2.x | ws | noise | mplex | ✅ | 21s | 201.716 | 11.823 |
| rust-v0.55 x js-v2.x (ws, noise, yamux) | rust-v0.55 | js-v2.x | ws | noise | yamux | ✅ | 22s | 152.76 | 21.94 |
| rust-v0.55 x js-v2.x (tcp, noise, mplex) | rust-v0.55 | js-v2.x | tcp | noise | mplex | ✅ | 20s | 104.637 | 20.993 |
| rust-v0.55 x js-v2.x (tcp, noise, yamux) | rust-v0.55 | js-v2.x | tcp | noise | yamux | ✅ | 20s | 101.423 | 4.414 |
| rust-v0.55 x nim-v1.14 (ws, noise, mplex) | rust-v0.55 | nim-v1.14 | ws | noise | mplex | ✅ | 5s | 161.141 | 42.987 |
| rust-v0.55 x nim-v1.14 (ws, noise, yamux) | rust-v0.55 | nim-v1.14 | ws | noise | yamux | ✅ | 5s | 108.305 | 2.629 |
| rust-v0.55 x nim-v1.14 (tcp, noise, mplex) | rust-v0.55 | nim-v1.14 | tcp | noise | mplex | ✅ | 5s | 122.891 | 47.797 |
| rust-v0.55 x nim-v1.14 (tcp, noise, yamux) | rust-v0.55 | nim-v1.14 | tcp | noise | yamux | ✅ | 5s | 123.543 | 6.154 |
| rust-v0.55 x js-v3.x (ws, noise, mplex) | rust-v0.55 | js-v3.x | ws | noise | mplex | ✅ | 18s | 173.272 | 24.797 |
| rust-v0.55 x js-v3.x (ws, noise, yamux) | rust-v0.55 | js-v3.x | ws | noise | yamux | ✅ | 19s | 120.685 | 24.41 |
| rust-v0.55 x js-v3.x (tcp, noise, mplex) | rust-v0.55 | js-v3.x | tcp | noise | mplex | ✅ | 19s | 160.754 | 33.457 |
| rust-v0.55 x js-v3.x (tcp, noise, yamux) | rust-v0.55 | js-v3.x | tcp | noise | yamux | ✅ | 20s | 165.225 | 24.964 |
| rust-v0.55 x jvm-v1.2 (ws, tls, mplex) | rust-v0.55 | jvm-v1.2 | ws | tls | mplex | ✅ | 13s | 4648.4 | 2.049 |
| rust-v0.55 x jvm-v1.2 (ws, noise, yamux) | rust-v0.55 | jvm-v1.2 | ws | noise | yamux | ✅ | 11s | 1217.579 | 8.525 |
| rust-v0.55 x jvm-v1.2 (ws, noise, mplex) | rust-v0.55 | jvm-v1.2 | ws | noise | mplex | ✅ | 11s | 1138.764 | 4.179 |
| rust-v0.55 x jvm-v1.2 (ws, tls, yamux) | rust-v0.55 | jvm-v1.2 | ws | tls | yamux | ✅ | 14s | 3938.078 | 7.125 |
| rust-v0.55 x c-v0.0.1 (tcp, noise, mplex) | rust-v0.55 | c-v0.0.1 | tcp | noise | mplex | ✅ | 6s | 16.078 | 0.399 |
| rust-v0.55 x jvm-v1.2 (tcp, tls, mplex) | rust-v0.55 | jvm-v1.2 | tcp | tls | mplex | ✅ | 12s | 3912.879 | 10.516 |
| rust-v0.55 x c-v0.0.1 (tcp, noise, yamux) | rust-v0.55 | c-v0.0.1 | tcp | noise | yamux | ✅ | 6s | 66.93 | 5.358 |
| rust-v0.55 x jvm-v1.2 (tcp, noise, mplex) | rust-v0.55 | jvm-v1.2 | tcp | noise | mplex | ✅ | 10s | 1033.693 | 8.396 |
| rust-v0.55 x jvm-v1.2 (tcp, noise, yamux) | rust-v0.55 | jvm-v1.2 | tcp | noise | yamux | ✅ | 10s | 1189.892 | 8.667 |
| rust-v0.55 x jvm-v1.2 (tcp, tls, yamux) | rust-v0.55 | jvm-v1.2 | tcp | tls | yamux | ✅ | 12s | 3831.747 | 4.302 |
| rust-v0.55 x jvm-v1.2 (quic-v1) | rust-v0.55 | jvm-v1.2 | quic-v1 | - | - | ✅ | 12s | 1286.529 | 3.768 |
| rust-v0.55 x dotnet-v1.0 (tcp, noise, yamux) | rust-v0.55 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 5s | 167.637 | 15.437 |
| rust-v0.55 x eth-p2p-z-v0.0.1 (quic-v1) | rust-v0.55 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 4s | 10.444 | 0.85 |
| rust-v0.55 x zig-v0.0.1 (quic-v1) | rust-v0.55 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 5s | - | - |
| rust-v0.56 x rust-v0.53 (ws, tls, mplex) | rust-v0.56 | rust-v0.53 | ws | tls | mplex | ✅ | 4s | 86.34 | 0.266 |
| rust-v0.56 x rust-v0.53 (ws, tls, yamux) | rust-v0.56 | rust-v0.53 | ws | tls | yamux | ✅ | 5s | 91.713 | 0.216 |
| rust-v0.56 x rust-v0.53 (ws, noise, mplex) | rust-v0.56 | rust-v0.53 | ws | noise | mplex | ✅ | 5s | 90.389 | 0.448 |
| rust-v0.56 x rust-v0.53 (ws, noise, yamux) | rust-v0.56 | rust-v0.53 | ws | noise | yamux | ✅ | 4s | 131.491 | 43.448 |
| rust-v0.56 x rust-v0.53 (tcp, tls, mplex) | rust-v0.56 | rust-v0.53 | tcp | tls | mplex | ✅ | 5s | 49.753 | 0.49 |
| rust-v0.56 x rust-v0.53 (tcp, tls, yamux) | rust-v0.56 | rust-v0.53 | tcp | tls | yamux | ✅ | 4s | 54.382 | 42.837 |
| rust-v0.56 x rust-v0.53 (tcp, noise, mplex) | rust-v0.56 | rust-v0.53 | tcp | noise | mplex | ✅ | 5s | 2.244 | 0.057 |
| rust-v0.55 x c-v0.0.1 (quic-v1) | rust-v0.55 | c-v0.0.1 | quic-v1 | - | - | ❌ | 16s | - | - |
| rust-v0.56 x rust-v0.53 (tcp, noise, yamux) | rust-v0.56 | rust-v0.53 | tcp | noise | yamux | ✅ | 5s | 96.229 | 47.673 |
| rust-v0.56 x rust-v0.53 (quic-v1) | rust-v0.56 | rust-v0.53 | quic-v1 | - | - | ✅ | 5s | 5.653 | 0.523 |
| rust-v0.56 x rust-v0.53 (webrtc-direct) | rust-v0.56 | rust-v0.53 | webrtc-direct | - | - | ✅ | 5s | 224.723 | 1.88 |
| rust-v0.56 x rust-v0.54 (ws, tls, mplex) | rust-v0.56 | rust-v0.54 | ws | tls | mplex | ✅ | 4s | 89.699 | 0.423 |
| rust-v0.56 x rust-v0.54 (ws, tls, yamux) | rust-v0.56 | rust-v0.54 | ws | tls | yamux | ✅ | 4s | 90.244 | 0.183 |
| rust-v0.56 x rust-v0.54 (ws, noise, mplex) | rust-v0.56 | rust-v0.54 | ws | noise | mplex | ✅ | 4s | 93.98 | 0.574 |
| rust-v0.56 x rust-v0.54 (tcp, tls, mplex) | rust-v0.56 | rust-v0.54 | tcp | tls | mplex | ✅ | 4s | 44.604 | 0.205 |
| rust-v0.56 x rust-v0.54 (ws, noise, yamux) | rust-v0.56 | rust-v0.54 | ws | noise | yamux | ✅ | 5s | 136.331 | 43.693 |
| rust-v0.56 x rust-v0.54 (tcp, tls, yamux) | rust-v0.56 | rust-v0.54 | tcp | tls | yamux | ✅ | 5s | 86.588 | 43.464 |
| rust-v0.56 x rust-v0.54 (tcp, noise, yamux) | rust-v0.56 | rust-v0.54 | tcp | noise | yamux | ✅ | 5s | 50.648 | 0.322 |
| rust-v0.56 x rust-v0.54 (tcp, noise, mplex) | rust-v0.56 | rust-v0.54 | tcp | noise | mplex | ✅ | 5s | 49.308 | 0.744 |
| rust-v0.56 x rust-v0.54 (quic-v1) | rust-v0.56 | rust-v0.54 | quic-v1 | - | - | ✅ | 5s | 8.259 | 0.464 |
| rust-v0.56 x rust-v0.54 (webrtc-direct) | rust-v0.56 | rust-v0.54 | webrtc-direct | - | - | ✅ | 4s | 208.77 | 0.236 |
| rust-v0.56 x rust-v0.55 (ws, tls, mplex) | rust-v0.56 | rust-v0.55 | ws | tls | mplex | ✅ | 5s | 13.322 | 0.179 |
| rust-v0.56 x rust-v0.55 (ws, tls, yamux) | rust-v0.56 | rust-v0.55 | ws | tls | yamux | ✅ | 5s | 8.039 | 0.31 |
| rust-v0.56 x rust-v0.55 (ws, noise, mplex) | rust-v0.56 | rust-v0.55 | ws | noise | mplex | ✅ | 4s | 6.062 | 0.17 |
| rust-v0.56 x rust-v0.55 (ws, noise, yamux) | rust-v0.56 | rust-v0.55 | ws | noise | yamux | ✅ | 5s | 3.431 | 0.315 |
| rust-v0.56 x rust-v0.55 (tcp, tls, mplex) | rust-v0.56 | rust-v0.55 | tcp | tls | mplex | ✅ | 5s | 3.547 | 0.154 |
| rust-v0.56 x rust-v0.55 (tcp, tls, yamux) | rust-v0.56 | rust-v0.55 | tcp | tls | yamux | ✅ | 4s | 4.519 | 0.17 |
| rust-v0.56 x rust-v0.55 (tcp, noise, yamux) | rust-v0.56 | rust-v0.55 | tcp | noise | yamux | ✅ | 4s | 2.988 | 0.14 |
| rust-v0.56 x rust-v0.55 (tcp, noise, mplex) | rust-v0.56 | rust-v0.55 | tcp | noise | mplex | ✅ | 5s | 3.38 | 0.06 |
| rust-v0.56 x rust-v0.55 (quic-v1) | rust-v0.56 | rust-v0.55 | quic-v1 | - | - | ✅ | 4s | 7.137 | 0.267 |
| rust-v0.56 x rust-v0.55 (webrtc-direct) | rust-v0.56 | rust-v0.55 | webrtc-direct | - | - | ✅ | 4s | 215.416 | 0.674 |
| rust-v0.56 x rust-v0.56 (ws, tls, yamux) | rust-v0.56 | rust-v0.56 | ws | tls | yamux | ✅ | 5s | 11.448 | 0.834 |
| rust-v0.56 x rust-v0.56 (ws, tls, mplex) | rust-v0.56 | rust-v0.56 | ws | tls | mplex | ✅ | 5s | 6.918 | 0.206 |
| rust-v0.56 x rust-v0.56 (ws, noise, mplex) | rust-v0.56 | rust-v0.56 | ws | noise | mplex | ✅ | 4s | 2.518 | 0.076 |
| rust-v0.56 x rust-v0.56 (ws, noise, yamux) | rust-v0.56 | rust-v0.56 | ws | noise | yamux | ✅ | 4s | 4.52 | 0.282 |
| rust-v0.56 x rust-v0.56 (tcp, tls, mplex) | rust-v0.56 | rust-v0.56 | tcp | tls | mplex | ✅ | 4s | 3.407 | 0.103 |
| rust-v0.56 x rust-v0.56 (tcp, tls, yamux) | rust-v0.56 | rust-v0.56 | tcp | tls | yamux | ✅ | 4s | 5.314 | 0.198 |
| rust-v0.56 x rust-v0.56 (tcp, noise, mplex) | rust-v0.56 | rust-v0.56 | tcp | noise | mplex | ✅ | 5s | 3.697 | 0.11 |
| rust-v0.56 x rust-v0.56 (quic-v1) | rust-v0.56 | rust-v0.56 | quic-v1 | - | - | ✅ | 5s | 7.87 | 0.34 |
| rust-v0.56 x rust-v0.56 (tcp, noise, yamux) | rust-v0.56 | rust-v0.56 | tcp | noise | yamux | ✅ | 6s | 12.642 | 0.206 |
| rust-v0.56 x rust-v0.56 (webrtc-direct) | rust-v0.56 | rust-v0.56 | webrtc-direct | - | - | ✅ | 6s | 213.021 | 0.357 |
| rust-v0.56 x go-v0.38 (ws, tls, yamux) | rust-v0.56 | go-v0.38 | ws | tls | yamux | ✅ | 5s | 8.868 | 2.996 |
| rust-v0.56 x go-v0.38 (ws, noise, yamux) | rust-v0.56 | go-v0.38 | ws | noise | yamux | ✅ | 4s | 4.065 | 0.405 |
| rust-v0.56 x go-v0.38 (tcp, tls, yamux) | rust-v0.56 | go-v0.38 | tcp | tls | yamux | ✅ | 5s | 6.135 | 0.292 |
| rust-v0.56 x go-v0.38 (tcp, noise, yamux) | rust-v0.56 | go-v0.38 | tcp | noise | yamux | ✅ | 5s | 4.664 | 0.245 |
| rust-v0.56 x go-v0.38 (quic-v1) | rust-v0.56 | go-v0.38 | quic-v1 | - | - | ✅ | 4s | 7.308 | 0.185 |
| rust-v0.56 x go-v0.39 (ws, noise, yamux) | rust-v0.56 | go-v0.39 | ws | noise | yamux | ✅ | 4s | 6.809 | 0.82 |
| rust-v0.56 x go-v0.38 (webrtc-direct) | rust-v0.56 | go-v0.38 | webrtc-direct | - | - | ✅ | 5s | 24.319 | 0.811 |
| rust-v0.56 x go-v0.39 (ws, tls, yamux) | rust-v0.56 | go-v0.39 | ws | tls | yamux | ✅ | 5s | 10.559 | 1.115 |
| rust-v0.56 x go-v0.39 (tcp, tls, yamux) | rust-v0.56 | go-v0.39 | tcp | tls | yamux | ✅ | 4s | 3.694 | 0.586 |
| rust-v0.56 x go-v0.39 (tcp, noise, yamux) | rust-v0.56 | go-v0.39 | tcp | noise | yamux | ✅ | 5s | 11.42 | 1.635 |
| rust-v0.56 x go-v0.39 (quic-v1) | rust-v0.56 | go-v0.39 | quic-v1 | - | - | ✅ | 4s | 7.463 | 0.767 |
| rust-v0.56 x go-v0.39 (webrtc-direct) | rust-v0.56 | go-v0.39 | webrtc-direct | - | - | ✅ | 4s | 27.71 | 2.278 |
| rust-v0.56 x go-v0.40 (ws, tls, yamux) | rust-v0.56 | go-v0.40 | ws | tls | yamux | ✅ | 5s | 8.527 | 0.513 |
| rust-v0.56 x go-v0.40 (ws, noise, yamux) | rust-v0.56 | go-v0.40 | ws | noise | yamux | ✅ | 5s | 8.674 | 0.165 |
| rust-v0.56 x go-v0.40 (tcp, tls, yamux) | rust-v0.56 | go-v0.40 | tcp | tls | yamux | ✅ | 5s | 16.64 | 5.543 |
| rust-v0.56 x go-v0.40 (tcp, noise, yamux) | rust-v0.56 | go-v0.40 | tcp | noise | yamux | ✅ | 5s | 6.589 | 0.366 |
| rust-v0.56 x go-v0.40 (quic-v1) | rust-v0.56 | go-v0.40 | quic-v1 | - | - | ✅ | 5s | 7.498 | 0.431 |
| rust-v0.56 x go-v0.40 (webrtc-direct) | rust-v0.56 | go-v0.40 | webrtc-direct | - | - | ✅ | 6s | 19.606 | 0.667 |
| rust-v0.56 x go-v0.41 (ws, tls, yamux) | rust-v0.56 | go-v0.41 | ws | tls | yamux | ✅ | 5s | 7.117 | 0.304 |
| rust-v0.56 x go-v0.41 (ws, noise, yamux) | rust-v0.56 | go-v0.41 | ws | noise | yamux | ✅ | 5s | 4.454 | 0.526 |
| rust-v0.56 x go-v0.41 (tcp, tls, yamux) | rust-v0.56 | go-v0.41 | tcp | tls | yamux | ✅ | 5s | 6.454 | 0.381 |
| rust-v0.56 x go-v0.41 (tcp, noise, yamux) | rust-v0.56 | go-v0.41 | tcp | noise | yamux | ✅ | 5s | 3.98 | 0.355 |
| rust-v0.56 x go-v0.41 (quic-v1) | rust-v0.56 | go-v0.41 | quic-v1 | - | - | ✅ | 5s | 7.123 | 0.345 |
| rust-v0.56 x go-v0.41 (webrtc-direct) | rust-v0.56 | go-v0.41 | webrtc-direct | - | - | ✅ | 4s | 122.198 | 0.574 |
| rust-v0.56 x go-v0.42 (ws, tls, yamux) | rust-v0.56 | go-v0.42 | ws | tls | yamux | ✅ | 5s | 16.908 | 1.524 |
| rust-v0.56 x go-v0.42 (ws, noise, yamux) | rust-v0.56 | go-v0.42 | ws | noise | yamux | ✅ | 5s | 3.921 | 0.139 |
| rust-v0.56 x go-v0.42 (tcp, tls, yamux) | rust-v0.56 | go-v0.42 | tcp | tls | yamux | ✅ | 4s | 4.662 | 0.225 |
| rust-v0.56 x go-v0.42 (tcp, noise, yamux) | rust-v0.56 | go-v0.42 | tcp | noise | yamux | ✅ | 5s | 6.071 | 0.631 |
| rust-v0.56 x go-v0.42 (quic-v1) | rust-v0.56 | go-v0.42 | quic-v1 | - | - | ✅ | 5s | 7.422 | 0.777 |
| rust-v0.56 x go-v0.43 (ws, tls, yamux) | rust-v0.56 | go-v0.43 | ws | tls | yamux | ✅ | 4s | 5.136 | 0.461 |
| rust-v0.56 x go-v0.42 (webrtc-direct) | rust-v0.56 | go-v0.42 | webrtc-direct | - | - | ✅ | 6s | 11.598 | 0.576 |
| rust-v0.56 x go-v0.43 (ws, noise, yamux) | rust-v0.56 | go-v0.43 | ws | noise | yamux | ✅ | 4s | 3.184 | 0.277 |
| rust-v0.56 x go-v0.43 (tcp, tls, yamux) | rust-v0.56 | go-v0.43 | tcp | tls | yamux | ✅ | 5s | 7.722 | 0.26 |
| rust-v0.56 x go-v0.43 (tcp, noise, yamux) | rust-v0.56 | go-v0.43 | tcp | noise | yamux | ✅ | 6s | 6.027 | 0.311 |
| rust-v0.56 x go-v0.43 (quic-v1) | rust-v0.56 | go-v0.43 | quic-v1 | - | - | ✅ | 5s | 4.26 | 0.341 |
| rust-v0.56 x go-v0.43 (webrtc-direct) | rust-v0.56 | go-v0.43 | webrtc-direct | - | - | ✅ | 5s | 62.877 | 1.623 |
| rust-v0.56 x go-v0.44 (ws, tls, yamux) | rust-v0.56 | go-v0.44 | ws | tls | yamux | ✅ | 5s | 8.957 | 0.197 |
| rust-v0.56 x go-v0.44 (ws, noise, yamux) | rust-v0.56 | go-v0.44 | ws | noise | yamux | ✅ | 5s | 6.153 | 1.206 |
| rust-v0.56 x go-v0.44 (tcp, noise, yamux) | rust-v0.56 | go-v0.44 | tcp | noise | yamux | ✅ | 5s | 14.843 | 0.147 |
| rust-v0.56 x go-v0.44 (tcp, tls, yamux) | rust-v0.56 | go-v0.44 | tcp | tls | yamux | ✅ | 6s | 8.785 | 0.841 |
| rust-v0.56 x go-v0.44 (quic-v1) | rust-v0.56 | go-v0.44 | quic-v1 | - | - | ✅ | 5s | 6.016 | 0.281 |
| rust-v0.56 x go-v0.44 (webrtc-direct) | rust-v0.56 | go-v0.44 | webrtc-direct | - | - | ✅ | 5s | 33.867 | 2.161 |
| rust-v0.56 x go-v0.45 (ws, noise, yamux) | rust-v0.56 | go-v0.45 | ws | noise | yamux | ✅ | 5s | 5.62 | 0.988 |
| rust-v0.56 x go-v0.45 (ws, tls, yamux) | rust-v0.56 | go-v0.45 | ws | tls | yamux | ✅ | 5s | 8.119 | 0.348 |
| rust-v0.56 x go-v0.45 (tcp, tls, yamux) | rust-v0.56 | go-v0.45 | tcp | tls | yamux | ✅ | 5s | 7.369 | 3.785 |
| rust-v0.56 x go-v0.45 (tcp, noise, yamux) | rust-v0.56 | go-v0.45 | tcp | noise | yamux | ✅ | 5s | 8.269 | 0.526 |
| rust-v0.56 x go-v0.45 (quic-v1) | rust-v0.56 | go-v0.45 | quic-v1 | - | - | ✅ | 5s | 7.501 | 0.395 |
| rust-v0.56 x go-v0.45 (webrtc-direct) | rust-v0.56 | go-v0.45 | webrtc-direct | - | - | ✅ | 4s | 24.43 | 1.131 |
| rust-v0.56 x python-v0.4 (ws, noise, mplex) | rust-v0.56 | python-v0.4 | ws | noise | mplex | ✅ | 5s | 23.006 | 1.452 |
| rust-v0.56 x python-v0.4 (ws, noise, yamux) | rust-v0.56 | python-v0.4 | ws | noise | yamux | ✅ | 5s | 20.012 | 1.414 |
| rust-v0.56 x python-v0.4 (tcp, noise, mplex) | rust-v0.56 | python-v0.4 | tcp | noise | mplex | ✅ | 5s | 14.967 | 0.983 |
| rust-v0.56 x python-v0.4 (tcp, noise, yamux) | rust-v0.56 | python-v0.4 | tcp | noise | yamux | ✅ | 6s | 23.653 | 1.896 |
| rust-v0.56 x python-v0.4 (quic-v1) | rust-v0.56 | python-v0.4 | quic-v1 | - | - | ✅ | 5s | 39.911 | 3.562 |
| rust-v0.56 x js-v1.x (ws, noise, mplex) | rust-v0.56 | js-v1.x | ws | noise | mplex | ✅ | 19s | 148.8 | 10.94 |
| rust-v0.56 x js-v1.x (ws, noise, yamux) | rust-v0.56 | js-v1.x | ws | noise | yamux | ✅ | 20s | 156.478 | 23.601 |
| rust-v0.56 x js-v1.x (tcp, noise, mplex) | rust-v0.56 | js-v1.x | tcp | noise | mplex | ✅ | 20s | 156.501 | 12.489 |
| rust-v0.56 x js-v1.x (tcp, noise, yamux) | rust-v0.56 | js-v1.x | tcp | noise | yamux | ✅ | 20s | 132.339 | 12.181 |
| rust-v0.56 x js-v2.x (ws, noise, mplex) | rust-v0.56 | js-v2.x | ws | noise | mplex | ✅ | 20s | 156.258 | 14.289 |
| rust-v0.56 x js-v2.x (ws, noise, yamux) | rust-v0.56 | js-v2.x | ws | noise | yamux | ✅ | 21s | 152.108 | 12.515 |
| rust-v0.56 x js-v2.x (tcp, noise, mplex) | rust-v0.56 | js-v2.x | tcp | noise | mplex | ✅ | 21s | 105.022 | 12.521 |
| rust-v0.56 x js-v2.x (tcp, noise, yamux) | rust-v0.56 | js-v2.x | tcp | noise | yamux | ✅ | 20s | 158.747 | 10.057 |
| rust-v0.56 x nim-v1.14 (ws, noise, mplex) | rust-v0.56 | nim-v1.14 | ws | noise | mplex | ✅ | 4s | 150.708 | 43.744 |
| rust-v0.56 x nim-v1.14 (ws, noise, yamux) | rust-v0.56 | nim-v1.14 | ws | noise | yamux | ✅ | 5s | 121.611 | 4.304 |
| rust-v0.56 x nim-v1.14 (tcp, noise, mplex) | rust-v0.56 | nim-v1.14 | tcp | noise | mplex | ✅ | 5s | 157.2 | 43.84 |
| rust-v0.56 x nim-v1.14 (tcp, noise, yamux) | rust-v0.56 | nim-v1.14 | tcp | noise | yamux | ✅ | 4s | 87.099 | 2.1 |
| rust-v0.56 x js-v3.x (ws, noise, mplex) | rust-v0.56 | js-v3.x | ws | noise | mplex | ✅ | 18s | 181.215 | 27.93 |
| rust-v0.56 x js-v3.x (ws, noise, yamux) | rust-v0.56 | js-v3.x | ws | noise | yamux | ✅ | 18s | 162.18 | 40.006 |
| rust-v0.56 x js-v3.x (tcp, noise, mplex) | rust-v0.56 | js-v3.x | tcp | noise | mplex | ✅ | 19s | 222.133 | 20.666 |
| rust-v0.56 x jvm-v1.2 (ws, tls, mplex) | rust-v0.56 | jvm-v1.2 | ws | tls | mplex | ✅ | 13s | 4587.087 | 4.725 |
| rust-v0.56 x js-v3.x (tcp, noise, yamux) | rust-v0.56 | js-v3.x | tcp | noise | yamux | ✅ | 21s | 145.005 | 28.583 |
| rust-v0.56 x jvm-v1.2 (ws, noise, mplex) | rust-v0.56 | jvm-v1.2 | ws | noise | mplex | ✅ | 11s | 1233.54 | 11.15 |
| rust-v0.56 x jvm-v1.2 (ws, noise, yamux) | rust-v0.56 | jvm-v1.2 | ws | noise | yamux | ✅ | 12s | 1708.373 | 14.162 |
| rust-v0.56 x jvm-v1.2 (ws, tls, yamux) | rust-v0.56 | jvm-v1.2 | ws | tls | yamux | ✅ | 15s | 4031.96 | 5.391 |
| rust-v0.56 x jvm-v1.2 (tcp, tls, mplex) | rust-v0.56 | jvm-v1.2 | tcp | tls | mplex | ✅ | 12s | 3512.343 | 9.13 |
| rust-v0.56 x c-v0.0.1 (tcp, noise, mplex) | rust-v0.56 | c-v0.0.1 | tcp | noise | mplex | ✅ | 6s | 26.798 | 10.11 |
| rust-v0.56 x c-v0.0.1 (tcp, noise, yamux) | rust-v0.56 | c-v0.0.1 | tcp | noise | yamux | ✅ | 6s | 73.485 | 0.846 |
| rust-v0.56 x jvm-v1.2 (tcp, tls, yamux) | rust-v0.56 | jvm-v1.2 | tcp | tls | yamux | ✅ | 13s | 4092.414 | 12.431 |
| rust-v0.56 x jvm-v1.2 (tcp, noise, mplex) | rust-v0.56 | jvm-v1.2 | tcp | noise | mplex | ✅ | 11s | 1435.523 | 13.797 |
| rust-v0.56 x jvm-v1.2 (tcp, noise, yamux) | rust-v0.56 | jvm-v1.2 | tcp | noise | yamux | ✅ | 11s | 1036.356 | 8.412 |
| rust-v0.56 x jvm-v1.2 (quic-v1) | rust-v0.56 | jvm-v1.2 | quic-v1 | - | - | ✅ | 12s | 1825.527 | 10.54 |
| rust-v0.56 x zig-v0.0.1 (quic-v1) | rust-v0.56 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 4s | - | - |
| rust-v0.56 x dotnet-v1.0 (tcp, noise, yamux) | rust-v0.56 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 6s | 210.131 | 46.856 |
| rust-v0.56 x c-v0.0.1 (quic-v1) | rust-v0.56 | c-v0.0.1 | quic-v1 | - | - | ✅ | 11s | 5022.509 | 0.421 |
| rust-v0.56 x eth-p2p-z-v0.0.1 (quic-v1) | rust-v0.56 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 5s | 6.892 | 0.155 |
| go-v0.38 x rust-v0.53 (tcp, tls, yamux) | go-v0.38 | rust-v0.53 | tcp | tls | yamux | ✅ | 5s | 100.465 | 42.801 |
| go-v0.38 x rust-v0.53 (tcp, noise, yamux) | go-v0.38 | rust-v0.53 | tcp | noise | yamux | ✅ | 5s | 88.619 | 41.315 |
| go-v0.38 x rust-v0.53 (ws, tls, yamux) | go-v0.38 | rust-v0.53 | ws | tls | yamux | ✅ | 5s | 191.826 | 46.607 |
| go-v0.38 x rust-v0.53 (ws, noise, yamux) | go-v0.38 | rust-v0.53 | ws | noise | yamux | ✅ | 5s | 145.887 | 1.296 |
| go-v0.38 x rust-v0.53 (quic-v1) | go-v0.38 | rust-v0.53 | quic-v1 | - | - | ✅ | 4s | 7.759 | 0.364 |
| go-v0.38 x rust-v0.53 (webrtc-direct) | go-v0.38 | rust-v0.53 | webrtc-direct | - | - | ✅ | 5s | 418.555 | 0.79 |
| go-v0.38 x rust-v0.54 (tcp, tls, yamux) | go-v0.38 | rust-v0.54 | tcp | tls | yamux | ✅ | 4s | 91.129 | 42.339 |
| go-v0.38 x rust-v0.54 (tcp, noise, yamux) | go-v0.38 | rust-v0.54 | tcp | noise | yamux | ✅ | 5s | 89.881 | 41.748 |
| go-v0.38 x rust-v0.54 (ws, noise, yamux) | go-v0.38 | rust-v0.54 | ws | noise | yamux | ✅ | 5s | 180.859 | 46.67 |
| go-v0.38 x rust-v0.54 (ws, tls, yamux) | go-v0.38 | rust-v0.54 | ws | tls | yamux | ✅ | 6s | 183.202 | 42.553 |
| go-v0.38 x rust-v0.54 (quic-v1) | go-v0.38 | rust-v0.54 | quic-v1 | - | - | ✅ | 4s | 6.019 | 0.657 |
| go-v0.38 x rust-v0.54 (webrtc-direct) | go-v0.38 | rust-v0.54 | webrtc-direct | - | - | ✅ | 6s | 412.814 | 0.582 |
| go-v0.38 x rust-v0.55 (tcp, noise, yamux) | go-v0.38 | rust-v0.55 | tcp | noise | yamux | ✅ | 4s | 12.306 | 0.891 |
| go-v0.38 x rust-v0.55 (tcp, tls, yamux) | go-v0.38 | rust-v0.55 | tcp | tls | yamux | ✅ | 5s | 12.232 | 0.453 |
| go-v0.38 x rust-v0.55 (ws, tls, yamux) | go-v0.38 | rust-v0.55 | ws | tls | yamux | ✅ | 4s | 8.604 | 0.392 |
| go-v0.38 x rust-v0.55 (ws, noise, yamux) | go-v0.38 | rust-v0.55 | ws | noise | yamux | ✅ | 4s | 10.828 | 0.991 |
| go-v0.38 x rust-v0.55 (quic-v1) | go-v0.38 | rust-v0.55 | quic-v1 | - | - | ✅ | 5s | 7.109 | 0.316 |
| go-v0.38 x rust-v0.56 (tcp, tls, yamux) | go-v0.38 | rust-v0.56 | tcp | tls | yamux | ✅ | 5s | 16.153 | 0.918 |
| go-v0.38 x rust-v0.55 (webrtc-direct) | go-v0.38 | rust-v0.55 | webrtc-direct | - | - | ✅ | 5s | 409.629 | 0.661 |
| go-v0.38 x rust-v0.56 (ws, tls, yamux) | go-v0.38 | rust-v0.56 | ws | tls | yamux | ✅ | 4s | 9.463 | 0.653 |
| go-v0.38 x rust-v0.56 (tcp, noise, yamux) | go-v0.38 | rust-v0.56 | tcp | noise | yamux | ✅ | 6s | 10.737 | 0.295 |
| go-v0.38 x rust-v0.56 (ws, noise, yamux) | go-v0.38 | rust-v0.56 | ws | noise | yamux | ✅ | 5s | 11.738 | 1.656 |
| go-v0.38 x rust-v0.56 (quic-v1) | go-v0.38 | rust-v0.56 | quic-v1 | - | - | ✅ | 5s | 7.31 | 0.625 |
| go-v0.38 x go-v0.38 (tcp, tls, yamux) | go-v0.38 | go-v0.38 | tcp | tls | yamux | ✅ | 4s | 9.952 | 0.742 |
| go-v0.38 x go-v0.38 (tcp, noise, yamux) | go-v0.38 | go-v0.38 | tcp | noise | yamux | ✅ | 4s | 6.917 | 0.847 |
| go-v0.38 x go-v0.38 (ws, tls, yamux) | go-v0.38 | go-v0.38 | ws | tls | yamux | ✅ | 4s | 15.219 | 1.858 |
| go-v0.38 x go-v0.38 (ws, noise, yamux) | go-v0.38 | go-v0.38 | ws | noise | yamux | ✅ | 4s | 19.464 | 1.674 |
| go-v0.38 x go-v0.38 (wss, noise, yamux) | go-v0.38 | go-v0.38 | wss | noise | yamux | ✅ | 4s | 23.14 | 0.689 |
| go-v0.38 x go-v0.38 (wss, tls, yamux) | go-v0.38 | go-v0.38 | wss | tls | yamux | ✅ | 5s | 11.128 | 0.607 |
| go-v0.38 x go-v0.38 (quic-v1) | go-v0.38 | go-v0.38 | quic-v1 | - | - | ✅ | 5s | 11.663 | 0.402 |
| go-v0.38 x rust-v0.56 (webrtc-direct) | go-v0.38 | rust-v0.56 | webrtc-direct | - | - | ❌ | 9s | - | - |
| go-v0.38 x go-v0.38 (webtransport) | go-v0.38 | go-v0.38 | webtransport | - | - | ✅ | 5s | 8.007 | 0.311 |
| go-v0.38 x go-v0.38 (webrtc-direct) | go-v0.38 | go-v0.38 | webrtc-direct | - | - | ✅ | 5s | 212.59 | 0.592 |
| go-v0.38 x go-v0.39 (tcp, tls, yamux) | go-v0.38 | go-v0.39 | tcp | tls | yamux | ✅ | 5s | 7.465 | 0.918 |
| go-v0.38 x go-v0.39 (tcp, noise, yamux) | go-v0.38 | go-v0.39 | tcp | noise | yamux | ✅ | 4s | 6.035 | 0.441 |
| go-v0.38 x go-v0.39 (ws, tls, yamux) | go-v0.38 | go-v0.39 | ws | tls | yamux | ✅ | 5s | 15.674 | 0.532 |
| go-v0.38 x go-v0.39 (ws, noise, yamux) | go-v0.38 | go-v0.39 | ws | noise | yamux | ✅ | 4s | 21.473 | 0.484 |
| go-v0.38 x go-v0.39 (wss, tls, yamux) | go-v0.38 | go-v0.39 | wss | tls | yamux | ✅ | 5s | 11.343 | 1.594 |
| go-v0.38 x go-v0.39 (wss, noise, yamux) | go-v0.38 | go-v0.39 | wss | noise | yamux | ✅ | 5s | 13.712 | 0.983 |
| go-v0.38 x go-v0.39 (quic-v1) | go-v0.38 | go-v0.39 | quic-v1 | - | - | ✅ | 6s | 17.091 | 0.969 |
| go-v0.38 x go-v0.39 (webtransport) | go-v0.38 | go-v0.39 | webtransport | - | - | ✅ | 5s | 19.347 | 1.239 |
| go-v0.38 x go-v0.39 (webrtc-direct) | go-v0.38 | go-v0.39 | webrtc-direct | - | - | ✅ | 5s | 219.757 | 0.71 |
| go-v0.38 x go-v0.40 (tcp, tls, yamux) | go-v0.38 | go-v0.40 | tcp | tls | yamux | ✅ | 5s | 12.802 | 0.366 |
| go-v0.38 x go-v0.40 (tcp, noise, yamux) | go-v0.38 | go-v0.40 | tcp | noise | yamux | ✅ | 5s | 8.257 | 0.35 |
| go-v0.38 x go-v0.40 (ws, noise, yamux) | go-v0.38 | go-v0.40 | ws | noise | yamux | ✅ | 4s | 11.541 | 1.074 |
| go-v0.38 x go-v0.40 (ws, tls, yamux) | go-v0.38 | go-v0.40 | ws | tls | yamux | ✅ | 5s | 8.884 | 1.485 |
| go-v0.38 x go-v0.40 (wss, tls, yamux) | go-v0.38 | go-v0.40 | wss | tls | yamux | ✅ | 6s | 19.902 | 1.365 |
| go-v0.38 x go-v0.40 (quic-v1) | go-v0.38 | go-v0.40 | quic-v1 | - | - | ✅ | 4s | 13.601 | 0.772 |
| go-v0.38 x go-v0.40 (wss, noise, yamux) | go-v0.38 | go-v0.40 | wss | noise | yamux | ✅ | 6s | 16.279 | 0.644 |
| go-v0.38 x go-v0.40 (webtransport) | go-v0.38 | go-v0.40 | webtransport | - | - | ✅ | 5s | 15.647 | 0.656 |
| go-v0.38 x go-v0.41 (tcp, tls, yamux) | go-v0.38 | go-v0.41 | tcp | tls | yamux | ✅ | 5s | 6.148 | 0.799 |
| go-v0.38 x go-v0.41 (tcp, noise, yamux) | go-v0.38 | go-v0.41 | tcp | noise | yamux | ✅ | 4s | 8.909 | 0.332 |
| go-v0.38 x go-v0.40 (webrtc-direct) | go-v0.38 | go-v0.40 | webrtc-direct | - | - | ✅ | 5s | 218.423 | 0.796 |
| go-v0.38 x go-v0.41 (ws, tls, yamux) | go-v0.38 | go-v0.41 | ws | tls | yamux | ✅ | 5s | 9.315 | 0.917 |
| go-v0.38 x go-v0.41 (ws, noise, yamux) | go-v0.38 | go-v0.41 | ws | noise | yamux | ✅ | 5s | 11.886 | 1.785 |
| go-v0.38 x go-v0.41 (quic-v1) | go-v0.38 | go-v0.41 | quic-v1 | - | - | ✅ | 5s | 17.599 | 0.554 |
| go-v0.38 x go-v0.41 (wss, tls, yamux) | go-v0.38 | go-v0.41 | wss | tls | yamux | ✅ | 5s | 13.523 | 0.68 |
| go-v0.38 x go-v0.41 (wss, noise, yamux) | go-v0.38 | go-v0.41 | wss | noise | yamux | ✅ | 5s | 12.058 | 0.305 |
| go-v0.38 x go-v0.41 (webtransport) | go-v0.38 | go-v0.41 | webtransport | - | - | ✅ | 4s | 15.888 | 0.644 |
| go-v0.38 x go-v0.41 (webrtc-direct) | go-v0.38 | go-v0.41 | webrtc-direct | - | - | ✅ | 4s | 217.788 | 1.052 |
| go-v0.38 x go-v0.42 (tcp, tls, yamux) | go-v0.38 | go-v0.42 | tcp | tls | yamux | ✅ | 5s | 10.819 | 0.364 |
| go-v0.38 x go-v0.42 (tcp, noise, yamux) | go-v0.38 | go-v0.42 | tcp | noise | yamux | ✅ | 4s | 6.289 | 0.748 |
| go-v0.38 x go-v0.42 (ws, tls, yamux) | go-v0.38 | go-v0.42 | ws | tls | yamux | ✅ | 5s | 13.144 | 1.218 |
| go-v0.38 x go-v0.42 (ws, noise, yamux) | go-v0.38 | go-v0.42 | ws | noise | yamux | ✅ | 5s | 9.259 | 0.949 |
| go-v0.38 x go-v0.42 (wss, noise, yamux) | go-v0.38 | go-v0.42 | wss | noise | yamux | ✅ | 5s | 16.144 | 1.172 |
| go-v0.38 x go-v0.42 (wss, tls, yamux) | go-v0.38 | go-v0.42 | wss | tls | yamux | ✅ | 6s | 14.623 | 0.98 |
| go-v0.38 x go-v0.42 (quic-v1) | go-v0.38 | go-v0.42 | quic-v1 | - | - | ✅ | 5s | 13.014 | 1.225 |
| go-v0.38 x go-v0.42 (webtransport) | go-v0.38 | go-v0.42 | webtransport | - | - | ✅ | 5s | 12.777 | 1.367 |
| go-v0.38 x go-v0.42 (webrtc-direct) | go-v0.38 | go-v0.42 | webrtc-direct | - | - | ✅ | 5s | 206.015 | 0.269 |
| go-v0.38 x go-v0.43 (tcp, tls, yamux) | go-v0.38 | go-v0.43 | tcp | tls | yamux | ✅ | 5s | 31.037 | 0.928 |
| go-v0.38 x go-v0.43 (ws, tls, yamux) | go-v0.38 | go-v0.43 | ws | tls | yamux | ✅ | 5s | 17.607 | 2.876 |
| go-v0.38 x go-v0.43 (tcp, noise, yamux) | go-v0.38 | go-v0.43 | tcp | noise | yamux | ✅ | 5s | 8.452 | 0.848 |
| go-v0.38 x go-v0.43 (ws, noise, yamux) | go-v0.38 | go-v0.43 | ws | noise | yamux | ✅ | 4s | 12.548 | 0.998 |
| go-v0.38 x go-v0.43 (wss, tls, yamux) | go-v0.38 | go-v0.43 | wss | tls | yamux | ✅ | 5s | 19.069 | 1.22 |
| go-v0.38 x go-v0.43 (quic-v1) | go-v0.38 | go-v0.43 | quic-v1 | - | - | ✅ | 5s | 28.158 | 1.421 |
| go-v0.38 x go-v0.43 (wss, noise, yamux) | go-v0.38 | go-v0.43 | wss | noise | yamux | ✅ | 6s | 23.91 | 4.066 |
| go-v0.38 x go-v0.43 (webtransport) | go-v0.38 | go-v0.43 | webtransport | - | - | ✅ | 5s | 16.592 | 0.583 |
| go-v0.38 x go-v0.43 (webrtc-direct) | go-v0.38 | go-v0.43 | webrtc-direct | - | - | ✅ | 5s | 210.65 | 0.595 |
| go-v0.38 x go-v0.44 (tcp, tls, yamux) | go-v0.38 | go-v0.44 | tcp | tls | yamux | ✅ | 5s | 6.77 | 0.297 |
| go-v0.38 x go-v0.44 (tcp, noise, yamux) | go-v0.38 | go-v0.44 | tcp | noise | yamux | ✅ | 5s | 15.258 | 0.488 |
| go-v0.38 x go-v0.44 (ws, tls, yamux) | go-v0.38 | go-v0.44 | ws | tls | yamux | ✅ | 5s | 5.257 | 0.297 |
| go-v0.38 x go-v0.44 (ws, noise, yamux) | go-v0.38 | go-v0.44 | ws | noise | yamux | ✅ | 5s | 5.53 | 0.268 |
| go-v0.38 x go-v0.44 (wss, tls, yamux) | go-v0.38 | go-v0.44 | wss | tls | yamux | ✅ | 5s | 21.947 | 0.918 |
| go-v0.38 x go-v0.44 (wss, noise, yamux) | go-v0.38 | go-v0.44 | wss | noise | yamux | ✅ | 6s | 12.536 | 0.406 |
| go-v0.38 x go-v0.44 (webtransport) | go-v0.38 | go-v0.44 | webtransport | - | - | ✅ | 5s | 15.601 | 1.414 |
| go-v0.38 x go-v0.44 (quic-v1) | go-v0.38 | go-v0.44 | quic-v1 | - | - | ✅ | 6s | 20.253 | 1.719 |
| go-v0.38 x go-v0.44 (webrtc-direct) | go-v0.38 | go-v0.44 | webrtc-direct | - | - | ✅ | 5s | 223.438 | 0.688 |
| go-v0.38 x go-v0.45 (tcp, tls, yamux) | go-v0.38 | go-v0.45 | tcp | tls | yamux | ✅ | 5s | 9.564 | 2.619 |
| go-v0.38 x go-v0.45 (tcp, noise, yamux) | go-v0.38 | go-v0.45 | tcp | noise | yamux | ✅ | 5s | 12.445 | 1.477 |
| go-v0.38 x go-v0.45 (ws, tls, yamux) | go-v0.38 | go-v0.45 | ws | tls | yamux | ✅ | 5s | 10.62 | 0.74 |
| go-v0.38 x go-v0.45 (ws, noise, yamux) | go-v0.38 | go-v0.45 | ws | noise | yamux | ✅ | 4s | 12.744 | 2.685 |
| go-v0.38 x go-v0.45 (wss, tls, yamux) | go-v0.38 | go-v0.45 | wss | tls | yamux | ✅ | 5s | 20.718 | 1.277 |
| go-v0.38 x go-v0.45 (webtransport) | go-v0.38 | go-v0.45 | webtransport | - | - | ✅ | 4s | 21.96 | 0.758 |
| go-v0.38 x go-v0.45 (quic-v1) | go-v0.38 | go-v0.45 | quic-v1 | - | - | ✅ | 5s | 23.19 | 1.038 |
| go-v0.38 x go-v0.45 (wss, noise, yamux) | go-v0.38 | go-v0.45 | wss | noise | yamux | ✅ | 6s | 15.833 | 1.9 |
| go-v0.38 x go-v0.45 (webrtc-direct) | go-v0.38 | go-v0.45 | webrtc-direct | - | - | ✅ | 4s | 208.774 | 0.26 |
| go-v0.38 x python-v0.4 (ws, noise, yamux) | go-v0.38 | python-v0.4 | ws | noise | yamux | ✅ | 5s | 39.749 | 9.87 |
| go-v0.38 x python-v0.4 (tcp, noise, yamux) | go-v0.38 | python-v0.4 | tcp | noise | yamux | ✅ | 7s | 31.271 | 4.112 |
| go-v0.38 x python-v0.4 (wss, noise, yamux) | go-v0.38 | python-v0.4 | wss | noise | yamux | ✅ | 5s | 24.535 | 3.461 |
| go-v0.38 x python-v0.4 (quic-v1) | go-v0.38 | python-v0.4 | quic-v1 | - | - | ✅ | 5s | 88.951 | 20.86 |
| go-v0.38 x nim-v1.14 (tcp, noise, yamux) | go-v0.38 | nim-v1.14 | tcp | noise | yamux | ✅ | 5s | 214.488 | 43.563 |
| go-v0.38 x nim-v1.14 (ws, noise, yamux) | go-v0.38 | nim-v1.14 | ws | noise | yamux | ✅ | 5s | 272.733 | 43.321 |
| go-v0.38 x js-v1.x (tcp, noise, yamux) | go-v0.38 | js-v1.x | tcp | noise | yamux | ✅ | 18s | 242.829 | 30.239 |
| go-v0.38 x js-v1.x (ws, noise, yamux) | go-v0.38 | js-v1.x | ws | noise | yamux | ✅ | 19s | 169.142 | 17.961 |
| go-v0.38 x js-v2.x (tcp, noise, yamux) | go-v0.38 | js-v2.x | tcp | noise | yamux | ✅ | 21s | 186.84 | 28.288 |
| go-v0.38 x jvm-v1.2 (tcp, noise, yamux) | go-v0.38 | jvm-v1.2 | tcp | noise | yamux | ✅ | 11s | 1254.851 | 20.5 |
| go-v0.38 x js-v2.x (ws, noise, yamux) | go-v0.38 | js-v2.x | ws | noise | yamux | ✅ | 23s | 199.781 | 29.024 |
| go-v0.38 x js-v3.x (tcp, noise, yamux) | go-v0.38 | js-v3.x | tcp | noise | yamux | ✅ | 21s | 107.475 | 11.115 |
| go-v0.38 x jvm-v1.2 (tcp, tls, yamux) | go-v0.38 | jvm-v1.2 | tcp | tls | yamux | ✅ | 14s | 3304.176 | 14.911 |
| go-v0.38 x js-v3.x (ws, noise, yamux) | go-v0.38 | js-v3.x | ws | noise | yamux | ✅ | 21s | 175.549 | 21.419 |
| go-v0.38 x c-v0.0.1 (tcp, noise, yamux) | go-v0.38 | c-v0.0.1 | tcp | noise | yamux | ✅ | 6s | 166.816 | 60.826 |
| go-v0.38 x c-v0.0.1 (quic-v1) | go-v0.38 | c-v0.0.1 | quic-v1 | - | - | ✅ | 5s | 73.132 | 39.976 |
| go-v0.38 x jvm-v1.2 (ws, tls, yamux) | go-v0.38 | jvm-v1.2 | ws | tls | yamux | ✅ | 12s | 3879.715 | 20.159 |
| go-v0.38 x jvm-v1.2 (ws, noise, yamux) | go-v0.38 | jvm-v1.2 | ws | noise | yamux | ✅ | 10s | 1520.596 | 11.381 |
| go-v0.38 x dotnet-v1.0 (tcp, noise, yamux) | go-v0.38 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 6s | 395.976 | 43.469 |
| go-v0.38 x zig-v0.0.1 (quic-v1) | go-v0.38 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 6s | - | - |
| go-v0.38 x jvm-v1.2 (quic-v1) | go-v0.38 | jvm-v1.2 | quic-v1 | - | - | ✅ | 10s | 531.343 | 9.556 |
| go-v0.38 x eth-p2p-z-v0.0.1 (quic-v1) | go-v0.38 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 7s | 11.146 | 0.256 |
| go-v0.39 x rust-v0.53 (tcp, noise, yamux) | go-v0.39 | rust-v0.53 | tcp | noise | yamux | ✅ | 4s | 135.486 | 43.665 |
| go-v0.39 x rust-v0.53 (tcp, tls, yamux) | go-v0.39 | rust-v0.53 | tcp | tls | yamux | ✅ | 5s | 135.088 | 43.746 |
| go-v0.39 x rust-v0.53 (ws, tls, yamux) | go-v0.39 | rust-v0.53 | ws | tls | yamux | ✅ | 5s | 184.129 | 43.321 |
| go-v0.39 x rust-v0.53 (ws, noise, yamux) | go-v0.39 | rust-v0.53 | ws | noise | yamux | ✅ | 5s | 182.223 | 46.193 |
| go-v0.39 x rust-v0.53 (quic-v1) | go-v0.39 | rust-v0.53 | quic-v1 | - | - | ✅ | 5s | 5.178 | 0.371 |
| go-v0.39 x rust-v0.54 (tcp, tls, yamux) | go-v0.39 | rust-v0.54 | tcp | tls | yamux | ✅ | 4s | 91.621 | 42.883 |
| go-v0.39 x rust-v0.53 (webrtc-direct) | go-v0.39 | rust-v0.53 | webrtc-direct | - | - | ✅ | 6s | 413.906 | 0.382 |
| go-v0.39 x rust-v0.54 (tcp, noise, yamux) | go-v0.39 | rust-v0.54 | tcp | noise | yamux | ✅ | 5s | 103.452 | 44.353 |
| go-v0.39 x rust-v0.54 (ws, tls, yamux) | go-v0.39 | rust-v0.54 | ws | tls | yamux | ✅ | 5s | 180.469 | 41.558 |
| go-v0.39 x rust-v0.54 (ws, noise, yamux) | go-v0.39 | rust-v0.54 | ws | noise | yamux | ✅ | 5s | 191.191 | 45.387 |
| go-v0.39 x rust-v0.54 (quic-v1) | go-v0.39 | rust-v0.54 | quic-v1 | - | - | ✅ | 5s | 17.656 | 2.432 |
| go-v0.39 x rust-v0.54 (webrtc-direct) | go-v0.39 | rust-v0.54 | webrtc-direct | - | - | ✅ | 4s | 216.531 | 1.166 |
| go-v0.39 x rust-v0.55 (tcp, tls, yamux) | go-v0.39 | rust-v0.55 | tcp | tls | yamux | ✅ | 5s | 11.952 | 0.655 |
| go-v0.39 x rust-v0.55 (tcp, noise, yamux) | go-v0.39 | rust-v0.55 | tcp | noise | yamux | ✅ | 5s | 10.642 | 0.182 |
| go-v0.39 x rust-v0.55 (ws, tls, yamux) | go-v0.39 | rust-v0.55 | ws | tls | yamux | ✅ | 4s | 9.267 | 0.513 |
| go-v0.39 x rust-v0.55 (ws, noise, yamux) | go-v0.39 | rust-v0.55 | ws | noise | yamux | ✅ | 5s | 3.941 | 0.532 |
| go-v0.39 x rust-v0.55 (quic-v1) | go-v0.39 | rust-v0.55 | quic-v1 | - | - | ✅ | 5s | 16.439 | 0.501 |
| go-v0.39 x rust-v0.56 (tcp, tls, yamux) | go-v0.39 | rust-v0.56 | tcp | tls | yamux | ✅ | 5s | 7.572 | 0.778 |
| go-v0.39 x rust-v0.55 (webrtc-direct) | go-v0.39 | rust-v0.55 | webrtc-direct | - | - | ✅ | 5s | 415.072 | 0.841 |
| go-v0.39 x rust-v0.56 (tcp, noise, yamux) | go-v0.39 | rust-v0.56 | tcp | noise | yamux | ✅ | 5s | 15.632 | 1.061 |
| go-v0.39 x rust-v0.56 (ws, tls, yamux) | go-v0.39 | rust-v0.56 | ws | tls | yamux | ✅ | 5s | 4.333 | 0.205 |
| go-v0.39 x rust-v0.56 (ws, noise, yamux) | go-v0.39 | rust-v0.56 | ws | noise | yamux | ✅ | 5s | 10.125 | 0.443 |
| go-v0.39 x rust-v0.56 (quic-v1) | go-v0.39 | rust-v0.56 | quic-v1 | - | - | ✅ | 5s | 8.056 | 0.966 |
| go-v0.39 x go-v0.38 (tcp, tls, yamux) | go-v0.39 | go-v0.38 | tcp | tls | yamux | ✅ | 5s | 10.348 | 0.255 |
| go-v0.39 x go-v0.38 (tcp, noise, yamux) | go-v0.39 | go-v0.38 | tcp | noise | yamux | ✅ | 4s | 7.15 | 0.601 |
| go-v0.39 x go-v0.38 (ws, noise, yamux) | go-v0.39 | go-v0.38 | ws | noise | yamux | ✅ | 4s | 4.419 | 0.231 |
| go-v0.39 x go-v0.38 (ws, tls, yamux) | go-v0.39 | go-v0.38 | ws | tls | yamux | ✅ | 4s | 11.196 | 0.212 |
| go-v0.39 x go-v0.38 (wss, tls, yamux) | go-v0.39 | go-v0.38 | wss | tls | yamux | ✅ | 5s | 18.197 | 0.643 |
| go-v0.39 x go-v0.38 (quic-v1) | go-v0.39 | go-v0.38 | quic-v1 | - | - | ✅ | 4s | 10.816 | 0.901 |
| go-v0.39 x go-v0.38 (wss, noise, yamux) | go-v0.39 | go-v0.38 | wss | noise | yamux | ✅ | 5s | 12.528 | 0.429 |
| go-v0.39 x go-v0.38 (webtransport) | go-v0.39 | go-v0.38 | webtransport | - | - | ✅ | 4s | 5.224 | 0.216 |
| go-v0.39 x rust-v0.56 (webrtc-direct) | go-v0.39 | rust-v0.56 | webrtc-direct | - | - | ❌ | 10s | - | - |
| go-v0.39 x go-v0.38 (webrtc-direct) | go-v0.39 | go-v0.38 | webrtc-direct | - | - | ✅ | 5s | 211.237 | 0.385 |
| go-v0.39 x go-v0.39 (tcp, tls, yamux) | go-v0.39 | go-v0.39 | tcp | tls | yamux | ✅ | 4s | 7.666 | 0.856 |
| go-v0.39 x go-v0.39 (tcp, noise, yamux) | go-v0.39 | go-v0.39 | tcp | noise | yamux | ✅ | 5s | 11.787 | 0.686 |
| go-v0.39 x go-v0.39 (ws, tls, yamux) | go-v0.39 | go-v0.39 | ws | tls | yamux | ✅ | 4s | 17.784 | 0.399 |
| go-v0.39 x go-v0.39 (ws, noise, yamux) | go-v0.39 | go-v0.39 | ws | noise | yamux | ✅ | 5s | 13.932 | 0.803 |
| go-v0.39 x go-v0.39 (wss, noise, yamux) | go-v0.39 | go-v0.39 | wss | noise | yamux | ✅ | 5s | 17.599 | 4.884 |
| go-v0.39 x go-v0.39 (quic-v1) | go-v0.39 | go-v0.39 | quic-v1 | - | - | ✅ | 5s | 18.966 | 4.375 |
| go-v0.39 x go-v0.39 (wss, tls, yamux) | go-v0.39 | go-v0.39 | wss | tls | yamux | ✅ | 6s | 10.44 | 0.246 |
| go-v0.39 x go-v0.39 (webtransport) | go-v0.39 | go-v0.39 | webtransport | - | - | ✅ | 5s | 12.666 | 0.636 |
| go-v0.39 x go-v0.39 (webrtc-direct) | go-v0.39 | go-v0.39 | webrtc-direct | - | - | ✅ | 5s | 216.762 | 0.762 |
| go-v0.39 x go-v0.40 (tcp, tls, yamux) | go-v0.39 | go-v0.40 | tcp | tls | yamux | ✅ | 5s | 16.182 | 0.426 |
| go-v0.39 x go-v0.40 (tcp, noise, yamux) | go-v0.39 | go-v0.40 | tcp | noise | yamux | ✅ | 5s | 5.466 | 0.782 |
| go-v0.39 x go-v0.40 (ws, noise, yamux) | go-v0.39 | go-v0.40 | ws | noise | yamux | ✅ | 4s | 17.888 | 1.218 |
| go-v0.39 x go-v0.40 (ws, tls, yamux) | go-v0.39 | go-v0.40 | ws | tls | yamux | ✅ | 6s | 19.725 | 1.032 |
| go-v0.39 x go-v0.40 (wss, tls, yamux) | go-v0.39 | go-v0.40 | wss | tls | yamux | ✅ | 5s | 23.022 | 0.987 |
| go-v0.39 x go-v0.40 (wss, noise, yamux) | go-v0.39 | go-v0.40 | wss | noise | yamux | ✅ | 5s | 11.262 | 1.241 |
| go-v0.39 x go-v0.40 (quic-v1) | go-v0.39 | go-v0.40 | quic-v1 | - | - | ✅ | 5s | 9.476 | 1.11 |
| go-v0.39 x go-v0.40 (webtransport) | go-v0.39 | go-v0.40 | webtransport | - | - | ✅ | 4s | 7.906 | 0.321 |
| go-v0.39 x go-v0.41 (tcp, tls, yamux) | go-v0.39 | go-v0.41 | tcp | tls | yamux | ✅ | 5s | 11.034 | 0.649 |
| go-v0.39 x go-v0.40 (webrtc-direct) | go-v0.39 | go-v0.40 | webrtc-direct | - | - | ✅ | 6s | 220.43 | 0.519 |
| go-v0.39 x go-v0.41 (tcp, noise, yamux) | go-v0.39 | go-v0.41 | tcp | noise | yamux | ✅ | 5s | 12.878 | 0.803 |
| go-v0.39 x go-v0.41 (ws, tls, yamux) | go-v0.39 | go-v0.41 | ws | tls | yamux | ✅ | 5s | 8.5 | 0.565 |
| go-v0.39 x go-v0.41 (ws, noise, yamux) | go-v0.39 | go-v0.41 | ws | noise | yamux | ✅ | 4s | 7.523 | 0.74 |
| go-v0.39 x go-v0.41 (wss, tls, yamux) | go-v0.39 | go-v0.41 | wss | tls | yamux | ✅ | 4s | 20.486 | 1.232 |
| go-v0.39 x go-v0.41 (wss, noise, yamux) | go-v0.39 | go-v0.41 | wss | noise | yamux | ✅ | 5s | 12.237 | 0.294 |
| go-v0.39 x go-v0.41 (quic-v1) | go-v0.39 | go-v0.41 | quic-v1 | - | - | ✅ | 5s | 6.553 | 0.317 |
| go-v0.39 x go-v0.41 (webtransport) | go-v0.39 | go-v0.41 | webtransport | - | - | ✅ | 5s | 15.297 | 0.99 |
| go-v0.39 x go-v0.42 (tcp, tls, yamux) | go-v0.39 | go-v0.42 | tcp | tls | yamux | ✅ | 5s | 9.079 | 0.324 |
| go-v0.39 x go-v0.41 (webrtc-direct) | go-v0.39 | go-v0.41 | webrtc-direct | - | - | ✅ | 5s | 210.182 | 0.255 |
| go-v0.39 x go-v0.42 (tcp, noise, yamux) | go-v0.39 | go-v0.42 | tcp | noise | yamux | ✅ | 5s | 5.018 | 0.253 |
| go-v0.39 x go-v0.42 (ws, tls, yamux) | go-v0.39 | go-v0.42 | ws | tls | yamux | ✅ | 5s | 13.05 | 0.334 |
| go-v0.39 x go-v0.42 (ws, noise, yamux) | go-v0.39 | go-v0.42 | ws | noise | yamux | ✅ | 5s | 9.216 | 1.458 |
| go-v0.39 x go-v0.42 (wss, tls, yamux) | go-v0.39 | go-v0.42 | wss | tls | yamux | ✅ | 5s | 18.01 | 0.952 |
| go-v0.39 x go-v0.42 (wss, noise, yamux) | go-v0.39 | go-v0.42 | wss | noise | yamux | ✅ | 6s | 18.892 | 0.805 |
| go-v0.39 x go-v0.42 (quic-v1) | go-v0.39 | go-v0.42 | quic-v1 | - | - | ✅ | 4s | 10.689 | 0.542 |
| go-v0.39 x go-v0.42 (webtransport) | go-v0.39 | go-v0.42 | webtransport | - | - | ✅ | 5s | 26.34 | 2.219 |
| go-v0.39 x go-v0.42 (webrtc-direct) | go-v0.39 | go-v0.42 | webrtc-direct | - | - | ✅ | 5s | 212.61 | 0.431 |
| go-v0.39 x go-v0.43 (tcp, tls, yamux) | go-v0.39 | go-v0.43 | tcp | tls | yamux | ✅ | 4s | 7.854 | 0.3 |
| go-v0.39 x go-v0.43 (tcp, noise, yamux) | go-v0.39 | go-v0.43 | tcp | noise | yamux | ✅ | 5s | 6.138 | 0.209 |
| go-v0.39 x go-v0.43 (ws, tls, yamux) | go-v0.39 | go-v0.43 | ws | tls | yamux | ✅ | 4s | 9.446 | 0.498 |
| go-v0.39 x go-v0.43 (ws, noise, yamux) | go-v0.39 | go-v0.43 | ws | noise | yamux | ✅ | 4s | 8.864 | 0.584 |
| go-v0.39 x go-v0.43 (wss, tls, yamux) | go-v0.39 | go-v0.43 | wss | tls | yamux | ✅ | 6s | 17.852 | 1.663 |
| go-v0.39 x go-v0.43 (wss, noise, yamux) | go-v0.39 | go-v0.43 | wss | noise | yamux | ✅ | 5s | 22.147 | 2.539 |
| go-v0.39 x go-v0.43 (webtransport) | go-v0.39 | go-v0.43 | webtransport | - | - | ✅ | 4s | 12.876 | 0.91 |
| go-v0.39 x go-v0.43 (quic-v1) | go-v0.39 | go-v0.43 | quic-v1 | - | - | ✅ | 5s | 9.397 | 0.447 |
| go-v0.39 x go-v0.43 (webrtc-direct) | go-v0.39 | go-v0.43 | webrtc-direct | - | - | ✅ | 5s | 208.429 | 0.185 |
| go-v0.39 x go-v0.44 (tcp, tls, yamux) | go-v0.39 | go-v0.44 | tcp | tls | yamux | ✅ | 4s | 9.297 | 0.45 |
| go-v0.39 x go-v0.44 (tcp, noise, yamux) | go-v0.39 | go-v0.44 | tcp | noise | yamux | ✅ | 5s | 12.349 | 1.976 |
| go-v0.39 x go-v0.44 (ws, tls, yamux) | go-v0.39 | go-v0.44 | ws | tls | yamux | ✅ | 4s | 15.026 | 0.517 |
| go-v0.39 x go-v0.44 (ws, noise, yamux) | go-v0.39 | go-v0.44 | ws | noise | yamux | ✅ | 5s | 19.451 | 2.038 |
| go-v0.39 x go-v0.44 (wss, tls, yamux) | go-v0.39 | go-v0.44 | wss | tls | yamux | ✅ | 5s | 20.365 | 0.451 |
| go-v0.39 x go-v0.44 (quic-v1) | go-v0.39 | go-v0.44 | quic-v1 | - | - | ✅ | 4s | 10.041 | 0.363 |
| go-v0.39 x go-v0.44 (webtransport) | go-v0.39 | go-v0.44 | webtransport | - | - | ✅ | 5s | 17.344 | 1.419 |
| go-v0.39 x go-v0.44 (wss, noise, yamux) | go-v0.39 | go-v0.44 | wss | noise | yamux | ✅ | 6s | 12.381 | 0.343 |
| go-v0.39 x go-v0.44 (webrtc-direct) | go-v0.39 | go-v0.44 | webrtc-direct | - | - | ✅ | 5s | 218.407 | 1.259 |
| go-v0.39 x go-v0.45 (tcp, tls, yamux) | go-v0.39 | go-v0.45 | tcp | tls | yamux | ✅ | 5s | 14.656 | 4.301 |
| go-v0.39 x go-v0.45 (tcp, noise, yamux) | go-v0.39 | go-v0.45 | tcp | noise | yamux | ✅ | 5s | 7.686 | 0.6 |
| go-v0.39 x go-v0.45 (ws, tls, yamux) | go-v0.39 | go-v0.45 | ws | tls | yamux | ✅ | 4s | 13.945 | 5.303 |
| go-v0.39 x go-v0.45 (ws, noise, yamux) | go-v0.39 | go-v0.45 | ws | noise | yamux | ✅ | 5s | 11.914 | 0.799 |
| go-v0.39 x go-v0.45 (quic-v1) | go-v0.39 | go-v0.45 | quic-v1 | - | - | ✅ | 4s | 9.886 | 0.922 |
| go-v0.39 x go-v0.45 (wss, tls, yamux) | go-v0.39 | go-v0.45 | wss | tls | yamux | ✅ | 6s | 15.216 | 0.467 |
| go-v0.39 x go-v0.45 (wss, noise, yamux) | go-v0.39 | go-v0.45 | wss | noise | yamux | ✅ | 6s | 14.149 | 2.295 |
| go-v0.39 x go-v0.45 (webtransport) | go-v0.39 | go-v0.45 | webtransport | - | - | ✅ | 5s | 19.977 | 0.577 |
| go-v0.39 x go-v0.45 (webrtc-direct) | go-v0.39 | go-v0.45 | webrtc-direct | - | - | ✅ | 5s | 208.905 | 0.232 |
| go-v0.39 x python-v0.4 (tcp, noise, yamux) | go-v0.39 | python-v0.4 | tcp | noise | yamux | ✅ | 5s | 23.761 | 3.834 |
| go-v0.39 x python-v0.4 (ws, noise, yamux) | go-v0.39 | python-v0.4 | ws | noise | yamux | ✅ | 5s | 29.853 | 3.785 |
| go-v0.39 x python-v0.4 (wss, noise, yamux) | go-v0.39 | python-v0.4 | wss | noise | yamux | ✅ | 6s | 46.726 | 7.66 |
| go-v0.39 x python-v0.4 (quic-v1) | go-v0.39 | python-v0.4 | quic-v1 | - | - | ✅ | 5s | 65.156 | 17.76 |
| go-v0.39 x nim-v1.14 (tcp, noise, yamux) | go-v0.39 | nim-v1.14 | tcp | noise | yamux | ✅ | 5s | 208.701 | 42.87 |
| go-v0.39 x nim-v1.14 (ws, noise, yamux) | go-v0.39 | nim-v1.14 | ws | noise | yamux | ✅ | 5s | 257.679 | 43.63 |
| go-v0.39 x js-v1.x (ws, noise, yamux) | go-v0.39 | js-v1.x | ws | noise | yamux | ✅ | 19s | 142.407 | 18.313 |
| go-v0.39 x js-v1.x (tcp, noise, yamux) | go-v0.39 | js-v1.x | tcp | noise | yamux | ✅ | 21s | 217.004 | 12.195 |
| go-v0.39 x js-v2.x (tcp, noise, yamux) | go-v0.39 | js-v2.x | tcp | noise | yamux | ✅ | 21s | 142.176 | 21.727 |
| go-v0.39 x js-v2.x (ws, noise, yamux) | go-v0.39 | js-v2.x | ws | noise | yamux | ✅ | 22s | 195.139 | 26.59 |
| go-v0.39 x jvm-v1.2 (tcp, noise, yamux) | go-v0.39 | jvm-v1.2 | tcp | noise | yamux | ✅ | 11s | 1324.172 | 21.241 |
| go-v0.39 x js-v3.x (tcp, noise, yamux) | go-v0.39 | js-v3.x | tcp | noise | yamux | ✅ | 22s | 144.618 | 12.851 |
| go-v0.39 x js-v3.x (ws, noise, yamux) | go-v0.39 | js-v3.x | ws | noise | yamux | ✅ | 21s | 118.684 | 10.714 |
| go-v0.39 x jvm-v1.2 (tcp, tls, yamux) | go-v0.39 | jvm-v1.2 | tcp | tls | yamux | ✅ | 14s | 3224.702 | 7.996 |
| go-v0.39 x c-v0.0.1 (tcp, noise, yamux) | go-v0.39 | c-v0.0.1 | tcp | noise | yamux | ✅ | 6s | 127.504 | 53.4 |
| go-v0.39 x c-v0.0.1 (quic-v1) | go-v0.39 | c-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 54.081 | 37.176 |
| go-v0.39 x jvm-v1.2 (ws, noise, yamux) | go-v0.39 | jvm-v1.2 | ws | noise | yamux | ✅ | 9s | 1480.034 | 41.429 |
| go-v0.39 x jvm-v1.2 (ws, tls, yamux) | go-v0.39 | jvm-v1.2 | ws | tls | yamux | ✅ | 11s | 3365.862 | 24.502 |
| go-v0.39 x dotnet-v1.0 (tcp, noise, yamux) | go-v0.39 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 8s | 433.537 | 45.899 |
| go-v0.39 x zig-v0.0.1 (quic-v1) | go-v0.39 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 7s | - | - |
| go-v0.39 x eth-p2p-z-v0.0.1 (quic-v1) | go-v0.39 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 8.099 | 0.254 |
| go-v0.39 x jvm-v1.2 (quic-v1) | go-v0.39 | jvm-v1.2 | quic-v1 | - | - | ✅ | 11s | 546.953 | 6.969 |
| go-v0.40 x rust-v0.53 (tcp, tls, yamux) | go-v0.40 | rust-v0.53 | tcp | tls | yamux | ✅ | 4s | 92.779 | 42.789 |
| go-v0.40 x rust-v0.53 (tcp, noise, yamux) | go-v0.40 | rust-v0.53 | tcp | noise | yamux | ✅ | 5s | 139.053 | 43.701 |
| go-v0.40 x rust-v0.53 (ws, tls, yamux) | go-v0.40 | rust-v0.53 | ws | tls | yamux | ✅ | 4s | 228.144 | 41.944 |
| go-v0.40 x rust-v0.53 (ws, noise, yamux) | go-v0.40 | rust-v0.53 | ws | noise | yamux | ✅ | 5s | 226.024 | 47.455 |
| go-v0.40 x rust-v0.53 (quic-v1) | go-v0.40 | rust-v0.53 | quic-v1 | - | - | ✅ | 5s | 9.82 | 0.227 |
| go-v0.40 x rust-v0.53 (webrtc-direct) | go-v0.40 | rust-v0.53 | webrtc-direct | - | - | ✅ | 4s | 212.419 | 0.46 |
| go-v0.40 x rust-v0.54 (tcp, tls, yamux) | go-v0.40 | rust-v0.54 | tcp | tls | yamux | ✅ | 5s | 137.613 | 44.968 |
| go-v0.40 x rust-v0.54 (tcp, noise, yamux) | go-v0.40 | rust-v0.54 | tcp | noise | yamux | ✅ | 6s | 103.921 | 54.625 |
| go-v0.40 x rust-v0.54 (ws, tls, yamux) | go-v0.40 | rust-v0.54 | ws | tls | yamux | ✅ | 5s | 229.054 | 43.692 |
| go-v0.40 x rust-v0.54 (ws, noise, yamux) | go-v0.40 | rust-v0.54 | ws | noise | yamux | ✅ | 5s | 231.937 | 43.289 |
| go-v0.40 x rust-v0.54 (quic-v1) | go-v0.40 | rust-v0.54 | quic-v1 | - | - | ✅ | 4s | 5.193 | 0.177 |
| go-v0.40 x rust-v0.54 (webrtc-direct) | go-v0.40 | rust-v0.54 | webrtc-direct | - | - | ✅ | 5s | 221.635 | 1.084 |
| go-v0.40 x rust-v0.55 (tcp, noise, yamux) | go-v0.40 | rust-v0.55 | tcp | noise | yamux | ✅ | 5s | 13.169 | 0.604 |
| go-v0.40 x rust-v0.55 (tcp, tls, yamux) | go-v0.40 | rust-v0.55 | tcp | tls | yamux | ✅ | 5s | 10.384 | 0.271 |
| go-v0.40 x rust-v0.55 (ws, tls, yamux) | go-v0.40 | rust-v0.55 | ws | tls | yamux | ✅ | 6s | 17.37 | 1.448 |
| go-v0.40 x rust-v0.55 (ws, noise, yamux) | go-v0.40 | rust-v0.55 | ws | noise | yamux | ✅ | 5s | 4.003 | 0.186 |
| go-v0.40 x rust-v0.55 (quic-v1) | go-v0.40 | rust-v0.55 | quic-v1 | - | - | ✅ | 5s | 7.381 | 0.361 |
| go-v0.40 x rust-v0.56 (tcp, tls, yamux) | go-v0.40 | rust-v0.56 | tcp | tls | yamux | ✅ | 4s | 7.872 | 0.26 |
| go-v0.40 x rust-v0.55 (webrtc-direct) | go-v0.40 | rust-v0.55 | webrtc-direct | - | - | ✅ | 5s | 418.41 | 0.986 |
| go-v0.40 x rust-v0.56 (tcp, noise, yamux) | go-v0.40 | rust-v0.56 | tcp | noise | yamux | ✅ | 4s | 5.454 | 0.21 |
| go-v0.40 x rust-v0.56 (ws, noise, yamux) | go-v0.40 | rust-v0.56 | ws | noise | yamux | ✅ | 4s | 5.258 | 0.438 |
| go-v0.40 x rust-v0.56 (ws, tls, yamux) | go-v0.40 | rust-v0.56 | ws | tls | yamux | ✅ | 5s | 14.66 | 1.747 |
| go-v0.40 x rust-v0.56 (quic-v1) | go-v0.40 | rust-v0.56 | quic-v1 | - | - | ✅ | 5s | 8.294 | 0.363 |
| go-v0.40 x go-v0.38 (tcp, tls, yamux) | go-v0.40 | go-v0.38 | tcp | tls | yamux | ✅ | 5s | 8.317 | 0.381 |
| go-v0.40 x go-v0.38 (tcp, noise, yamux) | go-v0.40 | go-v0.38 | tcp | noise | yamux | ✅ | 5s | 13.627 | 0.697 |
| go-v0.40 x go-v0.38 (ws, tls, yamux) | go-v0.40 | go-v0.38 | ws | tls | yamux | ✅ | 5s | 12.069 | 0.502 |
| go-v0.40 x go-v0.38 (ws, noise, yamux) | go-v0.40 | go-v0.38 | ws | noise | yamux | ✅ | 5s | 13.619 | 0.88 |
| go-v0.40 x go-v0.38 (wss, tls, yamux) | go-v0.40 | go-v0.38 | wss | tls | yamux | ✅ | 4s | 12.904 | 0.351 |
| go-v0.40 x rust-v0.56 (webrtc-direct) | go-v0.40 | rust-v0.56 | webrtc-direct | - | - | ❌ | 10s | - | - |
| go-v0.40 x go-v0.38 (wss, noise, yamux) | go-v0.40 | go-v0.38 | wss | noise | yamux | ✅ | 5s | 17.066 | 1.114 |
| go-v0.40 x go-v0.38 (quic-v1) | go-v0.40 | go-v0.38 | quic-v1 | - | - | ✅ | 6s | 9.93 | 0.731 |
| go-v0.40 x go-v0.38 (webtransport) | go-v0.40 | go-v0.38 | webtransport | - | - | ✅ | 4s | 10.015 | 0.44 |
| go-v0.40 x go-v0.38 (webrtc-direct) | go-v0.40 | go-v0.38 | webrtc-direct | - | - | ✅ | 5s | 20.311 | 0.452 |
| go-v0.40 x go-v0.39 (tcp, tls, yamux) | go-v0.40 | go-v0.39 | tcp | tls | yamux | ✅ | 5s | 10.203 | 0.721 |
| go-v0.40 x go-v0.39 (tcp, noise, yamux) | go-v0.40 | go-v0.39 | tcp | noise | yamux | ✅ | 5s | 9.551 | 0.627 |
| go-v0.40 x go-v0.39 (ws, tls, yamux) | go-v0.40 | go-v0.39 | ws | tls | yamux | ✅ | 5s | 7.878 | 0.613 |
| go-v0.40 x go-v0.39 (ws, noise, yamux) | go-v0.40 | go-v0.39 | ws | noise | yamux | ✅ | 4s | 12.701 | 1.765 |
| go-v0.40 x go-v0.39 (wss, tls, yamux) | go-v0.40 | go-v0.39 | wss | tls | yamux | ✅ | 5s | 25.022 | 1.065 |
| go-v0.40 x go-v0.39 (quic-v1) | go-v0.40 | go-v0.39 | quic-v1 | - | - | ✅ | 5s | 6.933 | 0.223 |
| go-v0.40 x go-v0.39 (wss, noise, yamux) | go-v0.40 | go-v0.39 | wss | noise | yamux | ✅ | 5s | 9.012 | 0.21 |
| go-v0.40 x go-v0.39 (webtransport) | go-v0.40 | go-v0.39 | webtransport | - | - | ✅ | 5s | 11.613 | 1.038 |
| go-v0.40 x go-v0.39 (webrtc-direct) | go-v0.40 | go-v0.39 | webrtc-direct | - | - | ✅ | 4s | 214.983 | 0.559 |
| go-v0.40 x go-v0.40 (tcp, tls, yamux) | go-v0.40 | go-v0.40 | tcp | tls | yamux | ✅ | 5s | 10.151 | 3.106 |
| go-v0.40 x go-v0.40 (tcp, noise, yamux) | go-v0.40 | go-v0.40 | tcp | noise | yamux | ✅ | 5s | 16.884 | 1.617 |
| go-v0.40 x go-v0.40 (ws, tls, yamux) | go-v0.40 | go-v0.40 | ws | tls | yamux | ✅ | 4s | 11.089 | 1.692 |
| go-v0.40 x go-v0.40 (ws, noise, yamux) | go-v0.40 | go-v0.40 | ws | noise | yamux | ✅ | 5s | 11.154 | 2.293 |
| go-v0.40 x go-v0.40 (wss, tls, yamux) | go-v0.40 | go-v0.40 | wss | tls | yamux | ✅ | 5s | 19.083 | 1.185 |
| go-v0.40 x go-v0.40 (wss, noise, yamux) | go-v0.40 | go-v0.40 | wss | noise | yamux | ✅ | 4s | 11.984 | 1.008 |
| go-v0.40 x go-v0.40 (quic-v1) | go-v0.40 | go-v0.40 | quic-v1 | - | - | ✅ | 5s | 24.88 | 0.498 |
| go-v0.40 x go-v0.40 (webtransport) | go-v0.40 | go-v0.40 | webtransport | - | - | ✅ | 4s | 7.585 | 0.287 |
| go-v0.40 x go-v0.40 (webrtc-direct) | go-v0.40 | go-v0.40 | webrtc-direct | - | - | ✅ | 5s | 213.7 | 0.634 |
| go-v0.40 x go-v0.41 (tcp, tls, yamux) | go-v0.40 | go-v0.41 | tcp | tls | yamux | ✅ | 5s | 15.079 | 4.907 |
| go-v0.40 x go-v0.41 (tcp, noise, yamux) | go-v0.40 | go-v0.41 | tcp | noise | yamux | ✅ | 5s | 10.224 | 0.594 |
| go-v0.40 x go-v0.41 (ws, tls, yamux) | go-v0.40 | go-v0.41 | ws | tls | yamux | ✅ | 5s | 33.752 | 6.873 |
| go-v0.40 x go-v0.41 (ws, noise, yamux) | go-v0.40 | go-v0.41 | ws | noise | yamux | ✅ | 5s | 7.22 | 0.394 |
| go-v0.40 x go-v0.41 (wss, tls, yamux) | go-v0.40 | go-v0.41 | wss | tls | yamux | ✅ | 5s | 21.4 | 0.929 |
| go-v0.40 x go-v0.41 (quic-v1) | go-v0.40 | go-v0.41 | quic-v1 | - | - | ✅ | 5s | 11.559 | 0.501 |
| go-v0.40 x go-v0.41 (webtransport) | go-v0.40 | go-v0.41 | webtransport | - | - | ✅ | 4s | 22.713 | 0.709 |
| go-v0.40 x go-v0.41 (wss, noise, yamux) | go-v0.40 | go-v0.41 | wss | noise | yamux | ✅ | 6s | 17.019 | 0.496 |
| go-v0.40 x go-v0.41 (webrtc-direct) | go-v0.40 | go-v0.41 | webrtc-direct | - | - | ✅ | 5s | 65.344 | 2.432 |
| go-v0.40 x go-v0.42 (tcp, tls, yamux) | go-v0.40 | go-v0.42 | tcp | tls | yamux | ✅ | 4s | 6.732 | 0.296 |
| go-v0.40 x go-v0.42 (tcp, noise, yamux) | go-v0.40 | go-v0.42 | tcp | noise | yamux | ✅ | 5s | 5.439 | 0.785 |
| go-v0.40 x go-v0.42 (ws, tls, yamux) | go-v0.40 | go-v0.42 | ws | tls | yamux | ✅ | 5s | 15.536 | 5.514 |
| go-v0.40 x go-v0.42 (ws, noise, yamux) | go-v0.40 | go-v0.42 | ws | noise | yamux | ✅ | 4s | 9.785 | 0.749 |
| go-v0.40 x go-v0.42 (wss, tls, yamux) | go-v0.40 | go-v0.42 | wss | tls | yamux | ✅ | 5s | 16.087 | 0.458 |
| go-v0.40 x go-v0.42 (wss, noise, yamux) | go-v0.40 | go-v0.42 | wss | noise | yamux | ✅ | 5s | 15.234 | 0.772 |
| go-v0.40 x go-v0.42 (quic-v1) | go-v0.40 | go-v0.42 | quic-v1 | - | - | ✅ | 4s | 10.963 | 0.842 |
| go-v0.40 x go-v0.42 (webtransport) | go-v0.40 | go-v0.42 | webtransport | - | - | ✅ | 5s | 10.906 | 0.989 |
| go-v0.40 x go-v0.42 (webrtc-direct) | go-v0.40 | go-v0.42 | webrtc-direct | - | - | ✅ | 4s | 216.344 | 0.551 |
| go-v0.40 x go-v0.43 (tcp, tls, yamux) | go-v0.40 | go-v0.43 | tcp | tls | yamux | ✅ | 5s | 6.331 | 0.567 |
| go-v0.40 x go-v0.43 (tcp, noise, yamux) | go-v0.40 | go-v0.43 | tcp | noise | yamux | ✅ | 5s | 8.554 | 1.453 |
| go-v0.40 x go-v0.43 (ws, tls, yamux) | go-v0.40 | go-v0.43 | ws | tls | yamux | ✅ | 4s | 17.875 | 0.796 |
| go-v0.40 x go-v0.43 (ws, noise, yamux) | go-v0.40 | go-v0.43 | ws | noise | yamux | ✅ | 5s | 15.19 | 0.422 |
| go-v0.40 x go-v0.43 (wss, noise, yamux) | go-v0.40 | go-v0.43 | wss | noise | yamux | ✅ | 4s | 18.522 | 0.957 |
| go-v0.40 x go-v0.43 (quic-v1) | go-v0.40 | go-v0.43 | quic-v1 | - | - | ✅ | 5s | 17.188 | 1.086 |
| go-v0.40 x go-v0.43 (wss, tls, yamux) | go-v0.40 | go-v0.43 | wss | tls | yamux | ✅ | 5s | 10.343 | 1.325 |
| go-v0.40 x go-v0.43 (webtransport) | go-v0.40 | go-v0.43 | webtransport | - | - | ✅ | 5s | 13.053 | 0.724 |
| go-v0.40 x go-v0.43 (webrtc-direct) | go-v0.40 | go-v0.43 | webrtc-direct | - | - | ✅ | 5s | 211.716 | 0.542 |
| go-v0.40 x go-v0.44 (tcp, tls, yamux) | go-v0.40 | go-v0.44 | tcp | tls | yamux | ✅ | 4s | 10.443 | 0.373 |
| go-v0.40 x go-v0.44 (tcp, noise, yamux) | go-v0.40 | go-v0.44 | tcp | noise | yamux | ✅ | 5s | 15.31 | 0.439 |
| go-v0.40 x go-v0.44 (ws, tls, yamux) | go-v0.40 | go-v0.44 | ws | tls | yamux | ✅ | 5s | 15.233 | 1.923 |
| go-v0.40 x go-v0.44 (ws, noise, yamux) | go-v0.40 | go-v0.44 | ws | noise | yamux | ✅ | 4s | 14.101 | 0.338 |
| go-v0.40 x go-v0.44 (wss, tls, yamux) | go-v0.40 | go-v0.44 | wss | tls | yamux | ✅ | 6s | 15.234 | 0.407 |
| go-v0.40 x go-v0.44 (quic-v1) | go-v0.40 | go-v0.44 | quic-v1 | - | - | ✅ | 4s | 17.007 | 0.813 |
| go-v0.40 x go-v0.44 (wss, noise, yamux) | go-v0.40 | go-v0.44 | wss | noise | yamux | ✅ | 6s | 20.357 | 1.097 |
| go-v0.40 x go-v0.44 (webtransport) | go-v0.40 | go-v0.44 | webtransport | - | - | ✅ | 5s | 15.739 | 1.32 |
| go-v0.40 x go-v0.44 (webrtc-direct) | go-v0.40 | go-v0.44 | webrtc-direct | - | - | ✅ | 4s | 215.961 | 0.516 |
| go-v0.40 x go-v0.45 (tcp, tls, yamux) | go-v0.40 | go-v0.45 | tcp | tls | yamux | ✅ | 5s | 10.075 | 0.415 |
| go-v0.40 x go-v0.45 (tcp, noise, yamux) | go-v0.40 | go-v0.45 | tcp | noise | yamux | ✅ | 4s | 16.19 | 5.428 |
| go-v0.40 x go-v0.45 (ws, tls, yamux) | go-v0.40 | go-v0.45 | ws | tls | yamux | ✅ | 5s | 13.204 | 0.341 |
| go-v0.40 x go-v0.45 (ws, noise, yamux) | go-v0.40 | go-v0.45 | ws | noise | yamux | ✅ | 4s | 20.19 | 1.446 |
| go-v0.40 x go-v0.45 (wss, noise, yamux) | go-v0.40 | go-v0.45 | wss | noise | yamux | ✅ | 5s | 19.574 | 0.32 |
| go-v0.40 x go-v0.45 (wss, tls, yamux) | go-v0.40 | go-v0.45 | wss | tls | yamux | ✅ | 5s | 28.49 | 7.847 |
| go-v0.40 x go-v0.45 (quic-v1) | go-v0.40 | go-v0.45 | quic-v1 | - | - | ✅ | 5s | 17.111 | 0.785 |
| go-v0.40 x go-v0.45 (webtransport) | go-v0.40 | go-v0.45 | webtransport | - | - | ✅ | 5s | 15.7 | 0.641 |
| go-v0.40 x go-v0.45 (webrtc-direct) | go-v0.40 | go-v0.45 | webrtc-direct | - | - | ✅ | 5s | 210.268 | 0.303 |
| go-v0.40 x python-v0.4 (tcp, noise, yamux) | go-v0.40 | python-v0.4 | tcp | noise | yamux | ✅ | 5s | 34.501 | 8.74 |
| go-v0.40 x python-v0.4 (wss, noise, yamux) | go-v0.40 | python-v0.4 | wss | noise | yamux | ✅ | 5s | 31.12 | 4.37 |
| go-v0.40 x python-v0.4 (ws, noise, yamux) | go-v0.40 | python-v0.4 | ws | noise | yamux | ✅ | 5s | 33.306 | 5.974 |
| go-v0.40 x python-v0.4 (quic-v1) | go-v0.40 | python-v0.4 | quic-v1 | - | - | ✅ | 6s | 54.362 | 10.563 |
| go-v0.40 x nim-v1.14 (tcp, noise, yamux) | go-v0.40 | nim-v1.14 | tcp | noise | yamux | ✅ | 4s | 222.217 | 47.721 |
| go-v0.40 x nim-v1.14 (ws, noise, yamux) | go-v0.40 | nim-v1.14 | ws | noise | yamux | ✅ | 5s | 257.95 | 43.648 |
| go-v0.40 x js-v1.x (tcp, noise, yamux) | go-v0.40 | js-v1.x | tcp | noise | yamux | ✅ | 20s | 213.545 | 16.688 |
| go-v0.40 x js-v1.x (ws, noise, yamux) | go-v0.40 | js-v1.x | ws | noise | yamux | ✅ | 20s | 211.541 | 21.458 |
| go-v0.40 x js-v2.x (tcp, noise, yamux) | go-v0.40 | js-v2.x | tcp | noise | yamux | ✅ | 22s | 161.94 | 30.704 |
| go-v0.40 x js-v3.x (tcp, noise, yamux) | go-v0.40 | js-v3.x | tcp | noise | yamux | ✅ | 21s | 171.802 | 23.356 |
| go-v0.40 x js-v2.x (ws, noise, yamux) | go-v0.40 | js-v2.x | ws | noise | yamux | ✅ | 22s | 181.859 | 32.243 |
| go-v0.40 x jvm-v1.2 (tcp, noise, yamux) | go-v0.40 | jvm-v1.2 | tcp | noise | yamux | ✅ | 12s | 1190.675 | 32.331 |
| go-v0.40 x jvm-v1.2 (tcp, tls, yamux) | go-v0.40 | jvm-v1.2 | tcp | tls | yamux | ✅ | 14s | 3830.213 | 14.834 |
| go-v0.40 x js-v3.x (ws, noise, yamux) | go-v0.40 | js-v3.x | ws | noise | yamux | ✅ | 22s | 115.931 | 17.343 |
| go-v0.40 x c-v0.0.1 (tcp, noise, yamux) | go-v0.40 | c-v0.0.1 | tcp | noise | yamux | ✅ | 6s | 123.169 | 54.477 |
| go-v0.40 x c-v0.0.1 (quic-v1) | go-v0.40 | c-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 34.386 | 1.679 |
| go-v0.40 x jvm-v1.2 (ws, noise, yamux) | go-v0.40 | jvm-v1.2 | ws | noise | yamux | ✅ | 9s | 1545.901 | 44.028 |
| go-v0.40 x dotnet-v1.0 (tcp, noise, yamux) | go-v0.40 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 6s | 385.849 | 49.298 |
| go-v0.40 x zig-v0.0.1 (quic-v1) | go-v0.40 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 6s | - | - |
| go-v0.40 x jvm-v1.2 (ws, tls, yamux) | go-v0.40 | jvm-v1.2 | ws | tls | yamux | ✅ | 11s | 3418.309 | 13.346 |
| go-v0.40 x eth-p2p-z-v0.0.1 (quic-v1) | go-v0.40 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 7s | 13.831 | 0.407 |
| go-v0.40 x jvm-v1.2 (quic-v1) | go-v0.40 | jvm-v1.2 | quic-v1 | - | - | ✅ | 10s | 548.615 | 9.386 |
| go-v0.41 x rust-v0.53 (tcp, tls, yamux) | go-v0.41 | rust-v0.53 | tcp | tls | yamux | ✅ | 4s | 94.019 | 46.63 |
| go-v0.41 x rust-v0.53 (tcp, noise, yamux) | go-v0.41 | rust-v0.53 | tcp | noise | yamux | ✅ | 5s | 141.076 | 47.707 |
| go-v0.41 x rust-v0.53 (ws, tls, yamux) | go-v0.41 | rust-v0.53 | ws | tls | yamux | ✅ | 5s | 223.645 | 43.369 |
| go-v0.41 x rust-v0.53 (ws, noise, yamux) | go-v0.41 | rust-v0.53 | ws | noise | yamux | ✅ | 4s | 180.496 | 47.104 |
| go-v0.41 x rust-v0.53 (quic-v1) | go-v0.41 | rust-v0.53 | quic-v1 | - | - | ✅ | 5s | 6.261 | 0.23 |
| go-v0.41 x rust-v0.53 (webrtc-direct) | go-v0.41 | rust-v0.53 | webrtc-direct | - | - | ✅ | 5s | 408.373 | 0.422 |
| go-v0.41 x rust-v0.54 (tcp, tls, yamux) | go-v0.41 | rust-v0.54 | tcp | tls | yamux | ✅ | 6s | 97.329 | 43.991 |
| go-v0.41 x rust-v0.54 (tcp, noise, yamux) | go-v0.41 | rust-v0.54 | tcp | noise | yamux | ✅ | 5s | 100.261 | 44.989 |
| go-v0.41 x rust-v0.54 (ws, tls, yamux) | go-v0.41 | rust-v0.54 | ws | tls | yamux | ✅ | 6s | 182.38 | 46.828 |
| go-v0.41 x rust-v0.54 (quic-v1) | go-v0.41 | rust-v0.54 | quic-v1 | - | - | ✅ | 4s | 10.402 | 0.284 |
| go-v0.41 x rust-v0.54 (ws, noise, yamux) | go-v0.41 | rust-v0.54 | ws | noise | yamux | ✅ | 5s | 230.617 | 47.732 |
| go-v0.41 x rust-v0.55 (tcp, tls, yamux) | go-v0.41 | rust-v0.55 | tcp | tls | yamux | ✅ | 5s | 7.279 | 0.649 |
| go-v0.41 x rust-v0.54 (webrtc-direct) | go-v0.41 | rust-v0.54 | webrtc-direct | - | - | ✅ | 5s | 412.686 | 1.331 |
| go-v0.41 x rust-v0.55 (ws, noise, yamux) | go-v0.41 | rust-v0.55 | ws | noise | yamux | ✅ | 4s | 10.184 | 1.381 |
| go-v0.41 x rust-v0.55 (tcp, noise, yamux) | go-v0.41 | rust-v0.55 | tcp | noise | yamux | ✅ | 6s | 8.158 | 1.301 |
| go-v0.41 x rust-v0.55 (ws, tls, yamux) | go-v0.41 | rust-v0.55 | ws | tls | yamux | ✅ | 6s | 10.336 | 0.416 |
| go-v0.41 x rust-v0.55 (quic-v1) | go-v0.41 | rust-v0.55 | quic-v1 | - | - | ✅ | 5s | 7.81 | 0.509 |
| go-v0.41 x rust-v0.56 (tcp, tls, yamux) | go-v0.41 | rust-v0.56 | tcp | tls | yamux | ✅ | 4s | 9.658 | 0.438 |
| go-v0.41 x rust-v0.55 (webrtc-direct) | go-v0.41 | rust-v0.55 | webrtc-direct | - | - | ✅ | 5s | 413.283 | 0.332 |
| go-v0.41 x rust-v0.56 (tcp, noise, yamux) | go-v0.41 | rust-v0.56 | tcp | noise | yamux | ✅ | 4s | 7.408 | 0.692 |
| go-v0.41 x rust-v0.56 (ws, tls, yamux) | go-v0.41 | rust-v0.56 | ws | tls | yamux | ✅ | 4s | 10.339 | 0.422 |
| go-v0.41 x rust-v0.56 (ws, noise, yamux) | go-v0.41 | rust-v0.56 | ws | noise | yamux | ✅ | 5s | 8.71 | 0.49 |
| go-v0.41 x rust-v0.56 (quic-v1) | go-v0.41 | rust-v0.56 | quic-v1 | - | - | ✅ | 4s | 10.611 | 1.698 |
| go-v0.41 x go-v0.38 (tcp, tls, yamux) | go-v0.41 | go-v0.38 | tcp | tls | yamux | ✅ | 4s | 4.573 | 0.214 |
| go-v0.41 x go-v0.38 (tcp, noise, yamux) | go-v0.41 | go-v0.38 | tcp | noise | yamux | ✅ | 5s | 9.639 | 0.953 |
| go-v0.41 x go-v0.38 (ws, tls, yamux) | go-v0.41 | go-v0.38 | ws | tls | yamux | ✅ | 4s | 13.239 | 1.64 |
| go-v0.41 x go-v0.38 (wss, tls, yamux) | go-v0.41 | go-v0.38 | wss | tls | yamux | ✅ | 4s | 7.955 | 0.219 |
| go-v0.41 x go-v0.38 (ws, noise, yamux) | go-v0.41 | go-v0.38 | ws | noise | yamux | ✅ | 5s | 11.705 | 0.852 |
| go-v0.41 x go-v0.38 (quic-v1) | go-v0.41 | go-v0.38 | quic-v1 | - | - | ✅ | 4s | 16.782 | 0.623 |
| go-v0.41 x go-v0.38 (webtransport) | go-v0.41 | go-v0.38 | webtransport | - | - | ✅ | 5s | 19.956 | 2.357 |
| go-v0.41 x rust-v0.56 (webrtc-direct) | go-v0.41 | rust-v0.56 | webrtc-direct | - | - | ❌ | 10s | - | - |
| go-v0.41 x go-v0.38 (wss, noise, yamux) | go-v0.41 | go-v0.38 | wss | noise | yamux | ✅ | 7s | 21.586 | 3.469 |
| go-v0.41 x go-v0.38 (webrtc-direct) | go-v0.41 | go-v0.38 | webrtc-direct | - | - | ✅ | 5s | 206.914 | 0.255 |
| go-v0.41 x go-v0.39 (tcp, tls, yamux) | go-v0.41 | go-v0.39 | tcp | tls | yamux | ✅ | 5s | 8.093 | 0.274 |
| go-v0.41 x go-v0.39 (tcp, noise, yamux) | go-v0.41 | go-v0.39 | tcp | noise | yamux | ✅ | 4s | 7.642 | 0.36 |
| go-v0.41 x go-v0.39 (ws, tls, yamux) | go-v0.41 | go-v0.39 | ws | tls | yamux | ✅ | 5s | 9.213 | 0.299 |
| go-v0.41 x go-v0.39 (ws, noise, yamux) | go-v0.41 | go-v0.39 | ws | noise | yamux | ✅ | 4s | 23.15 | 0.983 |
| go-v0.41 x go-v0.39 (quic-v1) | go-v0.41 | go-v0.39 | quic-v1 | - | - | ✅ | 4s | 19.692 | 3.319 |
| go-v0.41 x go-v0.39 (wss, noise, yamux) | go-v0.41 | go-v0.39 | wss | noise | yamux | ✅ | 5s | 14.717 | 0.331 |
| go-v0.41 x go-v0.39 (webtransport) | go-v0.41 | go-v0.39 | webtransport | - | - | ✅ | 4s | 13.675 | 0.595 |
| go-v0.41 x go-v0.39 (wss, tls, yamux) | go-v0.41 | go-v0.39 | wss | tls | yamux | ✅ | 7s | 17.214 | 0.532 |
| go-v0.41 x go-v0.39 (webrtc-direct) | go-v0.41 | go-v0.39 | webrtc-direct | - | - | ✅ | 5s | 215.553 | 0.721 |
| go-v0.41 x go-v0.40 (tcp, tls, yamux) | go-v0.41 | go-v0.40 | tcp | tls | yamux | ✅ | 5s | 7.945 | 0.331 |
| go-v0.41 x go-v0.40 (tcp, noise, yamux) | go-v0.41 | go-v0.40 | tcp | noise | yamux | ✅ | 5s | 8.595 | 0.481 |
| go-v0.41 x go-v0.40 (ws, tls, yamux) | go-v0.41 | go-v0.40 | ws | tls | yamux | ✅ | 4s | 10.254 | 0.506 |
| go-v0.41 x go-v0.40 (ws, noise, yamux) | go-v0.41 | go-v0.40 | ws | noise | yamux | ✅ | 5s | 16.696 | 4.825 |
| go-v0.41 x go-v0.40 (wss, noise, yamux) | go-v0.41 | go-v0.40 | wss | noise | yamux | ✅ | 5s | 10.326 | 0.334 |
| go-v0.41 x go-v0.40 (wss, tls, yamux) | go-v0.41 | go-v0.40 | wss | tls | yamux | ✅ | 6s | 10.681 | 0.817 |
| go-v0.41 x go-v0.40 (quic-v1) | go-v0.41 | go-v0.40 | quic-v1 | - | - | ✅ | 6s | 17.452 | 0.713 |
| go-v0.41 x go-v0.40 (webtransport) | go-v0.41 | go-v0.40 | webtransport | - | - | ✅ | 5s | 6.511 | 0.291 |
| go-v0.41 x go-v0.40 (webrtc-direct) | go-v0.41 | go-v0.40 | webrtc-direct | - | - | ✅ | 5s | 209.572 | 0.345 |
| go-v0.41 x go-v0.41 (tcp, tls, yamux) | go-v0.41 | go-v0.41 | tcp | tls | yamux | ✅ | 6s | 5.57 | 0.176 |
| go-v0.41 x go-v0.41 (tcp, noise, yamux) | go-v0.41 | go-v0.41 | tcp | noise | yamux | ✅ | 5s | 5.553 | 0.213 |
| go-v0.41 x go-v0.41 (ws, tls, yamux) | go-v0.41 | go-v0.41 | ws | tls | yamux | ✅ | 5s | 7.384 | 0.396 |
| go-v0.41 x go-v0.41 (ws, noise, yamux) | go-v0.41 | go-v0.41 | ws | noise | yamux | ✅ | 4s | 15.882 | 0.427 |
| go-v0.41 x go-v0.41 (wss, tls, yamux) | go-v0.41 | go-v0.41 | wss | tls | yamux | ✅ | 5s | 16.854 | 0.868 |
| go-v0.41 x go-v0.41 (wss, noise, yamux) | go-v0.41 | go-v0.41 | wss | noise | yamux | ✅ | 5s | 8.504 | 0.201 |
| go-v0.41 x go-v0.41 (quic-v1) | go-v0.41 | go-v0.41 | quic-v1 | - | - | ✅ | 5s | 11.558 | 1.574 |
| go-v0.41 x go-v0.41 (webtransport) | go-v0.41 | go-v0.41 | webtransport | - | - | ✅ | 6s | 15.817 | 0.721 |
| go-v0.41 x go-v0.41 (webrtc-direct) | go-v0.41 | go-v0.41 | webrtc-direct | - | - | ✅ | 5s | 211.514 | 0.712 |
| go-v0.41 x go-v0.42 (tcp, tls, yamux) | go-v0.41 | go-v0.42 | tcp | tls | yamux | ✅ | 5s | 10.517 | 1.861 |
| go-v0.41 x go-v0.42 (tcp, noise, yamux) | go-v0.41 | go-v0.42 | tcp | noise | yamux | ✅ | 4s | 8.266 | 0.629 |
| go-v0.41 x go-v0.42 (ws, tls, yamux) | go-v0.41 | go-v0.42 | ws | tls | yamux | ✅ | 4s | 10.158 | 0.396 |
| go-v0.41 x go-v0.42 (ws, noise, yamux) | go-v0.41 | go-v0.42 | ws | noise | yamux | ✅ | 5s | 11.319 | 0.905 |
| go-v0.41 x go-v0.42 (wss, noise, yamux) | go-v0.41 | go-v0.42 | wss | noise | yamux | ✅ | 5s | 26.33 | 0.427 |
| go-v0.41 x go-v0.42 (quic-v1) | go-v0.41 | go-v0.42 | quic-v1 | - | - | ✅ | 5s | 14.49 | 1.606 |
| go-v0.41 x go-v0.42 (wss, tls, yamux) | go-v0.41 | go-v0.42 | wss | tls | yamux | ✅ | 6s | 12.353 | 0.548 |
| go-v0.41 x go-v0.42 (webtransport) | go-v0.41 | go-v0.42 | webtransport | - | - | ✅ | 5s | 10.297 | 0.375 |
| go-v0.41 x go-v0.42 (webrtc-direct) | go-v0.41 | go-v0.42 | webrtc-direct | - | - | ✅ | 5s | 22.876 | 1.321 |
| go-v0.41 x go-v0.43 (tcp, tls, yamux) | go-v0.41 | go-v0.43 | tcp | tls | yamux | ✅ | 5s | 9.17 | 1.046 |
| go-v0.41 x go-v0.43 (tcp, noise, yamux) | go-v0.41 | go-v0.43 | tcp | noise | yamux | ✅ | 5s | 6.893 | 0.28 |
| go-v0.41 x go-v0.43 (ws, tls, yamux) | go-v0.41 | go-v0.43 | ws | tls | yamux | ✅ | 4s | 10.316 | 1.033 |
| go-v0.41 x go-v0.43 (ws, noise, yamux) | go-v0.41 | go-v0.43 | ws | noise | yamux | ✅ | 4s | 10.153 | 3.37 |
| go-v0.41 x go-v0.43 (wss, tls, yamux) | go-v0.41 | go-v0.43 | wss | tls | yamux | ✅ | 5s | 21.65 | 1.117 |
| go-v0.41 x go-v0.43 (wss, noise, yamux) | go-v0.41 | go-v0.43 | wss | noise | yamux | ✅ | 5s | 18.403 | 0.569 |
| go-v0.41 x go-v0.43 (quic-v1) | go-v0.41 | go-v0.43 | quic-v1 | - | - | ✅ | 5s | 12.545 | 1.537 |
| go-v0.41 x go-v0.43 (webtransport) | go-v0.41 | go-v0.43 | webtransport | - | - | ✅ | 5s | 7.928 | 0.28 |
| go-v0.41 x go-v0.43 (webrtc-direct) | go-v0.41 | go-v0.43 | webrtc-direct | - | - | ✅ | 5s | 228.322 | 1.47 |
| go-v0.41 x go-v0.44 (tcp, tls, yamux) | go-v0.41 | go-v0.44 | tcp | tls | yamux | ✅ | 5s | 22.062 | 2.332 |
| go-v0.41 x go-v0.44 (tcp, noise, yamux) | go-v0.41 | go-v0.44 | tcp | noise | yamux | ✅ | 5s | 13.919 | 2.184 |
| go-v0.41 x go-v0.44 (ws, tls, yamux) | go-v0.41 | go-v0.44 | ws | tls | yamux | ✅ | 4s | 10.508 | 1.396 |
| go-v0.41 x go-v0.44 (ws, noise, yamux) | go-v0.41 | go-v0.44 | ws | noise | yamux | ✅ | 4s | 13.115 | 0.521 |
| go-v0.41 x go-v0.44 (wss, noise, yamux) | go-v0.41 | go-v0.44 | wss | noise | yamux | ✅ | 4s | 23.215 | 6.086 |
| go-v0.41 x go-v0.44 (wss, tls, yamux) | go-v0.41 | go-v0.44 | wss | tls | yamux | ✅ | 5s | 17.232 | 0.593 |
| go-v0.41 x go-v0.44 (quic-v1) | go-v0.41 | go-v0.44 | quic-v1 | - | - | ✅ | 4s | 14.17 | 0.468 |
| go-v0.41 x go-v0.44 (webtransport) | go-v0.41 | go-v0.44 | webtransport | - | - | ✅ | 5s | 16.121 | 0.666 |
| go-v0.41 x go-v0.44 (webrtc-direct) | go-v0.41 | go-v0.44 | webrtc-direct | - | - | ✅ | 4s | 215.561 | 0.349 |
| go-v0.41 x go-v0.45 (tcp, tls, yamux) | go-v0.41 | go-v0.45 | tcp | tls | yamux | ✅ | 4s | 8.669 | 0.927 |
| go-v0.41 x go-v0.45 (tcp, noise, yamux) | go-v0.41 | go-v0.45 | tcp | noise | yamux | ✅ | 5s | 8.148 | 0.539 |
| go-v0.41 x go-v0.45 (ws, tls, yamux) | go-v0.41 | go-v0.45 | ws | tls | yamux | ✅ | 5s | 7.067 | 0.409 |
| go-v0.41 x go-v0.45 (ws, noise, yamux) | go-v0.41 | go-v0.45 | ws | noise | yamux | ✅ | 4s | 9.439 | 0.628 |
| go-v0.41 x go-v0.45 (quic-v1) | go-v0.41 | go-v0.45 | quic-v1 | - | - | ✅ | 5s | 21.121 | 0.81 |
| go-v0.41 x go-v0.45 (wss, tls, yamux) | go-v0.41 | go-v0.45 | wss | tls | yamux | ✅ | 6s | 32.938 | 1.451 |
| go-v0.41 x go-v0.45 (wss, noise, yamux) | go-v0.41 | go-v0.45 | wss | noise | yamux | ✅ | 6s | 13.55 | 0.543 |
| go-v0.41 x go-v0.45 (webtransport) | go-v0.41 | go-v0.45 | webtransport | - | - | ✅ | 5s | 28.746 | 1.452 |
| go-v0.41 x go-v0.45 (webrtc-direct) | go-v0.41 | go-v0.45 | webrtc-direct | - | - | ✅ | 5s | 10.751 | 0.514 |
| go-v0.41 x python-v0.4 (tcp, noise, yamux) | go-v0.41 | python-v0.4 | tcp | noise | yamux | ✅ | 5s | 23.413 | 2.958 |
| go-v0.41 x python-v0.4 (ws, noise, yamux) | go-v0.41 | python-v0.4 | ws | noise | yamux | ✅ | 5s | 30.81 | 7.234 |
| go-v0.41 x python-v0.4 (wss, noise, yamux) | go-v0.41 | python-v0.4 | wss | noise | yamux | ✅ | 5s | 34.608 | 5.044 |
| go-v0.41 x python-v0.4 (quic-v1) | go-v0.41 | python-v0.4 | quic-v1 | - | - | ✅ | 6s | 72.952 | 12.099 |
| go-v0.41 x nim-v1.14 (tcp, noise, yamux) | go-v0.41 | nim-v1.14 | tcp | noise | yamux | ✅ | 5s | 211.348 | 43.567 |
| go-v0.41 x nim-v1.14 (ws, noise, yamux) | go-v0.41 | nim-v1.14 | ws | noise | yamux | ✅ | 5s | 263.152 | 43.54 |
| go-v0.41 x js-v1.x (tcp, noise, yamux) | go-v0.41 | js-v1.x | tcp | noise | yamux | ✅ | 18s | 187.638 | 37.356 |
| go-v0.41 x js-v1.x (ws, noise, yamux) | go-v0.41 | js-v1.x | ws | noise | yamux | ✅ | 20s | 172.188 | 17.176 |
| go-v0.41 x jvm-v1.2 (tcp, noise, yamux) | go-v0.41 | jvm-v1.2 | tcp | noise | yamux | ✅ | 10s | 1022.453 | 18.51 |
| go-v0.41 x js-v2.x (ws, noise, yamux) | go-v0.41 | js-v2.x | ws | noise | yamux | ✅ | 22s | 170.363 | 26.887 |
| go-v0.41 x js-v3.x (tcp, noise, yamux) | go-v0.41 | js-v3.x | tcp | noise | yamux | ✅ | 22s | 198.522 | 35.828 |
| go-v0.41 x js-v2.x (tcp, noise, yamux) | go-v0.41 | js-v2.x | tcp | noise | yamux | ✅ | 24s | 233.83 | 21.672 |
| go-v0.41 x jvm-v1.2 (tcp, tls, yamux) | go-v0.41 | jvm-v1.2 | tcp | tls | yamux | ✅ | 14s | 3488.27 | 9.749 |
| go-v0.41 x js-v3.x (ws, noise, yamux) | go-v0.41 | js-v3.x | ws | noise | yamux | ✅ | 22s | 167.295 | 12.748 |
| go-v0.41 x jvm-v1.2 (ws, tls, yamux) | go-v0.41 | jvm-v1.2 | ws | tls | yamux | ✅ | 9s | 2478.099 | 29.34 |
| go-v0.41 x c-v0.0.1 (tcp, noise, yamux) | go-v0.41 | c-v0.0.1 | tcp | noise | yamux | ✅ | 5s | 146.409 | 52.898 |
| go-v0.41 x c-v0.0.1 (quic-v1) | go-v0.41 | c-v0.0.1 | quic-v1 | - | - | ✅ | 5s | 27.384 | 2.909 |
| go-v0.41 x jvm-v1.2 (ws, noise, yamux) | go-v0.41 | jvm-v1.2 | ws | noise | yamux | ✅ | 10s | 1096.83 | 31.414 |
| go-v0.41 x zig-v0.0.1 (quic-v1) | go-v0.41 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 5s | - | - |
| go-v0.41 x dotnet-v1.0 (tcp, noise, yamux) | go-v0.41 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 6s | 332.587 | 43.052 |
| go-v0.41 x eth-p2p-z-v0.0.1 (quic-v1) | go-v0.41 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 10.89 | 0.339 |
| go-v0.41 x jvm-v1.2 (quic-v1) | go-v0.41 | jvm-v1.2 | quic-v1 | - | - | ✅ | 10s | 607.051 | 6.479 |
| go-v0.42 x rust-v0.53 (tcp, noise, yamux) | go-v0.42 | rust-v0.53 | tcp | noise | yamux | ✅ | 5s | 91.222 | 41.331 |
| go-v0.42 x rust-v0.53 (tcp, tls, yamux) | go-v0.42 | rust-v0.53 | tcp | tls | yamux | ✅ | 5s | 136.088 | 43.816 |
| go-v0.42 x rust-v0.53 (ws, tls, yamux) | go-v0.42 | rust-v0.53 | ws | tls | yamux | ✅ | 5s | 229.824 | 43.774 |
| go-v0.42 x rust-v0.53 (quic-v1) | go-v0.42 | rust-v0.53 | quic-v1 | - | - | ✅ | 4s | 9.525 | 0.899 |
| go-v0.42 x rust-v0.53 (ws, noise, yamux) | go-v0.42 | rust-v0.53 | ws | noise | yamux | ✅ | 5s | 293.352 | 43.609 |
| go-v0.42 x rust-v0.53 (webrtc-direct) | go-v0.42 | rust-v0.53 | webrtc-direct | - | - | ✅ | 5s | 223.573 | 1.178 |
| go-v0.42 x rust-v0.54 (tcp, tls, yamux) | go-v0.42 | rust-v0.54 | tcp | tls | yamux | ✅ | 5s | 89.989 | 41.932 |
| go-v0.42 x rust-v0.54 (tcp, noise, yamux) | go-v0.42 | rust-v0.54 | tcp | noise | yamux | ✅ | 4s | 96.524 | 43.767 |
| go-v0.42 x rust-v0.54 (ws, tls, yamux) | go-v0.42 | rust-v0.54 | ws | tls | yamux | ✅ | 4s | 187.225 | 41.722 |
| go-v0.42 x rust-v0.54 (quic-v1) | go-v0.42 | rust-v0.54 | quic-v1 | - | - | ✅ | 5s | 13.627 | 0.966 |
| go-v0.42 x rust-v0.54 (ws, noise, yamux) | go-v0.42 | rust-v0.54 | ws | noise | yamux | ✅ | 5s | 197.45 | 43.36 |
| go-v0.42 x rust-v0.55 (tcp, tls, yamux) | go-v0.42 | rust-v0.55 | tcp | tls | yamux | ✅ | 4s | 4.532 | 0.146 |
| go-v0.42 x rust-v0.54 (webrtc-direct) | go-v0.42 | rust-v0.54 | webrtc-direct | - | - | ✅ | 5s | 429.223 | 1.826 |
| go-v0.42 x rust-v0.55 (tcp, noise, yamux) | go-v0.42 | rust-v0.55 | tcp | noise | yamux | ✅ | 5s | 6.321 | 0.217 |
| go-v0.42 x rust-v0.55 (ws, tls, yamux) | go-v0.42 | rust-v0.55 | ws | tls | yamux | ✅ | 4s | 13.896 | 6.03 |
| go-v0.42 x rust-v0.55 (ws, noise, yamux) | go-v0.42 | rust-v0.55 | ws | noise | yamux | ✅ | 5s | 6.563 | 0.269 |
| go-v0.42 x rust-v0.55 (quic-v1) | go-v0.42 | rust-v0.55 | quic-v1 | - | - | ✅ | 4s | 12.531 | 0.568 |
| go-v0.42 x rust-v0.56 (tcp, noise, yamux) | go-v0.42 | rust-v0.56 | tcp | noise | yamux | ✅ | 4s | 7.042 | 0.97 |
| go-v0.42 x rust-v0.56 (tcp, tls, yamux) | go-v0.42 | rust-v0.56 | tcp | tls | yamux | ✅ | 5s | 7.04 | 0.379 |
| go-v0.42 x rust-v0.55 (webrtc-direct) | go-v0.42 | rust-v0.55 | webrtc-direct | - | - | ✅ | 6s | 412.802 | 0.838 |
| go-v0.42 x rust-v0.56 (ws, tls, yamux) | go-v0.42 | rust-v0.56 | ws | tls | yamux | ✅ | 6s | 4.293 | 0.205 |
| go-v0.42 x rust-v0.56 (ws, noise, yamux) | go-v0.42 | rust-v0.56 | ws | noise | yamux | ✅ | 5s | 5.205 | 0.298 |
| go-v0.42 x rust-v0.56 (quic-v1) | go-v0.42 | rust-v0.56 | quic-v1 | - | - | ✅ | 5s | 6.976 | 0.192 |
| go-v0.42 x go-v0.38 (tcp, tls, yamux) | go-v0.42 | go-v0.38 | tcp | tls | yamux | ✅ | 4s | 16.24 | 0.52 |
| go-v0.42 x go-v0.38 (tcp, noise, yamux) | go-v0.42 | go-v0.38 | tcp | noise | yamux | ✅ | 4s | 6.99 | 0.217 |
| go-v0.42 x go-v0.38 (ws, tls, yamux) | go-v0.42 | go-v0.38 | ws | tls | yamux | ✅ | 4s | 11.736 | 1.359 |
| go-v0.42 x go-v0.38 (ws, noise, yamux) | go-v0.42 | go-v0.38 | ws | noise | yamux | ✅ | 4s | 6.606 | 0.605 |
| go-v0.42 x go-v0.38 (wss, tls, yamux) | go-v0.42 | go-v0.38 | wss | tls | yamux | ✅ | 5s | 13.86 | 2.975 |
| go-v0.42 x go-v0.38 (wss, noise, yamux) | go-v0.42 | go-v0.38 | wss | noise | yamux | ✅ | 4s | 14.166 | 0.453 |
| go-v0.42 x go-v0.38 (quic-v1) | go-v0.42 | go-v0.38 | quic-v1 | - | - | ✅ | 5s | 10.267 | 1.184 |
| go-v0.42 x rust-v0.56 (webrtc-direct) | go-v0.42 | rust-v0.56 | webrtc-direct | - | - | ❌ | 10s | - | - |
| go-v0.42 x go-v0.38 (webtransport) | go-v0.42 | go-v0.38 | webtransport | - | - | ✅ | 4s | 9.826 | 0.367 |
| go-v0.42 x go-v0.38 (webrtc-direct) | go-v0.42 | go-v0.38 | webrtc-direct | - | - | ✅ | 5s | 216.798 | 0.91 |
| go-v0.42 x go-v0.39 (tcp, noise, yamux) | go-v0.42 | go-v0.39 | tcp | noise | yamux | ✅ | 5s | 9.96 | 0.475 |
| go-v0.42 x go-v0.39 (tcp, tls, yamux) | go-v0.42 | go-v0.39 | tcp | tls | yamux | ✅ | 5s | 17.657 | 4.48 |
| go-v0.42 x go-v0.39 (ws, tls, yamux) | go-v0.42 | go-v0.39 | ws | tls | yamux | ✅ | 5s | 12.092 | 0.665 |
| go-v0.42 x go-v0.39 (ws, noise, yamux) | go-v0.42 | go-v0.39 | ws | noise | yamux | ✅ | 6s | 19.039 | 0.525 |
| go-v0.42 x go-v0.39 (wss, tls, yamux) | go-v0.42 | go-v0.39 | wss | tls | yamux | ✅ | 5s | 34.51 | 0.762 |
| go-v0.42 x go-v0.39 (wss, noise, yamux) | go-v0.42 | go-v0.39 | wss | noise | yamux | ✅ | 6s | 17.154 | 0.599 |
| go-v0.42 x go-v0.39 (quic-v1) | go-v0.42 | go-v0.39 | quic-v1 | - | - | ✅ | 5s | 14.75 | 0.674 |
| go-v0.42 x go-v0.39 (webtransport) | go-v0.42 | go-v0.39 | webtransport | - | - | ✅ | 5s | 11.57 | 0.335 |
| go-v0.42 x go-v0.39 (webrtc-direct) | go-v0.42 | go-v0.39 | webrtc-direct | - | - | ✅ | 4s | 215.883 | 0.52 |
| go-v0.42 x go-v0.40 (tcp, tls, yamux) | go-v0.42 | go-v0.40 | tcp | tls | yamux | ✅ | 5s | 14.751 | 1.203 |
| go-v0.42 x go-v0.40 (ws, tls, yamux) | go-v0.42 | go-v0.40 | ws | tls | yamux | ✅ | 4s | 13.155 | 1.21 |
| go-v0.42 x go-v0.40 (tcp, noise, yamux) | go-v0.42 | go-v0.40 | tcp | noise | yamux | ✅ | 5s | 8.169 | 1.906 |
| go-v0.42 x go-v0.40 (ws, noise, yamux) | go-v0.42 | go-v0.40 | ws | noise | yamux | ✅ | 4s | 16.1 | 0.78 |
| go-v0.42 x go-v0.40 (quic-v1) | go-v0.42 | go-v0.40 | quic-v1 | - | - | ✅ | 4s | 16.204 | 2.745 |
| go-v0.42 x go-v0.40 (wss, tls, yamux) | go-v0.42 | go-v0.40 | wss | tls | yamux | ✅ | 6s | 21.966 | 0.357 |
| go-v0.42 x go-v0.40 (webtransport) | go-v0.42 | go-v0.40 | webtransport | - | - | ✅ | 5s | 12.604 | 0.482 |
| go-v0.42 x go-v0.40 (wss, noise, yamux) | go-v0.42 | go-v0.40 | wss | noise | yamux | ✅ | 6s | 26.829 | 0.834 |
| go-v0.42 x go-v0.40 (webrtc-direct) | go-v0.42 | go-v0.40 | webrtc-direct | - | - | ✅ | 5s | 213.304 | 0.539 |
| go-v0.42 x go-v0.41 (tcp, noise, yamux) | go-v0.42 | go-v0.41 | tcp | noise | yamux | ✅ | 4s | 5.905 | 0.816 |
| go-v0.42 x go-v0.41 (tcp, tls, yamux) | go-v0.42 | go-v0.41 | tcp | tls | yamux | ✅ | 6s | 10.963 | 0.273 |
| go-v0.42 x go-v0.41 (ws, tls, yamux) | go-v0.42 | go-v0.41 | ws | tls | yamux | ✅ | 5s | 16.571 | 1.204 |
| go-v0.42 x go-v0.41 (ws, noise, yamux) | go-v0.42 | go-v0.41 | ws | noise | yamux | ✅ | 4s | 21.724 | 8.532 |
| go-v0.42 x go-v0.41 (wss, noise, yamux) | go-v0.42 | go-v0.41 | wss | noise | yamux | ✅ | 4s | 19.92 | 1.087 |
| go-v0.42 x go-v0.41 (quic-v1) | go-v0.42 | go-v0.41 | quic-v1 | - | - | ✅ | 5s | 13.885 | 1.383 |
| go-v0.42 x go-v0.41 (wss, tls, yamux) | go-v0.42 | go-v0.41 | wss | tls | yamux | ✅ | 6s | 19.018 | 1.959 |
| go-v0.42 x go-v0.41 (webtransport) | go-v0.42 | go-v0.41 | webtransport | - | - | ✅ | 5s | 21.056 | 6.567 |
| go-v0.42 x go-v0.41 (webrtc-direct) | go-v0.42 | go-v0.41 | webrtc-direct | - | - | ✅ | 5s | 215.035 | 0.518 |
| go-v0.42 x go-v0.42 (tcp, tls, yamux) | go-v0.42 | go-v0.42 | tcp | tls | yamux | ✅ | 4s | 16.749 | 0.487 |
| go-v0.42 x go-v0.42 (tcp, noise, yamux) | go-v0.42 | go-v0.42 | tcp | noise | yamux | ✅ | 5s | 8.928 | 1.179 |
| go-v0.42 x go-v0.42 (ws, tls, yamux) | go-v0.42 | go-v0.42 | ws | tls | yamux | ✅ | 4s | 7.991 | 0.689 |
| go-v0.42 x go-v0.42 (ws, noise, yamux) | go-v0.42 | go-v0.42 | ws | noise | yamux | ✅ | 5s | 15.758 | 4.98 |
| go-v0.42 x go-v0.42 (quic-v1) | go-v0.42 | go-v0.42 | quic-v1 | - | - | ✅ | 4s | 34.496 | 3.101 |
| go-v0.42 x go-v0.42 (wss, tls, yamux) | go-v0.42 | go-v0.42 | wss | tls | yamux | ✅ | 6s | 31.445 | 3.644 |
| go-v0.42 x go-v0.42 (wss, noise, yamux) | go-v0.42 | go-v0.42 | wss | noise | yamux | ✅ | 6s | 16.048 | 0.537 |
| go-v0.42 x go-v0.42 (webtransport) | go-v0.42 | go-v0.42 | webtransport | - | - | ✅ | 5s | 9.223 | 0.265 |
| go-v0.42 x go-v0.42 (webrtc-direct) | go-v0.42 | go-v0.42 | webrtc-direct | - | - | ✅ | 5s | 212.855 | 0.431 |
| go-v0.42 x go-v0.43 (tcp, tls, yamux) | go-v0.42 | go-v0.43 | tcp | tls | yamux | ✅ | 5s | 8.746 | 0.589 |
| go-v0.42 x go-v0.43 (tcp, noise, yamux) | go-v0.42 | go-v0.43 | tcp | noise | yamux | ✅ | 5s | 6.157 | 1.027 |
| go-v0.42 x go-v0.43 (ws, tls, yamux) | go-v0.42 | go-v0.43 | ws | tls | yamux | ✅ | 5s | 6.238 | 0.212 |
| go-v0.42 x go-v0.43 (ws, noise, yamux) | go-v0.42 | go-v0.43 | ws | noise | yamux | ✅ | 5s | 10.348 | 2.561 |
| go-v0.42 x go-v0.43 (quic-v1) | go-v0.42 | go-v0.43 | quic-v1 | - | - | ✅ | 4s | 23.957 | 4.695 |
| go-v0.42 x go-v0.43 (wss, tls, yamux) | go-v0.42 | go-v0.43 | wss | tls | yamux | ✅ | 5s | 15.109 | 0.759 |
| go-v0.42 x go-v0.43 (wss, noise, yamux) | go-v0.42 | go-v0.43 | wss | noise | yamux | ✅ | 6s | 19.991 | 0.82 |
| go-v0.42 x go-v0.43 (webtransport) | go-v0.42 | go-v0.43 | webtransport | - | - | ✅ | 5s | 8.075 | 0.254 |
| go-v0.42 x go-v0.43 (webrtc-direct) | go-v0.42 | go-v0.43 | webrtc-direct | - | - | ✅ | 4s | 223.141 | 0.685 |
| go-v0.42 x go-v0.44 (tcp, tls, yamux) | go-v0.42 | go-v0.44 | tcp | tls | yamux | ✅ | 5s | 10.98 | 1.502 |
| go-v0.42 x go-v0.44 (tcp, noise, yamux) | go-v0.42 | go-v0.44 | tcp | noise | yamux | ✅ | 4s | 11.486 | 1.596 |
| go-v0.42 x go-v0.44 (ws, tls, yamux) | go-v0.42 | go-v0.44 | ws | tls | yamux | ✅ | 4s | 16.456 | 7.12 |
| go-v0.42 x go-v0.44 (ws, noise, yamux) | go-v0.42 | go-v0.44 | ws | noise | yamux | ✅ | 4s | 16.85 | 0.487 |
| go-v0.42 x go-v0.44 (wss, noise, yamux) | go-v0.42 | go-v0.44 | wss | noise | yamux | ✅ | 4s | 12.202 | 0.653 |
| go-v0.42 x go-v0.44 (quic-v1) | go-v0.42 | go-v0.44 | quic-v1 | - | - | ✅ | 5s | 16.026 | 2.186 |
| go-v0.42 x go-v0.44 (wss, tls, yamux) | go-v0.42 | go-v0.44 | wss | tls | yamux | ✅ | 6s | 10.025 | 0.269 |
| go-v0.42 x go-v0.44 (webtransport) | go-v0.42 | go-v0.44 | webtransport | - | - | ✅ | 5s | 25.795 | 0.594 |
| go-v0.42 x go-v0.45 (tcp, tls, yamux) | go-v0.42 | go-v0.45 | tcp | tls | yamux | ✅ | 4s | 10.077 | 0.345 |
| go-v0.42 x go-v0.44 (webrtc-direct) | go-v0.42 | go-v0.44 | webrtc-direct | - | - | ✅ | 5s | 211.223 | 0.427 |
| go-v0.42 x go-v0.45 (tcp, noise, yamux) | go-v0.42 | go-v0.45 | tcp | noise | yamux | ✅ | 5s | 11.318 | 0.634 |
| go-v0.42 x go-v0.45 (ws, tls, yamux) | go-v0.42 | go-v0.45 | ws | tls | yamux | ✅ | 4s | 7.359 | 0.721 |
| go-v0.42 x go-v0.45 (ws, noise, yamux) | go-v0.42 | go-v0.45 | ws | noise | yamux | ✅ | 5s | 20.742 | 3.967 |
| go-v0.42 x go-v0.45 (wss, noise, yamux) | go-v0.42 | go-v0.45 | wss | noise | yamux | ✅ | 5s | 25.582 | 0.525 |
| go-v0.42 x go-v0.45 (quic-v1) | go-v0.42 | go-v0.45 | quic-v1 | - | - | ✅ | 5s | 14.409 | 0.726 |
| go-v0.42 x go-v0.45 (wss, tls, yamux) | go-v0.42 | go-v0.45 | wss | tls | yamux | ✅ | 7s | 10.436 | 0.374 |
| go-v0.42 x go-v0.45 (webtransport) | go-v0.42 | go-v0.45 | webtransport | - | - | ✅ | 5s | 11.181 | 0.429 |
| go-v0.42 x go-v0.45 (webrtc-direct) | go-v0.42 | go-v0.45 | webrtc-direct | - | - | ✅ | 6s | 214.681 | 0.497 |
| go-v0.42 x python-v0.4 (tcp, noise, yamux) | go-v0.42 | python-v0.4 | tcp | noise | yamux | ✅ | 5s | 29.622 | 5.446 |
| go-v0.42 x python-v0.4 (ws, noise, yamux) | go-v0.42 | python-v0.4 | ws | noise | yamux | ✅ | 5s | 21.776 | 4.513 |
| go-v0.42 x python-v0.4 (wss, noise, yamux) | go-v0.42 | python-v0.4 | wss | noise | yamux | ✅ | 5s | 31.603 | 5.846 |
| go-v0.42 x python-v0.4 (quic-v1) | go-v0.42 | python-v0.4 | quic-v1 | - | - | ✅ | 4s | 150.129 | 19.582 |
| go-v0.42 x nim-v1.14 (tcp, noise, yamux) | go-v0.42 | nim-v1.14 | tcp | noise | yamux | ✅ | 5s | 216.304 | 51.44 |
| go-v0.42 x nim-v1.14 (ws, noise, yamux) | go-v0.42 | nim-v1.14 | ws | noise | yamux | ✅ | 5s | 247.238 | 43.636 |
| go-v0.42 x js-v1.x (tcp, noise, yamux) | go-v0.42 | js-v1.x | tcp | noise | yamux | ✅ | 20s | 139.296 | 13.335 |
| go-v0.42 x js-v1.x (ws, noise, yamux) | go-v0.42 | js-v1.x | ws | noise | yamux | ✅ | 21s | 220.798 | 27.422 |
| go-v0.42 x jvm-v1.2 (tcp, tls, yamux) | go-v0.42 | jvm-v1.2 | tcp | tls | yamux | ✅ | 13s | 3866.422 | 35.74 |
| go-v0.42 x jvm-v1.2 (tcp, noise, yamux) | go-v0.42 | jvm-v1.2 | tcp | noise | yamux | ✅ | 12s | 1246.082 | 35.461 |
| go-v0.42 x js-v2.x (ws, noise, yamux) | go-v0.42 | js-v2.x | ws | noise | yamux | ✅ | 23s | 182.497 | 26.472 |
| go-v0.42 x js-v2.x (tcp, noise, yamux) | go-v0.42 | js-v2.x | tcp | noise | yamux | ✅ | 23s | 107.779 | 16.52 |
| go-v0.42 x js-v3.x (tcp, noise, yamux) | go-v0.42 | js-v3.x | tcp | noise | yamux | ✅ | 23s | 95.46 | 14.702 |
| go-v0.42 x js-v3.x (ws, noise, yamux) | go-v0.42 | js-v3.x | ws | noise | yamux | ✅ | 22s | 85.763 | 14.844 |
| go-v0.42 x c-v0.0.1 (tcp, noise, yamux) | go-v0.42 | c-v0.0.1 | tcp | noise | yamux | ✅ | 7s | 136.171 | 63.509 |
| go-v0.42 x c-v0.0.1 (quic-v1) | go-v0.42 | c-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 27.684 | 0.874 |
| go-v0.42 x jvm-v1.2 (ws, tls, yamux) | go-v0.42 | jvm-v1.2 | ws | tls | yamux | ✅ | 11s | 3717.443 | 15.753 |
| go-v0.42 x zig-v0.0.1 (quic-v1) | go-v0.42 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 6s | - | - |
| go-v0.42 x dotnet-v1.0 (tcp, noise, yamux) | go-v0.42 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 8s | 523.811 | 46.788 |
| go-v0.42 x jvm-v1.2 (ws, noise, yamux) | go-v0.42 | jvm-v1.2 | ws | noise | yamux | ✅ | 11s | 1669.947 | 44.185 |
| go-v0.42 x eth-p2p-z-v0.0.1 (quic-v1) | go-v0.42 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 19.874 | 0.87 |
| go-v0.42 x jvm-v1.2 (quic-v1) | go-v0.42 | jvm-v1.2 | quic-v1 | - | - | ✅ | 10s | 460.955 | 7.647 |
| go-v0.43 x rust-v0.53 (tcp, tls, yamux) | go-v0.43 | rust-v0.53 | tcp | tls | yamux | ✅ | 5s | 59.425 | 6.681 |
| go-v0.43 x rust-v0.53 (tcp, noise, yamux) | go-v0.43 | rust-v0.53 | tcp | noise | yamux | ✅ | 5s | 94.394 | 41.452 |
| go-v0.43 x rust-v0.53 (quic-v1) | go-v0.43 | rust-v0.53 | quic-v1 | - | - | ✅ | 5s | 16.387 | 3.357 |
| go-v0.43 x rust-v0.53 (ws, tls, yamux) | go-v0.43 | rust-v0.53 | ws | tls | yamux | ✅ | 5s | 178.318 | 42.724 |
| go-v0.43 x rust-v0.53 (ws, noise, yamux) | go-v0.43 | rust-v0.53 | ws | noise | yamux | ✅ | 6s | 180.666 | 45.268 |
| go-v0.43 x rust-v0.54 (tcp, tls, yamux) | go-v0.43 | rust-v0.54 | tcp | tls | yamux | ✅ | 5s | 95.601 | 45.914 |
| go-v0.43 x rust-v0.53 (webrtc-direct) | go-v0.43 | rust-v0.53 | webrtc-direct | - | - | ✅ | 6s | 410.599 | 0.43 |
| go-v0.43 x rust-v0.54 (tcp, noise, yamux) | go-v0.43 | rust-v0.54 | tcp | noise | yamux | ✅ | 5s | 135.939 | 47.281 |
| go-v0.43 x rust-v0.54 (ws, tls, yamux) | go-v0.43 | rust-v0.54 | ws | tls | yamux | ✅ | 5s | 184.192 | 42.772 |
| go-v0.43 x rust-v0.54 (ws, noise, yamux) | go-v0.43 | rust-v0.54 | ws | noise | yamux | ✅ | 5s | 137.713 | 1.376 |
| go-v0.43 x rust-v0.54 (quic-v1) | go-v0.43 | rust-v0.54 | quic-v1 | - | - | ✅ | 5s | 12.956 | 1.315 |
| go-v0.43 x rust-v0.55 (tcp, tls, yamux) | go-v0.43 | rust-v0.55 | tcp | tls | yamux | ✅ | 4s | 15.998 | 0.785 |
| go-v0.43 x rust-v0.54 (webrtc-direct) | go-v0.43 | rust-v0.54 | webrtc-direct | - | - | ✅ | 5s | 411.12 | 0.502 |
| go-v0.43 x rust-v0.55 (tcp, noise, yamux) | go-v0.43 | rust-v0.55 | tcp | noise | yamux | ✅ | 4s | 5.015 | 0.192 |
| go-v0.43 x rust-v0.55 (ws, tls, yamux) | go-v0.43 | rust-v0.55 | ws | tls | yamux | ✅ | 5s | 13.492 | 0.377 |
| go-v0.43 x rust-v0.55 (ws, noise, yamux) | go-v0.43 | rust-v0.55 | ws | noise | yamux | ✅ | 5s | 15.896 | 2.097 |
| go-v0.43 x rust-v0.55 (quic-v1) | go-v0.43 | rust-v0.55 | quic-v1 | - | - | ✅ | 4s | 6.814 | 0.602 |
| go-v0.43 x rust-v0.55 (webrtc-direct) | go-v0.43 | rust-v0.55 | webrtc-direct | - | - | ✅ | 5s | 258.875 | 0.301 |
| go-v0.43 x rust-v0.56 (tcp, tls, yamux) | go-v0.43 | rust-v0.56 | tcp | tls | yamux | ✅ | 5s | 16.206 | 1.78 |
| go-v0.43 x rust-v0.56 (tcp, noise, yamux) | go-v0.43 | rust-v0.56 | tcp | noise | yamux | ✅ | 5s | 10.941 | 0.326 |
| go-v0.43 x rust-v0.56 (ws, tls, yamux) | go-v0.43 | rust-v0.56 | ws | tls | yamux | ✅ | 5s | 13.037 | 0.371 |
| go-v0.43 x rust-v0.56 (ws, noise, yamux) | go-v0.43 | rust-v0.56 | ws | noise | yamux | ✅ | 5s | 4.93 | 0.562 |
| go-v0.43 x rust-v0.56 (quic-v1) | go-v0.43 | rust-v0.56 | quic-v1 | - | - | ✅ | 5s | 12.211 | 0.519 |
| go-v0.43 x go-v0.38 (tcp, tls, yamux) | go-v0.43 | go-v0.38 | tcp | tls | yamux | ✅ | 4s | 16.803 | 0.581 |
| go-v0.43 x go-v0.38 (tcp, noise, yamux) | go-v0.43 | go-v0.38 | tcp | noise | yamux | ✅ | 4s | 11.293 | 0.667 |
| go-v0.43 x go-v0.38 (ws, tls, yamux) | go-v0.43 | go-v0.38 | ws | tls | yamux | ✅ | 4s | 16.132 | 1.213 |
| go-v0.43 x go-v0.38 (ws, noise, yamux) | go-v0.43 | go-v0.38 | ws | noise | yamux | ✅ | 5s | 10.873 | 0.59 |
| go-v0.43 x go-v0.38 (wss, tls, yamux) | go-v0.43 | go-v0.38 | wss | tls | yamux | ✅ | 4s | 13.085 | 0.431 |
| go-v0.43 x go-v0.38 (wss, noise, yamux) | go-v0.43 | go-v0.38 | wss | noise | yamux | ✅ | 5s | 14.438 | 1.122 |
| go-v0.43 x go-v0.38 (quic-v1) | go-v0.43 | go-v0.38 | quic-v1 | - | - | ✅ | 3s | 10.08 | 0.739 |
| go-v0.43 x go-v0.38 (webtransport) | go-v0.43 | go-v0.38 | webtransport | - | - | ✅ | 5s | 16.192 | 0.808 |
| go-v0.43 x rust-v0.56 (webrtc-direct) | go-v0.43 | rust-v0.56 | webrtc-direct | - | - | ❌ | 10s | - | - |
| go-v0.43 x go-v0.38 (webrtc-direct) | go-v0.43 | go-v0.38 | webrtc-direct | - | - | ✅ | 4s | 225.287 | 0.371 |
| go-v0.43 x go-v0.39 (tcp, tls, yamux) | go-v0.43 | go-v0.39 | tcp | tls | yamux | ✅ | 5s | 10.685 | 0.937 |
| go-v0.43 x go-v0.39 (tcp, noise, yamux) | go-v0.43 | go-v0.39 | tcp | noise | yamux | ✅ | 5s | 13.331 | 0.277 |
| go-v0.43 x go-v0.39 (ws, noise, yamux) | go-v0.43 | go-v0.39 | ws | noise | yamux | ✅ | 5s | 14.38 | 0.459 |
| go-v0.43 x go-v0.39 (ws, tls, yamux) | go-v0.43 | go-v0.39 | ws | tls | yamux | ✅ | 5s | 18.661 | 1.061 |
| go-v0.43 x go-v0.39 (wss, tls, yamux) | go-v0.43 | go-v0.39 | wss | tls | yamux | ✅ | 5s | 13.189 | 0.355 |
| go-v0.43 x go-v0.39 (quic-v1) | go-v0.43 | go-v0.39 | quic-v1 | - | - | ✅ | 4s | 12.264 | 0.449 |
| go-v0.43 x go-v0.39 (webtransport) | go-v0.43 | go-v0.39 | webtransport | - | - | ✅ | 4s | 17.379 | 1.298 |
| go-v0.43 x go-v0.39 (webrtc-direct) | go-v0.43 | go-v0.39 | webrtc-direct | - | - | ✅ | 5s | 211.945 | 0.558 |
| go-v0.43 x go-v0.40 (tcp, tls, yamux) | go-v0.43 | go-v0.40 | tcp | tls | yamux | ✅ | 4s | 12.152 | 2.142 |
| go-v0.43 x go-v0.39 (wss, noise, yamux) | go-v0.43 | go-v0.39 | wss | noise | yamux | ✅ | 7s | 15.19 | 0.892 |
| go-v0.43 x go-v0.40 (tcp, noise, yamux) | go-v0.43 | go-v0.40 | tcp | noise | yamux | ✅ | 5s | 62.151 | 2.186 |
| go-v0.43 x go-v0.40 (ws, tls, yamux) | go-v0.43 | go-v0.40 | ws | tls | yamux | ✅ | 4s | 11.386 | 1.292 |
| go-v0.43 x go-v0.40 (ws, noise, yamux) | go-v0.43 | go-v0.40 | ws | noise | yamux | ✅ | 4s | 11.706 | 0.932 |
| go-v0.43 x go-v0.40 (wss, tls, yamux) | go-v0.43 | go-v0.40 | wss | tls | yamux | ✅ | 4s | 21.294 | 0.956 |
| go-v0.43 x go-v0.40 (quic-v1) | go-v0.43 | go-v0.40 | quic-v1 | - | - | ✅ | 5s | 9.342 | 0.721 |
| go-v0.43 x go-v0.40 (wss, noise, yamux) | go-v0.43 | go-v0.40 | wss | noise | yamux | ✅ | 5s | 31.36 | 1.779 |
| go-v0.43 x go-v0.40 (webtransport) | go-v0.43 | go-v0.40 | webtransport | - | - | ✅ | 5s | 16.525 | 0.713 |
| go-v0.43 x go-v0.40 (webrtc-direct) | go-v0.43 | go-v0.40 | webrtc-direct | - | - | ✅ | 5s | 215.719 | 0.767 |
| go-v0.43 x go-v0.41 (tcp, tls, yamux) | go-v0.43 | go-v0.41 | tcp | tls | yamux | ✅ | 5s | 8.67 | 0.652 |
| go-v0.43 x go-v0.41 (tcp, noise, yamux) | go-v0.43 | go-v0.41 | tcp | noise | yamux | ✅ | 5s | 9.196 | 1.104 |
| go-v0.43 x go-v0.41 (ws, tls, yamux) | go-v0.43 | go-v0.41 | ws | tls | yamux | ✅ | 4s | 12.12 | 0.682 |
| go-v0.43 x go-v0.41 (ws, noise, yamux) | go-v0.43 | go-v0.41 | ws | noise | yamux | ✅ | 5s | 9.197 | 0.392 |
| go-v0.43 x go-v0.41 (wss, tls, yamux) | go-v0.43 | go-v0.41 | wss | tls | yamux | ✅ | 5s | 24.009 | 1.523 |
| go-v0.43 x go-v0.41 (wss, noise, yamux) | go-v0.43 | go-v0.41 | wss | noise | yamux | ✅ | 5s | 14.512 | 0.291 |
| go-v0.43 x go-v0.41 (quic-v1) | go-v0.43 | go-v0.41 | quic-v1 | - | - | ✅ | 5s | 16.263 | 3.35 |
| go-v0.43 x go-v0.41 (webtransport) | go-v0.43 | go-v0.41 | webtransport | - | - | ✅ | 5s | 9.874 | 0.443 |
| go-v0.43 x go-v0.41 (webrtc-direct) | go-v0.43 | go-v0.41 | webrtc-direct | - | - | ✅ | 4s | 11.895 | 0.285 |
| go-v0.43 x go-v0.42 (tcp, tls, yamux) | go-v0.43 | go-v0.42 | tcp | tls | yamux | ✅ | 4s | 10.177 | 0.343 |
| go-v0.43 x go-v0.42 (tcp, noise, yamux) | go-v0.43 | go-v0.42 | tcp | noise | yamux | ✅ | 5s | 9.079 | 0.39 |
| go-v0.43 x go-v0.42 (ws, tls, yamux) | go-v0.43 | go-v0.42 | ws | tls | yamux | ✅ | 4s | 18.206 | 0.812 |
| go-v0.43 x go-v0.42 (ws, noise, yamux) | go-v0.43 | go-v0.42 | ws | noise | yamux | ✅ | 4s | 11.694 | 1.389 |
| go-v0.43 x go-v0.42 (wss, tls, yamux) | go-v0.43 | go-v0.42 | wss | tls | yamux | ✅ | 4s | 25.632 | 2.191 |
| go-v0.43 x go-v0.42 (wss, noise, yamux) | go-v0.43 | go-v0.42 | wss | noise | yamux | ✅ | 5s | 22.879 | 2.483 |
| go-v0.43 x go-v0.42 (quic-v1) | go-v0.43 | go-v0.42 | quic-v1 | - | - | ✅ | 4s | 14.084 | 2.19 |
| go-v0.43 x go-v0.42 (webtransport) | go-v0.43 | go-v0.42 | webtransport | - | - | ✅ | 5s | 20.797 | 0.456 |
| go-v0.43 x go-v0.42 (webrtc-direct) | go-v0.43 | go-v0.42 | webrtc-direct | - | - | ✅ | 5s | 210.869 | 0.458 |
| go-v0.43 x go-v0.43 (tcp, tls, yamux) | go-v0.43 | go-v0.43 | tcp | tls | yamux | ✅ | 4s | 12.221 | 4.201 |
| go-v0.43 x go-v0.43 (tcp, noise, yamux) | go-v0.43 | go-v0.43 | tcp | noise | yamux | ✅ | 5s | 8.801 | 0.705 |
| go-v0.43 x go-v0.43 (ws, tls, yamux) | go-v0.43 | go-v0.43 | ws | tls | yamux | ✅ | 5s | 11.585 | 0.48 |
| go-v0.43 x go-v0.43 (ws, noise, yamux) | go-v0.43 | go-v0.43 | ws | noise | yamux | ✅ | 4s | 8.348 | 0.768 |
| go-v0.43 x go-v0.43 (wss, tls, yamux) | go-v0.43 | go-v0.43 | wss | tls | yamux | ✅ | 5s | 19.176 | 1.221 |
| go-v0.43 x go-v0.43 (quic-v1) | go-v0.43 | go-v0.43 | quic-v1 | - | - | ✅ | 5s | 14.172 | 0.413 |
| go-v0.43 x go-v0.43 (wss, noise, yamux) | go-v0.43 | go-v0.43 | wss | noise | yamux | ✅ | 5s | 17.861 | 1.659 |
| go-v0.43 x go-v0.43 (webtransport) | go-v0.43 | go-v0.43 | webtransport | - | - | ✅ | 5s | 9.938 | 0.481 |
| go-v0.43 x go-v0.43 (webrtc-direct) | go-v0.43 | go-v0.43 | webrtc-direct | - | - | ✅ | 5s | 210.847 | 0.719 |
| go-v0.43 x go-v0.44 (tcp, tls, yamux) | go-v0.43 | go-v0.44 | tcp | tls | yamux | ✅ | 4s | 5.954 | 0.8 |
| go-v0.43 x go-v0.44 (tcp, noise, yamux) | go-v0.43 | go-v0.44 | tcp | noise | yamux | ✅ | 5s | 8.615 | 1.096 |
| go-v0.43 x go-v0.44 (ws, tls, yamux) | go-v0.43 | go-v0.44 | ws | tls | yamux | ✅ | 5s | 7.601 | 0.554 |
| go-v0.43 x go-v0.44 (ws, noise, yamux) | go-v0.43 | go-v0.44 | ws | noise | yamux | ✅ | 5s | 51.425 | 2.246 |
| go-v0.43 x go-v0.44 (wss, tls, yamux) | go-v0.43 | go-v0.44 | wss | tls | yamux | ✅ | 6s | 20.535 | 1.047 |
| go-v0.43 x go-v0.44 (quic-v1) | go-v0.43 | go-v0.44 | quic-v1 | - | - | ✅ | 4s | 18.096 | 0.66 |
| go-v0.43 x go-v0.44 (wss, noise, yamux) | go-v0.43 | go-v0.44 | wss | noise | yamux | ✅ | 6s | 12.204 | 0.404 |
| go-v0.43 x go-v0.44 (webtransport) | go-v0.43 | go-v0.44 | webtransport | - | - | ✅ | 5s | 9.479 | 0.321 |
| go-v0.43 x go-v0.44 (webrtc-direct) | go-v0.43 | go-v0.44 | webrtc-direct | - | - | ✅ | 5s | 230.624 | 1.142 |
| go-v0.43 x go-v0.45 (tcp, noise, yamux) | go-v0.43 | go-v0.45 | tcp | noise | yamux | ✅ | 4s | 6.115 | 0.38 |
| go-v0.43 x go-v0.45 (tcp, tls, yamux) | go-v0.43 | go-v0.45 | tcp | tls | yamux | ✅ | 5s | 9.258 | 0.264 |
| go-v0.43 x go-v0.45 (ws, noise, yamux) | go-v0.43 | go-v0.45 | ws | noise | yamux | ✅ | 4s | 20.625 | 8.591 |
| go-v0.43 x go-v0.45 (ws, tls, yamux) | go-v0.43 | go-v0.45 | ws | tls | yamux | ✅ | 6s | 19.971 | 2.475 |
| go-v0.43 x go-v0.45 (wss, tls, yamux) | go-v0.43 | go-v0.45 | wss | tls | yamux | ✅ | 5s | 11.303 | 0.27 |
| go-v0.43 x go-v0.45 (quic-v1) | go-v0.43 | go-v0.45 | quic-v1 | - | - | ✅ | 4s | 6.429 | 0.272 |
| go-v0.43 x go-v0.45 (wss, noise, yamux) | go-v0.43 | go-v0.45 | wss | noise | yamux | ✅ | 6s | 17.627 | 0.358 |
| go-v0.43 x go-v0.45 (webtransport) | go-v0.43 | go-v0.45 | webtransport | - | - | ✅ | 6s | 15.196 | 1.108 |
| go-v0.43 x go-v0.45 (webrtc-direct) | go-v0.43 | go-v0.45 | webrtc-direct | - | - | ✅ | 5s | 212.727 | 0.65 |
| go-v0.43 x python-v0.4 (tcp, noise, yamux) | go-v0.43 | python-v0.4 | tcp | noise | yamux | ✅ | 5s | 29.605 | 3.773 |
| go-v0.43 x python-v0.4 (ws, noise, yamux) | go-v0.43 | python-v0.4 | ws | noise | yamux | ✅ | 5s | 36.102 | 6.267 |
| go-v0.43 x python-v0.4 (wss, noise, yamux) | go-v0.43 | python-v0.4 | wss | noise | yamux | ✅ | 6s | 46.606 | 6.499 |
| go-v0.43 x python-v0.4 (quic-v1) | go-v0.43 | python-v0.4 | quic-v1 | - | - | ✅ | 6s | 119.67 | 13.349 |
| go-v0.43 x nim-v1.14 (tcp, noise, yamux) | go-v0.43 | nim-v1.14 | tcp | noise | yamux | ✅ | 5s | 201.522 | 43.638 |
| go-v0.43 x nim-v1.14 (ws, noise, yamux) | go-v0.43 | nim-v1.14 | ws | noise | yamux | ✅ | 5s | 263.882 | 49.248 |
| go-v0.43 x js-v1.x (tcp, noise, yamux) | go-v0.43 | js-v1.x | tcp | noise | yamux | ✅ | 19s | 204.266 | 21.464 |
| go-v0.43 x js-v1.x (ws, noise, yamux) | go-v0.43 | js-v1.x | ws | noise | yamux | ✅ | 19s | 176.595 | 17.468 |
| go-v0.43 x js-v2.x (tcp, noise, yamux) | go-v0.43 | js-v2.x | tcp | noise | yamux | ✅ | 22s | 152.022 | 28.817 |
| go-v0.43 x jvm-v1.2 (tcp, noise, yamux) | go-v0.43 | jvm-v1.2 | tcp | noise | yamux | ✅ | 10s | 1070.971 | 22.028 |
| go-v0.43 x jvm-v1.2 (tcp, tls, yamux) | go-v0.43 | jvm-v1.2 | tcp | tls | yamux | ✅ | 13s | 3067.112 | 9.856 |
| go-v0.43 x js-v3.x (tcp, noise, yamux) | go-v0.43 | js-v3.x | tcp | noise | yamux | ✅ | 21s | 130.03 | 21.909 |
| go-v0.43 x js-v2.x (ws, noise, yamux) | go-v0.43 | js-v2.x | ws | noise | yamux | ✅ | 23s | 128.241 | 16.639 |
| go-v0.43 x js-v3.x (ws, noise, yamux) | go-v0.43 | js-v3.x | ws | noise | yamux | ✅ | 21s | 93.655 | 12.932 |
| go-v0.43 x c-v0.0.1 (tcp, noise, yamux) | go-v0.43 | c-v0.0.1 | tcp | noise | yamux | ✅ | 5s | 127.978 | 61.514 |
| go-v0.43 x c-v0.0.1 (quic-v1) | go-v0.43 | c-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 82.084 | 50.398 |
| go-v0.43 x jvm-v1.2 (ws, noise, yamux) | go-v0.43 | jvm-v1.2 | ws | noise | yamux | ✅ | 10s | 1538.264 | 21.575 |
| go-v0.43 x dotnet-v1.0 (tcp, noise, yamux) | go-v0.43 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 7s | 485.224 | 46.129 |
| go-v0.43 x jvm-v1.2 (ws, tls, yamux) | go-v0.43 | jvm-v1.2 | ws | tls | yamux | ✅ | 12s | 4120.681 | 25.905 |
| go-v0.43 x eth-p2p-z-v0.0.1 (quic-v1) | go-v0.43 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 19.216 | 4.062 |
| go-v0.43 x zig-v0.0.1 (quic-v1) | go-v0.43 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 7s | - | - |
| go-v0.43 x jvm-v1.2 (quic-v1) | go-v0.43 | jvm-v1.2 | quic-v1 | - | - | ✅ | 11s | 600.794 | 6.85 |
| go-v0.44 x rust-v0.53 (tcp, tls, yamux) | go-v0.44 | rust-v0.53 | tcp | tls | yamux | ✅ | 4s | 95.321 | 45.873 |
| go-v0.44 x rust-v0.53 (tcp, noise, yamux) | go-v0.44 | rust-v0.53 | tcp | noise | yamux | ✅ | 4s | 96.223 | 46.879 |
| go-v0.44 x rust-v0.53 (ws, tls, yamux) | go-v0.44 | rust-v0.53 | ws | tls | yamux | ✅ | 5s | 187.009 | 52.646 |
| go-v0.44 x rust-v0.53 (quic-v1) | go-v0.44 | rust-v0.53 | quic-v1 | - | - | ✅ | 4s | 15.969 | 0.72 |
| go-v0.44 x rust-v0.54 (tcp, tls, yamux) | go-v0.44 | rust-v0.54 | tcp | tls | yamux | ✅ | 5s | 94.87 | 43.223 |
| go-v0.44 x rust-v0.53 (ws, noise, yamux) | go-v0.44 | rust-v0.53 | ws | noise | yamux | ✅ | 6s | 222.659 | 43.842 |
| go-v0.44 x rust-v0.53 (webrtc-direct) | go-v0.44 | rust-v0.53 | webrtc-direct | - | - | ✅ | 5s | 411.378 | 0.548 |
| go-v0.44 x rust-v0.54 (tcp, noise, yamux) | go-v0.44 | rust-v0.54 | tcp | noise | yamux | ✅ | 5s | 96.406 | 42.456 |
| go-v0.44 x rust-v0.54 (ws, tls, yamux) | go-v0.44 | rust-v0.54 | ws | tls | yamux | ✅ | 5s | 185.013 | 44.996 |
| go-v0.44 x rust-v0.54 (quic-v1) | go-v0.44 | rust-v0.54 | quic-v1 | - | - | ✅ | 4s | 7.492 | 0.203 |
| go-v0.44 x rust-v0.54 (ws, noise, yamux) | go-v0.44 | rust-v0.54 | ws | noise | yamux | ✅ | 6s | 182.126 | 46.858 |
| go-v0.44 x rust-v0.55 (tcp, tls, yamux) | go-v0.44 | rust-v0.55 | tcp | tls | yamux | ✅ | 4s | 9.488 | 0.26 |
| go-v0.44 x rust-v0.55 (tcp, noise, yamux) | go-v0.44 | rust-v0.55 | tcp | noise | yamux | ✅ | 4s | 11.664 | 0.273 |
| go-v0.44 x rust-v0.55 (ws, tls, yamux) | go-v0.44 | rust-v0.55 | ws | tls | yamux | ✅ | 5s | 13.274 | 0.936 |
| go-v0.44 x rust-v0.54 (webrtc-direct) | go-v0.44 | rust-v0.54 | webrtc-direct | - | - | ✅ | 6s | 426.636 | 2.267 |
| go-v0.44 x rust-v0.55 (ws, noise, yamux) | go-v0.44 | rust-v0.55 | ws | noise | yamux | ✅ | 5s | 5.238 | 0.201 |
| go-v0.44 x rust-v0.55 (quic-v1) | go-v0.44 | rust-v0.55 | quic-v1 | - | - | ✅ | 4s | 5.739 | 0.274 |
| go-v0.44 x rust-v0.55 (webrtc-direct) | go-v0.44 | rust-v0.55 | webrtc-direct | - | - | ✅ | 5s | 411.571 | 0.343 |
| go-v0.44 x rust-v0.56 (tcp, tls, yamux) | go-v0.44 | rust-v0.56 | tcp | tls | yamux | ✅ | 5s | 7.162 | 0.359 |
| go-v0.44 x rust-v0.56 (tcp, noise, yamux) | go-v0.44 | rust-v0.56 | tcp | noise | yamux | ✅ | 4s | 8.534 | 0.642 |
| go-v0.44 x rust-v0.56 (ws, tls, yamux) | go-v0.44 | rust-v0.56 | ws | tls | yamux | ✅ | 5s | 10.467 | 0.379 |
| go-v0.44 x rust-v0.56 (ws, noise, yamux) | go-v0.44 | rust-v0.56 | ws | noise | yamux | ✅ | 5s | 8.783 | 1.437 |
| go-v0.44 x rust-v0.56 (quic-v1) | go-v0.44 | rust-v0.56 | quic-v1 | - | - | ✅ | 5s | 7.622 | 0.739 |
| go-v0.44 x go-v0.38 (tcp, tls, yamux) | go-v0.44 | go-v0.38 | tcp | tls | yamux | ✅ | 4s | 7.719 | 1.486 |
| go-v0.44 x go-v0.38 (tcp, noise, yamux) | go-v0.44 | go-v0.38 | tcp | noise | yamux | ✅ | 4s | 6.158 | 0.375 |
| go-v0.44 x go-v0.38 (ws, tls, yamux) | go-v0.44 | go-v0.38 | ws | tls | yamux | ✅ | 5s | 9.071 | 0.714 |
| go-v0.44 x go-v0.38 (ws, noise, yamux) | go-v0.44 | go-v0.38 | ws | noise | yamux | ✅ | 4s | 4.838 | 0.845 |
| go-v0.44 x go-v0.38 (wss, tls, yamux) | go-v0.44 | go-v0.38 | wss | tls | yamux | ✅ | 5s | 22.459 | 2.032 |
| go-v0.44 x go-v0.38 (quic-v1) | go-v0.44 | go-v0.38 | quic-v1 | - | - | ✅ | 5s | 20.393 | 0.5 |
| go-v0.44 x go-v0.38 (wss, noise, yamux) | go-v0.44 | go-v0.38 | wss | noise | yamux | ✅ | 5s | 20.683 | 0.367 |
| go-v0.44 x rust-v0.56 (webrtc-direct) | go-v0.44 | rust-v0.56 | webrtc-direct | - | - | ❌ | 10s | - | - |
| go-v0.44 x go-v0.38 (webtransport) | go-v0.44 | go-v0.38 | webtransport | - | - | ✅ | 5s | 12.056 | 0.456 |
| go-v0.44 x go-v0.38 (webrtc-direct) | go-v0.44 | go-v0.38 | webrtc-direct | - | - | ✅ | 5s | 15.637 | 0.476 |
| go-v0.44 x go-v0.39 (tcp, tls, yamux) | go-v0.44 | go-v0.39 | tcp | tls | yamux | ✅ | 4s | 8.203 | 0.662 |
| go-v0.44 x go-v0.39 (tcp, noise, yamux) | go-v0.44 | go-v0.39 | tcp | noise | yamux | ✅ | 5s | 7.759 | 0.402 |
| go-v0.44 x go-v0.39 (ws, tls, yamux) | go-v0.44 | go-v0.39 | ws | tls | yamux | ✅ | 4s | 18.652 | 0.814 |
| go-v0.44 x go-v0.39 (ws, noise, yamux) | go-v0.44 | go-v0.39 | ws | noise | yamux | ✅ | 5s | 15.656 | 2.704 |
| go-v0.44 x go-v0.39 (wss, tls, yamux) | go-v0.44 | go-v0.39 | wss | tls | yamux | ✅ | 4s | 15.537 | 0.616 |
| go-v0.44 x go-v0.39 (wss, noise, yamux) | go-v0.44 | go-v0.39 | wss | noise | yamux | ✅ | 5s | 11.694 | 0.362 |
| go-v0.44 x go-v0.39 (quic-v1) | go-v0.44 | go-v0.39 | quic-v1 | - | - | ✅ | 5s | 36.566 | 1.852 |
| go-v0.44 x go-v0.39 (webtransport) | go-v0.44 | go-v0.39 | webtransport | - | - | ✅ | 5s | 24.088 | 1.436 |
| go-v0.44 x go-v0.39 (webrtc-direct) | go-v0.44 | go-v0.39 | webrtc-direct | - | - | ✅ | 5s | 16.522 | 2.005 |
| go-v0.44 x go-v0.40 (tcp, tls, yamux) | go-v0.44 | go-v0.40 | tcp | tls | yamux | ✅ | 5s | 7.487 | 0.446 |
| go-v0.44 x go-v0.40 (tcp, noise, yamux) | go-v0.44 | go-v0.40 | tcp | noise | yamux | ✅ | 4s | 13.798 | 0.549 |
| go-v0.44 x go-v0.40 (ws, tls, yamux) | go-v0.44 | go-v0.40 | ws | tls | yamux | ✅ | 5s | 10.869 | 0.95 |
| go-v0.44 x go-v0.40 (ws, noise, yamux) | go-v0.44 | go-v0.40 | ws | noise | yamux | ✅ | 4s | 49.727 | 1.47 |
| go-v0.44 x go-v0.40 (wss, tls, yamux) | go-v0.44 | go-v0.40 | wss | tls | yamux | ✅ | 6s | 24.288 | 2.27 |
| go-v0.44 x go-v0.40 (webtransport) | go-v0.44 | go-v0.40 | webtransport | - | - | ✅ | 4s | 22.556 | 1.293 |
| go-v0.44 x go-v0.40 (quic-v1) | go-v0.44 | go-v0.40 | quic-v1 | - | - | ✅ | 5s | 19.438 | 2.566 |
| go-v0.44 x go-v0.40 (wss, noise, yamux) | go-v0.44 | go-v0.40 | wss | noise | yamux | ✅ | 6s | 15.101 | 1.469 |
| go-v0.44 x go-v0.40 (webrtc-direct) | go-v0.44 | go-v0.40 | webrtc-direct | - | - | ✅ | 5s | 30.952 | 0.778 |
| go-v0.44 x go-v0.41 (tcp, tls, yamux) | go-v0.44 | go-v0.41 | tcp | tls | yamux | ✅ | 5s | 10.118 | 0.944 |
| go-v0.44 x go-v0.41 (tcp, noise, yamux) | go-v0.44 | go-v0.41 | tcp | noise | yamux | ✅ | 4s | 12.689 | 0.617 |
| go-v0.44 x go-v0.41 (ws, tls, yamux) | go-v0.44 | go-v0.41 | ws | tls | yamux | ✅ | 5s | 8.26 | 0.554 |
| go-v0.44 x go-v0.41 (ws, noise, yamux) | go-v0.44 | go-v0.41 | ws | noise | yamux | ✅ | 5s | 23.302 | 0.395 |
| go-v0.44 x go-v0.41 (wss, tls, yamux) | go-v0.44 | go-v0.41 | wss | tls | yamux | ✅ | 5s | 18.215 | 1.017 |
| go-v0.44 x go-v0.41 (wss, noise, yamux) | go-v0.44 | go-v0.41 | wss | noise | yamux | ✅ | 4s | 10.317 | 0.267 |
| go-v0.44 x go-v0.41 (quic-v1) | go-v0.44 | go-v0.41 | quic-v1 | - | - | ✅ | 5s | 13.677 | 0.545 |
| go-v0.44 x go-v0.41 (webtransport) | go-v0.44 | go-v0.41 | webtransport | - | - | ✅ | 5s | 20.919 | 0.672 |
| go-v0.44 x go-v0.41 (webrtc-direct) | go-v0.44 | go-v0.41 | webrtc-direct | - | - | ✅ | 5s | 214.702 | 0.454 |
| go-v0.44 x go-v0.42 (tcp, noise, yamux) | go-v0.44 | go-v0.42 | tcp | noise | yamux | ✅ | 4s | 11.208 | 0.949 |
| go-v0.44 x go-v0.42 (tcp, tls, yamux) | go-v0.44 | go-v0.42 | tcp | tls | yamux | ✅ | 5s | 21.88 | 3.212 |
| go-v0.44 x go-v0.42 (ws, tls, yamux) | go-v0.44 | go-v0.42 | ws | tls | yamux | ✅ | 5s | 11.556 | 0.629 |
| go-v0.44 x go-v0.42 (ws, noise, yamux) | go-v0.44 | go-v0.42 | ws | noise | yamux | ✅ | 5s | 13.342 | 3.071 |
| go-v0.44 x go-v0.42 (wss, tls, yamux) | go-v0.44 | go-v0.42 | wss | tls | yamux | ✅ | 5s | 26.838 | 3.819 |
| go-v0.44 x go-v0.42 (quic-v1) | go-v0.44 | go-v0.42 | quic-v1 | - | - | ✅ | 5s | 15.523 | 2.306 |
| go-v0.44 x go-v0.42 (wss, noise, yamux) | go-v0.44 | go-v0.42 | wss | noise | yamux | ✅ | 5s | 8.656 | 0.334 |
| go-v0.44 x go-v0.42 (webtransport) | go-v0.44 | go-v0.42 | webtransport | - | - | ✅ | 5s | 21.636 | 1.258 |
| go-v0.44 x go-v0.42 (webrtc-direct) | go-v0.44 | go-v0.42 | webrtc-direct | - | - | ✅ | 4s | 218.628 | 1.612 |
| go-v0.44 x go-v0.43 (tcp, noise, yamux) | go-v0.44 | go-v0.43 | tcp | noise | yamux | ✅ | 4s | 7.735 | 1.313 |
| go-v0.44 x go-v0.43 (tcp, tls, yamux) | go-v0.44 | go-v0.43 | tcp | tls | yamux | ✅ | 6s | 12.705 | 0.607 |
| go-v0.44 x go-v0.43 (ws, tls, yamux) | go-v0.44 | go-v0.43 | ws | tls | yamux | ✅ | 4s | 7.86 | 0.283 |
| go-v0.44 x go-v0.43 (ws, noise, yamux) | go-v0.44 | go-v0.43 | ws | noise | yamux | ✅ | 4s | 14.494 | 0.72 |
| go-v0.44 x go-v0.43 (wss, tls, yamux) | go-v0.44 | go-v0.43 | wss | tls | yamux | ✅ | 5s | 19.718 | 0.845 |
| go-v0.44 x go-v0.43 (quic-v1) | go-v0.44 | go-v0.43 | quic-v1 | - | - | ✅ | 5s | 16.684 | 1.098 |
| go-v0.44 x go-v0.43 (wss, noise, yamux) | go-v0.44 | go-v0.43 | wss | noise | yamux | ✅ | 5s | 16.852 | 2.868 |
| go-v0.44 x go-v0.43 (webtransport) | go-v0.44 | go-v0.43 | webtransport | - | - | ✅ | 4s | 18.647 | 0.507 |
| go-v0.44 x go-v0.44 (tcp, tls, yamux) | go-v0.44 | go-v0.44 | tcp | tls | yamux | ✅ | 4s | 8.287 | 0.599 |
| go-v0.44 x go-v0.43 (webrtc-direct) | go-v0.44 | go-v0.43 | webrtc-direct | - | - | ✅ | 5s | 273.157 | 1.054 |
| go-v0.44 x go-v0.44 (tcp, noise, yamux) | go-v0.44 | go-v0.44 | tcp | noise | yamux | ✅ | 5s | 10.31 | 0.99 |
| go-v0.44 x go-v0.44 (ws, tls, yamux) | go-v0.44 | go-v0.44 | ws | tls | yamux | ✅ | 4s | 6.181 | 0.279 |
| go-v0.44 x go-v0.44 (ws, noise, yamux) | go-v0.44 | go-v0.44 | ws | noise | yamux | ✅ | 4s | 16.571 | 1.886 |
| go-v0.44 x go-v0.44 (wss, tls, yamux) | go-v0.44 | go-v0.44 | wss | tls | yamux | ✅ | 5s | 21.344 | 0.38 |
| go-v0.44 x go-v0.44 (quic-v1) | go-v0.44 | go-v0.44 | quic-v1 | - | - | ✅ | 4s | 22.226 | 1.82 |
| go-v0.44 x go-v0.44 (wss, noise, yamux) | go-v0.44 | go-v0.44 | wss | noise | yamux | ✅ | 5s | 14.799 | 0.382 |
| go-v0.44 x go-v0.44 (webtransport) | go-v0.44 | go-v0.44 | webtransport | - | - | ✅ | 5s | 17 | 0.501 |
| go-v0.44 x go-v0.44 (webrtc-direct) | go-v0.44 | go-v0.44 | webrtc-direct | - | - | ✅ | 5s | 216.685 | 0.318 |
| go-v0.44 x go-v0.45 (tcp, tls, yamux) | go-v0.44 | go-v0.45 | tcp | tls | yamux | ✅ | 5s | 6.851 | 0.313 |
| go-v0.44 x go-v0.45 (tcp, noise, yamux) | go-v0.44 | go-v0.45 | tcp | noise | yamux | ✅ | 5s | 9.225 | 1.264 |
| go-v0.44 x go-v0.45 (ws, tls, yamux) | go-v0.44 | go-v0.45 | ws | tls | yamux | ✅ | 5s | 73.781 | 0.544 |
| go-v0.44 x go-v0.45 (ws, noise, yamux) | go-v0.44 | go-v0.45 | ws | noise | yamux | ✅ | 4s | 11.839 | 0.65 |
| go-v0.44 x go-v0.45 (wss, tls, yamux) | go-v0.44 | go-v0.45 | wss | tls | yamux | ✅ | 5s | 15.213 | 0.296 |
| go-v0.44 x go-v0.45 (quic-v1) | go-v0.44 | go-v0.45 | quic-v1 | - | - | ✅ | 4s | 11.168 | 0.375 |
| go-v0.44 x go-v0.45 (wss, noise, yamux) | go-v0.44 | go-v0.45 | wss | noise | yamux | ✅ | 6s | 11.481 | 0.378 |
| go-v0.44 x go-v0.45 (webtransport) | go-v0.44 | go-v0.45 | webtransport | - | - | ✅ | 5s | 14.112 | 0.25 |
| go-v0.44 x go-v0.45 (webrtc-direct) | go-v0.44 | go-v0.45 | webrtc-direct | - | - | ✅ | 5s | 225.815 | 1.554 |
| go-v0.44 x python-v0.4 (tcp, noise, yamux) | go-v0.44 | python-v0.4 | tcp | noise | yamux | ✅ | 5s | 22.919 | 4.089 |
| go-v0.44 x python-v0.4 (ws, noise, yamux) | go-v0.44 | python-v0.4 | ws | noise | yamux | ✅ | 6s | 27.15 | 4.834 |
| go-v0.44 x python-v0.4 (wss, noise, yamux) | go-v0.44 | python-v0.4 | wss | noise | yamux | ✅ | 6s | 46.805 | 5.104 |
| go-v0.44 x python-v0.4 (quic-v1) | go-v0.44 | python-v0.4 | quic-v1 | - | - | ✅ | 7s | 154.859 | 15.613 |
| go-v0.44 x nim-v1.14 (tcp, noise, yamux) | go-v0.44 | nim-v1.14 | tcp | noise | yamux | ✅ | 5s | 199.936 | 43.602 |
| go-v0.44 x nim-v1.14 (ws, noise, yamux) | go-v0.44 | nim-v1.14 | ws | noise | yamux | ✅ | 5s | 247.074 | 43.479 |
| go-v0.44 x js-v1.x (tcp, noise, yamux) | go-v0.44 | js-v1.x | tcp | noise | yamux | ✅ | 19s | 176.693 | 22.589 |
| go-v0.44 x js-v1.x (ws, noise, yamux) | go-v0.44 | js-v1.x | ws | noise | yamux | ✅ | 20s | 203.435 | 43.794 |
| go-v0.44 x js-v2.x (tcp, noise, yamux) | go-v0.44 | js-v2.x | tcp | noise | yamux | ✅ | 22s | 159.905 | 25.728 |
| go-v0.44 x js-v2.x (ws, noise, yamux) | go-v0.44 | js-v2.x | ws | noise | yamux | ✅ | 21s | 216.703 | 25.717 |
| go-v0.44 x jvm-v1.2 (tcp, noise, yamux) | go-v0.44 | jvm-v1.2 | tcp | noise | yamux | ✅ | 11s | 1145.104 | 23.385 |
| go-v0.44 x js-v3.x (tcp, noise, yamux) | go-v0.44 | js-v3.x | tcp | noise | yamux | ✅ | 21s | 194.915 | 15.963 |
| go-v0.44 x jvm-v1.2 (tcp, tls, yamux) | go-v0.44 | jvm-v1.2 | tcp | tls | yamux | ✅ | 13s | 3292.745 | 9.344 |
| go-v0.44 x js-v3.x (ws, noise, yamux) | go-v0.44 | js-v3.x | ws | noise | yamux | ✅ | 21s | 86.812 | 16.802 |
| go-v0.44 x c-v0.0.1 (tcp, noise, yamux) | go-v0.44 | c-v0.0.1 | tcp | noise | yamux | ✅ | 6s | 128.913 | 60.082 |
| go-v0.44 x c-v0.0.1 (quic-v1) | go-v0.44 | c-v0.0.1 | quic-v1 | - | - | ✅ | 5s | 64.32 | 27.145 |
| go-v0.44 x jvm-v1.2 (ws, noise, yamux) | go-v0.44 | jvm-v1.2 | ws | noise | yamux | ✅ | 10s | 1494.302 | 32.073 |
| go-v0.44 x dotnet-v1.0 (tcp, noise, yamux) | go-v0.44 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 7s | 465.017 | 44.969 |
| go-v0.44 x zig-v0.0.1 (quic-v1) | go-v0.44 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 7s | - | - |
| go-v0.44 x jvm-v1.2 (ws, tls, yamux) | go-v0.44 | jvm-v1.2 | ws | tls | yamux | ✅ | 12s | 3344.271 | 13.832 |
| go-v0.44 x eth-p2p-z-v0.0.1 (quic-v1) | go-v0.44 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 7s | 11.246 | 0.623 |
| go-v0.44 x jvm-v1.2 (quic-v1) | go-v0.44 | jvm-v1.2 | quic-v1 | - | - | ✅ | 11s | 390.833 | 5.496 |
| go-v0.45 x rust-v0.53 (tcp, tls, yamux) | go-v0.45 | rust-v0.53 | tcp | tls | yamux | ✅ | 4s | 95.157 | 46.595 |
| go-v0.45 x rust-v0.53 (tcp, noise, yamux) | go-v0.45 | rust-v0.53 | tcp | noise | yamux | ✅ | 5s | 138.249 | 43.607 |
| go-v0.45 x rust-v0.53 (ws, noise, yamux) | go-v0.45 | rust-v0.53 | ws | noise | yamux | ✅ | 4s | 181.953 | 42.786 |
| go-v0.45 x rust-v0.53 (ws, tls, yamux) | go-v0.45 | rust-v0.53 | ws | tls | yamux | ✅ | 6s | 186.02 | 45.635 |
| go-v0.45 x rust-v0.53 (quic-v1) | go-v0.45 | rust-v0.53 | quic-v1 | - | - | ✅ | 5s | 8.794 | 0.71 |
| go-v0.45 x rust-v0.53 (webrtc-direct) | go-v0.45 | rust-v0.53 | webrtc-direct | - | - | ✅ | 5s | 449.416 | 4.479 |
| go-v0.45 x rust-v0.54 (tcp, noise, yamux) | go-v0.45 | rust-v0.54 | tcp | noise | yamux | ✅ | 4s | 94.532 | 45.628 |
| go-v0.45 x rust-v0.54 (tcp, tls, yamux) | go-v0.45 | rust-v0.54 | tcp | tls | yamux | ✅ | 6s | 90.23 | 42.142 |
| go-v0.45 x rust-v0.54 (ws, tls, yamux) | go-v0.45 | rust-v0.54 | ws | tls | yamux | ✅ | 5s | 178.571 | 45.135 |
| go-v0.45 x rust-v0.54 (ws, noise, yamux) | go-v0.45 | rust-v0.54 | ws | noise | yamux | ✅ | 5s | 179.908 | 41.895 |
| go-v0.45 x rust-v0.54 (quic-v1) | go-v0.45 | rust-v0.54 | quic-v1 | - | - | ✅ | 4s | 14.034 | 0.365 |
| go-v0.45 x rust-v0.54 (webrtc-direct) | go-v0.45 | rust-v0.54 | webrtc-direct | - | - | ✅ | 5s | 422.496 | 2.798 |
| go-v0.45 x rust-v0.55 (tcp, tls, yamux) | go-v0.45 | rust-v0.55 | tcp | tls | yamux | ✅ | 5s | 12.613 | 1.42 |
| go-v0.45 x rust-v0.55 (tcp, noise, yamux) | go-v0.45 | rust-v0.55 | tcp | noise | yamux | ✅ | 5s | 40.894 | 0.535 |
| go-v0.45 x rust-v0.55 (ws, tls, yamux) | go-v0.45 | rust-v0.55 | ws | tls | yamux | ✅ | 5s | 8.512 | 0.447 |
| go-v0.45 x rust-v0.55 (ws, noise, yamux) | go-v0.45 | rust-v0.55 | ws | noise | yamux | ✅ | 5s | 13.777 | 0.847 |
| go-v0.45 x rust-v0.55 (quic-v1) | go-v0.45 | rust-v0.55 | quic-v1 | - | - | ✅ | 5s | 10.289 | 0.498 |
| go-v0.45 x rust-v0.55 (webrtc-direct) | go-v0.45 | rust-v0.55 | webrtc-direct | - | - | ✅ | 4s | 416.443 | 0.666 |
| go-v0.45 x rust-v0.56 (tcp, tls, yamux) | go-v0.45 | rust-v0.56 | tcp | tls | yamux | ✅ | 5s | 14.466 | 1.516 |
| go-v0.45 x rust-v0.56 (tcp, noise, yamux) | go-v0.45 | rust-v0.56 | tcp | noise | yamux | ✅ | 4s | 14.04 | 0.706 |
| go-v0.45 x rust-v0.56 (ws, tls, yamux) | go-v0.45 | rust-v0.56 | ws | tls | yamux | ✅ | 5s | 10.121 | 1.228 |
| go-v0.45 x rust-v0.56 (quic-v1) | go-v0.45 | rust-v0.56 | quic-v1 | - | - | ✅ | 5s | 9.046 | 0.521 |
| go-v0.45 x rust-v0.56 (ws, noise, yamux) | go-v0.45 | rust-v0.56 | ws | noise | yamux | ✅ | 5s | 65.378 | 0.838 |
| go-v0.45 x go-v0.38 (tcp, tls, yamux) | go-v0.45 | go-v0.38 | tcp | tls | yamux | ✅ | 5s | 5.829 | 0.174 |
| go-v0.45 x go-v0.38 (tcp, noise, yamux) | go-v0.45 | go-v0.38 | tcp | noise | yamux | ✅ | 4s | 8.592 | 0.222 |
| go-v0.45 x go-v0.38 (ws, tls, yamux) | go-v0.45 | go-v0.38 | ws | tls | yamux | ✅ | 4s | 7.381 | 1.148 |
| go-v0.45 x go-v0.38 (ws, noise, yamux) | go-v0.45 | go-v0.38 | ws | noise | yamux | ✅ | 4s | 4.308 | 0.214 |
| go-v0.45 x go-v0.38 (wss, noise, yamux) | go-v0.45 | go-v0.38 | wss | noise | yamux | ✅ | 4s | 16.854 | 0.88 |
| go-v0.45 x go-v0.38 (quic-v1) | go-v0.45 | go-v0.38 | quic-v1 | - | - | ✅ | 4s | 14.767 | 0.369 |
| go-v0.45 x rust-v0.56 (webrtc-direct) | go-v0.45 | rust-v0.56 | webrtc-direct | - | - | ❌ | 9s | - | - |
| go-v0.45 x go-v0.38 (wss, tls, yamux) | go-v0.45 | go-v0.38 | wss | tls | yamux | ✅ | 7s | 7.944 | 0.212 |
| go-v0.45 x go-v0.38 (webtransport) | go-v0.45 | go-v0.38 | webtransport | - | - | ✅ | 4s | 16.675 | 0.632 |
| go-v0.45 x go-v0.38 (webrtc-direct) | go-v0.45 | go-v0.38 | webrtc-direct | - | - | ✅ | 5s | 225.432 | 3.048 |
| go-v0.45 x go-v0.39 (tcp, tls, yamux) | go-v0.45 | go-v0.39 | tcp | tls | yamux | ✅ | 4s | 10.486 | 0.539 |
| go-v0.45 x go-v0.39 (tcp, noise, yamux) | go-v0.45 | go-v0.39 | tcp | noise | yamux | ✅ | 5s | 11.374 | 0.503 |
| go-v0.45 x go-v0.39 (ws, tls, yamux) | go-v0.45 | go-v0.39 | ws | tls | yamux | ✅ | 4s | 15.828 | 2.502 |
| go-v0.45 x go-v0.39 (ws, noise, yamux) | go-v0.45 | go-v0.39 | ws | noise | yamux | ✅ | 5s | 19.337 | 0.995 |
| go-v0.45 x go-v0.39 (wss, tls, yamux) | go-v0.45 | go-v0.39 | wss | tls | yamux | ✅ | 6s | 21.681 | 1.632 |
| go-v0.45 x go-v0.39 (wss, noise, yamux) | go-v0.45 | go-v0.39 | wss | noise | yamux | ✅ | 5s | 20.547 | 0.415 |
| go-v0.45 x go-v0.39 (webtransport) | go-v0.45 | go-v0.39 | webtransport | - | - | ✅ | 5s | 22.352 | 0.845 |
| go-v0.45 x go-v0.39 (quic-v1) | go-v0.45 | go-v0.39 | quic-v1 | - | - | ✅ | 6s | 14.597 | 0.491 |
| go-v0.45 x go-v0.39 (webrtc-direct) | go-v0.45 | go-v0.39 | webrtc-direct | - | - | ✅ | 5s | 14.296 | 0.377 |
| go-v0.45 x go-v0.40 (tcp, tls, yamux) | go-v0.45 | go-v0.40 | tcp | tls | yamux | ✅ | 5s | 5.529 | 0.45 |
| go-v0.45 x go-v0.40 (tcp, noise, yamux) | go-v0.45 | go-v0.40 | tcp | noise | yamux | ✅ | 5s | 8.908 | 0.41 |
| go-v0.45 x go-v0.40 (ws, tls, yamux) | go-v0.45 | go-v0.40 | ws | tls | yamux | ✅ | 5s | 7.617 | 0.373 |
| go-v0.45 x go-v0.40 (ws, noise, yamux) | go-v0.45 | go-v0.40 | ws | noise | yamux | ✅ | 4s | 8.143 | 0.942 |
| go-v0.45 x go-v0.40 (wss, tls, yamux) | go-v0.45 | go-v0.40 | wss | tls | yamux | ✅ | 4s | 25.559 | 1.174 |
| go-v0.45 x go-v0.40 (wss, noise, yamux) | go-v0.45 | go-v0.40 | wss | noise | yamux | ✅ | 5s | 18.979 | 0.568 |
| go-v0.45 x go-v0.40 (quic-v1) | go-v0.45 | go-v0.40 | quic-v1 | - | - | ✅ | 5s | 15.195 | 1.366 |
| go-v0.45 x go-v0.40 (webtransport) | go-v0.45 | go-v0.40 | webtransport | - | - | ✅ | 5s | 11.038 | 0.348 |
| go-v0.45 x go-v0.40 (webrtc-direct) | go-v0.45 | go-v0.40 | webrtc-direct | - | - | ✅ | 5s | 209.858 | 0.28 |
| go-v0.45 x go-v0.41 (tcp, tls, yamux) | go-v0.45 | go-v0.41 | tcp | tls | yamux | ✅ | 6s | 52.86 | 0.513 |
| go-v0.45 x go-v0.41 (tcp, noise, yamux) | go-v0.45 | go-v0.41 | tcp | noise | yamux | ✅ | 5s | 10.103 | 2.57 |
| go-v0.45 x go-v0.41 (ws, tls, yamux) | go-v0.45 | go-v0.41 | ws | tls | yamux | ✅ | 4s | 11.995 | 0.463 |
| go-v0.45 x go-v0.41 (ws, noise, yamux) | go-v0.45 | go-v0.41 | ws | noise | yamux | ✅ | 5s | 45.844 | 0.396 |
| go-v0.45 x go-v0.41 (wss, tls, yamux) | go-v0.45 | go-v0.41 | wss | tls | yamux | ✅ | 4s | 24.235 | 0.662 |
| go-v0.45 x go-v0.41 (quic-v1) | go-v0.45 | go-v0.41 | quic-v1 | - | - | ✅ | 5s | 12.807 | 0.78 |
| go-v0.45 x go-v0.41 (wss, noise, yamux) | go-v0.45 | go-v0.41 | wss | noise | yamux | ✅ | 6s | 14.714 | 0.631 |
| go-v0.45 x go-v0.41 (webtransport) | go-v0.45 | go-v0.41 | webtransport | - | - | ✅ | 4s | 16.414 | 3.534 |
| go-v0.45 x go-v0.41 (webrtc-direct) | go-v0.45 | go-v0.41 | webrtc-direct | - | - | ✅ | 5s | 215.556 | 1 |
| go-v0.45 x go-v0.42 (tcp, tls, yamux) | go-v0.45 | go-v0.42 | tcp | tls | yamux | ✅ | 5s | 7.293 | 0.269 |
| go-v0.45 x go-v0.42 (tcp, noise, yamux) | go-v0.45 | go-v0.42 | tcp | noise | yamux | ✅ | 5s | 9.087 | 1.678 |
| go-v0.45 x go-v0.42 (ws, tls, yamux) | go-v0.45 | go-v0.42 | ws | tls | yamux | ✅ | 5s | 10.803 | 0.471 |
| go-v0.45 x go-v0.42 (ws, noise, yamux) | go-v0.45 | go-v0.42 | ws | noise | yamux | ✅ | 5s | 29.068 | 2.209 |
| go-v0.45 x go-v0.42 (wss, tls, yamux) | go-v0.45 | go-v0.42 | wss | tls | yamux | ✅ | 5s | 26.636 | 0.632 |
| go-v0.45 x go-v0.42 (quic-v1) | go-v0.45 | go-v0.42 | quic-v1 | - | - | ✅ | 4s | 9.207 | 0.548 |
| go-v0.45 x go-v0.42 (wss, noise, yamux) | go-v0.45 | go-v0.42 | wss | noise | yamux | ✅ | 6s | 7.882 | 0.165 |
| go-v0.45 x go-v0.42 (webtransport) | go-v0.45 | go-v0.42 | webtransport | - | - | ✅ | 4s | 10.059 | 0.383 |
| go-v0.45 x go-v0.43 (tcp, tls, yamux) | go-v0.45 | go-v0.43 | tcp | tls | yamux | ✅ | 4s | 7.59 | 0.59 |
| go-v0.45 x go-v0.42 (webrtc-direct) | go-v0.45 | go-v0.42 | webrtc-direct | - | - | ✅ | 6s | 218.134 | 0.841 |
| go-v0.45 x go-v0.43 (tcp, noise, yamux) | go-v0.45 | go-v0.43 | tcp | noise | yamux | ✅ | 5s | 6.163 | 0.46 |
| go-v0.45 x go-v0.43 (ws, tls, yamux) | go-v0.45 | go-v0.43 | ws | tls | yamux | ✅ | 5s | 12.899 | 3.489 |
| go-v0.45 x go-v0.43 (ws, noise, yamux) | go-v0.45 | go-v0.43 | ws | noise | yamux | ✅ | 5s | 17.167 | 0.647 |
| go-v0.45 x go-v0.43 (wss, tls, yamux) | go-v0.45 | go-v0.43 | wss | tls | yamux | ✅ | 4s | 14.116 | 0.941 |
| go-v0.45 x go-v0.43 (wss, noise, yamux) | go-v0.45 | go-v0.43 | wss | noise | yamux | ✅ | 5s | 7.365 | 0.162 |
| go-v0.45 x go-v0.43 (quic-v1) | go-v0.45 | go-v0.43 | quic-v1 | - | - | ✅ | 4s | 14.622 | 0.431 |
| go-v0.45 x go-v0.43 (webtransport) | go-v0.45 | go-v0.43 | webtransport | - | - | ✅ | 4s | 17.8 | 0.6 |
| go-v0.45 x go-v0.43 (webrtc-direct) | go-v0.45 | go-v0.43 | webrtc-direct | - | - | ✅ | 5s | 216.233 | 0.665 |
| go-v0.45 x go-v0.44 (tcp, tls, yamux) | go-v0.45 | go-v0.44 | tcp | tls | yamux | ✅ | 5s | 6.661 | 0.265 |
| go-v0.45 x go-v0.44 (tcp, noise, yamux) | go-v0.45 | go-v0.44 | tcp | noise | yamux | ✅ | 4s | 9.798 | 1.899 |
| go-v0.45 x go-v0.44 (ws, tls, yamux) | go-v0.45 | go-v0.44 | ws | tls | yamux | ✅ | 4s | 7.049 | 0.873 |
| go-v0.45 x go-v0.44 (ws, noise, yamux) | go-v0.45 | go-v0.44 | ws | noise | yamux | ✅ | 5s | 20.531 | 0.532 |
| go-v0.45 x go-v0.44 (wss, noise, yamux) | go-v0.45 | go-v0.44 | wss | noise | yamux | ✅ | 5s | 24.066 | 1.18 |
| go-v0.45 x go-v0.44 (quic-v1) | go-v0.45 | go-v0.44 | quic-v1 | - | - | ✅ | 4s | 13.412 | 1.221 |
| go-v0.45 x go-v0.44 (wss, tls, yamux) | go-v0.45 | go-v0.44 | wss | tls | yamux | ✅ | 6s | 18.231 | 2.818 |
| go-v0.45 x go-v0.44 (webtransport) | go-v0.45 | go-v0.44 | webtransport | - | - | ✅ | 4s | 10.892 | 0.414 |
| go-v0.45 x go-v0.44 (webrtc-direct) | go-v0.45 | go-v0.44 | webrtc-direct | - | - | ✅ | 4s | 26.42 | 0.865 |
| go-v0.45 x go-v0.45 (tcp, tls, yamux) | go-v0.45 | go-v0.45 | tcp | tls | yamux | ✅ | 5s | 12.041 | 1.065 |
| go-v0.45 x go-v0.45 (tcp, noise, yamux) | go-v0.45 | go-v0.45 | tcp | noise | yamux | ✅ | 5s | 8.481 | 0.524 |
| go-v0.45 x go-v0.45 (ws, tls, yamux) | go-v0.45 | go-v0.45 | ws | tls | yamux | ✅ | 4s | 12.233 | 1.186 |
| go-v0.45 x go-v0.45 (ws, noise, yamux) | go-v0.45 | go-v0.45 | ws | noise | yamux | ✅ | 5s | 7.667 | 0.612 |
| go-v0.45 x go-v0.45 (quic-v1) | go-v0.45 | go-v0.45 | quic-v1 | - | - | ✅ | 4s | 12.058 | 0.455 |
| go-v0.45 x go-v0.45 (wss, tls, yamux) | go-v0.45 | go-v0.45 | wss | tls | yamux | ✅ | 6s | 10.993 | 0.39 |
| go-v0.45 x go-v0.45 (wss, noise, yamux) | go-v0.45 | go-v0.45 | wss | noise | yamux | ✅ | 5s | 29.625 | 0.542 |
| go-v0.45 x go-v0.45 (webtransport) | go-v0.45 | go-v0.45 | webtransport | - | - | ✅ | 5s | 10.486 | 0.295 |
| go-v0.45 x go-v0.45 (webrtc-direct) | go-v0.45 | go-v0.45 | webrtc-direct | - | - | ✅ | 4s | 218.37 | 2.48 |
| go-v0.45 x python-v0.4 (tcp, noise, yamux) | go-v0.45 | python-v0.4 | tcp | noise | yamux | ✅ | 5s | 45.666 | 5.746 |
| go-v0.45 x python-v0.4 (ws, noise, yamux) | go-v0.45 | python-v0.4 | ws | noise | yamux | ✅ | 5s | 28.438 | 5.8 |
| go-v0.45 x python-v0.4 (wss, noise, yamux) | go-v0.45 | python-v0.4 | wss | noise | yamux | ✅ | 7s | 38.884 | 5.501 |
| go-v0.45 x python-v0.4 (quic-v1) | go-v0.45 | python-v0.4 | quic-v1 | - | - | ✅ | 6s | 93.474 | 9.739 |
| go-v0.45 x nim-v1.14 (tcp, noise, yamux) | go-v0.45 | nim-v1.14 | tcp | noise | yamux | ✅ | 5s | 203.293 | 43.756 |
| go-v0.45 x nim-v1.14 (ws, noise, yamux) | go-v0.45 | nim-v1.14 | ws | noise | yamux | ✅ | 6s | 260.294 | 47.571 |
| go-v0.45 x js-v1.x (tcp, noise, yamux) | go-v0.45 | js-v1.x | tcp | noise | yamux | ✅ | 19s | 180.081 | 18.804 |
| go-v0.45 x js-v1.x (ws, noise, yamux) | go-v0.45 | js-v1.x | ws | noise | yamux | ✅ | 20s | 232.31 | 19.189 |
| go-v0.45 x js-v2.x (tcp, noise, yamux) | go-v0.45 | js-v2.x | tcp | noise | yamux | ✅ | 21s | 196.991 | 19.994 |
| go-v0.45 x js-v2.x (ws, noise, yamux) | go-v0.45 | js-v2.x | ws | noise | yamux | ✅ | 22s | 208.634 | 37.348 |
| go-v0.45 x js-v3.x (tcp, noise, yamux) | go-v0.45 | js-v3.x | tcp | noise | yamux | ✅ | 22s | 155.458 | 23.626 |
| go-v0.45 x jvm-v1.2 (tcp, noise, yamux) | go-v0.45 | jvm-v1.2 | tcp | noise | yamux | ✅ | 11s | 1169.39 | 10.353 |
| go-v0.45 x jvm-v1.2 (tcp, tls, yamux) | go-v0.45 | jvm-v1.2 | tcp | tls | yamux | ✅ | 13s | 3249.32 | 9.073 |
| go-v0.45 x js-v3.x (ws, noise, yamux) | go-v0.45 | js-v3.x | ws | noise | yamux | ✅ | 22s | 85.45 | 16.426 |
| go-v0.45 x c-v0.0.1 (tcp, noise, yamux) | go-v0.45 | c-v0.0.1 | tcp | noise | yamux | ✅ | 5s | 128.587 | 51.385 |
| go-v0.45 x c-v0.0.1 (quic-v1) | go-v0.45 | c-v0.0.1 | quic-v1 | - | - | ✅ | 5s | 78.872 | 37.734 |
| go-v0.45 x jvm-v1.2 (ws, noise, yamux) | go-v0.45 | jvm-v1.2 | ws | noise | yamux | ✅ | 10s | 1553.019 | 23.933 |
| go-v0.45 x dotnet-v1.0 (tcp, noise, yamux) | go-v0.45 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 8s | 489.44 | 49.588 |
| go-v0.45 x jvm-v1.2 (ws, tls, yamux) | go-v0.45 | jvm-v1.2 | ws | tls | yamux | ✅ | 12s | 3868.216 | 22.404 |
| go-v0.45 x zig-v0.0.1 (quic-v1) | go-v0.45 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 6s | - | - |
| go-v0.45 x eth-p2p-z-v0.0.1 (quic-v1) | go-v0.45 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 7s | 7.625 | 0.185 |
| go-v0.45 x jvm-v1.2 (quic-v1) | go-v0.45 | jvm-v1.2 | quic-v1 | - | - | ✅ | 11s | 431.14 | 5.074 |
| python-v0.4 x rust-v0.53 (tcp, noise, mplex) | python-v0.4 | rust-v0.53 | tcp | noise | mplex | ✅ | 5s | - | - |
| python-v0.4 x rust-v0.53 (tcp, noise, yamux) | python-v0.4 | rust-v0.53 | tcp | noise | yamux | ✅ | 5s | - | - |
| python-v0.4 x rust-v0.53 (quic-v1) | python-v0.4 | rust-v0.53 | quic-v1 | - | - | ✅ | 5s | - | - |
| python-v0.4 x rust-v0.54 (tcp, noise, yamux) | python-v0.4 | rust-v0.54 | tcp | noise | yamux | ✅ | 5s | - | - |
| python-v0.4 x rust-v0.54 (tcp, noise, mplex) | python-v0.4 | rust-v0.54 | tcp | noise | mplex | ✅ | 6s | - | - |
| python-v0.4 x rust-v0.54 (quic-v1) | python-v0.4 | rust-v0.54 | quic-v1 | - | - | ✅ | 5s | - | - |
| python-v0.4 x rust-v0.53 (ws, noise, mplex) | python-v0.4 | rust-v0.53 | ws | noise | mplex | ✅ | 10s | - | - |
| python-v0.4 x rust-v0.55 (tcp, noise, mplex) | python-v0.4 | rust-v0.55 | tcp | noise | mplex | ✅ | 4s | - | - |
| python-v0.4 x rust-v0.55 (tcp, noise, yamux) | python-v0.4 | rust-v0.55 | tcp | noise | yamux | ✅ | 4s | - | - |
| python-v0.4 x rust-v0.53 (ws, noise, yamux) | python-v0.4 | rust-v0.53 | ws | noise | yamux | ✅ | 12s | - | - |
| python-v0.4 x rust-v0.54 (ws, noise, mplex) | python-v0.4 | rust-v0.54 | ws | noise | mplex | ✅ | 11s | - | - |
| python-v0.4 x rust-v0.54 (ws, noise, yamux) | python-v0.4 | rust-v0.54 | ws | noise | yamux | ✅ | 10s | - | - |
| python-v0.4 x rust-v0.55 (quic-v1) | python-v0.4 | rust-v0.55 | quic-v1 | - | - | ✅ | 4s | - | - |
| python-v0.4 x rust-v0.56 (tcp, noise, mplex) | python-v0.4 | rust-v0.56 | tcp | noise | mplex | ✅ | 5s | - | - |
| python-v0.4 x rust-v0.56 (tcp, noise, yamux) | python-v0.4 | rust-v0.56 | tcp | noise | yamux | ✅ | 4s | - | - |
| python-v0.4 x rust-v0.56 (quic-v1) | python-v0.4 | rust-v0.56 | quic-v1 | - | - | ✅ | 4s | - | - |
| python-v0.4 x go-v0.38 (tcp, noise, yamux) | python-v0.4 | go-v0.38 | tcp | noise | yamux | ✅ | 3s | - | - |
| python-v0.4 x rust-v0.55 (ws, noise, mplex) | python-v0.4 | rust-v0.55 | ws | noise | mplex | ✅ | 13s | - | - |
| python-v0.4 x go-v0.38 (quic-v1) | python-v0.4 | go-v0.38 | quic-v1 | - | - | ✅ | 3s | - | - |
| python-v0.4 x go-v0.39 (tcp, noise, yamux) | python-v0.4 | go-v0.39 | tcp | noise | yamux | ✅ | 4s | - | - |
| python-v0.4 x rust-v0.55 (ws, noise, yamux) | python-v0.4 | rust-v0.55 | ws | noise | yamux | ✅ | 15s | - | - |
| python-v0.4 x rust-v0.56 (ws, noise, mplex) | python-v0.4 | rust-v0.56 | ws | noise | mplex | ✅ | 15s | - | - |
| python-v0.4 x go-v0.39 (quic-v1) | python-v0.4 | go-v0.39 | quic-v1 | - | - | ✅ | 4s | - | - |
| python-v0.4 x rust-v0.56 (ws, noise, yamux) | python-v0.4 | rust-v0.56 | ws | noise | yamux | ✅ | 14s | - | - |
| python-v0.4 x go-v0.40 (tcp, noise, yamux) | python-v0.4 | go-v0.40 | tcp | noise | yamux | ✅ | 4s | - | - |
| python-v0.4 x go-v0.40 (quic-v1) | python-v0.4 | go-v0.40 | quic-v1 | - | - | ✅ | 3s | - | - |
| python-v0.4 x go-v0.41 (tcp, noise, yamux) | python-v0.4 | go-v0.41 | tcp | noise | yamux | ✅ | 3s | - | - |
| python-v0.4 x go-v0.38 (ws, noise, yamux) | python-v0.4 | go-v0.38 | ws | noise | yamux | ✅ | 44s | - | - |
| python-v0.4 x go-v0.38 (wss, noise, yamux) | python-v0.4 | go-v0.38 | wss | noise | yamux | ✅ | 43s | - | - |
| python-v0.4 x go-v0.41 (quic-v1) | python-v0.4 | go-v0.41 | quic-v1 | - | - | ✅ | 3s | - | - |
| python-v0.4 x go-v0.42 (tcp, noise, yamux) | python-v0.4 | go-v0.42 | tcp | noise | yamux | ✅ | 3s | - | - |
| python-v0.4 x go-v0.39 (ws, noise, yamux) | python-v0.4 | go-v0.39 | ws | noise | yamux | ✅ | 43s | - | - |
| python-v0.4 x go-v0.39 (wss, noise, yamux) | python-v0.4 | go-v0.39 | wss | noise | yamux | ✅ | 44s | - | - |
| python-v0.4 x go-v0.42 (quic-v1) | python-v0.4 | go-v0.42 | quic-v1 | - | - | ✅ | 4s | - | - |
| python-v0.4 x go-v0.43 (tcp, noise, yamux) | python-v0.4 | go-v0.43 | tcp | noise | yamux | ✅ | 3s | - | - |
| python-v0.4 x go-v0.40 (ws, noise, yamux) | python-v0.4 | go-v0.40 | ws | noise | yamux | ✅ | 44s | - | - |
| python-v0.4 x go-v0.40 (wss, noise, yamux) | python-v0.4 | go-v0.40 | wss | noise | yamux | ✅ | 44s | - | - |
| python-v0.4 x go-v0.43 (quic-v1) | python-v0.4 | go-v0.43 | quic-v1 | - | - | ✅ | 3s | - | - |
| python-v0.4 x go-v0.44 (tcp, noise, yamux) | python-v0.4 | go-v0.44 | tcp | noise | yamux | ✅ | 2s | - | - |
| python-v0.4 x go-v0.41 (ws, noise, yamux) | python-v0.4 | go-v0.41 | ws | noise | yamux | ✅ | 43s | - | - |
| python-v0.4 x go-v0.41 (wss, noise, yamux) | python-v0.4 | go-v0.41 | wss | noise | yamux | ✅ | 43s | - | - |
| python-v0.4 x go-v0.44 (quic-v1) | python-v0.4 | go-v0.44 | quic-v1 | - | - | ✅ | 3s | - | - |
| python-v0.4 x go-v0.45 (tcp, noise, yamux) | python-v0.4 | go-v0.45 | tcp | noise | yamux | ✅ | 3s | - | - |
| python-v0.4 x go-v0.42 (ws, noise, yamux) | python-v0.4 | go-v0.42 | ws | noise | yamux | ✅ | 44s | - | - |
| python-v0.4 x go-v0.42 (wss, noise, yamux) | python-v0.4 | go-v0.42 | wss | noise | yamux | ✅ | 43s | - | - |
| python-v0.4 x go-v0.45 (quic-v1) | python-v0.4 | go-v0.45 | quic-v1 | - | - | ✅ | 3s | - | - |
| python-v0.4 x python-v0.4 (tcp, noise, mplex) | python-v0.4 | python-v0.4 | tcp | noise | mplex | ✅ | 3s | - | - |
| python-v0.4 x go-v0.43 (ws, noise, yamux) | python-v0.4 | go-v0.43 | ws | noise | yamux | ✅ | 43s | - | - |
| python-v0.4 x go-v0.43 (wss, noise, yamux) | python-v0.4 | go-v0.43 | wss | noise | yamux | ✅ | 44s | - | - |
| python-v0.4 x python-v0.4 (tcp, noise, yamux) | python-v0.4 | python-v0.4 | tcp | noise | yamux | ✅ | 4s | - | - |
| python-v0.4 x python-v0.4 (ws, noise, mplex) | python-v0.4 | python-v0.4 | ws | noise | mplex | ✅ | 3s | - | - |
| python-v0.4 x python-v0.4 (ws, noise, yamux) | python-v0.4 | python-v0.4 | ws | noise | yamux | ✅ | 4s | - | - |
| python-v0.4 x python-v0.4 (wss, noise, mplex) | python-v0.4 | python-v0.4 | wss | noise | mplex | ✅ | 4s | - | - |
| python-v0.4 x go-v0.44 (ws, noise, yamux) | python-v0.4 | go-v0.44 | ws | noise | yamux | ✅ | 44s | - | - |
| python-v0.4 x go-v0.44 (wss, noise, yamux) | python-v0.4 | go-v0.44 | wss | noise | yamux | ✅ | 43s | - | - |
| python-v0.4 x python-v0.4 (wss, noise, yamux) | python-v0.4 | python-v0.4 | wss | noise | yamux | ✅ | 4s | - | - |
| python-v0.4 x python-v0.4 (quic-v1) | python-v0.4 | python-v0.4 | quic-v1 | - | - | ✅ | 4s | - | - |
| python-v0.4 x go-v0.45 (ws, noise, yamux) | python-v0.4 | go-v0.45 | ws | noise | yamux | ✅ | 43s | - | - |
| python-v0.4 x go-v0.45 (wss, noise, yamux) | python-v0.4 | go-v0.45 | wss | noise | yamux | ✅ | 44s | - | - |
| python-v0.4 x js-v1.x (tcp, noise, mplex) | python-v0.4 | js-v1.x | tcp | noise | mplex | ✅ | 16s | - | - |
| python-v0.4 x js-v1.x (tcp, noise, yamux) | python-v0.4 | js-v1.x | tcp | noise | yamux | ✅ | 17s | - | - |
| python-v0.4 x js-v2.x (tcp, noise, mplex) | python-v0.4 | js-v2.x | tcp | noise | mplex | ✅ | 18s | - | - |
| python-v0.4 x js-v2.x (tcp, noise, yamux) | python-v0.4 | js-v2.x | tcp | noise | yamux | ✅ | 18s | - | - |
| python-v0.4 x js-v3.x (tcp, noise, mplex) | python-v0.4 | js-v3.x | tcp | noise | mplex | ✅ | 12s | - | - |
| python-v0.4 x js-v1.x (ws, noise, mplex) | python-v0.4 | js-v1.x | ws | noise | mplex | ✅ | 30s | - | - |
| python-v0.4 x js-v3.x (tcp, noise, yamux) | python-v0.4 | js-v3.x | tcp | noise | yamux | ✅ | 13s | - | - |
| python-v0.4 x js-v1.x (ws, noise, yamux) | python-v0.4 | js-v1.x | ws | noise | yamux | ✅ | 29s | - | - |
| python-v0.4 x nim-v1.14 (tcp, noise, yamux) | python-v0.4 | nim-v1.14 | tcp | noise | yamux | ✅ | 4s | - | - |
| python-v0.4 x nim-v1.14 (tcp, noise, mplex) | python-v0.4 | nim-v1.14 | tcp | noise | mplex | ✅ | 4s | - | - |
| python-v0.4 x jvm-v1.2 (tcp, noise, mplex) | python-v0.4 | jvm-v1.2 | tcp | noise | mplex | ✅ | 5s | - | - |
| python-v0.4 x jvm-v1.2 (tcp, noise, yamux) | python-v0.4 | jvm-v1.2 | tcp | noise | yamux | ✅ | 5s | - | - |
| python-v0.4 x js-v2.x (ws, noise, mplex) | python-v0.4 | js-v2.x | ws | noise | mplex | ✅ | 196s | - | - |
| python-v0.4 x js-v2.x (ws, noise, yamux) | python-v0.4 | js-v2.x | ws | noise | yamux | ✅ | 195s | - | - |
| python-v0.4 x jvm-v1.2 (quic-v1) | python-v0.4 | jvm-v1.2 | quic-v1 | - | - | ✅ | 4s | - | - |
| python-v0.4 x c-v0.0.1 (tcp, noise, yamux) | python-v0.4 | c-v0.0.1 | tcp | noise | yamux | ✅ | 3s | - | - |
| python-v0.4 x js-v3.x (ws, noise, mplex) | python-v0.4 | js-v3.x | ws | noise | mplex | ✅ | 191s | - | - |
| python-v0.4 x js-v3.x (ws, noise, yamux) | python-v0.4 | js-v3.x | ws | noise | yamux | ✅ | 190s | - | - |
| python-v0.4 x c-v0.0.1 (quic-v1) | python-v0.4 | c-v0.0.1 | quic-v1 | - | - | ✅ | 4s | - | - |
| python-v0.4 x nim-v1.14 (ws, noise, mplex) | python-v0.4 | nim-v1.14 | ws | noise | mplex | ✅ | 183s | - | - |
| python-v0.4 x nim-v1.14 (ws, noise, yamux) | python-v0.4 | nim-v1.14 | ws | noise | yamux | ✅ | 183s | - | - |
| python-v0.4 x dotnet-v1.0 (tcp, noise, yamux) | python-v0.4 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 4s | - | - |
| python-v0.4 x eth-p2p-z-v0.0.1 (quic-v1) | python-v0.4 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 4s | - | - |
| js-v1.x x rust-v0.53 (tcp, noise, mplex) | js-v1.x | rust-v0.53 | tcp | noise | mplex | ✅ | 8s | 111 | 22 |
| js-v1.x x rust-v0.53 (tcp, noise, yamux) | js-v1.x | rust-v0.53 | tcp | noise | yamux | ✅ | 9s | 95 | 18 |
| python-v0.4 x jvm-v1.2 (ws, noise, mplex) | python-v0.4 | jvm-v1.2 | ws | noise | mplex | ✅ | 184s | - | - |
| python-v0.4 x jvm-v1.2 (ws, noise, yamux) | python-v0.4 | jvm-v1.2 | ws | noise | yamux | ✅ | 184s | - | - |
| js-v1.x x rust-v0.53 (ws, noise, mplex) | js-v1.x | rust-v0.53 | ws | noise | mplex | ✅ | 8s | 243 | 66 |
| js-v1.x x rust-v0.53 (ws, noise, yamux) | js-v1.x | rust-v0.53 | ws | noise | yamux | ✅ | 9s | 202 | 23 |
| js-v1.x x rust-v0.54 (tcp, noise, mplex) | js-v1.x | rust-v0.54 | tcp | noise | mplex | ✅ | 10s | 132 | 28 |
| js-v1.x x rust-v0.54 (tcp, noise, yamux) | js-v1.x | rust-v0.54 | tcp | noise | yamux | ✅ | 11s | 120 | 28 |
| js-v1.x x rust-v0.54 (ws, noise, mplex) | js-v1.x | rust-v0.54 | ws | noise | mplex | ✅ | 12s | 214 | 26 |
| js-v1.x x rust-v0.54 (ws, noise, yamux) | js-v1.x | rust-v0.54 | ws | noise | yamux | ✅ | 11s | 225 | 33 |
| js-v1.x x rust-v0.55 (tcp, noise, mplex) | js-v1.x | rust-v0.55 | tcp | noise | mplex | ✅ | 12s | 75 | 28 |
| python-v0.4 x c-v0.0.1 (tcp, noise, mplex) | python-v0.4 | c-v0.0.1 | tcp | noise | mplex | ✅ | 34s | - | - |
| js-v1.x x rust-v0.55 (tcp, noise, yamux) | js-v1.x | rust-v0.55 | tcp | noise | yamux | ✅ | 11s | 49 | 20 |
| js-v1.x x rust-v0.55 (ws, noise, mplex) | js-v1.x | rust-v0.55 | ws | noise | mplex | ✅ | 13s | 155 | 57 |
| python-v0.4 x zig-v0.0.1 (quic-v1) | python-v0.4 | zig-v0.0.1 | quic-v1 | - | - | ❌ | 35s | - | - |
| js-v1.x x rust-v0.55 (ws, noise, yamux) | js-v1.x | rust-v0.55 | ws | noise | yamux | ✅ | 14s | 112 | 39 |
| js-v1.x x rust-v0.56 (tcp, noise, yamux) | js-v1.x | rust-v0.56 | tcp | noise | yamux | ✅ | 15s | 100 | 33 |
| js-v1.x x rust-v0.56 (tcp, noise, mplex) | js-v1.x | rust-v0.56 | tcp | noise | mplex | ✅ | 15s | 88 | 27 |
| js-v1.x x rust-v0.56 (ws, noise, mplex) | js-v1.x | rust-v0.56 | ws | noise | mplex | ✅ | 15s | 71 | 17 |
| js-v1.x x rust-v0.56 (ws, noise, yamux) | js-v1.x | rust-v0.56 | ws | noise | yamux | ✅ | 14s | 62 | 22 |
| js-v1.x x go-v0.38 (tcp, noise, yamux) | js-v1.x | go-v0.38 | tcp | noise | yamux | ✅ | 14s | 51 | 17 |
| js-v1.x x go-v0.38 (wss, noise, yamux) | js-v1.x | go-v0.38 | wss | noise | yamux | ✅ | 16s | 263 | 55 |
| js-v1.x x go-v0.38 (ws, noise, yamux) | js-v1.x | go-v0.38 | ws | noise | yamux | ✅ | 17s | 133 | 45 |
| js-v1.x x go-v0.39 (tcp, noise, yamux) | js-v1.x | go-v0.39 | tcp | noise | yamux | ✅ | 16s | 110 | 35 |
| js-v1.x x go-v0.39 (ws, noise, yamux) | js-v1.x | go-v0.39 | ws | noise | yamux | ✅ | 17s | 117 | 45 |
| js-v1.x x go-v0.40 (tcp, noise, yamux) | js-v1.x | go-v0.40 | tcp | noise | yamux | ✅ | 16s | 99 | 35 |
| js-v1.x x go-v0.39 (wss, noise, yamux) | js-v1.x | go-v0.39 | wss | noise | yamux | ✅ | 17s | 191 | 42 |
| js-v1.x x go-v0.40 (ws, noise, yamux) | js-v1.x | go-v0.40 | ws | noise | yamux | ✅ | 16s | 99 | 31 |
| js-v1.x x go-v0.40 (wss, noise, yamux) | js-v1.x | go-v0.40 | wss | noise | yamux | ✅ | 17s | 119 | 27 |
| js-v1.x x go-v0.41 (tcp, noise, yamux) | js-v1.x | go-v0.41 | tcp | noise | yamux | ✅ | 18s | 142 | 43 |
| js-v1.x x go-v0.41 (ws, noise, yamux) | js-v1.x | go-v0.41 | ws | noise | yamux | ✅ | 17s | 159 | 49 |
| js-v1.x x go-v0.41 (wss, noise, yamux) | js-v1.x | go-v0.41 | wss | noise | yamux | ✅ | 18s | 206 | 37 |
| js-v1.x x go-v0.42 (tcp, noise, yamux) | js-v1.x | go-v0.42 | tcp | noise | yamux | ✅ | 17s | 72 | 29 |
| js-v1.x x go-v0.42 (ws, noise, yamux) | js-v1.x | go-v0.42 | ws | noise | yamux | ✅ | 17s | 121 | 35 |
| js-v1.x x go-v0.42 (wss, noise, yamux) | js-v1.x | go-v0.42 | wss | noise | yamux | ✅ | 18s | 191 | 38 |
| js-v1.x x go-v0.43 (tcp, noise, yamux) | js-v1.x | go-v0.43 | tcp | noise | yamux | ✅ | 17s | 88 | 29 |
| js-v1.x x go-v0.43 (ws, noise, yamux) | js-v1.x | go-v0.43 | ws | noise | yamux | ✅ | 18s | 94 | 32 |
| js-v1.x x go-v0.43 (wss, noise, yamux) | js-v1.x | go-v0.43 | wss | noise | yamux | ✅ | 18s | 227 | 50 |
| js-v1.x x go-v0.44 (tcp, noise, yamux) | js-v1.x | go-v0.44 | tcp | noise | yamux | ✅ | 18s | 169 | 67 |
| js-v1.x x go-v0.44 (ws, noise, yamux) | js-v1.x | go-v0.44 | ws | noise | yamux | ✅ | 19s | 168 | 35 |
| js-v1.x x go-v0.44 (wss, noise, yamux) | js-v1.x | go-v0.44 | wss | noise | yamux | ✅ | 18s | 217 | 37 |
| js-v1.x x go-v0.45 (ws, noise, yamux) | js-v1.x | go-v0.45 | ws | noise | yamux | ✅ | 17s | 132 | 48 |
| js-v1.x x go-v0.45 (tcp, noise, yamux) | js-v1.x | go-v0.45 | tcp | noise | yamux | ✅ | 19s | 94 | 32 |
| js-v1.x x go-v0.45 (wss, noise, yamux) | js-v1.x | go-v0.45 | wss | noise | yamux | ✅ | 18s | 144 | 33 |
| js-v1.x x python-v0.4 (tcp, noise, mplex) | js-v1.x | python-v0.4 | tcp | noise | mplex | ✅ | 18s | 62 | 19 |
| js-v1.x x python-v0.4 (tcp, noise, yamux) | js-v1.x | python-v0.4 | tcp | noise | yamux | ✅ | 23s | 246 | 67 |
| js-v1.x x python-v0.4 (ws, noise, mplex) | js-v1.x | python-v0.4 | ws | noise | mplex | ✅ | 25s | 209 | 54 |
| js-v1.x x python-v0.4 (ws, noise, yamux) | js-v1.x | python-v0.4 | ws | noise | yamux | ✅ | 26s | 207 | 60 |
| js-v1.x x python-v0.4 (wss, noise, mplex) | js-v1.x | python-v0.4 | wss | noise | mplex | ✅ | 25s | 266 | 55 |
| js-v1.x x python-v0.4 (wss, noise, yamux) | js-v1.x | python-v0.4 | wss | noise | yamux | ✅ | 26s | 238 | 55 |
| js-v1.x x js-v1.x (tcp, noise, mplex) | js-v1.x | js-v1.x | tcp | noise | mplex | ✅ | 26s | 139 | 39 |
| js-v1.x x js-v1.x (tcp, noise, yamux) | js-v1.x | js-v1.x | tcp | noise | yamux | ✅ | 25s | 134 | 43 |
| js-v1.x x js-v1.x (ws, noise, mplex) | js-v1.x | js-v1.x | ws | noise | mplex | ✅ | 24s | 221 | 118 |
| js-v1.x x js-v1.x (ws, noise, yamux) | js-v1.x | js-v1.x | ws | noise | yamux | ✅ | 33s | 411 | 109 |
| js-v1.x x js-v2.x (tcp, noise, yamux) | js-v1.x | js-v2.x | tcp | noise | yamux | ✅ | 35s | 313 | 106 |
| js-v1.x x js-v2.x (tcp, noise, mplex) | js-v1.x | js-v2.x | tcp | noise | mplex | ✅ | 37s | 330 | 107 |
| js-v1.x x js-v2.x (ws, noise, mplex) | js-v1.x | js-v2.x | ws | noise | mplex | ✅ | 36s | 430 | 133 |
| js-v1.x x js-v2.x (ws, noise, yamux) | js-v1.x | js-v2.x | ws | noise | yamux | ✅ | 37s | 305 | 150 |
| js-v1.x x js-v3.x (tcp, noise, mplex) | js-v1.x | js-v3.x | tcp | noise | mplex | ✅ | 36s | 229 | 116 |
| js-v1.x x js-v3.x (ws, noise, mplex) | js-v1.x | js-v3.x | ws | noise | mplex | ✅ | 35s | 189 | 57 |
| js-v1.x x js-v3.x (tcp, noise, yamux) | js-v1.x | js-v3.x | tcp | noise | yamux | ✅ | 36s | 199 | 86 |
| js-v1.x x js-v3.x (ws, noise, yamux) | js-v1.x | js-v3.x | ws | noise | yamux | ✅ | 23s | 267 | 91 |
| js-v1.x x nim-v1.14 (tcp, noise, mplex) | js-v1.x | nim-v1.14 | tcp | noise | mplex | ✅ | 23s | 266 | 51 |
| js-v1.x x nim-v1.14 (ws, noise, mplex) | js-v1.x | nim-v1.14 | ws | noise | mplex | ✅ | 24s | 279 | 36 |
| js-v1.x x nim-v1.14 (tcp, noise, yamux) | js-v1.x | nim-v1.14 | tcp | noise | yamux | ✅ | 25s | 227 | 44 |
| js-v1.x x nim-v1.14 (ws, noise, yamux) | js-v1.x | nim-v1.14 | ws | noise | yamux | ✅ | 24s | 306 | 57 |
| js-v1.x x jvm-v1.2 (tcp, noise, mplex) | js-v1.x | jvm-v1.2 | tcp | noise | mplex | ✅ | 25s | 1022 | 68 |
| js-v1.x x jvm-v1.2 (tcp, noise, yamux) | js-v1.x | jvm-v1.2 | tcp | noise | yamux | ✅ | 25s | 1252 | 84 |
| js-v1.x x jvm-v1.2 (ws, noise, mplex) | js-v1.x | jvm-v1.2 | ws | noise | mplex | ❌ | 28s | - | - |
| js-v1.x x c-v0.0.1 (tcp, noise, mplex) | js-v1.x | c-v0.0.1 | tcp | noise | mplex | ✅ | 19s | 109 | 25 |
| js-v1.x x jvm-v1.2 (ws, noise, yamux) | js-v1.x | jvm-v1.2 | ws | noise | yamux | ❌ | 23s | - | - |
| js-v1.x x c-v0.0.1 (tcp, noise, yamux) | js-v1.x | c-v0.0.1 | tcp | noise | yamux | ✅ | 18s | 196 | 109 |
| js-v1.x x dotnet-v1.0 (tcp, noise, yamux) | js-v1.x | dotnet-v1.0 | tcp | noise | yamux | ✅ | 20s | 348 | 99 |
| js-v2.x x rust-v0.53 (tcp, noise, mplex) | js-v2.x | rust-v0.53 | tcp | noise | mplex | ✅ | 19s | 181 | 46 |
| js-v2.x x rust-v0.53 (tcp, noise, yamux) | js-v2.x | rust-v0.53 | tcp | noise | yamux | ✅ | 20s | 167 | 50 |
| js-v2.x x rust-v0.53 (ws, noise, mplex) | js-v2.x | rust-v0.53 | ws | noise | mplex | ✅ | 20s | 312 | 73 |
| js-v2.x x rust-v0.53 (ws, noise, yamux) | js-v2.x | rust-v0.53 | ws | noise | yamux | ✅ | 19s | 347 | 102 |
| js-v2.x x rust-v0.54 (tcp, noise, mplex) | js-v2.x | rust-v0.54 | tcp | noise | mplex | ✅ | 21s | 198 | 44 |
| js-v2.x x rust-v0.54 (tcp, noise, yamux) | js-v2.x | rust-v0.54 | tcp | noise | yamux | ✅ | 22s | 192 | 43 |
| js-v2.x x rust-v0.54 (ws, noise, mplex) | js-v2.x | rust-v0.54 | ws | noise | mplex | ✅ | 22s | 383 | 118 |
| js-v2.x x rust-v0.54 (ws, noise, yamux) | js-v2.x | rust-v0.54 | ws | noise | yamux | ✅ | 21s | 337 | 64 |
| js-v2.x x rust-v0.55 (tcp, noise, mplex) | js-v2.x | rust-v0.55 | tcp | noise | mplex | ✅ | 22s | 123 | 37 |
| js-v2.x x rust-v0.55 (tcp, noise, yamux) | js-v2.x | rust-v0.55 | tcp | noise | yamux | ✅ | 21s | 144 | 49 |
| js-v2.x x rust-v0.55 (ws, noise, mplex) | js-v2.x | rust-v0.55 | ws | noise | mplex | ✅ | 21s | 131 | 37 |
| js-v2.x x rust-v0.55 (ws, noise, yamux) | js-v2.x | rust-v0.55 | ws | noise | yamux | ✅ | 20s | 161 | 49 |
| js-v2.x x rust-v0.56 (tcp, noise, mplex) | js-v2.x | rust-v0.56 | tcp | noise | mplex | ✅ | 21s | 152 | 44 |
| js-v2.x x rust-v0.56 (ws, noise, mplex) | js-v2.x | rust-v0.56 | ws | noise | mplex | ✅ | 22s | 186 | 59 |
| js-v2.x x rust-v0.56 (tcp, noise, yamux) | js-v2.x | rust-v0.56 | tcp | noise | yamux | ✅ | 23s | 142 | 50 |
| js-v2.x x rust-v0.56 (ws, noise, yamux) | js-v2.x | rust-v0.56 | ws | noise | yamux | ✅ | 22s | 174 | 51 |
| js-v2.x x go-v0.38 (tcp, noise, yamux) | js-v2.x | go-v0.38 | tcp | noise | yamux | ✅ | 22s | 114 | 40 |
| js-v2.x x go-v0.38 (ws, noise, yamux) | js-v2.x | go-v0.38 | ws | noise | yamux | ✅ | 22s | 121 | 46 |
| js-v2.x x go-v0.38 (wss, noise, yamux) | js-v2.x | go-v0.38 | wss | noise | yamux | ✅ | 21s | 218 | 46 |
| js-v2.x x go-v0.39 (tcp, noise, yamux) | js-v2.x | go-v0.39 | tcp | noise | yamux | ✅ | 20s | 127 | 53 |
| js-v2.x x go-v0.39 (ws, noise, yamux) | js-v2.x | go-v0.39 | ws | noise | yamux | ✅ | 22s | 174 | 61 |
| js-v2.x x go-v0.39 (wss, noise, yamux) | js-v2.x | go-v0.39 | wss | noise | yamux | ✅ | 22s | 259 | 54 |
| js-v2.x x go-v0.40 (tcp, noise, yamux) | js-v2.x | go-v0.40 | tcp | noise | yamux | ✅ | 22s | 179 | 57 |
| js-v2.x x go-v0.40 (ws, noise, yamux) | js-v2.x | go-v0.40 | ws | noise | yamux | ✅ | 22s | 182 | 55 |
| js-v2.x x go-v0.40 (wss, noise, yamux) | js-v2.x | go-v0.40 | wss | noise | yamux | ✅ | 23s | 204 | 55 |
| js-v2.x x go-v0.41 (ws, noise, yamux) | js-v2.x | go-v0.41 | ws | noise | yamux | ✅ | 21s | 153 | 48 |
| js-v2.x x go-v0.41 (tcp, noise, yamux) | js-v2.x | go-v0.41 | tcp | noise | yamux | ✅ | 22s | 119 | 43 |
| js-v2.x x go-v0.41 (wss, noise, yamux) | js-v2.x | go-v0.41 | wss | noise | yamux | ✅ | 20s | 154 | 43 |
| js-v2.x x go-v0.42 (tcp, noise, yamux) | js-v2.x | go-v0.42 | tcp | noise | yamux | ✅ | 23s | 155 | 62 |
| js-v2.x x go-v0.42 (ws, noise, yamux) | js-v2.x | go-v0.42 | ws | noise | yamux | ✅ | 22s | 225 | 67 |
| js-v2.x x go-v0.42 (wss, noise, yamux) | js-v2.x | go-v0.42 | wss | noise | yamux | ✅ | 22s | 279 | 48 |
| js-v2.x x go-v0.43 (tcp, noise, yamux) | js-v2.x | go-v0.43 | tcp | noise | yamux | ✅ | 23s | 135 | 44 |
| js-v2.x x go-v0.43 (ws, noise, yamux) | js-v2.x | go-v0.43 | ws | noise | yamux | ✅ | 22s | 140 | 46 |
| js-v2.x x go-v0.43 (wss, noise, yamux) | js-v2.x | go-v0.43 | wss | noise | yamux | ✅ | 22s | 237 | 46 |
| js-v2.x x go-v0.44 (tcp, noise, yamux) | js-v2.x | go-v0.44 | tcp | noise | yamux | ✅ | 22s | 120 | 41 |
| js-v2.x x go-v0.44 (ws, noise, yamux) | js-v2.x | go-v0.44 | ws | noise | yamux | ✅ | 21s | 126 | 48 |
| js-v2.x x go-v0.44 (wss, noise, yamux) | js-v2.x | go-v0.44 | wss | noise | yamux | ✅ | 22s | 274 | 54 |
| js-v2.x x go-v0.45 (ws, noise, yamux) | js-v2.x | go-v0.45 | ws | noise | yamux | ✅ | 23s | 157 | 52 |
| js-v2.x x go-v0.45 (wss, noise, yamux) | js-v2.x | go-v0.45 | wss | noise | yamux | ✅ | 24s | 349 | 68 |
| js-v2.x x go-v0.45 (tcp, noise, yamux) | js-v2.x | go-v0.45 | tcp | noise | yamux | ✅ | 25s | 153 | 50 |
| js-v2.x x python-v0.4 (tcp, noise, mplex) | js-v2.x | python-v0.4 | tcp | noise | mplex | ✅ | 24s | 150 | 46 |
| js-v2.x x python-v0.4 (tcp, noise, yamux) | js-v2.x | python-v0.4 | tcp | noise | yamux | ✅ | 24s | 151 | 52 |
| js-v2.x x python-v0.4 (ws, noise, mplex) | js-v2.x | python-v0.4 | ws | noise | mplex | ✅ | 23s | 80 | 26 |
| js-v2.x x python-v0.4 (ws, noise, yamux) | js-v2.x | python-v0.4 | ws | noise | yamux | ✅ | 23s | 106 | 33 |
| js-v2.x x python-v0.4 (wss, noise, mplex) | js-v2.x | python-v0.4 | wss | noise | mplex | ✅ | 33s | 514 | 87 |
| js-v2.x x python-v0.4 (wss, noise, yamux) | js-v2.x | python-v0.4 | wss | noise | yamux | ✅ | 35s | 453 | 83 |
| js-v2.x x js-v1.x (tcp, noise, mplex) | js-v2.x | js-v1.x | tcp | noise | mplex | ✅ | 36s | 252 | 97 |
| js-v2.x x js-v1.x (ws, noise, mplex) | js-v2.x | js-v1.x | ws | noise | mplex | ✅ | 37s | 299 | 65 |
| js-v2.x x js-v1.x (tcp, noise, yamux) | js-v2.x | js-v1.x | tcp | noise | yamux | ✅ | 37s | 206 | 67 |
| js-v2.x x js-v1.x (ws, noise, yamux) | js-v2.x | js-v1.x | ws | noise | yamux | ✅ | 37s | 231 | 90 |
| js-v2.x x js-v2.x (tcp, noise, mplex) | js-v2.x | js-v2.x | tcp | noise | mplex | ✅ | 36s | 189 | 75 |
| js-v2.x x js-v2.x (tcp, noise, yamux) | js-v2.x | js-v2.x | tcp | noise | yamux | ✅ | 36s | 195 | 84 |
| js-v2.x x js-v2.x (ws, noise, mplex) | js-v2.x | js-v2.x | ws | noise | mplex | ✅ | 35s | 327 | 127 |
| js-v2.x x js-v3.x (tcp, noise, mplex) | js-v2.x | js-v3.x | tcp | noise | mplex | ✅ | 34s | 211 | 49 |
| js-v2.x x js-v2.x (ws, noise, yamux) | js-v2.x | js-v2.x | ws | noise | yamux | ✅ | 36s | 293 | 105 |
| js-v2.x x js-v3.x (tcp, noise, yamux) | js-v2.x | js-v3.x | tcp | noise | yamux | ✅ | 36s | 223 | 74 |
| js-v2.x x js-v3.x (ws, noise, mplex) | js-v2.x | js-v3.x | ws | noise | mplex | ✅ | 35s | 196 | 45 |
| js-v2.x x nim-v1.14 (tcp, noise, mplex) | js-v2.x | nim-v1.14 | tcp | noise | mplex | ✅ | 34s | 195 | 25 |
| js-v2.x x nim-v1.14 (tcp, noise, yamux) | js-v2.x | nim-v1.14 | tcp | noise | yamux | ✅ | 33s | 216 | 40 |
| js-v2.x x js-v3.x (ws, noise, yamux) | js-v2.x | js-v3.x | ws | noise | yamux | ✅ | 36s | 181 | 86 |
| js-v2.x x nim-v1.14 (ws, noise, mplex) | js-v2.x | nim-v1.14 | ws | noise | mplex | ✅ | 24s | 338 | 51 |
| js-v2.x x nim-v1.14 (ws, noise, yamux) | js-v2.x | nim-v1.14 | ws | noise | yamux | ✅ | 25s | 331 | 61 |
| js-v2.x x jvm-v1.2 (tcp, noise, mplex) | js-v2.x | jvm-v1.2 | tcp | noise | mplex | ✅ | 27s | 1269 | 122 |
| js-v2.x x jvm-v1.2 (tcp, noise, yamux) | js-v2.x | jvm-v1.2 | tcp | noise | yamux | ✅ | 28s | 1320 | 160 |
| js-v2.x x c-v0.0.1 (tcp, noise, mplex) | js-v2.x | c-v0.0.1 | tcp | noise | mplex | ✅ | 25s | 139 | 27 |
| js-v2.x x jvm-v1.2 (ws, noise, mplex) | js-v2.x | jvm-v1.2 | ws | noise | mplex | ✅ | 28s | 2004 | 256 |
| js-v2.x x c-v0.0.1 (tcp, noise, yamux) | js-v2.x | c-v0.0.1 | tcp | noise | yamux | ✅ | 24s | 163 | 83 |
| js-v2.x x jvm-v1.2 (ws, noise, yamux) | js-v2.x | jvm-v1.2 | ws | noise | yamux | ✅ | 28s | 1815 | 161 |
| js-v2.x x dotnet-v1.0 (tcp, noise, yamux) | js-v2.x | dotnet-v1.0 | tcp | noise | yamux | ✅ | 21s | 503 | 147 |
| js-v3.x x rust-v0.53 (tcp, noise, mplex) | js-v3.x | rust-v0.53 | tcp | noise | mplex | ✅ | 22s | 191 | 5 |
| js-v3.x x rust-v0.53 (tcp, noise, yamux) | js-v3.x | rust-v0.53 | tcp | noise | yamux | ✅ | 22s | 170 | 5 |
| js-v3.x x rust-v0.53 (ws, noise, yamux) | js-v3.x | rust-v0.53 | ws | noise | yamux | ✅ | 21s | 238 | 5 |
| js-v3.x x rust-v0.53 (ws, noise, mplex) | js-v3.x | rust-v0.53 | ws | noise | mplex | ✅ | 22s | 218 | 5 |
| js-v3.x x rust-v0.54 (tcp, noise, mplex) | js-v3.x | rust-v0.54 | tcp | noise | mplex | ✅ | 21s | 181 | 4 |
| js-v3.x x rust-v0.54 (tcp, noise, yamux) | js-v3.x | rust-v0.54 | tcp | noise | yamux | ✅ | 22s | 153 | 4 |
| js-v3.x x rust-v0.54 (ws, noise, mplex) | js-v3.x | rust-v0.54 | ws | noise | mplex | ✅ | 21s | 230 | 4 |
| js-v3.x x rust-v0.54 (ws, noise, yamux) | js-v3.x | rust-v0.54 | ws | noise | yamux | ✅ | 19s | 300 | 5 |
| js-v3.x x rust-v0.55 (tcp, noise, mplex) | js-v3.x | rust-v0.55 | tcp | noise | mplex | ✅ | 22s | 119 | 5 |
| js-v3.x x rust-v0.55 (tcp, noise, yamux) | js-v3.x | rust-v0.55 | tcp | noise | yamux | ✅ | 22s | 140 | 5 |
| js-v3.x x rust-v0.55 (ws, noise, mplex) | js-v3.x | rust-v0.55 | ws | noise | mplex | ✅ | 22s | 135 | 19 |
| js-v3.x x rust-v0.55 (ws, noise, yamux) | js-v3.x | rust-v0.55 | ws | noise | yamux | ✅ | 21s | 135 | 19 |
| js-v3.x x rust-v0.56 (tcp, noise, mplex) | js-v3.x | rust-v0.56 | tcp | noise | mplex | ✅ | 21s | 104 | 12 |
| js-v3.x x rust-v0.56 (tcp, noise, yamux) | js-v3.x | rust-v0.56 | tcp | noise | yamux | ✅ | 21s | 121 | 14 |
| js-v3.x x rust-v0.56 (ws, noise, mplex) | js-v3.x | rust-v0.56 | ws | noise | mplex | ✅ | 21s | 97 | 9 |
| js-v3.x x rust-v0.56 (ws, noise, yamux) | js-v3.x | rust-v0.56 | ws | noise | yamux | ✅ | 19s | 154 | 17 |
| js-v3.x x go-v0.38 (tcp, noise, yamux) | js-v3.x | go-v0.38 | tcp | noise | yamux | ✅ | 21s | 133 | 13 |
| js-v3.x x go-v0.38 (ws, noise, yamux) | js-v3.x | go-v0.38 | ws | noise | yamux | ✅ | 21s | 182 | 2 |
| js-v3.x x go-v0.38 (wss, noise, yamux) | js-v3.x | go-v0.38 | wss | noise | yamux | ✅ | 22s | 260 | 36 |
| js-v3.x x go-v0.39 (tcp, noise, yamux) | js-v3.x | go-v0.39 | tcp | noise | yamux | ✅ | 22s | 125 | 13 |
| js-v3.x x go-v0.39 (ws, noise, yamux) | js-v3.x | go-v0.39 | ws | noise | yamux | ✅ | 22s | 108 | 11 |
| js-v3.x x go-v0.39 (wss, noise, yamux) | js-v3.x | go-v0.39 | wss | noise | yamux | ✅ | 21s | 184 | 33 |
| js-v3.x x go-v0.40 (tcp, noise, yamux) | js-v3.x | go-v0.40 | tcp | noise | yamux | ✅ | 22s | 109 | 12 |
| js-v3.x x go-v0.40 (ws, noise, yamux) | js-v3.x | go-v0.40 | ws | noise | yamux | ✅ | 20s | 171 | 23 |
| js-v3.x x go-v0.40 (wss, noise, yamux) | js-v3.x | go-v0.40 | wss | noise | yamux | ✅ | 22s | 238 | 34 |
| js-v3.x x go-v0.41 (tcp, noise, yamux) | js-v3.x | go-v0.41 | tcp | noise | yamux | ✅ | 21s | 140 | 16 |
| js-v3.x x go-v0.41 (ws, noise, yamux) | js-v3.x | go-v0.41 | ws | noise | yamux | ✅ | 21s | 163 | 12 |
| js-v3.x x go-v0.41 (wss, noise, yamux) | js-v3.x | go-v0.41 | wss | noise | yamux | ✅ | 21s | 226 | 1 |
| js-v3.x x go-v0.42 (tcp, noise, yamux) | js-v3.x | go-v0.42 | tcp | noise | yamux | ✅ | 22s | 143 | 19 |
| js-v3.x x go-v0.42 (ws, noise, yamux) | js-v3.x | go-v0.42 | ws | noise | yamux | ✅ | 22s | 131 | 14 |
| js-v3.x x go-v0.42 (wss, noise, yamux) | js-v3.x | go-v0.42 | wss | noise | yamux | ✅ | 22s | 155 | 12 |
| js-v3.x x go-v0.43 (tcp, noise, yamux) | js-v3.x | go-v0.43 | tcp | noise | yamux | ✅ | 20s | 131 | 2 |
| js-v3.x x go-v0.43 (ws, noise, yamux) | js-v3.x | go-v0.43 | ws | noise | yamux | ✅ | 21s | 155 | 15 |
| js-v3.x x go-v0.43 (wss, noise, yamux) | js-v3.x | go-v0.43 | wss | noise | yamux | ✅ | 21s | 282 | 32 |
| js-v3.x x go-v0.44 (tcp, noise, yamux) | js-v3.x | go-v0.44 | tcp | noise | yamux | ✅ | 22s | 129 | 17 |
| js-v3.x x go-v0.44 (ws, noise, yamux) | js-v3.x | go-v0.44 | ws | noise | yamux | ✅ | 21s | 146 | 16 |
| js-v3.x x go-v0.44 (wss, noise, yamux) | js-v3.x | go-v0.44 | wss | noise | yamux | ✅ | 22s | 219 | 31 |
| js-v3.x x go-v0.45 (tcp, noise, yamux) | js-v3.x | go-v0.45 | tcp | noise | yamux | ✅ | 22s | 128 | 2 |
| js-v3.x x go-v0.45 (ws, noise, yamux) | js-v3.x | go-v0.45 | ws | noise | yamux | ✅ | 22s | 151 | 17 |
| js-v3.x x go-v0.45 (wss, noise, yamux) | js-v3.x | go-v0.45 | wss | noise | yamux | ✅ | 21s | 250 | 3 |
| js-v3.x x python-v0.4 (tcp, noise, mplex) | js-v3.x | python-v0.4 | tcp | noise | mplex | ✅ | 24s | 169 | 4 |
| js-v3.x x python-v0.4 (tcp, noise, yamux) | js-v3.x | python-v0.4 | tcp | noise | yamux | ✅ | 26s | 163 | 11 |
| js-v3.x x python-v0.4 (ws, noise, mplex) | js-v3.x | python-v0.4 | ws | noise | mplex | ✅ | 26s | 260 | 9 |
| js-v3.x x python-v0.4 (ws, noise, yamux) | js-v3.x | python-v0.4 | ws | noise | yamux | ✅ | 26s | 222 | 11 |
| js-v3.x x python-v0.4 (wss, noise, mplex) | js-v3.x | python-v0.4 | wss | noise | mplex | ✅ | 25s | 286 | 6 |
| js-v3.x x python-v0.4 (wss, noise, yamux) | js-v3.x | python-v0.4 | wss | noise | yamux | ✅ | 26s | 303 | 7 |
| js-v3.x x js-v1.x (tcp, noise, mplex) | js-v3.x | js-v1.x | tcp | noise | mplex | ✅ | 25s | 205 | 12 |
| js-v3.x x js-v1.x (tcp, noise, yamux) | js-v3.x | js-v1.x | tcp | noise | yamux | ✅ | 28s | 311 | 19 |
| js-v3.x x js-v1.x (ws, noise, mplex) | js-v3.x | js-v1.x | ws | noise | mplex | ✅ | 38s | 465 | 16 |
| js-v3.x x js-v1.x (ws, noise, yamux) | js-v3.x | js-v1.x | ws | noise | yamux | ✅ | 39s | 340 | 20 |
| js-v3.x x js-v2.x (tcp, noise, mplex) | js-v3.x | js-v2.x | tcp | noise | mplex | ✅ | 39s | 231 | 28 |
| js-v3.x x js-v2.x (tcp, noise, yamux) | js-v3.x | js-v2.x | tcp | noise | yamux | ✅ | 39s | 235 | 29 |
| js-v3.x x js-v2.x (ws, noise, mplex) | js-v3.x | js-v2.x | ws | noise | mplex | ✅ | 41s | 268 | 4 |
| js-v3.x x js-v3.x (tcp, noise, mplex) | js-v3.x | js-v3.x | tcp | noise | mplex | ✅ | 39s | 145 | 24 |
| js-v3.x x js-v2.x (ws, noise, yamux) | js-v3.x | js-v2.x | ws | noise | yamux | ✅ | 41s | 275 | 44 |
| js-v3.x x js-v3.x (tcp, noise, yamux) | js-v3.x | js-v3.x | tcp | noise | yamux | ✅ | 33s | 237 | 8 |
| js-v3.x x js-v3.x (ws, noise, mplex) | js-v3.x | js-v3.x | ws | noise | mplex | ✅ | 28s | 255 | 9 |
| js-v3.x x js-v3.x (ws, noise, yamux) | js-v3.x | js-v3.x | ws | noise | yamux | ✅ | 29s | 202 | 10 |
| js-v3.x x nim-v1.14 (tcp, noise, mplex) | js-v3.x | nim-v1.14 | tcp | noise | mplex | ✅ | 29s | 213 | 5 |
| js-v3.x x nim-v1.14 (tcp, noise, yamux) | js-v3.x | nim-v1.14 | tcp | noise | yamux | ✅ | 29s | 212 | 7 |
| js-v3.x x nim-v1.14 (ws, noise, mplex) | js-v3.x | nim-v1.14 | ws | noise | mplex | ✅ | 29s | 249 | 8 |
| js-v3.x x nim-v1.14 (ws, noise, yamux) | js-v3.x | nim-v1.14 | ws | noise | yamux | ✅ | 26s | 191 | 8 |
| js-v3.x x jvm-v1.2 (tcp, noise, mplex) | js-v3.x | jvm-v1.2 | tcp | noise | mplex | ✅ | 28s | 658 | 2 |
| js-v3.x x jvm-v1.2 (tcp, noise, yamux) | js-v3.x | jvm-v1.2 | tcp | noise | yamux | ✅ | 25s | 1267 | 101 |
| nim-v1.14 x rust-v0.53 (tcp, noise, mplex) | nim-v1.14 | rust-v0.53 | tcp | noise | mplex | ✅ | 5s | 281.0 | 1.0 |
| nim-v1.14 x rust-v0.53 (tcp, noise, yamux) | nim-v1.14 | rust-v0.53 | tcp | noise | yamux | ✅ | 5s | 315.0 | 0.0 |
| nim-v1.14 x rust-v0.53 (ws, noise, mplex) | nim-v1.14 | rust-v0.53 | ws | noise | mplex | ✅ | 5s | 459.0 | 42.0 |
| nim-v1.14 x rust-v0.53 (ws, noise, yamux) | nim-v1.14 | rust-v0.53 | ws | noise | yamux | ✅ | 5s | 452.0 | 43.0 |
| nim-v1.14 x rust-v0.54 (tcp, noise, mplex) | nim-v1.14 | rust-v0.54 | tcp | noise | mplex | ✅ | 5s | 283.0 | 4.0 |
| nim-v1.14 x rust-v0.54 (tcp, noise, yamux) | nim-v1.14 | rust-v0.54 | tcp | noise | yamux | ✅ | 6s | 329.0 | 0.0 |
| js-v3.x x jvm-v1.2 (ws, noise, mplex) | js-v3.x | jvm-v1.2 | ws | noise | mplex | ✅ | 22s | 1499 | 24 |
| js-v3.x x c-v0.0.1 (tcp, noise, mplex) | js-v3.x | c-v0.0.1 | tcp | noise | mplex | ✅ | 19s | 100 | 2 |
| js-v3.x x jvm-v1.2 (ws, noise, yamux) | js-v3.x | jvm-v1.2 | ws | noise | yamux | ✅ | 22s | 1304 | 87 |
| nim-v1.14 x rust-v0.54 (ws, noise, mplex) | nim-v1.14 | rust-v0.54 | ws | noise | mplex | ✅ | 6s | 455.0 | 43.0 |
| js-v3.x x c-v0.0.1 (tcp, noise, yamux) | js-v3.x | c-v0.0.1 | tcp | noise | yamux | ✅ | 20s | 156 | 6 |
| js-v3.x x dotnet-v1.0 (tcp, noise, yamux) | js-v3.x | dotnet-v1.0 | tcp | noise | yamux | ✅ | 20s | 263 | 15 |
| nim-v1.14 x rust-v0.54 (ws, noise, yamux) | nim-v1.14 | rust-v0.54 | ws | noise | yamux | ✅ | 5s | 457.0 | 43.0 |
| nim-v1.14 x rust-v0.55 (tcp, noise, mplex) | nim-v1.14 | rust-v0.55 | tcp | noise | mplex | ✅ | 5s | 184.0 | 0.0 |
| nim-v1.14 x rust-v0.55 (tcp, noise, yamux) | nim-v1.14 | rust-v0.55 | tcp | noise | yamux | ✅ | 5s | 193.0 | 0.0 |
| nim-v1.14 x rust-v0.55 (ws, noise, mplex) | nim-v1.14 | rust-v0.55 | ws | noise | mplex | ✅ | 5s | 191.0 | 0.0 |
| nim-v1.14 x rust-v0.55 (ws, noise, yamux) | nim-v1.14 | rust-v0.55 | ws | noise | yamux | ✅ | 4s | 188.0 | 0.0 |
| nim-v1.14 x rust-v0.56 (tcp, noise, mplex) | nim-v1.14 | rust-v0.56 | tcp | noise | mplex | ✅ | 5s | 183.0 | 43.0 |
| nim-v1.14 x rust-v0.56 (tcp, noise, yamux) | nim-v1.14 | rust-v0.56 | tcp | noise | yamux | ✅ | 5s | 183.0 | 1.0 |
| nim-v1.14 x rust-v0.56 (ws, noise, mplex) | nim-v1.14 | rust-v0.56 | ws | noise | mplex | ✅ | 5s | 194.0 | 48.0 |
| nim-v1.14 x rust-v0.56 (ws, noise, yamux) | nim-v1.14 | rust-v0.56 | ws | noise | yamux | ✅ | 5s | 185.0 | 0.0 |
| nim-v1.14 x go-v0.38 (ws, noise, yamux) | nim-v1.14 | go-v0.38 | ws | noise | yamux | ✅ | 5s | 251.0 | 0.0 |
| nim-v1.14 x go-v0.38 (tcp, noise, yamux) | nim-v1.14 | go-v0.38 | tcp | noise | yamux | ✅ | 6s | 202.0 | 0.0 |
| nim-v1.14 x go-v0.39 (tcp, noise, yamux) | nim-v1.14 | go-v0.39 | tcp | noise | yamux | ✅ | 5s | 147.0 | 0.0 |
| nim-v1.14 x go-v0.39 (ws, noise, yamux) | nim-v1.14 | go-v0.39 | ws | noise | yamux | ✅ | 5s | 243.0 | 0.0 |
| nim-v1.14 x go-v0.40 (tcp, noise, yamux) | nim-v1.14 | go-v0.40 | tcp | noise | yamux | ✅ | 5s | 196.0 | 0.0 |
| nim-v1.14 x go-v0.40 (ws, noise, yamux) | nim-v1.14 | go-v0.40 | ws | noise | yamux | ✅ | 5s | 244.0 | 0.0 |
| nim-v1.14 x go-v0.41 (tcp, noise, yamux) | nim-v1.14 | go-v0.41 | tcp | noise | yamux | ✅ | 5s | 193.0 | 0.0 |
| nim-v1.14 x go-v0.41 (ws, noise, yamux) | nim-v1.14 | go-v0.41 | ws | noise | yamux | ✅ | 5s | 195.0 | 0.0 |
| nim-v1.14 x go-v0.42 (tcp, noise, yamux) | nim-v1.14 | go-v0.42 | tcp | noise | yamux | ✅ | 4s | 216.0 | 0.0 |
| nim-v1.14 x go-v0.42 (ws, noise, yamux) | nim-v1.14 | go-v0.42 | ws | noise | yamux | ✅ | 5s | 249.0 | 0.0 |
| nim-v1.14 x go-v0.43 (tcp, noise, yamux) | nim-v1.14 | go-v0.43 | tcp | noise | yamux | ✅ | 5s | 135.0 | 0.0 |
| nim-v1.14 x go-v0.43 (ws, noise, yamux) | nim-v1.14 | go-v0.43 | ws | noise | yamux | ✅ | 4s | 242.0 | 0.0 |
| nim-v1.14 x go-v0.44 (tcp, noise, yamux) | nim-v1.14 | go-v0.44 | tcp | noise | yamux | ✅ | 5s | 192.0 | 0.0 |
| nim-v1.14 x go-v0.44 (ws, noise, yamux) | nim-v1.14 | go-v0.44 | ws | noise | yamux | ✅ | 4s | 248.0 | 0.0 |
| nim-v1.14 x go-v0.45 (tcp, noise, yamux) | nim-v1.14 | go-v0.45 | tcp | noise | yamux | ✅ | 5s | 196.0 | 0.0 |
| nim-v1.14 x go-v0.45 (ws, noise, yamux) | nim-v1.14 | go-v0.45 | ws | noise | yamux | ✅ | 5s | 251.0 | 0.0 |
| nim-v1.14 x python-v0.4 (tcp, noise, mplex) | nim-v1.14 | python-v0.4 | tcp | noise | mplex | ✅ | 5s | 154.0 | 1.0 |
| nim-v1.14 x python-v0.4 (tcp, noise, yamux) | nim-v1.14 | python-v0.4 | tcp | noise | yamux | ✅ | 5s | 169.0 | 0.0 |
| nim-v1.14 x python-v0.4 (ws, noise, mplex) | nim-v1.14 | python-v0.4 | ws | noise | mplex | ✅ | 6s | 187.0 | 1.0 |
| nim-v1.14 x python-v0.4 (ws, noise, yamux) | nim-v1.14 | python-v0.4 | ws | noise | yamux | ✅ | 5s | 224.0 | 1.0 |
| nim-v1.14 x js-v1.x (tcp, noise, mplex) | nim-v1.14 | js-v1.x | tcp | noise | mplex | ✅ | 19s | 296.0 | 1.0 |
| nim-v1.14 x js-v1.x (tcp, noise, yamux) | nim-v1.14 | js-v1.x | tcp | noise | yamux | ✅ | 21s | 327.0 | 1.0 |
| nim-v1.14 x js-v1.x (ws, noise, mplex) | nim-v1.14 | js-v1.x | ws | noise | mplex | ✅ | 21s | 350.0 | 2.0 |
| nim-v1.14 x js-v1.x (ws, noise, yamux) | nim-v1.14 | js-v1.x | ws | noise | yamux | ✅ | 21s | 345.0 | 2.0 |
| nim-v1.14 x js-v2.x (tcp, noise, mplex) | nim-v1.14 | js-v2.x | tcp | noise | mplex | ✅ | 21s | 247.0 | 3.0 |
| nim-v1.14 x js-v2.x (tcp, noise, yamux) | nim-v1.14 | js-v2.x | tcp | noise | yamux | ✅ | 21s | 268.0 | 4.0 |
| nim-v1.14 x js-v2.x (ws, noise, mplex) | nim-v1.14 | js-v2.x | ws | noise | mplex | ✅ | 21s | 253.0 | 1.0 |
| nim-v1.14 x js-v2.x (ws, noise, yamux) | nim-v1.14 | js-v2.x | ws | noise | yamux | ✅ | 20s | 302.0 | 4.0 |
| nim-v1.14 x nim-v1.14 (tcp, noise, mplex) | nim-v1.14 | nim-v1.14 | tcp | noise | mplex | ✅ | 5s | 384.0 | 4.0 |
| nim-v1.14 x nim-v1.14 (tcp, noise, yamux) | nim-v1.14 | nim-v1.14 | tcp | noise | yamux | ✅ | 5s | 394.0 | 0.0 |
| nim-v1.14 x nim-v1.14 (ws, noise, mplex) | nim-v1.14 | nim-v1.14 | ws | noise | mplex | ✅ | 5s | 402.0 | 1.0 |
| nim-v1.14 x nim-v1.14 (ws, noise, yamux) | nim-v1.14 | nim-v1.14 | ws | noise | yamux | ✅ | 5s | 392.0 | 1.0 |
| nim-v1.14 x js-v3.x (tcp, noise, mplex) | nim-v1.14 | js-v3.x | tcp | noise | mplex | ✅ | 20s | 297.0 | 2.0 |
| nim-v1.14 x js-v3.x (tcp, noise, yamux) | nim-v1.14 | js-v3.x | tcp | noise | yamux | ✅ | 19s | 268.0 | 3.0 |
| nim-v1.14 x jvm-v1.2 (tcp, noise, mplex) | nim-v1.14 | jvm-v1.2 | tcp | noise | mplex | ✅ | 11s | 1080.0 | 8.0 |
| nim-v1.14 x jvm-v1.2 (tcp, noise, yamux) | nim-v1.14 | jvm-v1.2 | tcp | noise | yamux | ✅ | 11s | 1025.0 | 6.0 |
| nim-v1.14 x js-v3.x (ws, noise, yamux) | nim-v1.14 | js-v3.x | ws | noise | yamux | ✅ | 20s | 329.0 | 10.0 |
| nim-v1.14 x js-v3.x (ws, noise, mplex) | nim-v1.14 | js-v3.x | ws | noise | mplex | ✅ | 20s | 340.0 | 12.0 |
| nim-v1.14 x jvm-v1.2 (ws, noise, mplex) | nim-v1.14 | jvm-v1.2 | ws | noise | mplex | ✅ | 11s | 1254.0 | 6.0 |
| nim-v1.14 x jvm-v1.2 (ws, noise, yamux) | nim-v1.14 | jvm-v1.2 | ws | noise | yamux | ✅ | 10s | 1238.0 | 4.0 |
| nim-v1.14 x c-v0.0.1 (tcp, noise, mplex) | nim-v1.14 | c-v0.0.1 | tcp | noise | mplex | ✅ | 4s | 183.0 | 0.0 |
| nim-v1.14 x c-v0.0.1 (tcp, noise, yamux) | nim-v1.14 | c-v0.0.1 | tcp | noise | yamux | ✅ | 4s | 293.0 | 1.0 |
| nim-v1.14 x dotnet-v1.0 (tcp, noise, yamux) | nim-v1.14 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 5s | 392.0 | 4.0 |
| jvm-v1.2 x rust-v0.53 (tcp, noise, mplex) | jvm-v1.2 | rust-v0.53 | tcp | noise | mplex | ✅ | 15s | - | - |
| jvm-v1.2 x rust-v0.53 (tcp, noise, yamux) | jvm-v1.2 | rust-v0.53 | tcp | noise | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x rust-v0.53 (tcp, tls, mplex) | jvm-v1.2 | rust-v0.53 | tcp | tls | mplex | ✅ | 17s | - | - |
| jvm-v1.2 x rust-v0.53 (tcp, tls, yamux) | jvm-v1.2 | rust-v0.53 | tcp | tls | yamux | ✅ | 17s | - | - |
| jvm-v1.2 x rust-v0.53 (ws, noise, mplex) | jvm-v1.2 | rust-v0.53 | ws | noise | mplex | ✅ | 15s | - | - |
| jvm-v1.2 x rust-v0.53 (ws, tls, mplex) | jvm-v1.2 | rust-v0.53 | ws | tls | mplex | ✅ | 19s | - | - |
| jvm-v1.2 x rust-v0.53 (ws, tls, yamux) | jvm-v1.2 | rust-v0.53 | ws | tls | yamux | ✅ | 18s | - | - |
| jvm-v1.2 x rust-v0.53 (ws, noise, yamux) | jvm-v1.2 | rust-v0.53 | ws | noise | yamux | ✅ | 17s | - | - |
| jvm-v1.2 x rust-v0.53 (quic-v1) | jvm-v1.2 | rust-v0.53 | quic-v1 | - | - | ✅ | 12s | - | - |
| jvm-v1.2 x rust-v0.54 (tcp, tls, mplex) | jvm-v1.2 | rust-v0.54 | tcp | tls | mplex | ✅ | 14s | - | - |
| jvm-v1.2 x rust-v0.54 (tcp, tls, yamux) | jvm-v1.2 | rust-v0.54 | tcp | tls | yamux | ✅ | 14s | - | - |
| jvm-v1.2 x rust-v0.54 (tcp, noise, mplex) | jvm-v1.2 | rust-v0.54 | tcp | noise | mplex | ✅ | 14s | - | - |
| jvm-v1.2 x rust-v0.54 (tcp, noise, yamux) | jvm-v1.2 | rust-v0.54 | tcp | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x rust-v0.54 (ws, noise, mplex) | jvm-v1.2 | rust-v0.54 | ws | noise | mplex | ✅ | 13s | - | - |
| jvm-v1.2 x rust-v0.54 (ws, tls, mplex) | jvm-v1.2 | rust-v0.54 | ws | tls | mplex | ✅ | 15s | - | - |
| jvm-v1.2 x rust-v0.54 (ws, tls, yamux) | jvm-v1.2 | rust-v0.54 | ws | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x rust-v0.54 (ws, noise, yamux) | jvm-v1.2 | rust-v0.54 | ws | noise | yamux | ✅ | 12s | - | - |
| jvm-v1.2 x rust-v0.54 (quic-v1) | jvm-v1.2 | rust-v0.54 | quic-v1 | - | - | ✅ | 14s | - | - |
| jvm-v1.2 x rust-v0.55 (tcp, tls, mplex) | jvm-v1.2 | rust-v0.55 | tcp | tls | mplex | ✅ | 15s | - | - |
| jvm-v1.2 x rust-v0.55 (tcp, noise, mplex) | jvm-v1.2 | rust-v0.55 | tcp | noise | mplex | ✅ | 13s | - | - |
| jvm-v1.2 x rust-v0.55 (tcp, tls, yamux) | jvm-v1.2 | rust-v0.55 | tcp | tls | yamux | ✅ | 16s | - | - |
| jvm-v1.2 x rust-v0.55 (tcp, noise, yamux) | jvm-v1.2 | rust-v0.55 | tcp | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x rust-v0.55 (ws, tls, mplex) | jvm-v1.2 | rust-v0.55 | ws | tls | mplex | ✅ | 15s | - | - |
| jvm-v1.2 x rust-v0.55 (ws, tls, yamux) | jvm-v1.2 | rust-v0.55 | ws | tls | yamux | ✅ | 16s | - | - |
| jvm-v1.2 x rust-v0.55 (ws, noise, mplex) | jvm-v1.2 | rust-v0.55 | ws | noise | mplex | ✅ | 13s | - | - |
| jvm-v1.2 x rust-v0.55 (ws, noise, yamux) | jvm-v1.2 | rust-v0.55 | ws | noise | yamux | ✅ | 12s | - | - |
| jvm-v1.2 x rust-v0.55 (quic-v1) | jvm-v1.2 | rust-v0.55 | quic-v1 | - | - | ✅ | 13s | - | - |
| jvm-v1.2 x rust-v0.56 (tcp, tls, mplex) | jvm-v1.2 | rust-v0.56 | tcp | tls | mplex | ✅ | 14s | - | - |
| jvm-v1.2 x rust-v0.56 (tcp, noise, mplex) | jvm-v1.2 | rust-v0.56 | tcp | noise | mplex | ✅ | 14s | - | - |
| jvm-v1.2 x rust-v0.56 (tcp, tls, yamux) | jvm-v1.2 | rust-v0.56 | tcp | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x rust-v0.56 (tcp, noise, yamux) | jvm-v1.2 | rust-v0.56 | tcp | noise | yamux | ✅ | 12s | - | - |
| jvm-v1.2 x rust-v0.56 (ws, tls, mplex) | jvm-v1.2 | rust-v0.56 | ws | tls | mplex | ✅ | 13s | - | - |
| jvm-v1.2 x rust-v0.56 (ws, noise, mplex) | jvm-v1.2 | rust-v0.56 | ws | noise | mplex | ✅ | 13s | - | - |
| jvm-v1.2 x rust-v0.56 (ws, tls, yamux) | jvm-v1.2 | rust-v0.56 | ws | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x rust-v0.56 (ws, noise, yamux) | jvm-v1.2 | rust-v0.56 | ws | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x go-v0.38 (tcp, noise, yamux) | jvm-v1.2 | go-v0.38 | tcp | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x rust-v0.56 (quic-v1) | jvm-v1.2 | rust-v0.56 | quic-v1 | - | - | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.38 (tcp, tls, yamux) | jvm-v1.2 | go-v0.38 | tcp | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.38 (ws, tls, yamux) | jvm-v1.2 | go-v0.38 | ws | tls | yamux | ✅ | 16s | - | - |
| jvm-v1.2 x go-v0.38 (ws, noise, yamux) | jvm-v1.2 | go-v0.38 | ws | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x go-v0.39 (tcp, noise, yamux) | jvm-v1.2 | go-v0.39 | tcp | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x go-v0.38 (quic-v1) | jvm-v1.2 | go-v0.38 | quic-v1 | - | - | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.39 (tcp, tls, yamux) | jvm-v1.2 | go-v0.39 | tcp | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.39 (ws, tls, yamux) | jvm-v1.2 | go-v0.39 | ws | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.39 (ws, noise, yamux) | jvm-v1.2 | go-v0.39 | ws | noise | yamux | ✅ | 14s | - | - |
| jvm-v1.2 x go-v0.39 (quic-v1) | jvm-v1.2 | go-v0.39 | quic-v1 | - | - | ✅ | 14s | - | - |
| jvm-v1.2 x go-v0.40 (tcp, noise, yamux) | jvm-v1.2 | go-v0.40 | tcp | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x go-v0.40 (tcp, tls, yamux) | jvm-v1.2 | go-v0.40 | tcp | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.40 (ws, noise, yamux) | jvm-v1.2 | go-v0.40 | ws | noise | yamux | ✅ | 11s | - | - |
| jvm-v1.2 x go-v0.40 (ws, tls, yamux) | jvm-v1.2 | go-v0.40 | ws | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.40 (quic-v1) | jvm-v1.2 | go-v0.40 | quic-v1 | - | - | ✅ | 14s | - | - |
| jvm-v1.2 x go-v0.41 (tcp, noise, yamux) | jvm-v1.2 | go-v0.41 | tcp | noise | yamux | ✅ | 12s | - | - |
| jvm-v1.2 x go-v0.41 (tcp, tls, yamux) | jvm-v1.2 | go-v0.41 | tcp | tls | yamux | ✅ | 14s | - | - |
| jvm-v1.2 x go-v0.41 (ws, noise, yamux) | jvm-v1.2 | go-v0.41 | ws | noise | yamux | ✅ | 14s | - | - |
| jvm-v1.2 x go-v0.41 (ws, tls, yamux) | jvm-v1.2 | go-v0.41 | ws | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.41 (quic-v1) | jvm-v1.2 | go-v0.41 | quic-v1 | - | - | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.42 (tcp, tls, yamux) | jvm-v1.2 | go-v0.42 | tcp | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.42 (tcp, noise, yamux) | jvm-v1.2 | go-v0.42 | tcp | noise | yamux | ✅ | 12s | - | - |
| jvm-v1.2 x go-v0.42 (ws, tls, yamux) | jvm-v1.2 | go-v0.42 | ws | tls | yamux | ✅ | 14s | - | - |
| jvm-v1.2 x go-v0.42 (ws, noise, yamux) | jvm-v1.2 | go-v0.42 | ws | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x go-v0.42 (quic-v1) | jvm-v1.2 | go-v0.42 | quic-v1 | - | - | ✅ | 14s | - | - |
| jvm-v1.2 x go-v0.43 (tcp, noise, yamux) | jvm-v1.2 | go-v0.43 | tcp | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x go-v0.43 (tcp, tls, yamux) | jvm-v1.2 | go-v0.43 | tcp | tls | yamux | ✅ | 16s | - | - |
| jvm-v1.2 x go-v0.43 (ws, tls, yamux) | jvm-v1.2 | go-v0.43 | ws | tls | yamux | ✅ | 16s | - | - |
| jvm-v1.2 x go-v0.43 (ws, noise, yamux) | jvm-v1.2 | go-v0.43 | ws | noise | yamux | ✅ | 14s | - | - |
| jvm-v1.2 x go-v0.43 (quic-v1) | jvm-v1.2 | go-v0.43 | quic-v1 | - | - | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.44 (tcp, noise, yamux) | jvm-v1.2 | go-v0.44 | tcp | noise | yamux | ✅ | 12s | - | - |
| jvm-v1.2 x go-v0.44 (tcp, tls, yamux) | jvm-v1.2 | go-v0.44 | tcp | tls | yamux | ✅ | 16s | - | - |
| jvm-v1.2 x go-v0.44 (ws, tls, yamux) | jvm-v1.2 | go-v0.44 | ws | tls | yamux | ✅ | 14s | - | - |
| jvm-v1.2 x go-v0.44 (ws, noise, yamux) | jvm-v1.2 | go-v0.44 | ws | noise | yamux | ✅ | 14s | - | - |
| jvm-v1.2 x go-v0.44 (quic-v1) | jvm-v1.2 | go-v0.44 | quic-v1 | - | - | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.45 (tcp, noise, yamux) | jvm-v1.2 | go-v0.45 | tcp | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x go-v0.45 (tcp, tls, yamux) | jvm-v1.2 | go-v0.45 | tcp | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.45 (ws, tls, yamux) | jvm-v1.2 | go-v0.45 | ws | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.45 (ws, noise, yamux) | jvm-v1.2 | go-v0.45 | ws | noise | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x python-v0.4 (tcp, noise, mplex) | jvm-v1.2 | python-v0.4 | tcp | noise | mplex | ❌ | 11s | - | - |
| jvm-v1.2 x go-v0.45 (quic-v1) | jvm-v1.2 | go-v0.45 | quic-v1 | - | - | ✅ | 16s | - | - |
| jvm-v1.2 x python-v0.4 (tcp, noise, yamux) | jvm-v1.2 | python-v0.4 | tcp | noise | yamux | ❌ | 11s | - | - |
| jvm-v1.2 x python-v0.4 (ws, noise, mplex) | jvm-v1.2 | python-v0.4 | ws | noise | mplex | ❌ | 11s | - | - |
| jvm-v1.2 x python-v0.4 (ws, noise, yamux) | jvm-v1.2 | python-v0.4 | ws | noise | yamux | ❌ | 11s | - | - |
| jvm-v1.2 x python-v0.4 (quic-v1) | jvm-v1.2 | python-v0.4 | quic-v1 | - | - | ❌ | 16s | - | - |
| jvm-v1.2 x js-v1.x (tcp, noise, mplex) | jvm-v1.2 | js-v1.x | tcp | noise | mplex | ✅ | 32s | - | - |
| jvm-v1.2 x js-v1.x (tcp, noise, yamux) | jvm-v1.2 | js-v1.x | tcp | noise | yamux | ✅ | 31s | - | - |
| jvm-v1.2 x js-v1.x (ws, noise, mplex) | jvm-v1.2 | js-v1.x | ws | noise | mplex | ✅ | 32s | - | - |
| jvm-v1.2 x js-v1.x (ws, noise, yamux) | jvm-v1.2 | js-v1.x | ws | noise | yamux | ✅ | 32s | - | - |
| jvm-v1.2 x js-v2.x (tcp, noise, mplex) | jvm-v1.2 | js-v2.x | tcp | noise | mplex | ✅ | 32s | - | - |
| jvm-v1.2 x js-v2.x (tcp, noise, yamux) | jvm-v1.2 | js-v2.x | tcp | noise | yamux | ✅ | 31s | - | - |
| jvm-v1.2 x js-v2.x (ws, noise, mplex) | jvm-v1.2 | js-v2.x | ws | noise | mplex | ✅ | 30s | - | - |
| jvm-v1.2 x js-v2.x (ws, noise, yamux) | jvm-v1.2 | js-v2.x | ws | noise | yamux | ✅ | 27s | - | - |
| jvm-v1.2 x nim-v1.14 (tcp, noise, mplex) | jvm-v1.2 | nim-v1.14 | tcp | noise | mplex | ✅ | 16s | - | - |
| jvm-v1.2 x nim-v1.14 (tcp, noise, yamux) | jvm-v1.2 | nim-v1.14 | tcp | noise | yamux | ✅ | 16s | - | - |
| jvm-v1.2 x nim-v1.14 (ws, noise, mplex) | jvm-v1.2 | nim-v1.14 | ws | noise | mplex | ✅ | 16s | - | - |
| jvm-v1.2 x js-v3.x (tcp, noise, mplex) | jvm-v1.2 | js-v3.x | tcp | noise | mplex | ✅ | 26s | - | - |
| jvm-v1.2 x nim-v1.14 (ws, noise, yamux) | jvm-v1.2 | nim-v1.14 | ws | noise | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x js-v3.x (tcp, noise, yamux) | jvm-v1.2 | js-v3.x | tcp | noise | yamux | ✅ | 27s | - | - |
| jvm-v1.2 x js-v3.x (ws, noise, mplex) | jvm-v1.2 | js-v3.x | ws | noise | mplex | ✅ | 27s | - | - |
| jvm-v1.2 x js-v3.x (ws, noise, yamux) | jvm-v1.2 | js-v3.x | ws | noise | yamux | ✅ | 26s | - | - |
| jvm-v1.2 x jvm-v1.2 (tcp, tls, mplex) | jvm-v1.2 | jvm-v1.2 | tcp | tls | mplex | ✅ | 18s | - | - |
| jvm-v1.2 x jvm-v1.2 (tcp, noise, mplex) | jvm-v1.2 | jvm-v1.2 | tcp | noise | mplex | ✅ | 19s | - | - |
| jvm-v1.2 x jvm-v1.2 (tcp, tls, yamux) | jvm-v1.2 | jvm-v1.2 | tcp | tls | yamux | ✅ | 24s | - | - |
| jvm-v1.2 x jvm-v1.2 (tcp, noise, yamux) | jvm-v1.2 | jvm-v1.2 | tcp | noise | yamux | ✅ | 23s | - | - |
| jvm-v1.2 x jvm-v1.2 (ws, tls, mplex) | jvm-v1.2 | jvm-v1.2 | ws | tls | mplex | ✅ | 28s | - | - |
| jvm-v1.2 x jvm-v1.2 (ws, noise, mplex) | jvm-v1.2 | jvm-v1.2 | ws | noise | mplex | ✅ | 24s | - | - |
| jvm-v1.2 x jvm-v1.2 (ws, noise, yamux) | jvm-v1.2 | jvm-v1.2 | ws | noise | yamux | ✅ | 22s | - | - |
| jvm-v1.2 x jvm-v1.2 (ws, tls, yamux) | jvm-v1.2 | jvm-v1.2 | ws | tls | yamux | ✅ | 29s | - | - |
| jvm-v1.2 x c-v0.0.1 (tcp, noise, mplex) | jvm-v1.2 | c-v0.0.1 | tcp | noise | mplex | ✅ | 16s | - | - |
| jvm-v1.2 x c-v0.0.1 (tcp, noise, yamux) | jvm-v1.2 | c-v0.0.1 | tcp | noise | yamux | ❌ | 11s | - | - |
| jvm-v1.2 x jvm-v1.2 (quic-v1) | jvm-v1.2 | jvm-v1.2 | quic-v1 | - | - | ✅ | 21s | - | - |
| c-v0.0.1 x rust-v0.53 (tcp, noise, mplex) | c-v0.0.1 | rust-v0.53 | tcp | noise | mplex | ✅ | 6s | 72.000 | 8.000 |
| jvm-v1.2 x c-v0.0.1 (quic-v1) | jvm-v1.2 | c-v0.0.1 | quic-v1 | - | - | ✅ | 16s | - | - |
| c-v0.0.1 x rust-v0.53 (tcp, noise, yamux) | c-v0.0.1 | rust-v0.53 | tcp | noise | yamux | ✅ | 5s | 77.000 | 0.000 |
| c-v0.0.1 x rust-v0.54 (tcp, noise, mplex) | c-v0.0.1 | rust-v0.54 | tcp | noise | mplex | ✅ | 6s | 64.000 | 0.000 |
| jvm-v1.2 x zig-v0.0.1 (quic-v1) | jvm-v1.2 | zig-v0.0.1 | quic-v1 | - | - | ❌ | 12s | - | - |
| jvm-v1.2 x dotnet-v1.0 (tcp, noise, yamux) | jvm-v1.2 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 14s | - | - |
| c-v0.0.1 x rust-v0.53 (quic-v1) | c-v0.0.1 | rust-v0.53 | quic-v1 | - | - | ✅ | 7s | 34.000 | 0.000 |
| c-v0.0.1 x rust-v0.54 (tcp, noise, yamux) | c-v0.0.1 | rust-v0.54 | tcp | noise | yamux | ✅ | 6s | 65.000 | 0.000 |
| c-v0.0.1 x rust-v0.55 (tcp, noise, mplex) | c-v0.0.1 | rust-v0.55 | tcp | noise | mplex | ✅ | 4s | 6.000 | 1.000 |
| jvm-v1.2 x eth-p2p-z-v0.0.1 (quic-v1) | jvm-v1.2 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 15s | - | - |
| c-v0.0.1 x rust-v0.55 (tcp, noise, yamux) | c-v0.0.1 | rust-v0.55 | tcp | noise | yamux | ✅ | 4s | 58.000 | 1.000 |
| c-v0.0.1 x rust-v0.54 (quic-v1) | c-v0.0.1 | rust-v0.54 | quic-v1 | - | - | ✅ | 7s | 26.000 | 0.000 |
| c-v0.0.1 x rust-v0.55 (quic-v1) | c-v0.0.1 | rust-v0.55 | quic-v1 | - | - | ✅ | 4s | 26.000 | 0.000 |
| c-v0.0.1 x rust-v0.56 (tcp, noise, mplex) | c-v0.0.1 | rust-v0.56 | tcp | noise | mplex | ✅ | 5s | 5.000 | 0.000 |
| c-v0.0.1 x rust-v0.56 (tcp, noise, yamux) | c-v0.0.1 | rust-v0.56 | tcp | noise | yamux | ✅ | 4s | 56.000 | 0.000 |
| c-v0.0.1 x go-v0.38 (tcp, noise, yamux) | c-v0.0.1 | go-v0.38 | tcp | noise | yamux | ✅ | 5s | 119.000 | 1.000 |
| c-v0.0.1 x rust-v0.56 (quic-v1) | c-v0.0.1 | rust-v0.56 | quic-v1 | - | - | ✅ | 7s | 37.000 | 1.000 |
| c-v0.0.1 x go-v0.39 (tcp, noise, yamux) | c-v0.0.1 | go-v0.39 | tcp | noise | yamux | ✅ | 4s | 117.000 | 0.000 |
| c-v0.0.1 x go-v0.40 (tcp, noise, yamux) | c-v0.0.1 | go-v0.40 | tcp | noise | yamux | ✅ | 5s | 124.000 | 0.000 |
| c-v0.0.1 x go-v0.41 (tcp, noise, yamux) | c-v0.0.1 | go-v0.41 | tcp | noise | yamux | ✅ | 5s | 117.000 | 1.000 |
| c-v0.0.1 x go-v0.42 (tcp, noise, yamux) | c-v0.0.1 | go-v0.42 | tcp | noise | yamux | ✅ | 3s | 122.000 | 0.000 |
| c-v0.0.1 x go-v0.43 (tcp, noise, yamux) | c-v0.0.1 | go-v0.43 | tcp | noise | yamux | ✅ | 3s | 125.000 | 1.000 |
| c-v0.0.1 x go-v0.44 (tcp, noise, yamux) | c-v0.0.1 | go-v0.44 | tcp | noise | yamux | ✅ | 4s | 119.000 | 0.000 |
| c-v0.0.1 x go-v0.38 (quic-v1) | c-v0.0.1 | go-v0.38 | quic-v1 | - | - | ✅ | 19s | 131.000 | 1.000 |
| c-v0.0.1 x go-v0.45 (tcp, noise, yamux) | c-v0.0.1 | go-v0.45 | tcp | noise | yamux | ✅ | 3s | 125.000 | 1.000 |
| c-v0.0.1 x go-v0.39 (quic-v1) | c-v0.0.1 | go-v0.39 | quic-v1 | - | - | ✅ | 20s | 142.000 | 0.000 |
| c-v0.0.1 x go-v0.40 (quic-v1) | c-v0.0.1 | go-v0.40 | quic-v1 | - | - | ✅ | 19s | 137.000 | 2.000 |
| c-v0.0.1 x go-v0.41 (quic-v1) | c-v0.0.1 | go-v0.41 | quic-v1 | - | - | ✅ | 18s | 140.000 | 1.000 |
| c-v0.0.1 x go-v0.42 (quic-v1) | c-v0.0.1 | go-v0.42 | quic-v1 | - | - | ✅ | 19s | 143.000 | 0.000 |
| c-v0.0.1 x python-v0.4 (tcp, noise, mplex) | c-v0.0.1 | python-v0.4 | tcp | noise | mplex | ✅ | 5s | 17.000 | 1.000 |
| c-v0.0.1 x go-v0.43 (quic-v1) | c-v0.0.1 | go-v0.43 | quic-v1 | - | - | ✅ | 19s | 117.000 | 3.000 |
| c-v0.0.1 x python-v0.4 (quic-v1) | c-v0.0.1 | python-v0.4 | quic-v1 | - | - | ✅ | 5s | 227.000 | 16.000 |
| c-v0.0.1 x python-v0.4 (tcp, noise, yamux) | c-v0.0.1 | python-v0.4 | tcp | noise | yamux | ✅ | 6s | 236.000 | 2.000 |
| c-v0.0.1 x go-v0.44 (quic-v1) | c-v0.0.1 | go-v0.44 | quic-v1 | - | - | ✅ | 19s | 133.000 | 2.000 |
| c-v0.0.1 x nim-v1.14 (tcp, noise, mplex) | c-v0.0.1 | nim-v1.14 | tcp | noise | mplex | ✅ | 5s | 108.000 | 0.000 |
| c-v0.0.1 x go-v0.45 (quic-v1) | c-v0.0.1 | go-v0.45 | quic-v1 | - | - | ✅ | 19s | 151.000 | 2.000 |
| c-v0.0.1 x js-v1.x (tcp, noise, mplex) | c-v0.0.1 | js-v1.x | tcp | noise | mplex | ✅ | 19s | 144.000 | 6.000 |
| c-v0.0.1 x nim-v1.14 (tcp, noise, yamux) | c-v0.0.1 | nim-v1.14 | tcp | noise | yamux | ✅ | 5s | 291.000 | 2.000 |
| c-v0.0.1 x js-v1.x (tcp, noise, yamux) | c-v0.0.1 | js-v1.x | tcp | noise | yamux | ✅ | 21s | 389.000 | 9.000 |
| c-v0.0.1 x js-v2.x (tcp, noise, mplex) | c-v0.0.1 | js-v2.x | tcp | noise | mplex | ✅ | 21s | 158.000 | 3.000 |
| c-v0.0.1 x js-v3.x (tcp, noise, mplex) | c-v0.0.1 | js-v3.x | tcp | noise | mplex | ✅ | 20s | 117.000 | 6.000 |
| c-v0.0.1 x jvm-v1.2 (tcp, noise, mplex) | c-v0.0.1 | jvm-v1.2 | tcp | noise | mplex | ✅ | 9s | 764.000 | 15.000 |
| c-v0.0.1 x js-v2.x (tcp, noise, yamux) | c-v0.0.1 | js-v2.x | tcp | noise | yamux | ✅ | 22s | 407.000 | 2.000 |
| c-v0.0.1 x js-v3.x (tcp, noise, yamux) | c-v0.0.1 | js-v3.x | tcp | noise | yamux | ✅ | 21s | 291.000 | 5.000 |
| c-v0.0.1 x jvm-v1.2 (tcp, noise, yamux) | c-v0.0.1 | jvm-v1.2 | tcp | noise | yamux | ❌ | 8s | - | - |
| c-v0.0.1 x c-v0.0.1 (tcp, noise, mplex) | c-v0.0.1 | c-v0.0.1 | tcp | noise | mplex | ✅ | 5s | 21.000 | 2.000 |
| c-v0.0.1 x c-v0.0.1 (quic-v1) | c-v0.0.1 | c-v0.0.1 | quic-v1 | - | - | ✅ | 4s | 67.000 | 24.000 |
| c-v0.0.1 x dotnet-v1.0 (tcp, noise, yamux) | c-v0.0.1 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 5s | 373.000 | 6.000 |
| c-v0.0.1 x eth-p2p-z-v0.0.1 (quic-v1) | c-v0.0.1 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 4s | 102.000 | 1.000 |
| c-v0.0.1 x jvm-v1.2 (quic-v1) | c-v0.0.1 | jvm-v1.2 | quic-v1 | - | - | ✅ | 11s | 2649.000 | 9.000 |
| c-v0.0.1 x c-v0.0.1 (tcp, noise, yamux) | c-v0.0.1 | c-v0.0.1 | tcp | noise | yamux | ✅ | 10s | 5295.000 | 0.000 |
| dotnet-v1.0 x rust-v0.53 (tcp, noise, yamux) | dotnet-v1.0 | rust-v0.53 | tcp | noise | yamux | ✅ | 6s | - | - |
| dotnet-v1.0 x rust-v0.54 (tcp, noise, yamux) | dotnet-v1.0 | rust-v0.54 | tcp | noise | yamux | ✅ | 5s | - | - |
| dotnet-v1.0 x rust-v0.55 (tcp, noise, yamux) | dotnet-v1.0 | rust-v0.55 | tcp | noise | yamux | ✅ | 4s | - | - |
| dotnet-v1.0 x rust-v0.56 (tcp, noise, yamux) | dotnet-v1.0 | rust-v0.56 | tcp | noise | yamux | ✅ | 6s | - | - |
| dotnet-v1.0 x go-v0.38 (tcp, noise, yamux) | dotnet-v1.0 | go-v0.38 | tcp | noise | yamux | ✅ | 5s | - | - |
| dotnet-v1.0 x go-v0.39 (tcp, noise, yamux) | dotnet-v1.0 | go-v0.39 | tcp | noise | yamux | ✅ | 5s | - | - |
| dotnet-v1.0 x go-v0.40 (tcp, noise, yamux) | dotnet-v1.0 | go-v0.40 | tcp | noise | yamux | ✅ | 5s | - | - |
| dotnet-v1.0 x go-v0.41 (tcp, noise, yamux) | dotnet-v1.0 | go-v0.41 | tcp | noise | yamux | ✅ | 5s | - | - |
| dotnet-v1.0 x go-v0.42 (tcp, noise, yamux) | dotnet-v1.0 | go-v0.42 | tcp | noise | yamux | ✅ | 5s | - | - |
| dotnet-v1.0 x go-v0.43 (tcp, noise, yamux) | dotnet-v1.0 | go-v0.43 | tcp | noise | yamux | ✅ | 5s | - | - |
| dotnet-v1.0 x go-v0.44 (tcp, noise, yamux) | dotnet-v1.0 | go-v0.44 | tcp | noise | yamux | ✅ | 5s | - | - |
| dotnet-v1.0 x go-v0.45 (tcp, noise, yamux) | dotnet-v1.0 | go-v0.45 | tcp | noise | yamux | ✅ | 6s | - | - |
| dotnet-v1.0 x python-v0.4 (tcp, noise, yamux) | dotnet-v1.0 | python-v0.4 | tcp | noise | yamux | ✅ | 5s | - | - |
| c-v0.0.1 x zig-v0.0.1 (quic-v1) | c-v0.0.1 | zig-v0.0.1 | quic-v1 | - | - | ❌ | 20s | - | - |
| dotnet-v1.0 x nim-v1.14 (tcp, noise, yamux) | dotnet-v1.0 | nim-v1.14 | tcp | noise | yamux | ✅ | 7s | - | - |
| dotnet-v1.0 x c-v0.0.1 (tcp, noise, yamux) | dotnet-v1.0 | c-v0.0.1 | tcp | noise | yamux | ✅ | 7s | - | - |
| zig-v0.0.1 x rust-v0.53 (quic-v1) | zig-v0.0.1 | rust-v0.53 | quic-v1 | - | - | ✅ | 6s | - | - |
| dotnet-v1.0 x dotnet-v1.0 (tcp, noise, yamux) | dotnet-v1.0 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 8s | - | - |
| dotnet-v1.0 x jvm-v1.2 (tcp, noise, yamux) | dotnet-v1.0 | jvm-v1.2 | tcp | noise | yamux | ✅ | 10s | - | - |
| dotnet-v1.0 x js-v1.x (tcp, noise, yamux) | dotnet-v1.0 | js-v1.x | tcp | noise | yamux | ❌ | 15s | - | - |
| zig-v0.0.1 x rust-v0.54 (quic-v1) | zig-v0.0.1 | rust-v0.54 | quic-v1 | - | - | ✅ | 5s | - | - |
| dotnet-v1.0 x js-v2.x (tcp, noise, yamux) | dotnet-v1.0 | js-v2.x | tcp | noise | yamux | ❌ | 16s | - | - |
| dotnet-v1.0 x js-v3.x (tcp, noise, yamux) | dotnet-v1.0 | js-v3.x | tcp | noise | yamux | ❌ | 16s | - | - |
| zig-v0.0.1 x rust-v0.55 (quic-v1) | zig-v0.0.1 | rust-v0.55 | quic-v1 | - | - | ✅ | 4s | - | - |
| zig-v0.0.1 x rust-v0.56 (quic-v1) | zig-v0.0.1 | rust-v0.56 | quic-v1 | - | - | ✅ | 5s | - | - |
| zig-v0.0.1 x go-v0.38 (quic-v1) | zig-v0.0.1 | go-v0.38 | quic-v1 | - | - | ✅ | 5s | - | - |
| zig-v0.0.1 x go-v0.39 (quic-v1) | zig-v0.0.1 | go-v0.39 | quic-v1 | - | - | ✅ | 4s | - | - |
| zig-v0.0.1 x go-v0.40 (quic-v1) | zig-v0.0.1 | go-v0.40 | quic-v1 | - | - | ✅ | 5s | - | - |
| zig-v0.0.1 x go-v0.41 (quic-v1) | zig-v0.0.1 | go-v0.41 | quic-v1 | - | - | ✅ | 4s | - | - |
| zig-v0.0.1 x go-v0.42 (quic-v1) | zig-v0.0.1 | go-v0.42 | quic-v1 | - | - | ✅ | 5s | - | - |
| zig-v0.0.1 x go-v0.43 (quic-v1) | zig-v0.0.1 | go-v0.43 | quic-v1 | - | - | ✅ | 5s | - | - |
| zig-v0.0.1 x go-v0.44 (quic-v1) | zig-v0.0.1 | go-v0.44 | quic-v1 | - | - | ✅ | 4s | - | - |
| zig-v0.0.1 x go-v0.45 (quic-v1) | zig-v0.0.1 | go-v0.45 | quic-v1 | - | - | ✅ | 5s | - | - |
| zig-v0.0.1 x zig-v0.0.1 (quic-v1) | zig-v0.0.1 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 5s | - | - |
| zig-v0.0.1 x eth-p2p-z-v0.0.1 (quic-v1) | zig-v0.0.1 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 4s | - | - |
| eth-p2p-z-v0.0.1 x rust-v0.53 (quic-v1) | eth-p2p-z-v0.0.1 | rust-v0.53 | quic-v1 | - | - | ✅ | 5s | - | - |
| eth-p2p-z-v0.0.1 x rust-v0.54 (quic-v1) | eth-p2p-z-v0.0.1 | rust-v0.54 | quic-v1 | - | - | ✅ | 5s | - | - |
| eth-p2p-z-v0.0.1 x rust-v0.55 (quic-v1) | eth-p2p-z-v0.0.1 | rust-v0.55 | quic-v1 | - | - | ✅ | 5s | - | - |
| zig-v0.0.1 x jvm-v1.2 (quic-v1) | zig-v0.0.1 | jvm-v1.2 | quic-v1 | - | - | ✅ | 10s | - | - |
| eth-p2p-z-v0.0.1 x rust-v0.56 (quic-v1) | eth-p2p-z-v0.0.1 | rust-v0.56 | quic-v1 | - | - | ✅ | 4s | - | - |
| eth-p2p-z-v0.0.1 x go-v0.38 (quic-v1) | eth-p2p-z-v0.0.1 | go-v0.38 | quic-v1 | - | - | ✅ | 4s | - | - |
| eth-p2p-z-v0.0.1 x go-v0.39 (quic-v1) | eth-p2p-z-v0.0.1 | go-v0.39 | quic-v1 | - | - | ✅ | 5s | - | - |
| eth-p2p-z-v0.0.1 x go-v0.40 (quic-v1) | eth-p2p-z-v0.0.1 | go-v0.40 | quic-v1 | - | - | ✅ | 4s | - | - |
| zig-v0.0.1 x python-v0.4 (quic-v1) | zig-v0.0.1 | python-v0.4 | quic-v1 | - | - | ✅ | 15s | - | - |
| eth-p2p-z-v0.0.1 x go-v0.41 (quic-v1) | eth-p2p-z-v0.0.1 | go-v0.41 | quic-v1 | - | - | ✅ | 5s | - | - |
| eth-p2p-z-v0.0.1 x go-v0.42 (quic-v1) | eth-p2p-z-v0.0.1 | go-v0.42 | quic-v1 | - | - | ✅ | 4s | - | - |
| zig-v0.0.1 x c-v0.0.1 (quic-v1) | zig-v0.0.1 | c-v0.0.1 | quic-v1 | - | - | ✅ | 16s | - | - |
| eth-p2p-z-v0.0.1 x go-v0.43 (quic-v1) | eth-p2p-z-v0.0.1 | go-v0.43 | quic-v1 | - | - | ✅ | 5s | - | - |
| eth-p2p-z-v0.0.1 x go-v0.44 (quic-v1) | eth-p2p-z-v0.0.1 | go-v0.44 | quic-v1 | - | - | ✅ | 5s | - | - |
| eth-p2p-z-v0.0.1 x go-v0.45 (quic-v1) | eth-p2p-z-v0.0.1 | go-v0.45 | quic-v1 | - | - | ✅ | 4s | - | - |
| eth-p2p-z-v0.0.1 x python-v0.4 (quic-v1) | eth-p2p-z-v0.0.1 | python-v0.4 | quic-v1 | - | - | ✅ | 6s | - | - |
| eth-p2p-z-v0.0.1 x c-v0.0.1 (quic-v1) | eth-p2p-z-v0.0.1 | c-v0.0.1 | quic-v1 | - | - | ✅ | 5s | - | - |
| eth-p2p-z-v0.0.1 x eth-p2p-z-v0.0.1 (quic-v1) | eth-p2p-z-v0.0.1 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 5s | - | - |
| eth-p2p-z-v0.0.1 x jvm-v1.2 (quic-v1) | eth-p2p-z-v0.0.1 | jvm-v1.2 | quic-v1 | - | - | ✅ | 10s | - | - |
| chromium-js-v1.x x rust-v0.53 (webrtc-direct) | chromium-js-v1.x | rust-v0.53 | webrtc-direct | - | - | ✅ | 23s | 373 | 42 |
| chromium-js-v1.x x rust-v0.54 (webrtc-direct) | chromium-js-v1.x | rust-v0.54 | webrtc-direct | - | - | ✅ | 23s | 295 | 32 |
| chromium-js-v1.x x rust-v0.55 (webrtc-direct) | chromium-js-v1.x | rust-v0.55 | webrtc-direct | - | - | ✅ | 23s | 336 | 30 |
| chromium-js-v1.x x rust-v0.56 (webrtc-direct) | chromium-js-v1.x | rust-v0.56 | webrtc-direct | - | - | ✅ | 22s | 365 | 37 |
| chromium-js-v1.x x go-v0.38 (webtransport) | chromium-js-v1.x | go-v0.38 | webtransport | - | - | ✅ | 23s | 148 | 39 |
| chromium-js-v1.x x go-v0.38 (wss, noise, yamux) | chromium-js-v1.x | go-v0.38 | wss | noise | yamux | ✅ | 22s | 183 | 35 |
| chromium-js-v1.x x go-v0.38 (webrtc-direct) | chromium-js-v1.x | go-v0.38 | webrtc-direct | - | - | ✅ | 21s | 222 | 23 |
| chromium-js-v1.x x go-v0.39 (webtransport) | chromium-js-v1.x | go-v0.39 | webtransport | - | - | ✅ | 22s | 193 | 36 |
| chromium-js-v1.x x go-v0.39 (wss, noise, yamux) | chromium-js-v1.x | go-v0.39 | wss | noise | yamux | ✅ | 22s | 218 | 54 |
| chromium-js-v1.x x go-v0.39 (webrtc-direct) | chromium-js-v1.x | go-v0.39 | webrtc-direct | - | - | ✅ | 23s | 324 | 68 |
| chromium-js-v1.x x go-v0.40 (webtransport) | chromium-js-v1.x | go-v0.40 | webtransport | - | - | ✅ | 23s | 153 | 38 |
| chromium-js-v1.x x go-v0.40 (wss, noise, yamux) | chromium-js-v1.x | go-v0.40 | wss | noise | yamux | ✅ | 23s | 240 | 51 |
| chromium-js-v1.x x go-v0.40 (webrtc-direct) | chromium-js-v1.x | go-v0.40 | webrtc-direct | - | - | ✅ | 22s | 218 | 36 |
| chromium-js-v1.x x go-v0.41 (webtransport) | chromium-js-v1.x | go-v0.41 | webtransport | - | - | ✅ | 22s | 111 | 27 |
| chromium-js-v1.x x go-v0.41 (wss, noise, yamux) | chromium-js-v1.x | go-v0.41 | wss | noise | yamux | ✅ | 23s | 284 | 45 |
| chromium-js-v1.x x go-v0.41 (webrtc-direct) | chromium-js-v1.x | go-v0.41 | webrtc-direct | - | - | ✅ | 24s | 338 | 38 |
| chromium-js-v1.x x go-v0.42 (webtransport) | chromium-js-v1.x | go-v0.42 | webtransport | - | - | ✅ | 23s | 174 | 35 |
| chromium-js-v1.x x go-v0.42 (wss, noise, yamux) | chromium-js-v1.x | go-v0.42 | wss | noise | yamux | ✅ | 24s | 233 | 46 |
| chromium-js-v1.x x go-v0.42 (webrtc-direct) | chromium-js-v1.x | go-v0.42 | webrtc-direct | - | - | ✅ | 23s | 235 | 33 |
| chromium-js-v1.x x go-v0.43 (webtransport) | chromium-js-v1.x | go-v0.43 | webtransport | - | - | ✅ | 22s | 186 | 48 |
| chromium-js-v1.x x go-v0.43 (wss, noise, yamux) | chromium-js-v1.x | go-v0.43 | wss | noise | yamux | ✅ | 22s | 182 | 35 |
| chromium-js-v1.x x go-v0.43 (webrtc-direct) | chromium-js-v1.x | go-v0.43 | webrtc-direct | - | - | ✅ | 23s | 313 | 60 |
| chromium-js-v1.x x go-v0.44 (webtransport) | chromium-js-v1.x | go-v0.44 | webtransport | - | - | ✅ | 24s | 215 | 45 |
| chromium-js-v1.x x go-v0.44 (wss, noise, yamux) | chromium-js-v1.x | go-v0.44 | wss | noise | yamux | ✅ | 23s | 301 | 65 |
| chromium-js-v1.x x go-v0.44 (webrtc-direct) | chromium-js-v1.x | go-v0.44 | webrtc-direct | - | - | ✅ | 24s | 288 | 40 |
| chromium-js-v1.x x go-v0.45 (webtransport) | chromium-js-v1.x | go-v0.45 | webtransport | - | - | ✅ | 23s | 189 | 53 |
| chromium-js-v1.x x go-v0.45 (wss, noise, yamux) | chromium-js-v1.x | go-v0.45 | wss | noise | yamux | ✅ | 24s | 150 | 29 |
| chromium-js-v1.x x go-v0.45 (webrtc-direct) | chromium-js-v1.x | go-v0.45 | webrtc-direct | - | - | ✅ | 23s | 278 | 27 |
| chromium-js-v1.x x python-v0.4 (wss, noise, yamux) | chromium-js-v1.x | python-v0.4 | wss | noise | yamux | ✅ | 36s | 600 | 154 |
| chromium-js-v1.x x python-v0.4 (wss, noise, mplex) | chromium-js-v1.x | python-v0.4 | wss | noise | mplex | ✅ | 37s | 539 | 144 |
| chromium-js-v1.x x chromium-js-v1.x (webrtc) | chromium-js-v1.x | chromium-js-v1.x | webrtc | - | - | ✅ | 38s | 1331 | 123 |
| chromium-js-v1.x x chromium-js-v2.x (webrtc) | chromium-js-v1.x | chromium-js-v2.x | webrtc | - | - | ✅ | 41s | 555 | 49 |
| chromium-js-v1.x x firefox-js-v1.x (webrtc) | chromium-js-v1.x | firefox-js-v1.x | webrtc | - | - | ✅ | 42s | 1221 | 110 |
| chromium-js-v1.x x webkit-js-v1.x (webrtc) | chromium-js-v1.x | webkit-js-v1.x | webrtc | - | - | ✅ | 44s | 898 | 103 |
| chromium-js-v1.x x firefox-js-v2.x (webrtc) | chromium-js-v1.x | firefox-js-v2.x | webrtc | - | - | ✅ | 44s | 948 | 74 |
| chromium-js-v2.x x rust-v0.53 (webrtc-direct) | chromium-js-v2.x | rust-v0.53 | webrtc-direct | - | - | ✅ | 27s | 388 | 65 |
| chromium-js-v2.x x rust-v0.54 (webrtc-direct) | chromium-js-v2.x | rust-v0.54 | webrtc-direct | - | - | ✅ | 28s | 383 | 54 |
| chromium-js-v1.x x webkit-js-v2.x (webrtc) | chromium-js-v1.x | webkit-js-v2.x | webrtc | - | - | ✅ | 29s | 926 | 136 |
| chromium-js-v2.x x rust-v0.55 (webrtc-direct) | chromium-js-v2.x | rust-v0.55 | webrtc-direct | - | - | ✅ | 27s | 257 | 31 |
| chromium-js-v2.x x rust-v0.56 (webrtc-direct) | chromium-js-v2.x | rust-v0.56 | webrtc-direct | - | - | ✅ | 27s | 269 | 22 |
| chromium-js-v2.x x go-v0.38 (wss, noise, yamux) | chromium-js-v2.x | go-v0.38 | wss | noise | yamux | ✅ | 24s | 267 | 76 |
| chromium-js-v2.x x go-v0.38 (webtransport) | chromium-js-v2.x | go-v0.38 | webtransport | - | - | ✅ | 26s | 239 | 49 |
| chromium-js-v2.x x go-v0.38 (webrtc-direct) | chromium-js-v2.x | go-v0.38 | webrtc-direct | - | - | ✅ | 23s | 314 | 46 |
| chromium-js-v2.x x go-v0.39 (webtransport) | chromium-js-v2.x | go-v0.39 | webtransport | - | - | ✅ | 24s | 214 | 59 |
| chromium-js-v2.x x go-v0.39 (wss, noise, yamux) | chromium-js-v2.x | go-v0.39 | wss | noise | yamux | ✅ | 25s | 287 | 77 |
| eth-p2p-z-v0.0.1 x zig-v0.0.1 (quic-v1) | eth-p2p-z-v0.0.1 | zig-v0.0.1 | quic-v1 | - | - | ❌ | 194s | - | - |
| chromium-js-v2.x x go-v0.39 (webrtc-direct) | chromium-js-v2.x | go-v0.39 | webrtc-direct | - | - | ✅ | 25s | 343 | 60 |
| chromium-js-v2.x x go-v0.40 (webtransport) | chromium-js-v2.x | go-v0.40 | webtransport | - | - | ✅ | 25s | 230 | 60 |
| chromium-js-v2.x x go-v0.40 (wss, noise, yamux) | chromium-js-v2.x | go-v0.40 | wss | noise | yamux | ✅ | 25s | 314 | 82 |
| chromium-js-v2.x x go-v0.40 (webrtc-direct) | chromium-js-v2.x | go-v0.40 | webrtc-direct | - | - | ✅ | 24s | 221 | 19 |
| chromium-js-v2.x x go-v0.41 (webtransport) | chromium-js-v2.x | go-v0.41 | webtransport | - | - | ✅ | 26s | 238 | 59 |
| chromium-js-v2.x x go-v0.41 (wss, noise, yamux) | chromium-js-v2.x | go-v0.41 | wss | noise | yamux | ✅ | 28s | 344 | 82 |
| chromium-js-v2.x x go-v0.41 (webrtc-direct) | chromium-js-v2.x | go-v0.41 | webrtc-direct | - | - | ✅ | 27s | 334 | 75 |
| chromium-js-v2.x x go-v0.42 (wss, noise, yamux) | chromium-js-v2.x | go-v0.42 | wss | noise | yamux | ✅ | 28s | 297 | 63 |
| chromium-js-v2.x x go-v0.42 (webtransport) | chromium-js-v2.x | go-v0.42 | webtransport | - | - | ✅ | 28s | 192 | 56 |
| chromium-js-v2.x x go-v0.42 (webrtc-direct) | chromium-js-v2.x | go-v0.42 | webrtc-direct | - | - | ✅ | 27s | 260 | 51 |
| chromium-js-v2.x x go-v0.43 (webtransport) | chromium-js-v2.x | go-v0.43 | webtransport | - | - | ✅ | 27s | 188 | 46 |
| chromium-js-v2.x x go-v0.43 (wss, noise, yamux) | chromium-js-v2.x | go-v0.43 | wss | noise | yamux | ✅ | 27s | 229 | 73 |
| chromium-js-v2.x x go-v0.43 (webrtc-direct) | chromium-js-v2.x | go-v0.43 | webrtc-direct | - | - | ✅ | 28s | 364 | 66 |
| chromium-js-v2.x x go-v0.44 (webtransport) | chromium-js-v2.x | go-v0.44 | webtransport | - | - | ✅ | 27s | 236 | 68 |
| chromium-js-v2.x x go-v0.44 (wss, noise, yamux) | chromium-js-v2.x | go-v0.44 | wss | noise | yamux | ✅ | 29s | 362 | 81 |
| chromium-js-v2.x x go-v0.45 (webtransport) | chromium-js-v2.x | go-v0.45 | webtransport | - | - | ✅ | 29s | 307 | 79 |
| chromium-js-v2.x x go-v0.44 (webrtc-direct) | chromium-js-v2.x | go-v0.44 | webrtc-direct | - | - | ✅ | 29s | 331 | 59 |
| chromium-js-v2.x x go-v0.45 (wss, noise, yamux) | chromium-js-v2.x | go-v0.45 | wss | noise | yamux | ✅ | 29s | 310 | 82 |
| chromium-js-v2.x x go-v0.45 (webrtc-direct) | chromium-js-v2.x | go-v0.45 | webrtc-direct | - | - | ✅ | 28s | 272 | 24 |
| chromium-js-v2.x x python-v0.4 (wss, noise, mplex) | chromium-js-v2.x | python-v0.4 | wss | noise | mplex | ✅ | 28s | 178 | 31 |
| chromium-js-v2.x x python-v0.4 (wss, noise, yamux) | chromium-js-v2.x | python-v0.4 | wss | noise | yamux | ✅ | 42s | 856 | 309 |
| chromium-js-v2.x x chromium-js-v1.x (webrtc) | chromium-js-v2.x | chromium-js-v1.x | webrtc | - | - | ✅ | 47s | 1588 | 156 |
| chromium-js-v2.x x chromium-js-v2.x (webrtc) | chromium-js-v2.x | chromium-js-v2.x | webrtc | - | - | ✅ | 47s | 1261 | 124 |
| chromium-js-v2.x x webkit-js-v1.x (webrtc) | chromium-js-v2.x | webkit-js-v1.x | webrtc | - | - | ✅ | 49s | 1094 | 69 |
| chromium-js-v2.x x webkit-js-v2.x (webrtc) | chromium-js-v2.x | webkit-js-v2.x | webrtc | - | - | ✅ | 49s | 849 | 43 |
| chromium-js-v2.x x firefox-js-v1.x (webrtc) | chromium-js-v2.x | firefox-js-v1.x | webrtc | - | - | ✅ | 52s | 1076 | 58 |
| chromium-js-v2.x x firefox-js-v2.x (webrtc) | chromium-js-v2.x | firefox-js-v2.x | webrtc | - | - | ✅ | 53s | 765 | 79 |
| firefox-js-v1.x x rust-v0.53 (webrtc-direct) | firefox-js-v1.x | rust-v0.53 | webrtc-direct | - | - | ✅ | 51s | 1450 | 75 |
| firefox-js-v1.x x rust-v0.54 (webrtc-direct) | firefox-js-v1.x | rust-v0.54 | webrtc-direct | - | - | ✅ | 33s | 1621 | 96 |
| firefox-js-v1.x x rust-v0.55 (webrtc-direct) | firefox-js-v1.x | rust-v0.55 | webrtc-direct | - | - | ✅ | 33s | 1592 | 61 |
| firefox-js-v1.x x rust-v0.56 (webrtc-direct) | firefox-js-v1.x | rust-v0.56 | webrtc-direct | - | - | ✅ | 33s | 1494 | 59 |
| firefox-js-v1.x x go-v0.38 (webtransport) | firefox-js-v1.x | go-v0.38 | webtransport | - | - | ❌ | 31s | - | - |
| firefox-js-v1.x x go-v0.38 (webrtc-direct) | firefox-js-v1.x | go-v0.38 | webrtc-direct | - | - | ✅ | 32s | 268 | 70 |
| firefox-js-v1.x x go-v0.38 (wss, noise, yamux) | firefox-js-v1.x | go-v0.38 | wss | noise | yamux | ✅ | 32s | 311 | 139 |
| firefox-js-v1.x x go-v0.39 (webtransport) | firefox-js-v1.x | go-v0.39 | webtransport | - | - | ❌ | 31s | - | - |
| firefox-js-v1.x x go-v0.39 (wss, noise, yamux) | firefox-js-v1.x | go-v0.39 | wss | noise | yamux | ✅ | 32s | 250 | 104 |
| firefox-js-v1.x x go-v0.39 (webrtc-direct) | firefox-js-v1.x | go-v0.39 | webrtc-direct | - | - | ✅ | 30s | 444 | 105 |
| firefox-js-v1.x x go-v0.40 (webtransport) | firefox-js-v1.x | go-v0.40 | webtransport | - | - | ❌ | 31s | - | - |
| firefox-js-v1.x x go-v0.40 (wss, noise, yamux) | firefox-js-v1.x | go-v0.40 | wss | noise | yamux | ✅ | 32s | 382 | 149 |
| firefox-js-v1.x x go-v0.40 (webrtc-direct) | firefox-js-v1.x | go-v0.40 | webrtc-direct | - | - | ✅ | 33s | 474 | 85 |
| firefox-js-v1.x x go-v0.41 (webtransport) | firefox-js-v1.x | go-v0.41 | webtransport | - | - | ❌ | 32s | - | - |
| firefox-js-v1.x x go-v0.41 (wss, noise, yamux) | firefox-js-v1.x | go-v0.41 | wss | noise | yamux | ✅ | 32s | 278 | 126 |
| firefox-js-v1.x x go-v0.42 (webtransport) | firefox-js-v1.x | go-v0.42 | webtransport | - | - | ❌ | 31s | - | - |
| firefox-js-v1.x x go-v0.41 (webrtc-direct) | firefox-js-v1.x | go-v0.41 | webrtc-direct | - | - | ✅ | 32s | 294 | 74 |
| firefox-js-v1.x x go-v0.42 (wss, noise, yamux) | firefox-js-v1.x | go-v0.42 | wss | noise | yamux | ✅ | 30s | 356 | 143 |
| firefox-js-v1.x x go-v0.42 (webrtc-direct) | firefox-js-v1.x | go-v0.42 | webrtc-direct | - | - | ✅ | 30s | 343 | 86 |
| firefox-js-v1.x x go-v0.43 (webtransport) | firefox-js-v1.x | go-v0.43 | webtransport | - | - | ❌ | 31s | - | - |
| firefox-js-v1.x x go-v0.43 (wss, noise, yamux) | firefox-js-v1.x | go-v0.43 | wss | noise | yamux | ✅ | 32s | 330 | 148 |
| firefox-js-v1.x x go-v0.43 (webrtc-direct) | firefox-js-v1.x | go-v0.43 | webrtc-direct | - | - | ✅ | 32s | 343 | 75 |
| firefox-js-v1.x x go-v0.44 (webtransport) | firefox-js-v1.x | go-v0.44 | webtransport | - | - | ❌ | 31s | - | - |
| firefox-js-v1.x x go-v0.44 (wss, noise, yamux) | firefox-js-v1.x | go-v0.44 | wss | noise | yamux | ✅ | 32s | 265 | 114 |
| firefox-js-v1.x x go-v0.44 (webrtc-direct) | firefox-js-v1.x | go-v0.44 | webrtc-direct | - | - | ✅ | 32s | 328 | 85 |
| firefox-js-v1.x x go-v0.45 (webtransport) | firefox-js-v1.x | go-v0.45 | webtransport | - | - | ❌ | 35s | - | - |
| firefox-js-v1.x x go-v0.45 (wss, noise, yamux) | firefox-js-v1.x | go-v0.45 | wss | noise | yamux | ✅ | 40s | 707 | 347 |
| firefox-js-v1.x x go-v0.45 (webrtc-direct) | firefox-js-v1.x | go-v0.45 | webrtc-direct | - | - | ✅ | 42s | 806 | 149 |
| firefox-js-v1.x x python-v0.4 (wss, noise, mplex) | firefox-js-v1.x | python-v0.4 | wss | noise | mplex | ✅ | 43s | 786 | 213 |
| firefox-js-v1.x x python-v0.4 (wss, noise, yamux) | firefox-js-v1.x | python-v0.4 | wss | noise | yamux | ✅ | 44s | 616 | 286 |
| firefox-js-v1.x x chromium-js-v1.x (webrtc) | firefox-js-v1.x | chromium-js-v1.x | webrtc | - | - | ✅ | 47s | 2468 | 187 |
| firefox-js-v1.x x chromium-js-v2.x (webrtc) | firefox-js-v1.x | chromium-js-v2.x | webrtc | - | - | ✅ | 48s | 2198 | 280 |
| firefox-js-v1.x x firefox-js-v1.x (webrtc) | firefox-js-v1.x | firefox-js-v1.x | webrtc | - | - | ✅ | 48s | 2437 | 258 |
| firefox-js-v1.x x firefox-js-v2.x (webrtc) | firefox-js-v1.x | firefox-js-v2.x | webrtc | - | - | ✅ | 50s | 2693 | 314 |
| firefox-js-v1.x x webkit-js-v1.x (webrtc) | firefox-js-v1.x | webkit-js-v1.x | webrtc | - | - | ✅ | 43s | 2268 | 319 |
| firefox-js-v1.x x webkit-js-v2.x (webrtc) | firefox-js-v1.x | webkit-js-v2.x | webrtc | - | - | ✅ | 42s | 1535 | 129 |
| firefox-js-v2.x x rust-v0.54 (webrtc-direct) | firefox-js-v2.x | rust-v0.54 | webrtc-direct | - | - | ✅ | 42s | 1467 | 51 |
| firefox-js-v2.x x rust-v0.53 (webrtc-direct) | firefox-js-v2.x | rust-v0.53 | webrtc-direct | - | - | ✅ | 44s | 1494 | 74 |
| firefox-js-v2.x x rust-v0.55 (webrtc-direct) | firefox-js-v2.x | rust-v0.55 | webrtc-direct | - | - | ✅ | 40s | 1494 | 63 |
| firefox-js-v2.x x go-v0.38 (webtransport) | firefox-js-v2.x | go-v0.38 | webtransport | - | - | ❌ | 37s | - | - |
| firefox-js-v2.x x rust-v0.56 (webrtc-direct) | firefox-js-v2.x | rust-v0.56 | webrtc-direct | - | - | ✅ | 40s | 1508 | 43 |
| firefox-js-v2.x x go-v0.38 (wss, noise, yamux) | firefox-js-v2.x | go-v0.38 | wss | noise | yamux | ✅ | 33s | 421 | 198 |
| firefox-js-v2.x x go-v0.38 (webrtc-direct) | firefox-js-v2.x | go-v0.38 | webrtc-direct | - | - | ✅ | 32s | 456 | 71 |
| firefox-js-v2.x x go-v0.39 (webtransport) | firefox-js-v2.x | go-v0.39 | webtransport | - | - | ❌ | 33s | - | - |
| firefox-js-v2.x x go-v0.39 (wss, noise, yamux) | firefox-js-v2.x | go-v0.39 | wss | noise | yamux | ✅ | 33s | 289 | 139 |
| firefox-js-v2.x x go-v0.39 (webrtc-direct) | firefox-js-v2.x | go-v0.39 | webrtc-direct | - | - | ✅ | 35s | 392 | 46 |
| firefox-js-v2.x x go-v0.40 (webtransport) | firefox-js-v2.x | go-v0.40 | webtransport | - | - | ❌ | 34s | - | - |
| firefox-js-v2.x x go-v0.40 (wss, noise, yamux) | firefox-js-v2.x | go-v0.40 | wss | noise | yamux | ✅ | 35s | 310 | 123 |
| firefox-js-v2.x x go-v0.40 (webrtc-direct) | firefox-js-v2.x | go-v0.40 | webrtc-direct | - | - | ✅ | 34s | 349 | 42 |
| firefox-js-v2.x x go-v0.41 (webtransport) | firefox-js-v2.x | go-v0.41 | webtransport | - | - | ❌ | 33s | - | - |
| firefox-js-v2.x x go-v0.41 (wss, noise, yamux) | firefox-js-v2.x | go-v0.41 | wss | noise | yamux | ✅ | 32s | 381 | 187 |
| firefox-js-v2.x x go-v0.41 (webrtc-direct) | firefox-js-v2.x | go-v0.41 | webrtc-direct | - | - | ✅ | 33s | 376 | 55 |
| firefox-js-v2.x x go-v0.42 (webtransport) | firefox-js-v2.x | go-v0.42 | webtransport | - | - | ❌ | 34s | - | - |
| firefox-js-v2.x x go-v0.42 (wss, noise, yamux) | firefox-js-v2.x | go-v0.42 | wss | noise | yamux | ✅ | 35s | 390 | 181 |
| firefox-js-v2.x x go-v0.42 (webrtc-direct) | firefox-js-v2.x | go-v0.42 | webrtc-direct | - | - | ✅ | 35s | 488 | 66 |
| firefox-js-v2.x x go-v0.43 (webtransport) | firefox-js-v2.x | go-v0.43 | webtransport | - | - | ❌ | 34s | - | - |
| firefox-js-v2.x x go-v0.43 (wss, noise, yamux) | firefox-js-v2.x | go-v0.43 | wss | noise | yamux | ✅ | 34s | 280 | 117 |
| firefox-js-v2.x x go-v0.43 (webrtc-direct) | firefox-js-v2.x | go-v0.43 | webrtc-direct | - | - | ✅ | 34s | 284 | 60 |
| firefox-js-v2.x x go-v0.44 (webtransport) | firefox-js-v2.x | go-v0.44 | webtransport | - | - | ❌ | 34s | - | - |
| firefox-js-v2.x x go-v0.44 (wss, noise, yamux) | firefox-js-v2.x | go-v0.44 | wss | noise | yamux | ✅ | 34s | 400 | 169 |
| firefox-js-v2.x x go-v0.44 (webrtc-direct) | firefox-js-v2.x | go-v0.44 | webrtc-direct | - | - | ✅ | 37s | 465 | 67 |
| firefox-js-v2.x x go-v0.45 (webtransport) | firefox-js-v2.x | go-v0.45 | webtransport | - | - | ❌ | 35s | - | - |
| firefox-js-v2.x x go-v0.45 (wss, noise, yamux) | firefox-js-v2.x | go-v0.45 | wss | noise | yamux | ✅ | 37s | 479 | 210 |
| firefox-js-v2.x x go-v0.45 (webrtc-direct) | firefox-js-v2.x | go-v0.45 | webrtc-direct | - | - | ✅ | 37s | 420 | 47 |
| firefox-js-v2.x x python-v0.4 (wss, noise, mplex) | firefox-js-v2.x | python-v0.4 | wss | noise | mplex | ✅ | 38s | 305 | 75 |
| firefox-js-v2.x x python-v0.4 (wss, noise, yamux) | firefox-js-v2.x | python-v0.4 | wss | noise | yamux | ✅ | 47s | 678 | 325 |
| firefox-js-v2.x x chromium-js-v1.x (webrtc) | firefox-js-v2.x | chromium-js-v1.x | webrtc | - | - | ✅ | 51s | 2660 | 158 |
| firefox-js-v2.x x chromium-js-v2.x (webrtc) | firefox-js-v2.x | chromium-js-v2.x | webrtc | - | - | ✅ | 54s | 2038 | 221 |
| webkit-js-v1.x x rust-v0.53 (webrtc-direct) | webkit-js-v1.x | rust-v0.53 | webrtc-direct | - | - | ✅ | 43s | 1019 | 134 |
| firefox-js-v2.x x firefox-js-v1.x (webrtc) | firefox-js-v2.x | firefox-js-v1.x | webrtc | - | - | ✅ | 55s | 1426 | 112 |
| firefox-js-v2.x x webkit-js-v1.x (webrtc) | firefox-js-v2.x | webkit-js-v1.x | webrtc | - | - | ✅ | 53s | 2011 | 214 |
| firefox-js-v2.x x firefox-js-v2.x (webrtc) | firefox-js-v2.x | firefox-js-v2.x | webrtc | - | - | ✅ | 55s | 1628 | 162 |
| firefox-js-v2.x x webkit-js-v2.x (webrtc) | firefox-js-v2.x | webkit-js-v2.x | webrtc | - | - | ✅ | 52s | 1268 | 179 |
| webkit-js-v1.x x rust-v0.54 (webrtc-direct) | webkit-js-v1.x | rust-v0.54 | webrtc-direct | - | - | ✅ | 33s | 462 | 71 |
| webkit-js-v1.x x rust-v0.55 (webrtc-direct) | webkit-js-v1.x | rust-v0.55 | webrtc-direct | - | - | ✅ | 30s | 552 | 69 |
| webkit-js-v1.x x rust-v0.56 (webrtc-direct) | webkit-js-v1.x | rust-v0.56 | webrtc-direct | - | - | ✅ | 28s | 649 | 133 |
| webkit-js-v1.x x go-v0.38 (wss, noise, yamux) | webkit-js-v1.x | go-v0.38 | wss | noise | yamux | ✅ | 26s | 423 | 111 |
| webkit-js-v1.x x go-v0.38 (webrtc-direct) | webkit-js-v1.x | go-v0.38 | webrtc-direct | - | - | ✅ | 26s | 622 | 68 |
| webkit-js-v1.x x go-v0.39 (wss, noise, yamux) | webkit-js-v1.x | go-v0.39 | wss | noise | yamux | ✅ | 27s | 571 | 167 |
| webkit-js-v1.x x go-v0.39 (webrtc-direct) | webkit-js-v1.x | go-v0.39 | webrtc-direct | - | - | ✅ | 26s | 464 | 98 |
| webkit-js-v1.x x go-v0.40 (wss, noise, yamux) | webkit-js-v1.x | go-v0.40 | wss | noise | yamux | ✅ | 26s | 428 | 126 |
| webkit-js-v1.x x go-v0.40 (webrtc-direct) | webkit-js-v1.x | go-v0.40 | webrtc-direct | - | - | ✅ | 25s | 473 | 112 |
| webkit-js-v1.x x go-v0.41 (wss, noise, yamux) | webkit-js-v1.x | go-v0.41 | wss | noise | yamux | ✅ | 25s | 453 | 166 |
| webkit-js-v1.x x go-v0.41 (webrtc-direct) | webkit-js-v1.x | go-v0.41 | webrtc-direct | - | - | ✅ | 27s | 624 | 196 |
| webkit-js-v1.x x go-v0.42 (wss, noise, yamux) | webkit-js-v1.x | go-v0.42 | wss | noise | yamux | ✅ | 26s | 549 | 168 |
| webkit-js-v1.x x go-v0.42 (webrtc-direct) | webkit-js-v1.x | go-v0.42 | webrtc-direct | - | - | ✅ | 27s | 591 | 96 |
| webkit-js-v1.x x go-v0.43 (wss, noise, yamux) | webkit-js-v1.x | go-v0.43 | wss | noise | yamux | ✅ | 27s | 404 | 97 |
| webkit-js-v1.x x go-v0.43 (webrtc-direct) | webkit-js-v1.x | go-v0.43 | webrtc-direct | - | - | ✅ | 27s | 473 | 83 |
| webkit-js-v1.x x go-v0.44 (wss, noise, yamux) | webkit-js-v1.x | go-v0.44 | wss | noise | yamux | ✅ | 27s | 536 | 179 |
| webkit-js-v1.x x go-v0.44 (webrtc-direct) | webkit-js-v1.x | go-v0.44 | webrtc-direct | - | - | ✅ | 26s | 515 | 124 |
| webkit-js-v1.x x go-v0.45 (wss, noise, yamux) | webkit-js-v1.x | go-v0.45 | wss | noise | yamux | ✅ | 26s | 483 | 114 |
| webkit-js-v1.x x go-v0.45 (webrtc-direct) | webkit-js-v1.x | go-v0.45 | webrtc-direct | - | - | ✅ | 35s | 692 | 134 |
| webkit-js-v1.x x python-v0.4 (wss, noise, mplex) | webkit-js-v1.x | python-v0.4 | wss | noise | mplex | ✅ | 37s | 992 | 223 |
| webkit-js-v1.x x python-v0.4 (wss, noise, yamux) | webkit-js-v1.x | python-v0.4 | wss | noise | yamux | ✅ | 40s | 967 | 182 |
| webkit-js-v1.x x chromium-js-v1.x (webrtc) | webkit-js-v1.x | chromium-js-v1.x | webrtc | - | - | ✅ | 43s | 2412 | 164 |
| webkit-js-v1.x x chromium-js-v2.x (webrtc) | webkit-js-v1.x | chromium-js-v2.x | webrtc | - | - | ✅ | 46s | 2087 | 269 |
| webkit-js-v1.x x firefox-js-v1.x (webrtc) | webkit-js-v1.x | firefox-js-v1.x | webrtc | - | - | ❌ | 51s | - | - |
| webkit-js-v1.x x webkit-js-v1.x (webrtc) | webkit-js-v1.x | webkit-js-v1.x | webrtc | - | - | ✅ | 45s | 1875 | 352 |
| webkit-js-v1.x x firefox-js-v2.x (webrtc) | webkit-js-v1.x | firefox-js-v2.x | webrtc | - | - | ✅ | 53s | 1805 | 232 |
| webkit-js-v1.x x webkit-js-v2.x (webrtc) | webkit-js-v1.x | webkit-js-v2.x | webrtc | - | - | ✅ | 38s | 1704 | 191 |
| webkit-js-v2.x x rust-v0.53 (webrtc-direct) | webkit-js-v2.x | rust-v0.53 | webrtc-direct | - | - | ✅ | 35s | 1501 | 73 |
| webkit-js-v2.x x rust-v0.54 (webrtc-direct) | webkit-js-v2.x | rust-v0.54 | webrtc-direct | - | - | ✅ | 33s | 1493 | 99 |
| webkit-js-v2.x x rust-v0.55 (webrtc-direct) | webkit-js-v2.x | rust-v0.55 | webrtc-direct | - | - | ✅ | 32s | 1543 | 112 |
| webkit-js-v2.x x rust-v0.56 (webrtc-direct) | webkit-js-v2.x | rust-v0.56 | webrtc-direct | - | - | ✅ | 30s | 565 | 115 |
| webkit-js-v2.x x go-v0.38 (wss, noise, yamux) | webkit-js-v2.x | go-v0.38 | wss | noise | yamux | ✅ | 28s | 448 | 110 |
| webkit-js-v2.x x go-v0.38 (webrtc-direct) | webkit-js-v2.x | go-v0.38 | webrtc-direct | - | - | ✅ | 29s | 468 | 111 |
| webkit-js-v2.x x go-v0.39 (wss, noise, yamux) | webkit-js-v2.x | go-v0.39 | wss | noise | yamux | ✅ | 27s | 379 | 70 |
| webkit-js-v2.x x go-v0.39 (webrtc-direct) | webkit-js-v2.x | go-v0.39 | webrtc-direct | - | - | ✅ | 28s | 501 | 98 |
| webkit-js-v2.x x go-v0.40 (wss, noise, yamux) | webkit-js-v2.x | go-v0.40 | wss | noise | yamux | ✅ | 28s | 439 | 134 |
| webkit-js-v2.x x go-v0.40 (webrtc-direct) | webkit-js-v2.x | go-v0.40 | webrtc-direct | - | - | ✅ | 29s | 537 | 96 |
| webkit-js-v2.x x go-v0.41 (wss, noise, yamux) | webkit-js-v2.x | go-v0.41 | wss | noise | yamux | ✅ | 29s | 496 | 121 |
| webkit-js-v2.x x go-v0.41 (webrtc-direct) | webkit-js-v2.x | go-v0.41 | webrtc-direct | - | - | ✅ | 30s | 444 | 71 |
| webkit-js-v2.x x go-v0.42 (wss, noise, yamux) | webkit-js-v2.x | go-v0.42 | wss | noise | yamux | ✅ | 29s | 544 | 129 |
| webkit-js-v2.x x go-v0.42 (webrtc-direct) | webkit-js-v2.x | go-v0.42 | webrtc-direct | - | - | ✅ | 29s | 510 | 99 |
| webkit-js-v2.x x go-v0.43 (wss, noise, yamux) | webkit-js-v2.x | go-v0.43 | wss | noise | yamux | ✅ | 28s | 463 | 145 |
| webkit-js-v2.x x go-v0.43 (webrtc-direct) | webkit-js-v2.x | go-v0.43 | webrtc-direct | - | - | ✅ | 28s | 518 | 96 |
| webkit-js-v2.x x go-v0.44 (wss, noise, yamux) | webkit-js-v2.x | go-v0.44 | wss | noise | yamux | ✅ | 30s | 505 | 92 |
| webkit-js-v2.x x go-v0.44 (webrtc-direct) | webkit-js-v2.x | go-v0.44 | webrtc-direct | - | - | ✅ | 30s | 576 | 94 |
| webkit-js-v2.x x go-v0.45 (wss, noise, yamux) | webkit-js-v2.x | go-v0.45 | wss | noise | yamux | ✅ | 32s | 737 | 246 |
| webkit-js-v2.x x go-v0.45 (webrtc-direct) | webkit-js-v2.x | go-v0.45 | webrtc-direct | - | - | ✅ | 35s | 778 | 155 |
| webkit-js-v2.x x python-v0.4 (wss, noise, yamux) | webkit-js-v2.x | python-v0.4 | wss | noise | yamux | ✅ | 36s | 983 | 261 |
| webkit-js-v2.x x python-v0.4 (wss, noise, mplex) | webkit-js-v2.x | python-v0.4 | wss | noise | mplex | ✅ | 39s | 925 | 157 |
| webkit-js-v2.x x chromium-js-v1.x (webrtc) | webkit-js-v2.x | chromium-js-v1.x | webrtc | - | - | ✅ | 44s | 2211 | 180 |
| chromium-rust-v0.53 x rust-v0.53 (webrtc-direct) | chromium-rust-v0.53 | rust-v0.53 | webrtc-direct | - | - | ✅ | 9s | 473.2 | 0.2 |
| chromium-rust-v0.53 x rust-v0.53 (ws, noise, mplex) | chromium-rust-v0.53 | rust-v0.53 | ws | noise | mplex | ✅ | 10s | 491.0 | 0.5 |
| webkit-js-v2.x x chromium-js-v2.x (webrtc) | webkit-js-v2.x | chromium-js-v2.x | webrtc | - | - | ✅ | 45s | 1813 | 97 |
| chromium-rust-v0.53 x rust-v0.53 (ws, noise, yamux) | chromium-rust-v0.53 | rust-v0.53 | ws | noise | yamux | ✅ | 10s | 371.699 | 23.299 |
| chromium-rust-v0.53 x rust-v0.54 (webrtc-direct) | chromium-rust-v0.53 | rust-v0.54 | webrtc-direct | - | - | ✅ | 9s | 460.0 | 0.2 |
| chromium-rust-v0.53 x rust-v0.54 (ws, noise, mplex) | chromium-rust-v0.53 | rust-v0.54 | ws | noise | mplex | ✅ | 8s | 496.4 | 0.5 |
| webkit-js-v2.x x firefox-js-v1.x (webrtc) | webkit-js-v2.x | firefox-js-v1.x | webrtc | - | - | ✅ | 48s | 1565 | 228 |
| chromium-rust-v0.53 x rust-v0.54 (ws, noise, yamux) | chromium-rust-v0.53 | rust-v0.54 | ws | noise | yamux | ✅ | 8s | 379.0 | 25.9 |
| chromium-rust-v0.53 x rust-v0.55 (webrtc-direct) | chromium-rust-v0.53 | rust-v0.55 | webrtc-direct | - | - | ✅ | 7s | 436.799 | 0.1 |
| webkit-js-v2.x x firefox-js-v2.x (webrtc) | webkit-js-v2.x | firefox-js-v2.x | webrtc | - | - | ✅ | 50s | 1771 | 92 |
| webkit-js-v2.x x webkit-js-v1.x (webrtc) | webkit-js-v2.x | webkit-js-v1.x | webrtc | - | - | ✅ | 42s | 1849 | 116 |
| chromium-rust-v0.53 x rust-v0.55 (ws, noise, mplex) | chromium-rust-v0.53 | rust-v0.55 | ws | noise | mplex | ✅ | 7s | 422.399 | 0.4 |
| webkit-js-v2.x x webkit-js-v2.x (webrtc) | webkit-js-v2.x | webkit-js-v2.x | webrtc | - | - | ✅ | 38s | 726 | 32 |
| chromium-rust-v0.53 x rust-v0.55 (ws, noise, yamux) | chromium-rust-v0.53 | rust-v0.55 | ws | noise | yamux | ✅ | 6s | 339.7 | 6.7 |
| chromium-rust-v0.53 x rust-v0.56 (webrtc-direct) | chromium-rust-v0.53 | rust-v0.56 | webrtc-direct | - | - | ✅ | 7s | 245.6 | 6.0 |
| chromium-rust-v0.53 x rust-v0.56 (ws, noise, mplex) | chromium-rust-v0.53 | rust-v0.56 | ws | noise | mplex | ✅ | 6s | 425.4 | 0.5 |
| chromium-rust-v0.53 x go-v0.38 (webtransport) | chromium-rust-v0.53 | go-v0.38 | webtransport | - | - | ✅ | 5s | 84.0 | 2.1 |
| chromium-rust-v0.53 x rust-v0.56 (ws, noise, yamux) | chromium-rust-v0.53 | rust-v0.56 | ws | noise | yamux | ✅ | 6s | 326.0 | 8.5 |
| chromium-rust-v0.53 x go-v0.38 (webrtc-direct) | chromium-rust-v0.53 | go-v0.38 | webrtc-direct | - | - | ✅ | 5s | 174.3 | 0.2 |
| chromium-rust-v0.53 x go-v0.38 (ws, noise, yamux) | chromium-rust-v0.53 | go-v0.38 | ws | noise | yamux | ✅ | 5s | 327.3 | 4.3 |
| chromium-rust-v0.53 x go-v0.39 (webtransport) | chromium-rust-v0.53 | go-v0.39 | webtransport | - | - | ✅ | 5s | 88.799 | 2.0 |
| chromium-rust-v0.53 x go-v0.39 (webrtc-direct) | chromium-rust-v0.53 | go-v0.39 | webrtc-direct | - | - | ✅ | 6s | 230.8 | 8.6 |
| chromium-rust-v0.53 x go-v0.39 (ws, noise, yamux) | chromium-rust-v0.53 | go-v0.39 | ws | noise | yamux | ✅ | 5s | 334.9 | 4.7 |
| chromium-rust-v0.53 x go-v0.40 (webtransport) | chromium-rust-v0.53 | go-v0.40 | webtransport | - | - | ✅ | 6s | 108.1 | 0.1 |
| chromium-rust-v0.53 x go-v0.40 (ws, noise, yamux) | chromium-rust-v0.53 | go-v0.40 | ws | noise | yamux | ✅ | 5s | 342.9 | 11.199 |
| chromium-rust-v0.53 x go-v0.40 (webrtc-direct) | chromium-rust-v0.53 | go-v0.40 | webrtc-direct | - | - | ✅ | 7s | 1358.0 | 1.699 |
| chromium-rust-v0.53 x go-v0.41 (webtransport) | chromium-rust-v0.53 | go-v0.41 | webtransport | - | - | ✅ | 5s | 67.7 | 0.3 |
| chromium-rust-v0.53 x go-v0.41 (webrtc-direct) | chromium-rust-v0.53 | go-v0.41 | webrtc-direct | - | - | ✅ | 5s | 206.3 | 2.299 |
| chromium-rust-v0.53 x go-v0.41 (ws, noise, yamux) | chromium-rust-v0.53 | go-v0.41 | ws | noise | yamux | ✅ | 5s | 320.4 | 4.1 |
| chromium-rust-v0.53 x go-v0.42 (webtransport) | chromium-rust-v0.53 | go-v0.42 | webtransport | - | - | ✅ | 4s | 108.5 | 2.9 |
| chromium-rust-v0.53 x go-v0.42 (webrtc-direct) | chromium-rust-v0.53 | go-v0.42 | webrtc-direct | - | - | ✅ | 5s | 161.4 | 3.299 |
| chromium-rust-v0.53 x go-v0.42 (ws, noise, yamux) | chromium-rust-v0.53 | go-v0.42 | ws | noise | yamux | ✅ | 5s | 329.1 | 5.5 |
| chromium-rust-v0.53 x go-v0.43 (webtransport) | chromium-rust-v0.53 | go-v0.43 | webtransport | - | - | ✅ | 4s | 47.6 | 0.399 |
| chromium-rust-v0.53 x go-v0.43 (webrtc-direct) | chromium-rust-v0.53 | go-v0.43 | webrtc-direct | - | - | ✅ | 5s | 184.5 | 0.1 |
| chromium-rust-v0.53 x go-v0.44 (webtransport) | chromium-rust-v0.53 | go-v0.44 | webtransport | - | - | ✅ | 5s | 81.9 | 0.6 |
| chromium-rust-v0.53 x go-v0.43 (ws, noise, yamux) | chromium-rust-v0.53 | go-v0.43 | ws | noise | yamux | ✅ | 6s | 339.4 | 5.8 |
| chromium-rust-v0.53 x go-v0.44 (ws, noise, yamux) | chromium-rust-v0.53 | go-v0.44 | ws | noise | yamux | ✅ | 5s | 339.3 | 11.4 |
| chromium-rust-v0.53 x go-v0.44 (webrtc-direct) | chromium-rust-v0.53 | go-v0.44 | webrtc-direct | - | - | ✅ | 6s | 183.399 | 8.6 |
| chromium-rust-v0.53 x go-v0.45 (webtransport) | chromium-rust-v0.53 | go-v0.45 | webtransport | - | - | ✅ | 6s | 78.1 | 2.1 |
| chromium-rust-v0.53 x go-v0.45 (webrtc-direct) | chromium-rust-v0.53 | go-v0.45 | webrtc-direct | - | - | ✅ | 5s | 173.0 | 0.1 |
| chromium-rust-v0.53 x go-v0.45 (ws, noise, yamux) | chromium-rust-v0.53 | go-v0.45 | ws | noise | yamux | ✅ | 6s | 333.3 | 4.199 |
| chromium-rust-v0.53 x python-v0.4 (ws, noise, yamux) | chromium-rust-v0.53 | python-v0.4 | ws | noise | yamux | ✅ | 7s | 352.599 | 18.099 |
| chromium-rust-v0.53 x nim-v1.14 (ws, noise, mplex) | chromium-rust-v0.53 | nim-v1.14 | ws | noise | mplex | ✅ | 6s | 452.399 | 0.699 |
| chromium-rust-v0.53 x js-v1.x (ws, noise, yamux) | chromium-rust-v0.53 | js-v1.x | ws | noise | yamux | ✅ | 19s | 351.5 | 14.5 |
| chromium-rust-v0.53 x js-v1.x (ws, noise, mplex) | chromium-rust-v0.53 | js-v1.x | ws | noise | mplex | ✅ | 20s | 440.8 | 0.5 |
| chromium-rust-v0.53 x nim-v1.14 (ws, noise, yamux) | chromium-rust-v0.53 | nim-v1.14 | ws | noise | yamux | ✅ | 5s | 338.399 | 6.7 |
| chromium-rust-v0.53 x js-v2.x (ws, noise, mplex) | chromium-rust-v0.53 | js-v2.x | ws | noise | mplex | ✅ | 20s | 434.799 | 0.6 |
| chromium-rust-v0.53 x js-v2.x (ws, noise, yamux) | chromium-rust-v0.53 | js-v2.x | ws | noise | yamux | ✅ | 20s | 327.2 | 4.9 |
| chromium-rust-v0.53 x js-v3.x (ws, noise, mplex) | chromium-rust-v0.53 | js-v3.x | ws | noise | mplex | ✅ | 19s | 430.8 | 1.1 |
| chromium-rust-v0.53 x js-v3.x (ws, noise, yamux) | chromium-rust-v0.53 | js-v3.x | ws | noise | yamux | ✅ | 19s | 326.0 | 4.7 |
| chromium-rust-v0.54 x rust-v0.53 (webrtc-direct) | chromium-rust-v0.54 | rust-v0.53 | webrtc-direct | - | - | ✅ | 5s | 300.5 | 0.1 |
| chromium-rust-v0.54 x rust-v0.53 (ws, noise, mplex) | chromium-rust-v0.54 | rust-v0.53 | ws | noise | mplex | ✅ | 5s | 457.5 | 0.5 |
| chromium-rust-v0.54 x rust-v0.53 (ws, noise, yamux) | chromium-rust-v0.54 | rust-v0.53 | ws | noise | yamux | ✅ | 6s | 336.8 | 6.4 |
| chromium-rust-v0.53 x jvm-v1.2 (ws, noise, yamux) | chromium-rust-v0.53 | jvm-v1.2 | ws | noise | yamux | ✅ | 7s | 989.199 | 41.2 |
| chromium-rust-v0.54 x rust-v0.54 (webrtc-direct) | chromium-rust-v0.54 | rust-v0.54 | webrtc-direct | - | - | ✅ | 6s | 187.3 | 0.1 |
| chromium-rust-v0.54 x rust-v0.54 (ws, noise, mplex) | chromium-rust-v0.54 | rust-v0.54 | ws | noise | mplex | ✅ | 5s | 412.6 | 0.3 |
| chromium-rust-v0.54 x rust-v0.54 (ws, noise, yamux) | chromium-rust-v0.54 | rust-v0.54 | ws | noise | yamux | ✅ | 4s | 324.2 | 4.3 |
| chromium-rust-v0.54 x rust-v0.55 (webrtc-direct) | chromium-rust-v0.54 | rust-v0.55 | webrtc-direct | - | - | ✅ | 4s | 175.2 | 0.0 |
| chromium-rust-v0.54 x rust-v0.55 (ws, noise, mplex) | chromium-rust-v0.54 | rust-v0.55 | ws | noise | mplex | ✅ | 4s | 411.0 | 0.2 |
| chromium-rust-v0.54 x rust-v0.55 (ws, noise, yamux) | chromium-rust-v0.54 | rust-v0.55 | ws | noise | yamux | ✅ | 4s | 327.0 | 3.1 |
| chromium-rust-v0.54 x rust-v0.56 (webrtc-direct) | chromium-rust-v0.54 | rust-v0.56 | webrtc-direct | - | - | ✅ | 5s | 177.2 | 1.3 |
| chromium-rust-v0.54 x rust-v0.56 (ws, noise, mplex) | chromium-rust-v0.54 | rust-v0.56 | ws | noise | mplex | ✅ | 5s | 412.0 | 0.2 |
| chromium-rust-v0.54 x rust-v0.56 (ws, noise, yamux) | chromium-rust-v0.54 | rust-v0.56 | ws | noise | yamux | ✅ | 5s | 331.2 | 3.9 |
| chromium-rust-v0.54 x go-v0.38 (webtransport) | chromium-rust-v0.54 | go-v0.38 | webtransport | - | - | ✅ | 4s | 73.2 | 0.2 |
| chromium-rust-v0.54 x go-v0.38 (webrtc-direct) | chromium-rust-v0.54 | go-v0.38 | webrtc-direct | - | - | ✅ | 4s | 123.3 | 0.2 |
| chromium-rust-v0.54 x go-v0.39 (webtransport) | chromium-rust-v0.54 | go-v0.39 | webtransport | - | - | ✅ | 4s | 62.4 | 0.2 |
| chromium-rust-v0.54 x go-v0.38 (ws, noise, yamux) | chromium-rust-v0.54 | go-v0.38 | ws | noise | yamux | ✅ | 5s | 329.3 | 7.9 |
| chromium-rust-v0.54 x go-v0.39 (webrtc-direct) | chromium-rust-v0.54 | go-v0.39 | webrtc-direct | - | - | ✅ | 6s | 1371.8 | 0.2 |
| chromium-rust-v0.54 x go-v0.39 (ws, noise, yamux) | chromium-rust-v0.54 | go-v0.39 | ws | noise | yamux | ✅ | 5s | 322.9 | 5.6 |
| chromium-rust-v0.54 x go-v0.40 (webtransport) | chromium-rust-v0.54 | go-v0.40 | webtransport | - | - | ✅ | 5s | 60.6 | 0.6 |
| chromium-rust-v0.54 x go-v0.40 (webrtc-direct) | chromium-rust-v0.54 | go-v0.40 | webrtc-direct | - | - | ✅ | 4s | 120.8 | 0.0 |
| chromium-rust-v0.54 x go-v0.41 (webtransport) | chromium-rust-v0.54 | go-v0.41 | webtransport | - | - | ✅ | 4s | 67.5 | 0.6 |
| chromium-rust-v0.54 x go-v0.40 (ws, noise, yamux) | chromium-rust-v0.54 | go-v0.40 | ws | noise | yamux | ✅ | 4s | 334.6 | 9.4 |
| chromium-rust-v0.54 x go-v0.41 (webrtc-direct) | chromium-rust-v0.54 | go-v0.41 | webrtc-direct | - | - | ✅ | 4s | 141.0 | 0.0 |
| chromium-rust-v0.54 x go-v0.41 (ws, noise, yamux) | chromium-rust-v0.54 | go-v0.41 | ws | noise | yamux | ✅ | 5s | 331.3 | 10.6 |
| chromium-rust-v0.54 x go-v0.42 (webtransport) | chromium-rust-v0.54 | go-v0.42 | webtransport | - | - | ✅ | 5s | 64.2 | 0.5 |
| chromium-rust-v0.54 x go-v0.42 (webrtc-direct) | chromium-rust-v0.54 | go-v0.42 | webrtc-direct | - | - | ✅ | 4s | 146.1 | 0.1 |
| chromium-rust-v0.54 x go-v0.42 (ws, noise, yamux) | chromium-rust-v0.54 | go-v0.42 | ws | noise | yamux | ✅ | 5s | 330.1 | 6.0 |
| chromium-rust-v0.54 x go-v0.43 (webrtc-direct) | chromium-rust-v0.54 | go-v0.43 | webrtc-direct | - | - | ✅ | 4s | 161.7 | 0.1 |
| chromium-rust-v0.54 x go-v0.43 (webtransport) | chromium-rust-v0.54 | go-v0.43 | webtransport | - | - | ✅ | 5s | 65.6 | 0.4 |
| chromium-rust-v0.54 x go-v0.43 (ws, noise, yamux) | chromium-rust-v0.54 | go-v0.43 | ws | noise | yamux | ✅ | 5s | 330.8 | 7.8 |
| chromium-rust-v0.54 x go-v0.44 (webtransport) | chromium-rust-v0.54 | go-v0.44 | webtransport | - | - | ✅ | 4s | 56.2 | 0.3 |
| chromium-rust-v0.54 x go-v0.44 (webrtc-direct) | chromium-rust-v0.54 | go-v0.44 | webrtc-direct | - | - | ✅ | 5s | 130.2 | 0.1 |
| chromium-rust-v0.54 x go-v0.44 (ws, noise, yamux) | chromium-rust-v0.54 | go-v0.44 | ws | noise | yamux | ✅ | 5s | 336.4 | 6.1 |
| chromium-rust-v0.54 x go-v0.45 (webtransport) | chromium-rust-v0.54 | go-v0.45 | webtransport | - | - | ✅ | 4s | 56.4 | 0.7 |
| chromium-rust-v0.54 x go-v0.45 (webrtc-direct) | chromium-rust-v0.54 | go-v0.45 | webrtc-direct | - | - | ✅ | 5s | 142.8 | 0.2 |
| chromium-rust-v0.54 x go-v0.45 (ws, noise, yamux) | chromium-rust-v0.54 | go-v0.45 | ws | noise | yamux | ✅ | 4s | 340.0 | 8.0 |
| chromium-rust-v0.54 x python-v0.4 (ws, noise, yamux) | chromium-rust-v0.54 | python-v0.4 | ws | noise | yamux | ✅ | 5s | 316.3 | 3.2 |
| chromium-rust-v0.54 x python-v0.4 (ws, noise, mplex) | chromium-rust-v0.54 | python-v0.4 | ws | noise | mplex | ✅ | 16s | 10425.4 | 0.7 |
| chromium-rust-v0.54 x js-v1.x (ws, noise, mplex) | chromium-rust-v0.54 | js-v1.x | ws | noise | mplex | ✅ | 15s | 438.8 | 0.5 |
| chromium-rust-v0.54 x js-v1.x (ws, noise, yamux) | chromium-rust-v0.54 | js-v1.x | ws | noise | yamux | ✅ | 15s | 335.7 | 12.4 |
| chromium-rust-v0.54 x js-v2.x (ws, noise, mplex) | chromium-rust-v0.54 | js-v2.x | ws | noise | mplex | ✅ | 15s | 430.1 | 0.3 |
| chromium-rust-v0.54 x js-v2.x (ws, noise, yamux) | chromium-rust-v0.54 | js-v2.x | ws | noise | yamux | ✅ | 16s | 350.4 | 17.0 |
| chromium-rust-v0.54 x js-v3.x (ws, noise, mplex) | chromium-rust-v0.54 | js-v3.x | ws | noise | mplex | ✅ | 15s | 431.5 | 0.6 |
| chromium-rust-v0.54 x nim-v1.14 (ws, noise, mplex) | chromium-rust-v0.54 | nim-v1.14 | ws | noise | mplex | ✅ | 4s | 421.9 | 0.2 |
| chromium-rust-v0.54 x nim-v1.14 (ws, noise, yamux) | chromium-rust-v0.54 | nim-v1.14 | ws | noise | yamux | ✅ | 4s | 319.6 | 4.2 |
| chromium-rust-v0.54 x jvm-v1.2 (ws, noise, yamux) | chromium-rust-v0.54 | jvm-v1.2 | ws | noise | yamux | ✅ | 5s | 579.2 | 14.9 |
| chromium-rust-v0.54 x js-v3.x (ws, noise, yamux) | chromium-rust-v0.54 | js-v3.x | ws | noise | yamux | ✅ | 12s | 317.3 | 4.8 |
| chromium-rust-v0.54 x jvm-v1.2 (ws, noise, mplex) | chromium-rust-v0.54 | jvm-v1.2 | ws | noise | mplex | ✅ | 16s | 11031.0 | 1.5 |
| chromium-rust-v0.53 x python-v0.4 (ws, noise, mplex) | chromium-rust-v0.53 | python-v0.4 | ws | noise | mplex | ❌ | 185s | - | - |
| chromium-rust-v0.53 x jvm-v1.2 (ws, noise, mplex) | chromium-rust-v0.53 | jvm-v1.2 | ws | noise | mplex | ❌ | 185s | - | - |

---

## Matrix View by Transport + Secure Channel + Muxer

### quic-v1

| Dialer \ Listener | c-v0.0.1 | eth-p2p-z-v0.0.1 | go-v0.38 | go-v0.39 | go-v0.40 | go-v0.41 | go-v0.42 | go-v0.43 | go-v0.44 | go-v0.45 | jvm-v1.2 | python-v0.4 | rust-v0.53 | rust-v0.54 | rust-v0.55 | rust-v0.56 | zig-v0.0.1 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **c-v0.0.1** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
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
| **rust-v0.55** | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **rust-v0.56** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **zig-v0.0.1** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

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
| **chromium-rust-v0.53** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
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
| **rust-v0.53** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
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
| **webkit-js-v1.x** | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ |
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

*Generated: 2025-12-24T04:06:00Z*
<!-- TEST_RESULTS_END -->

