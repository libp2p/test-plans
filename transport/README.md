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

## Test Pass: `transport-interop-030128-27-12-2025`

**Summary:**
- **Total Tests:** 2302
- **Passed:** ✅ 2251
- **Failed:** ❌ 51
- **Pass Rate:** 97.8%

**Environment:**
- **Platform:** x86_64
- **OS:** Linux
- **Workers:** 8
- **Duration:** 3857s

**Timestamps:**
- **Started:** 2025-12-27T03:01:28Z
- **Completed:** 2025-12-27T04:05:45Z

---

## Test Results

| Test | Dialer | Listener | Transport | Secure | Muxer | Status | Duration | Handshake+RTT (ms) | Ping RTT (ms) |
|------|--------|----------|-----------|--------|-------|--------|----------|-------------------|---------------|
| rust-v0.53 x rust-v0.53 (ws, tls, yamux) | rust-v0.53 | rust-v0.53 | ws | tls | yamux | ✅ | 4s | 269.87 | 91.805 |
| rust-v0.53 x rust-v0.53 (ws, noise, mplex) | rust-v0.53 | rust-v0.53 | ws | noise | mplex | ✅ | 4s | 268.629 | 92.784 |
| rust-v0.53 x rust-v0.53 (tcp, tls, yamux) | rust-v0.53 | rust-v0.53 | tcp | tls | yamux | ✅ | 5s | 139.893 | 89.42 |
| rust-v0.53 x rust-v0.53 (ws, noise, yamux) | rust-v0.53 | rust-v0.53 | ws | noise | yamux | ✅ | 5s | 267.819 | 92.161 |
| rust-v0.53 x rust-v0.53 (tcp, tls, mplex) | rust-v0.53 | rust-v0.53 | tcp | tls | mplex | ✅ | 5s | 45.038 | 0.079 |
| rust-v0.53 x rust-v0.53 (tcp, noise, yamux) | rust-v0.53 | rust-v0.53 | tcp | noise | yamux | ✅ | 6s | 131.448 | 43.936 |
| rust-v0.53 x rust-v0.53 (ws, tls, mplex) | rust-v0.53 | rust-v0.53 | ws | tls | mplex | ✅ | 6s | 264.974 | 91.832 |
| rust-v0.53 x rust-v0.53 (tcp, noise, mplex) | rust-v0.53 | rust-v0.53 | tcp | noise | mplex | ✅ | 7s | 90.36 | 0.103 |
| rust-v0.53 x rust-v0.53 (quic-v1) | rust-v0.53 | rust-v0.53 | quic-v1 | - | - | ✅ | 3s | 4.095 | 0.37 |
| rust-v0.53 x rust-v0.54 (ws, tls, mplex) | rust-v0.53 | rust-v0.54 | ws | tls | mplex | ✅ | 4s | 264.809 | 91.883 |
| rust-v0.53 x rust-v0.54 (ws, tls, yamux) | rust-v0.53 | rust-v0.54 | ws | tls | yamux | ✅ | 5s | 279.52 | 95.841 |
| rust-v0.53 x rust-v0.54 (tcp, tls, mplex) | rust-v0.53 | rust-v0.54 | tcp | tls | mplex | ✅ | 4s | 44.384 | 0.171 |
| rust-v0.53 x rust-v0.54 (ws, noise, mplex) | rust-v0.53 | rust-v0.54 | ws | noise | mplex | ✅ | 5s | 279.37 | 92.074 |
| rust-v0.53 x rust-v0.54 (ws, noise, yamux) | rust-v0.53 | rust-v0.54 | ws | noise | yamux | ✅ | 6s | 272.774 | 95.709 |
| rust-v0.53 x rust-v0.54 (tcp, tls, yamux) | rust-v0.53 | rust-v0.54 | tcp | tls | yamux | ✅ | 5s | 132.326 | 87.776 |
| rust-v0.53 x rust-v0.54 (tcp, noise, mplex) | rust-v0.53 | rust-v0.54 | tcp | noise | mplex | ✅ | 4s | 93.256 | 0.117 |
| rust-v0.53 x rust-v0.54 (tcp, noise, yamux) | rust-v0.53 | rust-v0.54 | tcp | noise | yamux | ✅ | 4s | 139.601 | 43.971 |
| rust-v0.53 x rust-v0.54 (quic-v1) | rust-v0.53 | rust-v0.54 | quic-v1 | - | - | ✅ | 4s | 4.337 | 0.659 |
| rust-v0.53 x rust-v0.54 (webrtc-direct) | rust-v0.53 | rust-v0.54 | webrtc-direct | - | - | ✅ | 4s | 217.187 | 0.498 |
| rust-v0.53 x rust-v0.55 (ws, tls, mplex) | rust-v0.53 | rust-v0.55 | ws | tls | mplex | ✅ | 4s | 134.852 | 42.743 |
| rust-v0.53 x rust-v0.55 (ws, noise, mplex) | rust-v0.53 | rust-v0.55 | ws | noise | mplex | ✅ | 4s | 135.45 | 47.069 |
| rust-v0.53 x rust-v0.55 (ws, tls, yamux) | rust-v0.53 | rust-v0.55 | ws | tls | yamux | ✅ | 5s | 131.384 | 42.082 |
| rust-v0.53 x rust-v0.55 (ws, noise, yamux) | rust-v0.53 | rust-v0.55 | ws | noise | yamux | ✅ | 4s | 134.23 | 43.284 |
| rust-v0.53 x rust-v0.55 (tcp, tls, mplex) | rust-v0.53 | rust-v0.55 | tcp | tls | mplex | ✅ | 4s | 3.489 | 0.059 |
| rust-v0.53 x rust-v0.55 (tcp, tls, yamux) | rust-v0.53 | rust-v0.55 | tcp | tls | yamux | ✅ | 4s | 49.974 | 44.617 |
| rust-v0.53 x rust-v0.55 (tcp, noise, mplex) | rust-v0.53 | rust-v0.55 | tcp | noise | mplex | ✅ | 4s | 95.249 | 46.219 |
| rust-v0.53 x rust-v0.55 (tcp, noise, yamux) | rust-v0.53 | rust-v0.55 | tcp | noise | yamux | ✅ | 4s | 47.373 | 2.055 |
| rust-v0.53 x rust-v0.55 (quic-v1) | rust-v0.53 | rust-v0.55 | quic-v1 | - | - | ✅ | 4s | 3.594 | 0.173 |
| rust-v0.53 x rust-v0.55 (webrtc-direct) | rust-v0.53 | rust-v0.55 | webrtc-direct | - | - | ✅ | 4s | 222.449 | 0.405 |
| rust-v0.53 x rust-v0.56 (ws, tls, yamux) | rust-v0.53 | rust-v0.56 | ws | tls | yamux | ✅ | 4s | 132.926 | 42.238 |
| rust-v0.53 x rust-v0.56 (ws, tls, mplex) | rust-v0.53 | rust-v0.56 | ws | tls | mplex | ✅ | 5s | 136.943 | 46.642 |
| rust-v0.53 x rust-v0.56 (ws, noise, mplex) | rust-v0.53 | rust-v0.56 | ws | noise | mplex | ✅ | 4s | 89.472 | 0.075 |
| rust-v0.53 x rust-v0.56 (ws, noise, yamux) | rust-v0.53 | rust-v0.56 | ws | noise | yamux | ✅ | 4s | 135.536 | 42.976 |
| rust-v0.53 x rust-v0.56 (tcp, tls, mplex) | rust-v0.53 | rust-v0.56 | tcp | tls | mplex | ✅ | 5s | 4.813 | 0.08 |
| rust-v0.53 x rust-v0.56 (tcp, tls, yamux) | rust-v0.53 | rust-v0.56 | tcp | tls | yamux | ✅ | 4s | 43.201 | 40.702 |
| rust-v0.53 x rust-v0.56 (tcp, noise, mplex) | rust-v0.53 | rust-v0.56 | tcp | noise | mplex | ✅ | 5s | 42.62 | 0.068 |
| rust-v0.53 x rust-v0.56 (quic-v1) | rust-v0.53 | rust-v0.56 | quic-v1 | - | - | ✅ | 3s | 3.195 | 0.264 |
| rust-v0.53 x rust-v0.56 (tcp, noise, yamux) | rust-v0.53 | rust-v0.56 | tcp | noise | yamux | ✅ | 4s | 92.08 | 43.149 |
| rust-v0.53 x rust-v0.56 (webrtc-direct) | rust-v0.53 | rust-v0.56 | webrtc-direct | - | - | ✅ | 5s | 206.853 | 0.247 |
| rust-v0.53 x go-v0.38 (ws, tls, yamux) | rust-v0.53 | go-v0.38 | ws | tls | yamux | ✅ | 4s | 96.304 | 0.737 |
| rust-v0.53 x go-v0.38 (ws, noise, yamux) | rust-v0.53 | go-v0.38 | ws | noise | yamux | ✅ | 4s | 91.387 | 0.277 |
| rust-v0.53 x go-v0.38 (tcp, tls, yamux) | rust-v0.53 | go-v0.38 | tcp | tls | yamux | ✅ | 4s | 3.364 | 0.139 |
| rust-v0.53 x go-v0.38 (tcp, noise, yamux) | rust-v0.53 | go-v0.38 | tcp | noise | yamux | ✅ | 5s | 44.939 | 0.222 |
| rust-v0.53 x go-v0.38 (quic-v1) | rust-v0.53 | go-v0.38 | quic-v1 | - | - | ✅ | 4s | 8.702 | 0.737 |
| rust-v0.53 x go-v0.38 (webrtc-direct) | rust-v0.53 | go-v0.38 | webrtc-direct | - | - | ✅ | 4s | 20.726 | 0.227 |
| rust-v0.53 x go-v0.39 (ws, tls, yamux) | rust-v0.53 | go-v0.39 | ws | tls | yamux | ✅ | 4s | 88.189 | 0.242 |
| rust-v0.53 x go-v0.39 (ws, noise, yamux) | rust-v0.53 | go-v0.39 | ws | noise | yamux | ✅ | 5s | 87.53 | 0.305 |
| rust-v0.53 x go-v0.39 (tcp, tls, yamux) | rust-v0.53 | go-v0.39 | tcp | tls | yamux | ✅ | 4s | 4.311 | 0.549 |
| rust-v0.53 x go-v0.39 (tcp, noise, yamux) | rust-v0.53 | go-v0.39 | tcp | noise | yamux | ✅ | 4s | 9.407 | 0.316 |
| rust-v0.53 x go-v0.39 (webrtc-direct) | rust-v0.53 | go-v0.39 | webrtc-direct | - | - | ✅ | 4s | 16.079 | 0.272 |
| rust-v0.53 x go-v0.39 (quic-v1) | rust-v0.53 | go-v0.39 | quic-v1 | - | - | ✅ | 5s | 6.165 | 0.406 |
| rust-v0.53 x go-v0.40 (ws, tls, yamux) | rust-v0.53 | go-v0.40 | ws | tls | yamux | ✅ | 4s | 91.052 | 0.214 |
| rust-v0.53 x go-v0.40 (ws, noise, yamux) | rust-v0.53 | go-v0.40 | ws | noise | yamux | ✅ | 4s | 133.344 | 45.884 |
| rust-v0.53 x go-v0.40 (tcp, tls, yamux) | rust-v0.53 | go-v0.40 | tcp | tls | yamux | ✅ | 4s | 3.622 | 0.361 |
| rust-v0.53 x go-v0.40 (tcp, noise, yamux) | rust-v0.53 | go-v0.40 | tcp | noise | yamux | ✅ | 4s | 4.541 | 0.27 |
| rust-v0.53 x go-v0.40 (quic-v1) | rust-v0.53 | go-v0.40 | quic-v1 | - | - | ✅ | 4s | 4.895 | 0.265 |
| rust-v0.53 x go-v0.40 (webrtc-direct) | rust-v0.53 | go-v0.40 | webrtc-direct | - | - | ✅ | 4s | 15.22 | 0.451 |
| rust-v0.53 x go-v0.41 (ws, tls, yamux) | rust-v0.53 | go-v0.41 | ws | tls | yamux | ✅ | 4s | 130.624 | 41.694 |
| rust-v0.53 x go-v0.41 (ws, noise, yamux) | rust-v0.53 | go-v0.41 | ws | noise | yamux | ✅ | 5s | 91.18 | 0.244 |
| rust-v0.53 x go-v0.41 (tcp, noise, yamux) | rust-v0.53 | go-v0.41 | tcp | noise | yamux | ✅ | 4s | 2.077 | 0.075 |
| rust-v0.53 x go-v0.41 (tcp, tls, yamux) | rust-v0.53 | go-v0.41 | tcp | tls | yamux | ✅ | 5s | 43.948 | 41.038 |
| rust-v0.53 x go-v0.41 (quic-v1) | rust-v0.53 | go-v0.41 | quic-v1 | - | - | ✅ | 5s | 7.518 | 0.185 |
| rust-v0.53 x go-v0.41 (webrtc-direct) | rust-v0.53 | go-v0.41 | webrtc-direct | - | - | ✅ | 4s | 9.635 | 0.317 |
| rust-v0.53 x go-v0.42 (ws, tls, yamux) | rust-v0.53 | go-v0.42 | ws | tls | yamux | ✅ | 4s | 92.018 | 0.388 |
| rust-v0.53 x go-v0.42 (ws, noise, yamux) | rust-v0.53 | go-v0.42 | ws | noise | yamux | ✅ | 4s | 92.764 | 0.343 |
| rust-v0.53 x go-v0.42 (tcp, tls, yamux) | rust-v0.53 | go-v0.42 | tcp | tls | yamux | ✅ | 4s | 3.177 | 0.214 |
| rust-v0.53 x go-v0.42 (quic-v1) | rust-v0.53 | go-v0.42 | quic-v1 | - | - | ✅ | 3s | 5.293 | 0.315 |
| rust-v0.53 x go-v0.42 (tcp, noise, yamux) | rust-v0.53 | go-v0.42 | tcp | noise | yamux | ✅ | 5s | 3.012 | 0.196 |
| rust-v0.53 x go-v0.42 (webrtc-direct) | rust-v0.53 | go-v0.42 | webrtc-direct | - | - | ✅ | 4s | 12.024 | 0.448 |
| rust-v0.53 x go-v0.43 (ws, tls, yamux) | rust-v0.53 | go-v0.43 | ws | tls | yamux | ✅ | 4s | 98.44 | 0.693 |
| rust-v0.53 x go-v0.43 (ws, noise, yamux) | rust-v0.53 | go-v0.43 | ws | noise | yamux | ✅ | 4s | 91.94 | 0.54 |
| rust-v0.53 x go-v0.43 (tcp, tls, yamux) | rust-v0.53 | go-v0.43 | tcp | tls | yamux | ✅ | 4s | 6.09 | 1.183 |
| rust-v0.53 x go-v0.43 (tcp, noise, yamux) | rust-v0.53 | go-v0.43 | tcp | noise | yamux | ✅ | 5s | 3.435 | 0.559 |
| rust-v0.53 x go-v0.43 (quic-v1) | rust-v0.53 | go-v0.43 | quic-v1 | - | - | ✅ | 4s | 7.48 | 0.436 |
| rust-v0.53 x go-v0.43 (webrtc-direct) | rust-v0.53 | go-v0.43 | webrtc-direct | - | - | ✅ | 5s | 14.959 | 0.915 |
| rust-v0.53 x go-v0.44 (ws, noise, yamux) | rust-v0.53 | go-v0.44 | ws | noise | yamux | ✅ | 4s | 88.484 | 0.18 |
| rust-v0.53 x go-v0.44 (ws, tls, yamux) | rust-v0.53 | go-v0.44 | ws | tls | yamux | ✅ | 5s | 92.9 | 0.391 |
| rust-v0.53 x go-v0.44 (tcp, tls, yamux) | rust-v0.53 | go-v0.44 | tcp | tls | yamux | ✅ | 5s | 57.164 | 41.484 |
| rust-v0.53 x go-v0.44 (tcp, noise, yamux) | rust-v0.53 | go-v0.44 | tcp | noise | yamux | ✅ | 4s | 4.652 | 0.148 |
| rust-v0.53 x go-v0.44 (quic-v1) | rust-v0.53 | go-v0.44 | quic-v1 | - | - | ✅ | 5s | 4.467 | 0.181 |
| rust-v0.53 x go-v0.44 (webrtc-direct) | rust-v0.53 | go-v0.44 | webrtc-direct | - | - | ✅ | 4s | 29.502 | 0.432 |
| rust-v0.53 x go-v0.45 (ws, noise, yamux) | rust-v0.53 | go-v0.45 | ws | noise | yamux | ✅ | 4s | 136.393 | 46.316 |
| rust-v0.53 x go-v0.45 (ws, tls, yamux) | rust-v0.53 | go-v0.45 | ws | tls | yamux | ✅ | 5s | 94.187 | 0.448 |
| rust-v0.53 x go-v0.45 (tcp, tls, yamux) | rust-v0.53 | go-v0.45 | tcp | tls | yamux | ✅ | 5s | 3.022 | 0.45 |
| rust-v0.53 x go-v0.45 (tcp, noise, yamux) | rust-v0.53 | go-v0.45 | tcp | noise | yamux | ✅ | 4s | 2.717 | 0.165 |
| rust-v0.53 x go-v0.45 (quic-v1) | rust-v0.53 | go-v0.45 | quic-v1 | - | - | ✅ | 4s | 6.262 | 0.854 |
| rust-v0.53 x go-v0.45 (webrtc-direct) | rust-v0.53 | go-v0.45 | webrtc-direct | - | - | ✅ | 5s | 40.395 | 0.291 |
| rust-v0.53 x python-v0.4 (ws, noise, mplex) | rust-v0.53 | python-v0.4 | ws | noise | mplex | ✅ | 4s | 99.239 | 0.709 |
| rust-v0.53 x python-v0.4 (ws, noise, yamux) | rust-v0.53 | python-v0.4 | ws | noise | yamux | ✅ | 4s | 111.105 | 1.803 |
| rust-v0.53 x python-v0.4 (tcp, noise, mplex) | rust-v0.53 | python-v0.4 | tcp | noise | mplex | ✅ | 4s | 13.773 | 0.977 |
| rust-v0.53 x python-v0.4 (quic-v1) | rust-v0.53 | python-v0.4 | quic-v1 | - | - | ✅ | 4s | 31.814 | 2.583 |
| rust-v0.53 x python-v0.4 (tcp, noise, yamux) | rust-v0.53 | python-v0.4 | tcp | noise | yamux | ✅ | 5s | 15.261 | 0.95 |
| rust-v0.53 x js-v1.x (ws, noise, mplex) | rust-v0.53 | js-v1.x | ws | noise | mplex | ✅ | 15s | 217.54 | 15.28 |
| rust-v0.53 x js-v1.x (ws, noise, yamux) | rust-v0.53 | js-v1.x | ws | noise | yamux | ✅ | 15s | 201.393 | 14.243 |
| rust-v0.53 x js-v1.x (tcp, noise, mplex) | rust-v0.53 | js-v1.x | tcp | noise | mplex | ✅ | 15s | 119.12 | 6.372 |
| rust-v0.53 x js-v1.x (tcp, noise, yamux) | rust-v0.53 | js-v1.x | tcp | noise | yamux | ✅ | 15s | 134.304 | 11.971 |
| rust-v0.53 x js-v2.x (ws, noise, mplex) | rust-v0.53 | js-v2.x | ws | noise | mplex | ✅ | 15s | 197.385 | 9.587 |
| rust-v0.53 x js-v2.x (ws, noise, yamux) | rust-v0.53 | js-v2.x | ws | noise | yamux | ✅ | 15s | 168.562 | 14.17 |
| rust-v0.53 x js-v2.x (tcp, noise, mplex) | rust-v0.53 | js-v2.x | tcp | noise | mplex | ✅ | 15s | 110.576 | 4.377 |
| rust-v0.53 x nim-v1.14 (ws, noise, mplex) | rust-v0.53 | nim-v1.14 | ws | noise | mplex | ✅ | 4s | 285.158 | 87.75 |
| rust-v0.53 x nim-v1.14 (ws, noise, yamux) | rust-v0.53 | nim-v1.14 | ws | noise | yamux | ✅ | 4s | 241.756 | 47.603 |
| rust-v0.53 x nim-v1.14 (tcp, noise, mplex) | rust-v0.53 | nim-v1.14 | tcp | noise | mplex | ✅ | 4s | 147.736 | 0.479 |
| rust-v0.53 x nim-v1.14 (tcp, noise, yamux) | rust-v0.53 | nim-v1.14 | tcp | noise | yamux | ✅ | 4s | 194.846 | 49.207 |
| rust-v0.53 x js-v2.x (tcp, noise, yamux) | rust-v0.53 | js-v2.x | tcp | noise | yamux | ✅ | 15s | 147.357 | 12.917 |
| rust-v0.53 x js-v3.x (ws, noise, mplex) | rust-v0.53 | js-v3.x | ws | noise | mplex | ✅ | 15s | 150.397 | 10.653 |
| rust-v0.53 x js-v3.x (ws, noise, yamux) | rust-v0.53 | js-v3.x | ws | noise | yamux | ✅ | 15s | 189.835 | 21.898 |
| rust-v0.53 x js-v3.x (tcp, noise, mplex) | rust-v0.53 | js-v3.x | tcp | noise | mplex | ✅ | 15s | 122.368 | 16.072 |
| rust-v0.53 x js-v3.x (tcp, noise, yamux) | rust-v0.53 | js-v3.x | tcp | noise | yamux | ✅ | 15s | 126.008 | 34.125 |
| rust-v0.53 x jvm-v1.2 (ws, tls, mplex) | rust-v0.53 | jvm-v1.2 | ws | tls | mplex | ✅ | 9s | 3635.806 | 116.916 |
| rust-v0.53 x jvm-v1.2 (ws, noise, mplex) | rust-v0.53 | jvm-v1.2 | ws | noise | mplex | ✅ | 10s | 1466.968 | 18.116 |
| rust-v0.53 x jvm-v1.2 (ws, noise, yamux) | rust-v0.53 | jvm-v1.2 | ws | noise | yamux | ✅ | 10s | 1582.202 | 49.652 |
| rust-v0.53 x jvm-v1.2 (ws, tls, yamux) | rust-v0.53 | jvm-v1.2 | ws | tls | yamux | ✅ | 12s | 4022.74 | 25.748 |
| rust-v0.53 x jvm-v1.2 (tcp, noise, mplex) | rust-v0.53 | jvm-v1.2 | tcp | noise | mplex | ✅ | 9s | 863.369 | 6.33 |
| rust-v0.53 x jvm-v1.2 (tcp, tls, mplex) | rust-v0.53 | jvm-v1.2 | tcp | tls | mplex | ✅ | 12s | 2672.407 | 2.957 |
| rust-v0.53 x jvm-v1.2 (tcp, tls, yamux) | rust-v0.53 | jvm-v1.2 | tcp | tls | yamux | ✅ | 11s | 2646.289 | 50.53 |
| rust-v0.53 x c-v0.0.1 (tcp, noise, mplex) | rust-v0.53 | c-v0.0.1 | tcp | noise | mplex | ✅ | 4s | 52.881 | 3.442 |
| rust-v0.53 x jvm-v1.2 (tcp, noise, yamux) | rust-v0.53 | jvm-v1.2 | tcp | noise | yamux | ✅ | 6s | 729.605 | 3.68 |
| rust-v0.53 x c-v0.0.1 (tcp, noise, yamux) | rust-v0.53 | c-v0.0.1 | tcp | noise | yamux | ✅ | 4s | 104.151 | 1.79 |
| rust-v0.53 x zig-v0.0.1 (quic-v1) | rust-v0.53 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 4s | - | - |
| rust-v0.53 x dotnet-v1.0 (tcp, noise, yamux) | rust-v0.53 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 4s | 114.213 | 9.022 |
| rust-v0.53 x jvm-v1.2 (quic-v1) | rust-v0.53 | jvm-v1.2 | quic-v1 | - | - | ✅ | 9s | 1226.888 | 2.548 |
| rust-v0.53 x eth-p2p-z-v0.0.1 (quic-v1) | rust-v0.53 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 4s | 7.333 | 0.256 |
| rust-v0.54 x rust-v0.53 (ws, tls, mplex) | rust-v0.54 | rust-v0.53 | ws | tls | mplex | ✅ | 4s | 269.906 | 87.845 |
| rust-v0.54 x rust-v0.53 (ws, tls, yamux) | rust-v0.54 | rust-v0.53 | ws | tls | yamux | ✅ | 4s | 269.444 | 87.6 |
| rust-v0.54 x rust-v0.53 (ws, noise, mplex) | rust-v0.54 | rust-v0.53 | ws | noise | mplex | ✅ | 3s | 270.353 | 91.778 |
| rust-v0.54 x rust-v0.53 (tcp, tls, mplex) | rust-v0.54 | rust-v0.53 | tcp | tls | mplex | ✅ | 3s | 44.519 | 0.125 |
| rust-v0.54 x rust-v0.53 (ws, noise, yamux) | rust-v0.54 | rust-v0.53 | ws | noise | yamux | ✅ | 4s | 272.708 | 87.905 |
| rust-v0.54 x rust-v0.53 (tcp, noise, mplex) | rust-v0.54 | rust-v0.53 | tcp | noise | mplex | ✅ | 3s | 89.637 | 0.134 |
| rust-v0.54 x rust-v0.53 (tcp, tls, yamux) | rust-v0.54 | rust-v0.53 | tcp | tls | yamux | ✅ | 5s | 148.151 | 91.465 |
| rust-v0.54 x rust-v0.53 (tcp, noise, yamux) | rust-v0.54 | rust-v0.53 | tcp | noise | yamux | ✅ | 4s | 135.278 | 44.018 |
| rust-v0.54 x rust-v0.53 (quic-v1) | rust-v0.54 | rust-v0.53 | quic-v1 | - | - | ✅ | 4s | 6.849 | 0.484 |
| rust-v0.54 x rust-v0.53 (webrtc-direct) | rust-v0.54 | rust-v0.53 | webrtc-direct | - | - | ✅ | 4s | 238.828 | 0.641 |
| rust-v0.53 x c-v0.0.1 (quic-v1) | rust-v0.53 | c-v0.0.1 | quic-v1 | - | - | ❌ | 14s | - | - |
| rust-v0.54 x rust-v0.54 (ws, tls, mplex) | rust-v0.54 | rust-v0.54 | ws | tls | mplex | ✅ | 5s | 270.054 | 87.906 |
| rust-v0.54 x rust-v0.54 (ws, tls, yamux) | rust-v0.54 | rust-v0.54 | ws | tls | yamux | ✅ | 4s | 266.436 | 87.781 |
| rust-v0.54 x rust-v0.54 (ws, noise, mplex) | rust-v0.54 | rust-v0.54 | ws | noise | mplex | ✅ | 5s | 272.191 | 92.172 |
| rust-v0.54 x rust-v0.54 (tcp, tls, mplex) | rust-v0.54 | rust-v0.54 | tcp | tls | mplex | ✅ | 4s | 51.192 | 0.147 |
| rust-v0.54 x rust-v0.54 (ws, noise, yamux) | rust-v0.54 | rust-v0.54 | ws | noise | yamux | ✅ | 4s | 268.165 | 87.697 |
| rust-v0.54 x rust-v0.54 (tcp, tls, yamux) | rust-v0.54 | rust-v0.54 | tcp | tls | yamux | ✅ | 4s | 140.072 | 87.706 |
| rust-v0.54 x rust-v0.54 (tcp, noise, mplex) | rust-v0.54 | rust-v0.54 | tcp | noise | mplex | ✅ | 4s | 87.102 | 0.463 |
| rust-v0.54 x rust-v0.54 (tcp, noise, yamux) | rust-v0.54 | rust-v0.54 | tcp | noise | yamux | ✅ | 4s | 137.28 | 43.568 |
| rust-v0.54 x rust-v0.54 (quic-v1) | rust-v0.54 | rust-v0.54 | quic-v1 | - | - | ✅ | 4s | 5.736 | 0.616 |
| rust-v0.54 x rust-v0.55 (ws, tls, mplex) | rust-v0.54 | rust-v0.55 | ws | tls | mplex | ✅ | 3s | 134.989 | 48.16 |
| rust-v0.54 x rust-v0.54 (webrtc-direct) | rust-v0.54 | rust-v0.54 | webrtc-direct | - | - | ✅ | 5s | 211.918 | 0.459 |
| rust-v0.54 x rust-v0.55 (ws, tls, yamux) | rust-v0.54 | rust-v0.55 | ws | tls | yamux | ✅ | 5s | 138.307 | 46.717 |
| rust-v0.54 x rust-v0.55 (ws, noise, mplex) | rust-v0.54 | rust-v0.55 | ws | noise | mplex | ✅ | 4s | 135.159 | 42.853 |
| rust-v0.54 x rust-v0.55 (ws, noise, yamux) | rust-v0.54 | rust-v0.55 | ws | noise | yamux | ✅ | 5s | 147.046 | 42.852 |
| rust-v0.54 x rust-v0.55 (tcp, tls, mplex) | rust-v0.54 | rust-v0.55 | tcp | tls | mplex | ✅ | 5s | 46.492 | 41.256 |
| rust-v0.54 x rust-v0.55 (tcp, tls, yamux) | rust-v0.54 | rust-v0.55 | tcp | tls | yamux | ✅ | 5s | 42.839 | 40.321 |
| rust-v0.54 x rust-v0.55 (tcp, noise, mplex) | rust-v0.54 | rust-v0.55 | tcp | noise | mplex | ✅ | 4s | 43.199 | 0.066 |
| rust-v0.54 x rust-v0.55 (tcp, noise, yamux) | rust-v0.54 | rust-v0.55 | tcp | noise | yamux | ✅ | 4s | 55.028 | 3.011 |
| rust-v0.54 x rust-v0.55 (quic-v1) | rust-v0.54 | rust-v0.55 | quic-v1 | - | - | ✅ | 4s | 12.97 | 0.951 |
| rust-v0.54 x rust-v0.56 (ws, tls, mplex) | rust-v0.54 | rust-v0.56 | ws | tls | mplex | ✅ | 3s | 149.302 | 45.03 |
| rust-v0.54 x rust-v0.55 (webrtc-direct) | rust-v0.54 | rust-v0.55 | webrtc-direct | - | - | ✅ | 5s | 223.0 | 0.411 |
| rust-v0.54 x rust-v0.56 (ws, tls, yamux) | rust-v0.54 | rust-v0.56 | ws | tls | yamux | ✅ | 4s | 93.337 | 0.31 |
| rust-v0.54 x rust-v0.56 (ws, noise, mplex) | rust-v0.54 | rust-v0.56 | ws | noise | mplex | ✅ | 4s | 136.395 | 44.487 |
| rust-v0.54 x rust-v0.56 (ws, noise, yamux) | rust-v0.54 | rust-v0.56 | ws | noise | yamux | ✅ | 4s | 86.432 | 0.23 |
| rust-v0.54 x rust-v0.56 (tcp, tls, mplex) | rust-v0.54 | rust-v0.56 | tcp | tls | mplex | ✅ | 4s | 45.048 | 41.202 |
| rust-v0.54 x rust-v0.56 (tcp, tls, yamux) | rust-v0.54 | rust-v0.56 | tcp | tls | yamux | ✅ | 4s | 46.137 | 42.82 |
| rust-v0.54 x rust-v0.56 (tcp, noise, yamux) | rust-v0.54 | rust-v0.56 | tcp | noise | yamux | ✅ | 4s | 89.417 | 43.427 |
| rust-v0.54 x rust-v0.56 (tcp, noise, mplex) | rust-v0.54 | rust-v0.56 | tcp | noise | mplex | ✅ | 4s | 47.566 | 0.046 |
| rust-v0.54 x rust-v0.56 (quic-v1) | rust-v0.54 | rust-v0.56 | quic-v1 | - | - | ✅ | 5s | 5.579 | 0.406 |
| rust-v0.54 x rust-v0.56 (webrtc-direct) | rust-v0.54 | rust-v0.56 | webrtc-direct | - | - | ✅ | 4s | 213.686 | 0.593 |
| rust-v0.54 x go-v0.38 (ws, tls, yamux) | rust-v0.54 | go-v0.38 | ws | tls | yamux | ✅ | 4s | 99.838 | 0.44 |
| rust-v0.54 x go-v0.38 (ws, noise, yamux) | rust-v0.54 | go-v0.38 | ws | noise | yamux | ✅ | 4s | 135.744 | 46.424 |
| rust-v0.54 x go-v0.38 (tcp, tls, yamux) | rust-v0.54 | go-v0.38 | tcp | tls | yamux | ✅ | 4s | 3.823 | 1.109 |
| rust-v0.54 x go-v0.38 (tcp, noise, yamux) | rust-v0.54 | go-v0.38 | tcp | noise | yamux | ✅ | 4s | 5.403 | 0.181 |
| rust-v0.54 x go-v0.38 (quic-v1) | rust-v0.54 | go-v0.38 | quic-v1 | - | - | ✅ | 4s | 4.255 | 0.306 |
| rust-v0.54 x go-v0.38 (webrtc-direct) | rust-v0.54 | go-v0.38 | webrtc-direct | - | - | ✅ | 5s | 8.834 | 0.228 |
| rust-v0.54 x go-v0.39 (ws, tls, yamux) | rust-v0.54 | go-v0.39 | ws | tls | yamux | ✅ | 4s | 94.718 | 0.333 |
| rust-v0.54 x go-v0.39 (ws, noise, yamux) | rust-v0.54 | go-v0.39 | ws | noise | yamux | ✅ | 4s | 94.366 | 2.794 |
| rust-v0.54 x go-v0.39 (tcp, tls, yamux) | rust-v0.54 | go-v0.39 | tcp | tls | yamux | ✅ | 5s | 47.276 | 40.68 |
| rust-v0.54 x go-v0.39 (tcp, noise, yamux) | rust-v0.54 | go-v0.39 | tcp | noise | yamux | ✅ | 4s | 5.32 | 0.362 |
| rust-v0.54 x go-v0.39 (quic-v1) | rust-v0.54 | go-v0.39 | quic-v1 | - | - | ✅ | 3s | 4.382 | 0.259 |
| rust-v0.54 x go-v0.39 (webrtc-direct) | rust-v0.54 | go-v0.39 | webrtc-direct | - | - | ✅ | 4s | 15.975 | 0.453 |
| rust-v0.54 x go-v0.40 (ws, tls, yamux) | rust-v0.54 | go-v0.40 | ws | tls | yamux | ✅ | 4s | 49.362 | 0.285 |
| rust-v0.54 x go-v0.40 (ws, noise, yamux) | rust-v0.54 | go-v0.40 | ws | noise | yamux | ✅ | 4s | 91.778 | 0.22 |
| rust-v0.54 x go-v0.40 (tcp, tls, yamux) | rust-v0.54 | go-v0.40 | tcp | tls | yamux | ✅ | 5s | 5.102 | 1.244 |
| rust-v0.54 x go-v0.40 (tcp, noise, yamux) | rust-v0.54 | go-v0.40 | tcp | noise | yamux | ✅ | 5s | 4.204 | 0.169 |
| rust-v0.54 x go-v0.40 (quic-v1) | rust-v0.54 | go-v0.40 | quic-v1 | - | - | ✅ | 5s | 6.986 | 0.539 |
| rust-v0.54 x go-v0.40 (webrtc-direct) | rust-v0.54 | go-v0.40 | webrtc-direct | - | - | ✅ | 4s | 8.111 | 0.175 |
| rust-v0.54 x go-v0.41 (ws, tls, yamux) | rust-v0.54 | go-v0.41 | ws | tls | yamux | ✅ | 5s | 91.04 | 0.25 |
| rust-v0.54 x go-v0.41 (ws, noise, yamux) | rust-v0.54 | go-v0.41 | ws | noise | yamux | ✅ | 4s | 92.059 | 0.902 |
| rust-v0.54 x go-v0.41 (tcp, tls, yamux) | rust-v0.54 | go-v0.41 | tcp | tls | yamux | ✅ | 4s | 49.467 | 42.236 |
| rust-v0.54 x go-v0.41 (tcp, noise, yamux) | rust-v0.54 | go-v0.41 | tcp | noise | yamux | ✅ | 4s | 4.603 | 0.142 |
| rust-v0.54 x go-v0.41 (quic-v1) | rust-v0.54 | go-v0.41 | quic-v1 | - | - | ✅ | 4s | 4.207 | 0.603 |
| rust-v0.54 x go-v0.41 (webrtc-direct) | rust-v0.54 | go-v0.41 | webrtc-direct | - | - | ✅ | 4s | 15.38 | 0.254 |
| rust-v0.54 x go-v0.42 (ws, tls, yamux) | rust-v0.54 | go-v0.42 | ws | tls | yamux | ✅ | 4s | 95.11 | 0.248 |
| rust-v0.54 x go-v0.42 (ws, noise, yamux) | rust-v0.54 | go-v0.42 | ws | noise | yamux | ✅ | 5s | 100.251 | 0.999 |
| rust-v0.54 x go-v0.42 (tcp, tls, yamux) | rust-v0.54 | go-v0.42 | tcp | tls | yamux | ✅ | 4s | 6.689 | 0.431 |
| rust-v0.54 x go-v0.42 (tcp, noise, yamux) | rust-v0.54 | go-v0.42 | tcp | noise | yamux | ✅ | 4s | 4.097 | 0.249 |
| rust-v0.54 x go-v0.42 (quic-v1) | rust-v0.54 | go-v0.42 | quic-v1 | - | - | ✅ | 4s | 6.129 | 1.099 |
| rust-v0.54 x go-v0.42 (webrtc-direct) | rust-v0.54 | go-v0.42 | webrtc-direct | - | - | ✅ | 4s | 7.566 | 0.215 |
| rust-v0.54 x go-v0.43 (ws, tls, yamux) | rust-v0.54 | go-v0.43 | ws | tls | yamux | ✅ | 4s | 145.27 | 41.252 |
| rust-v0.54 x go-v0.43 (ws, noise, yamux) | rust-v0.54 | go-v0.43 | ws | noise | yamux | ✅ | 4s | 135.004 | 42.266 |
| rust-v0.54 x go-v0.43 (tcp, tls, yamux) | rust-v0.54 | go-v0.43 | tcp | tls | yamux | ✅ | 4s | 3.517 | 0.603 |
| rust-v0.54 x go-v0.43 (tcp, noise, yamux) | rust-v0.54 | go-v0.43 | tcp | noise | yamux | ✅ | 4s | 2.968 | 0.479 |
| rust-v0.54 x go-v0.43 (quic-v1) | rust-v0.54 | go-v0.43 | quic-v1 | - | - | ✅ | 5s | 6.449 | 0.243 |
| rust-v0.54 x go-v0.43 (webrtc-direct) | rust-v0.54 | go-v0.43 | webrtc-direct | - | - | ✅ | 4s | 8.873 | 0.215 |
| rust-v0.54 x go-v0.44 (ws, tls, yamux) | rust-v0.54 | go-v0.44 | ws | tls | yamux | ✅ | 4s | 95.335 | 0.442 |
| rust-v0.54 x go-v0.44 (ws, noise, yamux) | rust-v0.54 | go-v0.44 | ws | noise | yamux | ✅ | 4s | 94.151 | 0.128 |
| rust-v0.54 x go-v0.44 (tcp, tls, yamux) | rust-v0.54 | go-v0.44 | tcp | tls | yamux | ✅ | 4s | 10.948 | 0.589 |
| rust-v0.54 x go-v0.44 (tcp, noise, yamux) | rust-v0.54 | go-v0.44 | tcp | noise | yamux | ✅ | 4s | 4.268 | 0.064 |
| rust-v0.54 x go-v0.44 (quic-v1) | rust-v0.54 | go-v0.44 | quic-v1 | - | - | ✅ | 4s | 6.927 | 0.755 |
| rust-v0.54 x go-v0.45 (ws, tls, yamux) | rust-v0.54 | go-v0.45 | ws | tls | yamux | ✅ | 4s | 94.55 | 0.306 |
| rust-v0.54 x go-v0.44 (webrtc-direct) | rust-v0.54 | go-v0.44 | webrtc-direct | - | - | ✅ | 5s | 24.265 | 0.316 |
| rust-v0.54 x go-v0.45 (ws, noise, yamux) | rust-v0.54 | go-v0.45 | ws | noise | yamux | ✅ | 5s | 135.965 | 46.3 |
| rust-v0.54 x go-v0.45 (tcp, tls, yamux) | rust-v0.54 | go-v0.45 | tcp | tls | yamux | ✅ | 4s | 3.261 | 0.444 |
| rust-v0.54 x go-v0.45 (tcp, noise, yamux) | rust-v0.54 | go-v0.45 | tcp | noise | yamux | ✅ | 4s | 5.011 | 0.775 |
| rust-v0.54 x go-v0.45 (quic-v1) | rust-v0.54 | go-v0.45 | quic-v1 | - | - | ✅ | 4s | 7.314 | 0.68 |
| rust-v0.54 x go-v0.45 (webrtc-direct) | rust-v0.54 | go-v0.45 | webrtc-direct | - | - | ✅ | 4s | 16.234 | 0.538 |
| rust-v0.54 x python-v0.4 (ws, noise, mplex) | rust-v0.54 | python-v0.4 | ws | noise | mplex | ✅ | 4s | 57.636 | 0.981 |
| rust-v0.54 x python-v0.4 (ws, noise, yamux) | rust-v0.54 | python-v0.4 | ws | noise | yamux | ✅ | 5s | 113.673 | 2.339 |
| rust-v0.54 x python-v0.4 (tcp, noise, mplex) | rust-v0.54 | python-v0.4 | tcp | noise | mplex | ✅ | 4s | 13.032 | 0.817 |
| rust-v0.54 x python-v0.4 (tcp, noise, yamux) | rust-v0.54 | python-v0.4 | tcp | noise | yamux | ✅ | 4s | 13.361 | 1.101 |
| rust-v0.54 x python-v0.4 (quic-v1) | rust-v0.54 | python-v0.4 | quic-v1 | - | - | ✅ | 4s | 46.417 | 10.453 |
| rust-v0.54 x js-v1.x (ws, noise, mplex) | rust-v0.54 | js-v1.x | ws | noise | mplex | ✅ | 17s | 217.629 | 13.5 |
| rust-v0.54 x js-v1.x (ws, noise, yamux) | rust-v0.54 | js-v1.x | ws | noise | yamux | ✅ | 17s | 251.946 | 62.186 |
| rust-v0.54 x js-v1.x (tcp, noise, mplex) | rust-v0.54 | js-v1.x | tcp | noise | mplex | ✅ | 17s | 117.844 | 17.895 |
| rust-v0.54 x js-v1.x (tcp, noise, yamux) | rust-v0.54 | js-v1.x | tcp | noise | yamux | ✅ | 17s | 162.931 | 9.31 |
| rust-v0.54 x js-v2.x (ws, noise, mplex) | rust-v0.54 | js-v2.x | ws | noise | mplex | ✅ | 18s | 185.556 | 22.714 |
| rust-v0.54 x js-v2.x (ws, noise, yamux) | rust-v0.54 | js-v2.x | ws | noise | yamux | ✅ | 17s | 211.252 | 13.833 |
| rust-v0.54 x js-v2.x (tcp, noise, mplex) | rust-v0.54 | js-v2.x | tcp | noise | mplex | ✅ | 17s | 124.365 | 8.212 |
| rust-v0.54 x nim-v1.14 (ws, noise, mplex) | rust-v0.54 | nim-v1.14 | ws | noise | mplex | ✅ | 4s | 281.584 | 88.448 |
| rust-v0.54 x nim-v1.14 (ws, noise, yamux) | rust-v0.54 | nim-v1.14 | ws | noise | yamux | ✅ | 4s | 249.606 | 50.826 |
| rust-v0.53 x rust-v0.53 (webrtc-direct) | rust-v0.53 | rust-v0.53 | webrtc-direct | - | - | ❌ | 194s | - | - |
| rust-v0.54 x nim-v1.14 (tcp, noise, mplex) | rust-v0.54 | nim-v1.14 | tcp | noise | mplex | ✅ | 5s | 145.423 | 0.264 |
| rust-v0.54 x nim-v1.14 (tcp, noise, yamux) | rust-v0.54 | nim-v1.14 | tcp | noise | yamux | ✅ | 6s | 146.189 | 47.741 |
| rust-v0.54 x js-v2.x (tcp, noise, yamux) | rust-v0.54 | js-v2.x | tcp | noise | yamux | ✅ | 17s | 168.716 | 14.432 |
| rust-v0.54 x js-v3.x (ws, noise, yamux) | rust-v0.54 | js-v3.x | ws | noise | yamux | ✅ | 17s | 251.725 | 19.0 |
| rust-v0.54 x js-v3.x (ws, noise, mplex) | rust-v0.54 | js-v3.x | ws | noise | mplex | ✅ | 19s | 179.033 | 17.634 |
| rust-v0.54 x js-v3.x (tcp, noise, mplex) | rust-v0.54 | js-v3.x | tcp | noise | mplex | ✅ | 19s | 149.185 | 14.915 |
| rust-v0.54 x js-v3.x (tcp, noise, yamux) | rust-v0.54 | js-v3.x | tcp | noise | yamux | ✅ | 19s | 163.113 | 20.779 |
| rust-v0.54 x jvm-v1.2 (ws, tls, mplex) | rust-v0.54 | jvm-v1.2 | ws | tls | mplex | ✅ | 11s | 3142.877 | 5.105 |
| rust-v0.54 x jvm-v1.2 (ws, tls, yamux) | rust-v0.54 | jvm-v1.2 | ws | tls | yamux | ✅ | 12s | 3626.815 | 47.252 |
| rust-v0.54 x jvm-v1.2 (ws, noise, mplex) | rust-v0.54 | jvm-v1.2 | ws | noise | mplex | ✅ | 11s | 1687.716 | 18.745 |
| rust-v0.54 x jvm-v1.2 (ws, noise, yamux) | rust-v0.54 | jvm-v1.2 | ws | noise | yamux | ✅ | 11s | 1438.433 | 47.578 |
| rust-v0.54 x jvm-v1.2 (tcp, noise, mplex) | rust-v0.54 | jvm-v1.2 | tcp | noise | mplex | ✅ | 10s | 1183.467 | 7.378 |
| rust-v0.54 x jvm-v1.2 (tcp, tls, mplex) | rust-v0.54 | jvm-v1.2 | tcp | tls | mplex | ✅ | 12s | 3813.215 | 8.949 |
| rust-v0.54 x jvm-v1.2 (tcp, noise, yamux) | rust-v0.54 | jvm-v1.2 | tcp | noise | yamux | ✅ | 10s | 1187.726 | 7.028 |
| rust-v0.54 x jvm-v1.2 (tcp, tls, yamux) | rust-v0.54 | jvm-v1.2 | tcp | tls | yamux | ✅ | 13s | 4347.151 | 50.162 |
| rust-v0.54 x c-v0.0.1 (tcp, noise, mplex) | rust-v0.54 | c-v0.0.1 | tcp | noise | mplex | ✅ | 6s | 54.786 | 2.207 |
| rust-v0.54 x c-v0.0.1 (tcp, noise, yamux) | rust-v0.54 | c-v0.0.1 | tcp | noise | yamux | ✅ | 6s | 99.787 | 0.392 |
| rust-v0.54 x c-v0.0.1 (quic-v1) | rust-v0.54 | c-v0.0.1 | quic-v1 | - | - | ✅ | 4s | 10.962 | 3.771 |
| rust-v0.54 x jvm-v1.2 (quic-v1) | rust-v0.54 | jvm-v1.2 | quic-v1 | - | - | ✅ | 12s | 1536.392 | 3.508 |
| rust-v0.54 x dotnet-v1.0 (tcp, noise, yamux) | rust-v0.54 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 6s | 217.684 | 12.127 |
| rust-v0.54 x eth-p2p-z-v0.0.1 (quic-v1) | rust-v0.54 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 5s | 8.628 | 0.402 |
| rust-v0.54 x zig-v0.0.1 (quic-v1) | rust-v0.54 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 6s | - | - |
| rust-v0.55 x rust-v0.53 (ws, tls, mplex) | rust-v0.55 | rust-v0.53 | ws | tls | mplex | ✅ | 5s | 92.666 | 1.193 |
| rust-v0.55 x rust-v0.53 (ws, tls, yamux) | rust-v0.55 | rust-v0.53 | ws | tls | yamux | ✅ | 4s | 133.487 | 43.501 |
| rust-v0.55 x rust-v0.53 (ws, noise, mplex) | rust-v0.55 | rust-v0.53 | ws | noise | mplex | ✅ | 6s | 93.941 | 0.93 |
| rust-v0.55 x rust-v0.53 (tcp, tls, mplex) | rust-v0.55 | rust-v0.53 | tcp | tls | mplex | ✅ | 4s | 45.238 | 0.164 |
| rust-v0.55 x rust-v0.53 (ws, noise, yamux) | rust-v0.55 | rust-v0.53 | ws | noise | yamux | ✅ | 6s | 134.95 | 43.562 |
| rust-v0.55 x rust-v0.53 (tcp, noise, yamux) | rust-v0.55 | rust-v0.53 | tcp | noise | yamux | ✅ | 4s | 7.038 | 0.142 |
| rust-v0.55 x rust-v0.53 (tcp, tls, yamux) | rust-v0.55 | rust-v0.53 | tcp | tls | yamux | ✅ | 6s | 89.726 | 43.863 |
| rust-v0.55 x rust-v0.53 (tcp, noise, mplex) | rust-v0.55 | rust-v0.53 | tcp | noise | mplex | ✅ | 5s | 50.487 | 0.334 |
| rust-v0.55 x rust-v0.53 (quic-v1) | rust-v0.55 | rust-v0.53 | quic-v1 | - | - | ✅ | 6s | 2.863 | 0.258 |
| rust-v0.55 x rust-v0.53 (webrtc-direct) | rust-v0.55 | rust-v0.53 | webrtc-direct | - | - | ✅ | 5s | 277.324 | 0.207 |
| rust-v0.55 x rust-v0.54 (ws, tls, mplex) | rust-v0.55 | rust-v0.54 | ws | tls | mplex | ✅ | 5s | 91.595 | 1.452 |
| rust-v0.55 x rust-v0.54 (ws, tls, yamux) | rust-v0.55 | rust-v0.54 | ws | tls | yamux | ✅ | 5s | 132.94 | 43.735 |
| rust-v0.55 x rust-v0.54 (ws, noise, mplex) | rust-v0.55 | rust-v0.54 | ws | noise | mplex | ✅ | 5s | 91.04 | 0.378 |
| rust-v0.55 x rust-v0.54 (tcp, tls, mplex) | rust-v0.55 | rust-v0.54 | tcp | tls | mplex | ✅ | 5s | 47.16 | 0.27 |
| rust-v0.55 x rust-v0.54 (ws, noise, yamux) | rust-v0.55 | rust-v0.54 | ws | noise | yamux | ✅ | 5s | 136.42 | 44.134 |
| rust-v0.55 x rust-v0.54 (tcp, noise, mplex) | rust-v0.55 | rust-v0.54 | tcp | noise | mplex | ✅ | 5s | 47.581 | 0.373 |
| rust-v0.55 x rust-v0.54 (tcp, tls, yamux) | rust-v0.55 | rust-v0.54 | tcp | tls | yamux | ✅ | 5s | 94.293 | 47.904 |
| rust-v0.55 x rust-v0.54 (tcp, noise, yamux) | rust-v0.55 | rust-v0.54 | tcp | noise | yamux | ✅ | 6s | 47.734 | 0.303 |
| rust-v0.55 x rust-v0.54 (quic-v1) | rust-v0.55 | rust-v0.54 | quic-v1 | - | - | ✅ | 5s | 8.017 | 0.644 |
| rust-v0.55 x rust-v0.55 (ws, tls, mplex) | rust-v0.55 | rust-v0.55 | ws | tls | mplex | ✅ | 4s | 6.525 | 0.162 |
| rust-v0.55 x rust-v0.54 (webrtc-direct) | rust-v0.55 | rust-v0.54 | webrtc-direct | - | - | ✅ | 5s | 426.781 | 1.817 |
| rust-v0.55 x rust-v0.55 (ws, tls, yamux) | rust-v0.55 | rust-v0.55 | ws | tls | yamux | ✅ | 4s | 9.824 | 0.464 |
| rust-v0.55 x rust-v0.55 (ws, noise, mplex) | rust-v0.55 | rust-v0.55 | ws | noise | mplex | ✅ | 5s | 3.649 | 0.16 |
| rust-v0.55 x rust-v0.55 (ws, noise, yamux) | rust-v0.55 | rust-v0.55 | ws | noise | yamux | ✅ | 5s | 2.151 | 0.131 |
| rust-v0.55 x rust-v0.55 (tcp, tls, mplex) | rust-v0.55 | rust-v0.55 | tcp | tls | mplex | ✅ | 4s | 2.599 | 0.048 |
| rust-v0.55 x rust-v0.55 (tcp, noise, mplex) | rust-v0.55 | rust-v0.55 | tcp | noise | mplex | ✅ | 4s | 4.908 | 0.072 |
| rust-v0.55 x rust-v0.55 (tcp, tls, yamux) | rust-v0.55 | rust-v0.55 | tcp | tls | yamux | ✅ | 6s | 4.595 | 0.28 |
| rust-v0.55 x rust-v0.55 (tcp, noise, yamux) | rust-v0.55 | rust-v0.55 | tcp | noise | yamux | ✅ | 5s | 2.166 | 0.144 |
| rust-v0.55 x rust-v0.55 (quic-v1) | rust-v0.55 | rust-v0.55 | quic-v1 | - | - | ✅ | 5s | 3.064 | 0.203 |
| rust-v0.55 x rust-v0.55 (webrtc-direct) | rust-v0.55 | rust-v0.55 | webrtc-direct | - | - | ✅ | 5s | 225.543 | 0.771 |
| rust-v0.55 x rust-v0.56 (ws, tls, yamux) | rust-v0.55 | rust-v0.56 | ws | tls | yamux | ✅ | 5s | 5.111 | 0.191 |
| rust-v0.55 x rust-v0.56 (ws, tls, mplex) | rust-v0.55 | rust-v0.56 | ws | tls | mplex | ✅ | 5s | 9.785 | 0.708 |
| rust-v0.55 x rust-v0.56 (ws, noise, mplex) | rust-v0.55 | rust-v0.56 | ws | noise | mplex | ✅ | 4s | 7.355 | 0.124 |
| rust-v0.55 x rust-v0.56 (ws, noise, yamux) | rust-v0.55 | rust-v0.56 | ws | noise | yamux | ✅ | 4s | 2.203 | 0.097 |
| rust-v0.55 x rust-v0.56 (tcp, tls, yamux) | rust-v0.55 | rust-v0.56 | tcp | tls | yamux | ✅ | 4s | 11.313 | 0.439 |
| rust-v0.55 x rust-v0.56 (tcp, tls, mplex) | rust-v0.55 | rust-v0.56 | tcp | tls | mplex | ✅ | 5s | 4.05 | 0.06 |
| rust-v0.55 x rust-v0.56 (tcp, noise, mplex) | rust-v0.55 | rust-v0.56 | tcp | noise | mplex | ✅ | 5s | 5.852 | 0.009 |
| rust-v0.55 x rust-v0.56 (tcp, noise, yamux) | rust-v0.55 | rust-v0.56 | tcp | noise | yamux | ✅ | 5s | 10.612 | 0.149 |
| rust-v0.55 x rust-v0.56 (quic-v1) | rust-v0.55 | rust-v0.56 | quic-v1 | - | - | ✅ | 5s | 11.333 | 0.495 |
| rust-v0.55 x go-v0.38 (ws, tls, yamux) | rust-v0.55 | go-v0.38 | ws | tls | yamux | ✅ | 4s | 6.425 | 0.42 |
| rust-v0.55 x rust-v0.56 (webrtc-direct) | rust-v0.55 | rust-v0.56 | webrtc-direct | - | - | ✅ | 5s | 209.994 | 0.315 |
| rust-v0.55 x go-v0.38 (ws, noise, yamux) | rust-v0.55 | go-v0.38 | ws | noise | yamux | ✅ | 4s | 10.253 | 0.49 |
| rust-v0.55 x go-v0.38 (tcp, tls, yamux) | rust-v0.55 | go-v0.38 | tcp | tls | yamux | ✅ | 4s | 5.062 | 0.188 |
| rust-v0.55 x go-v0.38 (tcp, noise, yamux) | rust-v0.55 | go-v0.38 | tcp | noise | yamux | ✅ | 5s | 4.12 | 0.461 |
| rust-v0.55 x go-v0.38 (quic-v1) | rust-v0.55 | go-v0.38 | quic-v1 | - | - | ✅ | 5s | 4.922 | 0.214 |
| rust-v0.55 x go-v0.38 (webrtc-direct) | rust-v0.55 | go-v0.38 | webrtc-direct | - | - | ✅ | 5s | 11.295 | 0.405 |
| rust-v0.55 x go-v0.39 (ws, tls, yamux) | rust-v0.55 | go-v0.39 | ws | tls | yamux | ✅ | 5s | 7.651 | 0.28 |
| rust-v0.55 x go-v0.39 (ws, noise, yamux) | rust-v0.55 | go-v0.39 | ws | noise | yamux | ✅ | 5s | 7.992 | 2.66 |
| rust-v0.55 x go-v0.39 (tcp, tls, yamux) | rust-v0.55 | go-v0.39 | tcp | tls | yamux | ✅ | 5s | 4.557 | 0.696 |
| rust-v0.55 x go-v0.39 (tcp, noise, yamux) | rust-v0.55 | go-v0.39 | tcp | noise | yamux | ✅ | 4s | 4.924 | 1.512 |
| rust-v0.55 x go-v0.39 (quic-v1) | rust-v0.55 | go-v0.39 | quic-v1 | - | - | ✅ | 4s | 3.732 | 0.296 |
| rust-v0.55 x go-v0.39 (webrtc-direct) | rust-v0.55 | go-v0.39 | webrtc-direct | - | - | ✅ | 5s | 15.856 | 0.416 |
| rust-v0.55 x go-v0.40 (ws, tls, yamux) | rust-v0.55 | go-v0.40 | ws | tls | yamux | ✅ | 4s | 8.313 | 0.671 |
| rust-v0.55 x go-v0.40 (ws, noise, yamux) | rust-v0.55 | go-v0.40 | ws | noise | yamux | ✅ | 5s | 9.186 | 0.589 |
| rust-v0.55 x go-v0.40 (tcp, tls, yamux) | rust-v0.55 | go-v0.40 | tcp | tls | yamux | ✅ | 4s | 5.626 | 0.421 |
| rust-v0.55 x go-v0.40 (tcp, noise, yamux) | rust-v0.55 | go-v0.40 | tcp | noise | yamux | ✅ | 4s | 8.111 | 0.416 |
| rust-v0.55 x go-v0.40 (quic-v1) | rust-v0.55 | go-v0.40 | quic-v1 | - | - | ✅ | 4s | 5.94 | 0.316 |
| rust-v0.55 x go-v0.41 (ws, tls, yamux) | rust-v0.55 | go-v0.41 | ws | tls | yamux | ✅ | 4s | 7.198 | 0.446 |
| rust-v0.55 x go-v0.40 (webrtc-direct) | rust-v0.55 | go-v0.40 | webrtc-direct | - | - | ✅ | 5s | 23.979 | 2.663 |
| rust-v0.55 x go-v0.41 (ws, noise, yamux) | rust-v0.55 | go-v0.41 | ws | noise | yamux | ✅ | 5s | 5.471 | 0.366 |
| rust-v0.55 x go-v0.41 (tcp, tls, yamux) | rust-v0.55 | go-v0.41 | tcp | tls | yamux | ✅ | 4s | 4.574 | 0.521 |
| rust-v0.55 x go-v0.41 (tcp, noise, yamux) | rust-v0.55 | go-v0.41 | tcp | noise | yamux | ✅ | 4s | 6.208 | 0.697 |
| rust-v0.55 x go-v0.41 (quic-v1) | rust-v0.55 | go-v0.41 | quic-v1 | - | - | ✅ | 5s | 7.203 | 0.572 |
| rust-v0.55 x go-v0.41 (webrtc-direct) | rust-v0.55 | go-v0.41 | webrtc-direct | - | - | ✅ | 5s | 30.788 | 3.31 |
| rust-v0.55 x go-v0.42 (ws, tls, yamux) | rust-v0.55 | go-v0.42 | ws | tls | yamux | ✅ | 4s | 4.556 | 1.011 |
| rust-v0.55 x go-v0.42 (ws, noise, yamux) | rust-v0.55 | go-v0.42 | ws | noise | yamux | ✅ | 5s | 5.384 | 0.504 |
| rust-v0.55 x go-v0.42 (tcp, tls, yamux) | rust-v0.55 | go-v0.42 | tcp | tls | yamux | ✅ | 4s | 4.789 | 0.191 |
| rust-v0.55 x go-v0.42 (tcp, noise, yamux) | rust-v0.55 | go-v0.42 | tcp | noise | yamux | ✅ | 5s | 6.634 | 0.266 |
| rust-v0.55 x go-v0.42 (quic-v1) | rust-v0.55 | go-v0.42 | quic-v1 | - | - | ✅ | 4s | 9.677 | 0.401 |
| rust-v0.55 x go-v0.42 (webrtc-direct) | rust-v0.55 | go-v0.42 | webrtc-direct | - | - | ✅ | 4s | 54.634 | 0.72 |
| rust-v0.55 x go-v0.43 (ws, tls, yamux) | rust-v0.55 | go-v0.43 | ws | tls | yamux | ✅ | 5s | 8.522 | 1.182 |
| rust-v0.55 x go-v0.43 (ws, noise, yamux) | rust-v0.55 | go-v0.43 | ws | noise | yamux | ✅ | 5s | 8.195 | 0.429 |
| rust-v0.55 x go-v0.43 (tcp, noise, yamux) | rust-v0.55 | go-v0.43 | tcp | noise | yamux | ✅ | 5s | 7.82 | 0.142 |
| rust-v0.55 x go-v0.43 (quic-v1) | rust-v0.55 | go-v0.43 | quic-v1 | - | - | ✅ | 4s | 10.008 | 0.307 |
| rust-v0.55 x go-v0.43 (tcp, tls, yamux) | rust-v0.55 | go-v0.43 | tcp | tls | yamux | ✅ | 6s | 7.268 | 0.943 |
| rust-v0.55 x go-v0.43 (webrtc-direct) | rust-v0.55 | go-v0.43 | webrtc-direct | - | - | ✅ | 5s | 18.003 | 0.865 |
| rust-v0.55 x go-v0.44 (ws, tls, yamux) | rust-v0.55 | go-v0.44 | ws | tls | yamux | ✅ | 5s | 8.02 | 0.908 |
| rust-v0.55 x go-v0.44 (ws, noise, yamux) | rust-v0.55 | go-v0.44 | ws | noise | yamux | ✅ | 5s | 5.659 | 0.31 |
| rust-v0.55 x go-v0.44 (tcp, tls, yamux) | rust-v0.55 | go-v0.44 | tcp | tls | yamux | ✅ | 5s | 8.288 | 0.277 |
| rust-v0.55 x go-v0.44 (tcp, noise, yamux) | rust-v0.55 | go-v0.44 | tcp | noise | yamux | ✅ | 5s | 4.224 | 0.215 |
| rust-v0.55 x go-v0.44 (quic-v1) | rust-v0.55 | go-v0.44 | quic-v1 | - | - | ✅ | 5s | 12.72 | 1.982 |
| rust-v0.55 x go-v0.44 (webrtc-direct) | rust-v0.55 | go-v0.44 | webrtc-direct | - | - | ✅ | 5s | 18.787 | 1.135 |
| rust-v0.55 x go-v0.45 (ws, tls, yamux) | rust-v0.55 | go-v0.45 | ws | tls | yamux | ✅ | 5s | 6.548 | 0.379 |
| rust-v0.55 x go-v0.45 (ws, noise, yamux) | rust-v0.55 | go-v0.45 | ws | noise | yamux | ✅ | 5s | 9.921 | 0.173 |
| rust-v0.55 x go-v0.45 (tcp, tls, yamux) | rust-v0.55 | go-v0.45 | tcp | tls | yamux | ✅ | 5s | 12.433 | 0.473 |
| rust-v0.55 x go-v0.45 (tcp, noise, yamux) | rust-v0.55 | go-v0.45 | tcp | noise | yamux | ✅ | 5s | 4.585 | 0.288 |
| rust-v0.55 x go-v0.45 (quic-v1) | rust-v0.55 | go-v0.45 | quic-v1 | - | - | ✅ | 5s | 13.101 | 0.235 |
| rust-v0.55 x go-v0.45 (webrtc-direct) | rust-v0.55 | go-v0.45 | webrtc-direct | - | - | ✅ | 5s | 15.698 | 0.705 |
| rust-v0.55 x python-v0.4 (ws, noise, mplex) | rust-v0.55 | python-v0.4 | ws | noise | mplex | ✅ | 5s | 17.54 | 1.36 |
| rust-v0.55 x python-v0.4 (ws, noise, yamux) | rust-v0.55 | python-v0.4 | ws | noise | yamux | ✅ | 5s | 24.626 | 1.471 |
| rust-v0.55 x python-v0.4 (tcp, noise, mplex) | rust-v0.55 | python-v0.4 | tcp | noise | mplex | ✅ | 5s | 25.078 | 1.35 |
| rust-v0.55 x python-v0.4 (tcp, noise, yamux) | rust-v0.55 | python-v0.4 | tcp | noise | yamux | ✅ | 5s | 17.588 | 1.306 |
| rust-v0.55 x js-v1.x (ws, noise, mplex) | rust-v0.55 | js-v1.x | ws | noise | mplex | ✅ | 18s | 145.585 | 14.021 |
| rust-v0.55 x js-v1.x (ws, noise, yamux) | rust-v0.55 | js-v1.x | ws | noise | yamux | ✅ | 20s | 130.909 | 13.555 |
| rust-v0.55 x js-v1.x (tcp, noise, mplex) | rust-v0.55 | js-v1.x | tcp | noise | mplex | ✅ | 19s | 113.235 | 11.143 |
| rust-v0.55 x js-v1.x (tcp, noise, yamux) | rust-v0.55 | js-v1.x | tcp | noise | yamux | ✅ | 19s | 91.785 | 10.369 |
| rust-v0.55 x js-v2.x (ws, noise, mplex) | rust-v0.55 | js-v2.x | ws | noise | mplex | ✅ | 19s | 176.723 | 12.646 |
| rust-v0.55 x js-v2.x (ws, noise, yamux) | rust-v0.55 | js-v2.x | ws | noise | yamux | ✅ | 19s | 145.342 | 16.047 |
| rust-v0.55 x js-v2.x (tcp, noise, mplex) | rust-v0.55 | js-v2.x | tcp | noise | mplex | ✅ | 19s | 111.633 | 6.471 |
| rust-v0.55 x python-v0.4 (quic-v1) | rust-v0.55 | python-v0.4 | quic-v1 | - | - | ❌ | 26s | - | - |
| rust-v0.55 x nim-v1.14 (ws, noise, mplex) | rust-v0.55 | nim-v1.14 | ws | noise | mplex | ✅ | 5s | 162.822 | 43.477 |
| rust-v0.55 x nim-v1.14 (ws, noise, yamux) | rust-v0.55 | nim-v1.14 | ws | noise | yamux | ✅ | 4s | 117.915 | 5.247 |
| rust-v0.55 x nim-v1.14 (tcp, noise, mplex) | rust-v0.55 | nim-v1.14 | tcp | noise | mplex | ✅ | 5s | 162.636 | 44.261 |
| rust-v0.55 x nim-v1.14 (tcp, noise, yamux) | rust-v0.55 | nim-v1.14 | tcp | noise | yamux | ✅ | 6s | 113.006 | 1.663 |
| rust-v0.55 x js-v2.x (tcp, noise, yamux) | rust-v0.55 | js-v2.x | tcp | noise | yamux | ✅ | 19s | 149.073 | 22.931 |
| rust-v0.55 x js-v3.x (ws, noise, mplex) | rust-v0.55 | js-v3.x | ws | noise | mplex | ✅ | 19s | 130.029 | 19.806 |
| rust-v0.55 x js-v3.x (ws, noise, yamux) | rust-v0.55 | js-v3.x | ws | noise | yamux | ✅ | 19s | 153.467 | 26.92 |
| rust-v0.55 x js-v3.x (tcp, noise, mplex) | rust-v0.55 | js-v3.x | tcp | noise | mplex | ✅ | 19s | 142.654 | 37.152 |
| rust-v0.55 x js-v3.x (tcp, noise, yamux) | rust-v0.55 | js-v3.x | tcp | noise | yamux | ✅ | 21s | 143.535 | 26.295 |
| rust-v0.55 x jvm-v1.2 (ws, tls, mplex) | rust-v0.55 | jvm-v1.2 | ws | tls | mplex | ✅ | 13s | 3424.495 | 3.607 |
| rust-v0.55 x jvm-v1.2 (ws, tls, yamux) | rust-v0.55 | jvm-v1.2 | ws | tls | yamux | ✅ | 12s | 3373.431 | 6.481 |
| rust-v0.55 x jvm-v1.2 (ws, noise, mplex) | rust-v0.55 | jvm-v1.2 | ws | noise | mplex | ✅ | 10s | 1035.559 | 4.324 |
| rust-v0.55 x jvm-v1.2 (ws, noise, yamux) | rust-v0.55 | jvm-v1.2 | ws | noise | yamux | ✅ | 9s | 1530.246 | 20.646 |
| rust-v0.55 x jvm-v1.2 (tcp, noise, mplex) | rust-v0.55 | jvm-v1.2 | tcp | noise | mplex | ✅ | 11s | 1605.335 | 6.254 |
| rust-v0.55 x jvm-v1.2 (tcp, tls, mplex) | rust-v0.55 | jvm-v1.2 | tcp | tls | mplex | ✅ | 13s | 3971.451 | 7.242 |
| rust-v0.55 x c-v0.0.1 (tcp, noise, yamux) | rust-v0.55 | c-v0.0.1 | tcp | noise | yamux | ✅ | 5s | 75.142 | 3.046 |
| rust-v0.55 x jvm-v1.2 (tcp, tls, yamux) | rust-v0.55 | jvm-v1.2 | tcp | tls | yamux | ✅ | 13s | 3924.926 | 4.369 |
| rust-v0.55 x jvm-v1.2 (tcp, noise, yamux) | rust-v0.55 | jvm-v1.2 | tcp | noise | yamux | ✅ | 10s | 784.719 | 4.131 |
| rust-v0.55 x c-v0.0.1 (quic-v1) | rust-v0.55 | c-v0.0.1 | quic-v1 | - | - | ✅ | 5s | 17.541 | 0.652 |
| rust-v0.55 x jvm-v1.2 (quic-v1) | rust-v0.55 | jvm-v1.2 | quic-v1 | - | - | ✅ | 10s | 693.891 | 8.947 |
| rust-v0.55 x dotnet-v1.0 (tcp, noise, yamux) | rust-v0.55 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 4s | 179.182 | 20.502 |
| rust-v0.55 x zig-v0.0.1 (quic-v1) | rust-v0.55 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 4s | - | - |
| rust-v0.55 x eth-p2p-z-v0.0.1 (quic-v1) | rust-v0.55 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 4s | 5.057 | 0.174 |
| rust-v0.56 x rust-v0.53 (ws, tls, mplex) | rust-v0.56 | rust-v0.53 | ws | tls | mplex | ✅ | 4s | 91.592 | 0.455 |
| rust-v0.56 x rust-v0.53 (ws, tls, yamux) | rust-v0.56 | rust-v0.53 | ws | tls | yamux | ✅ | 5s | 58.292 | 0.577 |
| rust-v0.56 x rust-v0.53 (ws, noise, mplex) | rust-v0.56 | rust-v0.53 | ws | noise | mplex | ✅ | 4s | 89.278 | 0.195 |
| rust-v0.56 x rust-v0.53 (ws, noise, yamux) | rust-v0.56 | rust-v0.53 | ws | noise | yamux | ✅ | 5s | 141.781 | 47.405 |
| rust-v0.55 x c-v0.0.1 (tcp, noise, mplex) | rust-v0.55 | c-v0.0.1 | tcp | noise | mplex | ✅ | 15s | 10012.292 | 0.304 |
| rust-v0.56 x rust-v0.53 (tcp, tls, mplex) | rust-v0.56 | rust-v0.53 | tcp | tls | mplex | ✅ | 4s | 13.251 | 0.179 |
| rust-v0.56 x rust-v0.53 (tcp, noise, yamux) | rust-v0.56 | rust-v0.53 | tcp | noise | yamux | ✅ | 4s | 9.166 | 0.33 |
| rust-v0.56 x rust-v0.53 (tcp, noise, mplex) | rust-v0.56 | rust-v0.53 | tcp | noise | mplex | ✅ | 4s | 61.33 | 0.324 |
| rust-v0.56 x rust-v0.53 (tcp, tls, yamux) | rust-v0.56 | rust-v0.53 | tcp | tls | yamux | ✅ | 6s | 95.554 | 47.573 |
| rust-v0.56 x rust-v0.53 (quic-v1) | rust-v0.56 | rust-v0.53 | quic-v1 | - | - | ✅ | 4s | 7.525 | 0.529 |
| rust-v0.56 x rust-v0.53 (webrtc-direct) | rust-v0.56 | rust-v0.53 | webrtc-direct | - | - | ✅ | 4s | 213.909 | 0.601 |
| rust-v0.56 x rust-v0.54 (ws, tls, mplex) | rust-v0.56 | rust-v0.54 | ws | tls | mplex | ✅ | 5s | 94.546 | 0.687 |
| rust-v0.56 x rust-v0.54 (ws, tls, yamux) | rust-v0.56 | rust-v0.54 | ws | tls | yamux | ✅ | 4s | 95.794 | 0.293 |
| rust-v0.56 x rust-v0.54 (ws, noise, mplex) | rust-v0.56 | rust-v0.54 | ws | noise | mplex | ✅ | 5s | 96.011 | 0.361 |
| rust-v0.56 x rust-v0.54 (ws, noise, yamux) | rust-v0.56 | rust-v0.54 | ws | noise | yamux | ✅ | 5s | 99.835 | 0.317 |
| rust-v0.56 x rust-v0.54 (tcp, tls, yamux) | rust-v0.56 | rust-v0.54 | tcp | tls | yamux | ✅ | 5s | 12.356 | 0.485 |
| rust-v0.56 x rust-v0.54 (tcp, tls, mplex) | rust-v0.56 | rust-v0.54 | tcp | tls | mplex | ✅ | 5s | 50.551 | 0.163 |
| rust-v0.56 x rust-v0.54 (tcp, noise, mplex) | rust-v0.56 | rust-v0.54 | tcp | noise | mplex | ✅ | 5s | 45.152 | 0.224 |
| rust-v0.56 x rust-v0.54 (tcp, noise, yamux) | rust-v0.56 | rust-v0.54 | tcp | noise | yamux | ✅ | 4s | 45.141 | 0.285 |
| rust-v0.56 x rust-v0.54 (quic-v1) | rust-v0.56 | rust-v0.54 | quic-v1 | - | - | ✅ | 5s | 11.577 | 0.544 |
| rust-v0.56 x rust-v0.54 (webrtc-direct) | rust-v0.56 | rust-v0.54 | webrtc-direct | - | - | ✅ | 5s | 214.807 | 0.455 |
| rust-v0.56 x rust-v0.55 (ws, tls, mplex) | rust-v0.56 | rust-v0.55 | ws | tls | mplex | ✅ | 5s | 7.996 | 0.055 |
| rust-v0.56 x rust-v0.55 (ws, tls, yamux) | rust-v0.56 | rust-v0.55 | ws | tls | yamux | ✅ | 4s | 6.832 | 0.215 |
| rust-v0.56 x rust-v0.55 (ws, noise, mplex) | rust-v0.56 | rust-v0.55 | ws | noise | mplex | ✅ | 5s | 6.452 | 0.359 |
| rust-v0.56 x rust-v0.55 (tcp, tls, mplex) | rust-v0.56 | rust-v0.55 | tcp | tls | mplex | ✅ | 4s | 2.68 | 0.056 |
| rust-v0.56 x rust-v0.55 (ws, noise, yamux) | rust-v0.56 | rust-v0.55 | ws | noise | yamux | ✅ | 5s | 5.588 | 0.19 |
| rust-v0.56 x rust-v0.55 (tcp, tls, yamux) | rust-v0.56 | rust-v0.55 | tcp | tls | yamux | ✅ | 4s | 8.214 | 1.14 |
| rust-v0.56 x rust-v0.55 (tcp, noise, yamux) | rust-v0.56 | rust-v0.55 | tcp | noise | yamux | ✅ | 5s | 9.783 | 0.346 |
| rust-v0.56 x rust-v0.55 (tcp, noise, mplex) | rust-v0.56 | rust-v0.55 | tcp | noise | mplex | ✅ | 5s | 7.063 | 0.2 |
| rust-v0.56 x rust-v0.55 (quic-v1) | rust-v0.56 | rust-v0.55 | quic-v1 | - | - | ✅ | 5s | 6.183 | 0.373 |
| rust-v0.56 x rust-v0.56 (ws, tls, mplex) | rust-v0.56 | rust-v0.56 | ws | tls | mplex | ✅ | 5s | 6.866 | 0.127 |
| rust-v0.56 x rust-v0.55 (webrtc-direct) | rust-v0.56 | rust-v0.55 | webrtc-direct | - | - | ✅ | 5s | 219.372 | 0.705 |
| rust-v0.56 x rust-v0.56 (ws, tls, yamux) | rust-v0.56 | rust-v0.56 | ws | tls | yamux | ✅ | 5s | 5.532 | 0.304 |
| rust-v0.56 x rust-v0.56 (ws, noise, mplex) | rust-v0.56 | rust-v0.56 | ws | noise | mplex | ✅ | 5s | 9.006 | 0.117 |
| rust-v0.56 x rust-v0.56 (ws, noise, yamux) | rust-v0.56 | rust-v0.56 | ws | noise | yamux | ✅ | 5s | 3.612 | 0.187 |
| rust-v0.56 x rust-v0.56 (tcp, tls, mplex) | rust-v0.56 | rust-v0.56 | tcp | tls | mplex | ✅ | 5s | 6.884 | 0.577 |
| rust-v0.56 x rust-v0.56 (tcp, tls, yamux) | rust-v0.56 | rust-v0.56 | tcp | tls | yamux | ✅ | 4s | 4.505 | 0.206 |
| rust-v0.56 x rust-v0.56 (tcp, noise, mplex) | rust-v0.56 | rust-v0.56 | tcp | noise | mplex | ✅ | 5s | 2.75 | 0.092 |
| rust-v0.56 x rust-v0.56 (tcp, noise, yamux) | rust-v0.56 | rust-v0.56 | tcp | noise | yamux | ✅ | 4s | 4.103 | 0.175 |
| rust-v0.56 x rust-v0.56 (quic-v1) | rust-v0.56 | rust-v0.56 | quic-v1 | - | - | ✅ | 4s | 8.652 | 0.369 |
| rust-v0.56 x go-v0.38 (ws, tls, yamux) | rust-v0.56 | go-v0.38 | ws | tls | yamux | ✅ | 4s | 4.233 | 0.518 |
| rust-v0.56 x rust-v0.56 (webrtc-direct) | rust-v0.56 | rust-v0.56 | webrtc-direct | - | - | ✅ | 5s | 221.318 | 0.46 |
| rust-v0.56 x go-v0.38 (ws, noise, yamux) | rust-v0.56 | go-v0.38 | ws | noise | yamux | ✅ | 5s | 2.624 | 0.203 |
| rust-v0.56 x go-v0.38 (tcp, tls, yamux) | rust-v0.56 | go-v0.38 | tcp | tls | yamux | ✅ | 5s | 9.415 | 0.809 |
| rust-v0.56 x go-v0.38 (tcp, noise, yamux) | rust-v0.56 | go-v0.38 | tcp | noise | yamux | ✅ | 5s | 7.755 | 0.293 |
| rust-v0.56 x go-v0.38 (quic-v1) | rust-v0.56 | go-v0.38 | quic-v1 | - | - | ✅ | 5s | 8.137 | 0.455 |
| rust-v0.56 x go-v0.38 (webrtc-direct) | rust-v0.56 | go-v0.38 | webrtc-direct | - | - | ✅ | 5s | 16.216 | 0.748 |
| rust-v0.56 x go-v0.39 (ws, tls, yamux) | rust-v0.56 | go-v0.39 | ws | tls | yamux | ✅ | 4s | 7.845 | 1.683 |
| rust-v0.56 x go-v0.39 (ws, noise, yamux) | rust-v0.56 | go-v0.39 | ws | noise | yamux | ✅ | 4s | 6.47 | 0.189 |
| rust-v0.56 x go-v0.39 (tcp, tls, yamux) | rust-v0.56 | go-v0.39 | tcp | tls | yamux | ✅ | 5s | 8.167 | 0.356 |
| rust-v0.56 x go-v0.39 (tcp, noise, yamux) | rust-v0.56 | go-v0.39 | tcp | noise | yamux | ✅ | 5s | 4.444 | 0.257 |
| rust-v0.56 x go-v0.39 (quic-v1) | rust-v0.56 | go-v0.39 | quic-v1 | - | - | ✅ | 4s | 6.584 | 0.223 |
| rust-v0.56 x go-v0.39 (webrtc-direct) | rust-v0.56 | go-v0.39 | webrtc-direct | - | - | ✅ | 5s | 13.536 | 0.473 |
| rust-v0.56 x go-v0.40 (ws, noise, yamux) | rust-v0.56 | go-v0.40 | ws | noise | yamux | ✅ | 5s | 4.249 | 0.674 |
| rust-v0.56 x go-v0.40 (ws, tls, yamux) | rust-v0.56 | go-v0.40 | ws | tls | yamux | ✅ | 5s | 9.207 | 2.531 |
| rust-v0.56 x go-v0.40 (tcp, tls, yamux) | rust-v0.56 | go-v0.40 | tcp | tls | yamux | ✅ | 4s | 3.245 | 0.534 |
| rust-v0.56 x go-v0.40 (quic-v1) | rust-v0.56 | go-v0.40 | quic-v1 | - | - | ✅ | 5s | 8.707 | 0.636 |
| rust-v0.56 x go-v0.40 (tcp, noise, yamux) | rust-v0.56 | go-v0.40 | tcp | noise | yamux | ✅ | 5s | 4.98 | 0.116 |
| rust-v0.56 x go-v0.40 (webrtc-direct) | rust-v0.56 | go-v0.40 | webrtc-direct | - | - | ✅ | 5s | 15.194 | 0.684 |
| rust-v0.56 x go-v0.41 (ws, tls, yamux) | rust-v0.56 | go-v0.41 | ws | tls | yamux | ✅ | 5s | 8.321 | 1.08 |
| rust-v0.56 x go-v0.41 (ws, noise, yamux) | rust-v0.56 | go-v0.41 | ws | noise | yamux | ✅ | 5s | 7.301 | 3.66 |
| rust-v0.56 x go-v0.41 (tcp, tls, yamux) | rust-v0.56 | go-v0.41 | tcp | tls | yamux | ✅ | 5s | 4.545 | 0.726 |
| rust-v0.56 x go-v0.41 (tcp, noise, yamux) | rust-v0.56 | go-v0.41 | tcp | noise | yamux | ✅ | 4s | 4.991 | 0.402 |
| rust-v0.56 x go-v0.41 (quic-v1) | rust-v0.56 | go-v0.41 | quic-v1 | - | - | ✅ | 5s | 3.361 | 0.244 |
| rust-v0.56 x go-v0.41 (webrtc-direct) | rust-v0.56 | go-v0.41 | webrtc-direct | - | - | ✅ | 5s | 36.085 | 0.59 |
| rust-v0.56 x go-v0.42 (ws, tls, yamux) | rust-v0.56 | go-v0.42 | ws | tls | yamux | ✅ | 4s | 8.231 | 0.492 |
| rust-v0.56 x go-v0.42 (ws, noise, yamux) | rust-v0.56 | go-v0.42 | ws | noise | yamux | ✅ | 5s | 8.336 | 4.45 |
| rust-v0.56 x go-v0.42 (tcp, tls, yamux) | rust-v0.56 | go-v0.42 | tcp | tls | yamux | ✅ | 4s | 4.232 | 0.473 |
| rust-v0.56 x go-v0.42 (tcp, noise, yamux) | rust-v0.56 | go-v0.42 | tcp | noise | yamux | ✅ | 5s | 9.972 | 0.314 |
| rust-v0.56 x go-v0.42 (quic-v1) | rust-v0.56 | go-v0.42 | quic-v1 | - | - | ✅ | 5s | 19.737 | 0.437 |
| rust-v0.56 x go-v0.42 (webrtc-direct) | rust-v0.56 | go-v0.42 | webrtc-direct | - | - | ✅ | 5s | 40.907 | 1.039 |
| rust-v0.56 x go-v0.43 (ws, tls, yamux) | rust-v0.56 | go-v0.43 | ws | tls | yamux | ✅ | 5s | 11.146 | 0.459 |
| rust-v0.56 x go-v0.43 (ws, noise, yamux) | rust-v0.56 | go-v0.43 | ws | noise | yamux | ✅ | 5s | 7.719 | 0.652 |
| rust-v0.56 x go-v0.43 (tcp, tls, yamux) | rust-v0.56 | go-v0.43 | tcp | tls | yamux | ✅ | 5s | 13.588 | 0.457 |
| rust-v0.56 x go-v0.43 (quic-v1) | rust-v0.56 | go-v0.43 | quic-v1 | - | - | ✅ | 4s | 5.585 | 0.288 |
| rust-v0.56 x go-v0.43 (tcp, noise, yamux) | rust-v0.56 | go-v0.43 | tcp | noise | yamux | ✅ | 6s | 8.737 | 0.499 |
| rust-v0.56 x go-v0.43 (webrtc-direct) | rust-v0.56 | go-v0.43 | webrtc-direct | - | - | ✅ | 5s | 24.458 | 0.508 |
| rust-v0.56 x go-v0.44 (ws, tls, yamux) | rust-v0.56 | go-v0.44 | ws | tls | yamux | ✅ | 4s | 11.812 | 1.039 |
| rust-v0.56 x go-v0.44 (ws, noise, yamux) | rust-v0.56 | go-v0.44 | ws | noise | yamux | ✅ | 5s | 6.684 | 0.509 |
| rust-v0.56 x go-v0.44 (tcp, tls, yamux) | rust-v0.56 | go-v0.44 | tcp | tls | yamux | ✅ | 4s | 3.741 | 0.272 |
| rust-v0.56 x go-v0.44 (tcp, noise, yamux) | rust-v0.56 | go-v0.44 | tcp | noise | yamux | ✅ | 5s | 4.476 | 0.221 |
| rust-v0.56 x go-v0.44 (quic-v1) | rust-v0.56 | go-v0.44 | quic-v1 | - | - | ✅ | 5s | 6.701 | 1.058 |
| rust-v0.56 x go-v0.44 (webrtc-direct) | rust-v0.56 | go-v0.44 | webrtc-direct | - | - | ✅ | 5s | 26.279 | 1.398 |
| rust-v0.56 x go-v0.45 (ws, tls, yamux) | rust-v0.56 | go-v0.45 | ws | tls | yamux | ✅ | 6s | 14.032 | 0.26 |
| rust-v0.56 x go-v0.45 (ws, noise, yamux) | rust-v0.56 | go-v0.45 | ws | noise | yamux | ✅ | 5s | 24.453 | 0.328 |
| rust-v0.56 x go-v0.45 (tcp, tls, yamux) | rust-v0.56 | go-v0.45 | tcp | tls | yamux | ✅ | 5s | 9.509 | 0.156 |
| rust-v0.56 x go-v0.45 (tcp, noise, yamux) | rust-v0.56 | go-v0.45 | tcp | noise | yamux | ✅ | 5s | 4.661 | 0.187 |
| rust-v0.56 x go-v0.45 (quic-v1) | rust-v0.56 | go-v0.45 | quic-v1 | - | - | ✅ | 5s | 6.55 | 0.288 |
| rust-v0.56 x go-v0.45 (webrtc-direct) | rust-v0.56 | go-v0.45 | webrtc-direct | - | - | ✅ | 5s | 28.172 | 0.585 |
| rust-v0.56 x python-v0.4 (ws, noise, mplex) | rust-v0.56 | python-v0.4 | ws | noise | mplex | ✅ | 6s | 13.811 | 0.888 |
| rust-v0.56 x python-v0.4 (ws, noise, yamux) | rust-v0.56 | python-v0.4 | ws | noise | yamux | ✅ | 5s | 24.363 | 1.705 |
| rust-v0.56 x python-v0.4 (tcp, noise, mplex) | rust-v0.56 | python-v0.4 | tcp | noise | mplex | ✅ | 5s | 18.18 | 1.097 |
| rust-v0.56 x python-v0.4 (tcp, noise, yamux) | rust-v0.56 | python-v0.4 | tcp | noise | yamux | ✅ | 5s | 16.855 | 1.089 |
| rust-v0.56 x python-v0.4 (quic-v1) | rust-v0.56 | python-v0.4 | quic-v1 | - | - | ✅ | 5s | 61.526 | 2.54 |
| rust-v0.56 x js-v1.x (ws, noise, mplex) | rust-v0.56 | js-v1.x | ws | noise | mplex | ✅ | 19s | 186.987 | 26.279 |
| rust-v0.56 x js-v1.x (ws, noise, yamux) | rust-v0.56 | js-v1.x | ws | noise | yamux | ✅ | 20s | 139.938 | 14.752 |
| rust-v0.56 x js-v1.x (tcp, noise, mplex) | rust-v0.56 | js-v1.x | tcp | noise | mplex | ✅ | 21s | 141.316 | 13.776 |
| rust-v0.56 x js-v1.x (tcp, noise, yamux) | rust-v0.56 | js-v1.x | tcp | noise | yamux | ✅ | 21s | 111.954 | 11.485 |
| rust-v0.56 x js-v2.x (ws, noise, mplex) | rust-v0.56 | js-v2.x | ws | noise | mplex | ✅ | 21s | 132.679 | 14.805 |
| rust-v0.56 x js-v2.x (ws, noise, yamux) | rust-v0.56 | js-v2.x | ws | noise | yamux | ✅ | 21s | 147.886 | 20.576 |
| rust-v0.56 x js-v2.x (tcp, noise, yamux) | rust-v0.56 | js-v2.x | tcp | noise | yamux | ✅ | 20s | 114.298 | 13.034 |
| rust-v0.56 x js-v2.x (tcp, noise, mplex) | rust-v0.56 | js-v2.x | tcp | noise | mplex | ✅ | 21s | 99.632 | 12.616 |
| rust-v0.56 x nim-v1.14 (ws, noise, mplex) | rust-v0.56 | nim-v1.14 | ws | noise | mplex | ✅ | 4s | 159.459 | 43.765 |
| rust-v0.56 x nim-v1.14 (ws, noise, yamux) | rust-v0.56 | nim-v1.14 | ws | noise | yamux | ✅ | 5s | 126.777 | 6.126 |
| rust-v0.56 x nim-v1.14 (tcp, noise, yamux) | rust-v0.56 | nim-v1.14 | tcp | noise | yamux | ✅ | 4s | 75.906 | 2.298 |
| rust-v0.56 x nim-v1.14 (tcp, noise, mplex) | rust-v0.56 | nim-v1.14 | tcp | noise | mplex | ✅ | 5s | 158.642 | 43.772 |
| rust-v0.56 x js-v3.x (ws, noise, mplex) | rust-v0.56 | js-v3.x | ws | noise | mplex | ✅ | 17s | 152.702 | 23.193 |
| rust-v0.56 x js-v3.x (ws, noise, yamux) | rust-v0.56 | js-v3.x | ws | noise | yamux | ✅ | 19s | 138.032 | 25.723 |
| rust-v0.56 x jvm-v1.2 (ws, tls, mplex) | rust-v0.56 | jvm-v1.2 | ws | tls | mplex | ✅ | 13s | 4628.051 | 3.498 |
| rust-v0.56 x js-v3.x (tcp, noise, yamux) | rust-v0.56 | js-v3.x | tcp | noise | yamux | ✅ | 20s | 141.651 | 26.149 |
| rust-v0.56 x js-v3.x (tcp, noise, mplex) | rust-v0.56 | js-v3.x | tcp | noise | mplex | ✅ | 22s | 142.215 | 20.709 |
| rust-v0.56 x jvm-v1.2 (ws, tls, yamux) | rust-v0.56 | jvm-v1.2 | ws | tls | yamux | ✅ | 13s | 4248.091 | 4.426 |
| rust-v0.56 x jvm-v1.2 (ws, noise, mplex) | rust-v0.56 | jvm-v1.2 | ws | noise | mplex | ✅ | 12s | 1188.793 | 8.997 |
| rust-v0.56 x jvm-v1.2 (ws, noise, yamux) | rust-v0.56 | jvm-v1.2 | ws | noise | yamux | ✅ | 11s | 1166.474 | 5.065 |
| rust-v0.56 x jvm-v1.2 (tcp, tls, mplex) | rust-v0.56 | jvm-v1.2 | tcp | tls | mplex | ✅ | 11s | 2734.276 | 7.021 |
| rust-v0.56 x c-v0.0.1 (tcp, noise, mplex) | rust-v0.56 | c-v0.0.1 | tcp | noise | mplex | ✅ | 6s | 13.696 | 0.226 |
| rust-v0.56 x c-v0.0.1 (tcp, noise, yamux) | rust-v0.56 | c-v0.0.1 | tcp | noise | yamux | ✅ | 6s | 63.533 | 2.452 |
| rust-v0.56 x c-v0.0.1 (quic-v1) | rust-v0.56 | c-v0.0.1 | quic-v1 | - | - | ✅ | 5s | 19.778 | 2.04 |
| rust-v0.56 x jvm-v1.2 (tcp, tls, yamux) | rust-v0.56 | jvm-v1.2 | tcp | tls | yamux | ✅ | 13s | 3526.138 | 4.559 |
| rust-v0.56 x jvm-v1.2 (tcp, noise, mplex) | rust-v0.56 | jvm-v1.2 | tcp | noise | mplex | ✅ | 10s | 1161.308 | 5.552 |
| rust-v0.56 x jvm-v1.2 (tcp, noise, yamux) | rust-v0.56 | jvm-v1.2 | tcp | noise | yamux | ✅ | 11s | 1133.649 | 4.78 |
| rust-v0.56 x jvm-v1.2 (quic-v1) | rust-v0.56 | jvm-v1.2 | quic-v1 | - | - | ✅ | 11s | 1416.585 | 6.165 |
| rust-v0.56 x dotnet-v1.0 (tcp, noise, yamux) | rust-v0.56 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 6s | 188.449 | 11.791 |
| rust-v0.56 x zig-v0.0.1 (quic-v1) | rust-v0.56 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 4s | - | - |
| rust-v0.56 x eth-p2p-z-v0.0.1 (quic-v1) | rust-v0.56 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 5s | 13.14 | 0.424 |
| go-v0.38 x rust-v0.53 (tcp, tls, yamux) | go-v0.38 | rust-v0.53 | tcp | tls | yamux | ✅ | 6s | 95.145 | 44.399 |
| go-v0.38 x rust-v0.53 (tcp, noise, yamux) | go-v0.38 | rust-v0.53 | tcp | noise | yamux | ✅ | 6s | 137.422 | 42.98 |
| go-v0.38 x rust-v0.53 (ws, tls, yamux) | go-v0.38 | rust-v0.53 | ws | tls | yamux | ✅ | 5s | 174.706 | 42.918 |
| go-v0.38 x rust-v0.53 (ws, noise, yamux) | go-v0.38 | rust-v0.53 | ws | noise | yamux | ✅ | 6s | 183.904 | 43.309 |
| go-v0.38 x rust-v0.53 (quic-v1) | go-v0.38 | rust-v0.53 | quic-v1 | - | - | ✅ | 4s | 10.209 | 0.64 |
| go-v0.38 x rust-v0.54 (tcp, tls, yamux) | go-v0.38 | rust-v0.54 | tcp | tls | yamux | ✅ | 4s | 94.745 | 42.557 |
| go-v0.38 x rust-v0.53 (webrtc-direct) | go-v0.38 | rust-v0.53 | webrtc-direct | - | - | ✅ | 5s | 413.555 | 0.349 |
| go-v0.38 x rust-v0.54 (tcp, noise, yamux) | go-v0.38 | rust-v0.54 | tcp | noise | yamux | ✅ | 4s | 102.852 | 46.673 |
| go-v0.38 x rust-v0.54 (ws, tls, yamux) | go-v0.38 | rust-v0.54 | ws | tls | yamux | ✅ | 5s | 181.519 | 42.052 |
| go-v0.38 x rust-v0.54 (ws, noise, yamux) | go-v0.38 | rust-v0.54 | ws | noise | yamux | ✅ | 5s | 182.695 | 41.924 |
| go-v0.38 x rust-v0.54 (quic-v1) | go-v0.38 | rust-v0.54 | quic-v1 | - | - | ✅ | 5s | 5.463 | 0.283 |
| go-v0.38 x rust-v0.54 (webrtc-direct) | go-v0.38 | rust-v0.54 | webrtc-direct | - | - | ✅ | 5s | 207.214 | 0.254 |
| go-v0.38 x rust-v0.55 (tcp, tls, yamux) | go-v0.38 | rust-v0.55 | tcp | tls | yamux | ✅ | 5s | 9.408 | 1.307 |
| go-v0.38 x rust-v0.55 (ws, tls, yamux) | go-v0.38 | rust-v0.55 | ws | tls | yamux | ✅ | 5s | 9.17 | 0.416 |
| go-v0.38 x rust-v0.55 (tcp, noise, yamux) | go-v0.38 | rust-v0.55 | tcp | noise | yamux | ✅ | 5s | 5.4 | 0.188 |
| go-v0.38 x rust-v0.55 (ws, noise, yamux) | go-v0.38 | rust-v0.55 | ws | noise | yamux | ✅ | 5s | 8.304 | 0.37 |
| go-v0.38 x rust-v0.55 (quic-v1) | go-v0.38 | rust-v0.55 | quic-v1 | - | - | ✅ | 5s | 5.944 | 0.297 |
| go-v0.38 x rust-v0.55 (webrtc-direct) | go-v0.38 | rust-v0.55 | webrtc-direct | - | - | ✅ | 5s | 415.508 | 0.551 |
| go-v0.38 x rust-v0.56 (tcp, tls, yamux) | go-v0.38 | rust-v0.56 | tcp | tls | yamux | ✅ | 5s | 10.344 | 0.273 |
| go-v0.38 x rust-v0.56 (tcp, noise, yamux) | go-v0.38 | rust-v0.56 | tcp | noise | yamux | ✅ | 5s | 18.077 | 3.404 |
| go-v0.38 x rust-v0.56 (ws, tls, yamux) | go-v0.38 | rust-v0.56 | ws | tls | yamux | ✅ | 5s | 4.914 | 0.474 |
| go-v0.38 x rust-v0.56 (ws, noise, yamux) | go-v0.38 | rust-v0.56 | ws | noise | yamux | ✅ | 5s | 10.001 | 2.828 |
| go-v0.38 x rust-v0.56 (quic-v1) | go-v0.38 | rust-v0.56 | quic-v1 | - | - | ✅ | 4s | 10.257 | 0.8 |
| go-v0.38 x go-v0.38 (tcp, tls, yamux) | go-v0.38 | go-v0.38 | tcp | tls | yamux | ✅ | 5s | 13.254 | 2.208 |
| go-v0.38 x go-v0.38 (tcp, noise, yamux) | go-v0.38 | go-v0.38 | tcp | noise | yamux | ✅ | 4s | 9.247 | 0.418 |
| go-v0.38 x go-v0.38 (ws, tls, yamux) | go-v0.38 | go-v0.38 | ws | tls | yamux | ✅ | 4s | 6.989 | 0.332 |
| go-v0.38 x go-v0.38 (ws, noise, yamux) | go-v0.38 | go-v0.38 | ws | noise | yamux | ✅ | 4s | 8.648 | 0.493 |
| go-v0.38 x go-v0.38 (wss, tls, yamux) | go-v0.38 | go-v0.38 | wss | tls | yamux | ✅ | 4s | 14.06 | 0.531 |
| go-v0.38 x go-v0.38 (quic-v1) | go-v0.38 | go-v0.38 | quic-v1 | - | - | ✅ | 4s | 13.257 | 0.661 |
| go-v0.38 x go-v0.38 (wss, noise, yamux) | go-v0.38 | go-v0.38 | wss | noise | yamux | ✅ | 5s | 14.376 | 0.372 |
| go-v0.38 x rust-v0.56 (webrtc-direct) | go-v0.38 | rust-v0.56 | webrtc-direct | - | - | ❌ | 10s | - | - |
| go-v0.38 x go-v0.38 (webtransport) | go-v0.38 | go-v0.38 | webtransport | - | - | ✅ | 5s | 13.518 | 0.704 |
| go-v0.38 x go-v0.38 (webrtc-direct) | go-v0.38 | go-v0.38 | webrtc-direct | - | - | ✅ | 5s | 220.653 | 0.9 |
| go-v0.38 x go-v0.39 (tcp, tls, yamux) | go-v0.38 | go-v0.39 | tcp | tls | yamux | ✅ | 4s | 6.68 | 0.322 |
| go-v0.38 x go-v0.39 (tcp, noise, yamux) | go-v0.38 | go-v0.39 | tcp | noise | yamux | ✅ | 5s | 11.852 | 2.099 |
| go-v0.38 x go-v0.39 (ws, tls, yamux) | go-v0.38 | go-v0.39 | ws | tls | yamux | ✅ | 4s | 9.287 | 1.524 |
| go-v0.38 x go-v0.39 (ws, noise, yamux) | go-v0.38 | go-v0.39 | ws | noise | yamux | ✅ | 5s | 14.89 | 0.401 |
| go-v0.38 x go-v0.39 (wss, tls, yamux) | go-v0.38 | go-v0.39 | wss | tls | yamux | ✅ | 4s | 14.39 | 0.989 |
| go-v0.38 x go-v0.39 (wss, noise, yamux) | go-v0.38 | go-v0.39 | wss | noise | yamux | ✅ | 5s | 23.557 | 2.538 |
| go-v0.38 x go-v0.39 (webtransport) | go-v0.38 | go-v0.39 | webtransport | - | - | ✅ | 4s | 12.753 | 0.454 |
| go-v0.38 x go-v0.39 (quic-v1) | go-v0.38 | go-v0.39 | quic-v1 | - | - | ✅ | 4s | 10.29 | 0.47 |
| go-v0.38 x go-v0.39 (webrtc-direct) | go-v0.38 | go-v0.39 | webrtc-direct | - | - | ✅ | 4s | 212.546 | 0.574 |
| go-v0.38 x go-v0.40 (tcp, tls, yamux) | go-v0.38 | go-v0.40 | tcp | tls | yamux | ✅ | 5s | 6.994 | 0.678 |
| go-v0.38 x go-v0.40 (tcp, noise, yamux) | go-v0.38 | go-v0.40 | tcp | noise | yamux | ✅ | 5s | 10.58 | 2.105 |
| go-v0.38 x go-v0.40 (ws, tls, yamux) | go-v0.38 | go-v0.40 | ws | tls | yamux | ✅ | 4s | 13.65 | 0.373 |
| go-v0.38 x go-v0.40 (ws, noise, yamux) | go-v0.38 | go-v0.40 | ws | noise | yamux | ✅ | 5s | 12.833 | 0.55 |
| go-v0.38 x go-v0.40 (wss, tls, yamux) | go-v0.38 | go-v0.40 | wss | tls | yamux | ✅ | 5s | 15.272 | 0.417 |
| go-v0.38 x go-v0.40 (wss, noise, yamux) | go-v0.38 | go-v0.40 | wss | noise | yamux | ✅ | 4s | 15.804 | 0.367 |
| go-v0.38 x go-v0.40 (quic-v1) | go-v0.38 | go-v0.40 | quic-v1 | - | - | ✅ | 5s | 6.549 | 0.353 |
| go-v0.38 x go-v0.40 (webtransport) | go-v0.38 | go-v0.40 | webtransport | - | - | ✅ | 5s | 16.693 | 0.926 |
| go-v0.38 x go-v0.40 (webrtc-direct) | go-v0.38 | go-v0.40 | webrtc-direct | - | - | ✅ | 5s | 216.434 | 2.5 |
| go-v0.38 x go-v0.41 (tcp, tls, yamux) | go-v0.38 | go-v0.41 | tcp | tls | yamux | ✅ | 5s | 14.48 | 0.506 |
| go-v0.38 x go-v0.41 (tcp, noise, yamux) | go-v0.38 | go-v0.41 | tcp | noise | yamux | ✅ | 5s | 14.534 | 4.63 |
| go-v0.38 x go-v0.41 (ws, tls, yamux) | go-v0.38 | go-v0.41 | ws | tls | yamux | ✅ | 5s | 8.36 | 0.275 |
| go-v0.38 x go-v0.41 (ws, noise, yamux) | go-v0.38 | go-v0.41 | ws | noise | yamux | ✅ | 5s | 9.084 | 0.362 |
| go-v0.38 x go-v0.41 (wss, tls, yamux) | go-v0.38 | go-v0.41 | wss | tls | yamux | ✅ | 5s | 19.538 | 1.1 |
| go-v0.38 x go-v0.41 (quic-v1) | go-v0.38 | go-v0.41 | quic-v1 | - | - | ✅ | 5s | 14.991 | 0.503 |
| go-v0.38 x go-v0.41 (webtransport) | go-v0.38 | go-v0.41 | webtransport | - | - | ✅ | 4s | 14.635 | 0.848 |
| go-v0.38 x go-v0.41 (wss, noise, yamux) | go-v0.38 | go-v0.41 | wss | noise | yamux | ✅ | 6s | 10.257 | 0.299 |
| go-v0.38 x go-v0.41 (webrtc-direct) | go-v0.38 | go-v0.41 | webrtc-direct | - | - | ✅ | 4s | 209.381 | 0.358 |
| go-v0.38 x go-v0.42 (tcp, noise, yamux) | go-v0.38 | go-v0.42 | tcp | noise | yamux | ✅ | 4s | 13.627 | 0.982 |
| go-v0.38 x go-v0.42 (tcp, tls, yamux) | go-v0.38 | go-v0.42 | tcp | tls | yamux | ✅ | 6s | 11.824 | 2.187 |
| go-v0.38 x go-v0.42 (ws, tls, yamux) | go-v0.38 | go-v0.42 | ws | tls | yamux | ✅ | 4s | 7.593 | 0.523 |
| go-v0.38 x go-v0.42 (ws, noise, yamux) | go-v0.38 | go-v0.42 | ws | noise | yamux | ✅ | 5s | 8.515 | 0.746 |
| go-v0.38 x go-v0.42 (wss, tls, yamux) | go-v0.38 | go-v0.42 | wss | tls | yamux | ✅ | 5s | 23.295 | 0.582 |
| go-v0.38 x go-v0.42 (quic-v1) | go-v0.38 | go-v0.42 | quic-v1 | - | - | ✅ | 5s | 17.788 | 1.415 |
| go-v0.38 x go-v0.42 (wss, noise, yamux) | go-v0.38 | go-v0.42 | wss | noise | yamux | ✅ | 5s | 17.201 | 0.979 |
| go-v0.38 x go-v0.42 (webtransport) | go-v0.38 | go-v0.42 | webtransport | - | - | ✅ | 5s | 9.524 | 0.468 |
| go-v0.38 x go-v0.42 (webrtc-direct) | go-v0.38 | go-v0.42 | webrtc-direct | - | - | ✅ | 4s | 210.585 | 0.334 |
| go-v0.38 x go-v0.43 (tcp, tls, yamux) | go-v0.38 | go-v0.43 | tcp | tls | yamux | ✅ | 5s | 13.897 | 0.7 |
| go-v0.38 x go-v0.43 (tcp, noise, yamux) | go-v0.38 | go-v0.43 | tcp | noise | yamux | ✅ | 5s | 11.312 | 0.261 |
| go-v0.38 x go-v0.43 (ws, tls, yamux) | go-v0.38 | go-v0.43 | ws | tls | yamux | ✅ | 4s | 14.319 | 3.508 |
| go-v0.38 x go-v0.43 (ws, noise, yamux) | go-v0.38 | go-v0.43 | ws | noise | yamux | ✅ | 5s | 12.151 | 1.132 |
| go-v0.38 x go-v0.43 (wss, noise, yamux) | go-v0.38 | go-v0.43 | wss | noise | yamux | ✅ | 4s | 20.889 | 0.614 |
| go-v0.38 x go-v0.43 (quic-v1) | go-v0.38 | go-v0.43 | quic-v1 | - | - | ✅ | 5s | 15.291 | 0.607 |
| go-v0.38 x go-v0.43 (wss, tls, yamux) | go-v0.38 | go-v0.43 | wss | tls | yamux | ✅ | 6s | 21.47 | 0.355 |
| go-v0.38 x go-v0.43 (webtransport) | go-v0.38 | go-v0.43 | webtransport | - | - | ✅ | 5s | 12.412 | 0.405 |
| go-v0.38 x go-v0.43 (webrtc-direct) | go-v0.38 | go-v0.43 | webrtc-direct | - | - | ✅ | 4s | 218.642 | 1.103 |
| go-v0.38 x go-v0.44 (tcp, tls, yamux) | go-v0.38 | go-v0.44 | tcp | tls | yamux | ✅ | 4s | 7.234 | 0.412 |
| go-v0.38 x go-v0.44 (tcp, noise, yamux) | go-v0.38 | go-v0.44 | tcp | noise | yamux | ✅ | 4s | 13.258 | 0.519 |
| go-v0.38 x go-v0.44 (ws, tls, yamux) | go-v0.38 | go-v0.44 | ws | tls | yamux | ✅ | 4s | 13.852 | 1.542 |
| go-v0.38 x go-v0.44 (ws, noise, yamux) | go-v0.38 | go-v0.44 | ws | noise | yamux | ✅ | 4s | 10.581 | 1.808 |
| go-v0.38 x go-v0.44 (wss, tls, yamux) | go-v0.38 | go-v0.44 | wss | tls | yamux | ✅ | 5s | 19.697 | 0.582 |
| go-v0.38 x go-v0.44 (quic-v1) | go-v0.38 | go-v0.44 | quic-v1 | - | - | ✅ | 5s | 8.168 | 0.542 |
| go-v0.38 x go-v0.44 (wss, noise, yamux) | go-v0.38 | go-v0.44 | wss | noise | yamux | ✅ | 5s | 18.261 | 0.223 |
| go-v0.38 x go-v0.44 (webtransport) | go-v0.38 | go-v0.44 | webtransport | - | - | ✅ | 4s | 14.746 | 0.541 |
| go-v0.38 x go-v0.44 (webrtc-direct) | go-v0.38 | go-v0.44 | webrtc-direct | - | - | ✅ | 5s | 20.57 | 0.705 |
| go-v0.38 x go-v0.45 (tcp, tls, yamux) | go-v0.38 | go-v0.45 | tcp | tls | yamux | ✅ | 5s | 11.412 | 0.475 |
| go-v0.38 x go-v0.45 (tcp, noise, yamux) | go-v0.38 | go-v0.45 | tcp | noise | yamux | ✅ | 5s | 8.818 | 0.384 |
| go-v0.38 x go-v0.45 (ws, tls, yamux) | go-v0.38 | go-v0.45 | ws | tls | yamux | ✅ | 4s | 10.407 | 1.238 |
| go-v0.38 x go-v0.45 (ws, noise, yamux) | go-v0.38 | go-v0.45 | ws | noise | yamux | ✅ | 5s | 16.445 | 0.543 |
| go-v0.38 x go-v0.45 (wss, tls, yamux) | go-v0.38 | go-v0.45 | wss | tls | yamux | ✅ | 6s | 22.775 | 3.712 |
| go-v0.38 x go-v0.45 (wss, noise, yamux) | go-v0.38 | go-v0.45 | wss | noise | yamux | ✅ | 5s | 18.981 | 0.36 |
| go-v0.38 x go-v0.45 (quic-v1) | go-v0.38 | go-v0.45 | quic-v1 | - | - | ✅ | 6s | 14.808 | 1.327 |
| go-v0.38 x go-v0.45 (webtransport) | go-v0.38 | go-v0.45 | webtransport | - | - | ✅ | 5s | 12.074 | 0.368 |
| go-v0.38 x go-v0.45 (webrtc-direct) | go-v0.38 | go-v0.45 | webrtc-direct | - | - | ✅ | 5s | 209.257 | 0.185 |
| go-v0.38 x python-v0.4 (tcp, noise, yamux) | go-v0.38 | python-v0.4 | tcp | noise | yamux | ✅ | 5s | 20.023 | 4.089 |
| go-v0.38 x python-v0.4 (ws, noise, yamux) | go-v0.38 | python-v0.4 | ws | noise | yamux | ✅ | 5s | 28.587 | 4.373 |
| go-v0.38 x python-v0.4 (wss, noise, yamux) | go-v0.38 | python-v0.4 | wss | noise | yamux | ✅ | 6s | 39.345 | 6.764 |
| go-v0.38 x python-v0.4 (quic-v1) | go-v0.38 | python-v0.4 | quic-v1 | - | - | ✅ | 6s | 61.54 | 17.071 |
| go-v0.38 x nim-v1.14 (tcp, noise, yamux) | go-v0.38 | nim-v1.14 | tcp | noise | yamux | ✅ | 5s | 213.725 | 43.664 |
| go-v0.38 x nim-v1.14 (ws, noise, yamux) | go-v0.38 | nim-v1.14 | ws | noise | yamux | ✅ | 4s | 249.779 | 43.589 |
| go-v0.38 x js-v1.x (ws, noise, yamux) | go-v0.38 | js-v1.x | ws | noise | yamux | ✅ | 19s | 162.671 | 17.19 |
| go-v0.38 x js-v1.x (tcp, noise, yamux) | go-v0.38 | js-v1.x | tcp | noise | yamux | ✅ | 20s | 288.817 | 30.735 |
| go-v0.38 x js-v2.x (ws, noise, yamux) | go-v0.38 | js-v2.x | ws | noise | yamux | ✅ | 21s | 177.941 | 21.623 |
| go-v0.38 x js-v2.x (tcp, noise, yamux) | go-v0.38 | js-v2.x | tcp | noise | yamux | ✅ | 23s | 194.607 | 23.384 |
| go-v0.38 x jvm-v1.2 (tcp, noise, yamux) | go-v0.38 | jvm-v1.2 | tcp | noise | yamux | ✅ | 11s | 1126.72 | 39.018 |
| go-v0.38 x js-v3.x (tcp, noise, yamux) | go-v0.38 | js-v3.x | tcp | noise | yamux | ✅ | 22s | 126.194 | 18.829 |
| go-v0.38 x js-v3.x (ws, noise, yamux) | go-v0.38 | js-v3.x | ws | noise | yamux | ✅ | 21s | 159.571 | 22.962 |
| go-v0.38 x jvm-v1.2 (tcp, tls, yamux) | go-v0.38 | jvm-v1.2 | tcp | tls | yamux | ✅ | 13s | 3395.484 | 16.372 |
| go-v0.38 x c-v0.0.1 (tcp, noise, yamux) | go-v0.38 | c-v0.0.1 | tcp | noise | yamux | ✅ | 6s | 129.339 | 56.381 |
| go-v0.38 x c-v0.0.1 (quic-v1) | go-v0.38 | c-v0.0.1 | quic-v1 | - | - | ❌ | 5s | - | - |
| go-v0.38 x jvm-v1.2 (ws, noise, yamux) | go-v0.38 | jvm-v1.2 | ws | noise | yamux | ✅ | 10s | 1301.281 | 34.102 |
| go-v0.38 x zig-v0.0.1 (quic-v1) | go-v0.38 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 6s | - | - |
| go-v0.38 x jvm-v1.2 (ws, tls, yamux) | go-v0.38 | jvm-v1.2 | ws | tls | yamux | ✅ | 12s | 3551.445 | 11.423 |
| go-v0.38 x dotnet-v1.0 (tcp, noise, yamux) | go-v0.38 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 7s | 515.741 | 52.456 |
| go-v0.38 x eth-p2p-z-v0.0.1 (quic-v1) | go-v0.38 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 7s | 13.767 | 0.98 |
| go-v0.38 x jvm-v1.2 (quic-v1) | go-v0.38 | jvm-v1.2 | quic-v1 | - | - | ✅ | 11s | 712.337 | 11.364 |
| go-v0.39 x rust-v0.53 (tcp, noise, yamux) | go-v0.39 | rust-v0.53 | tcp | noise | yamux | ✅ | 3s | 145.528 | 47.759 |
| go-v0.39 x rust-v0.53 (tcp, tls, yamux) | go-v0.39 | rust-v0.53 | tcp | tls | yamux | ✅ | 5s | 140.563 | 47.647 |
| go-v0.39 x rust-v0.53 (ws, noise, yamux) | go-v0.39 | rust-v0.53 | ws | noise | yamux | ✅ | 4s | 187.169 | 41.001 |
| go-v0.39 x rust-v0.53 (ws, tls, yamux) | go-v0.39 | rust-v0.53 | ws | tls | yamux | ✅ | 6s | 185.092 | 43.582 |
| go-v0.39 x rust-v0.53 (quic-v1) | go-v0.39 | rust-v0.53 | quic-v1 | - | - | ✅ | 5s | 6.237 | 0.287 |
| go-v0.39 x rust-v0.53 (webrtc-direct) | go-v0.39 | rust-v0.53 | webrtc-direct | - | - | ✅ | 5s | 416.884 | 0.444 |
| go-v0.39 x rust-v0.54 (tcp, tls, yamux) | go-v0.39 | rust-v0.54 | tcp | tls | yamux | ✅ | 5s | 102.129 | 46.906 |
| go-v0.39 x rust-v0.54 (tcp, noise, yamux) | go-v0.39 | rust-v0.54 | tcp | noise | yamux | ✅ | 5s | 88.761 | 42.775 |
| go-v0.39 x rust-v0.54 (ws, noise, yamux) | go-v0.39 | rust-v0.54 | ws | noise | yamux | ✅ | 5s | 191.435 | 43.078 |
| go-v0.39 x rust-v0.54 (ws, tls, yamux) | go-v0.39 | rust-v0.54 | ws | tls | yamux | ✅ | 5s | 234.394 | 47.637 |
| go-v0.39 x rust-v0.54 (quic-v1) | go-v0.39 | rust-v0.54 | quic-v1 | - | - | ✅ | 4s | 10.432 | 0.739 |
| go-v0.39 x rust-v0.55 (tcp, tls, yamux) | go-v0.39 | rust-v0.55 | tcp | tls | yamux | ✅ | 4s | 13.401 | 0.47 |
| go-v0.39 x rust-v0.54 (webrtc-direct) | go-v0.39 | rust-v0.54 | webrtc-direct | - | - | ✅ | 5s | 420.482 | 2.38 |
| go-v0.39 x rust-v0.55 (tcp, noise, yamux) | go-v0.39 | rust-v0.55 | tcp | noise | yamux | ✅ | 5s | 8.028 | 0.937 |
| go-v0.39 x rust-v0.55 (ws, tls, yamux) | go-v0.39 | rust-v0.55 | ws | tls | yamux | ✅ | 4s | 7.424 | 0.39 |
| go-v0.39 x rust-v0.55 (ws, noise, yamux) | go-v0.39 | rust-v0.55 | ws | noise | yamux | ✅ | 5s | 9.767 | 0.715 |
| go-v0.39 x rust-v0.55 (quic-v1) | go-v0.39 | rust-v0.55 | quic-v1 | - | - | ✅ | 5s | 14.746 | 2.465 |
| go-v0.39 x rust-v0.56 (tcp, tls, yamux) | go-v0.39 | rust-v0.56 | tcp | tls | yamux | ✅ | 4s | 7.621 | 0.349 |
| go-v0.39 x rust-v0.55 (webrtc-direct) | go-v0.39 | rust-v0.55 | webrtc-direct | - | - | ✅ | 5s | 413.781 | 0.365 |
| go-v0.39 x rust-v0.56 (tcp, noise, yamux) | go-v0.39 | rust-v0.56 | tcp | noise | yamux | ✅ | 4s | 15.164 | 1.26 |
| go-v0.39 x rust-v0.56 (ws, tls, yamux) | go-v0.39 | rust-v0.56 | ws | tls | yamux | ✅ | 4s | 3.971 | 0.249 |
| go-v0.39 x rust-v0.56 (ws, noise, yamux) | go-v0.39 | rust-v0.56 | ws | noise | yamux | ✅ | 4s | 6.022 | 0.449 |
| go-v0.39 x rust-v0.56 (quic-v1) | go-v0.39 | rust-v0.56 | quic-v1 | - | - | ✅ | 5s | 15.482 | 0.591 |
| go-v0.39 x go-v0.38 (tcp, tls, yamux) | go-v0.39 | go-v0.38 | tcp | tls | yamux | ✅ | 4s | 14.713 | 1.284 |
| go-v0.39 x go-v0.38 (tcp, noise, yamux) | go-v0.39 | go-v0.38 | tcp | noise | yamux | ✅ | 5s | 10.733 | 0.444 |
| go-v0.39 x go-v0.38 (ws, tls, yamux) | go-v0.39 | go-v0.38 | ws | tls | yamux | ✅ | 4s | 5.803 | 0.287 |
| go-v0.39 x go-v0.38 (ws, noise, yamux) | go-v0.39 | go-v0.38 | ws | noise | yamux | ✅ | 4s | 18.583 | 2.092 |
| go-v0.39 x go-v0.38 (wss, tls, yamux) | go-v0.39 | go-v0.38 | wss | tls | yamux | ✅ | 5s | 11.597 | 0.186 |
| go-v0.39 x go-v0.38 (wss, noise, yamux) | go-v0.39 | go-v0.38 | wss | noise | yamux | ✅ | 4s | 11.107 | 0.304 |
| go-v0.39 x go-v0.38 (quic-v1) | go-v0.39 | go-v0.38 | quic-v1 | - | - | ✅ | 5s | 7.869 | 0.487 |
| go-v0.39 x rust-v0.56 (webrtc-direct) | go-v0.39 | rust-v0.56 | webrtc-direct | - | - | ❌ | 9s | - | - |
| go-v0.39 x go-v0.38 (webtransport) | go-v0.39 | go-v0.38 | webtransport | - | - | ✅ | 5s | 13.639 | 0.34 |
| go-v0.39 x go-v0.39 (tcp, tls, yamux) | go-v0.39 | go-v0.39 | tcp | tls | yamux | ✅ | 4s | 16.091 | 0.508 |
| go-v0.39 x go-v0.38 (webrtc-direct) | go-v0.39 | go-v0.38 | webrtc-direct | - | - | ✅ | 6s | 229.115 | 2.17 |
| go-v0.39 x go-v0.39 (tcp, noise, yamux) | go-v0.39 | go-v0.39 | tcp | noise | yamux | ✅ | 5s | 6.841 | 0.393 |
| go-v0.39 x go-v0.39 (ws, tls, yamux) | go-v0.39 | go-v0.39 | ws | tls | yamux | ✅ | 5s | 6.387 | 0.343 |
| go-v0.39 x go-v0.39 (ws, noise, yamux) | go-v0.39 | go-v0.39 | ws | noise | yamux | ✅ | 4s | 8.349 | 0.636 |
| go-v0.39 x go-v0.39 (wss, tls, yamux) | go-v0.39 | go-v0.39 | wss | tls | yamux | ✅ | 6s | 19.457 | 0.455 |
| go-v0.39 x go-v0.39 (quic-v1) | go-v0.39 | go-v0.39 | quic-v1 | - | - | ✅ | 5s | 18.786 | 3.487 |
| go-v0.39 x go-v0.39 (wss, noise, yamux) | go-v0.39 | go-v0.39 | wss | noise | yamux | ✅ | 6s | 14.307 | 0.608 |
| go-v0.39 x go-v0.39 (webtransport) | go-v0.39 | go-v0.39 | webtransport | - | - | ✅ | 4s | 17.777 | 1.329 |
| go-v0.39 x go-v0.39 (webrtc-direct) | go-v0.39 | go-v0.39 | webrtc-direct | - | - | ✅ | 5s | 216.758 | 0.91 |
| go-v0.39 x go-v0.40 (tcp, tls, yamux) | go-v0.39 | go-v0.40 | tcp | tls | yamux | ✅ | 5s | 18.337 | 0.376 |
| go-v0.39 x go-v0.40 (ws, tls, yamux) | go-v0.39 | go-v0.40 | ws | tls | yamux | ✅ | 4s | 9.444 | 0.549 |
| go-v0.39 x go-v0.40 (tcp, noise, yamux) | go-v0.39 | go-v0.40 | tcp | noise | yamux | ✅ | 5s | 8.193 | 0.545 |
| go-v0.39 x go-v0.40 (ws, noise, yamux) | go-v0.39 | go-v0.40 | ws | noise | yamux | ✅ | 5s | 12.865 | 0.74 |
| go-v0.39 x go-v0.40 (quic-v1) | go-v0.39 | go-v0.40 | quic-v1 | - | - | ✅ | 4s | 16.119 | 1.293 |
| go-v0.39 x go-v0.40 (wss, tls, yamux) | go-v0.39 | go-v0.40 | wss | tls | yamux | ✅ | 5s | 16.734 | 0.866 |
| go-v0.39 x go-v0.40 (wss, noise, yamux) | go-v0.39 | go-v0.40 | wss | noise | yamux | ✅ | 6s | 7.823 | 0.288 |
| go-v0.39 x go-v0.40 (webtransport) | go-v0.39 | go-v0.40 | webtransport | - | - | ✅ | 5s | 11.868 | 0.553 |
| go-v0.39 x go-v0.40 (webrtc-direct) | go-v0.39 | go-v0.40 | webrtc-direct | - | - | ✅ | 5s | 213.488 | 0.684 |
| go-v0.39 x go-v0.41 (tcp, tls, yamux) | go-v0.39 | go-v0.41 | tcp | tls | yamux | ✅ | 5s | 10.59 | 0.827 |
| go-v0.39 x go-v0.41 (tcp, noise, yamux) | go-v0.39 | go-v0.41 | tcp | noise | yamux | ✅ | 4s | 9.733 | 1.414 |
| go-v0.39 x go-v0.41 (ws, tls, yamux) | go-v0.39 | go-v0.41 | ws | tls | yamux | ✅ | 5s | 7.178 | 0.25 |
| go-v0.39 x go-v0.41 (ws, noise, yamux) | go-v0.39 | go-v0.41 | ws | noise | yamux | ✅ | 4s | 13.339 | 1.408 |
| go-v0.39 x go-v0.41 (wss, tls, yamux) | go-v0.39 | go-v0.41 | wss | tls | yamux | ✅ | 5s | 21.54 | 0.928 |
| go-v0.39 x go-v0.41 (quic-v1) | go-v0.39 | go-v0.41 | quic-v1 | - | - | ✅ | 4s | 13.465 | 0.738 |
| go-v0.39 x go-v0.41 (wss, noise, yamux) | go-v0.39 | go-v0.41 | wss | noise | yamux | ✅ | 5s | 9.658 | 0.502 |
| go-v0.39 x go-v0.41 (webtransport) | go-v0.39 | go-v0.41 | webtransport | - | - | ✅ | 4s | 11.761 | 0.442 |
| go-v0.39 x go-v0.42 (tcp, tls, yamux) | go-v0.39 | go-v0.42 | tcp | tls | yamux | ✅ | 4s | 9.207 | 1.757 |
| go-v0.39 x go-v0.41 (webrtc-direct) | go-v0.39 | go-v0.41 | webrtc-direct | - | - | ✅ | 5s | 216.806 | 0.615 |
| go-v0.39 x go-v0.42 (tcp, noise, yamux) | go-v0.39 | go-v0.42 | tcp | noise | yamux | ✅ | 5s | 7.364 | 0.582 |
| go-v0.39 x go-v0.42 (ws, tls, yamux) | go-v0.39 | go-v0.42 | ws | tls | yamux | ✅ | 5s | 10.305 | 0.442 |
| go-v0.39 x go-v0.42 (ws, noise, yamux) | go-v0.39 | go-v0.42 | ws | noise | yamux | ✅ | 5s | 16.185 | 0.601 |
| go-v0.39 x go-v0.42 (wss, noise, yamux) | go-v0.39 | go-v0.42 | wss | noise | yamux | ✅ | 5s | 24.644 | 0.788 |
| go-v0.39 x go-v0.42 (wss, tls, yamux) | go-v0.39 | go-v0.42 | wss | tls | yamux | ✅ | 5s | 16.944 | 1.035 |
| go-v0.39 x go-v0.42 (quic-v1) | go-v0.39 | go-v0.42 | quic-v1 | - | - | ✅ | 5s | 8.585 | 0.369 |
| go-v0.39 x go-v0.42 (webtransport) | go-v0.39 | go-v0.42 | webtransport | - | - | ✅ | 5s | 22.027 | 0.576 |
| go-v0.39 x go-v0.42 (webrtc-direct) | go-v0.39 | go-v0.42 | webrtc-direct | - | - | ✅ | 5s | 213.671 | 0.578 |
| go-v0.39 x go-v0.43 (tcp, noise, yamux) | go-v0.39 | go-v0.43 | tcp | noise | yamux | ✅ | 4s | 7.121 | 0.315 |
| go-v0.39 x go-v0.43 (tcp, tls, yamux) | go-v0.39 | go-v0.43 | tcp | tls | yamux | ✅ | 6s | 9.345 | 1.876 |
| go-v0.39 x go-v0.43 (ws, tls, yamux) | go-v0.39 | go-v0.43 | ws | tls | yamux | ✅ | 5s | 11.876 | 1.469 |
| go-v0.39 x go-v0.43 (ws, noise, yamux) | go-v0.39 | go-v0.43 | ws | noise | yamux | ✅ | 4s | 20.715 | 2.783 |
| go-v0.39 x go-v0.43 (wss, tls, yamux) | go-v0.39 | go-v0.43 | wss | tls | yamux | ✅ | 5s | 21.148 | 1.213 |
| go-v0.39 x go-v0.43 (wss, noise, yamux) | go-v0.39 | go-v0.43 | wss | noise | yamux | ✅ | 6s | 9.464 | 0.532 |
| go-v0.39 x go-v0.43 (quic-v1) | go-v0.39 | go-v0.43 | quic-v1 | - | - | ✅ | 5s | 7.785 | 0.351 |
| go-v0.39 x go-v0.43 (webtransport) | go-v0.39 | go-v0.43 | webtransport | - | - | ✅ | 5s | 17.265 | 1.12 |
| go-v0.39 x go-v0.44 (tcp, tls, yamux) | go-v0.39 | go-v0.44 | tcp | tls | yamux | ✅ | 4s | 13.808 | 3.496 |
| go-v0.39 x go-v0.43 (webrtc-direct) | go-v0.39 | go-v0.43 | webrtc-direct | - | - | ✅ | 5s | 220.791 | 0.984 |
| go-v0.39 x go-v0.44 (tcp, noise, yamux) | go-v0.39 | go-v0.44 | tcp | noise | yamux | ✅ | 5s | 11.652 | 0.55 |
| go-v0.39 x go-v0.44 (ws, tls, yamux) | go-v0.39 | go-v0.44 | ws | tls | yamux | ✅ | 4s | 10.265 | 0.305 |
| go-v0.39 x go-v0.44 (ws, noise, yamux) | go-v0.39 | go-v0.44 | ws | noise | yamux | ✅ | 5s | 12.313 | 0.676 |
| go-v0.39 x go-v0.44 (wss, tls, yamux) | go-v0.39 | go-v0.44 | wss | tls | yamux | ✅ | 6s | 22.643 | 0.854 |
| go-v0.39 x go-v0.44 (quic-v1) | go-v0.39 | go-v0.44 | quic-v1 | - | - | ✅ | 5s | 14.012 | 0.971 |
| go-v0.39 x go-v0.44 (wss, noise, yamux) | go-v0.39 | go-v0.44 | wss | noise | yamux | ✅ | 6s | 18.546 | 2.178 |
| go-v0.39 x go-v0.44 (webtransport) | go-v0.39 | go-v0.44 | webtransport | - | - | ✅ | 5s | 10.055 | 0.41 |
| go-v0.39 x go-v0.44 (webrtc-direct) | go-v0.39 | go-v0.44 | webrtc-direct | - | - | ✅ | 5s | 210.799 | 0.363 |
| go-v0.39 x go-v0.45 (tcp, tls, yamux) | go-v0.39 | go-v0.45 | tcp | tls | yamux | ✅ | 5s | 7.633 | 0.809 |
| go-v0.39 x go-v0.45 (ws, tls, yamux) | go-v0.39 | go-v0.45 | ws | tls | yamux | ✅ | 4s | 13.757 | 2.557 |
| go-v0.39 x go-v0.45 (tcp, noise, yamux) | go-v0.39 | go-v0.45 | tcp | noise | yamux | ✅ | 5s | 12.363 | 1.244 |
| go-v0.39 x go-v0.45 (ws, noise, yamux) | go-v0.39 | go-v0.45 | ws | noise | yamux | ✅ | 4s | 9.123 | 0.44 |
| go-v0.39 x go-v0.45 (quic-v1) | go-v0.39 | go-v0.45 | quic-v1 | - | - | ✅ | 4s | 19.712 | 3.614 |
| go-v0.39 x go-v0.45 (wss, tls, yamux) | go-v0.39 | go-v0.45 | wss | tls | yamux | ✅ | 5s | 13.226 | 0.338 |
| go-v0.39 x go-v0.45 (webtransport) | go-v0.39 | go-v0.45 | webtransport | - | - | ✅ | 5s | 17.917 | 0.545 |
| go-v0.39 x go-v0.45 (wss, noise, yamux) | go-v0.39 | go-v0.45 | wss | noise | yamux | ✅ | 6s | 14.682 | 0.902 |
| go-v0.39 x go-v0.45 (webrtc-direct) | go-v0.39 | go-v0.45 | webrtc-direct | - | - | ✅ | 5s | 210.253 | 0.41 |
| go-v0.39 x python-v0.4 (tcp, noise, yamux) | go-v0.39 | python-v0.4 | tcp | noise | yamux | ✅ | 4s | 20.496 | 4.933 |
| go-v0.39 x python-v0.4 (ws, noise, yamux) | go-v0.39 | python-v0.4 | ws | noise | yamux | ✅ | 5s | 20.154 | 4.378 |
| go-v0.39 x python-v0.4 (wss, noise, yamux) | go-v0.39 | python-v0.4 | wss | noise | yamux | ✅ | 5s | 40.797 | 4.925 |
| go-v0.39 x python-v0.4 (quic-v1) | go-v0.39 | python-v0.4 | quic-v1 | - | - | ✅ | 5s | 65.005 | 10.316 |
| go-v0.39 x nim-v1.14 (tcp, noise, yamux) | go-v0.39 | nim-v1.14 | tcp | noise | yamux | ✅ | 5s | 209.349 | 44.261 |
| go-v0.39 x nim-v1.14 (ws, noise, yamux) | go-v0.39 | nim-v1.14 | ws | noise | yamux | ✅ | 5s | 284.156 | 55.546 |
| go-v0.39 x js-v1.x (tcp, noise, yamux) | go-v0.39 | js-v1.x | tcp | noise | yamux | ✅ | 21s | 138.756 | 13.901 |
| go-v0.39 x js-v1.x (ws, noise, yamux) | go-v0.39 | js-v1.x | ws | noise | yamux | ✅ | 20s | 142.982 | 17.391 |
| go-v0.39 x js-v2.x (tcp, noise, yamux) | go-v0.39 | js-v2.x | tcp | noise | yamux | ✅ | 21s | 150.729 | 20.951 |
| go-v0.39 x js-v3.x (tcp, noise, yamux) | go-v0.39 | js-v3.x | tcp | noise | yamux | ✅ | 21s | 138.78 | 21.409 |
| go-v0.39 x js-v2.x (ws, noise, yamux) | go-v0.39 | js-v2.x | ws | noise | yamux | ✅ | 23s | 198.366 | 21.934 |
| go-v0.39 x jvm-v1.2 (tcp, noise, yamux) | go-v0.39 | jvm-v1.2 | tcp | noise | yamux | ✅ | 11s | 1264.807 | 50.843 |
| go-v0.39 x jvm-v1.2 (tcp, tls, yamux) | go-v0.39 | jvm-v1.2 | tcp | tls | yamux | ✅ | 14s | 3481.656 | 11.834 |
| go-v0.39 x js-v3.x (ws, noise, yamux) | go-v0.39 | js-v3.x | ws | noise | yamux | ✅ | 23s | 179.036 | 20.226 |
| go-v0.39 x c-v0.0.1 (tcp, noise, yamux) | go-v0.39 | c-v0.0.1 | tcp | noise | yamux | ✅ | 6s | 139.542 | 59.335 |
| go-v0.39 x c-v0.0.1 (quic-v1) | go-v0.39 | c-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 89.741 | 2.556 |
| go-v0.39 x jvm-v1.2 (ws, noise, yamux) | go-v0.39 | jvm-v1.2 | ws | noise | yamux | ✅ | 9s | 1565.528 | 45.4 |
| go-v0.39 x dotnet-v1.0 (tcp, noise, yamux) | go-v0.39 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 6s | 519.914 | 46.9 |
| go-v0.39 x zig-v0.0.1 (quic-v1) | go-v0.39 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 6s | - | - |
| go-v0.39 x eth-p2p-z-v0.0.1 (quic-v1) | go-v0.39 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 13.642 | 1.323 |
| go-v0.39 x jvm-v1.2 (ws, tls, yamux) | go-v0.39 | jvm-v1.2 | ws | tls | yamux | ✅ | 12s | 2901.827 | 10.623 |
| go-v0.39 x jvm-v1.2 (quic-v1) | go-v0.39 | jvm-v1.2 | quic-v1 | - | - | ✅ | 11s | 694.498 | 23.133 |
| go-v0.40 x rust-v0.53 (tcp, tls, yamux) | go-v0.40 | rust-v0.53 | tcp | tls | yamux | ✅ | 4s | 136.826 | 43.73 |
| go-v0.40 x rust-v0.53 (tcp, noise, yamux) | go-v0.40 | rust-v0.53 | tcp | noise | yamux | ✅ | 4s | 100.673 | 46.959 |
| go-v0.40 x rust-v0.53 (ws, tls, yamux) | go-v0.40 | rust-v0.53 | ws | tls | yamux | ✅ | 4s | 180.402 | 46.52 |
| go-v0.40 x rust-v0.53 (ws, noise, yamux) | go-v0.40 | rust-v0.53 | ws | noise | yamux | ✅ | 5s | 223.225 | 43.446 |
| go-v0.40 x rust-v0.53 (quic-v1) | go-v0.40 | rust-v0.53 | quic-v1 | - | - | ✅ | 6s | 6.161 | 0.553 |
| go-v0.40 x rust-v0.54 (tcp, tls, yamux) | go-v0.40 | rust-v0.54 | tcp | tls | yamux | ✅ | 4s | 140.142 | 43.675 |
| go-v0.40 x rust-v0.53 (webrtc-direct) | go-v0.40 | rust-v0.53 | webrtc-direct | - | - | ✅ | 5s | 415.174 | 1.017 |
| go-v0.40 x rust-v0.54 (tcp, noise, yamux) | go-v0.40 | rust-v0.54 | tcp | noise | yamux | ✅ | 5s | 86.62 | 42.752 |
| go-v0.40 x rust-v0.54 (ws, tls, yamux) | go-v0.40 | rust-v0.54 | ws | tls | yamux | ✅ | 5s | 189.107 | 48.177 |
| go-v0.40 x rust-v0.54 (ws, noise, yamux) | go-v0.40 | rust-v0.54 | ws | noise | yamux | ✅ | 5s | 188.848 | 45.669 |
| go-v0.40 x rust-v0.54 (quic-v1) | go-v0.40 | rust-v0.54 | quic-v1 | - | - | ✅ | 5s | 8.064 | 0.536 |
| go-v0.40 x rust-v0.54 (webrtc-direct) | go-v0.40 | rust-v0.54 | webrtc-direct | - | - | ✅ | 5s | 414.314 | 2.31 |
| go-v0.40 x rust-v0.55 (tcp, noise, yamux) | go-v0.40 | rust-v0.55 | tcp | noise | yamux | ✅ | 4s | 13.243 | 0.197 |
| go-v0.40 x rust-v0.55 (tcp, tls, yamux) | go-v0.40 | rust-v0.55 | tcp | tls | yamux | ✅ | 6s | 14.879 | 3.848 |
| go-v0.40 x rust-v0.55 (ws, tls, yamux) | go-v0.40 | rust-v0.55 | ws | tls | yamux | ✅ | 5s | 8.051 | 0.852 |
| go-v0.40 x rust-v0.55 (ws, noise, yamux) | go-v0.40 | rust-v0.55 | ws | noise | yamux | ✅ | 6s | 4.969 | 0.162 |
| go-v0.40 x rust-v0.55 (quic-v1) | go-v0.40 | rust-v0.55 | quic-v1 | - | - | ✅ | 4s | 9.464 | 0.567 |
| go-v0.40 x rust-v0.56 (tcp, tls, yamux) | go-v0.40 | rust-v0.56 | tcp | tls | yamux | ✅ | 4s | 6.716 | 0.545 |
| go-v0.40 x rust-v0.55 (webrtc-direct) | go-v0.40 | rust-v0.55 | webrtc-direct | - | - | ✅ | 5s | 416.159 | 0.547 |
| go-v0.40 x rust-v0.56 (tcp, noise, yamux) | go-v0.40 | rust-v0.56 | tcp | noise | yamux | ✅ | 3s | 11.647 | 2.91 |
| go-v0.40 x rust-v0.56 (ws, noise, yamux) | go-v0.40 | rust-v0.56 | ws | noise | yamux | ✅ | 3s | 5.317 | 0.432 |
| go-v0.40 x rust-v0.56 (ws, tls, yamux) | go-v0.40 | rust-v0.56 | ws | tls | yamux | ✅ | 5s | 7.815 | 0.395 |
| go-v0.40 x rust-v0.56 (quic-v1) | go-v0.40 | rust-v0.56 | quic-v1 | - | - | ✅ | 4s | 9.22 | 0.31 |
| go-v0.40 x go-v0.38 (tcp, tls, yamux) | go-v0.40 | go-v0.38 | tcp | tls | yamux | ✅ | 4s | 10.129 | 1.51 |
| go-v0.40 x go-v0.38 (tcp, noise, yamux) | go-v0.40 | go-v0.38 | tcp | noise | yamux | ✅ | 4s | 8.179 | 0.808 |
| go-v0.40 x go-v0.38 (ws, tls, yamux) | go-v0.40 | go-v0.38 | ws | tls | yamux | ✅ | 5s | 10.867 | 2.722 |
| go-v0.40 x go-v0.38 (ws, noise, yamux) | go-v0.40 | go-v0.38 | ws | noise | yamux | ✅ | 4s | 12.96 | 0.906 |
| go-v0.40 x go-v0.38 (wss, tls, yamux) | go-v0.40 | go-v0.38 | wss | tls | yamux | ✅ | 5s | 21.503 | 4.395 |
| go-v0.40 x go-v0.38 (quic-v1) | go-v0.40 | go-v0.38 | quic-v1 | - | - | ✅ | 4s | 16.519 | 0.565 |
| go-v0.40 x rust-v0.56 (webrtc-direct) | go-v0.40 | rust-v0.56 | webrtc-direct | - | - | ❌ | 10s | - | - |
| go-v0.40 x go-v0.38 (wss, noise, yamux) | go-v0.40 | go-v0.38 | wss | noise | yamux | ✅ | 6s | 10.331 | 1.983 |
| go-v0.40 x go-v0.38 (webtransport) | go-v0.40 | go-v0.38 | webtransport | - | - | ✅ | 5s | 12.365 | 1.419 |
| go-v0.40 x go-v0.38 (webrtc-direct) | go-v0.40 | go-v0.38 | webrtc-direct | - | - | ✅ | 4s | 209.668 | 0.232 |
| go-v0.40 x go-v0.39 (tcp, tls, yamux) | go-v0.40 | go-v0.39 | tcp | tls | yamux | ✅ | 4s | 5.791 | 0.271 |
| go-v0.40 x go-v0.39 (tcp, noise, yamux) | go-v0.40 | go-v0.39 | tcp | noise | yamux | ✅ | 5s | 5.638 | 0.815 |
| go-v0.40 x go-v0.39 (ws, tls, yamux) | go-v0.40 | go-v0.39 | ws | tls | yamux | ✅ | 4s | 13.025 | 0.491 |
| go-v0.40 x go-v0.39 (ws, noise, yamux) | go-v0.40 | go-v0.39 | ws | noise | yamux | ✅ | 5s | 16.139 | 0.497 |
| go-v0.40 x go-v0.39 (wss, tls, yamux) | go-v0.40 | go-v0.39 | wss | tls | yamux | ✅ | 5s | 16.051 | 2.73 |
| go-v0.40 x go-v0.39 (wss, noise, yamux) | go-v0.40 | go-v0.39 | wss | noise | yamux | ✅ | 5s | 13.277 | 0.849 |
| go-v0.40 x go-v0.39 (quic-v1) | go-v0.40 | go-v0.39 | quic-v1 | - | - | ✅ | 5s | 10.37 | 0.683 |
| go-v0.40 x go-v0.39 (webtransport) | go-v0.40 | go-v0.39 | webtransport | - | - | ✅ | 5s | 16.52 | 0.489 |
| go-v0.40 x go-v0.39 (webrtc-direct) | go-v0.40 | go-v0.39 | webrtc-direct | - | - | ✅ | 6s | 215.202 | 0.76 |
| go-v0.40 x go-v0.40 (tcp, tls, yamux) | go-v0.40 | go-v0.40 | tcp | tls | yamux | ✅ | 4s | 13.734 | 1.144 |
| go-v0.40 x go-v0.40 (tcp, noise, yamux) | go-v0.40 | go-v0.40 | tcp | noise | yamux | ✅ | 5s | 8.481 | 0.355 |
| go-v0.40 x go-v0.40 (ws, noise, yamux) | go-v0.40 | go-v0.40 | ws | noise | yamux | ✅ | 4s | 12.77 | 0.752 |
| go-v0.40 x go-v0.40 (ws, tls, yamux) | go-v0.40 | go-v0.40 | ws | tls | yamux | ✅ | 5s | 22.93 | 6.026 |
| go-v0.40 x go-v0.40 (wss, noise, yamux) | go-v0.40 | go-v0.40 | wss | noise | yamux | ✅ | 4s | 11.784 | 0.272 |
| go-v0.40 x go-v0.40 (wss, tls, yamux) | go-v0.40 | go-v0.40 | wss | tls | yamux | ✅ | 6s | 13.995 | 0.594 |
| go-v0.40 x go-v0.40 (quic-v1) | go-v0.40 | go-v0.40 | quic-v1 | - | - | ✅ | 5s | 13.316 | 0.351 |
| go-v0.40 x go-v0.40 (webtransport) | go-v0.40 | go-v0.40 | webtransport | - | - | ✅ | 5s | 19.085 | 0.623 |
| go-v0.40 x go-v0.40 (webrtc-direct) | go-v0.40 | go-v0.40 | webrtc-direct | - | - | ✅ | 5s | 214.673 | 0.694 |
| go-v0.40 x go-v0.41 (tcp, tls, yamux) | go-v0.40 | go-v0.41 | tcp | tls | yamux | ✅ | 5s | 10.323 | 0.361 |
| go-v0.40 x go-v0.41 (ws, tls, yamux) | go-v0.40 | go-v0.41 | ws | tls | yamux | ✅ | 4s | 9.887 | 0.322 |
| go-v0.40 x go-v0.41 (tcp, noise, yamux) | go-v0.40 | go-v0.41 | tcp | noise | yamux | ✅ | 6s | 10.82 | 2.922 |
| go-v0.40 x go-v0.41 (ws, noise, yamux) | go-v0.40 | go-v0.41 | ws | noise | yamux | ✅ | 4s | 6.2 | 0.19 |
| go-v0.40 x go-v0.41 (wss, tls, yamux) | go-v0.40 | go-v0.41 | wss | tls | yamux | ✅ | 5s | 11.654 | 1.84 |
| go-v0.40 x go-v0.41 (wss, noise, yamux) | go-v0.40 | go-v0.41 | wss | noise | yamux | ✅ | 5s | 21.273 | 1.538 |
| go-v0.40 x go-v0.41 (quic-v1) | go-v0.40 | go-v0.41 | quic-v1 | - | - | ✅ | 5s | 13.285 | 3.264 |
| go-v0.40 x go-v0.41 (webtransport) | go-v0.40 | go-v0.41 | webtransport | - | - | ✅ | 5s | 15.387 | 0.895 |
| go-v0.40 x go-v0.41 (webrtc-direct) | go-v0.40 | go-v0.41 | webrtc-direct | - | - | ✅ | 5s | 219.426 | 1.064 |
| go-v0.40 x go-v0.42 (tcp, tls, yamux) | go-v0.40 | go-v0.42 | tcp | tls | yamux | ✅ | 5s | 7.654 | 1.407 |
| go-v0.40 x go-v0.42 (tcp, noise, yamux) | go-v0.40 | go-v0.42 | tcp | noise | yamux | ✅ | 5s | 9.874 | 0.261 |
| go-v0.40 x go-v0.42 (ws, tls, yamux) | go-v0.40 | go-v0.42 | ws | tls | yamux | ✅ | 5s | 5.117 | 0.257 |
| go-v0.40 x go-v0.42 (ws, noise, yamux) | go-v0.40 | go-v0.42 | ws | noise | yamux | ✅ | 4s | 11.743 | 0.315 |
| go-v0.40 x go-v0.42 (wss, tls, yamux) | go-v0.40 | go-v0.42 | wss | tls | yamux | ✅ | 5s | 19.841 | 0.514 |
| go-v0.40 x go-v0.42 (wss, noise, yamux) | go-v0.40 | go-v0.42 | wss | noise | yamux | ✅ | 5s | 16.166 | 0.707 |
| go-v0.40 x go-v0.42 (quic-v1) | go-v0.40 | go-v0.42 | quic-v1 | - | - | ✅ | 4s | 17.456 | 2.901 |
| go-v0.40 x go-v0.42 (webtransport) | go-v0.40 | go-v0.42 | webtransport | - | - | ✅ | 5s | 19.819 | 1.363 |
| go-v0.40 x go-v0.42 (webrtc-direct) | go-v0.40 | go-v0.42 | webrtc-direct | - | - | ✅ | 4s | 215.962 | 0.658 |
| go-v0.40 x go-v0.43 (tcp, tls, yamux) | go-v0.40 | go-v0.43 | tcp | tls | yamux | ✅ | 5s | 9.499 | 0.711 |
| go-v0.40 x go-v0.43 (ws, tls, yamux) | go-v0.40 | go-v0.43 | ws | tls | yamux | ✅ | 4s | 5.297 | 0.525 |
| go-v0.40 x go-v0.43 (tcp, noise, yamux) | go-v0.40 | go-v0.43 | tcp | noise | yamux | ✅ | 6s | 8.513 | 0.35 |
| go-v0.40 x go-v0.43 (ws, noise, yamux) | go-v0.40 | go-v0.43 | ws | noise | yamux | ✅ | 4s | 12.282 | 3.81 |
| go-v0.40 x go-v0.43 (wss, noise, yamux) | go-v0.40 | go-v0.43 | wss | noise | yamux | ✅ | 5s | 14.019 | 0.649 |
| go-v0.40 x go-v0.43 (wss, tls, yamux) | go-v0.40 | go-v0.43 | wss | tls | yamux | ✅ | 5s | 18.211 | 0.602 |
| go-v0.40 x go-v0.43 (quic-v1) | go-v0.40 | go-v0.43 | quic-v1 | - | - | ✅ | 5s | 9.582 | 0.558 |
| go-v0.40 x go-v0.43 (webtransport) | go-v0.40 | go-v0.43 | webtransport | - | - | ✅ | 4s | 6.193 | 0.231 |
| go-v0.40 x go-v0.43 (webrtc-direct) | go-v0.40 | go-v0.43 | webrtc-direct | - | - | ✅ | 5s | 217.736 | 0.607 |
| go-v0.40 x go-v0.44 (tcp, tls, yamux) | go-v0.40 | go-v0.44 | tcp | tls | yamux | ✅ | 5s | 16.33 | 0.865 |
| go-v0.40 x go-v0.44 (tcp, noise, yamux) | go-v0.40 | go-v0.44 | tcp | noise | yamux | ✅ | 5s | 14.88 | 1.188 |
| go-v0.40 x go-v0.44 (ws, tls, yamux) | go-v0.40 | go-v0.44 | ws | tls | yamux | ✅ | 5s | 19.654 | 0.605 |
| go-v0.40 x go-v0.44 (ws, noise, yamux) | go-v0.40 | go-v0.44 | ws | noise | yamux | ✅ | 5s | 13.625 | 0.559 |
| go-v0.40 x go-v0.44 (wss, tls, yamux) | go-v0.40 | go-v0.44 | wss | tls | yamux | ✅ | 5s | 17.301 | 0.507 |
| go-v0.40 x go-v0.44 (wss, noise, yamux) | go-v0.40 | go-v0.44 | wss | noise | yamux | ✅ | 4s | 14.834 | 0.548 |
| go-v0.40 x go-v0.44 (quic-v1) | go-v0.40 | go-v0.44 | quic-v1 | - | - | ✅ | 5s | 10.175 | 0.902 |
| go-v0.40 x go-v0.44 (webtransport) | go-v0.40 | go-v0.44 | webtransport | - | - | ✅ | 5s | 17.451 | 1.253 |
| go-v0.40 x go-v0.44 (webrtc-direct) | go-v0.40 | go-v0.44 | webrtc-direct | - | - | ✅ | 4s | 26.967 | 0.414 |
| go-v0.40 x go-v0.45 (tcp, tls, yamux) | go-v0.40 | go-v0.45 | tcp | tls | yamux | ✅ | 4s | 8.872 | 0.515 |
| go-v0.40 x go-v0.45 (ws, tls, yamux) | go-v0.40 | go-v0.45 | ws | tls | yamux | ✅ | 4s | 13.223 | 0.84 |
| go-v0.40 x go-v0.45 (tcp, noise, yamux) | go-v0.40 | go-v0.45 | tcp | noise | yamux | ✅ | 5s | 16.226 | 2.566 |
| go-v0.40 x go-v0.45 (ws, noise, yamux) | go-v0.40 | go-v0.45 | ws | noise | yamux | ✅ | 5s | 5.156 | 0.239 |
| go-v0.40 x go-v0.45 (wss, tls, yamux) | go-v0.40 | go-v0.45 | wss | tls | yamux | ✅ | 4s | 18.461 | 0.85 |
| go-v0.40 x go-v0.45 (quic-v1) | go-v0.40 | go-v0.45 | quic-v1 | - | - | ✅ | 5s | 16.002 | 2.951 |
| go-v0.40 x go-v0.45 (wss, noise, yamux) | go-v0.40 | go-v0.45 | wss | noise | yamux | ✅ | 5s | 13.048 | 0.498 |
| go-v0.40 x go-v0.45 (webtransport) | go-v0.40 | go-v0.45 | webtransport | - | - | ✅ | 5s | 17.601 | 1.478 |
| go-v0.40 x go-v0.45 (webrtc-direct) | go-v0.40 | go-v0.45 | webrtc-direct | - | - | ✅ | 5s | 216.663 | 0.534 |
| go-v0.40 x python-v0.4 (tcp, noise, yamux) | go-v0.40 | python-v0.4 | tcp | noise | yamux | ✅ | 4s | 22.252 | 3.784 |
| go-v0.40 x python-v0.4 (ws, noise, yamux) | go-v0.40 | python-v0.4 | ws | noise | yamux | ✅ | 5s | 24.453 | 4.543 |
| go-v0.40 x python-v0.4 (wss, noise, yamux) | go-v0.40 | python-v0.4 | wss | noise | yamux | ✅ | 5s | 33.246 | 4.358 |
| go-v0.40 x python-v0.4 (quic-v1) | go-v0.40 | python-v0.4 | quic-v1 | - | - | ✅ | 6s | 52.407 | 16.124 |
| go-v0.40 x nim-v1.14 (tcp, noise, yamux) | go-v0.40 | nim-v1.14 | tcp | noise | yamux | ✅ | 5s | 177.349 | 57.728 |
| go-v0.40 x nim-v1.14 (ws, noise, yamux) | go-v0.40 | nim-v1.14 | ws | noise | yamux | ✅ | 5s | 251.192 | 47.57 |
| go-v0.40 x js-v1.x (tcp, noise, yamux) | go-v0.40 | js-v1.x | tcp | noise | yamux | ✅ | 19s | 196.422 | 28.341 |
| go-v0.40 x js-v1.x (ws, noise, yamux) | go-v0.40 | js-v1.x | ws | noise | yamux | ✅ | 22s | 200.602 | 17.991 |
| go-v0.40 x js-v2.x (tcp, noise, yamux) | go-v0.40 | js-v2.x | tcp | noise | yamux | ✅ | 22s | 141.722 | 27.972 |
| go-v0.40 x jvm-v1.2 (tcp, noise, yamux) | go-v0.40 | jvm-v1.2 | tcp | noise | yamux | ✅ | 11s | 1338.742 | 32.531 |
| go-v0.40 x js-v2.x (ws, noise, yamux) | go-v0.40 | js-v2.x | ws | noise | yamux | ✅ | 22s | 156.944 | 22.875 |
| go-v0.40 x jvm-v1.2 (tcp, tls, yamux) | go-v0.40 | jvm-v1.2 | tcp | tls | yamux | ✅ | 13s | 3363.086 | 21.359 |
| go-v0.40 x js-v3.x (tcp, noise, yamux) | go-v0.40 | js-v3.x | tcp | noise | yamux | ✅ | 23s | 134.001 | 24.512 |
| go-v0.40 x js-v3.x (ws, noise, yamux) | go-v0.40 | js-v3.x | ws | noise | yamux | ✅ | 22s | 96.819 | 22.952 |
| go-v0.40 x c-v0.0.1 (tcp, noise, yamux) | go-v0.40 | c-v0.0.1 | tcp | noise | yamux | ✅ | 6s | 133.965 | 51.424 |
| go-v0.40 x c-v0.0.1 (quic-v1) | go-v0.40 | c-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 60.882 | 38.716 |
| go-v0.40 x dotnet-v1.0 (tcp, noise, yamux) | go-v0.40 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 7s | 564.126 | 48.294 |
| go-v0.40 x zig-v0.0.1 (quic-v1) | go-v0.40 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 6s | - | - |
| go-v0.40 x jvm-v1.2 (ws, noise, yamux) | go-v0.40 | jvm-v1.2 | ws | noise | yamux | ✅ | 11s | 1372.357 | 30.03 |
| go-v0.40 x eth-p2p-z-v0.0.1 (quic-v1) | go-v0.40 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 18.756 | 0.828 |
| go-v0.40 x jvm-v1.2 (ws, tls, yamux) | go-v0.40 | jvm-v1.2 | ws | tls | yamux | ✅ | 13s | 4183.992 | 15.583 |
| go-v0.40 x jvm-v1.2 (quic-v1) | go-v0.40 | jvm-v1.2 | quic-v1 | - | - | ✅ | 11s | 538.789 | 5.935 |
| go-v0.41 x rust-v0.53 (tcp, tls, yamux) | go-v0.41 | rust-v0.53 | tcp | tls | yamux | ✅ | 3s | 94.93 | 44.031 |
| go-v0.41 x rust-v0.53 (tcp, noise, yamux) | go-v0.41 | rust-v0.53 | tcp | noise | yamux | ✅ | 4s | 97.968 | 42.054 |
| go-v0.41 x rust-v0.53 (ws, tls, yamux) | go-v0.41 | rust-v0.53 | ws | tls | yamux | ✅ | 5s | 236.151 | 43.389 |
| go-v0.41 x rust-v0.53 (ws, noise, yamux) | go-v0.41 | rust-v0.53 | ws | noise | yamux | ✅ | 6s | 189.55 | 44.605 |
| go-v0.41 x rust-v0.53 (quic-v1) | go-v0.41 | rust-v0.53 | quic-v1 | - | - | ✅ | 5s | 16.481 | 0.781 |
| go-v0.41 x rust-v0.54 (tcp, tls, yamux) | go-v0.41 | rust-v0.54 | tcp | tls | yamux | ✅ | 5s | 94.262 | 42.099 |
| go-v0.41 x rust-v0.53 (webrtc-direct) | go-v0.41 | rust-v0.53 | webrtc-direct | - | - | ✅ | 6s | 408.555 | 0.292 |
| go-v0.41 x rust-v0.54 (tcp, noise, yamux) | go-v0.41 | rust-v0.54 | tcp | noise | yamux | ✅ | 5s | 93.891 | 42.563 |
| go-v0.41 x rust-v0.54 (ws, tls, yamux) | go-v0.41 | rust-v0.54 | ws | tls | yamux | ✅ | 5s | 182.76 | 44.481 |
| go-v0.41 x rust-v0.54 (ws, noise, yamux) | go-v0.41 | rust-v0.54 | ws | noise | yamux | ✅ | 5s | 174.774 | 42.157 |
| go-v0.41 x rust-v0.54 (quic-v1) | go-v0.41 | rust-v0.54 | quic-v1 | - | - | ✅ | 5s | 14.581 | 2.264 |
| go-v0.41 x rust-v0.55 (tcp, tls, yamux) | go-v0.41 | rust-v0.55 | tcp | tls | yamux | ✅ | 5s | 11.857 | 1.085 |
| go-v0.41 x rust-v0.54 (webrtc-direct) | go-v0.41 | rust-v0.54 | webrtc-direct | - | - | ✅ | 6s | 418.332 | 1.484 |
| go-v0.41 x rust-v0.55 (tcp, noise, yamux) | go-v0.41 | rust-v0.55 | tcp | noise | yamux | ✅ | 5s | 8.003 | 1.968 |
| go-v0.41 x rust-v0.55 (ws, tls, yamux) | go-v0.41 | rust-v0.55 | ws | tls | yamux | ✅ | 5s | 9.399 | 0.365 |
| go-v0.41 x rust-v0.55 (ws, noise, yamux) | go-v0.41 | rust-v0.55 | ws | noise | yamux | ✅ | 5s | 4.446 | 0.174 |
| go-v0.41 x rust-v0.55 (quic-v1) | go-v0.41 | rust-v0.55 | quic-v1 | - | - | ✅ | 4s | 9.81 | 0.589 |
| go-v0.41 x rust-v0.55 (webrtc-direct) | go-v0.41 | rust-v0.55 | webrtc-direct | - | - | ✅ | 5s | 417.29 | 1.059 |
| go-v0.41 x rust-v0.56 (tcp, tls, yamux) | go-v0.41 | rust-v0.56 | tcp | tls | yamux | ✅ | 4s | 5.273 | 0.412 |
| go-v0.41 x rust-v0.56 (tcp, noise, yamux) | go-v0.41 | rust-v0.56 | tcp | noise | yamux | ✅ | 4s | 4.928 | 0.21 |
| go-v0.41 x rust-v0.56 (ws, tls, yamux) | go-v0.41 | rust-v0.56 | ws | tls | yamux | ✅ | 5s | 7.945 | 0.825 |
| go-v0.41 x rust-v0.56 (quic-v1) | go-v0.41 | rust-v0.56 | quic-v1 | - | - | ✅ | 4s | 8.995 | 1.067 |
| go-v0.41 x rust-v0.56 (ws, noise, yamux) | go-v0.41 | rust-v0.56 | ws | noise | yamux | ✅ | 5s | 4.395 | 0.591 |
| go-v0.41 x go-v0.38 (tcp, tls, yamux) | go-v0.41 | go-v0.38 | tcp | tls | yamux | ✅ | 4s | 7.367 | 0.312 |
| go-v0.41 x go-v0.38 (tcp, noise, yamux) | go-v0.41 | go-v0.38 | tcp | noise | yamux | ✅ | 4s | 13.58 | 1.303 |
| go-v0.41 x go-v0.38 (ws, noise, yamux) | go-v0.41 | go-v0.38 | ws | noise | yamux | ✅ | 3s | 9.777 | 0.89 |
| go-v0.41 x go-v0.38 (ws, tls, yamux) | go-v0.41 | go-v0.38 | ws | tls | yamux | ✅ | 4s | 10.293 | 0.253 |
| go-v0.41 x go-v0.38 (wss, tls, yamux) | go-v0.41 | go-v0.38 | wss | tls | yamux | ✅ | 5s | 10.189 | 0.637 |
| go-v0.41 x go-v0.38 (quic-v1) | go-v0.41 | go-v0.38 | quic-v1 | - | - | ✅ | 4s | 10.749 | 1.538 |
| go-v0.41 x go-v0.38 (wss, noise, yamux) | go-v0.41 | go-v0.38 | wss | noise | yamux | ✅ | 5s | 15.298 | 0.621 |
| go-v0.41 x rust-v0.56 (webrtc-direct) | go-v0.41 | rust-v0.56 | webrtc-direct | - | - | ❌ | 10s | - | - |
| go-v0.41 x go-v0.38 (webtransport) | go-v0.41 | go-v0.38 | webtransport | - | - | ✅ | 5s | 11.48 | 0.481 |
| go-v0.41 x go-v0.39 (tcp, tls, yamux) | go-v0.41 | go-v0.39 | tcp | tls | yamux | ✅ | 4s | 10.341 | 0.301 |
| go-v0.41 x go-v0.38 (webrtc-direct) | go-v0.41 | go-v0.38 | webrtc-direct | - | - | ✅ | 5s | 216.6 | 1.04 |
| go-v0.41 x go-v0.39 (tcp, noise, yamux) | go-v0.41 | go-v0.39 | tcp | noise | yamux | ✅ | 5s | 7.995 | 1.348 |
| go-v0.41 x go-v0.39 (ws, tls, yamux) | go-v0.41 | go-v0.39 | ws | tls | yamux | ✅ | 5s | 9.395 | 0.467 |
| go-v0.41 x go-v0.39 (ws, noise, yamux) | go-v0.41 | go-v0.39 | ws | noise | yamux | ✅ | 4s | 8.214 | 1.908 |
| go-v0.41 x go-v0.39 (wss, tls, yamux) | go-v0.41 | go-v0.39 | wss | tls | yamux | ✅ | 6s | 21.902 | 1.977 |
| go-v0.41 x go-v0.39 (wss, noise, yamux) | go-v0.41 | go-v0.39 | wss | noise | yamux | ✅ | 5s | 17.291 | 0.872 |
| go-v0.41 x go-v0.39 (quic-v1) | go-v0.41 | go-v0.39 | quic-v1 | - | - | ✅ | 6s | 10.563 | 0.406 |
| go-v0.41 x go-v0.39 (webtransport) | go-v0.41 | go-v0.39 | webtransport | - | - | ✅ | 4s | 6.076 | 0.247 |
| go-v0.41 x go-v0.39 (webrtc-direct) | go-v0.41 | go-v0.39 | webrtc-direct | - | - | ✅ | 5s | 214.488 | 0.875 |
| go-v0.41 x go-v0.40 (tcp, noise, yamux) | go-v0.41 | go-v0.40 | tcp | noise | yamux | ✅ | 4s | 15.739 | 1.954 |
| go-v0.41 x go-v0.40 (tcp, tls, yamux) | go-v0.41 | go-v0.40 | tcp | tls | yamux | ✅ | 5s | 7.458 | 0.962 |
| go-v0.41 x go-v0.40 (ws, tls, yamux) | go-v0.41 | go-v0.40 | ws | tls | yamux | ✅ | 5s | 9.984 | 2.72 |
| go-v0.41 x go-v0.40 (ws, noise, yamux) | go-v0.41 | go-v0.40 | ws | noise | yamux | ✅ | 6s | 10.638 | 0.577 |
| go-v0.41 x go-v0.40 (wss, noise, yamux) | go-v0.41 | go-v0.40 | wss | noise | yamux | ✅ | 5s | 17.572 | 0.893 |
| go-v0.41 x go-v0.40 (quic-v1) | go-v0.41 | go-v0.40 | quic-v1 | - | - | ✅ | 4s | 14.721 | 0.823 |
| go-v0.41 x go-v0.40 (wss, tls, yamux) | go-v0.41 | go-v0.40 | wss | tls | yamux | ✅ | 6s | 16.157 | 0.513 |
| go-v0.41 x go-v0.40 (webtransport) | go-v0.41 | go-v0.40 | webtransport | - | - | ✅ | 5s | 12.712 | 0.341 |
| go-v0.41 x go-v0.40 (webrtc-direct) | go-v0.41 | go-v0.40 | webrtc-direct | - | - | ✅ | 5s | 210.969 | 0.783 |
| go-v0.41 x go-v0.41 (tcp, tls, yamux) | go-v0.41 | go-v0.41 | tcp | tls | yamux | ✅ | 4s | 11.068 | 0.367 |
| go-v0.41 x go-v0.41 (tcp, noise, yamux) | go-v0.41 | go-v0.41 | tcp | noise | yamux | ✅ | 4s | 7.994 | 1.698 |
| go-v0.41 x go-v0.41 (ws, noise, yamux) | go-v0.41 | go-v0.41 | ws | noise | yamux | ✅ | 4s | 10.685 | 1.997 |
| go-v0.41 x go-v0.41 (ws, tls, yamux) | go-v0.41 | go-v0.41 | ws | tls | yamux | ✅ | 5s | 19.365 | 0.703 |
| go-v0.41 x go-v0.41 (wss, tls, yamux) | go-v0.41 | go-v0.41 | wss | tls | yamux | ✅ | 5s | 18.949 | 4.069 |
| go-v0.41 x go-v0.41 (wss, noise, yamux) | go-v0.41 | go-v0.41 | wss | noise | yamux | ✅ | 5s | 13.681 | 1.063 |
| go-v0.41 x go-v0.41 (quic-v1) | go-v0.41 | go-v0.41 | quic-v1 | - | - | ✅ | 5s | 18.021 | 0.725 |
| go-v0.41 x go-v0.41 (webtransport) | go-v0.41 | go-v0.41 | webtransport | - | - | ✅ | 5s | 25.216 | 0.702 |
| go-v0.41 x go-v0.41 (webrtc-direct) | go-v0.41 | go-v0.41 | webrtc-direct | - | - | ✅ | 5s | 209.39 | 0.408 |
| go-v0.41 x go-v0.42 (tcp, tls, yamux) | go-v0.41 | go-v0.42 | tcp | tls | yamux | ✅ | 5s | 11.189 | 2.78 |
| go-v0.41 x go-v0.42 (tcp, noise, yamux) | go-v0.41 | go-v0.42 | tcp | noise | yamux | ✅ | 5s | 14.435 | 0.845 |
| go-v0.41 x go-v0.42 (ws, tls, yamux) | go-v0.41 | go-v0.42 | ws | tls | yamux | ✅ | 5s | 8.368 | 0.901 |
| go-v0.41 x go-v0.42 (ws, noise, yamux) | go-v0.41 | go-v0.42 | ws | noise | yamux | ✅ | 5s | 4.921 | 0.227 |
| go-v0.41 x go-v0.42 (wss, tls, yamux) | go-v0.41 | go-v0.42 | wss | tls | yamux | ✅ | 6s | 24.755 | 0.673 |
| go-v0.41 x go-v0.42 (quic-v1) | go-v0.41 | go-v0.42 | quic-v1 | - | - | ✅ | 5s | 26.316 | 3.359 |
| go-v0.41 x go-v0.42 (wss, noise, yamux) | go-v0.41 | go-v0.42 | wss | noise | yamux | ✅ | 7s | 13.088 | 0.285 |
| go-v0.41 x go-v0.42 (webtransport) | go-v0.41 | go-v0.42 | webtransport | - | - | ✅ | 6s | 11.194 | 0.44 |
| go-v0.41 x go-v0.42 (webrtc-direct) | go-v0.41 | go-v0.42 | webrtc-direct | - | - | ✅ | 4s | 27.415 | 0.923 |
| go-v0.41 x go-v0.43 (tcp, tls, yamux) | go-v0.41 | go-v0.43 | tcp | tls | yamux | ✅ | 4s | 12.943 | 1.782 |
| go-v0.41 x go-v0.43 (tcp, noise, yamux) | go-v0.41 | go-v0.43 | tcp | noise | yamux | ✅ | 5s | 11.45 | 0.781 |
| go-v0.41 x go-v0.43 (ws, tls, yamux) | go-v0.41 | go-v0.43 | ws | tls | yamux | ✅ | 4s | 8.34 | 0.413 |
| go-v0.41 x go-v0.43 (ws, noise, yamux) | go-v0.41 | go-v0.43 | ws | noise | yamux | ✅ | 4s | 17.764 | 1.31 |
| go-v0.41 x go-v0.43 (wss, tls, yamux) | go-v0.41 | go-v0.43 | wss | tls | yamux | ✅ | 4s | 26.053 | 1.169 |
| go-v0.41 x go-v0.43 (quic-v1) | go-v0.41 | go-v0.43 | quic-v1 | - | - | ✅ | 5s | 14.548 | 0.969 |
| go-v0.41 x go-v0.43 (wss, noise, yamux) | go-v0.41 | go-v0.43 | wss | noise | yamux | ✅ | 5s | 16.052 | 3.008 |
| go-v0.41 x go-v0.43 (webtransport) | go-v0.41 | go-v0.43 | webtransport | - | - | ✅ | 5s | 11.28 | 0.403 |
| go-v0.41 x go-v0.43 (webrtc-direct) | go-v0.41 | go-v0.43 | webrtc-direct | - | - | ✅ | 5s | 221.341 | 0.905 |
| go-v0.41 x go-v0.44 (tcp, noise, yamux) | go-v0.41 | go-v0.44 | tcp | noise | yamux | ✅ | 5s | 6.322 | 0.488 |
| go-v0.41 x go-v0.44 (tcp, tls, yamux) | go-v0.41 | go-v0.44 | tcp | tls | yamux | ✅ | 6s | 8.994 | 0.541 |
| go-v0.41 x go-v0.44 (ws, tls, yamux) | go-v0.41 | go-v0.44 | ws | tls | yamux | ✅ | 5s | 9.418 | 1.621 |
| go-v0.41 x go-v0.44 (ws, noise, yamux) | go-v0.41 | go-v0.44 | ws | noise | yamux | ✅ | 4s | 15.638 | 1.639 |
| go-v0.41 x go-v0.44 (wss, tls, yamux) | go-v0.41 | go-v0.44 | wss | tls | yamux | ✅ | 6s | 22.715 | 0.67 |
| go-v0.41 x go-v0.44 (quic-v1) | go-v0.41 | go-v0.44 | quic-v1 | - | - | ✅ | 5s | 14.505 | 0.364 |
| go-v0.41 x go-v0.44 (wss, noise, yamux) | go-v0.41 | go-v0.44 | wss | noise | yamux | ✅ | 5s | 19.064 | 0.522 |
| go-v0.41 x go-v0.44 (webtransport) | go-v0.41 | go-v0.44 | webtransport | - | - | ✅ | 4s | 73.359 | 1.042 |
| go-v0.41 x go-v0.45 (tcp, tls, yamux) | go-v0.41 | go-v0.45 | tcp | tls | yamux | ✅ | 4s | 9.379 | 0.666 |
| go-v0.41 x go-v0.44 (webrtc-direct) | go-v0.41 | go-v0.44 | webrtc-direct | - | - | ✅ | 6s | 222.667 | 0.858 |
| go-v0.41 x go-v0.45 (ws, tls, yamux) | go-v0.41 | go-v0.45 | ws | tls | yamux | ✅ | 4s | 9.135 | 1.072 |
| go-v0.41 x go-v0.45 (tcp, noise, yamux) | go-v0.41 | go-v0.45 | tcp | noise | yamux | ✅ | 5s | 9.197 | 1.245 |
| go-v0.41 x go-v0.45 (ws, noise, yamux) | go-v0.41 | go-v0.45 | ws | noise | yamux | ✅ | 4s | 9.911 | 0.316 |
| go-v0.41 x go-v0.45 (wss, tls, yamux) | go-v0.41 | go-v0.45 | wss | tls | yamux | ✅ | 4s | 13.604 | 0.361 |
| go-v0.41 x go-v0.45 (wss, noise, yamux) | go-v0.41 | go-v0.45 | wss | noise | yamux | ✅ | 5s | 17.214 | 0.559 |
| go-v0.41 x go-v0.45 (quic-v1) | go-v0.41 | go-v0.45 | quic-v1 | - | - | ✅ | 5s | 10.087 | 1.388 |
| go-v0.41 x go-v0.45 (webtransport) | go-v0.41 | go-v0.45 | webtransport | - | - | ✅ | 5s | 40.266 | 0.928 |
| go-v0.41 x go-v0.45 (webrtc-direct) | go-v0.41 | go-v0.45 | webrtc-direct | - | - | ✅ | 5s | 219.553 | 1.449 |
| go-v0.41 x python-v0.4 (tcp, noise, yamux) | go-v0.41 | python-v0.4 | tcp | noise | yamux | ✅ | 5s | 30.608 | 4.2 |
| go-v0.41 x python-v0.4 (ws, noise, yamux) | go-v0.41 | python-v0.4 | ws | noise | yamux | ✅ | 5s | 39.19 | 9.17 |
| go-v0.41 x python-v0.4 (wss, noise, yamux) | go-v0.41 | python-v0.4 | wss | noise | yamux | ✅ | 5s | 26.208 | 2.922 |
| go-v0.41 x python-v0.4 (quic-v1) | go-v0.41 | python-v0.4 | quic-v1 | - | - | ✅ | 5s | 115.136 | 12.131 |
| go-v0.41 x nim-v1.14 (tcp, noise, yamux) | go-v0.41 | nim-v1.14 | tcp | noise | yamux | ✅ | 5s | 200.089 | 46.461 |
| go-v0.41 x nim-v1.14 (ws, noise, yamux) | go-v0.41 | nim-v1.14 | ws | noise | yamux | ✅ | 5s | 246.929 | 42.654 |
| go-v0.41 x js-v1.x (tcp, noise, yamux) | go-v0.41 | js-v1.x | tcp | noise | yamux | ✅ | 19s | 156.246 | 22.436 |
| go-v0.41 x js-v1.x (ws, noise, yamux) | go-v0.41 | js-v1.x | ws | noise | yamux | ✅ | 20s | 163.343 | 17.359 |
| go-v0.41 x js-v2.x (tcp, noise, yamux) | go-v0.41 | js-v2.x | tcp | noise | yamux | ✅ | 22s | 168.531 | 20.204 |
| go-v0.41 x jvm-v1.2 (tcp, noise, yamux) | go-v0.41 | jvm-v1.2 | tcp | noise | yamux | ✅ | 10s | 1329.043 | 12.319 |
| go-v0.41 x js-v2.x (ws, noise, yamux) | go-v0.41 | js-v2.x | ws | noise | yamux | ✅ | 22s | 178.194 | 41.586 |
| go-v0.41 x js-v3.x (tcp, noise, yamux) | go-v0.41 | js-v3.x | tcp | noise | yamux | ✅ | 21s | 206.695 | 29.073 |
| go-v0.41 x jvm-v1.2 (tcp, tls, yamux) | go-v0.41 | jvm-v1.2 | tcp | tls | yamux | ✅ | 14s | 3410.976 | 9.911 |
| go-v0.41 x js-v3.x (ws, noise, yamux) | go-v0.41 | js-v3.x | ws | noise | yamux | ✅ | 21s | 56.333 | 9.816 |
| go-v0.41 x c-v0.0.1 (tcp, noise, yamux) | go-v0.41 | c-v0.0.1 | tcp | noise | yamux | ✅ | 5s | 129.02 | 64.309 |
| go-v0.41 x c-v0.0.1 (quic-v1) | go-v0.41 | c-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 74.682 | 42.213 |
| go-v0.41 x jvm-v1.2 (ws, noise, yamux) | go-v0.41 | jvm-v1.2 | ws | noise | yamux | ✅ | 10s | 1566.636 | 42.289 |
| go-v0.41 x dotnet-v1.0 (tcp, noise, yamux) | go-v0.41 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 6s | 447.684 | 52.83 |
| go-v0.41 x jvm-v1.2 (ws, tls, yamux) | go-v0.41 | jvm-v1.2 | ws | tls | yamux | ✅ | 12s | 3969.25 | 16.686 |
| go-v0.41 x zig-v0.0.1 (quic-v1) | go-v0.41 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 6s | - | - |
| go-v0.41 x eth-p2p-z-v0.0.1 (quic-v1) | go-v0.41 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 15.76 | 2.314 |
| go-v0.41 x jvm-v1.2 (quic-v1) | go-v0.41 | jvm-v1.2 | quic-v1 | - | - | ✅ | 11s | 475.766 | 13.279 |
| go-v0.42 x rust-v0.53 (tcp, tls, yamux) | go-v0.42 | rust-v0.53 | tcp | tls | yamux | ✅ | 4s | 95.675 | 46.409 |
| go-v0.42 x rust-v0.53 (tcp, noise, yamux) | go-v0.42 | rust-v0.53 | tcp | noise | yamux | ✅ | 4s | 93.925 | 41.573 |
| go-v0.42 x rust-v0.53 (ws, tls, yamux) | go-v0.42 | rust-v0.53 | ws | tls | yamux | ✅ | 5s | 193.119 | 46.245 |
| go-v0.42 x rust-v0.53 (ws, noise, yamux) | go-v0.42 | rust-v0.53 | ws | noise | yamux | ✅ | 5s | 178.113 | 42.031 |
| go-v0.42 x rust-v0.53 (quic-v1) | go-v0.42 | rust-v0.53 | quic-v1 | - | - | ✅ | 5s | 15.353 | 1.203 |
| go-v0.42 x rust-v0.53 (webrtc-direct) | go-v0.42 | rust-v0.53 | webrtc-direct | - | - | ✅ | 5s | 217.808 | 0.871 |
| go-v0.42 x rust-v0.54 (tcp, noise, yamux) | go-v0.42 | rust-v0.54 | tcp | noise | yamux | ✅ | 4s | 94.464 | 46.733 |
| go-v0.42 x rust-v0.54 (tcp, tls, yamux) | go-v0.42 | rust-v0.54 | tcp | tls | yamux | ✅ | 6s | 93.93 | 43.054 |
| go-v0.42 x rust-v0.54 (ws, tls, yamux) | go-v0.42 | rust-v0.54 | ws | tls | yamux | ✅ | 5s | 185.617 | 46.023 |
| go-v0.42 x rust-v0.54 (ws, noise, yamux) | go-v0.42 | rust-v0.54 | ws | noise | yamux | ✅ | 5s | 186.017 | 46.966 |
| go-v0.42 x rust-v0.54 (quic-v1) | go-v0.42 | rust-v0.54 | quic-v1 | - | - | ✅ | 4s | 7.162 | 0.264 |
| go-v0.42 x rust-v0.54 (webrtc-direct) | go-v0.42 | rust-v0.54 | webrtc-direct | - | - | ✅ | 4s | 411.348 | 0.274 |
| go-v0.42 x rust-v0.55 (tcp, tls, yamux) | go-v0.42 | rust-v0.55 | tcp | tls | yamux | ✅ | 4s | 9.274 | 0.462 |
| go-v0.42 x rust-v0.55 (tcp, noise, yamux) | go-v0.42 | rust-v0.55 | tcp | noise | yamux | ✅ | 5s | 12.361 | 1.589 |
| go-v0.42 x rust-v0.55 (ws, tls, yamux) | go-v0.42 | rust-v0.55 | ws | tls | yamux | ✅ | 5s | 15.844 | 1.323 |
| go-v0.42 x rust-v0.55 (ws, noise, yamux) | go-v0.42 | rust-v0.55 | ws | noise | yamux | ✅ | 5s | 10.648 | 0.861 |
| go-v0.42 x rust-v0.55 (quic-v1) | go-v0.42 | rust-v0.55 | quic-v1 | - | - | ✅ | 4s | 14.19 | 0.438 |
| go-v0.42 x rust-v0.56 (tcp, tls, yamux) | go-v0.42 | rust-v0.56 | tcp | tls | yamux | ✅ | 5s | 6.119 | 0.684 |
| go-v0.42 x rust-v0.55 (webrtc-direct) | go-v0.42 | rust-v0.55 | webrtc-direct | - | - | ✅ | 5s | 425.09 | 1.983 |
| go-v0.42 x rust-v0.56 (tcp, noise, yamux) | go-v0.42 | rust-v0.56 | tcp | noise | yamux | ✅ | 5s | 4.05 | 0.155 |
| go-v0.42 x rust-v0.56 (ws, tls, yamux) | go-v0.42 | rust-v0.56 | ws | tls | yamux | ✅ | 4s | 5.939 | 0.317 |
| go-v0.42 x rust-v0.56 (ws, noise, yamux) | go-v0.42 | rust-v0.56 | ws | noise | yamux | ✅ | 4s | 12.902 | 1.548 |
| go-v0.42 x rust-v0.56 (quic-v1) | go-v0.42 | rust-v0.56 | quic-v1 | - | - | ✅ | 5s | 12.591 | 2.683 |
| go-v0.42 x go-v0.38 (tcp, tls, yamux) | go-v0.42 | go-v0.38 | tcp | tls | yamux | ✅ | 4s | 7.042 | 0.44 |
| go-v0.42 x go-v0.38 (tcp, noise, yamux) | go-v0.42 | go-v0.38 | tcp | noise | yamux | ✅ | 5s | 16.17 | 5.65 |
| go-v0.42 x go-v0.38 (ws, tls, yamux) | go-v0.42 | go-v0.38 | ws | tls | yamux | ✅ | 4s | 12.867 | 0.572 |
| go-v0.42 x go-v0.38 (ws, noise, yamux) | go-v0.42 | go-v0.38 | ws | noise | yamux | ✅ | 5s | 9.255 | 0.304 |
| go-v0.42 x go-v0.38 (wss, noise, yamux) | go-v0.42 | go-v0.38 | wss | noise | yamux | ✅ | 4s | 12.112 | 0.446 |
| go-v0.42 x go-v0.38 (wss, tls, yamux) | go-v0.42 | go-v0.38 | wss | tls | yamux | ✅ | 5s | 13.054 | 0.413 |
| go-v0.42 x go-v0.38 (quic-v1) | go-v0.42 | go-v0.38 | quic-v1 | - | - | ✅ | 5s | 5.422 | 0.276 |
| go-v0.42 x rust-v0.56 (webrtc-direct) | go-v0.42 | rust-v0.56 | webrtc-direct | - | - | ❌ | 9s | - | - |
| go-v0.42 x go-v0.38 (webtransport) | go-v0.42 | go-v0.38 | webtransport | - | - | ✅ | 5s | 12.167 | 0.524 |
| go-v0.42 x go-v0.39 (tcp, tls, yamux) | go-v0.42 | go-v0.39 | tcp | tls | yamux | ✅ | 4s | 12.402 | 2.11 |
| go-v0.42 x go-v0.38 (webrtc-direct) | go-v0.42 | go-v0.38 | webrtc-direct | - | - | ✅ | 6s | 221.341 | 0.903 |
| go-v0.42 x go-v0.39 (tcp, noise, yamux) | go-v0.42 | go-v0.39 | tcp | noise | yamux | ✅ | 5s | 8.107 | 0.324 |
| go-v0.42 x go-v0.39 (ws, noise, yamux) | go-v0.42 | go-v0.39 | ws | noise | yamux | ✅ | 5s | 8.202 | 0.868 |
| go-v0.42 x go-v0.39 (ws, tls, yamux) | go-v0.42 | go-v0.39 | ws | tls | yamux | ✅ | 5s | 22.341 | 1.164 |
| go-v0.42 x go-v0.39 (wss, tls, yamux) | go-v0.42 | go-v0.39 | wss | tls | yamux | ✅ | 5s | 21.213 | 1.838 |
| go-v0.42 x go-v0.39 (quic-v1) | go-v0.42 | go-v0.39 | quic-v1 | - | - | ✅ | 5s | 83.952 | 1.588 |
| go-v0.42 x go-v0.39 (wss, noise, yamux) | go-v0.42 | go-v0.39 | wss | noise | yamux | ✅ | 6s | 7.948 | 0.171 |
| go-v0.42 x go-v0.39 (webtransport) | go-v0.42 | go-v0.39 | webtransport | - | - | ✅ | 5s | 16.057 | 0.789 |
| go-v0.42 x go-v0.40 (tcp, noise, yamux) | go-v0.42 | go-v0.40 | tcp | noise | yamux | ✅ | 4s | 7.601 | 0.664 |
| go-v0.42 x go-v0.40 (tcp, tls, yamux) | go-v0.42 | go-v0.40 | tcp | tls | yamux | ✅ | 5s | 11.711 | 1.318 |
| go-v0.42 x go-v0.39 (webrtc-direct) | go-v0.42 | go-v0.39 | webrtc-direct | - | - | ✅ | 6s | 217.406 | 0.683 |
| go-v0.42 x go-v0.40 (ws, tls, yamux) | go-v0.42 | go-v0.40 | ws | tls | yamux | ✅ | 5s | 7.416 | 0.296 |
| go-v0.42 x go-v0.40 (ws, noise, yamux) | go-v0.42 | go-v0.40 | ws | noise | yamux | ✅ | 5s | 5.997 | 0.236 |
| go-v0.42 x go-v0.40 (wss, tls, yamux) | go-v0.42 | go-v0.40 | wss | tls | yamux | ✅ | 5s | 17.289 | 1.379 |
| go-v0.42 x go-v0.40 (quic-v1) | go-v0.42 | go-v0.40 | quic-v1 | - | - | ✅ | 4s | 14.786 | 0.538 |
| go-v0.42 x go-v0.40 (wss, noise, yamux) | go-v0.42 | go-v0.40 | wss | noise | yamux | ✅ | 5s | 10.437 | 0.284 |
| go-v0.42 x go-v0.40 (webtransport) | go-v0.42 | go-v0.40 | webtransport | - | - | ✅ | 4s | 23.943 | 6.334 |
| go-v0.42 x go-v0.41 (tcp, tls, yamux) | go-v0.42 | go-v0.41 | tcp | tls | yamux | ✅ | 4s | 9.801 | 0.963 |
| go-v0.42 x go-v0.40 (webrtc-direct) | go-v0.42 | go-v0.40 | webrtc-direct | - | - | ✅ | 5s | 222.469 | 3.314 |
| go-v0.42 x go-v0.41 (ws, tls, yamux) | go-v0.42 | go-v0.41 | ws | tls | yamux | ✅ | 5s | 10.104 | 0.328 |
| go-v0.42 x go-v0.41 (tcp, noise, yamux) | go-v0.42 | go-v0.41 | tcp | noise | yamux | ✅ | 5s | 6.854 | 0.566 |
| go-v0.42 x go-v0.41 (ws, noise, yamux) | go-v0.42 | go-v0.41 | ws | noise | yamux | ✅ | 5s | 12.66 | 0.516 |
| go-v0.42 x go-v0.41 (wss, tls, yamux) | go-v0.42 | go-v0.41 | wss | tls | yamux | ✅ | 5s | 15.378 | 0.692 |
| go-v0.42 x go-v0.41 (wss, noise, yamux) | go-v0.42 | go-v0.41 | wss | noise | yamux | ✅ | 5s | 12.076 | 1.073 |
| go-v0.42 x go-v0.41 (quic-v1) | go-v0.42 | go-v0.41 | quic-v1 | - | - | ✅ | 5s | 42.871 | 1.213 |
| go-v0.42 x go-v0.41 (webtransport) | go-v0.42 | go-v0.41 | webtransport | - | - | ✅ | 5s | 17.261 | 0.459 |
| go-v0.42 x go-v0.41 (webrtc-direct) | go-v0.42 | go-v0.41 | webrtc-direct | - | - | ✅ | 5s | 218.472 | 0.721 |
| go-v0.42 x go-v0.42 (tcp, tls, yamux) | go-v0.42 | go-v0.42 | tcp | tls | yamux | ✅ | 4s | 11.129 | 0.766 |
| go-v0.42 x go-v0.42 (tcp, noise, yamux) | go-v0.42 | go-v0.42 | tcp | noise | yamux | ✅ | 5s | 3.704 | 0.21 |
| go-v0.42 x go-v0.42 (ws, tls, yamux) | go-v0.42 | go-v0.42 | ws | tls | yamux | ✅ | 4s | 37.351 | 4.228 |
| go-v0.42 x go-v0.42 (ws, noise, yamux) | go-v0.42 | go-v0.42 | ws | noise | yamux | ✅ | 5s | 8.574 | 0.628 |
| go-v0.42 x go-v0.42 (wss, tls, yamux) | go-v0.42 | go-v0.42 | wss | tls | yamux | ✅ | 5s | 22.117 | 4.88 |
| go-v0.42 x go-v0.42 (wss, noise, yamux) | go-v0.42 | go-v0.42 | wss | noise | yamux | ✅ | 5s | 16.57 | 0.649 |
| go-v0.42 x go-v0.42 (quic-v1) | go-v0.42 | go-v0.42 | quic-v1 | - | - | ✅ | 4s | 7.5 | 0.305 |
| go-v0.42 x go-v0.42 (webtransport) | go-v0.42 | go-v0.42 | webtransport | - | - | ✅ | 4s | 15.695 | 0.352 |
| go-v0.42 x go-v0.42 (webrtc-direct) | go-v0.42 | go-v0.42 | webrtc-direct | - | - | ✅ | 5s | 24.006 | 1.301 |
| go-v0.42 x go-v0.43 (tcp, tls, yamux) | go-v0.42 | go-v0.43 | tcp | tls | yamux | ✅ | 5s | 4.607 | 0.172 |
| go-v0.42 x go-v0.43 (tcp, noise, yamux) | go-v0.42 | go-v0.43 | tcp | noise | yamux | ✅ | 5s | 10.733 | 0.323 |
| go-v0.42 x go-v0.43 (ws, tls, yamux) | go-v0.42 | go-v0.43 | ws | tls | yamux | ✅ | 5s | 15.043 | 0.947 |
| go-v0.42 x go-v0.43 (ws, noise, yamux) | go-v0.42 | go-v0.43 | ws | noise | yamux | ✅ | 5s | 9.347 | 1.964 |
| go-v0.42 x go-v0.43 (wss, tls, yamux) | go-v0.42 | go-v0.43 | wss | tls | yamux | ✅ | 5s | 23.175 | 1.175 |
| go-v0.42 x go-v0.43 (wss, noise, yamux) | go-v0.42 | go-v0.43 | wss | noise | yamux | ✅ | 5s | 16.356 | 0.401 |
| go-v0.42 x go-v0.43 (quic-v1) | go-v0.42 | go-v0.43 | quic-v1 | - | - | ✅ | 5s | 11.907 | 0.49 |
| go-v0.42 x go-v0.43 (webtransport) | go-v0.42 | go-v0.43 | webtransport | - | - | ✅ | 5s | 52.177 | 2.166 |
| go-v0.42 x go-v0.43 (webrtc-direct) | go-v0.42 | go-v0.43 | webrtc-direct | - | - | ✅ | 5s | 16.633 | 0.918 |
| go-v0.42 x go-v0.44 (tcp, tls, yamux) | go-v0.42 | go-v0.44 | tcp | tls | yamux | ✅ | 5s | 10.165 | 2.791 |
| go-v0.42 x go-v0.44 (tcp, noise, yamux) | go-v0.42 | go-v0.44 | tcp | noise | yamux | ✅ | 4s | 8.834 | 0.744 |
| go-v0.42 x go-v0.44 (ws, tls, yamux) | go-v0.42 | go-v0.44 | ws | tls | yamux | ✅ | 5s | 9.763 | 1.052 |
| go-v0.42 x go-v0.44 (ws, noise, yamux) | go-v0.42 | go-v0.44 | ws | noise | yamux | ✅ | 4s | 7.243 | 0.739 |
| go-v0.42 x go-v0.44 (wss, noise, yamux) | go-v0.42 | go-v0.44 | wss | noise | yamux | ✅ | 5s | 18.599 | 1.47 |
| go-v0.42 x go-v0.44 (wss, tls, yamux) | go-v0.42 | go-v0.44 | wss | tls | yamux | ✅ | 6s | 15.882 | 0.851 |
| go-v0.42 x go-v0.44 (quic-v1) | go-v0.42 | go-v0.44 | quic-v1 | - | - | ✅ | 5s | 13.695 | 1.943 |
| go-v0.42 x go-v0.44 (webtransport) | go-v0.42 | go-v0.44 | webtransport | - | - | ✅ | 4s | 8.486 | 0.267 |
| go-v0.42 x go-v0.44 (webrtc-direct) | go-v0.42 | go-v0.44 | webrtc-direct | - | - | ✅ | 5s | 212.026 | 1.074 |
| go-v0.42 x go-v0.45 (tcp, tls, yamux) | go-v0.42 | go-v0.45 | tcp | tls | yamux | ✅ | 5s | 8.232 | 0.635 |
| go-v0.42 x go-v0.45 (tcp, noise, yamux) | go-v0.42 | go-v0.45 | tcp | noise | yamux | ✅ | 4s | 12.986 | 2.042 |
| go-v0.42 x go-v0.45 (ws, tls, yamux) | go-v0.42 | go-v0.45 | ws | tls | yamux | ✅ | 5s | 11.278 | 2.278 |
| go-v0.42 x go-v0.45 (ws, noise, yamux) | go-v0.42 | go-v0.45 | ws | noise | yamux | ✅ | 4s | 13.828 | 0.677 |
| go-v0.42 x go-v0.45 (quic-v1) | go-v0.42 | go-v0.45 | quic-v1 | - | - | ✅ | 4s | 12.812 | 1.161 |
| go-v0.42 x go-v0.45 (wss, tls, yamux) | go-v0.42 | go-v0.45 | wss | tls | yamux | ✅ | 6s | 26.472 | 1.89 |
| go-v0.42 x go-v0.45 (wss, noise, yamux) | go-v0.42 | go-v0.45 | wss | noise | yamux | ✅ | 6s | 15.587 | 1.279 |
| go-v0.42 x go-v0.45 (webtransport) | go-v0.42 | go-v0.45 | webtransport | - | - | ✅ | 5s | 16.777 | 0.855 |
| go-v0.42 x go-v0.45 (webrtc-direct) | go-v0.42 | go-v0.45 | webrtc-direct | - | - | ✅ | 5s | 211.963 | 0.425 |
| go-v0.42 x python-v0.4 (ws, noise, yamux) | go-v0.42 | python-v0.4 | ws | noise | yamux | ✅ | 4s | 23.239 | 3.388 |
| go-v0.42 x python-v0.4 (tcp, noise, yamux) | go-v0.42 | python-v0.4 | tcp | noise | yamux | ✅ | 6s | 18.379 | 2.536 |
| go-v0.42 x python-v0.4 (wss, noise, yamux) | go-v0.42 | python-v0.4 | wss | noise | yamux | ✅ | 5s | 27.828 | 4.652 |
| go-v0.42 x python-v0.4 (quic-v1) | go-v0.42 | python-v0.4 | quic-v1 | - | - | ✅ | 5s | 79.642 | 19.992 |
| go-v0.42 x nim-v1.14 (tcp, noise, yamux) | go-v0.42 | nim-v1.14 | tcp | noise | yamux | ✅ | 5s | 214.024 | 43.529 |
| go-v0.42 x nim-v1.14 (ws, noise, yamux) | go-v0.42 | nim-v1.14 | ws | noise | yamux | ✅ | 5s | 255.672 | 43.594 |
| go-v0.42 x js-v1.x (tcp, noise, yamux) | go-v0.42 | js-v1.x | tcp | noise | yamux | ✅ | 19s | 132.024 | 17.579 |
| go-v0.42 x js-v1.x (ws, noise, yamux) | go-v0.42 | js-v1.x | ws | noise | yamux | ✅ | 21s | 150.25 | 18.483 |
| go-v0.42 x jvm-v1.2 (tcp, noise, yamux) | go-v0.42 | jvm-v1.2 | tcp | noise | yamux | ✅ | 10s | 1212.841 | 34.46 |
| go-v0.42 x js-v2.x (tcp, noise, yamux) | go-v0.42 | js-v2.x | tcp | noise | yamux | ✅ | 22s | 153.069 | 25.576 |
| go-v0.42 x js-v3.x (tcp, noise, yamux) | go-v0.42 | js-v3.x | tcp | noise | yamux | ✅ | 21s | 196.028 | 28.201 |
| go-v0.42 x js-v2.x (ws, noise, yamux) | go-v0.42 | js-v2.x | ws | noise | yamux | ✅ | 22s | 158.79 | 29.96 |
| go-v0.42 x js-v3.x (ws, noise, yamux) | go-v0.42 | js-v3.x | ws | noise | yamux | ✅ | 21s | 144.572 | 8.671 |
| go-v0.42 x jvm-v1.2 (tcp, tls, yamux) | go-v0.42 | jvm-v1.2 | tcp | tls | yamux | ✅ | 14s | 2941.076 | 8.175 |
| go-v0.42 x c-v0.0.1 (tcp, noise, yamux) | go-v0.42 | c-v0.0.1 | tcp | noise | yamux | ✅ | 6s | 123.532 | 54.372 |
| go-v0.42 x c-v0.0.1 (quic-v1) | go-v0.42 | c-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 22.047 | 2.524 |
| go-v0.42 x dotnet-v1.0 (tcp, noise, yamux) | go-v0.42 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 6s | 542.972 | 45.822 |
| go-v0.42 x jvm-v1.2 (ws, noise, yamux) | go-v0.42 | jvm-v1.2 | ws | noise | yamux | ✅ | 10s | 1318.241 | 41.623 |
| go-v0.42 x zig-v0.0.1 (quic-v1) | go-v0.42 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 6s | - | - |
| go-v0.42 x eth-p2p-z-v0.0.1 (quic-v1) | go-v0.42 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 7s | 20.968 | 0.741 |
| go-v0.42 x jvm-v1.2 (ws, tls, yamux) | go-v0.42 | jvm-v1.2 | ws | tls | yamux | ✅ | 12s | 3995.727 | 9.804 |
| go-v0.42 x jvm-v1.2 (quic-v1) | go-v0.42 | jvm-v1.2 | quic-v1 | - | - | ✅ | 11s | 569.555 | 4.917 |
| go-v0.43 x rust-v0.53 (tcp, tls, yamux) | go-v0.43 | rust-v0.53 | tcp | tls | yamux | ✅ | 3s | 95.72 | 43.045 |
| go-v0.43 x rust-v0.53 (tcp, noise, yamux) | go-v0.43 | rust-v0.53 | tcp | noise | yamux | ✅ | 4s | 90.733 | 42.352 |
| go-v0.43 x rust-v0.53 (quic-v1) | go-v0.43 | rust-v0.53 | quic-v1 | - | - | ✅ | 4s | 8.995 | 1.641 |
| go-v0.43 x rust-v0.53 (ws, tls, yamux) | go-v0.43 | rust-v0.53 | ws | tls | yamux | ✅ | 6s | 227.123 | 43.725 |
| go-v0.43 x rust-v0.53 (webrtc-direct) | go-v0.43 | rust-v0.53 | webrtc-direct | - | - | ✅ | 5s | 412.483 | 0.465 |
| go-v0.43 x rust-v0.53 (ws, noise, yamux) | go-v0.43 | rust-v0.53 | ws | noise | yamux | ✅ | 7s | 230.507 | 43.687 |
| go-v0.43 x rust-v0.54 (tcp, tls, yamux) | go-v0.43 | rust-v0.54 | tcp | tls | yamux | ✅ | 5s | 89.983 | 43.097 |
| go-v0.43 x rust-v0.54 (tcp, noise, yamux) | go-v0.43 | rust-v0.54 | tcp | noise | yamux | ✅ | 6s | 90.203 | 43.149 |
| go-v0.43 x rust-v0.54 (ws, tls, yamux) | go-v0.43 | rust-v0.54 | ws | tls | yamux | ✅ | 5s | 187.469 | 46.106 |
| go-v0.43 x rust-v0.54 (ws, noise, yamux) | go-v0.43 | rust-v0.54 | ws | noise | yamux | ✅ | 5s | 186.765 | 46.412 |
| go-v0.43 x rust-v0.54 (quic-v1) | go-v0.43 | rust-v0.54 | quic-v1 | - | - | ✅ | 4s | 9.396 | 0.469 |
| go-v0.43 x rust-v0.55 (tcp, noise, yamux) | go-v0.43 | rust-v0.55 | tcp | noise | yamux | ✅ | 5s | 5.654 | 0.352 |
| go-v0.43 x rust-v0.54 (webrtc-direct) | go-v0.43 | rust-v0.54 | webrtc-direct | - | - | ✅ | 6s | 412.946 | 0.707 |
| go-v0.43 x rust-v0.55 (tcp, tls, yamux) | go-v0.43 | rust-v0.55 | tcp | tls | yamux | ✅ | 5s | 12.452 | 0.464 |
| go-v0.43 x rust-v0.55 (ws, tls, yamux) | go-v0.43 | rust-v0.55 | ws | tls | yamux | ✅ | 5s | 10.256 | 0.659 |
| go-v0.43 x rust-v0.55 (ws, noise, yamux) | go-v0.43 | rust-v0.55 | ws | noise | yamux | ✅ | 5s | 3.485 | 0.183 |
| go-v0.43 x rust-v0.55 (quic-v1) | go-v0.43 | rust-v0.55 | quic-v1 | - | - | ✅ | 5s | 17.5 | 3.003 |
| go-v0.43 x rust-v0.56 (tcp, tls, yamux) | go-v0.43 | rust-v0.56 | tcp | tls | yamux | ✅ | 4s | 6.489 | 0.249 |
| go-v0.43 x rust-v0.55 (webrtc-direct) | go-v0.43 | rust-v0.55 | webrtc-direct | - | - | ✅ | 6s | 418.047 | 0.677 |
| go-v0.43 x rust-v0.56 (tcp, noise, yamux) | go-v0.43 | rust-v0.56 | tcp | noise | yamux | ✅ | 4s | 4.403 | 0.273 |
| go-v0.43 x rust-v0.56 (ws, tls, yamux) | go-v0.43 | rust-v0.56 | ws | tls | yamux | ✅ | 5s | 14.67 | 0.749 |
| go-v0.43 x rust-v0.56 (ws, noise, yamux) | go-v0.43 | rust-v0.56 | ws | noise | yamux | ✅ | 5s | 77.725 | 0.778 |
| go-v0.43 x rust-v0.56 (quic-v1) | go-v0.43 | rust-v0.56 | quic-v1 | - | - | ✅ | 5s | 11.569 | 1.22 |
| go-v0.43 x go-v0.38 (tcp, tls, yamux) | go-v0.43 | go-v0.38 | tcp | tls | yamux | ✅ | 5s | 14.546 | 7.757 |
| go-v0.43 x go-v0.38 (tcp, noise, yamux) | go-v0.43 | go-v0.38 | tcp | noise | yamux | ✅ | 4s | 8.395 | 0.55 |
| go-v0.43 x go-v0.38 (ws, tls, yamux) | go-v0.43 | go-v0.38 | ws | tls | yamux | ✅ | 5s | 7.681 | 0.27 |
| go-v0.43 x go-v0.38 (ws, noise, yamux) | go-v0.43 | go-v0.38 | ws | noise | yamux | ✅ | 3s | 11.154 | 0.935 |
| go-v0.43 x go-v0.38 (wss, tls, yamux) | go-v0.43 | go-v0.38 | wss | tls | yamux | ✅ | 5s | 17.438 | 0.889 |
| go-v0.43 x go-v0.38 (quic-v1) | go-v0.43 | go-v0.38 | quic-v1 | - | - | ✅ | 4s | 8.993 | 0.301 |
| go-v0.43 x rust-v0.56 (webrtc-direct) | go-v0.43 | rust-v0.56 | webrtc-direct | - | - | ❌ | 9s | - | - |
| go-v0.43 x go-v0.38 (webtransport) | go-v0.43 | go-v0.38 | webtransport | - | - | ✅ | 4s | 75.635 | 0.58 |
| go-v0.43 x go-v0.38 (wss, noise, yamux) | go-v0.43 | go-v0.38 | wss | noise | yamux | ✅ | 6s | 12.209 | 0.292 |
| go-v0.43 x go-v0.38 (webrtc-direct) | go-v0.43 | go-v0.38 | webrtc-direct | - | - | ✅ | 4s | 213.701 | 1.974 |
| go-v0.43 x go-v0.39 (tcp, tls, yamux) | go-v0.43 | go-v0.39 | tcp | tls | yamux | ✅ | 5s | 8.116 | 0.815 |
| go-v0.43 x go-v0.39 (tcp, noise, yamux) | go-v0.43 | go-v0.39 | tcp | noise | yamux | ✅ | 5s | 7.867 | 0.5 |
| go-v0.43 x go-v0.39 (ws, tls, yamux) | go-v0.43 | go-v0.39 | ws | tls | yamux | ✅ | 4s | 10.583 | 0.708 |
| go-v0.43 x go-v0.39 (ws, noise, yamux) | go-v0.43 | go-v0.39 | ws | noise | yamux | ✅ | 4s | 11.262 | 0.77 |
| go-v0.43 x go-v0.39 (wss, tls, yamux) | go-v0.43 | go-v0.39 | wss | tls | yamux | ✅ | 5s | 18.79 | 0.249 |
| go-v0.43 x go-v0.39 (quic-v1) | go-v0.43 | go-v0.39 | quic-v1 | - | - | ✅ | 5s | 23.06 | 0.57 |
| go-v0.43 x go-v0.39 (wss, noise, yamux) | go-v0.43 | go-v0.39 | wss | noise | yamux | ✅ | 5s | 12.291 | 0.85 |
| go-v0.43 x go-v0.39 (webtransport) | go-v0.43 | go-v0.39 | webtransport | - | - | ✅ | 4s | 25.705 | 1.772 |
| go-v0.43 x go-v0.39 (webrtc-direct) | go-v0.43 | go-v0.39 | webrtc-direct | - | - | ✅ | 5s | 224.098 | 0.699 |
| go-v0.43 x go-v0.40 (tcp, noise, yamux) | go-v0.43 | go-v0.40 | tcp | noise | yamux | ✅ | 4s | 10.661 | 1.095 |
| go-v0.43 x go-v0.40 (tcp, tls, yamux) | go-v0.43 | go-v0.40 | tcp | tls | yamux | ✅ | 6s | 9.715 | 2.604 |
| go-v0.43 x go-v0.40 (ws, tls, yamux) | go-v0.43 | go-v0.40 | ws | tls | yamux | ✅ | 5s | 9.043 | 0.368 |
| go-v0.43 x go-v0.40 (ws, noise, yamux) | go-v0.43 | go-v0.40 | ws | noise | yamux | ✅ | 5s | 10.438 | 0.984 |
| go-v0.43 x go-v0.40 (wss, tls, yamux) | go-v0.43 | go-v0.40 | wss | tls | yamux | ✅ | 6s | 15.809 | 0.433 |
| go-v0.43 x go-v0.40 (wss, noise, yamux) | go-v0.43 | go-v0.40 | wss | noise | yamux | ✅ | 5s | 17.359 | 1.201 |
| go-v0.43 x go-v0.40 (quic-v1) | go-v0.43 | go-v0.40 | quic-v1 | - | - | ✅ | 6s | 13.395 | 0.681 |
| go-v0.43 x go-v0.40 (webtransport) | go-v0.43 | go-v0.40 | webtransport | - | - | ✅ | 5s | 58.732 | 3.04 |
| go-v0.43 x go-v0.40 (webrtc-direct) | go-v0.43 | go-v0.40 | webrtc-direct | - | - | ✅ | 5s | 216.201 | 1.486 |
| go-v0.43 x go-v0.41 (tcp, tls, yamux) | go-v0.43 | go-v0.41 | tcp | tls | yamux | ✅ | 5s | 14.126 | 0.854 |
| go-v0.43 x go-v0.41 (tcp, noise, yamux) | go-v0.43 | go-v0.41 | tcp | noise | yamux | ✅ | 5s | 9.181 | 3.553 |
| go-v0.43 x go-v0.41 (ws, tls, yamux) | go-v0.43 | go-v0.41 | ws | tls | yamux | ✅ | 6s | 13.818 | 1.057 |
| go-v0.43 x go-v0.41 (ws, noise, yamux) | go-v0.43 | go-v0.41 | ws | noise | yamux | ✅ | 4s | 14.791 | 0.945 |
| go-v0.43 x go-v0.41 (wss, tls, yamux) | go-v0.43 | go-v0.41 | wss | tls | yamux | ✅ | 4s | 18.493 | 1.068 |
| go-v0.43 x go-v0.41 (wss, noise, yamux) | go-v0.43 | go-v0.41 | wss | noise | yamux | ✅ | 6s | 13.779 | 0.384 |
| go-v0.43 x go-v0.41 (quic-v1) | go-v0.43 | go-v0.41 | quic-v1 | - | - | ✅ | 5s | 17.923 | 1.237 |
| go-v0.43 x go-v0.41 (webtransport) | go-v0.43 | go-v0.41 | webtransport | - | - | ✅ | 6s | 25.334 | 0.846 |
| go-v0.43 x go-v0.41 (webrtc-direct) | go-v0.43 | go-v0.41 | webrtc-direct | - | - | ✅ | 5s | 212.968 | 0.653 |
| go-v0.43 x go-v0.42 (tcp, tls, yamux) | go-v0.43 | go-v0.42 | tcp | tls | yamux | ✅ | 5s | 5.481 | 0.487 |
| go-v0.43 x go-v0.42 (ws, tls, yamux) | go-v0.43 | go-v0.42 | ws | tls | yamux | ✅ | 5s | 8.407 | 0.212 |
| go-v0.43 x go-v0.42 (tcp, noise, yamux) | go-v0.43 | go-v0.42 | tcp | noise | yamux | ✅ | 6s | 6.226 | 0.283 |
| go-v0.43 x go-v0.42 (ws, noise, yamux) | go-v0.43 | go-v0.42 | ws | noise | yamux | ✅ | 5s | 7.894 | 1.46 |
| go-v0.43 x go-v0.42 (wss, tls, yamux) | go-v0.43 | go-v0.42 | wss | tls | yamux | ✅ | 5s | 20.602 | 0.517 |
| go-v0.43 x go-v0.42 (quic-v1) | go-v0.43 | go-v0.42 | quic-v1 | - | - | ✅ | 5s | 13.543 | 2.035 |
| go-v0.43 x go-v0.42 (wss, noise, yamux) | go-v0.43 | go-v0.42 | wss | noise | yamux | ✅ | 5s | 11.279 | 0.464 |
| go-v0.43 x go-v0.42 (webtransport) | go-v0.43 | go-v0.42 | webtransport | - | - | ✅ | 4s | 19.556 | 0.528 |
| go-v0.43 x go-v0.43 (tcp, tls, yamux) | go-v0.43 | go-v0.43 | tcp | tls | yamux | ✅ | 5s | 16.134 | 0.292 |
| go-v0.43 x go-v0.42 (webrtc-direct) | go-v0.43 | go-v0.42 | webrtc-direct | - | - | ✅ | 6s | 217.246 | 0.708 |
| go-v0.43 x go-v0.43 (tcp, noise, yamux) | go-v0.43 | go-v0.43 | tcp | noise | yamux | ✅ | 5s | 7.285 | 0.493 |
| go-v0.43 x go-v0.43 (ws, tls, yamux) | go-v0.43 | go-v0.43 | ws | tls | yamux | ✅ | 5s | 9.12 | 1.37 |
| go-v0.43 x go-v0.43 (ws, noise, yamux) | go-v0.43 | go-v0.43 | ws | noise | yamux | ✅ | 5s | 29.467 | 2.188 |
| go-v0.43 x go-v0.43 (wss, tls, yamux) | go-v0.43 | go-v0.43 | wss | tls | yamux | ✅ | 5s | 25.895 | 0.49 |
| go-v0.43 x go-v0.43 (quic-v1) | go-v0.43 | go-v0.43 | quic-v1 | - | - | ✅ | 5s | 15.006 | 3.05 |
| go-v0.43 x go-v0.43 (wss, noise, yamux) | go-v0.43 | go-v0.43 | wss | noise | yamux | ✅ | 5s | 19.677 | 3.617 |
| go-v0.43 x go-v0.43 (webtransport) | go-v0.43 | go-v0.43 | webtransport | - | - | ✅ | 4s | 25.422 | 0.864 |
| go-v0.43 x go-v0.43 (webrtc-direct) | go-v0.43 | go-v0.43 | webrtc-direct | - | - | ✅ | 5s | 217.718 | 1.39 |
| go-v0.43 x go-v0.44 (tcp, noise, yamux) | go-v0.43 | go-v0.44 | tcp | noise | yamux | ✅ | 5s | 6.229 | 1.3 |
| go-v0.43 x go-v0.44 (tcp, tls, yamux) | go-v0.43 | go-v0.44 | tcp | tls | yamux | ✅ | 5s | 5.8 | 0.271 |
| go-v0.43 x go-v0.44 (ws, tls, yamux) | go-v0.43 | go-v0.44 | ws | tls | yamux | ✅ | 5s | 5.812 | 0.505 |
| go-v0.43 x go-v0.44 (ws, noise, yamux) | go-v0.43 | go-v0.44 | ws | noise | yamux | ✅ | 4s | 10.154 | 1.065 |
| go-v0.43 x go-v0.44 (wss, tls, yamux) | go-v0.43 | go-v0.44 | wss | tls | yamux | ✅ | 5s | 21.914 | 0.457 |
| go-v0.43 x go-v0.44 (wss, noise, yamux) | go-v0.43 | go-v0.44 | wss | noise | yamux | ✅ | 4s | 12.041 | 0.342 |
| go-v0.43 x go-v0.44 (quic-v1) | go-v0.43 | go-v0.44 | quic-v1 | - | - | ✅ | 4s | 15.441 | 3.582 |
| go-v0.43 x go-v0.44 (webtransport) | go-v0.43 | go-v0.44 | webtransport | - | - | ✅ | 4s | 21.233 | 0.834 |
| go-v0.43 x go-v0.44 (webrtc-direct) | go-v0.43 | go-v0.44 | webrtc-direct | - | - | ✅ | 4s | 221.494 | 5.23 |
| go-v0.43 x go-v0.45 (tcp, tls, yamux) | go-v0.43 | go-v0.45 | tcp | tls | yamux | ✅ | 5s | 13.03 | 0.375 |
| go-v0.43 x go-v0.45 (tcp, noise, yamux) | go-v0.43 | go-v0.45 | tcp | noise | yamux | ✅ | 5s | 10.068 | 1.221 |
| go-v0.43 x go-v0.45 (ws, tls, yamux) | go-v0.43 | go-v0.45 | ws | tls | yamux | ✅ | 5s | 4.801 | 0.694 |
| go-v0.43 x go-v0.45 (ws, noise, yamux) | go-v0.43 | go-v0.45 | ws | noise | yamux | ✅ | 6s | 14.109 | 1.147 |
| go-v0.43 x go-v0.45 (wss, tls, yamux) | go-v0.43 | go-v0.45 | wss | tls | yamux | ✅ | 5s | 17.613 | 0.63 |
| go-v0.43 x go-v0.45 (wss, noise, yamux) | go-v0.43 | go-v0.45 | wss | noise | yamux | ✅ | 5s | 15.046 | 0.463 |
| go-v0.43 x go-v0.45 (quic-v1) | go-v0.43 | go-v0.45 | quic-v1 | - | - | ✅ | 5s | 14.232 | 1.209 |
| go-v0.43 x go-v0.45 (webtransport) | go-v0.43 | go-v0.45 | webtransport | - | - | ✅ | 5s | 24.289 | 3.197 |
| go-v0.43 x go-v0.45 (webrtc-direct) | go-v0.43 | go-v0.45 | webrtc-direct | - | - | ✅ | 5s | 214.565 | 0.472 |
| go-v0.43 x python-v0.4 (tcp, noise, yamux) | go-v0.43 | python-v0.4 | tcp | noise | yamux | ✅ | 4s | 81.436 | 3.288 |
| go-v0.43 x python-v0.4 (ws, noise, yamux) | go-v0.43 | python-v0.4 | ws | noise | yamux | ✅ | 5s | 29.163 | 3.325 |
| go-v0.43 x python-v0.4 (wss, noise, yamux) | go-v0.43 | python-v0.4 | wss | noise | yamux | ✅ | 5s | 39.455 | 6.899 |
| go-v0.43 x python-v0.4 (quic-v1) | go-v0.43 | python-v0.4 | quic-v1 | - | - | ✅ | 5s | 124.697 | 15.197 |
| go-v0.43 x nim-v1.14 (tcp, noise, yamux) | go-v0.43 | nim-v1.14 | tcp | noise | yamux | ✅ | 5s | 228.061 | 47.567 |
| go-v0.43 x nim-v1.14 (ws, noise, yamux) | go-v0.43 | nim-v1.14 | ws | noise | yamux | ✅ | 6s | 246.814 | 43.354 |
| go-v0.43 x js-v1.x (tcp, noise, yamux) | go-v0.43 | js-v1.x | tcp | noise | yamux | ✅ | 18s | 146.9 | 21.465 |
| go-v0.43 x js-v1.x (ws, noise, yamux) | go-v0.43 | js-v1.x | ws | noise | yamux | ✅ | 20s | 173.114 | 18.501 |
| go-v0.43 x js-v2.x (tcp, noise, yamux) | go-v0.43 | js-v2.x | tcp | noise | yamux | ✅ | 22s | 190.354 | 37.738 |
| go-v0.43 x js-v3.x (tcp, noise, yamux) | go-v0.43 | js-v3.x | tcp | noise | yamux | ✅ | 21s | 135.825 | 21.827 |
| go-v0.43 x js-v2.x (ws, noise, yamux) | go-v0.43 | js-v2.x | ws | noise | yamux | ✅ | 22s | 192.242 | 30.201 |
| go-v0.43 x jvm-v1.2 (tcp, noise, yamux) | go-v0.43 | jvm-v1.2 | tcp | noise | yamux | ✅ | 11s | 1213.247 | 13.871 |
| go-v0.43 x jvm-v1.2 (tcp, tls, yamux) | go-v0.43 | jvm-v1.2 | tcp | tls | yamux | ✅ | 12s | 2817.476 | 6.056 |
| go-v0.43 x js-v3.x (ws, noise, yamux) | go-v0.43 | js-v3.x | ws | noise | yamux | ✅ | 21s | 149.942 | 16.204 |
| go-v0.43 x c-v0.0.1 (tcp, noise, yamux) | go-v0.43 | c-v0.0.1 | tcp | noise | yamux | ✅ | 6s | 118.189 | 54.51 |
| go-v0.43 x c-v0.0.1 (quic-v1) | go-v0.43 | c-v0.0.1 | quic-v1 | - | - | ✅ | 5s | 42.257 | 23.251 |
| go-v0.43 x jvm-v1.2 (ws, tls, yamux) | go-v0.43 | jvm-v1.2 | ws | tls | yamux | ✅ | 11s | 3748.496 | 24.609 |
| go-v0.43 x jvm-v1.2 (ws, noise, yamux) | go-v0.43 | jvm-v1.2 | ws | noise | yamux | ✅ | 10s | 1687.882 | 11.174 |
| go-v0.43 x dotnet-v1.0 (tcp, noise, yamux) | go-v0.43 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 6s | 404.434 | 43.292 |
| go-v0.43 x zig-v0.0.1 (quic-v1) | go-v0.43 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 7s | - | - |
| go-v0.43 x eth-p2p-z-v0.0.1 (quic-v1) | go-v0.43 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 15.389 | 0.277 |
| go-v0.43 x jvm-v1.2 (quic-v1) | go-v0.43 | jvm-v1.2 | quic-v1 | - | - | ✅ | 10s | 694.358 | 9.866 |
| go-v0.44 x rust-v0.53 (tcp, noise, yamux) | go-v0.44 | rust-v0.53 | tcp | noise | yamux | ✅ | 4s | 98.353 | 45.594 |
| go-v0.44 x rust-v0.53 (tcp, tls, yamux) | go-v0.44 | rust-v0.53 | tcp | tls | yamux | ✅ | 5s | 95.078 | 47.149 |
| go-v0.44 x rust-v0.53 (ws, tls, yamux) | go-v0.44 | rust-v0.53 | ws | tls | yamux | ✅ | 5s | 181.317 | 41.856 |
| go-v0.44 x rust-v0.53 (quic-v1) | go-v0.44 | rust-v0.53 | quic-v1 | - | - | ✅ | 4s | 17.42 | 0.478 |
| go-v0.44 x rust-v0.53 (ws, noise, yamux) | go-v0.44 | rust-v0.53 | ws | noise | yamux | ✅ | 6s | 191.418 | 46.621 |
| go-v0.44 x rust-v0.53 (webrtc-direct) | go-v0.44 | rust-v0.53 | webrtc-direct | - | - | ✅ | 6s | 211.783 | 0.502 |
| go-v0.44 x rust-v0.54 (tcp, noise, yamux) | go-v0.44 | rust-v0.54 | tcp | noise | yamux | ✅ | 5s | 91.318 | 40.82 |
| go-v0.44 x rust-v0.54 (tcp, tls, yamux) | go-v0.44 | rust-v0.54 | tcp | tls | yamux | ✅ | 6s | 95.489 | 43.304 |
| go-v0.44 x rust-v0.54 (ws, tls, yamux) | go-v0.44 | rust-v0.54 | ws | tls | yamux | ✅ | 4s | 205.579 | 42.684 |
| go-v0.44 x rust-v0.54 (ws, noise, yamux) | go-v0.44 | rust-v0.54 | ws | noise | yamux | ✅ | 5s | 212.88 | 43.034 |
| go-v0.44 x rust-v0.54 (quic-v1) | go-v0.44 | rust-v0.54 | quic-v1 | - | - | ✅ | 4s | 6.708 | 0.206 |
| go-v0.44 x rust-v0.55 (tcp, tls, yamux) | go-v0.44 | rust-v0.55 | tcp | tls | yamux | ✅ | 5s | 7.32 | 0.596 |
| go-v0.44 x rust-v0.55 (tcp, noise, yamux) | go-v0.44 | rust-v0.55 | tcp | noise | yamux | ✅ | 5s | 8.115 | 0.551 |
| go-v0.44 x rust-v0.55 (ws, noise, yamux) | go-v0.44 | rust-v0.55 | ws | noise | yamux | ✅ | 4s | 5.349 | 0.48 |
| go-v0.44 x rust-v0.55 (ws, tls, yamux) | go-v0.44 | rust-v0.55 | ws | tls | yamux | ✅ | 5s | 8.155 | 0.281 |
| go-v0.44 x rust-v0.55 (quic-v1) | go-v0.44 | rust-v0.55 | quic-v1 | - | - | ✅ | 4s | 14.045 | 0.51 |
| go-v0.44 x rust-v0.55 (webrtc-direct) | go-v0.44 | rust-v0.55 | webrtc-direct | - | - | ✅ | 4s | 214.954 | 0.924 |
| go-v0.44 x rust-v0.56 (tcp, tls, yamux) | go-v0.44 | rust-v0.56 | tcp | tls | yamux | ✅ | 5s | 5.946 | 0.282 |
| go-v0.44 x rust-v0.56 (tcp, noise, yamux) | go-v0.44 | rust-v0.56 | tcp | noise | yamux | ✅ | 4s | 4.83 | 0.207 |
| go-v0.44 x rust-v0.54 (webrtc-direct) | go-v0.44 | rust-v0.54 | webrtc-direct | - | - | ❌ | 10s | - | - |
| go-v0.44 x rust-v0.56 (ws, tls, yamux) | go-v0.44 | rust-v0.56 | ws | tls | yamux | ✅ | 5s | 12.418 | 0.79 |
| go-v0.44 x rust-v0.56 (ws, noise, yamux) | go-v0.44 | rust-v0.56 | ws | noise | yamux | ✅ | 5s | 12.846 | 0.579 |
| go-v0.44 x rust-v0.56 (quic-v1) | go-v0.44 | rust-v0.56 | quic-v1 | - | - | ✅ | 5s | 4.658 | 0.183 |
| go-v0.44 x go-v0.38 (tcp, tls, yamux) | go-v0.44 | go-v0.38 | tcp | tls | yamux | ✅ | 4s | 6.447 | 0.155 |
| go-v0.44 x go-v0.38 (ws, tls, yamux) | go-v0.44 | go-v0.38 | ws | tls | yamux | ✅ | 4s | 11.809 | 0.524 |
| go-v0.44 x go-v0.38 (tcp, noise, yamux) | go-v0.44 | go-v0.38 | tcp | noise | yamux | ✅ | 4s | 8.571 | 0.432 |
| go-v0.44 x go-v0.38 (ws, noise, yamux) | go-v0.44 | go-v0.38 | ws | noise | yamux | ✅ | 5s | 8.594 | 0.319 |
| go-v0.44 x go-v0.38 (quic-v1) | go-v0.44 | go-v0.38 | quic-v1 | - | - | ✅ | 3s | 14.502 | 0.626 |
| go-v0.44 x go-v0.38 (wss, noise, yamux) | go-v0.44 | go-v0.38 | wss | noise | yamux | ✅ | 5s | 17.617 | 0.567 |
| go-v0.44 x rust-v0.56 (webrtc-direct) | go-v0.44 | rust-v0.56 | webrtc-direct | - | - | ❌ | 10s | - | - |
| go-v0.44 x go-v0.38 (webtransport) | go-v0.44 | go-v0.38 | webtransport | - | - | ✅ | 5s | 24.044 | 1.597 |
| go-v0.44 x go-v0.38 (wss, tls, yamux) | go-v0.44 | go-v0.38 | wss | tls | yamux | ✅ | 6s | 109.641 | 0.399 |
| go-v0.44 x go-v0.38 (webrtc-direct) | go-v0.44 | go-v0.38 | webrtc-direct | - | - | ✅ | 5s | 237.372 | 0.771 |
| go-v0.44 x go-v0.39 (tcp, tls, yamux) | go-v0.44 | go-v0.39 | tcp | tls | yamux | ✅ | 5s | 10.353 | 0.442 |
| go-v0.44 x go-v0.39 (tcp, noise, yamux) | go-v0.44 | go-v0.39 | tcp | noise | yamux | ✅ | 4s | 5.205 | 0.281 |
| go-v0.44 x go-v0.39 (ws, tls, yamux) | go-v0.44 | go-v0.39 | ws | tls | yamux | ✅ | 5s | 18.585 | 4.308 |
| go-v0.44 x go-v0.39 (ws, noise, yamux) | go-v0.44 | go-v0.39 | ws | noise | yamux | ✅ | 5s | 18.305 | 0.611 |
| go-v0.44 x go-v0.39 (wss, noise, yamux) | go-v0.44 | go-v0.39 | wss | noise | yamux | ✅ | 6s | 16.334 | 0.528 |
| go-v0.44 x go-v0.39 (wss, tls, yamux) | go-v0.44 | go-v0.39 | wss | tls | yamux | ✅ | 6s | 13.331 | 0.371 |
| go-v0.44 x go-v0.39 (quic-v1) | go-v0.44 | go-v0.39 | quic-v1 | - | - | ✅ | 5s | 13.196 | 1.148 |
| go-v0.44 x go-v0.39 (webtransport) | go-v0.44 | go-v0.39 | webtransport | - | - | ✅ | 5s | 11.586 | 0.33 |
| go-v0.44 x go-v0.39 (webrtc-direct) | go-v0.44 | go-v0.39 | webrtc-direct | - | - | ✅ | 5s | 215.83 | 0.542 |
| go-v0.44 x go-v0.40 (tcp, tls, yamux) | go-v0.44 | go-v0.40 | tcp | tls | yamux | ✅ | 5s | 6.424 | 0.252 |
| go-v0.44 x go-v0.40 (tcp, noise, yamux) | go-v0.44 | go-v0.40 | tcp | noise | yamux | ✅ | 5s | 12.456 | 0.84 |
| go-v0.44 x go-v0.40 (ws, tls, yamux) | go-v0.44 | go-v0.40 | ws | tls | yamux | ✅ | 4s | 15.153 | 0.678 |
| go-v0.44 x go-v0.40 (ws, noise, yamux) | go-v0.44 | go-v0.40 | ws | noise | yamux | ✅ | 5s | 17.995 | 5.111 |
| go-v0.44 x go-v0.40 (quic-v1) | go-v0.44 | go-v0.40 | quic-v1 | - | - | ✅ | 5s | 8.256 | 0.412 |
| go-v0.44 x go-v0.40 (wss, noise, yamux) | go-v0.44 | go-v0.40 | wss | noise | yamux | ✅ | 5s | 94.721 | 0.276 |
| go-v0.44 x go-v0.40 (webtransport) | go-v0.44 | go-v0.40 | webtransport | - | - | ✅ | 4s | 19.459 | 2.853 |
| go-v0.44 x go-v0.40 (wss, tls, yamux) | go-v0.44 | go-v0.40 | wss | tls | yamux | ✅ | 6s | 21.955 | 1.293 |
| go-v0.44 x go-v0.40 (webrtc-direct) | go-v0.44 | go-v0.40 | webrtc-direct | - | - | ✅ | 5s | 211.281 | 0.298 |
| go-v0.44 x go-v0.41 (tcp, tls, yamux) | go-v0.44 | go-v0.41 | tcp | tls | yamux | ✅ | 5s | 10.783 | 0.594 |
| go-v0.44 x go-v0.41 (tcp, noise, yamux) | go-v0.44 | go-v0.41 | tcp | noise | yamux | ✅ | 4s | 6.521 | 0.658 |
| go-v0.44 x go-v0.41 (ws, tls, yamux) | go-v0.44 | go-v0.41 | ws | tls | yamux | ✅ | 5s | 10.429 | 1.066 |
| go-v0.44 x go-v0.41 (ws, noise, yamux) | go-v0.44 | go-v0.41 | ws | noise | yamux | ✅ | 4s | 6.341 | 0.58 |
| go-v0.44 x go-v0.41 (wss, tls, yamux) | go-v0.44 | go-v0.41 | wss | tls | yamux | ✅ | 5s | 21.759 | 0.574 |
| go-v0.44 x go-v0.41 (quic-v1) | go-v0.44 | go-v0.41 | quic-v1 | - | - | ✅ | 5s | 7.645 | 0.454 |
| go-v0.44 x go-v0.41 (webtransport) | go-v0.44 | go-v0.41 | webtransport | - | - | ✅ | 5s | 22.685 | 4.698 |
| go-v0.44 x go-v0.41 (wss, noise, yamux) | go-v0.44 | go-v0.41 | wss | noise | yamux | ✅ | 7s | 13.034 | 0.33 |
| go-v0.44 x go-v0.41 (webrtc-direct) | go-v0.44 | go-v0.41 | webrtc-direct | - | - | ✅ | 5s | 213.542 | 0.297 |
| go-v0.44 x go-v0.42 (tcp, tls, yamux) | go-v0.44 | go-v0.42 | tcp | tls | yamux | ✅ | 5s | 6.819 | 0.665 |
| go-v0.44 x go-v0.42 (tcp, noise, yamux) | go-v0.44 | go-v0.42 | tcp | noise | yamux | ✅ | 4s | 11.046 | 0.633 |
| go-v0.44 x go-v0.42 (ws, tls, yamux) | go-v0.44 | go-v0.42 | ws | tls | yamux | ✅ | 5s | 10.022 | 0.357 |
| go-v0.44 x go-v0.42 (ws, noise, yamux) | go-v0.44 | go-v0.42 | ws | noise | yamux | ✅ | 5s | 22.271 | 8.128 |
| go-v0.44 x go-v0.42 (wss, tls, yamux) | go-v0.44 | go-v0.42 | wss | tls | yamux | ✅ | 5s | 22.078 | 0.781 |
| go-v0.44 x go-v0.42 (wss, noise, yamux) | go-v0.44 | go-v0.42 | wss | noise | yamux | ✅ | 4s | 22.183 | 0.515 |
| go-v0.44 x go-v0.42 (quic-v1) | go-v0.44 | go-v0.42 | quic-v1 | - | - | ✅ | 5s | 15.458 | 1.943 |
| go-v0.44 x go-v0.42 (webtransport) | go-v0.44 | go-v0.42 | webtransport | - | - | ✅ | 4s | 16.897 | 0.823 |
| go-v0.44 x go-v0.42 (webrtc-direct) | go-v0.44 | go-v0.42 | webrtc-direct | - | - | ✅ | 5s | 217.196 | 0.691 |
| go-v0.44 x go-v0.43 (tcp, tls, yamux) | go-v0.44 | go-v0.43 | tcp | tls | yamux | ✅ | 5s | 8.992 | 0.518 |
| go-v0.44 x go-v0.43 (tcp, noise, yamux) | go-v0.44 | go-v0.43 | tcp | noise | yamux | ✅ | 4s | 8.135 | 1.164 |
| go-v0.44 x go-v0.43 (ws, tls, yamux) | go-v0.44 | go-v0.43 | ws | tls | yamux | ✅ | 5s | 20.225 | 1.984 |
| go-v0.44 x go-v0.43 (ws, noise, yamux) | go-v0.44 | go-v0.43 | ws | noise | yamux | ✅ | 5s | 10.542 | 0.318 |
| go-v0.44 x go-v0.43 (wss, tls, yamux) | go-v0.44 | go-v0.43 | wss | tls | yamux | ✅ | 5s | 18.038 | 1.228 |
| go-v0.44 x go-v0.43 (quic-v1) | go-v0.44 | go-v0.43 | quic-v1 | - | - | ✅ | 4s | 16.619 | 0.987 |
| go-v0.44 x go-v0.43 (webtransport) | go-v0.44 | go-v0.43 | webtransport | - | - | ✅ | 4s | 64.611 | 0.572 |
| go-v0.44 x go-v0.43 (wss, noise, yamux) | go-v0.44 | go-v0.43 | wss | noise | yamux | ✅ | 7s | 9.941 | 0.519 |
| go-v0.44 x go-v0.43 (webrtc-direct) | go-v0.44 | go-v0.43 | webrtc-direct | - | - | ✅ | 4s | 27.39 | 1.767 |
| go-v0.44 x go-v0.44 (tcp, tls, yamux) | go-v0.44 | go-v0.44 | tcp | tls | yamux | ✅ | 5s | 5.741 | 0.69 |
| go-v0.44 x go-v0.44 (tcp, noise, yamux) | go-v0.44 | go-v0.44 | tcp | noise | yamux | ✅ | 4s | 14.786 | 0.31 |
| go-v0.44 x go-v0.44 (ws, tls, yamux) | go-v0.44 | go-v0.44 | ws | tls | yamux | ✅ | 4s | 14.614 | 0.504 |
| go-v0.44 x go-v0.44 (ws, noise, yamux) | go-v0.44 | go-v0.44 | ws | noise | yamux | ✅ | 4s | 11.701 | 0.797 |
| go-v0.44 x go-v0.44 (wss, tls, yamux) | go-v0.44 | go-v0.44 | wss | tls | yamux | ✅ | 5s | 20.444 | 0.932 |
| go-v0.44 x go-v0.44 (wss, noise, yamux) | go-v0.44 | go-v0.44 | wss | noise | yamux | ✅ | 5s | 21.992 | 0.382 |
| go-v0.44 x go-v0.44 (quic-v1) | go-v0.44 | go-v0.44 | quic-v1 | - | - | ✅ | 5s | 14.078 | 1.012 |
| go-v0.44 x go-v0.44 (webtransport) | go-v0.44 | go-v0.44 | webtransport | - | - | ✅ | 5s | 8.935 | 0.24 |
| go-v0.44 x go-v0.44 (webrtc-direct) | go-v0.44 | go-v0.44 | webrtc-direct | - | - | ✅ | 5s | 210.232 | 0.347 |
| go-v0.44 x go-v0.45 (tcp, tls, yamux) | go-v0.44 | go-v0.45 | tcp | tls | yamux | ✅ | 5s | 12.803 | 1.563 |
| go-v0.44 x go-v0.45 (tcp, noise, yamux) | go-v0.44 | go-v0.45 | tcp | noise | yamux | ✅ | 4s | 10.572 | 0.983 |
| go-v0.44 x go-v0.45 (ws, tls, yamux) | go-v0.44 | go-v0.45 | ws | tls | yamux | ✅ | 5s | 60.644 | 2.145 |
| go-v0.44 x go-v0.45 (ws, noise, yamux) | go-v0.44 | go-v0.45 | ws | noise | yamux | ✅ | 4s | 11.712 | 0.688 |
| go-v0.44 x go-v0.45 (quic-v1) | go-v0.44 | go-v0.45 | quic-v1 | - | - | ✅ | 4s | 22.368 | 2.801 |
| go-v0.44 x go-v0.45 (webtransport) | go-v0.44 | go-v0.45 | webtransport | - | - | ✅ | 4s | 26.247 | 0.512 |
| go-v0.44 x go-v0.45 (wss, noise, yamux) | go-v0.44 | go-v0.45 | wss | noise | yamux | ✅ | 5s | 90.414 | 0.784 |
| go-v0.44 x go-v0.45 (webrtc-direct) | go-v0.44 | go-v0.45 | webrtc-direct | - | - | ✅ | 5s | 216.996 | 1.606 |
| go-v0.44 x python-v0.4 (tcp, noise, yamux) | go-v0.44 | python-v0.4 | tcp | noise | yamux | ✅ | 5s | 27.068 | 2.503 |
| go-v0.44 x go-v0.45 (wss, tls, yamux) | go-v0.44 | go-v0.45 | wss | tls | yamux | ✅ | 8s | 18.329 | 0.473 |
| go-v0.44 x python-v0.4 (ws, noise, yamux) | go-v0.44 | python-v0.4 | ws | noise | yamux | ✅ | 5s | 31.972 | 4.398 |
| go-v0.44 x python-v0.4 (wss, noise, yamux) | go-v0.44 | python-v0.4 | wss | noise | yamux | ✅ | 5s | 39.982 | 6.997 |
| go-v0.44 x python-v0.4 (quic-v1) | go-v0.44 | python-v0.4 | quic-v1 | - | - | ✅ | 5s | 152.516 | 12.53 |
| go-v0.44 x nim-v1.14 (tcp, noise, yamux) | go-v0.44 | nim-v1.14 | tcp | noise | yamux | ✅ | 5s | 198.622 | 43.478 |
| go-v0.44 x nim-v1.14 (ws, noise, yamux) | go-v0.44 | nim-v1.14 | ws | noise | yamux | ✅ | 5s | 257.561 | 41.987 |
| go-v0.44 x js-v1.x (tcp, noise, yamux) | go-v0.44 | js-v1.x | tcp | noise | yamux | ✅ | 19s | 163.299 | 18.294 |
| go-v0.44 x js-v1.x (ws, noise, yamux) | go-v0.44 | js-v1.x | ws | noise | yamux | ✅ | 20s | 165.812 | 17.276 |
| go-v0.44 x js-v2.x (tcp, noise, yamux) | go-v0.44 | js-v2.x | tcp | noise | yamux | ✅ | 21s | 211.499 | 27.058 |
| go-v0.44 x js-v3.x (tcp, noise, yamux) | go-v0.44 | js-v3.x | tcp | noise | yamux | ✅ | 21s | 186.512 | 30.515 |
| go-v0.44 x jvm-v1.2 (tcp, noise, yamux) | go-v0.44 | jvm-v1.2 | tcp | noise | yamux | ✅ | 10s | 1205.729 | 21.331 |
| go-v0.44 x js-v2.x (ws, noise, yamux) | go-v0.44 | js-v2.x | ws | noise | yamux | ✅ | 22s | 161.693 | 26.624 |
| go-v0.44 x js-v3.x (ws, noise, yamux) | go-v0.44 | js-v3.x | ws | noise | yamux | ✅ | 22s | 266.018 | 44.966 |
| go-v0.44 x jvm-v1.2 (tcp, tls, yamux) | go-v0.44 | jvm-v1.2 | tcp | tls | yamux | ✅ | 14s | 3546.654 | 10.052 |
| go-v0.44 x c-v0.0.1 (tcp, noise, yamux) | go-v0.44 | c-v0.0.1 | tcp | noise | yamux | ✅ | 6s | 119.302 | 51.212 |
| go-v0.44 x c-v0.0.1 (quic-v1) | go-v0.44 | c-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 28.178 | 5.324 |
| go-v0.44 x jvm-v1.2 (ws, noise, yamux) | go-v0.44 | jvm-v1.2 | ws | noise | yamux | ✅ | 10s | 1449.374 | 26.469 |
| go-v0.44 x dotnet-v1.0 (tcp, noise, yamux) | go-v0.44 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 7s | 503.47 | 53.846 |
| go-v0.44 x zig-v0.0.1 (quic-v1) | go-v0.44 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 5s | - | - |
| go-v0.44 x eth-p2p-z-v0.0.1 (quic-v1) | go-v0.44 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 62.071 | 0.865 |
| go-v0.44 x jvm-v1.2 (ws, tls, yamux) | go-v0.44 | jvm-v1.2 | ws | tls | yamux | ✅ | 13s | 3820.3 | 11.945 |
| go-v0.44 x jvm-v1.2 (quic-v1) | go-v0.44 | jvm-v1.2 | quic-v1 | - | - | ✅ | 11s | 1012.968 | 6.398 |
| go-v0.45 x rust-v0.53 (tcp, tls, yamux) | go-v0.45 | rust-v0.53 | tcp | tls | yamux | ✅ | 5s | 94.728 | 42.287 |
| go-v0.45 x rust-v0.53 (tcp, noise, yamux) | go-v0.45 | rust-v0.53 | tcp | noise | yamux | ✅ | 5s | 134.423 | 43.637 |
| go-v0.45 x rust-v0.53 (ws, tls, yamux) | go-v0.45 | rust-v0.53 | ws | tls | yamux | ✅ | 4s | 224.698 | 45.37 |
| go-v0.45 x rust-v0.53 (ws, noise, yamux) | go-v0.45 | rust-v0.53 | ws | noise | yamux | ✅ | 4s | 182.572 | 43.738 |
| go-v0.45 x rust-v0.53 (quic-v1) | go-v0.45 | rust-v0.53 | quic-v1 | - | - | ✅ | 5s | 16.619 | 1.665 |
| go-v0.45 x rust-v0.53 (webrtc-direct) | go-v0.45 | rust-v0.53 | webrtc-direct | - | - | ✅ | 6s | 411.284 | 0.595 |
| go-v0.45 x rust-v0.54 (tcp, noise, yamux) | go-v0.45 | rust-v0.54 | tcp | noise | yamux | ✅ | 4s | 93.447 | 41.518 |
| go-v0.45 x rust-v0.54 (tcp, tls, yamux) | go-v0.45 | rust-v0.54 | tcp | tls | yamux | ✅ | 6s | 91.341 | 41.762 |
| go-v0.45 x rust-v0.54 (ws, tls, yamux) | go-v0.45 | rust-v0.54 | ws | tls | yamux | ✅ | 5s | 201.241 | 47.641 |
| go-v0.45 x rust-v0.54 (ws, noise, yamux) | go-v0.45 | rust-v0.54 | ws | noise | yamux | ✅ | 6s | 226.641 | 43.689 |
| go-v0.45 x rust-v0.54 (quic-v1) | go-v0.45 | rust-v0.54 | quic-v1 | - | - | ✅ | 5s | 6.902 | 0.494 |
| go-v0.45 x rust-v0.54 (webrtc-direct) | go-v0.45 | rust-v0.54 | webrtc-direct | - | - | ✅ | 5s | 411.011 | 0.404 |
| go-v0.45 x rust-v0.55 (tcp, tls, yamux) | go-v0.45 | rust-v0.55 | tcp | tls | yamux | ✅ | 4s | 5.085 | 0.16 |
| go-v0.45 x rust-v0.55 (tcp, noise, yamux) | go-v0.45 | rust-v0.55 | tcp | noise | yamux | ✅ | 5s | 4.292 | 0.19 |
| go-v0.45 x rust-v0.55 (ws, tls, yamux) | go-v0.45 | rust-v0.55 | ws | tls | yamux | ✅ | 5s | 9.134 | 1.153 |
| go-v0.45 x rust-v0.55 (ws, noise, yamux) | go-v0.45 | rust-v0.55 | ws | noise | yamux | ✅ | 4s | 11.827 | 1.003 |
| go-v0.45 x rust-v0.55 (quic-v1) | go-v0.45 | rust-v0.55 | quic-v1 | - | - | ✅ | 5s | 21.511 | 0.327 |
| go-v0.45 x rust-v0.55 (webrtc-direct) | go-v0.45 | rust-v0.55 | webrtc-direct | - | - | ✅ | 5s | 413.799 | 0.488 |
| go-v0.45 x rust-v0.56 (tcp, tls, yamux) | go-v0.45 | rust-v0.56 | tcp | tls | yamux | ✅ | 5s | 6.785 | 0.658 |
| go-v0.45 x rust-v0.56 (ws, tls, yamux) | go-v0.45 | rust-v0.56 | ws | tls | yamux | ✅ | 4s | 10.994 | 1.501 |
| go-v0.45 x rust-v0.56 (tcp, noise, yamux) | go-v0.45 | rust-v0.56 | tcp | noise | yamux | ✅ | 6s | 7.629 | 0.616 |
| go-v0.45 x rust-v0.56 (ws, noise, yamux) | go-v0.45 | rust-v0.56 | ws | noise | yamux | ✅ | 5s | 8.781 | 0.333 |
| go-v0.45 x rust-v0.56 (quic-v1) | go-v0.45 | rust-v0.56 | quic-v1 | - | - | ✅ | 5s | 9.656 | 0.347 |
| go-v0.45 x go-v0.38 (tcp, tls, yamux) | go-v0.45 | go-v0.38 | tcp | tls | yamux | ✅ | 5s | 7.802 | 0.582 |
| go-v0.45 x go-v0.38 (tcp, noise, yamux) | go-v0.45 | go-v0.38 | tcp | noise | yamux | ✅ | 4s | 10.898 | 0.545 |
| go-v0.45 x go-v0.38 (ws, tls, yamux) | go-v0.45 | go-v0.38 | ws | tls | yamux | ✅ | 5s | 17.249 | 0.986 |
| go-v0.45 x go-v0.38 (ws, noise, yamux) | go-v0.45 | go-v0.38 | ws | noise | yamux | ✅ | 4s | 16.158 | 0.406 |
| go-v0.45 x go-v0.38 (wss, tls, yamux) | go-v0.45 | go-v0.38 | wss | tls | yamux | ✅ | 5s | 15.401 | 0.248 |
| go-v0.45 x go-v0.38 (wss, noise, yamux) | go-v0.45 | go-v0.38 | wss | noise | yamux | ✅ | 4s | 20.869 | 0.334 |
| go-v0.45 x go-v0.38 (quic-v1) | go-v0.45 | go-v0.38 | quic-v1 | - | - | ✅ | 5s | 5.962 | 0.333 |
| go-v0.45 x rust-v0.56 (webrtc-direct) | go-v0.45 | rust-v0.56 | webrtc-direct | - | - | ❌ | 9s | - | - |
| go-v0.45 x go-v0.38 (webtransport) | go-v0.45 | go-v0.38 | webtransport | - | - | ✅ | 5s | 27.909 | 1.658 |
| go-v0.45 x go-v0.38 (webrtc-direct) | go-v0.45 | go-v0.38 | webrtc-direct | - | - | ✅ | 4s | 215.932 | 0.55 |
| go-v0.45 x go-v0.39 (tcp, tls, yamux) | go-v0.45 | go-v0.39 | tcp | tls | yamux | ✅ | 4s | 13.916 | 4.05 |
| go-v0.45 x go-v0.39 (tcp, noise, yamux) | go-v0.45 | go-v0.39 | tcp | noise | yamux | ✅ | 4s | 17.702 | 2.288 |
| go-v0.45 x go-v0.39 (ws, tls, yamux) | go-v0.45 | go-v0.39 | ws | tls | yamux | ✅ | 5s | 16.68 | 0.422 |
| go-v0.45 x go-v0.39 (ws, noise, yamux) | go-v0.45 | go-v0.39 | ws | noise | yamux | ✅ | 4s | 8.122 | 0.54 |
| go-v0.45 x go-v0.39 (quic-v1) | go-v0.45 | go-v0.39 | quic-v1 | - | - | ✅ | 5s | 11.163 | 1.845 |
| go-v0.45 x go-v0.39 (wss, tls, yamux) | go-v0.45 | go-v0.39 | wss | tls | yamux | ✅ | 7s | 19.994 | 1.26 |
| go-v0.45 x go-v0.39 (webtransport) | go-v0.45 | go-v0.39 | webtransport | - | - | ✅ | 5s | 11.419 | 0.4 |
| go-v0.45 x go-v0.39 (wss, noise, yamux) | go-v0.45 | go-v0.39 | wss | noise | yamux | ✅ | 6s | 14.483 | 0.898 |
| go-v0.45 x go-v0.39 (webrtc-direct) | go-v0.45 | go-v0.39 | webrtc-direct | - | - | ✅ | 5s | 219.962 | 2.53 |
| go-v0.45 x go-v0.40 (tcp, tls, yamux) | go-v0.45 | go-v0.40 | tcp | tls | yamux | ✅ | 5s | 9.08 | 0.557 |
| go-v0.45 x go-v0.40 (tcp, noise, yamux) | go-v0.45 | go-v0.40 | tcp | noise | yamux | ✅ | 5s | 6.382 | 0.347 |
| go-v0.45 x go-v0.40 (ws, tls, yamux) | go-v0.45 | go-v0.40 | ws | tls | yamux | ✅ | 5s | 13.37 | 0.938 |
| go-v0.45 x go-v0.40 (ws, noise, yamux) | go-v0.45 | go-v0.40 | ws | noise | yamux | ✅ | 4s | 17.689 | 8.706 |
| go-v0.45 x go-v0.40 (wss, noise, yamux) | go-v0.45 | go-v0.40 | wss | noise | yamux | ✅ | 4s | 33.183 | 2.58 |
| go-v0.45 x go-v0.40 (quic-v1) | go-v0.45 | go-v0.40 | quic-v1 | - | - | ✅ | 5s | 17.98 | 0.581 |
| go-v0.45 x go-v0.40 (webtransport) | go-v0.45 | go-v0.40 | webtransport | - | - | ✅ | 5s | 14.909 | 1.359 |
| go-v0.45 x go-v0.40 (wss, tls, yamux) | go-v0.45 | go-v0.40 | wss | tls | yamux | ✅ | 6s | 94.999 | 1.208 |
| go-v0.45 x go-v0.40 (webrtc-direct) | go-v0.45 | go-v0.40 | webrtc-direct | - | - | ✅ | 5s | 219.113 | 0.33 |
| go-v0.45 x go-v0.41 (tcp, tls, yamux) | go-v0.45 | go-v0.41 | tcp | tls | yamux | ✅ | 5s | 8.084 | 0.794 |
| go-v0.45 x go-v0.41 (tcp, noise, yamux) | go-v0.45 | go-v0.41 | tcp | noise | yamux | ✅ | 4s | 12.375 | 2.364 |
| go-v0.45 x go-v0.41 (ws, tls, yamux) | go-v0.45 | go-v0.41 | ws | tls | yamux | ✅ | 4s | 8.586 | 0.37 |
| go-v0.45 x go-v0.41 (ws, noise, yamux) | go-v0.45 | go-v0.41 | ws | noise | yamux | ✅ | 4s | 15.339 | 0.524 |
| go-v0.45 x go-v0.41 (quic-v1) | go-v0.45 | go-v0.41 | quic-v1 | - | - | ✅ | 4s | 22.162 | 2.223 |
| go-v0.45 x go-v0.41 (wss, tls, yamux) | go-v0.45 | go-v0.41 | wss | tls | yamux | ✅ | 6s | 26.917 | 2.353 |
| go-v0.45 x go-v0.41 (wss, noise, yamux) | go-v0.45 | go-v0.41 | wss | noise | yamux | ✅ | 5s | 11.758 | 0.321 |
| go-v0.45 x go-v0.41 (webtransport) | go-v0.45 | go-v0.41 | webtransport | - | - | ✅ | 4s | 10.612 | 0.685 |
| go-v0.45 x go-v0.41 (webrtc-direct) | go-v0.45 | go-v0.41 | webrtc-direct | - | - | ✅ | 5s | 113.485 | 0.817 |
| go-v0.45 x go-v0.42 (tcp, tls, yamux) | go-v0.45 | go-v0.42 | tcp | tls | yamux | ✅ | 5s | 9.962 | 0.882 |
| go-v0.45 x go-v0.42 (tcp, noise, yamux) | go-v0.45 | go-v0.42 | tcp | noise | yamux | ✅ | 5s | 4.988 | 0.359 |
| go-v0.45 x go-v0.42 (ws, tls, yamux) | go-v0.45 | go-v0.42 | ws | tls | yamux | ✅ | 6s | 13.437 | 1.504 |
| go-v0.45 x go-v0.42 (ws, noise, yamux) | go-v0.45 | go-v0.42 | ws | noise | yamux | ✅ | 5s | 17.776 | 1.021 |
| go-v0.45 x go-v0.42 (wss, noise, yamux) | go-v0.45 | go-v0.42 | wss | noise | yamux | ✅ | 4s | 13.024 | 0.485 |
| go-v0.45 x go-v0.42 (wss, tls, yamux) | go-v0.45 | go-v0.42 | wss | tls | yamux | ✅ | 5s | 10.539 | 0.786 |
| go-v0.45 x go-v0.42 (quic-v1) | go-v0.45 | go-v0.42 | quic-v1 | - | - | ✅ | 5s | 6.188 | 0.274 |
| go-v0.45 x go-v0.42 (webtransport) | go-v0.45 | go-v0.42 | webtransport | - | - | ✅ | 4s | 23.07 | 0.597 |
| go-v0.45 x go-v0.42 (webrtc-direct) | go-v0.45 | go-v0.42 | webrtc-direct | - | - | ✅ | 5s | 216.392 | 0.444 |
| go-v0.45 x go-v0.43 (tcp, tls, yamux) | go-v0.45 | go-v0.43 | tcp | tls | yamux | ✅ | 5s | 9.707 | 0.415 |
| go-v0.45 x go-v0.43 (tcp, noise, yamux) | go-v0.45 | go-v0.43 | tcp | noise | yamux | ✅ | 4s | 9.486 | 1.028 |
| go-v0.45 x go-v0.43 (ws, tls, yamux) | go-v0.45 | go-v0.43 | ws | tls | yamux | ✅ | 4s | 13.712 | 0.52 |
| go-v0.45 x go-v0.43 (ws, noise, yamux) | go-v0.45 | go-v0.43 | ws | noise | yamux | ✅ | 4s | 13.515 | 0.615 |
| go-v0.45 x go-v0.43 (wss, tls, yamux) | go-v0.45 | go-v0.43 | wss | tls | yamux | ✅ | 4s | 22.002 | 0.729 |
| go-v0.45 x go-v0.43 (quic-v1) | go-v0.45 | go-v0.43 | quic-v1 | - | - | ✅ | 5s | 17.042 | 1.019 |
| go-v0.45 x go-v0.43 (wss, noise, yamux) | go-v0.45 | go-v0.43 | wss | noise | yamux | ✅ | 5s | 13.242 | 0.387 |
| go-v0.45 x go-v0.43 (webtransport) | go-v0.45 | go-v0.43 | webtransport | - | - | ✅ | 5s | 49.755 | 0.53 |
| go-v0.45 x go-v0.43 (webrtc-direct) | go-v0.45 | go-v0.43 | webrtc-direct | - | - | ✅ | 4s | 210.688 | 0.208 |
| go-v0.45 x go-v0.44 (tcp, tls, yamux) | go-v0.45 | go-v0.44 | tcp | tls | yamux | ✅ | 4s | 8.256 | 0.431 |
| go-v0.45 x go-v0.44 (tcp, noise, yamux) | go-v0.45 | go-v0.44 | tcp | noise | yamux | ✅ | 4s | 7.899 | 1.065 |
| go-v0.45 x go-v0.44 (ws, tls, yamux) | go-v0.45 | go-v0.44 | ws | tls | yamux | ✅ | 4s | 18.151 | 1.494 |
| go-v0.45 x go-v0.44 (ws, noise, yamux) | go-v0.45 | go-v0.44 | ws | noise | yamux | ✅ | 5s | 16.867 | 1.682 |
| go-v0.45 x go-v0.44 (wss, tls, yamux) | go-v0.45 | go-v0.44 | wss | tls | yamux | ✅ | 5s | 17.042 | 0.529 |
| go-v0.45 x go-v0.44 (quic-v1) | go-v0.45 | go-v0.44 | quic-v1 | - | - | ✅ | 5s | 16.463 | 0.481 |
| go-v0.45 x go-v0.44 (webtransport) | go-v0.45 | go-v0.44 | webtransport | - | - | ✅ | 4s | 27.184 | 0.89 |
| go-v0.45 x go-v0.44 (wss, noise, yamux) | go-v0.45 | go-v0.44 | wss | noise | yamux | ✅ | 7s | 15.313 | 1.054 |
| go-v0.45 x go-v0.44 (webrtc-direct) | go-v0.45 | go-v0.44 | webrtc-direct | - | - | ✅ | 5s | 209.988 | 0.375 |
| go-v0.45 x go-v0.45 (tcp, tls, yamux) | go-v0.45 | go-v0.45 | tcp | tls | yamux | ✅ | 5s | 5.075 | 0.406 |
| go-v0.45 x go-v0.45 (tcp, noise, yamux) | go-v0.45 | go-v0.45 | tcp | noise | yamux | ✅ | 4s | 14.14 | 0.677 |
| go-v0.45 x go-v0.45 (ws, tls, yamux) | go-v0.45 | go-v0.45 | ws | tls | yamux | ✅ | 4s | 18.432 | 1.902 |
| go-v0.45 x go-v0.45 (ws, noise, yamux) | go-v0.45 | go-v0.45 | ws | noise | yamux | ✅ | 4s | 9.463 | 0.451 |
| go-v0.45 x go-v0.45 (wss, noise, yamux) | go-v0.45 | go-v0.45 | wss | noise | yamux | ✅ | 4s | 30.314 | 2.943 |
| go-v0.45 x go-v0.45 (quic-v1) | go-v0.45 | go-v0.45 | quic-v1 | - | - | ✅ | 5s | 10.276 | 0.787 |
| go-v0.45 x go-v0.45 (webtransport) | go-v0.45 | go-v0.45 | webtransport | - | - | ✅ | 4s | 27.723 | 4.644 |
| go-v0.45 x go-v0.45 (wss, tls, yamux) | go-v0.45 | go-v0.45 | wss | tls | yamux | ✅ | 7s | 21.221 | 0.717 |
| go-v0.45 x go-v0.45 (webrtc-direct) | go-v0.45 | go-v0.45 | webrtc-direct | - | - | ✅ | 5s | 210.775 | 0.295 |
| go-v0.45 x python-v0.4 (tcp, noise, yamux) | go-v0.45 | python-v0.4 | tcp | noise | yamux | ✅ | 5s | 21.825 | 3.221 |
| go-v0.45 x python-v0.4 (ws, noise, yamux) | go-v0.45 | python-v0.4 | ws | noise | yamux | ✅ | 5s | 36.844 | 5.998 |
| go-v0.45 x python-v0.4 (wss, noise, yamux) | go-v0.45 | python-v0.4 | wss | noise | yamux | ✅ | 5s | 44.784 | 5.731 |
| go-v0.45 x python-v0.4 (quic-v1) | go-v0.45 | python-v0.4 | quic-v1 | - | - | ✅ | 5s | 85.471 | 5.72 |
| go-v0.45 x nim-v1.14 (tcp, noise, yamux) | go-v0.45 | nim-v1.14 | tcp | noise | yamux | ✅ | 4s | 207.472 | 43.548 |
| go-v0.45 x nim-v1.14 (ws, noise, yamux) | go-v0.45 | nim-v1.14 | ws | noise | yamux | ✅ | 5s | 248.255 | 43.662 |
| go-v0.45 x js-v1.x (tcp, noise, yamux) | go-v0.45 | js-v1.x | tcp | noise | yamux | ✅ | 20s | 173.364 | 19.535 |
| go-v0.45 x js-v1.x (ws, noise, yamux) | go-v0.45 | js-v1.x | ws | noise | yamux | ✅ | 20s | 176.817 | 14.66 |
| go-v0.45 x js-v2.x (tcp, noise, yamux) | go-v0.45 | js-v2.x | tcp | noise | yamux | ✅ | 21s | 139.218 | 25.206 |
| go-v0.45 x jvm-v1.2 (tcp, noise, yamux) | go-v0.45 | jvm-v1.2 | tcp | noise | yamux | ✅ | 11s | 1230.705 | 32.402 |
| go-v0.45 x js-v3.x (tcp, noise, yamux) | go-v0.45 | js-v3.x | tcp | noise | yamux | ✅ | 22s | 136.726 | 21.909 |
| go-v0.45 x js-v2.x (ws, noise, yamux) | go-v0.45 | js-v2.x | ws | noise | yamux | ✅ | 23s | 178.819 | 16.175 |
| go-v0.45 x jvm-v1.2 (tcp, tls, yamux) | go-v0.45 | jvm-v1.2 | tcp | tls | yamux | ✅ | 13s | 3419.415 | 7.617 |
| go-v0.45 x js-v3.x (ws, noise, yamux) | go-v0.45 | js-v3.x | ws | noise | yamux | ✅ | 22s | 185.641 | 17.223 |
| go-v0.45 x c-v0.0.1 (tcp, noise, yamux) | go-v0.45 | c-v0.0.1 | tcp | noise | yamux | ✅ | 6s | 120.787 | 53.476 |
| go-v0.45 x c-v0.0.1 (quic-v1) | go-v0.45 | c-v0.0.1 | quic-v1 | - | - | ✅ | 5s | 60.776 | 33.451 |
| go-v0.45 x zig-v0.0.1 (quic-v1) | go-v0.45 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 6s | - | - |
| go-v0.45 x jvm-v1.2 (ws, noise, yamux) | go-v0.45 | jvm-v1.2 | ws | noise | yamux | ✅ | 10s | 1763.538 | 113.521 |
| go-v0.45 x dotnet-v1.0 (tcp, noise, yamux) | go-v0.45 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 8s | 550.997 | 46.931 |
| go-v0.45 x jvm-v1.2 (ws, tls, yamux) | go-v0.45 | jvm-v1.2 | ws | tls | yamux | ✅ | 13s | 4316.254 | 19.354 |
| go-v0.45 x eth-p2p-z-v0.0.1 (quic-v1) | go-v0.45 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 15.604 | 1.397 |
| go-v0.45 x jvm-v1.2 (quic-v1) | go-v0.45 | jvm-v1.2 | quic-v1 | - | - | ✅ | 12s | 566.856 | 11.515 |
| python-v0.4 x rust-v0.53 (tcp, noise, mplex) | python-v0.4 | rust-v0.53 | tcp | noise | mplex | ✅ | 4s | - | - |
| python-v0.4 x rust-v0.53 (tcp, noise, yamux) | python-v0.4 | rust-v0.53 | tcp | noise | yamux | ✅ | 6s | - | - |
| python-v0.4 x rust-v0.53 (quic-v1) | python-v0.4 | rust-v0.53 | quic-v1 | - | - | ✅ | 6s | - | - |
| python-v0.4 x rust-v0.54 (tcp, noise, mplex) | python-v0.4 | rust-v0.54 | tcp | noise | mplex | ✅ | 5s | - | - |
| python-v0.4 x rust-v0.54 (tcp, noise, yamux) | python-v0.4 | rust-v0.54 | tcp | noise | yamux | ✅ | 5s | - | - |
| python-v0.4 x rust-v0.54 (quic-v1) | python-v0.4 | rust-v0.54 | quic-v1 | - | - | ✅ | 4s | - | - |
| python-v0.4 x rust-v0.55 (tcp, noise, mplex) | python-v0.4 | rust-v0.55 | tcp | noise | mplex | ✅ | 4s | - | - |
| python-v0.4 x rust-v0.55 (tcp, noise, yamux) | python-v0.4 | rust-v0.55 | tcp | noise | yamux | ✅ | 3s | - | - |
| python-v0.4 x rust-v0.53 (ws, noise, mplex) | python-v0.4 | rust-v0.53 | ws | noise | mplex | ✅ | 11s | - | - |
| python-v0.4 x rust-v0.53 (ws, noise, yamux) | python-v0.4 | rust-v0.53 | ws | noise | yamux | ✅ | 11s | - | - |
| python-v0.4 x rust-v0.54 (ws, noise, mplex) | python-v0.4 | rust-v0.54 | ws | noise | mplex | ✅ | 10s | - | - |
| python-v0.4 x rust-v0.54 (ws, noise, yamux) | python-v0.4 | rust-v0.54 | ws | noise | yamux | ✅ | 10s | - | - |
| python-v0.4 x rust-v0.55 (quic-v1) | python-v0.4 | rust-v0.55 | quic-v1 | - | - | ✅ | 5s | - | - |
| python-v0.4 x rust-v0.56 (tcp, noise, mplex) | python-v0.4 | rust-v0.56 | tcp | noise | mplex | ✅ | 5s | - | - |
| python-v0.4 x rust-v0.56 (tcp, noise, yamux) | python-v0.4 | rust-v0.56 | tcp | noise | yamux | ✅ | 5s | - | - |
| python-v0.4 x rust-v0.56 (quic-v1) | python-v0.4 | rust-v0.56 | quic-v1 | - | - | ✅ | 5s | - | - |
| python-v0.4 x go-v0.38 (tcp, noise, yamux) | python-v0.4 | go-v0.38 | tcp | noise | yamux | ✅ | 4s | - | - |
| python-v0.4 x rust-v0.55 (ws, noise, mplex) | python-v0.4 | rust-v0.55 | ws | noise | mplex | ✅ | 13s | - | - |
| python-v0.4 x go-v0.38 (quic-v1) | python-v0.4 | go-v0.38 | quic-v1 | - | - | ✅ | 4s | - | - |
| python-v0.4 x go-v0.39 (tcp, noise, yamux) | python-v0.4 | go-v0.39 | tcp | noise | yamux | ✅ | 4s | - | - |
| python-v0.4 x rust-v0.55 (ws, noise, yamux) | python-v0.4 | rust-v0.55 | ws | noise | yamux | ✅ | 15s | - | - |
| python-v0.4 x rust-v0.56 (ws, noise, mplex) | python-v0.4 | rust-v0.56 | ws | noise | mplex | ✅ | 14s | - | - |
| python-v0.4 x go-v0.39 (quic-v1) | python-v0.4 | go-v0.39 | quic-v1 | - | - | ✅ | 4s | - | - |
| python-v0.4 x rust-v0.56 (ws, noise, yamux) | python-v0.4 | rust-v0.56 | ws | noise | yamux | ✅ | 14s | - | - |
| python-v0.4 x go-v0.40 (tcp, noise, yamux) | python-v0.4 | go-v0.40 | tcp | noise | yamux | ✅ | 3s | - | - |
| python-v0.4 x go-v0.40 (quic-v1) | python-v0.4 | go-v0.40 | quic-v1 | - | - | ✅ | 3s | - | - |
| python-v0.4 x go-v0.41 (tcp, noise, yamux) | python-v0.4 | go-v0.41 | tcp | noise | yamux | ✅ | 3s | - | - |
| python-v0.4 x go-v0.38 (ws, noise, yamux) | python-v0.4 | go-v0.38 | ws | noise | yamux | ✅ | 44s | - | - |
| python-v0.4 x go-v0.38 (wss, noise, yamux) | python-v0.4 | go-v0.38 | wss | noise | yamux | ✅ | 43s | - | - |
| python-v0.4 x go-v0.41 (quic-v1) | python-v0.4 | go-v0.41 | quic-v1 | - | - | ✅ | 3s | - | - |
| python-v0.4 x go-v0.42 (tcp, noise, yamux) | python-v0.4 | go-v0.42 | tcp | noise | yamux | ✅ | 3s | - | - |
| python-v0.4 x go-v0.39 (ws, noise, yamux) | python-v0.4 | go-v0.39 | ws | noise | yamux | ✅ | 44s | - | - |
| python-v0.4 x go-v0.39 (wss, noise, yamux) | python-v0.4 | go-v0.39 | wss | noise | yamux | ✅ | 43s | - | - |
| python-v0.4 x go-v0.42 (quic-v1) | python-v0.4 | go-v0.42 | quic-v1 | - | - | ✅ | 3s | - | - |
| python-v0.4 x go-v0.43 (tcp, noise, yamux) | python-v0.4 | go-v0.43 | tcp | noise | yamux | ✅ | 4s | - | - |
| python-v0.4 x go-v0.40 (ws, noise, yamux) | python-v0.4 | go-v0.40 | ws | noise | yamux | ✅ | 44s | - | - |
| python-v0.4 x go-v0.40 (wss, noise, yamux) | python-v0.4 | go-v0.40 | wss | noise | yamux | ✅ | 44s | - | - |
| python-v0.4 x go-v0.43 (quic-v1) | python-v0.4 | go-v0.43 | quic-v1 | - | - | ✅ | 3s | - | - |
| python-v0.4 x go-v0.44 (tcp, noise, yamux) | python-v0.4 | go-v0.44 | tcp | noise | yamux | ✅ | 3s | - | - |
| python-v0.4 x go-v0.41 (ws, noise, yamux) | python-v0.4 | go-v0.41 | ws | noise | yamux | ✅ | 43s | - | - |
| python-v0.4 x go-v0.41 (wss, noise, yamux) | python-v0.4 | go-v0.41 | wss | noise | yamux | ✅ | 44s | - | - |
| python-v0.4 x go-v0.44 (quic-v1) | python-v0.4 | go-v0.44 | quic-v1 | - | - | ✅ | 3s | - | - |
| python-v0.4 x go-v0.45 (tcp, noise, yamux) | python-v0.4 | go-v0.45 | tcp | noise | yamux | ✅ | 3s | - | - |
| python-v0.4 x go-v0.42 (ws, noise, yamux) | python-v0.4 | go-v0.42 | ws | noise | yamux | ✅ | 43s | - | - |
| python-v0.4 x go-v0.42 (wss, noise, yamux) | python-v0.4 | go-v0.42 | wss | noise | yamux | ✅ | 43s | - | - |
| python-v0.4 x go-v0.45 (quic-v1) | python-v0.4 | go-v0.45 | quic-v1 | - | - | ✅ | 3s | - | - |
| python-v0.4 x python-v0.4 (tcp, noise, mplex) | python-v0.4 | python-v0.4 | tcp | noise | mplex | ✅ | 3s | - | - |
| python-v0.4 x go-v0.43 (ws, noise, yamux) | python-v0.4 | go-v0.43 | ws | noise | yamux | ✅ | 44s | - | - |
| python-v0.4 x python-v0.4 (tcp, noise, yamux) | python-v0.4 | python-v0.4 | tcp | noise | yamux | ✅ | 3s | - | - |
| python-v0.4 x go-v0.43 (wss, noise, yamux) | python-v0.4 | go-v0.43 | wss | noise | yamux | ✅ | 43s | - | - |
| python-v0.4 x python-v0.4 (ws, noise, mplex) | python-v0.4 | python-v0.4 | ws | noise | mplex | ✅ | 4s | - | - |
| python-v0.4 x python-v0.4 (ws, noise, yamux) | python-v0.4 | python-v0.4 | ws | noise | yamux | ✅ | 4s | - | - |
| python-v0.4 x python-v0.4 (wss, noise, mplex) | python-v0.4 | python-v0.4 | wss | noise | mplex | ✅ | 4s | - | - |
| python-v0.4 x python-v0.4 (wss, noise, yamux) | python-v0.4 | python-v0.4 | wss | noise | yamux | ✅ | 4s | - | - |
| python-v0.4 x go-v0.44 (ws, noise, yamux) | python-v0.4 | go-v0.44 | ws | noise | yamux | ✅ | 44s | - | - |
| python-v0.4 x python-v0.4 (quic-v1) | python-v0.4 | python-v0.4 | quic-v1 | - | - | ✅ | 4s | - | - |
| python-v0.4 x go-v0.44 (wss, noise, yamux) | python-v0.4 | go-v0.44 | wss | noise | yamux | ✅ | 45s | - | - |
| python-v0.4 x go-v0.45 (ws, noise, yamux) | python-v0.4 | go-v0.45 | ws | noise | yamux | ✅ | 44s | - | - |
| python-v0.4 x go-v0.45 (wss, noise, yamux) | python-v0.4 | go-v0.45 | wss | noise | yamux | ✅ | 44s | - | - |
| python-v0.4 x js-v1.x (tcp, noise, mplex) | python-v0.4 | js-v1.x | tcp | noise | mplex | ✅ | 15s | - | - |
| python-v0.4 x js-v1.x (tcp, noise, yamux) | python-v0.4 | js-v1.x | tcp | noise | yamux | ✅ | 17s | - | - |
| python-v0.4 x js-v2.x (tcp, noise, mplex) | python-v0.4 | js-v2.x | tcp | noise | mplex | ✅ | 17s | - | - |
| python-v0.4 x js-v2.x (tcp, noise, yamux) | python-v0.4 | js-v2.x | tcp | noise | yamux | ✅ | 18s | - | - |
| python-v0.4 x js-v3.x (tcp, noise, mplex) | python-v0.4 | js-v3.x | tcp | noise | mplex | ✅ | 12s | - | - |
| python-v0.4 x js-v1.x (ws, noise, mplex) | python-v0.4 | js-v1.x | ws | noise | mplex | ✅ | 28s | - | - |
| python-v0.4 x js-v1.x (ws, noise, yamux) | python-v0.4 | js-v1.x | ws | noise | yamux | ✅ | 29s | - | - |
| python-v0.4 x js-v3.x (tcp, noise, yamux) | python-v0.4 | js-v3.x | tcp | noise | yamux | ✅ | 12s | - | - |
| python-v0.4 x nim-v1.14 (tcp, noise, mplex) | python-v0.4 | nim-v1.14 | tcp | noise | mplex | ✅ | 4s | - | - |
| python-v0.4 x nim-v1.14 (tcp, noise, yamux) | python-v0.4 | nim-v1.14 | tcp | noise | yamux | ✅ | 3s | - | - |
| python-v0.4 x jvm-v1.2 (tcp, noise, mplex) | python-v0.4 | jvm-v1.2 | tcp | noise | mplex | ✅ | 5s | - | - |
| python-v0.4 x jvm-v1.2 (tcp, noise, yamux) | python-v0.4 | jvm-v1.2 | tcp | noise | yamux | ✅ | 4s | - | - |
| python-v0.4 x js-v2.x (ws, noise, mplex) | python-v0.4 | js-v2.x | ws | noise | mplex | ✅ | 195s | - | - |
| python-v0.4 x js-v2.x (ws, noise, yamux) | python-v0.4 | js-v2.x | ws | noise | yamux | ✅ | 195s | - | - |
| python-v0.4 x jvm-v1.2 (quic-v1) | python-v0.4 | jvm-v1.2 | quic-v1 | - | - | ✅ | 5s | - | - |
| python-v0.4 x c-v0.0.1 (tcp, noise, yamux) | python-v0.4 | c-v0.0.1 | tcp | noise | yamux | ✅ | 3s | - | - |
| python-v0.4 x js-v3.x (ws, noise, mplex) | python-v0.4 | js-v3.x | ws | noise | mplex | ✅ | 191s | - | - |
| python-v0.4 x js-v3.x (ws, noise, yamux) | python-v0.4 | js-v3.x | ws | noise | yamux | ✅ | 191s | - | - |
| python-v0.4 x nim-v1.14 (ws, noise, mplex) | python-v0.4 | nim-v1.14 | ws | noise | mplex | ✅ | 183s | - | - |
| python-v0.4 x c-v0.0.1 (quic-v1) | python-v0.4 | c-v0.0.1 | quic-v1 | - | - | ✅ | 3s | - | - |
| python-v0.4 x nim-v1.14 (ws, noise, yamux) | python-v0.4 | nim-v1.14 | ws | noise | yamux | ✅ | 183s | - | - |
| python-v0.4 x dotnet-v1.0 (tcp, noise, yamux) | python-v0.4 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 4s | - | - |
| python-v0.4 x eth-p2p-z-v0.0.1 (quic-v1) | python-v0.4 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 4s | - | - |
| python-v0.4 x jvm-v1.2 (ws, noise, mplex) | python-v0.4 | jvm-v1.2 | ws | noise | mplex | ✅ | 184s | - | - |
| js-v1.x x rust-v0.53 (tcp, noise, mplex) | js-v1.x | rust-v0.53 | tcp | noise | mplex | ✅ | 8s | 107 | 19 |
| python-v0.4 x jvm-v1.2 (ws, noise, yamux) | python-v0.4 | jvm-v1.2 | ws | noise | yamux | ✅ | 184s | - | - |
| js-v1.x x rust-v0.53 (tcp, noise, yamux) | js-v1.x | rust-v0.53 | tcp | noise | yamux | ✅ | 10s | 120 | 30 |
| js-v1.x x rust-v0.53 (ws, noise, mplex) | js-v1.x | rust-v0.53 | ws | noise | mplex | ✅ | 8s | 195 | 21 |
| js-v1.x x rust-v0.53 (ws, noise, yamux) | js-v1.x | rust-v0.53 | ws | noise | yamux | ✅ | 9s | 199 | 22 |
| js-v1.x x rust-v0.54 (tcp, noise, mplex) | js-v1.x | rust-v0.54 | tcp | noise | mplex | ✅ | 10s | 130 | 31 |
| js-v1.x x rust-v0.54 (tcp, noise, yamux) | js-v1.x | rust-v0.54 | tcp | noise | yamux | ✅ | 11s | 119 | 24 |
| js-v1.x x rust-v0.54 (ws, noise, mplex) | js-v1.x | rust-v0.54 | ws | noise | mplex | ✅ | 12s | 233 | 28 |
| js-v1.x x rust-v0.54 (ws, noise, yamux) | js-v1.x | rust-v0.54 | ws | noise | yamux | ✅ | 11s | 213 | 35 |
| js-v1.x x rust-v0.55 (tcp, noise, mplex) | js-v1.x | rust-v0.55 | tcp | noise | mplex | ✅ | 11s | 59 | 20 |
| js-v1.x x rust-v0.55 (tcp, noise, yamux) | js-v1.x | rust-v0.55 | tcp | noise | yamux | ✅ | 11s | 61 | 24 |
| python-v0.4 x c-v0.0.1 (tcp, noise, mplex) | python-v0.4 | c-v0.0.1 | tcp | noise | mplex | ✅ | 34s | - | - |
| js-v1.x x rust-v0.55 (ws, noise, mplex) | js-v1.x | rust-v0.55 | ws | noise | mplex | ✅ | 12s | 129 | 35 |
| python-v0.4 x zig-v0.0.1 (quic-v1) | python-v0.4 | zig-v0.0.1 | quic-v1 | - | - | ❌ | 36s | - | - |
| js-v1.x x rust-v0.55 (ws, noise, yamux) | js-v1.x | rust-v0.55 | ws | noise | yamux | ✅ | 14s | 96 | 23 |
| js-v1.x x rust-v0.56 (tcp, noise, mplex) | js-v1.x | rust-v0.56 | tcp | noise | mplex | ✅ | 14s | 95 | 31 |
| js-v1.x x rust-v0.56 (tcp, noise, yamux) | js-v1.x | rust-v0.56 | tcp | noise | yamux | ✅ | 14s | 95 | 37 |
| js-v1.x x rust-v0.56 (ws, noise, mplex) | js-v1.x | rust-v0.56 | ws | noise | mplex | ✅ | 14s | 66 | 21 |
| js-v1.x x rust-v0.56 (ws, noise, yamux) | js-v1.x | rust-v0.56 | ws | noise | yamux | ✅ | 13s | 74 | 18 |
| js-v1.x x go-v0.38 (tcp, noise, yamux) | js-v1.x | go-v0.38 | tcp | noise | yamux | ✅ | 13s | 56 | 16 |
| js-v1.x x go-v0.38 (ws, noise, yamux) | js-v1.x | go-v0.38 | ws | noise | yamux | ✅ | 18s | 154 | 42 |
| js-v1.x x go-v0.38 (wss, noise, yamux) | js-v1.x | go-v0.38 | wss | noise | yamux | ✅ | 17s | 219 | 53 |
| js-v1.x x go-v0.39 (tcp, noise, yamux) | js-v1.x | go-v0.39 | tcp | noise | yamux | ✅ | 17s | 108 | 37 |
| js-v1.x x go-v0.39 (ws, noise, yamux) | js-v1.x | go-v0.39 | ws | noise | yamux | ✅ | 17s | 115 | 37 |
| js-v1.x x go-v0.39 (wss, noise, yamux) | js-v1.x | go-v0.39 | wss | noise | yamux | ✅ | 17s | 124 | 14 |
| js-v1.x x go-v0.40 (tcp, noise, yamux) | js-v1.x | go-v0.40 | tcp | noise | yamux | ✅ | 17s | 66 | 22 |
| js-v1.x x go-v0.40 (ws, noise, yamux) | js-v1.x | go-v0.40 | ws | noise | yamux | ✅ | 16s | 103 | 31 |
| js-v1.x x go-v0.40 (wss, noise, yamux) | js-v1.x | go-v0.40 | wss | noise | yamux | ✅ | 16s | 110 | 20 |
| js-v1.x x go-v0.41 (tcp, noise, yamux) | js-v1.x | go-v0.41 | tcp | noise | yamux | ✅ | 16s | 127 | 50 |
| js-v1.x x go-v0.41 (ws, noise, yamux) | js-v1.x | go-v0.41 | ws | noise | yamux | ✅ | 18s | 139 | 43 |
| js-v1.x x go-v0.41 (wss, noise, yamux) | js-v1.x | go-v0.41 | wss | noise | yamux | ✅ | 18s | 216 | 42 |
| js-v1.x x go-v0.42 (tcp, noise, yamux) | js-v1.x | go-v0.42 | tcp | noise | yamux | ✅ | 19s | 110 | 42 |
| js-v1.x x go-v0.43 (tcp, noise, yamux) | js-v1.x | go-v0.43 | tcp | noise | yamux | ✅ | 17s | 73 | 24 |
| js-v1.x x go-v0.42 (wss, noise, yamux) | js-v1.x | go-v0.42 | wss | noise | yamux | ✅ | 19s | 125 | 25 |
| js-v1.x x go-v0.42 (ws, noise, yamux) | js-v1.x | go-v0.42 | ws | noise | yamux | ✅ | 19s | 101 | 26 |
| js-v1.x x go-v0.43 (ws, noise, yamux) | js-v1.x | go-v0.43 | ws | noise | yamux | ✅ | 17s | 48 | 14 |
| js-v1.x x go-v0.43 (wss, noise, yamux) | js-v1.x | go-v0.43 | wss | noise | yamux | ✅ | 19s | 273 | 62 |
| js-v1.x x go-v0.44 (tcp, noise, yamux) | js-v1.x | go-v0.44 | tcp | noise | yamux | ✅ | 19s | 132 | 49 |
| js-v1.x x go-v0.44 (ws, noise, yamux) | js-v1.x | go-v0.44 | ws | noise | yamux | ✅ | 19s | 168 | 35 |
| js-v1.x x go-v0.45 (tcp, noise, yamux) | js-v1.x | go-v0.45 | tcp | noise | yamux | ✅ | 18s | 101 | 35 |
| js-v1.x x go-v0.45 (ws, noise, yamux) | js-v1.x | go-v0.45 | ws | noise | yamux | ✅ | 19s | 97 | 35 |
| js-v1.x x go-v0.44 (wss, noise, yamux) | js-v1.x | go-v0.44 | wss | noise | yamux | ✅ | 20s | 148 | 22 |
| js-v1.x x go-v0.45 (wss, noise, yamux) | js-v1.x | go-v0.45 | wss | noise | yamux | ✅ | 20s | 153 | 20 |
| js-v1.x x python-v0.4 (tcp, noise, mplex) | js-v1.x | python-v0.4 | tcp | noise | mplex | ✅ | 19s | 73 | 24 |
| js-v1.x x python-v0.4 (tcp, noise, yamux) | js-v1.x | python-v0.4 | tcp | noise | yamux | ✅ | 22s | 169 | 62 |
| js-v1.x x python-v0.4 (ws, noise, yamux) | js-v1.x | python-v0.4 | ws | noise | yamux | ✅ | 22s | 262 | 70 |
| js-v1.x x python-v0.4 (ws, noise, mplex) | js-v1.x | python-v0.4 | ws | noise | mplex | ✅ | 24s | 266 | 58 |
| js-v1.x x python-v0.4 (wss, noise, mplex) | js-v1.x | python-v0.4 | wss | noise | mplex | ✅ | 25s | 358 | 51 |
| js-v1.x x python-v0.4 (wss, noise, yamux) | js-v1.x | python-v0.4 | wss | noise | yamux | ✅ | 24s | 286 | 74 |
| js-v1.x x js-v1.x (tcp, noise, mplex) | js-v1.x | js-v1.x | tcp | noise | mplex | ✅ | 25s | 218 | 67 |
| js-v1.x x js-v1.x (tcp, noise, yamux) | js-v1.x | js-v1.x | tcp | noise | yamux | ✅ | 24s | 128 | 40 |
| js-v1.x x js-v1.x (ws, noise, mplex) | js-v1.x | js-v1.x | ws | noise | mplex | ✅ | 25s | 148 | 59 |
| js-v1.x x js-v1.x (ws, noise, yamux) | js-v1.x | js-v1.x | ws | noise | yamux | ✅ | 33s | 399 | 111 |
| js-v1.x x js-v2.x (tcp, noise, yamux) | js-v1.x | js-v2.x | tcp | noise | yamux | ✅ | 35s | 304 | 105 |
| js-v1.x x js-v2.x (tcp, noise, mplex) | js-v1.x | js-v2.x | tcp | noise | mplex | ✅ | 36s | 302 | 95 |
| js-v1.x x js-v2.x (ws, noise, yamux) | js-v1.x | js-v2.x | ws | noise | yamux | ✅ | 35s | 318 | 118 |
| js-v1.x x js-v3.x (tcp, noise, mplex) | js-v1.x | js-v3.x | tcp | noise | mplex | ✅ | 35s | 247 | 79 |
| js-v1.x x js-v2.x (ws, noise, mplex) | js-v1.x | js-v2.x | ws | noise | mplex | ✅ | 38s | 259 | 79 |
| js-v1.x x js-v3.x (ws, noise, mplex) | js-v1.x | js-v3.x | ws | noise | mplex | ✅ | 33s | 122 | 27 |
| js-v1.x x js-v3.x (tcp, noise, yamux) | js-v1.x | js-v3.x | tcp | noise | yamux | ✅ | 35s | 117 | 32 |
| js-v1.x x js-v3.x (ws, noise, yamux) | js-v1.x | js-v3.x | ws | noise | yamux | ✅ | 25s | 251 | 85 |
| js-v1.x x nim-v1.14 (tcp, noise, mplex) | js-v1.x | nim-v1.14 | tcp | noise | mplex | ✅ | 24s | 238 | 36 |
| js-v1.x x nim-v1.14 (tcp, noise, yamux) | js-v1.x | nim-v1.14 | tcp | noise | yamux | ✅ | 24s | 239 | 46 |
| js-v1.x x nim-v1.14 (ws, noise, mplex) | js-v1.x | nim-v1.14 | ws | noise | mplex | ✅ | 24s | 294 | 36 |
| js-v1.x x nim-v1.14 (ws, noise, yamux) | js-v1.x | nim-v1.14 | ws | noise | yamux | ✅ | 23s | 272 | 31 |
| js-v1.x x jvm-v1.2 (tcp, noise, mplex) | js-v1.x | jvm-v1.2 | tcp | noise | mplex | ✅ | 24s | 644 | 62 |
| js-v1.x x jvm-v1.2 (tcp, noise, yamux) | js-v1.x | jvm-v1.2 | tcp | noise | yamux | ✅ | 24s | 788 | 148 |
| js-v1.x x jvm-v1.2 (ws, noise, mplex) | js-v1.x | jvm-v1.2 | ws | noise | mplex | ❌ | 28s | - | - |
| js-v1.x x c-v0.0.1 (tcp, noise, mplex) | js-v1.x | c-v0.0.1 | tcp | noise | mplex | ✅ | 19s | 102 | 21 |
| js-v1.x x c-v0.0.1 (tcp, noise, yamux) | js-v1.x | c-v0.0.1 | tcp | noise | yamux | ✅ | 19s | 170 | 79 |
| js-v1.x x dotnet-v1.0 (tcp, noise, yamux) | js-v1.x | dotnet-v1.0 | tcp | noise | yamux | ✅ | 20s | 354 | 129 |
| js-v2.x x rust-v0.53 (tcp, noise, mplex) | js-v2.x | rust-v0.53 | tcp | noise | mplex | ✅ | 21s | 202 | 53 |
| js-v1.x x jvm-v1.2 (ws, noise, yamux) | js-v1.x | jvm-v1.2 | ws | noise | yamux | ❌ | 25s | - | - |
| js-v2.x x rust-v0.53 (tcp, noise, yamux) | js-v2.x | rust-v0.53 | tcp | noise | yamux | ✅ | 20s | 184 | 39 |
| js-v2.x x rust-v0.53 (ws, noise, mplex) | js-v2.x | rust-v0.53 | ws | noise | mplex | ✅ | 21s | 250 | 30 |
| js-v2.x x rust-v0.53 (ws, noise, yamux) | js-v2.x | rust-v0.53 | ws | noise | yamux | ✅ | 18s | 292 | 51 |
| js-v2.x x rust-v0.54 (tcp, noise, mplex) | js-v2.x | rust-v0.54 | tcp | noise | mplex | ✅ | 21s | 195 | 52 |
| js-v2.x x rust-v0.54 (tcp, noise, yamux) | js-v2.x | rust-v0.54 | tcp | noise | yamux | ✅ | 22s | 221 | 61 |
| js-v2.x x rust-v0.54 (ws, noise, mplex) | js-v2.x | rust-v0.54 | ws | noise | mplex | ✅ | 22s | 338 | 105 |
| js-v2.x x rust-v0.54 (ws, noise, yamux) | js-v2.x | rust-v0.54 | ws | noise | yamux | ✅ | 22s | 352 | 106 |
| js-v2.x x rust-v0.55 (tcp, noise, mplex) | js-v2.x | rust-v0.55 | tcp | noise | mplex | ✅ | 22s | 169 | 62 |
| js-v2.x x rust-v0.55 (tcp, noise, yamux) | js-v2.x | rust-v0.55 | tcp | noise | yamux | ✅ | 21s | 117 | 48 |
| js-v2.x x rust-v0.55 (ws, noise, mplex) | js-v2.x | rust-v0.55 | ws | noise | mplex | ✅ | 21s | 121 | 32 |
| js-v2.x x rust-v0.55 (ws, noise, yamux) | js-v2.x | rust-v0.55 | ws | noise | yamux | ✅ | 20s | 140 | 50 |
| js-v2.x x rust-v0.56 (tcp, noise, mplex) | js-v2.x | rust-v0.56 | tcp | noise | mplex | ✅ | 23s | 158 | 63 |
| js-v2.x x rust-v0.56 (tcp, noise, yamux) | js-v2.x | rust-v0.56 | tcp | noise | yamux | ✅ | 22s | 172 | 58 |
| js-v2.x x rust-v0.56 (ws, noise, mplex) | js-v2.x | rust-v0.56 | ws | noise | mplex | ✅ | 22s | 153 | 40 |
| js-v2.x x rust-v0.56 (ws, noise, yamux) | js-v2.x | rust-v0.56 | ws | noise | yamux | ✅ | 22s | 153 | 49 |
| js-v2.x x go-v0.38 (tcp, noise, yamux) | js-v2.x | go-v0.38 | tcp | noise | yamux | ✅ | 22s | 140 | 58 |
| js-v2.x x go-v0.38 (wss, noise, yamux) | js-v2.x | go-v0.38 | wss | noise | yamux | ✅ | 22s | 198 | 42 |
| js-v2.x x go-v0.38 (ws, noise, yamux) | js-v2.x | go-v0.38 | ws | noise | yamux | ✅ | 22s | 105 | 36 |
| js-v2.x x go-v0.39 (tcp, noise, yamux) | js-v2.x | go-v0.39 | tcp | noise | yamux | ✅ | 20s | 75 | 25 |
| js-v2.x x go-v0.39 (ws, noise, yamux) | js-v2.x | go-v0.39 | ws | noise | yamux | ✅ | 21s | 202 | 59 |
| js-v2.x x go-v0.39 (wss, noise, yamux) | js-v2.x | go-v0.39 | wss | noise | yamux | ✅ | 22s | 303 | 61 |
| js-v2.x x go-v0.40 (tcp, noise, yamux) | js-v2.x | go-v0.40 | tcp | noise | yamux | ✅ | 22s | 172 | 67 |
| js-v2.x x go-v0.40 (ws, noise, yamux) | js-v2.x | go-v0.40 | ws | noise | yamux | ✅ | 23s | 136 | 34 |
| js-v2.x x go-v0.40 (wss, noise, yamux) | js-v2.x | go-v0.40 | wss | noise | yamux | ✅ | 22s | 247 | 54 |
| js-v2.x x go-v0.41 (tcp, noise, yamux) | js-v2.x | go-v0.41 | tcp | noise | yamux | ✅ | 23s | 133 | 49 |
| js-v2.x x go-v0.41 (ws, noise, yamux) | js-v2.x | go-v0.41 | ws | noise | yamux | ✅ | 22s | 130 | 45 |
| js-v2.x x go-v0.41 (wss, noise, yamux) | js-v2.x | go-v0.41 | wss | noise | yamux | ✅ | 22s | 189 | 44 |
| js-v2.x x go-v0.42 (tcp, noise, yamux) | js-v2.x | go-v0.42 | tcp | noise | yamux | ✅ | 22s | 160 | 58 |
| js-v2.x x go-v0.42 (ws, noise, yamux) | js-v2.x | go-v0.42 | ws | noise | yamux | ✅ | 22s | 192 | 63 |
| js-v2.x x go-v0.42 (wss, noise, yamux) | js-v2.x | go-v0.42 | wss | noise | yamux | ✅ | 23s | 275 | 55 |
| js-v2.x x go-v0.43 (tcp, noise, yamux) | js-v2.x | go-v0.43 | tcp | noise | yamux | ✅ | 23s | 143 | 60 |
| js-v2.x x go-v0.43 (ws, noise, yamux) | js-v2.x | go-v0.43 | ws | noise | yamux | ✅ | 23s | 175 | 56 |
| js-v2.x x go-v0.43 (wss, noise, yamux) | js-v2.x | go-v0.43 | wss | noise | yamux | ✅ | 23s | 199 | 44 |
| js-v2.x x go-v0.44 (tcp, noise, yamux) | js-v2.x | go-v0.44 | tcp | noise | yamux | ✅ | 22s | 118 | 38 |
| js-v2.x x go-v0.44 (ws, noise, yamux) | js-v2.x | go-v0.44 | ws | noise | yamux | ✅ | 22s | 75 | 24 |
| js-v2.x x go-v0.44 (wss, noise, yamux) | js-v2.x | go-v0.44 | wss | noise | yamux | ✅ | 22s | 264 | 63 |
| js-v2.x x go-v0.45 (tcp, noise, yamux) | js-v2.x | go-v0.45 | tcp | noise | yamux | ✅ | 23s | 182 | 80 |
| js-v2.x x go-v0.45 (ws, noise, yamux) | js-v2.x | go-v0.45 | ws | noise | yamux | ✅ | 23s | 164 | 51 |
| js-v2.x x go-v0.45 (wss, noise, yamux) | js-v2.x | go-v0.45 | wss | noise | yamux | ✅ | 23s | 252 | 46 |
| js-v2.x x python-v0.4 (tcp, noise, mplex) | js-v2.x | python-v0.4 | tcp | noise | mplex | ✅ | 23s | 121 | 44 |
| js-v2.x x python-v0.4 (tcp, noise, yamux) | js-v2.x | python-v0.4 | tcp | noise | yamux | ✅ | 23s | 121 | 53 |
| js-v2.x x python-v0.4 (ws, noise, mplex) | js-v2.x | python-v0.4 | ws | noise | mplex | ✅ | 22s | 139 | 35 |
| js-v2.x x python-v0.4 (ws, noise, yamux) | js-v2.x | python-v0.4 | ws | noise | yamux | ✅ | 23s | 115 | 49 |
| js-v2.x x python-v0.4 (wss, noise, mplex) | js-v2.x | python-v0.4 | wss | noise | mplex | ✅ | 34s | 444 | 75 |
| js-v2.x x python-v0.4 (wss, noise, yamux) | js-v2.x | python-v0.4 | wss | noise | yamux | ✅ | 35s | 402 | 71 |
| js-v2.x x js-v1.x (tcp, noise, yamux) | js-v2.x | js-v1.x | tcp | noise | yamux | ✅ | 36s | 272 | 105 |
| js-v2.x x js-v1.x (tcp, noise, mplex) | js-v2.x | js-v1.x | tcp | noise | mplex | ✅ | 37s | 234 | 73 |
| js-v2.x x js-v1.x (ws, noise, mplex) | js-v2.x | js-v1.x | ws | noise | mplex | ✅ | 36s | 289 | 112 |
| js-v2.x x js-v1.x (ws, noise, yamux) | js-v2.x | js-v1.x | ws | noise | yamux | ✅ | 35s | 294 | 101 |
| js-v2.x x js-v2.x (tcp, noise, yamux) | js-v2.x | js-v2.x | tcp | noise | yamux | ✅ | 35s | 135 | 48 |
| js-v2.x x js-v2.x (tcp, noise, mplex) | js-v2.x | js-v2.x | tcp | noise | mplex | ✅ | 36s | 127 | 52 |
| js-v2.x x js-v2.x (ws, noise, mplex) | js-v2.x | js-v2.x | ws | noise | mplex | ✅ | 37s | 310 | 71 |
| js-v2.x x js-v2.x (ws, noise, yamux) | js-v2.x | js-v2.x | ws | noise | yamux | ✅ | 36s | 505 | 249 |
| js-v2.x x js-v3.x (tcp, noise, mplex) | js-v2.x | js-v3.x | tcp | noise | mplex | ✅ | 37s | 257 | 77 |
| js-v2.x x js-v3.x (tcp, noise, yamux) | js-v2.x | js-v3.x | tcp | noise | yamux | ✅ | 36s | 194 | 89 |
| js-v2.x x js-v3.x (ws, noise, mplex) | js-v2.x | js-v3.x | ws | noise | mplex | ✅ | 37s | 188 | 47 |
| js-v2.x x js-v3.x (ws, noise, yamux) | js-v2.x | js-v3.x | ws | noise | yamux | ✅ | 36s | 198 | 68 |
| js-v2.x x nim-v1.14 (tcp, noise, mplex) | js-v2.x | nim-v1.14 | tcp | noise | mplex | ✅ | 36s | 199 | 28 |
| js-v2.x x nim-v1.14 (tcp, noise, yamux) | js-v2.x | nim-v1.14 | tcp | noise | yamux | ✅ | 35s | 185 | 26 |
| js-v2.x x nim-v1.14 (ws, noise, mplex) | js-v2.x | nim-v1.14 | ws | noise | mplex | ✅ | 26s | 343 | 49 |
| js-v2.x x nim-v1.14 (ws, noise, yamux) | js-v2.x | nim-v1.14 | ws | noise | yamux | ✅ | 26s | 327 | 62 |
| js-v2.x x jvm-v1.2 (tcp, noise, mplex) | js-v2.x | jvm-v1.2 | tcp | noise | mplex | ✅ | 27s | 1117 | 135 |
| js-v2.x x jvm-v1.2 (tcp, noise, yamux) | js-v2.x | jvm-v1.2 | tcp | noise | yamux | ✅ | 27s | 1172 | 133 |
| js-v2.x x c-v0.0.1 (tcp, noise, mplex) | js-v2.x | c-v0.0.1 | tcp | noise | mplex | ✅ | 27s | 119 | 17 |
| js-v2.x x c-v0.0.1 (tcp, noise, yamux) | js-v2.x | c-v0.0.1 | tcp | noise | yamux | ✅ | 25s | 170 | 89 |
| js-v2.x x jvm-v1.2 (ws, noise, yamux) | js-v2.x | jvm-v1.2 | ws | noise | yamux | ✅ | 28s | 1608 | 168 |
| js-v2.x x jvm-v1.2 (ws, noise, mplex) | js-v2.x | jvm-v1.2 | ws | noise | mplex | ✅ | 29s | 1511 | 145 |
| js-v3.x x rust-v0.53 (tcp, noise, mplex) | js-v3.x | rust-v0.53 | tcp | noise | mplex | ✅ | 21s | 204 | 1 |
| js-v2.x x dotnet-v1.0 (tcp, noise, yamux) | js-v2.x | dotnet-v1.0 | tcp | noise | yamux | ✅ | 22s | 392 | 94 |
| js-v3.x x rust-v0.53 (tcp, noise, yamux) | js-v3.x | rust-v0.53 | tcp | noise | yamux | ✅ | 22s | 185 | 5 |
| js-v3.x x rust-v0.53 (ws, noise, mplex) | js-v3.x | rust-v0.53 | ws | noise | mplex | ✅ | 22s | 215 | 5 |
| js-v3.x x rust-v0.53 (ws, noise, yamux) | js-v3.x | rust-v0.53 | ws | noise | yamux | ✅ | 22s | 207 | 4 |
| js-v3.x x rust-v0.54 (tcp, noise, mplex) | js-v3.x | rust-v0.54 | tcp | noise | mplex | ✅ | 22s | 168 | 6 |
| js-v3.x x rust-v0.54 (tcp, noise, yamux) | js-v3.x | rust-v0.54 | tcp | noise | yamux | ✅ | 21s | 143 | 3 |
| js-v3.x x rust-v0.54 (ws, noise, mplex) | js-v3.x | rust-v0.54 | ws | noise | mplex | ✅ | 21s | 225 | 5 |
| js-v3.x x rust-v0.54 (ws, noise, yamux) | js-v3.x | rust-v0.54 | ws | noise | yamux | ✅ | 20s | 274 | 7 |
| js-v3.x x rust-v0.55 (tcp, noise, mplex) | js-v3.x | rust-v0.55 | tcp | noise | mplex | ✅ | 22s | 141 | 4 |
| js-v3.x x rust-v0.55 (tcp, noise, yamux) | js-v3.x | rust-v0.55 | tcp | noise | yamux | ✅ | 22s | 110 | 20 |
| js-v3.x x rust-v0.55 (ws, noise, mplex) | js-v3.x | rust-v0.55 | ws | noise | mplex | ✅ | 22s | 134 | 16 |
| js-v3.x x rust-v0.55 (ws, noise, yamux) | js-v3.x | rust-v0.55 | ws | noise | yamux | ✅ | 21s | 128 | 16 |
| js-v3.x x rust-v0.56 (tcp, noise, mplex) | js-v3.x | rust-v0.56 | tcp | noise | mplex | ✅ | 22s | 118 | 2 |
| js-v3.x x rust-v0.56 (tcp, noise, yamux) | js-v3.x | rust-v0.56 | tcp | noise | yamux | ✅ | 21s | 80 | 10 |
| js-v3.x x rust-v0.56 (ws, noise, mplex) | js-v3.x | rust-v0.56 | ws | noise | mplex | ✅ | 21s | 94 | 13 |
| js-v3.x x rust-v0.56 (ws, noise, yamux) | js-v3.x | rust-v0.56 | ws | noise | yamux | ✅ | 22s | 162 | 5 |
| js-v3.x x go-v0.38 (tcp, noise, yamux) | js-v3.x | go-v0.38 | tcp | noise | yamux | ✅ | 22s | 126 | 14 |
| js-v3.x x go-v0.38 (ws, noise, yamux) | js-v3.x | go-v0.38 | ws | noise | yamux | ✅ | 22s | 153 | 14 |
| js-v3.x x go-v0.38 (wss, noise, yamux) | js-v3.x | go-v0.38 | wss | noise | yamux | ✅ | 22s | 233 | 36 |
| js-v3.x x go-v0.39 (tcp, noise, yamux) | js-v3.x | go-v0.39 | tcp | noise | yamux | ✅ | 22s | 111 | 11 |
| js-v3.x x go-v0.39 (ws, noise, yamux) | js-v3.x | go-v0.39 | ws | noise | yamux | ✅ | 22s | 110 | 14 |
| js-v3.x x go-v0.39 (wss, noise, yamux) | js-v3.x | go-v0.39 | wss | noise | yamux | ✅ | 22s | 198 | 31 |
| js-v3.x x go-v0.40 (tcp, noise, yamux) | js-v3.x | go-v0.40 | tcp | noise | yamux | ✅ | 21s | 74 | 7 |
| js-v3.x x go-v0.40 (ws, noise, yamux) | js-v3.x | go-v0.40 | ws | noise | yamux | ✅ | 22s | 178 | 19 |
| js-v3.x x go-v0.41 (tcp, noise, yamux) | js-v3.x | go-v0.41 | tcp | noise | yamux | ✅ | 22s | 148 | 1 |
| js-v3.x x go-v0.40 (wss, noise, yamux) | js-v3.x | go-v0.40 | wss | noise | yamux | ✅ | 22s | 230 | 32 |
| js-v3.x x go-v0.41 (ws, noise, yamux) | js-v3.x | go-v0.41 | ws | noise | yamux | ✅ | 22s | 117 | 11 |
| js-v3.x x go-v0.41 (wss, noise, yamux) | js-v3.x | go-v0.41 | wss | noise | yamux | ✅ | 22s | 212 | 18 |
| js-v3.x x go-v0.42 (tcp, noise, yamux) | js-v3.x | go-v0.42 | tcp | noise | yamux | ✅ | 22s | 110 | 10 |
| js-v3.x x go-v0.42 (ws, noise, yamux) | js-v3.x | go-v0.42 | ws | noise | yamux | ✅ | 22s | 115 | 11 |
| js-v3.x x go-v0.42 (wss, noise, yamux) | js-v3.x | go-v0.42 | wss | noise | yamux | ✅ | 22s | 158 | 24 |
| js-v3.x x go-v0.43 (tcp, noise, yamux) | js-v3.x | go-v0.43 | tcp | noise | yamux | ✅ | 21s | 132 | 18 |
| js-v3.x x go-v0.43 (ws, noise, yamux) | js-v3.x | go-v0.43 | ws | noise | yamux | ✅ | 22s | 153 | 15 |
| js-v3.x x go-v0.43 (wss, noise, yamux) | js-v3.x | go-v0.43 | wss | noise | yamux | ✅ | 21s | 219 | 32 |
| js-v3.x x go-v0.44 (tcp, noise, yamux) | js-v3.x | go-v0.44 | tcp | noise | yamux | ✅ | 22s | 129 | 15 |
| js-v3.x x go-v0.44 (wss, noise, yamux) | js-v3.x | go-v0.44 | wss | noise | yamux | ✅ | 22s | 222 | 32 |
| js-v3.x x go-v0.44 (ws, noise, yamux) | js-v3.x | go-v0.44 | ws | noise | yamux | ✅ | 23s | 145 | 16 |
| js-v3.x x go-v0.45 (tcp, noise, yamux) | js-v3.x | go-v0.45 | tcp | noise | yamux | ✅ | 22s | 84 | 8 |
| js-v3.x x go-v0.45 (ws, noise, yamux) | js-v3.x | go-v0.45 | ws | noise | yamux | ✅ | 21s | 100 | 12 |
| js-v3.x x python-v0.4 (tcp, noise, yamux) | js-v3.x | python-v0.4 | tcp | noise | yamux | ✅ | 24s | 158 | 3 |
| js-v3.x x go-v0.45 (wss, noise, yamux) | js-v3.x | go-v0.45 | wss | noise | yamux | ✅ | 26s | 237 | 32 |
| js-v3.x x python-v0.4 (tcp, noise, mplex) | js-v3.x | python-v0.4 | tcp | noise | mplex | ✅ | 25s | 156 | 13 |
| js-v3.x x python-v0.4 (ws, noise, yamux) | js-v3.x | python-v0.4 | ws | noise | yamux | ✅ | 24s | 133 | 4 |
| js-v3.x x python-v0.4 (ws, noise, mplex) | js-v3.x | python-v0.4 | ws | noise | mplex | ✅ | 25s | 159 | 10 |
| js-v3.x x python-v0.4 (wss, noise, mplex) | js-v3.x | python-v0.4 | wss | noise | mplex | ✅ | 25s | 231 | 4 |
| js-v3.x x python-v0.4 (wss, noise, yamux) | js-v3.x | python-v0.4 | wss | noise | yamux | ✅ | 25s | 227 | 6 |
| js-v3.x x js-v1.x (tcp, noise, mplex) | js-v3.x | js-v1.x | tcp | noise | mplex | ✅ | 24s | 139 | 11 |
| js-v3.x x js-v1.x (tcp, noise, yamux) | js-v3.x | js-v1.x | tcp | noise | yamux | ✅ | 38s | 258 | 19 |
| js-v3.x x js-v1.x (ws, noise, yamux) | js-v3.x | js-v1.x | ws | noise | yamux | ✅ | 38s | 343 | 15 |
| js-v3.x x js-v1.x (ws, noise, mplex) | js-v3.x | js-v1.x | ws | noise | mplex | ✅ | 39s | 303 | 10 |
| js-v3.x x js-v2.x (tcp, noise, mplex) | js-v3.x | js-v2.x | tcp | noise | mplex | ✅ | 39s | 243 | 20 |
| js-v3.x x js-v2.x (tcp, noise, yamux) | js-v3.x | js-v2.x | tcp | noise | yamux | ✅ | 41s | 204 | 25 |
| js-v3.x x js-v2.x (ws, noise, mplex) | js-v3.x | js-v2.x | ws | noise | mplex | ✅ | 40s | 277 | 5 |
| js-v3.x x js-v3.x (tcp, noise, mplex) | js-v3.x | js-v3.x | tcp | noise | mplex | ✅ | 38s | 106 | 6 |
| js-v3.x x js-v2.x (ws, noise, yamux) | js-v3.x | js-v2.x | ws | noise | yamux | ✅ | 40s | 157 | 3 |
| js-v3.x x js-v3.x (tcp, noise, yamux) | js-v3.x | js-v3.x | tcp | noise | yamux | ✅ | 29s | 249 | 4 |
| js-v3.x x js-v3.x (ws, noise, mplex) | js-v3.x | js-v3.x | ws | noise | mplex | ✅ | 29s | 266 | 5 |
| js-v3.x x js-v3.x (ws, noise, yamux) | js-v3.x | js-v3.x | ws | noise | yamux | ✅ | 29s | 209 | 10 |
| js-v3.x x nim-v1.14 (tcp, noise, mplex) | js-v3.x | nim-v1.14 | tcp | noise | mplex | ✅ | 29s | 234 | 9 |
| js-v3.x x nim-v1.14 (tcp, noise, yamux) | js-v3.x | nim-v1.14 | tcp | noise | yamux | ✅ | 29s | 218 | 4 |
| js-v3.x x nim-v1.14 (ws, noise, mplex) | js-v3.x | nim-v1.14 | ws | noise | mplex | ✅ | 29s | 255 | 8 |
| js-v3.x x nim-v1.14 (ws, noise, yamux) | js-v3.x | nim-v1.14 | ws | noise | yamux | ✅ | 28s | 263 | 6 |
| js-v3.x x jvm-v1.2 (tcp, noise, mplex) | js-v3.x | jvm-v1.2 | tcp | noise | mplex | ✅ | 29s | 897 | 3 |
| nim-v1.14 x rust-v0.53 (tcp, noise, mplex) | nim-v1.14 | rust-v0.53 | tcp | noise | mplex | ✅ | 6s | 287.0 | 3.0 |
| nim-v1.14 x rust-v0.53 (tcp, noise, yamux) | nim-v1.14 | rust-v0.53 | tcp | noise | yamux | ✅ | 5s | 324.0 | 0.0 |
| nim-v1.14 x rust-v0.53 (ws, noise, mplex) | nim-v1.14 | rust-v0.53 | ws | noise | mplex | ✅ | 5s | 469.0 | 43.0 |
| nim-v1.14 x rust-v0.53 (ws, noise, yamux) | nim-v1.14 | rust-v0.53 | ws | noise | yamux | ✅ | 6s | 448.0 | 47.0 |
| js-v3.x x jvm-v1.2 (tcp, noise, yamux) | js-v3.x | jvm-v1.2 | tcp | noise | yamux | ✅ | 24s | 1260 | 17 |
| js-v3.x x jvm-v1.2 (ws, noise, mplex) | js-v3.x | jvm-v1.2 | ws | noise | mplex | ✅ | 24s | 1577 | 9 |
| js-v3.x x c-v0.0.1 (tcp, noise, mplex) | js-v3.x | c-v0.0.1 | tcp | noise | mplex | ✅ | 23s | 113 | 2 |
| js-v3.x x jvm-v1.2 (ws, noise, yamux) | js-v3.x | jvm-v1.2 | ws | noise | yamux | ✅ | 24s | 1251 | 52 |
| js-v3.x x c-v0.0.1 (tcp, noise, yamux) | js-v3.x | c-v0.0.1 | tcp | noise | yamux | ✅ | 22s | 147 | 6 |
| js-v3.x x dotnet-v1.0 (tcp, noise, yamux) | js-v3.x | dotnet-v1.0 | tcp | noise | yamux | ✅ | 21s | 316 | 11 |
| nim-v1.14 x rust-v0.54 (tcp, noise, mplex) | nim-v1.14 | rust-v0.54 | tcp | noise | mplex | ✅ | 6s | 322.0 | 0.0 |
| nim-v1.14 x rust-v0.54 (tcp, noise, yamux) | nim-v1.14 | rust-v0.54 | tcp | noise | yamux | ✅ | 5s | 319.0 | 0.0 |
| nim-v1.14 x rust-v0.54 (ws, noise, mplex) | nim-v1.14 | rust-v0.54 | ws | noise | mplex | ✅ | 4s | 454.0 | 43.0 |
| nim-v1.14 x rust-v0.54 (ws, noise, yamux) | nim-v1.14 | rust-v0.54 | ws | noise | yamux | ✅ | 5s | 453.0 | 43.0 |
| nim-v1.14 x rust-v0.55 (tcp, noise, mplex) | nim-v1.14 | rust-v0.55 | tcp | noise | mplex | ✅ | 5s | 184.0 | 43.0 |
| nim-v1.14 x rust-v0.55 (tcp, noise, yamux) | nim-v1.14 | rust-v0.55 | tcp | noise | yamux | ✅ | 5s | 192.0 | 46.0 |
| nim-v1.14 x rust-v0.55 (ws, noise, mplex) | nim-v1.14 | rust-v0.55 | ws | noise | mplex | ✅ | 4s | 187.0 | 0.0 |
| nim-v1.14 x rust-v0.55 (ws, noise, yamux) | nim-v1.14 | rust-v0.55 | ws | noise | yamux | ✅ | 4s | 191.0 | 46.0 |
| nim-v1.14 x rust-v0.56 (tcp, noise, mplex) | nim-v1.14 | rust-v0.56 | tcp | noise | mplex | ✅ | 5s | 185.0 | 0.0 |
| nim-v1.14 x rust-v0.56 (tcp, noise, yamux) | nim-v1.14 | rust-v0.56 | tcp | noise | yamux | ✅ | 4s | 188.0 | 0.0 |
| nim-v1.14 x rust-v0.56 (ws, noise, yamux) | nim-v1.14 | rust-v0.56 | ws | noise | yamux | ✅ | 4s | 195.0 | 0.0 |
| nim-v1.14 x rust-v0.56 (ws, noise, mplex) | nim-v1.14 | rust-v0.56 | ws | noise | mplex | ✅ | 5s | 186.0 | 0.0 |
| nim-v1.14 x go-v0.38 (tcp, noise, yamux) | nim-v1.14 | go-v0.38 | tcp | noise | yamux | ✅ | 5s | 207.0 | 0.0 |
| nim-v1.14 x go-v0.38 (ws, noise, yamux) | nim-v1.14 | go-v0.38 | ws | noise | yamux | ✅ | 4s | 239.0 | 0.0 |
| nim-v1.14 x go-v0.39 (tcp, noise, yamux) | nim-v1.14 | go-v0.39 | tcp | noise | yamux | ✅ | 5s | 141.0 | 0.0 |
| nim-v1.14 x go-v0.39 (ws, noise, yamux) | nim-v1.14 | go-v0.39 | ws | noise | yamux | ✅ | 5s | 262.0 | 4.0 |
| nim-v1.14 x go-v0.40 (tcp, noise, yamux) | nim-v1.14 | go-v0.40 | tcp | noise | yamux | ✅ | 4s | 203.0 | 2.0 |
| nim-v1.14 x go-v0.40 (ws, noise, yamux) | nim-v1.14 | go-v0.40 | ws | noise | yamux | ✅ | 5s | 237.0 | 0.0 |
| nim-v1.14 x go-v0.41 (tcp, noise, yamux) | nim-v1.14 | go-v0.41 | tcp | noise | yamux | ✅ | 4s | 205.0 | 0.0 |
| nim-v1.14 x go-v0.41 (ws, noise, yamux) | nim-v1.14 | go-v0.41 | ws | noise | yamux | ✅ | 5s | 211.0 | 0.0 |
| nim-v1.14 x go-v0.42 (ws, noise, yamux) | nim-v1.14 | go-v0.42 | ws | noise | yamux | ✅ | 4s | 190.0 | 0.0 |
| nim-v1.14 x go-v0.42 (tcp, noise, yamux) | nim-v1.14 | go-v0.42 | tcp | noise | yamux | ✅ | 6s | 196.0 | 0.0 |
| nim-v1.14 x go-v0.43 (tcp, noise, yamux) | nim-v1.14 | go-v0.43 | tcp | noise | yamux | ✅ | 5s | 190.0 | 0.0 |
| nim-v1.14 x go-v0.43 (ws, noise, yamux) | nim-v1.14 | go-v0.43 | ws | noise | yamux | ✅ | 5s | 191.0 | 0.0 |
| nim-v1.14 x go-v0.44 (tcp, noise, yamux) | nim-v1.14 | go-v0.44 | tcp | noise | yamux | ✅ | 5s | 154.0 | 0.0 |
| nim-v1.14 x go-v0.44 (ws, noise, yamux) | nim-v1.14 | go-v0.44 | ws | noise | yamux | ✅ | 6s | 247.0 | 0.0 |
| nim-v1.14 x go-v0.45 (tcp, noise, yamux) | nim-v1.14 | go-v0.45 | tcp | noise | yamux | ✅ | 5s | 210.0 | 0.0 |
| nim-v1.14 x go-v0.45 (ws, noise, yamux) | nim-v1.14 | go-v0.45 | ws | noise | yamux | ✅ | 5s | 256.0 | 0.0 |
| nim-v1.14 x python-v0.4 (tcp, noise, mplex) | nim-v1.14 | python-v0.4 | tcp | noise | mplex | ✅ | 5s | 180.0 | 1.0 |
| nim-v1.14 x python-v0.4 (tcp, noise, yamux) | nim-v1.14 | python-v0.4 | tcp | noise | yamux | ✅ | 5s | 169.0 | 0.0 |
| nim-v1.14 x python-v0.4 (ws, noise, mplex) | nim-v1.14 | python-v0.4 | ws | noise | mplex | ✅ | 5s | 208.0 | 1.0 |
| nim-v1.14 x python-v0.4 (ws, noise, yamux) | nim-v1.14 | python-v0.4 | ws | noise | yamux | ✅ | 5s | 218.0 | 1.0 |
| nim-v1.14 x js-v1.x (tcp, noise, mplex) | nim-v1.14 | js-v1.x | tcp | noise | mplex | ✅ | 20s | 283.0 | 1.0 |
| nim-v1.14 x js-v1.x (ws, noise, mplex) | nim-v1.14 | js-v1.x | ws | noise | mplex | ✅ | 21s | 308.0 | 1.0 |
| nim-v1.14 x js-v1.x (tcp, noise, yamux) | nim-v1.14 | js-v1.x | tcp | noise | yamux | ✅ | 22s | 309.0 | 3.0 |
| nim-v1.14 x js-v1.x (ws, noise, yamux) | nim-v1.14 | js-v1.x | ws | noise | yamux | ✅ | 21s | 307.0 | 4.0 |
| nim-v1.14 x js-v2.x (tcp, noise, mplex) | nim-v1.14 | js-v2.x | tcp | noise | mplex | ✅ | 21s | 264.0 | 1.0 |
| nim-v1.14 x js-v2.x (tcp, noise, yamux) | nim-v1.14 | js-v2.x | tcp | noise | yamux | ✅ | 22s | 275.0 | 3.0 |
| nim-v1.14 x js-v2.x (ws, noise, mplex) | nim-v1.14 | js-v2.x | ws | noise | mplex | ✅ | 22s | 300.0 | 1.0 |
| nim-v1.14 x js-v2.x (ws, noise, yamux) | nim-v1.14 | js-v2.x | ws | noise | yamux | ✅ | 21s | 282.0 | 4.0 |
| nim-v1.14 x nim-v1.14 (tcp, noise, mplex) | nim-v1.14 | nim-v1.14 | tcp | noise | mplex | ✅ | 5s | 389.0 | 1.0 |
| nim-v1.14 x nim-v1.14 (tcp, noise, yamux) | nim-v1.14 | nim-v1.14 | tcp | noise | yamux | ✅ | 5s | 381.0 | 0.0 |
| nim-v1.14 x nim-v1.14 (ws, noise, mplex) | nim-v1.14 | nim-v1.14 | ws | noise | mplex | ✅ | 5s | 395.0 | 1.0 |
| nim-v1.14 x nim-v1.14 (ws, noise, yamux) | nim-v1.14 | nim-v1.14 | ws | noise | yamux | ✅ | 5s | 404.0 | 1.0 |
| nim-v1.14 x js-v3.x (tcp, noise, mplex) | nim-v1.14 | js-v3.x | tcp | noise | mplex | ✅ | 18s | 307.0 | 3.0 |
| nim-v1.14 x jvm-v1.2 (tcp, noise, mplex) | nim-v1.14 | jvm-v1.2 | tcp | noise | mplex | ✅ | 11s | 1323.0 | 8.0 |
| nim-v1.14 x js-v3.x (ws, noise, mplex) | nim-v1.14 | js-v3.x | ws | noise | mplex | ✅ | 20s | 318.0 | 5.0 |
| nim-v1.14 x js-v3.x (tcp, noise, yamux) | nim-v1.14 | js-v3.x | tcp | noise | yamux | ✅ | 20s | 269.0 | 4.0 |
| nim-v1.14 x jvm-v1.2 (tcp, noise, yamux) | nim-v1.14 | jvm-v1.2 | tcp | noise | yamux | ✅ | 11s | 1495.0 | 8.0 |
| nim-v1.14 x js-v3.x (ws, noise, yamux) | nim-v1.14 | js-v3.x | ws | noise | yamux | ✅ | 20s | 264.0 | 5.0 |
| nim-v1.14 x jvm-v1.2 (ws, noise, mplex) | nim-v1.14 | jvm-v1.2 | ws | noise | mplex | ✅ | 10s | 789.0 | 4.0 |
| nim-v1.14 x jvm-v1.2 (ws, noise, yamux) | nim-v1.14 | jvm-v1.2 | ws | noise | yamux | ✅ | 10s | 769.0 | 1.0 |
| nim-v1.14 x c-v0.0.1 (tcp, noise, mplex) | nim-v1.14 | c-v0.0.1 | tcp | noise | mplex | ✅ | 5s | 198.0 | 0.0 |
| nim-v1.14 x c-v0.0.1 (tcp, noise, yamux) | nim-v1.14 | c-v0.0.1 | tcp | noise | yamux | ✅ | 4s | 302.0 | 0.0 |
| nim-v1.14 x dotnet-v1.0 (tcp, noise, yamux) | nim-v1.14 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 6s | 454.0 | 14.0 |
| jvm-v1.2 x rust-v0.53 (tcp, tls, mplex) | jvm-v1.2 | rust-v0.53 | tcp | tls | mplex | ✅ | 14s | - | - |
| jvm-v1.2 x rust-v0.53 (tcp, noise, mplex) | jvm-v1.2 | rust-v0.53 | tcp | noise | mplex | ✅ | 14s | - | - |
| jvm-v1.2 x rust-v0.53 (tcp, noise, yamux) | jvm-v1.2 | rust-v0.53 | tcp | noise | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x rust-v0.53 (tcp, tls, yamux) | jvm-v1.2 | rust-v0.53 | tcp | tls | yamux | ✅ | 17s | - | - |
| jvm-v1.2 x rust-v0.53 (ws, tls, mplex) | jvm-v1.2 | rust-v0.53 | ws | tls | mplex | ✅ | 17s | - | - |
| jvm-v1.2 x rust-v0.53 (ws, noise, mplex) | jvm-v1.2 | rust-v0.53 | ws | noise | mplex | ✅ | 14s | - | - |
| jvm-v1.2 x rust-v0.53 (ws, tls, yamux) | jvm-v1.2 | rust-v0.53 | ws | tls | yamux | ✅ | 18s | - | - |
| jvm-v1.2 x rust-v0.53 (ws, noise, yamux) | jvm-v1.2 | rust-v0.53 | ws | noise | yamux | ✅ | 14s | - | - |
| jvm-v1.2 x rust-v0.53 (quic-v1) | jvm-v1.2 | rust-v0.53 | quic-v1 | - | - | ✅ | 12s | - | - |
| jvm-v1.2 x rust-v0.54 (tcp, tls, mplex) | jvm-v1.2 | rust-v0.54 | tcp | tls | mplex | ✅ | 13s | - | - |
| jvm-v1.2 x rust-v0.54 (tcp, noise, mplex) | jvm-v1.2 | rust-v0.54 | tcp | noise | mplex | ✅ | 13s | - | - |
| jvm-v1.2 x rust-v0.54 (tcp, tls, yamux) | jvm-v1.2 | rust-v0.54 | tcp | tls | yamux | ✅ | 16s | - | - |
| jvm-v1.2 x rust-v0.54 (tcp, noise, yamux) | jvm-v1.2 | rust-v0.54 | tcp | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x rust-v0.54 (ws, tls, mplex) | jvm-v1.2 | rust-v0.54 | ws | tls | mplex | ✅ | 16s | - | - |
| jvm-v1.2 x rust-v0.54 (ws, noise, mplex) | jvm-v1.2 | rust-v0.54 | ws | noise | mplex | ✅ | 15s | - | - |
| jvm-v1.2 x rust-v0.54 (ws, tls, yamux) | jvm-v1.2 | rust-v0.54 | ws | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x rust-v0.54 (ws, noise, yamux) | jvm-v1.2 | rust-v0.54 | ws | noise | yamux | ✅ | 12s | - | - |
| jvm-v1.2 x rust-v0.54 (quic-v1) | jvm-v1.2 | rust-v0.54 | quic-v1 | - | - | ✅ | 14s | - | - |
| jvm-v1.2 x rust-v0.55 (tcp, tls, mplex) | jvm-v1.2 | rust-v0.55 | tcp | tls | mplex | ✅ | 15s | - | - |
| jvm-v1.2 x rust-v0.55 (tcp, tls, yamux) | jvm-v1.2 | rust-v0.55 | tcp | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x rust-v0.55 (tcp, noise, mplex) | jvm-v1.2 | rust-v0.55 | tcp | noise | mplex | ✅ | 15s | - | - |
| jvm-v1.2 x rust-v0.55 (tcp, noise, yamux) | jvm-v1.2 | rust-v0.55 | tcp | noise | yamux | ✅ | 12s | - | - |
| jvm-v1.2 x rust-v0.55 (ws, tls, mplex) | jvm-v1.2 | rust-v0.55 | ws | tls | mplex | ✅ | 14s | - | - |
| jvm-v1.2 x rust-v0.55 (ws, tls, yamux) | jvm-v1.2 | rust-v0.55 | ws | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x rust-v0.55 (ws, noise, mplex) | jvm-v1.2 | rust-v0.55 | ws | noise | mplex | ✅ | 12s | - | - |
| jvm-v1.2 x rust-v0.55 (ws, noise, yamux) | jvm-v1.2 | rust-v0.55 | ws | noise | yamux | ✅ | 12s | - | - |
| jvm-v1.2 x rust-v0.55 (quic-v1) | jvm-v1.2 | rust-v0.55 | quic-v1 | - | - | ✅ | 14s | - | - |
| jvm-v1.2 x rust-v0.56 (tcp, noise, mplex) | jvm-v1.2 | rust-v0.56 | tcp | noise | mplex | ✅ | 13s | - | - |
| jvm-v1.2 x rust-v0.56 (tcp, tls, mplex) | jvm-v1.2 | rust-v0.56 | tcp | tls | mplex | ✅ | 15s | - | - |
| jvm-v1.2 x rust-v0.56 (tcp, tls, yamux) | jvm-v1.2 | rust-v0.56 | tcp | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x rust-v0.56 (tcp, noise, yamux) | jvm-v1.2 | rust-v0.56 | tcp | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x rust-v0.56 (ws, tls, mplex) | jvm-v1.2 | rust-v0.56 | ws | tls | mplex | ✅ | 13s | - | - |
| jvm-v1.2 x rust-v0.56 (ws, noise, mplex) | jvm-v1.2 | rust-v0.56 | ws | noise | mplex | ✅ | 13s | - | - |
| jvm-v1.2 x rust-v0.56 (ws, tls, yamux) | jvm-v1.2 | rust-v0.56 | ws | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x rust-v0.56 (ws, noise, yamux) | jvm-v1.2 | rust-v0.56 | ws | noise | yamux | ✅ | 12s | - | - |
| jvm-v1.2 x go-v0.38 (tcp, noise, yamux) | jvm-v1.2 | go-v0.38 | tcp | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x rust-v0.56 (quic-v1) | jvm-v1.2 | rust-v0.56 | quic-v1 | - | - | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.38 (tcp, tls, yamux) | jvm-v1.2 | go-v0.38 | tcp | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.38 (ws, tls, yamux) | jvm-v1.2 | go-v0.38 | ws | tls | yamux | ✅ | 16s | - | - |
| jvm-v1.2 x go-v0.38 (ws, noise, yamux) | jvm-v1.2 | go-v0.38 | ws | noise | yamux | ✅ | 14s | - | - |
| jvm-v1.2 x go-v0.38 (quic-v1) | jvm-v1.2 | go-v0.38 | quic-v1 | - | - | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.39 (tcp, noise, yamux) | jvm-v1.2 | go-v0.39 | tcp | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x go-v0.39 (tcp, tls, yamux) | jvm-v1.2 | go-v0.39 | tcp | tls | yamux | ✅ | 16s | - | - |
| jvm-v1.2 x go-v0.39 (ws, noise, yamux) | jvm-v1.2 | go-v0.39 | ws | noise | yamux | ✅ | 12s | - | - |
| jvm-v1.2 x go-v0.39 (ws, tls, yamux) | jvm-v1.2 | go-v0.39 | ws | tls | yamux | ✅ | 16s | - | - |
| jvm-v1.2 x go-v0.39 (quic-v1) | jvm-v1.2 | go-v0.39 | quic-v1 | - | - | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.40 (tcp, noise, yamux) | jvm-v1.2 | go-v0.40 | tcp | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x go-v0.40 (tcp, tls, yamux) | jvm-v1.2 | go-v0.40 | tcp | tls | yamux | ✅ | 16s | - | - |
| jvm-v1.2 x go-v0.40 (ws, noise, yamux) | jvm-v1.2 | go-v0.40 | ws | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x go-v0.40 (ws, tls, yamux) | jvm-v1.2 | go-v0.40 | ws | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.40 (quic-v1) | jvm-v1.2 | go-v0.40 | quic-v1 | - | - | ✅ | 14s | - | - |
| jvm-v1.2 x go-v0.41 (tcp, tls, yamux) | jvm-v1.2 | go-v0.41 | tcp | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.41 (tcp, noise, yamux) | jvm-v1.2 | go-v0.41 | tcp | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x go-v0.41 (ws, tls, yamux) | jvm-v1.2 | go-v0.41 | ws | tls | yamux | ✅ | 14s | - | - |
| jvm-v1.2 x go-v0.41 (ws, noise, yamux) | jvm-v1.2 | go-v0.41 | ws | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x go-v0.41 (quic-v1) | jvm-v1.2 | go-v0.41 | quic-v1 | - | - | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.42 (tcp, tls, yamux) | jvm-v1.2 | go-v0.42 | tcp | tls | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x go-v0.42 (tcp, noise, yamux) | jvm-v1.2 | go-v0.42 | tcp | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x go-v0.42 (ws, tls, yamux) | jvm-v1.2 | go-v0.42 | ws | tls | yamux | ✅ | 14s | - | - |
| jvm-v1.2 x go-v0.42 (ws, noise, yamux) | jvm-v1.2 | go-v0.42 | ws | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x go-v0.42 (quic-v1) | jvm-v1.2 | go-v0.42 | quic-v1 | - | - | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.43 (tcp, noise, yamux) | jvm-v1.2 | go-v0.43 | tcp | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x go-v0.43 (tcp, tls, yamux) | jvm-v1.2 | go-v0.43 | tcp | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.43 (ws, tls, yamux) | jvm-v1.2 | go-v0.43 | ws | tls | yamux | ✅ | 16s | - | - |
| jvm-v1.2 x go-v0.43 (ws, noise, yamux) | jvm-v1.2 | go-v0.43 | ws | noise | yamux | ✅ | 14s | - | - |
| jvm-v1.2 x go-v0.43 (quic-v1) | jvm-v1.2 | go-v0.43 | quic-v1 | - | - | ✅ | 14s | - | - |
| jvm-v1.2 x go-v0.44 (tcp, noise, yamux) | jvm-v1.2 | go-v0.44 | tcp | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x go-v0.44 (tcp, tls, yamux) | jvm-v1.2 | go-v0.44 | tcp | tls | yamux | ✅ | 16s | - | - |
| jvm-v1.2 x go-v0.44 (ws, noise, yamux) | jvm-v1.2 | go-v0.44 | ws | noise | yamux | ✅ | 12s | - | - |
| jvm-v1.2 x go-v0.44 (ws, tls, yamux) | jvm-v1.2 | go-v0.44 | ws | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.44 (quic-v1) | jvm-v1.2 | go-v0.44 | quic-v1 | - | - | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.45 (tcp, tls, yamux) | jvm-v1.2 | go-v0.45 | tcp | tls | yamux | ✅ | 16s | - | - |
| jvm-v1.2 x go-v0.45 (tcp, noise, yamux) | jvm-v1.2 | go-v0.45 | tcp | noise | yamux | ✅ | 14s | - | - |
| jvm-v1.2 x go-v0.45 (ws, tls, yamux) | jvm-v1.2 | go-v0.45 | ws | tls | yamux | ✅ | 16s | - | - |
| jvm-v1.2 x python-v0.4 (tcp, noise, mplex) | jvm-v1.2 | python-v0.4 | tcp | noise | mplex | ❌ | 11s | - | - |
| jvm-v1.2 x go-v0.45 (ws, noise, yamux) | jvm-v1.2 | go-v0.45 | ws | noise | yamux | ✅ | 14s | - | - |
| jvm-v1.2 x python-v0.4 (tcp, noise, yamux) | jvm-v1.2 | python-v0.4 | tcp | noise | yamux | ❌ | 10s | - | - |
| jvm-v1.2 x go-v0.45 (quic-v1) | jvm-v1.2 | go-v0.45 | quic-v1 | - | - | ✅ | 15s | - | - |
| jvm-v1.2 x python-v0.4 (ws, noise, mplex) | jvm-v1.2 | python-v0.4 | ws | noise | mplex | ❌ | 10s | - | - |
| jvm-v1.2 x python-v0.4 (ws, noise, yamux) | jvm-v1.2 | python-v0.4 | ws | noise | yamux | ❌ | 13s | - | - |
| jvm-v1.2 x python-v0.4 (quic-v1) | jvm-v1.2 | python-v0.4 | quic-v1 | - | - | ❌ | 19s | - | - |
| jvm-v1.2 x js-v1.x (tcp, noise, mplex) | jvm-v1.2 | js-v1.x | tcp | noise | mplex | ✅ | 31s | - | - |
| jvm-v1.2 x js-v1.x (tcp, noise, yamux) | jvm-v1.2 | js-v1.x | tcp | noise | yamux | ✅ | 33s | - | - |
| jvm-v1.2 x js-v1.x (ws, noise, mplex) | jvm-v1.2 | js-v1.x | ws | noise | mplex | ✅ | 32s | - | - |
| jvm-v1.2 x js-v1.x (ws, noise, yamux) | jvm-v1.2 | js-v1.x | ws | noise | yamux | ✅ | 32s | - | - |
| jvm-v1.2 x js-v2.x (tcp, noise, mplex) | jvm-v1.2 | js-v2.x | tcp | noise | mplex | ✅ | 33s | - | - |
| jvm-v1.2 x js-v2.x (tcp, noise, yamux) | jvm-v1.2 | js-v2.x | tcp | noise | yamux | ✅ | 31s | - | - |
| jvm-v1.2 x js-v2.x (ws, noise, mplex) | jvm-v1.2 | js-v2.x | ws | noise | mplex | ✅ | 28s | - | - |
| jvm-v1.2 x js-v2.x (ws, noise, yamux) | jvm-v1.2 | js-v2.x | ws | noise | yamux | ✅ | 25s | - | - |
| jvm-v1.2 x nim-v1.14 (tcp, noise, mplex) | jvm-v1.2 | nim-v1.14 | tcp | noise | mplex | ✅ | 16s | - | - |
| jvm-v1.2 x nim-v1.14 (tcp, noise, yamux) | jvm-v1.2 | nim-v1.14 | tcp | noise | yamux | ✅ | 16s | - | - |
| jvm-v1.2 x nim-v1.14 (ws, noise, mplex) | jvm-v1.2 | nim-v1.14 | ws | noise | mplex | ✅ | 15s | - | - |
| jvm-v1.2 x js-v3.x (tcp, noise, mplex) | jvm-v1.2 | js-v3.x | tcp | noise | mplex | ✅ | 26s | - | - |
| jvm-v1.2 x nim-v1.14 (ws, noise, yamux) | jvm-v1.2 | nim-v1.14 | ws | noise | yamux | ✅ | 14s | - | - |
| jvm-v1.2 x js-v3.x (tcp, noise, yamux) | jvm-v1.2 | js-v3.x | tcp | noise | yamux | ✅ | 27s | - | - |
| jvm-v1.2 x js-v3.x (ws, noise, mplex) | jvm-v1.2 | js-v3.x | ws | noise | mplex | ✅ | 26s | - | - |
| jvm-v1.2 x js-v3.x (ws, noise, yamux) | jvm-v1.2 | js-v3.x | ws | noise | yamux | ✅ | 28s | - | - |
| jvm-v1.2 x jvm-v1.2 (tcp, tls, mplex) | jvm-v1.2 | jvm-v1.2 | tcp | tls | mplex | ✅ | 19s | - | - |
| jvm-v1.2 x jvm-v1.2 (tcp, tls, yamux) | jvm-v1.2 | jvm-v1.2 | tcp | tls | yamux | ✅ | 21s | - | - |
| jvm-v1.2 x jvm-v1.2 (tcp, noise, mplex) | jvm-v1.2 | jvm-v1.2 | tcp | noise | mplex | ✅ | 19s | - | - |
| jvm-v1.2 x jvm-v1.2 (tcp, noise, yamux) | jvm-v1.2 | jvm-v1.2 | tcp | noise | yamux | ✅ | 21s | - | - |
| jvm-v1.2 x jvm-v1.2 (ws, tls, mplex) | jvm-v1.2 | jvm-v1.2 | ws | tls | mplex | ✅ | 26s | - | - |
| jvm-v1.2 x jvm-v1.2 (ws, noise, yamux) | jvm-v1.2 | jvm-v1.2 | ws | noise | yamux | ✅ | 21s | - | - |
| jvm-v1.2 x jvm-v1.2 (ws, noise, mplex) | jvm-v1.2 | jvm-v1.2 | ws | noise | mplex | ✅ | 23s | - | - |
| jvm-v1.2 x jvm-v1.2 (ws, tls, yamux) | jvm-v1.2 | jvm-v1.2 | ws | tls | yamux | ✅ | 27s | - | - |
| jvm-v1.2 x c-v0.0.1 (tcp, noise, yamux) | jvm-v1.2 | c-v0.0.1 | tcp | noise | yamux | ❌ | 15s | - | - |
| jvm-v1.2 x c-v0.0.1 (tcp, noise, mplex) | jvm-v1.2 | c-v0.0.1 | tcp | noise | mplex | ✅ | 17s | - | - |
| jvm-v1.2 x jvm-v1.2 (quic-v1) | jvm-v1.2 | jvm-v1.2 | quic-v1 | - | - | ✅ | 22s | - | - |
| c-v0.0.1 x rust-v0.53 (tcp, noise, mplex) | c-v0.0.1 | rust-v0.53 | tcp | noise | mplex | ✅ | 5s | 95.000 | 1.000 |
| jvm-v1.2 x c-v0.0.1 (quic-v1) | jvm-v1.2 | c-v0.0.1 | quic-v1 | - | - | ✅ | 18s | - | - |
| c-v0.0.1 x rust-v0.53 (tcp, noise, yamux) | c-v0.0.1 | rust-v0.53 | tcp | noise | yamux | ✅ | 6s | 66.000 | 1.000 |
| jvm-v1.2 x zig-v0.0.1 (quic-v1) | jvm-v1.2 | zig-v0.0.1 | quic-v1 | - | - | ❌ | 13s | - | - |
| jvm-v1.2 x dotnet-v1.0 (tcp, noise, yamux) | jvm-v1.2 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 15s | - | - |
| c-v0.0.1 x rust-v0.54 (tcp, noise, mplex) | c-v0.0.1 | rust-v0.54 | tcp | noise | mplex | ✅ | 5s | 15.000 | 0.000 |
| c-v0.0.1 x rust-v0.53 (quic-v1) | c-v0.0.1 | rust-v0.53 | quic-v1 | - | - | ✅ | 8s | 62.000 | 1.000 |
| c-v0.0.1 x rust-v0.54 (tcp, noise, yamux) | c-v0.0.1 | rust-v0.54 | tcp | noise | yamux | ✅ | 5s | 56.000 | 0.000 |
| jvm-v1.2 x eth-p2p-z-v0.0.1 (quic-v1) | jvm-v1.2 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 15s | - | - |
| c-v0.0.1 x rust-v0.55 (tcp, noise, mplex) | c-v0.0.1 | rust-v0.55 | tcp | noise | mplex | ✅ | 4s | 5.000 | 0.000 |
| c-v0.0.1 x rust-v0.55 (tcp, noise, yamux) | c-v0.0.1 | rust-v0.55 | tcp | noise | yamux | ✅ | 4s | 62.000 | 1.000 |
| c-v0.0.1 x rust-v0.54 (quic-v1) | c-v0.0.1 | rust-v0.54 | quic-v1 | - | - | ✅ | 7s | 27.000 | 0.000 |
| c-v0.0.1 x rust-v0.56 (tcp, noise, mplex) | c-v0.0.1 | rust-v0.56 | tcp | noise | mplex | ✅ | 4s | 9.000 | 0.000 |
| c-v0.0.1 x rust-v0.56 (tcp, noise, yamux) | c-v0.0.1 | rust-v0.56 | tcp | noise | yamux | ✅ | 4s | 65.000 | 1.000 |
| c-v0.0.1 x rust-v0.55 (quic-v1) | c-v0.0.1 | rust-v0.55 | quic-v1 | - | - | ✅ | 6s | 28.000 | 0.000 |
| c-v0.0.1 x go-v0.38 (tcp, noise, yamux) | c-v0.0.1 | go-v0.38 | tcp | noise | yamux | ✅ | 4s | 114.000 | 0.000 |
| c-v0.0.1 x go-v0.39 (tcp, noise, yamux) | c-v0.0.1 | go-v0.39 | tcp | noise | yamux | ✅ | 4s | 110.000 | 0.000 |
| c-v0.0.1 x rust-v0.56 (quic-v1) | c-v0.0.1 | rust-v0.56 | quic-v1 | - | - | ✅ | 7s | 21.000 | 1.000 |
| c-v0.0.1 x go-v0.40 (tcp, noise, yamux) | c-v0.0.1 | go-v0.40 | tcp | noise | yamux | ✅ | 5s | 123.000 | 0.000 |
| c-v0.0.1 x go-v0.41 (tcp, noise, yamux) | c-v0.0.1 | go-v0.41 | tcp | noise | yamux | ✅ | 4s | 118.000 | 0.000 |
| c-v0.0.1 x go-v0.42 (tcp, noise, yamux) | c-v0.0.1 | go-v0.42 | tcp | noise | yamux | ✅ | 4s | 119.000 | 0.000 |
| c-v0.0.1 x go-v0.43 (tcp, noise, yamux) | c-v0.0.1 | go-v0.43 | tcp | noise | yamux | ✅ | 4s | 131.000 | 0.000 |
| c-v0.0.1 x go-v0.44 (tcp, noise, yamux) | c-v0.0.1 | go-v0.44 | tcp | noise | yamux | ✅ | 6s | 122.000 | 1.000 |
| c-v0.0.1 x go-v0.38 (quic-v1) | c-v0.0.1 | go-v0.38 | quic-v1 | - | - | ✅ | 20s | 161.000 | 1.000 |
| c-v0.0.1 x go-v0.39 (quic-v1) | c-v0.0.1 | go-v0.39 | quic-v1 | - | - | ✅ | 20s | 122.000 | 2.000 |
| c-v0.0.1 x go-v0.40 (quic-v1) | c-v0.0.1 | go-v0.40 | quic-v1 | - | - | ✅ | 19s | 147.000 | 0.000 |
| c-v0.0.1 x go-v0.41 (quic-v1) | c-v0.0.1 | go-v0.41 | quic-v1 | - | - | ✅ | 20s | 158.000 | 1.000 |
| c-v0.0.1 x go-v0.45 (tcp, noise, yamux) | c-v0.0.1 | go-v0.45 | tcp | noise | yamux | ✅ | 6s | 130.000 | 0.000 |
| c-v0.0.1 x go-v0.42 (quic-v1) | c-v0.0.1 | go-v0.42 | quic-v1 | - | - | ✅ | 20s | 143.000 | 4.000 |
| c-v0.0.1 x python-v0.4 (tcp, noise, mplex) | c-v0.0.1 | python-v0.4 | tcp | noise | mplex | ✅ | 6s | 42.000 | 1.000 |
| c-v0.0.1 x python-v0.4 (tcp, noise, yamux) | c-v0.0.1 | python-v0.4 | tcp | noise | yamux | ✅ | 6s | 247.000 | 2.000 |
| c-v0.0.1 x python-v0.4 (quic-v1) | c-v0.0.1 | python-v0.4 | quic-v1 | - | - | ✅ | 6s | 217.000 | 1.000 |
| c-v0.0.1 x go-v0.45 (quic-v1) | c-v0.0.1 | go-v0.45 | quic-v1 | - | - | ✅ | 20s | 152.000 | 0.000 |
| c-v0.0.1 x js-v1.x (tcp, noise, yamux) | c-v0.0.1 | js-v1.x | tcp | noise | yamux | ✅ | 22s | 400.000 | 17.000 |
| c-v0.0.1 x js-v1.x (tcp, noise, mplex) | c-v0.0.1 | js-v1.x | tcp | noise | mplex | ✅ | 23s | 107.000 | 7.000 |
| c-v0.0.1 x js-v2.x (tcp, noise, mplex) | c-v0.0.1 | js-v2.x | tcp | noise | mplex | ✅ | 25s | 169.000 | 4.000 |
| c-v0.0.1 x nim-v1.14 (tcp, noise, mplex) | c-v0.0.1 | nim-v1.14 | tcp | noise | mplex | ✅ | 5s | 144.000 | 1.000 |
| c-v0.0.1 x js-v3.x (tcp, noise, mplex) | c-v0.0.1 | js-v3.x | tcp | noise | mplex | ✅ | 24s | 109.000 | 5.000 |
| c-v0.0.1 x nim-v1.14 (tcp, noise, yamux) | c-v0.0.1 | nim-v1.14 | tcp | noise | yamux | ✅ | 6s | 282.000 | 43.000 |
| c-v0.0.1 x js-v2.x (tcp, noise, yamux) | c-v0.0.1 | js-v2.x | tcp | noise | yamux | ✅ | 26s | 387.000 | 1.000 |
| c-v0.0.1 x js-v3.x (tcp, noise, yamux) | c-v0.0.1 | js-v3.x | tcp | noise | yamux | ❌ | 21s | - | - |
| c-v0.0.1 x c-v0.0.1 (tcp, noise, mplex) | c-v0.0.1 | c-v0.0.1 | tcp | noise | mplex | ✅ | 6s | 34.000 | 0.000 |
| c-v0.0.1 x c-v0.0.1 (tcp, noise, yamux) | c-v0.0.1 | c-v0.0.1 | tcp | noise | yamux | ✅ | 6s | 356.000 | 0.000 |
| c-v0.0.1 x jvm-v1.2 (tcp, noise, mplex) | c-v0.0.1 | jvm-v1.2 | tcp | noise | mplex | ✅ | 12s | 1226.000 | 17.000 |
| c-v0.0.1 x jvm-v1.2 (tcp, noise, yamux) | c-v0.0.1 | jvm-v1.2 | tcp | noise | yamux | ❌ | 11s | - | - |
| c-v0.0.1 x c-v0.0.1 (quic-v1) | c-v0.0.1 | c-v0.0.1 | quic-v1 | - | - | ✅ | 5s | 78.000 | 9.000 |
| c-v0.0.1 x dotnet-v1.0 (tcp, noise, yamux) | c-v0.0.1 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 7s | 465.000 | 14.000 |
| c-v0.0.1 x jvm-v1.2 (quic-v1) | c-v0.0.1 | jvm-v1.2 | quic-v1 | - | - | ✅ | 16s | 3339.000 | 3.000 |
| c-v0.0.1 x eth-p2p-z-v0.0.1 (quic-v1) | c-v0.0.1 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 5s | 160.000 | 10.000 |
| dotnet-v1.0 x rust-v0.53 (tcp, noise, yamux) | dotnet-v1.0 | rust-v0.53 | tcp | noise | yamux | ✅ | 6s | - | - |
| dotnet-v1.0 x rust-v0.54 (tcp, noise, yamux) | dotnet-v1.0 | rust-v0.54 | tcp | noise | yamux | ✅ | 5s | - | - |
| dotnet-v1.0 x rust-v0.55 (tcp, noise, yamux) | dotnet-v1.0 | rust-v0.55 | tcp | noise | yamux | ✅ | 7s | - | - |
| dotnet-v1.0 x go-v0.38 (tcp, noise, yamux) | dotnet-v1.0 | go-v0.38 | tcp | noise | yamux | ✅ | 7s | - | - |
| dotnet-v1.0 x rust-v0.56 (tcp, noise, yamux) | dotnet-v1.0 | rust-v0.56 | tcp | noise | yamux | ✅ | 7s | - | - |
| dotnet-v1.0 x go-v0.39 (tcp, noise, yamux) | dotnet-v1.0 | go-v0.39 | tcp | noise | yamux | ✅ | 6s | - | - |
| dotnet-v1.0 x go-v0.40 (tcp, noise, yamux) | dotnet-v1.0 | go-v0.40 | tcp | noise | yamux | ✅ | 7s | - | - |
| c-v0.0.1 x zig-v0.0.1 (quic-v1) | c-v0.0.1 | zig-v0.0.1 | quic-v1 | - | - | ❌ | 20s | - | - |
| dotnet-v1.0 x go-v0.41 (tcp, noise, yamux) | dotnet-v1.0 | go-v0.41 | tcp | noise | yamux | ✅ | 6s | - | - |
| dotnet-v1.0 x go-v0.42 (tcp, noise, yamux) | dotnet-v1.0 | go-v0.42 | tcp | noise | yamux | ✅ | 6s | - | - |
| dotnet-v1.0 x go-v0.43 (tcp, noise, yamux) | dotnet-v1.0 | go-v0.43 | tcp | noise | yamux | ✅ | 6s | - | - |
| dotnet-v1.0 x go-v0.44 (tcp, noise, yamux) | dotnet-v1.0 | go-v0.44 | tcp | noise | yamux | ✅ | 6s | - | - |
| dotnet-v1.0 x go-v0.45 (tcp, noise, yamux) | dotnet-v1.0 | go-v0.45 | tcp | noise | yamux | ✅ | 6s | - | - |
| dotnet-v1.0 x python-v0.4 (tcp, noise, yamux) | dotnet-v1.0 | python-v0.4 | tcp | noise | yamux | ✅ | 7s | - | - |
| dotnet-v1.0 x nim-v1.14 (tcp, noise, yamux) | dotnet-v1.0 | nim-v1.14 | tcp | noise | yamux | ✅ | 8s | - | - |
| dotnet-v1.0 x c-v0.0.1 (tcp, noise, yamux) | dotnet-v1.0 | c-v0.0.1 | tcp | noise | yamux | ✅ | 7s | - | - |
| dotnet-v1.0 x js-v1.x (tcp, noise, yamux) | dotnet-v1.0 | js-v1.x | tcp | noise | yamux | ❌ | 16s | - | - |
| dotnet-v1.0 x js-v2.x (tcp, noise, yamux) | dotnet-v1.0 | js-v2.x | tcp | noise | yamux | ❌ | 17s | - | - |
| dotnet-v1.0 x jvm-v1.2 (tcp, noise, yamux) | dotnet-v1.0 | jvm-v1.2 | tcp | noise | yamux | ✅ | 12s | - | - |
| dotnet-v1.0 x js-v3.x (tcp, noise, yamux) | dotnet-v1.0 | js-v3.x | tcp | noise | yamux | ❌ | 17s | - | - |
| dotnet-v1.0 x dotnet-v1.0 (tcp, noise, yamux) | dotnet-v1.0 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 7s | - | - |
| zig-v0.0.1 x rust-v0.53 (quic-v1) | zig-v0.0.1 | rust-v0.53 | quic-v1 | - | - | ✅ | 5s | - | - |
| zig-v0.0.1 x rust-v0.54 (quic-v1) | zig-v0.0.1 | rust-v0.54 | quic-v1 | - | - | ✅ | 4s | - | - |
| zig-v0.0.1 x rust-v0.55 (quic-v1) | zig-v0.0.1 | rust-v0.55 | quic-v1 | - | - | ✅ | 5s | - | - |
| zig-v0.0.1 x rust-v0.56 (quic-v1) | zig-v0.0.1 | rust-v0.56 | quic-v1 | - | - | ✅ | 5s | - | - |
| zig-v0.0.1 x go-v0.38 (quic-v1) | zig-v0.0.1 | go-v0.38 | quic-v1 | - | - | ✅ | 5s | - | - |
| zig-v0.0.1 x go-v0.39 (quic-v1) | zig-v0.0.1 | go-v0.39 | quic-v1 | - | - | ✅ | 5s | - | - |
| zig-v0.0.1 x go-v0.40 (quic-v1) | zig-v0.0.1 | go-v0.40 | quic-v1 | - | - | ✅ | 4s | - | - |
| zig-v0.0.1 x go-v0.41 (quic-v1) | zig-v0.0.1 | go-v0.41 | quic-v1 | - | - | ✅ | 5s | - | - |
| zig-v0.0.1 x go-v0.42 (quic-v1) | zig-v0.0.1 | go-v0.42 | quic-v1 | - | - | ✅ | 4s | - | - |
| zig-v0.0.1 x go-v0.43 (quic-v1) | zig-v0.0.1 | go-v0.43 | quic-v1 | - | - | ✅ | 4s | - | - |
| zig-v0.0.1 x go-v0.44 (quic-v1) | zig-v0.0.1 | go-v0.44 | quic-v1 | - | - | ✅ | 6s | - | - |
| zig-v0.0.1 x go-v0.45 (quic-v1) | zig-v0.0.1 | go-v0.45 | quic-v1 | - | - | ✅ | 5s | - | - |
| zig-v0.0.1 x zig-v0.0.1 (quic-v1) | zig-v0.0.1 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 5s | - | - |
| zig-v0.0.1 x eth-p2p-z-v0.0.1 (quic-v1) | zig-v0.0.1 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 5s | - | - |
| eth-p2p-z-v0.0.1 x rust-v0.53 (quic-v1) | eth-p2p-z-v0.0.1 | rust-v0.53 | quic-v1 | - | - | ✅ | 6s | - | - |
| zig-v0.0.1 x jvm-v1.2 (quic-v1) | zig-v0.0.1 | jvm-v1.2 | quic-v1 | - | - | ✅ | 13s | - | - |
| zig-v0.0.1 x python-v0.4 (quic-v1) | zig-v0.0.1 | python-v0.4 | quic-v1 | - | - | ✅ | 16s | - | - |
| eth-p2p-z-v0.0.1 x rust-v0.54 (quic-v1) | eth-p2p-z-v0.0.1 | rust-v0.54 | quic-v1 | - | - | ✅ | 5s | - | - |
| zig-v0.0.1 x c-v0.0.1 (quic-v1) | zig-v0.0.1 | c-v0.0.1 | quic-v1 | - | - | ❌ | 15s | - | - |
| eth-p2p-z-v0.0.1 x rust-v0.55 (quic-v1) | eth-p2p-z-v0.0.1 | rust-v0.55 | quic-v1 | - | - | ✅ | 5s | - | - |
| eth-p2p-z-v0.0.1 x rust-v0.56 (quic-v1) | eth-p2p-z-v0.0.1 | rust-v0.56 | quic-v1 | - | - | ✅ | 6s | - | - |
| eth-p2p-z-v0.0.1 x go-v0.38 (quic-v1) | eth-p2p-z-v0.0.1 | go-v0.38 | quic-v1 | - | - | ✅ | 5s | - | - |
| eth-p2p-z-v0.0.1 x go-v0.39 (quic-v1) | eth-p2p-z-v0.0.1 | go-v0.39 | quic-v1 | - | - | ✅ | 4s | - | - |
| eth-p2p-z-v0.0.1 x go-v0.40 (quic-v1) | eth-p2p-z-v0.0.1 | go-v0.40 | quic-v1 | - | - | ✅ | 5s | - | - |
| eth-p2p-z-v0.0.1 x go-v0.41 (quic-v1) | eth-p2p-z-v0.0.1 | go-v0.41 | quic-v1 | - | - | ✅ | 5s | - | - |
| eth-p2p-z-v0.0.1 x go-v0.42 (quic-v1) | eth-p2p-z-v0.0.1 | go-v0.42 | quic-v1 | - | - | ✅ | 4s | - | - |
| eth-p2p-z-v0.0.1 x go-v0.43 (quic-v1) | eth-p2p-z-v0.0.1 | go-v0.43 | quic-v1 | - | - | ✅ | 4s | - | - |
| eth-p2p-z-v0.0.1 x go-v0.44 (quic-v1) | eth-p2p-z-v0.0.1 | go-v0.44 | quic-v1 | - | - | ✅ | 5s | - | - |
| eth-p2p-z-v0.0.1 x go-v0.45 (quic-v1) | eth-p2p-z-v0.0.1 | go-v0.45 | quic-v1 | - | - | ✅ | 5s | - | - |
| eth-p2p-z-v0.0.1 x python-v0.4 (quic-v1) | eth-p2p-z-v0.0.1 | python-v0.4 | quic-v1 | - | - | ✅ | 5s | - | - |
| eth-p2p-z-v0.0.1 x c-v0.0.1 (quic-v1) | eth-p2p-z-v0.0.1 | c-v0.0.1 | quic-v1 | - | - | ✅ | 5s | - | - |
| eth-p2p-z-v0.0.1 x eth-p2p-z-v0.0.1 (quic-v1) | eth-p2p-z-v0.0.1 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 5s | - | - |
| eth-p2p-z-v0.0.1 x jvm-v1.2 (quic-v1) | eth-p2p-z-v0.0.1 | jvm-v1.2 | quic-v1 | - | - | ✅ | 12s | - | - |
| chromium-js-v1.x x rust-v0.53 (webrtc-direct) | chromium-js-v1.x | rust-v0.53 | webrtc-direct | - | - | ✅ | 27s | 340 | 38 |
| chromium-js-v1.x x rust-v0.54 (webrtc-direct) | chromium-js-v1.x | rust-v0.54 | webrtc-direct | - | - | ✅ | 26s | 389 | 29 |
| chromium-js-v1.x x rust-v0.55 (webrtc-direct) | chromium-js-v1.x | rust-v0.55 | webrtc-direct | - | - | ✅ | 26s | 278 | 24 |
| chromium-js-v1.x x rust-v0.56 (webrtc-direct) | chromium-js-v1.x | rust-v0.56 | webrtc-direct | - | - | ✅ | 26s | 353 | 34 |
| chromium-js-v1.x x go-v0.38 (webtransport) | chromium-js-v1.x | go-v0.38 | webtransport | - | - | ✅ | 25s | 156 | 44 |
| c-v0.0.1 x go-v0.43 (quic-v1) | c-v0.0.1 | go-v0.43 | quic-v1 | - | - | ❌ | 194s | - | - |
| chromium-js-v1.x x go-v0.38 (wss, noise, yamux) | chromium-js-v1.x | go-v0.38 | wss | noise | yamux | ✅ | 25s | 315 | 52 |
| chromium-js-v1.x x go-v0.38 (webrtc-direct) | chromium-js-v1.x | go-v0.38 | webrtc-direct | - | - | ✅ | 25s | 268 | 47 |
| chromium-js-v1.x x go-v0.39 (webtransport) | chromium-js-v1.x | go-v0.39 | webtransport | - | - | ✅ | 25s | 168 | 48 |
| chromium-js-v1.x x go-v0.39 (wss, noise, yamux) | chromium-js-v1.x | go-v0.39 | wss | noise | yamux | ✅ | 24s | 230 | 62 |
| c-v0.0.1 x go-v0.44 (quic-v1) | c-v0.0.1 | go-v0.44 | quic-v1 | - | - | ❌ | 194s | - | - |
| chromium-js-v1.x x go-v0.39 (webrtc-direct) | chromium-js-v1.x | go-v0.39 | webrtc-direct | - | - | ✅ | 24s | 233 | 20 |
| chromium-js-v1.x x go-v0.40 (webtransport) | chromium-js-v1.x | go-v0.40 | webtransport | - | - | ✅ | 22s | 228 | 57 |
| chromium-js-v1.x x go-v0.40 (wss, noise, yamux) | chromium-js-v1.x | go-v0.40 | wss | noise | yamux | ✅ | 23s | 341 | 125 |
| chromium-js-v1.x x go-v0.40 (webrtc-direct) | chromium-js-v1.x | go-v0.40 | webrtc-direct | - | - | ✅ | 22s | 255 | 37 |
| chromium-js-v1.x x go-v0.41 (webtransport) | chromium-js-v1.x | go-v0.41 | webtransport | - | - | ✅ | 22s | 142 | 42 |
| chromium-js-v1.x x go-v0.41 (wss, noise, yamux) | chromium-js-v1.x | go-v0.41 | wss | noise | yamux | ✅ | 22s | 276 | 92 |
| chromium-js-v1.x x go-v0.41 (webrtc-direct) | chromium-js-v1.x | go-v0.41 | webrtc-direct | - | - | ✅ | 22s | 304 | 20 |
| chromium-js-v1.x x go-v0.42 (webtransport) | chromium-js-v1.x | go-v0.42 | webtransport | - | - | ✅ | 22s | 114 | 30 |
| chromium-js-v1.x x go-v0.42 (wss, noise, yamux) | chromium-js-v1.x | go-v0.42 | wss | noise | yamux | ✅ | 23s | 303 | 83 |
| chromium-js-v1.x x go-v0.43 (webtransport) | chromium-js-v1.x | go-v0.43 | webtransport | - | - | ✅ | 23s | 254 | 56 |
| chromium-js-v1.x x go-v0.42 (webrtc-direct) | chromium-js-v1.x | go-v0.42 | webrtc-direct | - | - | ✅ | 23s | 310 | 50 |
| chromium-js-v1.x x go-v0.43 (wss, noise, yamux) | chromium-js-v1.x | go-v0.43 | wss | noise | yamux | ✅ | 23s | 244 | 48 |
| chromium-js-v1.x x go-v0.43 (webrtc-direct) | chromium-js-v1.x | go-v0.43 | webrtc-direct | - | - | ✅ | 22s | 176 | 20 |
| chromium-js-v1.x x go-v0.44 (webtransport) | chromium-js-v1.x | go-v0.44 | webtransport | - | - | ✅ | 22s | 150 | 36 |
| chromium-js-v1.x x go-v0.44 (wss, noise, yamux) | chromium-js-v1.x | go-v0.44 | wss | noise | yamux | ✅ | 21s | 203 | 40 |
| chromium-js-v1.x x go-v0.44 (webrtc-direct) | chromium-js-v1.x | go-v0.44 | webrtc-direct | - | - | ✅ | 26s | 396 | 54 |
| chromium-js-v1.x x go-v0.45 (webtransport) | chromium-js-v1.x | go-v0.45 | webtransport | - | - | ✅ | 25s | 249 | 50 |
| chromium-js-v1.x x go-v0.45 (wss, noise, yamux) | chromium-js-v1.x | go-v0.45 | wss | noise | yamux | ✅ | 26s | 348 | 101 |
| chromium-js-v1.x x python-v0.4 (wss, noise, mplex) | chromium-js-v1.x | python-v0.4 | wss | noise | mplex | ✅ | 26s | 253 | 44 |
| chromium-js-v1.x x go-v0.45 (webrtc-direct) | chromium-js-v1.x | go-v0.45 | webrtc-direct | - | - | ✅ | 26s | 450 | 50 |
| chromium-js-v1.x x python-v0.4 (wss, noise, yamux) | chromium-js-v1.x | python-v0.4 | wss | noise | yamux | ✅ | 24s | 333 | 48 |
| chromium-js-v1.x x chromium-js-v1.x (webrtc) | chromium-js-v1.x | chromium-js-v1.x | webrtc | - | - | ✅ | 27s | 791 | 118 |
| chromium-js-v1.x x chromium-js-v2.x (webrtc) | chromium-js-v1.x | chromium-js-v2.x | webrtc | - | - | ✅ | 39s | 1010 | 88 |
| chromium-js-v1.x x webkit-js-v1.x (webrtc) | chromium-js-v1.x | webkit-js-v1.x | webrtc | - | - | ✅ | 39s | 1355 | 162 |
| chromium-js-v2.x x rust-v0.53 (webrtc-direct) | chromium-js-v2.x | rust-v0.53 | webrtc-direct | - | - | ✅ | 39s | 292 | 22 |
| chromium-js-v1.x x webkit-js-v2.x (webrtc) | chromium-js-v1.x | webkit-js-v2.x | webrtc | - | - | ✅ | 40s | 743 | 56 |
| chromium-js-v1.x x firefox-js-v1.x (webrtc) | chromium-js-v1.x | firefox-js-v1.x | webrtc | - | - | ✅ | 42s | 998 | 132 |
| chromium-js-v1.x x firefox-js-v2.x (webrtc) | chromium-js-v1.x | firefox-js-v2.x | webrtc | - | - | ✅ | 42s | 941 | 61 |
| chromium-js-v2.x x rust-v0.54 (webrtc-direct) | chromium-js-v2.x | rust-v0.54 | webrtc-direct | - | - | ✅ | 36s | 208 | 14 |
| eth-p2p-z-v0.0.1 x zig-v0.0.1 (quic-v1) | eth-p2p-z-v0.0.1 | zig-v0.0.1 | quic-v1 | - | - | ❌ | 194s | - | - |
| chromium-js-v2.x x rust-v0.55 (webrtc-direct) | chromium-js-v2.x | rust-v0.55 | webrtc-direct | - | - | ✅ | 25s | 361 | 46 |
| chromium-js-v2.x x go-v0.38 (webtransport) | chromium-js-v2.x | go-v0.38 | webtransport | - | - | ✅ | 25s | 230 | 62 |
| chromium-js-v2.x x rust-v0.56 (webrtc-direct) | chromium-js-v2.x | rust-v0.56 | webrtc-direct | - | - | ✅ | 26s | 421 | 37 |
| chromium-js-v2.x x go-v0.38 (wss, noise, yamux) | chromium-js-v2.x | go-v0.38 | wss | noise | yamux | ✅ | 25s | 376 | 102 |
| chromium-js-v2.x x go-v0.38 (webrtc-direct) | chromium-js-v2.x | go-v0.38 | webrtc-direct | - | - | ✅ | 26s | 352 | 70 |
| chromium-js-v2.x x go-v0.39 (webtransport) | chromium-js-v2.x | go-v0.39 | webtransport | - | - | ✅ | 25s | 135 | 40 |
| chromium-js-v2.x x go-v0.39 (wss, noise, yamux) | chromium-js-v2.x | go-v0.39 | wss | noise | yamux | ✅ | 25s | 215 | 51 |
| chromium-js-v2.x x go-v0.39 (webrtc-direct) | chromium-js-v2.x | go-v0.39 | webrtc-direct | - | - | ✅ | 28s | 347 | 26 |
| chromium-js-v2.x x go-v0.40 (webtransport) | chromium-js-v2.x | go-v0.40 | webtransport | - | - | ✅ | 28s | 219 | 53 |
| chromium-js-v2.x x go-v0.40 (wss, noise, yamux) | chromium-js-v2.x | go-v0.40 | wss | noise | yamux | ✅ | 27s | 351 | 89 |
| chromium-js-v2.x x go-v0.40 (webrtc-direct) | chromium-js-v2.x | go-v0.40 | webrtc-direct | - | - | ✅ | 28s | 236 | 47 |
| chromium-js-v2.x x go-v0.41 (webtransport) | chromium-js-v2.x | go-v0.41 | webtransport | - | - | ✅ | 28s | 207 | 51 |
| chromium-js-v2.x x go-v0.41 (wss, noise, yamux) | chromium-js-v2.x | go-v0.41 | wss | noise | yamux | ✅ | 28s | 289 | 67 |
| chromium-js-v2.x x go-v0.42 (webtransport) | chromium-js-v2.x | go-v0.42 | webtransport | - | - | ✅ | 27s | 208 | 65 |
| chromium-js-v2.x x go-v0.41 (webrtc-direct) | chromium-js-v2.x | go-v0.41 | webrtc-direct | - | - | ✅ | 28s | 244 | 36 |
| chromium-js-v2.x x go-v0.42 (wss, noise, yamux) | chromium-js-v2.x | go-v0.42 | wss | noise | yamux | ✅ | 27s | 349 | 106 |
| chromium-js-v2.x x go-v0.43 (webtransport) | chromium-js-v2.x | go-v0.43 | webtransport | - | - | ✅ | 28s | 256 | 61 |
| chromium-js-v2.x x go-v0.43 (wss, noise, yamux) | chromium-js-v2.x | go-v0.43 | wss | noise | yamux | ✅ | 28s | 361 | 94 |
| chromium-js-v2.x x go-v0.42 (webrtc-direct) | chromium-js-v2.x | go-v0.42 | webrtc-direct | - | - | ✅ | 29s | 327 | 73 |
| chromium-js-v2.x x go-v0.44 (webtransport) | chromium-js-v2.x | go-v0.44 | webtransport | - | - | ✅ | 28s | 219 | 62 |
| chromium-js-v2.x x go-v0.43 (webrtc-direct) | chromium-js-v2.x | go-v0.43 | webrtc-direct | - | - | ✅ | 29s | 401 | 48 |
| chromium-js-v2.x x go-v0.44 (wss, noise, yamux) | chromium-js-v2.x | go-v0.44 | wss | noise | yamux | ✅ | 28s | 201 | 38 |
| chromium-js-v2.x x go-v0.44 (webrtc-direct) | chromium-js-v2.x | go-v0.44 | webrtc-direct | - | - | ✅ | 27s | 176 | 31 |
| chromium-js-v2.x x go-v0.45 (webtransport) | chromium-js-v2.x | go-v0.45 | webtransport | - | - | ✅ | 36s | 269 | 83 |
| chromium-js-v2.x x go-v0.45 (wss, noise, yamux) | chromium-js-v2.x | go-v0.45 | wss | noise | yamux | ✅ | 36s | 404 | 108 |
| chromium-js-v2.x x go-v0.45 (webrtc-direct) | chromium-js-v2.x | go-v0.45 | webrtc-direct | - | - | ✅ | 37s | 513 | 109 |
| chromium-js-v2.x x python-v0.4 (wss, noise, mplex) | chromium-js-v2.x | python-v0.4 | wss | noise | mplex | ✅ | 38s | 331 | 55 |
| chromium-js-v2.x x python-v0.4 (wss, noise, yamux) | chromium-js-v2.x | python-v0.4 | wss | noise | yamux | ✅ | 39s | 362 | 115 |
| chromium-js-v2.x x chromium-js-v2.x (webrtc) | chromium-js-v2.x | chromium-js-v2.x | webrtc | - | - | ✅ | 38s | 913 | 104 |
| chromium-js-v2.x x chromium-js-v1.x (webrtc) | chromium-js-v2.x | chromium-js-v1.x | webrtc | - | - | ✅ | 39s | 1029 | 87 |
| chromium-js-v2.x x firefox-js-v1.x (webrtc) | chromium-js-v2.x | firefox-js-v1.x | webrtc | - | - | ✅ | 43s | 1304 | 157 |
| chromium-js-v2.x x webkit-js-v1.x (webrtc) | chromium-js-v2.x | webkit-js-v1.x | webrtc | - | - | ✅ | 39s | 1157 | 129 |
| chromium-js-v2.x x webkit-js-v2.x (webrtc) | chromium-js-v2.x | webkit-js-v2.x | webrtc | - | - | ✅ | 40s | 1126 | 111 |
| chromium-js-v2.x x firefox-js-v2.x (webrtc) | chromium-js-v2.x | firefox-js-v2.x | webrtc | - | - | ✅ | 44s | 1057 | 74 |
| firefox-js-v1.x x rust-v0.53 (webrtc-direct) | firefox-js-v1.x | rust-v0.53 | webrtc-direct | - | - | ✅ | 41s | 1469 | 42 |
| firefox-js-v1.x x rust-v0.54 (webrtc-direct) | firefox-js-v1.x | rust-v0.54 | webrtc-direct | - | - | ✅ | 41s | 1472 | 63 |
| firefox-js-v1.x x rust-v0.55 (webrtc-direct) | firefox-js-v1.x | rust-v0.55 | webrtc-direct | - | - | ✅ | 41s | 1474 | 51 |
| firefox-js-v1.x x go-v0.38 (webtransport) | firefox-js-v1.x | go-v0.38 | webtransport | - | - | ❌ | 38s | - | - |
| firefox-js-v1.x x rust-v0.56 (webrtc-direct) | firefox-js-v1.x | rust-v0.56 | webrtc-direct | - | - | ✅ | 41s | 1427 | 41 |
| firefox-js-v1.x x go-v0.38 (wss, noise, yamux) | firefox-js-v1.x | go-v0.38 | wss | noise | yamux | ✅ | 30s | 344 | 126 |
| firefox-js-v1.x x go-v0.38 (webrtc-direct) | firefox-js-v1.x | go-v0.38 | webrtc-direct | - | - | ✅ | 30s | 409 | 108 |
| firefox-js-v1.x x go-v0.39 (webtransport) | firefox-js-v1.x | go-v0.39 | webtransport | - | - | ❌ | 30s | - | - |
| firefox-js-v1.x x go-v0.39 (wss, noise, yamux) | firefox-js-v1.x | go-v0.39 | wss | noise | yamux | ✅ | 32s | 285 | 126 |
| firefox-js-v1.x x go-v0.39 (webrtc-direct) | firefox-js-v1.x | go-v0.39 | webrtc-direct | - | - | ✅ | 32s | 353 | 57 |
| firefox-js-v1.x x go-v0.40 (webtransport) | firefox-js-v1.x | go-v0.40 | webtransport | - | - | ❌ | 31s | - | - |
| firefox-js-v1.x x go-v0.40 (wss, noise, yamux) | firefox-js-v1.x | go-v0.40 | wss | noise | yamux | ✅ | 32s | 223 | 101 |
| firefox-js-v1.x x go-v0.40 (webrtc-direct) | firefox-js-v1.x | go-v0.40 | webrtc-direct | - | - | ✅ | 31s | 285 | 73 |
| firefox-js-v1.x x go-v0.41 (webtransport) | firefox-js-v1.x | go-v0.41 | webtransport | - | - | ❌ | 31s | - | - |
| firefox-js-v1.x x go-v0.41 (webrtc-direct) | firefox-js-v1.x | go-v0.41 | webrtc-direct | - | - | ✅ | 30s | 280 | 71 |
| firefox-js-v1.x x go-v0.41 (wss, noise, yamux) | firefox-js-v1.x | go-v0.41 | wss | noise | yamux | ✅ | 32s | 322 | 140 |
| firefox-js-v1.x x go-v0.42 (webtransport) | firefox-js-v1.x | go-v0.42 | webtransport | - | - | ❌ | 31s | - | - |
| firefox-js-v1.x x go-v0.42 (wss, noise, yamux) | firefox-js-v1.x | go-v0.42 | wss | noise | yamux | ✅ | 31s | 325 | 176 |
| firefox-js-v1.x x go-v0.42 (webrtc-direct) | firefox-js-v1.x | go-v0.42 | webrtc-direct | - | - | ✅ | 30s | 306 | 66 |
| firefox-js-v1.x x go-v0.43 (webtransport) | firefox-js-v1.x | go-v0.43 | webtransport | - | - | ❌ | 31s | - | - |
| firefox-js-v1.x x go-v0.43 (wss, noise, yamux) | firefox-js-v1.x | go-v0.43 | wss | noise | yamux | ✅ | 30s | 213 | 89 |
| firefox-js-v1.x x go-v0.43 (webrtc-direct) | firefox-js-v1.x | go-v0.43 | webrtc-direct | - | - | ✅ | 31s | 378 | 88 |
| firefox-js-v1.x x go-v0.44 (webtransport) | firefox-js-v1.x | go-v0.44 | webtransport | - | - | ❌ | 32s | - | - |
| firefox-js-v1.x x go-v0.44 (wss, noise, yamux) | firefox-js-v1.x | go-v0.44 | wss | noise | yamux | ✅ | 32s | 398 | 157 |
| firefox-js-v1.x x go-v0.44 (webrtc-direct) | firefox-js-v1.x | go-v0.44 | webrtc-direct | - | - | ✅ | 31s | 363 | 130 |
| firefox-js-v1.x x go-v0.45 (webtransport) | firefox-js-v1.x | go-v0.45 | webtransport | - | - | ❌ | 31s | - | - |
| firefox-js-v1.x x go-v0.45 (wss, noise, yamux) | firefox-js-v1.x | go-v0.45 | wss | noise | yamux | ✅ | 32s | 311 | 133 |
| firefox-js-v1.x x go-v0.45 (webrtc-direct) | firefox-js-v1.x | go-v0.45 | webrtc-direct | - | - | ✅ | 32s | 258 | 59 |
| firefox-js-v1.x x python-v0.4 (wss, noise, mplex) | firefox-js-v1.x | python-v0.4 | wss | noise | mplex | ✅ | 31s | 149 | 56 |
| firefox-js-v1.x x python-v0.4 (wss, noise, yamux) | firefox-js-v1.x | python-v0.4 | wss | noise | yamux | ✅ | 50s | 596 | 264 |
| firefox-js-v1.x x chromium-js-v1.x (webrtc) | firefox-js-v1.x | chromium-js-v1.x | webrtc | - | - | ✅ | 52s | 2560 | 263 |
| firefox-js-v1.x x chromium-js-v2.x (webrtc) | firefox-js-v1.x | chromium-js-v2.x | webrtc | - | - | ✅ | 53s | 2560 | 262 |
| firefox-js-v1.x x firefox-js-v1.x (webrtc) | firefox-js-v1.x | firefox-js-v1.x | webrtc | - | - | ✅ | 55s | 1892 | 238 |
| firefox-js-v1.x x webkit-js-v1.x (webrtc) | firefox-js-v1.x | webkit-js-v1.x | webrtc | - | - | ✅ | 55s | 1830 | 221 |
| firefox-js-v1.x x firefox-js-v2.x (webrtc) | firefox-js-v1.x | firefox-js-v2.x | webrtc | - | - | ✅ | 55s | 1736 | 184 |
| firefox-js-v1.x x webkit-js-v2.x (webrtc) | firefox-js-v1.x | webkit-js-v2.x | webrtc | - | - | ✅ | 53s | 990 | 130 |
| firefox-js-v2.x x rust-v0.53 (webrtc-direct) | firefox-js-v2.x | rust-v0.53 | webrtc-direct | - | - | ✅ | 53s | 1482 | 31 |
| firefox-js-v2.x x rust-v0.54 (webrtc-direct) | firefox-js-v2.x | rust-v0.54 | webrtc-direct | - | - | ✅ | 35s | 1614 | 81 |
| firefox-js-v2.x x go-v0.38 (webtransport) | firefox-js-v2.x | go-v0.38 | webtransport | - | - | ❌ | 33s | - | - |
| firefox-js-v2.x x rust-v0.55 (webrtc-direct) | firefox-js-v2.x | rust-v0.55 | webrtc-direct | - | - | ✅ | 36s | 1525 | 69 |
| firefox-js-v2.x x rust-v0.56 (webrtc-direct) | firefox-js-v2.x | rust-v0.56 | webrtc-direct | - | - | ✅ | 35s | 1604 | 72 |
| firefox-js-v2.x x go-v0.38 (wss, noise, yamux) | firefox-js-v2.x | go-v0.38 | wss | noise | yamux | ✅ | 34s | 295 | 119 |
| firefox-js-v2.x x go-v0.38 (webrtc-direct) | firefox-js-v2.x | go-v0.38 | webrtc-direct | - | - | ✅ | 33s | 263 | 52 |
| firefox-js-v2.x x go-v0.39 (webtransport) | firefox-js-v2.x | go-v0.39 | webtransport | - | - | ❌ | 32s | - | - |
| firefox-js-v2.x x go-v0.39 (wss, noise, yamux) | firefox-js-v2.x | go-v0.39 | wss | noise | yamux | ✅ | 32s | 123 | 75 |
| firefox-js-v2.x x go-v0.39 (webrtc-direct) | firefox-js-v2.x | go-v0.39 | webrtc-direct | - | - | ✅ | 32s | 400 | 52 |
| firefox-js-v2.x x go-v0.40 (webtransport) | firefox-js-v2.x | go-v0.40 | webtransport | - | - | ❌ | 34s | - | - |
| firefox-js-v2.x x go-v0.40 (wss, noise, yamux) | firefox-js-v2.x | go-v0.40 | wss | noise | yamux | ✅ | 33s | 464 | 241 |
| firefox-js-v2.x x go-v0.40 (webrtc-direct) | firefox-js-v2.x | go-v0.40 | webrtc-direct | - | - | ✅ | 35s | 359 | 76 |
| firefox-js-v2.x x go-v0.41 (webtransport) | firefox-js-v2.x | go-v0.41 | webtransport | - | - | ❌ | 35s | - | - |
| firefox-js-v2.x x go-v0.41 (wss, noise, yamux) | firefox-js-v2.x | go-v0.41 | wss | noise | yamux | ✅ | 34s | 335 | 138 |
| firefox-js-v2.x x go-v0.41 (webrtc-direct) | firefox-js-v2.x | go-v0.41 | webrtc-direct | - | - | ✅ | 34s | 317 | 58 |
| firefox-js-v2.x x go-v0.42 (webtransport) | firefox-js-v2.x | go-v0.42 | webtransport | - | - | ❌ | 33s | - | - |
| firefox-js-v2.x x go-v0.42 (wss, noise, yamux) | firefox-js-v2.x | go-v0.42 | wss | noise | yamux | ✅ | 34s | 410 | 176 |
| firefox-js-v2.x x go-v0.42 (webrtc-direct) | firefox-js-v2.x | go-v0.42 | webrtc-direct | - | - | ✅ | 34s | 336 | 62 |
| firefox-js-v2.x x go-v0.43 (webtransport) | firefox-js-v2.x | go-v0.43 | webtransport | - | - | ❌ | 33s | - | - |
| firefox-js-v2.x x go-v0.43 (wss, noise, yamux) | firefox-js-v2.x | go-v0.43 | wss | noise | yamux | ✅ | 34s | 283 | 135 |
| firefox-js-v2.x x go-v0.44 (webtransport) | firefox-js-v2.x | go-v0.44 | webtransport | - | - | ❌ | 34s | - | - |
| firefox-js-v2.x x go-v0.43 (webrtc-direct) | firefox-js-v2.x | go-v0.43 | webrtc-direct | - | - | ✅ | 34s | 314 | 44 |
| firefox-js-v2.x x go-v0.44 (wss, noise, yamux) | firefox-js-v2.x | go-v0.44 | wss | noise | yamux | ✅ | 34s | 226 | 110 |
| firefox-js-v2.x x go-v0.44 (webrtc-direct) | firefox-js-v2.x | go-v0.44 | webrtc-direct | - | - | ✅ | 34s | 211 | 39 |
| firefox-js-v2.x x go-v0.45 (webtransport) | firefox-js-v2.x | go-v0.45 | webtransport | - | - | ❌ | 42s | - | - |
| firefox-js-v2.x x go-v0.45 (wss, noise, yamux) | firefox-js-v2.x | go-v0.45 | wss | noise | yamux | ✅ | 42s | 462 | 210 |
| firefox-js-v2.x x python-v0.4 (wss, noise, mplex) | firefox-js-v2.x | python-v0.4 | wss | noise | mplex | ✅ | 43s | 342 | 133 |
| firefox-js-v2.x x python-v0.4 (wss, noise, yamux) | firefox-js-v2.x | python-v0.4 | wss | noise | yamux | ✅ | 43s | 384 | 139 |
| firefox-js-v2.x x go-v0.45 (webrtc-direct) | firefox-js-v2.x | go-v0.45 | webrtc-direct | - | - | ✅ | 46s | 495 | 60 |
| firefox-js-v2.x x chromium-js-v2.x (webrtc) | firefox-js-v2.x | chromium-js-v2.x | webrtc | - | - | ✅ | 46s | 1440 | 133 |
| firefox-js-v2.x x chromium-js-v1.x (webrtc) | firefox-js-v2.x | chromium-js-v1.x | webrtc | - | - | ✅ | 49s | 1707 | 131 |
| firefox-js-v2.x x firefox-js-v1.x (webrtc) | firefox-js-v2.x | firefox-js-v1.x | webrtc | - | - | ✅ | 50s | 1755 | 301 |
| webkit-js-v1.x x rust-v0.54 (webrtc-direct) | webkit-js-v1.x | rust-v0.54 | webrtc-direct | - | - | ✅ | 35s | 705 | 101 |
| firefox-js-v2.x x firefox-js-v2.x (webrtc) | firefox-js-v2.x | firefox-js-v2.x | webrtc | - | - | ✅ | 47s | 2037 | 167 |
| webkit-js-v1.x x rust-v0.53 (webrtc-direct) | webkit-js-v1.x | rust-v0.53 | webrtc-direct | - | - | ✅ | 38s | 609 | 71 |
| webkit-js-v1.x x rust-v0.55 (webrtc-direct) | webkit-js-v1.x | rust-v0.55 | webrtc-direct | - | - | ✅ | 35s | 624 | 79 |
| firefox-js-v2.x x webkit-js-v1.x (webrtc) | firefox-js-v2.x | webkit-js-v1.x | webrtc | - | - | ✅ | 45s | 1260 | 93 |
| webkit-js-v1.x x rust-v0.56 (webrtc-direct) | webkit-js-v1.x | rust-v0.56 | webrtc-direct | - | - | ✅ | 35s | 513 | 71 |
| webkit-js-v1.x x go-v0.38 (wss, noise, yamux) | webkit-js-v1.x | go-v0.38 | wss | noise | yamux | ✅ | 33s | 399 | 123 |
| firefox-js-v2.x x webkit-js-v2.x (webrtc) | firefox-js-v2.x | webkit-js-v2.x | webrtc | - | - | ✅ | 46s | 1213 | 171 |
| webkit-js-v1.x x go-v0.38 (webrtc-direct) | webkit-js-v1.x | go-v0.38 | webrtc-direct | - | - | ✅ | 26s | 523 | 95 |
| webkit-js-v1.x x go-v0.39 (wss, noise, yamux) | webkit-js-v1.x | go-v0.39 | wss | noise | yamux | ✅ | 27s | 524 | 190 |
| webkit-js-v1.x x go-v0.39 (webrtc-direct) | webkit-js-v1.x | go-v0.39 | webrtc-direct | - | - | ✅ | 26s | 489 | 107 |
| webkit-js-v1.x x go-v0.40 (wss, noise, yamux) | webkit-js-v1.x | go-v0.40 | wss | noise | yamux | ✅ | 26s | 439 | 115 |
| webkit-js-v1.x x go-v0.40 (webrtc-direct) | webkit-js-v1.x | go-v0.40 | webrtc-direct | - | - | ✅ | 27s | 463 | 90 |
| webkit-js-v1.x x go-v0.41 (wss, noise, yamux) | webkit-js-v1.x | go-v0.41 | wss | noise | yamux | ✅ | 26s | 457 | 104 |
| webkit-js-v1.x x go-v0.41 (webrtc-direct) | webkit-js-v1.x | go-v0.41 | webrtc-direct | - | - | ✅ | 26s | 381 | 68 |
| webkit-js-v1.x x go-v0.42 (wss, noise, yamux) | webkit-js-v1.x | go-v0.42 | wss | noise | yamux | ✅ | 26s | 280 | 58 |
| webkit-js-v1.x x go-v0.42 (webrtc-direct) | webkit-js-v1.x | go-v0.42 | webrtc-direct | - | - | ✅ | 26s | 593 | 103 |
| webkit-js-v1.x x go-v0.43 (wss, noise, yamux) | webkit-js-v1.x | go-v0.43 | wss | noise | yamux | ✅ | 27s | 452 | 90 |
| webkit-js-v1.x x go-v0.43 (webrtc-direct) | webkit-js-v1.x | go-v0.43 | webrtc-direct | - | - | ✅ | 27s | 411 | 98 |
| webkit-js-v1.x x go-v0.44 (wss, noise, yamux) | webkit-js-v1.x | go-v0.44 | wss | noise | yamux | ✅ | 27s | 372 | 85 |
| webkit-js-v1.x x go-v0.44 (webrtc-direct) | webkit-js-v1.x | go-v0.44 | webrtc-direct | - | - | ✅ | 27s | 420 | 80 |
| webkit-js-v1.x x go-v0.45 (wss, noise, yamux) | webkit-js-v1.x | go-v0.45 | wss | noise | yamux | ✅ | 27s | 474 | 148 |
| webkit-js-v1.x x go-v0.45 (webrtc-direct) | webkit-js-v1.x | go-v0.45 | webrtc-direct | - | - | ✅ | 27s | 412 | 44 |
| webkit-js-v1.x x python-v0.4 (wss, noise, mplex) | webkit-js-v1.x | python-v0.4 | wss | noise | mplex | ✅ | 26s | 298 | 53 |
| webkit-js-v1.x x python-v0.4 (wss, noise, yamux) | webkit-js-v1.x | python-v0.4 | wss | noise | yamux | ✅ | 42s | 1244 | 445 |
| webkit-js-v1.x x chromium-js-v1.x (webrtc) | webkit-js-v1.x | chromium-js-v1.x | webrtc | - | - | ✅ | 43s | 2271 | 265 |
| webkit-js-v1.x x chromium-js-v2.x (webrtc) | webkit-js-v1.x | chromium-js-v2.x | webrtc | - | - | ✅ | 46s | 1913 | 185 |
| webkit-js-v1.x x webkit-js-v1.x (webrtc) | webkit-js-v1.x | webkit-js-v1.x | webrtc | - | - | ✅ | 47s | 1406 | 95 |
| webkit-js-v2.x x rust-v0.53 (webrtc-direct) | webkit-js-v2.x | rust-v0.53 | webrtc-direct | - | - | ✅ | 45s | 583 | 76 |
| webkit-js-v1.x x firefox-js-v1.x (webrtc) | webkit-js-v1.x | firefox-js-v1.x | webrtc | - | - | ✅ | 51s | 1439 | 141 |
| webkit-js-v1.x x webkit-js-v2.x (webrtc) | webkit-js-v1.x | webkit-js-v2.x | webrtc | - | - | ✅ | 48s | 1353 | 115 |
| webkit-js-v1.x x firefox-js-v2.x (webrtc) | webkit-js-v1.x | firefox-js-v2.x | webrtc | - | - | ✅ | 53s | 1285 | 96 |
| webkit-js-v2.x x rust-v0.55 (webrtc-direct) | webkit-js-v2.x | rust-v0.55 | webrtc-direct | - | - | ✅ | 31s | 1468 | 88 |
| webkit-js-v2.x x rust-v0.54 (webrtc-direct) | webkit-js-v2.x | rust-v0.54 | webrtc-direct | - | - | ✅ | 33s | 1509 | 85 |
| webkit-js-v2.x x rust-v0.56 (webrtc-direct) | webkit-js-v2.x | rust-v0.56 | webrtc-direct | - | - | ✅ | 30s | 1500 | 85 |
| webkit-js-v2.x x go-v0.38 (wss, noise, yamux) | webkit-js-v2.x | go-v0.38 | wss | noise | yamux | ✅ | 27s | 519 | 151 |
| webkit-js-v2.x x go-v0.38 (webrtc-direct) | webkit-js-v2.x | go-v0.38 | webrtc-direct | - | - | ✅ | 28s | 402 | 83 |
| webkit-js-v2.x x go-v0.39 (wss, noise, yamux) | webkit-js-v2.x | go-v0.39 | wss | noise | yamux | ✅ | 27s | 432 | 107 |
| webkit-js-v2.x x go-v0.39 (webrtc-direct) | webkit-js-v2.x | go-v0.39 | webrtc-direct | - | - | ✅ | 27s | 370 | 65 |
| webkit-js-v2.x x go-v0.40 (wss, noise, yamux) | webkit-js-v2.x | go-v0.40 | wss | noise | yamux | ✅ | 26s | 290 | 75 |
| webkit-js-v2.x x go-v0.40 (webrtc-direct) | webkit-js-v2.x | go-v0.40 | webrtc-direct | - | - | ✅ | 28s | 471 | 84 |
| webkit-js-v2.x x go-v0.41 (wss, noise, yamux) | webkit-js-v2.x | go-v0.41 | wss | noise | yamux | ✅ | 29s | 457 | 115 |
| webkit-js-v2.x x go-v0.41 (webrtc-direct) | webkit-js-v2.x | go-v0.41 | webrtc-direct | - | - | ✅ | 29s | 433 | 71 |
| webkit-js-v2.x x go-v0.42 (wss, noise, yamux) | webkit-js-v2.x | go-v0.42 | wss | noise | yamux | ✅ | 29s | 401 | 99 |
| webkit-js-v2.x x go-v0.42 (webrtc-direct) | webkit-js-v2.x | go-v0.42 | webrtc-direct | - | - | ✅ | 28s | 408 | 65 |
| webkit-js-v2.x x go-v0.43 (wss, noise, yamux) | webkit-js-v2.x | go-v0.43 | wss | noise | yamux | ✅ | 28s | 189 | 55 |
| webkit-js-v2.x x go-v0.43 (webrtc-direct) | webkit-js-v2.x | go-v0.43 | webrtc-direct | - | - | ✅ | 28s | 462 | 79 |
| webkit-js-v2.x x go-v0.44 (wss, noise, yamux) | webkit-js-v2.x | go-v0.44 | wss | noise | yamux | ✅ | 27s | 326 | 90 |
| webkit-js-v2.x x go-v0.44 (webrtc-direct) | webkit-js-v2.x | go-v0.44 | webrtc-direct | - | - | ✅ | 39s | 542 | 111 |
| webkit-js-v2.x x go-v0.45 (wss, noise, yamux) | webkit-js-v2.x | go-v0.45 | wss | noise | yamux | ✅ | 38s | 876 | 218 |
| webkit-js-v2.x x go-v0.45 (webrtc-direct) | webkit-js-v2.x | go-v0.45 | webrtc-direct | - | - | ✅ | 38s | 610 | 62 |
| webkit-js-v2.x x python-v0.4 (wss, noise, mplex) | webkit-js-v2.x | python-v0.4 | wss | noise | mplex | ✅ | 39s | 585 | 126 |
| webkit-js-v2.x x python-v0.4 (wss, noise, yamux) | webkit-js-v2.x | python-v0.4 | wss | noise | yamux | ✅ | 38s | 591 | 188 |
| webkit-js-v2.x x chromium-js-v1.x (webrtc) | webkit-js-v2.x | chromium-js-v1.x | webrtc | - | - | ✅ | 40s | 885 | 96 |
| webkit-js-v2.x x chromium-js-v2.x (webrtc) | webkit-js-v2.x | chromium-js-v2.x | webrtc | - | - | ✅ | 40s | 937 | 41 |
| webkit-js-v2.x x firefox-js-v1.x (webrtc) | webkit-js-v2.x | firefox-js-v1.x | webrtc | - | - | ✅ | 43s | 1711 | 127 |
| chromium-rust-v0.53 x rust-v0.53 (webrtc-direct) | chromium-rust-v0.53 | rust-v0.53 | webrtc-direct | - | - | ✅ | 8s | 530.1 | 0.2 |
| chromium-rust-v0.53 x rust-v0.53 (ws, noise, mplex) | chromium-rust-v0.53 | rust-v0.53 | ws | noise | mplex | ✅ | 7s | 442.0 | 0.6 |
| chromium-rust-v0.53 x rust-v0.53 (ws, noise, yamux) | chromium-rust-v0.53 | rust-v0.53 | ws | noise | yamux | ✅ | 8s | 390.9 | 31.3 |
| chromium-rust-v0.53 x rust-v0.54 (webrtc-direct) | chromium-rust-v0.53 | rust-v0.54 | webrtc-direct | - | - | ✅ | 9s | 327.699 | 0.2 |
| chromium-rust-v0.53 x rust-v0.54 (ws, noise, mplex) | chromium-rust-v0.53 | rust-v0.54 | ws | noise | mplex | ✅ | 10s | 524.5 | 0.6 |
| chromium-rust-v0.53 x rust-v0.54 (ws, noise, yamux) | chromium-rust-v0.53 | rust-v0.54 | ws | noise | yamux | ✅ | 9s | 365.4 | 21.8 |
| chromium-rust-v0.53 x rust-v0.55 (webrtc-direct) | chromium-rust-v0.53 | rust-v0.55 | webrtc-direct | - | - | ✅ | 10s | 417.0 | 7.5 |
| chromium-rust-v0.53 x rust-v0.55 (ws, noise, mplex) | chromium-rust-v0.53 | rust-v0.55 | ws | noise | mplex | ✅ | 9s | 465.0 | 0.6 |
| chromium-rust-v0.53 x rust-v0.55 (ws, noise, yamux) | chromium-rust-v0.53 | rust-v0.55 | ws | noise | yamux | ✅ | 8s | 356.9 | 8.8 |
| chromium-rust-v0.53 x rust-v0.56 (webrtc-direct) | chromium-rust-v0.53 | rust-v0.56 | webrtc-direct | - | - | ✅ | 7s | 388.0 | 0.1 |
| chromium-rust-v0.53 x rust-v0.56 (ws, noise, mplex) | chromium-rust-v0.53 | rust-v0.56 | ws | noise | mplex | ✅ | 8s | 437.5 | 1.0 |
| chromium-rust-v0.53 x rust-v0.56 (ws, noise, yamux) | chromium-rust-v0.53 | rust-v0.56 | ws | noise | yamux | ✅ | 8s | 346.0 | 8.699 |
| webkit-js-v2.x x webkit-js-v1.x (webrtc) | webkit-js-v2.x | webkit-js-v1.x | webrtc | - | - | ✅ | 33s | 1676 | 137 |
| chromium-rust-v0.53 x go-v0.38 (webtransport) | chromium-rust-v0.53 | go-v0.38 | webtransport | - | - | ✅ | 5s | 86.6 | 1.6 |
| webkit-js-v2.x x webkit-js-v2.x (webrtc) | webkit-js-v2.x | webkit-js-v2.x | webrtc | - | - | ✅ | 34s | 853 | 31 |
| chromium-rust-v0.53 x go-v0.38 (webrtc-direct) | chromium-rust-v0.53 | go-v0.38 | webrtc-direct | - | - | ✅ | 6s | 168.3 | 0.1 |
| webkit-js-v2.x x firefox-js-v2.x (webrtc) | webkit-js-v2.x | firefox-js-v2.x | webrtc | - | - | ✅ | 37s | 706 | 60 |
| chromium-rust-v0.53 x go-v0.38 (ws, noise, yamux) | chromium-rust-v0.53 | go-v0.38 | ws | noise | yamux | ✅ | 5s | 333.4 | 9.2 |
| chromium-rust-v0.53 x go-v0.39 (webtransport) | chromium-rust-v0.53 | go-v0.39 | webtransport | - | - | ✅ | 5s | 113.9 | 0.5 |
| chromium-rust-v0.53 x go-v0.39 (webrtc-direct) | chromium-rust-v0.53 | go-v0.39 | webrtc-direct | - | - | ✅ | 5s | 204.5 | 5.9 |
| chromium-rust-v0.53 x go-v0.39 (ws, noise, yamux) | chromium-rust-v0.53 | go-v0.39 | ws | noise | yamux | ✅ | 5s | 334.299 | 5.9 |
| chromium-rust-v0.53 x go-v0.40 (webtransport) | chromium-rust-v0.53 | go-v0.40 | webtransport | - | - | ✅ | 4s | 112.7 | 1.4 |
| chromium-rust-v0.53 x go-v0.40 (webrtc-direct) | chromium-rust-v0.53 | go-v0.40 | webrtc-direct | - | - | ✅ | 6s | 1370.3 | 0.4 |
| chromium-rust-v0.53 x go-v0.40 (ws, noise, yamux) | chromium-rust-v0.53 | go-v0.40 | ws | noise | yamux | ✅ | 6s | 341.9 | 9.2 |
| chromium-rust-v0.53 x go-v0.41 (webtransport) | chromium-rust-v0.53 | go-v0.41 | webtransport | - | - | ✅ | 5s | 64.0 | 0.4 |
| chromium-rust-v0.53 x go-v0.41 (webrtc-direct) | chromium-rust-v0.53 | go-v0.41 | webrtc-direct | - | - | ✅ | 6s | 126.899 | 0.099 |
| chromium-rust-v0.53 x go-v0.41 (ws, noise, yamux) | chromium-rust-v0.53 | go-v0.41 | ws | noise | yamux | ✅ | 5s | 318.7 | 2.6 |
| chromium-rust-v0.53 x go-v0.42 (webtransport) | chromium-rust-v0.53 | go-v0.42 | webtransport | - | - | ✅ | 5s | 92.899 | 0.1 |
| chromium-rust-v0.53 x go-v0.42 (webrtc-direct) | chromium-rust-v0.53 | go-v0.42 | webrtc-direct | - | - | ✅ | 5s | 154.6 | 0.1 |
| chromium-rust-v0.53 x go-v0.42 (ws, noise, yamux) | chromium-rust-v0.53 | go-v0.42 | ws | noise | yamux | ✅ | 6s | 330.6 | 8.599 |
| chromium-rust-v0.53 x go-v0.43 (webtransport) | chromium-rust-v0.53 | go-v0.43 | webtransport | - | - | ✅ | 5s | 65.1 | 0.799 |
| chromium-rust-v0.53 x go-v0.43 (ws, noise, yamux) | chromium-rust-v0.53 | go-v0.43 | ws | noise | yamux | ✅ | 5s | 323.6 | 4.8 |
| chromium-rust-v0.53 x go-v0.43 (webrtc-direct) | chromium-rust-v0.53 | go-v0.43 | webrtc-direct | - | - | ✅ | 6s | 213.5 | 1.6 |
| chromium-rust-v0.53 x go-v0.44 (webtransport) | chromium-rust-v0.53 | go-v0.44 | webtransport | - | - | ✅ | 6s | 44.0 | 0.5 |
| chromium-rust-v0.53 x go-v0.44 (webrtc-direct) | chromium-rust-v0.53 | go-v0.44 | webrtc-direct | - | - | ✅ | 5s | 285.9 | 0.2 |
| chromium-rust-v0.53 x go-v0.44 (ws, noise, yamux) | chromium-rust-v0.53 | go-v0.44 | ws | noise | yamux | ✅ | 5s | 328.1 | 3.8 |
| chromium-rust-v0.53 x go-v0.45 (webtransport) | chromium-rust-v0.53 | go-v0.45 | webtransport | - | - | ✅ | 5s | 95.0 | 0.3 |
| chromium-rust-v0.53 x go-v0.45 (webrtc-direct) | chromium-rust-v0.53 | go-v0.45 | webrtc-direct | - | - | ✅ | 5s | 177.9 | 0.1 |
| chromium-rust-v0.53 x go-v0.45 (ws, noise, yamux) | chromium-rust-v0.53 | go-v0.45 | ws | noise | yamux | ✅ | 6s | 338.3 | 7.6 |
| chromium-rust-v0.53 x python-v0.4 (ws, noise, yamux) | chromium-rust-v0.53 | python-v0.4 | ws | noise | yamux | ✅ | 5s | 345.5 | 13.5 |
| chromium-rust-v0.53 x nim-v1.14 (ws, noise, mplex) | chromium-rust-v0.53 | nim-v1.14 | ws | noise | mplex | ✅ | 6s | 439.699 | 0.6 |
| chromium-rust-v0.53 x js-v1.x (ws, noise, mplex) | chromium-rust-v0.53 | js-v1.x | ws | noise | mplex | ✅ | 18s | 451.8 | 0.6 |
| chromium-rust-v0.53 x js-v1.x (ws, noise, yamux) | chromium-rust-v0.53 | js-v1.x | ws | noise | yamux | ✅ | 19s | 364.0 | 32.9 |
| chromium-rust-v0.53 x nim-v1.14 (ws, noise, yamux) | chromium-rust-v0.53 | nim-v1.14 | ws | noise | yamux | ✅ | 6s | 342.0 | 10.2 |
| chromium-rust-v0.53 x js-v2.x (ws, noise, mplex) | chromium-rust-v0.53 | js-v2.x | ws | noise | mplex | ✅ | 20s | 434.5 | 0.599 |
| chromium-rust-v0.53 x js-v2.x (ws, noise, yamux) | chromium-rust-v0.53 | js-v2.x | ws | noise | yamux | ✅ | 19s | 340.6 | 14.4 |
| chromium-rust-v0.53 x js-v3.x (ws, noise, mplex) | chromium-rust-v0.53 | js-v3.x | ws | noise | mplex | ✅ | 19s | 425.2 | 0.6 |
| chromium-rust-v0.53 x js-v3.x (ws, noise, yamux) | chromium-rust-v0.53 | js-v3.x | ws | noise | yamux | ✅ | 18s | 333.3 | 13.399 |
| chromium-rust-v0.54 x rust-v0.53 (webrtc-direct) | chromium-rust-v0.54 | rust-v0.53 | webrtc-direct | - | - | ✅ | 5s | 247.1 | 0.0 |
| chromium-rust-v0.54 x rust-v0.53 (ws, noise, mplex) | chromium-rust-v0.54 | rust-v0.53 | ws | noise | mplex | ✅ | 5s | 422.6 | 0.4 |
| chromium-rust-v0.53 x jvm-v1.2 (ws, noise, yamux) | chromium-rust-v0.53 | jvm-v1.2 | ws | noise | yamux | ✅ | 8s | 1174.0 | 29.5 |
| chromium-rust-v0.54 x rust-v0.53 (ws, noise, yamux) | chromium-rust-v0.54 | rust-v0.53 | ws | noise | yamux | ✅ | 5s | 332.1 | 3.7 |
| chromium-rust-v0.54 x rust-v0.54 (webrtc-direct) | chromium-rust-v0.54 | rust-v0.54 | webrtc-direct | - | - | ✅ | 5s | 204.0 | 0.1 |
| chromium-rust-v0.54 x rust-v0.54 (ws, noise, mplex) | chromium-rust-v0.54 | rust-v0.54 | ws | noise | mplex | ✅ | 4s | 413.2 | 0.5 |
| chromium-rust-v0.54 x rust-v0.54 (ws, noise, yamux) | chromium-rust-v0.54 | rust-v0.54 | ws | noise | yamux | ✅ | 4s | 322.0 | 2.7 |
| chromium-rust-v0.54 x rust-v0.55 (webrtc-direct) | chromium-rust-v0.54 | rust-v0.55 | webrtc-direct | - | - | ✅ | 4s | 189.1 | 0.1 |
| chromium-rust-v0.54 x rust-v0.55 (ws, noise, mplex) | chromium-rust-v0.54 | rust-v0.55 | ws | noise | mplex | ✅ | 5s | 415.9 | 0.2 |
| chromium-rust-v0.54 x rust-v0.55 (ws, noise, yamux) | chromium-rust-v0.54 | rust-v0.55 | ws | noise | yamux | ✅ | 4s | 331.4 | 9.0 |
| chromium-rust-v0.54 x rust-v0.56 (webrtc-direct) | chromium-rust-v0.54 | rust-v0.56 | webrtc-direct | - | - | ✅ | 5s | 298.0 | 0.2 |
| chromium-rust-v0.54 x rust-v0.56 (ws, noise, mplex) | chromium-rust-v0.54 | rust-v0.56 | ws | noise | mplex | ✅ | 4s | 415.9 | 0.2 |
| chromium-rust-v0.54 x rust-v0.56 (ws, noise, yamux) | chromium-rust-v0.54 | rust-v0.56 | ws | noise | yamux | ✅ | 5s | 325.3 | 2.5 |
| chromium-rust-v0.54 x go-v0.38 (webtransport) | chromium-rust-v0.54 | go-v0.38 | webtransport | - | - | ✅ | 5s | 41.6 | 0.3 |
| chromium-rust-v0.54 x go-v0.38 (webrtc-direct) | chromium-rust-v0.54 | go-v0.38 | webrtc-direct | - | - | ✅ | 4s | 127.9 | 0.0 |
| chromium-rust-v0.54 x go-v0.38 (ws, noise, yamux) | chromium-rust-v0.54 | go-v0.38 | ws | noise | yamux | ✅ | 4s | 327.1 | 10.4 |
| chromium-rust-v0.54 x go-v0.39 (webtransport) | chromium-rust-v0.54 | go-v0.39 | webtransport | - | - | ✅ | 4s | 61.2 | 0.3 |
| chromium-rust-v0.54 x go-v0.39 (webrtc-direct) | chromium-rust-v0.54 | go-v0.39 | webrtc-direct | - | - | ✅ | 4s | 141.0 | 0.0 |
| chromium-rust-v0.54 x go-v0.39 (ws, noise, yamux) | chromium-rust-v0.54 | go-v0.39 | ws | noise | yamux | ✅ | 5s | 330.5 | 6.4 |
| chromium-rust-v0.54 x go-v0.40 (webtransport) | chromium-rust-v0.54 | go-v0.40 | webtransport | - | - | ✅ | 4s | 66.2 | 0.6 |
| chromium-rust-v0.54 x go-v0.40 (webrtc-direct) | chromium-rust-v0.54 | go-v0.40 | webrtc-direct | - | - | ✅ | 4s | 97.4 | 0.1 |
| chromium-rust-v0.54 x go-v0.40 (ws, noise, yamux) | chromium-rust-v0.54 | go-v0.40 | ws | noise | yamux | ✅ | 4s | 319.1 | 3.8 |
| chromium-rust-v0.54 x go-v0.41 (webtransport) | chromium-rust-v0.54 | go-v0.41 | webtransport | - | - | ✅ | 5s | 49.5 | 2.3 |
| chromium-rust-v0.54 x go-v0.41 (webrtc-direct) | chromium-rust-v0.54 | go-v0.41 | webrtc-direct | - | - | ✅ | 4s | 142.4 | 0.1 |
| chromium-rust-v0.54 x go-v0.42 (webtransport) | chromium-rust-v0.54 | go-v0.42 | webtransport | - | - | ✅ | 4s | 77.9 | 0.3 |
| chromium-rust-v0.54 x go-v0.41 (ws, noise, yamux) | chromium-rust-v0.54 | go-v0.41 | ws | noise | yamux | ✅ | 5s | 333.6 | 4.9 |
| chromium-rust-v0.54 x go-v0.42 (webrtc-direct) | chromium-rust-v0.54 | go-v0.42 | webrtc-direct | - | - | ✅ | 4s | 271.0 | 0.2 |
| chromium-rust-v0.54 x go-v0.42 (ws, noise, yamux) | chromium-rust-v0.54 | go-v0.42 | ws | noise | yamux | ✅ | 5s | 320.9 | 2.6 |
| chromium-rust-v0.54 x go-v0.43 (webtransport) | chromium-rust-v0.54 | go-v0.43 | webtransport | - | - | ✅ | 5s | 75.9 | 0.3 |
| chromium-rust-v0.54 x go-v0.43 (webrtc-direct) | chromium-rust-v0.54 | go-v0.43 | webrtc-direct | - | - | ✅ | 4s | 143.3 | 0.1 |
| chromium-rust-v0.54 x go-v0.43 (ws, noise, yamux) | chromium-rust-v0.54 | go-v0.43 | ws | noise | yamux | ✅ | 5s | 323.0 | 6.6 |
| chromium-rust-v0.54 x go-v0.44 (webtransport) | chromium-rust-v0.54 | go-v0.44 | webtransport | - | - | ✅ | 4s | 86.0 | 0.8 |
| chromium-rust-v0.54 x go-v0.44 (webrtc-direct) | chromium-rust-v0.54 | go-v0.44 | webrtc-direct | - | - | ✅ | 4s | 109.4 | 0.0 |
| chromium-rust-v0.54 x go-v0.44 (ws, noise, yamux) | chromium-rust-v0.54 | go-v0.44 | ws | noise | yamux | ✅ | 5s | 325.6 | 3.2 |
| chromium-rust-v0.54 x go-v0.45 (webrtc-direct) | chromium-rust-v0.54 | go-v0.45 | webrtc-direct | - | - | ✅ | 4s | 141.2 | 0.1 |
| chromium-rust-v0.54 x go-v0.45 (webtransport) | chromium-rust-v0.54 | go-v0.45 | webtransport | - | - | ✅ | 5s | 50.5 | 0.6 |
| chromium-rust-v0.54 x go-v0.45 (ws, noise, yamux) | chromium-rust-v0.54 | go-v0.45 | ws | noise | yamux | ✅ | 5s | 327.2 | 5.2 |
| chromium-rust-v0.54 x python-v0.4 (ws, noise, yamux) | chromium-rust-v0.54 | python-v0.4 | ws | noise | yamux | ✅ | 4s | 326.0 | 3.5 |
| chromium-rust-v0.54 x python-v0.4 (ws, noise, mplex) | chromium-rust-v0.54 | python-v0.4 | ws | noise | mplex | ✅ | 15s | 10425.6 | 0.6 |
| chromium-rust-v0.54 x js-v1.x (ws, noise, mplex) | chromium-rust-v0.54 | js-v1.x | ws | noise | mplex | ✅ | 15s | 430.1 | 0.4 |
| chromium-rust-v0.54 x js-v1.x (ws, noise, yamux) | chromium-rust-v0.54 | js-v1.x | ws | noise | yamux | ✅ | 14s | 340.9 | 11.2 |
| chromium-rust-v0.54 x js-v2.x (ws, noise, mplex) | chromium-rust-v0.54 | js-v2.x | ws | noise | mplex | ✅ | 15s | 421.5 | 0.5 |
| chromium-rust-v0.54 x js-v2.x (ws, noise, yamux) | chromium-rust-v0.54 | js-v2.x | ws | noise | yamux | ✅ | 16s | 338.1 | 16.4 |
| chromium-rust-v0.54 x js-v3.x (ws, noise, mplex) | chromium-rust-v0.54 | js-v3.x | ws | noise | mplex | ✅ | 15s | 422.4 | 3.7 |
| chromium-rust-v0.54 x nim-v1.14 (ws, noise, mplex) | chromium-rust-v0.54 | nim-v1.14 | ws | noise | mplex | ✅ | 5s | 416.4 | 0.3 |
| chromium-rust-v0.54 x nim-v1.14 (ws, noise, yamux) | chromium-rust-v0.54 | nim-v1.14 | ws | noise | yamux | ✅ | 5s | 321.7 | 3.6 |
| chromium-rust-v0.54 x jvm-v1.2 (ws, noise, yamux) | chromium-rust-v0.54 | jvm-v1.2 | ws | noise | yamux | ✅ | 6s | 580.9 | 19.6 |
| chromium-rust-v0.54 x js-v3.x (ws, noise, yamux) | chromium-rust-v0.54 | js-v3.x | ws | noise | yamux | ✅ | 12s | 313.5 | 3.4 |
| chromium-rust-v0.54 x jvm-v1.2 (ws, noise, mplex) | chromium-rust-v0.54 | jvm-v1.2 | ws | noise | mplex | ✅ | 16s | 10838.7 | 1.5 |
| chromium-rust-v0.53 x python-v0.4 (ws, noise, mplex) | chromium-rust-v0.53 | python-v0.4 | ws | noise | mplex | ❌ | 184s | - | - |
| chromium-rust-v0.53 x jvm-v1.2 (ws, noise, mplex) | chromium-rust-v0.53 | jvm-v1.2 | ws | noise | mplex | ❌ | 185s | - | - |

---

## Matrix View by Transport + Secure Channel + Muxer

### quic-v1

| Dialer \ Listener | c-v0.0.1 | eth-p2p-z-v0.0.1 | go-v0.38 | go-v0.39 | go-v0.40 | go-v0.41 | go-v0.42 | go-v0.43 | go-v0.44 | go-v0.45 | jvm-v1.2 | python-v0.4 | rust-v0.53 | rust-v0.54 | rust-v0.55 | rust-v0.56 | zig-v0.0.1 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **c-v0.0.1** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **eth-p2p-z-v0.0.1** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **go-v0.38** | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.39** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.40** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.41** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.42** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.43** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.44** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **go-v0.45** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **jvm-v1.2** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **python-v0.4** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **rust-v0.53** | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **rust-v0.54** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **rust-v0.55** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **rust-v0.56** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
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
| **c-v0.0.1** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
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
| **go-v0.44** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ❌ |
| **go-v0.45** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **rust-v0.53** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ |
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

*Generated: 2025-12-27T04:05:49Z*
<!-- TEST_RESULTS_END -->

