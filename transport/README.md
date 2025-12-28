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

## Test Pass: `transport-interop-025059-28-12-2025`

**Summary:**
- **Total Tests:** 2302
- **Passed:** ✅ 2258
- **Failed:** ❌ 44
- **Pass Rate:** 98.1%

**Environment:**
- **Platform:** x86_64
- **OS:** Linux
- **Workers:** 8
- **Duration:** 3743s

**Timestamps:**
- **Started:** 2025-12-28T02:50:59Z
- **Completed:** 2025-12-28T03:53:22Z

---

## Test Results

| Test | Dialer | Listener | Transport | Secure | Muxer | Status | Duration | Handshake+RTT (ms) | Ping RTT (ms) |
|------|--------|----------|-----------|--------|-------|--------|----------|-------------------|---------------|
| rust-v0.53 x rust-v0.53 (tcp, tls, mplex) | rust-v0.53 | rust-v0.53 | tcp | tls | mplex | ✅ | 3s | 46.838 | 41.715 |
| rust-v0.53 x rust-v0.53 (tcp, tls, yamux) | rust-v0.53 | rust-v0.53 | tcp | tls | yamux | ✅ | 5s | 135.023 | 91.694 |
| rust-v0.53 x rust-v0.53 (ws, tls, mplex) | rust-v0.53 | rust-v0.53 | ws | tls | mplex | ✅ | 5s | 262.958 | 87.849 |
| rust-v0.53 x rust-v0.53 (tcp, noise, yamux) | rust-v0.53 | rust-v0.53 | tcp | noise | yamux | ✅ | 6s | 141.326 | 43.987 |
| rust-v0.53 x rust-v0.53 (ws, noise, yamux) | rust-v0.53 | rust-v0.53 | ws | noise | yamux | ✅ | 6s | 283.569 | 95.746 |
| rust-v0.53 x rust-v0.53 (tcp, noise, mplex) | rust-v0.53 | rust-v0.53 | tcp | noise | mplex | ✅ | 6s | 91.207 | 0.11 |
| rust-v0.53 x rust-v0.53 (ws, tls, yamux) | rust-v0.53 | rust-v0.53 | ws | tls | yamux | ✅ | 7s | 268.19 | 91.754 |
| rust-v0.53 x rust-v0.53 (ws, noise, mplex) | rust-v0.53 | rust-v0.53 | ws | noise | mplex | ✅ | 6s | 261.904 | 87.815 |
| rust-v0.53 x rust-v0.53 (quic-v1) | rust-v0.53 | rust-v0.53 | quic-v1 | - | - | ✅ | 4s | 4.088 | 0.224 |
| rust-v0.53 x rust-v0.53 (webrtc-direct) | rust-v0.53 | rust-v0.53 | webrtc-direct | - | - | ✅ | 5s | 210.523 | 0.244 |
| rust-v0.53 x rust-v0.54 (ws, noise, mplex) | rust-v0.53 | rust-v0.54 | ws | noise | mplex | ✅ | 5s | 269.652 | 92.003 |
| rust-v0.53 x rust-v0.54 (ws, tls, mplex) | rust-v0.53 | rust-v0.54 | ws | tls | mplex | ✅ | 5s | 275.537 | 90.61 |
| rust-v0.53 x rust-v0.54 (ws, tls, yamux) | rust-v0.53 | rust-v0.54 | ws | tls | yamux | ✅ | 6s | 277.353 | 95.538 |
| rust-v0.53 x rust-v0.54 (ws, noise, yamux) | rust-v0.53 | rust-v0.54 | ws | noise | yamux | ✅ | 5s | 270.889 | 91.775 |
| rust-v0.53 x rust-v0.54 (tcp, tls, yamux) | rust-v0.53 | rust-v0.54 | tcp | tls | yamux | ✅ | 5s | 137.608 | 91.742 |
| rust-v0.53 x rust-v0.54 (tcp, tls, mplex) | rust-v0.53 | rust-v0.54 | tcp | tls | mplex | ✅ | 6s | 46.461 | 0.125 |
| rust-v0.53 x rust-v0.54 (tcp, noise, mplex) | rust-v0.53 | rust-v0.54 | tcp | noise | mplex | ✅ | 6s | 96.84 | 0.126 |
| rust-v0.53 x rust-v0.54 (tcp, noise, yamux) | rust-v0.53 | rust-v0.54 | tcp | noise | yamux | ✅ | 4s | 136.986 | 48.074 |
| rust-v0.53 x rust-v0.54 (quic-v1) | rust-v0.53 | rust-v0.54 | quic-v1 | - | - | ✅ | 4s | 6.961 | 0.471 |
| rust-v0.53 x rust-v0.54 (webrtc-direct) | rust-v0.53 | rust-v0.54 | webrtc-direct | - | - | ✅ | 4s | 240.215 | 0.953 |
| rust-v0.53 x rust-v0.55 (ws, tls, mplex) | rust-v0.53 | rust-v0.55 | ws | tls | mplex | ✅ | 5s | 138.039 | 46.143 |
| rust-v0.53 x rust-v0.55 (ws, noise, mplex) | rust-v0.53 | rust-v0.55 | ws | noise | mplex | ✅ | 5s | 131.263 | 43.209 |
| rust-v0.53 x rust-v0.55 (ws, tls, yamux) | rust-v0.53 | rust-v0.55 | ws | tls | yamux | ✅ | 5s | 140.505 | 46.291 |
| rust-v0.53 x rust-v0.55 (ws, noise, yamux) | rust-v0.53 | rust-v0.55 | ws | noise | yamux | ✅ | 6s | 130.663 | 43.418 |
| rust-v0.53 x rust-v0.55 (tcp, tls, mplex) | rust-v0.53 | rust-v0.55 | tcp | tls | mplex | ✅ | 5s | 3.492 | 0.215 |
| rust-v0.53 x rust-v0.55 (tcp, tls, yamux) | rust-v0.53 | rust-v0.55 | tcp | tls | yamux | ✅ | 5s | 6.773 | 1.5 |
| rust-v0.53 x rust-v0.55 (tcp, noise, mplex) | rust-v0.53 | rust-v0.55 | tcp | noise | mplex | ✅ | 5s | 47.229 | 0.134 |
| rust-v0.53 x rust-v0.55 (tcp, noise, yamux) | rust-v0.53 | rust-v0.55 | tcp | noise | yamux | ✅ | 4s | 44.0 | 0.276 |
| rust-v0.53 x rust-v0.55 (quic-v1) | rust-v0.53 | rust-v0.55 | quic-v1 | - | - | ✅ | 5s | 5.581 | 0.346 |
| rust-v0.53 x rust-v0.56 (ws, tls, mplex) | rust-v0.53 | rust-v0.56 | ws | tls | mplex | ✅ | 3s | 92.046 | 0.06 |
| rust-v0.53 x rust-v0.55 (webrtc-direct) | rust-v0.53 | rust-v0.55 | webrtc-direct | - | - | ✅ | 5s | 211.66 | 0.5 |
| rust-v0.53 x rust-v0.56 (ws, tls, yamux) | rust-v0.53 | rust-v0.56 | ws | tls | yamux | ✅ | 5s | 136.447 | 42.855 |
| rust-v0.53 x rust-v0.56 (ws, noise, mplex) | rust-v0.53 | rust-v0.56 | ws | noise | mplex | ✅ | 6s | 139.462 | 47.342 |
| rust-v0.53 x rust-v0.56 (tcp, tls, yamux) | rust-v0.53 | rust-v0.56 | tcp | tls | yamux | ✅ | 4s | 45.768 | 42.943 |
| rust-v0.53 x rust-v0.56 (ws, noise, yamux) | rust-v0.53 | rust-v0.56 | ws | noise | yamux | ✅ | 6s | 133.619 | 43.281 |
| rust-v0.53 x rust-v0.56 (tcp, tls, mplex) | rust-v0.53 | rust-v0.56 | tcp | tls | mplex | ✅ | 5s | 43.102 | 40.606 |
| rust-v0.53 x rust-v0.56 (tcp, noise, mplex) | rust-v0.53 | rust-v0.56 | tcp | noise | mplex | ✅ | 5s | 43.715 | 0.23 |
| rust-v0.53 x rust-v0.56 (tcp, noise, yamux) | rust-v0.53 | rust-v0.56 | tcp | noise | yamux | ✅ | 5s | 43.073 | 0.08 |
| rust-v0.53 x rust-v0.56 (quic-v1) | rust-v0.53 | rust-v0.56 | quic-v1 | - | - | ✅ | 5s | 3.672 | 0.279 |
| rust-v0.53 x rust-v0.56 (webrtc-direct) | rust-v0.53 | rust-v0.56 | webrtc-direct | - | - | ✅ | 5s | 283.221 | 0.241 |
| rust-v0.53 x go-v0.38 (ws, tls, yamux) | rust-v0.53 | go-v0.38 | ws | tls | yamux | ✅ | 5s | 86.85 | 0.827 |
| rust-v0.53 x go-v0.38 (tcp, tls, yamux) | rust-v0.53 | go-v0.38 | tcp | tls | yamux | ✅ | 4s | 4.127 | 0.714 |
| rust-v0.53 x go-v0.38 (ws, noise, yamux) | rust-v0.53 | go-v0.38 | ws | noise | yamux | ✅ | 5s | 88.158 | 42.157 |
| rust-v0.53 x go-v0.38 (tcp, noise, yamux) | rust-v0.53 | go-v0.38 | tcp | noise | yamux | ✅ | 4s | 4.496 | 0.12 |
| rust-v0.53 x go-v0.38 (quic-v1) | rust-v0.53 | go-v0.38 | quic-v1 | - | - | ✅ | 5s | 3.46 | 0.126 |
| rust-v0.53 x go-v0.38 (webrtc-direct) | rust-v0.53 | go-v0.38 | webrtc-direct | - | - | ✅ | 5s | 127.267 | 0.239 |
| rust-v0.53 x go-v0.39 (ws, tls, yamux) | rust-v0.53 | go-v0.39 | ws | tls | yamux | ✅ | 4s | 137.77 | 46.706 |
| rust-v0.53 x go-v0.39 (ws, noise, yamux) | rust-v0.53 | go-v0.39 | ws | noise | yamux | ✅ | 5s | 93.534 | 42.467 |
| rust-v0.53 x go-v0.39 (tcp, tls, yamux) | rust-v0.53 | go-v0.39 | tcp | tls | yamux | ✅ | 5s | 8.823 | 1.537 |
| rust-v0.53 x go-v0.39 (tcp, noise, yamux) | rust-v0.53 | go-v0.39 | tcp | noise | yamux | ✅ | 4s | 51.235 | 46.747 |
| rust-v0.53 x go-v0.39 (quic-v1) | rust-v0.53 | go-v0.39 | quic-v1 | - | - | ✅ | 5s | 6.613 | 2.531 |
| rust-v0.53 x go-v0.39 (webrtc-direct) | rust-v0.53 | go-v0.39 | webrtc-direct | - | - | ✅ | 4s | 8.092 | 0.246 |
| rust-v0.53 x go-v0.40 (ws, tls, yamux) | rust-v0.53 | go-v0.40 | ws | tls | yamux | ✅ | 5s | 138.667 | 43.556 |
| rust-v0.53 x go-v0.40 (ws, noise, yamux) | rust-v0.53 | go-v0.40 | ws | noise | yamux | ✅ | 5s | 89.427 | 0.287 |
| rust-v0.53 x go-v0.40 (tcp, tls, yamux) | rust-v0.53 | go-v0.40 | tcp | tls | yamux | ✅ | 4s | 4.178 | 1.23 |
| rust-v0.53 x go-v0.40 (tcp, noise, yamux) | rust-v0.53 | go-v0.40 | tcp | noise | yamux | ✅ | 5s | 3.563 | 0.49 |
| rust-v0.53 x go-v0.40 (quic-v1) | rust-v0.53 | go-v0.40 | quic-v1 | - | - | ✅ | 5s | 9.833 | 0.856 |
| rust-v0.53 x go-v0.40 (webrtc-direct) | rust-v0.53 | go-v0.40 | webrtc-direct | - | - | ✅ | 4s | 24.178 | 0.377 |
| rust-v0.53 x go-v0.41 (ws, tls, yamux) | rust-v0.53 | go-v0.41 | ws | tls | yamux | ✅ | 5s | 94.013 | 0.254 |
| rust-v0.53 x go-v0.41 (ws, noise, yamux) | rust-v0.53 | go-v0.41 | ws | noise | yamux | ✅ | 4s | 91.884 | 0.205 |
| rust-v0.53 x go-v0.41 (tcp, tls, yamux) | rust-v0.53 | go-v0.41 | tcp | tls | yamux | ✅ | 5s | 51.848 | 47.798 |
| rust-v0.53 x go-v0.41 (quic-v1) | rust-v0.53 | go-v0.41 | quic-v1 | - | - | ✅ | 4s | 3.758 | 0.304 |
| rust-v0.53 x go-v0.41 (tcp, noise, yamux) | rust-v0.53 | go-v0.41 | tcp | noise | yamux | ✅ | 5s | 2.326 | 0.204 |
| rust-v0.53 x go-v0.41 (webrtc-direct) | rust-v0.53 | go-v0.41 | webrtc-direct | - | - | ✅ | 5s | 11.213 | 0.306 |
| rust-v0.53 x go-v0.42 (ws, tls, yamux) | rust-v0.53 | go-v0.42 | ws | tls | yamux | ✅ | 5s | 91.173 | 0.203 |
| rust-v0.53 x go-v0.42 (tcp, tls, yamux) | rust-v0.53 | go-v0.42 | tcp | tls | yamux | ✅ | 5s | 9.416 | 2.331 |
| rust-v0.53 x go-v0.42 (ws, noise, yamux) | rust-v0.53 | go-v0.42 | ws | noise | yamux | ✅ | 6s | 93.341 | 4.026 |
| rust-v0.53 x go-v0.42 (tcp, noise, yamux) | rust-v0.53 | go-v0.42 | tcp | noise | yamux | ✅ | 5s | 3.034 | 0.181 |
| rust-v0.53 x go-v0.42 (quic-v1) | rust-v0.53 | go-v0.42 | quic-v1 | - | - | ✅ | 5s | 4.355 | 0.222 |
| rust-v0.53 x go-v0.42 (webrtc-direct) | rust-v0.53 | go-v0.42 | webrtc-direct | - | - | ✅ | 5s | 12.337 | 0.378 |
| rust-v0.53 x go-v0.43 (ws, tls, yamux) | rust-v0.53 | go-v0.43 | ws | tls | yamux | ✅ | 5s | 98.401 | 0.227 |
| rust-v0.53 x go-v0.43 (ws, noise, yamux) | rust-v0.53 | go-v0.43 | ws | noise | yamux | ✅ | 5s | 94.008 | 0.676 |
| rust-v0.53 x go-v0.43 (tcp, tls, yamux) | rust-v0.53 | go-v0.43 | tcp | tls | yamux | ✅ | 4s | 3.011 | 0.676 |
| rust-v0.53 x go-v0.43 (tcp, noise, yamux) | rust-v0.53 | go-v0.43 | tcp | noise | yamux | ✅ | 5s | 4.165 | 0.768 |
| rust-v0.53 x go-v0.43 (quic-v1) | rust-v0.53 | go-v0.43 | quic-v1 | - | - | ✅ | 4s | 7.076 | 0.274 |
| rust-v0.53 x go-v0.43 (webrtc-direct) | rust-v0.53 | go-v0.43 | webrtc-direct | - | - | ✅ | 5s | 18.257 | 0.406 |
| rust-v0.53 x go-v0.44 (ws, tls, yamux) | rust-v0.53 | go-v0.44 | ws | tls | yamux | ✅ | 5s | 148.752 | 42.792 |
| rust-v0.53 x go-v0.44 (tcp, tls, yamux) | rust-v0.53 | go-v0.44 | tcp | tls | yamux | ✅ | 4s | 47.295 | 44.144 |
| rust-v0.53 x go-v0.44 (ws, noise, yamux) | rust-v0.53 | go-v0.44 | ws | noise | yamux | ✅ | 6s | 140.626 | 42.427 |
| rust-v0.53 x go-v0.44 (tcp, noise, yamux) | rust-v0.53 | go-v0.44 | tcp | noise | yamux | ✅ | 5s | 3.605 | 0.112 |
| rust-v0.53 x go-v0.44 (quic-v1) | rust-v0.53 | go-v0.44 | quic-v1 | - | - | ✅ | 5s | 7.148 | 0.252 |
| rust-v0.53 x go-v0.44 (webrtc-direct) | rust-v0.53 | go-v0.44 | webrtc-direct | - | - | ✅ | 5s | 70.263 | 2.251 |
| rust-v0.53 x go-v0.45 (ws, tls, yamux) | rust-v0.53 | go-v0.45 | ws | tls | yamux | ✅ | 4s | 90.347 | 43.525 |
| rust-v0.53 x go-v0.45 (ws, noise, yamux) | rust-v0.53 | go-v0.45 | ws | noise | yamux | ✅ | 5s | 97.33 | 0.386 |
| rust-v0.53 x go-v0.45 (tcp, tls, yamux) | rust-v0.53 | go-v0.45 | tcp | tls | yamux | ✅ | 5s | 3.261 | 0.449 |
| rust-v0.53 x go-v0.45 (tcp, noise, yamux) | rust-v0.53 | go-v0.45 | tcp | noise | yamux | ✅ | 4s | 3.616 | 0.158 |
| rust-v0.53 x go-v0.45 (webrtc-direct) | rust-v0.53 | go-v0.45 | webrtc-direct | - | - | ✅ | 4s | 37.286 | 0.316 |
| rust-v0.53 x go-v0.45 (quic-v1) | rust-v0.53 | go-v0.45 | quic-v1 | - | - | ✅ | 5s | 10.493 | 0.674 |
| rust-v0.53 x python-v0.4 (ws, noise, mplex) | rust-v0.53 | python-v0.4 | ws | noise | mplex | ✅ | 5s | 99.385 | 1.376 |
| rust-v0.53 x python-v0.4 (tcp, noise, mplex) | rust-v0.53 | python-v0.4 | tcp | noise | mplex | ✅ | 4s | 10.106 | 1.393 |
| rust-v0.53 x python-v0.4 (ws, noise, yamux) | rust-v0.53 | python-v0.4 | ws | noise | yamux | ✅ | 6s | 108.567 | 3.725 |
| rust-v0.53 x python-v0.4 (quic-v1) | rust-v0.53 | python-v0.4 | quic-v1 | - | - | ✅ | 4s | 59.473 | 7.45 |
| rust-v0.53 x python-v0.4 (tcp, noise, yamux) | rust-v0.53 | python-v0.4 | tcp | noise | yamux | ✅ | 6s | 9.218 | 0.533 |
| rust-v0.53 x js-v1.x (ws, noise, mplex) | rust-v0.53 | js-v1.x | ws | noise | mplex | ✅ | 14s | 186.977 | 19.05 |
| rust-v0.53 x js-v1.x (ws, noise, yamux) | rust-v0.53 | js-v1.x | ws | noise | yamux | ✅ | 15s | 232.987 | 16.583 |
| rust-v0.53 x js-v1.x (tcp, noise, mplex) | rust-v0.53 | js-v1.x | tcp | noise | mplex | ✅ | 14s | 115.408 | 7.602 |
| rust-v0.53 x js-v1.x (tcp, noise, yamux) | rust-v0.53 | js-v1.x | tcp | noise | yamux | ✅ | 15s | 119.312 | 7.647 |
| rust-v0.53 x js-v2.x (ws, noise, mplex) | rust-v0.53 | js-v2.x | ws | noise | mplex | ✅ | 14s | 162.978 | 10.442 |
| rust-v0.53 x js-v2.x (ws, noise, yamux) | rust-v0.53 | js-v2.x | ws | noise | yamux | ✅ | 14s | 215.887 | 8.161 |
| rust-v0.53 x js-v2.x (tcp, noise, mplex) | rust-v0.53 | js-v2.x | tcp | noise | mplex | ✅ | 14s | 132.481 | 6.175 |
| rust-v0.53 x js-v2.x (tcp, noise, yamux) | rust-v0.53 | js-v2.x | tcp | noise | yamux | ✅ | 13s | 105.394 | 4.874 |
| rust-v0.53 x nim-v1.14 (ws, noise, mplex) | rust-v0.53 | nim-v1.14 | ws | noise | mplex | ✅ | 4s | 273.877 | 87.761 |
| rust-v0.53 x nim-v1.14 (ws, noise, yamux) | rust-v0.53 | nim-v1.14 | ws | noise | yamux | ✅ | 4s | 236.9 | 43.137 |
| rust-v0.53 x nim-v1.14 (tcp, noise, mplex) | rust-v0.53 | nim-v1.14 | tcp | noise | mplex | ✅ | 4s | 101.311 | 2.009 |
| rust-v0.53 x nim-v1.14 (tcp, noise, yamux) | rust-v0.53 | nim-v1.14 | tcp | noise | yamux | ✅ | 4s | 144.957 | 44.835 |
| rust-v0.53 x js-v3.x (ws, noise, mplex) | rust-v0.53 | js-v3.x | ws | noise | mplex | ✅ | 12s | 187.13 | 15.96 |
| rust-v0.53 x js-v3.x (tcp, noise, mplex) | rust-v0.53 | js-v3.x | tcp | noise | mplex | ✅ | 12s | 132.377 | 12.255 |
| rust-v0.53 x js-v3.x (ws, noise, yamux) | rust-v0.53 | js-v3.x | ws | noise | yamux | ✅ | 15s | 200.093 | 24.013 |
| rust-v0.53 x js-v3.x (tcp, noise, yamux) | rust-v0.53 | js-v3.x | tcp | noise | yamux | ✅ | 14s | 132.797 | 12.715 |
| rust-v0.53 x jvm-v1.2 (ws, tls, mplex) | rust-v0.53 | jvm-v1.2 | ws | tls | mplex | ✅ | 10s | 3227.938 | 1.882 |
| rust-v0.53 x jvm-v1.2 (ws, noise, mplex) | rust-v0.53 | jvm-v1.2 | ws | noise | mplex | ✅ | 8s | 988.889 | 49.714 |
| rust-v0.53 x jvm-v1.2 (ws, tls, yamux) | rust-v0.53 | jvm-v1.2 | ws | tls | yamux | ✅ | 10s | 2590.375 | 49.141 |
| rust-v0.53 x jvm-v1.2 (ws, noise, yamux) | rust-v0.53 | jvm-v1.2 | ws | noise | yamux | ✅ | 8s | 1024.651 | 46.545 |
| rust-v0.53 x jvm-v1.2 (tcp, tls, mplex) | rust-v0.53 | jvm-v1.2 | tcp | tls | mplex | ✅ | 8s | 1861.533 | 2.704 |
| rust-v0.53 x c-v0.0.1 (tcp, noise, mplex) | rust-v0.53 | c-v0.0.1 | tcp | noise | mplex | ✅ | 5s | 56.88 | 7.841 |
| rust-v0.53 x c-v0.0.1 (tcp, noise, yamux) | rust-v0.53 | c-v0.0.1 | tcp | noise | yamux | ✅ | 4s | 108.028 | 0.668 |
| rust-v0.53 x jvm-v1.2 (tcp, noise, mplex) | rust-v0.53 | jvm-v1.2 | tcp | noise | mplex | ✅ | 8s | 923.617 | 5.53 |
| rust-v0.53 x jvm-v1.2 (tcp, noise, yamux) | rust-v0.53 | jvm-v1.2 | tcp | noise | yamux | ✅ | 8s | 778.897 | 3.565 |
| rust-v0.53 x c-v0.0.1 (quic-v1) | rust-v0.53 | c-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 18.704 | 3.879 |
| rust-v0.53 x jvm-v1.2 (tcp, tls, yamux) | rust-v0.53 | jvm-v1.2 | tcp | tls | yamux | ✅ | 10s | 2143.549 | 51.679 |
| rust-v0.53 x jvm-v1.2 (quic-v1) | rust-v0.53 | jvm-v1.2 | quic-v1 | - | - | ✅ | 9s | 982.836 | 3.635 |
| rust-v0.53 x dotnet-v1.0 (tcp, noise, yamux) | rust-v0.53 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 4s | 125.349 | 4.119 |
| rust-v0.53 x zig-v0.0.1 (quic-v1) | rust-v0.53 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 5s | - | - |
| rust-v0.53 x eth-p2p-z-v0.0.1 (quic-v1) | rust-v0.53 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 5s | 2.81 | 0.169 |
| rust-v0.54 x rust-v0.53 (ws, tls, yamux) | rust-v0.54 | rust-v0.53 | ws | tls | yamux | ✅ | 4s | 267.286 | 87.836 |
| rust-v0.54 x rust-v0.53 (ws, tls, mplex) | rust-v0.54 | rust-v0.53 | ws | tls | mplex | ✅ | 6s | 277.677 | 96.119 |
| rust-v0.54 x rust-v0.53 (ws, noise, mplex) | rust-v0.54 | rust-v0.53 | ws | noise | mplex | ✅ | 5s | 269.111 | 91.955 |
| rust-v0.54 x rust-v0.53 (ws, noise, yamux) | rust-v0.54 | rust-v0.53 | ws | noise | yamux | ✅ | 6s | 265.518 | 91.864 |
| rust-v0.54 x rust-v0.53 (tcp, tls, mplex) | rust-v0.54 | rust-v0.53 | tcp | tls | mplex | ✅ | 6s | 47.352 | 43.282 |
| rust-v0.54 x rust-v0.53 (tcp, tls, yamux) | rust-v0.54 | rust-v0.53 | tcp | tls | yamux | ✅ | 5s | 44.614 | 41.391 |
| rust-v0.54 x rust-v0.53 (tcp, noise, mplex) | rust-v0.54 | rust-v0.53 | tcp | noise | mplex | ✅ | 5s | 90.492 | 0.1 |
| rust-v0.54 x rust-v0.53 (quic-v1) | rust-v0.54 | rust-v0.53 | quic-v1 | - | - | ✅ | 3s | 3.75 | 0.403 |
| rust-v0.54 x rust-v0.53 (tcp, noise, yamux) | rust-v0.54 | rust-v0.53 | tcp | noise | yamux | ✅ | 5s | 133.038 | 44.066 |
| rust-v0.54 x rust-v0.53 (webrtc-direct) | rust-v0.54 | rust-v0.53 | webrtc-direct | - | - | ✅ | 5s | 207.931 | 0.18 |
| rust-v0.54 x rust-v0.54 (ws, tls, mplex) | rust-v0.54 | rust-v0.54 | ws | tls | mplex | ✅ | 4s | 267.462 | 88.003 |
| rust-v0.54 x rust-v0.54 (ws, tls, yamux) | rust-v0.54 | rust-v0.54 | ws | tls | yamux | ✅ | 5s | 278.086 | 95.698 |
| rust-v0.54 x rust-v0.54 (ws, noise, mplex) | rust-v0.54 | rust-v0.54 | ws | noise | mplex | ✅ | 5s | 262.669 | 87.926 |
| rust-v0.54 x rust-v0.54 (tcp, tls, mplex) | rust-v0.54 | rust-v0.54 | tcp | tls | mplex | ✅ | 5s | 4.407 | 0.073 |
| rust-v0.54 x rust-v0.54 (ws, noise, yamux) | rust-v0.54 | rust-v0.54 | ws | noise | yamux | ✅ | 5s | 270.656 | 91.41 |
| rust-v0.54 x rust-v0.54 (tcp, tls, yamux) | rust-v0.54 | rust-v0.54 | tcp | tls | yamux | ✅ | 5s | 138.702 | 91.698 |
| rust-v0.54 x rust-v0.54 (tcp, noise, mplex) | rust-v0.54 | rust-v0.54 | tcp | noise | mplex | ✅ | 4s | 86.232 | 0.363 |
| rust-v0.54 x rust-v0.54 (tcp, noise, yamux) | rust-v0.54 | rust-v0.54 | tcp | noise | yamux | ✅ | 5s | 137.82 | 43.972 |
| rust-v0.54 x rust-v0.54 (quic-v1) | rust-v0.54 | rust-v0.54 | quic-v1 | - | - | ✅ | 4s | 3.782 | 0.206 |
| rust-v0.54 x rust-v0.54 (webrtc-direct) | rust-v0.54 | rust-v0.54 | webrtc-direct | - | - | ✅ | 5s | 211.8 | 2.642 |
| rust-v0.54 x rust-v0.55 (ws, tls, mplex) | rust-v0.54 | rust-v0.55 | ws | tls | mplex | ✅ | 4s | 136.483 | 43.031 |
| rust-v0.54 x rust-v0.55 (ws, noise, mplex) | rust-v0.54 | rust-v0.55 | ws | noise | mplex | ✅ | 5s | 133.887 | 43.184 |
| rust-v0.54 x rust-v0.55 (ws, tls, yamux) | rust-v0.54 | rust-v0.55 | ws | tls | yamux | ✅ | 5s | 89.057 | 0.208 |
| rust-v0.54 x rust-v0.55 (ws, noise, yamux) | rust-v0.54 | rust-v0.55 | ws | noise | yamux | ✅ | 5s | 93.51 | 0.209 |
| rust-v0.54 x rust-v0.55 (tcp, tls, mplex) | rust-v0.54 | rust-v0.55 | tcp | tls | mplex | ✅ | 6s | 7.292 | 0.078 |
| rust-v0.54 x rust-v0.55 (tcp, tls, yamux) | rust-v0.54 | rust-v0.55 | tcp | tls | yamux | ✅ | 5s | 3.947 | 0.119 |
| rust-v0.54 x rust-v0.55 (tcp, noise, mplex) | rust-v0.54 | rust-v0.55 | tcp | noise | mplex | ✅ | 5s | 47.134 | 0.045 |
| rust-v0.54 x rust-v0.55 (tcp, noise, yamux) | rust-v0.54 | rust-v0.55 | tcp | noise | yamux | ✅ | 5s | 86.384 | 43.57 |
| rust-v0.54 x rust-v0.55 (quic-v1) | rust-v0.54 | rust-v0.55 | quic-v1 | - | - | ✅ | 5s | 3.124 | 0.244 |
| rust-v0.54 x rust-v0.55 (webrtc-direct) | rust-v0.54 | rust-v0.55 | webrtc-direct | - | - | ✅ | 5s | 208.388 | 0.224 |
| rust-v0.54 x rust-v0.56 (ws, tls, mplex) | rust-v0.54 | rust-v0.56 | ws | tls | mplex | ✅ | 4s | 140.64 | 42.741 |
| rust-v0.54 x rust-v0.56 (ws, tls, yamux) | rust-v0.54 | rust-v0.56 | ws | tls | yamux | ✅ | 5s | 138.04 | 41.971 |
| rust-v0.54 x rust-v0.56 (ws, noise, mplex) | rust-v0.54 | rust-v0.56 | ws | noise | mplex | ✅ | 4s | 136.806 | 47.213 |
| rust-v0.54 x rust-v0.56 (ws, noise, yamux) | rust-v0.54 | rust-v0.56 | ws | noise | yamux | ✅ | 4s | 134.144 | 43.33 |
| rust-v0.54 x rust-v0.56 (tcp, tls, mplex) | rust-v0.54 | rust-v0.56 | tcp | tls | mplex | ✅ | 5s | 43.999 | 40.653 |
| rust-v0.54 x rust-v0.56 (tcp, tls, yamux) | rust-v0.54 | rust-v0.56 | tcp | tls | yamux | ✅ | 4s | 49.871 | 46.455 |
| rust-v0.54 x rust-v0.56 (tcp, noise, mplex) | rust-v0.54 | rust-v0.56 | tcp | noise | mplex | ✅ | 5s | 94.304 | 47.553 |
| rust-v0.54 x rust-v0.56 (tcp, noise, yamux) | rust-v0.54 | rust-v0.56 | tcp | noise | yamux | ✅ | 5s | 44.276 | 0.132 |
| rust-v0.54 x rust-v0.56 (quic-v1) | rust-v0.54 | rust-v0.56 | quic-v1 | - | - | ✅ | 5s | 4.948 | 0.415 |
| rust-v0.54 x rust-v0.56 (webrtc-direct) | rust-v0.54 | rust-v0.56 | webrtc-direct | - | - | ✅ | 5s | 214.959 | 0.41 |
| rust-v0.54 x go-v0.38 (ws, tls, yamux) | rust-v0.54 | go-v0.38 | ws | tls | yamux | ✅ | 4s | 93.094 | 0.629 |
| rust-v0.54 x go-v0.38 (ws, noise, yamux) | rust-v0.54 | go-v0.38 | ws | noise | yamux | ✅ | 5s | 136.032 | 42.361 |
| rust-v0.54 x go-v0.38 (tcp, noise, yamux) | rust-v0.54 | go-v0.38 | tcp | noise | yamux | ✅ | 4s | 2.806 | 0.424 |
| rust-v0.54 x go-v0.38 (tcp, tls, yamux) | rust-v0.54 | go-v0.38 | tcp | tls | yamux | ✅ | 5s | 4.818 | 0.304 |
| rust-v0.54 x go-v0.38 (quic-v1) | rust-v0.54 | go-v0.38 | quic-v1 | - | - | ✅ | 5s | 3.876 | 0.196 |
| rust-v0.54 x go-v0.39 (ws, tls, yamux) | rust-v0.54 | go-v0.39 | ws | tls | yamux | ✅ | 4s | 129.845 | 42.09 |
| rust-v0.54 x go-v0.38 (webrtc-direct) | rust-v0.54 | go-v0.38 | webrtc-direct | - | - | ✅ | 4s | 55.59 | 0.354 |
| rust-v0.54 x go-v0.39 (ws, noise, yamux) | rust-v0.54 | go-v0.39 | ws | noise | yamux | ✅ | 5s | 94.621 | 0.569 |
| rust-v0.54 x go-v0.39 (tcp, tls, yamux) | rust-v0.54 | go-v0.39 | tcp | tls | yamux | ✅ | 4s | 49.003 | 44.651 |
| rust-v0.54 x go-v0.39 (tcp, noise, yamux) | rust-v0.54 | go-v0.39 | tcp | noise | yamux | ✅ | 5s | 5.23 | 0.996 |
| rust-v0.54 x go-v0.39 (quic-v1) | rust-v0.54 | go-v0.39 | quic-v1 | - | - | ✅ | 5s | 5.639 | 0.547 |
| rust-v0.54 x go-v0.39 (webrtc-direct) | rust-v0.54 | go-v0.39 | webrtc-direct | - | - | ✅ | 5s | 9.124 | 0.223 |
| rust-v0.54 x go-v0.40 (ws, tls, yamux) | rust-v0.54 | go-v0.40 | ws | tls | yamux | ✅ | 5s | 129.912 | 41.694 |
| rust-v0.54 x go-v0.40 (ws, noise, yamux) | rust-v0.54 | go-v0.40 | ws | noise | yamux | ✅ | 4s | 92.413 | 0.211 |
| rust-v0.54 x go-v0.40 (tcp, tls, yamux) | rust-v0.54 | go-v0.40 | tcp | tls | yamux | ✅ | 5s | 5.716 | 0.263 |
| rust-v0.54 x go-v0.40 (tcp, noise, yamux) | rust-v0.54 | go-v0.40 | tcp | noise | yamux | ✅ | 5s | 3.954 | 0.163 |
| rust-v0.54 x go-v0.40 (quic-v1) | rust-v0.54 | go-v0.40 | quic-v1 | - | - | ✅ | 4s | 4.61 | 0.309 |
| rust-v0.54 x go-v0.40 (webrtc-direct) | rust-v0.54 | go-v0.40 | webrtc-direct | - | - | ✅ | 5s | 6.444 | 0.237 |
| rust-v0.54 x go-v0.41 (ws, tls, yamux) | rust-v0.54 | go-v0.41 | ws | tls | yamux | ✅ | 5s | 87.153 | 0.543 |
| rust-v0.54 x go-v0.41 (ws, noise, yamux) | rust-v0.54 | go-v0.41 | ws | noise | yamux | ✅ | 5s | 140.584 | 46.771 |
| rust-v0.54 x go-v0.41 (tcp, tls, yamux) | rust-v0.54 | go-v0.41 | tcp | tls | yamux | ✅ | 5s | 3.272 | 0.19 |
| rust-v0.54 x go-v0.41 (tcp, noise, yamux) | rust-v0.54 | go-v0.41 | tcp | noise | yamux | ✅ | 5s | 3.087 | 0.375 |
| rust-v0.54 x go-v0.41 (quic-v1) | rust-v0.54 | go-v0.41 | quic-v1 | - | - | ✅ | 5s | 4.509 | 0.223 |
| rust-v0.54 x go-v0.42 (ws, tls, yamux) | rust-v0.54 | go-v0.42 | ws | tls | yamux | ✅ | 4s | 132.505 | 42.663 |
| rust-v0.54 x go-v0.41 (webrtc-direct) | rust-v0.54 | go-v0.41 | webrtc-direct | - | - | ✅ | 5s | 8.891 | 0.402 |
| rust-v0.54 x go-v0.42 (ws, noise, yamux) | rust-v0.54 | go-v0.42 | ws | noise | yamux | ✅ | 5s | 92.255 | 0.944 |
| rust-v0.54 x go-v0.42 (tcp, noise, yamux) | rust-v0.54 | go-v0.42 | tcp | noise | yamux | ✅ | 5s | 3.331 | 0.671 |
| rust-v0.54 x go-v0.42 (tcp, tls, yamux) | rust-v0.54 | go-v0.42 | tcp | tls | yamux | ✅ | 5s | 48.754 | 1.753 |
| rust-v0.54 x go-v0.42 (quic-v1) | rust-v0.54 | go-v0.42 | quic-v1 | - | - | ✅ | 4s | 4.415 | 0.232 |
| rust-v0.54 x go-v0.42 (webrtc-direct) | rust-v0.54 | go-v0.42 | webrtc-direct | - | - | ✅ | 5s | 8.16 | 0.236 |
| rust-v0.54 x go-v0.43 (ws, noise, yamux) | rust-v0.54 | go-v0.43 | ws | noise | yamux | ✅ | 4s | 91.273 | 0.607 |
| rust-v0.54 x go-v0.43 (ws, tls, yamux) | rust-v0.54 | go-v0.43 | ws | tls | yamux | ✅ | 6s | 139.226 | 46.074 |
| rust-v0.54 x go-v0.43 (tcp, noise, yamux) | rust-v0.54 | go-v0.43 | tcp | noise | yamux | ✅ | 5s | 2.794 | 0.194 |
| rust-v0.54 x go-v0.43 (tcp, tls, yamux) | rust-v0.54 | go-v0.43 | tcp | tls | yamux | ✅ | 6s | 3.042 | 0.459 |
| rust-v0.54 x go-v0.43 (webrtc-direct) | rust-v0.54 | go-v0.43 | webrtc-direct | - | - | ✅ | 5s | 19.566 | 0.291 |
| rust-v0.54 x go-v0.43 (quic-v1) | rust-v0.54 | go-v0.43 | quic-v1 | - | - | ✅ | 5s | 4.473 | 0.345 |
| rust-v0.54 x go-v0.44 (ws, tls, yamux) | rust-v0.54 | go-v0.44 | ws | tls | yamux | ✅ | 4s | 89.353 | 0.379 |
| rust-v0.54 x go-v0.44 (ws, noise, yamux) | rust-v0.54 | go-v0.44 | ws | noise | yamux | ✅ | 5s | 93.798 | 0.251 |
| rust-v0.54 x go-v0.44 (tcp, tls, yamux) | rust-v0.54 | go-v0.44 | tcp | tls | yamux | ✅ | 5s | 46.991 | 0.991 |
| rust-v0.54 x go-v0.44 (tcp, noise, yamux) | rust-v0.54 | go-v0.44 | tcp | noise | yamux | ✅ | 5s | 47.607 | 0.106 |
| rust-v0.54 x go-v0.44 (quic-v1) | rust-v0.54 | go-v0.44 | quic-v1 | - | - | ✅ | 5s | 4.64 | 0.243 |
| rust-v0.54 x go-v0.44 (webrtc-direct) | rust-v0.54 | go-v0.44 | webrtc-direct | - | - | ✅ | 5s | 6.924 | 0.193 |
| rust-v0.54 x go-v0.45 (ws, tls, yamux) | rust-v0.54 | go-v0.45 | ws | tls | yamux | ✅ | 4s | 95.683 | 0.342 |
| rust-v0.54 x go-v0.45 (ws, noise, yamux) | rust-v0.54 | go-v0.45 | ws | noise | yamux | ✅ | 5s | 136.947 | 42.783 |
| rust-v0.54 x go-v0.45 (tcp, tls, yamux) | rust-v0.54 | go-v0.45 | tcp | tls | yamux | ✅ | 5s | 3.56 | 0.735 |
| rust-v0.54 x go-v0.45 (tcp, noise, yamux) | rust-v0.54 | go-v0.45 | tcp | noise | yamux | ✅ | 5s | 3.593 | 0.098 |
| rust-v0.54 x go-v0.45 (quic-v1) | rust-v0.54 | go-v0.45 | quic-v1 | - | - | ✅ | 4s | 7.726 | 1.151 |
| rust-v0.54 x go-v0.45 (webrtc-direct) | rust-v0.54 | go-v0.45 | webrtc-direct | - | - | ✅ | 5s | 96.376 | 0.424 |
| rust-v0.54 x python-v0.4 (ws, noise, mplex) | rust-v0.54 | python-v0.4 | ws | noise | mplex | ✅ | 5s | 102.867 | 1.611 |
| rust-v0.54 x python-v0.4 (ws, noise, yamux) | rust-v0.54 | python-v0.4 | ws | noise | yamux | ✅ | 5s | 94.877 | 0.899 |
| rust-v0.54 x python-v0.4 (tcp, noise, mplex) | rust-v0.54 | python-v0.4 | tcp | noise | mplex | ✅ | 5s | 12.291 | 0.517 |
| rust-v0.54 x python-v0.4 (tcp, noise, yamux) | rust-v0.54 | python-v0.4 | tcp | noise | yamux | ✅ | 4s | 17.557 | 0.613 |
| rust-v0.54 x python-v0.4 (quic-v1) | rust-v0.54 | python-v0.4 | quic-v1 | - | - | ✅ | 5s | 65.276 | 8.359 |
| rust-v0.54 x js-v1.x (ws, noise, mplex) | rust-v0.54 | js-v1.x | ws | noise | mplex | ✅ | 14s | 199.019 | 18.374 |
| rust-v0.54 x js-v1.x (ws, noise, yamux) | rust-v0.54 | js-v1.x | ws | noise | yamux | ✅ | 14s | 173.875 | 11.44 |
| rust-v0.54 x js-v1.x (tcp, noise, mplex) | rust-v0.54 | js-v1.x | tcp | noise | mplex | ✅ | 15s | 142.083 | 22.731 |
| rust-v0.54 x js-v1.x (tcp, noise, yamux) | rust-v0.54 | js-v1.x | tcp | noise | yamux | ✅ | 15s | 145.108 | 5.926 |
| rust-v0.54 x js-v2.x (ws, noise, mplex) | rust-v0.54 | js-v2.x | ws | noise | mplex | ✅ | 15s | 180.21 | 11.334 |
| rust-v0.54 x js-v2.x (ws, noise, yamux) | rust-v0.54 | js-v2.x | ws | noise | yamux | ✅ | 16s | 189.313 | 31.879 |
| rust-v0.54 x js-v2.x (tcp, noise, mplex) | rust-v0.54 | js-v2.x | tcp | noise | mplex | ✅ | 16s | 156.577 | 6.311 |
| rust-v0.54 x js-v2.x (tcp, noise, yamux) | rust-v0.54 | js-v2.x | tcp | noise | yamux | ✅ | 15s | 115.394 | 8.718 |
| rust-v0.54 x nim-v1.14 (ws, noise, mplex) | rust-v0.54 | nim-v1.14 | ws | noise | mplex | ✅ | 3s | 277.406 | 91.774 |
| rust-v0.54 x nim-v1.14 (ws, noise, yamux) | rust-v0.54 | nim-v1.14 | ws | noise | yamux | ✅ | 3s | 232.79 | 45.524 |
| rust-v0.54 x nim-v1.14 (tcp, noise, mplex) | rust-v0.54 | nim-v1.14 | tcp | noise | mplex | ✅ | 4s | 102.131 | 4.068 |
| rust-v0.54 x nim-v1.14 (tcp, noise, yamux) | rust-v0.54 | nim-v1.14 | tcp | noise | yamux | ✅ | 4s | 186.288 | 44.534 |
| rust-v0.54 x js-v3.x (ws, noise, mplex) | rust-v0.54 | js-v3.x | ws | noise | mplex | ✅ | 13s | 194.823 | 21.452 |
| rust-v0.54 x js-v3.x (ws, noise, yamux) | rust-v0.54 | js-v3.x | ws | noise | yamux | ✅ | 14s | 210.839 | 18.686 |
| rust-v0.54 x js-v3.x (tcp, noise, mplex) | rust-v0.54 | js-v3.x | tcp | noise | mplex | ✅ | 15s | 125.369 | 13.238 |
| rust-v0.54 x js-v3.x (tcp, noise, yamux) | rust-v0.54 | js-v3.x | tcp | noise | yamux | ✅ | 15s | 155.117 | 52.892 |
| rust-v0.54 x jvm-v1.2 (ws, tls, mplex) | rust-v0.54 | jvm-v1.2 | ws | tls | mplex | ✅ | 11s | 3836.17 | 4.325 |
| rust-v0.54 x jvm-v1.2 (ws, noise, mplex) | rust-v0.54 | jvm-v1.2 | ws | noise | mplex | ✅ | 9s | 1344.01 | 48.76 |
| rust-v0.54 x jvm-v1.2 (ws, tls, yamux) | rust-v0.54 | jvm-v1.2 | ws | tls | yamux | ✅ | 11s | 3181.611 | 46.734 |
| rust-v0.54 x jvm-v1.2 (ws, noise, yamux) | rust-v0.54 | jvm-v1.2 | ws | noise | yamux | ✅ | 9s | 935.851 | 44.066 |
| rust-v0.54 x jvm-v1.2 (tcp, tls, mplex) | rust-v0.54 | jvm-v1.2 | tcp | tls | mplex | ✅ | 8s | 1934.508 | 7.208 |
| rust-v0.54 x c-v0.0.1 (tcp, noise, mplex) | rust-v0.54 | c-v0.0.1 | tcp | noise | mplex | ✅ | 5s | 63.309 | 3.74 |
| rust-v0.54 x c-v0.0.1 (tcp, noise, yamux) | rust-v0.54 | c-v0.0.1 | tcp | noise | yamux | ✅ | 4s | 107.968 | 3.719 |
| rust-v0.54 x jvm-v1.2 (tcp, tls, yamux) | rust-v0.54 | jvm-v1.2 | tcp | tls | yamux | ✅ | 10s | 2889.762 | 46.668 |
| rust-v0.54 x jvm-v1.2 (tcp, noise, mplex) | rust-v0.54 | jvm-v1.2 | tcp | noise | mplex | ✅ | 9s | 957.278 | 4.535 |
| rust-v0.54 x jvm-v1.2 (tcp, noise, yamux) | rust-v0.54 | jvm-v1.2 | tcp | noise | yamux | ✅ | 9s | 897.027 | 2.566 |
| rust-v0.54 x jvm-v1.2 (quic-v1) | rust-v0.54 | jvm-v1.2 | quic-v1 | - | - | ✅ | 9s | 994.665 | 3.296 |
| rust-v0.54 x dotnet-v1.0 (tcp, noise, yamux) | rust-v0.54 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 4s | 104.158 | 2.91 |
| rust-v0.54 x zig-v0.0.1 (quic-v1) | rust-v0.54 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 4s | - | - |
| rust-v0.54 x eth-p2p-z-v0.0.1 (quic-v1) | rust-v0.54 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 4s | 3.98 | 0.155 |
| rust-v0.55 x rust-v0.53 (ws, tls, mplex) | rust-v0.55 | rust-v0.53 | ws | tls | mplex | ✅ | 5s | 89.519 | 0.263 |
| rust-v0.55 x rust-v0.53 (ws, noise, mplex) | rust-v0.55 | rust-v0.53 | ws | noise | mplex | ✅ | 4s | 93.025 | 0.192 |
| rust-v0.55 x rust-v0.53 (ws, tls, yamux) | rust-v0.55 | rust-v0.53 | ws | tls | yamux | ✅ | 5s | 135.818 | 47.496 |
| rust-v0.55 x rust-v0.53 (ws, noise, yamux) | rust-v0.55 | rust-v0.53 | ws | noise | yamux | ✅ | 5s | 145.892 | 47.508 |
| rust-v0.55 x rust-v0.53 (tcp, tls, mplex) | rust-v0.55 | rust-v0.53 | tcp | tls | mplex | ✅ | 4s | 49.196 | 0.199 |
| rust-v0.55 x rust-v0.53 (tcp, tls, yamux) | rust-v0.55 | rust-v0.53 | tcp | tls | yamux | ✅ | 5s | 86.917 | 43.77 |
| rust-v0.55 x rust-v0.53 (tcp, noise, mplex) | rust-v0.55 | rust-v0.53 | tcp | noise | mplex | ✅ | 5s | 44.691 | 0.128 |
| rust-v0.54 x c-v0.0.1 (quic-v1) | rust-v0.54 | c-v0.0.1 | quic-v1 | - | - | ❌ | 14s | - | - |
| rust-v0.55 x rust-v0.53 (tcp, noise, yamux) | rust-v0.55 | rust-v0.53 | tcp | noise | yamux | ✅ | 5s | 44.531 | 0.108 |
| rust-v0.55 x rust-v0.53 (quic-v1) | rust-v0.55 | rust-v0.53 | quic-v1 | - | - | ✅ | 5s | 4.625 | 0.291 |
| rust-v0.55 x rust-v0.53 (webrtc-direct) | rust-v0.55 | rust-v0.53 | webrtc-direct | - | - | ✅ | 5s | 206.128 | 0.203 |
| rust-v0.55 x rust-v0.54 (ws, tls, mplex) | rust-v0.55 | rust-v0.54 | ws | tls | mplex | ✅ | 4s | 93.184 | 0.197 |
| rust-v0.55 x rust-v0.54 (ws, tls, yamux) | rust-v0.55 | rust-v0.54 | ws | tls | yamux | ✅ | 5s | 89.45 | 0.132 |
| rust-v0.55 x rust-v0.54 (ws, noise, mplex) | rust-v0.55 | rust-v0.54 | ws | noise | mplex | ✅ | 5s | 93.018 | 0.643 |
| rust-v0.55 x rust-v0.54 (ws, noise, yamux) | rust-v0.55 | rust-v0.54 | ws | noise | yamux | ✅ | 4s | 141.556 | 43.331 |
| rust-v0.55 x rust-v0.54 (tcp, tls, mplex) | rust-v0.55 | rust-v0.54 | tcp | tls | mplex | ✅ | 4s | 50.538 | 0.299 |
| rust-v0.55 x rust-v0.54 (tcp, tls, yamux) | rust-v0.55 | rust-v0.54 | tcp | tls | yamux | ✅ | 5s | 88.004 | 43.623 |
| rust-v0.55 x rust-v0.54 (tcp, noise, mplex) | rust-v0.55 | rust-v0.54 | tcp | noise | mplex | ✅ | 5s | 2.431 | 0.08 |
| rust-v0.55 x rust-v0.54 (quic-v1) | rust-v0.55 | rust-v0.54 | quic-v1 | - | - | ✅ | 4s | 3.698 | 0.328 |
| rust-v0.55 x rust-v0.54 (tcp, noise, yamux) | rust-v0.55 | rust-v0.54 | tcp | noise | yamux | ✅ | 6s | 47.959 | 2.287 |
| rust-v0.55 x rust-v0.54 (webrtc-direct) | rust-v0.55 | rust-v0.54 | webrtc-direct | - | - | ✅ | 5s | 210.759 | 0.375 |
| rust-v0.55 x rust-v0.55 (ws, tls, mplex) | rust-v0.55 | rust-v0.55 | ws | tls | mplex | ✅ | 5s | 3.575 | 0.027 |
| rust-v0.55 x rust-v0.55 (ws, tls, yamux) | rust-v0.55 | rust-v0.55 | ws | tls | yamux | ✅ | 4s | 10.591 | 0.378 |
| rust-v0.55 x rust-v0.55 (ws, noise, mplex) | rust-v0.55 | rust-v0.55 | ws | noise | mplex | ✅ | 5s | 2.315 | 0.066 |
| rust-v0.55 x rust-v0.55 (ws, noise, yamux) | rust-v0.55 | rust-v0.55 | ws | noise | yamux | ✅ | 5s | 2.633 | 0.119 |
| rust-v0.55 x rust-v0.55 (tcp, tls, mplex) | rust-v0.55 | rust-v0.55 | tcp | tls | mplex | ✅ | 5s | 12.259 | 0.071 |
| rust-v0.55 x rust-v0.55 (tcp, tls, yamux) | rust-v0.55 | rust-v0.55 | tcp | tls | yamux | ✅ | 4s | 3.753 | 0.125 |
| rust-v0.55 x rust-v0.55 (tcp, noise, mplex) | rust-v0.55 | rust-v0.55 | tcp | noise | mplex | ✅ | 5s | 1.766 | 0.047 |
| rust-v0.55 x rust-v0.55 (tcp, noise, yamux) | rust-v0.55 | rust-v0.55 | tcp | noise | yamux | ✅ | 5s | 2.912 | 0.169 |
| rust-v0.55 x rust-v0.55 (quic-v1) | rust-v0.55 | rust-v0.55 | quic-v1 | - | - | ✅ | 5s | 3.336 | 0.192 |
| rust-v0.55 x rust-v0.56 (ws, tls, mplex) | rust-v0.55 | rust-v0.56 | ws | tls | mplex | ✅ | 5s | 13.191 | 0.104 |
| rust-v0.55 x rust-v0.55 (webrtc-direct) | rust-v0.55 | rust-v0.55 | webrtc-direct | - | - | ✅ | 5s | 209.013 | 0.268 |
| rust-v0.55 x rust-v0.56 (ws, tls, yamux) | rust-v0.55 | rust-v0.56 | ws | tls | yamux | ✅ | 4s | 6.696 | 0.311 |
| rust-v0.55 x rust-v0.56 (ws, noise, mplex) | rust-v0.55 | rust-v0.56 | ws | noise | mplex | ✅ | 5s | 2.62 | 0.054 |
| rust-v0.55 x rust-v0.56 (tcp, tls, yamux) | rust-v0.55 | rust-v0.56 | tcp | tls | yamux | ✅ | 5s | 3.084 | 0.121 |
| rust-v0.55 x rust-v0.56 (ws, noise, yamux) | rust-v0.55 | rust-v0.56 | ws | noise | yamux | ✅ | 6s | 6.585 | 0.153 |
| rust-v0.55 x rust-v0.56 (tcp, tls, mplex) | rust-v0.55 | rust-v0.56 | tcp | tls | mplex | ✅ | 5s | 2.338 | 0.041 |
| rust-v0.55 x rust-v0.56 (tcp, noise, mplex) | rust-v0.55 | rust-v0.56 | tcp | noise | mplex | ✅ | 5s | 2.332 | 0.049 |
| rust-v0.55 x rust-v0.56 (tcp, noise, yamux) | rust-v0.55 | rust-v0.56 | tcp | noise | yamux | ✅ | 5s | 2.381 | 0.114 |
| rust-v0.55 x rust-v0.56 (quic-v1) | rust-v0.55 | rust-v0.56 | quic-v1 | - | - | ✅ | 5s | 4.661 | 0.333 |
| rust-v0.55 x rust-v0.56 (webrtc-direct) | rust-v0.55 | rust-v0.56 | webrtc-direct | - | - | ✅ | 4s | 303.062 | 0.232 |
| rust-v0.55 x go-v0.38 (ws, tls, yamux) | rust-v0.55 | go-v0.38 | ws | tls | yamux | ✅ | 5s | 3.535 | 0.202 |
| rust-v0.55 x go-v0.38 (ws, noise, yamux) | rust-v0.55 | go-v0.38 | ws | noise | yamux | ✅ | 5s | 3.252 | 0.118 |
| rust-v0.55 x go-v0.38 (tcp, tls, yamux) | rust-v0.55 | go-v0.38 | tcp | tls | yamux | ✅ | 5s | 9.593 | 0.297 |
| rust-v0.55 x go-v0.38 (tcp, noise, yamux) | rust-v0.55 | go-v0.38 | tcp | noise | yamux | ✅ | 5s | 2.916 | 0.305 |
| rust-v0.55 x go-v0.38 (quic-v1) | rust-v0.55 | go-v0.38 | quic-v1 | - | - | ✅ | 6s | 5.803 | 1.594 |
| rust-v0.55 x go-v0.38 (webrtc-direct) | rust-v0.55 | go-v0.38 | webrtc-direct | - | - | ✅ | 5s | 47.034 | 0.475 |
| rust-v0.55 x go-v0.39 (ws, tls, yamux) | rust-v0.55 | go-v0.39 | ws | tls | yamux | ✅ | 4s | 3.565 | 0.12 |
| rust-v0.55 x go-v0.39 (ws, noise, yamux) | rust-v0.55 | go-v0.39 | ws | noise | yamux | ✅ | 5s | 5.672 | 0.234 |
| rust-v0.55 x go-v0.39 (tcp, tls, yamux) | rust-v0.55 | go-v0.39 | tcp | tls | yamux | ✅ | 4s | 4.9 | 1.537 |
| rust-v0.55 x go-v0.39 (tcp, noise, yamux) | rust-v0.55 | go-v0.39 | tcp | noise | yamux | ✅ | 4s | 3.918 | 1.741 |
| rust-v0.55 x go-v0.39 (quic-v1) | rust-v0.55 | go-v0.39 | quic-v1 | - | - | ✅ | 5s | 4.538 | 0.303 |
| rust-v0.55 x go-v0.39 (webrtc-direct) | rust-v0.55 | go-v0.39 | webrtc-direct | - | - | ✅ | 5s | 158.165 | 0.784 |
| rust-v0.55 x go-v0.40 (ws, tls, yamux) | rust-v0.55 | go-v0.40 | ws | tls | yamux | ✅ | 5s | 9.594 | 0.239 |
| rust-v0.55 x go-v0.40 (ws, noise, yamux) | rust-v0.55 | go-v0.40 | ws | noise | yamux | ✅ | 4s | 6.288 | 0.772 |
| rust-v0.55 x go-v0.40 (tcp, tls, yamux) | rust-v0.55 | go-v0.40 | tcp | tls | yamux | ✅ | 5s | 4.378 | 0.562 |
| rust-v0.55 x go-v0.40 (tcp, noise, yamux) | rust-v0.55 | go-v0.40 | tcp | noise | yamux | ✅ | 4s | 4.366 | 0.173 |
| rust-v0.55 x go-v0.40 (quic-v1) | rust-v0.55 | go-v0.40 | quic-v1 | - | - | ✅ | 5s | 7.272 | 0.325 |
| rust-v0.55 x go-v0.40 (webrtc-direct) | rust-v0.55 | go-v0.40 | webrtc-direct | - | - | ✅ | 4s | 11.112 | 0.297 |
| rust-v0.55 x go-v0.41 (ws, tls, yamux) | rust-v0.55 | go-v0.41 | ws | tls | yamux | ✅ | 5s | 8.032 | 1.018 |
| rust-v0.55 x go-v0.41 (ws, noise, yamux) | rust-v0.55 | go-v0.41 | ws | noise | yamux | ✅ | 4s | 5.902 | 0.76 |
| rust-v0.55 x go-v0.41 (tcp, tls, yamux) | rust-v0.55 | go-v0.41 | tcp | tls | yamux | ✅ | 5s | 5.59 | 0.162 |
| rust-v0.55 x go-v0.41 (tcp, noise, yamux) | rust-v0.55 | go-v0.41 | tcp | noise | yamux | ✅ | 4s | 2.232 | 0.135 |
| rust-v0.55 x go-v0.41 (quic-v1) | rust-v0.55 | go-v0.41 | quic-v1 | - | - | ✅ | 5s | 6.419 | 0.21 |
| rust-v0.55 x go-v0.42 (ws, tls, yamux) | rust-v0.55 | go-v0.42 | ws | tls | yamux | ✅ | 5s | 9.466 | 0.578 |
| rust-v0.55 x go-v0.41 (webrtc-direct) | rust-v0.55 | go-v0.41 | webrtc-direct | - | - | ✅ | 5s | 14.376 | 0.465 |
| rust-v0.55 x go-v0.42 (ws, noise, yamux) | rust-v0.55 | go-v0.42 | ws | noise | yamux | ✅ | 5s | 8.161 | 0.835 |
| rust-v0.55 x go-v0.42 (tcp, tls, yamux) | rust-v0.55 | go-v0.42 | tcp | tls | yamux | ✅ | 5s | 3.617 | 0.296 |
| rust-v0.55 x go-v0.42 (tcp, noise, yamux) | rust-v0.55 | go-v0.42 | tcp | noise | yamux | ✅ | 5s | 3.756 | 0.413 |
| rust-v0.55 x go-v0.42 (quic-v1) | rust-v0.55 | go-v0.42 | quic-v1 | - | - | ✅ | 5s | 5.035 | 0.333 |
| rust-v0.55 x go-v0.42 (webrtc-direct) | rust-v0.55 | go-v0.42 | webrtc-direct | - | - | ✅ | 4s | 14.133 | 1.337 |
| rust-v0.55 x go-v0.43 (ws, tls, yamux) | rust-v0.55 | go-v0.43 | ws | tls | yamux | ✅ | 5s | 3.206 | 0.347 |
| rust-v0.55 x go-v0.43 (ws, noise, yamux) | rust-v0.55 | go-v0.43 | ws | noise | yamux | ✅ | 4s | 3.778 | 0.71 |
| rust-v0.55 x go-v0.43 (tcp, tls, yamux) | rust-v0.55 | go-v0.43 | tcp | tls | yamux | ✅ | 4s | 8.116 | 0.579 |
| rust-v0.55 x go-v0.43 (tcp, noise, yamux) | rust-v0.55 | go-v0.43 | tcp | noise | yamux | ✅ | 5s | 14.142 | 0.133 |
| rust-v0.55 x go-v0.43 (quic-v1) | rust-v0.55 | go-v0.43 | quic-v1 | - | - | ✅ | 4s | 9.366 | 0.503 |
| rust-v0.55 x go-v0.43 (webrtc-direct) | rust-v0.55 | go-v0.43 | webrtc-direct | - | - | ✅ | 4s | 208.541 | 0.416 |
| rust-v0.55 x go-v0.44 (ws, tls, yamux) | rust-v0.55 | go-v0.44 | ws | tls | yamux | ✅ | 5s | 5.539 | 0.674 |
| rust-v0.55 x go-v0.44 (ws, noise, yamux) | rust-v0.55 | go-v0.44 | ws | noise | yamux | ✅ | 4s | 3.551 | 0.158 |
| rust-v0.55 x go-v0.44 (tcp, tls, yamux) | rust-v0.55 | go-v0.44 | tcp | tls | yamux | ✅ | 5s | 2.835 | 0.192 |
| rust-v0.55 x go-v0.44 (tcp, noise, yamux) | rust-v0.55 | go-v0.44 | tcp | noise | yamux | ✅ | 5s | 8.632 | 0.569 |
| rust-v0.55 x go-v0.44 (quic-v1) | rust-v0.55 | go-v0.44 | quic-v1 | - | - | ✅ | 4s | 20.13 | 1.061 |
| rust-v0.55 x go-v0.44 (webrtc-direct) | rust-v0.55 | go-v0.44 | webrtc-direct | - | - | ✅ | 5s | 23.077 | 0.367 |
| rust-v0.55 x go-v0.45 (ws, tls, yamux) | rust-v0.55 | go-v0.45 | ws | tls | yamux | ✅ | 4s | 4.614 | 0.257 |
| rust-v0.55 x go-v0.45 (ws, noise, yamux) | rust-v0.55 | go-v0.45 | ws | noise | yamux | ✅ | 5s | 4.738 | 0.277 |
| rust-v0.55 x go-v0.45 (tcp, tls, yamux) | rust-v0.55 | go-v0.45 | tcp | tls | yamux | ✅ | 5s | 4.461 | 0.177 |
| rust-v0.55 x go-v0.45 (tcp, noise, yamux) | rust-v0.55 | go-v0.45 | tcp | noise | yamux | ✅ | 5s | 7.888 | 0.864 |
| rust-v0.55 x go-v0.45 (quic-v1) | rust-v0.55 | go-v0.45 | quic-v1 | - | - | ✅ | 5s | 6.58 | 0.968 |
| rust-v0.55 x go-v0.45 (webrtc-direct) | rust-v0.55 | go-v0.45 | webrtc-direct | - | - | ✅ | 5s | 8.908 | 0.249 |
| rust-v0.55 x python-v0.4 (ws, noise, mplex) | rust-v0.55 | python-v0.4 | ws | noise | mplex | ✅ | 4s | 11.189 | 0.829 |
| rust-v0.55 x python-v0.4 (ws, noise, yamux) | rust-v0.55 | python-v0.4 | ws | noise | yamux | ✅ | 5s | 13.97 | 0.979 |
| rust-v0.55 x python-v0.4 (tcp, noise, mplex) | rust-v0.55 | python-v0.4 | tcp | noise | mplex | ✅ | 5s | 10.204 | 0.615 |
| rust-v0.55 x python-v0.4 (tcp, noise, yamux) | rust-v0.55 | python-v0.4 | tcp | noise | yamux | ✅ | 6s | 14.195 | 1.129 |
| rust-v0.55 x python-v0.4 (quic-v1) | rust-v0.55 | python-v0.4 | quic-v1 | - | - | ✅ | 5s | 44.782 | 4.752 |
| rust-v0.55 x js-v1.x (ws, noise, mplex) | rust-v0.55 | js-v1.x | ws | noise | mplex | ✅ | 17s | 158.773 | 20.381 |
| rust-v0.55 x js-v1.x (tcp, noise, mplex) | rust-v0.55 | js-v1.x | tcp | noise | mplex | ✅ | 17s | 99.775 | 10.53 |
| rust-v0.55 x js-v1.x (ws, noise, yamux) | rust-v0.55 | js-v1.x | ws | noise | yamux | ✅ | 18s | 164.88 | 14.118 |
| rust-v0.55 x js-v1.x (tcp, noise, yamux) | rust-v0.55 | js-v1.x | tcp | noise | yamux | ✅ | 17s | 129.806 | 10.337 |
| rust-v0.55 x js-v2.x (ws, noise, mplex) | rust-v0.55 | js-v2.x | ws | noise | mplex | ✅ | 17s | 110.673 | 13.748 |
| rust-v0.55 x js-v2.x (ws, noise, yamux) | rust-v0.55 | js-v2.x | ws | noise | yamux | ✅ | 18s | 170.501 | 17.513 |
| rust-v0.55 x js-v2.x (tcp, noise, mplex) | rust-v0.55 | js-v2.x | tcp | noise | mplex | ✅ | 17s | 76.964 | 9.911 |
| rust-v0.55 x js-v2.x (tcp, noise, yamux) | rust-v0.55 | js-v2.x | tcp | noise | yamux | ✅ | 16s | 89.273 | 10.679 |
| rust-v0.55 x nim-v1.14 (ws, noise, mplex) | rust-v0.55 | nim-v1.14 | ws | noise | mplex | ✅ | 4s | 151.817 | 43.669 |
| rust-v0.55 x nim-v1.14 (ws, noise, yamux) | rust-v0.55 | nim-v1.14 | ws | noise | yamux | ✅ | 4s | 105.363 | 4.935 |
| rust-v0.55 x nim-v1.14 (tcp, noise, mplex) | rust-v0.55 | nim-v1.14 | tcp | noise | mplex | ✅ | 4s | 66.478 | 0.548 |
| rust-v0.55 x nim-v1.14 (tcp, noise, yamux) | rust-v0.55 | nim-v1.14 | tcp | noise | yamux | ✅ | 4s | 74.36 | 5.017 |
| rust-v0.55 x js-v3.x (ws, noise, mplex) | rust-v0.55 | js-v3.x | ws | noise | mplex | ✅ | 17s | 191.443 | 19.435 |
| rust-v0.55 x js-v3.x (ws, noise, yamux) | rust-v0.55 | js-v3.x | ws | noise | yamux | ✅ | 16s | 247.558 | 13.054 |
| rust-v0.55 x js-v3.x (tcp, noise, mplex) | rust-v0.55 | js-v3.x | tcp | noise | mplex | ✅ | 18s | 123.125 | 18.984 |
| rust-v0.55 x jvm-v1.2 (ws, tls, mplex) | rust-v0.55 | jvm-v1.2 | ws | tls | mplex | ✅ | 12s | 4132.013 | 5.515 |
| rust-v0.55 x jvm-v1.2 (ws, noise, mplex) | rust-v0.55 | jvm-v1.2 | ws | noise | mplex | ✅ | 11s | 1325.054 | 40.537 |
| rust-v0.55 x js-v3.x (tcp, noise, yamux) | rust-v0.55 | js-v3.x | tcp | noise | yamux | ✅ | 19s | 118.844 | 28.048 |
| rust-v0.55 x jvm-v1.2 (ws, noise, yamux) | rust-v0.55 | jvm-v1.2 | ws | noise | yamux | ✅ | 10s | 1373.129 | 7.057 |
| rust-v0.55 x jvm-v1.2 (ws, tls, yamux) | rust-v0.55 | jvm-v1.2 | ws | tls | yamux | ✅ | 13s | 3558.414 | 4.133 |
| rust-v0.55 x c-v0.0.1 (tcp, noise, mplex) | rust-v0.55 | c-v0.0.1 | tcp | noise | mplex | ✅ | 5s | 22.172 | 13.26 |
| rust-v0.55 x c-v0.0.1 (tcp, noise, yamux) | rust-v0.55 | c-v0.0.1 | tcp | noise | yamux | ✅ | 6s | 61.267 | 1.279 |
| rust-v0.55 x c-v0.0.1 (quic-v1) | rust-v0.55 | c-v0.0.1 | quic-v1 | - | - | ✅ | 5s | 17.64 | 0.383 |
| rust-v0.55 x jvm-v1.2 (tcp, noise, mplex) | rust-v0.55 | jvm-v1.2 | tcp | noise | mplex | ✅ | 10s | 1393.014 | 13.563 |
| rust-v0.55 x jvm-v1.2 (tcp, noise, yamux) | rust-v0.55 | jvm-v1.2 | tcp | noise | yamux | ✅ | 9s | 1385.272 | 7.24 |
| rust-v0.55 x jvm-v1.2 (tcp, tls, yamux) | rust-v0.55 | jvm-v1.2 | tcp | tls | yamux | ✅ | 12s | 3010.624 | 5.339 |
| rust-v0.55 x jvm-v1.2 (tcp, tls, mplex) | rust-v0.55 | jvm-v1.2 | tcp | tls | mplex | ✅ | 13s | 3828.556 | 2.972 |
| rust-v0.55 x jvm-v1.2 (quic-v1) | rust-v0.55 | jvm-v1.2 | quic-v1 | - | - | ✅ | 11s | 1147.948 | 4.433 |
| rust-v0.55 x dotnet-v1.0 (tcp, noise, yamux) | rust-v0.55 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 5s | 137.732 | 5.896 |
| rust-v0.55 x zig-v0.0.1 (quic-v1) | rust-v0.55 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 4s | - | - |
| rust-v0.56 x rust-v0.53 (ws, tls, mplex) | rust-v0.56 | rust-v0.53 | ws | tls | mplex | ✅ | 5s | 138.613 | 44.348 |
| rust-v0.55 x eth-p2p-z-v0.0.1 (quic-v1) | rust-v0.55 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 5.337 | 0.237 |
| rust-v0.56 x rust-v0.53 (ws, tls, yamux) | rust-v0.56 | rust-v0.53 | ws | tls | yamux | ✅ | 5s | 138.748 | 43.544 |
| rust-v0.56 x rust-v0.53 (ws, noise, mplex) | rust-v0.56 | rust-v0.53 | ws | noise | mplex | ✅ | 6s | 90.836 | 0.483 |
| rust-v0.56 x rust-v0.53 (ws, noise, yamux) | rust-v0.56 | rust-v0.53 | ws | noise | yamux | ✅ | 5s | 129.994 | 43.758 |
| rust-v0.56 x rust-v0.53 (tcp, tls, mplex) | rust-v0.56 | rust-v0.53 | tcp | tls | mplex | ✅ | 5s | 44.502 | 0.123 |
| rust-v0.56 x rust-v0.53 (tcp, tls, yamux) | rust-v0.56 | rust-v0.53 | tcp | tls | yamux | ✅ | 6s | 93.264 | 47.702 |
| rust-v0.56 x rust-v0.53 (tcp, noise, mplex) | rust-v0.56 | rust-v0.53 | tcp | noise | mplex | ✅ | 5s | 47.18 | 0.121 |
| rust-v0.56 x rust-v0.53 (tcp, noise, yamux) | rust-v0.56 | rust-v0.53 | tcp | noise | yamux | ✅ | 5s | 4.692 | 0.177 |
| rust-v0.56 x rust-v0.53 (quic-v1) | rust-v0.56 | rust-v0.53 | quic-v1 | - | - | ✅ | 4s | 11.648 | 0.51 |
| rust-v0.56 x rust-v0.54 (ws, tls, mplex) | rust-v0.56 | rust-v0.54 | ws | tls | mplex | ✅ | 5s | 93.407 | 0.194 |
| rust-v0.56 x rust-v0.53 (webrtc-direct) | rust-v0.56 | rust-v0.53 | webrtc-direct | - | - | ✅ | 5s | 331.922 | 0.274 |
| rust-v0.56 x rust-v0.54 (ws, tls, yamux) | rust-v0.56 | rust-v0.54 | ws | tls | yamux | ✅ | 5s | 135.079 | 43.673 |
| rust-v0.56 x rust-v0.54 (ws, noise, mplex) | rust-v0.56 | rust-v0.54 | ws | noise | mplex | ✅ | 4s | 92.205 | 3.911 |
| rust-v0.56 x rust-v0.54 (ws, noise, yamux) | rust-v0.56 | rust-v0.54 | ws | noise | yamux | ✅ | 5s | 136.604 | 44.539 |
| rust-v0.56 x rust-v0.54 (tcp, tls, mplex) | rust-v0.56 | rust-v0.54 | tcp | tls | mplex | ✅ | 4s | 47.117 | 0.242 |
| rust-v0.56 x rust-v0.54 (tcp, tls, yamux) | rust-v0.56 | rust-v0.54 | tcp | tls | yamux | ✅ | 5s | 92.642 | 43.663 |
| rust-v0.56 x rust-v0.54 (tcp, noise, mplex) | rust-v0.56 | rust-v0.54 | tcp | noise | mplex | ✅ | 4s | 44.392 | 0.784 |
| rust-v0.56 x rust-v0.54 (quic-v1) | rust-v0.56 | rust-v0.54 | quic-v1 | - | - | ✅ | 4s | 4.151 | 0.256 |
| rust-v0.56 x rust-v0.54 (tcp, noise, yamux) | rust-v0.56 | rust-v0.54 | tcp | noise | yamux | ✅ | 5s | 46.321 | 0.162 |
| rust-v0.56 x rust-v0.54 (webrtc-direct) | rust-v0.56 | rust-v0.54 | webrtc-direct | - | - | ✅ | 5s | 210.567 | 0.453 |
| rust-v0.56 x rust-v0.55 (ws, tls, mplex) | rust-v0.56 | rust-v0.55 | ws | tls | mplex | ✅ | 5s | 5.427 | 0.334 |
| rust-v0.56 x rust-v0.55 (ws, tls, yamux) | rust-v0.56 | rust-v0.55 | ws | tls | yamux | ✅ | 5s | 4.828 | 0.235 |
| rust-v0.56 x rust-v0.55 (ws, noise, mplex) | rust-v0.56 | rust-v0.55 | ws | noise | mplex | ✅ | 5s | 3.088 | 0.157 |
| rust-v0.56 x rust-v0.55 (ws, noise, yamux) | rust-v0.56 | rust-v0.55 | ws | noise | yamux | ✅ | 5s | 3.081 | 0.15 |
| rust-v0.56 x rust-v0.55 (tcp, tls, mplex) | rust-v0.56 | rust-v0.55 | tcp | tls | mplex | ✅ | 5s | 4.912 | 0.061 |
| rust-v0.56 x rust-v0.55 (tcp, tls, yamux) | rust-v0.56 | rust-v0.55 | tcp | tls | yamux | ✅ | 5s | 5.263 | 0.37 |
| rust-v0.56 x rust-v0.55 (tcp, noise, mplex) | rust-v0.56 | rust-v0.55 | tcp | noise | mplex | ✅ | 4s | 2.815 | 0.057 |
| rust-v0.56 x rust-v0.55 (tcp, noise, yamux) | rust-v0.56 | rust-v0.55 | tcp | noise | yamux | ✅ | 6s | 3.017 | 0.146 |
| rust-v0.56 x rust-v0.55 (quic-v1) | rust-v0.56 | rust-v0.55 | quic-v1 | - | - | ✅ | 5s | 6.375 | 0.461 |
| rust-v0.56 x rust-v0.55 (webrtc-direct) | rust-v0.56 | rust-v0.55 | webrtc-direct | - | - | ✅ | 5s | 214.274 | 0.343 |
| rust-v0.56 x rust-v0.56 (ws, tls, mplex) | rust-v0.56 | rust-v0.56 | ws | tls | mplex | ✅ | 5s | 3.561 | 0.117 |
| rust-v0.56 x rust-v0.56 (ws, tls, yamux) | rust-v0.56 | rust-v0.56 | ws | tls | yamux | ✅ | 4s | 3.257 | 0.18 |
| rust-v0.56 x rust-v0.56 (ws, noise, mplex) | rust-v0.56 | rust-v0.56 | ws | noise | mplex | ✅ | 5s | 7.791 | 0.151 |
| rust-v0.56 x rust-v0.56 (tcp, tls, mplex) | rust-v0.56 | rust-v0.56 | tcp | tls | mplex | ✅ | 4s | 2.296 | 0.062 |
| rust-v0.56 x rust-v0.56 (ws, noise, yamux) | rust-v0.56 | rust-v0.56 | ws | noise | yamux | ✅ | 6s | 4.94 | 0.178 |
| rust-v0.56 x rust-v0.56 (tcp, tls, yamux) | rust-v0.56 | rust-v0.56 | tcp | tls | yamux | ✅ | 5s | 5.858 | 0.234 |
| rust-v0.56 x rust-v0.56 (tcp, noise, mplex) | rust-v0.56 | rust-v0.56 | tcp | noise | mplex | ✅ | 4s | 4.074 | 0.075 |
| rust-v0.56 x rust-v0.56 (tcp, noise, yamux) | rust-v0.56 | rust-v0.56 | tcp | noise | yamux | ✅ | 5s | 2.592 | 0.103 |
| rust-v0.56 x rust-v0.56 (quic-v1) | rust-v0.56 | rust-v0.56 | quic-v1 | - | - | ✅ | 4s | 3.794 | 0.236 |
| rust-v0.56 x rust-v0.56 (webrtc-direct) | rust-v0.56 | rust-v0.56 | webrtc-direct | - | - | ✅ | 5s | 207.039 | 0.237 |
| rust-v0.56 x go-v0.38 (ws, tls, yamux) | rust-v0.56 | go-v0.38 | ws | tls | yamux | ✅ | 5s | 6.844 | 0.605 |
| rust-v0.56 x go-v0.38 (ws, noise, yamux) | rust-v0.56 | go-v0.38 | ws | noise | yamux | ✅ | 4s | 4.73 | 0.252 |
| rust-v0.56 x go-v0.38 (tcp, tls, yamux) | rust-v0.56 | go-v0.38 | tcp | tls | yamux | ✅ | 5s | 13.604 | 1.06 |
| rust-v0.56 x go-v0.38 (quic-v1) | rust-v0.56 | go-v0.38 | quic-v1 | - | - | ✅ | 4s | 4.908 | 0.431 |
| rust-v0.56 x go-v0.38 (tcp, noise, yamux) | rust-v0.56 | go-v0.38 | tcp | noise | yamux | ✅ | 6s | 2.413 | 0.124 |
| rust-v0.56 x go-v0.39 (ws, tls, yamux) | rust-v0.56 | go-v0.39 | ws | tls | yamux | ✅ | 4s | 5.23 | 1.071 |
| rust-v0.56 x go-v0.38 (webrtc-direct) | rust-v0.56 | go-v0.38 | webrtc-direct | - | - | ✅ | 5s | 12.317 | 0.388 |
| rust-v0.56 x go-v0.39 (ws, noise, yamux) | rust-v0.56 | go-v0.39 | ws | noise | yamux | ✅ | 5s | 4.425 | 0.275 |
| rust-v0.56 x go-v0.39 (tcp, tls, yamux) | rust-v0.56 | go-v0.39 | tcp | tls | yamux | ✅ | 5s | 4.685 | 0.275 |
| rust-v0.56 x go-v0.39 (tcp, noise, yamux) | rust-v0.56 | go-v0.39 | tcp | noise | yamux | ✅ | 5s | 4.502 | 0.311 |
| rust-v0.56 x go-v0.39 (quic-v1) | rust-v0.56 | go-v0.39 | quic-v1 | - | - | ✅ | 5s | 4.802 | 0.246 |
| rust-v0.56 x go-v0.39 (webrtc-direct) | rust-v0.56 | go-v0.39 | webrtc-direct | - | - | ✅ | 5s | 7.68 | 0.217 |
| rust-v0.56 x go-v0.40 (ws, noise, yamux) | rust-v0.56 | go-v0.40 | ws | noise | yamux | ✅ | 4s | 11.88 | 0.746 |
| rust-v0.56 x go-v0.40 (ws, tls, yamux) | rust-v0.56 | go-v0.40 | ws | tls | yamux | ✅ | 5s | 8.005 | 1.569 |
| rust-v0.56 x go-v0.40 (tcp, tls, yamux) | rust-v0.56 | go-v0.40 | tcp | tls | yamux | ✅ | 5s | 5.215 | 0.827 |
| rust-v0.56 x go-v0.40 (tcp, noise, yamux) | rust-v0.56 | go-v0.40 | tcp | noise | yamux | ✅ | 5s | 5.139 | 0.765 |
| rust-v0.56 x go-v0.40 (quic-v1) | rust-v0.56 | go-v0.40 | quic-v1 | - | - | ✅ | 5s | 4.058 | 0.466 |
| rust-v0.56 x go-v0.40 (webrtc-direct) | rust-v0.56 | go-v0.40 | webrtc-direct | - | - | ✅ | 4s | 18.094 | 0.443 |
| rust-v0.56 x go-v0.41 (ws, tls, yamux) | rust-v0.56 | go-v0.41 | ws | tls | yamux | ✅ | 4s | 6.015 | 0.647 |
| rust-v0.56 x go-v0.41 (ws, noise, yamux) | rust-v0.56 | go-v0.41 | ws | noise | yamux | ✅ | 5s | 3.932 | 0.708 |
| rust-v0.56 x go-v0.41 (tcp, tls, yamux) | rust-v0.56 | go-v0.41 | tcp | tls | yamux | ✅ | 4s | 4.618 | 0.283 |
| rust-v0.56 x go-v0.41 (tcp, noise, yamux) | rust-v0.56 | go-v0.41 | tcp | noise | yamux | ✅ | 5s | 2.384 | 0.113 |
| rust-v0.56 x go-v0.41 (webrtc-direct) | rust-v0.56 | go-v0.41 | webrtc-direct | - | - | ✅ | 4s | 16.768 | 0.591 |
| rust-v0.56 x go-v0.41 (quic-v1) | rust-v0.56 | go-v0.41 | quic-v1 | - | - | ✅ | 6s | 7.253 | 0.684 |
| rust-v0.56 x go-v0.42 (ws, tls, yamux) | rust-v0.56 | go-v0.42 | ws | tls | yamux | ✅ | 5s | 5.304 | 0.554 |
| rust-v0.56 x go-v0.42 (tcp, tls, yamux) | rust-v0.56 | go-v0.42 | tcp | tls | yamux | ✅ | 4s | 6.445 | 0.968 |
| rust-v0.56 x go-v0.42 (ws, noise, yamux) | rust-v0.56 | go-v0.42 | ws | noise | yamux | ✅ | 5s | 5.764 | 0.454 |
| rust-v0.56 x go-v0.42 (tcp, noise, yamux) | rust-v0.56 | go-v0.42 | tcp | noise | yamux | ✅ | 5s | 3.837 | 0.22 |
| rust-v0.56 x go-v0.42 (quic-v1) | rust-v0.56 | go-v0.42 | quic-v1 | - | - | ✅ | 4s | 7.586 | 0.296 |
| rust-v0.56 x go-v0.43 (ws, tls, yamux) | rust-v0.56 | go-v0.43 | ws | tls | yamux | ✅ | 4s | 8.99 | 0.285 |
| rust-v0.56 x go-v0.43 (ws, noise, yamux) | rust-v0.56 | go-v0.43 | ws | noise | yamux | ✅ | 4s | 7.845 | 1.244 |
| rust-v0.56 x go-v0.43 (tcp, tls, yamux) | rust-v0.56 | go-v0.43 | tcp | tls | yamux | ✅ | 5s | 2.795 | 0.312 |
| rust-v0.56 x go-v0.43 (tcp, noise, yamux) | rust-v0.56 | go-v0.43 | tcp | noise | yamux | ✅ | 4s | 5.979 | 0.137 |
| rust-v0.56 x go-v0.43 (quic-v1) | rust-v0.56 | go-v0.43 | quic-v1 | - | - | ✅ | 4s | 8.579 | 2.334 |
| rust-v0.56 x go-v0.43 (webrtc-direct) | rust-v0.56 | go-v0.43 | webrtc-direct | - | - | ✅ | 5s | 8.519 | 0.543 |
| rust-v0.56 x go-v0.44 (ws, tls, yamux) | rust-v0.56 | go-v0.44 | ws | tls | yamux | ✅ | 4s | 4.266 | 0.354 |
| rust-v0.56 x go-v0.44 (tcp, tls, yamux) | rust-v0.56 | go-v0.44 | tcp | tls | yamux | ✅ | 3s | 2.97 | 0.198 |
| rust-v0.56 x go-v0.44 (ws, noise, yamux) | rust-v0.56 | go-v0.44 | ws | noise | yamux | ✅ | 5s | 6.429 | 0.48 |
| rust-v0.56 x go-v0.44 (tcp, noise, yamux) | rust-v0.56 | go-v0.44 | tcp | noise | yamux | ✅ | 5s | 2.766 | 0.115 |
| rust-v0.56 x go-v0.44 (quic-v1) | rust-v0.56 | go-v0.44 | quic-v1 | - | - | ✅ | 4s | 11.263 | 0.19 |
| rust-v0.56 x go-v0.44 (webrtc-direct) | rust-v0.56 | go-v0.44 | webrtc-direct | - | - | ✅ | 4s | 8.977 | 0.278 |
| rust-v0.56 x go-v0.45 (ws, tls, yamux) | rust-v0.56 | go-v0.45 | ws | tls | yamux | ✅ | 5s | 4.477 | 0.402 |
| rust-v0.56 x go-v0.45 (ws, noise, yamux) | rust-v0.56 | go-v0.45 | ws | noise | yamux | ✅ | 4s | 3.932 | 0.471 |
| rust-v0.56 x go-v0.45 (tcp, tls, yamux) | rust-v0.56 | go-v0.45 | tcp | tls | yamux | ✅ | 4s | 6.989 | 0.247 |
| rust-v0.56 x go-v0.45 (tcp, noise, yamux) | rust-v0.56 | go-v0.45 | tcp | noise | yamux | ✅ | 4s | 4.488 | 0.145 |
| rust-v0.56 x go-v0.45 (quic-v1) | rust-v0.56 | go-v0.45 | quic-v1 | - | - | ✅ | 4s | 5.259 | 0.694 |
| rust-v0.56 x go-v0.45 (webrtc-direct) | rust-v0.56 | go-v0.45 | webrtc-direct | - | - | ✅ | 4s | 12.045 | 0.33 |
| rust-v0.56 x python-v0.4 (ws, noise, mplex) | rust-v0.56 | python-v0.4 | ws | noise | mplex | ✅ | 4s | 15.841 | 1.55 |
| rust-v0.56 x python-v0.4 (ws, noise, yamux) | rust-v0.56 | python-v0.4 | ws | noise | yamux | ✅ | 5s | 20.93 | 1.697 |
| rust-v0.56 x python-v0.4 (tcp, noise, mplex) | rust-v0.56 | python-v0.4 | tcp | noise | mplex | ✅ | 5s | 14.778 | 0.961 |
| rust-v0.56 x python-v0.4 (tcp, noise, yamux) | rust-v0.56 | python-v0.4 | tcp | noise | yamux | ✅ | 5s | 17.26 | 1.106 |
| rust-v0.56 x python-v0.4 (quic-v1) | rust-v0.56 | python-v0.4 | quic-v1 | - | - | ✅ | 4s | 22.483 | 2.383 |
| rust-v0.56 x js-v1.x (ws, noise, mplex) | rust-v0.56 | js-v1.x | ws | noise | mplex | ✅ | 16s | 113.861 | 12.714 |
| rust-v0.56 x js-v1.x (ws, noise, yamux) | rust-v0.56 | js-v1.x | ws | noise | yamux | ✅ | 17s | 154.596 | 16.637 |
| rust-v0.56 x js-v1.x (tcp, noise, mplex) | rust-v0.56 | js-v1.x | tcp | noise | mplex | ✅ | 17s | 121.004 | 18.904 |
| rust-v0.56 x js-v1.x (tcp, noise, yamux) | rust-v0.56 | js-v1.x | tcp | noise | yamux | ✅ | 16s | 88.735 | 10.299 |
| rust-v0.56 x js-v2.x (ws, noise, mplex) | rust-v0.56 | js-v2.x | ws | noise | mplex | ✅ | 16s | 94.07 | 11.583 |
| rust-v0.56 x js-v2.x (ws, noise, yamux) | rust-v0.56 | js-v2.x | ws | noise | yamux | ✅ | 16s | 111.653 | 14.176 |
| rust-v0.56 x js-v2.x (tcp, noise, mplex) | rust-v0.56 | js-v2.x | tcp | noise | mplex | ✅ | 17s | 93.7 | 9.656 |
| rust-v0.56 x nim-v1.14 (ws, noise, mplex) | rust-v0.56 | nim-v1.14 | ws | noise | mplex | ✅ | 4s | 105.121 | 1.97 |
| rust-v0.56 x nim-v1.14 (ws, noise, yamux) | rust-v0.56 | nim-v1.14 | ws | noise | yamux | ✅ | 4s | 115.683 | 2.568 |
| rust-v0.56 x nim-v1.14 (tcp, noise, mplex) | rust-v0.56 | nim-v1.14 | tcp | noise | mplex | ✅ | 5s | 121.353 | 43.471 |
| rust-v0.56 x nim-v1.14 (tcp, noise, yamux) | rust-v0.56 | nim-v1.14 | tcp | noise | yamux | ✅ | 4s | 110.336 | 2.151 |
| rust-v0.56 x js-v2.x (tcp, noise, yamux) | rust-v0.56 | js-v2.x | tcp | noise | yamux | ✅ | 16s | 108.099 | 12.172 |
| rust-v0.56 x js-v3.x (ws, noise, mplex) | rust-v0.56 | js-v3.x | ws | noise | mplex | ✅ | 15s | 100.82 | 19.629 |
| rust-v0.56 x js-v3.x (ws, noise, yamux) | rust-v0.56 | js-v3.x | ws | noise | yamux | ✅ | 16s | 102.929 | 15.587 |
| rust-v0.56 x js-v3.x (tcp, noise, mplex) | rust-v0.56 | js-v3.x | tcp | noise | mplex | ✅ | 16s | 112.7 | 48.893 |
| rust-v0.56 x js-v3.x (tcp, noise, yamux) | rust-v0.56 | js-v3.x | tcp | noise | yamux | ✅ | 15s | 81.11 | 22.46 |
| rust-v0.56 x jvm-v1.2 (ws, tls, mplex) | rust-v0.56 | jvm-v1.2 | ws | tls | mplex | ✅ | 10s | 3885.504 | 29.04 |
| rust-v0.56 x jvm-v1.2 (ws, noise, mplex) | rust-v0.56 | jvm-v1.2 | ws | noise | mplex | ✅ | 10s | 2111.001 | 37.3 |
| rust-v0.56 x jvm-v1.2 (ws, noise, yamux) | rust-v0.56 | jvm-v1.2 | ws | noise | yamux | ✅ | 11s | 1779.298 | 8.891 |
| rust-v0.56 x jvm-v1.2 (ws, tls, yamux) | rust-v0.56 | jvm-v1.2 | ws | tls | yamux | ✅ | 12s | 4680.316 | 16.004 |
| rust-v0.56 x jvm-v1.2 (tcp, noise, mplex) | rust-v0.56 | jvm-v1.2 | tcp | noise | mplex | ✅ | 10s | 971.968 | 11.865 |
| rust-v0.56 x jvm-v1.2 (tcp, tls, mplex) | rust-v0.56 | jvm-v1.2 | tcp | tls | mplex | ✅ | 13s | 3199.85 | 6.382 |
| rust-v0.56 x jvm-v1.2 (tcp, tls, yamux) | rust-v0.56 | jvm-v1.2 | tcp | tls | yamux | ✅ | 11s | 2580.196 | 7.062 |
| rust-v0.56 x c-v0.0.1 (tcp, noise, mplex) | rust-v0.56 | c-v0.0.1 | tcp | noise | mplex | ✅ | 4s | 6.723 | 0.133 |
| rust-v0.56 x jvm-v1.2 (tcp, noise, yamux) | rust-v0.56 | jvm-v1.2 | tcp | noise | yamux | ✅ | 8s | 734.35 | 3.768 |
| rust-v0.56 x c-v0.0.1 (tcp, noise, yamux) | rust-v0.56 | c-v0.0.1 | tcp | noise | yamux | ✅ | 4s | 60.891 | 1.043 |
| rust-v0.56 x c-v0.0.1 (quic-v1) | rust-v0.56 | c-v0.0.1 | quic-v1 | - | - | ✅ | 4s | 12.257 | 0.587 |
| rust-v0.56 x jvm-v1.2 (quic-v1) | rust-v0.56 | jvm-v1.2 | quic-v1 | - | - | ✅ | 9s | 1085.967 | 6.373 |
| rust-v0.56 x dotnet-v1.0 (tcp, noise, yamux) | rust-v0.56 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 5s | 133.178 | 8.976 |
| rust-v0.56 x zig-v0.0.1 (quic-v1) | rust-v0.56 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 5s | - | - |
| rust-v0.56 x eth-p2p-z-v0.0.1 (quic-v1) | rust-v0.56 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 4s | 4.484 | 0.192 |
| go-v0.38 x rust-v0.53 (tcp, tls, yamux) | go-v0.38 | rust-v0.53 | tcp | tls | yamux | ✅ | 4s | 138.078 | 44.523 |
| go-v0.38 x rust-v0.53 (ws, tls, yamux) | go-v0.38 | rust-v0.53 | ws | tls | yamux | ✅ | 3s | 189.194 | 47.237 |
| go-v0.38 x rust-v0.53 (tcp, noise, yamux) | go-v0.38 | rust-v0.53 | tcp | noise | yamux | ✅ | 5s | 144.342 | 47.755 |
| go-v0.38 x rust-v0.53 (ws, noise, yamux) | go-v0.38 | rust-v0.53 | ws | noise | yamux | ✅ | 4s | 188.428 | 43.868 |
| go-v0.38 x rust-v0.53 (quic-v1) | go-v0.38 | rust-v0.53 | quic-v1 | - | - | ✅ | 4s | 8.283 | 0.484 |
| go-v0.38 x rust-v0.54 (tcp, tls, yamux) | go-v0.38 | rust-v0.54 | tcp | tls | yamux | ✅ | 4s | 92.622 | 43.299 |
| go-v0.38 x rust-v0.53 (webrtc-direct) | go-v0.38 | rust-v0.53 | webrtc-direct | - | - | ✅ | 5s | 409.375 | 0.39 |
| go-v0.38 x rust-v0.54 (tcp, noise, yamux) | go-v0.38 | rust-v0.54 | tcp | noise | yamux | ✅ | 5s | 96.557 | 43.483 |
| go-v0.38 x rust-v0.54 (ws, tls, yamux) | go-v0.38 | rust-v0.54 | ws | tls | yamux | ✅ | 4s | 180.682 | 42.937 |
| go-v0.38 x rust-v0.54 (ws, noise, yamux) | go-v0.38 | rust-v0.54 | ws | noise | yamux | ✅ | 4s | 222.744 | 47.983 |
| go-v0.38 x rust-v0.54 (quic-v1) | go-v0.38 | rust-v0.54 | quic-v1 | - | - | ✅ | 4s | 7.867 | 0.472 |
| go-v0.38 x rust-v0.55 (tcp, tls, yamux) | go-v0.38 | rust-v0.55 | tcp | tls | yamux | ✅ | 4s | 8.442 | 0.404 |
| go-v0.38 x rust-v0.54 (webrtc-direct) | go-v0.38 | rust-v0.54 | webrtc-direct | - | - | ✅ | 5s | 416.369 | 1.298 |
| go-v0.38 x rust-v0.55 (tcp, noise, yamux) | go-v0.38 | rust-v0.55 | tcp | noise | yamux | ✅ | 4s | 5.142 | 0.7 |
| go-v0.38 x rust-v0.55 (ws, tls, yamux) | go-v0.38 | rust-v0.55 | ws | tls | yamux | ✅ | 4s | 5.141 | 0.531 |
| go-v0.38 x rust-v0.55 (ws, noise, yamux) | go-v0.38 | rust-v0.55 | ws | noise | yamux | ✅ | 4s | 5.883 | 0.259 |
| go-v0.38 x rust-v0.55 (quic-v1) | go-v0.38 | rust-v0.55 | quic-v1 | - | - | ✅ | 4s | 5.413 | 0.227 |
| go-v0.38 x rust-v0.56 (tcp, tls, yamux) | go-v0.38 | rust-v0.56 | tcp | tls | yamux | ✅ | 4s | 8.989 | 0.756 |
| go-v0.38 x rust-v0.55 (webrtc-direct) | go-v0.38 | rust-v0.55 | webrtc-direct | - | - | ✅ | 6s | 416.205 | 1.818 |
| go-v0.38 x rust-v0.56 (tcp, noise, yamux) | go-v0.38 | rust-v0.56 | tcp | noise | yamux | ✅ | 5s | 4.814 | 0.595 |
| go-v0.38 x rust-v0.56 (ws, tls, yamux) | go-v0.38 | rust-v0.56 | ws | tls | yamux | ✅ | 4s | 6.823 | 1.036 |
| go-v0.38 x rust-v0.56 (ws, noise, yamux) | go-v0.38 | rust-v0.56 | ws | noise | yamux | ✅ | 5s | 5.2 | 0.174 |
| go-v0.38 x rust-v0.56 (quic-v1) | go-v0.38 | rust-v0.56 | quic-v1 | - | - | ✅ | 5s | 7.729 | 1.066 |
| go-v0.38 x go-v0.38 (tcp, tls, yamux) | go-v0.38 | go-v0.38 | tcp | tls | yamux | ✅ | 4s | 5.85 | 0.628 |
| go-v0.38 x go-v0.38 (tcp, noise, yamux) | go-v0.38 | go-v0.38 | tcp | noise | yamux | ✅ | 3s | 6.634 | 0.228 |
| go-v0.38 x go-v0.38 (ws, tls, yamux) | go-v0.38 | go-v0.38 | ws | tls | yamux | ✅ | 4s | 7.54 | 0.246 |
| go-v0.38 x go-v0.38 (ws, noise, yamux) | go-v0.38 | go-v0.38 | ws | noise | yamux | ✅ | 4s | 9.706 | 0.198 |
| go-v0.38 x go-v0.38 (wss, tls, yamux) | go-v0.38 | go-v0.38 | wss | tls | yamux | ✅ | 4s | 22.417 | 1.005 |
| go-v0.38 x go-v0.38 (wss, noise, yamux) | go-v0.38 | go-v0.38 | wss | noise | yamux | ✅ | 5s | 13.55 | 0.497 |
| go-v0.38 x rust-v0.56 (webrtc-direct) | go-v0.38 | rust-v0.56 | webrtc-direct | - | - | ❌ | 9s | - | - |
| go-v0.38 x go-v0.38 (webtransport) | go-v0.38 | go-v0.38 | webtransport | - | - | ✅ | 4s | 16.414 | 4.587 |
| go-v0.38 x go-v0.38 (quic-v1) | go-v0.38 | go-v0.38 | quic-v1 | - | - | ✅ | 5s | 10.821 | 0.577 |
| go-v0.38 x go-v0.38 (webrtc-direct) | go-v0.38 | go-v0.38 | webrtc-direct | - | - | ✅ | 5s | 213.721 | 0.338 |
| go-v0.38 x go-v0.39 (tcp, tls, yamux) | go-v0.38 | go-v0.39 | tcp | tls | yamux | ✅ | 4s | 13.309 | 0.468 |
| go-v0.38 x go-v0.39 (tcp, noise, yamux) | go-v0.38 | go-v0.39 | tcp | noise | yamux | ✅ | 4s | 6.408 | 0.927 |
| go-v0.38 x go-v0.39 (ws, tls, yamux) | go-v0.38 | go-v0.39 | ws | tls | yamux | ✅ | 4s | 8.457 | 0.515 |
| go-v0.38 x go-v0.39 (ws, noise, yamux) | go-v0.38 | go-v0.39 | ws | noise | yamux | ✅ | 4s | 13.4 | 1.051 |
| go-v0.38 x go-v0.39 (wss, tls, yamux) | go-v0.38 | go-v0.39 | wss | tls | yamux | ✅ | 4s | 11.979 | 0.891 |
| go-v0.38 x go-v0.39 (wss, noise, yamux) | go-v0.38 | go-v0.39 | wss | noise | yamux | ✅ | 5s | 10.047 | 1.09 |
| go-v0.38 x go-v0.39 (quic-v1) | go-v0.38 | go-v0.39 | quic-v1 | - | - | ✅ | 4s | 6.202 | 0.328 |
| go-v0.38 x go-v0.39 (webtransport) | go-v0.38 | go-v0.39 | webtransport | - | - | ✅ | 4s | 7.512 | 0.309 |
| go-v0.38 x go-v0.39 (webrtc-direct) | go-v0.38 | go-v0.39 | webrtc-direct | - | - | ✅ | 4s | 219.062 | 1.203 |
| go-v0.38 x go-v0.40 (tcp, tls, yamux) | go-v0.38 | go-v0.40 | tcp | tls | yamux | ✅ | 4s | 11.369 | 2.152 |
| go-v0.38 x go-v0.40 (tcp, noise, yamux) | go-v0.38 | go-v0.40 | tcp | noise | yamux | ✅ | 4s | 5.713 | 0.332 |
| go-v0.38 x go-v0.40 (ws, tls, yamux) | go-v0.38 | go-v0.40 | ws | tls | yamux | ✅ | 4s | 5.934 | 1.426 |
| go-v0.38 x go-v0.40 (ws, noise, yamux) | go-v0.38 | go-v0.40 | ws | noise | yamux | ✅ | 5s | 13.175 | 0.876 |
| go-v0.38 x go-v0.40 (wss, tls, yamux) | go-v0.38 | go-v0.40 | wss | tls | yamux | ✅ | 5s | 14.097 | 0.519 |
| go-v0.38 x go-v0.40 (wss, noise, yamux) | go-v0.38 | go-v0.40 | wss | noise | yamux | ✅ | 4s | 12.29 | 0.402 |
| go-v0.38 x go-v0.40 (quic-v1) | go-v0.38 | go-v0.40 | quic-v1 | - | - | ✅ | 5s | 7.952 | 0.702 |
| go-v0.38 x go-v0.40 (webtransport) | go-v0.38 | go-v0.40 | webtransport | - | - | ✅ | 4s | 14.13 | 0.471 |
| go-v0.38 x go-v0.40 (webrtc-direct) | go-v0.38 | go-v0.40 | webrtc-direct | - | - | ✅ | 4s | 213.039 | 0.885 |
| go-v0.38 x go-v0.41 (tcp, tls, yamux) | go-v0.38 | go-v0.41 | tcp | tls | yamux | ✅ | 4s | 9.351 | 0.419 |
| go-v0.38 x go-v0.41 (tcp, noise, yamux) | go-v0.38 | go-v0.41 | tcp | noise | yamux | ✅ | 4s | 6.302 | 1.288 |
| go-v0.38 x go-v0.41 (ws, tls, yamux) | go-v0.38 | go-v0.41 | ws | tls | yamux | ✅ | 4s | 11.069 | 1.995 |
| go-v0.38 x go-v0.41 (ws, noise, yamux) | go-v0.38 | go-v0.41 | ws | noise | yamux | ✅ | 3s | 11.475 | 0.541 |
| go-v0.38 x go-v0.41 (wss, tls, yamux) | go-v0.38 | go-v0.41 | wss | tls | yamux | ✅ | 4s | 56.254 | 1.582 |
| go-v0.38 x go-v0.41 (wss, noise, yamux) | go-v0.38 | go-v0.41 | wss | noise | yamux | ✅ | 4s | 11.731 | 1.343 |
| go-v0.38 x go-v0.41 (quic-v1) | go-v0.38 | go-v0.41 | quic-v1 | - | - | ✅ | 4s | 6.479 | 0.385 |
| go-v0.38 x go-v0.41 (webtransport) | go-v0.38 | go-v0.41 | webtransport | - | - | ✅ | 4s | 13.691 | 0.785 |
| go-v0.38 x go-v0.41 (webrtc-direct) | go-v0.38 | go-v0.41 | webrtc-direct | - | - | ✅ | 5s | 240.683 | 0.983 |
| go-v0.38 x go-v0.42 (tcp, tls, yamux) | go-v0.38 | go-v0.42 | tcp | tls | yamux | ✅ | 4s | 15.887 | 1.849 |
| go-v0.38 x go-v0.42 (tcp, noise, yamux) | go-v0.38 | go-v0.42 | tcp | noise | yamux | ✅ | 4s | 10.438 | 0.837 |
| go-v0.38 x go-v0.42 (ws, tls, yamux) | go-v0.38 | go-v0.42 | ws | tls | yamux | ✅ | 4s | 6.265 | 1.156 |
| go-v0.38 x go-v0.42 (ws, noise, yamux) | go-v0.38 | go-v0.42 | ws | noise | yamux | ✅ | 4s | 11.973 | 1.641 |
| go-v0.38 x go-v0.42 (wss, tls, yamux) | go-v0.38 | go-v0.42 | wss | tls | yamux | ✅ | 4s | 18.655 | 1.19 |
| go-v0.38 x go-v0.42 (wss, noise, yamux) | go-v0.38 | go-v0.42 | wss | noise | yamux | ✅ | 4s | 15.069 | 1.203 |
| go-v0.38 x go-v0.42 (quic-v1) | go-v0.38 | go-v0.42 | quic-v1 | - | - | ✅ | 5s | 12.13 | 2.661 |
| go-v0.38 x go-v0.42 (webtransport) | go-v0.38 | go-v0.42 | webtransport | - | - | ✅ | 4s | 9.798 | 0.757 |
| go-v0.38 x go-v0.42 (webrtc-direct) | go-v0.38 | go-v0.42 | webrtc-direct | - | - | ✅ | 5s | 212.197 | 0.455 |
| go-v0.38 x go-v0.43 (tcp, tls, yamux) | go-v0.38 | go-v0.43 | tcp | tls | yamux | ✅ | 5s | 8.082 | 0.643 |
| go-v0.38 x go-v0.43 (tcp, noise, yamux) | go-v0.38 | go-v0.43 | tcp | noise | yamux | ✅ | 4s | 7.19 | 0.424 |
| go-v0.38 x go-v0.43 (ws, tls, yamux) | go-v0.38 | go-v0.43 | ws | tls | yamux | ✅ | 5s | 18.669 | 3.64 |
| go-v0.38 x go-v0.43 (ws, noise, yamux) | go-v0.38 | go-v0.43 | ws | noise | yamux | ✅ | 4s | 12.876 | 0.543 |
| go-v0.38 x go-v0.43 (wss, tls, yamux) | go-v0.38 | go-v0.43 | wss | tls | yamux | ✅ | 5s | 11.876 | 0.657 |
| go-v0.38 x go-v0.43 (wss, noise, yamux) | go-v0.38 | go-v0.43 | wss | noise | yamux | ✅ | 4s | 7.617 | 0.276 |
| go-v0.38 x go-v0.43 (quic-v1) | go-v0.38 | go-v0.43 | quic-v1 | - | - | ✅ | 4s | 5.952 | 0.354 |
| go-v0.38 x go-v0.43 (webtransport) | go-v0.38 | go-v0.43 | webtransport | - | - | ✅ | 4s | 19.916 | 0.448 |
| go-v0.38 x go-v0.43 (webrtc-direct) | go-v0.38 | go-v0.43 | webrtc-direct | - | - | ✅ | 4s | 221.941 | 0.759 |
| go-v0.38 x go-v0.44 (tcp, tls, yamux) | go-v0.38 | go-v0.44 | tcp | tls | yamux | ✅ | 5s | 19.723 | 6.706 |
| go-v0.38 x go-v0.44 (ws, tls, yamux) | go-v0.38 | go-v0.44 | ws | tls | yamux | ✅ | 4s | 20.073 | 2.233 |
| go-v0.38 x go-v0.44 (tcp, noise, yamux) | go-v0.38 | go-v0.44 | tcp | noise | yamux | ✅ | 5s | 8.729 | 1.542 |
| go-v0.38 x go-v0.44 (ws, noise, yamux) | go-v0.38 | go-v0.44 | ws | noise | yamux | ✅ | 4s | 4.572 | 0.315 |
| go-v0.38 x go-v0.44 (quic-v1) | go-v0.38 | go-v0.44 | quic-v1 | - | - | ✅ | 4s | 17.214 | 0.845 |
| go-v0.38 x go-v0.44 (wss, tls, yamux) | go-v0.38 | go-v0.44 | wss | tls | yamux | ✅ | 5s | 19.453 | 4.387 |
| go-v0.38 x go-v0.44 (wss, noise, yamux) | go-v0.38 | go-v0.44 | wss | noise | yamux | ✅ | 5s | 17.976 | 0.566 |
| go-v0.38 x go-v0.44 (webtransport) | go-v0.38 | go-v0.44 | webtransport | - | - | ✅ | 5s | 12.402 | 2.945 |
| go-v0.38 x go-v0.44 (webrtc-direct) | go-v0.38 | go-v0.44 | webrtc-direct | - | - | ✅ | 5s | 218.585 | 0.351 |
| go-v0.38 x go-v0.45 (tcp, tls, yamux) | go-v0.38 | go-v0.45 | tcp | tls | yamux | ✅ | 5s | 10.36 | 1.652 |
| go-v0.38 x go-v0.45 (tcp, noise, yamux) | go-v0.38 | go-v0.45 | tcp | noise | yamux | ✅ | 4s | 8.569 | 0.629 |
| go-v0.38 x go-v0.45 (ws, tls, yamux) | go-v0.38 | go-v0.45 | ws | tls | yamux | ✅ | 4s | 5.548 | 0.842 |
| go-v0.38 x go-v0.45 (ws, noise, yamux) | go-v0.38 | go-v0.45 | ws | noise | yamux | ✅ | 4s | 10.117 | 1.036 |
| go-v0.38 x go-v0.45 (wss, tls, yamux) | go-v0.38 | go-v0.45 | wss | tls | yamux | ✅ | 5s | 13.684 | 0.487 |
| go-v0.38 x go-v0.45 (quic-v1) | go-v0.38 | go-v0.45 | quic-v1 | - | - | ✅ | 4s | 17.113 | 0.403 |
| go-v0.38 x go-v0.45 (wss, noise, yamux) | go-v0.38 | go-v0.45 | wss | noise | yamux | ✅ | 5s | 12.316 | 0.339 |
| go-v0.38 x go-v0.45 (webtransport) | go-v0.38 | go-v0.45 | webtransport | - | - | ✅ | 5s | 10.894 | 0.371 |
| go-v0.38 x go-v0.45 (webrtc-direct) | go-v0.38 | go-v0.45 | webrtc-direct | - | - | ✅ | 4s | 210.444 | 0.37 |
| go-v0.38 x python-v0.4 (tcp, noise, yamux) | go-v0.38 | python-v0.4 | tcp | noise | yamux | ✅ | 4s | 18.15 | 2.792 |
| go-v0.38 x python-v0.4 (ws, noise, yamux) | go-v0.38 | python-v0.4 | ws | noise | yamux | ✅ | 5s | 23.371 | 3.313 |
| go-v0.38 x python-v0.4 (wss, noise, yamux) | go-v0.38 | python-v0.4 | wss | noise | yamux | ✅ | 5s | 36.172 | 5.431 |
| go-v0.38 x python-v0.4 (quic-v1) | go-v0.38 | python-v0.4 | quic-v1 | - | - | ✅ | 5s | 55.253 | 15.048 |
| go-v0.38 x nim-v1.14 (tcp, noise, yamux) | go-v0.38 | nim-v1.14 | tcp | noise | yamux | ✅ | 4s | 205.05 | 43.633 |
| go-v0.38 x nim-v1.14 (ws, noise, yamux) | go-v0.38 | nim-v1.14 | ws | noise | yamux | ✅ | 4s | 250.385 | 43.867 |
| go-v0.38 x js-v1.x (tcp, noise, yamux) | go-v0.38 | js-v1.x | tcp | noise | yamux | ✅ | 16s | 136.432 | 16.219 |
| go-v0.38 x js-v1.x (ws, noise, yamux) | go-v0.38 | js-v1.x | ws | noise | yamux | ✅ | 17s | 138.843 | 19.168 |
| go-v0.38 x js-v2.x (tcp, noise, yamux) | go-v0.38 | js-v2.x | tcp | noise | yamux | ✅ | 18s | 113.557 | 13.361 |
| go-v0.38 x js-v2.x (ws, noise, yamux) | go-v0.38 | js-v2.x | ws | noise | yamux | ✅ | 17s | 127.256 | 23.875 |
| go-v0.38 x js-v3.x (tcp, noise, yamux) | go-v0.38 | js-v3.x | tcp | noise | yamux | ✅ | 17s | 88.438 | 19.564 |
| go-v0.38 x js-v3.x (ws, noise, yamux) | go-v0.38 | js-v3.x | ws | noise | yamux | ✅ | 17s | 137.46 | 13.494 |
| go-v0.38 x jvm-v1.2 (tcp, noise, yamux) | go-v0.38 | jvm-v1.2 | tcp | noise | yamux | ✅ | 9s | 870.836 | 37.294 |
| go-v0.38 x jvm-v1.2 (tcp, tls, yamux) | go-v0.38 | jvm-v1.2 | tcp | tls | yamux | ✅ | 10s | 3088.839 | 20.52 |
| go-v0.38 x c-v0.0.1 (tcp, noise, yamux) | go-v0.38 | c-v0.0.1 | tcp | noise | yamux | ✅ | 6s | 143.881 | 59.914 |
| go-v0.38 x c-v0.0.1 (quic-v1) | go-v0.38 | c-v0.0.1 | quic-v1 | - | - | ✅ | 5s | 45.95 | 1.85 |
| go-v0.38 x jvm-v1.2 (ws, tls, yamux) | go-v0.38 | jvm-v1.2 | ws | tls | yamux | ✅ | 11s | 3290.803 | 39.779 |
| go-v0.38 x jvm-v1.2 (ws, noise, yamux) | go-v0.38 | jvm-v1.2 | ws | noise | yamux | ✅ | 9s | 1181.68 | 27.51 |
| go-v0.38 x jvm-v1.2 (quic-v1) | go-v0.38 | jvm-v1.2 | quic-v1 | - | - | ✅ | 9s | 517.307 | 13.903 |
| go-v0.38 x zig-v0.0.1 (quic-v1) | go-v0.38 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 4s | - | - |
| go-v0.38 x dotnet-v1.0 (tcp, noise, yamux) | go-v0.38 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 4s | 295.467 | 42.127 |
| go-v0.38 x eth-p2p-z-v0.0.1 (quic-v1) | go-v0.38 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 4s | 7.72 | 0.919 |
| go-v0.39 x rust-v0.53 (tcp, tls, yamux) | go-v0.39 | rust-v0.53 | tcp | tls | yamux | ✅ | 4s | 137.959 | 43.739 |
| go-v0.39 x rust-v0.53 (tcp, noise, yamux) | go-v0.39 | rust-v0.53 | tcp | noise | yamux | ✅ | 5s | 130.984 | 43.045 |
| go-v0.39 x rust-v0.53 (ws, tls, yamux) | go-v0.39 | rust-v0.53 | ws | tls | yamux | ✅ | 4s | 181.911 | 43.336 |
| go-v0.39 x rust-v0.53 (ws, noise, yamux) | go-v0.39 | rust-v0.53 | ws | noise | yamux | ✅ | 4s | 183.048 | 42.628 |
| go-v0.39 x rust-v0.53 (quic-v1) | go-v0.39 | rust-v0.53 | quic-v1 | - | - | ✅ | 4s | 7.136 | 0.322 |
| go-v0.39 x rust-v0.53 (webrtc-direct) | go-v0.39 | rust-v0.53 | webrtc-direct | - | - | ✅ | 6s | 419.239 | 0.82 |
| go-v0.39 x rust-v0.54 (tcp, tls, yamux) | go-v0.39 | rust-v0.54 | tcp | tls | yamux | ✅ | 5s | 96.18 | 46.308 |
| go-v0.39 x rust-v0.54 (tcp, noise, yamux) | go-v0.39 | rust-v0.54 | tcp | noise | yamux | ✅ | 4s | 89.839 | 42.358 |
| go-v0.39 x rust-v0.54 (ws, noise, yamux) | go-v0.39 | rust-v0.54 | ws | noise | yamux | ✅ | 4s | 175.014 | 44.125 |
| go-v0.39 x rust-v0.54 (ws, tls, yamux) | go-v0.39 | rust-v0.54 | ws | tls | yamux | ✅ | 5s | 179.439 | 42.582 |
| go-v0.39 x rust-v0.54 (quic-v1) | go-v0.39 | rust-v0.54 | quic-v1 | - | - | ✅ | 4s | 9.034 | 1.038 |
| go-v0.39 x rust-v0.54 (webrtc-direct) | go-v0.39 | rust-v0.54 | webrtc-direct | - | - | ✅ | 5s | 216.265 | 0.637 |
| go-v0.39 x rust-v0.55 (tcp, tls, yamux) | go-v0.39 | rust-v0.55 | tcp | tls | yamux | ✅ | 3s | 4.44 | 0.245 |
| go-v0.39 x rust-v0.55 (tcp, noise, yamux) | go-v0.39 | rust-v0.55 | tcp | noise | yamux | ✅ | 4s | 7.568 | 0.515 |
| go-v0.39 x rust-v0.55 (ws, tls, yamux) | go-v0.39 | rust-v0.55 | ws | tls | yamux | ✅ | 4s | 10.826 | 0.895 |
| go-v0.39 x rust-v0.55 (quic-v1) | go-v0.39 | rust-v0.55 | quic-v1 | - | - | ✅ | 3s | 8.554 | 1.26 |
| go-v0.39 x rust-v0.55 (ws, noise, yamux) | go-v0.39 | rust-v0.55 | ws | noise | yamux | ✅ | 5s | 5.997 | 0.452 |
| go-v0.39 x rust-v0.55 (webrtc-direct) | go-v0.39 | rust-v0.55 | webrtc-direct | - | - | ✅ | 5s | 413.348 | 0.379 |
| go-v0.39 x rust-v0.56 (tcp, tls, yamux) | go-v0.39 | rust-v0.56 | tcp | tls | yamux | ✅ | 4s | 5.141 | 0.204 |
| go-v0.39 x rust-v0.56 (tcp, noise, yamux) | go-v0.39 | rust-v0.56 | tcp | noise | yamux | ✅ | 4s | 3.766 | 0.168 |
| go-v0.39 x rust-v0.56 (ws, tls, yamux) | go-v0.39 | rust-v0.56 | ws | tls | yamux | ✅ | 4s | 15.043 | 0.544 |
| go-v0.39 x rust-v0.56 (ws, noise, yamux) | go-v0.39 | rust-v0.56 | ws | noise | yamux | ✅ | 5s | 6.158 | 0.8 |
| go-v0.39 x rust-v0.56 (quic-v1) | go-v0.39 | rust-v0.56 | quic-v1 | - | - | ✅ | 4s | 4.969 | 0.193 |
| go-v0.39 x go-v0.38 (tcp, tls, yamux) | go-v0.39 | go-v0.38 | tcp | tls | yamux | ✅ | 4s | 8.297 | 0.199 |
| go-v0.39 x go-v0.38 (ws, tls, yamux) | go-v0.39 | go-v0.38 | ws | tls | yamux | ✅ | 4s | 8.901 | 1.16 |
| go-v0.39 x go-v0.38 (tcp, noise, yamux) | go-v0.39 | go-v0.38 | tcp | noise | yamux | ✅ | 4s | 13.218 | 0.891 |
| go-v0.39 x go-v0.38 (ws, noise, yamux) | go-v0.39 | go-v0.38 | ws | noise | yamux | ✅ | 4s | 15.251 | 2.397 |
| go-v0.39 x go-v0.38 (wss, noise, yamux) | go-v0.39 | go-v0.38 | wss | noise | yamux | ✅ | 4s | 12.614 | 0.304 |
| go-v0.39 x go-v0.38 (wss, tls, yamux) | go-v0.39 | go-v0.38 | wss | tls | yamux | ✅ | 5s | 9.558 | 0.807 |
| go-v0.39 x rust-v0.56 (webrtc-direct) | go-v0.39 | rust-v0.56 | webrtc-direct | - | - | ❌ | 10s | - | - |
| go-v0.39 x go-v0.38 (quic-v1) | go-v0.39 | go-v0.38 | quic-v1 | - | - | ✅ | 4s | 5.984 | 0.244 |
| go-v0.39 x go-v0.38 (webtransport) | go-v0.39 | go-v0.38 | webtransport | - | - | ✅ | 4s | 12.929 | 0.389 |
| go-v0.39 x go-v0.38 (webrtc-direct) | go-v0.39 | go-v0.38 | webrtc-direct | - | - | ✅ | 5s | 210.918 | 0.343 |
| go-v0.39 x go-v0.39 (tcp, tls, yamux) | go-v0.39 | go-v0.39 | tcp | tls | yamux | ✅ | 4s | 5.752 | 0.278 |
| rust-v0.56 x go-v0.42 (webrtc-direct) | rust-v0.56 | go-v0.42 | webrtc-direct | - | - | ❌ | 194s | - | - |
| go-v0.39 x go-v0.39 (tcp, noise, yamux) | go-v0.39 | go-v0.39 | tcp | noise | yamux | ✅ | 5s | 9.347 | 0.426 |
| go-v0.39 x go-v0.39 (ws, tls, yamux) | go-v0.39 | go-v0.39 | ws | tls | yamux | ✅ | 4s | 13.57 | 0.424 |
| go-v0.39 x go-v0.39 (ws, noise, yamux) | go-v0.39 | go-v0.39 | ws | noise | yamux | ✅ | 5s | 9.598 | 0.584 |
| go-v0.39 x go-v0.39 (wss, tls, yamux) | go-v0.39 | go-v0.39 | wss | tls | yamux | ✅ | 4s | 6.522 | 0.186 |
| go-v0.39 x go-v0.39 (wss, noise, yamux) | go-v0.39 | go-v0.39 | wss | noise | yamux | ✅ | 5s | 9.209 | 0.465 |
| go-v0.39 x go-v0.39 (quic-v1) | go-v0.39 | go-v0.39 | quic-v1 | - | - | ✅ | 5s | 11.711 | 1.09 |
| go-v0.39 x go-v0.39 (webtransport) | go-v0.39 | go-v0.39 | webtransport | - | - | ✅ | 4s | 9.584 | 0.406 |
| go-v0.39 x go-v0.39 (webrtc-direct) | go-v0.39 | go-v0.39 | webrtc-direct | - | - | ✅ | 4s | 211.39 | 0.25 |
| go-v0.39 x go-v0.40 (tcp, tls, yamux) | go-v0.39 | go-v0.40 | tcp | tls | yamux | ✅ | 5s | 12.26 | 1.438 |
| go-v0.39 x go-v0.40 (tcp, noise, yamux) | go-v0.39 | go-v0.40 | tcp | noise | yamux | ✅ | 5s | 12.883 | 1.948 |
| go-v0.39 x go-v0.40 (ws, tls, yamux) | go-v0.39 | go-v0.40 | ws | tls | yamux | ✅ | 5s | 12.141 | 0.432 |
| go-v0.39 x go-v0.40 (ws, noise, yamux) | go-v0.39 | go-v0.40 | ws | noise | yamux | ✅ | 5s | 9.325 | 0.418 |
| go-v0.39 x go-v0.40 (wss, tls, yamux) | go-v0.39 | go-v0.40 | wss | tls | yamux | ✅ | 5s | 15.023 | 0.675 |
| go-v0.39 x go-v0.40 (wss, noise, yamux) | go-v0.39 | go-v0.40 | wss | noise | yamux | ✅ | 5s | 17.922 | 0.692 |
| go-v0.39 x go-v0.40 (quic-v1) | go-v0.39 | go-v0.40 | quic-v1 | - | - | ✅ | 5s | 19.742 | 0.561 |
| go-v0.39 x go-v0.40 (webtransport) | go-v0.39 | go-v0.40 | webtransport | - | - | ✅ | 5s | 7.806 | 0.274 |
| go-v0.39 x go-v0.41 (tcp, tls, yamux) | go-v0.39 | go-v0.41 | tcp | tls | yamux | ✅ | 5s | 11.52 | 0.576 |
| go-v0.39 x go-v0.40 (webrtc-direct) | go-v0.39 | go-v0.40 | webrtc-direct | - | - | ✅ | 5s | 221.29 | 0.362 |
| go-v0.39 x go-v0.41 (tcp, noise, yamux) | go-v0.39 | go-v0.41 | tcp | noise | yamux | ✅ | 5s | 9.133 | 0.618 |
| go-v0.39 x go-v0.41 (ws, tls, yamux) | go-v0.39 | go-v0.41 | ws | tls | yamux | ✅ | 5s | 8.521 | 0.673 |
| go-v0.39 x go-v0.41 (ws, noise, yamux) | go-v0.39 | go-v0.41 | ws | noise | yamux | ✅ | 5s | 14.978 | 0.352 |
| go-v0.39 x go-v0.41 (wss, tls, yamux) | go-v0.39 | go-v0.41 | wss | tls | yamux | ✅ | 5s | 29.788 | 0.719 |
| go-v0.39 x go-v0.41 (quic-v1) | go-v0.39 | go-v0.41 | quic-v1 | - | - | ✅ | 4s | 8.138 | 0.538 |
| go-v0.39 x go-v0.41 (wss, noise, yamux) | go-v0.39 | go-v0.41 | wss | noise | yamux | ✅ | 6s | 11.357 | 0.761 |
| go-v0.39 x go-v0.41 (webtransport) | go-v0.39 | go-v0.41 | webtransport | - | - | ✅ | 5s | 20.583 | 0.487 |
| go-v0.39 x go-v0.41 (webrtc-direct) | go-v0.39 | go-v0.41 | webrtc-direct | - | - | ✅ | 5s | 212.198 | 0.72 |
| go-v0.39 x go-v0.42 (tcp, tls, yamux) | go-v0.39 | go-v0.42 | tcp | tls | yamux | ✅ | 5s | 8.007 | 1.338 |
| go-v0.39 x go-v0.42 (tcp, noise, yamux) | go-v0.39 | go-v0.42 | tcp | noise | yamux | ✅ | 5s | 4.738 | 0.158 |
| go-v0.39 x go-v0.42 (ws, noise, yamux) | go-v0.39 | go-v0.42 | ws | noise | yamux | ✅ | 5s | 9.906 | 1.204 |
| go-v0.39 x go-v0.42 (ws, tls, yamux) | go-v0.39 | go-v0.42 | ws | tls | yamux | ✅ | 6s | 20.076 | 5.266 |
| go-v0.39 x go-v0.42 (wss, tls, yamux) | go-v0.39 | go-v0.42 | wss | tls | yamux | ✅ | 5s | 14.104 | 0.896 |
| go-v0.39 x go-v0.42 (wss, noise, yamux) | go-v0.39 | go-v0.42 | wss | noise | yamux | ✅ | 6s | 7.528 | 0.474 |
| go-v0.39 x go-v0.42 (quic-v1) | go-v0.39 | go-v0.42 | quic-v1 | - | - | ✅ | 6s | 11.359 | 1.298 |
| go-v0.39 x go-v0.42 (webtransport) | go-v0.39 | go-v0.42 | webtransport | - | - | ✅ | 6s | 12.121 | 0.271 |
| go-v0.39 x go-v0.42 (webrtc-direct) | go-v0.39 | go-v0.42 | webrtc-direct | - | - | ✅ | 5s | 211.556 | 0.313 |
| go-v0.39 x go-v0.43 (tcp, tls, yamux) | go-v0.39 | go-v0.43 | tcp | tls | yamux | ✅ | 5s | 13.275 | 1.219 |
| go-v0.39 x go-v0.43 (tcp, noise, yamux) | go-v0.39 | go-v0.43 | tcp | noise | yamux | ✅ | 4s | 6.966 | 0.602 |
| go-v0.39 x go-v0.43 (ws, tls, yamux) | go-v0.39 | go-v0.43 | ws | tls | yamux | ✅ | 5s | 9.465 | 0.557 |
| go-v0.39 x go-v0.43 (ws, noise, yamux) | go-v0.39 | go-v0.43 | ws | noise | yamux | ✅ | 5s | 12.259 | 0.78 |
| go-v0.39 x go-v0.43 (wss, tls, yamux) | go-v0.39 | go-v0.43 | wss | tls | yamux | ✅ | 5s | 11.309 | 0.42 |
| go-v0.39 x go-v0.43 (wss, noise, yamux) | go-v0.39 | go-v0.43 | wss | noise | yamux | ✅ | 5s | 11.786 | 0.605 |
| go-v0.39 x go-v0.43 (quic-v1) | go-v0.39 | go-v0.43 | quic-v1 | - | - | ✅ | 4s | 9.502 | 0.546 |
| go-v0.39 x go-v0.43 (webtransport) | go-v0.39 | go-v0.43 | webtransport | - | - | ✅ | 4s | 15.508 | 0.576 |
| go-v0.39 x go-v0.43 (webrtc-direct) | go-v0.39 | go-v0.43 | webrtc-direct | - | - | ✅ | 5s | 210.701 | 0.398 |
| go-v0.39 x go-v0.44 (tcp, tls, yamux) | go-v0.39 | go-v0.44 | tcp | tls | yamux | ✅ | 5s | 14.083 | 1.042 |
| go-v0.39 x go-v0.44 (tcp, noise, yamux) | go-v0.39 | go-v0.44 | tcp | noise | yamux | ✅ | 5s | 9.296 | 1.146 |
| go-v0.39 x go-v0.44 (ws, tls, yamux) | go-v0.39 | go-v0.44 | ws | tls | yamux | ✅ | 5s | 8.07 | 0.476 |
| go-v0.39 x go-v0.44 (ws, noise, yamux) | go-v0.39 | go-v0.44 | ws | noise | yamux | ✅ | 4s | 18.671 | 3.418 |
| go-v0.39 x go-v0.44 (wss, tls, yamux) | go-v0.39 | go-v0.44 | wss | tls | yamux | ✅ | 5s | 16.333 | 0.81 |
| go-v0.39 x go-v0.44 (wss, noise, yamux) | go-v0.39 | go-v0.44 | wss | noise | yamux | ✅ | 5s | 19.872 | 0.292 |
| go-v0.39 x go-v0.44 (quic-v1) | go-v0.39 | go-v0.44 | quic-v1 | - | - | ✅ | 4s | 11.125 | 1.292 |
| go-v0.39 x go-v0.44 (webtransport) | go-v0.39 | go-v0.44 | webtransport | - | - | ✅ | 5s | 22.436 | 0.425 |
| go-v0.39 x go-v0.44 (webrtc-direct) | go-v0.39 | go-v0.44 | webrtc-direct | - | - | ✅ | 4s | 334.034 | 0.268 |
| go-v0.39 x go-v0.45 (tcp, tls, yamux) | go-v0.39 | go-v0.45 | tcp | tls | yamux | ✅ | 4s | 13.419 | 2.314 |
| go-v0.39 x go-v0.45 (tcp, noise, yamux) | go-v0.39 | go-v0.45 | tcp | noise | yamux | ✅ | 5s | 6.721 | 0.326 |
| go-v0.39 x go-v0.45 (ws, tls, yamux) | go-v0.39 | go-v0.45 | ws | tls | yamux | ✅ | 5s | 6.558 | 0.302 |
| go-v0.39 x go-v0.45 (ws, noise, yamux) | go-v0.39 | go-v0.45 | ws | noise | yamux | ✅ | 5s | 12.386 | 2.155 |
| go-v0.39 x go-v0.45 (wss, tls, yamux) | go-v0.39 | go-v0.45 | wss | tls | yamux | ✅ | 6s | 15.063 | 0.546 |
| go-v0.39 x go-v0.45 (quic-v1) | go-v0.39 | go-v0.45 | quic-v1 | - | - | ✅ | 5s | 11.082 | 0.613 |
| go-v0.39 x go-v0.45 (wss, noise, yamux) | go-v0.39 | go-v0.45 | wss | noise | yamux | ✅ | 5s | 20.919 | 0.871 |
| go-v0.39 x go-v0.45 (webtransport) | go-v0.39 | go-v0.45 | webtransport | - | - | ✅ | 5s | 6.655 | 0.244 |
| go-v0.39 x go-v0.45 (webrtc-direct) | go-v0.39 | go-v0.45 | webrtc-direct | - | - | ✅ | 5s | 225.684 | 0.686 |
| go-v0.39 x python-v0.4 (tcp, noise, yamux) | go-v0.39 | python-v0.4 | tcp | noise | yamux | ✅ | 5s | 22.782 | 2.584 |
| go-v0.39 x python-v0.4 (ws, noise, yamux) | go-v0.39 | python-v0.4 | ws | noise | yamux | ✅ | 5s | 22.907 | 3.899 |
| go-v0.39 x python-v0.4 (wss, noise, yamux) | go-v0.39 | python-v0.4 | wss | noise | yamux | ✅ | 5s | 35.365 | 6.696 |
| go-v0.39 x python-v0.4 (quic-v1) | go-v0.39 | python-v0.4 | quic-v1 | - | - | ✅ | 5s | 59.807 | 6.891 |
| go-v0.39 x nim-v1.14 (tcp, noise, yamux) | go-v0.39 | nim-v1.14 | tcp | noise | yamux | ✅ | 4s | 215.828 | 42.977 |
| go-v0.39 x nim-v1.14 (ws, noise, yamux) | go-v0.39 | nim-v1.14 | ws | noise | yamux | ✅ | 5s | 252.163 | 43.565 |
| go-v0.39 x js-v1.x (tcp, noise, yamux) | go-v0.39 | js-v1.x | tcp | noise | yamux | ✅ | 18s | 219.289 | 19.005 |
| go-v0.39 x js-v1.x (ws, noise, yamux) | go-v0.39 | js-v1.x | ws | noise | yamux | ✅ | 19s | 184.233 | 22.346 |
| go-v0.39 x js-v2.x (tcp, noise, yamux) | go-v0.39 | js-v2.x | tcp | noise | yamux | ✅ | 21s | 193.877 | 25.881 |
| go-v0.39 x js-v3.x (tcp, noise, yamux) | go-v0.39 | js-v3.x | tcp | noise | yamux | ✅ | 20s | 165.342 | 22.774 |
| go-v0.39 x jvm-v1.2 (tcp, noise, yamux) | go-v0.39 | jvm-v1.2 | tcp | noise | yamux | ✅ | 11s | 1227.597 | 19.073 |
| go-v0.39 x js-v2.x (ws, noise, yamux) | go-v0.39 | js-v2.x | ws | noise | yamux | ✅ | 21s | 154.45 | 27.282 |
| go-v0.39 x jvm-v1.2 (tcp, tls, yamux) | go-v0.39 | jvm-v1.2 | tcp | tls | yamux | ✅ | 13s | 3348.408 | 9.256 |
| go-v0.39 x js-v3.x (ws, noise, yamux) | go-v0.39 | js-v3.x | ws | noise | yamux | ✅ | 21s | 142.48 | 12.513 |
| go-v0.39 x jvm-v1.2 (ws, tls, yamux) | go-v0.39 | jvm-v1.2 | ws | tls | yamux | ✅ | 10s | 3234.7 | 16.283 |
| go-v0.39 x c-v0.0.1 (quic-v1) | go-v0.39 | c-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 27.634 | 6.489 |
| go-v0.39 x c-v0.0.1 (tcp, noise, yamux) | go-v0.39 | c-v0.0.1 | tcp | noise | yamux | ✅ | 7s | 131.584 | 58.887 |
| go-v0.39 x jvm-v1.2 (ws, noise, yamux) | go-v0.39 | jvm-v1.2 | ws | noise | yamux | ✅ | 9s | 1340.925 | 19.858 |
| go-v0.39 x dotnet-v1.0 (tcp, noise, yamux) | go-v0.39 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 7s | 335.4 | 42.545 |
| go-v0.39 x zig-v0.0.1 (quic-v1) | go-v0.39 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 6s | - | - |
| go-v0.39 x jvm-v1.2 (quic-v1) | go-v0.39 | jvm-v1.2 | quic-v1 | - | - | ✅ | 10s | 432.188 | 6.49 |
| go-v0.39 x eth-p2p-z-v0.0.1 (quic-v1) | go-v0.39 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 7s | 4.344 | 0.162 |
| go-v0.40 x rust-v0.53 (tcp, tls, yamux) | go-v0.40 | rust-v0.53 | tcp | tls | yamux | ✅ | 4s | 93.071 | 45.205 |
| go-v0.40 x rust-v0.53 (tcp, noise, yamux) | go-v0.40 | rust-v0.53 | tcp | noise | yamux | ✅ | 4s | 91.47 | 41.545 |
| go-v0.40 x rust-v0.53 (ws, tls, yamux) | go-v0.40 | rust-v0.53 | ws | tls | yamux | ✅ | 4s | 192.733 | 45.801 |
| go-v0.40 x rust-v0.53 (ws, noise, yamux) | go-v0.40 | rust-v0.53 | ws | noise | yamux | ✅ | 5s | 175.746 | 42.447 |
| go-v0.40 x rust-v0.53 (quic-v1) | go-v0.40 | rust-v0.53 | quic-v1 | - | - | ✅ | 5s | 7.719 | 0.244 |
| go-v0.40 x rust-v0.53 (webrtc-direct) | go-v0.40 | rust-v0.53 | webrtc-direct | - | - | ✅ | 5s | 412.298 | 0.627 |
| go-v0.40 x rust-v0.54 (tcp, tls, yamux) | go-v0.40 | rust-v0.54 | tcp | tls | yamux | ✅ | 5s | 94.422 | 42.203 |
| go-v0.40 x rust-v0.54 (tcp, noise, yamux) | go-v0.40 | rust-v0.54 | tcp | noise | yamux | ✅ | 5s | 91.421 | 42.505 |
| go-v0.40 x rust-v0.54 (ws, tls, yamux) | go-v0.40 | rust-v0.54 | ws | tls | yamux | ✅ | 5s | 181.871 | 42.996 |
| go-v0.40 x rust-v0.54 (ws, noise, yamux) | go-v0.40 | rust-v0.54 | ws | noise | yamux | ✅ | 5s | 145.45 | 0.829 |
| go-v0.40 x rust-v0.54 (quic-v1) | go-v0.40 | rust-v0.54 | quic-v1 | - | - | ✅ | 5s | 8.641 | 0.28 |
| go-v0.40 x rust-v0.54 (webrtc-direct) | go-v0.40 | rust-v0.54 | webrtc-direct | - | - | ✅ | 5s | 414.413 | 0.693 |
| go-v0.40 x rust-v0.55 (tcp, tls, yamux) | go-v0.40 | rust-v0.55 | tcp | tls | yamux | ✅ | 5s | 12.578 | 0.427 |
| go-v0.40 x rust-v0.55 (tcp, noise, yamux) | go-v0.40 | rust-v0.55 | tcp | noise | yamux | ✅ | 5s | 5.589 | 0.602 |
| go-v0.40 x rust-v0.55 (ws, noise, yamux) | go-v0.40 | rust-v0.55 | ws | noise | yamux | ✅ | 4s | 6.22 | 0.666 |
| go-v0.40 x rust-v0.55 (ws, tls, yamux) | go-v0.40 | rust-v0.55 | ws | tls | yamux | ✅ | 6s | 10.295 | 0.713 |
| go-v0.40 x rust-v0.55 (quic-v1) | go-v0.40 | rust-v0.55 | quic-v1 | - | - | ✅ | 5s | 9.368 | 0.613 |
| go-v0.40 x rust-v0.56 (tcp, tls, yamux) | go-v0.40 | rust-v0.56 | tcp | tls | yamux | ✅ | 4s | 7.978 | 0.344 |
| go-v0.40 x rust-v0.56 (tcp, noise, yamux) | go-v0.40 | rust-v0.56 | tcp | noise | yamux | ✅ | 5s | 4.298 | 0.29 |
| go-v0.40 x rust-v0.55 (webrtc-direct) | go-v0.40 | rust-v0.55 | webrtc-direct | - | - | ✅ | 6s | 410.459 | 0.578 |
| go-v0.40 x rust-v0.56 (ws, tls, yamux) | go-v0.40 | rust-v0.56 | ws | tls | yamux | ✅ | 5s | 4.347 | 0.239 |
| go-v0.40 x rust-v0.56 (ws, noise, yamux) | go-v0.40 | rust-v0.56 | ws | noise | yamux | ✅ | 4s | 6.469 | 0.856 |
| go-v0.40 x rust-v0.56 (quic-v1) | go-v0.40 | rust-v0.56 | quic-v1 | - | - | ✅ | 4s | 9.569 | 0.37 |
| go-v0.40 x go-v0.38 (tcp, tls, yamux) | go-v0.40 | go-v0.38 | tcp | tls | yamux | ✅ | 4s | 8.649 | 1.553 |
| go-v0.40 x go-v0.38 (tcp, noise, yamux) | go-v0.40 | go-v0.38 | tcp | noise | yamux | ✅ | 4s | 9.189 | 1.087 |
| go-v0.40 x go-v0.38 (ws, tls, yamux) | go-v0.40 | go-v0.38 | ws | tls | yamux | ✅ | 4s | 7.495 | 0.346 |
| go-v0.40 x go-v0.38 (ws, noise, yamux) | go-v0.40 | go-v0.38 | ws | noise | yamux | ✅ | 4s | 10.886 | 1.161 |
| go-v0.40 x go-v0.38 (wss, tls, yamux) | go-v0.40 | go-v0.38 | wss | tls | yamux | ✅ | 5s | 18.083 | 0.544 |
| go-v0.40 x go-v0.38 (wss, noise, yamux) | go-v0.40 | go-v0.38 | wss | noise | yamux | ✅ | 4s | 23.577 | 0.921 |
| go-v0.40 x go-v0.38 (quic-v1) | go-v0.40 | go-v0.38 | quic-v1 | - | - | ✅ | 4s | 6.66 | 0.251 |
| go-v0.40 x go-v0.38 (webtransport) | go-v0.40 | go-v0.38 | webtransport | - | - | ✅ | 5s | 7.816 | 0.324 |
| go-v0.40 x rust-v0.56 (webrtc-direct) | go-v0.40 | rust-v0.56 | webrtc-direct | - | - | ❌ | 10s | - | - |
| go-v0.40 x go-v0.38 (webrtc-direct) | go-v0.40 | go-v0.38 | webrtc-direct | - | - | ✅ | 5s | 209.917 | 0.474 |
| go-v0.40 x go-v0.39 (tcp, tls, yamux) | go-v0.40 | go-v0.39 | tcp | tls | yamux | ✅ | 5s | 9.179 | 0.966 |
| go-v0.40 x go-v0.39 (tcp, noise, yamux) | go-v0.40 | go-v0.39 | tcp | noise | yamux | ✅ | 4s | 7.979 | 1.39 |
| go-v0.40 x go-v0.39 (ws, tls, yamux) | go-v0.40 | go-v0.39 | ws | tls | yamux | ✅ | 5s | 12.392 | 0.599 |
| go-v0.40 x go-v0.39 (ws, noise, yamux) | go-v0.40 | go-v0.39 | ws | noise | yamux | ✅ | 5s | 12.922 | 0.404 |
| go-v0.40 x go-v0.39 (wss, tls, yamux) | go-v0.40 | go-v0.39 | wss | tls | yamux | ✅ | 5s | 12.669 | 0.242 |
| go-v0.40 x go-v0.39 (quic-v1) | go-v0.40 | go-v0.39 | quic-v1 | - | - | ✅ | 4s | 11.801 | 0.58 |
| go-v0.40 x go-v0.39 (wss, noise, yamux) | go-v0.40 | go-v0.39 | wss | noise | yamux | ✅ | 6s | 14.217 | 2.889 |
| go-v0.40 x go-v0.39 (webtransport) | go-v0.40 | go-v0.39 | webtransport | - | - | ✅ | 5s | 16.58 | 1.078 |
| go-v0.40 x go-v0.40 (tcp, tls, yamux) | go-v0.40 | go-v0.40 | tcp | tls | yamux | ✅ | 5s | 9.791 | 1.031 |
| go-v0.40 x go-v0.39 (webrtc-direct) | go-v0.40 | go-v0.39 | webrtc-direct | - | - | ✅ | 6s | 220.155 | 0.632 |
| go-v0.40 x go-v0.40 (tcp, noise, yamux) | go-v0.40 | go-v0.40 | tcp | noise | yamux | ✅ | 4s | 6.445 | 0.473 |
| go-v0.40 x go-v0.40 (ws, tls, yamux) | go-v0.40 | go-v0.40 | ws | tls | yamux | ✅ | 5s | 4.844 | 0.193 |
| go-v0.40 x go-v0.40 (ws, noise, yamux) | go-v0.40 | go-v0.40 | ws | noise | yamux | ✅ | 5s | 6.369 | 0.393 |
| go-v0.40 x go-v0.40 (quic-v1) | go-v0.40 | go-v0.40 | quic-v1 | - | - | ✅ | 4s | 15.133 | 0.723 |
| go-v0.40 x go-v0.40 (wss, noise, yamux) | go-v0.40 | go-v0.40 | wss | noise | yamux | ✅ | 5s | 16.839 | 0.312 |
| go-v0.40 x go-v0.40 (wss, tls, yamux) | go-v0.40 | go-v0.40 | wss | tls | yamux | ✅ | 5s | 18.662 | 0.258 |
| go-v0.40 x go-v0.40 (webtransport) | go-v0.40 | go-v0.40 | webtransport | - | - | ✅ | 4s | 14.828 | 1.025 |
| go-v0.40 x go-v0.40 (webrtc-direct) | go-v0.40 | go-v0.40 | webrtc-direct | - | - | ✅ | 4s | 223.56 | 0.611 |
| go-v0.40 x go-v0.41 (tcp, tls, yamux) | go-v0.40 | go-v0.41 | tcp | tls | yamux | ✅ | 5s | 13.511 | 1.584 |
| go-v0.40 x go-v0.41 (ws, tls, yamux) | go-v0.40 | go-v0.41 | ws | tls | yamux | ✅ | 5s | 14.579 | 0.598 |
| go-v0.40 x go-v0.41 (tcp, noise, yamux) | go-v0.40 | go-v0.41 | tcp | noise | yamux | ✅ | 5s | 9.639 | 1.438 |
| go-v0.40 x go-v0.41 (ws, noise, yamux) | go-v0.40 | go-v0.41 | ws | noise | yamux | ✅ | 5s | 12.395 | 0.329 |
| go-v0.40 x go-v0.41 (wss, tls, yamux) | go-v0.40 | go-v0.41 | wss | tls | yamux | ✅ | 5s | 32.47 | 0.445 |
| go-v0.40 x go-v0.41 (quic-v1) | go-v0.40 | go-v0.41 | quic-v1 | - | - | ✅ | 5s | 18.08 | 1.278 |
| go-v0.40 x go-v0.41 (webtransport) | go-v0.40 | go-v0.41 | webtransport | - | - | ✅ | 4s | 12.881 | 0.422 |
| go-v0.40 x go-v0.41 (wss, noise, yamux) | go-v0.40 | go-v0.41 | wss | noise | yamux | ✅ | 7s | 12.745 | 0.294 |
| go-v0.40 x go-v0.41 (webrtc-direct) | go-v0.40 | go-v0.41 | webrtc-direct | - | - | ✅ | 4s | 14.253 | 0.664 |
| go-v0.40 x go-v0.42 (tcp, noise, yamux) | go-v0.40 | go-v0.42 | tcp | noise | yamux | ✅ | 4s | 8.334 | 0.458 |
| go-v0.40 x go-v0.42 (tcp, tls, yamux) | go-v0.40 | go-v0.42 | tcp | tls | yamux | ✅ | 5s | 7.411 | 0.819 |
| go-v0.40 x go-v0.42 (ws, tls, yamux) | go-v0.40 | go-v0.42 | ws | tls | yamux | ✅ | 5s | 10.184 | 0.934 |
| go-v0.40 x go-v0.42 (ws, noise, yamux) | go-v0.40 | go-v0.42 | ws | noise | yamux | ✅ | 4s | 7.809 | 0.271 |
| go-v0.40 x go-v0.42 (wss, tls, yamux) | go-v0.40 | go-v0.42 | wss | tls | yamux | ✅ | 5s | 26.988 | 1.134 |
| go-v0.40 x go-v0.42 (quic-v1) | go-v0.40 | go-v0.42 | quic-v1 | - | - | ✅ | 5s | 18.995 | 0.68 |
| go-v0.40 x go-v0.42 (wss, noise, yamux) | go-v0.40 | go-v0.42 | wss | noise | yamux | ✅ | 5s | 12.176 | 0.543 |
| go-v0.40 x go-v0.42 (webtransport) | go-v0.40 | go-v0.42 | webtransport | - | - | ✅ | 5s | 8.802 | 0.243 |
| go-v0.40 x go-v0.42 (webrtc-direct) | go-v0.40 | go-v0.42 | webrtc-direct | - | - | ✅ | 4s | 214.44 | 1.348 |
| go-v0.40 x go-v0.43 (tcp, tls, yamux) | go-v0.40 | go-v0.43 | tcp | tls | yamux | ✅ | 4s | 12.161 | 4.169 |
| go-v0.40 x go-v0.43 (tcp, noise, yamux) | go-v0.40 | go-v0.43 | tcp | noise | yamux | ✅ | 4s | 7.805 | 0.272 |
| go-v0.40 x go-v0.43 (ws, tls, yamux) | go-v0.40 | go-v0.43 | ws | tls | yamux | ✅ | 4s | 9.91 | 0.734 |
| go-v0.40 x go-v0.43 (ws, noise, yamux) | go-v0.40 | go-v0.43 | ws | noise | yamux | ✅ | 4s | 8.516 | 0.991 |
| go-v0.40 x go-v0.43 (wss, tls, yamux) | go-v0.40 | go-v0.43 | wss | tls | yamux | ✅ | 6s | 17.443 | 1.177 |
| go-v0.40 x go-v0.43 (wss, noise, yamux) | go-v0.40 | go-v0.43 | wss | noise | yamux | ✅ | 5s | 17.306 | 0.533 |
| go-v0.40 x go-v0.43 (quic-v1) | go-v0.40 | go-v0.43 | quic-v1 | - | - | ✅ | 5s | 6.847 | 0.326 |
| go-v0.40 x go-v0.43 (webtransport) | go-v0.40 | go-v0.43 | webtransport | - | - | ✅ | 5s | 11.093 | 1.967 |
| go-v0.40 x go-v0.43 (webrtc-direct) | go-v0.40 | go-v0.43 | webrtc-direct | - | - | ✅ | 4s | 213.986 | 0.902 |
| go-v0.40 x go-v0.44 (tcp, tls, yamux) | go-v0.40 | go-v0.44 | tcp | tls | yamux | ✅ | 5s | 7.357 | 0.525 |
| go-v0.40 x go-v0.44 (tcp, noise, yamux) | go-v0.40 | go-v0.44 | tcp | noise | yamux | ✅ | 5s | 9.205 | 1.07 |
| go-v0.40 x go-v0.44 (ws, tls, yamux) | go-v0.40 | go-v0.44 | ws | tls | yamux | ✅ | 4s | 10.106 | 0.911 |
| go-v0.40 x go-v0.44 (ws, noise, yamux) | go-v0.40 | go-v0.44 | ws | noise | yamux | ✅ | 4s | 9.71 | 0.505 |
| go-v0.40 x go-v0.44 (wss, tls, yamux) | go-v0.40 | go-v0.44 | wss | tls | yamux | ✅ | 5s | 13.412 | 0.656 |
| go-v0.40 x go-v0.44 (quic-v1) | go-v0.40 | go-v0.44 | quic-v1 | - | - | ✅ | 5s | 16.046 | 1.668 |
| go-v0.40 x go-v0.44 (webtransport) | go-v0.40 | go-v0.44 | webtransport | - | - | ✅ | 4s | 14.903 | 0.404 |
| go-v0.40 x go-v0.44 (wss, noise, yamux) | go-v0.40 | go-v0.44 | wss | noise | yamux | ✅ | 6s | 13.583 | 0.309 |
| go-v0.40 x go-v0.44 (webrtc-direct) | go-v0.40 | go-v0.44 | webrtc-direct | - | - | ✅ | 4s | 210.898 | 0.269 |
| go-v0.40 x go-v0.45 (tcp, tls, yamux) | go-v0.40 | go-v0.45 | tcp | tls | yamux | ✅ | 5s | 5.636 | 0.404 |
| go-v0.40 x go-v0.45 (tcp, noise, yamux) | go-v0.40 | go-v0.45 | tcp | noise | yamux | ✅ | 5s | 11.107 | 0.507 |
| go-v0.40 x go-v0.45 (ws, tls, yamux) | go-v0.40 | go-v0.45 | ws | tls | yamux | ✅ | 4s | 17.211 | 2.482 |
| go-v0.40 x go-v0.45 (ws, noise, yamux) | go-v0.40 | go-v0.45 | ws | noise | yamux | ✅ | 5s | 7.916 | 1.275 |
| go-v0.40 x go-v0.45 (wss, tls, yamux) | go-v0.40 | go-v0.45 | wss | tls | yamux | ✅ | 5s | 18.993 | 1.061 |
| go-v0.40 x go-v0.45 (quic-v1) | go-v0.40 | go-v0.45 | quic-v1 | - | - | ✅ | 5s | 15.315 | 0.791 |
| go-v0.40 x go-v0.45 (wss, noise, yamux) | go-v0.40 | go-v0.45 | wss | noise | yamux | ✅ | 5s | 15.591 | 1.085 |
| go-v0.40 x go-v0.45 (webtransport) | go-v0.40 | go-v0.45 | webtransport | - | - | ✅ | 5s | 11.543 | 0.385 |
| go-v0.40 x go-v0.45 (webrtc-direct) | go-v0.40 | go-v0.45 | webrtc-direct | - | - | ✅ | 5s | 225.894 | 0.912 |
| go-v0.40 x python-v0.4 (tcp, noise, yamux) | go-v0.40 | python-v0.4 | tcp | noise | yamux | ✅ | 5s | 16.498 | 2.114 |
| go-v0.40 x python-v0.4 (ws, noise, yamux) | go-v0.40 | python-v0.4 | ws | noise | yamux | ✅ | 5s | 31.751 | 3.095 |
| go-v0.40 x python-v0.4 (wss, noise, yamux) | go-v0.40 | python-v0.4 | wss | noise | yamux | ✅ | 5s | 38.53 | 6.981 |
| go-v0.40 x python-v0.4 (quic-v1) | go-v0.40 | python-v0.4 | quic-v1 | - | - | ✅ | 6s | 94.518 | 9.862 |
| go-v0.40 x nim-v1.14 (tcp, noise, yamux) | go-v0.40 | nim-v1.14 | tcp | noise | yamux | ✅ | 5s | 216.072 | 47.617 |
| go-v0.40 x nim-v1.14 (ws, noise, yamux) | go-v0.40 | nim-v1.14 | ws | noise | yamux | ✅ | 5s | 256.71 | 47.446 |
| go-v0.40 x js-v1.x (ws, noise, yamux) | go-v0.40 | js-v1.x | ws | noise | yamux | ✅ | 18s | 172.956 | 18.608 |
| go-v0.40 x js-v1.x (tcp, noise, yamux) | go-v0.40 | js-v1.x | tcp | noise | yamux | ✅ | 20s | 153.407 | 20.617 |
| go-v0.40 x js-v2.x (tcp, noise, yamux) | go-v0.40 | js-v2.x | tcp | noise | yamux | ✅ | 22s | 150.694 | 21.478 |
| go-v0.40 x jvm-v1.2 (tcp, noise, yamux) | go-v0.40 | jvm-v1.2 | tcp | noise | yamux | ✅ | 11s | 1153.953 | 13.247 |
| go-v0.40 x js-v2.x (ws, noise, yamux) | go-v0.40 | js-v2.x | ws | noise | yamux | ✅ | 22s | 136.664 | 27.092 |
| go-v0.40 x jvm-v1.2 (tcp, tls, yamux) | go-v0.40 | jvm-v1.2 | tcp | tls | yamux | ✅ | 12s | 3151.085 | 10.704 |
| go-v0.40 x js-v3.x (tcp, noise, yamux) | go-v0.40 | js-v3.x | tcp | noise | yamux | ✅ | 22s | 127.548 | 12.48 |
| go-v0.40 x js-v3.x (ws, noise, yamux) | go-v0.40 | js-v3.x | ws | noise | yamux | ✅ | 21s | 111.555 | 13.329 |
| go-v0.40 x c-v0.0.1 (tcp, noise, yamux) | go-v0.40 | c-v0.0.1 | tcp | noise | yamux | ✅ | 6s | 121.281 | 56.823 |
| go-v0.40 x c-v0.0.1 (quic-v1) | go-v0.40 | c-v0.0.1 | quic-v1 | - | - | ✅ | 5s | 86.862 | 56.493 |
| go-v0.40 x jvm-v1.2 (ws, noise, yamux) | go-v0.40 | jvm-v1.2 | ws | noise | yamux | ✅ | 10s | 1689.068 | 59.918 |
| go-v0.40 x dotnet-v1.0 (tcp, noise, yamux) | go-v0.40 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 6s | 441.187 | 50.608 |
| go-v0.40 x zig-v0.0.1 (quic-v1) | go-v0.40 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 7s | - | - |
| go-v0.40 x eth-p2p-z-v0.0.1 (quic-v1) | go-v0.40 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 7.552 | 0.183 |
| go-v0.40 x jvm-v1.2 (ws, tls, yamux) | go-v0.40 | jvm-v1.2 | ws | tls | yamux | ✅ | 12s | 3212.947 | 14.701 |
| go-v0.40 x jvm-v1.2 (quic-v1) | go-v0.40 | jvm-v1.2 | quic-v1 | - | - | ✅ | 10s | 441.168 | 11.525 |
| go-v0.41 x rust-v0.53 (tcp, tls, yamux) | go-v0.41 | rust-v0.53 | tcp | tls | yamux | ✅ | 4s | 101.26 | 44.883 |
| go-v0.41 x rust-v0.53 (tcp, noise, yamux) | go-v0.41 | rust-v0.53 | tcp | noise | yamux | ✅ | 4s | 95.243 | 45.992 |
| go-v0.41 x rust-v0.53 (ws, noise, yamux) | go-v0.41 | rust-v0.53 | ws | noise | yamux | ✅ | 4s | 184.25 | 44.514 |
| go-v0.41 x rust-v0.53 (ws, tls, yamux) | go-v0.41 | rust-v0.53 | ws | tls | yamux | ✅ | 6s | 239.785 | 43.441 |
| go-v0.41 x rust-v0.53 (quic-v1) | go-v0.41 | rust-v0.53 | quic-v1 | - | - | ✅ | 5s | 6.4 | 0.478 |
| go-v0.41 x rust-v0.53 (webrtc-direct) | go-v0.41 | rust-v0.53 | webrtc-direct | - | - | ✅ | 6s | 414.363 | 0.672 |
| go-v0.41 x rust-v0.54 (tcp, tls, yamux) | go-v0.41 | rust-v0.54 | tcp | tls | yamux | ✅ | 5s | 89.771 | 42.448 |
| go-v0.41 x rust-v0.54 (tcp, noise, yamux) | go-v0.41 | rust-v0.54 | tcp | noise | yamux | ✅ | 5s | 131.354 | 43.754 |
| go-v0.41 x rust-v0.54 (ws, tls, yamux) | go-v0.41 | rust-v0.54 | ws | tls | yamux | ✅ | 5s | 184.741 | 41.881 |
| go-v0.41 x rust-v0.54 (ws, noise, yamux) | go-v0.41 | rust-v0.54 | ws | noise | yamux | ✅ | 6s | 218.267 | 43.473 |
| go-v0.41 x rust-v0.54 (quic-v1) | go-v0.41 | rust-v0.54 | quic-v1 | - | - | ✅ | 4s | 8.25 | 0.442 |
| go-v0.41 x rust-v0.55 (tcp, noise, yamux) | go-v0.41 | rust-v0.55 | tcp | noise | yamux | ✅ | 5s | 8.818 | 0.468 |
| go-v0.41 x rust-v0.54 (webrtc-direct) | go-v0.41 | rust-v0.54 | webrtc-direct | - | - | ✅ | 6s | 418.511 | 1.38 |
| go-v0.41 x rust-v0.55 (tcp, tls, yamux) | go-v0.41 | rust-v0.55 | tcp | tls | yamux | ✅ | 6s | 15.361 | 0.722 |
| go-v0.41 x rust-v0.55 (ws, tls, yamux) | go-v0.41 | rust-v0.55 | ws | tls | yamux | ✅ | 5s | 17.23 | 0.405 |
| go-v0.41 x rust-v0.55 (ws, noise, yamux) | go-v0.41 | rust-v0.55 | ws | noise | yamux | ✅ | 5s | 3.578 | 0.163 |
| go-v0.41 x rust-v0.55 (quic-v1) | go-v0.41 | rust-v0.55 | quic-v1 | - | - | ✅ | 5s | 4.578 | 0.245 |
| go-v0.41 x rust-v0.56 (tcp, tls, yamux) | go-v0.41 | rust-v0.56 | tcp | tls | yamux | ✅ | 3s | 14.165 | 0.555 |
| go-v0.41 x rust-v0.55 (webrtc-direct) | go-v0.41 | rust-v0.55 | webrtc-direct | - | - | ✅ | 5s | 413.456 | 0.62 |
| go-v0.41 x rust-v0.56 (ws, noise, yamux) | go-v0.41 | rust-v0.56 | ws | noise | yamux | ✅ | 4s | 7.934 | 0.594 |
| go-v0.41 x rust-v0.56 (tcp, noise, yamux) | go-v0.41 | rust-v0.56 | tcp | noise | yamux | ✅ | 6s | 10.808 | 0.179 |
| go-v0.41 x rust-v0.56 (ws, tls, yamux) | go-v0.41 | rust-v0.56 | ws | tls | yamux | ✅ | 5s | 11.296 | 0.397 |
| go-v0.41 x rust-v0.56 (quic-v1) | go-v0.41 | rust-v0.56 | quic-v1 | - | - | ✅ | 5s | 11.46 | 0.499 |
| go-v0.41 x go-v0.38 (tcp, tls, yamux) | go-v0.41 | go-v0.38 | tcp | tls | yamux | ✅ | 5s | 10.833 | 1.459 |
| go-v0.41 x go-v0.38 (tcp, noise, yamux) | go-v0.41 | go-v0.38 | tcp | noise | yamux | ✅ | 4s | 9.388 | 0.384 |
| go-v0.41 x go-v0.38 (ws, tls, yamux) | go-v0.41 | go-v0.38 | ws | tls | yamux | ✅ | 4s | 8.469 | 0.69 |
| go-v0.41 x go-v0.38 (ws, noise, yamux) | go-v0.41 | go-v0.38 | ws | noise | yamux | ✅ | 4s | 10.961 | 2.005 |
| go-v0.41 x go-v0.38 (wss, tls, yamux) | go-v0.41 | go-v0.38 | wss | tls | yamux | ✅ | 5s | 14.104 | 0.932 |
| go-v0.41 x go-v0.38 (quic-v1) | go-v0.41 | go-v0.38 | quic-v1 | - | - | ✅ | 4s | 12.007 | 0.542 |
| go-v0.41 x go-v0.38 (webtransport) | go-v0.41 | go-v0.38 | webtransport | - | - | ✅ | 4s | 10.722 | 0.487 |
| go-v0.41 x go-v0.38 (wss, noise, yamux) | go-v0.41 | go-v0.38 | wss | noise | yamux | ✅ | 5s | 13.988 | 1.472 |
| go-v0.41 x rust-v0.56 (webrtc-direct) | go-v0.41 | rust-v0.56 | webrtc-direct | - | - | ❌ | 10s | - | - |
| go-v0.41 x go-v0.38 (webrtc-direct) | go-v0.41 | go-v0.38 | webrtc-direct | - | - | ✅ | 5s | 212.529 | 0.283 |
| go-v0.41 x go-v0.39 (tcp, tls, yamux) | go-v0.41 | go-v0.39 | tcp | tls | yamux | ✅ | 4s | 6.319 | 0.27 |
| go-v0.41 x go-v0.39 (tcp, noise, yamux) | go-v0.41 | go-v0.39 | tcp | noise | yamux | ✅ | 4s | 8.01 | 0.296 |
| go-v0.41 x go-v0.39 (ws, tls, yamux) | go-v0.41 | go-v0.39 | ws | tls | yamux | ✅ | 4s | 10.002 | 0.454 |
| go-v0.41 x go-v0.39 (ws, noise, yamux) | go-v0.41 | go-v0.39 | ws | noise | yamux | ✅ | 5s | 6.267 | 1.015 |
| go-v0.41 x go-v0.39 (wss, noise, yamux) | go-v0.41 | go-v0.39 | wss | noise | yamux | ✅ | 5s | 21.733 | 1.601 |
| go-v0.41 x go-v0.39 (wss, tls, yamux) | go-v0.41 | go-v0.39 | wss | tls | yamux | ✅ | 6s | 18.532 | 2.808 |
| go-v0.41 x go-v0.39 (quic-v1) | go-v0.41 | go-v0.39 | quic-v1 | - | - | ✅ | 5s | 10.402 | 0.72 |
| go-v0.41 x go-v0.39 (webtransport) | go-v0.41 | go-v0.39 | webtransport | - | - | ✅ | 6s | 8.968 | 0.366 |
| go-v0.41 x go-v0.39 (webrtc-direct) | go-v0.41 | go-v0.39 | webrtc-direct | - | - | ✅ | 5s | 208.147 | 0.237 |
| go-v0.41 x go-v0.40 (tcp, tls, yamux) | go-v0.41 | go-v0.40 | tcp | tls | yamux | ✅ | 5s | 7.108 | 1.686 |
| go-v0.41 x go-v0.40 (tcp, noise, yamux) | go-v0.41 | go-v0.40 | tcp | noise | yamux | ✅ | 4s | 5.447 | 0.304 |
| go-v0.41 x go-v0.40 (ws, tls, yamux) | go-v0.41 | go-v0.40 | ws | tls | yamux | ✅ | 5s | 7.409 | 0.433 |
| go-v0.41 x go-v0.40 (ws, noise, yamux) | go-v0.41 | go-v0.40 | ws | noise | yamux | ✅ | 4s | 12.265 | 5.116 |
| go-v0.41 x go-v0.40 (wss, tls, yamux) | go-v0.41 | go-v0.40 | wss | tls | yamux | ✅ | 5s | 14.136 | 0.488 |
| go-v0.41 x go-v0.40 (quic-v1) | go-v0.41 | go-v0.40 | quic-v1 | - | - | ✅ | 5s | 10.061 | 0.507 |
| go-v0.41 x go-v0.40 (wss, noise, yamux) | go-v0.41 | go-v0.40 | wss | noise | yamux | ✅ | 5s | 7.563 | 0.238 |
| go-v0.41 x go-v0.40 (webtransport) | go-v0.41 | go-v0.40 | webtransport | - | - | ✅ | 4s | 6.969 | 0.403 |
| go-v0.41 x go-v0.40 (webrtc-direct) | go-v0.41 | go-v0.40 | webrtc-direct | - | - | ✅ | 5s | 212.231 | 0.273 |
| go-v0.41 x go-v0.41 (tcp, tls, yamux) | go-v0.41 | go-v0.41 | tcp | tls | yamux | ✅ | 5s | 7.88 | 0.57 |
| go-v0.41 x go-v0.41 (tcp, noise, yamux) | go-v0.41 | go-v0.41 | tcp | noise | yamux | ✅ | 5s | 8.443 | 0.257 |
| go-v0.41 x go-v0.41 (ws, tls, yamux) | go-v0.41 | go-v0.41 | ws | tls | yamux | ✅ | 4s | 7.732 | 0.347 |
| go-v0.41 x go-v0.41 (ws, noise, yamux) | go-v0.41 | go-v0.41 | ws | noise | yamux | ✅ | 4s | 7.012 | 0.245 |
| go-v0.41 x go-v0.41 (wss, tls, yamux) | go-v0.41 | go-v0.41 | wss | tls | yamux | ✅ | 4s | 10.661 | 0.314 |
| go-v0.41 x go-v0.41 (wss, noise, yamux) | go-v0.41 | go-v0.41 | wss | noise | yamux | ✅ | 5s | 13.603 | 0.651 |
| go-v0.41 x go-v0.41 (webtransport) | go-v0.41 | go-v0.41 | webtransport | - | - | ✅ | 4s | 14.689 | 1.226 |
| go-v0.41 x go-v0.41 (quic-v1) | go-v0.41 | go-v0.41 | quic-v1 | - | - | ✅ | 6s | 12.53 | 1.038 |
| go-v0.41 x go-v0.41 (webrtc-direct) | go-v0.41 | go-v0.41 | webrtc-direct | - | - | ✅ | 5s | 209.029 | 0.294 |
| go-v0.41 x go-v0.42 (tcp, tls, yamux) | go-v0.41 | go-v0.42 | tcp | tls | yamux | ✅ | 5s | 16.063 | 6.251 |
| go-v0.41 x go-v0.42 (tcp, noise, yamux) | go-v0.41 | go-v0.42 | tcp | noise | yamux | ✅ | 5s | 7.676 | 0.946 |
| go-v0.41 x go-v0.42 (ws, tls, yamux) | go-v0.41 | go-v0.42 | ws | tls | yamux | ✅ | 5s | 7.805 | 0.437 |
| go-v0.41 x go-v0.42 (ws, noise, yamux) | go-v0.41 | go-v0.42 | ws | noise | yamux | ✅ | 5s | 9.398 | 0.72 |
| go-v0.41 x go-v0.42 (wss, tls, yamux) | go-v0.41 | go-v0.42 | wss | tls | yamux | ✅ | 5s | 22.751 | 0.992 |
| go-v0.41 x go-v0.42 (quic-v1) | go-v0.41 | go-v0.42 | quic-v1 | - | - | ✅ | 5s | 22.112 | 3.358 |
| go-v0.41 x go-v0.42 (wss, noise, yamux) | go-v0.41 | go-v0.42 | wss | noise | yamux | ✅ | 5s | 16.729 | 0.522 |
| go-v0.41 x go-v0.42 (webtransport) | go-v0.41 | go-v0.42 | webtransport | - | - | ✅ | 5s | 11.041 | 0.887 |
| go-v0.41 x go-v0.42 (webrtc-direct) | go-v0.41 | go-v0.42 | webrtc-direct | - | - | ✅ | 4s | 227.87 | 4.452 |
| go-v0.41 x go-v0.43 (tcp, tls, yamux) | go-v0.41 | go-v0.43 | tcp | tls | yamux | ✅ | 4s | 10.413 | 0.716 |
| go-v0.41 x go-v0.43 (tcp, noise, yamux) | go-v0.41 | go-v0.43 | tcp | noise | yamux | ✅ | 5s | 9.108 | 0.837 |
| go-v0.41 x go-v0.43 (ws, tls, yamux) | go-v0.41 | go-v0.43 | ws | tls | yamux | ✅ | 5s | 6.807 | 0.249 |
| go-v0.41 x go-v0.43 (ws, noise, yamux) | go-v0.41 | go-v0.43 | ws | noise | yamux | ✅ | 5s | 13.164 | 0.369 |
| go-v0.41 x go-v0.43 (wss, tls, yamux) | go-v0.41 | go-v0.43 | wss | tls | yamux | ✅ | 5s | 13.916 | 0.858 |
| go-v0.41 x go-v0.43 (wss, noise, yamux) | go-v0.41 | go-v0.43 | wss | noise | yamux | ✅ | 4s | 21.801 | 1.627 |
| go-v0.41 x go-v0.43 (quic-v1) | go-v0.41 | go-v0.43 | quic-v1 | - | - | ✅ | 5s | 11.972 | 0.641 |
| go-v0.41 x go-v0.43 (webtransport) | go-v0.41 | go-v0.43 | webtransport | - | - | ✅ | 5s | 16.398 | 0.722 |
| go-v0.41 x go-v0.43 (webrtc-direct) | go-v0.41 | go-v0.43 | webrtc-direct | - | - | ✅ | 5s | 220.489 | 0.665 |
| go-v0.41 x go-v0.44 (tcp, tls, yamux) | go-v0.41 | go-v0.44 | tcp | tls | yamux | ✅ | 5s | 6.354 | 0.376 |
| go-v0.41 x go-v0.44 (tcp, noise, yamux) | go-v0.41 | go-v0.44 | tcp | noise | yamux | ✅ | 5s | 9.167 | 0.319 |
| go-v0.41 x go-v0.44 (ws, noise, yamux) | go-v0.41 | go-v0.44 | ws | noise | yamux | ✅ | 4s | 6.428 | 0.669 |
| go-v0.41 x go-v0.44 (ws, tls, yamux) | go-v0.41 | go-v0.44 | ws | tls | yamux | ✅ | 5s | 11.246 | 1.54 |
| go-v0.41 x go-v0.44 (wss, tls, yamux) | go-v0.41 | go-v0.44 | wss | tls | yamux | ✅ | 5s | 21.174 | 0.725 |
| go-v0.41 x go-v0.44 (wss, noise, yamux) | go-v0.41 | go-v0.44 | wss | noise | yamux | ✅ | 6s | 12.763 | 0.348 |
| go-v0.41 x go-v0.44 (quic-v1) | go-v0.41 | go-v0.44 | quic-v1 | - | - | ✅ | 5s | 7.459 | 0.448 |
| go-v0.41 x go-v0.44 (webtransport) | go-v0.41 | go-v0.44 | webtransport | - | - | ✅ | 5s | 9.354 | 0.337 |
| go-v0.41 x go-v0.44 (webrtc-direct) | go-v0.41 | go-v0.44 | webrtc-direct | - | - | ✅ | 4s | 211.628 | 0.485 |
| go-v0.41 x go-v0.45 (tcp, tls, yamux) | go-v0.41 | go-v0.45 | tcp | tls | yamux | ✅ | 4s | 10.965 | 0.754 |
| go-v0.41 x go-v0.45 (tcp, noise, yamux) | go-v0.41 | go-v0.45 | tcp | noise | yamux | ✅ | 4s | 7.719 | 0.993 |
| go-v0.41 x go-v0.45 (ws, tls, yamux) | go-v0.41 | go-v0.45 | ws | tls | yamux | ✅ | 5s | 23.741 | 0.412 |
| go-v0.41 x go-v0.45 (ws, noise, yamux) | go-v0.41 | go-v0.45 | ws | noise | yamux | ✅ | 5s | 15.83 | 2.089 |
| go-v0.41 x go-v0.45 (wss, noise, yamux) | go-v0.41 | go-v0.45 | wss | noise | yamux | ✅ | 5s | 14.173 | 0.571 |
| go-v0.41 x go-v0.45 (wss, tls, yamux) | go-v0.41 | go-v0.45 | wss | tls | yamux | ✅ | 5s | 7.314 | 0.174 |
| go-v0.41 x go-v0.45 (quic-v1) | go-v0.41 | go-v0.45 | quic-v1 | - | - | ✅ | 5s | 12.806 | 0.281 |
| go-v0.41 x go-v0.45 (webtransport) | go-v0.41 | go-v0.45 | webtransport | - | - | ✅ | 5s | 20.409 | 0.433 |
| go-v0.41 x go-v0.45 (webrtc-direct) | go-v0.41 | go-v0.45 | webrtc-direct | - | - | ✅ | 4s | 216.22 | 1.414 |
| go-v0.41 x python-v0.4 (tcp, noise, yamux) | go-v0.41 | python-v0.4 | tcp | noise | yamux | ✅ | 5s | 22.516 | 5.469 |
| go-v0.41 x python-v0.4 (wss, noise, yamux) | go-v0.41 | python-v0.4 | wss | noise | yamux | ✅ | 5s | 54.453 | 11.018 |
| go-v0.41 x python-v0.4 (ws, noise, yamux) | go-v0.41 | python-v0.4 | ws | noise | yamux | ✅ | 6s | 26.784 | 5.449 |
| go-v0.41 x python-v0.4 (quic-v1) | go-v0.41 | python-v0.4 | quic-v1 | - | - | ✅ | 5s | 87.995 | 15.202 |
| go-v0.41 x nim-v1.14 (tcp, noise, yamux) | go-v0.41 | nim-v1.14 | tcp | noise | yamux | ✅ | 5s | 237.25 | 47.549 |
| go-v0.41 x nim-v1.14 (ws, noise, yamux) | go-v0.41 | nim-v1.14 | ws | noise | yamux | ✅ | 5s | 249.354 | 43.575 |
| go-v0.41 x js-v1.x (tcp, noise, yamux) | go-v0.41 | js-v1.x | tcp | noise | yamux | ✅ | 18s | 146.913 | 18.283 |
| go-v0.41 x js-v1.x (ws, noise, yamux) | go-v0.41 | js-v1.x | ws | noise | yamux | ✅ | 18s | 203.482 | 15.998 |
| go-v0.41 x js-v2.x (tcp, noise, yamux) | go-v0.41 | js-v2.x | tcp | noise | yamux | ✅ | 21s | 161.215 | 25.591 |
| go-v0.41 x js-v3.x (tcp, noise, yamux) | go-v0.41 | js-v3.x | tcp | noise | yamux | ✅ | 20s | 138.623 | 13.791 |
| go-v0.41 x js-v2.x (ws, noise, yamux) | go-v0.41 | js-v2.x | ws | noise | yamux | ✅ | 22s | 162.924 | 29.705 |
| go-v0.41 x jvm-v1.2 (tcp, noise, yamux) | go-v0.41 | jvm-v1.2 | tcp | noise | yamux | ✅ | 10s | 1097.784 | 13.965 |
| go-v0.41 x jvm-v1.2 (tcp, tls, yamux) | go-v0.41 | jvm-v1.2 | tcp | tls | yamux | ✅ | 12s | 3312.003 | 9.878 |
| go-v0.41 x js-v3.x (ws, noise, yamux) | go-v0.41 | js-v3.x | ws | noise | yamux | ✅ | 21s | 174.003 | 16.278 |
| go-v0.41 x c-v0.0.1 (tcp, noise, yamux) | go-v0.41 | c-v0.0.1 | tcp | noise | yamux | ✅ | 5s | 134.142 | 55.212 |
| go-v0.41 x c-v0.0.1 (quic-v1) | go-v0.41 | c-v0.0.1 | quic-v1 | - | - | ✅ | 5s | 49.066 | 34.382 |
| go-v0.41 x jvm-v1.2 (ws, tls, yamux) | go-v0.41 | jvm-v1.2 | ws | tls | yamux | ✅ | 12s | 3806.954 | 16.191 |
| go-v0.41 x jvm-v1.2 (ws, noise, yamux) | go-v0.41 | jvm-v1.2 | ws | noise | yamux | ✅ | 10s | 1528.615 | 31.822 |
| go-v0.41 x dotnet-v1.0 (tcp, noise, yamux) | go-v0.41 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 6s | 338.346 | 47.134 |
| go-v0.41 x zig-v0.0.1 (quic-v1) | go-v0.41 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 6s | - | - |
| go-v0.41 x jvm-v1.2 (quic-v1) | go-v0.41 | jvm-v1.2 | quic-v1 | - | - | ✅ | 10s | 582.204 | 7.084 |
| go-v0.41 x eth-p2p-z-v0.0.1 (quic-v1) | go-v0.41 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 7.371 | 0.156 |
| go-v0.42 x rust-v0.53 (tcp, tls, yamux) | go-v0.42 | rust-v0.53 | tcp | tls | yamux | ✅ | 5s | 138.465 | 43.559 |
| go-v0.42 x rust-v0.53 (tcp, noise, yamux) | go-v0.42 | rust-v0.53 | tcp | noise | yamux | ✅ | 5s | 89.07 | 42.288 |
| go-v0.42 x rust-v0.53 (ws, tls, yamux) | go-v0.42 | rust-v0.53 | ws | tls | yamux | ✅ | 4s | 174.126 | 43.303 |
| go-v0.42 x rust-v0.53 (ws, noise, yamux) | go-v0.42 | rust-v0.53 | ws | noise | yamux | ✅ | 5s | 182.133 | 42.311 |
| go-v0.42 x rust-v0.53 (quic-v1) | go-v0.42 | rust-v0.53 | quic-v1 | - | - | ✅ | 6s | 12.895 | 3.003 |
| go-v0.42 x rust-v0.54 (tcp, tls, yamux) | go-v0.42 | rust-v0.54 | tcp | tls | yamux | ✅ | 5s | 140.102 | 43.676 |
| go-v0.42 x rust-v0.53 (webrtc-direct) | go-v0.42 | rust-v0.53 | webrtc-direct | - | - | ✅ | 6s | 695.941 | 1.329 |
| go-v0.42 x rust-v0.54 (tcp, noise, yamux) | go-v0.42 | rust-v0.54 | tcp | noise | yamux | ✅ | 6s | 91.85 | 42.595 |
| go-v0.42 x rust-v0.54 (ws, tls, yamux) | go-v0.42 | rust-v0.54 | ws | tls | yamux | ✅ | 5s | 227.497 | 47.615 |
| go-v0.42 x rust-v0.54 (ws, noise, yamux) | go-v0.42 | rust-v0.54 | ws | noise | yamux | ✅ | 5s | 229.565 | 43.561 |
| go-v0.42 x rust-v0.54 (quic-v1) | go-v0.42 | rust-v0.54 | quic-v1 | - | - | ✅ | 4s | 11.039 | 1.107 |
| go-v0.42 x rust-v0.54 (webrtc-direct) | go-v0.42 | rust-v0.54 | webrtc-direct | - | - | ✅ | 5s | 439.581 | 1.104 |
| go-v0.42 x rust-v0.55 (tcp, tls, yamux) | go-v0.42 | rust-v0.55 | tcp | tls | yamux | ✅ | 5s | 5.845 | 0.901 |
| go-v0.42 x rust-v0.55 (tcp, noise, yamux) | go-v0.42 | rust-v0.55 | tcp | noise | yamux | ✅ | 4s | 65.49 | 0.934 |
| go-v0.42 x rust-v0.55 (ws, tls, yamux) | go-v0.42 | rust-v0.55 | ws | tls | yamux | ✅ | 4s | 4.95 | 0.262 |
| go-v0.42 x rust-v0.55 (quic-v1) | go-v0.42 | rust-v0.55 | quic-v1 | - | - | ✅ | 4s | 30.379 | 5.697 |
| go-v0.42 x rust-v0.55 (ws, noise, yamux) | go-v0.42 | rust-v0.55 | ws | noise | yamux | ✅ | 6s | 5.714 | 0.348 |
| go-v0.42 x rust-v0.55 (webrtc-direct) | go-v0.42 | rust-v0.55 | webrtc-direct | - | - | ✅ | 6s | 416.236 | 1.098 |
| go-v0.42 x rust-v0.56 (tcp, tls, yamux) | go-v0.42 | rust-v0.56 | tcp | tls | yamux | ✅ | 5s | 59.565 | 6.709 |
| go-v0.42 x rust-v0.56 (tcp, noise, yamux) | go-v0.42 | rust-v0.56 | tcp | noise | yamux | ✅ | 6s | 7.429 | 0.309 |
| go-v0.42 x rust-v0.56 (ws, tls, yamux) | go-v0.42 | rust-v0.56 | ws | tls | yamux | ✅ | 5s | 82.577 | 0.502 |
| go-v0.42 x rust-v0.56 (ws, noise, yamux) | go-v0.42 | rust-v0.56 | ws | noise | yamux | ✅ | 5s | 9.55 | 0.343 |
| go-v0.42 x rust-v0.56 (quic-v1) | go-v0.42 | rust-v0.56 | quic-v1 | - | - | ✅ | 4s | 10.549 | 0.223 |
| go-v0.42 x go-v0.38 (tcp, tls, yamux) | go-v0.42 | go-v0.38 | tcp | tls | yamux | ✅ | 5s | 17.249 | 2.807 |
| go-v0.42 x go-v0.38 (tcp, noise, yamux) | go-v0.42 | go-v0.38 | tcp | noise | yamux | ✅ | 4s | 8.384 | 0.514 |
| go-v0.42 x go-v0.38 (ws, tls, yamux) | go-v0.42 | go-v0.38 | ws | tls | yamux | ✅ | 4s | 5.613 | 0.282 |
| go-v0.42 x go-v0.38 (ws, noise, yamux) | go-v0.42 | go-v0.38 | ws | noise | yamux | ✅ | 4s | 10.828 | 1.233 |
| go-v0.42 x go-v0.38 (wss, tls, yamux) | go-v0.42 | go-v0.38 | wss | tls | yamux | ✅ | 5s | 18.291 | 3.284 |
| go-v0.42 x go-v0.38 (quic-v1) | go-v0.42 | go-v0.38 | quic-v1 | - | - | ✅ | 4s | 13.917 | 0.51 |
| go-v0.42 x go-v0.38 (wss, noise, yamux) | go-v0.42 | go-v0.38 | wss | noise | yamux | ✅ | 6s | 10.505 | 0.332 |
| go-v0.42 x rust-v0.56 (webrtc-direct) | go-v0.42 | rust-v0.56 | webrtc-direct | - | - | ❌ | 9s | - | - |
| go-v0.42 x go-v0.38 (webtransport) | go-v0.42 | go-v0.38 | webtransport | - | - | ✅ | 5s | 12.7 | 0.571 |
| go-v0.42 x go-v0.38 (webrtc-direct) | go-v0.42 | go-v0.38 | webrtc-direct | - | - | ✅ | 4s | 217.462 | 0.699 |
| go-v0.42 x go-v0.39 (tcp, tls, yamux) | go-v0.42 | go-v0.39 | tcp | tls | yamux | ✅ | 5s | 7.25 | 0.684 |
| go-v0.42 x go-v0.39 (tcp, noise, yamux) | go-v0.42 | go-v0.39 | tcp | noise | yamux | ✅ | 4s | 5.807 | 0.371 |
| go-v0.42 x go-v0.39 (ws, tls, yamux) | go-v0.42 | go-v0.39 | ws | tls | yamux | ✅ | 5s | 15.155 | 1.27 |
| go-v0.42 x go-v0.39 (ws, noise, yamux) | go-v0.42 | go-v0.39 | ws | noise | yamux | ✅ | 4s | 6.449 | 0.334 |
| go-v0.42 x go-v0.39 (wss, tls, yamux) | go-v0.42 | go-v0.39 | wss | tls | yamux | ✅ | 5s | 9.935 | 0.553 |
| go-v0.42 x go-v0.39 (wss, noise, yamux) | go-v0.42 | go-v0.39 | wss | noise | yamux | ✅ | 5s | 13.339 | 0.625 |
| go-v0.42 x go-v0.39 (quic-v1) | go-v0.42 | go-v0.39 | quic-v1 | - | - | ✅ | 5s | 12.99 | 0.503 |
| go-v0.42 x go-v0.39 (webtransport) | go-v0.42 | go-v0.39 | webtransport | - | - | ✅ | 4s | 20.183 | 0.752 |
| go-v0.42 x go-v0.40 (tcp, tls, yamux) | go-v0.42 | go-v0.40 | tcp | tls | yamux | ✅ | 4s | 11.627 | 0.346 |
| go-v0.42 x go-v0.39 (webrtc-direct) | go-v0.42 | go-v0.39 | webrtc-direct | - | - | ✅ | 5s | 218.082 | 0.923 |
| go-v0.42 x go-v0.40 (tcp, noise, yamux) | go-v0.42 | go-v0.40 | tcp | noise | yamux | ✅ | 4s | 11.706 | 0.523 |
| go-v0.42 x go-v0.40 (ws, tls, yamux) | go-v0.42 | go-v0.40 | ws | tls | yamux | ✅ | 4s | 8.029 | 0.254 |
| go-v0.42 x go-v0.40 (ws, noise, yamux) | go-v0.42 | go-v0.40 | ws | noise | yamux | ✅ | 4s | 6.761 | 0.308 |
| go-v0.42 x go-v0.40 (wss, tls, yamux) | go-v0.42 | go-v0.40 | wss | tls | yamux | ✅ | 5s | 17.363 | 0.566 |
| go-v0.42 x go-v0.40 (quic-v1) | go-v0.42 | go-v0.40 | quic-v1 | - | - | ✅ | 5s | 5.634 | 0.262 |
| go-v0.42 x go-v0.40 (wss, noise, yamux) | go-v0.42 | go-v0.40 | wss | noise | yamux | ✅ | 5s | 6.906 | 0.22 |
| go-v0.42 x go-v0.40 (webtransport) | go-v0.42 | go-v0.40 | webtransport | - | - | ✅ | 5s | 22.544 | 0.713 |
| go-v0.42 x go-v0.40 (webrtc-direct) | go-v0.42 | go-v0.40 | webrtc-direct | - | - | ✅ | 6s | 219.963 | 0.556 |
| go-v0.42 x go-v0.41 (tcp, tls, yamux) | go-v0.42 | go-v0.41 | tcp | tls | yamux | ✅ | 5s | 8.116 | 1.731 |
| go-v0.42 x go-v0.41 (tcp, noise, yamux) | go-v0.42 | go-v0.41 | tcp | noise | yamux | ✅ | 5s | 9.204 | 0.5 |
| go-v0.42 x go-v0.41 (ws, tls, yamux) | go-v0.42 | go-v0.41 | ws | tls | yamux | ✅ | 4s | 10.323 | 0.38 |
| go-v0.42 x go-v0.41 (ws, noise, yamux) | go-v0.42 | go-v0.41 | ws | noise | yamux | ✅ | 5s | 5.925 | 0.247 |
| go-v0.42 x go-v0.41 (wss, noise, yamux) | go-v0.42 | go-v0.41 | wss | noise | yamux | ✅ | 5s | 15.435 | 0.559 |
| go-v0.42 x go-v0.41 (quic-v1) | go-v0.42 | go-v0.41 | quic-v1 | - | - | ✅ | 5s | 14.914 | 2.431 |
| go-v0.42 x go-v0.41 (wss, tls, yamux) | go-v0.42 | go-v0.41 | wss | tls | yamux | ✅ | 6s | 18.982 | 0.949 |
| go-v0.42 x go-v0.41 (webtransport) | go-v0.42 | go-v0.41 | webtransport | - | - | ✅ | 5s | 124.082 | 0.382 |
| go-v0.42 x go-v0.41 (webrtc-direct) | go-v0.42 | go-v0.41 | webrtc-direct | - | - | ✅ | 5s | 208.011 | 0.26 |
| go-v0.42 x go-v0.42 (tcp, tls, yamux) | go-v0.42 | go-v0.42 | tcp | tls | yamux | ✅ | 5s | 9.125 | 0.72 |
| go-v0.42 x go-v0.42 (tcp, noise, yamux) | go-v0.42 | go-v0.42 | tcp | noise | yamux | ✅ | 5s | 5.447 | 0.752 |
| go-v0.42 x go-v0.42 (ws, tls, yamux) | go-v0.42 | go-v0.42 | ws | tls | yamux | ✅ | 4s | 8.908 | 0.612 |
| go-v0.42 x go-v0.42 (ws, noise, yamux) | go-v0.42 | go-v0.42 | ws | noise | yamux | ✅ | 5s | 11.395 | 0.459 |
| go-v0.42 x go-v0.42 (wss, noise, yamux) | go-v0.42 | go-v0.42 | wss | noise | yamux | ✅ | 5s | 19.262 | 0.579 |
| go-v0.42 x go-v0.42 (quic-v1) | go-v0.42 | go-v0.42 | quic-v1 | - | - | ✅ | 5s | 7.122 | 0.236 |
| go-v0.42 x go-v0.42 (webtransport) | go-v0.42 | go-v0.42 | webtransport | - | - | ✅ | 4s | 12.225 | 0.3 |
| go-v0.42 x go-v0.42 (wss, tls, yamux) | go-v0.42 | go-v0.42 | wss | tls | yamux | ✅ | 6s | 11.063 | 0.428 |
| go-v0.42 x go-v0.42 (webrtc-direct) | go-v0.42 | go-v0.42 | webrtc-direct | - | - | ✅ | 5s | 221.94 | 0.536 |
| go-v0.42 x go-v0.43 (tcp, tls, yamux) | go-v0.42 | go-v0.43 | tcp | tls | yamux | ✅ | 4s | 7.247 | 1.626 |
| go-v0.42 x go-v0.43 (tcp, noise, yamux) | go-v0.42 | go-v0.43 | tcp | noise | yamux | ✅ | 5s | 10.804 | 0.605 |
| go-v0.42 x go-v0.43 (ws, tls, yamux) | go-v0.42 | go-v0.43 | ws | tls | yamux | ✅ | 4s | 10.537 | 0.597 |
| go-v0.42 x go-v0.43 (ws, noise, yamux) | go-v0.42 | go-v0.43 | ws | noise | yamux | ✅ | 5s | 10.473 | 0.315 |
| go-v0.42 x go-v0.43 (wss, tls, yamux) | go-v0.42 | go-v0.43 | wss | tls | yamux | ✅ | 5s | 26.58 | 0.889 |
| go-v0.42 x go-v0.43 (quic-v1) | go-v0.42 | go-v0.43 | quic-v1 | - | - | ✅ | 5s | 16.783 | 0.642 |
| go-v0.42 x go-v0.43 (wss, noise, yamux) | go-v0.42 | go-v0.43 | wss | noise | yamux | ✅ | 6s | 22.554 | 1.155 |
| go-v0.42 x go-v0.43 (webtransport) | go-v0.42 | go-v0.43 | webtransport | - | - | ✅ | 5s | 18.429 | 0.498 |
| go-v0.42 x go-v0.43 (webrtc-direct) | go-v0.42 | go-v0.43 | webrtc-direct | - | - | ✅ | 5s | 209.905 | 0.379 |
| go-v0.42 x go-v0.44 (tcp, tls, yamux) | go-v0.42 | go-v0.44 | tcp | tls | yamux | ✅ | 5s | 12.948 | 1.532 |
| go-v0.42 x go-v0.44 (tcp, noise, yamux) | go-v0.42 | go-v0.44 | tcp | noise | yamux | ✅ | 5s | 6.713 | 0.307 |
| go-v0.42 x go-v0.44 (ws, tls, yamux) | go-v0.42 | go-v0.44 | ws | tls | yamux | ✅ | 5s | 7.567 | 0.302 |
| go-v0.42 x go-v0.44 (ws, noise, yamux) | go-v0.42 | go-v0.44 | ws | noise | yamux | ✅ | 6s | 16.118 | 2.082 |
| go-v0.42 x go-v0.44 (wss, noise, yamux) | go-v0.42 | go-v0.44 | wss | noise | yamux | ✅ | 6s | 15.07 | 0.398 |
| go-v0.42 x go-v0.44 (quic-v1) | go-v0.42 | go-v0.44 | quic-v1 | - | - | ✅ | 5s | 47.542 | 0.342 |
| go-v0.42 x go-v0.44 (wss, tls, yamux) | go-v0.42 | go-v0.44 | wss | tls | yamux | ✅ | 6s | 14.749 | 0.321 |
| go-v0.42 x go-v0.44 (webtransport) | go-v0.42 | go-v0.44 | webtransport | - | - | ✅ | 6s | 25.011 | 0.591 |
| go-v0.42 x go-v0.44 (webrtc-direct) | go-v0.42 | go-v0.44 | webrtc-direct | - | - | ✅ | 5s | 10.787 | 0.366 |
| go-v0.42 x go-v0.45 (tcp, tls, yamux) | go-v0.42 | go-v0.45 | tcp | tls | yamux | ✅ | 5s | 9.337 | 3.848 |
| go-v0.42 x go-v0.45 (tcp, noise, yamux) | go-v0.42 | go-v0.45 | tcp | noise | yamux | ✅ | 4s | 8.199 | 0.553 |
| go-v0.42 x go-v0.45 (ws, tls, yamux) | go-v0.42 | go-v0.45 | ws | tls | yamux | ✅ | 3s | 17.893 | 0.78 |
| go-v0.42 x go-v0.45 (ws, noise, yamux) | go-v0.42 | go-v0.45 | ws | noise | yamux | ✅ | 4s | 11.441 | 1.11 |
| go-v0.42 x go-v0.45 (wss, tls, yamux) | go-v0.42 | go-v0.45 | wss | tls | yamux | ✅ | 5s | 36.624 | 0.97 |
| go-v0.42 x go-v0.45 (quic-v1) | go-v0.42 | go-v0.45 | quic-v1 | - | - | ✅ | 5s | 21.85 | 1.521 |
| go-v0.42 x go-v0.45 (wss, noise, yamux) | go-v0.42 | go-v0.45 | wss | noise | yamux | ✅ | 6s | 88.117 | 0.42 |
| go-v0.42 x go-v0.45 (webtransport) | go-v0.42 | go-v0.45 | webtransport | - | - | ✅ | 5s | 9.499 | 0.411 |
| go-v0.42 x go-v0.45 (webrtc-direct) | go-v0.42 | go-v0.45 | webrtc-direct | - | - | ✅ | 6s | 217.385 | 2.607 |
| go-v0.42 x python-v0.4 (tcp, noise, yamux) | go-v0.42 | python-v0.4 | tcp | noise | yamux | ✅ | 5s | 21.354 | 2.509 |
| go-v0.42 x python-v0.4 (ws, noise, yamux) | go-v0.42 | python-v0.4 | ws | noise | yamux | ✅ | 5s | 25.056 | 5.472 |
| go-v0.42 x python-v0.4 (wss, noise, yamux) | go-v0.42 | python-v0.4 | wss | noise | yamux | ✅ | 5s | 38.437 | 4.849 |
| go-v0.42 x python-v0.4 (quic-v1) | go-v0.42 | python-v0.4 | quic-v1 | - | - | ✅ | 6s | 157.679 | 19.205 |
| go-v0.42 x nim-v1.14 (tcp, noise, yamux) | go-v0.42 | nim-v1.14 | tcp | noise | yamux | ✅ | 5s | 202.139 | 43.514 |
| go-v0.42 x nim-v1.14 (ws, noise, yamux) | go-v0.42 | nim-v1.14 | ws | noise | yamux | ✅ | 5s | 255.627 | 43.598 |
| go-v0.42 x js-v1.x (tcp, noise, yamux) | go-v0.42 | js-v1.x | tcp | noise | yamux | ✅ | 19s | 174.294 | 15.688 |
| go-v0.42 x js-v1.x (ws, noise, yamux) | go-v0.42 | js-v1.x | ws | noise | yamux | ✅ | 20s | 160.781 | 17.195 |
| go-v0.42 x js-v2.x (tcp, noise, yamux) | go-v0.42 | js-v2.x | tcp | noise | yamux | ✅ | 21s | 160.533 | 28.628 |
| go-v0.42 x js-v2.x (ws, noise, yamux) | go-v0.42 | js-v2.x | ws | noise | yamux | ✅ | 22s | 175.69 | 14.9 |
| go-v0.42 x jvm-v1.2 (tcp, noise, yamux) | go-v0.42 | jvm-v1.2 | tcp | noise | yamux | ✅ | 11s | 1051.677 | 23.164 |
| go-v0.42 x js-v3.x (tcp, noise, yamux) | go-v0.42 | js-v3.x | tcp | noise | yamux | ✅ | 21s | 142.908 | 25.016 |
| go-v0.42 x js-v3.x (ws, noise, yamux) | go-v0.42 | js-v3.x | ws | noise | yamux | ✅ | 21s | 180.332 | 13.945 |
| go-v0.42 x jvm-v1.2 (tcp, tls, yamux) | go-v0.42 | jvm-v1.2 | tcp | tls | yamux | ✅ | 13s | 3474.635 | 8.201 |
| go-v0.42 x c-v0.0.1 (tcp, noise, yamux) | go-v0.42 | c-v0.0.1 | tcp | noise | yamux | ✅ | 6s | 129.368 | 55.633 |
| go-v0.42 x c-v0.0.1 (quic-v1) | go-v0.42 | c-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 72.627 | 7.162 |
| go-v0.42 x jvm-v1.2 (ws, noise, yamux) | go-v0.42 | jvm-v1.2 | ws | noise | yamux | ✅ | 9s | 1330.188 | 19.66 |
| go-v0.42 x dotnet-v1.0 (tcp, noise, yamux) | go-v0.42 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 6s | 499.924 | 46.018 |
| go-v0.42 x zig-v0.0.1 (quic-v1) | go-v0.42 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 6s | - | - |
| go-v0.42 x eth-p2p-z-v0.0.1 (quic-v1) | go-v0.42 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 15.504 | 0.283 |
| go-v0.42 x jvm-v1.2 (ws, tls, yamux) | go-v0.42 | jvm-v1.2 | ws | tls | yamux | ✅ | 11s | 3274.58 | 11.405 |
| go-v0.42 x jvm-v1.2 (quic-v1) | go-v0.42 | jvm-v1.2 | quic-v1 | - | - | ✅ | 11s | 544.255 | 11.501 |
| go-v0.43 x rust-v0.53 (tcp, tls, yamux) | go-v0.43 | rust-v0.53 | tcp | tls | yamux | ✅ | 4s | 107.016 | 48.111 |
| go-v0.43 x rust-v0.53 (tcp, noise, yamux) | go-v0.43 | rust-v0.53 | tcp | noise | yamux | ✅ | 4s | 91.868 | 45.519 |
| go-v0.43 x rust-v0.53 (ws, tls, yamux) | go-v0.43 | rust-v0.53 | ws | tls | yamux | ✅ | 4s | 226.633 | 46.34 |
| go-v0.43 x rust-v0.53 (ws, noise, yamux) | go-v0.43 | rust-v0.53 | ws | noise | yamux | ✅ | 4s | 231.936 | 47.801 |
| go-v0.43 x rust-v0.53 (quic-v1) | go-v0.43 | rust-v0.53 | quic-v1 | - | - | ✅ | 5s | 10.31 | 2.049 |
| go-v0.43 x rust-v0.53 (webrtc-direct) | go-v0.43 | rust-v0.53 | webrtc-direct | - | - | ✅ | 5s | 421.289 | 0.568 |
| go-v0.43 x rust-v0.54 (tcp, tls, yamux) | go-v0.43 | rust-v0.54 | tcp | tls | yamux | ✅ | 5s | 135.588 | 43.389 |
| go-v0.43 x rust-v0.54 (tcp, noise, yamux) | go-v0.43 | rust-v0.54 | tcp | noise | yamux | ✅ | 5s | 97.518 | 45.932 |
| go-v0.43 x rust-v0.54 (ws, tls, yamux) | go-v0.43 | rust-v0.54 | ws | tls | yamux | ✅ | 4s | 178.592 | 41.847 |
| go-v0.43 x rust-v0.54 (ws, noise, yamux) | go-v0.43 | rust-v0.54 | ws | noise | yamux | ✅ | 5s | 183.222 | 47.303 |
| go-v0.43 x rust-v0.54 (quic-v1) | go-v0.43 | rust-v0.54 | quic-v1 | - | - | ✅ | 4s | 14.167 | 2.647 |
| go-v0.43 x rust-v0.54 (webrtc-direct) | go-v0.43 | rust-v0.54 | webrtc-direct | - | - | ✅ | 5s | 415.759 | 0.867 |
| go-v0.43 x rust-v0.55 (tcp, tls, yamux) | go-v0.43 | rust-v0.55 | tcp | tls | yamux | ✅ | 4s | 9.723 | 0.58 |
| go-v0.43 x rust-v0.55 (tcp, noise, yamux) | go-v0.43 | rust-v0.55 | tcp | noise | yamux | ✅ | 5s | 4.97 | 0.316 |
| go-v0.43 x rust-v0.55 (ws, tls, yamux) | go-v0.43 | rust-v0.55 | ws | tls | yamux | ✅ | 4s | 9.265 | 0.643 |
| go-v0.43 x rust-v0.55 (ws, noise, yamux) | go-v0.43 | rust-v0.55 | ws | noise | yamux | ✅ | 5s | 5.998 | 0.483 |
| go-v0.43 x rust-v0.55 (quic-v1) | go-v0.43 | rust-v0.55 | quic-v1 | - | - | ✅ | 4s | 8.877 | 0.395 |
| go-v0.43 x rust-v0.55 (webrtc-direct) | go-v0.43 | rust-v0.55 | webrtc-direct | - | - | ✅ | 5s | 234.165 | 0.678 |
| go-v0.43 x rust-v0.56 (tcp, noise, yamux) | go-v0.43 | rust-v0.56 | tcp | noise | yamux | ✅ | 4s | 9.504 | 0.295 |
| go-v0.43 x rust-v0.56 (tcp, tls, yamux) | go-v0.43 | rust-v0.56 | tcp | tls | yamux | ✅ | 5s | 12.696 | 0.766 |
| go-v0.43 x rust-v0.56 (ws, noise, yamux) | go-v0.43 | rust-v0.56 | ws | noise | yamux | ✅ | 3s | 10.971 | 0.591 |
| go-v0.43 x rust-v0.56 (ws, tls, yamux) | go-v0.43 | rust-v0.56 | ws | tls | yamux | ✅ | 5s | 9.171 | 0.726 |
| go-v0.43 x rust-v0.56 (quic-v1) | go-v0.43 | rust-v0.56 | quic-v1 | - | - | ✅ | 5s | 6.801 | 0.285 |
| go-v0.43 x go-v0.38 (tcp, tls, yamux) | go-v0.43 | go-v0.38 | tcp | tls | yamux | ✅ | 4s | 7.104 | 0.22 |
| go-v0.43 x go-v0.38 (tcp, noise, yamux) | go-v0.43 | go-v0.38 | tcp | noise | yamux | ✅ | 4s | 8.357 | 1.815 |
| go-v0.43 x go-v0.38 (ws, tls, yamux) | go-v0.43 | go-v0.38 | ws | tls | yamux | ✅ | 4s | 7.622 | 0.5 |
| go-v0.43 x go-v0.38 (ws, noise, yamux) | go-v0.43 | go-v0.38 | ws | noise | yamux | ✅ | 4s | 14.498 | 1.023 |
| go-v0.43 x go-v0.38 (wss, tls, yamux) | go-v0.43 | go-v0.38 | wss | tls | yamux | ✅ | 5s | 13.248 | 0.384 |
| go-v0.43 x go-v0.38 (quic-v1) | go-v0.43 | go-v0.38 | quic-v1 | - | - | ✅ | 4s | 18.23 | 0.798 |
| go-v0.43 x go-v0.38 (wss, noise, yamux) | go-v0.43 | go-v0.38 | wss | noise | yamux | ✅ | 5s | 18.147 | 2.129 |
| go-v0.43 x rust-v0.56 (webrtc-direct) | go-v0.43 | rust-v0.56 | webrtc-direct | - | - | ❌ | 10s | - | - |
| go-v0.43 x go-v0.38 (webtransport) | go-v0.43 | go-v0.38 | webtransport | - | - | ✅ | 5s | 13.678 | 0.376 |
| go-v0.43 x go-v0.38 (webrtc-direct) | go-v0.43 | go-v0.38 | webrtc-direct | - | - | ✅ | 5s | 219.29 | 0.492 |
| go-v0.43 x go-v0.39 (tcp, tls, yamux) | go-v0.43 | go-v0.39 | tcp | tls | yamux | ✅ | 4s | 7.679 | 0.638 |
| go-v0.43 x go-v0.39 (tcp, noise, yamux) | go-v0.43 | go-v0.39 | tcp | noise | yamux | ✅ | 5s | 10.223 | 0.797 |
| go-v0.43 x go-v0.39 (ws, tls, yamux) | go-v0.43 | go-v0.39 | ws | tls | yamux | ✅ | 5s | 21.97 | 1.321 |
| go-v0.43 x go-v0.39 (ws, noise, yamux) | go-v0.43 | go-v0.39 | ws | noise | yamux | ✅ | 5s | 7.305 | 0.52 |
| go-v0.43 x go-v0.39 (wss, tls, yamux) | go-v0.43 | go-v0.39 | wss | tls | yamux | ✅ | 5s | 16.493 | 0.49 |
| go-v0.43 x go-v0.39 (wss, noise, yamux) | go-v0.43 | go-v0.39 | wss | noise | yamux | ✅ | 5s | 14.929 | 2.016 |
| go-v0.43 x go-v0.39 (quic-v1) | go-v0.43 | go-v0.39 | quic-v1 | - | - | ✅ | 5s | 96.235 | 0.529 |
| go-v0.43 x go-v0.39 (webtransport) | go-v0.43 | go-v0.39 | webtransport | - | - | ✅ | 4s | 10.216 | 0.567 |
| go-v0.43 x go-v0.39 (webrtc-direct) | go-v0.43 | go-v0.39 | webrtc-direct | - | - | ✅ | 5s | 221.182 | 1.066 |
| go-v0.43 x go-v0.40 (tcp, tls, yamux) | go-v0.43 | go-v0.40 | tcp | tls | yamux | ✅ | 4s | 13.379 | 3.556 |
| go-v0.43 x go-v0.40 (tcp, noise, yamux) | go-v0.43 | go-v0.40 | tcp | noise | yamux | ✅ | 4s | 11.353 | 2.666 |
| go-v0.43 x go-v0.40 (ws, tls, yamux) | go-v0.43 | go-v0.40 | ws | tls | yamux | ✅ | 6s | 24.366 | 2.113 |
| go-v0.43 x go-v0.40 (ws, noise, yamux) | go-v0.43 | go-v0.40 | ws | noise | yamux | ✅ | 5s | 13.38 | 1.226 |
| go-v0.43 x go-v0.40 (wss, noise, yamux) | go-v0.43 | go-v0.40 | wss | noise | yamux | ✅ | 5s | 22.134 | 1.254 |
| go-v0.43 x go-v0.40 (wss, tls, yamux) | go-v0.43 | go-v0.40 | wss | tls | yamux | ✅ | 6s | 8.466 | 0.512 |
| go-v0.43 x go-v0.40 (quic-v1) | go-v0.43 | go-v0.40 | quic-v1 | - | - | ✅ | 6s | 7.53 | 0.263 |
| go-v0.43 x go-v0.40 (webtransport) | go-v0.43 | go-v0.40 | webtransport | - | - | ✅ | 5s | 9.226 | 0.686 |
| go-v0.43 x go-v0.40 (webrtc-direct) | go-v0.43 | go-v0.40 | webrtc-direct | - | - | ✅ | 5s | 219.244 | 0.563 |
| go-v0.43 x go-v0.41 (tcp, tls, yamux) | go-v0.43 | go-v0.41 | tcp | tls | yamux | ✅ | 4s | 9.199 | 1.507 |
| go-v0.43 x go-v0.41 (tcp, noise, yamux) | go-v0.43 | go-v0.41 | tcp | noise | yamux | ✅ | 5s | 5.921 | 0.548 |
| go-v0.43 x go-v0.41 (ws, tls, yamux) | go-v0.43 | go-v0.41 | ws | tls | yamux | ✅ | 4s | 11.382 | 1.039 |
| go-v0.43 x go-v0.41 (ws, noise, yamux) | go-v0.43 | go-v0.41 | ws | noise | yamux | ✅ | 5s | 165.439 | 0.562 |
| go-v0.43 x go-v0.41 (wss, tls, yamux) | go-v0.43 | go-v0.41 | wss | tls | yamux | ✅ | 5s | 18.054 | 0.631 |
| go-v0.43 x go-v0.41 (wss, noise, yamux) | go-v0.43 | go-v0.41 | wss | noise | yamux | ✅ | 6s | 23.051 | 0.527 |
| go-v0.43 x go-v0.41 (quic-v1) | go-v0.43 | go-v0.41 | quic-v1 | - | - | ✅ | 5s | 25.247 | 0.397 |
| go-v0.43 x go-v0.41 (webtransport) | go-v0.43 | go-v0.41 | webtransport | - | - | ✅ | 4s | 11.371 | 0.356 |
| go-v0.43 x go-v0.41 (webrtc-direct) | go-v0.43 | go-v0.41 | webrtc-direct | - | - | ✅ | 5s | 213.324 | 0.492 |
| go-v0.43 x go-v0.42 (tcp, tls, yamux) | go-v0.43 | go-v0.42 | tcp | tls | yamux | ✅ | 5s | 8.097 | 1.785 |
| go-v0.43 x go-v0.42 (ws, tls, yamux) | go-v0.43 | go-v0.42 | ws | tls | yamux | ✅ | 4s | 15.916 | 2.152 |
| go-v0.43 x go-v0.42 (tcp, noise, yamux) | go-v0.43 | go-v0.42 | tcp | noise | yamux | ✅ | 5s | 7.953 | 0.488 |
| go-v0.43 x go-v0.42 (ws, noise, yamux) | go-v0.43 | go-v0.42 | ws | noise | yamux | ✅ | 5s | 8.472 | 0.938 |
| go-v0.43 x go-v0.42 (quic-v1) | go-v0.43 | go-v0.42 | quic-v1 | - | - | ✅ | 4s | 18.814 | 4.948 |
| go-v0.43 x go-v0.42 (wss, tls, yamux) | go-v0.43 | go-v0.42 | wss | tls | yamux | ✅ | 6s | 46.606 | 0.653 |
| go-v0.43 x go-v0.42 (wss, noise, yamux) | go-v0.43 | go-v0.42 | wss | noise | yamux | ✅ | 5s | 20.371 | 1.326 |
| go-v0.43 x go-v0.42 (webtransport) | go-v0.43 | go-v0.42 | webtransport | - | - | ✅ | 4s | 11.483 | 0.319 |
| go-v0.43 x go-v0.42 (webrtc-direct) | go-v0.43 | go-v0.42 | webrtc-direct | - | - | ✅ | 4s | 209.104 | 0.359 |
| go-v0.43 x go-v0.43 (tcp, noise, yamux) | go-v0.43 | go-v0.43 | tcp | noise | yamux | ✅ | 4s | 5.521 | 0.282 |
| go-v0.43 x go-v0.43 (tcp, tls, yamux) | go-v0.43 | go-v0.43 | tcp | tls | yamux | ✅ | 4s | 8.125 | 0.626 |
| go-v0.43 x go-v0.43 (ws, tls, yamux) | go-v0.43 | go-v0.43 | ws | tls | yamux | ✅ | 4s | 8.197 | 0.716 |
| go-v0.43 x go-v0.43 (ws, noise, yamux) | go-v0.43 | go-v0.43 | ws | noise | yamux | ✅ | 4s | 12.22 | 0.963 |
| go-v0.43 x go-v0.43 (wss, tls, yamux) | go-v0.43 | go-v0.43 | wss | tls | yamux | ✅ | 5s | 75.045 | 0.46 |
| go-v0.43 x go-v0.43 (quic-v1) | go-v0.43 | go-v0.43 | quic-v1 | - | - | ✅ | 5s | 18.255 | 1.482 |
| go-v0.43 x go-v0.43 (wss, noise, yamux) | go-v0.43 | go-v0.43 | wss | noise | yamux | ✅ | 6s | 12.478 | 0.656 |
| go-v0.43 x go-v0.43 (webtransport) | go-v0.43 | go-v0.43 | webtransport | - | - | ✅ | 5s | 9.668 | 0.454 |
| go-v0.43 x go-v0.43 (webrtc-direct) | go-v0.43 | go-v0.43 | webrtc-direct | - | - | ✅ | 5s | 218.895 | 0.601 |
| go-v0.43 x go-v0.44 (tcp, tls, yamux) | go-v0.43 | go-v0.44 | tcp | tls | yamux | ✅ | 6s | 7.675 | 0.349 |
| go-v0.43 x go-v0.44 (tcp, noise, yamux) | go-v0.43 | go-v0.44 | tcp | noise | yamux | ✅ | 5s | 5.871 | 0.285 |
| go-v0.43 x go-v0.44 (ws, tls, yamux) | go-v0.43 | go-v0.44 | ws | tls | yamux | ✅ | 4s | 8.469 | 0.439 |
| go-v0.43 x go-v0.44 (ws, noise, yamux) | go-v0.43 | go-v0.44 | ws | noise | yamux | ✅ | 4s | 6.708 | 0.357 |
| go-v0.43 x go-v0.44 (quic-v1) | go-v0.43 | go-v0.44 | quic-v1 | - | - | ✅ | 4s | 14.804 | 0.497 |
| go-v0.43 x go-v0.44 (wss, tls, yamux) | go-v0.43 | go-v0.44 | wss | tls | yamux | ✅ | 6s | 18.671 | 0.49 |
| go-v0.43 x go-v0.44 (wss, noise, yamux) | go-v0.43 | go-v0.44 | wss | noise | yamux | ✅ | 5s | 16.438 | 1.174 |
| go-v0.43 x go-v0.44 (webtransport) | go-v0.43 | go-v0.44 | webtransport | - | - | ✅ | 5s | 13.924 | 0.888 |
| go-v0.43 x go-v0.44 (webrtc-direct) | go-v0.43 | go-v0.44 | webrtc-direct | - | - | ✅ | 5s | 216.15 | 0.88 |
| go-v0.43 x go-v0.45 (tcp, tls, yamux) | go-v0.43 | go-v0.45 | tcp | tls | yamux | ✅ | 5s | 13.399 | 2.403 |
| go-v0.43 x go-v0.45 (tcp, noise, yamux) | go-v0.43 | go-v0.45 | tcp | noise | yamux | ✅ | 5s | 8.636 | 0.389 |
| go-v0.43 x go-v0.45 (ws, tls, yamux) | go-v0.43 | go-v0.45 | ws | tls | yamux | ✅ | 5s | 8.492 | 0.985 |
| go-v0.43 x go-v0.45 (ws, noise, yamux) | go-v0.43 | go-v0.45 | ws | noise | yamux | ✅ | 4s | 16.157 | 1.852 |
| go-v0.43 x go-v0.45 (quic-v1) | go-v0.43 | go-v0.45 | quic-v1 | - | - | ✅ | 4s | 14.592 | 1.161 |
| go-v0.43 x go-v0.45 (wss, noise, yamux) | go-v0.43 | go-v0.45 | wss | noise | yamux | ✅ | 5s | 20.029 | 0.882 |
| go-v0.43 x go-v0.45 (wss, tls, yamux) | go-v0.43 | go-v0.45 | wss | tls | yamux | ✅ | 6s | 19.94 | 1.143 |
| go-v0.43 x go-v0.45 (webtransport) | go-v0.43 | go-v0.45 | webtransport | - | - | ✅ | 4s | 18.981 | 0.665 |
| go-v0.43 x go-v0.45 (webrtc-direct) | go-v0.43 | go-v0.45 | webrtc-direct | - | - | ✅ | 5s | 8.988 | 0.354 |
| go-v0.43 x python-v0.4 (tcp, noise, yamux) | go-v0.43 | python-v0.4 | tcp | noise | yamux | ✅ | 5s | 37.829 | 5.835 |
| go-v0.43 x python-v0.4 (ws, noise, yamux) | go-v0.43 | python-v0.4 | ws | noise | yamux | ✅ | 5s | 37.607 | 5.198 |
| go-v0.43 x python-v0.4 (wss, noise, yamux) | go-v0.43 | python-v0.4 | wss | noise | yamux | ✅ | 6s | 76.049 | 7.531 |
| go-v0.43 x python-v0.4 (quic-v1) | go-v0.43 | python-v0.4 | quic-v1 | - | - | ✅ | 6s | 168.212 | 20.503 |
| go-v0.43 x nim-v1.14 (tcp, noise, yamux) | go-v0.43 | nim-v1.14 | tcp | noise | yamux | ✅ | 5s | 209.459 | 44.258 |
| go-v0.43 x nim-v1.14 (ws, noise, yamux) | go-v0.43 | nim-v1.14 | ws | noise | yamux | ✅ | 5s | 250.599 | 43.135 |
| go-v0.43 x js-v1.x (tcp, noise, yamux) | go-v0.43 | js-v1.x | tcp | noise | yamux | ✅ | 18s | 159.938 | 17.619 |
| go-v0.43 x js-v1.x (ws, noise, yamux) | go-v0.43 | js-v1.x | ws | noise | yamux | ✅ | 19s | 164.61 | 19.927 |
| go-v0.43 x js-v2.x (tcp, noise, yamux) | go-v0.43 | js-v2.x | tcp | noise | yamux | ✅ | 22s | 165.034 | 27.95 |
| go-v0.43 x jvm-v1.2 (tcp, noise, yamux) | go-v0.43 | jvm-v1.2 | tcp | noise | yamux | ✅ | 11s | 901.303 | 23.403 |
| go-v0.43 x js-v2.x (ws, noise, yamux) | go-v0.43 | js-v2.x | ws | noise | yamux | ✅ | 22s | 188.419 | 31.193 |
| go-v0.43 x js-v3.x (tcp, noise, yamux) | go-v0.43 | js-v3.x | tcp | noise | yamux | ✅ | 22s | 141.172 | 22.736 |
| go-v0.43 x jvm-v1.2 (tcp, tls, yamux) | go-v0.43 | jvm-v1.2 | tcp | tls | yamux | ✅ | 13s | 3497.465 | 6.762 |
| go-v0.43 x js-v3.x (ws, noise, yamux) | go-v0.43 | js-v3.x | ws | noise | yamux | ✅ | 22s | 118.305 | 20.497 |
| go-v0.43 x c-v0.0.1 (tcp, noise, yamux) | go-v0.43 | c-v0.0.1 | tcp | noise | yamux | ✅ | 5s | 131.236 | 55.311 |
| go-v0.43 x jvm-v1.2 (ws, tls, yamux) | go-v0.43 | jvm-v1.2 | ws | tls | yamux | ✅ | 11s | 3085.822 | 18.333 |
| go-v0.43 x jvm-v1.2 (ws, noise, yamux) | go-v0.43 | jvm-v1.2 | ws | noise | yamux | ✅ | 10s | 1496.953 | 75.166 |
| go-v0.43 x c-v0.0.1 (quic-v1) | go-v0.43 | c-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 21.31 | 1.429 |
| go-v0.43 x dotnet-v1.0 (tcp, noise, yamux) | go-v0.43 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 6s | 450.982 | 45.956 |
| go-v0.43 x zig-v0.0.1 (quic-v1) | go-v0.43 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 6s | - | - |
| go-v0.43 x eth-p2p-z-v0.0.1 (quic-v1) | go-v0.43 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 5s | 11.251 | 0.485 |
| go-v0.43 x jvm-v1.2 (quic-v1) | go-v0.43 | jvm-v1.2 | quic-v1 | - | - | ✅ | 11s | 743.793 | 9.387 |
| go-v0.44 x rust-v0.53 (tcp, tls, yamux) | go-v0.44 | rust-v0.53 | tcp | tls | yamux | ✅ | 4s | 94.498 | 41.169 |
| go-v0.44 x rust-v0.53 (tcp, noise, yamux) | go-v0.44 | rust-v0.53 | tcp | noise | yamux | ✅ | 4s | 92.577 | 41.634 |
| go-v0.44 x rust-v0.53 (ws, tls, yamux) | go-v0.44 | rust-v0.53 | ws | tls | yamux | ✅ | 4s | 228.045 | 47.619 |
| go-v0.44 x rust-v0.53 (ws, noise, yamux) | go-v0.44 | rust-v0.53 | ws | noise | yamux | ✅ | 4s | 188.996 | 44.266 |
| go-v0.44 x rust-v0.53 (quic-v1) | go-v0.44 | rust-v0.53 | quic-v1 | - | - | ✅ | 4s | 16.312 | 4.467 |
| go-v0.44 x rust-v0.54 (tcp, tls, yamux) | go-v0.44 | rust-v0.54 | tcp | tls | yamux | ✅ | 4s | 142.065 | 43.718 |
| go-v0.44 x rust-v0.53 (webrtc-direct) | go-v0.44 | rust-v0.53 | webrtc-direct | - | - | ✅ | 4s | 213.268 | 0.693 |
| go-v0.44 x rust-v0.54 (tcp, noise, yamux) | go-v0.44 | rust-v0.54 | tcp | noise | yamux | ✅ | 5s | 93.444 | 42.445 |
| go-v0.44 x rust-v0.54 (ws, tls, yamux) | go-v0.44 | rust-v0.54 | ws | tls | yamux | ✅ | 5s | 228.779 | 43.398 |
| go-v0.44 x rust-v0.54 (ws, noise, yamux) | go-v0.44 | rust-v0.54 | ws | noise | yamux | ✅ | 5s | 185.029 | 41.909 |
| go-v0.44 x rust-v0.54 (quic-v1) | go-v0.44 | rust-v0.54 | quic-v1 | - | - | ✅ | 4s | 7.699 | 0.285 |
| go-v0.44 x rust-v0.54 (webrtc-direct) | go-v0.44 | rust-v0.54 | webrtc-direct | - | - | ✅ | 5s | 409.88 | 0.302 |
| go-v0.44 x rust-v0.55 (tcp, tls, yamux) | go-v0.44 | rust-v0.55 | tcp | tls | yamux | ✅ | 4s | 5.736 | 0.655 |
| go-v0.44 x rust-v0.55 (tcp, noise, yamux) | go-v0.44 | rust-v0.55 | tcp | noise | yamux | ✅ | 5s | 8.315 | 1.88 |
| go-v0.44 x rust-v0.55 (ws, tls, yamux) | go-v0.44 | rust-v0.55 | ws | tls | yamux | ✅ | 5s | 47.108 | 0.395 |
| go-v0.44 x rust-v0.55 (ws, noise, yamux) | go-v0.44 | rust-v0.55 | ws | noise | yamux | ✅ | 4s | 6.097 | 0.354 |
| go-v0.44 x rust-v0.55 (quic-v1) | go-v0.44 | rust-v0.55 | quic-v1 | - | - | ✅ | 4s | 6.012 | 0.326 |
| go-v0.44 x rust-v0.55 (webrtc-direct) | go-v0.44 | rust-v0.55 | webrtc-direct | - | - | ✅ | 6s | 411.49 | 0.428 |
| go-v0.44 x rust-v0.56 (tcp, tls, yamux) | go-v0.44 | rust-v0.56 | tcp | tls | yamux | ✅ | 5s | 9.481 | 1.57 |
| go-v0.44 x rust-v0.56 (tcp, noise, yamux) | go-v0.44 | rust-v0.56 | tcp | noise | yamux | ✅ | 4s | 9.358 | 1.85 |
| go-v0.44 x rust-v0.56 (ws, tls, yamux) | go-v0.44 | rust-v0.56 | ws | tls | yamux | ✅ | 5s | 10.679 | 0.387 |
| go-v0.44 x rust-v0.56 (ws, noise, yamux) | go-v0.44 | rust-v0.56 | ws | noise | yamux | ✅ | 5s | 10.38 | 0.457 |
| go-v0.44 x rust-v0.56 (quic-v1) | go-v0.44 | rust-v0.56 | quic-v1 | - | - | ✅ | 4s | 14.221 | 0.503 |
| go-v0.44 x go-v0.38 (tcp, tls, yamux) | go-v0.44 | go-v0.38 | tcp | tls | yamux | ✅ | 4s | 12.577 | 5.84 |
| go-v0.44 x go-v0.38 (tcp, noise, yamux) | go-v0.44 | go-v0.38 | tcp | noise | yamux | ✅ | 4s | 17.767 | 2.068 |
| go-v0.44 x go-v0.38 (ws, tls, yamux) | go-v0.44 | go-v0.38 | ws | tls | yamux | ✅ | 3s | 8.605 | 0.508 |
| go-v0.44 x go-v0.38 (ws, noise, yamux) | go-v0.44 | go-v0.38 | ws | noise | yamux | ✅ | 5s | 11.305 | 0.471 |
| go-v0.44 x go-v0.38 (wss, tls, yamux) | go-v0.44 | go-v0.38 | wss | tls | yamux | ✅ | 5s | 16.935 | 0.923 |
| go-v0.44 x go-v0.38 (wss, noise, yamux) | go-v0.44 | go-v0.38 | wss | noise | yamux | ✅ | 5s | 85.602 | 0.394 |
| go-v0.44 x go-v0.38 (quic-v1) | go-v0.44 | go-v0.38 | quic-v1 | - | - | ✅ | 5s | 6.763 | 1.218 |
| go-v0.44 x go-v0.38 (webtransport) | go-v0.44 | go-v0.38 | webtransport | - | - | ✅ | 5s | 9.915 | 0.558 |
| go-v0.44 x rust-v0.56 (webrtc-direct) | go-v0.44 | rust-v0.56 | webrtc-direct | - | - | ❌ | 10s | - | - |
| go-v0.44 x go-v0.39 (tcp, tls, yamux) | go-v0.44 | go-v0.39 | tcp | tls | yamux | ✅ | 5s | 10.49 | 0.463 |
| go-v0.44 x go-v0.38 (webrtc-direct) | go-v0.44 | go-v0.38 | webrtc-direct | - | - | ✅ | 5s | 47.004 | 1.163 |
| go-v0.44 x go-v0.39 (tcp, noise, yamux) | go-v0.44 | go-v0.39 | tcp | noise | yamux | ✅ | 4s | 20.86 | 1.171 |
| go-v0.44 x go-v0.39 (ws, tls, yamux) | go-v0.44 | go-v0.39 | ws | tls | yamux | ✅ | 4s | 7.794 | 0.253 |
| go-v0.44 x go-v0.39 (ws, noise, yamux) | go-v0.44 | go-v0.39 | ws | noise | yamux | ✅ | 4s | 20.876 | 3.458 |
| go-v0.44 x go-v0.39 (quic-v1) | go-v0.44 | go-v0.39 | quic-v1 | - | - | ✅ | 4s | 22.66 | 2.362 |
| go-v0.44 x go-v0.39 (wss, tls, yamux) | go-v0.44 | go-v0.39 | wss | tls | yamux | ✅ | 6s | 17.701 | 0.802 |
| go-v0.44 x go-v0.39 (wss, noise, yamux) | go-v0.44 | go-v0.39 | wss | noise | yamux | ✅ | 5s | 22.307 | 1.255 |
| go-v0.44 x go-v0.39 (webtransport) | go-v0.44 | go-v0.39 | webtransport | - | - | ✅ | 5s | 19.463 | 0.689 |
| go-v0.44 x go-v0.39 (webrtc-direct) | go-v0.44 | go-v0.39 | webrtc-direct | - | - | ✅ | 5s | 210.066 | 0.274 |
| go-v0.44 x go-v0.40 (tcp, tls, yamux) | go-v0.44 | go-v0.40 | tcp | tls | yamux | ✅ | 5s | 6.968 | 0.845 |
| go-v0.44 x go-v0.40 (tcp, noise, yamux) | go-v0.44 | go-v0.40 | tcp | noise | yamux | ✅ | 5s | 9.993 | 0.536 |
| go-v0.44 x go-v0.40 (ws, tls, yamux) | go-v0.44 | go-v0.40 | ws | tls | yamux | ✅ | 4s | 13.163 | 1.487 |
| go-v0.44 x go-v0.40 (ws, noise, yamux) | go-v0.44 | go-v0.40 | ws | noise | yamux | ✅ | 5s | 6.347 | 0.392 |
| go-v0.44 x go-v0.40 (webtransport) | go-v0.44 | go-v0.40 | webtransport | - | - | ✅ | 4s | 22.98 | 0.832 |
| go-v0.44 x go-v0.40 (wss, tls, yamux) | go-v0.44 | go-v0.40 | wss | tls | yamux | ✅ | 6s | 19.2 | 1.12 |
| go-v0.44 x go-v0.40 (quic-v1) | go-v0.44 | go-v0.40 | quic-v1 | - | - | ✅ | 5s | 13.388 | 1.225 |
| go-v0.44 x go-v0.40 (wss, noise, yamux) | go-v0.44 | go-v0.40 | wss | noise | yamux | ✅ | 6s | 16.272 | 0.464 |
| go-v0.44 x go-v0.40 (webrtc-direct) | go-v0.44 | go-v0.40 | webrtc-direct | - | - | ✅ | 5s | 212.166 | 0.474 |
| go-v0.44 x go-v0.41 (tcp, tls, yamux) | go-v0.44 | go-v0.41 | tcp | tls | yamux | ✅ | 5s | 8.195 | 0.696 |
| go-v0.44 x go-v0.41 (tcp, noise, yamux) | go-v0.44 | go-v0.41 | tcp | noise | yamux | ✅ | 5s | 11.373 | 1.578 |
| go-v0.44 x go-v0.41 (ws, tls, yamux) | go-v0.44 | go-v0.41 | ws | tls | yamux | ✅ | 5s | 10.674 | 0.542 |
| go-v0.44 x go-v0.41 (ws, noise, yamux) | go-v0.44 | go-v0.41 | ws | noise | yamux | ✅ | 4s | 22.159 | 3.222 |
| go-v0.44 x go-v0.41 (quic-v1) | go-v0.44 | go-v0.41 | quic-v1 | - | - | ✅ | 5s | 12.015 | 0.318 |
| go-v0.44 x go-v0.41 (wss, tls, yamux) | go-v0.44 | go-v0.41 | wss | tls | yamux | ✅ | 6s | 15.015 | 0.338 |
| go-v0.44 x go-v0.41 (webtransport) | go-v0.44 | go-v0.41 | webtransport | - | - | ✅ | 6s | 53.488 | 4.668 |
| go-v0.44 x go-v0.41 (wss, noise, yamux) | go-v0.44 | go-v0.41 | wss | noise | yamux | ✅ | 6s | 24.946 | 2.018 |
| go-v0.44 x go-v0.41 (webrtc-direct) | go-v0.44 | go-v0.41 | webrtc-direct | - | - | ✅ | 6s | 9.753 | 0.252 |
| go-v0.44 x go-v0.42 (tcp, tls, yamux) | go-v0.44 | go-v0.42 | tcp | tls | yamux | ✅ | 5s | 4.961 | 0.428 |
| go-v0.44 x go-v0.42 (tcp, noise, yamux) | go-v0.44 | go-v0.42 | tcp | noise | yamux | ✅ | 6s | 7.854 | 1.356 |
| go-v0.44 x go-v0.42 (ws, tls, yamux) | go-v0.44 | go-v0.42 | ws | tls | yamux | ✅ | 4s | 13.657 | 0.425 |
| go-v0.44 x go-v0.42 (ws, noise, yamux) | go-v0.44 | go-v0.42 | ws | noise | yamux | ✅ | 4s | 9.578 | 0.555 |
| go-v0.44 x go-v0.42 (wss, noise, yamux) | go-v0.44 | go-v0.42 | wss | noise | yamux | ✅ | 5s | 21.438 | 1.292 |
| go-v0.44 x go-v0.42 (quic-v1) | go-v0.44 | go-v0.42 | quic-v1 | - | - | ✅ | 5s | 10.779 | 0.63 |
| go-v0.44 x go-v0.42 (wss, tls, yamux) | go-v0.44 | go-v0.42 | wss | tls | yamux | ✅ | 6s | 17.102 | 0.702 |
| go-v0.44 x go-v0.42 (webtransport) | go-v0.44 | go-v0.42 | webtransport | - | - | ✅ | 5s | 11.868 | 0.372 |
| go-v0.44 x go-v0.43 (tcp, tls, yamux) | go-v0.44 | go-v0.43 | tcp | tls | yamux | ✅ | 5s | 6.117 | 0.199 |
| go-v0.44 x go-v0.42 (webrtc-direct) | go-v0.44 | go-v0.42 | webrtc-direct | - | - | ✅ | 5s | 305.127 | 0.29 |
| go-v0.44 x go-v0.43 (tcp, noise, yamux) | go-v0.44 | go-v0.43 | tcp | noise | yamux | ✅ | 5s | 9.023 | 1.492 |
| go-v0.44 x go-v0.43 (ws, tls, yamux) | go-v0.44 | go-v0.43 | ws | tls | yamux | ✅ | 5s | 6.692 | 1.678 |
| go-v0.44 x go-v0.43 (ws, noise, yamux) | go-v0.44 | go-v0.43 | ws | noise | yamux | ✅ | 4s | 17.413 | 4.4 |
| go-v0.44 x go-v0.43 (wss, tls, yamux) | go-v0.44 | go-v0.43 | wss | tls | yamux | ✅ | 5s | 23.502 | 1.539 |
| go-v0.44 x go-v0.43 (quic-v1) | go-v0.44 | go-v0.43 | quic-v1 | - | - | ✅ | 4s | 12.674 | 0.884 |
| go-v0.44 x go-v0.43 (webtransport) | go-v0.44 | go-v0.43 | webtransport | - | - | ✅ | 5s | 15.192 | 0.773 |
| go-v0.44 x go-v0.43 (wss, noise, yamux) | go-v0.44 | go-v0.43 | wss | noise | yamux | ✅ | 6s | 15.244 | 0.745 |
| go-v0.44 x go-v0.43 (webrtc-direct) | go-v0.44 | go-v0.43 | webrtc-direct | - | - | ✅ | 5s | 211.303 | 0.334 |
| go-v0.44 x go-v0.44 (tcp, tls, yamux) | go-v0.44 | go-v0.44 | tcp | tls | yamux | ✅ | 5s | 15.31 | 3.442 |
| go-v0.44 x go-v0.44 (tcp, noise, yamux) | go-v0.44 | go-v0.44 | tcp | noise | yamux | ✅ | 5s | 7.46 | 0.539 |
| go-v0.44 x go-v0.44 (ws, tls, yamux) | go-v0.44 | go-v0.44 | ws | tls | yamux | ✅ | 4s | 16.055 | 0.425 |
| go-v0.44 x go-v0.44 (ws, noise, yamux) | go-v0.44 | go-v0.44 | ws | noise | yamux | ✅ | 5s | 18.722 | 6.538 |
| go-v0.44 x go-v0.44 (webtransport) | go-v0.44 | go-v0.44 | webtransport | - | - | ✅ | 4s | 19.558 | 1.189 |
| go-v0.44 x go-v0.44 (quic-v1) | go-v0.44 | go-v0.44 | quic-v1 | - | - | ✅ | 5s | 15.873 | 0.705 |
| go-v0.44 x go-v0.44 (wss, tls, yamux) | go-v0.44 | go-v0.44 | wss | tls | yamux | ✅ | 6s | 15.205 | 0.879 |
| go-v0.44 x go-v0.44 (wss, noise, yamux) | go-v0.44 | go-v0.44 | wss | noise | yamux | ✅ | 6s | 18.3 | 3.057 |
| go-v0.44 x go-v0.44 (webrtc-direct) | go-v0.44 | go-v0.44 | webrtc-direct | - | - | ✅ | 5s | 11.998 | 0.402 |
| go-v0.44 x go-v0.45 (tcp, tls, yamux) | go-v0.44 | go-v0.45 | tcp | tls | yamux | ✅ | 5s | 11.134 | 2.546 |
| go-v0.44 x go-v0.45 (tcp, noise, yamux) | go-v0.44 | go-v0.45 | tcp | noise | yamux | ✅ | 4s | 7.603 | 0.917 |
| go-v0.44 x go-v0.45 (ws, tls, yamux) | go-v0.44 | go-v0.45 | ws | tls | yamux | ✅ | 5s | 10.241 | 1.96 |
| go-v0.44 x go-v0.45 (ws, noise, yamux) | go-v0.44 | go-v0.45 | ws | noise | yamux | ✅ | 4s | 10.756 | 1.526 |
| go-v0.44 x go-v0.45 (wss, noise, yamux) | go-v0.44 | go-v0.45 | wss | noise | yamux | ✅ | 4s | 31.084 | 0.34 |
| go-v0.44 x go-v0.45 (quic-v1) | go-v0.44 | go-v0.45 | quic-v1 | - | - | ✅ | 5s | 19.892 | 0.622 |
| go-v0.44 x go-v0.45 (wss, tls, yamux) | go-v0.44 | go-v0.45 | wss | tls | yamux | ✅ | 6s | 19.008 | 0.429 |
| go-v0.44 x go-v0.45 (webtransport) | go-v0.44 | go-v0.45 | webtransport | - | - | ✅ | 5s | 23.625 | 0.606 |
| go-v0.44 x go-v0.45 (webrtc-direct) | go-v0.44 | go-v0.45 | webrtc-direct | - | - | ✅ | 4s | 10.836 | 0.287 |
| go-v0.44 x python-v0.4 (tcp, noise, yamux) | go-v0.44 | python-v0.4 | tcp | noise | yamux | ✅ | 5s | 29.653 | 8.289 |
| go-v0.44 x python-v0.4 (ws, noise, yamux) | go-v0.44 | python-v0.4 | ws | noise | yamux | ✅ | 5s | 35.946 | 9.253 |
| go-v0.44 x python-v0.4 (wss, noise, yamux) | go-v0.44 | python-v0.4 | wss | noise | yamux | ✅ | 5s | 40.639 | 6.159 |
| go-v0.44 x python-v0.4 (quic-v1) | go-v0.44 | python-v0.4 | quic-v1 | - | - | ✅ | 5s | 93.102 | 21.708 |
| go-v0.44 x nim-v1.14 (tcp, noise, yamux) | go-v0.44 | nim-v1.14 | tcp | noise | yamux | ✅ | 4s | 219.53 | 43.567 |
| go-v0.44 x nim-v1.14 (ws, noise, yamux) | go-v0.44 | nim-v1.14 | ws | noise | yamux | ✅ | 5s | 220.246 | 44.705 |
| go-v0.44 x js-v1.x (ws, noise, yamux) | go-v0.44 | js-v1.x | ws | noise | yamux | ✅ | 19s | 191.146 | 19.654 |
| go-v0.44 x js-v1.x (tcp, noise, yamux) | go-v0.44 | js-v1.x | tcp | noise | yamux | ✅ | 20s | 154.427 | 16.929 |
| go-v0.44 x js-v2.x (ws, noise, yamux) | go-v0.44 | js-v2.x | ws | noise | yamux | ✅ | 21s | 162.481 | 27.5 |
| go-v0.44 x js-v3.x (tcp, noise, yamux) | go-v0.44 | js-v3.x | tcp | noise | yamux | ✅ | 21s | 130.714 | 22.081 |
| go-v0.44 x jvm-v1.2 (tcp, noise, yamux) | go-v0.44 | jvm-v1.2 | tcp | noise | yamux | ✅ | 10s | 1299.306 | 27.574 |
| go-v0.44 x js-v2.x (tcp, noise, yamux) | go-v0.44 | js-v2.x | tcp | noise | yamux | ✅ | 23s | 147.677 | 20.819 |
| go-v0.44 x jvm-v1.2 (tcp, tls, yamux) | go-v0.44 | jvm-v1.2 | tcp | tls | yamux | ✅ | 13s | 3335.803 | 10.728 |
| go-v0.44 x js-v3.x (ws, noise, yamux) | go-v0.44 | js-v3.x | ws | noise | yamux | ✅ | 22s | 50.078 | 8.846 |
| go-v0.44 x c-v0.0.1 (tcp, noise, yamux) | go-v0.44 | c-v0.0.1 | tcp | noise | yamux | ✅ | 6s | 129.212 | 54.867 |
| go-v0.44 x c-v0.0.1 (quic-v1) | go-v0.44 | c-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 95.217 | 44.063 |
| go-v0.44 x jvm-v1.2 (ws, noise, yamux) | go-v0.44 | jvm-v1.2 | ws | noise | yamux | ✅ | 10s | 1682.354 | 48.571 |
| go-v0.44 x jvm-v1.2 (ws, tls, yamux) | go-v0.44 | jvm-v1.2 | ws | tls | yamux | ✅ | 11s | 3558.953 | 12.24 |
| go-v0.44 x dotnet-v1.0 (tcp, noise, yamux) | go-v0.44 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 7s | 515.249 | 50.311 |
| go-v0.44 x zig-v0.0.1 (quic-v1) | go-v0.44 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 6s | - | - |
| go-v0.44 x eth-p2p-z-v0.0.1 (quic-v1) | go-v0.44 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 14.864 | 2.458 |
| go-v0.44 x jvm-v1.2 (quic-v1) | go-v0.44 | jvm-v1.2 | quic-v1 | - | - | ✅ | 11s | 592.659 | 9.982 |
| go-v0.45 x rust-v0.53 (tcp, tls, yamux) | go-v0.45 | rust-v0.53 | tcp | tls | yamux | ✅ | 4s | 98.302 | 46.31 |
| go-v0.45 x rust-v0.53 (tcp, noise, yamux) | go-v0.45 | rust-v0.53 | tcp | noise | yamux | ✅ | 4s | 141.067 | 43.267 |
| go-v0.45 x rust-v0.53 (quic-v1) | go-v0.45 | rust-v0.53 | quic-v1 | - | - | ✅ | 4s | 10.66 | 0.466 |
| go-v0.45 x rust-v0.53 (ws, tls, yamux) | go-v0.45 | rust-v0.53 | ws | tls | yamux | ✅ | 5s | 189.958 | 43.298 |
| go-v0.45 x rust-v0.53 (ws, noise, yamux) | go-v0.45 | rust-v0.53 | ws | noise | yamux | ✅ | 5s | 182.647 | 42.886 |
| go-v0.45 x rust-v0.54 (tcp, tls, yamux) | go-v0.45 | rust-v0.54 | tcp | tls | yamux | ✅ | 4s | 93.707 | 46.656 |
| go-v0.45 x rust-v0.53 (webrtc-direct) | go-v0.45 | rust-v0.53 | webrtc-direct | - | - | ✅ | 6s | 414.693 | 1.674 |
| go-v0.45 x rust-v0.54 (tcp, noise, yamux) | go-v0.45 | rust-v0.54 | tcp | noise | yamux | ✅ | 5s | 127.072 | 42.926 |
| go-v0.45 x rust-v0.54 (ws, noise, yamux) | go-v0.45 | rust-v0.54 | ws | noise | yamux | ✅ | 5s | 186.45 | 45.16 |
| go-v0.45 x rust-v0.54 (ws, tls, yamux) | go-v0.45 | rust-v0.54 | ws | tls | yamux | ✅ | 6s | 234.357 | 47.62 |
| go-v0.45 x rust-v0.54 (quic-v1) | go-v0.45 | rust-v0.54 | quic-v1 | - | - | ✅ | 4s | 10.235 | 0.268 |
| go-v0.45 x rust-v0.55 (tcp, tls, yamux) | go-v0.45 | rust-v0.55 | tcp | tls | yamux | ✅ | 5s | 5.804 | 0.223 |
| go-v0.45 x rust-v0.55 (tcp, noise, yamux) | go-v0.45 | rust-v0.55 | tcp | noise | yamux | ✅ | 4s | 11.304 | 0.384 |
| go-v0.45 x rust-v0.54 (webrtc-direct) | go-v0.45 | rust-v0.54 | webrtc-direct | - | - | ✅ | 6s | 445.54 | 1.441 |
| go-v0.45 x rust-v0.55 (ws, tls, yamux) | go-v0.45 | rust-v0.55 | ws | tls | yamux | ✅ | 5s | 14.948 | 0.389 |
| go-v0.45 x rust-v0.55 (ws, noise, yamux) | go-v0.45 | rust-v0.55 | ws | noise | yamux | ✅ | 5s | 4.157 | 0.2 |
| go-v0.45 x rust-v0.55 (quic-v1) | go-v0.45 | rust-v0.55 | quic-v1 | - | - | ✅ | 5s | 13.641 | 0.803 |
| go-v0.45 x rust-v0.55 (webrtc-direct) | go-v0.45 | rust-v0.55 | webrtc-direct | - | - | ✅ | 5s | 433.186 | 5.429 |
| go-v0.45 x rust-v0.56 (tcp, tls, yamux) | go-v0.45 | rust-v0.56 | tcp | tls | yamux | ✅ | 5s | 10.232 | 1.136 |
| go-v0.45 x rust-v0.56 (tcp, noise, yamux) | go-v0.45 | rust-v0.56 | tcp | noise | yamux | ✅ | 5s | 5.671 | 0.364 |
| go-v0.45 x rust-v0.56 (ws, tls, yamux) | go-v0.45 | rust-v0.56 | ws | tls | yamux | ✅ | 5s | 10.259 | 1.408 |
| go-v0.45 x rust-v0.56 (ws, noise, yamux) | go-v0.45 | rust-v0.56 | ws | noise | yamux | ✅ | 5s | 12.01 | 1.625 |
| go-v0.45 x rust-v0.56 (quic-v1) | go-v0.45 | rust-v0.56 | quic-v1 | - | - | ✅ | 5s | 4.656 | 0.185 |
| go-v0.45 x go-v0.38 (tcp, tls, yamux) | go-v0.45 | go-v0.38 | tcp | tls | yamux | ✅ | 5s | 13.873 | 2.065 |
| go-v0.45 x go-v0.38 (tcp, noise, yamux) | go-v0.45 | go-v0.38 | tcp | noise | yamux | ✅ | 4s | 9.606 | 0.971 |
| go-v0.45 x go-v0.38 (ws, tls, yamux) | go-v0.45 | go-v0.38 | ws | tls | yamux | ✅ | 4s | 14.538 | 1.023 |
| go-v0.45 x go-v0.38 (ws, noise, yamux) | go-v0.45 | go-v0.38 | ws | noise | yamux | ✅ | 4s | 7.267 | 0.688 |
| go-v0.45 x go-v0.38 (quic-v1) | go-v0.45 | go-v0.38 | quic-v1 | - | - | ✅ | 4s | 11.124 | 0.624 |
| go-v0.45 x go-v0.38 (wss, tls, yamux) | go-v0.45 | go-v0.38 | wss | tls | yamux | ✅ | 5s | 20.354 | 0.425 |
| go-v0.45 x go-v0.38 (wss, noise, yamux) | go-v0.45 | go-v0.38 | wss | noise | yamux | ✅ | 5s | 11.846 | 0.384 |
| go-v0.45 x go-v0.38 (webtransport) | go-v0.45 | go-v0.38 | webtransport | - | - | ✅ | 4s | 7.173 | 0.245 |
| go-v0.45 x rust-v0.56 (webrtc-direct) | go-v0.45 | rust-v0.56 | webrtc-direct | - | - | ❌ | 11s | - | - |
| go-v0.45 x go-v0.38 (webrtc-direct) | go-v0.45 | go-v0.38 | webrtc-direct | - | - | ✅ | 5s | 217.57 | 1.377 |
| go-v0.45 x go-v0.39 (tcp, tls, yamux) | go-v0.45 | go-v0.39 | tcp | tls | yamux | ✅ | 5s | 11.461 | 1.798 |
| go-v0.45 x go-v0.39 (tcp, noise, yamux) | go-v0.45 | go-v0.39 | tcp | noise | yamux | ✅ | 5s | 11.128 | 2.657 |
| go-v0.45 x go-v0.39 (ws, tls, yamux) | go-v0.45 | go-v0.39 | ws | tls | yamux | ✅ | 4s | 8.246 | 0.341 |
| go-v0.45 x go-v0.39 (ws, noise, yamux) | go-v0.45 | go-v0.39 | ws | noise | yamux | ✅ | 5s | 19.761 | 2.365 |
| go-v0.45 x go-v0.39 (quic-v1) | go-v0.45 | go-v0.39 | quic-v1 | - | - | ✅ | 5s | 17.991 | 0.732 |
| go-v0.45 x go-v0.39 (wss, tls, yamux) | go-v0.45 | go-v0.39 | wss | tls | yamux | ✅ | 6s | 27.011 | 3.868 |
| go-v0.45 x go-v0.39 (wss, noise, yamux) | go-v0.45 | go-v0.39 | wss | noise | yamux | ✅ | 6s | 19.39 | 0.772 |
| go-v0.45 x go-v0.39 (webtransport) | go-v0.45 | go-v0.39 | webtransport | - | - | ✅ | 4s | 12.38 | 0.962 |
| go-v0.45 x go-v0.39 (webrtc-direct) | go-v0.45 | go-v0.39 | webrtc-direct | - | - | ✅ | 5s | 212.589 | 0.526 |
| go-v0.45 x go-v0.40 (tcp, noise, yamux) | go-v0.45 | go-v0.40 | tcp | noise | yamux | ✅ | 4s | 7.01 | 0.47 |
| go-v0.45 x go-v0.40 (tcp, tls, yamux) | go-v0.45 | go-v0.40 | tcp | tls | yamux | ✅ | 5s | 13.05 | 0.371 |
| go-v0.45 x go-v0.40 (ws, tls, yamux) | go-v0.45 | go-v0.40 | ws | tls | yamux | ✅ | 5s | 7.633 | 0.414 |
| go-v0.45 x go-v0.40 (ws, noise, yamux) | go-v0.45 | go-v0.40 | ws | noise | yamux | ✅ | 5s | 20.238 | 2.11 |
| go-v0.45 x go-v0.40 (quic-v1) | go-v0.45 | go-v0.40 | quic-v1 | - | - | ✅ | 4s | 16.107 | 2.53 |
| go-v0.45 x go-v0.40 (wss, noise, yamux) | go-v0.45 | go-v0.40 | wss | noise | yamux | ✅ | 6s | 18.46 | 0.275 |
| go-v0.45 x go-v0.40 (webtransport) | go-v0.45 | go-v0.40 | webtransport | - | - | ✅ | 4s | 19.664 | 1.097 |
| go-v0.45 x go-v0.40 (wss, tls, yamux) | go-v0.45 | go-v0.40 | wss | tls | yamux | ✅ | 7s | 16.782 | 0.428 |
| go-v0.45 x go-v0.40 (webrtc-direct) | go-v0.45 | go-v0.40 | webrtc-direct | - | - | ✅ | 4s | 277.44 | 0.335 |
| go-v0.45 x go-v0.41 (tcp, tls, yamux) | go-v0.45 | go-v0.41 | tcp | tls | yamux | ✅ | 5s | 7.286 | 0.243 |
| go-v0.45 x go-v0.41 (tcp, noise, yamux) | go-v0.45 | go-v0.41 | tcp | noise | yamux | ✅ | 4s | 8.08 | 1.782 |
| go-v0.45 x go-v0.41 (ws, tls, yamux) | go-v0.45 | go-v0.41 | ws | tls | yamux | ✅ | 5s | 20.687 | 0.82 |
| go-v0.45 x go-v0.41 (ws, noise, yamux) | go-v0.45 | go-v0.41 | ws | noise | yamux | ✅ | 4s | 10.743 | 2.369 |
| go-v0.45 x go-v0.41 (quic-v1) | go-v0.45 | go-v0.41 | quic-v1 | - | - | ✅ | 4s | 13.376 | 1.197 |
| go-v0.45 x go-v0.41 (wss, tls, yamux) | go-v0.45 | go-v0.41 | wss | tls | yamux | ✅ | 6s | 14.374 | 0.421 |
| go-v0.45 x go-v0.41 (wss, noise, yamux) | go-v0.45 | go-v0.41 | wss | noise | yamux | ✅ | 5s | 21.386 | 0.924 |
| go-v0.45 x go-v0.41 (webtransport) | go-v0.45 | go-v0.41 | webtransport | - | - | ✅ | 5s | 8.234 | 0.468 |
| go-v0.45 x go-v0.41 (webrtc-direct) | go-v0.45 | go-v0.41 | webrtc-direct | - | - | ✅ | 6s | 222.644 | 0.332 |
| go-v0.45 x go-v0.42 (tcp, tls, yamux) | go-v0.45 | go-v0.42 | tcp | tls | yamux | ✅ | 5s | 14.426 | 1.826 |
| go-v0.45 x go-v0.42 (tcp, noise, yamux) | go-v0.45 | go-v0.42 | tcp | noise | yamux | ✅ | 5s | 15.584 | 2.306 |
| go-v0.45 x go-v0.42 (ws, tls, yamux) | go-v0.45 | go-v0.42 | ws | tls | yamux | ✅ | 4s | 13.349 | 0.645 |
| go-v0.45 x go-v0.42 (ws, noise, yamux) | go-v0.45 | go-v0.42 | ws | noise | yamux | ✅ | 4s | 14.612 | 0.561 |
| go-v0.45 x go-v0.42 (wss, tls, yamux) | go-v0.45 | go-v0.42 | wss | tls | yamux | ✅ | 5s | 21.904 | 0.717 |
| go-v0.45 x go-v0.42 (quic-v1) | go-v0.45 | go-v0.42 | quic-v1 | - | - | ✅ | 5s | 21.085 | 0.667 |
| go-v0.45 x go-v0.42 (wss, noise, yamux) | go-v0.45 | go-v0.42 | wss | noise | yamux | ✅ | 5s | 66.355 | 0.283 |
| go-v0.45 x go-v0.42 (webtransport) | go-v0.45 | go-v0.42 | webtransport | - | - | ✅ | 5s | 14.401 | 0.517 |
| go-v0.45 x go-v0.43 (tcp, tls, yamux) | go-v0.45 | go-v0.43 | tcp | tls | yamux | ✅ | 4s | 12.558 | 1.966 |
| go-v0.45 x go-v0.42 (webrtc-direct) | go-v0.45 | go-v0.42 | webrtc-direct | - | - | ✅ | 5s | 221.638 | 0.309 |
| go-v0.45 x go-v0.43 (tcp, noise, yamux) | go-v0.45 | go-v0.43 | tcp | noise | yamux | ✅ | 5s | 5.194 | 0.437 |
| go-v0.45 x go-v0.43 (ws, tls, yamux) | go-v0.45 | go-v0.43 | ws | tls | yamux | ✅ | 5s | 11.19 | 0.412 |
| go-v0.45 x go-v0.43 (ws, noise, yamux) | go-v0.45 | go-v0.43 | ws | noise | yamux | ✅ | 5s | 12.091 | 2.252 |
| go-v0.45 x go-v0.43 (wss, tls, yamux) | go-v0.45 | go-v0.43 | wss | tls | yamux | ✅ | 5s | 12.582 | 0.346 |
| go-v0.45 x go-v0.43 (quic-v1) | go-v0.45 | go-v0.43 | quic-v1 | - | - | ✅ | 4s | 21.623 | 0.581 |
| go-v0.45 x go-v0.43 (wss, noise, yamux) | go-v0.45 | go-v0.43 | wss | noise | yamux | ✅ | 6s | 18.161 | 0.688 |
| go-v0.45 x go-v0.43 (webtransport) | go-v0.45 | go-v0.43 | webtransport | - | - | ✅ | 4s | 19.69 | 1.491 |
| go-v0.45 x go-v0.44 (tcp, tls, yamux) | go-v0.45 | go-v0.44 | tcp | tls | yamux | ✅ | 4s | 10.225 | 0.213 |
| go-v0.45 x go-v0.43 (webrtc-direct) | go-v0.45 | go-v0.43 | webrtc-direct | - | - | ✅ | 6s | 213.721 | 0.321 |
| go-v0.45 x go-v0.44 (tcp, noise, yamux) | go-v0.45 | go-v0.44 | tcp | noise | yamux | ✅ | 5s | 8.96 | 1.705 |
| go-v0.45 x go-v0.44 (ws, tls, yamux) | go-v0.45 | go-v0.44 | ws | tls | yamux | ✅ | 5s | 11.85 | 0.925 |
| go-v0.45 x go-v0.44 (ws, noise, yamux) | go-v0.45 | go-v0.44 | ws | noise | yamux | ✅ | 5s | 11.362 | 0.487 |
| go-v0.45 x go-v0.44 (wss, tls, yamux) | go-v0.45 | go-v0.44 | wss | tls | yamux | ✅ | 5s | 27.946 | 0.484 |
| go-v0.45 x go-v0.44 (quic-v1) | go-v0.45 | go-v0.44 | quic-v1 | - | - | ✅ | 5s | 16.017 | 2.237 |
| go-v0.45 x go-v0.44 (wss, noise, yamux) | go-v0.45 | go-v0.44 | wss | noise | yamux | ✅ | 5s | 17.073 | 0.9 |
| go-v0.45 x go-v0.44 (webtransport) | go-v0.45 | go-v0.44 | webtransport | - | - | ✅ | 5s | 15.368 | 0.586 |
| go-v0.45 x go-v0.44 (webrtc-direct) | go-v0.45 | go-v0.44 | webrtc-direct | - | - | ✅ | 5s | 213.157 | 0.83 |
| go-v0.45 x go-v0.45 (tcp, tls, yamux) | go-v0.45 | go-v0.45 | tcp | tls | yamux | ✅ | 4s | 10.893 | 0.77 |
| go-v0.45 x go-v0.45 (tcp, noise, yamux) | go-v0.45 | go-v0.45 | tcp | noise | yamux | ✅ | 4s | 10.59 | 0.586 |
| go-v0.45 x go-v0.45 (ws, tls, yamux) | go-v0.45 | go-v0.45 | ws | tls | yamux | ✅ | 5s | 14.309 | 1.282 |
| go-v0.45 x go-v0.45 (ws, noise, yamux) | go-v0.45 | go-v0.45 | ws | noise | yamux | ✅ | 5s | 9.011 | 1.631 |
| go-v0.45 x go-v0.45 (quic-v1) | go-v0.45 | go-v0.45 | quic-v1 | - | - | ✅ | 4s | 14.788 | 0.752 |
| go-v0.45 x go-v0.45 (webtransport) | go-v0.45 | go-v0.45 | webtransport | - | - | ✅ | 4s | 17.396 | 0.64 |
| go-v0.45 x go-v0.45 (wss, tls, yamux) | go-v0.45 | go-v0.45 | wss | tls | yamux | ✅ | 7s | 19.546 | 0.558 |
| go-v0.45 x go-v0.45 (webrtc-direct) | go-v0.45 | go-v0.45 | webrtc-direct | - | - | ✅ | 5s | 216.088 | 0.382 |
| go-v0.45 x go-v0.45 (wss, noise, yamux) | go-v0.45 | go-v0.45 | wss | noise | yamux | ✅ | 6s | 41.174 | 0.272 |
| go-v0.45 x python-v0.4 (tcp, noise, yamux) | go-v0.45 | python-v0.4 | tcp | noise | yamux | ✅ | 5s | 14.797 | 2.204 |
| go-v0.45 x python-v0.4 (ws, noise, yamux) | go-v0.45 | python-v0.4 | ws | noise | yamux | ✅ | 5s | 36.597 | 2.389 |
| go-v0.45 x python-v0.4 (wss, noise, yamux) | go-v0.45 | python-v0.4 | wss | noise | yamux | ✅ | 5s | 35.686 | 6.637 |
| go-v0.45 x python-v0.4 (quic-v1) | go-v0.45 | python-v0.4 | quic-v1 | - | - | ✅ | 5s | 91.176 | 18.226 |
| go-v0.45 x nim-v1.14 (tcp, noise, yamux) | go-v0.45 | nim-v1.14 | tcp | noise | yamux | ✅ | 4s | 231.577 | 47.52 |
| go-v0.45 x nim-v1.14 (ws, noise, yamux) | go-v0.45 | nim-v1.14 | ws | noise | yamux | ✅ | 5s | 250.623 | 47.607 |
| go-v0.45 x js-v1.x (tcp, noise, yamux) | go-v0.45 | js-v1.x | tcp | noise | yamux | ✅ | 19s | 135.623 | 20.225 |
| go-v0.45 x js-v1.x (ws, noise, yamux) | go-v0.45 | js-v1.x | ws | noise | yamux | ✅ | 20s | 222.266 | 22.325 |
| go-v0.45 x js-v2.x (tcp, noise, yamux) | go-v0.45 | js-v2.x | tcp | noise | yamux | ✅ | 21s | 141.786 | 19.776 |
| go-v0.45 x js-v3.x (tcp, noise, yamux) | go-v0.45 | js-v3.x | tcp | noise | yamux | ✅ | 21s | 135.282 | 20.829 |
| go-v0.45 x jvm-v1.2 (tcp, noise, yamux) | go-v0.45 | jvm-v1.2 | tcp | noise | yamux | ✅ | 11s | 1399.931 | 27.496 |
| go-v0.45 x js-v2.x (ws, noise, yamux) | go-v0.45 | js-v2.x | ws | noise | yamux | ✅ | 23s | 222.659 | 30.989 |
| go-v0.45 x jvm-v1.2 (tcp, tls, yamux) | go-v0.45 | jvm-v1.2 | tcp | tls | yamux | ✅ | 13s | 3199.799 | 6.457 |
| go-v0.45 x js-v3.x (ws, noise, yamux) | go-v0.45 | js-v3.x | ws | noise | yamux | ✅ | 23s | 87.817 | 13.086 |
| go-v0.45 x c-v0.0.1 (tcp, noise, yamux) | go-v0.45 | c-v0.0.1 | tcp | noise | yamux | ✅ | 6s | 132.765 | 53.75 |
| go-v0.45 x c-v0.0.1 (quic-v1) | go-v0.45 | c-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 88.799 | 34.303 |
| go-v0.45 x jvm-v1.2 (ws, noise, yamux) | go-v0.45 | jvm-v1.2 | ws | noise | yamux | ✅ | 9s | 1433.933 | 64.323 |
| go-v0.45 x dotnet-v1.0 (tcp, noise, yamux) | go-v0.45 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 6s | 536.581 | 46.611 |
| go-v0.45 x zig-v0.0.1 (quic-v1) | go-v0.45 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 6s | - | - |
| go-v0.45 x jvm-v1.2 (ws, tls, yamux) | go-v0.45 | jvm-v1.2 | ws | tls | yamux | ✅ | 11s | 3931.291 | 17.475 |
| go-v0.45 x eth-p2p-z-v0.0.1 (quic-v1) | go-v0.45 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 7s | 10.713 | 0.317 |
| go-v0.45 x jvm-v1.2 (quic-v1) | go-v0.45 | jvm-v1.2 | quic-v1 | - | - | ✅ | 11s | 491.243 | 5.304 |
| python-v0.4 x rust-v0.53 (tcp, noise, mplex) | python-v0.4 | rust-v0.53 | tcp | noise | mplex | ✅ | 6s | - | - |
| python-v0.4 x rust-v0.53 (tcp, noise, yamux) | python-v0.4 | rust-v0.53 | tcp | noise | yamux | ✅ | 6s | - | - |
| python-v0.4 x rust-v0.53 (quic-v1) | python-v0.4 | rust-v0.53 | quic-v1 | - | - | ✅ | 6s | - | - |
| python-v0.4 x rust-v0.54 (tcp, noise, mplex) | python-v0.4 | rust-v0.54 | tcp | noise | mplex | ✅ | 6s | - | - |
| python-v0.4 x rust-v0.54 (tcp, noise, yamux) | python-v0.4 | rust-v0.54 | tcp | noise | yamux | ✅ | 6s | - | - |
| python-v0.4 x rust-v0.54 (quic-v1) | python-v0.4 | rust-v0.54 | quic-v1 | - | - | ✅ | 4s | - | - |
| python-v0.4 x rust-v0.53 (ws, noise, mplex) | python-v0.4 | rust-v0.53 | ws | noise | mplex | ✅ | 10s | - | - |
| python-v0.4 x rust-v0.55 (tcp, noise, mplex) | python-v0.4 | rust-v0.55 | tcp | noise | mplex | ✅ | 4s | - | - |
| python-v0.4 x rust-v0.53 (ws, noise, yamux) | python-v0.4 | rust-v0.53 | ws | noise | yamux | ✅ | 11s | - | - |
| python-v0.4 x rust-v0.55 (tcp, noise, yamux) | python-v0.4 | rust-v0.55 | tcp | noise | yamux | ✅ | 5s | - | - |
| python-v0.4 x rust-v0.54 (ws, noise, mplex) | python-v0.4 | rust-v0.54 | ws | noise | mplex | ✅ | 10s | - | - |
| python-v0.4 x rust-v0.54 (ws, noise, yamux) | python-v0.4 | rust-v0.54 | ws | noise | yamux | ✅ | 10s | - | - |
| python-v0.4 x rust-v0.56 (tcp, noise, mplex) | python-v0.4 | rust-v0.56 | tcp | noise | mplex | ✅ | 4s | - | - |
| python-v0.4 x rust-v0.56 (tcp, noise, yamux) | python-v0.4 | rust-v0.56 | tcp | noise | yamux | ✅ | 4s | - | - |
| python-v0.4 x rust-v0.55 (quic-v1) | python-v0.4 | rust-v0.55 | quic-v1 | - | - | ✅ | 5s | - | - |
| python-v0.4 x rust-v0.56 (quic-v1) | python-v0.4 | rust-v0.56 | quic-v1 | - | - | ✅ | 4s | - | - |
| python-v0.4 x go-v0.38 (tcp, noise, yamux) | python-v0.4 | go-v0.38 | tcp | noise | yamux | ✅ | 4s | - | - |
| python-v0.4 x rust-v0.55 (ws, noise, mplex) | python-v0.4 | rust-v0.55 | ws | noise | mplex | ✅ | 13s | - | - |
| python-v0.4 x go-v0.38 (quic-v1) | python-v0.4 | go-v0.38 | quic-v1 | - | - | ✅ | 4s | - | - |
| python-v0.4 x go-v0.39 (tcp, noise, yamux) | python-v0.4 | go-v0.39 | tcp | noise | yamux | ✅ | 4s | - | - |
| python-v0.4 x rust-v0.55 (ws, noise, yamux) | python-v0.4 | rust-v0.55 | ws | noise | yamux | ✅ | 15s | - | - |
| python-v0.4 x rust-v0.56 (ws, noise, mplex) | python-v0.4 | rust-v0.56 | ws | noise | mplex | ✅ | 14s | - | - |
| python-v0.4 x go-v0.39 (quic-v1) | python-v0.4 | go-v0.39 | quic-v1 | - | - | ✅ | 4s | - | - |
| python-v0.4 x rust-v0.56 (ws, noise, yamux) | python-v0.4 | rust-v0.56 | ws | noise | yamux | ✅ | 15s | - | - |
| python-v0.4 x go-v0.40 (tcp, noise, yamux) | python-v0.4 | go-v0.40 | tcp | noise | yamux | ✅ | 4s | - | - |
| python-v0.4 x go-v0.40 (quic-v1) | python-v0.4 | go-v0.40 | quic-v1 | - | - | ✅ | 4s | - | - |
| python-v0.4 x go-v0.41 (tcp, noise, yamux) | python-v0.4 | go-v0.41 | tcp | noise | yamux | ✅ | 3s | - | - |
| python-v0.4 x go-v0.38 (ws, noise, yamux) | python-v0.4 | go-v0.38 | ws | noise | yamux | ✅ | 43s | - | - |
| python-v0.4 x go-v0.38 (wss, noise, yamux) | python-v0.4 | go-v0.38 | wss | noise | yamux | ✅ | 43s | - | - |
| python-v0.4 x go-v0.41 (quic-v1) | python-v0.4 | go-v0.41 | quic-v1 | - | - | ✅ | 3s | - | - |
| python-v0.4 x go-v0.42 (tcp, noise, yamux) | python-v0.4 | go-v0.42 | tcp | noise | yamux | ✅ | 3s | - | - |
| python-v0.4 x go-v0.39 (ws, noise, yamux) | python-v0.4 | go-v0.39 | ws | noise | yamux | ✅ | 43s | - | - |
| python-v0.4 x go-v0.39 (wss, noise, yamux) | python-v0.4 | go-v0.39 | wss | noise | yamux | ✅ | 44s | - | - |
| python-v0.4 x go-v0.42 (quic-v1) | python-v0.4 | go-v0.42 | quic-v1 | - | - | ✅ | 3s | - | - |
| python-v0.4 x go-v0.40 (ws, noise, yamux) | python-v0.4 | go-v0.40 | ws | noise | yamux | ✅ | 43s | - | - |
| python-v0.4 x go-v0.43 (tcp, noise, yamux) | python-v0.4 | go-v0.43 | tcp | noise | yamux | ✅ | 3s | - | - |
| python-v0.4 x go-v0.40 (wss, noise, yamux) | python-v0.4 | go-v0.40 | wss | noise | yamux | ✅ | 43s | - | - |
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
| python-v0.4 x go-v0.43 (wss, noise, yamux) | python-v0.4 | go-v0.43 | wss | noise | yamux | ✅ | 44s | - | - |
| python-v0.4 x python-v0.4 (tcp, noise, yamux) | python-v0.4 | python-v0.4 | tcp | noise | yamux | ✅ | 4s | - | - |
| python-v0.4 x python-v0.4 (ws, noise, mplex) | python-v0.4 | python-v0.4 | ws | noise | mplex | ✅ | 3s | - | - |
| python-v0.4 x python-v0.4 (ws, noise, yamux) | python-v0.4 | python-v0.4 | ws | noise | yamux | ✅ | 4s | - | - |
| python-v0.4 x python-v0.4 (wss, noise, mplex) | python-v0.4 | python-v0.4 | wss | noise | mplex | ✅ | 4s | - | - |
| python-v0.4 x python-v0.4 (wss, noise, yamux) | python-v0.4 | python-v0.4 | wss | noise | yamux | ✅ | 4s | - | - |
| python-v0.4 x python-v0.4 (quic-v1) | python-v0.4 | python-v0.4 | quic-v1 | - | - | ✅ | 4s | - | - |
| python-v0.4 x go-v0.44 (ws, noise, yamux) | python-v0.4 | go-v0.44 | ws | noise | yamux | ✅ | 45s | - | - |
| python-v0.4 x go-v0.44 (wss, noise, yamux) | python-v0.4 | go-v0.44 | wss | noise | yamux | ✅ | 44s | - | - |
| python-v0.4 x go-v0.45 (ws, noise, yamux) | python-v0.4 | go-v0.45 | ws | noise | yamux | ✅ | 44s | - | - |
| python-v0.4 x go-v0.45 (wss, noise, yamux) | python-v0.4 | go-v0.45 | wss | noise | yamux | ✅ | 45s | - | - |
| python-v0.4 x js-v1.x (tcp, noise, mplex) | python-v0.4 | js-v1.x | tcp | noise | mplex | ✅ | 15s | - | - |
| python-v0.4 x js-v1.x (tcp, noise, yamux) | python-v0.4 | js-v1.x | tcp | noise | yamux | ✅ | 17s | - | - |
| python-v0.4 x js-v2.x (tcp, noise, mplex) | python-v0.4 | js-v2.x | tcp | noise | mplex | ✅ | 17s | - | - |
| python-v0.4 x js-v2.x (tcp, noise, yamux) | python-v0.4 | js-v2.x | tcp | noise | yamux | ✅ | 17s | - | - |
| python-v0.4 x js-v3.x (tcp, noise, mplex) | python-v0.4 | js-v3.x | tcp | noise | mplex | ✅ | 13s | - | - |
| python-v0.4 x js-v1.x (ws, noise, mplex) | python-v0.4 | js-v1.x | ws | noise | mplex | ✅ | 28s | - | - |
| python-v0.4 x js-v1.x (ws, noise, yamux) | python-v0.4 | js-v1.x | ws | noise | yamux | ✅ | 29s | - | - |
| python-v0.4 x js-v3.x (tcp, noise, yamux) | python-v0.4 | js-v3.x | tcp | noise | yamux | ✅ | 12s | - | - |
| python-v0.4 x nim-v1.14 (tcp, noise, mplex) | python-v0.4 | nim-v1.14 | tcp | noise | mplex | ✅ | 4s | - | - |
| python-v0.4 x nim-v1.14 (tcp, noise, yamux) | python-v0.4 | nim-v1.14 | tcp | noise | yamux | ✅ | 3s | - | - |
| python-v0.4 x jvm-v1.2 (tcp, noise, mplex) | python-v0.4 | jvm-v1.2 | tcp | noise | mplex | ✅ | 5s | - | - |
| python-v0.4 x jvm-v1.2 (tcp, noise, yamux) | python-v0.4 | jvm-v1.2 | tcp | noise | yamux | ✅ | 5s | - | - |
| python-v0.4 x js-v2.x (ws, noise, mplex) | python-v0.4 | js-v2.x | ws | noise | mplex | ✅ | 195s | - | - |
| python-v0.4 x js-v2.x (ws, noise, yamux) | python-v0.4 | js-v2.x | ws | noise | yamux | ✅ | 195s | - | - |
| python-v0.4 x jvm-v1.2 (quic-v1) | python-v0.4 | jvm-v1.2 | quic-v1 | - | - | ✅ | 4s | - | - |
| python-v0.4 x c-v0.0.1 (tcp, noise, yamux) | python-v0.4 | c-v0.0.1 | tcp | noise | yamux | ✅ | 3s | - | - |
| python-v0.4 x js-v3.x (ws, noise, mplex) | python-v0.4 | js-v3.x | ws | noise | mplex | ✅ | 191s | - | - |
| python-v0.4 x js-v3.x (ws, noise, yamux) | python-v0.4 | js-v3.x | ws | noise | yamux | ✅ | 191s | - | - |
| python-v0.4 x nim-v1.14 (ws, noise, mplex) | python-v0.4 | nim-v1.14 | ws | noise | mplex | ✅ | 182s | - | - |
| python-v0.4 x nim-v1.14 (ws, noise, yamux) | python-v0.4 | nim-v1.14 | ws | noise | yamux | ✅ | 183s | - | - |
| python-v0.4 x c-v0.0.1 (quic-v1) | python-v0.4 | c-v0.0.1 | quic-v1 | - | - | ✅ | 4s | - | - |
| python-v0.4 x dotnet-v1.0 (tcp, noise, yamux) | python-v0.4 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 4s | - | - |
| python-v0.4 x eth-p2p-z-v0.0.1 (quic-v1) | python-v0.4 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 3s | - | - |
| js-v1.x x rust-v0.53 (tcp, noise, mplex) | js-v1.x | rust-v0.53 | tcp | noise | mplex | ✅ | 8s | 97 | 16 |
| python-v0.4 x jvm-v1.2 (ws, noise, mplex) | python-v0.4 | jvm-v1.2 | ws | noise | mplex | ✅ | 185s | - | - |
| js-v1.x x rust-v0.53 (tcp, noise, yamux) | js-v1.x | rust-v0.53 | tcp | noise | yamux | ✅ | 9s | 109 | 20 |
| python-v0.4 x jvm-v1.2 (ws, noise, yamux) | python-v0.4 | jvm-v1.2 | ws | noise | yamux | ✅ | 184s | - | - |
| js-v1.x x rust-v0.53 (ws, noise, mplex) | js-v1.x | rust-v0.53 | ws | noise | mplex | ✅ | 9s | 192 | 19 |
| js-v1.x x rust-v0.53 (ws, noise, yamux) | js-v1.x | rust-v0.53 | ws | noise | yamux | ✅ | 7s | 210 | 31 |
| js-v1.x x rust-v0.54 (tcp, noise, mplex) | js-v1.x | rust-v0.54 | tcp | noise | mplex | ✅ | 10s | 142 | 31 |
| js-v1.x x rust-v0.54 (tcp, noise, yamux) | js-v1.x | rust-v0.54 | tcp | noise | yamux | ✅ | 12s | 135 | 27 |
| js-v1.x x rust-v0.54 (ws, noise, mplex) | js-v1.x | rust-v0.54 | ws | noise | mplex | ✅ | 12s | 220 | 31 |
| js-v1.x x rust-v0.54 (ws, noise, yamux) | js-v1.x | rust-v0.54 | ws | noise | yamux | ✅ | 11s | 207 | 23 |
| js-v1.x x rust-v0.55 (tcp, noise, mplex) | js-v1.x | rust-v0.55 | tcp | noise | mplex | ✅ | 12s | 65 | 21 |
| js-v1.x x rust-v0.55 (tcp, noise, yamux) | js-v1.x | rust-v0.55 | tcp | noise | yamux | ✅ | 10s | 55 | 20 |
| python-v0.4 x c-v0.0.1 (tcp, noise, mplex) | python-v0.4 | c-v0.0.1 | tcp | noise | mplex | ✅ | 33s | - | - |
| js-v1.x x rust-v0.55 (ws, noise, mplex) | js-v1.x | rust-v0.55 | ws | noise | mplex | ✅ | 12s | 126 | 43 |
| python-v0.4 x zig-v0.0.1 (quic-v1) | python-v0.4 | zig-v0.0.1 | quic-v1 | - | - | ❌ | 36s | - | - |
| js-v1.x x rust-v0.55 (ws, noise, yamux) | js-v1.x | rust-v0.55 | ws | noise | yamux | ✅ | 14s | 111 | 37 |
| js-v1.x x rust-v0.56 (tcp, noise, mplex) | js-v1.x | rust-v0.56 | tcp | noise | mplex | ✅ | 14s | 75 | 22 |
| js-v1.x x rust-v0.56 (tcp, noise, yamux) | js-v1.x | rust-v0.56 | tcp | noise | yamux | ✅ | 14s | 100 | 24 |
| js-v1.x x rust-v0.56 (ws, noise, mplex) | js-v1.x | rust-v0.56 | ws | noise | mplex | ✅ | 14s | 94 | 30 |
| js-v1.x x rust-v0.56 (ws, noise, yamux) | js-v1.x | rust-v0.56 | ws | noise | yamux | ✅ | 14s | 69 | 17 |
| js-v1.x x go-v0.38 (tcp, noise, yamux) | js-v1.x | go-v0.38 | tcp | noise | yamux | ✅ | 13s | 71 | 18 |
| js-v1.x x go-v0.38 (ws, noise, yamux) | js-v1.x | go-v0.38 | ws | noise | yamux | ✅ | 15s | 138 | 45 |
| js-v1.x x go-v0.38 (wss, noise, yamux) | js-v1.x | go-v0.38 | wss | noise | yamux | ✅ | 16s | 242 | 49 |
| js-v1.x x go-v0.39 (tcp, noise, yamux) | js-v1.x | go-v0.39 | tcp | noise | yamux | ✅ | 17s | 110 | 38 |
| js-v1.x x go-v0.39 (ws, noise, yamux) | js-v1.x | go-v0.39 | ws | noise | yamux | ✅ | 16s | 123 | 30 |
| js-v1.x x go-v0.39 (wss, noise, yamux) | js-v1.x | go-v0.39 | wss | noise | yamux | ✅ | 17s | 202 | 36 |
| js-v1.x x go-v0.40 (tcp, noise, yamux) | js-v1.x | go-v0.40 | tcp | noise | yamux | ✅ | 17s | 76 | 20 |
| js-v1.x x go-v0.40 (ws, noise, yamux) | js-v1.x | go-v0.40 | ws | noise | yamux | ✅ | 17s | 65 | 21 |
| js-v1.x x go-v0.40 (wss, noise, yamux) | js-v1.x | go-v0.40 | wss | noise | yamux | ✅ | 17s | 108 | 20 |
| js-v1.x x go-v0.41 (tcp, noise, yamux) | js-v1.x | go-v0.41 | tcp | noise | yamux | ✅ | 16s | 112 | 38 |
| js-v1.x x go-v0.41 (ws, noise, yamux) | js-v1.x | go-v0.41 | ws | noise | yamux | ✅ | 17s | 135 | 38 |
| js-v1.x x go-v0.41 (wss, noise, yamux) | js-v1.x | go-v0.41 | wss | noise | yamux | ✅ | 17s | 214 | 40 |
| js-v1.x x go-v0.42 (tcp, noise, yamux) | js-v1.x | go-v0.42 | tcp | noise | yamux | ✅ | 17s | 107 | 39 |
| js-v1.x x go-v0.42 (ws, noise, yamux) | js-v1.x | go-v0.42 | ws | noise | yamux | ✅ | 16s | 99 | 31 |
| js-v1.x x go-v0.42 (wss, noise, yamux) | js-v1.x | go-v0.42 | wss | noise | yamux | ✅ | 17s | 167 | 38 |
| js-v1.x x go-v0.43 (tcp, noise, yamux) | js-v1.x | go-v0.43 | tcp | noise | yamux | ✅ | 16s | 103 | 33 |
| js-v1.x x go-v0.43 (ws, noise, yamux) | js-v1.x | go-v0.43 | ws | noise | yamux | ✅ | 17s | 78 | 31 |
| js-v1.x x go-v0.43 (wss, noise, yamux) | js-v1.x | go-v0.43 | wss | noise | yamux | ✅ | 19s | 237 | 60 |
| js-v1.x x go-v0.44 (ws, noise, yamux) | js-v1.x | go-v0.44 | ws | noise | yamux | ✅ | 18s | 130 | 43 |
| js-v1.x x go-v0.44 (wss, noise, yamux) | js-v1.x | go-v0.44 | wss | noise | yamux | ✅ | 18s | 215 | 38 |
| js-v1.x x go-v0.44 (tcp, noise, yamux) | js-v1.x | go-v0.44 | tcp | noise | yamux | ✅ | 20s | 126 | 41 |
| js-v1.x x go-v0.45 (tcp, noise, yamux) | js-v1.x | go-v0.45 | tcp | noise | yamux | ✅ | 18s | 70 | 27 |
| js-v1.x x go-v0.45 (ws, noise, yamux) | js-v1.x | go-v0.45 | ws | noise | yamux | ✅ | 19s | 108 | 29 |
| js-v1.x x go-v0.45 (wss, noise, yamux) | js-v1.x | go-v0.45 | wss | noise | yamux | ✅ | 18s | 146 | 25 |
| js-v1.x x python-v0.4 (tcp, noise, mplex) | js-v1.x | python-v0.4 | tcp | noise | mplex | ✅ | 18s | 47 | 15 |
| js-v1.x x python-v0.4 (tcp, noise, yamux) | js-v1.x | python-v0.4 | tcp | noise | yamux | ✅ | 23s | 204 | 56 |
| js-v1.x x python-v0.4 (ws, noise, mplex) | js-v1.x | python-v0.4 | ws | noise | mplex | ✅ | 24s | 171 | 47 |
| js-v1.x x python-v0.4 (ws, noise, yamux) | js-v1.x | python-v0.4 | ws | noise | yamux | ✅ | 25s | 210 | 63 |
| js-v1.x x python-v0.4 (wss, noise, mplex) | js-v1.x | python-v0.4 | wss | noise | mplex | ✅ | 25s | 294 | 54 |
| js-v1.x x js-v1.x (tcp, noise, mplex) | js-v1.x | js-v1.x | tcp | noise | mplex | ✅ | 25s | 214 | 64 |
| js-v1.x x python-v0.4 (wss, noise, yamux) | js-v1.x | python-v0.4 | wss | noise | yamux | ✅ | 25s | 333 | 73 |
| js-v1.x x js-v1.x (tcp, noise, yamux) | js-v1.x | js-v1.x | tcp | noise | yamux | ✅ | 25s | 100 | 29 |
| js-v1.x x js-v1.x (ws, noise, mplex) | js-v1.x | js-v1.x | ws | noise | mplex | ✅ | 25s | 124 | 35 |
| js-v1.x x js-v1.x (ws, noise, yamux) | js-v1.x | js-v1.x | ws | noise | yamux | ✅ | 32s | 665 | 130 |
| js-v1.x x js-v2.x (tcp, noise, mplex) | js-v1.x | js-v2.x | tcp | noise | mplex | ✅ | 35s | 306 | 105 |
| js-v1.x x js-v2.x (tcp, noise, yamux) | js-v1.x | js-v2.x | tcp | noise | yamux | ✅ | 35s | 329 | 122 |
| js-v1.x x js-v2.x (ws, noise, mplex) | js-v1.x | js-v2.x | ws | noise | mplex | ✅ | 36s | 236 | 65 |
| js-v1.x x js-v2.x (ws, noise, yamux) | js-v1.x | js-v2.x | ws | noise | yamux | ✅ | 36s | 233 | 77 |
| js-v1.x x js-v3.x (tcp, noise, mplex) | js-v1.x | js-v3.x | tcp | noise | mplex | ✅ | 36s | 169 | 56 |
| js-v1.x x js-v3.x (tcp, noise, yamux) | js-v1.x | js-v3.x | tcp | noise | yamux | ✅ | 35s | 164 | 43 |
| js-v1.x x js-v3.x (ws, noise, mplex) | js-v1.x | js-v3.x | ws | noise | mplex | ✅ | 34s | 198 | 71 |
| js-v1.x x js-v3.x (ws, noise, yamux) | js-v1.x | js-v3.x | ws | noise | yamux | ✅ | 24s | 269 | 84 |
| js-v1.x x nim-v1.14 (tcp, noise, mplex) | js-v1.x | nim-v1.14 | tcp | noise | mplex | ✅ | 22s | 265 | 59 |
| js-v1.x x nim-v1.14 (tcp, noise, yamux) | js-v1.x | nim-v1.14 | tcp | noise | yamux | ✅ | 23s | 254 | 48 |
| js-v1.x x nim-v1.14 (ws, noise, yamux) | js-v1.x | nim-v1.14 | ws | noise | yamux | ✅ | 23s | 270 | 36 |
| js-v1.x x nim-v1.14 (ws, noise, mplex) | js-v1.x | nim-v1.14 | ws | noise | mplex | ✅ | 24s | 233 | 30 |
| js-v1.x x jvm-v1.2 (tcp, noise, mplex) | js-v1.x | jvm-v1.2 | tcp | noise | mplex | ✅ | 23s | 876 | 103 |
| js-v1.x x jvm-v1.2 (tcp, noise, yamux) | js-v1.x | jvm-v1.2 | tcp | noise | yamux | ✅ | 24s | 907 | 70 |
| js-v1.x x jvm-v1.2 (ws, noise, mplex) | js-v1.x | jvm-v1.2 | ws | noise | mplex | ❌ | 28s | - | - |
| js-v1.x x c-v0.0.1 (tcp, noise, mplex) | js-v1.x | c-v0.0.1 | tcp | noise | mplex | ✅ | 19s | 130 | 30 |
| js-v1.x x c-v0.0.1 (tcp, noise, yamux) | js-v1.x | c-v0.0.1 | tcp | noise | yamux | ✅ | 19s | 179 | 96 |
| js-v1.x x dotnet-v1.0 (tcp, noise, yamux) | js-v1.x | dotnet-v1.0 | tcp | noise | yamux | ✅ | 19s | 321 | 108 |
| js-v1.x x jvm-v1.2 (ws, noise, yamux) | js-v1.x | jvm-v1.2 | ws | noise | yamux | ❌ | 24s | - | - |
| js-v2.x x rust-v0.53 (tcp, noise, mplex) | js-v2.x | rust-v0.53 | tcp | noise | mplex | ✅ | 20s | 177 | 56 |
| js-v2.x x rust-v0.53 (tcp, noise, yamux) | js-v2.x | rust-v0.53 | tcp | noise | yamux | ✅ | 20s | 149 | 38 |
| js-v2.x x rust-v0.53 (ws, noise, mplex) | js-v2.x | rust-v0.53 | ws | noise | mplex | ✅ | 20s | 302 | 67 |
| js-v2.x x rust-v0.53 (ws, noise, yamux) | js-v2.x | rust-v0.53 | ws | noise | yamux | ✅ | 18s | 327 | 86 |
| js-v2.x x rust-v0.54 (tcp, noise, mplex) | js-v2.x | rust-v0.54 | tcp | noise | mplex | ✅ | 21s | 190 | 42 |
| js-v2.x x rust-v0.54 (tcp, noise, yamux) | js-v2.x | rust-v0.54 | tcp | noise | yamux | ✅ | 21s | 251 | 51 |
| js-v2.x x rust-v0.54 (ws, noise, mplex) | js-v2.x | rust-v0.54 | ws | noise | mplex | ✅ | 21s | 355 | 90 |
| js-v2.x x rust-v0.54 (ws, noise, yamux) | js-v2.x | rust-v0.54 | ws | noise | yamux | ✅ | 21s | 351 | 88 |
| js-v2.x x rust-v0.55 (tcp, noise, mplex) | js-v2.x | rust-v0.55 | tcp | noise | mplex | ✅ | 21s | 125 | 45 |
| js-v2.x x rust-v0.55 (tcp, noise, yamux) | js-v2.x | rust-v0.55 | tcp | noise | yamux | ✅ | 21s | 127 | 43 |
| js-v2.x x rust-v0.55 (ws, noise, mplex) | js-v2.x | rust-v0.55 | ws | noise | mplex | ✅ | 21s | 141 | 42 |
| js-v2.x x rust-v0.55 (ws, noise, yamux) | js-v2.x | rust-v0.55 | ws | noise | yamux | ✅ | 19s | 165 | 61 |
| js-v2.x x rust-v0.56 (tcp, noise, mplex) | js-v2.x | rust-v0.56 | tcp | noise | mplex | ✅ | 22s | 189 | 47 |
| js-v2.x x rust-v0.56 (tcp, noise, yamux) | js-v2.x | rust-v0.56 | tcp | noise | yamux | ✅ | 21s | 192 | 49 |
| js-v2.x x rust-v0.56 (ws, noise, mplex) | js-v2.x | rust-v0.56 | ws | noise | mplex | ✅ | 22s | 193 | 42 |
| js-v2.x x rust-v0.56 (ws, noise, yamux) | js-v2.x | rust-v0.56 | ws | noise | yamux | ✅ | 22s | 184 | 58 |
| js-v2.x x go-v0.38 (tcp, noise, yamux) | js-v2.x | go-v0.38 | tcp | noise | yamux | ✅ | 21s | 138 | 45 |
| js-v2.x x go-v0.38 (ws, noise, yamux) | js-v2.x | go-v0.38 | ws | noise | yamux | ✅ | 22s | 121 | 46 |
| js-v2.x x go-v0.38 (wss, noise, yamux) | js-v2.x | go-v0.38 | wss | noise | yamux | ✅ | 21s | 183 | 27 |
| js-v2.x x go-v0.39 (tcp, noise, yamux) | js-v2.x | go-v0.39 | tcp | noise | yamux | ✅ | 19s | 105 | 46 |
| js-v2.x x go-v0.39 (ws, noise, yamux) | js-v2.x | go-v0.39 | ws | noise | yamux | ✅ | 22s | 254 | 65 |
| js-v2.x x go-v0.40 (tcp, noise, yamux) | js-v2.x | go-v0.40 | tcp | noise | yamux | ✅ | 22s | 194 | 70 |
| js-v2.x x go-v0.39 (wss, noise, yamux) | js-v2.x | go-v0.39 | wss | noise | yamux | ✅ | 23s | 271 | 53 |
| js-v2.x x go-v0.40 (ws, noise, yamux) | js-v2.x | go-v0.40 | ws | noise | yamux | ✅ | 23s | 148 | 45 |
| js-v2.x x go-v0.40 (wss, noise, yamux) | js-v2.x | go-v0.40 | wss | noise | yamux | ✅ | 22s | 236 | 43 |
| js-v2.x x go-v0.41 (tcp, noise, yamux) | js-v2.x | go-v0.41 | tcp | noise | yamux | ✅ | 22s | 95 | 32 |
| js-v2.x x go-v0.41 (ws, noise, yamux) | js-v2.x | go-v0.41 | ws | noise | yamux | ✅ | 22s | 107 | 35 |
| js-v2.x x go-v0.41 (wss, noise, yamux) | js-v2.x | go-v0.41 | wss | noise | yamux | ✅ | 21s | 162 | 39 |
| js-v2.x x go-v0.42 (tcp, noise, yamux) | js-v2.x | go-v0.42 | tcp | noise | yamux | ✅ | 22s | 165 | 65 |
| js-v2.x x go-v0.42 (ws, noise, yamux) | js-v2.x | go-v0.42 | ws | noise | yamux | ✅ | 22s | 166 | 55 |
| js-v2.x x go-v0.42 (wss, noise, yamux) | js-v2.x | go-v0.42 | wss | noise | yamux | ✅ | 22s | 273 | 66 |
| js-v2.x x go-v0.43 (ws, noise, yamux) | js-v2.x | go-v0.43 | ws | noise | yamux | ✅ | 22s | 182 | 55 |
| js-v2.x x go-v0.43 (tcp, noise, yamux) | js-v2.x | go-v0.43 | tcp | noise | yamux | ✅ | 23s | 123 | 43 |
| js-v2.x x go-v0.43 (wss, noise, yamux) | js-v2.x | go-v0.43 | wss | noise | yamux | ✅ | 22s | 190 | 39 |
| js-v2.x x go-v0.44 (tcp, noise, yamux) | js-v2.x | go-v0.44 | tcp | noise | yamux | ✅ | 22s | 97 | 32 |
| js-v2.x x go-v0.44 (ws, noise, yamux) | js-v2.x | go-v0.44 | ws | noise | yamux | ✅ | 21s | 106 | 31 |
| js-v2.x x go-v0.44 (wss, noise, yamux) | js-v2.x | go-v0.44 | wss | noise | yamux | ✅ | 23s | 266 | 56 |
| js-v2.x x go-v0.45 (tcp, noise, yamux) | js-v2.x | go-v0.45 | tcp | noise | yamux | ✅ | 23s | 169 | 64 |
| js-v2.x x go-v0.45 (ws, noise, yamux) | js-v2.x | go-v0.45 | ws | noise | yamux | ✅ | 23s | 164 | 49 |
| js-v2.x x go-v0.45 (wss, noise, yamux) | js-v2.x | go-v0.45 | wss | noise | yamux | ✅ | 23s | 216 | 44 |
| js-v2.x x python-v0.4 (tcp, noise, mplex) | js-v2.x | python-v0.4 | tcp | noise | mplex | ✅ | 23s | 123 | 37 |
| js-v2.x x python-v0.4 (tcp, noise, yamux) | js-v2.x | python-v0.4 | tcp | noise | yamux | ✅ | 23s | 115 | 44 |
| js-v2.x x python-v0.4 (ws, noise, mplex) | js-v2.x | python-v0.4 | ws | noise | mplex | ✅ | 23s | 118 | 37 |
| js-v2.x x python-v0.4 (ws, noise, yamux) | js-v2.x | python-v0.4 | ws | noise | yamux | ✅ | 23s | 110 | 27 |
| js-v2.x x python-v0.4 (wss, noise, mplex) | js-v2.x | python-v0.4 | wss | noise | mplex | ✅ | 34s | 361 | 60 |
| js-v2.x x python-v0.4 (wss, noise, yamux) | js-v2.x | python-v0.4 | wss | noise | yamux | ✅ | 35s | 494 | 74 |
| js-v2.x x js-v1.x (tcp, noise, mplex) | js-v2.x | js-v1.x | tcp | noise | mplex | ✅ | 36s | 269 | 107 |
| js-v2.x x js-v1.x (ws, noise, mplex) | js-v2.x | js-v1.x | ws | noise | mplex | ✅ | 36s | 257 | 90 |
| js-v2.x x js-v1.x (tcp, noise, yamux) | js-v2.x | js-v1.x | tcp | noise | yamux | ✅ | 36s | 297 | 91 |
| js-v2.x x js-v1.x (ws, noise, yamux) | js-v2.x | js-v1.x | ws | noise | yamux | ✅ | 36s | 215 | 52 |
| js-v2.x x js-v2.x (tcp, noise, mplex) | js-v2.x | js-v2.x | tcp | noise | mplex | ✅ | 35s | 112 | 41 |
| js-v2.x x js-v2.x (tcp, noise, yamux) | js-v2.x | js-v2.x | tcp | noise | yamux | ✅ | 35s | 125 | 40 |
| js-v2.x x js-v2.x (ws, noise, mplex) | js-v2.x | js-v2.x | ws | noise | mplex | ✅ | 37s | 296 | 91 |
| js-v2.x x js-v2.x (ws, noise, yamux) | js-v2.x | js-v2.x | ws | noise | yamux | ✅ | 37s | 360 | 139 |
| js-v2.x x js-v3.x (tcp, noise, yamux) | js-v2.x | js-v3.x | tcp | noise | yamux | ✅ | 36s | 172 | 59 |
| js-v2.x x js-v3.x (tcp, noise, mplex) | js-v2.x | js-v3.x | tcp | noise | mplex | ✅ | 36s | 254 | 120 |
| js-v2.x x js-v3.x (ws, noise, mplex) | js-v2.x | js-v3.x | ws | noise | mplex | ✅ | 36s | 230 | 94 |
| js-v2.x x nim-v1.14 (tcp, noise, mplex) | js-v2.x | nim-v1.14 | tcp | noise | mplex | ✅ | 35s | 208 | 30 |
| js-v2.x x js-v3.x (ws, noise, yamux) | js-v2.x | js-v3.x | ws | noise | yamux | ✅ | 36s | 159 | 47 |
| js-v2.x x nim-v1.14 (tcp, noise, yamux) | js-v2.x | nim-v1.14 | tcp | noise | yamux | ✅ | 34s | 195 | 40 |
| js-v2.x x nim-v1.14 (ws, noise, mplex) | js-v2.x | nim-v1.14 | ws | noise | mplex | ✅ | 26s | 323 | 44 |
| js-v2.x x nim-v1.14 (ws, noise, yamux) | js-v2.x | nim-v1.14 | ws | noise | yamux | ✅ | 26s | 339 | 59 |
| js-v2.x x jvm-v1.2 (tcp, noise, mplex) | js-v2.x | jvm-v1.2 | tcp | noise | mplex | ✅ | 27s | 1161 | 126 |
| js-v2.x x c-v0.0.1 (tcp, noise, mplex) | js-v2.x | c-v0.0.1 | tcp | noise | mplex | ✅ | 26s | 104 | 9 |
| js-v2.x x jvm-v1.2 (tcp, noise, yamux) | js-v2.x | jvm-v1.2 | tcp | noise | yamux | ✅ | 28s | 1221 | 133 |
| js-v2.x x c-v0.0.1 (tcp, noise, yamux) | js-v2.x | c-v0.0.1 | tcp | noise | yamux | ✅ | 25s | 184 | 85 |
| js-v2.x x jvm-v1.2 (ws, noise, mplex) | js-v2.x | jvm-v1.2 | ws | noise | mplex | ✅ | 28s | 1593 | 179 |
| js-v2.x x jvm-v1.2 (ws, noise, yamux) | js-v2.x | jvm-v1.2 | ws | noise | yamux | ✅ | 28s | 979 | 114 |
| js-v2.x x dotnet-v1.0 (tcp, noise, yamux) | js-v2.x | dotnet-v1.0 | tcp | noise | yamux | ✅ | 22s | 496 | 118 |
| js-v3.x x rust-v0.53 (tcp, noise, mplex) | js-v3.x | rust-v0.53 | tcp | noise | mplex | ✅ | 22s | 160 | 5 |
| js-v3.x x rust-v0.53 (tcp, noise, yamux) | js-v3.x | rust-v0.53 | tcp | noise | yamux | ✅ | 21s | 161 | 4 |
| js-v3.x x rust-v0.53 (ws, noise, mplex) | js-v3.x | rust-v0.53 | ws | noise | mplex | ✅ | 22s | 224 | 6 |
| js-v3.x x rust-v0.54 (tcp, noise, mplex) | js-v3.x | rust-v0.54 | tcp | noise | mplex | ✅ | 22s | 154 | 5 |
| js-v3.x x rust-v0.53 (ws, noise, yamux) | js-v3.x | rust-v0.53 | ws | noise | yamux | ✅ | 23s | 213 | 5 |
| js-v3.x x rust-v0.54 (ws, noise, mplex) | js-v3.x | rust-v0.54 | ws | noise | mplex | ✅ | 22s | 181 | 3 |
| js-v3.x x rust-v0.54 (tcp, noise, yamux) | js-v3.x | rust-v0.54 | tcp | noise | yamux | ✅ | 23s | 136 | 3 |
| js-v3.x x rust-v0.54 (ws, noise, yamux) | js-v3.x | rust-v0.54 | ws | noise | yamux | ✅ | 21s | 280 | 6 |
| js-v3.x x rust-v0.55 (tcp, noise, mplex) | js-v3.x | rust-v0.55 | tcp | noise | mplex | ✅ | 21s | 113 | 16 |
| js-v3.x x rust-v0.55 (tcp, noise, yamux) | js-v3.x | rust-v0.55 | tcp | noise | yamux | ✅ | 22s | 135 | 15 |
| js-v3.x x rust-v0.55 (ws, noise, mplex) | js-v3.x | rust-v0.55 | ws | noise | mplex | ✅ | 21s | 128 | 17 |
| js-v3.x x rust-v0.55 (ws, noise, yamux) | js-v3.x | rust-v0.55 | ws | noise | yamux | ✅ | 22s | 152 | 18 |
| js-v3.x x rust-v0.56 (tcp, noise, mplex) | js-v3.x | rust-v0.56 | tcp | noise | mplex | ✅ | 21s | 120 | 18 |
| js-v3.x x rust-v0.56 (tcp, noise, yamux) | js-v3.x | rust-v0.56 | tcp | noise | yamux | ✅ | 21s | 82 | 13 |
| js-v3.x x rust-v0.56 (ws, noise, mplex) | js-v3.x | rust-v0.56 | ws | noise | mplex | ✅ | 21s | 95 | 16 |
| js-v3.x x rust-v0.56 (ws, noise, yamux) | js-v3.x | rust-v0.56 | ws | noise | yamux | ✅ | 21s | 185 | 13 |
| js-v3.x x go-v0.38 (tcp, noise, yamux) | js-v3.x | go-v0.38 | tcp | noise | yamux | ✅ | 22s | 164 | 17 |
| js-v3.x x go-v0.38 (ws, noise, yamux) | js-v3.x | go-v0.38 | ws | noise | yamux | ✅ | 22s | 159 | 3 |
| js-v3.x x go-v0.38 (wss, noise, yamux) | js-v3.x | go-v0.38 | wss | noise | yamux | ✅ | 22s | 223 | 20 |
| js-v3.x x go-v0.39 (tcp, noise, yamux) | js-v3.x | go-v0.39 | tcp | noise | yamux | ✅ | 23s | 130 | 13 |
| js-v3.x x go-v0.39 (ws, noise, yamux) | js-v3.x | go-v0.39 | ws | noise | yamux | ✅ | 22s | 127 | 14 |
| js-v3.x x go-v0.39 (wss, noise, yamux) | js-v3.x | go-v0.39 | wss | noise | yamux | ✅ | 22s | 215 | 20 |
| js-v3.x x go-v0.40 (tcp, noise, yamux) | js-v3.x | go-v0.40 | tcp | noise | yamux | ✅ | 22s | 106 | 2 |
| js-v3.x x go-v0.40 (ws, noise, yamux) | js-v3.x | go-v0.40 | ws | noise | yamux | ✅ | 22s | 187 | 15 |
| js-v3.x x go-v0.40 (wss, noise, yamux) | js-v3.x | go-v0.40 | wss | noise | yamux | ✅ | 22s | 268 | 30 |
| js-v3.x x go-v0.41 (tcp, noise, yamux) | js-v3.x | go-v0.41 | tcp | noise | yamux | ✅ | 22s | 146 | 13 |
| js-v3.x x go-v0.41 (ws, noise, yamux) | js-v3.x | go-v0.41 | ws | noise | yamux | ✅ | 22s | 130 | 10 |
| js-v3.x x go-v0.41 (wss, noise, yamux) | js-v3.x | go-v0.41 | wss | noise | yamux | ✅ | 22s | 187 | 23 |
| js-v3.x x go-v0.42 (tcp, noise, yamux) | js-v3.x | go-v0.42 | tcp | noise | yamux | ✅ | 21s | 126 | 1 |
| js-v3.x x go-v0.42 (ws, noise, yamux) | js-v3.x | go-v0.42 | ws | noise | yamux | ✅ | 21s | 98 | 11 |
| js-v3.x x go-v0.42 (wss, noise, yamux) | js-v3.x | go-v0.42 | wss | noise | yamux | ✅ | 22s | 153 | 18 |
| js-v3.x x go-v0.43 (tcp, noise, yamux) | js-v3.x | go-v0.43 | tcp | noise | yamux | ✅ | 23s | 142 | 13 |
| js-v3.x x go-v0.43 (ws, noise, yamux) | js-v3.x | go-v0.43 | ws | noise | yamux | ✅ | 22s | 154 | 16 |
| js-v3.x x go-v0.43 (wss, noise, yamux) | js-v3.x | go-v0.43 | wss | noise | yamux | ✅ | 23s | 241 | 19 |
| js-v3.x x go-v0.44 (tcp, noise, yamux) | js-v3.x | go-v0.44 | tcp | noise | yamux | ✅ | 22s | 133 | 16 |
| js-v3.x x go-v0.44 (ws, noise, yamux) | js-v3.x | go-v0.44 | ws | noise | yamux | ✅ | 22s | 150 | 2 |
| js-v3.x x go-v0.44 (wss, noise, yamux) | js-v3.x | go-v0.44 | wss | noise | yamux | ✅ | 22s | 195 | 13 |
| js-v3.x x go-v0.45 (tcp, noise, yamux) | js-v3.x | go-v0.45 | tcp | noise | yamux | ✅ | 21s | 116 | 12 |
| js-v3.x x go-v0.45 (ws, noise, yamux) | js-v3.x | go-v0.45 | ws | noise | yamux | ✅ | 21s | 117 | 10 |
| js-v3.x x python-v0.4 (tcp, noise, mplex) | js-v3.x | python-v0.4 | tcp | noise | mplex | ✅ | 23s | 134 | 9 |
| js-v3.x x go-v0.45 (wss, noise, yamux) | js-v3.x | go-v0.45 | wss | noise | yamux | ✅ | 25s | 278 | 2 |
| js-v3.x x python-v0.4 (ws, noise, mplex) | js-v3.x | python-v0.4 | ws | noise | mplex | ✅ | 24s | 188 | 3 |
| js-v3.x x python-v0.4 (tcp, noise, yamux) | js-v3.x | python-v0.4 | tcp | noise | yamux | ✅ | 26s | 146 | 3 |
| js-v3.x x python-v0.4 (wss, noise, mplex) | js-v3.x | python-v0.4 | wss | noise | mplex | ✅ | 24s | 244 | 5 |
| js-v3.x x python-v0.4 (ws, noise, yamux) | js-v3.x | python-v0.4 | ws | noise | yamux | ✅ | 26s | 158 | 4 |
| js-v3.x x python-v0.4 (wss, noise, yamux) | js-v3.x | python-v0.4 | wss | noise | yamux | ✅ | 25s | 230 | 6 |
| js-v3.x x js-v1.x (tcp, noise, mplex) | js-v3.x | js-v1.x | tcp | noise | mplex | ✅ | 25s | 155 | 8 |
| js-v3.x x js-v1.x (tcp, noise, yamux) | js-v3.x | js-v1.x | tcp | noise | yamux | ✅ | 37s | 402 | 18 |
| js-v3.x x js-v1.x (ws, noise, mplex) | js-v3.x | js-v1.x | ws | noise | mplex | ✅ | 40s | 321 | 16 |
| js-v3.x x js-v1.x (ws, noise, yamux) | js-v3.x | js-v1.x | ws | noise | yamux | ✅ | 41s | 274 | 9 |
| js-v3.x x js-v2.x (tcp, noise, yamux) | js-v3.x | js-v2.x | tcp | noise | yamux | ✅ | 40s | 239 | 4 |
| js-v3.x x js-v2.x (tcp, noise, mplex) | js-v3.x | js-v2.x | tcp | noise | mplex | ✅ | 42s | 194 | 19 |
| js-v3.x x js-v2.x (ws, noise, mplex) | js-v3.x | js-v2.x | ws | noise | mplex | ✅ | 41s | 208 | 5 |
| js-v3.x x js-v2.x (ws, noise, yamux) | js-v3.x | js-v2.x | ws | noise | yamux | ✅ | 40s | 218 | 2 |
| js-v3.x x js-v3.x (tcp, noise, mplex) | js-v3.x | js-v3.x | tcp | noise | mplex | ✅ | 40s | 124 | 11 |
| js-v3.x x js-v3.x (tcp, noise, yamux) | js-v3.x | js-v3.x | tcp | noise | yamux | ✅ | 28s | 243 | 13 |
| js-v3.x x js-v3.x (ws, noise, mplex) | js-v3.x | js-v3.x | ws | noise | mplex | ✅ | 29s | 210 | 33 |
| js-v3.x x js-v3.x (ws, noise, yamux) | js-v3.x | js-v3.x | ws | noise | yamux | ✅ | 29s | 195 | 9 |
| js-v3.x x nim-v1.14 (tcp, noise, mplex) | js-v3.x | nim-v1.14 | tcp | noise | mplex | ✅ | 29s | 230 | 5 |
| js-v3.x x nim-v1.14 (ws, noise, mplex) | js-v3.x | nim-v1.14 | ws | noise | mplex | ✅ | 28s | 264 | 5 |
| js-v3.x x nim-v1.14 (tcp, noise, yamux) | js-v3.x | nim-v1.14 | tcp | noise | yamux | ✅ | 30s | 187 | 5 |
| js-v3.x x nim-v1.14 (ws, noise, yamux) | js-v3.x | nim-v1.14 | ws | noise | yamux | ✅ | 29s | 197 | 5 |
| js-v3.x x jvm-v1.2 (tcp, noise, mplex) | js-v3.x | jvm-v1.2 | tcp | noise | mplex | ✅ | 29s | 810 | 3 |
| nim-v1.14 x rust-v0.53 (tcp, noise, mplex) | nim-v1.14 | rust-v0.53 | tcp | noise | mplex | ✅ | 6s | 294.0 | 1.0 |
| nim-v1.14 x rust-v0.53 (tcp, noise, yamux) | nim-v1.14 | rust-v0.53 | tcp | noise | yamux | ✅ | 5s | 322.0 | 0.0 |
| nim-v1.14 x rust-v0.53 (ws, noise, mplex) | nim-v1.14 | rust-v0.53 | ws | noise | mplex | ✅ | 6s | 468.0 | 44.0 |
| nim-v1.14 x rust-v0.53 (ws, noise, yamux) | nim-v1.14 | rust-v0.53 | ws | noise | yamux | ✅ | 5s | 465.0 | 47.0 |
| js-v3.x x jvm-v1.2 (tcp, noise, yamux) | js-v3.x | jvm-v1.2 | tcp | noise | yamux | ✅ | 25s | 1490 | 52 |
| js-v3.x x c-v0.0.1 (tcp, noise, mplex) | js-v3.x | c-v0.0.1 | tcp | noise | mplex | ✅ | 23s | 118 | 2 |
| js-v3.x x jvm-v1.2 (ws, noise, mplex) | js-v3.x | jvm-v1.2 | ws | noise | mplex | ✅ | 24s | 1494 | 12 |
| js-v3.x x jvm-v1.2 (ws, noise, yamux) | js-v3.x | jvm-v1.2 | ws | noise | yamux | ✅ | 24s | 1688 | 119 |
| js-v3.x x c-v0.0.1 (tcp, noise, yamux) | js-v3.x | c-v0.0.1 | tcp | noise | yamux | ✅ | 22s | 96 | 3 |
| nim-v1.14 x rust-v0.54 (tcp, noise, mplex) | nim-v1.14 | rust-v0.54 | tcp | noise | mplex | ✅ | 6s | 267.0 | 0.0 |
| js-v3.x x dotnet-v1.0 (tcp, noise, yamux) | js-v3.x | dotnet-v1.0 | tcp | noise | yamux | ✅ | 22s | 257 | 4 |
| nim-v1.14 x rust-v0.54 (tcp, noise, yamux) | nim-v1.14 | rust-v0.54 | tcp | noise | yamux | ✅ | 6s | 320.0 | 0.0 |
| nim-v1.14 x rust-v0.54 (ws, noise, mplex) | nim-v1.14 | rust-v0.54 | ws | noise | mplex | ✅ | 4s | 458.0 | 47.0 |
| nim-v1.14 x rust-v0.54 (ws, noise, yamux) | nim-v1.14 | rust-v0.54 | ws | noise | yamux | ✅ | 5s | 450.0 | 43.0 |
| nim-v1.14 x rust-v0.55 (tcp, noise, mplex) | nim-v1.14 | rust-v0.55 | tcp | noise | mplex | ✅ | 5s | 187.0 | 0.0 |
| nim-v1.14 x rust-v0.55 (tcp, noise, yamux) | nim-v1.14 | rust-v0.55 | tcp | noise | yamux | ✅ | 5s | 183.0 | 0.0 |
| nim-v1.14 x rust-v0.55 (ws, noise, mplex) | nim-v1.14 | rust-v0.55 | ws | noise | mplex | ✅ | 5s | 182.0 | 42.0 |
| nim-v1.14 x rust-v0.56 (tcp, noise, mplex) | nim-v1.14 | rust-v0.56 | tcp | noise | mplex | ✅ | 5s | 191.0 | 1.0 |
| nim-v1.14 x rust-v0.55 (ws, noise, yamux) | nim-v1.14 | rust-v0.55 | ws | noise | yamux | ✅ | 6s | 183.0 | 0.0 |
| nim-v1.14 x rust-v0.56 (tcp, noise, yamux) | nim-v1.14 | rust-v0.56 | tcp | noise | yamux | ✅ | 6s | 183.0 | 0.0 |
| nim-v1.14 x rust-v0.56 (ws, noise, mplex) | nim-v1.14 | rust-v0.56 | ws | noise | mplex | ✅ | 5s | 196.0 | 0.0 |
| nim-v1.14 x rust-v0.56 (ws, noise, yamux) | nim-v1.14 | rust-v0.56 | ws | noise | yamux | ✅ | 6s | 186.0 | 41.0 |
| nim-v1.14 x go-v0.38 (tcp, noise, yamux) | nim-v1.14 | go-v0.38 | tcp | noise | yamux | ✅ | 5s | 156.0 | 0.0 |
| nim-v1.14 x go-v0.38 (ws, noise, yamux) | nim-v1.14 | go-v0.38 | ws | noise | yamux | ✅ | 4s | 183.0 | 0.0 |
| nim-v1.14 x go-v0.39 (tcp, noise, yamux) | nim-v1.14 | go-v0.39 | tcp | noise | yamux | ✅ | 5s | 147.0 | 1.0 |
| nim-v1.14 x go-v0.39 (ws, noise, yamux) | nim-v1.14 | go-v0.39 | ws | noise | yamux | ✅ | 5s | 240.0 | 0.0 |
| nim-v1.14 x go-v0.40 (ws, noise, yamux) | nim-v1.14 | go-v0.40 | ws | noise | yamux | ✅ | 5s | 256.0 | 0.0 |
| nim-v1.14 x go-v0.40 (tcp, noise, yamux) | nim-v1.14 | go-v0.40 | tcp | noise | yamux | ✅ | 5s | 192.0 | 0.0 |
| nim-v1.14 x go-v0.41 (tcp, noise, yamux) | nim-v1.14 | go-v0.41 | tcp | noise | yamux | ✅ | 5s | 202.0 | 2.0 |
| nim-v1.14 x go-v0.41 (ws, noise, yamux) | nim-v1.14 | go-v0.41 | ws | noise | yamux | ✅ | 5s | 187.0 | 0.0 |
| nim-v1.14 x go-v0.42 (tcp, noise, yamux) | nim-v1.14 | go-v0.42 | tcp | noise | yamux | ✅ | 4s | 158.0 | 2.0 |
| nim-v1.14 x go-v0.42 (ws, noise, yamux) | nim-v1.14 | go-v0.42 | ws | noise | yamux | ✅ | 5s | 206.0 | 0.0 |
| nim-v1.14 x go-v0.43 (tcp, noise, yamux) | nim-v1.14 | go-v0.43 | tcp | noise | yamux | ✅ | 5s | 202.0 | 0.0 |
| nim-v1.14 x go-v0.44 (tcp, noise, yamux) | nim-v1.14 | go-v0.44 | tcp | noise | yamux | ✅ | 4s | 202.0 | 0.0 |
| nim-v1.14 x go-v0.43 (ws, noise, yamux) | nim-v1.14 | go-v0.43 | ws | noise | yamux | ✅ | 6s | 198.0 | 0.0 |
| nim-v1.14 x go-v0.44 (ws, noise, yamux) | nim-v1.14 | go-v0.44 | ws | noise | yamux | ✅ | 5s | 266.0 | 0.0 |
| nim-v1.14 x go-v0.45 (tcp, noise, yamux) | nim-v1.14 | go-v0.45 | tcp | noise | yamux | ✅ | 5s | 186.0 | 0.0 |
| nim-v1.14 x go-v0.45 (ws, noise, yamux) | nim-v1.14 | go-v0.45 | ws | noise | yamux | ✅ | 6s | 260.0 | 0.0 |
| nim-v1.14 x python-v0.4 (tcp, noise, mplex) | nim-v1.14 | python-v0.4 | tcp | noise | mplex | ✅ | 6s | 184.0 | 1.0 |
| nim-v1.14 x python-v0.4 (ws, noise, mplex) | nim-v1.14 | python-v0.4 | ws | noise | mplex | ✅ | 6s | 209.0 | 1.0 |
| nim-v1.14 x python-v0.4 (tcp, noise, yamux) | nim-v1.14 | python-v0.4 | tcp | noise | yamux | ✅ | 6s | 172.0 | 1.0 |
| nim-v1.14 x python-v0.4 (ws, noise, yamux) | nim-v1.14 | python-v0.4 | ws | noise | yamux | ✅ | 5s | 214.0 | 1.0 |
| nim-v1.14 x js-v1.x (tcp, noise, mplex) | nim-v1.14 | js-v1.x | tcp | noise | mplex | ✅ | 19s | 315.0 | 14.0 |
| nim-v1.14 x js-v1.x (tcp, noise, yamux) | nim-v1.14 | js-v1.x | tcp | noise | yamux | ✅ | 21s | 305.0 | 1.0 |
| nim-v1.14 x js-v1.x (ws, noise, mplex) | nim-v1.14 | js-v1.x | ws | noise | mplex | ✅ | 21s | 302.0 | 1.0 |
| nim-v1.14 x js-v1.x (ws, noise, yamux) | nim-v1.14 | js-v1.x | ws | noise | yamux | ✅ | 20s | 323.0 | 4.0 |
| nim-v1.14 x js-v2.x (tcp, noise, mplex) | nim-v1.14 | js-v2.x | tcp | noise | mplex | ✅ | 22s | 272.0 | 1.0 |
| nim-v1.14 x js-v2.x (tcp, noise, yamux) | nim-v1.14 | js-v2.x | tcp | noise | yamux | ✅ | 21s | 296.0 | 5.0 |
| nim-v1.14 x js-v2.x (ws, noise, yamux) | nim-v1.14 | js-v2.x | ws | noise | yamux | ✅ | 21s | 252.0 | 2.0 |
| nim-v1.14 x js-v2.x (ws, noise, mplex) | nim-v1.14 | js-v2.x | ws | noise | mplex | ✅ | 23s | 246.0 | 2.0 |
| nim-v1.14 x nim-v1.14 (tcp, noise, mplex) | nim-v1.14 | nim-v1.14 | tcp | noise | mplex | ✅ | 6s | 388.0 | 3.0 |
| nim-v1.14 x nim-v1.14 (tcp, noise, yamux) | nim-v1.14 | nim-v1.14 | tcp | noise | yamux | ✅ | 5s | 389.0 | 0.0 |
| nim-v1.14 x nim-v1.14 (ws, noise, mplex) | nim-v1.14 | nim-v1.14 | ws | noise | mplex | ✅ | 6s | 391.0 | 1.0 |
| nim-v1.14 x nim-v1.14 (ws, noise, yamux) | nim-v1.14 | nim-v1.14 | ws | noise | yamux | ✅ | 5s | 404.0 | 1.0 |
| nim-v1.14 x js-v3.x (tcp, noise, mplex) | nim-v1.14 | js-v3.x | tcp | noise | mplex | ✅ | 18s | 285.0 | 9.0 |
| nim-v1.14 x js-v3.x (tcp, noise, yamux) | nim-v1.14 | js-v3.x | tcp | noise | yamux | ✅ | 18s | 309.0 | 5.0 |
| nim-v1.14 x js-v3.x (ws, noise, mplex) | nim-v1.14 | js-v3.x | ws | noise | mplex | ✅ | 19s | 345.0 | 10.0 |
| nim-v1.14 x jvm-v1.2 (tcp, noise, mplex) | nim-v1.14 | jvm-v1.2 | tcp | noise | mplex | ✅ | 11s | 1348.0 | 5.0 |
| nim-v1.14 x jvm-v1.2 (tcp, noise, yamux) | nim-v1.14 | jvm-v1.2 | tcp | noise | yamux | ✅ | 10s | 1226.0 | 2.0 |
| nim-v1.14 x js-v3.x (ws, noise, yamux) | nim-v1.14 | js-v3.x | ws | noise | yamux | ✅ | 21s | 317.0 | 8.0 |
| nim-v1.14 x c-v0.0.1 (tcp, noise, mplex) | nim-v1.14 | c-v0.0.1 | tcp | noise | mplex | ✅ | 5s | 202.0 | 0.0 |
| nim-v1.14 x jvm-v1.2 (ws, noise, mplex) | nim-v1.14 | jvm-v1.2 | ws | noise | mplex | ✅ | 11s | 1090.0 | 3.0 |
| nim-v1.14 x jvm-v1.2 (ws, noise, yamux) | nim-v1.14 | jvm-v1.2 | ws | noise | yamux | ✅ | 10s | 1036.0 | 1.0 |
| nim-v1.14 x c-v0.0.1 (tcp, noise, yamux) | nim-v1.14 | c-v0.0.1 | tcp | noise | yamux | ✅ | 5s | 286.0 | 0.0 |
| nim-v1.14 x dotnet-v1.0 (tcp, noise, yamux) | nim-v1.14 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 5s | 428.0 | 6.0 |
| jvm-v1.2 x rust-v0.53 (tcp, tls, mplex) | jvm-v1.2 | rust-v0.53 | tcp | tls | mplex | ✅ | 15s | - | - |
| jvm-v1.2 x rust-v0.53 (tcp, noise, yamux) | jvm-v1.2 | rust-v0.53 | tcp | noise | yamux | ✅ | 14s | - | - |
| jvm-v1.2 x rust-v0.53 (tcp, noise, mplex) | jvm-v1.2 | rust-v0.53 | tcp | noise | mplex | ✅ | 16s | - | - |
| jvm-v1.2 x rust-v0.53 (tcp, tls, yamux) | jvm-v1.2 | rust-v0.53 | tcp | tls | yamux | ✅ | 16s | - | - |
| jvm-v1.2 x rust-v0.53 (ws, noise, mplex) | jvm-v1.2 | rust-v0.53 | ws | noise | mplex | ✅ | 16s | - | - |
| jvm-v1.2 x rust-v0.53 (ws, tls, mplex) | jvm-v1.2 | rust-v0.53 | ws | tls | mplex | ✅ | 19s | - | - |
| jvm-v1.2 x rust-v0.53 (ws, tls, yamux) | jvm-v1.2 | rust-v0.53 | ws | tls | yamux | ✅ | 18s | - | - |
| jvm-v1.2 x rust-v0.53 (ws, noise, yamux) | jvm-v1.2 | rust-v0.53 | ws | noise | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x rust-v0.53 (quic-v1) | jvm-v1.2 | rust-v0.53 | quic-v1 | - | - | ✅ | 12s | - | - |
| jvm-v1.2 x rust-v0.54 (tcp, tls, mplex) | jvm-v1.2 | rust-v0.54 | tcp | tls | mplex | ✅ | 14s | - | - |
| jvm-v1.2 x rust-v0.54 (tcp, noise, mplex) | jvm-v1.2 | rust-v0.54 | tcp | noise | mplex | ✅ | 14s | - | - |
| jvm-v1.2 x rust-v0.54 (tcp, tls, yamux) | jvm-v1.2 | rust-v0.54 | tcp | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x rust-v0.54 (tcp, noise, yamux) | jvm-v1.2 | rust-v0.54 | tcp | noise | yamux | ✅ | 12s | - | - |
| jvm-v1.2 x rust-v0.54 (ws, noise, mplex) | jvm-v1.2 | rust-v0.54 | ws | noise | mplex | ✅ | 12s | - | - |
| jvm-v1.2 x rust-v0.54 (ws, tls, mplex) | jvm-v1.2 | rust-v0.54 | ws | tls | mplex | ✅ | 15s | - | - |
| jvm-v1.2 x rust-v0.54 (ws, tls, yamux) | jvm-v1.2 | rust-v0.54 | ws | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x rust-v0.54 (ws, noise, yamux) | jvm-v1.2 | rust-v0.54 | ws | noise | yamux | ✅ | 11s | - | - |
| jvm-v1.2 x rust-v0.54 (quic-v1) | jvm-v1.2 | rust-v0.54 | quic-v1 | - | - | ✅ | 13s | - | - |
| jvm-v1.2 x rust-v0.55 (tcp, noise, mplex) | jvm-v1.2 | rust-v0.55 | tcp | noise | mplex | ✅ | 13s | - | - |
| jvm-v1.2 x rust-v0.55 (tcp, tls, yamux) | jvm-v1.2 | rust-v0.55 | tcp | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x rust-v0.55 (tcp, tls, mplex) | jvm-v1.2 | rust-v0.55 | tcp | tls | mplex | ✅ | 16s | - | - |
| jvm-v1.2 x rust-v0.55 (tcp, noise, yamux) | jvm-v1.2 | rust-v0.55 | tcp | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x rust-v0.55 (ws, tls, mplex) | jvm-v1.2 | rust-v0.55 | ws | tls | mplex | ✅ | 15s | - | - |
| jvm-v1.2 x rust-v0.55 (ws, tls, yamux) | jvm-v1.2 | rust-v0.55 | ws | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x rust-v0.55 (ws, noise, mplex) | jvm-v1.2 | rust-v0.55 | ws | noise | mplex | ✅ | 13s | - | - |
| jvm-v1.2 x rust-v0.55 (ws, noise, yamux) | jvm-v1.2 | rust-v0.55 | ws | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x rust-v0.55 (quic-v1) | jvm-v1.2 | rust-v0.55 | quic-v1 | - | - | ✅ | 14s | - | - |
| jvm-v1.2 x rust-v0.56 (tcp, tls, mplex) | jvm-v1.2 | rust-v0.56 | tcp | tls | mplex | ✅ | 15s | - | - |
| jvm-v1.2 x rust-v0.56 (tcp, noise, mplex) | jvm-v1.2 | rust-v0.56 | tcp | noise | mplex | ✅ | 13s | - | - |
| jvm-v1.2 x rust-v0.56 (tcp, tls, yamux) | jvm-v1.2 | rust-v0.56 | tcp | tls | yamux | ✅ | 16s | - | - |
| jvm-v1.2 x rust-v0.56 (tcp, noise, yamux) | jvm-v1.2 | rust-v0.56 | tcp | noise | yamux | ✅ | 12s | - | - |
| jvm-v1.2 x rust-v0.56 (ws, tls, mplex) | jvm-v1.2 | rust-v0.56 | ws | tls | mplex | ✅ | 14s | - | - |
| jvm-v1.2 x rust-v0.56 (ws, tls, yamux) | jvm-v1.2 | rust-v0.56 | ws | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x rust-v0.56 (ws, noise, mplex) | jvm-v1.2 | rust-v0.56 | ws | noise | mplex | ✅ | 13s | - | - |
| jvm-v1.2 x rust-v0.56 (ws, noise, yamux) | jvm-v1.2 | rust-v0.56 | ws | noise | yamux | ✅ | 12s | - | - |
| jvm-v1.2 x go-v0.38 (tcp, noise, yamux) | jvm-v1.2 | go-v0.38 | tcp | noise | yamux | ✅ | 12s | - | - |
| jvm-v1.2 x rust-v0.56 (quic-v1) | jvm-v1.2 | rust-v0.56 | quic-v1 | - | - | ✅ | 14s | - | - |
| jvm-v1.2 x go-v0.38 (tcp, tls, yamux) | jvm-v1.2 | go-v0.38 | tcp | tls | yamux | ✅ | 14s | - | - |
| jvm-v1.2 x go-v0.38 (ws, tls, yamux) | jvm-v1.2 | go-v0.38 | ws | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.38 (ws, noise, yamux) | jvm-v1.2 | go-v0.38 | ws | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x go-v0.38 (quic-v1) | jvm-v1.2 | go-v0.38 | quic-v1 | - | - | ✅ | 14s | - | - |
| jvm-v1.2 x go-v0.39 (tcp, tls, yamux) | jvm-v1.2 | go-v0.39 | tcp | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.39 (tcp, noise, yamux) | jvm-v1.2 | go-v0.39 | tcp | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x go-v0.39 (ws, noise, yamux) | jvm-v1.2 | go-v0.39 | ws | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x go-v0.39 (ws, tls, yamux) | jvm-v1.2 | go-v0.39 | ws | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.39 (quic-v1) | jvm-v1.2 | go-v0.39 | quic-v1 | - | - | ✅ | 14s | - | - |
| jvm-v1.2 x go-v0.40 (tcp, noise, yamux) | jvm-v1.2 | go-v0.40 | tcp | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x go-v0.40 (tcp, tls, yamux) | jvm-v1.2 | go-v0.40 | tcp | tls | yamux | ✅ | 16s | - | - |
| jvm-v1.2 x go-v0.40 (ws, noise, yamux) | jvm-v1.2 | go-v0.40 | ws | noise | yamux | ✅ | 12s | - | - |
| jvm-v1.2 x go-v0.40 (ws, tls, yamux) | jvm-v1.2 | go-v0.40 | ws | tls | yamux | ✅ | 14s | - | - |
| jvm-v1.2 x go-v0.40 (quic-v1) | jvm-v1.2 | go-v0.40 | quic-v1 | - | - | ✅ | 14s | - | - |
| jvm-v1.2 x go-v0.41 (tcp, noise, yamux) | jvm-v1.2 | go-v0.41 | tcp | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x go-v0.41 (tcp, tls, yamux) | jvm-v1.2 | go-v0.41 | tcp | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.41 (ws, tls, yamux) | jvm-v1.2 | go-v0.41 | ws | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.41 (ws, noise, yamux) | jvm-v1.2 | go-v0.41 | ws | noise | yamux | ✅ | 14s | - | - |
| jvm-v1.2 x go-v0.41 (quic-v1) | jvm-v1.2 | go-v0.41 | quic-v1 | - | - | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.42 (tcp, noise, yamux) | jvm-v1.2 | go-v0.42 | tcp | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x go-v0.42 (tcp, tls, yamux) | jvm-v1.2 | go-v0.42 | tcp | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.42 (ws, tls, yamux) | jvm-v1.2 | go-v0.42 | ws | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.42 (ws, noise, yamux) | jvm-v1.2 | go-v0.42 | ws | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x go-v0.42 (quic-v1) | jvm-v1.2 | go-v0.42 | quic-v1 | - | - | ✅ | 14s | - | - |
| jvm-v1.2 x go-v0.43 (tcp, noise, yamux) | jvm-v1.2 | go-v0.43 | tcp | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x go-v0.43 (tcp, tls, yamux) | jvm-v1.2 | go-v0.43 | tcp | tls | yamux | ✅ | 14s | - | - |
| jvm-v1.2 x go-v0.43 (ws, tls, yamux) | jvm-v1.2 | go-v0.43 | ws | tls | yamux | ✅ | 14s | - | - |
| jvm-v1.2 x go-v0.43 (ws, noise, yamux) | jvm-v1.2 | go-v0.43 | ws | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x go-v0.43 (quic-v1) | jvm-v1.2 | go-v0.43 | quic-v1 | - | - | ✅ | 14s | - | - |
| jvm-v1.2 x go-v0.44 (tcp, tls, yamux) | jvm-v1.2 | go-v0.44 | tcp | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.44 (tcp, noise, yamux) | jvm-v1.2 | go-v0.44 | tcp | noise | yamux | ✅ | 14s | - | - |
| jvm-v1.2 x go-v0.44 (ws, tls, yamux) | jvm-v1.2 | go-v0.44 | ws | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.44 (ws, noise, yamux) | jvm-v1.2 | go-v0.44 | ws | noise | yamux | ✅ | 14s | - | - |
| jvm-v1.2 x go-v0.44 (quic-v1) | jvm-v1.2 | go-v0.44 | quic-v1 | - | - | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.45 (tcp, tls, yamux) | jvm-v1.2 | go-v0.45 | tcp | tls | yamux | ✅ | 16s | - | - |
| jvm-v1.2 x go-v0.45 (tcp, noise, yamux) | jvm-v1.2 | go-v0.45 | tcp | noise | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.45 (ws, tls, yamux) | jvm-v1.2 | go-v0.45 | ws | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.45 (ws, noise, yamux) | jvm-v1.2 | go-v0.45 | ws | noise | yamux | ✅ | 14s | - | - |
| jvm-v1.2 x python-v0.4 (tcp, noise, mplex) | jvm-v1.2 | python-v0.4 | tcp | noise | mplex | ❌ | 11s | - | - |
| jvm-v1.2 x go-v0.45 (quic-v1) | jvm-v1.2 | go-v0.45 | quic-v1 | - | - | ✅ | 16s | - | - |
| jvm-v1.2 x python-v0.4 (tcp, noise, yamux) | jvm-v1.2 | python-v0.4 | tcp | noise | yamux | ❌ | 11s | - | - |
| jvm-v1.2 x python-v0.4 (ws, noise, mplex) | jvm-v1.2 | python-v0.4 | ws | noise | mplex | ❌ | 11s | - | - |
| jvm-v1.2 x python-v0.4 (ws, noise, yamux) | jvm-v1.2 | python-v0.4 | ws | noise | yamux | ❌ | 12s | - | - |
| jvm-v1.2 x python-v0.4 (quic-v1) | jvm-v1.2 | python-v0.4 | quic-v1 | - | - | ❌ | 15s | - | - |
| jvm-v1.2 x js-v1.x (tcp, noise, mplex) | jvm-v1.2 | js-v1.x | tcp | noise | mplex | ✅ | 33s | - | - |
| jvm-v1.2 x js-v1.x (tcp, noise, yamux) | jvm-v1.2 | js-v1.x | tcp | noise | yamux | ✅ | 32s | - | - |
| jvm-v1.2 x js-v1.x (ws, noise, mplex) | jvm-v1.2 | js-v1.x | ws | noise | mplex | ✅ | 31s | - | - |
| jvm-v1.2 x js-v1.x (ws, noise, yamux) | jvm-v1.2 | js-v1.x | ws | noise | yamux | ✅ | 31s | - | - |
| jvm-v1.2 x js-v2.x (tcp, noise, mplex) | jvm-v1.2 | js-v2.x | tcp | noise | mplex | ✅ | 32s | - | - |
| jvm-v1.2 x js-v2.x (tcp, noise, yamux) | jvm-v1.2 | js-v2.x | tcp | noise | yamux | ✅ | 32s | - | - |
| jvm-v1.2 x js-v2.x (ws, noise, mplex) | jvm-v1.2 | js-v2.x | ws | noise | mplex | ✅ | 29s | - | - |
| jvm-v1.2 x js-v2.x (ws, noise, yamux) | jvm-v1.2 | js-v2.x | ws | noise | yamux | ✅ | 26s | - | - |
| jvm-v1.2 x nim-v1.14 (tcp, noise, mplex) | jvm-v1.2 | nim-v1.14 | tcp | noise | mplex | ✅ | 16s | - | - |
| jvm-v1.2 x nim-v1.14 (tcp, noise, yamux) | jvm-v1.2 | nim-v1.14 | tcp | noise | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x nim-v1.14 (ws, noise, mplex) | jvm-v1.2 | nim-v1.14 | ws | noise | mplex | ✅ | 16s | - | - |
| jvm-v1.2 x nim-v1.14 (ws, noise, yamux) | jvm-v1.2 | nim-v1.14 | ws | noise | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x js-v3.x (tcp, noise, mplex) | jvm-v1.2 | js-v3.x | tcp | noise | mplex | ✅ | 27s | - | - |
| jvm-v1.2 x js-v3.x (tcp, noise, yamux) | jvm-v1.2 | js-v3.x | tcp | noise | yamux | ✅ | 27s | - | - |
| jvm-v1.2 x js-v3.x (ws, noise, mplex) | jvm-v1.2 | js-v3.x | ws | noise | mplex | ✅ | 27s | - | - |
| jvm-v1.2 x js-v3.x (ws, noise, yamux) | jvm-v1.2 | js-v3.x | ws | noise | yamux | ✅ | 27s | - | - |
| jvm-v1.2 x jvm-v1.2 (tcp, tls, mplex) | jvm-v1.2 | jvm-v1.2 | tcp | tls | mplex | ✅ | 17s | - | - |
| jvm-v1.2 x jvm-v1.2 (tcp, tls, yamux) | jvm-v1.2 | jvm-v1.2 | tcp | tls | yamux | ✅ | 21s | - | - |
| jvm-v1.2 x jvm-v1.2 (tcp, noise, mplex) | jvm-v1.2 | jvm-v1.2 | tcp | noise | mplex | ✅ | 20s | - | - |
| jvm-v1.2 x jvm-v1.2 (tcp, noise, yamux) | jvm-v1.2 | jvm-v1.2 | tcp | noise | yamux | ✅ | 21s | - | - |
| jvm-v1.2 x jvm-v1.2 (ws, noise, mplex) | jvm-v1.2 | jvm-v1.2 | ws | noise | mplex | ✅ | 24s | - | - |
| jvm-v1.2 x jvm-v1.2 (ws, noise, yamux) | jvm-v1.2 | jvm-v1.2 | ws | noise | yamux | ✅ | 22s | - | - |
| jvm-v1.2 x jvm-v1.2 (ws, tls, mplex) | jvm-v1.2 | jvm-v1.2 | ws | tls | mplex | ✅ | 29s | - | - |
| jvm-v1.2 x jvm-v1.2 (ws, tls, yamux) | jvm-v1.2 | jvm-v1.2 | ws | tls | yamux | ✅ | 28s | - | - |
| jvm-v1.2 x c-v0.0.1 (tcp, noise, mplex) | jvm-v1.2 | c-v0.0.1 | tcp | noise | mplex | ✅ | 16s | - | - |
| jvm-v1.2 x c-v0.0.1 (tcp, noise, yamux) | jvm-v1.2 | c-v0.0.1 | tcp | noise | yamux | ❌ | 12s | - | - |
| jvm-v1.2 x jvm-v1.2 (quic-v1) | jvm-v1.2 | jvm-v1.2 | quic-v1 | - | - | ✅ | 25s | - | - |
| c-v0.0.1 x rust-v0.53 (tcp, noise, mplex) | c-v0.0.1 | rust-v0.53 | tcp | noise | mplex | ✅ | 6s | 15.000 | 1.000 |
| jvm-v1.2 x c-v0.0.1 (quic-v1) | jvm-v1.2 | c-v0.0.1 | quic-v1 | - | - | ✅ | 15s | - | - |
| c-v0.0.1 x rust-v0.53 (tcp, noise, yamux) | c-v0.0.1 | rust-v0.53 | tcp | noise | yamux | ✅ | 5s | 71.000 | 1.000 |
| jvm-v1.2 x dotnet-v1.0 (tcp, noise, yamux) | jvm-v1.2 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x zig-v0.0.1 (quic-v1) | jvm-v1.2 | zig-v0.0.1 | quic-v1 | - | - | ❌ | 12s | - | - |
| c-v0.0.1 x rust-v0.54 (tcp, noise, mplex) | c-v0.0.1 | rust-v0.54 | tcp | noise | mplex | ✅ | 4s | 48.000 | 0.000 |
| c-v0.0.1 x rust-v0.53 (quic-v1) | c-v0.0.1 | rust-v0.53 | quic-v1 | - | - | ✅ | 8s | 39.000 | 2.000 |
| c-v0.0.1 x rust-v0.54 (tcp, noise, yamux) | c-v0.0.1 | rust-v0.54 | tcp | noise | yamux | ✅ | 4s | 100.000 | 43.000 |
| jvm-v1.2 x eth-p2p-z-v0.0.1 (quic-v1) | jvm-v1.2 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 15s | - | - |
| c-v0.0.1 x rust-v0.55 (tcp, noise, mplex) | c-v0.0.1 | rust-v0.55 | tcp | noise | mplex | ✅ | 4s | 10.000 | 3.000 |
| c-v0.0.1 x rust-v0.55 (tcp, noise, yamux) | c-v0.0.1 | rust-v0.55 | tcp | noise | yamux | ✅ | 4s | 65.000 | 1.000 |
| c-v0.0.1 x rust-v0.54 (quic-v1) | c-v0.0.1 | rust-v0.54 | quic-v1 | - | - | ✅ | 6s | 13.000 | 1.000 |
| c-v0.0.1 x rust-v0.56 (tcp, noise, mplex) | c-v0.0.1 | rust-v0.56 | tcp | noise | mplex | ✅ | 5s | 9.000 | 0.000 |
| c-v0.0.1 x rust-v0.56 (tcp, noise, yamux) | c-v0.0.1 | rust-v0.56 | tcp | noise | yamux | ✅ | 4s | 64.000 | 1.000 |
| c-v0.0.1 x rust-v0.55 (quic-v1) | c-v0.0.1 | rust-v0.55 | quic-v1 | - | - | ✅ | 7s | 18.000 | 0.000 |
| c-v0.0.1 x go-v0.38 (tcp, noise, yamux) | c-v0.0.1 | go-v0.38 | tcp | noise | yamux | ✅ | 5s | 114.000 | 0.000 |
| c-v0.0.1 x rust-v0.56 (quic-v1) | c-v0.0.1 | rust-v0.56 | quic-v1 | - | - | ✅ | 7s | 24.000 | 3.000 |
| c-v0.0.1 x go-v0.39 (tcp, noise, yamux) | c-v0.0.1 | go-v0.39 | tcp | noise | yamux | ✅ | 4s | 117.000 | 0.000 |
| c-v0.0.1 x go-v0.40 (tcp, noise, yamux) | c-v0.0.1 | go-v0.40 | tcp | noise | yamux | ✅ | 5s | 111.000 | 0.000 |
| c-v0.0.1 x go-v0.41 (tcp, noise, yamux) | c-v0.0.1 | go-v0.41 | tcp | noise | yamux | ✅ | 4s | 119.000 | 0.000 |
| c-v0.0.1 x go-v0.42 (tcp, noise, yamux) | c-v0.0.1 | go-v0.42 | tcp | noise | yamux | ✅ | 4s | 115.000 | 1.000 |
| c-v0.0.1 x go-v0.43 (tcp, noise, yamux) | c-v0.0.1 | go-v0.43 | tcp | noise | yamux | ✅ | 3s | 118.000 | 1.000 |
| c-v0.0.1 x go-v0.44 (tcp, noise, yamux) | c-v0.0.1 | go-v0.44 | tcp | noise | yamux | ✅ | 4s | 125.000 | 1.000 |
| c-v0.0.1 x go-v0.45 (tcp, noise, yamux) | c-v0.0.1 | go-v0.45 | tcp | noise | yamux | ✅ | 4s | 125.000 | 1.000 |
| c-v0.0.1 x go-v0.38 (quic-v1) | c-v0.0.1 | go-v0.38 | quic-v1 | - | - | ✅ | 19s | 130.000 | 1.000 |
| c-v0.0.1 x go-v0.39 (quic-v1) | c-v0.0.1 | go-v0.39 | quic-v1 | - | - | ✅ | 19s | 129.000 | 0.000 |
| c-v0.0.1 x go-v0.40 (quic-v1) | c-v0.0.1 | go-v0.40 | quic-v1 | - | - | ✅ | 19s | 157.000 | 0.000 |
| c-v0.0.1 x go-v0.41 (quic-v1) | c-v0.0.1 | go-v0.41 | quic-v1 | - | - | ✅ | 19s | 139.000 | 1.000 |
| c-v0.0.1 x go-v0.45 (quic-v1) | c-v0.0.1 | go-v0.45 | quic-v1 | - | - | ✅ | 4s | 121.000 | 0.000 |
| c-v0.0.1 x go-v0.42 (quic-v1) | c-v0.0.1 | go-v0.42 | quic-v1 | - | - | ✅ | 19s | 164.000 | 6.000 |
| c-v0.0.1 x python-v0.4 (tcp, noise, mplex) | c-v0.0.1 | python-v0.4 | tcp | noise | mplex | ✅ | 5s | 23.000 | 1.000 |
| c-v0.0.1 x python-v0.4 (tcp, noise, yamux) | c-v0.0.1 | python-v0.4 | tcp | noise | yamux | ✅ | 6s | 234.000 | 2.000 |
| c-v0.0.1 x go-v0.43 (quic-v1) | c-v0.0.1 | go-v0.43 | quic-v1 | - | - | ✅ | 19s | 119.000 | 1.000 |
| c-v0.0.1 x python-v0.4 (quic-v1) | c-v0.0.1 | python-v0.4 | quic-v1 | - | - | ✅ | 5s | 183.000 | 19.000 |
| c-v0.0.1 x go-v0.44 (quic-v1) | c-v0.0.1 | go-v0.44 | quic-v1 | - | - | ✅ | 18s | 174.000 | 1.000 |
| c-v0.0.1 x nim-v1.14 (tcp, noise, mplex) | c-v0.0.1 | nim-v1.14 | tcp | noise | mplex | ✅ | 5s | 96.000 | 1.000 |
| c-v0.0.1 x nim-v1.14 (tcp, noise, yamux) | c-v0.0.1 | nim-v1.14 | tcp | noise | yamux | ✅ | 5s | 272.000 | 5.000 |
| c-v0.0.1 x js-v1.x (tcp, noise, mplex) | c-v0.0.1 | js-v1.x | tcp | noise | mplex | ✅ | 19s | 109.000 | 1.000 |
| c-v0.0.1 x js-v1.x (tcp, noise, yamux) | c-v0.0.1 | js-v1.x | tcp | noise | yamux | ✅ | 20s | 350.000 | 2.000 |
| c-v0.0.1 x js-v2.x (tcp, noise, mplex) | c-v0.0.1 | js-v2.x | tcp | noise | mplex | ✅ | 21s | 199.000 | 3.000 |
| c-v0.0.1 x jvm-v1.2 (tcp, noise, mplex) | c-v0.0.1 | jvm-v1.2 | tcp | noise | mplex | ✅ | 10s | 1489.000 | 7.000 |
| c-v0.0.1 x js-v2.x (tcp, noise, yamux) | c-v0.0.1 | js-v2.x | tcp | noise | yamux | ✅ | 22s | 364.000 | 2.000 |
| c-v0.0.1 x js-v3.x (tcp, noise, mplex) | c-v0.0.1 | js-v3.x | tcp | noise | mplex | ✅ | 20s | 66.000 | 4.000 |
| c-v0.0.1 x jvm-v1.2 (tcp, noise, yamux) | c-v0.0.1 | jvm-v1.2 | tcp | noise | yamux | ❌ | 9s | - | - |
| c-v0.0.1 x js-v3.x (tcp, noise, yamux) | c-v0.0.1 | js-v3.x | tcp | noise | yamux | ✅ | 21s | 335.000 | 7.000 |
| c-v0.0.1 x c-v0.0.1 (tcp, noise, mplex) | c-v0.0.1 | c-v0.0.1 | tcp | noise | mplex | ✅ | 5s | 12.000 | 0.000 |
| c-v0.0.1 x c-v0.0.1 (tcp, noise, yamux) | c-v0.0.1 | c-v0.0.1 | tcp | noise | yamux | ✅ | 5s | 327.000 | 2.000 |
| c-v0.0.1 x c-v0.0.1 (quic-v1) | c-v0.0.1 | c-v0.0.1 | quic-v1 | - | - | ✅ | 5s | 38.000 | 1.000 |
| c-v0.0.1 x dotnet-v1.0 (tcp, noise, yamux) | c-v0.0.1 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 5s | 372.000 | 10.000 |
| c-v0.0.1 x eth-p2p-z-v0.0.1 (quic-v1) | c-v0.0.1 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 5s | 103.000 | 0.000 |
| c-v0.0.1 x jvm-v1.2 (quic-v1) | c-v0.0.1 | jvm-v1.2 | quic-v1 | - | - | ✅ | 10s | 2892.000 | 3.000 |
| dotnet-v1.0 x rust-v0.53 (tcp, noise, yamux) | dotnet-v1.0 | rust-v0.53 | tcp | noise | yamux | ✅ | 5s | - | - |
| dotnet-v1.0 x rust-v0.54 (tcp, noise, yamux) | dotnet-v1.0 | rust-v0.54 | tcp | noise | yamux | ✅ | 5s | - | - |
| dotnet-v1.0 x rust-v0.55 (tcp, noise, yamux) | dotnet-v1.0 | rust-v0.55 | tcp | noise | yamux | ✅ | 6s | - | - |
| dotnet-v1.0 x rust-v0.56 (tcp, noise, yamux) | dotnet-v1.0 | rust-v0.56 | tcp | noise | yamux | ✅ | 5s | - | - |
| dotnet-v1.0 x go-v0.38 (tcp, noise, yamux) | dotnet-v1.0 | go-v0.38 | tcp | noise | yamux | ✅ | 5s | - | - |
| dotnet-v1.0 x go-v0.39 (tcp, noise, yamux) | dotnet-v1.0 | go-v0.39 | tcp | noise | yamux | ✅ | 5s | - | - |
| dotnet-v1.0 x go-v0.40 (tcp, noise, yamux) | dotnet-v1.0 | go-v0.40 | tcp | noise | yamux | ✅ | 5s | - | - |
| dotnet-v1.0 x go-v0.41 (tcp, noise, yamux) | dotnet-v1.0 | go-v0.41 | tcp | noise | yamux | ✅ | 5s | - | - |
| dotnet-v1.0 x go-v0.42 (tcp, noise, yamux) | dotnet-v1.0 | go-v0.42 | tcp | noise | yamux | ✅ | 5s | - | - |
| dotnet-v1.0 x go-v0.43 (tcp, noise, yamux) | dotnet-v1.0 | go-v0.43 | tcp | noise | yamux | ✅ | 5s | - | - |
| dotnet-v1.0 x go-v0.44 (tcp, noise, yamux) | dotnet-v1.0 | go-v0.44 | tcp | noise | yamux | ✅ | 5s | - | - |
| dotnet-v1.0 x go-v0.45 (tcp, noise, yamux) | dotnet-v1.0 | go-v0.45 | tcp | noise | yamux | ✅ | 5s | - | - |
| dotnet-v1.0 x python-v0.4 (tcp, noise, yamux) | dotnet-v1.0 | python-v0.4 | tcp | noise | yamux | ✅ | 6s | - | - |
| c-v0.0.1 x zig-v0.0.1 (quic-v1) | c-v0.0.1 | zig-v0.0.1 | quic-v1 | - | - | ❌ | 19s | - | - |
| dotnet-v1.0 x nim-v1.14 (tcp, noise, yamux) | dotnet-v1.0 | nim-v1.14 | tcp | noise | yamux | ✅ | 6s | - | - |
| dotnet-v1.0 x c-v0.0.1 (tcp, noise, yamux) | dotnet-v1.0 | c-v0.0.1 | tcp | noise | yamux | ✅ | 7s | - | - |
| dotnet-v1.0 x dotnet-v1.0 (tcp, noise, yamux) | dotnet-v1.0 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 7s | - | - |
| zig-v0.0.1 x rust-v0.53 (quic-v1) | zig-v0.0.1 | rust-v0.53 | quic-v1 | - | - | ✅ | 5s | - | - |
| dotnet-v1.0 x jvm-v1.2 (tcp, noise, yamux) | dotnet-v1.0 | jvm-v1.2 | tcp | noise | yamux | ✅ | 10s | - | - |
| dotnet-v1.0 x js-v1.x (tcp, noise, yamux) | dotnet-v1.0 | js-v1.x | tcp | noise | yamux | ❌ | 15s | - | - |
| dotnet-v1.0 x js-v2.x (tcp, noise, yamux) | dotnet-v1.0 | js-v2.x | tcp | noise | yamux | ❌ | 15s | - | - |
| zig-v0.0.1 x rust-v0.54 (quic-v1) | zig-v0.0.1 | rust-v0.54 | quic-v1 | - | - | ✅ | 5s | - | - |
| dotnet-v1.0 x js-v3.x (tcp, noise, yamux) | dotnet-v1.0 | js-v3.x | tcp | noise | yamux | ❌ | 15s | - | - |
| zig-v0.0.1 x rust-v0.55 (quic-v1) | zig-v0.0.1 | rust-v0.55 | quic-v1 | - | - | ✅ | 5s | - | - |
| zig-v0.0.1 x rust-v0.56 (quic-v1) | zig-v0.0.1 | rust-v0.56 | quic-v1 | - | - | ✅ | 4s | - | - |
| zig-v0.0.1 x go-v0.38 (quic-v1) | zig-v0.0.1 | go-v0.38 | quic-v1 | - | - | ✅ | 5s | - | - |
| zig-v0.0.1 x go-v0.39 (quic-v1) | zig-v0.0.1 | go-v0.39 | quic-v1 | - | - | ✅ | 4s | - | - |
| zig-v0.0.1 x go-v0.40 (quic-v1) | zig-v0.0.1 | go-v0.40 | quic-v1 | - | - | ✅ | 6s | - | - |
| zig-v0.0.1 x go-v0.41 (quic-v1) | zig-v0.0.1 | go-v0.41 | quic-v1 | - | - | ✅ | 5s | - | - |
| zig-v0.0.1 x go-v0.43 (quic-v1) | zig-v0.0.1 | go-v0.43 | quic-v1 | - | - | ✅ | 4s | - | - |
| zig-v0.0.1 x go-v0.42 (quic-v1) | zig-v0.0.1 | go-v0.42 | quic-v1 | - | - | ✅ | 5s | - | - |
| zig-v0.0.1 x go-v0.44 (quic-v1) | zig-v0.0.1 | go-v0.44 | quic-v1 | - | - | ✅ | 4s | - | - |
| zig-v0.0.1 x go-v0.45 (quic-v1) | zig-v0.0.1 | go-v0.45 | quic-v1 | - | - | ✅ | 5s | - | - |
| zig-v0.0.1 x zig-v0.0.1 (quic-v1) | zig-v0.0.1 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 4s | - | - |
| zig-v0.0.1 x eth-p2p-z-v0.0.1 (quic-v1) | zig-v0.0.1 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 5s | - | - |
| eth-p2p-z-v0.0.1 x rust-v0.53 (quic-v1) | eth-p2p-z-v0.0.1 | rust-v0.53 | quic-v1 | - | - | ✅ | 5s | - | - |
| zig-v0.0.1 x jvm-v1.2 (quic-v1) | zig-v0.0.1 | jvm-v1.2 | quic-v1 | - | - | ✅ | 9s | - | - |
| eth-p2p-z-v0.0.1 x rust-v0.54 (quic-v1) | eth-p2p-z-v0.0.1 | rust-v0.54 | quic-v1 | - | - | ✅ | 4s | - | - |
| eth-p2p-z-v0.0.1 x rust-v0.55 (quic-v1) | eth-p2p-z-v0.0.1 | rust-v0.55 | quic-v1 | - | - | ✅ | 5s | - | - |
| eth-p2p-z-v0.0.1 x rust-v0.56 (quic-v1) | eth-p2p-z-v0.0.1 | rust-v0.56 | quic-v1 | - | - | ✅ | 4s | - | - |
| eth-p2p-z-v0.0.1 x go-v0.38 (quic-v1) | eth-p2p-z-v0.0.1 | go-v0.38 | quic-v1 | - | - | ✅ | 4s | - | - |
| eth-p2p-z-v0.0.1 x go-v0.39 (quic-v1) | eth-p2p-z-v0.0.1 | go-v0.39 | quic-v1 | - | - | ✅ | 4s | - | - |
| zig-v0.0.1 x python-v0.4 (quic-v1) | zig-v0.0.1 | python-v0.4 | quic-v1 | - | - | ✅ | 15s | - | - |
| eth-p2p-z-v0.0.1 x go-v0.40 (quic-v1) | eth-p2p-z-v0.0.1 | go-v0.40 | quic-v1 | - | - | ✅ | 5s | - | - |
| eth-p2p-z-v0.0.1 x go-v0.41 (quic-v1) | eth-p2p-z-v0.0.1 | go-v0.41 | quic-v1 | - | - | ✅ | 5s | - | - |
| eth-p2p-z-v0.0.1 x go-v0.42 (quic-v1) | eth-p2p-z-v0.0.1 | go-v0.42 | quic-v1 | - | - | ✅ | 5s | - | - |
| zig-v0.0.1 x c-v0.0.1 (quic-v1) | zig-v0.0.1 | c-v0.0.1 | quic-v1 | - | - | ✅ | 15s | - | - |
| eth-p2p-z-v0.0.1 x go-v0.43 (quic-v1) | eth-p2p-z-v0.0.1 | go-v0.43 | quic-v1 | - | - | ✅ | 5s | - | - |
| eth-p2p-z-v0.0.1 x go-v0.44 (quic-v1) | eth-p2p-z-v0.0.1 | go-v0.44 | quic-v1 | - | - | ✅ | 4s | - | - |
| eth-p2p-z-v0.0.1 x go-v0.45 (quic-v1) | eth-p2p-z-v0.0.1 | go-v0.45 | quic-v1 | - | - | ✅ | 4s | - | - |
| eth-p2p-z-v0.0.1 x c-v0.0.1 (quic-v1) | eth-p2p-z-v0.0.1 | c-v0.0.1 | quic-v1 | - | - | ✅ | 4s | - | - |
| eth-p2p-z-v0.0.1 x python-v0.4 (quic-v1) | eth-p2p-z-v0.0.1 | python-v0.4 | quic-v1 | - | - | ✅ | 6s | - | - |
| eth-p2p-z-v0.0.1 x eth-p2p-z-v0.0.1 (quic-v1) | eth-p2p-z-v0.0.1 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 5s | - | - |
| eth-p2p-z-v0.0.1 x jvm-v1.2 (quic-v1) | eth-p2p-z-v0.0.1 | jvm-v1.2 | quic-v1 | - | - | ✅ | 10s | - | - |
| chromium-js-v1.x x rust-v0.53 (webrtc-direct) | chromium-js-v1.x | rust-v0.53 | webrtc-direct | - | - | ✅ | 23s | 350 | 35 |
| chromium-js-v1.x x rust-v0.54 (webrtc-direct) | chromium-js-v1.x | rust-v0.54 | webrtc-direct | - | - | ✅ | 23s | 305 | 28 |
| chromium-js-v1.x x rust-v0.55 (webrtc-direct) | chromium-js-v1.x | rust-v0.55 | webrtc-direct | - | - | ✅ | 23s | 293 | 21 |
| chromium-js-v1.x x rust-v0.56 (webrtc-direct) | chromium-js-v1.x | rust-v0.56 | webrtc-direct | - | - | ✅ | 22s | 350 | 37 |
| chromium-js-v1.x x go-v0.38 (webtransport) | chromium-js-v1.x | go-v0.38 | webtransport | - | - | ✅ | 22s | 148 | 37 |
| chromium-js-v1.x x go-v0.38 (wss, noise, yamux) | chromium-js-v1.x | go-v0.38 | wss | noise | yamux | ✅ | 21s | 242 | 67 |
| chromium-js-v1.x x go-v0.38 (webrtc-direct) | chromium-js-v1.x | go-v0.38 | webrtc-direct | - | - | ✅ | 21s | 234 | 32 |
| chromium-js-v1.x x go-v0.39 (webtransport) | chromium-js-v1.x | go-v0.39 | webtransport | - | - | ✅ | 23s | 220 | 56 |
| chromium-js-v1.x x go-v0.39 (wss, noise, yamux) | chromium-js-v1.x | go-v0.39 | wss | noise | yamux | ✅ | 22s | 402 | 150 |
| chromium-js-v1.x x go-v0.39 (webrtc-direct) | chromium-js-v1.x | go-v0.39 | webrtc-direct | - | - | ✅ | 23s | 289 | 33 |
| chromium-js-v1.x x go-v0.40 (webtransport) | chromium-js-v1.x | go-v0.40 | webtransport | - | - | ✅ | 23s | 183 | 47 |
| chromium-js-v1.x x go-v0.40 (wss, noise, yamux) | chromium-js-v1.x | go-v0.40 | wss | noise | yamux | ✅ | 22s | 237 | 50 |
| chromium-js-v1.x x go-v0.40 (webrtc-direct) | chromium-js-v1.x | go-v0.40 | webrtc-direct | - | - | ✅ | 22s | 252 | 35 |
| chromium-js-v1.x x go-v0.41 (webtransport) | chromium-js-v1.x | go-v0.41 | webtransport | - | - | ✅ | 21s | 163 | 39 |
| chromium-js-v1.x x go-v0.41 (wss, noise, yamux) | chromium-js-v1.x | go-v0.41 | wss | noise | yamux | ✅ | 23s | 402 | 96 |
| chromium-js-v1.x x go-v0.42 (webtransport) | chromium-js-v1.x | go-v0.42 | webtransport | - | - | ✅ | 23s | 202 | 47 |
| chromium-js-v1.x x go-v0.41 (webrtc-direct) | chromium-js-v1.x | go-v0.41 | webrtc-direct | - | - | ✅ | 23s | 269 | 34 |
| chromium-js-v1.x x go-v0.42 (wss, noise, yamux) | chromium-js-v1.x | go-v0.42 | wss | noise | yamux | ✅ | 23s | 309 | 53 |
| chromium-js-v1.x x go-v0.43 (webtransport) | chromium-js-v1.x | go-v0.43 | webtransport | - | - | ✅ | 22s | 113 | 23 |
| chromium-js-v1.x x go-v0.42 (webrtc-direct) | chromium-js-v1.x | go-v0.42 | webrtc-direct | - | - | ✅ | 23s | 165 | 13 |
| chromium-js-v1.x x go-v0.43 (wss, noise, yamux) | chromium-js-v1.x | go-v0.43 | wss | noise | yamux | ✅ | 21s | 183 | 39 |
| chromium-js-v1.x x go-v0.43 (webrtc-direct) | chromium-js-v1.x | go-v0.43 | webrtc-direct | - | - | ✅ | 22s | 289 | 62 |
| chromium-js-v1.x x go-v0.44 (webtransport) | chromium-js-v1.x | go-v0.44 | webtransport | - | - | ✅ | 22s | 258 | 78 |
| chromium-js-v1.x x go-v0.44 (wss, noise, yamux) | chromium-js-v1.x | go-v0.44 | wss | noise | yamux | ✅ | 23s | 226 | 41 |
| chromium-js-v1.x x go-v0.44 (webrtc-direct) | chromium-js-v1.x | go-v0.44 | webrtc-direct | - | - | ✅ | 23s | 243 | 31 |
| chromium-js-v1.x x go-v0.45 (webtransport) | chromium-js-v1.x | go-v0.45 | webtransport | - | - | ✅ | 23s | 182 | 25 |
| chromium-js-v1.x x go-v0.45 (wss, noise, yamux) | chromium-js-v1.x | go-v0.45 | wss | noise | yamux | ✅ | 23s | 245 | 47 |
| chromium-js-v1.x x go-v0.45 (webrtc-direct) | chromium-js-v1.x | go-v0.45 | webrtc-direct | - | - | ✅ | 22s | 175 | 30 |
| chromium-js-v1.x x python-v0.4 (wss, noise, mplex) | chromium-js-v1.x | python-v0.4 | wss | noise | mplex | ✅ | 35s | 372 | 91 |
| chromium-js-v1.x x python-v0.4 (wss, noise, yamux) | chromium-js-v1.x | python-v0.4 | wss | noise | yamux | ✅ | 37s | 395 | 102 |
| chromium-js-v1.x x chromium-js-v1.x (webrtc) | chromium-js-v1.x | chromium-js-v1.x | webrtc | - | - | ✅ | 39s | 1084 | 94 |
| chromium-js-v1.x x chromium-js-v2.x (webrtc) | chromium-js-v1.x | chromium-js-v2.x | webrtc | - | - | ✅ | 40s | 998 | 76 |
| chromium-js-v1.x x webkit-js-v1.x (webrtc) | chromium-js-v1.x | webkit-js-v1.x | webrtc | - | - | ✅ | 41s | 914 | 108 |
| chromium-js-v1.x x firefox-js-v1.x (webrtc) | chromium-js-v1.x | firefox-js-v1.x | webrtc | - | - | ✅ | 43s | 1170 | 119 |
| chromium-js-v1.x x firefox-js-v2.x (webrtc) | chromium-js-v1.x | firefox-js-v2.x | webrtc | - | - | ✅ | 45s | 1018 | 103 |
| chromium-js-v1.x x webkit-js-v2.x (webrtc) | chromium-js-v1.x | webkit-js-v2.x | webrtc | - | - | ✅ | 29s | 990 | 89 |
| chromium-js-v2.x x rust-v0.53 (webrtc-direct) | chromium-js-v2.x | rust-v0.53 | webrtc-direct | - | - | ✅ | 28s | 390 | 41 |
| chromium-js-v2.x x rust-v0.54 (webrtc-direct) | chromium-js-v2.x | rust-v0.54 | webrtc-direct | - | - | ✅ | 27s | 378 | 51 |
| chromium-js-v2.x x rust-v0.55 (webrtc-direct) | chromium-js-v2.x | rust-v0.55 | webrtc-direct | - | - | ✅ | 26s | 362 | 70 |
| chromium-js-v2.x x rust-v0.56 (webrtc-direct) | chromium-js-v2.x | rust-v0.56 | webrtc-direct | - | - | ✅ | 26s | 339 | 36 |
| chromium-js-v2.x x go-v0.38 (webtransport) | chromium-js-v2.x | go-v0.38 | webtransport | - | - | ✅ | 25s | 141 | 50 |
| chromium-js-v2.x x go-v0.38 (wss, noise, yamux) | chromium-js-v2.x | go-v0.38 | wss | noise | yamux | ✅ | 24s | 324 | 103 |
| chromium-js-v2.x x go-v0.38 (webrtc-direct) | chromium-js-v2.x | go-v0.38 | webrtc-direct | - | - | ✅ | 24s | 331 | 70 |
| chromium-js-v2.x x go-v0.39 (webtransport) | chromium-js-v2.x | go-v0.39 | webtransport | - | - | ✅ | 25s | 206 | 55 |
| chromium-js-v2.x x go-v0.39 (wss, noise, yamux) | chromium-js-v2.x | go-v0.39 | wss | noise | yamux | ✅ | 24s | 305 | 93 |
| chromium-js-v2.x x go-v0.39 (webrtc-direct) | chromium-js-v2.x | go-v0.39 | webrtc-direct | - | - | ✅ | 24s | 292 | 39 |
| chromium-js-v2.x x go-v0.40 (webtransport) | chromium-js-v2.x | go-v0.40 | webtransport | - | - | ✅ | 24s | 211 | 46 |
| eth-p2p-z-v0.0.1 x zig-v0.0.1 (quic-v1) | eth-p2p-z-v0.0.1 | zig-v0.0.1 | quic-v1 | - | - | ❌ | 194s | - | - |
| chromium-js-v2.x x go-v0.40 (wss, noise, yamux) | chromium-js-v2.x | go-v0.40 | wss | noise | yamux | ✅ | 24s | 227 | 57 |
| chromium-js-v2.x x go-v0.40 (webrtc-direct) | chromium-js-v2.x | go-v0.40 | webrtc-direct | - | - | ✅ | 24s | 255 | 53 |
| chromium-js-v2.x x go-v0.41 (webtransport) | chromium-js-v2.x | go-v0.41 | webtransport | - | - | ✅ | 28s | 376 | 124 |
| chromium-js-v2.x x go-v0.41 (wss, noise, yamux) | chromium-js-v2.x | go-v0.41 | wss | noise | yamux | ✅ | 28s | 378 | 101 |
| chromium-js-v2.x x go-v0.41 (webrtc-direct) | chromium-js-v2.x | go-v0.41 | webrtc-direct | - | - | ✅ | 29s | 323 | 82 |
| chromium-js-v2.x x go-v0.42 (webtransport) | chromium-js-v2.x | go-v0.42 | webtransport | - | - | ✅ | 28s | 206 | 62 |
| chromium-js-v2.x x go-v0.42 (wss, noise, yamux) | chromium-js-v2.x | go-v0.42 | wss | noise | yamux | ✅ | 27s | 324 | 89 |
| chromium-js-v2.x x go-v0.42 (webrtc-direct) | chromium-js-v2.x | go-v0.42 | webrtc-direct | - | - | ✅ | 27s | 263 | 47 |
| chromium-js-v2.x x go-v0.43 (webtransport) | chromium-js-v2.x | go-v0.43 | webtransport | - | - | ✅ | 27s | 176 | 41 |
| chromium-js-v2.x x go-v0.43 (wss, noise, yamux) | chromium-js-v2.x | go-v0.43 | wss | noise | yamux | ✅ | 27s | 220 | 47 |
| chromium-js-v2.x x go-v0.43 (webrtc-direct) | chromium-js-v2.x | go-v0.43 | webrtc-direct | - | - | ✅ | 28s | 317 | 62 |
| chromium-js-v2.x x go-v0.44 (webtransport) | chromium-js-v2.x | go-v0.44 | webtransport | - | - | ✅ | 29s | 221 | 60 |
| chromium-js-v2.x x go-v0.44 (wss, noise, yamux) | chromium-js-v2.x | go-v0.44 | wss | noise | yamux | ✅ | 29s | 301 | 84 |
| chromium-js-v2.x x go-v0.44 (webrtc-direct) | chromium-js-v2.x | go-v0.44 | webrtc-direct | - | - | ✅ | 29s | 243 | 43 |
| chromium-js-v2.x x go-v0.45 (webtransport) | chromium-js-v2.x | go-v0.45 | webtransport | - | - | ✅ | 29s | 236 | 64 |
| chromium-js-v2.x x go-v0.45 (wss, noise, yamux) | chromium-js-v2.x | go-v0.45 | wss | noise | yamux | ✅ | 28s | 331 | 89 |
| chromium-js-v2.x x python-v0.4 (wss, noise, mplex) | chromium-js-v2.x | python-v0.4 | wss | noise | mplex | ✅ | 27s | 199 | 42 |
| chromium-js-v2.x x go-v0.45 (webrtc-direct) | chromium-js-v2.x | go-v0.45 | webrtc-direct | - | - | ✅ | 29s | 238 | 33 |
| chromium-js-v2.x x python-v0.4 (wss, noise, yamux) | chromium-js-v2.x | python-v0.4 | wss | noise | yamux | ✅ | 43s | 440 | 126 |
| chromium-js-v2.x x chromium-js-v1.x (webrtc) | chromium-js-v2.x | chromium-js-v1.x | webrtc | - | - | ✅ | 45s | 1544 | 119 |
| chromium-js-v2.x x chromium-js-v2.x (webrtc) | chromium-js-v2.x | chromium-js-v2.x | webrtc | - | - | ✅ | 47s | 1622 | 126 |
| chromium-js-v2.x x webkit-js-v1.x (webrtc) | chromium-js-v2.x | webkit-js-v1.x | webrtc | - | - | ✅ | 48s | 1361 | 74 |
| chromium-js-v2.x x webkit-js-v2.x (webrtc) | chromium-js-v2.x | webkit-js-v2.x | webrtc | - | - | ✅ | 48s | 848 | 56 |
| chromium-js-v2.x x firefox-js-v1.x (webrtc) | chromium-js-v2.x | firefox-js-v1.x | webrtc | - | - | ✅ | 51s | 1129 | 116 |
| chromium-js-v2.x x firefox-js-v2.x (webrtc) | chromium-js-v2.x | firefox-js-v2.x | webrtc | - | - | ✅ | 53s | 768 | 66 |
| firefox-js-v1.x x rust-v0.53 (webrtc-direct) | firefox-js-v1.x | rust-v0.53 | webrtc-direct | - | - | ✅ | 51s | 1470 | 41 |
| firefox-js-v1.x x rust-v0.54 (webrtc-direct) | firefox-js-v1.x | rust-v0.54 | webrtc-direct | - | - | ✅ | 34s | 1592 | 77 |
| firefox-js-v1.x x rust-v0.55 (webrtc-direct) | firefox-js-v1.x | rust-v0.55 | webrtc-direct | - | - | ✅ | 33s | 1500 | 59 |
| firefox-js-v1.x x rust-v0.56 (webrtc-direct) | firefox-js-v1.x | rust-v0.56 | webrtc-direct | - | - | ✅ | 33s | 1504 | 64 |
| firefox-js-v1.x x go-v0.38 (webtransport) | firefox-js-v1.x | go-v0.38 | webtransport | - | - | ❌ | 31s | - | - |
| firefox-js-v1.x x go-v0.38 (wss, noise, yamux) | firefox-js-v1.x | go-v0.38 | wss | noise | yamux | ✅ | 31s | 364 | 153 |
| firefox-js-v1.x x go-v0.38 (webrtc-direct) | firefox-js-v1.x | go-v0.38 | webrtc-direct | - | - | ✅ | 31s | 198 | 54 |
| firefox-js-v1.x x go-v0.39 (webtransport) | firefox-js-v1.x | go-v0.39 | webtransport | - | - | ❌ | 31s | - | - |
| firefox-js-v1.x x go-v0.39 (wss, noise, yamux) | firefox-js-v1.x | go-v0.39 | wss | noise | yamux | ✅ | 30s | 194 | 94 |
| firefox-js-v1.x x go-v0.39 (webrtc-direct) | firefox-js-v1.x | go-v0.39 | webrtc-direct | - | - | ✅ | 30s | 415 | 104 |
| firefox-js-v1.x x go-v0.40 (webtransport) | firefox-js-v1.x | go-v0.40 | webtransport | - | - | ❌ | 30s | - | - |
| firefox-js-v1.x x go-v0.40 (wss, noise, yamux) | firefox-js-v1.x | go-v0.40 | wss | noise | yamux | ✅ | 32s | 461 | 231 |
| firefox-js-v1.x x go-v0.40 (webrtc-direct) | firefox-js-v1.x | go-v0.40 | webrtc-direct | - | - | ✅ | 33s | 320 | 63 |
| firefox-js-v1.x x go-v0.41 (webtransport) | firefox-js-v1.x | go-v0.41 | webtransport | - | - | ❌ | 31s | - | - |
| firefox-js-v1.x x go-v0.41 (wss, noise, yamux) | firefox-js-v1.x | go-v0.41 | wss | noise | yamux | ✅ | 32s | 296 | 139 |
| firefox-js-v1.x x go-v0.41 (webrtc-direct) | firefox-js-v1.x | go-v0.41 | webrtc-direct | - | - | ✅ | 31s | 250 | 63 |
| firefox-js-v1.x x go-v0.42 (webtransport) | firefox-js-v1.x | go-v0.42 | webtransport | - | - | ❌ | 31s | - | - |
| firefox-js-v1.x x go-v0.42 (wss, noise, yamux) | firefox-js-v1.x | go-v0.42 | wss | noise | yamux | ✅ | 30s | 315 | 125 |
| firefox-js-v1.x x go-v0.42 (webrtc-direct) | firefox-js-v1.x | go-v0.42 | webrtc-direct | - | - | ✅ | 30s | 317 | 81 |
| firefox-js-v1.x x go-v0.43 (webtransport) | firefox-js-v1.x | go-v0.43 | webtransport | - | - | ❌ | 30s | - | - |
| firefox-js-v1.x x go-v0.43 (wss, noise, yamux) | firefox-js-v1.x | go-v0.43 | wss | noise | yamux | ✅ | 32s | 373 | 167 |
| firefox-js-v1.x x go-v0.43 (webrtc-direct) | firefox-js-v1.x | go-v0.43 | webrtc-direct | - | - | ✅ | 31s | 399 | 102 |
| firefox-js-v1.x x go-v0.44 (webtransport) | firefox-js-v1.x | go-v0.44 | webtransport | - | - | ❌ | 32s | - | - |
| firefox-js-v1.x x go-v0.44 (wss, noise, yamux) | firefox-js-v1.x | go-v0.44 | wss | noise | yamux | ✅ | 33s | 264 | 117 |
| firefox-js-v1.x x go-v0.44 (webrtc-direct) | firefox-js-v1.x | go-v0.44 | webrtc-direct | - | - | ✅ | 32s | 261 | 60 |
| firefox-js-v1.x x go-v0.45 (webtransport) | firefox-js-v1.x | go-v0.45 | webtransport | - | - | ❌ | 36s | - | - |
| firefox-js-v1.x x go-v0.45 (wss, noise, yamux) | firefox-js-v1.x | go-v0.45 | wss | noise | yamux | ✅ | 39s | 730 | 383 |
| firefox-js-v1.x x go-v0.45 (webrtc-direct) | firefox-js-v1.x | go-v0.45 | webrtc-direct | - | - | ✅ | 42s | 494 | 135 |
| firefox-js-v1.x x python-v0.4 (wss, noise, mplex) | firefox-js-v1.x | python-v0.4 | wss | noise | mplex | ✅ | 43s | 417 | 162 |
| firefox-js-v1.x x python-v0.4 (wss, noise, yamux) | firefox-js-v1.x | python-v0.4 | wss | noise | yamux | ✅ | 43s | 553 | 241 |
| firefox-js-v1.x x chromium-js-v1.x (webrtc) | firefox-js-v1.x | chromium-js-v1.x | webrtc | - | - | ✅ | 47s | 2125 | 188 |
| firefox-js-v1.x x chromium-js-v2.x (webrtc) | firefox-js-v1.x | chromium-js-v2.x | webrtc | - | - | ✅ | 48s | 1650 | 231 |
| firefox-js-v1.x x firefox-js-v1.x (webrtc) | firefox-js-v1.x | firefox-js-v1.x | webrtc | - | - | ✅ | 48s | 2069 | 359 |
| firefox-js-v1.x x firefox-js-v2.x (webrtc) | firefox-js-v1.x | firefox-js-v2.x | webrtc | - | - | ✅ | 50s | 2579 | 248 |
| firefox-js-v1.x x webkit-js-v1.x (webrtc) | firefox-js-v1.x | webkit-js-v1.x | webrtc | - | - | ✅ | 43s | 1935 | 178 |
| firefox-js-v1.x x webkit-js-v2.x (webrtc) | firefox-js-v1.x | webkit-js-v2.x | webrtc | - | - | ✅ | 43s | 1414 | 151 |
| firefox-js-v2.x x rust-v0.53 (webrtc-direct) | firefox-js-v2.x | rust-v0.53 | webrtc-direct | - | - | ✅ | 43s | 1539 | 69 |
| firefox-js-v2.x x rust-v0.54 (webrtc-direct) | firefox-js-v2.x | rust-v0.54 | webrtc-direct | - | - | ✅ | 43s | 1517 | 47 |
| firefox-js-v2.x x rust-v0.55 (webrtc-direct) | firefox-js-v2.x | rust-v0.55 | webrtc-direct | - | - | ✅ | 40s | 1539 | 65 |
| firefox-js-v2.x x go-v0.38 (webtransport) | firefox-js-v2.x | go-v0.38 | webtransport | - | - | ❌ | 38s | - | - |
| firefox-js-v2.x x rust-v0.56 (webrtc-direct) | firefox-js-v2.x | rust-v0.56 | webrtc-direct | - | - | ✅ | 41s | 1446 | 55 |
| firefox-js-v2.x x go-v0.38 (wss, noise, yamux) | firefox-js-v2.x | go-v0.38 | wss | noise | yamux | ✅ | 32s | 428 | 155 |
| firefox-js-v2.x x go-v0.38 (webrtc-direct) | firefox-js-v2.x | go-v0.38 | webrtc-direct | - | - | ✅ | 33s | 394 | 118 |
| firefox-js-v2.x x go-v0.39 (webtransport) | firefox-js-v2.x | go-v0.39 | webtransport | - | - | ❌ | 33s | - | - |
| firefox-js-v2.x x go-v0.39 (wss, noise, yamux) | firefox-js-v2.x | go-v0.39 | wss | noise | yamux | ✅ | 33s | 331 | 137 |
| firefox-js-v2.x x go-v0.39 (webrtc-direct) | firefox-js-v2.x | go-v0.39 | webrtc-direct | - | - | ✅ | 35s | 434 | 73 |
| firefox-js-v2.x x go-v0.40 (webtransport) | firefox-js-v2.x | go-v0.40 | webtransport | - | - | ❌ | 33s | - | - |
| firefox-js-v2.x x go-v0.40 (wss, noise, yamux) | firefox-js-v2.x | go-v0.40 | wss | noise | yamux | ✅ | 33s | 306 | 132 |
| firefox-js-v2.x x go-v0.40 (webrtc-direct) | firefox-js-v2.x | go-v0.40 | webrtc-direct | - | - | ✅ | 33s | 234 | 56 |
| firefox-js-v2.x x go-v0.41 (webtransport) | firefox-js-v2.x | go-v0.41 | webtransport | - | - | ❌ | 33s | - | - |
| firefox-js-v2.x x go-v0.41 (wss, noise, yamux) | firefox-js-v2.x | go-v0.41 | wss | noise | yamux | ✅ | 32s | 360 | 192 |
| firefox-js-v2.x x go-v0.41 (webrtc-direct) | firefox-js-v2.x | go-v0.41 | webrtc-direct | - | - | ✅ | 33s | 337 | 68 |
| firefox-js-v2.x x go-v0.42 (webtransport) | firefox-js-v2.x | go-v0.42 | webtransport | - | - | ❌ | 32s | - | - |
| firefox-js-v2.x x go-v0.42 (wss, noise, yamux) | firefox-js-v2.x | go-v0.42 | wss | noise | yamux | ✅ | 34s | 350 | 161 |
| firefox-js-v2.x x go-v0.42 (webrtc-direct) | firefox-js-v2.x | go-v0.42 | webrtc-direct | - | - | ✅ | 35s | 301 | 49 |
| firefox-js-v2.x x go-v0.43 (webtransport) | firefox-js-v2.x | go-v0.43 | webtransport | - | - | ❌ | 34s | - | - |
| firefox-js-v2.x x go-v0.43 (wss, noise, yamux) | firefox-js-v2.x | go-v0.43 | wss | noise | yamux | ✅ | 34s | 302 | 155 |
| firefox-js-v2.x x go-v0.44 (webtransport) | firefox-js-v2.x | go-v0.44 | webtransport | - | - | ❌ | 33s | - | - |
| firefox-js-v2.x x go-v0.43 (webrtc-direct) | firefox-js-v2.x | go-v0.43 | webrtc-direct | - | - | ✅ | 35s | 369 | 73 |
| firefox-js-v2.x x go-v0.44 (wss, noise, yamux) | firefox-js-v2.x | go-v0.44 | wss | noise | yamux | ✅ | 35s | 492 | 279 |
| firefox-js-v2.x x go-v0.44 (webrtc-direct) | firefox-js-v2.x | go-v0.44 | webrtc-direct | - | - | ✅ | 36s | 380 | 70 |
| firefox-js-v2.x x go-v0.45 (webtransport) | firefox-js-v2.x | go-v0.45 | webtransport | - | - | ❌ | 36s | - | - |
| firefox-js-v2.x x python-v0.4 (wss, noise, mplex) | firefox-js-v2.x | python-v0.4 | wss | noise | mplex | ✅ | 35s | 275 | 84 |
| firefox-js-v2.x x go-v0.45 (webrtc-direct) | firefox-js-v2.x | go-v0.45 | webrtc-direct | - | - | ✅ | 37s | 400 | 129 |
| firefox-js-v2.x x go-v0.45 (wss, noise, yamux) | firefox-js-v2.x | go-v0.45 | wss | noise | yamux | ✅ | 38s | 386 | 238 |
| firefox-js-v2.x x python-v0.4 (wss, noise, yamux) | firefox-js-v2.x | python-v0.4 | wss | noise | yamux | ✅ | 47s | 638 | 361 |
| firefox-js-v2.x x chromium-js-v1.x (webrtc) | firefox-js-v2.x | chromium-js-v1.x | webrtc | - | - | ✅ | 50s | 2428 | 154 |
| webkit-js-v1.x x rust-v0.53 (webrtc-direct) | webkit-js-v1.x | rust-v0.53 | webrtc-direct | - | - | ✅ | 45s | 725 | 123 |
| firefox-js-v2.x x chromium-js-v2.x (webrtc) | firefox-js-v2.x | chromium-js-v2.x | webrtc | - | - | ✅ | 58s | 2290 | 223 |
| firefox-js-v2.x x firefox-js-v1.x (webrtc) | firefox-js-v2.x | firefox-js-v1.x | webrtc | - | - | ✅ | 55s | 3061 | 388 |
| firefox-js-v2.x x firefox-js-v2.x (webrtc) | firefox-js-v2.x | firefox-js-v2.x | webrtc | - | - | ✅ | 56s | 1290 | 122 |
| firefox-js-v2.x x webkit-js-v1.x (webrtc) | firefox-js-v2.x | webkit-js-v1.x | webrtc | - | - | ✅ | 53s | 1358 | 122 |
| firefox-js-v2.x x webkit-js-v2.x (webrtc) | firefox-js-v2.x | webkit-js-v2.x | webrtc | - | - | ✅ | 52s | 1415 | 141 |
| webkit-js-v1.x x rust-v0.54 (webrtc-direct) | webkit-js-v1.x | rust-v0.54 | webrtc-direct | - | - | ✅ | 30s | 609 | 77 |
| webkit-js-v1.x x rust-v0.55 (webrtc-direct) | webkit-js-v1.x | rust-v0.55 | webrtc-direct | - | - | ✅ | 29s | 495 | 67 |
| webkit-js-v1.x x rust-v0.56 (webrtc-direct) | webkit-js-v1.x | rust-v0.56 | webrtc-direct | - | - | ✅ | 27s | 656 | 81 |
| webkit-js-v1.x x go-v0.38 (wss, noise, yamux) | webkit-js-v1.x | go-v0.38 | wss | noise | yamux | ✅ | 26s | 383 | 105 |
| webkit-js-v1.x x go-v0.38 (webrtc-direct) | webkit-js-v1.x | go-v0.38 | webrtc-direct | - | - | ✅ | 27s | 484 | 96 |
| webkit-js-v1.x x go-v0.39 (wss, noise, yamux) | webkit-js-v1.x | go-v0.39 | wss | noise | yamux | ✅ | 26s | 442 | 134 |
| webkit-js-v1.x x go-v0.39 (webrtc-direct) | webkit-js-v1.x | go-v0.39 | webrtc-direct | - | - | ✅ | 26s | 480 | 96 |
| webkit-js-v1.x x go-v0.40 (wss, noise, yamux) | webkit-js-v1.x | go-v0.40 | wss | noise | yamux | ✅ | 27s | 330 | 96 |
| webkit-js-v1.x x go-v0.40 (webrtc-direct) | webkit-js-v1.x | go-v0.40 | webrtc-direct | - | - | ✅ | 25s | 545 | 105 |
| webkit-js-v1.x x go-v0.41 (wss, noise, yamux) | webkit-js-v1.x | go-v0.41 | wss | noise | yamux | ✅ | 24s | 475 | 159 |
| webkit-js-v1.x x go-v0.41 (webrtc-direct) | webkit-js-v1.x | go-v0.41 | webrtc-direct | - | - | ✅ | 27s | 421 | 88 |
| webkit-js-v1.x x go-v0.42 (wss, noise, yamux) | webkit-js-v1.x | go-v0.42 | wss | noise | yamux | ✅ | 27s | 554 | 124 |
| webkit-js-v1.x x go-v0.42 (webrtc-direct) | webkit-js-v1.x | go-v0.42 | webrtc-direct | - | - | ✅ | 27s | 429 | 106 |
| webkit-js-v1.x x go-v0.43 (wss, noise, yamux) | webkit-js-v1.x | go-v0.43 | wss | noise | yamux | ✅ | 28s | 464 | 99 |
| webkit-js-v1.x x go-v0.43 (webrtc-direct) | webkit-js-v1.x | go-v0.43 | webrtc-direct | - | - | ✅ | 27s | 493 | 131 |
| webkit-js-v1.x x go-v0.44 (wss, noise, yamux) | webkit-js-v1.x | go-v0.44 | wss | noise | yamux | ✅ | 26s | 327 | 101 |
| webkit-js-v1.x x go-v0.44 (webrtc-direct) | webkit-js-v1.x | go-v0.44 | webrtc-direct | - | - | ✅ | 27s | 647 | 95 |
| webkit-js-v1.x x go-v0.45 (wss, noise, yamux) | webkit-js-v1.x | go-v0.45 | wss | noise | yamux | ✅ | 26s | 461 | 122 |
| webkit-js-v1.x x go-v0.45 (webrtc-direct) | webkit-js-v1.x | go-v0.45 | webrtc-direct | - | - | ✅ | 35s | 1052 | 108 |
| webkit-js-v1.x x python-v0.4 (wss, noise, mplex) | webkit-js-v1.x | python-v0.4 | wss | noise | mplex | ✅ | 40s | 998 | 207 |
| webkit-js-v1.x x python-v0.4 (wss, noise, yamux) | webkit-js-v1.x | python-v0.4 | wss | noise | yamux | ✅ | 39s | 830 | 271 |
| webkit-js-v1.x x chromium-js-v1.x (webrtc) | webkit-js-v1.x | chromium-js-v1.x | webrtc | - | - | ✅ | 42s | 2021 | 162 |
| webkit-js-v1.x x chromium-js-v2.x (webrtc) | webkit-js-v1.x | chromium-js-v2.x | webrtc | - | - | ✅ | 42s | 1773 | 218 |
| webkit-js-v1.x x firefox-js-v1.x (webrtc) | webkit-js-v1.x | firefox-js-v1.x | webrtc | - | - | ✅ | 49s | 2220 | 196 |
| webkit-js-v1.x x webkit-js-v1.x (webrtc) | webkit-js-v1.x | webkit-js-v1.x | webrtc | - | - | ✅ | 43s | 2029 | 302 |
| webkit-js-v1.x x firefox-js-v2.x (webrtc) | webkit-js-v1.x | firefox-js-v2.x | webrtc | - | - | ✅ | 51s | 2075 | 112 |
| webkit-js-v1.x x webkit-js-v2.x (webrtc) | webkit-js-v1.x | webkit-js-v2.x | webrtc | - | - | ✅ | 38s | 1806 | 162 |
| webkit-js-v2.x x rust-v0.53 (webrtc-direct) | webkit-js-v2.x | rust-v0.53 | webrtc-direct | - | - | ✅ | 34s | 541 | 112 |
| webkit-js-v2.x x rust-v0.54 (webrtc-direct) | webkit-js-v2.x | rust-v0.54 | webrtc-direct | - | - | ✅ | 34s | 523 | 94 |
| webkit-js-v2.x x rust-v0.56 (webrtc-direct) | webkit-js-v2.x | rust-v0.56 | webrtc-direct | - | - | ✅ | 30s | 419 | 52 |
| webkit-js-v2.x x rust-v0.55 (webrtc-direct) | webkit-js-v2.x | rust-v0.55 | webrtc-direct | - | - | ✅ | 33s | 1429 | 48 |
| webkit-js-v2.x x go-v0.38 (wss, noise, yamux) | webkit-js-v2.x | go-v0.38 | wss | noise | yamux | ✅ | 29s | 506 | 117 |
| webkit-js-v2.x x go-v0.38 (webrtc-direct) | webkit-js-v2.x | go-v0.38 | webrtc-direct | - | - | ✅ | 27s | 460 | 59 |
| webkit-js-v2.x x go-v0.39 (wss, noise, yamux) | webkit-js-v2.x | go-v0.39 | wss | noise | yamux | ✅ | 27s | 443 | 112 |
| webkit-js-v2.x x go-v0.39 (webrtc-direct) | webkit-js-v2.x | go-v0.39 | webrtc-direct | - | - | ✅ | 28s | 466 | 78 |
| webkit-js-v2.x x go-v0.40 (wss, noise, yamux) | webkit-js-v2.x | go-v0.40 | wss | noise | yamux | ✅ | 28s | 445 | 142 |
| webkit-js-v2.x x go-v0.40 (webrtc-direct) | webkit-js-v2.x | go-v0.40 | webrtc-direct | - | - | ✅ | 29s | 533 | 67 |
| webkit-js-v2.x x go-v0.41 (wss, noise, yamux) | webkit-js-v2.x | go-v0.41 | wss | noise | yamux | ✅ | 29s | 417 | 103 |
| webkit-js-v2.x x go-v0.41 (webrtc-direct) | webkit-js-v2.x | go-v0.41 | webrtc-direct | - | - | ✅ | 29s | 432 | 102 |
| webkit-js-v2.x x go-v0.42 (wss, noise, yamux) | webkit-js-v2.x | go-v0.42 | wss | noise | yamux | ✅ | 29s | 521 | 122 |
| webkit-js-v2.x x go-v0.42 (webrtc-direct) | webkit-js-v2.x | go-v0.42 | webrtc-direct | - | - | ✅ | 28s | 403 | 56 |
| webkit-js-v2.x x go-v0.43 (wss, noise, yamux) | webkit-js-v2.x | go-v0.43 | wss | noise | yamux | ✅ | 27s | 535 | 114 |
| webkit-js-v2.x x go-v0.43 (webrtc-direct) | webkit-js-v2.x | go-v0.43 | webrtc-direct | - | - | ✅ | 30s | 603 | 90 |
| webkit-js-v2.x x go-v0.44 (wss, noise, yamux) | webkit-js-v2.x | go-v0.44 | wss | noise | yamux | ✅ | 30s | 502 | 177 |
| webkit-js-v2.x x go-v0.44 (webrtc-direct) | webkit-js-v2.x | go-v0.44 | webrtc-direct | - | - | ✅ | 31s | 551 | 131 |
| webkit-js-v2.x x go-v0.45 (wss, noise, yamux) | webkit-js-v2.x | go-v0.45 | wss | noise | yamux | ✅ | 31s | 670 | 185 |
| webkit-js-v2.x x go-v0.45 (webrtc-direct) | webkit-js-v2.x | go-v0.45 | webrtc-direct | - | - | ✅ | 32s | 604 | 85 |
| webkit-js-v2.x x python-v0.4 (wss, noise, mplex) | webkit-js-v2.x | python-v0.4 | wss | noise | mplex | ✅ | 33s | 861 | 169 |
| webkit-js-v2.x x python-v0.4 (wss, noise, yamux) | webkit-js-v2.x | python-v0.4 | wss | noise | yamux | ✅ | 35s | 585 | 189 |
| chromium-rust-v0.53 x rust-v0.53 (webrtc-direct) | chromium-rust-v0.53 | rust-v0.53 | webrtc-direct | - | - | ✅ | 9s | 364.0 | 0.5 |
| webkit-js-v2.x x chromium-js-v1.x (webrtc) | webkit-js-v2.x | chromium-js-v1.x | webrtc | - | - | ✅ | 39s | 3120 | 139 |
| chromium-rust-v0.53 x rust-v0.53 (ws, noise, mplex) | chromium-rust-v0.53 | rust-v0.53 | ws | noise | mplex | ✅ | 9s | 523.8 | 0.7 |
| chromium-rust-v0.53 x rust-v0.53 (ws, noise, yamux) | chromium-rust-v0.53 | rust-v0.53 | ws | noise | yamux | ✅ | 10s | 408.4 | 37.9 |
| chromium-rust-v0.53 x rust-v0.54 (webrtc-direct) | chromium-rust-v0.53 | rust-v0.54 | webrtc-direct | - | - | ✅ | 9s | 365.899 | 12.199 |
| chromium-rust-v0.53 x rust-v0.54 (ws, noise, mplex) | chromium-rust-v0.53 | rust-v0.54 | ws | noise | mplex | ✅ | 9s | 516.3 | 0.4 |
| webkit-js-v2.x x chromium-js-v2.x (webrtc) | webkit-js-v2.x | chromium-js-v2.x | webrtc | - | - | ✅ | 44s | 2180 | 238 |
| webkit-js-v2.x x firefox-js-v1.x (webrtc) | webkit-js-v2.x | firefox-js-v1.x | webrtc | - | - | ✅ | 46s | 1673 | 244 |
| chromium-rust-v0.53 x rust-v0.54 (ws, noise, yamux) | chromium-rust-v0.53 | rust-v0.54 | ws | noise | yamux | ✅ | 7s | 397.2 | 49.8 |
| chromium-rust-v0.53 x rust-v0.55 (webrtc-direct) | chromium-rust-v0.53 | rust-v0.55 | webrtc-direct | - | - | ✅ | 7s | 279.9 | 0.2 |
| webkit-js-v2.x x webkit-js-v1.x (webrtc) | webkit-js-v2.x | webkit-js-v1.x | webrtc | - | - | ✅ | 44s | 1183 | 98 |
| chromium-rust-v0.53 x rust-v0.55 (ws, noise, yamux) | chromium-rust-v0.53 | rust-v0.55 | ws | noise | yamux | ✅ | 7s | 349.4 | 4.2 |
| chromium-rust-v0.53 x rust-v0.55 (ws, noise, mplex) | chromium-rust-v0.53 | rust-v0.55 | ws | noise | mplex | ✅ | 7s | 442.6 | 0.4 |
| webkit-js-v2.x x firefox-js-v2.x (webrtc) | webkit-js-v2.x | firefox-js-v2.x | webrtc | - | - | ✅ | 48s | 833 | 39 |
| webkit-js-v2.x x webkit-js-v2.x (webrtc) | webkit-js-v2.x | webkit-js-v2.x | webrtc | - | - | ✅ | 42s | 570 | 43 |
| chromium-rust-v0.53 x rust-v0.56 (ws, noise, mplex) | chromium-rust-v0.53 | rust-v0.56 | ws | noise | mplex | ✅ | 5s | 423.6 | 0.5 |
| chromium-rust-v0.53 x rust-v0.56 (webrtc-direct) | chromium-rust-v0.53 | rust-v0.56 | webrtc-direct | - | - | ✅ | 6s | 1404.799 | 0.3 |
| chromium-rust-v0.53 x rust-v0.56 (ws, noise, yamux) | chromium-rust-v0.53 | rust-v0.56 | ws | noise | yamux | ✅ | 5s | 317.2 | 1.6 |
| chromium-rust-v0.53 x go-v0.38 (webrtc-direct) | chromium-rust-v0.53 | go-v0.38 | webrtc-direct | - | - | ✅ | 5s | 255.6 | 0.0 |
| chromium-rust-v0.53 x go-v0.38 (webtransport) | chromium-rust-v0.53 | go-v0.38 | webtransport | - | - | ✅ | 6s | 69.2 | 4.899 |
| chromium-rust-v0.53 x go-v0.38 (ws, noise, yamux) | chromium-rust-v0.53 | go-v0.38 | ws | noise | yamux | ✅ | 5s | 329.2 | 7.9 |
| chromium-rust-v0.53 x go-v0.39 (webtransport) | chromium-rust-v0.53 | go-v0.39 | webtransport | - | - | ✅ | 6s | 60.699 | 0.2 |
| chromium-rust-v0.53 x go-v0.39 (webrtc-direct) | chromium-rust-v0.53 | go-v0.39 | webrtc-direct | - | - | ✅ | 5s | 137.6 | 0.0 |
| chromium-rust-v0.53 x go-v0.39 (ws, noise, yamux) | chromium-rust-v0.53 | go-v0.39 | ws | noise | yamux | ✅ | 5s | 342.8 | 8.0 |
| chromium-rust-v0.53 x go-v0.40 (webtransport) | chromium-rust-v0.53 | go-v0.40 | webtransport | - | - | ✅ | 6s | 68.3 | 0.8 |
| chromium-rust-v0.53 x go-v0.40 (webrtc-direct) | chromium-rust-v0.53 | go-v0.40 | webrtc-direct | - | - | ✅ | 5s | 232.0 | 2.599 |
| chromium-rust-v0.53 x go-v0.41 (webtransport) | chromium-rust-v0.53 | go-v0.41 | webtransport | - | - | ✅ | 6s | 36.6 | 0.4 |
| chromium-rust-v0.53 x go-v0.40 (ws, noise, yamux) | chromium-rust-v0.53 | go-v0.40 | ws | noise | yamux | ✅ | 6s | 322.1 | 5.0 |
| chromium-rust-v0.53 x go-v0.41 (webrtc-direct) | chromium-rust-v0.53 | go-v0.41 | webrtc-direct | - | - | ✅ | 5s | 215.699 | 2.2 |
| chromium-rust-v0.53 x go-v0.41 (ws, noise, yamux) | chromium-rust-v0.53 | go-v0.41 | ws | noise | yamux | ✅ | 6s | 333.2 | 8.1 |
| chromium-rust-v0.53 x go-v0.42 (webtransport) | chromium-rust-v0.53 | go-v0.42 | webtransport | - | - | ✅ | 6s | 69.9 | 0.9 |
| chromium-rust-v0.53 x go-v0.42 (webrtc-direct) | chromium-rust-v0.53 | go-v0.42 | webrtc-direct | - | - | ✅ | 5s | 168.6 | 0.3 |
| chromium-rust-v0.53 x go-v0.42 (ws, noise, yamux) | chromium-rust-v0.53 | go-v0.42 | ws | noise | yamux | ✅ | 6s | 361.2 | 23.5 |
| chromium-rust-v0.53 x go-v0.43 (webtransport) | chromium-rust-v0.53 | go-v0.43 | webtransport | - | - | ✅ | 6s | 88.399 | 1.7 |
| chromium-rust-v0.53 x go-v0.43 (webrtc-direct) | chromium-rust-v0.53 | go-v0.43 | webrtc-direct | - | - | ✅ | 6s | 182.299 | 0.1 |
| chromium-rust-v0.53 x go-v0.43 (ws, noise, yamux) | chromium-rust-v0.53 | go-v0.43 | ws | noise | yamux | ✅ | 5s | 321.1 | 4.1 |
| chromium-rust-v0.53 x go-v0.44 (webtransport) | chromium-rust-v0.53 | go-v0.44 | webtransport | - | - | ✅ | 6s | 54.3 | 0.3 |
| chromium-rust-v0.53 x go-v0.44 (webrtc-direct) | chromium-rust-v0.53 | go-v0.44 | webrtc-direct | - | - | ✅ | 6s | 164.1 | 0.2 |
| chromium-rust-v0.53 x go-v0.44 (ws, noise, yamux) | chromium-rust-v0.53 | go-v0.44 | ws | noise | yamux | ✅ | 6s | 338.3 | 6.1 |
| chromium-rust-v0.53 x go-v0.45 (webtransport) | chromium-rust-v0.53 | go-v0.45 | webtransport | - | - | ✅ | 4s | 93.5 | 1.5 |
| chromium-rust-v0.53 x go-v0.45 (webrtc-direct) | chromium-rust-v0.53 | go-v0.45 | webrtc-direct | - | - | ✅ | 6s | 275.2 | 0.199 |
| chromium-rust-v0.53 x go-v0.45 (ws, noise, yamux) | chromium-rust-v0.53 | go-v0.45 | ws | noise | yamux | ✅ | 6s | 355.4 | 7.3 |
| chromium-rust-v0.53 x python-v0.4 (ws, noise, yamux) | chromium-rust-v0.53 | python-v0.4 | ws | noise | yamux | ✅ | 6s | 323.6 | 4.1 |
| chromium-rust-v0.53 x nim-v1.14 (ws, noise, mplex) | chromium-rust-v0.53 | nim-v1.14 | ws | noise | mplex | ✅ | 6s | 444.2 | 0.6 |
| chromium-rust-v0.53 x js-v1.x (ws, noise, mplex) | chromium-rust-v0.53 | js-v1.x | ws | noise | mplex | ✅ | 18s | 433.9 | 0.5 |
| chromium-rust-v0.53 x js-v1.x (ws, noise, yamux) | chromium-rust-v0.53 | js-v1.x | ws | noise | yamux | ✅ | 19s | 351.4 | 16.5 |
| chromium-rust-v0.53 x nim-v1.14 (ws, noise, yamux) | chromium-rust-v0.53 | nim-v1.14 | ws | noise | yamux | ✅ | 5s | 345.4 | 15.7 |
| chromium-rust-v0.53 x js-v2.x (ws, noise, mplex) | chromium-rust-v0.53 | js-v2.x | ws | noise | mplex | ✅ | 20s | 430.3 | 0.5 |
| chromium-rust-v0.53 x js-v2.x (ws, noise, yamux) | chromium-rust-v0.53 | js-v2.x | ws | noise | yamux | ✅ | 20s | 348.2 | 11.8 |
| chromium-rust-v0.53 x js-v3.x (ws, noise, mplex) | chromium-rust-v0.53 | js-v3.x | ws | noise | mplex | ✅ | 18s | 442.3 | 1.299 |
| chromium-rust-v0.53 x js-v3.x (ws, noise, yamux) | chromium-rust-v0.53 | js-v3.x | ws | noise | yamux | ✅ | 19s | 358.9 | 29.7 |
| chromium-rust-v0.54 x rust-v0.53 (webrtc-direct) | chromium-rust-v0.54 | rust-v0.53 | webrtc-direct | - | - | ✅ | 6s | 232.7 | 13.5 |
| chromium-rust-v0.53 x jvm-v1.2 (ws, noise, yamux) | chromium-rust-v0.53 | jvm-v1.2 | ws | noise | yamux | ✅ | 7s | 775.4 | 48.099 |
| chromium-rust-v0.54 x rust-v0.53 (ws, noise, mplex) | chromium-rust-v0.54 | rust-v0.53 | ws | noise | mplex | ✅ | 6s | 418.7 | 0.2 |
| chromium-rust-v0.54 x rust-v0.53 (ws, noise, yamux) | chromium-rust-v0.54 | rust-v0.53 | ws | noise | yamux | ✅ | 5s | 319.5 | 3.4 |
| chromium-rust-v0.54 x rust-v0.54 (ws, noise, mplex) | chromium-rust-v0.54 | rust-v0.54 | ws | noise | mplex | ✅ | 4s | 415.7 | 0.2 |
| chromium-rust-v0.54 x rust-v0.54 (webrtc-direct) | chromium-rust-v0.54 | rust-v0.54 | webrtc-direct | - | - | ✅ | 6s | 1352.7 | 0.0 |
| chromium-rust-v0.54 x rust-v0.54 (ws, noise, yamux) | chromium-rust-v0.54 | rust-v0.54 | ws | noise | yamux | ✅ | 4s | 320.4 | 1.5 |
| chromium-rust-v0.54 x rust-v0.55 (webrtc-direct) | chromium-rust-v0.54 | rust-v0.55 | webrtc-direct | - | - | ✅ | 4s | 204.8 | 0.3 |
| chromium-rust-v0.54 x rust-v0.55 (ws, noise, mplex) | chromium-rust-v0.54 | rust-v0.55 | ws | noise | mplex | ✅ | 4s | 421.9 | 0.3 |
| chromium-rust-v0.54 x rust-v0.55 (ws, noise, yamux) | chromium-rust-v0.54 | rust-v0.55 | ws | noise | yamux | ✅ | 4s | 323.1 | 2.7 |
| chromium-rust-v0.54 x rust-v0.56 (webrtc-direct) | chromium-rust-v0.54 | rust-v0.56 | webrtc-direct | - | - | ✅ | 4s | 175.2 | 0.0 |
| chromium-rust-v0.54 x rust-v0.56 (ws, noise, mplex) | chromium-rust-v0.54 | rust-v0.56 | ws | noise | mplex | ✅ | 5s | 417.9 | 0.3 |
| chromium-rust-v0.54 x rust-v0.56 (ws, noise, yamux) | chromium-rust-v0.54 | rust-v0.56 | ws | noise | yamux | ✅ | 4s | 321.4 | 2.7 |
| chromium-rust-v0.54 x go-v0.38 (webtransport) | chromium-rust-v0.54 | go-v0.38 | webtransport | - | - | ✅ | 4s | 45.4 | 0.3 |
| chromium-rust-v0.54 x go-v0.38 (webrtc-direct) | chromium-rust-v0.54 | go-v0.38 | webrtc-direct | - | - | ✅ | 5s | 138.5 | 0.1 |
| chromium-rust-v0.54 x go-v0.38 (ws, noise, yamux) | chromium-rust-v0.54 | go-v0.38 | ws | noise | yamux | ✅ | 5s | 328.2 | 6.5 |
| chromium-rust-v0.54 x go-v0.39 (webtransport) | chromium-rust-v0.54 | go-v0.39 | webtransport | - | - | ✅ | 5s | 53.4 | 0.3 |
| chromium-rust-v0.54 x go-v0.39 (webrtc-direct) | chromium-rust-v0.54 | go-v0.39 | webrtc-direct | - | - | ✅ | 4s | 149.5 | 0.1 |
| chromium-rust-v0.54 x go-v0.39 (ws, noise, yamux) | chromium-rust-v0.54 | go-v0.39 | ws | noise | yamux | ✅ | 5s | 326.0 | 7.3 |
| chromium-rust-v0.54 x go-v0.40 (webtransport) | chromium-rust-v0.54 | go-v0.40 | webtransport | - | - | ✅ | 4s | 52.6 | 0.0 |
| chromium-rust-v0.54 x go-v0.40 (webrtc-direct) | chromium-rust-v0.54 | go-v0.40 | webrtc-direct | - | - | ✅ | 4s | 149.5 | 0.1 |
| chromium-rust-v0.54 x go-v0.41 (webtransport) | chromium-rust-v0.54 | go-v0.41 | webtransport | - | - | ✅ | 5s | 46.7 | 0.2 |
| chromium-rust-v0.54 x go-v0.40 (ws, noise, yamux) | chromium-rust-v0.54 | go-v0.40 | ws | noise | yamux | ✅ | 5s | 321.0 | 2.6 |
| chromium-rust-v0.54 x go-v0.41 (webrtc-direct) | chromium-rust-v0.54 | go-v0.41 | webrtc-direct | - | - | ✅ | 4s | 162.9 | 0.1 |
| chromium-rust-v0.54 x go-v0.41 (ws, noise, yamux) | chromium-rust-v0.54 | go-v0.41 | ws | noise | yamux | ✅ | 4s | 326.4 | 7.6 |
| chromium-rust-v0.54 x go-v0.42 (webtransport) | chromium-rust-v0.54 | go-v0.42 | webtransport | - | - | ✅ | 4s | 64.1 | 0.3 |
| chromium-rust-v0.54 x go-v0.42 (webrtc-direct) | chromium-rust-v0.54 | go-v0.42 | webrtc-direct | - | - | ✅ | 5s | 141.0 | 0.0 |
| chromium-rust-v0.54 x go-v0.42 (ws, noise, yamux) | chromium-rust-v0.54 | go-v0.42 | ws | noise | yamux | ✅ | 5s | 320.5 | 3.1 |
| chromium-rust-v0.54 x go-v0.43 (webtransport) | chromium-rust-v0.54 | go-v0.43 | webtransport | - | - | ✅ | 4s | 47.6 | 0.4 |
| chromium-rust-v0.54 x go-v0.43 (webrtc-direct) | chromium-rust-v0.54 | go-v0.43 | webrtc-direct | - | - | ✅ | 4s | 109.5 | 0.1 |
| chromium-rust-v0.54 x go-v0.43 (ws, noise, yamux) | chromium-rust-v0.54 | go-v0.43 | ws | noise | yamux | ✅ | 4s | 315.1 | 2.9 |
| chromium-rust-v0.54 x go-v0.44 (webtransport) | chromium-rust-v0.54 | go-v0.44 | webtransport | - | - | ✅ | 4s | 55.4 | 0.3 |
| chromium-rust-v0.54 x go-v0.44 (webrtc-direct) | chromium-rust-v0.54 | go-v0.44 | webrtc-direct | - | - | ✅ | 4s | 156.0 | 0.1 |
| chromium-rust-v0.54 x go-v0.44 (ws, noise, yamux) | chromium-rust-v0.54 | go-v0.44 | ws | noise | yamux | ✅ | 4s | 322.4 | 5.3 |
| chromium-rust-v0.54 x go-v0.45 (webtransport) | chromium-rust-v0.54 | go-v0.45 | webtransport | - | - | ✅ | 4s | 35.0 | 0.2 |
| chromium-rust-v0.54 x go-v0.45 (webrtc-direct) | chromium-rust-v0.54 | go-v0.45 | webrtc-direct | - | - | ✅ | 4s | 211.6 | 0.1 |
| chromium-rust-v0.54 x go-v0.45 (ws, noise, yamux) | chromium-rust-v0.54 | go-v0.45 | ws | noise | yamux | ✅ | 4s | 324.7 | 3.9 |
| chromium-rust-v0.54 x python-v0.4 (ws, noise, yamux) | chromium-rust-v0.54 | python-v0.4 | ws | noise | yamux | ✅ | 4s | 323.0 | 5.5 |
| chromium-rust-v0.54 x python-v0.4 (ws, noise, mplex) | chromium-rust-v0.54 | python-v0.4 | ws | noise | mplex | ✅ | 14s | 10415.1 | 0.6 |
| chromium-rust-v0.54 x js-v1.x (ws, noise, mplex) | chromium-rust-v0.54 | js-v1.x | ws | noise | mplex | ✅ | 15s | 437.3 | 0.5 |
| chromium-rust-v0.54 x js-v1.x (ws, noise, yamux) | chromium-rust-v0.54 | js-v1.x | ws | noise | yamux | ✅ | 16s | 339.6 | 16.7 |
| chromium-rust-v0.54 x js-v2.x (ws, noise, mplex) | chromium-rust-v0.54 | js-v2.x | ws | noise | mplex | ✅ | 16s | 427.9 | 0.5 |
| chromium-rust-v0.54 x js-v2.x (ws, noise, yamux) | chromium-rust-v0.54 | js-v2.x | ws | noise | yamux | ✅ | 16s | 339.9 | 10.5 |
| chromium-rust-v0.54 x js-v3.x (ws, noise, mplex) | chromium-rust-v0.54 | js-v3.x | ws | noise | mplex | ✅ | 15s | 426.7 | 0.9 |
| chromium-rust-v0.54 x nim-v1.14 (ws, noise, mplex) | chromium-rust-v0.54 | nim-v1.14 | ws | noise | mplex | ✅ | 4s | 425.7 | 0.3 |
| chromium-rust-v0.54 x nim-v1.14 (ws, noise, yamux) | chromium-rust-v0.54 | nim-v1.14 | ws | noise | yamux | ✅ | 4s | 332.6 | 5.3 |
| chromium-rust-v0.54 x jvm-v1.2 (ws, noise, yamux) | chromium-rust-v0.54 | jvm-v1.2 | ws | noise | yamux | ✅ | 6s | 609.9 | 21.5 |
| chromium-rust-v0.54 x js-v3.x (ws, noise, yamux) | chromium-rust-v0.54 | js-v3.x | ws | noise | yamux | ✅ | 12s | 313.4 | 3.5 |
| chromium-rust-v0.54 x jvm-v1.2 (ws, noise, mplex) | chromium-rust-v0.54 | jvm-v1.2 | ws | noise | mplex | ✅ | 17s | 11031.2 | 1.5 |
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
| **rust-v0.54** | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **rust-v0.55** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
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
| **rust-v0.56** | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
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

*Generated: 2025-12-28T03:53:25Z*
<!-- TEST_RESULTS_END -->

