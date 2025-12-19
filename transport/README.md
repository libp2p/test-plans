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

## Test Pass: `transport-interop-024012-19-12-2025`

**Summary:**
- **Total Tests:** 2302
- **Passed:** ✅ 2255
- **Failed:** ❌ 47
- **Pass Rate:** 98.0%

**Environment:**
- **Platform:** x86_64
- **OS:** Linux
- **Workers:** 8
- **Duration:** 3812s

**Timestamps:**
- **Started:** 2025-12-19T02:40:12Z
- **Completed:** 2025-12-19T03:43:44Z

---

## Test Results

| Test | Dialer | Listener | Transport | Secure | Muxer | Status | Duration | Handshake+RTT (ms) | Ping RTT (ms) |
|------|--------|----------|-----------|--------|-------|--------|----------|-------------------|---------------|
| rust-v0.53 x rust-v0.53 (tcp, noise, yamux) | rust-v0.53 | rust-v0.53 | tcp | noise | yamux | ✅ | 4s | 141.335 | 47.976 |
| rust-v0.53 x rust-v0.53 (ws, noise, yamux) | rust-v0.53 | rust-v0.53 | ws | noise | yamux | ✅ | 4s | 278.776 | 87.681 |
| rust-v0.53 x rust-v0.53 (ws, tls, mplex) | rust-v0.53 | rust-v0.53 | ws | tls | mplex | ✅ | 5s | 276.346 | 91.82 |
| rust-v0.53 x rust-v0.53 (ws, tls, yamux) | rust-v0.53 | rust-v0.53 | ws | tls | yamux | ✅ | 5s | 273.919 | 91.815 |
| rust-v0.53 x rust-v0.53 (tcp, noise, mplex) | rust-v0.53 | rust-v0.53 | tcp | noise | mplex | ✅ | 5s | 94.295 | 0.098 |
| rust-v0.53 x rust-v0.53 (tcp, tls, yamux) | rust-v0.53 | rust-v0.53 | tcp | tls | yamux | ✅ | 6s | 135.577 | 87.838 |
| rust-v0.53 x rust-v0.53 (tcp, tls, mplex) | rust-v0.53 | rust-v0.53 | tcp | tls | mplex | ✅ | 6s | 47.5 | 0.099 |
| rust-v0.53 x rust-v0.53 (ws, noise, mplex) | rust-v0.53 | rust-v0.53 | ws | noise | mplex | ✅ | 7s | 277.044 | 91.936 |
| rust-v0.53 x rust-v0.53 (quic-v1) | rust-v0.53 | rust-v0.53 | quic-v1 | - | - | ✅ | 4s | 4.791 | 0.358 |
| rust-v0.53 x rust-v0.53 (webrtc-direct) | rust-v0.53 | rust-v0.53 | webrtc-direct | - | - | ✅ | 4s | 214.296 | 0.333 |
| rust-v0.53 x rust-v0.54 (ws, tls, mplex) | rust-v0.53 | rust-v0.54 | ws | tls | mplex | ✅ | 4s | 265.064 | 87.76 |
| rust-v0.53 x rust-v0.54 (ws, tls, yamux) | rust-v0.53 | rust-v0.54 | ws | tls | yamux | ✅ | 5s | 270.457 | 87.753 |
| rust-v0.53 x rust-v0.54 (ws, noise, mplex) | rust-v0.53 | rust-v0.54 | ws | noise | mplex | ✅ | 5s | 261.348 | 87.856 |
| rust-v0.53 x rust-v0.54 (tcp, tls, mplex) | rust-v0.53 | rust-v0.54 | tcp | tls | mplex | ✅ | 4s | 43.906 | 1.207 |
| rust-v0.53 x rust-v0.54 (tcp, tls, yamux) | rust-v0.53 | rust-v0.54 | tcp | tls | yamux | ✅ | 5s | 136.609 | 91.755 |
| rust-v0.53 x rust-v0.54 (ws, noise, yamux) | rust-v0.53 | rust-v0.54 | ws | noise | yamux | ✅ | 6s | 269.199 | 91.775 |
| rust-v0.53 x rust-v0.54 (tcp, noise, mplex) | rust-v0.53 | rust-v0.54 | tcp | noise | mplex | ✅ | 5s | 87.503 | 0.163 |
| rust-v0.53 x rust-v0.54 (tcp, noise, yamux) | rust-v0.53 | rust-v0.54 | tcp | noise | yamux | ✅ | 4s | 136.783 | 44.007 |
| rust-v0.53 x rust-v0.54 (quic-v1) | rust-v0.53 | rust-v0.54 | quic-v1 | - | - | ✅ | 5s | 3.159 | 0.179 |
| rust-v0.53 x rust-v0.54 (webrtc-direct) | rust-v0.53 | rust-v0.54 | webrtc-direct | - | - | ✅ | 4s | 210.431 | 0.181 |
| rust-v0.53 x rust-v0.55 (ws, tls, mplex) | rust-v0.53 | rust-v0.55 | ws | tls | mplex | ✅ | 5s | 138.643 | 42.427 |
| rust-v0.53 x rust-v0.55 (ws, noise, mplex) | rust-v0.53 | rust-v0.55 | ws | noise | mplex | ✅ | 5s | 136.682 | 47.264 |
| rust-v0.53 x rust-v0.55 (ws, tls, yamux) | rust-v0.53 | rust-v0.55 | ws | tls | yamux | ✅ | 5s | 136.304 | 46.439 |
| rust-v0.53 x rust-v0.55 (ws, noise, yamux) | rust-v0.53 | rust-v0.55 | ws | noise | yamux | ✅ | 5s | 130.172 | 43.237 |
| rust-v0.53 x rust-v0.55 (tcp, tls, yamux) | rust-v0.53 | rust-v0.55 | tcp | tls | yamux | ✅ | 4s | 50.283 | 47.774 |
| rust-v0.53 x rust-v0.55 (tcp, tls, mplex) | rust-v0.53 | rust-v0.55 | tcp | tls | mplex | ✅ | 6s | 3.772 | 0.142 |
| rust-v0.53 x rust-v0.55 (tcp, noise, mplex) | rust-v0.53 | rust-v0.55 | tcp | noise | mplex | ✅ | 5s | 90.709 | 43.505 |
| rust-v0.53 x rust-v0.55 (tcp, noise, yamux) | rust-v0.53 | rust-v0.55 | tcp | noise | yamux | ✅ | 5s | 42.764 | 0.068 |
| rust-v0.53 x rust-v0.55 (quic-v1) | rust-v0.53 | rust-v0.55 | quic-v1 | - | - | ✅ | 5s | 13.012 | 0.185 |
| rust-v0.53 x rust-v0.55 (webrtc-direct) | rust-v0.53 | rust-v0.55 | webrtc-direct | - | - | ✅ | 5s | 213.597 | 0.346 |
| rust-v0.53 x rust-v0.56 (ws, tls, mplex) | rust-v0.53 | rust-v0.56 | ws | tls | mplex | ✅ | 5s | 92.461 | 0.788 |
| rust-v0.53 x rust-v0.56 (ws, tls, yamux) | rust-v0.53 | rust-v0.56 | ws | tls | yamux | ✅ | 5s | 135.29 | 42.727 |
| rust-v0.53 x rust-v0.56 (ws, noise, mplex) | rust-v0.53 | rust-v0.56 | ws | noise | mplex | ✅ | 5s | 140.087 | 47.034 |
| rust-v0.53 x rust-v0.56 (ws, noise, yamux) | rust-v0.53 | rust-v0.56 | ws | noise | yamux | ✅ | 5s | 139.059 | 43.376 |
| rust-v0.53 x rust-v0.56 (tcp, tls, mplex) | rust-v0.53 | rust-v0.56 | tcp | tls | mplex | ✅ | 5s | 3.405 | 0.09 |
| rust-v0.53 x rust-v0.56 (tcp, tls, yamux) | rust-v0.53 | rust-v0.56 | tcp | tls | yamux | ✅ | 5s | 44.887 | 41.811 |
| rust-v0.53 x rust-v0.56 (tcp, noise, mplex) | rust-v0.53 | rust-v0.56 | tcp | noise | mplex | ✅ | 5s | 48.853 | 0.035 |
| rust-v0.53 x rust-v0.56 (quic-v1) | rust-v0.53 | rust-v0.56 | quic-v1 | - | - | ✅ | 4s | 5.555 | 0.313 |
| rust-v0.53 x rust-v0.56 (tcp, noise, yamux) | rust-v0.53 | rust-v0.56 | tcp | noise | yamux | ✅ | 5s | 91.925 | 43.635 |
| rust-v0.53 x rust-v0.56 (webrtc-direct) | rust-v0.53 | rust-v0.56 | webrtc-direct | - | - | ✅ | 5s | 208.439 | 0.223 |
| rust-v0.53 x go-v0.38 (ws, tls, yamux) | rust-v0.53 | go-v0.38 | ws | tls | yamux | ✅ | 5s | 88.928 | 1.188 |
| rust-v0.53 x go-v0.38 (tcp, tls, yamux) | rust-v0.53 | go-v0.38 | tcp | tls | yamux | ✅ | 4s | 2.994 | 0.615 |
| rust-v0.53 x go-v0.38 (ws, noise, yamux) | rust-v0.53 | go-v0.38 | ws | noise | yamux | ✅ | 5s | 92.624 | 0.175 |
| rust-v0.53 x go-v0.38 (tcp, noise, yamux) | rust-v0.53 | go-v0.38 | tcp | noise | yamux | ✅ | 4s | 4.734 | 0.205 |
| rust-v0.53 x go-v0.38 (quic-v1) | rust-v0.53 | go-v0.38 | quic-v1 | - | - | ✅ | 5s | 3.725 | 0.43 |
| rust-v0.53 x go-v0.38 (webrtc-direct) | rust-v0.53 | go-v0.38 | webrtc-direct | - | - | ✅ | 5s | 53.709 | 0.826 |
| rust-v0.53 x go-v0.39 (ws, noise, yamux) | rust-v0.53 | go-v0.39 | ws | noise | yamux | ✅ | 5s | 90.484 | 0.269 |
| rust-v0.53 x go-v0.39 (ws, tls, yamux) | rust-v0.53 | go-v0.39 | ws | tls | yamux | ✅ | 6s | 94.965 | 1.194 |
| rust-v0.53 x go-v0.39 (tcp, tls, yamux) | rust-v0.53 | go-v0.39 | tcp | tls | yamux | ✅ | 5s | 2.903 | 0.396 |
| rust-v0.53 x go-v0.39 (tcp, noise, yamux) | rust-v0.53 | go-v0.39 | tcp | noise | yamux | ✅ | 5s | 4.779 | 2.466 |
| rust-v0.53 x go-v0.39 (quic-v1) | rust-v0.53 | go-v0.39 | quic-v1 | - | - | ✅ | 5s | 9.688 | 0.503 |
| rust-v0.53 x go-v0.39 (webrtc-direct) | rust-v0.53 | go-v0.39 | webrtc-direct | - | - | ✅ | 4s | 84.297 | 0.367 |
| rust-v0.53 x go-v0.40 (ws, tls, yamux) | rust-v0.53 | go-v0.40 | ws | tls | yamux | ✅ | 4s | 96.089 | 1.362 |
| rust-v0.53 x go-v0.40 (ws, noise, yamux) | rust-v0.53 | go-v0.40 | ws | noise | yamux | ✅ | 5s | 45.165 | 0.672 |
| rust-v0.53 x go-v0.40 (tcp, tls, yamux) | rust-v0.53 | go-v0.40 | tcp | tls | yamux | ✅ | 4s | 4.057 | 0.133 |
| rust-v0.53 x go-v0.40 (tcp, noise, yamux) | rust-v0.53 | go-v0.40 | tcp | noise | yamux | ✅ | 5s | 47.021 | 42.0 |
| rust-v0.53 x go-v0.40 (quic-v1) | rust-v0.53 | go-v0.40 | quic-v1 | - | - | ✅ | 4s | 4.525 | 0.423 |
| rust-v0.53 x go-v0.40 (webrtc-direct) | rust-v0.53 | go-v0.40 | webrtc-direct | - | - | ✅ | 4s | 15.584 | 0.569 |
| rust-v0.53 x go-v0.41 (ws, tls, yamux) | rust-v0.53 | go-v0.41 | ws | tls | yamux | ✅ | 5s | 136.854 | 41.754 |
| rust-v0.53 x go-v0.41 (ws, noise, yamux) | rust-v0.53 | go-v0.41 | ws | noise | yamux | ✅ | 4s | 96.45 | 0.208 |
| rust-v0.53 x go-v0.41 (tcp, tls, yamux) | rust-v0.53 | go-v0.41 | tcp | tls | yamux | ✅ | 5s | 3.543 | 0.284 |
| rust-v0.53 x go-v0.41 (tcp, noise, yamux) | rust-v0.53 | go-v0.41 | tcp | noise | yamux | ✅ | 5s | 2.886 | 0.421 |
| rust-v0.53 x go-v0.41 (quic-v1) | rust-v0.53 | go-v0.41 | quic-v1 | - | - | ✅ | 4s | 8.596 | 0.589 |
| rust-v0.53 x go-v0.41 (webrtc-direct) | rust-v0.53 | go-v0.41 | webrtc-direct | - | - | ✅ | 5s | 28.265 | 0.244 |
| rust-v0.53 x go-v0.42 (ws, tls, yamux) | rust-v0.53 | go-v0.42 | ws | tls | yamux | ✅ | 4s | 91.263 | 1.64 |
| rust-v0.53 x go-v0.42 (ws, noise, yamux) | rust-v0.53 | go-v0.42 | ws | noise | yamux | ✅ | 4s | 98.461 | 0.704 |
| rust-v0.53 x go-v0.42 (tcp, tls, yamux) | rust-v0.53 | go-v0.42 | tcp | tls | yamux | ✅ | 5s | 3.019 | 0.13 |
| rust-v0.53 x go-v0.42 (tcp, noise, yamux) | rust-v0.53 | go-v0.42 | tcp | noise | yamux | ✅ | 5s | 54.436 | 47.925 |
| rust-v0.53 x go-v0.42 (quic-v1) | rust-v0.53 | go-v0.42 | quic-v1 | - | - | ✅ | 5s | 6.199 | 1.167 |
| rust-v0.53 x go-v0.42 (webrtc-direct) | rust-v0.53 | go-v0.42 | webrtc-direct | - | - | ✅ | 4s | 14.414 | 0.82 |
| rust-v0.53 x go-v0.43 (ws, tls, yamux) | rust-v0.53 | go-v0.43 | ws | tls | yamux | ✅ | 4s | 87.609 | 0.638 |
| rust-v0.53 x go-v0.43 (ws, noise, yamux) | rust-v0.53 | go-v0.43 | ws | noise | yamux | ✅ | 5s | 136.616 | 46.541 |
| rust-v0.53 x go-v0.43 (tcp, tls, yamux) | rust-v0.53 | go-v0.43 | tcp | tls | yamux | ✅ | 5s | 5.701 | 1.19 |
| rust-v0.53 x go-v0.43 (tcp, noise, yamux) | rust-v0.53 | go-v0.43 | tcp | noise | yamux | ✅ | 6s | 4.562 | 0.226 |
| rust-v0.53 x go-v0.43 (webrtc-direct) | rust-v0.53 | go-v0.43 | webrtc-direct | - | - | ✅ | 6s | 8.458 | 0.497 |
| rust-v0.53 x go-v0.43 (quic-v1) | rust-v0.53 | go-v0.43 | quic-v1 | - | - | ✅ | 6s | 6.084 | 0.467 |
| rust-v0.53 x go-v0.44 (ws, tls, yamux) | rust-v0.53 | go-v0.44 | ws | tls | yamux | ✅ | 5s | 134.376 | 42.484 |
| rust-v0.53 x go-v0.44 (ws, noise, yamux) | rust-v0.53 | go-v0.44 | ws | noise | yamux | ✅ | 5s | 92.164 | 0.181 |
| rust-v0.53 x go-v0.44 (tcp, tls, yamux) | rust-v0.53 | go-v0.44 | tcp | tls | yamux | ✅ | 5s | 47.785 | 43.637 |
| rust-v0.53 x go-v0.44 (tcp, noise, yamux) | rust-v0.53 | go-v0.44 | tcp | noise | yamux | ✅ | 5s | 4.148 | 0.16 |
| rust-v0.53 x go-v0.44 (quic-v1) | rust-v0.53 | go-v0.44 | quic-v1 | - | - | ✅ | 5s | 4.587 | 0.136 |
| rust-v0.53 x go-v0.44 (webrtc-direct) | rust-v0.53 | go-v0.44 | webrtc-direct | - | - | ✅ | 5s | 17.992 | 0.221 |
| rust-v0.53 x go-v0.45 (ws, noise, yamux) | rust-v0.53 | go-v0.45 | ws | noise | yamux | ✅ | 5s | 97.917 | 0.385 |
| rust-v0.53 x go-v0.45 (tcp, tls, yamux) | rust-v0.53 | go-v0.45 | tcp | tls | yamux | ✅ | 4s | 44.766 | 0.242 |
| rust-v0.53 x go-v0.45 (ws, tls, yamux) | rust-v0.53 | go-v0.45 | ws | tls | yamux | ✅ | 6s | 141.847 | 45.816 |
| rust-v0.53 x go-v0.45 (tcp, noise, yamux) | rust-v0.53 | go-v0.45 | tcp | noise | yamux | ✅ | 5s | 2.956 | 0.303 |
| rust-v0.53 x go-v0.45 (quic-v1) | rust-v0.53 | go-v0.45 | quic-v1 | - | - | ✅ | 5s | 8.817 | 0.14 |
| rust-v0.53 x go-v0.45 (webrtc-direct) | rust-v0.53 | go-v0.45 | webrtc-direct | - | - | ✅ | 4s | 79.884 | 0.513 |
| rust-v0.53 x python-v0.4 (ws, noise, mplex) | rust-v0.53 | python-v0.4 | ws | noise | mplex | ✅ | 5s | 98.012 | 1.212 |
| rust-v0.53 x python-v0.4 (tcp, noise, mplex) | rust-v0.53 | python-v0.4 | tcp | noise | mplex | ✅ | 4s | 13.321 | 0.906 |
| rust-v0.53 x python-v0.4 (ws, noise, yamux) | rust-v0.53 | python-v0.4 | ws | noise | yamux | ✅ | 5s | 58.186 | 1.412 |
| rust-v0.53 x python-v0.4 (quic-v1) | rust-v0.53 | python-v0.4 | quic-v1 | - | - | ✅ | 4s | 30.977 | 12.355 |
| rust-v0.53 x python-v0.4 (tcp, noise, yamux) | rust-v0.53 | python-v0.4 | tcp | noise | yamux | ✅ | 6s | 13.075 | 0.899 |
| rust-v0.53 x js-v1.x (ws, noise, mplex) | rust-v0.53 | js-v1.x | ws | noise | mplex | ✅ | 12s | 189.685 | 18.821 |
| rust-v0.53 x js-v1.x (ws, noise, yamux) | rust-v0.53 | js-v1.x | ws | noise | yamux | ✅ | 14s | 182.751 | 17.26 |
| rust-v0.53 x js-v1.x (tcp, noise, mplex) | rust-v0.53 | js-v1.x | tcp | noise | mplex | ✅ | 13s | 124.758 | 7.621 |
| rust-v0.53 x js-v1.x (tcp, noise, yamux) | rust-v0.53 | js-v1.x | tcp | noise | yamux | ✅ | 14s | 135.06 | 9.037 |
| rust-v0.53 x js-v2.x (ws, noise, mplex) | rust-v0.53 | js-v2.x | ws | noise | mplex | ✅ | 14s | 174.204 | 12.474 |
| rust-v0.53 x js-v2.x (ws, noise, yamux) | rust-v0.53 | js-v2.x | ws | noise | yamux | ✅ | 14s | 190.189 | 10.689 |
| rust-v0.53 x js-v2.x (tcp, noise, mplex) | rust-v0.53 | js-v2.x | tcp | noise | mplex | ✅ | 14s | 101.883 | 4.84 |
| rust-v0.53 x js-v2.x (tcp, noise, yamux) | rust-v0.53 | js-v2.x | tcp | noise | yamux | ✅ | 14s | 115.246 | 7.248 |
| rust-v0.53 x nim-v1.14 (ws, noise, mplex) | rust-v0.53 | nim-v1.14 | ws | noise | mplex | ✅ | 4s | 279.97 | 95.83 |
| rust-v0.53 x nim-v1.14 (ws, noise, yamux) | rust-v0.53 | nim-v1.14 | ws | noise | yamux | ✅ | 4s | 232.169 | 45.302 |
| rust-v0.53 x nim-v1.14 (tcp, noise, mplex) | rust-v0.53 | nim-v1.14 | tcp | noise | mplex | ✅ | 4s | 96.639 | 0.165 |
| rust-v0.53 x nim-v1.14 (tcp, noise, yamux) | rust-v0.53 | nim-v1.14 | tcp | noise | yamux | ✅ | 4s | 185.627 | 45.589 |
| rust-v0.53 x js-v3.x (ws, noise, mplex) | rust-v0.53 | js-v3.x | ws | noise | mplex | ✅ | 11s | 211.034 | 71.155 |
| rust-v0.53 x js-v3.x (ws, noise, yamux) | rust-v0.53 | js-v3.x | ws | noise | yamux | ✅ | 12s | 182.017 | 34.41 |
| rust-v0.53 x js-v3.x (tcp, noise, mplex) | rust-v0.53 | js-v3.x | tcp | noise | mplex | ✅ | 12s | 115.999 | 13.186 |
| rust-v0.53 x js-v3.x (tcp, noise, yamux) | rust-v0.53 | js-v3.x | tcp | noise | yamux | ✅ | 12s | 120.397 | 20.085 |
| rust-v0.53 x jvm-v1.2 (ws, noise, mplex) | rust-v0.53 | jvm-v1.2 | ws | noise | mplex | ✅ | 8s | 1241.709 | 40.339 |
| rust-v0.53 x jvm-v1.2 (ws, tls, mplex) | rust-v0.53 | jvm-v1.2 | ws | tls | mplex | ✅ | 10s | 3009.379 | 7.513 |
| rust-v0.53 x jvm-v1.2 (ws, noise, yamux) | rust-v0.53 | jvm-v1.2 | ws | noise | yamux | ✅ | 8s | 1077.499 | 47.77 |
| rust-v0.53 x jvm-v1.2 (ws, tls, yamux) | rust-v0.53 | jvm-v1.2 | ws | tls | yamux | ✅ | 10s | 3270.242 | 44.584 |
| rust-v0.53 x jvm-v1.2 (tcp, tls, mplex) | rust-v0.53 | jvm-v1.2 | tcp | tls | mplex | ✅ | 8s | 1696.172 | 2.078 |
| rust-v0.53 x jvm-v1.2 (tcp, tls, yamux) | rust-v0.53 | jvm-v1.2 | tcp | tls | yamux | ✅ | 8s | 1831.772 | 49.654 |
| rust-v0.53 x jvm-v1.2 (tcp, noise, mplex) | rust-v0.53 | jvm-v1.2 | tcp | noise | mplex | ✅ | 8s | 748.102 | 3.978 |
| rust-v0.53 x jvm-v1.2 (tcp, noise, yamux) | rust-v0.53 | jvm-v1.2 | tcp | noise | yamux | ✅ | 7s | 462.645 | 25.764 |
| rust-v0.53 x c-v0.0.1 (tcp, noise, mplex) | rust-v0.53 | c-v0.0.1 | tcp | noise | mplex | ✅ | 5s | 43.678 | 0.046 |
| rust-v0.53 x c-v0.0.1 (tcp, noise, yamux) | rust-v0.53 | c-v0.0.1 | tcp | noise | yamux | ✅ | 5s | 109.652 | 0.355 |
| rust-v0.53 x c-v0.0.1 (quic-v1) | rust-v0.53 | c-v0.0.1 | quic-v1 | - | - | ✅ | 4s | 7.048 | 0.275 |
| rust-v0.53 x dotnet-v1.0 (tcp, noise, yamux) | rust-v0.53 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 5s | 108.485 | 2.429 |
| rust-v0.53 x jvm-v1.2 (quic-v1) | rust-v0.53 | jvm-v1.2 | quic-v1 | - | - | ✅ | 7s | 933.69 | 2.576 |
| rust-v0.53 x zig-v0.0.1 (quic-v1) | rust-v0.53 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 4s | - | - |
| rust-v0.53 x eth-p2p-z-v0.0.1 (quic-v1) | rust-v0.53 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 5s | 2.869 | 0.128 |
| rust-v0.54 x rust-v0.53 (ws, tls, mplex) | rust-v0.54 | rust-v0.53 | ws | tls | mplex | ✅ | 4s | 273.078 | 91.992 |
| rust-v0.54 x rust-v0.53 (ws, tls, yamux) | rust-v0.54 | rust-v0.53 | ws | tls | yamux | ✅ | 5s | 272.817 | 87.84 |
| rust-v0.54 x rust-v0.53 (tcp, tls, mplex) | rust-v0.54 | rust-v0.53 | tcp | tls | mplex | ✅ | 5s | 5.132 | 0.089 |
| rust-v0.54 x rust-v0.53 (ws, noise, yamux) | rust-v0.54 | rust-v0.53 | ws | noise | yamux | ✅ | 5s | 268.27 | 87.724 |
| rust-v0.54 x rust-v0.53 (ws, noise, mplex) | rust-v0.54 | rust-v0.53 | ws | noise | mplex | ✅ | 6s | 266.456 | 87.8 |
| rust-v0.54 x rust-v0.53 (tcp, tls, yamux) | rust-v0.54 | rust-v0.53 | tcp | tls | yamux | ✅ | 5s | 141.776 | 91.737 |
| rust-v0.54 x rust-v0.53 (tcp, noise, mplex) | rust-v0.54 | rust-v0.53 | tcp | noise | mplex | ✅ | 6s | 93.155 | 0.101 |
| rust-v0.54 x rust-v0.53 (tcp, noise, yamux) | rust-v0.54 | rust-v0.53 | tcp | noise | yamux | ✅ | 5s | 141.97 | 43.889 |
| rust-v0.54 x rust-v0.53 (quic-v1) | rust-v0.54 | rust-v0.53 | quic-v1 | - | - | ✅ | 5s | 3.908 | 0.305 |
| rust-v0.54 x rust-v0.53 (webrtc-direct) | rust-v0.54 | rust-v0.53 | webrtc-direct | - | - | ✅ | 5s | 216.989 | 0.558 |
| rust-v0.54 x rust-v0.54 (ws, tls, mplex) | rust-v0.54 | rust-v0.54 | ws | tls | mplex | ✅ | 5s | 275.178 | 91.829 |
| rust-v0.54 x rust-v0.54 (ws, noise, mplex) | rust-v0.54 | rust-v0.54 | ws | noise | mplex | ✅ | 4s | 274.289 | 91.891 |
| rust-v0.54 x rust-v0.54 (ws, tls, yamux) | rust-v0.54 | rust-v0.54 | ws | tls | yamux | ✅ | 5s | 269.825 | 85.761 |
| rust-v0.54 x rust-v0.54 (ws, noise, yamux) | rust-v0.54 | rust-v0.54 | ws | noise | yamux | ✅ | 5s | 266.16 | 87.707 |
| rust-v0.54 x rust-v0.54 (tcp, tls, mplex) | rust-v0.54 | rust-v0.54 | tcp | tls | mplex | ✅ | 5s | 48.672 | 0.122 |
| rust-v0.54 x rust-v0.54 (tcp, noise, mplex) | rust-v0.54 | rust-v0.54 | tcp | noise | mplex | ✅ | 4s | 91.125 | 0.094 |
| rust-v0.54 x rust-v0.54 (tcp, tls, yamux) | rust-v0.54 | rust-v0.54 | tcp | tls | yamux | ✅ | 5s | 138.986 | 91.766 |
| rust-v0.54 x rust-v0.54 (tcp, noise, yamux) | rust-v0.54 | rust-v0.54 | tcp | noise | yamux | ✅ | 4s | 134.604 | 43.85 |
| rust-v0.54 x rust-v0.54 (quic-v1) | rust-v0.54 | rust-v0.54 | quic-v1 | - | - | ✅ | 5s | 3.761 | 0.229 |
| rust-v0.54 x rust-v0.55 (ws, tls, mplex) | rust-v0.54 | rust-v0.55 | ws | tls | mplex | ✅ | 4s | 135.53 | 42.653 |
| rust-v0.54 x rust-v0.54 (webrtc-direct) | rust-v0.54 | rust-v0.54 | webrtc-direct | - | - | ✅ | 6s | 264.7 | 0.18 |
| rust-v0.54 x rust-v0.55 (ws, tls, yamux) | rust-v0.54 | rust-v0.55 | ws | tls | yamux | ✅ | 5s | 139.053 | 46.654 |
| rust-v0.54 x rust-v0.55 (ws, noise, yamux) | rust-v0.54 | rust-v0.55 | ws | noise | yamux | ✅ | 4s | 138.335 | 43.385 |
| rust-v0.54 x rust-v0.55 (ws, noise, mplex) | rust-v0.54 | rust-v0.55 | ws | noise | mplex | ✅ | 6s | 135.885 | 46.799 |
| rust-v0.54 x rust-v0.55 (tcp, tls, mplex) | rust-v0.54 | rust-v0.55 | tcp | tls | mplex | ✅ | 5s | 44.966 | 41.776 |
| rust-v0.54 x rust-v0.55 (tcp, tls, yamux) | rust-v0.54 | rust-v0.55 | tcp | tls | yamux | ✅ | 5s | 46.895 | 42.535 |
| rust-v0.54 x rust-v0.55 (tcp, noise, yamux) | rust-v0.54 | rust-v0.55 | tcp | noise | yamux | ✅ | 5s | 89.978 | 43.247 |
| rust-v0.54 x rust-v0.55 (tcp, noise, mplex) | rust-v0.54 | rust-v0.55 | tcp | noise | mplex | ✅ | 5s | 49.454 | 0.005 |
| rust-v0.54 x rust-v0.55 (quic-v1) | rust-v0.54 | rust-v0.55 | quic-v1 | - | - | ✅ | 5s | 3.691 | 0.159 |
| rust-v0.54 x rust-v0.55 (webrtc-direct) | rust-v0.54 | rust-v0.55 | webrtc-direct | - | - | ✅ | 5s | 212.254 | 0.439 |
| rust-v0.54 x rust-v0.56 (ws, tls, yamux) | rust-v0.54 | rust-v0.56 | ws | tls | yamux | ✅ | 4s | 91.441 | 0.233 |
| rust-v0.54 x rust-v0.56 (ws, tls, mplex) | rust-v0.54 | rust-v0.56 | ws | tls | mplex | ✅ | 5s | 133.561 | 46.761 |
| rust-v0.54 x rust-v0.56 (ws, noise, mplex) | rust-v0.54 | rust-v0.56 | ws | noise | mplex | ✅ | 4s | 136.795 | 47.456 |
| rust-v0.54 x rust-v0.56 (ws, noise, yamux) | rust-v0.54 | rust-v0.56 | ws | noise | yamux | ✅ | 4s | 90.509 | 0.151 |
| rust-v0.54 x rust-v0.56 (tcp, tls, mplex) | rust-v0.54 | rust-v0.56 | tcp | tls | mplex | ✅ | 5s | 5.051 | 0.045 |
| rust-v0.54 x rust-v0.56 (tcp, tls, yamux) | rust-v0.54 | rust-v0.56 | tcp | tls | yamux | ✅ | 4s | 44.822 | 42.339 |
| rust-v0.54 x rust-v0.56 (tcp, noise, mplex) | rust-v0.54 | rust-v0.56 | tcp | noise | mplex | ✅ | 5s | 50.246 | 0.043 |
| rust-v0.54 x rust-v0.56 (tcp, noise, yamux) | rust-v0.54 | rust-v0.56 | tcp | noise | yamux | ✅ | 5s | 48.701 | 0.078 |
| rust-v0.54 x rust-v0.56 (quic-v1) | rust-v0.54 | rust-v0.56 | quic-v1 | - | - | ✅ | 4s | 4.041 | 0.145 |
| rust-v0.54 x rust-v0.56 (webrtc-direct) | rust-v0.54 | rust-v0.56 | webrtc-direct | - | - | ✅ | 5s | 413.293 | 0.322 |
| rust-v0.54 x go-v0.38 (ws, tls, yamux) | rust-v0.54 | go-v0.38 | ws | tls | yamux | ✅ | 5s | 49.8 | 0.188 |
| rust-v0.54 x go-v0.38 (ws, noise, yamux) | rust-v0.54 | go-v0.38 | ws | noise | yamux | ✅ | 4s | 92.778 | 0.543 |
| rust-v0.54 x go-v0.38 (quic-v1) | rust-v0.54 | go-v0.38 | quic-v1 | - | - | ✅ | 4s | 3.657 | 0.222 |
| rust-v0.54 x go-v0.38 (tcp, tls, yamux) | rust-v0.54 | go-v0.38 | tcp | tls | yamux | ✅ | 6s | 45.388 | 40.5 |
| rust-v0.54 x go-v0.38 (tcp, noise, yamux) | rust-v0.54 | go-v0.38 | tcp | noise | yamux | ✅ | 5s | 3.134 | 0.349 |
| rust-v0.54 x go-v0.38 (webrtc-direct) | rust-v0.54 | go-v0.38 | webrtc-direct | - | - | ✅ | 5s | 7.212 | 0.198 |
| rust-v0.54 x go-v0.39 (ws, tls, yamux) | rust-v0.54 | go-v0.39 | ws | tls | yamux | ✅ | 4s | 91.875 | 0.489 |
| rust-v0.54 x go-v0.39 (ws, noise, yamux) | rust-v0.54 | go-v0.39 | ws | noise | yamux | ✅ | 5s | 87.405 | 0.619 |
| rust-v0.54 x go-v0.39 (tcp, tls, yamux) | rust-v0.54 | go-v0.39 | tcp | tls | yamux | ✅ | 5s | 2.802 | 0.194 |
| rust-v0.54 x go-v0.39 (tcp, noise, yamux) | rust-v0.54 | go-v0.39 | tcp | noise | yamux | ✅ | 5s | 5.881 | 0.148 |
| rust-v0.54 x go-v0.39 (webrtc-direct) | rust-v0.54 | go-v0.39 | webrtc-direct | - | - | ✅ | 4s | 72.803 | 0.257 |
| rust-v0.54 x go-v0.39 (quic-v1) | rust-v0.54 | go-v0.39 | quic-v1 | - | - | ✅ | 5s | 10.167 | 0.417 |
| rust-v0.54 x go-v0.40 (ws, tls, yamux) | rust-v0.54 | go-v0.40 | ws | tls | yamux | ✅ | 5s | 94.617 | 0.218 |
| rust-v0.54 x go-v0.40 (ws, noise, yamux) | rust-v0.54 | go-v0.40 | ws | noise | yamux | ✅ | 5s | 90.481 | 0.57 |
| rust-v0.54 x go-v0.40 (tcp, tls, yamux) | rust-v0.54 | go-v0.40 | tcp | tls | yamux | ✅ | 4s | 3.098 | 0.191 |
| rust-v0.54 x go-v0.40 (tcp, noise, yamux) | rust-v0.54 | go-v0.40 | tcp | noise | yamux | ✅ | 5s | 3.454 | 0.108 |
| rust-v0.54 x go-v0.40 (quic-v1) | rust-v0.54 | go-v0.40 | quic-v1 | - | - | ✅ | 5s | 5.666 | 0.275 |
| rust-v0.54 x go-v0.40 (webrtc-direct) | rust-v0.54 | go-v0.40 | webrtc-direct | - | - | ✅ | 5s | 13.863 | 0.212 |
| rust-v0.54 x go-v0.41 (ws, tls, yamux) | rust-v0.54 | go-v0.41 | ws | tls | yamux | ✅ | 4s | 94.744 | 0.374 |
| rust-v0.54 x go-v0.41 (ws, noise, yamux) | rust-v0.54 | go-v0.41 | ws | noise | yamux | ✅ | 5s | 91.421 | 0.223 |
| rust-v0.54 x go-v0.41 (tcp, noise, yamux) | rust-v0.54 | go-v0.41 | tcp | noise | yamux | ✅ | 5s | 2.959 | 0.274 |
| rust-v0.54 x go-v0.41 (tcp, tls, yamux) | rust-v0.54 | go-v0.41 | tcp | tls | yamux | ✅ | 5s | 6.947 | 0.52 |
| rust-v0.54 x go-v0.41 (quic-v1) | rust-v0.54 | go-v0.41 | quic-v1 | - | - | ✅ | 4s | 6.869 | 0.732 |
| rust-v0.54 x go-v0.41 (webrtc-direct) | rust-v0.54 | go-v0.41 | webrtc-direct | - | - | ✅ | 5s | 14.494 | 0.223 |
| rust-v0.54 x go-v0.42 (ws, tls, yamux) | rust-v0.54 | go-v0.42 | ws | tls | yamux | ✅ | 5s | 93.384 | 0.486 |
| rust-v0.54 x go-v0.42 (ws, noise, yamux) | rust-v0.54 | go-v0.42 | ws | noise | yamux | ✅ | 5s | 133.724 | 44.135 |
| rust-v0.54 x go-v0.42 (tcp, tls, yamux) | rust-v0.54 | go-v0.42 | tcp | tls | yamux | ✅ | 5s | 2.471 | 0.195 |
| rust-v0.54 x go-v0.42 (tcp, noise, yamux) | rust-v0.54 | go-v0.42 | tcp | noise | yamux | ✅ | 5s | 6.498 | 1.37 |
| rust-v0.54 x go-v0.42 (quic-v1) | rust-v0.54 | go-v0.42 | quic-v1 | - | - | ✅ | 5s | 8.109 | 0.361 |
| rust-v0.54 x go-v0.42 (webrtc-direct) | rust-v0.54 | go-v0.42 | webrtc-direct | - | - | ✅ | 5s | 70.888 | 0.197 |
| rust-v0.54 x go-v0.43 (ws, tls, yamux) | rust-v0.54 | go-v0.43 | ws | tls | yamux | ✅ | 4s | 97.628 | 0.325 |
| rust-v0.54 x go-v0.43 (ws, noise, yamux) | rust-v0.54 | go-v0.43 | ws | noise | yamux | ✅ | 5s | 91.474 | 0.362 |
| rust-v0.54 x go-v0.43 (tcp, tls, yamux) | rust-v0.54 | go-v0.43 | tcp | tls | yamux | ✅ | 5s | 52.504 | 44.109 |
| rust-v0.54 x go-v0.43 (quic-v1) | rust-v0.54 | go-v0.43 | quic-v1 | - | - | ✅ | 5s | 5.463 | 0.349 |
| rust-v0.54 x go-v0.43 (tcp, noise, yamux) | rust-v0.54 | go-v0.43 | tcp | noise | yamux | ✅ | 5s | 49.733 | 46.951 |
| rust-v0.54 x go-v0.43 (webrtc-direct) | rust-v0.54 | go-v0.43 | webrtc-direct | - | - | ✅ | 5s | 9.115 | 0.274 |
| rust-v0.54 x go-v0.44 (ws, tls, yamux) | rust-v0.54 | go-v0.44 | ws | tls | yamux | ✅ | 5s | 137.942 | 45.736 |
| rust-v0.54 x go-v0.44 (tcp, tls, yamux) | rust-v0.54 | go-v0.44 | tcp | tls | yamux | ✅ | 4s | 4.353 | 0.325 |
| rust-v0.54 x go-v0.44 (ws, noise, yamux) | rust-v0.54 | go-v0.44 | ws | noise | yamux | ✅ | 6s | 93.272 | 0.537 |
| rust-v0.54 x go-v0.44 (quic-v1) | rust-v0.54 | go-v0.44 | quic-v1 | - | - | ✅ | 5s | 13.819 | 0.513 |
| rust-v0.54 x go-v0.44 (tcp, noise, yamux) | rust-v0.54 | go-v0.44 | tcp | noise | yamux | ✅ | 6s | 4.432 | 0.683 |
| rust-v0.54 x go-v0.45 (ws, tls, yamux) | rust-v0.54 | go-v0.45 | ws | tls | yamux | ✅ | 4s | 47.766 | 0.318 |
| rust-v0.54 x go-v0.44 (webrtc-direct) | rust-v0.54 | go-v0.44 | webrtc-direct | - | - | ✅ | 6s | 212.209 | 0.678 |
| rust-v0.54 x go-v0.45 (ws, noise, yamux) | rust-v0.54 | go-v0.45 | ws | noise | yamux | ✅ | 5s | 91.349 | 0.293 |
| rust-v0.54 x go-v0.45 (tcp, noise, yamux) | rust-v0.54 | go-v0.45 | tcp | noise | yamux | ✅ | 5s | 49.656 | 45.17 |
| rust-v0.54 x go-v0.45 (tcp, tls, yamux) | rust-v0.54 | go-v0.45 | tcp | tls | yamux | ✅ | 6s | 48.721 | 0.17 |
| rust-v0.54 x go-v0.45 (quic-v1) | rust-v0.54 | go-v0.45 | quic-v1 | - | - | ✅ | 5s | 5.507 | 0.5 |
| rust-v0.54 x go-v0.45 (webrtc-direct) | rust-v0.54 | go-v0.45 | webrtc-direct | - | - | ✅ | 4s | 16.394 | 0.589 |
| rust-v0.54 x python-v0.4 (ws, noise, mplex) | rust-v0.54 | python-v0.4 | ws | noise | mplex | ✅ | 5s | 99.791 | 1.47 |
| rust-v0.54 x python-v0.4 (ws, noise, yamux) | rust-v0.54 | python-v0.4 | ws | noise | yamux | ✅ | 4s | 104.97 | 2.056 |
| rust-v0.54 x python-v0.4 (tcp, noise, mplex) | rust-v0.54 | python-v0.4 | tcp | noise | mplex | ✅ | 5s | 8.374 | 0.622 |
| rust-v0.54 x python-v0.4 (tcp, noise, yamux) | rust-v0.54 | python-v0.4 | tcp | noise | yamux | ✅ | 5s | 64.426 | 43.687 |
| rust-v0.54 x js-v1.x (ws, noise, mplex) | rust-v0.54 | js-v1.x | ws | noise | mplex | ✅ | 15s | 167.889 | 12.761 |
| rust-v0.54 x js-v1.x (ws, noise, yamux) | rust-v0.54 | js-v1.x | ws | noise | yamux | ✅ | 14s | 193.955 | 11.282 |
| rust-v0.54 x js-v1.x (tcp, noise, mplex) | rust-v0.54 | js-v1.x | tcp | noise | mplex | ✅ | 13s | 122.957 | 9.205 |
| rust-v0.54 x js-v1.x (tcp, noise, yamux) | rust-v0.54 | js-v1.x | tcp | noise | yamux | ✅ | 14s | 127.58 | 6.367 |
| rust-v0.54 x js-v2.x (ws, noise, mplex) | rust-v0.54 | js-v2.x | ws | noise | mplex | ✅ | 13s | 144.712 | 9.82 |
| rust-v0.54 x js-v2.x (ws, noise, yamux) | rust-v0.54 | js-v2.x | ws | noise | yamux | ✅ | 14s | 153.625 | 9.15 |
| rust-v0.54 x js-v2.x (tcp, noise, mplex) | rust-v0.54 | js-v2.x | tcp | noise | mplex | ✅ | 13s | 89.713 | 6.319 |
| rust-v0.54 x nim-v1.14 (ws, noise, mplex) | rust-v0.54 | nim-v1.14 | ws | noise | mplex | ✅ | 3s | 283.712 | 87.686 |
| rust-v0.54 x nim-v1.14 (ws, noise, yamux) | rust-v0.54 | nim-v1.14 | ws | noise | yamux | ✅ | 4s | 232.574 | 45.505 |
| rust-v0.54 x nim-v1.14 (tcp, noise, mplex) | rust-v0.54 | nim-v1.14 | tcp | noise | mplex | ✅ | 4s | 104.746 | 6.71 |
| rust-v0.54 x nim-v1.14 (tcp, noise, yamux) | rust-v0.54 | nim-v1.14 | tcp | noise | yamux | ✅ | 4s | 143.678 | 45.035 |
| rust-v0.54 x js-v2.x (tcp, noise, yamux) | rust-v0.54 | js-v2.x | tcp | noise | yamux | ✅ | 13s | 129.575 | 10.172 |
| rust-v0.54 x js-v3.x (ws, noise, mplex) | rust-v0.54 | js-v3.x | ws | noise | mplex | ✅ | 13s | 144.421 | 12.363 |
| rust-v0.54 x js-v3.x (tcp, noise, mplex) | rust-v0.54 | js-v3.x | tcp | noise | mplex | ✅ | 13s | 95.143 | 9.27 |
| rust-v0.54 x js-v3.x (ws, noise, yamux) | rust-v0.54 | js-v3.x | ws | noise | yamux | ✅ | 14s | 187.635 | 43.602 |
| rust-v0.54 x js-v3.x (tcp, noise, yamux) | rust-v0.54 | js-v3.x | tcp | noise | yamux | ✅ | 13s | 96.089 | 9.292 |
| rust-v0.54 x jvm-v1.2 (ws, noise, mplex) | rust-v0.54 | jvm-v1.2 | ws | noise | mplex | ✅ | 8s | 1548.027 | 95.811 |
| rust-v0.54 x jvm-v1.2 (ws, tls, mplex) | rust-v0.54 | jvm-v1.2 | ws | tls | mplex | ✅ | 10s | 3863.953 | 9.626 |
| rust-v0.54 x jvm-v1.2 (ws, noise, yamux) | rust-v0.54 | jvm-v1.2 | ws | noise | yamux | ✅ | 9s | 1709.07 | 98.5 |
| rust-v0.54 x jvm-v1.2 (ws, tls, yamux) | rust-v0.54 | jvm-v1.2 | ws | tls | yamux | ✅ | 11s | 3668.109 | 46.402 |
| rust-v0.54 x jvm-v1.2 (tcp, noise, mplex) | rust-v0.54 | jvm-v1.2 | tcp | noise | mplex | ✅ | 8s | 768.195 | 4.577 |
| rust-v0.54 x jvm-v1.2 (tcp, tls, mplex) | rust-v0.54 | jvm-v1.2 | tcp | tls | mplex | ✅ | 10s | 2286.017 | 8.503 |
| rust-v0.54 x jvm-v1.2 (tcp, tls, yamux) | rust-v0.54 | jvm-v1.2 | tcp | tls | yamux | ✅ | 10s | 2084.102 | 44.171 |
| rust-v0.54 x c-v0.0.1 (tcp, noise, mplex) | rust-v0.54 | c-v0.0.1 | tcp | noise | mplex | ✅ | 4s | 51.199 | 3.799 |
| rust-v0.54 x c-v0.0.1 (tcp, noise, yamux) | rust-v0.54 | c-v0.0.1 | tcp | noise | yamux | ✅ | 5s | 107.362 | 5.044 |
| rust-v0.54 x c-v0.0.1 (quic-v1) | rust-v0.54 | c-v0.0.1 | quic-v1 | - | - | ✅ | 5s | 16.54 | 3.328 |
| rust-v0.54 x jvm-v1.2 (tcp, noise, yamux) | rust-v0.54 | jvm-v1.2 | tcp | noise | yamux | ✅ | 7s | 725.817 | 6.215 |
| rust-v0.54 x zig-v0.0.1 (quic-v1) | rust-v0.54 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 4s | - | - |
| rust-v0.54 x dotnet-v1.0 (tcp, noise, yamux) | rust-v0.54 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 5s | 140.115 | 6.158 |
| rust-v0.54 x jvm-v1.2 (quic-v1) | rust-v0.54 | jvm-v1.2 | quic-v1 | - | - | ✅ | 8s | 1434.302 | 5.436 |
| rust-v0.54 x eth-p2p-z-v0.0.1 (quic-v1) | rust-v0.54 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 4s | 3.482 | 0.153 |
| rust-v0.55 x rust-v0.53 (ws, tls, yamux) | rust-v0.55 | rust-v0.53 | ws | tls | yamux | ✅ | 4s | 137.036 | 43.484 |
| rust-v0.55 x rust-v0.53 (ws, tls, mplex) | rust-v0.55 | rust-v0.53 | ws | tls | mplex | ✅ | 5s | 94.71 | 0.297 |
| rust-v0.55 x rust-v0.53 (ws, noise, mplex) | rust-v0.55 | rust-v0.53 | ws | noise | mplex | ✅ | 4s | 91.311 | 0.687 |
| rust-v0.55 x rust-v0.53 (ws, noise, yamux) | rust-v0.55 | rust-v0.53 | ws | noise | yamux | ✅ | 5s | 131.373 | 43.957 |
| rust-v0.55 x rust-v0.53 (tcp, tls, mplex) | rust-v0.55 | rust-v0.53 | tcp | tls | mplex | ✅ | 4s | 47.478 | 0.37 |
| rust-v0.55 x rust-v0.53 (tcp, tls, yamux) | rust-v0.55 | rust-v0.53 | tcp | tls | yamux | ✅ | 5s | 89.116 | 43.656 |
| rust-v0.55 x rust-v0.53 (tcp, noise, mplex) | rust-v0.55 | rust-v0.53 | tcp | noise | mplex | ✅ | 5s | 48.821 | 0.304 |
| rust-v0.55 x rust-v0.53 (tcp, noise, yamux) | rust-v0.55 | rust-v0.53 | tcp | noise | yamux | ✅ | 4s | 42.347 | 0.113 |
| rust-v0.55 x rust-v0.53 (quic-v1) | rust-v0.55 | rust-v0.53 | quic-v1 | - | - | ✅ | 4s | 3.607 | 0.29 |
| rust-v0.55 x rust-v0.53 (webrtc-direct) | rust-v0.55 | rust-v0.53 | webrtc-direct | - | - | ✅ | 4s | 211.0 | 0.225 |
| rust-v0.55 x rust-v0.54 (ws, tls, mplex) | rust-v0.55 | rust-v0.54 | ws | tls | mplex | ✅ | 5s | 143.528 | 47.906 |
| rust-v0.55 x rust-v0.54 (ws, tls, yamux) | rust-v0.55 | rust-v0.54 | ws | tls | yamux | ✅ | 4s | 45.941 | 0.132 |
| rust-v0.55 x rust-v0.54 (ws, noise, mplex) | rust-v0.55 | rust-v0.54 | ws | noise | mplex | ✅ | 4s | 91.435 | 0.476 |
| rust-v0.55 x rust-v0.54 (ws, noise, yamux) | rust-v0.55 | rust-v0.54 | ws | noise | yamux | ✅ | 4s | 86.582 | 0.155 |
| rust-v0.55 x rust-v0.54 (tcp, tls, mplex) | rust-v0.55 | rust-v0.54 | tcp | tls | mplex | ✅ | 5s | 45.827 | 0.192 |
| rust-v0.55 x rust-v0.54 (tcp, tls, yamux) | rust-v0.55 | rust-v0.54 | tcp | tls | yamux | ✅ | 5s | 87.715 | 43.744 |
| rust-v0.55 x rust-v0.54 (tcp, noise, mplex) | rust-v0.55 | rust-v0.54 | tcp | noise | mplex | ✅ | 4s | 45.062 | 0.134 |
| rust-v0.55 x rust-v0.54 (tcp, noise, yamux) | rust-v0.55 | rust-v0.54 | tcp | noise | yamux | ✅ | 4s | 5.723 | 0.338 |
| rust-v0.55 x rust-v0.54 (quic-v1) | rust-v0.55 | rust-v0.54 | quic-v1 | - | - | ✅ | 5s | 3.222 | 0.219 |
| rust-v0.55 x rust-v0.55 (ws, tls, mplex) | rust-v0.55 | rust-v0.55 | ws | tls | mplex | ✅ | 4s | 6.279 | 0.118 |
| rust-v0.55 x rust-v0.54 (webrtc-direct) | rust-v0.55 | rust-v0.54 | webrtc-direct | - | - | ✅ | 5s | 222.433 | 0.655 |
| rust-v0.55 x rust-v0.55 (ws, noise, mplex) | rust-v0.55 | rust-v0.55 | ws | noise | mplex | ✅ | 4s | 2.862 | 0.067 |
| rust-v0.55 x rust-v0.55 (ws, tls, yamux) | rust-v0.55 | rust-v0.55 | ws | tls | yamux | ✅ | 4s | 5.611 | 0.21 |
| rust-v0.55 x rust-v0.55 (ws, noise, yamux) | rust-v0.55 | rust-v0.55 | ws | noise | yamux | ✅ | 5s | 2.311 | 0.107 |
| rust-v0.55 x rust-v0.55 (tcp, tls, mplex) | rust-v0.55 | rust-v0.55 | tcp | tls | mplex | ✅ | 4s | 5.406 | 0.081 |
| rust-v0.55 x rust-v0.55 (tcp, tls, yamux) | rust-v0.55 | rust-v0.55 | tcp | tls | yamux | ✅ | 4s | 4.048 | 0.116 |
| rust-v0.55 x rust-v0.55 (tcp, noise, mplex) | rust-v0.55 | rust-v0.55 | tcp | noise | mplex | ✅ | 4s | 2.209 | 0.094 |
| rust-v0.55 x rust-v0.55 (tcp, noise, yamux) | rust-v0.55 | rust-v0.55 | tcp | noise | yamux | ✅ | 4s | 1.747 | 0.086 |
| rust-v0.55 x rust-v0.55 (quic-v1) | rust-v0.55 | rust-v0.55 | quic-v1 | - | - | ✅ | 5s | 3.365 | 0.222 |
| rust-v0.55 x rust-v0.56 (ws, tls, mplex) | rust-v0.55 | rust-v0.56 | ws | tls | mplex | ✅ | 4s | 5.282 | 0.082 |
| rust-v0.55 x rust-v0.55 (webrtc-direct) | rust-v0.55 | rust-v0.55 | webrtc-direct | - | - | ✅ | 4s | 210.251 | 0.425 |
| rust-v0.55 x rust-v0.56 (ws, tls, yamux) | rust-v0.55 | rust-v0.56 | ws | tls | yamux | ✅ | 5s | 9.374 | 0.427 |
| rust-v0.55 x rust-v0.56 (ws, noise, yamux) | rust-v0.55 | rust-v0.56 | ws | noise | yamux | ✅ | 4s | 6.46 | 0.457 |
| rust-v0.55 x rust-v0.56 (tcp, tls, mplex) | rust-v0.55 | rust-v0.56 | tcp | tls | mplex | ✅ | 4s | 4.122 | 0.094 |
| rust-v0.55 x rust-v0.56 (ws, noise, mplex) | rust-v0.55 | rust-v0.56 | ws | noise | mplex | ✅ | 5s | 3.736 | 0.095 |
| rust-v0.55 x rust-v0.56 (tcp, tls, yamux) | rust-v0.55 | rust-v0.56 | tcp | tls | yamux | ✅ | 4s | 5.825 | 0.24 |
| rust-v0.55 x rust-v0.56 (tcp, noise, mplex) | rust-v0.55 | rust-v0.56 | tcp | noise | mplex | ✅ | 5s | 3.087 | 0.136 |
| rust-v0.55 x rust-v0.56 (tcp, noise, yamux) | rust-v0.55 | rust-v0.56 | tcp | noise | yamux | ✅ | 4s | 8.162 | 0.205 |
| rust-v0.55 x rust-v0.56 (quic-v1) | rust-v0.55 | rust-v0.56 | quic-v1 | - | - | ✅ | 4s | 5.081 | 0.408 |
| rust-v0.55 x go-v0.38 (ws, tls, yamux) | rust-v0.55 | go-v0.38 | ws | tls | yamux | ✅ | 4s | 2.918 | 0.335 |
| rust-v0.55 x rust-v0.56 (webrtc-direct) | rust-v0.55 | rust-v0.56 | webrtc-direct | - | - | ✅ | 5s | 232.45 | 0.233 |
| rust-v0.55 x go-v0.38 (ws, noise, yamux) | rust-v0.55 | go-v0.38 | ws | noise | yamux | ✅ | 5s | 4.371 | 0.627 |
| rust-v0.55 x go-v0.38 (tcp, tls, yamux) | rust-v0.55 | go-v0.38 | tcp | tls | yamux | ✅ | 4s | 6.631 | 0.731 |
| rust-v0.55 x go-v0.38 (tcp, noise, yamux) | rust-v0.55 | go-v0.38 | tcp | noise | yamux | ✅ | 5s | 3.856 | 0.528 |
| rust-v0.55 x go-v0.38 (quic-v1) | rust-v0.55 | go-v0.38 | quic-v1 | - | - | ✅ | 4s | 4.446 | 0.329 |
| rust-v0.55 x go-v0.38 (webrtc-direct) | rust-v0.55 | go-v0.38 | webrtc-direct | - | - | ✅ | 4s | 7.402 | 0.155 |
| rust-v0.55 x go-v0.39 (ws, tls, yamux) | rust-v0.55 | go-v0.39 | ws | tls | yamux | ✅ | 4s | 3.939 | 0.274 |
| rust-v0.55 x go-v0.39 (ws, noise, yamux) | rust-v0.55 | go-v0.39 | ws | noise | yamux | ✅ | 4s | 4.046 | 0.46 |
| rust-v0.55 x go-v0.39 (tcp, tls, yamux) | rust-v0.55 | go-v0.39 | tcp | tls | yamux | ✅ | 4s | 5.102 | 1.131 |
| rust-v0.55 x go-v0.39 (tcp, noise, yamux) | rust-v0.55 | go-v0.39 | tcp | noise | yamux | ✅ | 4s | 4.226 | 0.419 |
| rust-v0.55 x go-v0.39 (quic-v1) | rust-v0.55 | go-v0.39 | quic-v1 | - | - | ✅ | 4s | 7.852 | 3.616 |
| rust-v0.55 x go-v0.39 (webrtc-direct) | rust-v0.55 | go-v0.39 | webrtc-direct | - | - | ✅ | 4s | 20.889 | 0.431 |
| rust-v0.55 x go-v0.40 (ws, tls, yamux) | rust-v0.55 | go-v0.40 | ws | tls | yamux | ✅ | 4s | 5.713 | 0.542 |
| rust-v0.55 x go-v0.40 (ws, noise, yamux) | rust-v0.55 | go-v0.40 | ws | noise | yamux | ✅ | 4s | 3.779 | 0.341 |
| rust-v0.55 x go-v0.40 (tcp, tls, yamux) | rust-v0.55 | go-v0.40 | tcp | tls | yamux | ✅ | 5s | 5.351 | 0.861 |
| rust-v0.55 x go-v0.40 (tcp, noise, yamux) | rust-v0.55 | go-v0.40 | tcp | noise | yamux | ✅ | 4s | 4.882 | 1.098 |
| rust-v0.55 x go-v0.40 (quic-v1) | rust-v0.55 | go-v0.40 | quic-v1 | - | - | ✅ | 4s | 3.941 | 0.198 |
| rust-v0.55 x go-v0.40 (webrtc-direct) | rust-v0.55 | go-v0.40 | webrtc-direct | - | - | ✅ | 4s | 218.214 | 0.478 |
| rust-v0.55 x go-v0.41 (ws, noise, yamux) | rust-v0.55 | go-v0.41 | ws | noise | yamux | ✅ | 4s | 3.767 | 0.405 |
| rust-v0.55 x go-v0.41 (ws, tls, yamux) | rust-v0.55 | go-v0.41 | ws | tls | yamux | ✅ | 5s | 8.7 | 0.822 |
| rust-v0.55 x go-v0.41 (tcp, noise, yamux) | rust-v0.55 | go-v0.41 | tcp | noise | yamux | ✅ | 4s | 4.778 | 0.461 |
| rust-v0.55 x go-v0.41 (tcp, tls, yamux) | rust-v0.55 | go-v0.41 | tcp | tls | yamux | ✅ | 5s | 7.878 | 0.372 |
| rust-v0.55 x go-v0.41 (quic-v1) | rust-v0.55 | go-v0.41 | quic-v1 | - | - | ✅ | 4s | 7.093 | 0.234 |
| rust-v0.55 x go-v0.41 (webrtc-direct) | rust-v0.55 | go-v0.41 | webrtc-direct | - | - | ✅ | 4s | 8.282 | 0.133 |
| rust-v0.55 x go-v0.42 (ws, tls, yamux) | rust-v0.55 | go-v0.42 | ws | tls | yamux | ✅ | 4s | 4.123 | 0.314 |
| rust-v0.55 x go-v0.42 (ws, noise, yamux) | rust-v0.55 | go-v0.42 | ws | noise | yamux | ✅ | 4s | 3.963 | 0.641 |
| rust-v0.55 x go-v0.42 (tcp, tls, yamux) | rust-v0.55 | go-v0.42 | tcp | tls | yamux | ✅ | 4s | 3.692 | 0.199 |
| rust-v0.55 x go-v0.42 (tcp, noise, yamux) | rust-v0.55 | go-v0.42 | tcp | noise | yamux | ✅ | 4s | 8.183 | 1.932 |
| rust-v0.55 x go-v0.42 (webrtc-direct) | rust-v0.55 | go-v0.42 | webrtc-direct | - | - | ✅ | 5s | 12.489 | 0.565 |
| rust-v0.55 x go-v0.42 (quic-v1) | rust-v0.55 | go-v0.42 | quic-v1 | - | - | ✅ | 5s | 17.296 | 0.986 |
| rust-v0.55 x go-v0.43 (ws, tls, yamux) | rust-v0.55 | go-v0.43 | ws | tls | yamux | ✅ | 4s | 3.809 | 0.405 |
| rust-v0.55 x go-v0.43 (ws, noise, yamux) | rust-v0.55 | go-v0.43 | ws | noise | yamux | ✅ | 4s | 4.462 | 0.456 |
| rust-v0.55 x go-v0.43 (tcp, tls, yamux) | rust-v0.55 | go-v0.43 | tcp | tls | yamux | ✅ | 5s | 5.263 | 0.673 |
| rust-v0.55 x go-v0.43 (tcp, noise, yamux) | rust-v0.55 | go-v0.43 | tcp | noise | yamux | ✅ | 4s | 4.053 | 0.669 |
| rust-v0.55 x go-v0.43 (quic-v1) | rust-v0.55 | go-v0.43 | quic-v1 | - | - | ✅ | 4s | 3.641 | 0.279 |
| rust-v0.55 x go-v0.43 (webrtc-direct) | rust-v0.55 | go-v0.43 | webrtc-direct | - | - | ✅ | 4s | 17.139 | 0.342 |
| rust-v0.55 x go-v0.44 (ws, noise, yamux) | rust-v0.55 | go-v0.44 | ws | noise | yamux | ✅ | 3s | 6.062 | 0.362 |
| rust-v0.55 x go-v0.44 (ws, tls, yamux) | rust-v0.55 | go-v0.44 | ws | tls | yamux | ✅ | 5s | 6.83 | 0.289 |
| rust-v0.55 x go-v0.44 (tcp, tls, yamux) | rust-v0.55 | go-v0.44 | tcp | tls | yamux | ✅ | 4s | 5.614 | 0.251 |
| rust-v0.55 x go-v0.44 (tcp, noise, yamux) | rust-v0.55 | go-v0.44 | tcp | noise | yamux | ✅ | 4s | 4.365 | 0.125 |
| rust-v0.55 x go-v0.44 (quic-v1) | rust-v0.55 | go-v0.44 | quic-v1 | - | - | ✅ | 5s | 4.751 | 1.179 |
| rust-v0.55 x go-v0.44 (webrtc-direct) | rust-v0.55 | go-v0.44 | webrtc-direct | - | - | ✅ | 4s | 36.911 | 0.521 |
| rust-v0.55 x go-v0.45 (ws, tls, yamux) | rust-v0.55 | go-v0.45 | ws | tls | yamux | ✅ | 4s | 10.464 | 0.552 |
| rust-v0.55 x go-v0.45 (tcp, tls, yamux) | rust-v0.55 | go-v0.45 | tcp | tls | yamux | ✅ | 4s | 5.787 | 0.237 |
| rust-v0.55 x go-v0.45 (ws, noise, yamux) | rust-v0.55 | go-v0.45 | ws | noise | yamux | ✅ | 4s | 7.676 | 0.241 |
| rust-v0.55 x go-v0.45 (tcp, noise, yamux) | rust-v0.55 | go-v0.45 | tcp | noise | yamux | ✅ | 4s | 2.988 | 0.084 |
| rust-v0.55 x go-v0.45 (quic-v1) | rust-v0.55 | go-v0.45 | quic-v1 | - | - | ✅ | 4s | 8.992 | 1.607 |
| rust-v0.55 x go-v0.45 (webrtc-direct) | rust-v0.55 | go-v0.45 | webrtc-direct | - | - | ✅ | 4s | 19.551 | 0.366 |
| rust-v0.55 x python-v0.4 (ws, noise, mplex) | rust-v0.55 | python-v0.4 | ws | noise | mplex | ✅ | 5s | 16.172 | 1.299 |
| rust-v0.55 x python-v0.4 (ws, noise, yamux) | rust-v0.55 | python-v0.4 | ws | noise | yamux | ✅ | 4s | 22.622 | 1.846 |
| rust-v0.55 x python-v0.4 (tcp, noise, mplex) | rust-v0.55 | python-v0.4 | tcp | noise | mplex | ✅ | 4s | 18.173 | 0.977 |
| rust-v0.55 x python-v0.4 (tcp, noise, yamux) | rust-v0.55 | python-v0.4 | tcp | noise | yamux | ✅ | 4s | 10.426 | 0.72 |
| rust-v0.55 x python-v0.4 (quic-v1) | rust-v0.55 | python-v0.4 | quic-v1 | - | - | ✅ | 4s | 88.662 | 15.482 |
| rust-v0.55 x js-v1.x (ws, noise, mplex) | rust-v0.55 | js-v1.x | ws | noise | mplex | ✅ | 16s | 106.235 | 11.602 |
| rust-v0.55 x js-v1.x (ws, noise, yamux) | rust-v0.55 | js-v1.x | ws | noise | yamux | ✅ | 15s | 138.988 | 13.773 |
| rust-v0.55 x js-v1.x (tcp, noise, mplex) | rust-v0.55 | js-v1.x | tcp | noise | mplex | ✅ | 16s | 96.11 | 8.41 |
| rust-v0.55 x js-v1.x (tcp, noise, yamux) | rust-v0.55 | js-v1.x | tcp | noise | yamux | ✅ | 15s | 96.329 | 9.481 |
| rust-v0.55 x js-v2.x (ws, noise, mplex) | rust-v0.55 | js-v2.x | ws | noise | mplex | ✅ | 16s | 71.384 | 8.251 |
| rust-v0.55 x js-v2.x (ws, noise, yamux) | rust-v0.55 | js-v2.x | ws | noise | yamux | ✅ | 16s | 109.271 | 14.896 |
| rust-v0.55 x js-v2.x (tcp, noise, mplex) | rust-v0.55 | js-v2.x | tcp | noise | mplex | ✅ | 16s | 124.059 | 5.757 |
| rust-v0.55 x nim-v1.14 (ws, noise, mplex) | rust-v0.55 | nim-v1.14 | ws | noise | mplex | ✅ | 4s | 161.396 | 47.853 |
| rust-v0.55 x nim-v1.14 (ws, noise, yamux) | rust-v0.55 | nim-v1.14 | ws | noise | yamux | ✅ | 4s | 104.74 | 4.515 |
| rust-v0.55 x nim-v1.14 (tcp, noise, mplex) | rust-v0.55 | nim-v1.14 | tcp | noise | mplex | ✅ | 4s | 69.555 | 0.319 |
| rust-v0.55 x nim-v1.14 (tcp, noise, yamux) | rust-v0.55 | nim-v1.14 | tcp | noise | yamux | ✅ | 5s | 107.419 | 1.935 |
| rust-v0.55 x js-v2.x (tcp, noise, yamux) | rust-v0.55 | js-v2.x | tcp | noise | yamux | ✅ | 15s | 97.058 | 11.723 |
| rust-v0.55 x js-v3.x (ws, noise, mplex) | rust-v0.55 | js-v3.x | ws | noise | mplex | ✅ | 15s | 87.945 | 14.865 |
| rust-v0.55 x js-v3.x (ws, noise, yamux) | rust-v0.55 | js-v3.x | ws | noise | yamux | ✅ | 15s | 84.218 | 15.725 |
| rust-v0.55 x js-v3.x (tcp, noise, mplex) | rust-v0.55 | js-v3.x | tcp | noise | mplex | ✅ | 15s | 108.326 | 55.406 |
| rust-v0.55 x js-v3.x (tcp, noise, yamux) | rust-v0.55 | js-v3.x | tcp | noise | yamux | ✅ | 15s | 82.041 | 14.346 |
| rust-v0.55 x jvm-v1.2 (ws, tls, mplex) | rust-v0.55 | jvm-v1.2 | ws | tls | mplex | ✅ | 10s | 4062.38 | 21.198 |
| rust-v0.55 x jvm-v1.2 (ws, noise, mplex) | rust-v0.55 | jvm-v1.2 | ws | noise | mplex | ✅ | 9s | 970.793 | 4.986 |
| rust-v0.55 x jvm-v1.2 (ws, noise, yamux) | rust-v0.55 | jvm-v1.2 | ws | noise | yamux | ✅ | 9s | 1423.908 | 8.89 |
| rust-v0.55 x jvm-v1.2 (ws, tls, yamux) | rust-v0.55 | jvm-v1.2 | ws | tls | yamux | ✅ | 12s | 4418.14 | 14.365 |
| rust-v0.55 x jvm-v1.2 (tcp, noise, mplex) | rust-v0.55 | jvm-v1.2 | tcp | noise | mplex | ✅ | 9s | 821.428 | 3.437 |
| rust-v0.55 x jvm-v1.2 (tcp, tls, mplex) | rust-v0.55 | jvm-v1.2 | tcp | tls | mplex | ✅ | 12s | 2988.143 | 9.244 |
| rust-v0.55 x jvm-v1.2 (tcp, tls, yamux) | rust-v0.55 | jvm-v1.2 | tcp | tls | yamux | ✅ | 11s | 2545.785 | 4.709 |
| rust-v0.55 x c-v0.0.1 (tcp, noise, yamux) | rust-v0.55 | c-v0.0.1 | tcp | noise | yamux | ✅ | 4s | 62.494 | 0.27 |
| rust-v0.55 x c-v0.0.1 (tcp, noise, mplex) | rust-v0.55 | c-v0.0.1 | tcp | noise | mplex | ✅ | 4s | 15.752 | 9.65 |
| rust-v0.55 x jvm-v1.2 (tcp, noise, yamux) | rust-v0.55 | jvm-v1.2 | tcp | noise | yamux | ✅ | 7s | 804.288 | 4.158 |
| rust-v0.55 x c-v0.0.1 (quic-v1) | rust-v0.55 | c-v0.0.1 | quic-v1 | - | - | ✅ | 5s | 13.358 | 0.434 |
| rust-v0.55 x zig-v0.0.1 (quic-v1) | rust-v0.55 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 4s | - | - |
| rust-v0.55 x dotnet-v1.0 (tcp, noise, yamux) | rust-v0.55 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 5s | 143.827 | 7.876 |
| rust-v0.55 x jvm-v1.2 (quic-v1) | rust-v0.55 | jvm-v1.2 | quic-v1 | - | - | ✅ | 9s | 1290.721 | 4.871 |
| rust-v0.55 x eth-p2p-z-v0.0.1 (quic-v1) | rust-v0.55 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 5s | 4.126 | 0.268 |
| rust-v0.56 x rust-v0.53 (ws, tls, yamux) | rust-v0.56 | rust-v0.53 | ws | tls | yamux | ✅ | 4s | 144.485 | 47.737 |
| rust-v0.56 x rust-v0.53 (ws, tls, mplex) | rust-v0.56 | rust-v0.53 | ws | tls | mplex | ✅ | 5s | 97.944 | 1.583 |
| rust-v0.56 x rust-v0.53 (ws, noise, mplex) | rust-v0.56 | rust-v0.53 | ws | noise | mplex | ✅ | 5s | 97.682 | 0.242 |
| rust-v0.56 x rust-v0.53 (ws, noise, yamux) | rust-v0.56 | rust-v0.53 | ws | noise | yamux | ✅ | 5s | 132.086 | 43.46 |
| rust-v0.56 x rust-v0.53 (tcp, tls, yamux) | rust-v0.56 | rust-v0.53 | tcp | tls | yamux | ✅ | 4s | 94.824 | 46.333 |
| rust-v0.56 x rust-v0.53 (tcp, tls, mplex) | rust-v0.56 | rust-v0.53 | tcp | tls | mplex | ✅ | 5s | 49.264 | 0.233 |
| rust-v0.56 x rust-v0.53 (tcp, noise, mplex) | rust-v0.56 | rust-v0.53 | tcp | noise | mplex | ✅ | 4s | 48.525 | 0.277 |
| rust-v0.56 x rust-v0.53 (tcp, noise, yamux) | rust-v0.56 | rust-v0.53 | tcp | noise | yamux | ✅ | 4s | 45.81 | 0.377 |
| rust-v0.56 x rust-v0.53 (quic-v1) | rust-v0.56 | rust-v0.53 | quic-v1 | - | - | ✅ | 4s | 5.183 | 0.719 |
| rust-v0.56 x rust-v0.53 (webrtc-direct) | rust-v0.56 | rust-v0.53 | webrtc-direct | - | - | ✅ | 5s | 213.201 | 0.555 |
| rust-v0.56 x rust-v0.54 (ws, tls, yamux) | rust-v0.56 | rust-v0.54 | ws | tls | yamux | ✅ | 3s | 49.879 | 0.827 |
| rust-v0.56 x rust-v0.54 (ws, tls, mplex) | rust-v0.56 | rust-v0.54 | ws | tls | mplex | ✅ | 5s | 85.62 | 0.33 |
| rust-v0.56 x rust-v0.54 (ws, noise, mplex) | rust-v0.56 | rust-v0.54 | ws | noise | mplex | ✅ | 4s | 90.198 | 0.37 |
| rust-v0.56 x rust-v0.54 (tcp, tls, mplex) | rust-v0.56 | rust-v0.54 | tcp | tls | mplex | ✅ | 3s | 47.92 | 0.275 |
| rust-v0.56 x rust-v0.54 (ws, noise, yamux) | rust-v0.56 | rust-v0.54 | ws | noise | yamux | ✅ | 5s | 96.737 | 0.728 |
| rust-v0.56 x rust-v0.54 (tcp, tls, yamux) | rust-v0.56 | rust-v0.54 | tcp | tls | yamux | ✅ | 4s | 90.36 | 43.52 |
| rust-v0.56 x rust-v0.54 (tcp, noise, mplex) | rust-v0.56 | rust-v0.54 | tcp | noise | mplex | ✅ | 4s | 45.841 | 0.172 |
| rust-v0.56 x rust-v0.54 (tcp, noise, yamux) | rust-v0.56 | rust-v0.54 | tcp | noise | yamux | ✅ | 4s | 6.349 | 0.339 |
| rust-v0.56 x rust-v0.54 (quic-v1) | rust-v0.56 | rust-v0.54 | quic-v1 | - | - | ✅ | 5s | 9.505 | 0.826 |
| rust-v0.56 x rust-v0.54 (webrtc-direct) | rust-v0.56 | rust-v0.54 | webrtc-direct | - | - | ✅ | 4s | 209.064 | 0.2 |
| rust-v0.56 x rust-v0.55 (ws, tls, mplex) | rust-v0.56 | rust-v0.55 | ws | tls | mplex | ✅ | 3s | 2.914 | 0.105 |
| rust-v0.56 x rust-v0.55 (ws, tls, yamux) | rust-v0.56 | rust-v0.55 | ws | tls | yamux | ✅ | 5s | 6.057 | 0.339 |
| rust-v0.56 x rust-v0.55 (ws, noise, mplex) | rust-v0.56 | rust-v0.55 | ws | noise | mplex | ✅ | 4s | 5.493 | 0.811 |
| rust-v0.56 x rust-v0.55 (ws, noise, yamux) | rust-v0.56 | rust-v0.55 | ws | noise | yamux | ✅ | 4s | 3.241 | 0.132 |
| rust-v0.56 x rust-v0.55 (tcp, tls, mplex) | rust-v0.56 | rust-v0.55 | tcp | tls | mplex | ✅ | 5s | 5.308 | 0.121 |
| rust-v0.56 x rust-v0.55 (tcp, tls, yamux) | rust-v0.56 | rust-v0.55 | tcp | tls | yamux | ✅ | 4s | 5.804 | 0.38 |
| rust-v0.56 x rust-v0.55 (tcp, noise, yamux) | rust-v0.56 | rust-v0.55 | tcp | noise | yamux | ✅ | 4s | 2.159 | 0.092 |
| rust-v0.56 x rust-v0.55 (tcp, noise, mplex) | rust-v0.56 | rust-v0.55 | tcp | noise | mplex | ✅ | 5s | 2.391 | 0.073 |
| rust-v0.56 x rust-v0.55 (quic-v1) | rust-v0.56 | rust-v0.55 | quic-v1 | - | - | ✅ | 4s | 4.67 | 0.17 |
| rust-v0.56 x rust-v0.56 (ws, tls, mplex) | rust-v0.56 | rust-v0.56 | ws | tls | mplex | ✅ | 4s | 3.966 | 0.055 |
| rust-v0.56 x rust-v0.55 (webrtc-direct) | rust-v0.56 | rust-v0.55 | webrtc-direct | - | - | ✅ | 4s | 214.212 | 0.369 |
| rust-v0.56 x rust-v0.56 (ws, tls, yamux) | rust-v0.56 | rust-v0.56 | ws | tls | yamux | ✅ | 4s | 3.191 | 0.261 |
| rust-v0.56 x rust-v0.56 (ws, noise, mplex) | rust-v0.56 | rust-v0.56 | ws | noise | mplex | ✅ | 4s | 3.462 | 0.28 |
| rust-v0.56 x rust-v0.56 (ws, noise, yamux) | rust-v0.56 | rust-v0.56 | ws | noise | yamux | ✅ | 4s | 3.908 | 0.208 |
| rust-v0.56 x rust-v0.56 (tcp, tls, mplex) | rust-v0.56 | rust-v0.56 | tcp | tls | mplex | ✅ | 4s | 10.362 | 0.228 |
| rust-v0.56 x rust-v0.56 (tcp, tls, yamux) | rust-v0.56 | rust-v0.56 | tcp | tls | yamux | ✅ | 5s | 6.175 | 0.148 |
| rust-v0.56 x rust-v0.56 (tcp, noise, mplex) | rust-v0.56 | rust-v0.56 | tcp | noise | mplex | ✅ | 4s | 2.702 | 0.067 |
| rust-v0.56 x rust-v0.56 (tcp, noise, yamux) | rust-v0.56 | rust-v0.56 | tcp | noise | yamux | ✅ | 4s | 3.255 | 0.145 |
| rust-v0.56 x rust-v0.56 (quic-v1) | rust-v0.56 | rust-v0.56 | quic-v1 | - | - | ✅ | 4s | 4.879 | 0.361 |
| rust-v0.56 x rust-v0.56 (webrtc-direct) | rust-v0.56 | rust-v0.56 | webrtc-direct | - | - | ✅ | 5s | 222.44 | 0.803 |
| rust-v0.56 x go-v0.38 (ws, tls, yamux) | rust-v0.56 | go-v0.38 | ws | tls | yamux | ✅ | 4s | 4.457 | 0.298 |
| rust-v0.56 x go-v0.38 (ws, noise, yamux) | rust-v0.56 | go-v0.38 | ws | noise | yamux | ✅ | 4s | 3.529 | 0.231 |
| rust-v0.56 x go-v0.38 (tcp, noise, yamux) | rust-v0.56 | go-v0.38 | tcp | noise | yamux | ✅ | 4s | 9.116 | 2.184 |
| rust-v0.56 x go-v0.38 (tcp, tls, yamux) | rust-v0.56 | go-v0.38 | tcp | tls | yamux | ✅ | 5s | 5.783 | 0.278 |
| rust-v0.56 x go-v0.38 (quic-v1) | rust-v0.56 | go-v0.38 | quic-v1 | - | - | ✅ | 5s | 4.781 | 0.227 |
| rust-v0.56 x go-v0.38 (webrtc-direct) | rust-v0.56 | go-v0.38 | webrtc-direct | - | - | ✅ | 5s | 26.008 | 4.645 |
| rust-v0.56 x go-v0.39 (ws, tls, yamux) | rust-v0.56 | go-v0.39 | ws | tls | yamux | ✅ | 4s | 10.103 | 1.389 |
| rust-v0.56 x go-v0.39 (ws, noise, yamux) | rust-v0.56 | go-v0.39 | ws | noise | yamux | ✅ | 4s | 8.191 | 0.765 |
| rust-v0.56 x go-v0.39 (tcp, tls, yamux) | rust-v0.56 | go-v0.39 | tcp | tls | yamux | ✅ | 5s | 5.503 | 0.742 |
| rust-v0.56 x go-v0.39 (tcp, noise, yamux) | rust-v0.56 | go-v0.39 | tcp | noise | yamux | ✅ | 4s | 6.149 | 0.593 |
| rust-v0.56 x go-v0.39 (quic-v1) | rust-v0.56 | go-v0.39 | quic-v1 | - | - | ✅ | 4s | 3.845 | 0.245 |
| rust-v0.56 x go-v0.39 (webrtc-direct) | rust-v0.56 | go-v0.39 | webrtc-direct | - | - | ✅ | 5s | 9.644 | 0.347 |
| rust-v0.56 x go-v0.40 (ws, noise, yamux) | rust-v0.56 | go-v0.40 | ws | noise | yamux | ✅ | 4s | 8.997 | 0.367 |
| rust-v0.56 x go-v0.40 (ws, tls, yamux) | rust-v0.56 | go-v0.40 | ws | tls | yamux | ✅ | 5s | 12.567 | 0.983 |
| rust-v0.54 x python-v0.4 (quic-v1) | rust-v0.54 | python-v0.4 | quic-v1 | - | - | ❌ | 196s | - | - |
| rust-v0.56 x go-v0.40 (tcp, tls, yamux) | rust-v0.56 | go-v0.40 | tcp | tls | yamux | ✅ | 5s | 6.722 | 0.387 |
| rust-v0.56 x go-v0.40 (tcp, noise, yamux) | rust-v0.56 | go-v0.40 | tcp | noise | yamux | ✅ | 5s | 3.976 | 0.777 |
| rust-v0.56 x go-v0.40 (quic-v1) | rust-v0.56 | go-v0.40 | quic-v1 | - | - | ✅ | 4s | 5.442 | 0.731 |
| rust-v0.56 x go-v0.40 (webrtc-direct) | rust-v0.56 | go-v0.40 | webrtc-direct | - | - | ✅ | 4s | 102.515 | 0.317 |
| rust-v0.56 x go-v0.41 (ws, tls, yamux) | rust-v0.56 | go-v0.41 | ws | tls | yamux | ✅ | 4s | 5.582 | 0.355 |
| rust-v0.56 x go-v0.41 (tcp, tls, yamux) | rust-v0.56 | go-v0.41 | tcp | tls | yamux | ✅ | 4s | 4.448 | 0.566 |
| rust-v0.56 x go-v0.41 (ws, noise, yamux) | rust-v0.56 | go-v0.41 | ws | noise | yamux | ✅ | 5s | 10.437 | 0.365 |
| rust-v0.56 x go-v0.41 (tcp, noise, yamux) | rust-v0.56 | go-v0.41 | tcp | noise | yamux | ✅ | 5s | 4.855 | 0.838 |
| rust-v0.56 x go-v0.41 (quic-v1) | rust-v0.56 | go-v0.41 | quic-v1 | - | - | ✅ | 5s | 4.297 | 0.774 |
| rust-v0.56 x go-v0.41 (webrtc-direct) | rust-v0.56 | go-v0.41 | webrtc-direct | - | - | ✅ | 5s | 8.54 | 0.433 |
| rust-v0.56 x go-v0.42 (ws, tls, yamux) | rust-v0.56 | go-v0.42 | ws | tls | yamux | ✅ | 5s | 4.347 | 0.258 |
| rust-v0.56 x go-v0.42 (ws, noise, yamux) | rust-v0.56 | go-v0.42 | ws | noise | yamux | ✅ | 4s | 7.0 | 0.264 |
| rust-v0.56 x go-v0.42 (tcp, tls, yamux) | rust-v0.56 | go-v0.42 | tcp | tls | yamux | ✅ | 5s | 8.329 | 0.51 |
| rust-v0.56 x go-v0.42 (tcp, noise, yamux) | rust-v0.56 | go-v0.42 | tcp | noise | yamux | ✅ | 3s | 2.087 | 0.094 |
| rust-v0.56 x go-v0.42 (quic-v1) | rust-v0.56 | go-v0.42 | quic-v1 | - | - | ✅ | 5s | 9.26 | 0.508 |
| rust-v0.56 x go-v0.42 (webrtc-direct) | rust-v0.56 | go-v0.42 | webrtc-direct | - | - | ✅ | 4s | 117.674 | 0.705 |
| rust-v0.56 x go-v0.43 (ws, noise, yamux) | rust-v0.56 | go-v0.43 | ws | noise | yamux | ✅ | 5s | 4.165 | 0.647 |
| rust-v0.56 x go-v0.43 (ws, tls, yamux) | rust-v0.56 | go-v0.43 | ws | tls | yamux | ✅ | 5s | 3.598 | 0.418 |
| rust-v0.56 x go-v0.43 (tcp, tls, yamux) | rust-v0.56 | go-v0.43 | tcp | tls | yamux | ✅ | 5s | 3.499 | 0.197 |
| rust-v0.56 x go-v0.43 (tcp, noise, yamux) | rust-v0.56 | go-v0.43 | tcp | noise | yamux | ✅ | 5s | 3.696 | 0.334 |
| rust-v0.56 x go-v0.43 (quic-v1) | rust-v0.56 | go-v0.43 | quic-v1 | - | - | ✅ | 5s | 11.124 | 0.351 |
| rust-v0.56 x go-v0.43 (webrtc-direct) | rust-v0.56 | go-v0.43 | webrtc-direct | - | - | ✅ | 5s | 20.599 | 0.473 |
| rust-v0.56 x go-v0.44 (ws, tls, yamux) | rust-v0.56 | go-v0.44 | ws | tls | yamux | ✅ | 5s | 4.059 | 0.546 |
| rust-v0.56 x go-v0.44 (ws, noise, yamux) | rust-v0.56 | go-v0.44 | ws | noise | yamux | ✅ | 4s | 5.832 | 1.342 |
| rust-v0.56 x go-v0.44 (tcp, tls, yamux) | rust-v0.56 | go-v0.44 | tcp | tls | yamux | ✅ | 5s | 5.396 | 0.252 |
| rust-v0.56 x go-v0.44 (tcp, noise, yamux) | rust-v0.56 | go-v0.44 | tcp | noise | yamux | ✅ | 4s | 4.716 | 1.475 |
| rust-v0.56 x go-v0.44 (quic-v1) | rust-v0.56 | go-v0.44 | quic-v1 | - | - | ✅ | 4s | 5.462 | 0.221 |
| rust-v0.56 x go-v0.44 (webrtc-direct) | rust-v0.56 | go-v0.44 | webrtc-direct | - | - | ✅ | 5s | 48.665 | 0.601 |
| rust-v0.56 x go-v0.45 (ws, tls, yamux) | rust-v0.56 | go-v0.45 | ws | tls | yamux | ✅ | 4s | 3.143 | 0.197 |
| rust-v0.56 x go-v0.45 (ws, noise, yamux) | rust-v0.56 | go-v0.45 | ws | noise | yamux | ✅ | 5s | 4.101 | 0.188 |
| rust-v0.56 x go-v0.45 (tcp, tls, yamux) | rust-v0.56 | go-v0.45 | tcp | tls | yamux | ✅ | 5s | 8.33 | 0.753 |
| rust-v0.56 x go-v0.45 (quic-v1) | rust-v0.56 | go-v0.45 | quic-v1 | - | - | ✅ | 5s | 6.54 | 0.486 |
| rust-v0.56 x go-v0.45 (tcp, noise, yamux) | rust-v0.56 | go-v0.45 | tcp | noise | yamux | ✅ | 5s | 5.908 | 0.558 |
| rust-v0.56 x go-v0.45 (webrtc-direct) | rust-v0.56 | go-v0.45 | webrtc-direct | - | - | ✅ | 4s | 9.143 | 0.411 |
| rust-v0.56 x python-v0.4 (ws, noise, mplex) | rust-v0.56 | python-v0.4 | ws | noise | mplex | ✅ | 5s | 10.169 | 1.248 |
| rust-v0.56 x python-v0.4 (ws, noise, yamux) | rust-v0.56 | python-v0.4 | ws | noise | yamux | ✅ | 4s | 29.028 | 1.446 |
| rust-v0.56 x python-v0.4 (tcp, noise, mplex) | rust-v0.56 | python-v0.4 | tcp | noise | mplex | ✅ | 5s | 16.577 | 1.456 |
| rust-v0.56 x python-v0.4 (tcp, noise, yamux) | rust-v0.56 | python-v0.4 | tcp | noise | yamux | ✅ | 5s | 18.273 | 1.755 |
| rust-v0.56 x python-v0.4 (quic-v1) | rust-v0.56 | python-v0.4 | quic-v1 | - | - | ❌ | 15s | - | - |
| rust-v0.56 x js-v1.x (ws, noise, yamux) | rust-v0.56 | js-v1.x | ws | noise | yamux | ✅ | 17s | 131.945 | 15.318 |
| rust-v0.56 x js-v1.x (ws, noise, mplex) | rust-v0.56 | js-v1.x | ws | noise | mplex | ✅ | 19s | 145.928 | 14.94 |
| rust-v0.56 x js-v1.x (tcp, noise, mplex) | rust-v0.56 | js-v1.x | tcp | noise | mplex | ✅ | 18s | 118.281 | 11.81 |
| rust-v0.56 x js-v1.x (tcp, noise, yamux) | rust-v0.56 | js-v1.x | tcp | noise | yamux | ✅ | 17s | 161.401 | 11.604 |
| rust-v0.56 x js-v2.x (ws, noise, mplex) | rust-v0.56 | js-v2.x | ws | noise | mplex | ✅ | 17s | 166.618 | 17.365 |
| rust-v0.56 x js-v2.x (ws, noise, yamux) | rust-v0.56 | js-v2.x | ws | noise | yamux | ✅ | 17s | 116.084 | 20.037 |
| rust-v0.56 x js-v2.x (tcp, noise, mplex) | rust-v0.56 | js-v2.x | tcp | noise | mplex | ✅ | 18s | 87.315 | 9.372 |
| rust-v0.56 x nim-v1.14 (ws, noise, mplex) | rust-v0.56 | nim-v1.14 | ws | noise | mplex | ✅ | 4s | 156.466 | 43.811 |
| rust-v0.56 x nim-v1.14 (ws, noise, yamux) | rust-v0.56 | nim-v1.14 | ws | noise | yamux | ✅ | 5s | 108.887 | 3.88 |
| rust-v0.56 x nim-v1.14 (tcp, noise, mplex) | rust-v0.56 | nim-v1.14 | tcp | noise | mplex | ✅ | 5s | 169.679 | 43.713 |
| rust-v0.56 x nim-v1.14 (tcp, noise, yamux) | rust-v0.56 | nim-v1.14 | tcp | noise | yamux | ✅ | 5s | 128.043 | 1.264 |
| rust-v0.56 x js-v2.x (tcp, noise, yamux) | rust-v0.56 | js-v2.x | tcp | noise | yamux | ✅ | 17s | 128.167 | 12.564 |
| rust-v0.56 x js-v3.x (ws, noise, mplex) | rust-v0.56 | js-v3.x | ws | noise | mplex | ✅ | 18s | 129.696 | 18.908 |
| rust-v0.56 x js-v3.x (ws, noise, yamux) | rust-v0.56 | js-v3.x | ws | noise | yamux | ✅ | 18s | 126.844 | 23.981 |
| rust-v0.56 x js-v3.x (tcp, noise, yamux) | rust-v0.56 | js-v3.x | tcp | noise | yamux | ✅ | 19s | 111.903 | 23.507 |
| rust-v0.56 x js-v3.x (tcp, noise, mplex) | rust-v0.56 | js-v3.x | tcp | noise | mplex | ✅ | 19s | 138.174 | 19.476 |
| rust-v0.56 x jvm-v1.2 (ws, tls, mplex) | rust-v0.56 | jvm-v1.2 | ws | tls | mplex | ✅ | 12s | 3788.41 | 8.842 |
| rust-v0.56 x jvm-v1.2 (ws, tls, yamux) | rust-v0.56 | jvm-v1.2 | ws | tls | yamux | ✅ | 12s | 3408.401 | 5.323 |
| rust-v0.56 x jvm-v1.2 (ws, noise, mplex) | rust-v0.56 | jvm-v1.2 | ws | noise | mplex | ✅ | 8s | 903.636 | 8.515 |
| rust-v0.56 x jvm-v1.2 (ws, noise, yamux) | rust-v0.56 | jvm-v1.2 | ws | noise | yamux | ✅ | 8s | 911.84 | 27.32 |
| rust-v0.56 x c-v0.0.1 (tcp, noise, mplex) | rust-v0.56 | c-v0.0.1 | tcp | noise | mplex | ✅ | 5s | 37.273 | 24.754 |
| rust-v0.56 x c-v0.0.1 (tcp, noise, yamux) | rust-v0.56 | c-v0.0.1 | tcp | noise | yamux | ✅ | 6s | 96.222 | 2.321 |
| rust-v0.56 x jvm-v1.2 (tcp, noise, mplex) | rust-v0.56 | jvm-v1.2 | tcp | noise | mplex | ✅ | 10s | 1360.551 | 14.575 |
| rust-v0.56 x jvm-v1.2 (tcp, noise, yamux) | rust-v0.56 | jvm-v1.2 | tcp | noise | yamux | ✅ | 10s | 1440.343 | 8.344 |
| rust-v0.56 x jvm-v1.2 (tcp, tls, mplex) | rust-v0.56 | jvm-v1.2 | tcp | tls | mplex | ✅ | 12s | 4493.146 | 7.955 |
| rust-v0.56 x c-v0.0.1 (quic-v1) | rust-v0.56 | c-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 15.927 | 1.643 |
| rust-v0.56 x jvm-v1.2 (tcp, tls, yamux) | rust-v0.56 | jvm-v1.2 | tcp | tls | yamux | ✅ | 12s | 3841.401 | 4.126 |
| rust-v0.56 x jvm-v1.2 (quic-v1) | rust-v0.56 | jvm-v1.2 | quic-v1 | - | - | ✅ | 12s | 373.92 | 5.023 |
| rust-v0.56 x dotnet-v1.0 (tcp, noise, yamux) | rust-v0.56 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 5s | 171.316 | 41.724 |
| rust-v0.56 x zig-v0.0.1 (quic-v1) | rust-v0.56 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 4s | - | - |
| rust-v0.56 x eth-p2p-z-v0.0.1 (quic-v1) | rust-v0.56 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 4s | 5.023 | 0.2 |
| go-v0.38 x rust-v0.53 (tcp, tls, yamux) | go-v0.38 | rust-v0.53 | tcp | tls | yamux | ✅ | 4s | 93.338 | 47.385 |
| go-v0.38 x rust-v0.53 (tcp, noise, yamux) | go-v0.38 | rust-v0.53 | tcp | noise | yamux | ✅ | 5s | 142.071 | 43.888 |
| go-v0.38 x rust-v0.53 (ws, noise, yamux) | go-v0.38 | rust-v0.53 | ws | noise | yamux | ✅ | 5s | 180.49 | 41.278 |
| go-v0.38 x rust-v0.53 (ws, tls, yamux) | go-v0.38 | rust-v0.53 | ws | tls | yamux | ✅ | 6s | 138.045 | 0.708 |
| go-v0.38 x rust-v0.53 (quic-v1) | go-v0.38 | rust-v0.53 | quic-v1 | - | - | ✅ | 5s | 7.402 | 0.496 |
| go-v0.38 x rust-v0.53 (webrtc-direct) | go-v0.38 | rust-v0.53 | webrtc-direct | - | - | ✅ | 5s | 411.917 | 0.512 |
| go-v0.38 x rust-v0.54 (tcp, tls, yamux) | go-v0.38 | rust-v0.54 | tcp | tls | yamux | ✅ | 5s | 95.633 | 42.002 |
| go-v0.38 x rust-v0.54 (tcp, noise, yamux) | go-v0.38 | rust-v0.54 | tcp | noise | yamux | ✅ | 5s | 93.888 | 42.06 |
| go-v0.38 x rust-v0.54 (ws, tls, yamux) | go-v0.38 | rust-v0.54 | ws | tls | yamux | ✅ | 5s | 183.529 | 42.37 |
| go-v0.38 x rust-v0.54 (ws, noise, yamux) | go-v0.38 | rust-v0.54 | ws | noise | yamux | ✅ | 5s | 186.36 | 46.603 |
| go-v0.38 x rust-v0.54 (quic-v1) | go-v0.38 | rust-v0.54 | quic-v1 | - | - | ✅ | 4s | 5.849 | 0.233 |
| go-v0.38 x rust-v0.55 (tcp, tls, yamux) | go-v0.38 | rust-v0.55 | tcp | tls | yamux | ✅ | 5s | 8.928 | 0.451 |
| go-v0.38 x rust-v0.55 (tcp, noise, yamux) | go-v0.38 | rust-v0.55 | tcp | noise | yamux | ✅ | 4s | 4.507 | 0.406 |
| go-v0.38 x rust-v0.54 (webrtc-direct) | go-v0.38 | rust-v0.54 | webrtc-direct | - | - | ✅ | 5s | 209.951 | 0.649 |
| go-v0.38 x rust-v0.55 (ws, tls, yamux) | go-v0.38 | rust-v0.55 | ws | tls | yamux | ✅ | 4s | 6.107 | 0.384 |
| go-v0.38 x rust-v0.55 (quic-v1) | go-v0.38 | rust-v0.55 | quic-v1 | - | - | ✅ | 5s | 8.729 | 0.463 |
| go-v0.38 x rust-v0.55 (ws, noise, yamux) | go-v0.38 | rust-v0.55 | ws | noise | yamux | ✅ | 5s | 17.855 | 1.8 |
| go-v0.38 x rust-v0.56 (tcp, tls, yamux) | go-v0.38 | rust-v0.56 | tcp | tls | yamux | ✅ | 4s | 6.376 | 0.194 |
| go-v0.38 x rust-v0.55 (webrtc-direct) | go-v0.38 | rust-v0.55 | webrtc-direct | - | - | ✅ | 5s | 409.324 | 0.53 |
| go-v0.38 x rust-v0.56 (tcp, noise, yamux) | go-v0.38 | rust-v0.56 | tcp | noise | yamux | ✅ | 5s | 27.747 | 4.106 |
| go-v0.38 x rust-v0.56 (ws, tls, yamux) | go-v0.38 | rust-v0.56 | ws | tls | yamux | ✅ | 4s | 21.292 | 0.518 |
| go-v0.38 x rust-v0.56 (ws, noise, yamux) | go-v0.38 | rust-v0.56 | ws | noise | yamux | ✅ | 4s | 10.574 | 0.591 |
| go-v0.38 x rust-v0.56 (quic-v1) | go-v0.38 | rust-v0.56 | quic-v1 | - | - | ✅ | 5s | 7.66 | 0.463 |
| go-v0.38 x go-v0.38 (tcp, tls, yamux) | go-v0.38 | go-v0.38 | tcp | tls | yamux | ✅ | 4s | 10.957 | 0.744 |
| go-v0.38 x go-v0.38 (tcp, noise, yamux) | go-v0.38 | go-v0.38 | tcp | noise | yamux | ✅ | 5s | 7.621 | 0.387 |
| go-v0.38 x go-v0.38 (ws, tls, yamux) | go-v0.38 | go-v0.38 | ws | tls | yamux | ✅ | 4s | 6.52 | 0.267 |
| go-v0.38 x go-v0.38 (ws, noise, yamux) | go-v0.38 | go-v0.38 | ws | noise | yamux | ✅ | 4s | 8.433 | 0.971 |
| go-v0.38 x go-v0.38 (wss, tls, yamux) | go-v0.38 | go-v0.38 | wss | tls | yamux | ✅ | 4s | 19.533 | 1.008 |
| go-v0.38 x go-v0.38 (quic-v1) | go-v0.38 | go-v0.38 | quic-v1 | - | - | ✅ | 4s | 6.354 | 0.239 |
| go-v0.38 x go-v0.38 (wss, noise, yamux) | go-v0.38 | go-v0.38 | wss | noise | yamux | ✅ | 5s | 8.467 | 0.315 |
| go-v0.38 x rust-v0.56 (webrtc-direct) | go-v0.38 | rust-v0.56 | webrtc-direct | - | - | ❌ | 10s | - | - |
| go-v0.38 x go-v0.38 (webtransport) | go-v0.38 | go-v0.38 | webtransport | - | - | ✅ | 4s | 9.321 | 0.287 |
| go-v0.38 x go-v0.38 (webrtc-direct) | go-v0.38 | go-v0.38 | webrtc-direct | - | - | ✅ | 4s | 213.155 | 0.401 |
| go-v0.38 x go-v0.39 (tcp, noise, yamux) | go-v0.38 | go-v0.39 | tcp | noise | yamux | ✅ | 4s | 10.458 | 1.17 |
| go-v0.38 x go-v0.39 (tcp, tls, yamux) | go-v0.38 | go-v0.39 | tcp | tls | yamux | ✅ | 5s | 8.709 | 0.581 |
| go-v0.38 x go-v0.39 (ws, noise, yamux) | go-v0.38 | go-v0.39 | ws | noise | yamux | ✅ | 4s | 15.599 | 1.97 |
| go-v0.38 x go-v0.39 (ws, tls, yamux) | go-v0.38 | go-v0.39 | ws | tls | yamux | ✅ | 5s | 12.217 | 3.304 |
| go-v0.38 x go-v0.39 (wss, tls, yamux) | go-v0.38 | go-v0.39 | wss | tls | yamux | ✅ | 4s | 13.686 | 0.771 |
| go-v0.38 x go-v0.39 (wss, noise, yamux) | go-v0.38 | go-v0.39 | wss | noise | yamux | ✅ | 5s | 7.081 | 0.171 |
| go-v0.38 x go-v0.39 (quic-v1) | go-v0.38 | go-v0.39 | quic-v1 | - | - | ✅ | 5s | 14.545 | 0.814 |
| go-v0.38 x go-v0.39 (webtransport) | go-v0.38 | go-v0.39 | webtransport | - | - | ✅ | 4s | 10.955 | 0.309 |
| go-v0.38 x go-v0.39 (webrtc-direct) | go-v0.38 | go-v0.39 | webrtc-direct | - | - | ✅ | 5s | 225.837 | 1.725 |
| go-v0.38 x go-v0.40 (tcp, tls, yamux) | go-v0.38 | go-v0.40 | tcp | tls | yamux | ✅ | 4s | 12.847 | 0.669 |
| go-v0.38 x go-v0.40 (tcp, noise, yamux) | go-v0.38 | go-v0.40 | tcp | noise | yamux | ✅ | 4s | 12.057 | 0.36 |
| go-v0.38 x go-v0.40 (ws, tls, yamux) | go-v0.38 | go-v0.40 | ws | tls | yamux | ✅ | 5s | 10.089 | 0.939 |
| go-v0.38 x go-v0.40 (ws, noise, yamux) | go-v0.38 | go-v0.40 | ws | noise | yamux | ✅ | 4s | 12.741 | 2.782 |
| go-v0.38 x go-v0.40 (wss, tls, yamux) | go-v0.38 | go-v0.40 | wss | tls | yamux | ✅ | 5s | 9.798 | 0.367 |
| go-v0.38 x go-v0.40 (wss, noise, yamux) | go-v0.38 | go-v0.40 | wss | noise | yamux | ✅ | 5s | 18.035 | 2.278 |
| go-v0.38 x go-v0.40 (quic-v1) | go-v0.38 | go-v0.40 | quic-v1 | - | - | ✅ | 4s | 9.74 | 0.518 |
| go-v0.38 x go-v0.40 (webtransport) | go-v0.38 | go-v0.40 | webtransport | - | - | ✅ | 4s | 6.587 | 0.429 |
| go-v0.38 x go-v0.40 (webrtc-direct) | go-v0.38 | go-v0.40 | webrtc-direct | - | - | ✅ | 5s | 213.039 | 0.274 |
| go-v0.38 x go-v0.41 (tcp, tls, yamux) | go-v0.38 | go-v0.41 | tcp | tls | yamux | ✅ | 5s | 6.298 | 0.863 |
| go-v0.38 x go-v0.41 (tcp, noise, yamux) | go-v0.38 | go-v0.41 | tcp | noise | yamux | ✅ | 4s | 10.268 | 0.466 |
| go-v0.38 x go-v0.41 (ws, tls, yamux) | go-v0.38 | go-v0.41 | ws | tls | yamux | ✅ | 5s | 8.414 | 0.22 |
| go-v0.38 x go-v0.41 (ws, noise, yamux) | go-v0.38 | go-v0.41 | ws | noise | yamux | ✅ | 4s | 15.976 | 0.953 |
| go-v0.38 x go-v0.41 (wss, tls, yamux) | go-v0.38 | go-v0.41 | wss | tls | yamux | ✅ | 4s | 8.254 | 0.23 |
| go-v0.38 x go-v0.41 (wss, noise, yamux) | go-v0.38 | go-v0.41 | wss | noise | yamux | ✅ | 5s | 13.758 | 0.649 |
| go-v0.38 x go-v0.41 (webtransport) | go-v0.38 | go-v0.41 | webtransport | - | - | ✅ | 5s | 10.394 | 0.849 |
| go-v0.38 x go-v0.41 (quic-v1) | go-v0.38 | go-v0.41 | quic-v1 | - | - | ✅ | 5s | 9.752 | 0.827 |
| go-v0.38 x go-v0.41 (webrtc-direct) | go-v0.38 | go-v0.41 | webrtc-direct | - | - | ✅ | 5s | 209.198 | 0.416 |
| go-v0.38 x go-v0.42 (tcp, tls, yamux) | go-v0.38 | go-v0.42 | tcp | tls | yamux | ✅ | 4s | 7.181 | 0.632 |
| go-v0.38 x go-v0.42 (tcp, noise, yamux) | go-v0.38 | go-v0.42 | tcp | noise | yamux | ✅ | 5s | 11.423 | 1.05 |
| go-v0.38 x go-v0.42 (ws, tls, yamux) | go-v0.38 | go-v0.42 | ws | tls | yamux | ✅ | 5s | 8.998 | 0.294 |
| go-v0.38 x go-v0.42 (ws, noise, yamux) | go-v0.38 | go-v0.42 | ws | noise | yamux | ✅ | 5s | 7.808 | 0.527 |
| go-v0.38 x go-v0.42 (wss, tls, yamux) | go-v0.38 | go-v0.42 | wss | tls | yamux | ✅ | 4s | 18.385 | 0.617 |
| go-v0.38 x go-v0.42 (wss, noise, yamux) | go-v0.38 | go-v0.42 | wss | noise | yamux | ✅ | 5s | 16.63 | 1.025 |
| go-v0.38 x go-v0.42 (quic-v1) | go-v0.38 | go-v0.42 | quic-v1 | - | - | ✅ | 5s | 19.615 | 4.569 |
| go-v0.38 x go-v0.42 (webtransport) | go-v0.38 | go-v0.42 | webtransport | - | - | ✅ | 5s | 8.305 | 0.345 |
| go-v0.38 x go-v0.42 (webrtc-direct) | go-v0.38 | go-v0.42 | webrtc-direct | - | - | ✅ | 4s | 212.407 | 0.685 |
| go-v0.38 x go-v0.43 (tcp, tls, yamux) | go-v0.38 | go-v0.43 | tcp | tls | yamux | ✅ | 5s | 10.491 | 2.874 |
| go-v0.38 x go-v0.43 (ws, tls, yamux) | go-v0.38 | go-v0.43 | ws | tls | yamux | ✅ | 4s | 10.23 | 1.164 |
| go-v0.38 x go-v0.43 (tcp, noise, yamux) | go-v0.38 | go-v0.43 | tcp | noise | yamux | ✅ | 5s | 6.728 | 0.854 |
| go-v0.38 x go-v0.43 (ws, noise, yamux) | go-v0.38 | go-v0.43 | ws | noise | yamux | ✅ | 4s | 10.63 | 0.472 |
| go-v0.38 x go-v0.43 (wss, tls, yamux) | go-v0.38 | go-v0.43 | wss | tls | yamux | ✅ | 4s | 12.345 | 1.1 |
| go-v0.38 x go-v0.43 (wss, noise, yamux) | go-v0.38 | go-v0.43 | wss | noise | yamux | ✅ | 5s | 19.294 | 1.043 |
| go-v0.38 x go-v0.43 (quic-v1) | go-v0.38 | go-v0.43 | quic-v1 | - | - | ✅ | 4s | 9.019 | 0.664 |
| go-v0.38 x go-v0.43 (webtransport) | go-v0.38 | go-v0.43 | webtransport | - | - | ✅ | 5s | 7.282 | 0.259 |
| go-v0.38 x go-v0.43 (webrtc-direct) | go-v0.38 | go-v0.43 | webrtc-direct | - | - | ✅ | 5s | 213.719 | 0.62 |
| go-v0.38 x go-v0.44 (tcp, tls, yamux) | go-v0.38 | go-v0.44 | tcp | tls | yamux | ✅ | 4s | 12.239 | 0.606 |
| go-v0.38 x go-v0.44 (tcp, noise, yamux) | go-v0.38 | go-v0.44 | tcp | noise | yamux | ✅ | 5s | 13.354 | 1.057 |
| go-v0.38 x go-v0.44 (ws, tls, yamux) | go-v0.38 | go-v0.44 | ws | tls | yamux | ✅ | 5s | 18.454 | 0.862 |
| go-v0.38 x go-v0.44 (ws, noise, yamux) | go-v0.38 | go-v0.44 | ws | noise | yamux | ✅ | 4s | 9.291 | 0.368 |
| go-v0.38 x go-v0.44 (wss, tls, yamux) | go-v0.38 | go-v0.44 | wss | tls | yamux | ✅ | 5s | 11.731 | 0.433 |
| go-v0.38 x go-v0.44 (quic-v1) | go-v0.38 | go-v0.44 | quic-v1 | - | - | ✅ | 5s | 10.418 | 0.805 |
| go-v0.38 x go-v0.44 (wss, noise, yamux) | go-v0.38 | go-v0.44 | wss | noise | yamux | ✅ | 5s | 12.651 | 0.39 |
| go-v0.38 x go-v0.44 (webtransport) | go-v0.38 | go-v0.44 | webtransport | - | - | ✅ | 5s | 13.739 | 1.343 |
| go-v0.38 x go-v0.45 (tcp, tls, yamux) | go-v0.38 | go-v0.45 | tcp | tls | yamux | ✅ | 4s | 16.727 | 0.776 |
| go-v0.38 x go-v0.44 (webrtc-direct) | go-v0.38 | go-v0.44 | webrtc-direct | - | - | ✅ | 5s | 224.848 | 0.67 |
| go-v0.38 x go-v0.45 (ws, tls, yamux) | go-v0.38 | go-v0.45 | ws | tls | yamux | ✅ | 4s | 7.076 | 0.561 |
| go-v0.38 x go-v0.45 (tcp, noise, yamux) | go-v0.38 | go-v0.45 | tcp | noise | yamux | ✅ | 6s | 8.889 | 0.572 |
| go-v0.38 x go-v0.45 (ws, noise, yamux) | go-v0.38 | go-v0.45 | ws | noise | yamux | ✅ | 5s | 12.478 | 0.516 |
| go-v0.38 x go-v0.45 (wss, tls, yamux) | go-v0.38 | go-v0.45 | wss | tls | yamux | ✅ | 5s | 8.224 | 0.26 |
| go-v0.38 x go-v0.45 (wss, noise, yamux) | go-v0.38 | go-v0.45 | wss | noise | yamux | ✅ | 5s | 19.759 | 0.545 |
| go-v0.38 x go-v0.45 (quic-v1) | go-v0.38 | go-v0.45 | quic-v1 | - | - | ✅ | 4s | 11.478 | 0.831 |
| go-v0.38 x go-v0.45 (webtransport) | go-v0.38 | go-v0.45 | webtransport | - | - | ✅ | 5s | 15.515 | 0.437 |
| go-v0.38 x go-v0.45 (webrtc-direct) | go-v0.38 | go-v0.45 | webrtc-direct | - | - | ✅ | 5s | 224.414 | 3.31 |
| go-v0.38 x python-v0.4 (tcp, noise, yamux) | go-v0.38 | python-v0.4 | tcp | noise | yamux | ✅ | 5s | 32.022 | 6.823 |
| go-v0.38 x python-v0.4 (ws, noise, yamux) | go-v0.38 | python-v0.4 | ws | noise | yamux | ✅ | 5s | 29.33 | 3.93 |
| go-v0.38 x python-v0.4 (wss, noise, yamux) | go-v0.38 | python-v0.4 | wss | noise | yamux | ✅ | 5s | 24.438 | 3.643 |
| go-v0.38 x python-v0.4 (quic-v1) | go-v0.38 | python-v0.4 | quic-v1 | - | - | ✅ | 5s | 56.718 | 11.287 |
| go-v0.38 x nim-v1.14 (tcp, noise, yamux) | go-v0.38 | nim-v1.14 | tcp | noise | yamux | ✅ | 4s | 156.231 | 42.248 |
| go-v0.38 x nim-v1.14 (ws, noise, yamux) | go-v0.38 | nim-v1.14 | ws | noise | yamux | ✅ | 5s | 249.782 | 43.595 |
| go-v0.38 x js-v1.x (tcp, noise, yamux) | go-v0.38 | js-v1.x | tcp | noise | yamux | ✅ | 18s | 130.343 | 18.703 |
| go-v0.38 x js-v1.x (ws, noise, yamux) | go-v0.38 | js-v1.x | ws | noise | yamux | ✅ | 19s | 190.066 | 21.176 |
| go-v0.38 x js-v2.x (tcp, noise, yamux) | go-v0.38 | js-v2.x | tcp | noise | yamux | ✅ | 20s | 186.659 | 28.839 |
| go-v0.38 x jvm-v1.2 (tcp, noise, yamux) | go-v0.38 | jvm-v1.2 | tcp | noise | yamux | ✅ | 9s | 833.726 | 24.417 |
| go-v0.38 x js-v2.x (ws, noise, yamux) | go-v0.38 | js-v2.x | ws | noise | yamux | ✅ | 20s | 177.107 | 31.937 |
| go-v0.38 x js-v3.x (ws, noise, yamux) | go-v0.38 | js-v3.x | ws | noise | yamux | ✅ | 20s | 148.351 | 14.657 |
| go-v0.38 x js-v3.x (tcp, noise, yamux) | go-v0.38 | js-v3.x | tcp | noise | yamux | ✅ | 20s | 174.98 | 21.171 |
| go-v0.38 x jvm-v1.2 (tcp, tls, yamux) | go-v0.38 | jvm-v1.2 | tcp | tls | yamux | ✅ | 14s | 3305.033 | 15.071 |
| go-v0.38 x c-v0.0.1 (tcp, noise, yamux) | go-v0.38 | c-v0.0.1 | tcp | noise | yamux | ✅ | 4s | 119.331 | 53.875 |
| go-v0.38 x c-v0.0.1 (quic-v1) | go-v0.38 | c-v0.0.1 | quic-v1 | - | - | ✅ | 5s | 47.062 | 29.885 |
| go-v0.38 x dotnet-v1.0 (tcp, noise, yamux) | go-v0.38 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 6s | 452.426 | 56.727 |
| go-v0.38 x zig-v0.0.1 (quic-v1) | go-v0.38 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 6s | - | - |
| go-v0.38 x jvm-v1.2 (ws, tls, yamux) | go-v0.38 | jvm-v1.2 | ws | tls | yamux | ✅ | 12s | 3993.93 | 15.124 |
| go-v0.38 x jvm-v1.2 (ws, noise, yamux) | go-v0.38 | jvm-v1.2 | ws | noise | yamux | ✅ | 12s | 1508.203 | 11.754 |
| go-v0.38 x eth-p2p-z-v0.0.1 (quic-v1) | go-v0.38 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 6.902 | 0.301 |
| go-v0.38 x jvm-v1.2 (quic-v1) | go-v0.38 | jvm-v1.2 | quic-v1 | - | - | ✅ | 11s | 450.17 | 4.582 |
| go-v0.39 x rust-v0.53 (tcp, tls, yamux) | go-v0.39 | rust-v0.53 | tcp | tls | yamux | ✅ | 5s | 97.172 | 46.738 |
| go-v0.39 x rust-v0.53 (tcp, noise, yamux) | go-v0.39 | rust-v0.53 | tcp | noise | yamux | ✅ | 5s | 145.709 | 47.79 |
| go-v0.39 x rust-v0.53 (quic-v1) | go-v0.39 | rust-v0.53 | quic-v1 | - | - | ✅ | 4s | 7.939 | 0.312 |
| go-v0.39 x rust-v0.53 (ws, tls, yamux) | go-v0.39 | rust-v0.53 | ws | tls | yamux | ✅ | 5s | 189.933 | 45.006 |
| go-v0.39 x rust-v0.53 (ws, noise, yamux) | go-v0.39 | rust-v0.53 | ws | noise | yamux | ✅ | 6s | 184.544 | 45.606 |
| go-v0.39 x rust-v0.53 (webrtc-direct) | go-v0.39 | rust-v0.53 | webrtc-direct | - | - | ✅ | 5s | 443.118 | 1.396 |
| go-v0.39 x rust-v0.54 (tcp, tls, yamux) | go-v0.39 | rust-v0.54 | tcp | tls | yamux | ✅ | 6s | 93.219 | 43.064 |
| go-v0.39 x rust-v0.54 (tcp, noise, yamux) | go-v0.39 | rust-v0.54 | tcp | noise | yamux | ✅ | 5s | 92.688 | 41.688 |
| go-v0.39 x rust-v0.54 (ws, tls, yamux) | go-v0.39 | rust-v0.54 | ws | tls | yamux | ✅ | 5s | 230.389 | 43.75 |
| go-v0.39 x rust-v0.54 (ws, noise, yamux) | go-v0.39 | rust-v0.54 | ws | noise | yamux | ✅ | 5s | 178.234 | 43.045 |
| go-v0.39 x rust-v0.55 (tcp, tls, yamux) | go-v0.39 | rust-v0.55 | tcp | tls | yamux | ✅ | 4s | 11.874 | 2.527 |
| go-v0.39 x rust-v0.54 (quic-v1) | go-v0.39 | rust-v0.54 | quic-v1 | - | - | ✅ | 5s | 9.855 | 0.892 |
| go-v0.39 x rust-v0.54 (webrtc-direct) | go-v0.39 | rust-v0.54 | webrtc-direct | - | - | ✅ | 5s | 416.016 | 0.583 |
| go-v0.39 x rust-v0.55 (tcp, noise, yamux) | go-v0.39 | rust-v0.55 | tcp | noise | yamux | ✅ | 5s | 4.296 | 0.628 |
| go-v0.39 x rust-v0.55 (ws, tls, yamux) | go-v0.39 | rust-v0.55 | ws | tls | yamux | ✅ | 5s | 5.661 | 0.233 |
| go-v0.39 x rust-v0.55 (ws, noise, yamux) | go-v0.39 | rust-v0.55 | ws | noise | yamux | ✅ | 5s | 8.126 | 0.396 |
| go-v0.39 x rust-v0.55 (quic-v1) | go-v0.39 | rust-v0.55 | quic-v1 | - | - | ✅ | 4s | 8.342 | 0.455 |
| go-v0.39 x rust-v0.56 (tcp, tls, yamux) | go-v0.39 | rust-v0.56 | tcp | tls | yamux | ✅ | 5s | 9.646 | 0.782 |
| go-v0.39 x rust-v0.55 (webrtc-direct) | go-v0.39 | rust-v0.55 | webrtc-direct | - | - | ✅ | 6s | 414.967 | 1.038 |
| go-v0.39 x rust-v0.56 (tcp, noise, yamux) | go-v0.39 | rust-v0.56 | tcp | noise | yamux | ✅ | 5s | 8.979 | 0.632 |
| go-v0.39 x rust-v0.56 (ws, tls, yamux) | go-v0.39 | rust-v0.56 | ws | tls | yamux | ✅ | 5s | 4.787 | 0.33 |
| go-v0.39 x rust-v0.56 (ws, noise, yamux) | go-v0.39 | rust-v0.56 | ws | noise | yamux | ✅ | 5s | 5.601 | 0.186 |
| go-v0.39 x rust-v0.56 (quic-v1) | go-v0.39 | rust-v0.56 | quic-v1 | - | - | ✅ | 4s | 9.546 | 0.621 |
| go-v0.39 x go-v0.38 (tcp, tls, yamux) | go-v0.39 | go-v0.38 | tcp | tls | yamux | ✅ | 4s | 12.621 | 3.344 |
| go-v0.39 x go-v0.38 (ws, tls, yamux) | go-v0.39 | go-v0.38 | ws | tls | yamux | ✅ | 4s | 20.537 | 0.478 |
| go-v0.39 x go-v0.38 (ws, noise, yamux) | go-v0.39 | go-v0.38 | ws | noise | yamux | ✅ | 4s | 7.745 | 1.069 |
| go-v0.39 x go-v0.38 (tcp, noise, yamux) | go-v0.39 | go-v0.38 | tcp | noise | yamux | ✅ | 5s | 23.372 | 1.293 |
| go-v0.39 x go-v0.38 (wss, tls, yamux) | go-v0.39 | go-v0.38 | wss | tls | yamux | ✅ | 5s | 12.388 | 0.309 |
| go-v0.39 x go-v0.38 (quic-v1) | go-v0.39 | go-v0.38 | quic-v1 | - | - | ✅ | 4s | 11.364 | 1.254 |
| go-v0.39 x go-v0.38 (wss, noise, yamux) | go-v0.39 | go-v0.38 | wss | noise | yamux | ✅ | 6s | 16.313 | 2.338 |
| go-v0.39 x rust-v0.56 (webrtc-direct) | go-v0.39 | rust-v0.56 | webrtc-direct | - | - | ❌ | 10s | - | - |
| go-v0.39 x go-v0.38 (webtransport) | go-v0.39 | go-v0.38 | webtransport | - | - | ✅ | 4s | 9.817 | 0.372 |
| go-v0.39 x go-v0.39 (tcp, tls, yamux) | go-v0.39 | go-v0.39 | tcp | tls | yamux | ✅ | 4s | 14.169 | 0.329 |
| go-v0.39 x go-v0.38 (webrtc-direct) | go-v0.39 | go-v0.38 | webrtc-direct | - | - | ✅ | 5s | 213.403 | 0.383 |
| go-v0.39 x go-v0.39 (tcp, noise, yamux) | go-v0.39 | go-v0.39 | tcp | noise | yamux | ✅ | 5s | 9.803 | 0.994 |
| go-v0.39 x go-v0.39 (ws, tls, yamux) | go-v0.39 | go-v0.39 | ws | tls | yamux | ✅ | 5s | 21.244 | 0.553 |
| go-v0.39 x go-v0.39 (ws, noise, yamux) | go-v0.39 | go-v0.39 | ws | noise | yamux | ✅ | 4s | 14.56 | 0.377 |
| go-v0.39 x go-v0.39 (quic-v1) | go-v0.39 | go-v0.39 | quic-v1 | - | - | ✅ | 4s | 24.923 | 0.575 |
| go-v0.39 x go-v0.39 (wss, tls, yamux) | go-v0.39 | go-v0.39 | wss | tls | yamux | ✅ | 6s | 10.744 | 0.711 |
| go-v0.39 x go-v0.39 (wss, noise, yamux) | go-v0.39 | go-v0.39 | wss | noise | yamux | ✅ | 5s | 11.762 | 0.593 |
| go-v0.39 x go-v0.39 (webtransport) | go-v0.39 | go-v0.39 | webtransport | - | - | ✅ | 5s | 14.242 | 0.408 |
| go-v0.39 x go-v0.39 (webrtc-direct) | go-v0.39 | go-v0.39 | webrtc-direct | - | - | ✅ | 4s | 208.548 | 0.514 |
| go-v0.39 x go-v0.40 (tcp, tls, yamux) | go-v0.39 | go-v0.40 | tcp | tls | yamux | ✅ | 4s | 8.316 | 0.259 |
| go-v0.39 x go-v0.40 (tcp, noise, yamux) | go-v0.39 | go-v0.40 | tcp | noise | yamux | ✅ | 5s | 7.261 | 0.469 |
| go-v0.39 x go-v0.40 (ws, tls, yamux) | go-v0.39 | go-v0.40 | ws | tls | yamux | ✅ | 4s | 9.503 | 0.811 |
| go-v0.39 x go-v0.40 (ws, noise, yamux) | go-v0.39 | go-v0.40 | ws | noise | yamux | ✅ | 4s | 9.93 | 0.416 |
| go-v0.39 x go-v0.40 (wss, tls, yamux) | go-v0.39 | go-v0.40 | wss | tls | yamux | ✅ | 5s | 24.376 | 1.653 |
| go-v0.39 x go-v0.40 (quic-v1) | go-v0.39 | go-v0.40 | quic-v1 | - | - | ✅ | 4s | 12.959 | 1.211 |
| go-v0.39 x go-v0.40 (wss, noise, yamux) | go-v0.39 | go-v0.40 | wss | noise | yamux | ✅ | 5s | 10.425 | 0.332 |
| go-v0.39 x go-v0.40 (webtransport) | go-v0.39 | go-v0.40 | webtransport | - | - | ✅ | 5s | 10.846 | 1.271 |
| go-v0.39 x go-v0.40 (webrtc-direct) | go-v0.39 | go-v0.40 | webrtc-direct | - | - | ✅ | 4s | 223.762 | 1.787 |
| go-v0.39 x go-v0.41 (tcp, tls, yamux) | go-v0.39 | go-v0.41 | tcp | tls | yamux | ✅ | 4s | 14.46 | 2.767 |
| go-v0.39 x go-v0.41 (tcp, noise, yamux) | go-v0.39 | go-v0.41 | tcp | noise | yamux | ✅ | 5s | 6.203 | 0.314 |
| go-v0.39 x go-v0.41 (ws, tls, yamux) | go-v0.39 | go-v0.41 | ws | tls | yamux | ✅ | 4s | 10.421 | 3.063 |
| go-v0.39 x go-v0.41 (ws, noise, yamux) | go-v0.39 | go-v0.41 | ws | noise | yamux | ✅ | 5s | 5.248 | 0.313 |
| go-v0.39 x go-v0.41 (wss, noise, yamux) | go-v0.39 | go-v0.41 | wss | noise | yamux | ✅ | 5s | 19.792 | 0.569 |
| go-v0.39 x go-v0.41 (quic-v1) | go-v0.39 | go-v0.41 | quic-v1 | - | - | ✅ | 5s | 20.922 | 2.445 |
| go-v0.39 x go-v0.41 (wss, tls, yamux) | go-v0.39 | go-v0.41 | wss | tls | yamux | ✅ | 6s | 19.237 | 1.718 |
| go-v0.39 x go-v0.41 (webtransport) | go-v0.39 | go-v0.41 | webtransport | - | - | ✅ | 5s | 15.183 | 3.432 |
| go-v0.39 x go-v0.41 (webrtc-direct) | go-v0.39 | go-v0.41 | webrtc-direct | - | - | ✅ | 5s | 19.853 | 1.279 |
| go-v0.39 x go-v0.42 (tcp, tls, yamux) | go-v0.39 | go-v0.42 | tcp | tls | yamux | ✅ | 4s | 9.805 | 1.307 |
| go-v0.39 x go-v0.42 (tcp, noise, yamux) | go-v0.39 | go-v0.42 | tcp | noise | yamux | ✅ | 5s | 6.272 | 0.616 |
| go-v0.39 x go-v0.42 (ws, tls, yamux) | go-v0.39 | go-v0.42 | ws | tls | yamux | ✅ | 4s | 18.23 | 6.756 |
| go-v0.39 x go-v0.42 (ws, noise, yamux) | go-v0.39 | go-v0.42 | ws | noise | yamux | ✅ | 4s | 17.286 | 3.51 |
| go-v0.39 x go-v0.42 (wss, tls, yamux) | go-v0.39 | go-v0.42 | wss | tls | yamux | ✅ | 4s | 23.862 | 0.575 |
| go-v0.39 x go-v0.42 (quic-v1) | go-v0.39 | go-v0.42 | quic-v1 | - | - | ✅ | 5s | 11.645 | 2.293 |
| go-v0.39 x go-v0.42 (wss, noise, yamux) | go-v0.39 | go-v0.42 | wss | noise | yamux | ✅ | 5s | 11.324 | 0.663 |
| go-v0.39 x go-v0.42 (webtransport) | go-v0.39 | go-v0.42 | webtransport | - | - | ✅ | 5s | 13.965 | 0.816 |
| go-v0.39 x go-v0.42 (webrtc-direct) | go-v0.39 | go-v0.42 | webrtc-direct | - | - | ✅ | 5s | 211.218 | 0.262 |
| go-v0.39 x go-v0.43 (tcp, tls, yamux) | go-v0.39 | go-v0.43 | tcp | tls | yamux | ✅ | 5s | 5.746 | 0.866 |
| go-v0.39 x go-v0.43 (tcp, noise, yamux) | go-v0.39 | go-v0.43 | tcp | noise | yamux | ✅ | 5s | 14.252 | 1.673 |
| go-v0.39 x go-v0.43 (ws, tls, yamux) | go-v0.39 | go-v0.43 | ws | tls | yamux | ✅ | 4s | 5.623 | 0.319 |
| go-v0.39 x go-v0.43 (ws, noise, yamux) | go-v0.39 | go-v0.43 | ws | noise | yamux | ✅ | 5s | 11.311 | 0.948 |
| go-v0.39 x go-v0.43 (wss, tls, yamux) | go-v0.39 | go-v0.43 | wss | tls | yamux | ✅ | 5s | 24.017 | 1.239 |
| go-v0.39 x go-v0.43 (quic-v1) | go-v0.39 | go-v0.43 | quic-v1 | - | - | ✅ | 5s | 14.804 | 0.694 |
| go-v0.39 x go-v0.43 (wss, noise, yamux) | go-v0.39 | go-v0.43 | wss | noise | yamux | ✅ | 5s | 14.683 | 0.345 |
| go-v0.39 x go-v0.43 (webtransport) | go-v0.39 | go-v0.43 | webtransport | - | - | ✅ | 5s | 11.937 | 0.878 |
| go-v0.39 x go-v0.43 (webrtc-direct) | go-v0.39 | go-v0.43 | webrtc-direct | - | - | ✅ | 5s | 215.019 | 0.531 |
| go-v0.39 x go-v0.44 (tcp, tls, yamux) | go-v0.39 | go-v0.44 | tcp | tls | yamux | ✅ | 4s | 14.652 | 1.103 |
| go-v0.39 x go-v0.44 (tcp, noise, yamux) | go-v0.39 | go-v0.44 | tcp | noise | yamux | ✅ | 5s | 7.538 | 0.269 |
| go-v0.39 x go-v0.44 (ws, tls, yamux) | go-v0.39 | go-v0.44 | ws | tls | yamux | ✅ | 4s | 5.984 | 0.447 |
| go-v0.39 x go-v0.44 (ws, noise, yamux) | go-v0.39 | go-v0.44 | ws | noise | yamux | ✅ | 5s | 10.963 | 0.358 |
| go-v0.39 x go-v0.44 (quic-v1) | go-v0.39 | go-v0.44 | quic-v1 | - | - | ✅ | 5s | 9.849 | 0.587 |
| go-v0.39 x go-v0.44 (wss, noise, yamux) | go-v0.39 | go-v0.44 | wss | noise | yamux | ✅ | 5s | 24.048 | 1.396 |
| go-v0.39 x go-v0.44 (wss, tls, yamux) | go-v0.39 | go-v0.44 | wss | tls | yamux | ✅ | 7s | 7.887 | 0.196 |
| go-v0.39 x go-v0.44 (webtransport) | go-v0.39 | go-v0.44 | webtransport | - | - | ✅ | 5s | 10.276 | 0.281 |
| go-v0.39 x go-v0.44 (webrtc-direct) | go-v0.39 | go-v0.44 | webrtc-direct | - | - | ✅ | 4s | 212.718 | 0.578 |
| go-v0.39 x go-v0.45 (tcp, tls, yamux) | go-v0.39 | go-v0.45 | tcp | tls | yamux | ✅ | 6s | 13.284 | 1.188 |
| go-v0.39 x go-v0.45 (tcp, noise, yamux) | go-v0.39 | go-v0.45 | tcp | noise | yamux | ✅ | 5s | 9.298 | 2.113 |
| go-v0.39 x go-v0.45 (ws, tls, yamux) | go-v0.39 | go-v0.45 | ws | tls | yamux | ✅ | 4s | 7.709 | 0.872 |
| go-v0.39 x go-v0.45 (ws, noise, yamux) | go-v0.39 | go-v0.45 | ws | noise | yamux | ✅ | 5s | 11.279 | 1.61 |
| go-v0.39 x go-v0.45 (wss, tls, yamux) | go-v0.39 | go-v0.45 | wss | tls | yamux | ✅ | 5s | 15.561 | 0.659 |
| go-v0.39 x go-v0.45 (quic-v1) | go-v0.39 | go-v0.45 | quic-v1 | - | - | ✅ | 5s | 19.887 | 6.546 |
| go-v0.39 x go-v0.45 (wss, noise, yamux) | go-v0.39 | go-v0.45 | wss | noise | yamux | ✅ | 6s | 17.588 | 1.411 |
| go-v0.39 x go-v0.45 (webtransport) | go-v0.39 | go-v0.45 | webtransport | - | - | ✅ | 5s | 7.808 | 0.257 |
| go-v0.39 x go-v0.45 (webrtc-direct) | go-v0.39 | go-v0.45 | webrtc-direct | - | - | ✅ | 5s | 220.142 | 3.527 |
| go-v0.39 x python-v0.4 (tcp, noise, yamux) | go-v0.39 | python-v0.4 | tcp | noise | yamux | ✅ | 5s | 32.904 | 5.314 |
| go-v0.39 x python-v0.4 (ws, noise, yamux) | go-v0.39 | python-v0.4 | ws | noise | yamux | ✅ | 5s | 27.137 | 5.27 |
| go-v0.39 x python-v0.4 (wss, noise, yamux) | go-v0.39 | python-v0.4 | wss | noise | yamux | ✅ | 5s | 33.088 | 7.617 |
| go-v0.39 x python-v0.4 (quic-v1) | go-v0.39 | python-v0.4 | quic-v1 | - | - | ✅ | 6s | 70.676 | 21.793 |
| go-v0.39 x nim-v1.14 (tcp, noise, yamux) | go-v0.39 | nim-v1.14 | tcp | noise | yamux | ✅ | 5s | 205.765 | 43.665 |
| go-v0.39 x nim-v1.14 (ws, noise, yamux) | go-v0.39 | nim-v1.14 | ws | noise | yamux | ✅ | 5s | 268.759 | 47.558 |
| go-v0.39 x js-v1.x (tcp, noise, yamux) | go-v0.39 | js-v1.x | tcp | noise | yamux | ✅ | 19s | 151.217 | 16.717 |
| go-v0.39 x js-v1.x (ws, noise, yamux) | go-v0.39 | js-v1.x | ws | noise | yamux | ✅ | 20s | 188.928 | 26.452 |
| go-v0.39 x js-v2.x (tcp, noise, yamux) | go-v0.39 | js-v2.x | tcp | noise | yamux | ✅ | 21s | 235.052 | 25.254 |
| go-v0.39 x jvm-v1.2 (tcp, noise, yamux) | go-v0.39 | jvm-v1.2 | tcp | noise | yamux | ✅ | 10s | 1084.08 | 21.008 |
| go-v0.39 x js-v2.x (ws, noise, yamux) | go-v0.39 | js-v2.x | ws | noise | yamux | ✅ | 22s | 157.055 | 20.736 |
| go-v0.39 x jvm-v1.2 (tcp, tls, yamux) | go-v0.39 | jvm-v1.2 | tcp | tls | yamux | ✅ | 13s | 4067.399 | 7.991 |
| go-v0.39 x js-v3.x (ws, noise, yamux) | go-v0.39 | js-v3.x | ws | noise | yamux | ✅ | 21s | 138.79 | 26.227 |
| go-v0.39 x js-v3.x (tcp, noise, yamux) | go-v0.39 | js-v3.x | tcp | noise | yamux | ✅ | 22s | 136.408 | 12.628 |
| go-v0.39 x c-v0.0.1 (tcp, noise, yamux) | go-v0.39 | c-v0.0.1 | tcp | noise | yamux | ✅ | 6s | 123.749 | 55.075 |
| go-v0.39 x jvm-v1.2 (ws, tls, yamux) | go-v0.39 | jvm-v1.2 | ws | tls | yamux | ✅ | 10s | 3181.713 | 15.087 |
| go-v0.39 x c-v0.0.1 (quic-v1) | go-v0.39 | c-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 55.215 | 26.472 |
| go-v0.39 x jvm-v1.2 (ws, noise, yamux) | go-v0.39 | jvm-v1.2 | ws | noise | yamux | ✅ | 9s | 1174.945 | 31.065 |
| go-v0.39 x jvm-v1.2 (quic-v1) | go-v0.39 | jvm-v1.2 | quic-v1 | - | - | ✅ | 10s | 503.244 | 7.428 |
| go-v0.39 x dotnet-v1.0 (tcp, noise, yamux) | go-v0.39 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 7s | 357.078 | 46.071 |
| go-v0.39 x zig-v0.0.1 (quic-v1) | go-v0.39 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 6s | - | - |
| go-v0.39 x eth-p2p-z-v0.0.1 (quic-v1) | go-v0.39 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 9.167 | 0.84 |
| go-v0.40 x rust-v0.53 (tcp, tls, yamux) | go-v0.40 | rust-v0.53 | tcp | tls | yamux | ✅ | 4s | 99.089 | 45.909 |
| go-v0.40 x rust-v0.53 (tcp, noise, yamux) | go-v0.40 | rust-v0.53 | tcp | noise | yamux | ✅ | 4s | 93.262 | 41.727 |
| go-v0.40 x rust-v0.53 (ws, tls, yamux) | go-v0.40 | rust-v0.53 | ws | tls | yamux | ✅ | 5s | 228.205 | 43.615 |
| go-v0.40 x rust-v0.53 (ws, noise, yamux) | go-v0.40 | rust-v0.53 | ws | noise | yamux | ✅ | 4s | 181.102 | 43.276 |
| go-v0.40 x rust-v0.53 (quic-v1) | go-v0.40 | rust-v0.53 | quic-v1 | - | - | ✅ | 5s | 10.805 | 1.746 |
| go-v0.40 x rust-v0.53 (webrtc-direct) | go-v0.40 | rust-v0.53 | webrtc-direct | - | - | ✅ | 5s | 620.214 | 0.684 |
| go-v0.40 x rust-v0.54 (tcp, noise, yamux) | go-v0.40 | rust-v0.54 | tcp | noise | yamux | ✅ | 5s | 93.082 | 41.475 |
| go-v0.40 x rust-v0.54 (tcp, tls, yamux) | go-v0.40 | rust-v0.54 | tcp | tls | yamux | ✅ | 5s | 143.754 | 47.747 |
| go-v0.40 x rust-v0.54 (ws, tls, yamux) | go-v0.40 | rust-v0.54 | ws | tls | yamux | ✅ | 5s | 204.016 | 49.058 |
| go-v0.40 x rust-v0.54 (quic-v1) | go-v0.40 | rust-v0.54 | quic-v1 | - | - | ✅ | 5s | 8.097 | 0.32 |
| go-v0.40 x rust-v0.54 (ws, noise, yamux) | go-v0.40 | rust-v0.54 | ws | noise | yamux | ✅ | 5s | 186.297 | 46.415 |
| go-v0.40 x rust-v0.54 (webrtc-direct) | go-v0.40 | rust-v0.54 | webrtc-direct | - | - | ✅ | 5s | 210.551 | 0.55 |
| go-v0.40 x rust-v0.55 (tcp, tls, yamux) | go-v0.40 | rust-v0.55 | tcp | tls | yamux | ✅ | 5s | 14.103 | 1.389 |
| go-v0.40 x rust-v0.55 (tcp, noise, yamux) | go-v0.40 | rust-v0.55 | tcp | noise | yamux | ✅ | 4s | 11.448 | 3.661 |
| go-v0.40 x rust-v0.55 (ws, tls, yamux) | go-v0.40 | rust-v0.55 | ws | tls | yamux | ✅ | 5s | 8.101 | 0.68 |
| go-v0.40 x rust-v0.55 (ws, noise, yamux) | go-v0.40 | rust-v0.55 | ws | noise | yamux | ✅ | 4s | 11.072 | 0.477 |
| go-v0.40 x rust-v0.55 (quic-v1) | go-v0.40 | rust-v0.55 | quic-v1 | - | - | ✅ | 5s | 9.128 | 0.598 |
| go-v0.40 x rust-v0.56 (tcp, tls, yamux) | go-v0.40 | rust-v0.56 | tcp | tls | yamux | ✅ | 4s | 6.497 | 0.47 |
| go-v0.40 x rust-v0.55 (webrtc-direct) | go-v0.40 | rust-v0.55 | webrtc-direct | - | - | ✅ | 6s | 430.619 | 1.06 |
| go-v0.40 x rust-v0.56 (ws, tls, yamux) | go-v0.40 | rust-v0.56 | ws | tls | yamux | ✅ | 4s | 13.225 | 1.072 |
| go-v0.40 x rust-v0.56 (tcp, noise, yamux) | go-v0.40 | rust-v0.56 | tcp | noise | yamux | ✅ | 6s | 11.386 | 1.487 |
| go-v0.40 x rust-v0.56 (ws, noise, yamux) | go-v0.40 | rust-v0.56 | ws | noise | yamux | ✅ | 4s | 4.364 | 0.364 |
| go-v0.40 x rust-v0.56 (quic-v1) | go-v0.40 | rust-v0.56 | quic-v1 | - | - | ✅ | 5s | 10.884 | 0.549 |
| go-v0.40 x go-v0.38 (tcp, noise, yamux) | go-v0.40 | go-v0.38 | tcp | noise | yamux | ✅ | 3s | 7.49 | 0.906 |
| go-v0.40 x go-v0.38 (tcp, tls, yamux) | go-v0.40 | go-v0.38 | tcp | tls | yamux | ✅ | 5s | 7.596 | 0.404 |
| go-v0.40 x go-v0.38 (ws, tls, yamux) | go-v0.40 | go-v0.38 | ws | tls | yamux | ✅ | 5s | 18.775 | 2.29 |
| go-v0.40 x go-v0.38 (ws, noise, yamux) | go-v0.40 | go-v0.38 | ws | noise | yamux | ✅ | 4s | 10.691 | 2.47 |
| go-v0.40 x go-v0.38 (wss, tls, yamux) | go-v0.40 | go-v0.38 | wss | tls | yamux | ✅ | 5s | 8.663 | 0.353 |
| go-v0.40 x go-v0.38 (wss, noise, yamux) | go-v0.40 | go-v0.38 | wss | noise | yamux | ✅ | 5s | 16.32 | 0.502 |
| go-v0.40 x go-v0.38 (quic-v1) | go-v0.40 | go-v0.38 | quic-v1 | - | - | ✅ | 5s | 8.425 | 0.488 |
| go-v0.40 x rust-v0.56 (webrtc-direct) | go-v0.40 | rust-v0.56 | webrtc-direct | - | - | ❌ | 10s | - | - |
| go-v0.40 x go-v0.38 (webtransport) | go-v0.40 | go-v0.38 | webtransport | - | - | ✅ | 5s | 15.516 | 1.107 |
| go-v0.40 x go-v0.38 (webrtc-direct) | go-v0.40 | go-v0.38 | webrtc-direct | - | - | ✅ | 5s | 349.672 | 0.352 |
| go-v0.40 x go-v0.39 (tcp, tls, yamux) | go-v0.40 | go-v0.39 | tcp | tls | yamux | ✅ | 5s | 9.436 | 0.553 |
| go-v0.40 x go-v0.39 (tcp, noise, yamux) | go-v0.40 | go-v0.39 | tcp | noise | yamux | ✅ | 4s | 10.936 | 4.065 |
| go-v0.40 x go-v0.39 (ws, tls, yamux) | go-v0.40 | go-v0.39 | ws | tls | yamux | ✅ | 4s | 12.944 | 0.634 |
| go-v0.40 x go-v0.39 (ws, noise, yamux) | go-v0.40 | go-v0.39 | ws | noise | yamux | ✅ | 4s | 9.389 | 0.825 |
| go-v0.40 x go-v0.39 (wss, tls, yamux) | go-v0.40 | go-v0.39 | wss | tls | yamux | ✅ | 4s | 21.47 | 0.977 |
| go-v0.40 x go-v0.39 (quic-v1) | go-v0.40 | go-v0.39 | quic-v1 | - | - | ✅ | 4s | 7.894 | 0.496 |
| go-v0.40 x go-v0.39 (wss, noise, yamux) | go-v0.40 | go-v0.39 | wss | noise | yamux | ✅ | 5s | 16.355 | 0.695 |
| go-v0.40 x go-v0.39 (webtransport) | go-v0.40 | go-v0.39 | webtransport | - | - | ✅ | 4s | 16.273 | 1.28 |
| go-v0.40 x go-v0.39 (webrtc-direct) | go-v0.40 | go-v0.39 | webrtc-direct | - | - | ✅ | 5s | 213.673 | 2.634 |
| go-v0.40 x go-v0.40 (tcp, tls, yamux) | go-v0.40 | go-v0.40 | tcp | tls | yamux | ✅ | 5s | 5.224 | 0.22 |
| go-v0.40 x go-v0.40 (tcp, noise, yamux) | go-v0.40 | go-v0.40 | tcp | noise | yamux | ✅ | 5s | 8.54 | 0.501 |
| go-v0.40 x go-v0.40 (ws, tls, yamux) | go-v0.40 | go-v0.40 | ws | tls | yamux | ✅ | 5s | 8.265 | 1.235 |
| go-v0.40 x go-v0.40 (ws, noise, yamux) | go-v0.40 | go-v0.40 | ws | noise | yamux | ✅ | 5s | 6.475 | 0.829 |
| go-v0.40 x go-v0.40 (wss, tls, yamux) | go-v0.40 | go-v0.40 | wss | tls | yamux | ✅ | 5s | 20.161 | 0.656 |
| go-v0.40 x go-v0.40 (quic-v1) | go-v0.40 | go-v0.40 | quic-v1 | - | - | ✅ | 5s | 21.466 | 0.993 |
| go-v0.40 x go-v0.40 (wss, noise, yamux) | go-v0.40 | go-v0.40 | wss | noise | yamux | ✅ | 6s | 23.516 | 1.12 |
| go-v0.40 x go-v0.40 (webtransport) | go-v0.40 | go-v0.40 | webtransport | - | - | ✅ | 5s | 9.982 | 0.427 |
| go-v0.40 x go-v0.40 (webrtc-direct) | go-v0.40 | go-v0.40 | webrtc-direct | - | - | ✅ | 6s | 211.049 | 0.409 |
| go-v0.40 x go-v0.41 (tcp, noise, yamux) | go-v0.40 | go-v0.41 | tcp | noise | yamux | ✅ | 4s | 11.486 | 0.613 |
| go-v0.40 x go-v0.41 (tcp, tls, yamux) | go-v0.40 | go-v0.41 | tcp | tls | yamux | ✅ | 5s | 11.098 | 2.224 |
| go-v0.40 x go-v0.41 (ws, tls, yamux) | go-v0.40 | go-v0.41 | ws | tls | yamux | ✅ | 5s | 8.322 | 0.399 |
| go-v0.40 x go-v0.41 (ws, noise, yamux) | go-v0.40 | go-v0.41 | ws | noise | yamux | ✅ | 4s | 15.82 | 2.057 |
| go-v0.40 x go-v0.41 (wss, tls, yamux) | go-v0.40 | go-v0.41 | wss | tls | yamux | ✅ | 5s | 17.482 | 3.787 |
| go-v0.40 x go-v0.41 (wss, noise, yamux) | go-v0.40 | go-v0.41 | wss | noise | yamux | ✅ | 5s | 18.576 | 0.846 |
| go-v0.40 x go-v0.41 (quic-v1) | go-v0.40 | go-v0.41 | quic-v1 | - | - | ✅ | 5s | 10.516 | 0.443 |
| go-v0.40 x go-v0.41 (webrtc-direct) | go-v0.40 | go-v0.41 | webrtc-direct | - | - | ✅ | 4s | 212.092 | 0.492 |
| go-v0.40 x go-v0.41 (webtransport) | go-v0.40 | go-v0.41 | webtransport | - | - | ✅ | 5s | 15.217 | 0.396 |
| go-v0.40 x go-v0.42 (tcp, tls, yamux) | go-v0.40 | go-v0.42 | tcp | tls | yamux | ✅ | 5s | 4.43 | 0.674 |
| go-v0.40 x go-v0.42 (tcp, noise, yamux) | go-v0.40 | go-v0.42 | tcp | noise | yamux | ✅ | 5s | 9.763 | 0.333 |
| go-v0.40 x go-v0.42 (ws, tls, yamux) | go-v0.40 | go-v0.42 | ws | tls | yamux | ✅ | 5s | 9.552 | 0.291 |
| go-v0.40 x go-v0.42 (ws, noise, yamux) | go-v0.40 | go-v0.42 | ws | noise | yamux | ✅ | 5s | 10.291 | 1.319 |
| go-v0.40 x go-v0.42 (wss, tls, yamux) | go-v0.40 | go-v0.42 | wss | tls | yamux | ✅ | 5s | 17.318 | 0.591 |
| go-v0.40 x go-v0.42 (quic-v1) | go-v0.40 | go-v0.42 | quic-v1 | - | - | ✅ | 4s | 11.872 | 0.528 |
| go-v0.40 x go-v0.42 (wss, noise, yamux) | go-v0.40 | go-v0.42 | wss | noise | yamux | ✅ | 6s | 13.277 | 0.44 |
| go-v0.40 x go-v0.42 (webtransport) | go-v0.40 | go-v0.42 | webtransport | - | - | ✅ | 5s | 15.97 | 0.598 |
| go-v0.40 x go-v0.42 (webrtc-direct) | go-v0.40 | go-v0.42 | webrtc-direct | - | - | ✅ | 6s | 221.08 | 1.609 |
| go-v0.40 x go-v0.43 (tcp, tls, yamux) | go-v0.40 | go-v0.43 | tcp | tls | yamux | ✅ | 5s | 6.133 | 0.212 |
| go-v0.40 x go-v0.43 (ws, tls, yamux) | go-v0.40 | go-v0.43 | ws | tls | yamux | ✅ | 4s | 5.005 | 0.274 |
| go-v0.40 x go-v0.43 (tcp, noise, yamux) | go-v0.40 | go-v0.43 | tcp | noise | yamux | ✅ | 5s | 4.783 | 0.592 |
| go-v0.40 x go-v0.43 (ws, noise, yamux) | go-v0.40 | go-v0.43 | ws | noise | yamux | ✅ | 5s | 14.228 | 4.377 |
| go-v0.40 x go-v0.43 (wss, tls, yamux) | go-v0.40 | go-v0.43 | wss | tls | yamux | ✅ | 5s | 26.728 | 0.722 |
| go-v0.40 x go-v0.43 (quic-v1) | go-v0.40 | go-v0.43 | quic-v1 | - | - | ✅ | 4s | 11.727 | 0.386 |
| go-v0.40 x go-v0.43 (wss, noise, yamux) | go-v0.40 | go-v0.43 | wss | noise | yamux | ✅ | 6s | 12.785 | 1.648 |
| go-v0.40 x go-v0.43 (webtransport) | go-v0.40 | go-v0.43 | webtransport | - | - | ✅ | 5s | 10.991 | 0.494 |
| go-v0.40 x go-v0.43 (webrtc-direct) | go-v0.40 | go-v0.43 | webrtc-direct | - | - | ✅ | 6s | 85.068 | 1.123 |
| go-v0.40 x go-v0.44 (tcp, noise, yamux) | go-v0.40 | go-v0.44 | tcp | noise | yamux | ✅ | 5s | 13.369 | 2.218 |
| go-v0.40 x go-v0.44 (tcp, tls, yamux) | go-v0.40 | go-v0.44 | tcp | tls | yamux | ✅ | 5s | 12.555 | 1.318 |
| go-v0.40 x go-v0.44 (ws, tls, yamux) | go-v0.40 | go-v0.44 | ws | tls | yamux | ✅ | 5s | 9.248 | 0.255 |
| go-v0.40 x go-v0.44 (ws, noise, yamux) | go-v0.40 | go-v0.44 | ws | noise | yamux | ✅ | 5s | 7.621 | 0.995 |
| go-v0.40 x go-v0.44 (quic-v1) | go-v0.40 | go-v0.44 | quic-v1 | - | - | ✅ | 4s | 25.053 | 0.774 |
| go-v0.40 x go-v0.44 (wss, tls, yamux) | go-v0.40 | go-v0.44 | wss | tls | yamux | ✅ | 5s | 17.042 | 1.293 |
| go-v0.40 x go-v0.44 (wss, noise, yamux) | go-v0.40 | go-v0.44 | wss | noise | yamux | ✅ | 6s | 20.473 | 1.561 |
| go-v0.40 x go-v0.44 (webtransport) | go-v0.40 | go-v0.44 | webtransport | - | - | ✅ | 4s | 18.291 | 0.691 |
| go-v0.40 x go-v0.45 (tcp, tls, yamux) | go-v0.40 | go-v0.45 | tcp | tls | yamux | ✅ | 4s | 12.068 | 3.467 |
| go-v0.40 x go-v0.44 (webrtc-direct) | go-v0.40 | go-v0.44 | webrtc-direct | - | - | ✅ | 5s | 218.736 | 0.678 |
| go-v0.40 x go-v0.45 (tcp, noise, yamux) | go-v0.40 | go-v0.45 | tcp | noise | yamux | ✅ | 5s | 19.484 | 2.052 |
| go-v0.40 x go-v0.45 (ws, tls, yamux) | go-v0.40 | go-v0.45 | ws | tls | yamux | ✅ | 5s | 7.667 | 1.884 |
| go-v0.40 x go-v0.45 (ws, noise, yamux) | go-v0.40 | go-v0.45 | ws | noise | yamux | ✅ | 4s | 18.401 | 1.43 |
| go-v0.40 x go-v0.45 (wss, tls, yamux) | go-v0.40 | go-v0.45 | wss | tls | yamux | ✅ | 4s | 24.033 | 1.991 |
| go-v0.40 x go-v0.45 (wss, noise, yamux) | go-v0.40 | go-v0.45 | wss | noise | yamux | ✅ | 5s | 16.497 | 0.677 |
| go-v0.40 x go-v0.45 (quic-v1) | go-v0.40 | go-v0.45 | quic-v1 | - | - | ✅ | 5s | 8.8 | 1.414 |
| go-v0.40 x go-v0.45 (webtransport) | go-v0.40 | go-v0.45 | webtransport | - | - | ✅ | 5s | 10.595 | 0.38 |
| go-v0.40 x go-v0.45 (webrtc-direct) | go-v0.40 | go-v0.45 | webrtc-direct | - | - | ✅ | 5s | 219.169 | 0.686 |
| go-v0.40 x python-v0.4 (tcp, noise, yamux) | go-v0.40 | python-v0.4 | tcp | noise | yamux | ✅ | 5s | 19.852 | 2.847 |
| go-v0.40 x python-v0.4 (wss, noise, yamux) | go-v0.40 | python-v0.4 | wss | noise | yamux | ✅ | 6s | 40.607 | 6.042 |
| go-v0.40 x python-v0.4 (ws, noise, yamux) | go-v0.40 | python-v0.4 | ws | noise | yamux | ✅ | 6s | 23.689 | 4.878 |
| go-v0.40 x python-v0.4 (quic-v1) | go-v0.40 | python-v0.4 | quic-v1 | - | - | ✅ | 6s | 61.816 | 15.463 |
| go-v0.40 x nim-v1.14 (tcp, noise, yamux) | go-v0.40 | nim-v1.14 | tcp | noise | yamux | ✅ | 5s | 219.946 | 43.611 |
| go-v0.40 x nim-v1.14 (ws, noise, yamux) | go-v0.40 | nim-v1.14 | ws | noise | yamux | ✅ | 5s | 251.476 | 43.333 |
| go-v0.40 x js-v1.x (tcp, noise, yamux) | go-v0.40 | js-v1.x | tcp | noise | yamux | ✅ | 18s | 155.182 | 18.324 |
| go-v0.40 x js-v1.x (ws, noise, yamux) | go-v0.40 | js-v1.x | ws | noise | yamux | ✅ | 19s | 229.534 | 40.01 |
| go-v0.40 x js-v2.x (tcp, noise, yamux) | go-v0.40 | js-v2.x | tcp | noise | yamux | ✅ | 21s | 224.053 | 33.638 |
| go-v0.40 x js-v3.x (tcp, noise, yamux) | go-v0.40 | js-v3.x | tcp | noise | yamux | ✅ | 20s | 128.765 | 19.505 |
| go-v0.40 x jvm-v1.2 (tcp, noise, yamux) | go-v0.40 | jvm-v1.2 | tcp | noise | yamux | ✅ | 11s | 1061.787 | 19.846 |
| go-v0.40 x js-v2.x (ws, noise, yamux) | go-v0.40 | js-v2.x | ws | noise | yamux | ✅ | 22s | 216.449 | 31.886 |
| go-v0.40 x jvm-v1.2 (tcp, tls, yamux) | go-v0.40 | jvm-v1.2 | tcp | tls | yamux | ✅ | 13s | 3112.916 | 16.418 |
| go-v0.40 x js-v3.x (ws, noise, yamux) | go-v0.40 | js-v3.x | ws | noise | yamux | ✅ | 20s | 151.185 | 12.748 |
| go-v0.40 x c-v0.0.1 (tcp, noise, yamux) | go-v0.40 | c-v0.0.1 | tcp | noise | yamux | ✅ | 6s | 146.993 | 59.828 |
| go-v0.40 x c-v0.0.1 (quic-v1) | go-v0.40 | c-v0.0.1 | quic-v1 | - | - | ✅ | 5s | 72.243 | 47.197 |
| go-v0.40 x jvm-v1.2 (ws, noise, yamux) | go-v0.40 | jvm-v1.2 | ws | noise | yamux | ✅ | 10s | 1554.22 | 45.777 |
| go-v0.40 x jvm-v1.2 (ws, tls, yamux) | go-v0.40 | jvm-v1.2 | ws | tls | yamux | ✅ | 12s | 3680.811 | 24.692 |
| go-v0.40 x zig-v0.0.1 (quic-v1) | go-v0.40 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 6s | - | - |
| go-v0.40 x dotnet-v1.0 (tcp, noise, yamux) | go-v0.40 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 7s | 380.247 | 45.614 |
| go-v0.40 x eth-p2p-z-v0.0.1 (quic-v1) | go-v0.40 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 11.454 | 0.257 |
| go-v0.40 x jvm-v1.2 (quic-v1) | go-v0.40 | jvm-v1.2 | quic-v1 | - | - | ✅ | 11s | 630.641 | 3.869 |
| go-v0.41 x rust-v0.53 (tcp, tls, yamux) | go-v0.41 | rust-v0.53 | tcp | tls | yamux | ✅ | 4s | 96.367 | 42.816 |
| go-v0.41 x rust-v0.53 (tcp, noise, yamux) | go-v0.41 | rust-v0.53 | tcp | noise | yamux | ✅ | 4s | 107.777 | 49.993 |
| go-v0.41 x rust-v0.53 (ws, tls, yamux) | go-v0.41 | rust-v0.53 | ws | tls | yamux | ✅ | 5s | 180.533 | 42.803 |
| go-v0.41 x rust-v0.53 (ws, noise, yamux) | go-v0.41 | rust-v0.53 | ws | noise | yamux | ✅ | 6s | 192.138 | 47.706 |
| go-v0.41 x rust-v0.53 (quic-v1) | go-v0.41 | rust-v0.53 | quic-v1 | - | - | ✅ | 5s | 8.545 | 0.701 |
| go-v0.41 x rust-v0.54 (tcp, tls, yamux) | go-v0.41 | rust-v0.54 | tcp | tls | yamux | ✅ | 4s | 49.152 | 0.153 |
| go-v0.41 x rust-v0.53 (webrtc-direct) | go-v0.41 | rust-v0.53 | webrtc-direct | - | - | ✅ | 6s | 411.491 | 0.239 |
| go-v0.41 x rust-v0.54 (tcp, noise, yamux) | go-v0.41 | rust-v0.54 | tcp | noise | yamux | ✅ | 5s | 138.138 | 47.69 |
| go-v0.41 x rust-v0.54 (ws, tls, yamux) | go-v0.41 | rust-v0.54 | ws | tls | yamux | ✅ | 6s | 227.152 | 43.691 |
| go-v0.41 x rust-v0.54 (ws, noise, yamux) | go-v0.41 | rust-v0.54 | ws | noise | yamux | ✅ | 5s | 223.252 | 43.192 |
| go-v0.41 x rust-v0.54 (quic-v1) | go-v0.41 | rust-v0.54 | quic-v1 | - | - | ✅ | 5s | 17.211 | 1.441 |
| go-v0.41 x rust-v0.55 (tcp, tls, yamux) | go-v0.41 | rust-v0.55 | tcp | tls | yamux | ✅ | 4s | 14.382 | 2.5 |
| go-v0.41 x rust-v0.55 (tcp, noise, yamux) | go-v0.41 | rust-v0.55 | tcp | noise | yamux | ✅ | 5s | 3.992 | 0.352 |
| go-v0.41 x rust-v0.55 (ws, tls, yamux) | go-v0.41 | rust-v0.55 | ws | tls | yamux | ✅ | 5s | 4.233 | 0.177 |
| go-v0.41 x rust-v0.54 (webrtc-direct) | go-v0.41 | rust-v0.54 | webrtc-direct | - | - | ✅ | 6s | 412.668 | 1.619 |
| go-v0.41 x rust-v0.55 (ws, noise, yamux) | go-v0.41 | rust-v0.55 | ws | noise | yamux | ✅ | 5s | 3.567 | 0.356 |
| go-v0.41 x rust-v0.55 (quic-v1) | go-v0.41 | rust-v0.55 | quic-v1 | - | - | ✅ | 5s | 5.71 | 0.226 |
| go-v0.41 x rust-v0.55 (webrtc-direct) | go-v0.41 | rust-v0.55 | webrtc-direct | - | - | ✅ | 4s | 413.369 | 0.917 |
| go-v0.41 x rust-v0.56 (tcp, tls, yamux) | go-v0.41 | rust-v0.56 | tcp | tls | yamux | ✅ | 3s | 5.896 | 0.215 |
| go-v0.41 x rust-v0.56 (tcp, noise, yamux) | go-v0.41 | rust-v0.56 | tcp | noise | yamux | ✅ | 4s | 12.797 | 0.464 |
| go-v0.41 x rust-v0.56 (ws, noise, yamux) | go-v0.41 | rust-v0.56 | ws | noise | yamux | ✅ | 4s | 7.735 | 0.958 |
| go-v0.41 x rust-v0.56 (ws, tls, yamux) | go-v0.41 | rust-v0.56 | ws | tls | yamux | ✅ | 5s | 11.314 | 0.626 |
| go-v0.41 x rust-v0.56 (quic-v1) | go-v0.41 | rust-v0.56 | quic-v1 | - | - | ✅ | 5s | 11.219 | 1.29 |
| go-v0.41 x go-v0.38 (tcp, tls, yamux) | go-v0.41 | go-v0.38 | tcp | tls | yamux | ✅ | 5s | 8.632 | 1.19 |
| go-v0.41 x go-v0.38 (tcp, noise, yamux) | go-v0.41 | go-v0.38 | tcp | noise | yamux | ✅ | 4s | 6.782 | 0.648 |
| go-v0.41 x go-v0.38 (ws, tls, yamux) | go-v0.41 | go-v0.38 | ws | tls | yamux | ✅ | 4s | 5.286 | 0.201 |
| go-v0.41 x go-v0.38 (ws, noise, yamux) | go-v0.41 | go-v0.38 | ws | noise | yamux | ✅ | 4s | 15.367 | 1.628 |
| go-v0.41 x go-v0.38 (wss, tls, yamux) | go-v0.41 | go-v0.38 | wss | tls | yamux | ✅ | 5s | 12.721 | 0.331 |
| go-v0.41 x go-v0.38 (wss, noise, yamux) | go-v0.41 | go-v0.38 | wss | noise | yamux | ✅ | 5s | 11.588 | 0.301 |
| go-v0.41 x go-v0.38 (quic-v1) | go-v0.41 | go-v0.38 | quic-v1 | - | - | ✅ | 5s | 10.336 | 0.475 |
| go-v0.41 x rust-v0.56 (webrtc-direct) | go-v0.41 | rust-v0.56 | webrtc-direct | - | - | ❌ | 11s | - | - |
| go-v0.41 x go-v0.38 (webtransport) | go-v0.41 | go-v0.38 | webtransport | - | - | ✅ | 6s | 8.418 | 0.4 |
| go-v0.41 x go-v0.38 (webrtc-direct) | go-v0.41 | go-v0.38 | webrtc-direct | - | - | ✅ | 5s | 210.488 | 0.337 |
| go-v0.41 x go-v0.39 (tcp, tls, yamux) | go-v0.41 | go-v0.39 | tcp | tls | yamux | ✅ | 5s | 10.06 | 0.694 |
| go-v0.41 x go-v0.39 (tcp, noise, yamux) | go-v0.41 | go-v0.39 | tcp | noise | yamux | ✅ | 5s | 4.74 | 0.206 |
| go-v0.41 x go-v0.39 (ws, tls, yamux) | go-v0.41 | go-v0.39 | ws | tls | yamux | ✅ | 5s | 11.981 | 0.359 |
| go-v0.41 x go-v0.39 (ws, noise, yamux) | go-v0.41 | go-v0.39 | ws | noise | yamux | ✅ | 5s | 11.947 | 0.432 |
| go-v0.41 x go-v0.39 (wss, tls, yamux) | go-v0.41 | go-v0.39 | wss | tls | yamux | ✅ | 4s | 18.763 | 1.076 |
| go-v0.41 x go-v0.39 (wss, noise, yamux) | go-v0.41 | go-v0.39 | wss | noise | yamux | ✅ | 6s | 14.385 | 1.715 |
| go-v0.41 x go-v0.39 (quic-v1) | go-v0.41 | go-v0.39 | quic-v1 | - | - | ✅ | 5s | 9.458 | 0.539 |
| go-v0.41 x go-v0.39 (webtransport) | go-v0.41 | go-v0.39 | webtransport | - | - | ✅ | 4s | 19.232 | 0.913 |
| go-v0.41 x go-v0.40 (tcp, tls, yamux) | go-v0.41 | go-v0.40 | tcp | tls | yamux | ✅ | 4s | 4.461 | 0.196 |
| go-v0.41 x go-v0.39 (webrtc-direct) | go-v0.41 | go-v0.39 | webrtc-direct | - | - | ✅ | 6s | 212.077 | 0.438 |
| go-v0.41 x go-v0.40 (tcp, noise, yamux) | go-v0.41 | go-v0.40 | tcp | noise | yamux | ✅ | 4s | 6.998 | 0.244 |
| go-v0.41 x go-v0.40 (ws, noise, yamux) | go-v0.41 | go-v0.40 | ws | noise | yamux | ✅ | 4s | 38.235 | 5.467 |
| go-v0.41 x go-v0.40 (ws, tls, yamux) | go-v0.41 | go-v0.40 | ws | tls | yamux | ✅ | 6s | 12.673 | 0.539 |
| go-v0.41 x go-v0.40 (wss, tls, yamux) | go-v0.41 | go-v0.40 | wss | tls | yamux | ✅ | 5s | 11.784 | 0.794 |
| go-v0.41 x go-v0.40 (wss, noise, yamux) | go-v0.41 | go-v0.40 | wss | noise | yamux | ✅ | 5s | 20.791 | 3.215 |
| go-v0.41 x go-v0.40 (quic-v1) | go-v0.41 | go-v0.40 | quic-v1 | - | - | ✅ | 5s | 13.373 | 2.994 |
| go-v0.41 x go-v0.40 (webtransport) | go-v0.41 | go-v0.40 | webtransport | - | - | ✅ | 4s | 8.742 | 0.304 |
| go-v0.41 x go-v0.40 (webrtc-direct) | go-v0.41 | go-v0.40 | webrtc-direct | - | - | ✅ | 5s | 15.212 | 1 |
| go-v0.41 x go-v0.41 (tcp, tls, yamux) | go-v0.41 | go-v0.41 | tcp | tls | yamux | ✅ | 5s | 6.749 | 0.295 |
| go-v0.41 x go-v0.41 (tcp, noise, yamux) | go-v0.41 | go-v0.41 | tcp | noise | yamux | ✅ | 5s | 10.195 | 1.668 |
| go-v0.41 x go-v0.41 (ws, tls, yamux) | go-v0.41 | go-v0.41 | ws | tls | yamux | ✅ | 5s | 12.379 | 1.037 |
| go-v0.41 x go-v0.41 (ws, noise, yamux) | go-v0.41 | go-v0.41 | ws | noise | yamux | ✅ | 5s | 7.309 | 0.684 |
| go-v0.41 x go-v0.41 (wss, tls, yamux) | go-v0.41 | go-v0.41 | wss | tls | yamux | ✅ | 5s | 21.081 | 1.279 |
| go-v0.41 x go-v0.41 (quic-v1) | go-v0.41 | go-v0.41 | quic-v1 | - | - | ✅ | 5s | 10.862 | 0.681 |
| go-v0.41 x go-v0.41 (webtransport) | go-v0.41 | go-v0.41 | webtransport | - | - | ✅ | 5s | 28.215 | 0.89 |
| go-v0.41 x go-v0.41 (wss, noise, yamux) | go-v0.41 | go-v0.41 | wss | noise | yamux | ✅ | 6s | 11.569 | 0.316 |
| go-v0.41 x go-v0.41 (webrtc-direct) | go-v0.41 | go-v0.41 | webrtc-direct | - | - | ✅ | 5s | 209.167 | 0.476 |
| go-v0.41 x go-v0.42 (tcp, tls, yamux) | go-v0.41 | go-v0.42 | tcp | tls | yamux | ✅ | 5s | 7.226 | 0.303 |
| go-v0.41 x go-v0.42 (tcp, noise, yamux) | go-v0.41 | go-v0.42 | tcp | noise | yamux | ✅ | 5s | 10.733 | 0.659 |
| go-v0.41 x go-v0.42 (ws, tls, yamux) | go-v0.41 | go-v0.42 | ws | tls | yamux | ✅ | 5s | 9.826 | 0.851 |
| go-v0.41 x go-v0.42 (ws, noise, yamux) | go-v0.41 | go-v0.42 | ws | noise | yamux | ✅ | 5s | 8.486 | 1.679 |
| go-v0.41 x go-v0.42 (quic-v1) | go-v0.41 | go-v0.42 | quic-v1 | - | - | ✅ | 4s | 17.435 | 1.207 |
| go-v0.41 x go-v0.42 (webtransport) | go-v0.41 | go-v0.42 | webtransport | - | - | ✅ | 5s | 15.344 | 0.768 |
| go-v0.41 x go-v0.42 (wss, tls, yamux) | go-v0.41 | go-v0.42 | wss | tls | yamux | ✅ | 6s | 14.664 | 1.336 |
| go-v0.41 x go-v0.42 (wss, noise, yamux) | go-v0.41 | go-v0.42 | wss | noise | yamux | ✅ | 6s | 27.117 | 4.166 |
| go-v0.41 x go-v0.42 (webrtc-direct) | go-v0.41 | go-v0.42 | webrtc-direct | - | - | ✅ | 6s | 278.552 | 0.233 |
| go-v0.41 x go-v0.43 (tcp, tls, yamux) | go-v0.41 | go-v0.43 | tcp | tls | yamux | ✅ | 4s | 8.3 | 0.838 |
| go-v0.41 x go-v0.43 (tcp, noise, yamux) | go-v0.41 | go-v0.43 | tcp | noise | yamux | ✅ | 4s | 8.16 | 2.168 |
| go-v0.41 x go-v0.43 (ws, tls, yamux) | go-v0.41 | go-v0.43 | ws | tls | yamux | ✅ | 4s | 10.643 | 2.881 |
| go-v0.41 x go-v0.43 (ws, noise, yamux) | go-v0.41 | go-v0.43 | ws | noise | yamux | ✅ | 4s | 15.106 | 1.32 |
| go-v0.41 x go-v0.43 (quic-v1) | go-v0.41 | go-v0.43 | quic-v1 | - | - | ✅ | 4s | 22.212 | 1.531 |
| go-v0.41 x go-v0.43 (wss, noise, yamux) | go-v0.41 | go-v0.43 | wss | noise | yamux | ✅ | 6s | 18.843 | 0.318 |
| go-v0.41 x go-v0.43 (webtransport) | go-v0.41 | go-v0.43 | webtransport | - | - | ✅ | 5s | 14.552 | 0.49 |
| go-v0.41 x go-v0.43 (wss, tls, yamux) | go-v0.41 | go-v0.43 | wss | tls | yamux | ✅ | 7s | 10.285 | 0.634 |
| go-v0.41 x go-v0.43 (webrtc-direct) | go-v0.41 | go-v0.43 | webrtc-direct | - | - | ✅ | 5s | 210.654 | 0.369 |
| go-v0.41 x go-v0.44 (tcp, tls, yamux) | go-v0.41 | go-v0.44 | tcp | tls | yamux | ✅ | 5s | 8.17 | 0.766 |
| go-v0.41 x go-v0.44 (tcp, noise, yamux) | go-v0.41 | go-v0.44 | tcp | noise | yamux | ✅ | 6s | 11.034 | 0.364 |
| go-v0.41 x go-v0.44 (ws, tls, yamux) | go-v0.41 | go-v0.44 | ws | tls | yamux | ✅ | 4s | 4.517 | 0.419 |
| go-v0.41 x go-v0.44 (ws, noise, yamux) | go-v0.41 | go-v0.44 | ws | noise | yamux | ✅ | 5s | 14.82 | 0.851 |
| go-v0.41 x go-v0.44 (wss, tls, yamux) | go-v0.41 | go-v0.44 | wss | tls | yamux | ✅ | 6s | 36.036 | 1.598 |
| go-v0.41 x go-v0.44 (wss, noise, yamux) | go-v0.41 | go-v0.44 | wss | noise | yamux | ✅ | 5s | 20.318 | 0.96 |
| go-v0.41 x go-v0.44 (quic-v1) | go-v0.41 | go-v0.44 | quic-v1 | - | - | ✅ | 6s | 9.616 | 0.975 |
| go-v0.41 x go-v0.44 (webtransport) | go-v0.41 | go-v0.44 | webtransport | - | - | ✅ | 5s | 9.227 | 0.286 |
| go-v0.41 x go-v0.44 (webrtc-direct) | go-v0.41 | go-v0.44 | webrtc-direct | - | - | ✅ | 5s | 215.852 | 0.237 |
| go-v0.41 x go-v0.45 (tcp, tls, yamux) | go-v0.41 | go-v0.45 | tcp | tls | yamux | ✅ | 5s | 6.656 | 0.289 |
| go-v0.41 x go-v0.45 (tcp, noise, yamux) | go-v0.41 | go-v0.45 | tcp | noise | yamux | ✅ | 5s | 10.114 | 0.568 |
| go-v0.41 x go-v0.45 (ws, tls, yamux) | go-v0.41 | go-v0.45 | ws | tls | yamux | ✅ | 4s | 10.271 | 0.415 |
| go-v0.41 x go-v0.45 (ws, noise, yamux) | go-v0.41 | go-v0.45 | ws | noise | yamux | ✅ | 5s | 15.07 | 0.468 |
| go-v0.41 x go-v0.45 (wss, tls, yamux) | go-v0.41 | go-v0.45 | wss | tls | yamux | ✅ | 4s | 18.599 | 0.664 |
| go-v0.41 x go-v0.45 (wss, noise, yamux) | go-v0.41 | go-v0.45 | wss | noise | yamux | ✅ | 5s | 11.643 | 0.422 |
| go-v0.41 x go-v0.45 (quic-v1) | go-v0.41 | go-v0.45 | quic-v1 | - | - | ✅ | 5s | 16.144 | 1.175 |
| go-v0.41 x go-v0.45 (webtransport) | go-v0.41 | go-v0.45 | webtransport | - | - | ✅ | 5s | 17.014 | 0.463 |
| go-v0.41 x go-v0.45 (webrtc-direct) | go-v0.41 | go-v0.45 | webrtc-direct | - | - | ✅ | 5s | 221.118 | 0.322 |
| go-v0.41 x python-v0.4 (tcp, noise, yamux) | go-v0.41 | python-v0.4 | tcp | noise | yamux | ✅ | 5s | 11.355 | 1.758 |
| go-v0.41 x python-v0.4 (ws, noise, yamux) | go-v0.41 | python-v0.4 | ws | noise | yamux | ✅ | 5s | 31.155 | 5.154 |
| go-v0.41 x python-v0.4 (wss, noise, yamux) | go-v0.41 | python-v0.4 | wss | noise | yamux | ✅ | 6s | 39.593 | 6.736 |
| go-v0.41 x python-v0.4 (quic-v1) | go-v0.41 | python-v0.4 | quic-v1 | - | - | ✅ | 5s | 69.104 | 17.124 |
| go-v0.41 x nim-v1.14 (tcp, noise, yamux) | go-v0.41 | nim-v1.14 | tcp | noise | yamux | ✅ | 4s | 216.179 | 43.618 |
| go-v0.41 x nim-v1.14 (ws, noise, yamux) | go-v0.41 | nim-v1.14 | ws | noise | yamux | ✅ | 5s | 260.189 | 46.902 |
| go-v0.41 x js-v1.x (tcp, noise, yamux) | go-v0.41 | js-v1.x | tcp | noise | yamux | ✅ | 19s | 185.979 | 18.447 |
| go-v0.41 x js-v1.x (ws, noise, yamux) | go-v0.41 | js-v1.x | ws | noise | yamux | ✅ | 21s | 159.043 | 11.267 |
| go-v0.41 x js-v2.x (tcp, noise, yamux) | go-v0.41 | js-v2.x | tcp | noise | yamux | ✅ | 21s | 147.527 | 24.695 |
| go-v0.41 x jvm-v1.2 (tcp, noise, yamux) | go-v0.41 | jvm-v1.2 | tcp | noise | yamux | ✅ | 11s | 1475.474 | 37.304 |
| go-v0.41 x js-v3.x (tcp, noise, yamux) | go-v0.41 | js-v3.x | tcp | noise | yamux | ✅ | 22s | 128.08 | 22.247 |
| go-v0.41 x jvm-v1.2 (tcp, tls, yamux) | go-v0.41 | jvm-v1.2 | tcp | tls | yamux | ✅ | 13s | 3381.896 | 18.865 |
| go-v0.41 x js-v2.x (ws, noise, yamux) | go-v0.41 | js-v2.x | ws | noise | yamux | ✅ | 23s | 104.137 | 21.726 |
| go-v0.41 x js-v3.x (ws, noise, yamux) | go-v0.41 | js-v3.x | ws | noise | yamux | ✅ | 22s | 110.836 | 14.882 |
| go-v0.41 x c-v0.0.1 (tcp, noise, yamux) | go-v0.41 | c-v0.0.1 | tcp | noise | yamux | ✅ | 5s | 128.437 | 51.918 |
| go-v0.41 x c-v0.0.1 (quic-v1) | go-v0.41 | c-v0.0.1 | quic-v1 | - | - | ✅ | 5s | 63.167 | 37.216 |
| go-v0.41 x jvm-v1.2 (ws, noise, yamux) | go-v0.41 | jvm-v1.2 | ws | noise | yamux | ✅ | 9s | 1511.781 | 14.541 |
| go-v0.41 x zig-v0.0.1 (quic-v1) | go-v0.41 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 5s | - | - |
| go-v0.41 x dotnet-v1.0 (tcp, noise, yamux) | go-v0.41 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 7s | 536.134 | 47.161 |
| go-v0.41 x eth-p2p-z-v0.0.1 (quic-v1) | go-v0.41 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 14.226 | 0.23 |
| go-v0.41 x jvm-v1.2 (ws, tls, yamux) | go-v0.41 | jvm-v1.2 | ws | tls | yamux | ✅ | 13s | 3636.854 | 17.242 |
| go-v0.41 x jvm-v1.2 (quic-v1) | go-v0.41 | jvm-v1.2 | quic-v1 | - | - | ✅ | 11s | 523.357 | 8.561 |
| go-v0.42 x rust-v0.53 (tcp, tls, yamux) | go-v0.42 | rust-v0.53 | tcp | tls | yamux | ✅ | 4s | 91.305 | 41.654 |
| go-v0.42 x rust-v0.53 (tcp, noise, yamux) | go-v0.42 | rust-v0.53 | tcp | noise | yamux | ✅ | 5s | 95.586 | 40.997 |
| go-v0.42 x rust-v0.53 (ws, tls, yamux) | go-v0.42 | rust-v0.53 | ws | tls | yamux | ✅ | 4s | 184.447 | 42.022 |
| go-v0.42 x rust-v0.53 (quic-v1) | go-v0.42 | rust-v0.53 | quic-v1 | - | - | ✅ | 5s | 11.6 | 1.074 |
| go-v0.42 x rust-v0.53 (ws, noise, yamux) | go-v0.42 | rust-v0.53 | ws | noise | yamux | ✅ | 5s | 190.308 | 44.487 |
| go-v0.42 x rust-v0.54 (tcp, noise, yamux) | go-v0.42 | rust-v0.54 | tcp | noise | yamux | ✅ | 4s | 93.86 | 47.027 |
| go-v0.42 x rust-v0.54 (tcp, tls, yamux) | go-v0.42 | rust-v0.54 | tcp | tls | yamux | ✅ | 5s | 89.108 | 43.159 |
| go-v0.42 x rust-v0.53 (webrtc-direct) | go-v0.42 | rust-v0.53 | webrtc-direct | - | - | ✅ | 6s | 442.895 | 1.241 |
| go-v0.42 x rust-v0.54 (ws, tls, yamux) | go-v0.42 | rust-v0.54 | ws | tls | yamux | ✅ | 5s | 188.082 | 44.636 |
| go-v0.42 x rust-v0.54 (ws, noise, yamux) | go-v0.42 | rust-v0.54 | ws | noise | yamux | ✅ | 5s | 230.764 | 43.938 |
| go-v0.42 x rust-v0.54 (quic-v1) | go-v0.42 | rust-v0.54 | quic-v1 | - | - | ✅ | 5s | 9.857 | 0.574 |
| go-v0.42 x rust-v0.54 (webrtc-direct) | go-v0.42 | rust-v0.54 | webrtc-direct | - | - | ✅ | 6s | 437.936 | 0.774 |
| go-v0.42 x rust-v0.55 (tcp, noise, yamux) | go-v0.42 | rust-v0.55 | tcp | noise | yamux | ✅ | 4s | 7.557 | 0.445 |
| go-v0.42 x rust-v0.55 (tcp, tls, yamux) | go-v0.42 | rust-v0.55 | tcp | tls | yamux | ✅ | 5s | 12.014 | 0.542 |
| go-v0.42 x rust-v0.55 (ws, tls, yamux) | go-v0.42 | rust-v0.55 | ws | tls | yamux | ✅ | 5s | 16.528 | 3.1 |
| go-v0.42 x rust-v0.55 (ws, noise, yamux) | go-v0.42 | rust-v0.55 | ws | noise | yamux | ✅ | 5s | 4.326 | 0.326 |
| go-v0.42 x rust-v0.55 (quic-v1) | go-v0.42 | rust-v0.55 | quic-v1 | - | - | ✅ | 5s | 20.373 | 0.535 |
| go-v0.42 x rust-v0.56 (tcp, tls, yamux) | go-v0.42 | rust-v0.56 | tcp | tls | yamux | ✅ | 5s | 11.762 | 0.324 |
| go-v0.42 x rust-v0.55 (webrtc-direct) | go-v0.42 | rust-v0.55 | webrtc-direct | - | - | ✅ | 5s | 422.976 | 0.611 |
| go-v0.42 x rust-v0.56 (tcp, noise, yamux) | go-v0.42 | rust-v0.56 | tcp | noise | yamux | ✅ | 5s | 8.084 | 0.807 |
| go-v0.42 x rust-v0.56 (ws, tls, yamux) | go-v0.42 | rust-v0.56 | ws | tls | yamux | ✅ | 4s | 22.025 | 0.776 |
| go-v0.42 x rust-v0.56 (ws, noise, yamux) | go-v0.42 | rust-v0.56 | ws | noise | yamux | ✅ | 5s | 11.566 | 1.341 |
| go-v0.42 x rust-v0.56 (quic-v1) | go-v0.42 | rust-v0.56 | quic-v1 | - | - | ✅ | 5s | 40.618 | 0.402 |
| go-v0.42 x go-v0.38 (tcp, tls, yamux) | go-v0.42 | go-v0.38 | tcp | tls | yamux | ✅ | 5s | 11.652 | 0.902 |
| go-v0.42 x go-v0.38 (tcp, noise, yamux) | go-v0.42 | go-v0.38 | tcp | noise | yamux | ✅ | 4s | 7.448 | 0.674 |
| go-v0.42 x go-v0.38 (ws, tls, yamux) | go-v0.42 | go-v0.38 | ws | tls | yamux | ✅ | 4s | 7.968 | 1.06 |
| go-v0.42 x go-v0.38 (ws, noise, yamux) | go-v0.42 | go-v0.38 | ws | noise | yamux | ✅ | 4s | 21.816 | 5.452 |
| go-v0.42 x go-v0.38 (wss, noise, yamux) | go-v0.42 | go-v0.38 | wss | noise | yamux | ✅ | 5s | 10.564 | 0.849 |
| go-v0.42 x go-v0.38 (wss, tls, yamux) | go-v0.42 | go-v0.38 | wss | tls | yamux | ✅ | 5s | 14.002 | 1.276 |
| go-v0.42 x go-v0.38 (quic-v1) | go-v0.42 | go-v0.38 | quic-v1 | - | - | ✅ | 5s | 10.529 | 1.474 |
| go-v0.42 x rust-v0.56 (webrtc-direct) | go-v0.42 | rust-v0.56 | webrtc-direct | - | - | ❌ | 10s | - | - |
| go-v0.42 x go-v0.38 (webtransport) | go-v0.42 | go-v0.38 | webtransport | - | - | ✅ | 4s | 6.95 | 0.253 |
| go-v0.42 x go-v0.38 (webrtc-direct) | go-v0.42 | go-v0.38 | webrtc-direct | - | - | ✅ | 5s | 215.841 | 0.806 |
| go-v0.42 x go-v0.39 (tcp, tls, yamux) | go-v0.42 | go-v0.39 | tcp | tls | yamux | ✅ | 5s | 13.71 | 0.925 |
| go-v0.42 x go-v0.39 (tcp, noise, yamux) | go-v0.42 | go-v0.39 | tcp | noise | yamux | ✅ | 4s | 8.547 | 0.26 |
| go-v0.42 x go-v0.39 (ws, tls, yamux) | go-v0.42 | go-v0.39 | ws | tls | yamux | ✅ | 5s | 17.246 | 0.615 |
| go-v0.42 x go-v0.39 (ws, noise, yamux) | go-v0.42 | go-v0.39 | ws | noise | yamux | ✅ | 5s | 16.427 | 0.684 |
| go-v0.42 x go-v0.39 (quic-v1) | go-v0.42 | go-v0.39 | quic-v1 | - | - | ✅ | 5s | 14.531 | 1.812 |
| go-v0.42 x go-v0.39 (wss, noise, yamux) | go-v0.42 | go-v0.39 | wss | noise | yamux | ✅ | 5s | 14.115 | 0.579 |
| go-v0.42 x go-v0.39 (wss, tls, yamux) | go-v0.42 | go-v0.39 | wss | tls | yamux | ✅ | 6s | 12.171 | 0.23 |
| go-v0.42 x go-v0.39 (webtransport) | go-v0.42 | go-v0.39 | webtransport | - | - | ✅ | 5s | 16.295 | 0.565 |
| go-v0.42 x go-v0.39 (webrtc-direct) | go-v0.42 | go-v0.39 | webrtc-direct | - | - | ✅ | 5s | 215.127 | 0.971 |
| go-v0.42 x go-v0.40 (tcp, tls, yamux) | go-v0.42 | go-v0.40 | tcp | tls | yamux | ✅ | 5s | 10.768 | 2.574 |
| go-v0.42 x go-v0.40 (tcp, noise, yamux) | go-v0.42 | go-v0.40 | tcp | noise | yamux | ✅ | 5s | 7.454 | 1.183 |
| go-v0.42 x go-v0.40 (ws, tls, yamux) | go-v0.42 | go-v0.40 | ws | tls | yamux | ✅ | 5s | 10.219 | 1.66 |
| go-v0.42 x go-v0.40 (ws, noise, yamux) | go-v0.42 | go-v0.40 | ws | noise | yamux | ✅ | 4s | 15.912 | 4.69 |
| go-v0.42 x go-v0.40 (wss, tls, yamux) | go-v0.42 | go-v0.40 | wss | tls | yamux | ✅ | 4s | 19.312 | 1.402 |
| go-v0.42 x go-v0.40 (quic-v1) | go-v0.42 | go-v0.40 | quic-v1 | - | - | ✅ | 5s | 11.426 | 1.793 |
| go-v0.42 x go-v0.40 (wss, noise, yamux) | go-v0.42 | go-v0.40 | wss | noise | yamux | ✅ | 6s | 16.834 | 0.975 |
| go-v0.42 x go-v0.40 (webtransport) | go-v0.42 | go-v0.40 | webtransport | - | - | ✅ | 5s | 11.104 | 0.362 |
| go-v0.42 x go-v0.40 (webrtc-direct) | go-v0.42 | go-v0.40 | webrtc-direct | - | - | ✅ | 5s | 215.743 | 0.54 |
| go-v0.42 x go-v0.41 (tcp, tls, yamux) | go-v0.42 | go-v0.41 | tcp | tls | yamux | ✅ | 5s | 7.34 | 0.335 |
| go-v0.42 x go-v0.41 (tcp, noise, yamux) | go-v0.42 | go-v0.41 | tcp | noise | yamux | ✅ | 4s | 8.916 | 0.845 |
| go-v0.42 x go-v0.41 (ws, tls, yamux) | go-v0.42 | go-v0.41 | ws | tls | yamux | ✅ | 5s | 9.588 | 0.45 |
| go-v0.42 x go-v0.41 (ws, noise, yamux) | go-v0.42 | go-v0.41 | ws | noise | yamux | ✅ | 5s | 7.809 | 0.263 |
| go-v0.42 x go-v0.41 (wss, tls, yamux) | go-v0.42 | go-v0.41 | wss | tls | yamux | ✅ | 5s | 16.064 | 2.621 |
| go-v0.42 x go-v0.41 (quic-v1) | go-v0.42 | go-v0.41 | quic-v1 | - | - | ✅ | 4s | 17.904 | 4.497 |
| go-v0.42 x go-v0.41 (wss, noise, yamux) | go-v0.42 | go-v0.41 | wss | noise | yamux | ✅ | 6s | 13.194 | 0.707 |
| go-v0.42 x go-v0.41 (webtransport) | go-v0.42 | go-v0.41 | webtransport | - | - | ✅ | 5s | 11.665 | 0.452 |
| go-v0.42 x go-v0.41 (webrtc-direct) | go-v0.42 | go-v0.41 | webrtc-direct | - | - | ✅ | 5s | 212.399 | 0.694 |
| go-v0.42 x go-v0.42 (tcp, tls, yamux) | go-v0.42 | go-v0.42 | tcp | tls | yamux | ✅ | 5s | 10.976 | 0.899 |
| go-v0.42 x go-v0.42 (tcp, noise, yamux) | go-v0.42 | go-v0.42 | tcp | noise | yamux | ✅ | 5s | 6.953 | 1.168 |
| go-v0.42 x go-v0.42 (ws, tls, yamux) | go-v0.42 | go-v0.42 | ws | tls | yamux | ✅ | 4s | 10.726 | 1.674 |
| go-v0.42 x go-v0.42 (ws, noise, yamux) | go-v0.42 | go-v0.42 | ws | noise | yamux | ✅ | 5s | 9.268 | 2.414 |
| go-v0.42 x go-v0.42 (wss, tls, yamux) | go-v0.42 | go-v0.42 | wss | tls | yamux | ✅ | 5s | 13.032 | 1.232 |
| go-v0.42 x go-v0.42 (quic-v1) | go-v0.42 | go-v0.42 | quic-v1 | - | - | ✅ | 4s | 6.845 | 0.472 |
| go-v0.42 x go-v0.42 (wss, noise, yamux) | go-v0.42 | go-v0.42 | wss | noise | yamux | ✅ | 5s | 8.959 | 0.446 |
| go-v0.42 x go-v0.42 (webtransport) | go-v0.42 | go-v0.42 | webtransport | - | - | ✅ | 5s | 13.445 | 0.474 |
| go-v0.42 x go-v0.42 (webrtc-direct) | go-v0.42 | go-v0.42 | webrtc-direct | - | - | ✅ | 5s | 211.338 | 0.417 |
| go-v0.42 x go-v0.43 (tcp, tls, yamux) | go-v0.42 | go-v0.43 | tcp | tls | yamux | ✅ | 5s | 8.421 | 0.88 |
| go-v0.42 x go-v0.43 (tcp, noise, yamux) | go-v0.42 | go-v0.43 | tcp | noise | yamux | ✅ | 4s | 10.178 | 1.358 |
| go-v0.42 x go-v0.43 (ws, tls, yamux) | go-v0.42 | go-v0.43 | ws | tls | yamux | ✅ | 5s | 5.792 | 0.205 |
| go-v0.42 x go-v0.43 (ws, noise, yamux) | go-v0.42 | go-v0.43 | ws | noise | yamux | ✅ | 5s | 12.335 | 3.733 |
| go-v0.42 x go-v0.43 (quic-v1) | go-v0.42 | go-v0.43 | quic-v1 | - | - | ✅ | 4s | 19.512 | 1.596 |
| go-v0.42 x go-v0.43 (wss, tls, yamux) | go-v0.42 | go-v0.43 | wss | tls | yamux | ✅ | 5s | 27.528 | 0.935 |
| go-v0.42 x go-v0.43 (wss, noise, yamux) | go-v0.42 | go-v0.43 | wss | noise | yamux | ✅ | 6s | 16.146 | 2.5 |
| go-v0.42 x go-v0.43 (webtransport) | go-v0.42 | go-v0.43 | webtransport | - | - | ✅ | 4s | 20.403 | 0.445 |
| go-v0.42 x go-v0.43 (webrtc-direct) | go-v0.42 | go-v0.43 | webrtc-direct | - | - | ✅ | 5s | 217.112 | 0.362 |
| go-v0.42 x go-v0.44 (tcp, tls, yamux) | go-v0.42 | go-v0.44 | tcp | tls | yamux | ✅ | 5s | 13.394 | 2.039 |
| go-v0.42 x go-v0.44 (tcp, noise, yamux) | go-v0.42 | go-v0.44 | tcp | noise | yamux | ✅ | 4s | 7.506 | 0.881 |
| go-v0.42 x go-v0.44 (ws, tls, yamux) | go-v0.42 | go-v0.44 | ws | tls | yamux | ✅ | 5s | 5.99 | 0.345 |
| go-v0.42 x go-v0.44 (ws, noise, yamux) | go-v0.42 | go-v0.44 | ws | noise | yamux | ✅ | 5s | 10.377 | 2.144 |
| go-v0.42 x go-v0.44 (quic-v1) | go-v0.42 | go-v0.44 | quic-v1 | - | - | ✅ | 4s | 13.565 | 1.217 |
| go-v0.42 x go-v0.44 (wss, tls, yamux) | go-v0.42 | go-v0.44 | wss | tls | yamux | ✅ | 5s | 42.697 | 0.421 |
| go-v0.42 x go-v0.44 (wss, noise, yamux) | go-v0.42 | go-v0.44 | wss | noise | yamux | ✅ | 6s | 80.805 | 0.641 |
| go-v0.42 x go-v0.44 (webtransport) | go-v0.42 | go-v0.44 | webtransport | - | - | ✅ | 6s | 19.022 | 1.091 |
| go-v0.42 x go-v0.44 (webrtc-direct) | go-v0.42 | go-v0.44 | webrtc-direct | - | - | ✅ | 5s | 212.874 | 0.323 |
| go-v0.42 x go-v0.45 (tcp, tls, yamux) | go-v0.42 | go-v0.45 | tcp | tls | yamux | ✅ | 4s | 5.939 | 0.69 |
| go-v0.42 x go-v0.45 (tcp, noise, yamux) | go-v0.42 | go-v0.45 | tcp | noise | yamux | ✅ | 4s | 10.861 | 2.973 |
| go-v0.42 x go-v0.45 (ws, tls, yamux) | go-v0.42 | go-v0.45 | ws | tls | yamux | ✅ | 5s | 11.207 | 1.986 |
| go-v0.42 x go-v0.45 (ws, noise, yamux) | go-v0.42 | go-v0.45 | ws | noise | yamux | ✅ | 5s | 7.565 | 0.309 |
| go-v0.42 x go-v0.45 (wss, tls, yamux) | go-v0.42 | go-v0.45 | wss | tls | yamux | ✅ | 4s | 18.043 | 0.766 |
| go-v0.42 x go-v0.45 (quic-v1) | go-v0.42 | go-v0.45 | quic-v1 | - | - | ✅ | 4s | 17.132 | 0.979 |
| go-v0.42 x go-v0.45 (wss, noise, yamux) | go-v0.42 | go-v0.45 | wss | noise | yamux | ✅ | 5s | 74.231 | 0.523 |
| go-v0.42 x go-v0.45 (webtransport) | go-v0.42 | go-v0.45 | webtransport | - | - | ✅ | 4s | 21.945 | 2.222 |
| go-v0.42 x go-v0.45 (webrtc-direct) | go-v0.42 | go-v0.45 | webrtc-direct | - | - | ✅ | 5s | 216.979 | 0.371 |
| go-v0.42 x python-v0.4 (tcp, noise, yamux) | go-v0.42 | python-v0.4 | tcp | noise | yamux | ✅ | 5s | 20.874 | 3.498 |
| go-v0.42 x python-v0.4 (ws, noise, yamux) | go-v0.42 | python-v0.4 | ws | noise | yamux | ✅ | 5s | 35.803 | 7.375 |
| go-v0.42 x python-v0.4 (wss, noise, yamux) | go-v0.42 | python-v0.4 | wss | noise | yamux | ✅ | 6s | 67.886 | 6.406 |
| go-v0.42 x python-v0.4 (quic-v1) | go-v0.42 | python-v0.4 | quic-v1 | - | - | ✅ | 6s | 85.711 | 16.785 |
| go-v0.42 x nim-v1.14 (tcp, noise, yamux) | go-v0.42 | nim-v1.14 | tcp | noise | yamux | ✅ | 5s | 219.252 | 43.543 |
| go-v0.42 x nim-v1.14 (ws, noise, yamux) | go-v0.42 | nim-v1.14 | ws | noise | yamux | ✅ | 5s | 259.267 | 47.617 |
| go-v0.42 x js-v1.x (tcp, noise, yamux) | go-v0.42 | js-v1.x | tcp | noise | yamux | ✅ | 20s | 138.295 | 17.353 |
| go-v0.42 x js-v1.x (ws, noise, yamux) | go-v0.42 | js-v1.x | ws | noise | yamux | ✅ | 19s | 169.623 | 23.396 |
| go-v0.42 x js-v2.x (tcp, noise, yamux) | go-v0.42 | js-v2.x | tcp | noise | yamux | ✅ | 21s | 146.828 | 28.191 |
| go-v0.42 x jvm-v1.2 (tcp, noise, yamux) | go-v0.42 | jvm-v1.2 | tcp | noise | yamux | ✅ | 10s | 1395.418 | 17.603 |
| go-v0.42 x js-v2.x (ws, noise, yamux) | go-v0.42 | js-v2.x | ws | noise | yamux | ✅ | 22s | 161.746 | 21.634 |
| go-v0.42 x js-v3.x (tcp, noise, yamux) | go-v0.42 | js-v3.x | tcp | noise | yamux | ✅ | 21s | 129.344 | 21.128 |
| go-v0.42 x js-v3.x (ws, noise, yamux) | go-v0.42 | js-v3.x | ws | noise | yamux | ✅ | 21s | 90.913 | 12.952 |
| go-v0.42 x jvm-v1.2 (tcp, tls, yamux) | go-v0.42 | jvm-v1.2 | tcp | tls | yamux | ✅ | 13s | 2909.839 | 6.744 |
| go-v0.42 x c-v0.0.1 (tcp, noise, yamux) | go-v0.42 | c-v0.0.1 | tcp | noise | yamux | ✅ | 5s | 131.174 | 60.268 |
| go-v0.42 x c-v0.0.1 (quic-v1) | go-v0.42 | c-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 46.71 | 30.073 |
| go-v0.42 x dotnet-v1.0 (tcp, noise, yamux) | go-v0.42 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 7s | 580.381 | 44.758 |
| go-v0.42 x jvm-v1.2 (ws, noise, yamux) | go-v0.42 | jvm-v1.2 | ws | noise | yamux | ✅ | 10s | 1525.163 | 39.805 |
| go-v0.42 x zig-v0.0.1 (quic-v1) | go-v0.42 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 6s | - | - |
| go-v0.42 x eth-p2p-z-v0.0.1 (quic-v1) | go-v0.42 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 31.271 | 4.103 |
| go-v0.42 x jvm-v1.2 (ws, tls, yamux) | go-v0.42 | jvm-v1.2 | ws | tls | yamux | ✅ | 12s | 3595.794 | 9.834 |
| go-v0.42 x jvm-v1.2 (quic-v1) | go-v0.42 | jvm-v1.2 | quic-v1 | - | - | ✅ | 11s | 497.323 | 11.905 |
| go-v0.43 x rust-v0.53 (tcp, noise, yamux) | go-v0.43 | rust-v0.53 | tcp | noise | yamux | ✅ | 4s | 95.261 | 43.779 |
| go-v0.43 x rust-v0.53 (tcp, tls, yamux) | go-v0.43 | rust-v0.53 | tcp | tls | yamux | ✅ | 5s | 145.419 | 43.767 |
| go-v0.43 x rust-v0.53 (ws, tls, yamux) | go-v0.43 | rust-v0.53 | ws | tls | yamux | ✅ | 4s | 234.442 | 42.909 |
| go-v0.43 x rust-v0.53 (ws, noise, yamux) | go-v0.43 | rust-v0.53 | ws | noise | yamux | ✅ | 5s | 179.825 | 42.526 |
| go-v0.43 x rust-v0.53 (quic-v1) | go-v0.43 | rust-v0.53 | quic-v1 | - | - | ✅ | 5s | 7.914 | 0.388 |
| go-v0.43 x rust-v0.54 (tcp, tls, yamux) | go-v0.43 | rust-v0.54 | tcp | tls | yamux | ✅ | 5s | 139.185 | 48.504 |
| go-v0.43 x rust-v0.53 (webrtc-direct) | go-v0.43 | rust-v0.53 | webrtc-direct | - | - | ✅ | 5s | 409.142 | 0.259 |
| go-v0.43 x rust-v0.54 (tcp, noise, yamux) | go-v0.43 | rust-v0.54 | tcp | noise | yamux | ✅ | 5s | 90.12 | 43.003 |
| go-v0.43 x rust-v0.54 (ws, tls, yamux) | go-v0.43 | rust-v0.54 | ws | tls | yamux | ✅ | 5s | 179.627 | 44.863 |
| go-v0.43 x rust-v0.54 (ws, noise, yamux) | go-v0.43 | rust-v0.54 | ws | noise | yamux | ✅ | 5s | 221.883 | 47.56 |
| go-v0.43 x rust-v0.54 (quic-v1) | go-v0.43 | rust-v0.54 | quic-v1 | - | - | ✅ | 4s | 17.493 | 1.927 |
| go-v0.43 x rust-v0.55 (tcp, tls, yamux) | go-v0.43 | rust-v0.55 | tcp | tls | yamux | ✅ | 4s | 8.325 | 1.584 |
| go-v0.43 x rust-v0.54 (webrtc-direct) | go-v0.43 | rust-v0.54 | webrtc-direct | - | - | ✅ | 6s | 421.673 | 0.709 |
| go-v0.43 x rust-v0.55 (tcp, noise, yamux) | go-v0.43 | rust-v0.55 | tcp | noise | yamux | ✅ | 5s | 3.821 | 0.195 |
| go-v0.43 x rust-v0.55 (ws, tls, yamux) | go-v0.43 | rust-v0.55 | ws | tls | yamux | ✅ | 5s | 5.141 | 0.243 |
| go-v0.43 x rust-v0.55 (ws, noise, yamux) | go-v0.43 | rust-v0.55 | ws | noise | yamux | ✅ | 6s | 17.71 | 0.661 |
| go-v0.43 x rust-v0.55 (quic-v1) | go-v0.43 | rust-v0.55 | quic-v1 | - | - | ✅ | 4s | 18.658 | 0.739 |
| go-v0.43 x rust-v0.55 (webrtc-direct) | go-v0.43 | rust-v0.55 | webrtc-direct | - | - | ✅ | 5s | 216.028 | 0.549 |
| go-v0.43 x rust-v0.56 (tcp, tls, yamux) | go-v0.43 | rust-v0.56 | tcp | tls | yamux | ✅ | 5s | 5.818 | 0.595 |
| go-v0.43 x rust-v0.56 (tcp, noise, yamux) | go-v0.43 | rust-v0.56 | tcp | noise | yamux | ✅ | 5s | 5.84 | 0.292 |
| go-v0.43 x rust-v0.56 (ws, tls, yamux) | go-v0.43 | rust-v0.56 | ws | tls | yamux | ✅ | 5s | 9.106 | 1.578 |
| go-v0.43 x rust-v0.56 (ws, noise, yamux) | go-v0.43 | rust-v0.56 | ws | noise | yamux | ✅ | 4s | 12.196 | 1.188 |
| go-v0.43 x rust-v0.56 (quic-v1) | go-v0.43 | rust-v0.56 | quic-v1 | - | - | ✅ | 5s | 6.281 | 0.289 |
| go-v0.43 x go-v0.38 (tcp, tls, yamux) | go-v0.43 | go-v0.38 | tcp | tls | yamux | ✅ | 4s | 12.554 | 0.467 |
| go-v0.43 x go-v0.38 (ws, tls, yamux) | go-v0.43 | go-v0.38 | ws | tls | yamux | ✅ | 4s | 19.548 | 0.826 |
| go-v0.43 x go-v0.38 (tcp, noise, yamux) | go-v0.43 | go-v0.38 | tcp | noise | yamux | ✅ | 5s | 7.184 | 0.253 |
| go-v0.43 x go-v0.38 (ws, noise, yamux) | go-v0.43 | go-v0.38 | ws | noise | yamux | ✅ | 5s | 7.73 | 0.332 |
| go-v0.43 x go-v0.38 (wss, tls, yamux) | go-v0.43 | go-v0.38 | wss | tls | yamux | ✅ | 5s | 17.52 | 0.353 |
| go-v0.43 x go-v0.38 (wss, noise, yamux) | go-v0.43 | go-v0.38 | wss | noise | yamux | ✅ | 4s | 21.092 | 1.691 |
| go-v0.43 x go-v0.38 (quic-v1) | go-v0.43 | go-v0.38 | quic-v1 | - | - | ✅ | 5s | 7.843 | 0.352 |
| go-v0.43 x go-v0.38 (webtransport) | go-v0.43 | go-v0.38 | webtransport | - | - | ✅ | 5s | 18.486 | 1.232 |
| go-v0.43 x rust-v0.56 (webrtc-direct) | go-v0.43 | rust-v0.56 | webrtc-direct | - | - | ❌ | 10s | - | - |
| go-v0.43 x go-v0.38 (webrtc-direct) | go-v0.43 | go-v0.38 | webrtc-direct | - | - | ✅ | 5s | 215.611 | 0.718 |
| go-v0.43 x go-v0.39 (tcp, tls, yamux) | go-v0.43 | go-v0.39 | tcp | tls | yamux | ✅ | 4s | 9.075 | 0.774 |
| go-v0.43 x go-v0.39 (tcp, noise, yamux) | go-v0.43 | go-v0.39 | tcp | noise | yamux | ✅ | 5s | 9.478 | 0.526 |
| go-v0.43 x go-v0.39 (ws, noise, yamux) | go-v0.43 | go-v0.39 | ws | noise | yamux | ✅ | 4s | 16.326 | 1.148 |
| go-v0.43 x go-v0.39 (ws, tls, yamux) | go-v0.43 | go-v0.39 | ws | tls | yamux | ✅ | 5s | 14.455 | 1.703 |
| go-v0.43 x go-v0.39 (wss, tls, yamux) | go-v0.43 | go-v0.39 | wss | tls | yamux | ✅ | 5s | 13.893 | 0.297 |
| go-v0.43 x go-v0.39 (quic-v1) | go-v0.43 | go-v0.39 | quic-v1 | - | - | ✅ | 4s | 10.442 | 0.465 |
| go-v0.43 x go-v0.39 (webtransport) | go-v0.43 | go-v0.39 | webtransport | - | - | ✅ | 4s | 20.565 | 1.006 |
| go-v0.43 x go-v0.39 (wss, noise, yamux) | go-v0.43 | go-v0.39 | wss | noise | yamux | ✅ | 6s | 15.531 | 0.662 |
| go-v0.43 x go-v0.39 (webrtc-direct) | go-v0.43 | go-v0.39 | webrtc-direct | - | - | ✅ | 5s | 211.139 | 0.31 |
| go-v0.43 x go-v0.40 (tcp, tls, yamux) | go-v0.43 | go-v0.40 | tcp | tls | yamux | ✅ | 6s | 6.297 | 0.553 |
| go-v0.43 x go-v0.40 (tcp, noise, yamux) | go-v0.43 | go-v0.40 | tcp | noise | yamux | ✅ | 4s | 14.023 | 0.668 |
| go-v0.43 x go-v0.40 (ws, tls, yamux) | go-v0.43 | go-v0.40 | ws | tls | yamux | ✅ | 5s | 9.385 | 0.418 |
| go-v0.43 x go-v0.40 (ws, noise, yamux) | go-v0.43 | go-v0.40 | ws | noise | yamux | ✅ | 5s | 10.463 | 0.427 |
| go-v0.43 x go-v0.40 (wss, noise, yamux) | go-v0.43 | go-v0.40 | wss | noise | yamux | ✅ | 5s | 25.051 | 0.296 |
| go-v0.43 x go-v0.40 (quic-v1) | go-v0.43 | go-v0.40 | quic-v1 | - | - | ✅ | 5s | 25.6 | 1.624 |
| go-v0.43 x go-v0.40 (wss, tls, yamux) | go-v0.43 | go-v0.40 | wss | tls | yamux | ✅ | 6s | 17.515 | 1.327 |
| go-v0.43 x go-v0.40 (webtransport) | go-v0.43 | go-v0.40 | webtransport | - | - | ✅ | 6s | 9.126 | 0.423 |
| go-v0.43 x go-v0.40 (webrtc-direct) | go-v0.43 | go-v0.40 | webrtc-direct | - | - | ✅ | 5s | 230.809 | 2.098 |
| go-v0.43 x go-v0.41 (tcp, tls, yamux) | go-v0.43 | go-v0.41 | tcp | tls | yamux | ✅ | 5s | 11.054 | 0.654 |
| go-v0.43 x go-v0.41 (tcp, noise, yamux) | go-v0.43 | go-v0.41 | tcp | noise | yamux | ✅ | 5s | 6.638 | 0.253 |
| go-v0.43 x go-v0.41 (ws, tls, yamux) | go-v0.43 | go-v0.41 | ws | tls | yamux | ✅ | 5s | 18.255 | 0.778 |
| go-v0.43 x go-v0.41 (ws, noise, yamux) | go-v0.43 | go-v0.41 | ws | noise | yamux | ✅ | 4s | 16.115 | 4.031 |
| go-v0.43 x go-v0.41 (wss, tls, yamux) | go-v0.43 | go-v0.41 | wss | tls | yamux | ✅ | 4s | 19.637 | 0.598 |
| go-v0.43 x go-v0.41 (wss, noise, yamux) | go-v0.43 | go-v0.41 | wss | noise | yamux | ✅ | 5s | 10.995 | 1.408 |
| go-v0.43 x go-v0.41 (quic-v1) | go-v0.43 | go-v0.41 | quic-v1 | - | - | ✅ | 5s | 12.498 | 1.563 |
| go-v0.43 x go-v0.41 (webtransport) | go-v0.43 | go-v0.41 | webtransport | - | - | ✅ | 5s | 15.076 | 0.591 |
| go-v0.43 x go-v0.42 (tcp, tls, yamux) | go-v0.43 | go-v0.42 | tcp | tls | yamux | ✅ | 4s | 6.999 | 0.263 |
| go-v0.43 x go-v0.41 (webrtc-direct) | go-v0.43 | go-v0.41 | webrtc-direct | - | - | ✅ | 5s | 213.098 | 0.509 |
| go-v0.43 x go-v0.42 (tcp, noise, yamux) | go-v0.43 | go-v0.42 | tcp | noise | yamux | ✅ | 5s | 8.255 | 0.607 |
| go-v0.43 x go-v0.42 (ws, tls, yamux) | go-v0.43 | go-v0.42 | ws | tls | yamux | ✅ | 5s | 13.409 | 1.32 |
| go-v0.43 x go-v0.42 (ws, noise, yamux) | go-v0.43 | go-v0.42 | ws | noise | yamux | ✅ | 4s | 9.817 | 0.805 |
| go-v0.43 x go-v0.42 (wss, tls, yamux) | go-v0.43 | go-v0.42 | wss | tls | yamux | ✅ | 5s | 20.878 | 0.522 |
| go-v0.43 x go-v0.42 (quic-v1) | go-v0.43 | go-v0.42 | quic-v1 | - | - | ✅ | 5s | 14.533 | 3.736 |
| go-v0.43 x go-v0.42 (wss, noise, yamux) | go-v0.43 | go-v0.42 | wss | noise | yamux | ✅ | 5s | 16.388 | 4.068 |
| go-v0.43 x go-v0.42 (webtransport) | go-v0.43 | go-v0.42 | webtransport | - | - | ✅ | 5s | 60.595 | 0.493 |
| go-v0.43 x go-v0.43 (tcp, tls, yamux) | go-v0.43 | go-v0.43 | tcp | tls | yamux | ✅ | 5s | 11.64 | 0.748 |
| go-v0.43 x go-v0.42 (webrtc-direct) | go-v0.43 | go-v0.42 | webrtc-direct | - | - | ✅ | 5s | 213.35 | 0.958 |
| go-v0.43 x go-v0.43 (tcp, noise, yamux) | go-v0.43 | go-v0.43 | tcp | noise | yamux | ✅ | 5s | 7.804 | 0.982 |
| go-v0.43 x go-v0.43 (ws, tls, yamux) | go-v0.43 | go-v0.43 | ws | tls | yamux | ✅ | 5s | 12.318 | 1.604 |
| go-v0.43 x go-v0.43 (ws, noise, yamux) | go-v0.43 | go-v0.43 | ws | noise | yamux | ✅ | 5s | 9.435 | 1.803 |
| go-v0.43 x go-v0.43 (wss, tls, yamux) | go-v0.43 | go-v0.43 | wss | tls | yamux | ✅ | 5s | 22.255 | 0.464 |
| go-v0.43 x go-v0.43 (wss, noise, yamux) | go-v0.43 | go-v0.43 | wss | noise | yamux | ✅ | 4s | 12.803 | 0.368 |
| go-v0.43 x go-v0.43 (quic-v1) | go-v0.43 | go-v0.43 | quic-v1 | - | - | ✅ | 5s | 10.154 | 0.401 |
| go-v0.43 x go-v0.43 (webtransport) | go-v0.43 | go-v0.43 | webtransport | - | - | ✅ | 5s | 22.26 | 1.013 |
| go-v0.43 x go-v0.43 (webrtc-direct) | go-v0.43 | go-v0.43 | webrtc-direct | - | - | ✅ | 4s | 20.254 | 0.757 |
| go-v0.43 x go-v0.44 (tcp, tls, yamux) | go-v0.43 | go-v0.44 | tcp | tls | yamux | ✅ | 4s | 11.478 | 1.309 |
| go-v0.43 x go-v0.44 (tcp, noise, yamux) | go-v0.43 | go-v0.44 | tcp | noise | yamux | ✅ | 5s | 7.247 | 1.085 |
| go-v0.43 x go-v0.44 (ws, tls, yamux) | go-v0.43 | go-v0.44 | ws | tls | yamux | ✅ | 5s | 13.276 | 0.355 |
| go-v0.43 x go-v0.44 (ws, noise, yamux) | go-v0.43 | go-v0.44 | ws | noise | yamux | ✅ | 4s | 15.223 | 0.641 |
| go-v0.43 x go-v0.44 (wss, tls, yamux) | go-v0.43 | go-v0.44 | wss | tls | yamux | ✅ | 5s | 13.962 | 0.72 |
| go-v0.43 x go-v0.44 (wss, noise, yamux) | go-v0.43 | go-v0.44 | wss | noise | yamux | ✅ | 5s | 10.921 | 0.524 |
| go-v0.43 x go-v0.44 (quic-v1) | go-v0.43 | go-v0.44 | quic-v1 | - | - | ✅ | 4s | 12.432 | 0.571 |
| go-v0.43 x go-v0.44 (webtransport) | go-v0.43 | go-v0.44 | webtransport | - | - | ✅ | 5s | 15.797 | 0.748 |
| go-v0.43 x go-v0.44 (webrtc-direct) | go-v0.43 | go-v0.44 | webrtc-direct | - | - | ✅ | 5s | 224.03 | 0.499 |
| go-v0.43 x go-v0.45 (tcp, tls, yamux) | go-v0.43 | go-v0.45 | tcp | tls | yamux | ✅ | 4s | 11.399 | 1.658 |
| go-v0.43 x go-v0.45 (tcp, noise, yamux) | go-v0.43 | go-v0.45 | tcp | noise | yamux | ✅ | 5s | 10.633 | 3.041 |
| go-v0.43 x go-v0.45 (ws, tls, yamux) | go-v0.43 | go-v0.45 | ws | tls | yamux | ✅ | 4s | 14.037 | 0.678 |
| go-v0.43 x go-v0.45 (ws, noise, yamux) | go-v0.43 | go-v0.45 | ws | noise | yamux | ✅ | 5s | 11.687 | 0.869 |
| go-v0.43 x go-v0.45 (wss, noise, yamux) | go-v0.43 | go-v0.45 | wss | noise | yamux | ✅ | 5s | 20.228 | 0.555 |
| go-v0.43 x go-v0.45 (wss, tls, yamux) | go-v0.43 | go-v0.45 | wss | tls | yamux | ✅ | 5s | 22.388 | 0.637 |
| go-v0.43 x go-v0.45 (quic-v1) | go-v0.43 | go-v0.45 | quic-v1 | - | - | ✅ | 5s | 20.937 | 2.119 |
| go-v0.43 x go-v0.45 (webtransport) | go-v0.43 | go-v0.45 | webtransport | - | - | ✅ | 5s | 27.977 | 1.401 |
| go-v0.43 x go-v0.45 (webrtc-direct) | go-v0.43 | go-v0.45 | webrtc-direct | - | - | ✅ | 5s | 218.128 | 1.104 |
| go-v0.43 x python-v0.4 (tcp, noise, yamux) | go-v0.43 | python-v0.4 | tcp | noise | yamux | ✅ | 5s | 20.28 | 2.853 |
| go-v0.43 x python-v0.4 (ws, noise, yamux) | go-v0.43 | python-v0.4 | ws | noise | yamux | ✅ | 5s | 39.355 | 10.086 |
| go-v0.43 x python-v0.4 (wss, noise, yamux) | go-v0.43 | python-v0.4 | wss | noise | yamux | ✅ | 5s | 29.87 | 5.121 |
| go-v0.43 x python-v0.4 (quic-v1) | go-v0.43 | python-v0.4 | quic-v1 | - | - | ✅ | 5s | 91.489 | 16.55 |
| go-v0.43 x nim-v1.14 (tcp, noise, yamux) | go-v0.43 | nim-v1.14 | tcp | noise | yamux | ✅ | 4s | 190.271 | 58.381 |
| go-v0.43 x nim-v1.14 (ws, noise, yamux) | go-v0.43 | nim-v1.14 | ws | noise | yamux | ✅ | 5s | 243.792 | 43.654 |
| go-v0.43 x js-v1.x (ws, noise, yamux) | go-v0.43 | js-v1.x | ws | noise | yamux | ✅ | 20s | 197.736 | 19.63 |
| go-v0.43 x js-v1.x (tcp, noise, yamux) | go-v0.43 | js-v1.x | tcp | noise | yamux | ✅ | 22s | 147.407 | 21.935 |
| go-v0.43 x js-v2.x (tcp, noise, yamux) | go-v0.43 | js-v2.x | tcp | noise | yamux | ✅ | 22s | 155.806 | 37.532 |
| go-v0.43 x js-v2.x (ws, noise, yamux) | go-v0.43 | js-v2.x | ws | noise | yamux | ✅ | 23s | 156.868 | 28.448 |
| go-v0.43 x jvm-v1.2 (tcp, noise, yamux) | go-v0.43 | jvm-v1.2 | tcp | noise | yamux | ✅ | 12s | 1190.857 | 21.661 |
| go-v0.43 x js-v3.x (tcp, noise, yamux) | go-v0.43 | js-v3.x | tcp | noise | yamux | ✅ | 21s | 169.871 | 24.046 |
| go-v0.43 x jvm-v1.2 (tcp, tls, yamux) | go-v0.43 | jvm-v1.2 | tcp | tls | yamux | ✅ | 14s | 3114.729 | 6.658 |
| go-v0.43 x js-v3.x (ws, noise, yamux) | go-v0.43 | js-v3.x | ws | noise | yamux | ✅ | 22s | 104.824 | 23.872 |
| go-v0.43 x c-v0.0.1 (quic-v1) | go-v0.43 | c-v0.0.1 | quic-v1 | - | - | ✅ | 5s | 27.3 | 1.484 |
| go-v0.43 x c-v0.0.1 (tcp, noise, yamux) | go-v0.43 | c-v0.0.1 | tcp | noise | yamux | ✅ | 7s | 121.514 | 52.52 |
| go-v0.43 x dotnet-v1.0 (tcp, noise, yamux) | go-v0.43 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 6s | 707.499 | 53.835 |
| go-v0.43 x zig-v0.0.1 (quic-v1) | go-v0.43 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 6s | - | - |
| go-v0.43 x jvm-v1.2 (ws, noise, yamux) | go-v0.43 | jvm-v1.2 | ws | noise | yamux | ✅ | 10s | 1637.922 | 70.116 |
| go-v0.43 x jvm-v1.2 (ws, tls, yamux) | go-v0.43 | jvm-v1.2 | ws | tls | yamux | ✅ | 11s | 4039.463 | 21.884 |
| go-v0.43 x eth-p2p-z-v0.0.1 (quic-v1) | go-v0.43 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 10.168 | 0.205 |
| go-v0.43 x jvm-v1.2 (quic-v1) | go-v0.43 | jvm-v1.2 | quic-v1 | - | - | ✅ | 12s | 613.945 | 11.045 |
| go-v0.44 x rust-v0.53 (tcp, tls, yamux) | go-v0.44 | rust-v0.53 | tcp | tls | yamux | ✅ | 4s | 140.475 | 43.461 |
| go-v0.44 x rust-v0.53 (tcp, noise, yamux) | go-v0.44 | rust-v0.53 | tcp | noise | yamux | ✅ | 4s | 46.33 | 0.297 |
| go-v0.44 x rust-v0.53 (ws, tls, yamux) | go-v0.44 | rust-v0.53 | ws | tls | yamux | ✅ | 5s | 178.437 | 42.413 |
| go-v0.44 x rust-v0.53 (ws, noise, yamux) | go-v0.44 | rust-v0.53 | ws | noise | yamux | ✅ | 6s | 292.876 | 47.369 |
| go-v0.44 x rust-v0.53 (quic-v1) | go-v0.44 | rust-v0.53 | quic-v1 | - | - | ✅ | 5s | 6.54 | 0.323 |
| go-v0.44 x rust-v0.54 (tcp, tls, yamux) | go-v0.44 | rust-v0.54 | tcp | tls | yamux | ✅ | 5s | 136.027 | 43.376 |
| go-v0.44 x rust-v0.53 (webrtc-direct) | go-v0.44 | rust-v0.53 | webrtc-direct | - | - | ✅ | 6s | 413.032 | 0.724 |
| go-v0.44 x rust-v0.54 (tcp, noise, yamux) | go-v0.44 | rust-v0.54 | tcp | noise | yamux | ✅ | 5s | 94.817 | 43.288 |
| go-v0.44 x rust-v0.54 (ws, tls, yamux) | go-v0.44 | rust-v0.54 | ws | tls | yamux | ✅ | 5s | 227.143 | 43.545 |
| go-v0.44 x rust-v0.54 (ws, noise, yamux) | go-v0.44 | rust-v0.54 | ws | noise | yamux | ✅ | 5s | 189.43 | 46.198 |
| go-v0.44 x rust-v0.54 (quic-v1) | go-v0.44 | rust-v0.54 | quic-v1 | - | - | ✅ | 4s | 6.828 | 0.265 |
| go-v0.44 x rust-v0.55 (tcp, tls, yamux) | go-v0.44 | rust-v0.55 | tcp | tls | yamux | ✅ | 4s | 7.607 | 1.108 |
| go-v0.44 x rust-v0.55 (tcp, noise, yamux) | go-v0.44 | rust-v0.55 | tcp | noise | yamux | ✅ | 5s | 11.385 | 4.525 |
| go-v0.44 x rust-v0.54 (webrtc-direct) | go-v0.44 | rust-v0.54 | webrtc-direct | - | - | ✅ | 6s | 411.187 | 0.304 |
| go-v0.44 x rust-v0.55 (ws, tls, yamux) | go-v0.44 | rust-v0.55 | ws | tls | yamux | ✅ | 4s | 12.11 | 0.477 |
| go-v0.44 x rust-v0.55 (quic-v1) | go-v0.44 | rust-v0.55 | quic-v1 | - | - | ✅ | 4s | 6.943 | 0.19 |
| go-v0.44 x rust-v0.55 (ws, noise, yamux) | go-v0.44 | rust-v0.55 | ws | noise | yamux | ✅ | 5s | 9.289 | 0.426 |
| go-v0.44 x rust-v0.56 (tcp, tls, yamux) | go-v0.44 | rust-v0.56 | tcp | tls | yamux | ✅ | 4s | 6.785 | 0.221 |
| go-v0.44 x rust-v0.55 (webrtc-direct) | go-v0.44 | rust-v0.55 | webrtc-direct | - | - | ✅ | 5s | 425.266 | 1.085 |
| go-v0.44 x rust-v0.56 (tcp, noise, yamux) | go-v0.44 | rust-v0.56 | tcp | noise | yamux | ✅ | 4s | 11.02 | 0.802 |
| go-v0.44 x rust-v0.56 (ws, tls, yamux) | go-v0.44 | rust-v0.56 | ws | tls | yamux | ✅ | 5s | 15.755 | 1.117 |
| go-v0.44 x rust-v0.56 (ws, noise, yamux) | go-v0.44 | rust-v0.56 | ws | noise | yamux | ✅ | 4s | 9.191 | 0.631 |
| go-v0.44 x rust-v0.56 (quic-v1) | go-v0.44 | rust-v0.56 | quic-v1 | - | - | ✅ | 5s | 5.011 | 0.311 |
| go-v0.44 x go-v0.38 (tcp, tls, yamux) | go-v0.44 | go-v0.38 | tcp | tls | yamux | ✅ | 5s | 12.167 | 2.724 |
| go-v0.44 x go-v0.38 (tcp, noise, yamux) | go-v0.44 | go-v0.38 | tcp | noise | yamux | ✅ | 4s | 12.796 | 0.347 |
| go-v0.44 x go-v0.38 (ws, tls, yamux) | go-v0.44 | go-v0.38 | ws | tls | yamux | ✅ | 5s | 13.518 | 3.611 |
| go-v0.44 x go-v0.38 (ws, noise, yamux) | go-v0.44 | go-v0.38 | ws | noise | yamux | ✅ | 4s | 7.385 | 0.58 |
| go-v0.44 x go-v0.38 (wss, tls, yamux) | go-v0.44 | go-v0.38 | wss | tls | yamux | ✅ | 5s | 9.882 | 0.532 |
| go-v0.44 x go-v0.38 (wss, noise, yamux) | go-v0.44 | go-v0.38 | wss | noise | yamux | ✅ | 4s | 15.218 | 0.347 |
| go-v0.44 x go-v0.38 (quic-v1) | go-v0.44 | go-v0.38 | quic-v1 | - | - | ✅ | 5s | 13.747 | 0.339 |
| go-v0.44 x go-v0.38 (webtransport) | go-v0.44 | go-v0.38 | webtransport | - | - | ✅ | 4s | 13.681 | 0.354 |
| go-v0.44 x rust-v0.56 (webrtc-direct) | go-v0.44 | rust-v0.56 | webrtc-direct | - | - | ❌ | 11s | - | - |
| go-v0.44 x go-v0.39 (tcp, tls, yamux) | go-v0.44 | go-v0.39 | tcp | tls | yamux | ✅ | 4s | 78.194 | 0.322 |
| go-v0.44 x go-v0.38 (webrtc-direct) | go-v0.44 | go-v0.38 | webrtc-direct | - | - | ✅ | 5s | 223.614 | 0.386 |
| go-v0.44 x go-v0.39 (tcp, noise, yamux) | go-v0.44 | go-v0.39 | tcp | noise | yamux | ✅ | 5s | 10.076 | 0.258 |
| go-v0.44 x go-v0.39 (ws, tls, yamux) | go-v0.44 | go-v0.39 | ws | tls | yamux | ✅ | 5s | 15.544 | 4.146 |
| go-v0.44 x go-v0.39 (ws, noise, yamux) | go-v0.44 | go-v0.39 | ws | noise | yamux | ✅ | 4s | 15.484 | 1.849 |
| go-v0.44 x go-v0.39 (wss, tls, yamux) | go-v0.44 | go-v0.39 | wss | tls | yamux | ✅ | 6s | 19.865 | 1.139 |
| go-v0.44 x go-v0.39 (wss, noise, yamux) | go-v0.44 | go-v0.39 | wss | noise | yamux | ✅ | 5s | 20.585 | 0.641 |
| go-v0.44 x go-v0.39 (quic-v1) | go-v0.44 | go-v0.39 | quic-v1 | - | - | ✅ | 5s | 10.79 | 0.499 |
| go-v0.44 x go-v0.39 (webtransport) | go-v0.44 | go-v0.39 | webtransport | - | - | ✅ | 5s | 14.085 | 0.45 |
| go-v0.44 x go-v0.39 (webrtc-direct) | go-v0.44 | go-v0.39 | webrtc-direct | - | - | ✅ | 5s | 210.334 | 0.317 |
| go-v0.44 x go-v0.40 (tcp, noise, yamux) | go-v0.44 | go-v0.40 | tcp | noise | yamux | ✅ | 4s | 15.855 | 0.546 |
| go-v0.44 x go-v0.40 (tcp, tls, yamux) | go-v0.44 | go-v0.40 | tcp | tls | yamux | ✅ | 5s | 9.423 | 0.82 |
| go-v0.44 x go-v0.40 (ws, tls, yamux) | go-v0.44 | go-v0.40 | ws | tls | yamux | ✅ | 5s | 8.121 | 1.325 |
| go-v0.44 x go-v0.40 (wss, tls, yamux) | go-v0.44 | go-v0.40 | wss | tls | yamux | ✅ | 4s | 22.064 | 2.963 |
| go-v0.44 x go-v0.40 (ws, noise, yamux) | go-v0.44 | go-v0.40 | ws | noise | yamux | ✅ | 5s | 25.425 | 3.286 |
| go-v0.44 x go-v0.40 (wss, noise, yamux) | go-v0.44 | go-v0.40 | wss | noise | yamux | ✅ | 5s | 16.503 | 0.595 |
| go-v0.44 x go-v0.40 (quic-v1) | go-v0.44 | go-v0.40 | quic-v1 | - | - | ✅ | 5s | 19.3 | 0.825 |
| go-v0.44 x go-v0.40 (webtransport) | go-v0.44 | go-v0.40 | webtransport | - | - | ✅ | 5s | 11.639 | 0.613 |
| go-v0.44 x go-v0.41 (tcp, tls, yamux) | go-v0.44 | go-v0.41 | tcp | tls | yamux | ✅ | 4s | 15.849 | 0.984 |
| go-v0.44 x go-v0.40 (webrtc-direct) | go-v0.44 | go-v0.40 | webrtc-direct | - | - | ✅ | 5s | 222.112 | 0.631 |
| go-v0.44 x go-v0.41 (tcp, noise, yamux) | go-v0.44 | go-v0.41 | tcp | noise | yamux | ✅ | 4s | 7.521 | 0.305 |
| go-v0.44 x go-v0.41 (ws, tls, yamux) | go-v0.44 | go-v0.41 | ws | tls | yamux | ✅ | 4s | 9.699 | 0.909 |
| go-v0.44 x go-v0.41 (ws, noise, yamux) | go-v0.44 | go-v0.41 | ws | noise | yamux | ✅ | 5s | 12.218 | 0.735 |
| go-v0.44 x go-v0.41 (wss, tls, yamux) | go-v0.44 | go-v0.41 | wss | tls | yamux | ✅ | 5s | 20.14 | 0.615 |
| go-v0.44 x go-v0.41 (quic-v1) | go-v0.44 | go-v0.41 | quic-v1 | - | - | ✅ | 5s | 14.953 | 1.069 |
| go-v0.44 x go-v0.41 (wss, noise, yamux) | go-v0.44 | go-v0.41 | wss | noise | yamux | ✅ | 5s | 13.244 | 0.269 |
| go-v0.44 x go-v0.41 (webtransport) | go-v0.44 | go-v0.41 | webtransport | - | - | ✅ | 5s | 11.397 | 0.526 |
| go-v0.44 x go-v0.41 (webrtc-direct) | go-v0.44 | go-v0.41 | webrtc-direct | - | - | ✅ | 4s | 223.473 | 2.176 |
| go-v0.44 x go-v0.42 (tcp, tls, yamux) | go-v0.44 | go-v0.42 | tcp | tls | yamux | ✅ | 5s | 12.771 | 1.124 |
| go-v0.44 x go-v0.42 (tcp, noise, yamux) | go-v0.44 | go-v0.42 | tcp | noise | yamux | ✅ | 5s | 73.391 | 0.959 |
| go-v0.44 x go-v0.42 (ws, tls, yamux) | go-v0.44 | go-v0.42 | ws | tls | yamux | ✅ | 5s | 16.624 | 1.231 |
| go-v0.44 x go-v0.42 (ws, noise, yamux) | go-v0.44 | go-v0.42 | ws | noise | yamux | ✅ | 5s | 14.506 | 1.516 |
| go-v0.44 x go-v0.42 (wss, tls, yamux) | go-v0.44 | go-v0.42 | wss | tls | yamux | ✅ | 5s | 20.385 | 1.09 |
| go-v0.44 x go-v0.42 (quic-v1) | go-v0.44 | go-v0.42 | quic-v1 | - | - | ✅ | 5s | 17.358 | 1.333 |
| go-v0.44 x go-v0.42 (webtransport) | go-v0.44 | go-v0.42 | webtransport | - | - | ✅ | 4s | 14.039 | 0.468 |
| go-v0.44 x go-v0.42 (wss, noise, yamux) | go-v0.44 | go-v0.42 | wss | noise | yamux | ✅ | 6s | 17.907 | 1.885 |
| go-v0.44 x go-v0.42 (webrtc-direct) | go-v0.44 | go-v0.42 | webrtc-direct | - | - | ✅ | 4s | 220.141 | 1.607 |
| go-v0.44 x go-v0.43 (tcp, tls, yamux) | go-v0.44 | go-v0.43 | tcp | tls | yamux | ✅ | 4s | 9.496 | 1.353 |
| go-v0.44 x go-v0.43 (tcp, noise, yamux) | go-v0.44 | go-v0.43 | tcp | noise | yamux | ✅ | 5s | 7.085 | 0.696 |
| go-v0.44 x go-v0.43 (ws, tls, yamux) | go-v0.44 | go-v0.43 | ws | tls | yamux | ✅ | 5s | 9.626 | 0.265 |
| go-v0.44 x go-v0.43 (ws, noise, yamux) | go-v0.44 | go-v0.43 | ws | noise | yamux | ✅ | 4s | 14.691 | 0.956 |
| go-v0.44 x go-v0.43 (wss, tls, yamux) | go-v0.44 | go-v0.43 | wss | tls | yamux | ✅ | 5s | 14.382 | 0.817 |
| go-v0.44 x go-v0.43 (quic-v1) | go-v0.44 | go-v0.43 | quic-v1 | - | - | ✅ | 5s | 13.365 | 0.958 |
| go-v0.44 x go-v0.43 (webtransport) | go-v0.44 | go-v0.43 | webtransport | - | - | ✅ | 4s | 17.172 | 0.793 |
| go-v0.44 x go-v0.43 (webrtc-direct) | go-v0.44 | go-v0.43 | webrtc-direct | - | - | ✅ | 4s | 223.387 | 0.877 |
| go-v0.44 x go-v0.43 (wss, noise, yamux) | go-v0.44 | go-v0.43 | wss | noise | yamux | ✅ | 7s | 16.953 | 1.101 |
| go-v0.44 x go-v0.44 (tcp, tls, yamux) | go-v0.44 | go-v0.44 | tcp | tls | yamux | ✅ | 4s | 13.276 | 0.431 |
| go-v0.44 x go-v0.44 (tcp, noise, yamux) | go-v0.44 | go-v0.44 | tcp | noise | yamux | ✅ | 5s | 19.671 | 1.028 |
| go-v0.44 x go-v0.44 (ws, tls, yamux) | go-v0.44 | go-v0.44 | ws | tls | yamux | ✅ | 5s | 9.666 | 1.065 |
| go-v0.44 x go-v0.44 (ws, noise, yamux) | go-v0.44 | go-v0.44 | ws | noise | yamux | ✅ | 4s | 20.47 | 3.789 |
| go-v0.44 x go-v0.44 (wss, noise, yamux) | go-v0.44 | go-v0.44 | wss | noise | yamux | ✅ | 6s | 17.703 | 0.437 |
| go-v0.44 x go-v0.44 (wss, tls, yamux) | go-v0.44 | go-v0.44 | wss | tls | yamux | ✅ | 7s | 57.317 | 0.585 |
| go-v0.44 x go-v0.44 (quic-v1) | go-v0.44 | go-v0.44 | quic-v1 | - | - | ✅ | 6s | 18.101 | 0.617 |
| go-v0.44 x go-v0.44 (webtransport) | go-v0.44 | go-v0.44 | webtransport | - | - | ✅ | 5s | 51.19 | 0.384 |
| go-v0.44 x go-v0.44 (webrtc-direct) | go-v0.44 | go-v0.44 | webrtc-direct | - | - | ✅ | 5s | 12.51 | 0.267 |
| go-v0.44 x go-v0.45 (tcp, noise, yamux) | go-v0.44 | go-v0.45 | tcp | noise | yamux | ✅ | 5s | 11.004 | 0.972 |
| go-v0.44 x go-v0.45 (tcp, tls, yamux) | go-v0.44 | go-v0.45 | tcp | tls | yamux | ✅ | 6s | 18.209 | 0.951 |
| go-v0.44 x go-v0.45 (ws, tls, yamux) | go-v0.44 | go-v0.45 | ws | tls | yamux | ✅ | 5s | 13.668 | 3.01 |
| go-v0.44 x go-v0.45 (ws, noise, yamux) | go-v0.44 | go-v0.45 | ws | noise | yamux | ✅ | 5s | 23.801 | 0.94 |
| go-v0.44 x go-v0.45 (wss, noise, yamux) | go-v0.44 | go-v0.45 | wss | noise | yamux | ✅ | 5s | 23.548 | 0.619 |
| go-v0.44 x go-v0.45 (quic-v1) | go-v0.44 | go-v0.45 | quic-v1 | - | - | ✅ | 5s | 13.569 | 1.406 |
| go-v0.44 x go-v0.45 (wss, tls, yamux) | go-v0.44 | go-v0.45 | wss | tls | yamux | ✅ | 6s | 8.525 | 0.175 |
| go-v0.44 x go-v0.45 (webtransport) | go-v0.44 | go-v0.45 | webtransport | - | - | ✅ | 5s | 13.233 | 0.43 |
| go-v0.44 x go-v0.45 (webrtc-direct) | go-v0.44 | go-v0.45 | webrtc-direct | - | - | ✅ | 5s | 21.488 | 2.036 |
| go-v0.44 x python-v0.4 (tcp, noise, yamux) | go-v0.44 | python-v0.4 | tcp | noise | yamux | ✅ | 6s | 27.599 | 5.461 |
| go-v0.44 x python-v0.4 (ws, noise, yamux) | go-v0.44 | python-v0.4 | ws | noise | yamux | ✅ | 6s | 32.478 | 6.327 |
| go-v0.44 x python-v0.4 (wss, noise, yamux) | go-v0.44 | python-v0.4 | wss | noise | yamux | ✅ | 4s | 31.144 | 3.776 |
| go-v0.44 x python-v0.4 (quic-v1) | go-v0.44 | python-v0.4 | quic-v1 | - | - | ✅ | 5s | 80.711 | 16.91 |
| go-v0.44 x nim-v1.14 (tcp, noise, yamux) | go-v0.44 | nim-v1.14 | tcp | noise | yamux | ✅ | 5s | 208.13 | 43.27 |
| go-v0.44 x nim-v1.14 (ws, noise, yamux) | go-v0.44 | nim-v1.14 | ws | noise | yamux | ✅ | 5s | 249.701 | 43.582 |
| go-v0.44 x js-v1.x (tcp, noise, yamux) | go-v0.44 | js-v1.x | tcp | noise | yamux | ✅ | 21s | 189.231 | 14.031 |
| go-v0.44 x js-v1.x (ws, noise, yamux) | go-v0.44 | js-v1.x | ws | noise | yamux | ✅ | 21s | 196.236 | 15.938 |
| go-v0.44 x js-v2.x (tcp, noise, yamux) | go-v0.44 | js-v2.x | tcp | noise | yamux | ✅ | 23s | 229.779 | 29.509 |
| go-v0.44 x jvm-v1.2 (tcp, noise, yamux) | go-v0.44 | jvm-v1.2 | tcp | noise | yamux | ✅ | 11s | 1242.383 | 22.067 |
| go-v0.44 x js-v2.x (ws, noise, yamux) | go-v0.44 | js-v2.x | ws | noise | yamux | ✅ | 23s | 188.348 | 34.637 |
| go-v0.44 x jvm-v1.2 (tcp, tls, yamux) | go-v0.44 | jvm-v1.2 | tcp | tls | yamux | ✅ | 14s | 3684.572 | 13.82 |
| go-v0.44 x js-v3.x (tcp, noise, yamux) | go-v0.44 | js-v3.x | tcp | noise | yamux | ✅ | 23s | 97.867 | 16.659 |
| go-v0.44 x js-v3.x (ws, noise, yamux) | go-v0.44 | js-v3.x | ws | noise | yamux | ✅ | 22s | 122.307 | 14.501 |
| go-v0.44 x c-v0.0.1 (tcp, noise, yamux) | go-v0.44 | c-v0.0.1 | tcp | noise | yamux | ✅ | 6s | 133.031 | 56.315 |
| go-v0.44 x c-v0.0.1 (quic-v1) | go-v0.44 | c-v0.0.1 | quic-v1 | - | - | ✅ | 7s | 70.969 | 32.387 |
| go-v0.44 x dotnet-v1.0 (tcp, noise, yamux) | go-v0.44 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 7s | 561.017 | 43.066 |
| go-v0.44 x zig-v0.0.1 (quic-v1) | go-v0.44 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 7s | - | - |
| go-v0.44 x jvm-v1.2 (ws, noise, yamux) | go-v0.44 | jvm-v1.2 | ws | noise | yamux | ✅ | 10s | 1743.774 | 28.812 |
| go-v0.44 x jvm-v1.2 (ws, tls, yamux) | go-v0.44 | jvm-v1.2 | ws | tls | yamux | ✅ | 12s | 3637.026 | 21.017 |
| go-v0.44 x eth-p2p-z-v0.0.1 (quic-v1) | go-v0.44 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 7s | 12.349 | 0.32 |
| go-v0.44 x jvm-v1.2 (quic-v1) | go-v0.44 | jvm-v1.2 | quic-v1 | - | - | ✅ | 11s | 531.397 | 8.255 |
| go-v0.45 x rust-v0.53 (tcp, tls, yamux) | go-v0.45 | rust-v0.53 | tcp | tls | yamux | ✅ | 4s | 92.663 | 42.91 |
| go-v0.45 x rust-v0.53 (tcp, noise, yamux) | go-v0.45 | rust-v0.53 | tcp | noise | yamux | ✅ | 4s | 89.593 | 42.976 |
| go-v0.45 x rust-v0.53 (ws, tls, yamux) | go-v0.45 | rust-v0.53 | ws | tls | yamux | ✅ | 5s | 231.504 | 43.607 |
| go-v0.45 x rust-v0.53 (ws, noise, yamux) | go-v0.45 | rust-v0.53 | ws | noise | yamux | ✅ | 6s | 226.066 | 47.554 |
| go-v0.45 x rust-v0.53 (quic-v1) | go-v0.45 | rust-v0.53 | quic-v1 | - | - | ✅ | 5s | 7.013 | 0.397 |
| go-v0.45 x rust-v0.54 (tcp, tls, yamux) | go-v0.45 | rust-v0.54 | tcp | tls | yamux | ✅ | 5s | 136.919 | 42.245 |
| go-v0.45 x rust-v0.53 (webrtc-direct) | go-v0.45 | rust-v0.53 | webrtc-direct | - | - | ✅ | 6s | 516.455 | 0.916 |
| go-v0.45 x rust-v0.54 (tcp, noise, yamux) | go-v0.45 | rust-v0.54 | tcp | noise | yamux | ✅ | 6s | 99.054 | 46.217 |
| go-v0.45 x rust-v0.54 (ws, tls, yamux) | go-v0.45 | rust-v0.54 | ws | tls | yamux | ✅ | 5s | 232.061 | 47.663 |
| go-v0.45 x rust-v0.54 (ws, noise, yamux) | go-v0.45 | rust-v0.54 | ws | noise | yamux | ✅ | 5s | 192.744 | 45.597 |
| go-v0.45 x rust-v0.54 (quic-v1) | go-v0.45 | rust-v0.54 | quic-v1 | - | - | ✅ | 4s | 13.106 | 0.851 |
| go-v0.45 x rust-v0.54 (webrtc-direct) | go-v0.45 | rust-v0.54 | webrtc-direct | - | - | ✅ | 5s | 414.223 | 0.431 |
| go-v0.45 x rust-v0.55 (tcp, tls, yamux) | go-v0.45 | rust-v0.55 | tcp | tls | yamux | ✅ | 4s | 11.971 | 0.511 |
| go-v0.45 x rust-v0.55 (ws, tls, yamux) | go-v0.45 | rust-v0.55 | ws | tls | yamux | ✅ | 4s | 9.817 | 0.915 |
| go-v0.45 x rust-v0.55 (tcp, noise, yamux) | go-v0.45 | rust-v0.55 | tcp | noise | yamux | ✅ | 6s | 9.948 | 0.856 |
| go-v0.45 x rust-v0.55 (ws, noise, yamux) | go-v0.45 | rust-v0.55 | ws | noise | yamux | ✅ | 5s | 11.641 | 0.357 |
| go-v0.45 x rust-v0.55 (quic-v1) | go-v0.45 | rust-v0.55 | quic-v1 | - | - | ✅ | 5s | 10.269 | 0.532 |
| go-v0.45 x rust-v0.56 (tcp, tls, yamux) | go-v0.45 | rust-v0.56 | tcp | tls | yamux | ✅ | 4s | 9.435 | 1.579 |
| go-v0.45 x rust-v0.55 (webrtc-direct) | go-v0.45 | rust-v0.55 | webrtc-direct | - | - | ✅ | 6s | 417.977 | 1.18 |
| go-v0.45 x rust-v0.56 (tcp, noise, yamux) | go-v0.45 | rust-v0.56 | tcp | noise | yamux | ✅ | 5s | 13.002 | 0.741 |
| go-v0.45 x rust-v0.56 (ws, tls, yamux) | go-v0.45 | rust-v0.56 | ws | tls | yamux | ✅ | 4s | 9.534 | 0.409 |
| go-v0.45 x rust-v0.56 (ws, noise, yamux) | go-v0.45 | rust-v0.56 | ws | noise | yamux | ✅ | 5s | 8.198 | 1.189 |
| go-v0.45 x rust-v0.56 (quic-v1) | go-v0.45 | rust-v0.56 | quic-v1 | - | - | ✅ | 4s | 15.874 | 2.357 |
| go-v0.45 x go-v0.38 (tcp, tls, yamux) | go-v0.45 | go-v0.38 | tcp | tls | yamux | ✅ | 5s | 16.069 | 1.084 |
| go-v0.45 x go-v0.38 (tcp, noise, yamux) | go-v0.45 | go-v0.38 | tcp | noise | yamux | ✅ | 5s | 6.038 | 0.306 |
| go-v0.45 x go-v0.38 (ws, noise, yamux) | go-v0.45 | go-v0.38 | ws | noise | yamux | ✅ | 4s | 7.53 | 0.836 |
| go-v0.45 x go-v0.38 (ws, tls, yamux) | go-v0.45 | go-v0.38 | ws | tls | yamux | ✅ | 5s | 6.831 | 0.249 |
| go-v0.45 x go-v0.38 (wss, tls, yamux) | go-v0.45 | go-v0.38 | wss | tls | yamux | ✅ | 4s | 15.161 | 0.275 |
| go-v0.45 x go-v0.38 (wss, noise, yamux) | go-v0.45 | go-v0.38 | wss | noise | yamux | ✅ | 5s | 24.427 | 0.539 |
| go-v0.45 x go-v0.38 (quic-v1) | go-v0.45 | go-v0.38 | quic-v1 | - | - | ✅ | 5s | 10.126 | 0.847 |
| go-v0.45 x go-v0.38 (webtransport) | go-v0.45 | go-v0.38 | webtransport | - | - | ✅ | 4s | 17.148 | 0.478 |
| go-v0.45 x rust-v0.56 (webrtc-direct) | go-v0.45 | rust-v0.56 | webrtc-direct | - | - | ❌ | 10s | - | - |
| go-v0.45 x go-v0.38 (webrtc-direct) | go-v0.45 | go-v0.38 | webrtc-direct | - | - | ✅ | 5s | 220.833 | 0.499 |
| go-v0.45 x go-v0.39 (tcp, tls, yamux) | go-v0.45 | go-v0.39 | tcp | tls | yamux | ✅ | 4s | 8.265 | 0.327 |
| go-v0.45 x go-v0.39 (tcp, noise, yamux) | go-v0.45 | go-v0.39 | tcp | noise | yamux | ✅ | 5s | 7.213 | 0.519 |
| go-v0.45 x go-v0.39 (ws, tls, yamux) | go-v0.45 | go-v0.39 | ws | tls | yamux | ✅ | 4s | 8.49 | 0.427 |
| go-v0.45 x go-v0.39 (ws, noise, yamux) | go-v0.45 | go-v0.39 | ws | noise | yamux | ✅ | 5s | 27.567 | 5.723 |
| go-v0.45 x go-v0.39 (wss, tls, yamux) | go-v0.45 | go-v0.39 | wss | tls | yamux | ✅ | 4s | 52.087 | 0.579 |
| go-v0.45 x go-v0.39 (quic-v1) | go-v0.45 | go-v0.39 | quic-v1 | - | - | ✅ | 5s | 9.267 | 0.316 |
| go-v0.45 x go-v0.39 (wss, noise, yamux) | go-v0.45 | go-v0.39 | wss | noise | yamux | ✅ | 6s | 9.27 | 0.227 |
| go-v0.45 x go-v0.39 (webtransport) | go-v0.45 | go-v0.39 | webtransport | - | - | ✅ | 5s | 17.236 | 2.136 |
| go-v0.45 x go-v0.39 (webrtc-direct) | go-v0.45 | go-v0.39 | webrtc-direct | - | - | ✅ | 5s | 215.979 | 0.552 |
| go-v0.45 x go-v0.40 (tcp, tls, yamux) | go-v0.45 | go-v0.40 | tcp | tls | yamux | ✅ | 4s | 11.574 | 0.319 |
| go-v0.45 x go-v0.40 (tcp, noise, yamux) | go-v0.45 | go-v0.40 | tcp | noise | yamux | ✅ | 5s | 10.355 | 0.247 |
| go-v0.45 x go-v0.40 (ws, noise, yamux) | go-v0.45 | go-v0.40 | ws | noise | yamux | ✅ | 4s | 18.029 | 1.049 |
| go-v0.45 x go-v0.40 (ws, tls, yamux) | go-v0.45 | go-v0.40 | ws | tls | yamux | ✅ | 6s | 19.566 | 1.827 |
| go-v0.45 x go-v0.40 (wss, noise, yamux) | go-v0.45 | go-v0.40 | wss | noise | yamux | ✅ | 5s | 10.699 | 0.252 |
| go-v0.45 x go-v0.40 (quic-v1) | go-v0.45 | go-v0.40 | quic-v1 | - | - | ✅ | 4s | 11.165 | 0.512 |
| go-v0.45 x go-v0.40 (wss, tls, yamux) | go-v0.45 | go-v0.40 | wss | tls | yamux | ✅ | 6s | 26.055 | 0.98 |
| go-v0.45 x go-v0.40 (webtransport) | go-v0.45 | go-v0.40 | webtransport | - | - | ✅ | 6s | 15.98 | 0.496 |
| go-v0.45 x go-v0.40 (webrtc-direct) | go-v0.45 | go-v0.40 | webrtc-direct | - | - | ✅ | 5s | 223.271 | 1.175 |
| go-v0.45 x go-v0.41 (tcp, tls, yamux) | go-v0.45 | go-v0.41 | tcp | tls | yamux | ✅ | 5s | 7.603 | 1.579 |
| go-v0.45 x go-v0.41 (tcp, noise, yamux) | go-v0.45 | go-v0.41 | tcp | noise | yamux | ✅ | 4s | 12.865 | 3.186 |
| go-v0.45 x go-v0.41 (ws, tls, yamux) | go-v0.45 | go-v0.41 | ws | tls | yamux | ✅ | 5s | 10.679 | 1.399 |
| go-v0.45 x go-v0.41 (ws, noise, yamux) | go-v0.45 | go-v0.41 | ws | noise | yamux | ✅ | 5s | 8.046 | 0.427 |
| go-v0.45 x go-v0.41 (wss, tls, yamux) | go-v0.45 | go-v0.41 | wss | tls | yamux | ✅ | 5s | 24.511 | 0.446 |
| go-v0.45 x go-v0.41 (quic-v1) | go-v0.45 | go-v0.41 | quic-v1 | - | - | ✅ | 5s | 57.752 | 1.032 |
| go-v0.45 x go-v0.41 (wss, noise, yamux) | go-v0.45 | go-v0.41 | wss | noise | yamux | ✅ | 6s | 24.672 | 1.218 |
| go-v0.45 x go-v0.41 (webtransport) | go-v0.45 | go-v0.41 | webtransport | - | - | ✅ | 5s | 18.046 | 1.026 |
| go-v0.45 x go-v0.41 (webrtc-direct) | go-v0.45 | go-v0.41 | webrtc-direct | - | - | ✅ | 5s | 215.849 | 0.521 |
| go-v0.45 x go-v0.42 (tcp, tls, yamux) | go-v0.45 | go-v0.42 | tcp | tls | yamux | ✅ | 5s | 16.612 | 4.053 |
| go-v0.45 x go-v0.42 (tcp, noise, yamux) | go-v0.45 | go-v0.42 | tcp | noise | yamux | ✅ | 5s | 6.263 | 0.316 |
| go-v0.45 x go-v0.42 (ws, tls, yamux) | go-v0.45 | go-v0.42 | ws | tls | yamux | ✅ | 4s | 9.283 | 0.392 |
| go-v0.45 x go-v0.42 (ws, noise, yamux) | go-v0.45 | go-v0.42 | ws | noise | yamux | ✅ | 4s | 7.997 | 0.28 |
| go-v0.45 x go-v0.42 (quic-v1) | go-v0.45 | go-v0.42 | quic-v1 | - | - | ✅ | 5s | 16.146 | 1.178 |
| go-v0.45 x go-v0.42 (wss, tls, yamux) | go-v0.45 | go-v0.42 | wss | tls | yamux | ✅ | 7s | 29.07 | 0.634 |
| go-v0.45 x go-v0.42 (wss, noise, yamux) | go-v0.45 | go-v0.42 | wss | noise | yamux | ✅ | 6s | 19.623 | 1.42 |
| go-v0.45 x go-v0.42 (webtransport) | go-v0.45 | go-v0.42 | webtransport | - | - | ✅ | 5s | 16.986 | 1.128 |
| go-v0.45 x go-v0.43 (tcp, tls, yamux) | go-v0.45 | go-v0.43 | tcp | tls | yamux | ✅ | 5s | 6.307 | 0.814 |
| go-v0.45 x go-v0.42 (webrtc-direct) | go-v0.45 | go-v0.42 | webrtc-direct | - | - | ✅ | 6s | 212.953 | 0.606 |
| go-v0.45 x go-v0.43 (tcp, noise, yamux) | go-v0.45 | go-v0.43 | tcp | noise | yamux | ✅ | 5s | 16.84 | 0.837 |
| go-v0.45 x go-v0.43 (ws, tls, yamux) | go-v0.45 | go-v0.43 | ws | tls | yamux | ✅ | 5s | 10.246 | 0.385 |
| go-v0.45 x go-v0.43 (ws, noise, yamux) | go-v0.45 | go-v0.43 | ws | noise | yamux | ✅ | 4s | 9.939 | 2.284 |
| go-v0.45 x go-v0.43 (quic-v1) | go-v0.45 | go-v0.43 | quic-v1 | - | - | ✅ | 4s | 22.866 | 1.585 |
| go-v0.45 x go-v0.43 (wss, tls, yamux) | go-v0.45 | go-v0.43 | wss | tls | yamux | ✅ | 6s | 16.875 | 0.529 |
| go-v0.45 x go-v0.43 (wss, noise, yamux) | go-v0.45 | go-v0.43 | wss | noise | yamux | ✅ | 5s | 11.406 | 0.408 |
| go-v0.45 x go-v0.43 (webtransport) | go-v0.45 | go-v0.43 | webtransport | - | - | ✅ | 5s | 16.666 | 0.429 |
| go-v0.45 x go-v0.43 (webrtc-direct) | go-v0.45 | go-v0.43 | webrtc-direct | - | - | ✅ | 5s | 424.607 | 0.756 |
| go-v0.45 x go-v0.44 (tcp, tls, yamux) | go-v0.45 | go-v0.44 | tcp | tls | yamux | ✅ | 5s | 10.362 | 1.374 |
| go-v0.45 x go-v0.44 (tcp, noise, yamux) | go-v0.45 | go-v0.44 | tcp | noise | yamux | ✅ | 4s | 11.894 | 1.502 |
| go-v0.45 x go-v0.44 (ws, tls, yamux) | go-v0.45 | go-v0.44 | ws | tls | yamux | ✅ | 4s | 11.367 | 0.456 |
| go-v0.45 x go-v0.44 (ws, noise, yamux) | go-v0.45 | go-v0.44 | ws | noise | yamux | ✅ | 4s | 22.722 | 1.064 |
| go-v0.45 x go-v0.44 (wss, tls, yamux) | go-v0.45 | go-v0.44 | wss | tls | yamux | ✅ | 5s | 32.806 | 2.082 |
| go-v0.45 x go-v0.44 (wss, noise, yamux) | go-v0.45 | go-v0.44 | wss | noise | yamux | ✅ | 4s | 22.925 | 4.302 |
| go-v0.45 x go-v0.44 (quic-v1) | go-v0.45 | go-v0.44 | quic-v1 | - | - | ✅ | 5s | 10.264 | 0.481 |
| go-v0.45 x go-v0.44 (webtransport) | go-v0.45 | go-v0.44 | webtransport | - | - | ✅ | 4s | 16.273 | 0.31 |
| go-v0.45 x go-v0.44 (webrtc-direct) | go-v0.45 | go-v0.44 | webrtc-direct | - | - | ✅ | 4s | 218.085 | 0.316 |
| go-v0.45 x go-v0.45 (tcp, tls, yamux) | go-v0.45 | go-v0.45 | tcp | tls | yamux | ✅ | 4s | 15.436 | 2.396 |
| go-v0.45 x go-v0.45 (tcp, noise, yamux) | go-v0.45 | go-v0.45 | tcp | noise | yamux | ✅ | 5s | 8.359 | 0.281 |
| go-v0.45 x go-v0.45 (ws, tls, yamux) | go-v0.45 | go-v0.45 | ws | tls | yamux | ✅ | 4s | 9.74 | 1.833 |
| go-v0.45 x go-v0.45 (ws, noise, yamux) | go-v0.45 | go-v0.45 | ws | noise | yamux | ✅ | 5s | 17.982 | 2.256 |
| go-v0.45 x go-v0.45 (wss, tls, yamux) | go-v0.45 | go-v0.45 | wss | tls | yamux | ✅ | 6s | 16.796 | 0.518 |
| go-v0.45 x go-v0.45 (quic-v1) | go-v0.45 | go-v0.45 | quic-v1 | - | - | ✅ | 5s | 17.696 | 1.591 |
| go-v0.45 x go-v0.45 (wss, noise, yamux) | go-v0.45 | go-v0.45 | wss | noise | yamux | ✅ | 7s | 11.02 | 0.342 |
| go-v0.45 x go-v0.45 (webtransport) | go-v0.45 | go-v0.45 | webtransport | - | - | ✅ | 5s | 7.485 | 0.216 |
| go-v0.45 x go-v0.45 (webrtc-direct) | go-v0.45 | go-v0.45 | webrtc-direct | - | - | ✅ | 5s | 230.337 | 1.202 |
| go-v0.45 x python-v0.4 (tcp, noise, yamux) | go-v0.45 | python-v0.4 | tcp | noise | yamux | ✅ | 5s | 16.775 | 2.017 |
| go-v0.45 x python-v0.4 (ws, noise, yamux) | go-v0.45 | python-v0.4 | ws | noise | yamux | ✅ | 6s | 44.013 | 6.281 |
| go-v0.45 x python-v0.4 (wss, noise, yamux) | go-v0.45 | python-v0.4 | wss | noise | yamux | ✅ | 6s | 49.052 | 6.798 |
| go-v0.45 x python-v0.4 (quic-v1) | go-v0.45 | python-v0.4 | quic-v1 | - | - | ✅ | 6s | 90.728 | 18.218 |
| go-v0.45 x nim-v1.14 (tcp, noise, yamux) | go-v0.45 | nim-v1.14 | tcp | noise | yamux | ✅ | 5s | 209.118 | 42.094 |
| go-v0.45 x nim-v1.14 (ws, noise, yamux) | go-v0.45 | nim-v1.14 | ws | noise | yamux | ✅ | 5s | 267.419 | 43.576 |
| go-v0.45 x js-v1.x (tcp, noise, yamux) | go-v0.45 | js-v1.x | tcp | noise | yamux | ✅ | 19s | 195.404 | 24.463 |
| go-v0.45 x js-v1.x (ws, noise, yamux) | go-v0.45 | js-v1.x | ws | noise | yamux | ✅ | 21s | 173.257 | 18.427 |
| go-v0.45 x js-v2.x (tcp, noise, yamux) | go-v0.45 | js-v2.x | tcp | noise | yamux | ✅ | 22s | 199.346 | 21.958 |
| go-v0.45 x jvm-v1.2 (tcp, noise, yamux) | go-v0.45 | jvm-v1.2 | tcp | noise | yamux | ✅ | 10s | 1206.642 | 28.981 |
| go-v0.45 x js-v3.x (tcp, noise, yamux) | go-v0.45 | js-v3.x | tcp | noise | yamux | ✅ | 22s | 138.272 | 19.291 |
| go-v0.45 x js-v2.x (ws, noise, yamux) | go-v0.45 | js-v2.x | ws | noise | yamux | ✅ | 23s | 175.642 | 31.239 |
| go-v0.45 x jvm-v1.2 (tcp, tls, yamux) | go-v0.45 | jvm-v1.2 | tcp | tls | yamux | ✅ | 14s | 3753.351 | 21.773 |
| go-v0.45 x js-v3.x (ws, noise, yamux) | go-v0.45 | js-v3.x | ws | noise | yamux | ✅ | 22s | 173.424 | 26.553 |
| go-v0.45 x c-v0.0.1 (tcp, noise, yamux) | go-v0.45 | c-v0.0.1 | tcp | noise | yamux | ✅ | 6s | 135.329 | 54.323 |
| go-v0.45 x c-v0.0.1 (quic-v1) | go-v0.45 | c-v0.0.1 | quic-v1 | - | - | ✅ | 5s | 40.448 | 3.362 |
| go-v0.45 x jvm-v1.2 (ws, tls, yamux) | go-v0.45 | jvm-v1.2 | ws | tls | yamux | ✅ | 11s | 3347.365 | 23.532 |
| go-v0.45 x jvm-v1.2 (ws, noise, yamux) | go-v0.45 | jvm-v1.2 | ws | noise | yamux | ✅ | 10s | 1135.643 | 16.828 |
| go-v0.45 x dotnet-v1.0 (tcp, noise, yamux) | go-v0.45 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 6s | 407.029 | 42.054 |
| go-v0.45 x zig-v0.0.1 (quic-v1) | go-v0.45 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 5s | - | - |
| go-v0.45 x eth-p2p-z-v0.0.1 (quic-v1) | go-v0.45 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 6s | 12.58 | 0.865 |
| go-v0.45 x jvm-v1.2 (quic-v1) | go-v0.45 | jvm-v1.2 | quic-v1 | - | - | ✅ | 11s | 718.459 | 15.475 |
| python-v0.4 x rust-v0.53 (tcp, noise, mplex) | python-v0.4 | rust-v0.53 | tcp | noise | mplex | ✅ | 5s | - | - |
| python-v0.4 x rust-v0.53 (tcp, noise, yamux) | python-v0.4 | rust-v0.53 | tcp | noise | yamux | ✅ | 6s | - | - |
| python-v0.4 x rust-v0.53 (quic-v1) | python-v0.4 | rust-v0.53 | quic-v1 | - | - | ✅ | 5s | - | - |
| python-v0.4 x rust-v0.54 (tcp, noise, mplex) | python-v0.4 | rust-v0.54 | tcp | noise | mplex | ✅ | 5s | - | - |
| python-v0.4 x rust-v0.54 (tcp, noise, yamux) | python-v0.4 | rust-v0.54 | tcp | noise | yamux | ✅ | 5s | - | - |
| python-v0.4 x rust-v0.54 (quic-v1) | python-v0.4 | rust-v0.54 | quic-v1 | - | - | ✅ | 3s | - | - |
| python-v0.4 x rust-v0.55 (tcp, noise, mplex) | python-v0.4 | rust-v0.55 | tcp | noise | mplex | ✅ | 5s | - | - |
| python-v0.4 x rust-v0.55 (tcp, noise, yamux) | python-v0.4 | rust-v0.55 | tcp | noise | yamux | ✅ | 4s | - | - |
| python-v0.4 x rust-v0.53 (ws, noise, yamux) | python-v0.4 | rust-v0.53 | ws | noise | yamux | ✅ | 11s | - | - |
| python-v0.4 x rust-v0.53 (ws, noise, mplex) | python-v0.4 | rust-v0.53 | ws | noise | mplex | ✅ | 12s | - | - |
| python-v0.4 x rust-v0.54 (ws, noise, mplex) | python-v0.4 | rust-v0.54 | ws | noise | mplex | ✅ | 10s | - | - |
| python-v0.4 x rust-v0.54 (ws, noise, yamux) | python-v0.4 | rust-v0.54 | ws | noise | yamux | ✅ | 9s | - | - |
| python-v0.4 x rust-v0.55 (quic-v1) | python-v0.4 | rust-v0.55 | quic-v1 | - | - | ✅ | 5s | - | - |
| python-v0.4 x rust-v0.56 (tcp, noise, mplex) | python-v0.4 | rust-v0.56 | tcp | noise | mplex | ✅ | 4s | - | - |
| python-v0.4 x rust-v0.56 (tcp, noise, yamux) | python-v0.4 | rust-v0.56 | tcp | noise | yamux | ✅ | 5s | - | - |
| python-v0.4 x rust-v0.56 (quic-v1) | python-v0.4 | rust-v0.56 | quic-v1 | - | - | ✅ | 5s | - | - |
| python-v0.4 x go-v0.38 (tcp, noise, yamux) | python-v0.4 | go-v0.38 | tcp | noise | yamux | ✅ | 4s | - | - |
| python-v0.4 x rust-v0.55 (ws, noise, mplex) | python-v0.4 | rust-v0.55 | ws | noise | mplex | ✅ | 14s | - | - |
| python-v0.4 x go-v0.38 (quic-v1) | python-v0.4 | go-v0.38 | quic-v1 | - | - | ✅ | 4s | - | - |
| python-v0.4 x go-v0.39 (tcp, noise, yamux) | python-v0.4 | go-v0.39 | tcp | noise | yamux | ✅ | 4s | - | - |
| python-v0.4 x rust-v0.55 (ws, noise, yamux) | python-v0.4 | rust-v0.55 | ws | noise | yamux | ✅ | 14s | - | - |
| python-v0.4 x rust-v0.56 (ws, noise, mplex) | python-v0.4 | rust-v0.56 | ws | noise | mplex | ✅ | 15s | - | - |
| python-v0.4 x rust-v0.56 (ws, noise, yamux) | python-v0.4 | rust-v0.56 | ws | noise | yamux | ✅ | 14s | - | - |
| python-v0.4 x go-v0.39 (quic-v1) | python-v0.4 | go-v0.39 | quic-v1 | - | - | ✅ | 4s | - | - |
| python-v0.4 x go-v0.40 (tcp, noise, yamux) | python-v0.4 | go-v0.40 | tcp | noise | yamux | ✅ | 3s | - | - |
| python-v0.4 x go-v0.40 (quic-v1) | python-v0.4 | go-v0.40 | quic-v1 | - | - | ✅ | 4s | - | - |
| python-v0.4 x go-v0.41 (tcp, noise, yamux) | python-v0.4 | go-v0.41 | tcp | noise | yamux | ✅ | 3s | - | - |
| python-v0.4 x go-v0.38 (ws, noise, yamux) | python-v0.4 | go-v0.38 | ws | noise | yamux | ✅ | 43s | - | - |
| python-v0.4 x go-v0.38 (wss, noise, yamux) | python-v0.4 | go-v0.38 | wss | noise | yamux | ✅ | 43s | - | - |
| python-v0.4 x go-v0.41 (quic-v1) | python-v0.4 | go-v0.41 | quic-v1 | - | - | ✅ | 3s | - | - |
| python-v0.4 x go-v0.42 (tcp, noise, yamux) | python-v0.4 | go-v0.42 | tcp | noise | yamux | ✅ | 3s | - | - |
| python-v0.4 x go-v0.39 (ws, noise, yamux) | python-v0.4 | go-v0.39 | ws | noise | yamux | ✅ | 43s | - | - |
| python-v0.4 x go-v0.39 (wss, noise, yamux) | python-v0.4 | go-v0.39 | wss | noise | yamux | ✅ | 43s | - | - |
| python-v0.4 x go-v0.42 (quic-v1) | python-v0.4 | go-v0.42 | quic-v1 | - | - | ✅ | 3s | - | - |
| python-v0.4 x go-v0.43 (tcp, noise, yamux) | python-v0.4 | go-v0.43 | tcp | noise | yamux | ✅ | 3s | - | - |
| python-v0.4 x go-v0.40 (ws, noise, yamux) | python-v0.4 | go-v0.40 | ws | noise | yamux | ✅ | 44s | - | - |
| python-v0.4 x go-v0.40 (wss, noise, yamux) | python-v0.4 | go-v0.40 | wss | noise | yamux | ✅ | 43s | - | - |
| python-v0.4 x go-v0.43 (quic-v1) | python-v0.4 | go-v0.43 | quic-v1 | - | - | ✅ | 3s | - | - |
| python-v0.4 x go-v0.44 (tcp, noise, yamux) | python-v0.4 | go-v0.44 | tcp | noise | yamux | ✅ | 3s | - | - |
| python-v0.4 x go-v0.41 (ws, noise, yamux) | python-v0.4 | go-v0.41 | ws | noise | yamux | ✅ | 44s | - | - |
| python-v0.4 x go-v0.41 (wss, noise, yamux) | python-v0.4 | go-v0.41 | wss | noise | yamux | ✅ | 43s | - | - |
| python-v0.4 x go-v0.44 (quic-v1) | python-v0.4 | go-v0.44 | quic-v1 | - | - | ✅ | 3s | - | - |
| python-v0.4 x go-v0.45 (tcp, noise, yamux) | python-v0.4 | go-v0.45 | tcp | noise | yamux | ✅ | 3s | - | - |
| python-v0.4 x go-v0.42 (ws, noise, yamux) | python-v0.4 | go-v0.42 | ws | noise | yamux | ✅ | 42s | - | - |
| python-v0.4 x go-v0.42 (wss, noise, yamux) | python-v0.4 | go-v0.42 | wss | noise | yamux | ✅ | 43s | - | - |
| python-v0.4 x go-v0.45 (quic-v1) | python-v0.4 | go-v0.45 | quic-v1 | - | - | ✅ | 3s | - | - |
| python-v0.4 x python-v0.4 (tcp, noise, mplex) | python-v0.4 | python-v0.4 | tcp | noise | mplex | ✅ | 3s | - | - |
| python-v0.4 x go-v0.43 (ws, noise, yamux) | python-v0.4 | go-v0.43 | ws | noise | yamux | ✅ | 44s | - | - |
| python-v0.4 x python-v0.4 (tcp, noise, yamux) | python-v0.4 | python-v0.4 | tcp | noise | yamux | ✅ | 3s | - | - |
| python-v0.4 x python-v0.4 (ws, noise, mplex) | python-v0.4 | python-v0.4 | ws | noise | mplex | ✅ | 3s | - | - |
| python-v0.4 x go-v0.43 (wss, noise, yamux) | python-v0.4 | go-v0.43 | wss | noise | yamux | ✅ | 43s | - | - |
| python-v0.4 x python-v0.4 (ws, noise, yamux) | python-v0.4 | python-v0.4 | ws | noise | yamux | ✅ | 4s | - | - |
| python-v0.4 x python-v0.4 (wss, noise, yamux) | python-v0.4 | python-v0.4 | wss | noise | yamux | ✅ | 4s | - | - |
| python-v0.4 x python-v0.4 (quic-v1) | python-v0.4 | python-v0.4 | quic-v1 | - | - | ✅ | 4s | - | - |
| python-v0.4 x python-v0.4 (wss, noise, mplex) | python-v0.4 | python-v0.4 | wss | noise | mplex | ✅ | 5s | - | - |
| python-v0.4 x go-v0.44 (ws, noise, yamux) | python-v0.4 | go-v0.44 | ws | noise | yamux | ✅ | 44s | - | - |
| python-v0.4 x go-v0.44 (wss, noise, yamux) | python-v0.4 | go-v0.44 | wss | noise | yamux | ✅ | 43s | - | - |
| python-v0.4 x go-v0.45 (ws, noise, yamux) | python-v0.4 | go-v0.45 | ws | noise | yamux | ✅ | 44s | - | - |
| python-v0.4 x go-v0.45 (wss, noise, yamux) | python-v0.4 | go-v0.45 | wss | noise | yamux | ✅ | 44s | - | - |
| python-v0.4 x js-v1.x (tcp, noise, mplex) | python-v0.4 | js-v1.x | tcp | noise | mplex | ✅ | 17s | - | - |
| python-v0.4 x js-v1.x (tcp, noise, yamux) | python-v0.4 | js-v1.x | tcp | noise | yamux | ✅ | 17s | - | - |
| python-v0.4 x js-v2.x (tcp, noise, mplex) | python-v0.4 | js-v2.x | tcp | noise | mplex | ✅ | 19s | - | - |
| python-v0.4 x js-v2.x (tcp, noise, yamux) | python-v0.4 | js-v2.x | tcp | noise | yamux | ✅ | 18s | - | - |
| python-v0.4 x js-v1.x (ws, noise, mplex) | python-v0.4 | js-v1.x | ws | noise | mplex | ✅ | 28s | - | - |
| python-v0.4 x js-v3.x (tcp, noise, mplex) | python-v0.4 | js-v3.x | tcp | noise | mplex | ✅ | 13s | - | - |
| python-v0.4 x js-v1.x (ws, noise, yamux) | python-v0.4 | js-v1.x | ws | noise | yamux | ✅ | 29s | - | - |
| python-v0.4 x js-v3.x (tcp, noise, yamux) | python-v0.4 | js-v3.x | tcp | noise | yamux | ✅ | 13s | - | - |
| python-v0.4 x nim-v1.14 (tcp, noise, mplex) | python-v0.4 | nim-v1.14 | tcp | noise | mplex | ✅ | 4s | - | - |
| python-v0.4 x nim-v1.14 (tcp, noise, yamux) | python-v0.4 | nim-v1.14 | tcp | noise | yamux | ✅ | 3s | - | - |
| python-v0.4 x jvm-v1.2 (tcp, noise, mplex) | python-v0.4 | jvm-v1.2 | tcp | noise | mplex | ✅ | 5s | - | - |
| python-v0.4 x jvm-v1.2 (tcp, noise, yamux) | python-v0.4 | jvm-v1.2 | tcp | noise | yamux | ✅ | 4s | - | - |
| python-v0.4 x js-v2.x (ws, noise, mplex) | python-v0.4 | js-v2.x | ws | noise | mplex | ✅ | 195s | - | - |
| python-v0.4 x js-v2.x (ws, noise, yamux) | python-v0.4 | js-v2.x | ws | noise | yamux | ✅ | 195s | - | - |
| python-v0.4 x jvm-v1.2 (quic-v1) | python-v0.4 | jvm-v1.2 | quic-v1 | - | - | ✅ | 4s | - | - |
| python-v0.4 x c-v0.0.1 (tcp, noise, yamux) | python-v0.4 | c-v0.0.1 | tcp | noise | yamux | ✅ | 3s | - | - |
| python-v0.4 x js-v3.x (ws, noise, mplex) | python-v0.4 | js-v3.x | ws | noise | mplex | ✅ | 191s | - | - |
| python-v0.4 x c-v0.0.1 (quic-v1) | python-v0.4 | c-v0.0.1 | quic-v1 | - | - | ✅ | 3s | - | - |
| python-v0.4 x js-v3.x (ws, noise, yamux) | python-v0.4 | js-v3.x | ws | noise | yamux | ✅ | 193s | - | - |
| python-v0.4 x nim-v1.14 (ws, noise, mplex) | python-v0.4 | nim-v1.14 | ws | noise | mplex | ✅ | 183s | - | - |
| python-v0.4 x nim-v1.14 (ws, noise, yamux) | python-v0.4 | nim-v1.14 | ws | noise | yamux | ✅ | 182s | - | - |
| python-v0.4 x dotnet-v1.0 (tcp, noise, yamux) | python-v0.4 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 3s | - | - |
| python-v0.4 x eth-p2p-z-v0.0.1 (quic-v1) | python-v0.4 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 4s | - | - |
| js-v1.x x rust-v0.53 (tcp, noise, mplex) | js-v1.x | rust-v0.53 | tcp | noise | mplex | ✅ | 7s | 100 | 12 |
| js-v1.x x rust-v0.53 (tcp, noise, yamux) | js-v1.x | rust-v0.53 | tcp | noise | yamux | ✅ | 8s | 101 | 26 |
| python-v0.4 x jvm-v1.2 (ws, noise, mplex) | python-v0.4 | jvm-v1.2 | ws | noise | mplex | ✅ | 185s | - | - |
| python-v0.4 x jvm-v1.2 (ws, noise, yamux) | python-v0.4 | jvm-v1.2 | ws | noise | yamux | ✅ | 184s | - | - |
| js-v1.x x rust-v0.53 (ws, noise, mplex) | js-v1.x | rust-v0.53 | ws | noise | mplex | ✅ | 8s | 191 | 17 |
| js-v1.x x rust-v0.53 (ws, noise, yamux) | js-v1.x | rust-v0.53 | ws | noise | yamux | ✅ | 8s | 232 | 59 |
| js-v1.x x rust-v0.54 (tcp, noise, mplex) | js-v1.x | rust-v0.54 | tcp | noise | mplex | ✅ | 12s | 139 | 33 |
| js-v1.x x rust-v0.54 (ws, noise, mplex) | js-v1.x | rust-v0.54 | ws | noise | mplex | ✅ | 12s | 217 | 26 |
| js-v1.x x rust-v0.54 (tcp, noise, yamux) | js-v1.x | rust-v0.54 | tcp | noise | yamux | ✅ | 12s | 116 | 29 |
| js-v1.x x rust-v0.54 (ws, noise, yamux) | js-v1.x | rust-v0.54 | ws | noise | yamux | ✅ | 12s | 213 | 22 |
| js-v1.x x rust-v0.55 (tcp, noise, mplex) | js-v1.x | rust-v0.55 | tcp | noise | mplex | ✅ | 12s | 43 | 15 |
| python-v0.4 x c-v0.0.1 (tcp, noise, mplex) | python-v0.4 | c-v0.0.1 | tcp | noise | mplex | ✅ | 34s | - | - |
| js-v1.x x rust-v0.55 (tcp, noise, yamux) | js-v1.x | rust-v0.55 | tcp | noise | yamux | ✅ | 11s | 57 | 18 |
| python-v0.4 x zig-v0.0.1 (quic-v1) | python-v0.4 | zig-v0.0.1 | quic-v1 | - | - | ❌ | 36s | - | - |
| js-v1.x x rust-v0.55 (ws, noise, mplex) | js-v1.x | rust-v0.55 | ws | noise | mplex | ✅ | 15s | 128 | 33 |
| js-v1.x x rust-v0.55 (ws, noise, yamux) | js-v1.x | rust-v0.55 | ws | noise | yamux | ✅ | 14s | 148 | 46 |
| js-v1.x x rust-v0.56 (tcp, noise, mplex) | js-v1.x | rust-v0.56 | tcp | noise | mplex | ✅ | 15s | 91 | 30 |
| js-v1.x x rust-v0.56 (tcp, noise, yamux) | js-v1.x | rust-v0.56 | tcp | noise | yamux | ✅ | 15s | 94 | 37 |
| js-v1.x x rust-v0.56 (ws, noise, mplex) | js-v1.x | rust-v0.56 | ws | noise | mplex | ✅ | 15s | 96 | 29 |
| js-v1.x x rust-v0.56 (ws, noise, yamux) | js-v1.x | rust-v0.56 | ws | noise | yamux | ✅ | 15s | 103 | 36 |
| js-v1.x x go-v0.38 (tcp, noise, yamux) | js-v1.x | go-v0.38 | tcp | noise | yamux | ✅ | 14s | 73 | 24 |
| js-v1.x x go-v0.38 (ws, noise, yamux) | js-v1.x | go-v0.38 | ws | noise | yamux | ✅ | 17s | 147 | 40 |
| js-v1.x x go-v0.38 (wss, noise, yamux) | js-v1.x | go-v0.38 | wss | noise | yamux | ✅ | 17s | 269 | 48 |
| js-v1.x x go-v0.39 (tcp, noise, yamux) | js-v1.x | go-v0.39 | tcp | noise | yamux | ✅ | 17s | 107 | 39 |
| js-v1.x x go-v0.39 (ws, noise, yamux) | js-v1.x | go-v0.39 | ws | noise | yamux | ✅ | 18s | 119 | 34 |
| js-v1.x x go-v0.40 (tcp, noise, yamux) | js-v1.x | go-v0.40 | tcp | noise | yamux | ✅ | 16s | 94 | 33 |
| js-v1.x x go-v0.39 (wss, noise, yamux) | js-v1.x | go-v0.39 | wss | noise | yamux | ✅ | 18s | 198 | 33 |
| js-v1.x x go-v0.40 (ws, noise, yamux) | js-v1.x | go-v0.40 | ws | noise | yamux | ✅ | 17s | 87 | 29 |
| js-v1.x x go-v0.40 (wss, noise, yamux) | js-v1.x | go-v0.40 | wss | noise | yamux | ✅ | 17s | 109 | 24 |
| js-v1.x x go-v0.41 (tcp, noise, yamux) | js-v1.x | go-v0.41 | tcp | noise | yamux | ✅ | 17s | 128 | 46 |
| js-v1.x x go-v0.41 (ws, noise, yamux) | js-v1.x | go-v0.41 | ws | noise | yamux | ✅ | 18s | 132 | 46 |
| js-v1.x x go-v0.41 (wss, noise, yamux) | js-v1.x | go-v0.41 | wss | noise | yamux | ✅ | 18s | 234 | 39 |
| js-v1.x x go-v0.42 (tcp, noise, yamux) | js-v1.x | go-v0.42 | tcp | noise | yamux | ✅ | 18s | 152 | 52 |
| js-v1.x x go-v0.42 (ws, noise, yamux) | js-v1.x | go-v0.42 | ws | noise | yamux | ✅ | 18s | 169 | 54 |
| js-v1.x x go-v0.42 (wss, noise, yamux) | js-v1.x | go-v0.42 | wss | noise | yamux | ✅ | 18s | 163 | 37 |
| js-v1.x x go-v0.43 (tcp, noise, yamux) | js-v1.x | go-v0.43 | tcp | noise | yamux | ✅ | 18s | 62 | 22 |
| js-v1.x x go-v0.43 (ws, noise, yamux) | js-v1.x | go-v0.43 | ws | noise | yamux | ✅ | 17s | 76 | 28 |
| js-v1.x x go-v0.43 (wss, noise, yamux) | js-v1.x | go-v0.43 | wss | noise | yamux | ✅ | 19s | 258 | 39 |
| js-v1.x x go-v0.44 (tcp, noise, yamux) | js-v1.x | go-v0.44 | tcp | noise | yamux | ✅ | 19s | 158 | 43 |
| js-v1.x x go-v0.44 (wss, noise, yamux) | js-v1.x | go-v0.44 | wss | noise | yamux | ✅ | 18s | 212 | 37 |
| js-v1.x x go-v0.44 (ws, noise, yamux) | js-v1.x | go-v0.44 | ws | noise | yamux | ✅ | 20s | 145 | 50 |
| js-v1.x x go-v0.45 (tcp, noise, yamux) | js-v1.x | go-v0.45 | tcp | noise | yamux | ✅ | 19s | 94 | 26 |
| js-v1.x x go-v0.45 (ws, noise, yamux) | js-v1.x | go-v0.45 | ws | noise | yamux | ✅ | 19s | 115 | 29 |
| js-v1.x x go-v0.45 (wss, noise, yamux) | js-v1.x | go-v0.45 | wss | noise | yamux | ✅ | 19s | 160 | 30 |
| js-v1.x x python-v0.4 (tcp, noise, mplex) | js-v1.x | python-v0.4 | tcp | noise | mplex | ✅ | 19s | 76 | 19 |
| js-v1.x x python-v0.4 (tcp, noise, yamux) | js-v1.x | python-v0.4 | tcp | noise | yamux | ✅ | 23s | 167 | 57 |
| js-v1.x x python-v0.4 (ws, noise, mplex) | js-v1.x | python-v0.4 | ws | noise | mplex | ✅ | 25s | 214 | 62 |
| js-v1.x x python-v0.4 (ws, noise, yamux) | js-v1.x | python-v0.4 | ws | noise | yamux | ✅ | 25s | 188 | 66 |
| js-v1.x x python-v0.4 (wss, noise, yamux) | js-v1.x | python-v0.4 | wss | noise | yamux | ✅ | 25s | 273 | 55 |
| js-v1.x x python-v0.4 (wss, noise, mplex) | js-v1.x | python-v0.4 | wss | noise | mplex | ✅ | 27s | 242 | 55 |
| js-v1.x x js-v1.x (tcp, noise, mplex) | js-v1.x | js-v1.x | tcp | noise | mplex | ✅ | 27s | 111 | 29 |
| js-v1.x x js-v1.x (ws, noise, mplex) | js-v1.x | js-v1.x | ws | noise | mplex | ✅ | 25s | 178 | 66 |
| js-v1.x x js-v1.x (tcp, noise, yamux) | js-v1.x | js-v1.x | tcp | noise | yamux | ✅ | 27s | 126 | 35 |
| js-v1.x x js-v1.x (ws, noise, yamux) | js-v1.x | js-v1.x | ws | noise | yamux | ✅ | 34s | 404 | 124 |
| js-v1.x x js-v2.x (tcp, noise, mplex) | js-v1.x | js-v2.x | tcp | noise | mplex | ✅ | 34s | 344 | 97 |
| js-v1.x x js-v2.x (tcp, noise, yamux) | js-v1.x | js-v2.x | tcp | noise | yamux | ✅ | 36s | 336 | 105 |
| js-v1.x x js-v2.x (ws, noise, mplex) | js-v1.x | js-v2.x | ws | noise | mplex | ✅ | 38s | 290 | 84 |
| js-v1.x x js-v3.x (tcp, noise, mplex) | js-v1.x | js-v3.x | tcp | noise | mplex | ✅ | 36s | 263 | 85 |
| js-v1.x x js-v2.x (ws, noise, yamux) | js-v1.x | js-v2.x | ws | noise | yamux | ✅ | 38s | 271 | 71 |
| js-v1.x x js-v3.x (tcp, noise, yamux) | js-v1.x | js-v3.x | tcp | noise | yamux | ✅ | 36s | 155 | 65 |
| js-v1.x x js-v3.x (ws, noise, mplex) | js-v1.x | js-v3.x | ws | noise | mplex | ✅ | 36s | 141 | 34 |
| js-v1.x x js-v3.x (ws, noise, yamux) | js-v1.x | js-v3.x | ws | noise | yamux | ✅ | 25s | 265 | 87 |
| js-v1.x x nim-v1.14 (tcp, noise, mplex) | js-v1.x | nim-v1.14 | tcp | noise | mplex | ✅ | 26s | 289 | 54 |
| js-v1.x x nim-v1.14 (tcp, noise, yamux) | js-v1.x | nim-v1.14 | tcp | noise | yamux | ✅ | 24s | 250 | 53 |
| js-v1.x x nim-v1.14 (ws, noise, mplex) | js-v1.x | nim-v1.14 | ws | noise | mplex | ✅ | 25s | 311 | 52 |
| js-v1.x x nim-v1.14 (ws, noise, yamux) | js-v1.x | nim-v1.14 | ws | noise | yamux | ✅ | 25s | 302 | 60 |
| js-v1.x x jvm-v1.2 (tcp, noise, mplex) | js-v1.x | jvm-v1.2 | tcp | noise | mplex | ✅ | 25s | 902 | 68 |
| js-v1.x x jvm-v1.2 (tcp, noise, yamux) | js-v1.x | jvm-v1.2 | tcp | noise | yamux | ✅ | 26s | 676 | 87 |
| js-v1.x x jvm-v1.2 (ws, noise, mplex) | js-v1.x | jvm-v1.2 | ws | noise | mplex | ❌ | 29s | - | - |
| js-v1.x x c-v0.0.1 (tcp, noise, mplex) | js-v1.x | c-v0.0.1 | tcp | noise | mplex | ✅ | 20s | 131 | 38 |
| js-v1.x x c-v0.0.1 (tcp, noise, yamux) | js-v1.x | c-v0.0.1 | tcp | noise | yamux | ✅ | 20s | 191 | 96 |
| js-v1.x x dotnet-v1.0 (tcp, noise, yamux) | js-v1.x | dotnet-v1.0 | tcp | noise | yamux | ✅ | 20s | 392 | 101 |
| js-v2.x x rust-v0.53 (tcp, noise, mplex) | js-v2.x | rust-v0.53 | tcp | noise | mplex | ✅ | 21s | 172 | 38 |
| js-v2.x x rust-v0.53 (tcp, noise, yamux) | js-v2.x | rust-v0.53 | tcp | noise | yamux | ✅ | 21s | 166 | 49 |
| js-v1.x x jvm-v1.2 (ws, noise, yamux) | js-v1.x | jvm-v1.2 | ws | noise | yamux | ❌ | 25s | - | - |
| js-v2.x x rust-v0.53 (ws, noise, mplex) | js-v2.x | rust-v0.53 | ws | noise | mplex | ✅ | 21s | 307 | 74 |
| js-v2.x x rust-v0.53 (ws, noise, yamux) | js-v2.x | rust-v0.53 | ws | noise | yamux | ✅ | 19s | 343 | 98 |
| js-v2.x x rust-v0.54 (tcp, noise, mplex) | js-v2.x | rust-v0.54 | tcp | noise | mplex | ✅ | 21s | 233 | 59 |
| js-v2.x x rust-v0.54 (tcp, noise, yamux) | js-v2.x | rust-v0.54 | tcp | noise | yamux | ✅ | 22s | 224 | 60 |
| js-v2.x x rust-v0.54 (ws, noise, mplex) | js-v2.x | rust-v0.54 | ws | noise | mplex | ✅ | 23s | 360 | 102 |
| js-v2.x x rust-v0.55 (tcp, noise, mplex) | js-v2.x | rust-v0.55 | tcp | noise | mplex | ✅ | 21s | 127 | 44 |
| js-v2.x x rust-v0.54 (ws, noise, yamux) | js-v2.x | rust-v0.54 | ws | noise | yamux | ✅ | 23s | 327 | 93 |
| js-v2.x x rust-v0.55 (tcp, noise, yamux) | js-v2.x | rust-v0.55 | tcp | noise | yamux | ✅ | 22s | 140 | 44 |
| js-v2.x x rust-v0.55 (ws, noise, mplex) | js-v2.x | rust-v0.55 | ws | noise | mplex | ✅ | 22s | 149 | 35 |
| js-v2.x x rust-v0.55 (ws, noise, yamux) | js-v2.x | rust-v0.55 | ws | noise | yamux | ✅ | 20s | 144 | 48 |
| js-v2.x x rust-v0.56 (tcp, noise, mplex) | js-v2.x | rust-v0.56 | tcp | noise | mplex | ✅ | 21s | 138 | 50 |
| js-v2.x x rust-v0.56 (tcp, noise, yamux) | js-v2.x | rust-v0.56 | tcp | noise | yamux | ✅ | 22s | 151 | 51 |
| js-v2.x x rust-v0.56 (ws, noise, mplex) | js-v2.x | rust-v0.56 | ws | noise | mplex | ✅ | 22s | 176 | 48 |
| js-v2.x x rust-v0.56 (ws, noise, yamux) | js-v2.x | rust-v0.56 | ws | noise | yamux | ✅ | 22s | 172 | 53 |
| js-v2.x x go-v0.38 (tcp, noise, yamux) | js-v2.x | go-v0.38 | tcp | noise | yamux | ✅ | 22s | 149 | 59 |
| js-v2.x x go-v0.38 (ws, noise, yamux) | js-v2.x | go-v0.38 | ws | noise | yamux | ✅ | 22s | 163 | 50 |
| js-v2.x x go-v0.38 (wss, noise, yamux) | js-v2.x | go-v0.38 | wss | noise | yamux | ✅ | 21s | 211 | 39 |
| js-v2.x x go-v0.39 (tcp, noise, yamux) | js-v2.x | go-v0.39 | tcp | noise | yamux | ✅ | 21s | 94 | 40 |
| js-v2.x x go-v0.39 (ws, noise, yamux) | js-v2.x | go-v0.39 | ws | noise | yamux | ✅ | 21s | 201 | 67 |
| js-v2.x x go-v0.39 (wss, noise, yamux) | js-v2.x | go-v0.39 | wss | noise | yamux | ✅ | 22s | 272 | 61 |
| js-v2.x x go-v0.40 (ws, noise, yamux) | js-v2.x | go-v0.40 | ws | noise | yamux | ✅ | 22s | 189 | 66 |
| js-v2.x x go-v0.40 (tcp, noise, yamux) | js-v2.x | go-v0.40 | tcp | noise | yamux | ✅ | 23s | 192 | 63 |
| js-v2.x x go-v0.40 (wss, noise, yamux) | js-v2.x | go-v0.40 | wss | noise | yamux | ✅ | 23s | 262 | 57 |
| js-v2.x x go-v0.41 (ws, noise, yamux) | js-v2.x | go-v0.41 | ws | noise | yamux | ✅ | 22s | 119 | 31 |
| js-v2.x x go-v0.41 (tcp, noise, yamux) | js-v2.x | go-v0.41 | tcp | noise | yamux | ✅ | 23s | 127 | 48 |
| js-v2.x x go-v0.41 (wss, noise, yamux) | js-v2.x | go-v0.41 | wss | noise | yamux | ✅ | 23s | 145 | 28 |
| js-v2.x x go-v0.42 (tcp, noise, yamux) | js-v2.x | go-v0.42 | tcp | noise | yamux | ✅ | 19s | 161 | 60 |
| js-v2.x x go-v0.42 (ws, noise, yamux) | js-v2.x | go-v0.42 | ws | noise | yamux | ✅ | 23s | 182 | 54 |
| js-v2.x x go-v0.42 (wss, noise, yamux) | js-v2.x | go-v0.42 | wss | noise | yamux | ✅ | 23s | 254 | 47 |
| js-v2.x x go-v0.43 (tcp, noise, yamux) | js-v2.x | go-v0.43 | tcp | noise | yamux | ✅ | 23s | 139 | 54 |
| js-v2.x x go-v0.43 (wss, noise, yamux) | js-v2.x | go-v0.43 | wss | noise | yamux | ✅ | 23s | 274 | 48 |
| js-v2.x x go-v0.43 (ws, noise, yamux) | js-v2.x | go-v0.43 | ws | noise | yamux | ✅ | 23s | 128 | 43 |
| js-v2.x x go-v0.44 (tcp, noise, yamux) | js-v2.x | go-v0.44 | tcp | noise | yamux | ✅ | 23s | 115 | 42 |
| js-v2.x x go-v0.44 (ws, noise, yamux) | js-v2.x | go-v0.44 | ws | noise | yamux | ✅ | 22s | 112 | 37 |
| js-v2.x x go-v0.44 (wss, noise, yamux) | js-v2.x | go-v0.44 | wss | noise | yamux | ✅ | 20s | 301 | 54 |
| js-v2.x x go-v0.45 (tcp, noise, yamux) | js-v2.x | go-v0.45 | tcp | noise | yamux | ✅ | 23s | 144 | 51 |
| js-v2.x x go-v0.45 (wss, noise, yamux) | js-v2.x | go-v0.45 | wss | noise | yamux | ✅ | 23s | 272 | 51 |
| js-v2.x x go-v0.45 (ws, noise, yamux) | js-v2.x | go-v0.45 | ws | noise | yamux | ✅ | 25s | 207 | 56 |
| js-v2.x x python-v0.4 (tcp, noise, yamux) | js-v2.x | python-v0.4 | tcp | noise | yamux | ✅ | 23s | 159 | 65 |
| js-v2.x x python-v0.4 (tcp, noise, mplex) | js-v2.x | python-v0.4 | tcp | noise | mplex | ✅ | 25s | 113 | 29 |
| js-v2.x x python-v0.4 (ws, noise, mplex) | js-v2.x | python-v0.4 | ws | noise | mplex | ✅ | 23s | 130 | 28 |
| js-v2.x x python-v0.4 (ws, noise, yamux) | js-v2.x | python-v0.4 | ws | noise | yamux | ✅ | 23s | 161 | 48 |
| js-v2.x x python-v0.4 (wss, noise, mplex) | js-v2.x | python-v0.4 | wss | noise | mplex | ✅ | 22s | 272 | 50 |
| js-v2.x x python-v0.4 (wss, noise, yamux) | js-v2.x | python-v0.4 | wss | noise | yamux | ✅ | 37s | 373 | 67 |
| js-v2.x x js-v1.x (tcp, noise, mplex) | js-v2.x | js-v1.x | tcp | noise | mplex | ✅ | 38s | 256 | 87 |
| js-v2.x x js-v1.x (tcp, noise, yamux) | js-v2.x | js-v1.x | tcp | noise | yamux | ✅ | 37s | 282 | 102 |
| js-v2.x x js-v1.x (ws, noise, mplex) | js-v2.x | js-v1.x | ws | noise | mplex | ✅ | 39s | 232 | 65 |
| js-v2.x x js-v1.x (ws, noise, yamux) | js-v2.x | js-v1.x | ws | noise | yamux | ✅ | 39s | 296 | 78 |
| js-v2.x x js-v2.x (tcp, noise, yamux) | js-v2.x | js-v2.x | tcp | noise | yamux | ✅ | 38s | 198 | 67 |
| js-v2.x x js-v2.x (tcp, noise, mplex) | js-v2.x | js-v2.x | tcp | noise | mplex | ✅ | 39s | 164 | 66 |
| js-v2.x x js-v2.x (ws, noise, mplex) | js-v2.x | js-v2.x | ws | noise | mplex | ✅ | 32s | 329 | 79 |
| js-v2.x x js-v2.x (ws, noise, yamux) | js-v2.x | js-v2.x | ws | noise | yamux | ✅ | 34s | 362 | 123 |
| js-v2.x x js-v3.x (tcp, noise, mplex) | js-v2.x | js-v3.x | tcp | noise | mplex | ✅ | 35s | 269 | 79 |
| js-v2.x x js-v3.x (tcp, noise, yamux) | js-v2.x | js-v3.x | tcp | noise | yamux | ✅ | 34s | 378 | 208 |
| js-v2.x x js-v3.x (ws, noise, mplex) | js-v2.x | js-v3.x | ws | noise | mplex | ✅ | 34s | 221 | 57 |
| js-v2.x x js-v3.x (ws, noise, yamux) | js-v2.x | js-v3.x | ws | noise | yamux | ✅ | 34s | 206 | 55 |
| js-v2.x x nim-v1.14 (tcp, noise, mplex) | js-v2.x | nim-v1.14 | tcp | noise | mplex | ✅ | 33s | 266 | 40 |
| js-v2.x x nim-v1.14 (tcp, noise, yamux) | js-v2.x | nim-v1.14 | tcp | noise | yamux | ✅ | 33s | 183 | 28 |
| js-v2.x x nim-v1.14 (ws, noise, mplex) | js-v2.x | nim-v1.14 | ws | noise | mplex | ✅ | 30s | 312 | 46 |
| js-v2.x x nim-v1.14 (ws, noise, yamux) | js-v2.x | nim-v1.14 | ws | noise | yamux | ✅ | 26s | 407 | 92 |
| js-v2.x x jvm-v1.2 (tcp, noise, mplex) | js-v2.x | jvm-v1.2 | tcp | noise | mplex | ✅ | 26s | 1572 | 126 |
| js-v2.x x jvm-v1.2 (tcp, noise, yamux) | js-v2.x | jvm-v1.2 | tcp | noise | yamux | ✅ | 28s | 1057 | 145 |
| js-v2.x x c-v0.0.1 (tcp, noise, mplex) | js-v2.x | c-v0.0.1 | tcp | noise | mplex | ✅ | 26s | 134 | 26 |
| js-v2.x x jvm-v1.2 (ws, noise, mplex) | js-v2.x | jvm-v1.2 | ws | noise | mplex | ✅ | 28s | 1626 | 194 |
| js-v2.x x c-v0.0.1 (tcp, noise, yamux) | js-v2.x | c-v0.0.1 | tcp | noise | yamux | ✅ | 26s | 190 | 93 |
| js-v2.x x jvm-v1.2 (ws, noise, yamux) | js-v2.x | jvm-v1.2 | ws | noise | yamux | ✅ | 28s | 1308 | 182 |
| js-v2.x x dotnet-v1.0 (tcp, noise, yamux) | js-v2.x | dotnet-v1.0 | tcp | noise | yamux | ✅ | 23s | 235 | 73 |
| js-v3.x x rust-v0.53 (tcp, noise, mplex) | js-v3.x | rust-v0.53 | tcp | noise | mplex | ✅ | 22s | 203 | 6 |
| js-v3.x x rust-v0.53 (tcp, noise, yamux) | js-v3.x | rust-v0.53 | tcp | noise | yamux | ✅ | 21s | 199 | 5 |
| js-v3.x x rust-v0.53 (ws, noise, mplex) | js-v3.x | rust-v0.53 | ws | noise | mplex | ✅ | 23s | 238 | 11 |
| js-v3.x x rust-v0.53 (ws, noise, yamux) | js-v3.x | rust-v0.53 | ws | noise | yamux | ✅ | 22s | 230 | 4 |
| js-v3.x x rust-v0.54 (tcp, noise, yamux) | js-v3.x | rust-v0.54 | tcp | noise | yamux | ✅ | 22s | 170 | 5 |
| js-v3.x x rust-v0.54 (tcp, noise, mplex) | js-v3.x | rust-v0.54 | tcp | noise | mplex | ✅ | 22s | 157 | 5 |
| js-v3.x x rust-v0.54 (ws, noise, mplex) | js-v3.x | rust-v0.54 | ws | noise | mplex | ✅ | 22s | 220 | 5 |
| js-v3.x x rust-v0.54 (ws, noise, yamux) | js-v3.x | rust-v0.54 | ws | noise | yamux | ✅ | 22s | 213 | 4 |
| js-v3.x x rust-v0.55 (tcp, noise, mplex) | js-v3.x | rust-v0.55 | tcp | noise | mplex | ✅ | 22s | 123 | 6 |
| js-v3.x x rust-v0.55 (tcp, noise, yamux) | js-v3.x | rust-v0.55 | tcp | noise | yamux | ✅ | 23s | 124 | 16 |
| js-v3.x x rust-v0.55 (ws, noise, mplex) | js-v3.x | rust-v0.55 | ws | noise | mplex | ✅ | 22s | 130 | 16 |
| js-v3.x x rust-v0.55 (ws, noise, yamux) | js-v3.x | rust-v0.55 | ws | noise | yamux | ✅ | 22s | 156 | 2 |
| js-v3.x x rust-v0.56 (tcp, noise, yamux) | js-v3.x | rust-v0.56 | tcp | noise | yamux | ✅ | 21s | 123 | 1 |
| js-v3.x x rust-v0.56 (tcp, noise, mplex) | js-v3.x | rust-v0.56 | tcp | noise | mplex | ✅ | 23s | 110 | 14 |
| js-v3.x x rust-v0.56 (ws, noise, mplex) | js-v3.x | rust-v0.56 | ws | noise | mplex | ✅ | 22s | 133 | 2 |
| js-v3.x x rust-v0.56 (ws, noise, yamux) | js-v3.x | rust-v0.56 | ws | noise | yamux | ✅ | 22s | 100 | 12 |
| js-v3.x x go-v0.38 (tcp, noise, yamux) | js-v3.x | go-v0.38 | tcp | noise | yamux | ✅ | 21s | 137 | 2 |
| js-v3.x x go-v0.38 (ws, noise, yamux) | js-v3.x | go-v0.38 | ws | noise | yamux | ✅ | 21s | 158 | 2 |
| js-v3.x x go-v0.38 (wss, noise, yamux) | js-v3.x | go-v0.38 | wss | noise | yamux | ✅ | 22s | 244 | 36 |
| js-v3.x x go-v0.39 (tcp, noise, yamux) | js-v3.x | go-v0.39 | tcp | noise | yamux | ✅ | 23s | 139 | 13 |
| js-v3.x x go-v0.39 (wss, noise, yamux) | js-v3.x | go-v0.39 | wss | noise | yamux | ✅ | 22s | 210 | 30 |
| js-v3.x x go-v0.39 (ws, noise, yamux) | js-v3.x | go-v0.39 | ws | noise | yamux | ✅ | 23s | 145 | 18 |
| js-v3.x x go-v0.40 (tcp, noise, yamux) | js-v3.x | go-v0.40 | tcp | noise | yamux | ✅ | 22s | 113 | 11 |
| js-v3.x x go-v0.40 (ws, noise, yamux) | js-v3.x | go-v0.40 | ws | noise | yamux | ✅ | 21s | 109 | 13 |
| js-v3.x x go-v0.40 (wss, noise, yamux) | js-v3.x | go-v0.40 | wss | noise | yamux | ✅ | 21s | 310 | 37 |
| js-v3.x x go-v0.41 (tcp, noise, yamux) | js-v3.x | go-v0.41 | tcp | noise | yamux | ✅ | 22s | 136 | 15 |
| js-v3.x x go-v0.41 (ws, noise, yamux) | js-v3.x | go-v0.41 | ws | noise | yamux | ✅ | 22s | 131 | 9 |
| js-v3.x x go-v0.41 (wss, noise, yamux) | js-v3.x | go-v0.41 | wss | noise | yamux | ✅ | 23s | 317 | 40 |
| js-v3.x x go-v0.42 (tcp, noise, yamux) | js-v3.x | go-v0.42 | tcp | noise | yamux | ✅ | 22s | 91 | 9 |
| js-v3.x x go-v0.42 (ws, noise, yamux) | js-v3.x | go-v0.42 | ws | noise | yamux | ✅ | 23s | 128 | 13 |
| js-v3.x x go-v0.42 (wss, noise, yamux) | js-v3.x | go-v0.42 | wss | noise | yamux | ✅ | 22s | 145 | 17 |
| js-v3.x x go-v0.43 (tcp, noise, yamux) | js-v3.x | go-v0.43 | tcp | noise | yamux | ✅ | 22s | 68 | 6 |
| js-v3.x x go-v0.43 (ws, noise, yamux) | js-v3.x | go-v0.43 | ws | noise | yamux | ✅ | 22s | 154 | 17 |
| js-v3.x x go-v0.44 (tcp, noise, yamux) | js-v3.x | go-v0.44 | tcp | noise | yamux | ✅ | 22s | 126 | 14 |
| js-v3.x x go-v0.43 (wss, noise, yamux) | js-v3.x | go-v0.43 | wss | noise | yamux | ✅ | 23s | 257 | 23 |
| js-v3.x x go-v0.44 (ws, noise, yamux) | js-v3.x | go-v0.44 | ws | noise | yamux | ✅ | 23s | 115 | 15 |
| js-v3.x x go-v0.44 (wss, noise, yamux) | js-v3.x | go-v0.44 | wss | noise | yamux | ✅ | 22s | 201 | 33 |
| js-v3.x x go-v0.45 (tcp, noise, yamux) | js-v3.x | go-v0.45 | tcp | noise | yamux | ✅ | 22s | 114 | 13 |
| js-v3.x x go-v0.45 (ws, noise, yamux) | js-v3.x | go-v0.45 | ws | noise | yamux | ✅ | 22s | 122 | 12 |
| js-v3.x x go-v0.45 (wss, noise, yamux) | js-v3.x | go-v0.45 | wss | noise | yamux | ✅ | 22s | 150 | 20 |
| js-v3.x x python-v0.4 (tcp, noise, mplex) | js-v3.x | python-v0.4 | tcp | noise | mplex | ✅ | 27s | 180 | 4 |
| js-v3.x x python-v0.4 (tcp, noise, yamux) | js-v3.x | python-v0.4 | tcp | noise | yamux | ✅ | 28s | 158 | 4 |
| js-v3.x x python-v0.4 (ws, noise, yamux) | js-v3.x | python-v0.4 | ws | noise | yamux | ✅ | 27s | 224 | 4 |
| js-v3.x x python-v0.4 (ws, noise, mplex) | js-v3.x | python-v0.4 | ws | noise | mplex | ✅ | 29s | 254 | 12 |
| js-v3.x x python-v0.4 (wss, noise, mplex) | js-v3.x | python-v0.4 | wss | noise | mplex | ✅ | 28s | 286 | 5 |
| js-v3.x x js-v1.x (tcp, noise, mplex) | js-v3.x | js-v1.x | tcp | noise | mplex | ✅ | 26s | 158 | 4 |
| js-v3.x x python-v0.4 (wss, noise, yamux) | js-v3.x | python-v0.4 | wss | noise | yamux | ✅ | 28s | 208 | 5 |
| js-v3.x x js-v1.x (tcp, noise, yamux) | js-v3.x | js-v1.x | tcp | noise | yamux | ✅ | 26s | 136 | 2 |
| js-v3.x x js-v1.x (ws, noise, yamux) | js-v3.x | js-v1.x | ws | noise | yamux | ✅ | 38s | 389 | 6 |
| js-v3.x x js-v1.x (ws, noise, mplex) | js-v3.x | js-v1.x | ws | noise | mplex | ✅ | 41s | 390 | 23 |
| js-v3.x x js-v2.x (tcp, noise, yamux) | js-v3.x | js-v2.x | tcp | noise | yamux | ✅ | 40s | 350 | 45 |
| js-v3.x x js-v2.x (tcp, noise, mplex) | js-v3.x | js-v2.x | tcp | noise | mplex | ✅ | 41s | 343 | 15 |
| js-v3.x x js-v2.x (ws, noise, mplex) | js-v3.x | js-v2.x | ws | noise | mplex | ✅ | 41s | 225 | 3 |
| js-v3.x x js-v2.x (ws, noise, yamux) | js-v3.x | js-v2.x | ws | noise | yamux | ✅ | 42s | 241 | 7 |
| js-v3.x x js-v3.x (tcp, noise, yamux) | js-v3.x | js-v3.x | tcp | noise | yamux | ✅ | 39s | 166 | 3 |
| js-v3.x x js-v3.x (tcp, noise, mplex) | js-v3.x | js-v3.x | tcp | noise | mplex | ✅ | 41s | 137 | 13 |
| js-v3.x x js-v3.x (ws, noise, mplex) | js-v3.x | js-v3.x | ws | noise | mplex | ✅ | 28s | 248 | 6 |
| js-v3.x x js-v3.x (ws, noise, yamux) | js-v3.x | js-v3.x | ws | noise | yamux | ✅ | 28s | 259 | 11 |
| js-v3.x x nim-v1.14 (tcp, noise, mplex) | js-v3.x | nim-v1.14 | tcp | noise | mplex | ✅ | 29s | 237 | 7 |
| js-v3.x x nim-v1.14 (tcp, noise, yamux) | js-v3.x | nim-v1.14 | tcp | noise | yamux | ✅ | 28s | 244 | 5 |
| js-v3.x x nim-v1.14 (ws, noise, mplex) | js-v3.x | nim-v1.14 | ws | noise | mplex | ✅ | 29s | 291 | 6 |
| js-v3.x x nim-v1.14 (ws, noise, yamux) | js-v3.x | nim-v1.14 | ws | noise | yamux | ✅ | 29s | 271 | 8 |
| js-v3.x x jvm-v1.2 (tcp, noise, mplex) | js-v3.x | jvm-v1.2 | tcp | noise | mplex | ✅ | 28s | 1005 | 11 |
| js-v3.x x jvm-v1.2 (tcp, noise, yamux) | js-v3.x | jvm-v1.2 | tcp | noise | yamux | ✅ | 28s | 1134 | 79 |
| nim-v1.14 x rust-v0.53 (tcp, noise, mplex) | nim-v1.14 | rust-v0.53 | tcp | noise | mplex | ✅ | 5s | 277.0 | 1.0 |
| nim-v1.14 x rust-v0.53 (tcp, noise, yamux) | nim-v1.14 | rust-v0.53 | tcp | noise | yamux | ✅ | 6s | 323.0 | 0.0 |
| nim-v1.14 x rust-v0.53 (ws, noise, mplex) | nim-v1.14 | rust-v0.53 | ws | noise | mplex | ✅ | 5s | 461.0 | 43.0 |
| nim-v1.14 x rust-v0.53 (ws, noise, yamux) | nim-v1.14 | rust-v0.53 | ws | noise | yamux | ✅ | 5s | 467.0 | 47.0 |
| nim-v1.14 x rust-v0.54 (tcp, noise, mplex) | nim-v1.14 | rust-v0.54 | tcp | noise | mplex | ✅ | 5s | 277.0 | 2.0 |
| nim-v1.14 x rust-v0.54 (tcp, noise, yamux) | nim-v1.14 | rust-v0.54 | tcp | noise | yamux | ✅ | 6s | 330.0 | 0.0 |
| js-v3.x x jvm-v1.2 (ws, noise, mplex) | js-v3.x | jvm-v1.2 | ws | noise | mplex | ✅ | 22s | 1652 | 8 |
| js-v3.x x c-v0.0.1 (tcp, noise, mplex) | js-v3.x | c-v0.0.1 | tcp | noise | mplex | ✅ | 21s | 133 | 2 |
| js-v3.x x c-v0.0.1 (tcp, noise, yamux) | js-v3.x | c-v0.0.1 | tcp | noise | yamux | ✅ | 20s | 193 | 10 |
| js-v3.x x jvm-v1.2 (ws, noise, yamux) | js-v3.x | jvm-v1.2 | ws | noise | yamux | ✅ | 23s | 1303 | 97 |
| js-v3.x x dotnet-v1.0 (tcp, noise, yamux) | js-v3.x | dotnet-v1.0 | tcp | noise | yamux | ✅ | 20s | 232 | 12 |
| nim-v1.14 x rust-v0.54 (ws, noise, mplex) | nim-v1.14 | rust-v0.54 | ws | noise | mplex | ✅ | 6s | 449.0 | 43.0 |
| nim-v1.14 x rust-v0.54 (ws, noise, yamux) | nim-v1.14 | rust-v0.54 | ws | noise | yamux | ✅ | 6s | 463.0 | 47.0 |
| nim-v1.14 x rust-v0.55 (tcp, noise, mplex) | nim-v1.14 | rust-v0.55 | tcp | noise | mplex | ✅ | 5s | 189.0 | 48.0 |
| nim-v1.14 x rust-v0.55 (tcp, noise, yamux) | nim-v1.14 | rust-v0.55 | tcp | noise | yamux | ✅ | 5s | 182.0 | 46.0 |
| nim-v1.14 x rust-v0.55 (ws, noise, mplex) | nim-v1.14 | rust-v0.55 | ws | noise | mplex | ✅ | 4s | 194.0 | 42.0 |
| nim-v1.14 x rust-v0.55 (ws, noise, yamux) | nim-v1.14 | rust-v0.55 | ws | noise | yamux | ✅ | 5s | 194.0 | 0.0 |
| nim-v1.14 x rust-v0.56 (tcp, noise, mplex) | nim-v1.14 | rust-v0.56 | tcp | noise | mplex | ✅ | 5s | 182.0 | 0.0 |
| nim-v1.14 x rust-v0.56 (tcp, noise, yamux) | nim-v1.14 | rust-v0.56 | tcp | noise | yamux | ✅ | 5s | 185.0 | 0.0 |
| nim-v1.14 x rust-v0.56 (ws, noise, mplex) | nim-v1.14 | rust-v0.56 | ws | noise | mplex | ✅ | 6s | 182.0 | 0.0 |
| nim-v1.14 x rust-v0.56 (ws, noise, yamux) | nim-v1.14 | rust-v0.56 | ws | noise | yamux | ✅ | 5s | 200.0 | 41.0 |
| nim-v1.14 x go-v0.38 (ws, noise, yamux) | nim-v1.14 | go-v0.38 | ws | noise | yamux | ✅ | 4s | 239.0 | 0.0 |
| nim-v1.14 x go-v0.38 (tcp, noise, yamux) | nim-v1.14 | go-v0.38 | tcp | noise | yamux | ✅ | 6s | 151.0 | 0.0 |
| nim-v1.14 x go-v0.39 (tcp, noise, yamux) | nim-v1.14 | go-v0.39 | tcp | noise | yamux | ✅ | 4s | 189.0 | 0.0 |
| nim-v1.14 x go-v0.39 (ws, noise, yamux) | nim-v1.14 | go-v0.39 | ws | noise | yamux | ✅ | 4s | 253.0 | 0.0 |
| nim-v1.14 x go-v0.40 (tcp, noise, yamux) | nim-v1.14 | go-v0.40 | tcp | noise | yamux | ✅ | 5s | 147.0 | 0.0 |
| nim-v1.14 x go-v0.40 (ws, noise, yamux) | nim-v1.14 | go-v0.40 | ws | noise | yamux | ✅ | 5s | 242.0 | 0.0 |
| nim-v1.14 x go-v0.41 (tcp, noise, yamux) | nim-v1.14 | go-v0.41 | tcp | noise | yamux | ✅ | 5s | 144.0 | 0.0 |
| nim-v1.14 x go-v0.41 (ws, noise, yamux) | nim-v1.14 | go-v0.41 | ws | noise | yamux | ✅ | 5s | 149.0 | 0.0 |
| nim-v1.14 x go-v0.42 (tcp, noise, yamux) | nim-v1.14 | go-v0.42 | tcp | noise | yamux | ✅ | 5s | 136.0 | 0.0 |
| nim-v1.14 x go-v0.42 (ws, noise, yamux) | nim-v1.14 | go-v0.42 | ws | noise | yamux | ✅ | 5s | 205.0 | 0.0 |
| nim-v1.14 x go-v0.43 (ws, noise, yamux) | nim-v1.14 | go-v0.43 | ws | noise | yamux | ✅ | 5s | 234.0 | 0.0 |
| nim-v1.14 x go-v0.43 (tcp, noise, yamux) | nim-v1.14 | go-v0.43 | tcp | noise | yamux | ✅ | 5s | 183.0 | 0.0 |
| nim-v1.14 x go-v0.44 (tcp, noise, yamux) | nim-v1.14 | go-v0.44 | tcp | noise | yamux | ✅ | 5s | 201.0 | 0.0 |
| nim-v1.14 x go-v0.44 (ws, noise, yamux) | nim-v1.14 | go-v0.44 | ws | noise | yamux | ✅ | 5s | 229.0 | 0.0 |
| nim-v1.14 x go-v0.45 (tcp, noise, yamux) | nim-v1.14 | go-v0.45 | tcp | noise | yamux | ✅ | 5s | 198.0 | 0.0 |
| nim-v1.14 x go-v0.45 (ws, noise, yamux) | nim-v1.14 | go-v0.45 | ws | noise | yamux | ✅ | 5s | 267.0 | 0.0 |
| nim-v1.14 x python-v0.4 (tcp, noise, mplex) | nim-v1.14 | python-v0.4 | tcp | noise | mplex | ✅ | 5s | 163.0 | 1.0 |
| nim-v1.14 x python-v0.4 (tcp, noise, yamux) | nim-v1.14 | python-v0.4 | tcp | noise | yamux | ✅ | 5s | 175.0 | 3.0 |
| nim-v1.14 x python-v0.4 (ws, noise, mplex) | nim-v1.14 | python-v0.4 | ws | noise | mplex | ✅ | 6s | 222.0 | 1.0 |
| nim-v1.14 x python-v0.4 (ws, noise, yamux) | nim-v1.14 | python-v0.4 | ws | noise | yamux | ✅ | 5s | 215.0 | 2.0 |
| nim-v1.14 x js-v1.x (tcp, noise, mplex) | nim-v1.14 | js-v1.x | tcp | noise | mplex | ✅ | 19s | 291.0 | 2.0 |
| nim-v1.14 x js-v1.x (ws, noise, mplex) | nim-v1.14 | js-v1.x | ws | noise | mplex | ✅ | 20s | 329.0 | 1.0 |
| nim-v1.14 x js-v1.x (tcp, noise, yamux) | nim-v1.14 | js-v1.x | tcp | noise | yamux | ✅ | 22s | 276.0 | 12.0 |
| nim-v1.14 x js-v1.x (ws, noise, yamux) | nim-v1.14 | js-v1.x | ws | noise | yamux | ✅ | 21s | 320.0 | 5.0 |
| nim-v1.14 x js-v2.x (tcp, noise, mplex) | nim-v1.14 | js-v2.x | tcp | noise | mplex | ✅ | 23s | 285.0 | 1.0 |
| nim-v1.14 x js-v2.x (tcp, noise, yamux) | nim-v1.14 | js-v2.x | tcp | noise | yamux | ✅ | 22s | 290.0 | 2.0 |
| nim-v1.14 x js-v2.x (ws, noise, mplex) | nim-v1.14 | js-v2.x | ws | noise | mplex | ✅ | 22s | 342.0 | 4.0 |
| nim-v1.14 x js-v2.x (ws, noise, yamux) | nim-v1.14 | js-v2.x | ws | noise | yamux | ✅ | 21s | 276.0 | 1.0 |
| nim-v1.14 x nim-v1.14 (tcp, noise, mplex) | nim-v1.14 | nim-v1.14 | tcp | noise | mplex | ✅ | 4s | 396.0 | 3.0 |
| nim-v1.14 x nim-v1.14 (tcp, noise, yamux) | nim-v1.14 | nim-v1.14 | tcp | noise | yamux | ✅ | 4s | 383.0 | 0.0 |
| nim-v1.14 x nim-v1.14 (ws, noise, mplex) | nim-v1.14 | nim-v1.14 | ws | noise | mplex | ✅ | 5s | 390.0 | 1.0 |
| nim-v1.14 x nim-v1.14 (ws, noise, yamux) | nim-v1.14 | nim-v1.14 | ws | noise | yamux | ✅ | 5s | 393.0 | 1.0 |
| nim-v1.14 x js-v3.x (tcp, noise, mplex) | nim-v1.14 | js-v3.x | tcp | noise | mplex | ✅ | 19s | 307.0 | 8.0 |
| nim-v1.14 x jvm-v1.2 (tcp, noise, mplex) | nim-v1.14 | jvm-v1.2 | tcp | noise | mplex | ✅ | 11s | 1873.0 | 7.0 |
| nim-v1.14 x js-v3.x (tcp, noise, yamux) | nim-v1.14 | js-v3.x | tcp | noise | yamux | ✅ | 20s | 234.0 | 7.0 |
| nim-v1.14 x jvm-v1.2 (tcp, noise, yamux) | nim-v1.14 | jvm-v1.2 | tcp | noise | yamux | ✅ | 11s | 1163.0 | 10.0 |
| nim-v1.14 x js-v3.x (ws, noise, mplex) | nim-v1.14 | js-v3.x | ws | noise | mplex | ✅ | 20s | 311.0 | 6.0 |
| nim-v1.14 x js-v3.x (ws, noise, yamux) | nim-v1.14 | js-v3.x | ws | noise | yamux | ✅ | 21s | 345.0 | 8.0 |
| nim-v1.14 x jvm-v1.2 (ws, noise, yamux) | nim-v1.14 | jvm-v1.2 | ws | noise | yamux | ✅ | 10s | 1264.0 | 20.0 |
| nim-v1.14 x jvm-v1.2 (ws, noise, mplex) | nim-v1.14 | jvm-v1.2 | ws | noise | mplex | ✅ | 12s | 1127.0 | 2.0 |
| nim-v1.14 x c-v0.0.1 (tcp, noise, mplex) | nim-v1.14 | c-v0.0.1 | tcp | noise | mplex | ✅ | 5s | 187.0 | 0.0 |
| nim-v1.14 x c-v0.0.1 (tcp, noise, yamux) | nim-v1.14 | c-v0.0.1 | tcp | noise | yamux | ✅ | 5s | 313.0 | 12.0 |
| nim-v1.14 x dotnet-v1.0 (tcp, noise, yamux) | nim-v1.14 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 5s | 413.0 | 5.0 |
| jvm-v1.2 x rust-v0.53 (tcp, noise, mplex) | jvm-v1.2 | rust-v0.53 | tcp | noise | mplex | ✅ | 15s | - | - |
| jvm-v1.2 x rust-v0.53 (tcp, tls, mplex) | jvm-v1.2 | rust-v0.53 | tcp | tls | mplex | ✅ | 17s | - | - |
| jvm-v1.2 x rust-v0.53 (tcp, noise, yamux) | jvm-v1.2 | rust-v0.53 | tcp | noise | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x rust-v0.53 (tcp, tls, yamux) | jvm-v1.2 | rust-v0.53 | tcp | tls | yamux | ✅ | 17s | - | - |
| jvm-v1.2 x rust-v0.53 (ws, tls, mplex) | jvm-v1.2 | rust-v0.53 | ws | tls | mplex | ✅ | 17s | - | - |
| jvm-v1.2 x rust-v0.53 (ws, noise, mplex) | jvm-v1.2 | rust-v0.53 | ws | noise | mplex | ✅ | 15s | - | - |
| jvm-v1.2 x rust-v0.53 (ws, noise, yamux) | jvm-v1.2 | rust-v0.53 | ws | noise | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x rust-v0.53 (ws, tls, yamux) | jvm-v1.2 | rust-v0.53 | ws | tls | yamux | ✅ | 20s | - | - |
| jvm-v1.2 x rust-v0.53 (quic-v1) | jvm-v1.2 | rust-v0.53 | quic-v1 | - | - | ✅ | 13s | - | - |
| jvm-v1.2 x rust-v0.54 (tcp, noise, mplex) | jvm-v1.2 | rust-v0.54 | tcp | noise | mplex | ✅ | 13s | - | - |
| jvm-v1.2 x rust-v0.54 (tcp, tls, yamux) | jvm-v1.2 | rust-v0.54 | tcp | tls | yamux | ✅ | 14s | - | - |
| jvm-v1.2 x rust-v0.54 (tcp, tls, mplex) | jvm-v1.2 | rust-v0.54 | tcp | tls | mplex | ✅ | 16s | - | - |
| jvm-v1.2 x rust-v0.54 (tcp, noise, yamux) | jvm-v1.2 | rust-v0.54 | tcp | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x rust-v0.54 (ws, noise, mplex) | jvm-v1.2 | rust-v0.54 | ws | noise | mplex | ✅ | 13s | - | - |
| jvm-v1.2 x rust-v0.54 (ws, tls, mplex) | jvm-v1.2 | rust-v0.54 | ws | tls | mplex | ✅ | 15s | - | - |
| jvm-v1.2 x rust-v0.54 (ws, tls, yamux) | jvm-v1.2 | rust-v0.54 | ws | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x rust-v0.54 (ws, noise, yamux) | jvm-v1.2 | rust-v0.54 | ws | noise | yamux | ✅ | 12s | - | - |
| jvm-v1.2 x rust-v0.54 (quic-v1) | jvm-v1.2 | rust-v0.54 | quic-v1 | - | - | ✅ | 14s | - | - |
| jvm-v1.2 x rust-v0.55 (tcp, tls, mplex) | jvm-v1.2 | rust-v0.55 | tcp | tls | mplex | ✅ | 15s | - | - |
| jvm-v1.2 x rust-v0.55 (tcp, noise, mplex) | jvm-v1.2 | rust-v0.55 | tcp | noise | mplex | ✅ | 14s | - | - |
| jvm-v1.2 x rust-v0.55 (tcp, tls, yamux) | jvm-v1.2 | rust-v0.55 | tcp | tls | yamux | ✅ | 16s | - | - |
| jvm-v1.2 x rust-v0.55 (tcp, noise, yamux) | jvm-v1.2 | rust-v0.55 | tcp | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x rust-v0.55 (ws, tls, yamux) | jvm-v1.2 | rust-v0.55 | ws | tls | yamux | ✅ | 14s | - | - |
| jvm-v1.2 x rust-v0.55 (ws, tls, mplex) | jvm-v1.2 | rust-v0.55 | ws | tls | mplex | ✅ | 16s | - | - |
| jvm-v1.2 x rust-v0.55 (ws, noise, mplex) | jvm-v1.2 | rust-v0.55 | ws | noise | mplex | ✅ | 13s | - | - |
| jvm-v1.2 x rust-v0.55 (ws, noise, yamux) | jvm-v1.2 | rust-v0.55 | ws | noise | yamux | ✅ | 12s | - | - |
| jvm-v1.2 x rust-v0.55 (quic-v1) | jvm-v1.2 | rust-v0.55 | quic-v1 | - | - | ✅ | 15s | - | - |
| jvm-v1.2 x rust-v0.56 (tcp, tls, mplex) | jvm-v1.2 | rust-v0.56 | tcp | tls | mplex | ✅ | 15s | - | - |
| jvm-v1.2 x rust-v0.56 (tcp, noise, mplex) | jvm-v1.2 | rust-v0.56 | tcp | noise | mplex | ✅ | 14s | - | - |
| jvm-v1.2 x rust-v0.56 (tcp, tls, yamux) | jvm-v1.2 | rust-v0.56 | tcp | tls | yamux | ✅ | 16s | - | - |
| jvm-v1.2 x rust-v0.56 (tcp, noise, yamux) | jvm-v1.2 | rust-v0.56 | tcp | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x rust-v0.56 (ws, tls, mplex) | jvm-v1.2 | rust-v0.56 | ws | tls | mplex | ✅ | 13s | - | - |
| jvm-v1.2 x rust-v0.56 (ws, noise, mplex) | jvm-v1.2 | rust-v0.56 | ws | noise | mplex | ✅ | 13s | - | - |
| jvm-v1.2 x rust-v0.56 (ws, tls, yamux) | jvm-v1.2 | rust-v0.56 | ws | tls | yamux | ✅ | 14s | - | - |
| jvm-v1.2 x rust-v0.56 (ws, noise, yamux) | jvm-v1.2 | rust-v0.56 | ws | noise | yamux | ✅ | 11s | - | - |
| jvm-v1.2 x go-v0.38 (tcp, noise, yamux) | jvm-v1.2 | go-v0.38 | tcp | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x rust-v0.56 (quic-v1) | jvm-v1.2 | rust-v0.56 | quic-v1 | - | - | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.38 (tcp, tls, yamux) | jvm-v1.2 | go-v0.38 | tcp | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.38 (ws, tls, yamux) | jvm-v1.2 | go-v0.38 | ws | tls | yamux | ✅ | 16s | - | - |
| jvm-v1.2 x go-v0.38 (ws, noise, yamux) | jvm-v1.2 | go-v0.38 | ws | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x go-v0.38 (quic-v1) | jvm-v1.2 | go-v0.38 | quic-v1 | - | - | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.39 (tcp, tls, yamux) | jvm-v1.2 | go-v0.39 | tcp | tls | yamux | ✅ | 16s | - | - |
| jvm-v1.2 x go-v0.39 (tcp, noise, yamux) | jvm-v1.2 | go-v0.39 | tcp | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x go-v0.39 (ws, noise, yamux) | jvm-v1.2 | go-v0.39 | ws | noise | yamux | ✅ | 12s | - | - |
| jvm-v1.2 x go-v0.39 (ws, tls, yamux) | jvm-v1.2 | go-v0.39 | ws | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.39 (quic-v1) | jvm-v1.2 | go-v0.39 | quic-v1 | - | - | ✅ | 14s | - | - |
| jvm-v1.2 x go-v0.40 (tcp, noise, yamux) | jvm-v1.2 | go-v0.40 | tcp | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x go-v0.40 (tcp, tls, yamux) | jvm-v1.2 | go-v0.40 | tcp | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.40 (ws, noise, yamux) | jvm-v1.2 | go-v0.40 | ws | noise | yamux | ✅ | 12s | - | - |
| jvm-v1.2 x go-v0.40 (ws, tls, yamux) | jvm-v1.2 | go-v0.40 | ws | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.40 (quic-v1) | jvm-v1.2 | go-v0.40 | quic-v1 | - | - | ✅ | 14s | - | - |
| jvm-v1.2 x go-v0.41 (tcp, noise, yamux) | jvm-v1.2 | go-v0.41 | tcp | noise | yamux | ✅ | 12s | - | - |
| jvm-v1.2 x go-v0.41 (tcp, tls, yamux) | jvm-v1.2 | go-v0.41 | tcp | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.41 (ws, noise, yamux) | jvm-v1.2 | go-v0.41 | ws | noise | yamux | ✅ | 14s | - | - |
| jvm-v1.2 x go-v0.41 (ws, tls, yamux) | jvm-v1.2 | go-v0.41 | ws | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.41 (quic-v1) | jvm-v1.2 | go-v0.41 | quic-v1 | - | - | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.42 (tcp, noise, yamux) | jvm-v1.2 | go-v0.42 | tcp | noise | yamux | ✅ | 12s | - | - |
| jvm-v1.2 x go-v0.42 (tcp, tls, yamux) | jvm-v1.2 | go-v0.42 | tcp | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.42 (ws, tls, yamux) | jvm-v1.2 | go-v0.42 | ws | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.42 (ws, noise, yamux) | jvm-v1.2 | go-v0.42 | ws | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x go-v0.42 (quic-v1) | jvm-v1.2 | go-v0.42 | quic-v1 | - | - | ✅ | 14s | - | - |
| jvm-v1.2 x go-v0.43 (tcp, noise, yamux) | jvm-v1.2 | go-v0.43 | tcp | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x go-v0.43 (tcp, tls, yamux) | jvm-v1.2 | go-v0.43 | tcp | tls | yamux | ✅ | 16s | - | - |
| jvm-v1.2 x go-v0.43 (ws, tls, yamux) | jvm-v1.2 | go-v0.43 | ws | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.43 (ws, noise, yamux) | jvm-v1.2 | go-v0.43 | ws | noise | yamux | ✅ | 14s | - | - |
| jvm-v1.2 x go-v0.43 (quic-v1) | jvm-v1.2 | go-v0.43 | quic-v1 | - | - | ✅ | 16s | - | - |
| jvm-v1.2 x go-v0.44 (tcp, noise, yamux) | jvm-v1.2 | go-v0.44 | tcp | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x go-v0.44 (tcp, tls, yamux) | jvm-v1.2 | go-v0.44 | tcp | tls | yamux | ✅ | 16s | - | - |
| jvm-v1.2 x go-v0.44 (ws, tls, yamux) | jvm-v1.2 | go-v0.44 | ws | tls | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x go-v0.44 (ws, noise, yamux) | jvm-v1.2 | go-v0.44 | ws | noise | yamux | ✅ | 14s | - | - |
| jvm-v1.2 x go-v0.44 (quic-v1) | jvm-v1.2 | go-v0.44 | quic-v1 | - | - | ✅ | 14s | - | - |
| jvm-v1.2 x go-v0.45 (tcp, noise, yamux) | jvm-v1.2 | go-v0.45 | tcp | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x go-v0.45 (tcp, tls, yamux) | jvm-v1.2 | go-v0.45 | tcp | tls | yamux | ✅ | 16s | - | - |
| jvm-v1.2 x go-v0.45 (ws, noise, yamux) | jvm-v1.2 | go-v0.45 | ws | noise | yamux | ✅ | 13s | - | - |
| jvm-v1.2 x go-v0.45 (ws, tls, yamux) | jvm-v1.2 | go-v0.45 | ws | tls | yamux | ✅ | 17s | - | - |
| jvm-v1.2 x python-v0.4 (tcp, noise, mplex) | jvm-v1.2 | python-v0.4 | tcp | noise | mplex | ❌ | 11s | - | - |
| jvm-v1.2 x python-v0.4 (tcp, noise, yamux) | jvm-v1.2 | python-v0.4 | tcp | noise | yamux | ❌ | 11s | - | - |
| jvm-v1.2 x go-v0.45 (quic-v1) | jvm-v1.2 | go-v0.45 | quic-v1 | - | - | ✅ | 16s | - | - |
| jvm-v1.2 x python-v0.4 (ws, noise, mplex) | jvm-v1.2 | python-v0.4 | ws | noise | mplex | ❌ | 10s | - | - |
| jvm-v1.2 x python-v0.4 (ws, noise, yamux) | jvm-v1.2 | python-v0.4 | ws | noise | yamux | ❌ | 11s | - | - |
| jvm-v1.2 x python-v0.4 (quic-v1) | jvm-v1.2 | python-v0.4 | quic-v1 | - | - | ❌ | 16s | - | - |
| jvm-v1.2 x js-v1.x (tcp, noise, mplex) | jvm-v1.2 | js-v1.x | tcp | noise | mplex | ✅ | 33s | - | - |
| jvm-v1.2 x js-v1.x (tcp, noise, yamux) | jvm-v1.2 | js-v1.x | tcp | noise | yamux | ✅ | 32s | - | - |
| jvm-v1.2 x js-v1.x (ws, noise, mplex) | jvm-v1.2 | js-v1.x | ws | noise | mplex | ✅ | 33s | - | - |
| jvm-v1.2 x js-v1.x (ws, noise, yamux) | jvm-v1.2 | js-v1.x | ws | noise | yamux | ✅ | 33s | - | - |
| jvm-v1.2 x js-v2.x (tcp, noise, mplex) | jvm-v1.2 | js-v2.x | tcp | noise | mplex | ✅ | 33s | - | - |
| jvm-v1.2 x js-v2.x (tcp, noise, yamux) | jvm-v1.2 | js-v2.x | tcp | noise | yamux | ✅ | 32s | - | - |
| jvm-v1.2 x js-v2.x (ws, noise, mplex) | jvm-v1.2 | js-v2.x | ws | noise | mplex | ✅ | 30s | - | - |
| jvm-v1.2 x js-v2.x (ws, noise, yamux) | jvm-v1.2 | js-v2.x | ws | noise | yamux | ✅ | 28s | - | - |
| jvm-v1.2 x nim-v1.14 (tcp, noise, mplex) | jvm-v1.2 | nim-v1.14 | tcp | noise | mplex | ✅ | 15s | - | - |
| jvm-v1.2 x nim-v1.14 (tcp, noise, yamux) | jvm-v1.2 | nim-v1.14 | tcp | noise | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x nim-v1.14 (ws, noise, mplex) | jvm-v1.2 | nim-v1.14 | ws | noise | mplex | ✅ | 16s | - | - |
| jvm-v1.2 x js-v3.x (tcp, noise, mplex) | jvm-v1.2 | js-v3.x | tcp | noise | mplex | ✅ | 26s | - | - |
| jvm-v1.2 x nim-v1.14 (ws, noise, yamux) | jvm-v1.2 | nim-v1.14 | ws | noise | yamux | ✅ | 15s | - | - |
| jvm-v1.2 x js-v3.x (tcp, noise, yamux) | jvm-v1.2 | js-v3.x | tcp | noise | yamux | ✅ | 26s | - | - |
| jvm-v1.2 x js-v3.x (ws, noise, mplex) | jvm-v1.2 | js-v3.x | ws | noise | mplex | ✅ | 26s | - | - |
| jvm-v1.2 x js-v3.x (ws, noise, yamux) | jvm-v1.2 | js-v3.x | ws | noise | yamux | ✅ | 27s | - | - |
| jvm-v1.2 x jvm-v1.2 (tcp, tls, mplex) | jvm-v1.2 | jvm-v1.2 | tcp | tls | mplex | ✅ | 19s | - | - |
| jvm-v1.2 x jvm-v1.2 (tcp, noise, mplex) | jvm-v1.2 | jvm-v1.2 | tcp | noise | mplex | ✅ | 20s | - | - |
| jvm-v1.2 x jvm-v1.2 (tcp, tls, yamux) | jvm-v1.2 | jvm-v1.2 | tcp | tls | yamux | ✅ | 25s | - | - |
| jvm-v1.2 x jvm-v1.2 (tcp, noise, yamux) | jvm-v1.2 | jvm-v1.2 | tcp | noise | yamux | ✅ | 23s | - | - |
| jvm-v1.2 x jvm-v1.2 (ws, noise, mplex) | jvm-v1.2 | jvm-v1.2 | ws | noise | mplex | ✅ | 23s | - | - |
| jvm-v1.2 x jvm-v1.2 (ws, noise, yamux) | jvm-v1.2 | jvm-v1.2 | ws | noise | yamux | ✅ | 24s | - | - |
| jvm-v1.2 x jvm-v1.2 (ws, tls, mplex) | jvm-v1.2 | jvm-v1.2 | ws | tls | mplex | ✅ | 30s | - | - |
| jvm-v1.2 x jvm-v1.2 (ws, tls, yamux) | jvm-v1.2 | jvm-v1.2 | ws | tls | yamux | ✅ | 29s | - | - |
| jvm-v1.2 x jvm-v1.2 (quic-v1) | jvm-v1.2 | jvm-v1.2 | quic-v1 | - | - | ✅ | 20s | - | - |
| jvm-v1.2 x c-v0.0.1 (tcp, noise, yamux) | jvm-v1.2 | c-v0.0.1 | tcp | noise | yamux | ❌ | 12s | - | - |
| jvm-v1.2 x c-v0.0.1 (tcp, noise, mplex) | jvm-v1.2 | c-v0.0.1 | tcp | noise | mplex | ✅ | 16s | - | - |
| c-v0.0.1 x rust-v0.53 (tcp, noise, mplex) | c-v0.0.1 | rust-v0.53 | tcp | noise | mplex | ✅ | 6s | 33.000 | 0.000 |
| jvm-v1.2 x c-v0.0.1 (quic-v1) | jvm-v1.2 | c-v0.0.1 | quic-v1 | - | - | ✅ | 17s | - | - |
| jvm-v1.2 x dotnet-v1.0 (tcp, noise, yamux) | jvm-v1.2 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 14s | - | - |
| c-v0.0.1 x rust-v0.53 (tcp, noise, yamux) | c-v0.0.1 | rust-v0.53 | tcp | noise | yamux | ✅ | 6s | 65.000 | 0.000 |
| jvm-v1.2 x zig-v0.0.1 (quic-v1) | jvm-v1.2 | zig-v0.0.1 | quic-v1 | - | - | ❌ | 13s | - | - |
| c-v0.0.1 x rust-v0.54 (tcp, noise, mplex) | c-v0.0.1 | rust-v0.54 | tcp | noise | mplex | ✅ | 5s | 51.000 | 0.000 |
| c-v0.0.1 x rust-v0.53 (quic-v1) | c-v0.0.1 | rust-v0.53 | quic-v1 | - | - | ✅ | 7s | 59.000 | 1.000 |
| c-v0.0.1 x rust-v0.54 (tcp, noise, yamux) | c-v0.0.1 | rust-v0.54 | tcp | noise | yamux | ✅ | 5s | 57.000 | 0.000 |
| jvm-v1.2 x eth-p2p-z-v0.0.1 (quic-v1) | jvm-v1.2 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 15s | - | - |
| c-v0.0.1 x rust-v0.55 (tcp, noise, mplex) | c-v0.0.1 | rust-v0.55 | tcp | noise | mplex | ✅ | 4s | 9.000 | 0.000 |
| c-v0.0.1 x rust-v0.55 (tcp, noise, yamux) | c-v0.0.1 | rust-v0.55 | tcp | noise | yamux | ✅ | 4s | 58.000 | 0.000 |
| c-v0.0.1 x rust-v0.54 (quic-v1) | c-v0.0.1 | rust-v0.54 | quic-v1 | - | - | ✅ | 7s | 20.000 | 0.000 |
| c-v0.0.1 x rust-v0.56 (tcp, noise, mplex) | c-v0.0.1 | rust-v0.56 | tcp | noise | mplex | ✅ | 4s | 13.000 | 0.000 |
| c-v0.0.1 x rust-v0.56 (tcp, noise, yamux) | c-v0.0.1 | rust-v0.56 | tcp | noise | yamux | ✅ | 4s | 60.000 | 0.000 |
| c-v0.0.1 x rust-v0.55 (quic-v1) | c-v0.0.1 | rust-v0.55 | quic-v1 | - | - | ✅ | 6s | 15.000 | 0.000 |
| c-v0.0.1 x rust-v0.56 (quic-v1) | c-v0.0.1 | rust-v0.56 | quic-v1 | - | - | ✅ | 6s | 21.000 | 1.000 |
| c-v0.0.1 x go-v0.38 (tcp, noise, yamux) | c-v0.0.1 | go-v0.38 | tcp | noise | yamux | ✅ | 5s | 115.000 | 0.000 |
| c-v0.0.1 x go-v0.39 (tcp, noise, yamux) | c-v0.0.1 | go-v0.39 | tcp | noise | yamux | ✅ | 4s | 110.000 | 1.000 |
| c-v0.0.1 x go-v0.40 (tcp, noise, yamux) | c-v0.0.1 | go-v0.40 | tcp | noise | yamux | ✅ | 4s | 119.000 | 0.000 |
| c-v0.0.1 x go-v0.41 (tcp, noise, yamux) | c-v0.0.1 | go-v0.41 | tcp | noise | yamux | ✅ | 4s | 120.000 | 1.000 |
| c-v0.0.1 x go-v0.42 (tcp, noise, yamux) | c-v0.0.1 | go-v0.42 | tcp | noise | yamux | ✅ | 4s | 121.000 | 1.000 |
| c-v0.0.1 x go-v0.43 (tcp, noise, yamux) | c-v0.0.1 | go-v0.43 | tcp | noise | yamux | ✅ | 5s | 121.000 | 0.000 |
| c-v0.0.1 x go-v0.44 (tcp, noise, yamux) | c-v0.0.1 | go-v0.44 | tcp | noise | yamux | ✅ | 6s | 139.000 | 4.000 |
| c-v0.0.1 x go-v0.38 (quic-v1) | c-v0.0.1 | go-v0.38 | quic-v1 | - | - | ✅ | 20s | 124.000 | 0.000 |
| c-v0.0.1 x go-v0.39 (quic-v1) | c-v0.0.1 | go-v0.39 | quic-v1 | - | - | ✅ | 20s | 104.000 | 1.000 |
| c-v0.0.1 x go-v0.40 (quic-v1) | c-v0.0.1 | go-v0.40 | quic-v1 | - | - | ✅ | 19s | 147.000 | 1.000 |
| c-v0.0.1 x go-v0.41 (quic-v1) | c-v0.0.1 | go-v0.41 | quic-v1 | - | - | ✅ | 19s | 168.000 | 0.000 |
| c-v0.0.1 x go-v0.45 (tcp, noise, yamux) | c-v0.0.1 | go-v0.45 | tcp | noise | yamux | ✅ | 6s | 128.000 | 1.000 |
| c-v0.0.1 x python-v0.4 (tcp, noise, mplex) | c-v0.0.1 | python-v0.4 | tcp | noise | mplex | ✅ | 6s | 31.000 | 1.000 |
| c-v0.0.1 x go-v0.43 (quic-v1) | c-v0.0.1 | go-v0.43 | quic-v1 | - | - | ✅ | 20s | 193.000 | 1.000 |
| c-v0.0.1 x python-v0.4 (tcp, noise, yamux) | c-v0.0.1 | python-v0.4 | tcp | noise | yamux | ✅ | 6s | 228.000 | 2.000 |
| c-v0.0.1 x go-v0.44 (quic-v1) | c-v0.0.1 | go-v0.44 | quic-v1 | - | - | ✅ | 21s | 194.000 | 1.000 |
| c-v0.0.1 x python-v0.4 (quic-v1) | c-v0.0.1 | python-v0.4 | quic-v1 | - | - | ❌ | 16s | - | - |
| c-v0.0.1 x go-v0.45 (quic-v1) | c-v0.0.1 | go-v0.45 | quic-v1 | - | - | ✅ | 21s | 146.000 | 5.000 |
| c-v0.0.1 x js-v1.x (tcp, noise, mplex) | c-v0.0.1 | js-v1.x | tcp | noise | mplex | ✅ | 20s | 130.000 | 5.000 |
| c-v0.0.1 x nim-v1.14 (tcp, noise, mplex) | c-v0.0.1 | nim-v1.14 | tcp | noise | mplex | ✅ | 5s | 86.000 | 1.000 |
| c-v0.0.1 x js-v1.x (tcp, noise, yamux) | c-v0.0.1 | js-v1.x | tcp | noise | yamux | ✅ | 21s | 378.000 | 2.000 |
| c-v0.0.1 x js-v2.x (tcp, noise, mplex) | c-v0.0.1 | js-v2.x | tcp | noise | mplex | ✅ | 20s | 115.000 | 3.000 |
| c-v0.0.1 x js-v2.x (tcp, noise, yamux) | c-v0.0.1 | js-v2.x | tcp | noise | yamux | ✅ | 22s | 377.000 | 2.000 |
| c-v0.0.1 x nim-v1.14 (tcp, noise, yamux) | c-v0.0.1 | nim-v1.14 | tcp | noise | yamux | ✅ | 6s | 275.000 | 3.000 |
| c-v0.0.1 x js-v3.x (tcp, noise, mplex) | c-v0.0.1 | js-v3.x | tcp | noise | mplex | ✅ | 21s | 171.000 | 13.000 |
| c-v0.0.1 x jvm-v1.2 (tcp, noise, mplex) | c-v0.0.1 | jvm-v1.2 | tcp | noise | mplex | ✅ | 11s | 1385.000 | 7.000 |
| c-v0.0.1 x c-v0.0.1 (tcp, noise, mplex) | c-v0.0.1 | c-v0.0.1 | tcp | noise | mplex | ✅ | 6s | 23.000 | 0.000 |
| c-v0.0.1 x c-v0.0.1 (tcp, noise, yamux) | c-v0.0.1 | c-v0.0.1 | tcp | noise | yamux | ✅ | 6s | 386.000 | 1.000 |
| c-v0.0.1 x jvm-v1.2 (tcp, noise, yamux) | c-v0.0.1 | jvm-v1.2 | tcp | noise | yamux | ❌ | 11s | - | - |
| c-v0.0.1 x js-v3.x (tcp, noise, yamux) | c-v0.0.1 | js-v3.x | tcp | noise | yamux | ✅ | 21s | 311.000 | 3.000 |
| c-v0.0.1 x c-v0.0.1 (quic-v1) | c-v0.0.1 | c-v0.0.1 | quic-v1 | - | - | ✅ | 5s | 78.000 | 20.000 |
| c-v0.0.1 x jvm-v1.2 (quic-v1) | c-v0.0.1 | jvm-v1.2 | quic-v1 | - | - | ✅ | 13s | 2080.000 | 3.000 |
| c-v0.0.1 x dotnet-v1.0 (tcp, noise, yamux) | c-v0.0.1 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 4s | 483.000 | 7.000 |
| c-v0.0.1 x eth-p2p-z-v0.0.1 (quic-v1) | c-v0.0.1 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 4s | 126.000 | 1.000 |
| dotnet-v1.0 x rust-v0.53 (tcp, noise, yamux) | dotnet-v1.0 | rust-v0.53 | tcp | noise | yamux | ✅ | 5s | - | - |
| dotnet-v1.0 x rust-v0.54 (tcp, noise, yamux) | dotnet-v1.0 | rust-v0.54 | tcp | noise | yamux | ✅ | 5s | - | - |
| dotnet-v1.0 x rust-v0.55 (tcp, noise, yamux) | dotnet-v1.0 | rust-v0.55 | tcp | noise | yamux | ✅ | 5s | - | - |
| dotnet-v1.0 x rust-v0.56 (tcp, noise, yamux) | dotnet-v1.0 | rust-v0.56 | tcp | noise | yamux | ✅ | 5s | - | - |
| dotnet-v1.0 x go-v0.38 (tcp, noise, yamux) | dotnet-v1.0 | go-v0.38 | tcp | noise | yamux | ✅ | 5s | - | - |
| dotnet-v1.0 x go-v0.39 (tcp, noise, yamux) | dotnet-v1.0 | go-v0.39 | tcp | noise | yamux | ✅ | 5s | - | - |
| dotnet-v1.0 x go-v0.40 (tcp, noise, yamux) | dotnet-v1.0 | go-v0.40 | tcp | noise | yamux | ✅ | 5s | - | - |
| dotnet-v1.0 x go-v0.41 (tcp, noise, yamux) | dotnet-v1.0 | go-v0.41 | tcp | noise | yamux | ✅ | 5s | - | - |
| dotnet-v1.0 x go-v0.42 (tcp, noise, yamux) | dotnet-v1.0 | go-v0.42 | tcp | noise | yamux | ✅ | 5s | - | - |
| dotnet-v1.0 x go-v0.43 (tcp, noise, yamux) | dotnet-v1.0 | go-v0.43 | tcp | noise | yamux | ✅ | 6s | - | - |
| dotnet-v1.0 x go-v0.44 (tcp, noise, yamux) | dotnet-v1.0 | go-v0.44 | tcp | noise | yamux | ✅ | 5s | - | - |
| dotnet-v1.0 x go-v0.45 (tcp, noise, yamux) | dotnet-v1.0 | go-v0.45 | tcp | noise | yamux | ✅ | 5s | - | - |
| dotnet-v1.0 x python-v0.4 (tcp, noise, yamux) | dotnet-v1.0 | python-v0.4 | tcp | noise | yamux | ✅ | 5s | - | - |
| c-v0.0.1 x zig-v0.0.1 (quic-v1) | c-v0.0.1 | zig-v0.0.1 | quic-v1 | - | - | ❌ | 20s | - | - |
| dotnet-v1.0 x nim-v1.14 (tcp, noise, yamux) | dotnet-v1.0 | nim-v1.14 | tcp | noise | yamux | ✅ | 7s | - | - |
| dotnet-v1.0 x c-v0.0.1 (tcp, noise, yamux) | dotnet-v1.0 | c-v0.0.1 | tcp | noise | yamux | ✅ | 7s | - | - |
| dotnet-v1.0 x jvm-v1.2 (tcp, noise, yamux) | dotnet-v1.0 | jvm-v1.2 | tcp | noise | yamux | ✅ | 10s | - | - |
| dotnet-v1.0 x dotnet-v1.0 (tcp, noise, yamux) | dotnet-v1.0 | dotnet-v1.0 | tcp | noise | yamux | ✅ | 8s | - | - |
| dotnet-v1.0 x js-v1.x (tcp, noise, yamux) | dotnet-v1.0 | js-v1.x | tcp | noise | yamux | ❌ | 16s | - | - |
| dotnet-v1.0 x js-v2.x (tcp, noise, yamux) | dotnet-v1.0 | js-v2.x | tcp | noise | yamux | ❌ | 15s | - | - |
| zig-v0.0.1 x rust-v0.53 (quic-v1) | zig-v0.0.1 | rust-v0.53 | quic-v1 | - | - | ✅ | 6s | - | - |
| dotnet-v1.0 x js-v3.x (tcp, noise, yamux) | dotnet-v1.0 | js-v3.x | tcp | noise | yamux | ❌ | 16s | - | - |
| zig-v0.0.1 x rust-v0.54 (quic-v1) | zig-v0.0.1 | rust-v0.54 | quic-v1 | - | - | ✅ | 4s | - | - |
| zig-v0.0.1 x rust-v0.55 (quic-v1) | zig-v0.0.1 | rust-v0.55 | quic-v1 | - | - | ✅ | 3s | - | - |
| zig-v0.0.1 x rust-v0.56 (quic-v1) | zig-v0.0.1 | rust-v0.56 | quic-v1 | - | - | ✅ | 4s | - | - |
| zig-v0.0.1 x go-v0.38 (quic-v1) | zig-v0.0.1 | go-v0.38 | quic-v1 | - | - | ✅ | 4s | - | - |
| zig-v0.0.1 x go-v0.39 (quic-v1) | zig-v0.0.1 | go-v0.39 | quic-v1 | - | - | ✅ | 5s | - | - |
| zig-v0.0.1 x go-v0.40 (quic-v1) | zig-v0.0.1 | go-v0.40 | quic-v1 | - | - | ✅ | 4s | - | - |
| zig-v0.0.1 x go-v0.41 (quic-v1) | zig-v0.0.1 | go-v0.41 | quic-v1 | - | - | ✅ | 5s | - | - |
| zig-v0.0.1 x go-v0.42 (quic-v1) | zig-v0.0.1 | go-v0.42 | quic-v1 | - | - | ✅ | 4s | - | - |
| zig-v0.0.1 x go-v0.43 (quic-v1) | zig-v0.0.1 | go-v0.43 | quic-v1 | - | - | ✅ | 5s | - | - |
| zig-v0.0.1 x go-v0.44 (quic-v1) | zig-v0.0.1 | go-v0.44 | quic-v1 | - | - | ✅ | 4s | - | - |
| zig-v0.0.1 x go-v0.45 (quic-v1) | zig-v0.0.1 | go-v0.45 | quic-v1 | - | - | ✅ | 5s | - | - |
| zig-v0.0.1 x zig-v0.0.1 (quic-v1) | zig-v0.0.1 | zig-v0.0.1 | quic-v1 | - | - | ✅ | 4s | - | - |
| zig-v0.0.1 x eth-p2p-z-v0.0.1 (quic-v1) | zig-v0.0.1 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 4s | - | - |
| eth-p2p-z-v0.0.1 x rust-v0.53 (quic-v1) | eth-p2p-z-v0.0.1 | rust-v0.53 | quic-v1 | - | - | ✅ | 3s | - | - |
| eth-p2p-z-v0.0.1 x rust-v0.54 (quic-v1) | eth-p2p-z-v0.0.1 | rust-v0.54 | quic-v1 | - | - | ✅ | 4s | - | - |
| zig-v0.0.1 x jvm-v1.2 (quic-v1) | zig-v0.0.1 | jvm-v1.2 | quic-v1 | - | - | ✅ | 8s | - | - |
| eth-p2p-z-v0.0.1 x rust-v0.55 (quic-v1) | eth-p2p-z-v0.0.1 | rust-v0.55 | quic-v1 | - | - | ✅ | 3s | - | - |
| eth-p2p-z-v0.0.1 x rust-v0.56 (quic-v1) | eth-p2p-z-v0.0.1 | rust-v0.56 | quic-v1 | - | - | ✅ | 3s | - | - |
| eth-p2p-z-v0.0.1 x go-v0.38 (quic-v1) | eth-p2p-z-v0.0.1 | go-v0.38 | quic-v1 | - | - | ✅ | 3s | - | - |
| eth-p2p-z-v0.0.1 x go-v0.40 (quic-v1) | eth-p2p-z-v0.0.1 | go-v0.40 | quic-v1 | - | - | ✅ | 3s | - | - |
| eth-p2p-z-v0.0.1 x go-v0.39 (quic-v1) | eth-p2p-z-v0.0.1 | go-v0.39 | quic-v1 | - | - | ✅ | 4s | - | - |
| zig-v0.0.1 x python-v0.4 (quic-v1) | zig-v0.0.1 | python-v0.4 | quic-v1 | - | - | ✅ | 14s | - | - |
| eth-p2p-z-v0.0.1 x go-v0.41 (quic-v1) | eth-p2p-z-v0.0.1 | go-v0.41 | quic-v1 | - | - | ✅ | 3s | - | - |
| eth-p2p-z-v0.0.1 x go-v0.42 (quic-v1) | eth-p2p-z-v0.0.1 | go-v0.42 | quic-v1 | - | - | ✅ | 4s | - | - |
| zig-v0.0.1 x c-v0.0.1 (quic-v1) | zig-v0.0.1 | c-v0.0.1 | quic-v1 | - | - | ❌ | 15s | - | - |
| eth-p2p-z-v0.0.1 x go-v0.43 (quic-v1) | eth-p2p-z-v0.0.1 | go-v0.43 | quic-v1 | - | - | ✅ | 4s | - | - |
| eth-p2p-z-v0.0.1 x go-v0.44 (quic-v1) | eth-p2p-z-v0.0.1 | go-v0.44 | quic-v1 | - | - | ✅ | 4s | - | - |
| eth-p2p-z-v0.0.1 x go-v0.45 (quic-v1) | eth-p2p-z-v0.0.1 | go-v0.45 | quic-v1 | - | - | ✅ | 4s | - | - |
| eth-p2p-z-v0.0.1 x python-v0.4 (quic-v1) | eth-p2p-z-v0.0.1 | python-v0.4 | quic-v1 | - | - | ✅ | 5s | - | - |
| eth-p2p-z-v0.0.1 x c-v0.0.1 (quic-v1) | eth-p2p-z-v0.0.1 | c-v0.0.1 | quic-v1 | - | - | ✅ | 4s | - | - |
| eth-p2p-z-v0.0.1 x eth-p2p-z-v0.0.1 (quic-v1) | eth-p2p-z-v0.0.1 | eth-p2p-z-v0.0.1 | quic-v1 | - | - | ✅ | 5s | - | - |
| eth-p2p-z-v0.0.1 x jvm-v1.2 (quic-v1) | eth-p2p-z-v0.0.1 | jvm-v1.2 | quic-v1 | - | - | ✅ | 9s | - | - |
| chromium-js-v1.x x rust-v0.53 (webrtc-direct) | chromium-js-v1.x | rust-v0.53 | webrtc-direct | - | - | ✅ | 25s | 364 | 44 |
| chromium-js-v1.x x rust-v0.54 (webrtc-direct) | chromium-js-v1.x | rust-v0.54 | webrtc-direct | - | - | ✅ | 24s | 370 | 37 |
| chromium-js-v1.x x rust-v0.55 (webrtc-direct) | chromium-js-v1.x | rust-v0.55 | webrtc-direct | - | - | ✅ | 23s | 294 | 18 |
| chromium-js-v1.x x rust-v0.56 (webrtc-direct) | chromium-js-v1.x | rust-v0.56 | webrtc-direct | - | - | ✅ | 23s | 305 | 24 |
| chromium-js-v1.x x go-v0.38 (webtransport) | chromium-js-v1.x | go-v0.38 | webtransport | - | - | ✅ | 22s | 155 | 35 |
| chromium-js-v1.x x go-v0.38 (wss, noise, yamux) | chromium-js-v1.x | go-v0.38 | wss | noise | yamux | ✅ | 22s | 237 | 52 |
| chromium-js-v1.x x go-v0.38 (webrtc-direct) | chromium-js-v1.x | go-v0.38 | webrtc-direct | - | - | ✅ | 23s | 242 | 50 |
| chromium-js-v1.x x go-v0.39 (webtransport) | chromium-js-v1.x | go-v0.39 | webtransport | - | - | ✅ | 22s | 204 | 58 |
| chromium-js-v1.x x go-v0.39 (wss, noise, yamux) | chromium-js-v1.x | go-v0.39 | wss | noise | yamux | ✅ | 23s | 298 | 68 |
| chromium-js-v1.x x go-v0.39 (webrtc-direct) | chromium-js-v1.x | go-v0.39 | webrtc-direct | - | - | ✅ | 23s | 252 | 30 |
| chromium-js-v1.x x go-v0.40 (webtransport) | chromium-js-v1.x | go-v0.40 | webtransport | - | - | ✅ | 22s | 129 | 30 |
| chromium-js-v1.x x go-v0.40 (wss, noise, yamux) | chromium-js-v1.x | go-v0.40 | wss | noise | yamux | ✅ | 21s | 167 | 47 |
| chromium-js-v1.x x go-v0.40 (webrtc-direct) | chromium-js-v1.x | go-v0.40 | webrtc-direct | - | - | ✅ | 22s | 320 | 54 |
| chromium-js-v1.x x go-v0.41 (webtransport) | chromium-js-v1.x | go-v0.41 | webtransport | - | - | ✅ | 23s | 166 | 46 |
| chromium-js-v1.x x go-v0.41 (wss, noise, yamux) | chromium-js-v1.x | go-v0.41 | wss | noise | yamux | ✅ | 22s | 260 | 60 |
| chromium-js-v1.x x go-v0.41 (webrtc-direct) | chromium-js-v1.x | go-v0.41 | webrtc-direct | - | - | ✅ | 23s | 243 | 24 |
| chromium-js-v1.x x go-v0.42 (webtransport) | chromium-js-v1.x | go-v0.42 | webtransport | - | - | ✅ | 22s | 150 | 39 |
| chromium-js-v1.x x go-v0.42 (wss, noise, yamux) | chromium-js-v1.x | go-v0.42 | wss | noise | yamux | ✅ | 22s | 135 | 35 |
| c-v0.0.1 x go-v0.42 (quic-v1) | c-v0.0.1 | go-v0.42 | quic-v1 | - | - | ❌ | 194s | - | - |
| chromium-js-v1.x x go-v0.42 (webrtc-direct) | chromium-js-v1.x | go-v0.42 | webrtc-direct | - | - | ✅ | 22s | 315 | 60 |
| chromium-js-v1.x x go-v0.43 (webtransport) | chromium-js-v1.x | go-v0.43 | webtransport | - | - | ✅ | 23s | 241 | 70 |
| chromium-js-v1.x x go-v0.43 (wss, noise, yamux) | chromium-js-v1.x | go-v0.43 | wss | noise | yamux | ✅ | 22s | 321 | 86 |
| chromium-js-v1.x x go-v0.43 (webrtc-direct) | chromium-js-v1.x | go-v0.43 | webrtc-direct | - | - | ✅ | 23s | 272 | 50 |
| chromium-js-v1.x x go-v0.44 (webtransport) | chromium-js-v1.x | go-v0.44 | webtransport | - | - | ✅ | 22s | 173 | 47 |
| chromium-js-v1.x x go-v0.44 (wss, noise, yamux) | chromium-js-v1.x | go-v0.44 | wss | noise | yamux | ✅ | 22s | 188 | 34 |
| chromium-js-v1.x x go-v0.44 (webrtc-direct) | chromium-js-v1.x | go-v0.44 | webrtc-direct | - | - | ✅ | 21s | 320 | 62 |
| chromium-js-v1.x x go-v0.45 (webtransport) | chromium-js-v1.x | go-v0.45 | webtransport | - | - | ✅ | 27s | 326 | 73 |
| chromium-js-v1.x x go-v0.45 (wss, noise, yamux) | chromium-js-v1.x | go-v0.45 | wss | noise | yamux | ✅ | 27s | 448 | 111 |
| chromium-js-v1.x x python-v0.4 (wss, noise, mplex) | chromium-js-v1.x | python-v0.4 | wss | noise | mplex | ✅ | 27s | 337 | 71 |
| chromium-js-v1.x x go-v0.45 (webrtc-direct) | chromium-js-v1.x | go-v0.45 | webrtc-direct | - | - | ✅ | 28s | 425 | 73 |
| chromium-js-v1.x x python-v0.4 (wss, noise, yamux) | chromium-js-v1.x | python-v0.4 | wss | noise | yamux | ✅ | 28s | 390 | 90 |
| chromium-js-v1.x x chromium-js-v1.x (webrtc) | chromium-js-v1.x | chromium-js-v1.x | webrtc | - | - | ✅ | 29s | 620 | 54 |
| chromium-js-v1.x x chromium-js-v2.x (webrtc) | chromium-js-v1.x | chromium-js-v2.x | webrtc | - | - | ✅ | 33s | 1524 | 147 |
| chromium-js-v1.x x webkit-js-v1.x (webrtc) | chromium-js-v1.x | webkit-js-v1.x | webrtc | - | - | ✅ | 38s | 1148 | 70 |
| chromium-js-v2.x x rust-v0.53 (webrtc-direct) | chromium-js-v2.x | rust-v0.53 | webrtc-direct | - | - | ✅ | 38s | 408 | 44 |
| chromium-js-v1.x x webkit-js-v2.x (webrtc) | chromium-js-v1.x | webkit-js-v2.x | webrtc | - | - | ✅ | 39s | 920 | 34 |
| chromium-js-v2.x x rust-v0.54 (webrtc-direct) | chromium-js-v2.x | rust-v0.54 | webrtc-direct | - | - | ✅ | 36s | 334 | 51 |
| chromium-js-v1.x x firefox-js-v1.x (webrtc) | chromium-js-v1.x | firefox-js-v1.x | webrtc | - | - | ✅ | 43s | 830 | 111 |
| chromium-js-v1.x x firefox-js-v2.x (webrtc) | chromium-js-v1.x | firefox-js-v2.x | webrtc | - | - | ✅ | 42s | 981 | 59 |
| chromium-js-v2.x x rust-v0.55 (webrtc-direct) | chromium-js-v2.x | rust-v0.55 | webrtc-direct | - | - | ✅ | 29s | 329 | 33 |
| chromium-js-v2.x x rust-v0.56 (webrtc-direct) | chromium-js-v2.x | rust-v0.56 | webrtc-direct | - | - | ✅ | 25s | 391 | 77 |
| chromium-js-v2.x x go-v0.38 (webtransport) | chromium-js-v2.x | go-v0.38 | webtransport | - | - | ✅ | 25s | 226 | 61 |
| chromium-js-v2.x x go-v0.38 (wss, noise, yamux) | chromium-js-v2.x | go-v0.38 | wss | noise | yamux | ✅ | 25s | 315 | 84 |
| chromium-js-v2.x x go-v0.38 (webrtc-direct) | chromium-js-v2.x | go-v0.38 | webrtc-direct | - | - | ✅ | 25s | 251 | 49 |
| chromium-js-v2.x x go-v0.39 (webtransport) | chromium-js-v2.x | go-v0.39 | webtransport | - | - | ✅ | 24s | 122 | 28 |
| eth-p2p-z-v0.0.1 x zig-v0.0.1 (quic-v1) | eth-p2p-z-v0.0.1 | zig-v0.0.1 | quic-v1 | - | - | ❌ | 194s | - | - |
| chromium-js-v2.x x go-v0.39 (wss, noise, yamux) | chromium-js-v2.x | go-v0.39 | wss | noise | yamux | ✅ | 24s | 225 | 73 |
| chromium-js-v2.x x go-v0.39 (webrtc-direct) | chromium-js-v2.x | go-v0.39 | webrtc-direct | - | - | ✅ | 24s | 291 | 79 |
| chromium-js-v2.x x go-v0.40 (webtransport) | chromium-js-v2.x | go-v0.40 | webtransport | - | - | ✅ | 28s | 322 | 72 |
| chromium-js-v2.x x go-v0.40 (wss, noise, yamux) | chromium-js-v2.x | go-v0.40 | wss | noise | yamux | ✅ | 29s | 372 | 107 |
| chromium-js-v2.x x go-v0.40 (webrtc-direct) | chromium-js-v2.x | go-v0.40 | webrtc-direct | - | - | ✅ | 30s | 384 | 82 |
| chromium-js-v2.x x go-v0.41 (webtransport) | chromium-js-v2.x | go-v0.41 | webtransport | - | - | ✅ | 29s | 240 | 59 |
| chromium-js-v2.x x go-v0.41 (wss, noise, yamux) | chromium-js-v2.x | go-v0.41 | wss | noise | yamux | ✅ | 29s | 315 | 98 |
| chromium-js-v2.x x go-v0.42 (webtransport) | chromium-js-v2.x | go-v0.42 | webtransport | - | - | ✅ | 28s | 161 | 40 |
| chromium-js-v2.x x go-v0.41 (webrtc-direct) | chromium-js-v2.x | go-v0.41 | webrtc-direct | - | - | ✅ | 29s | 198 | 39 |
| chromium-js-v2.x x go-v0.42 (wss, noise, yamux) | chromium-js-v2.x | go-v0.42 | wss | noise | yamux | ✅ | 25s | 181 | 46 |
| chromium-js-v2.x x go-v0.42 (webrtc-direct) | chromium-js-v2.x | go-v0.42 | webrtc-direct | - | - | ✅ | 28s | 314 | 46 |
| chromium-js-v2.x x go-v0.43 (webtransport) | chromium-js-v2.x | go-v0.43 | webtransport | - | - | ✅ | 28s | 267 | 65 |
| chromium-js-v2.x x go-v0.44 (webtransport) | chromium-js-v2.x | go-v0.44 | webtransport | - | - | ✅ | 28s | 289 | 76 |
| chromium-js-v2.x x go-v0.43 (webrtc-direct) | chromium-js-v2.x | go-v0.43 | webrtc-direct | - | - | ✅ | 29s | 306 | 57 |
| chromium-js-v2.x x go-v0.43 (wss, noise, yamux) | chromium-js-v2.x | go-v0.43 | wss | noise | yamux | ✅ | 30s | 297 | 77 |
| chromium-js-v2.x x go-v0.44 (wss, noise, yamux) | chromium-js-v2.x | go-v0.44 | wss | noise | yamux | ✅ | 29s | 229 | 70 |
| chromium-js-v2.x x go-v0.44 (webrtc-direct) | chromium-js-v2.x | go-v0.44 | webrtc-direct | - | - | ✅ | 29s | 252 | 28 |
| chromium-js-v2.x x go-v0.45 (webtransport) | chromium-js-v2.x | go-v0.45 | webtransport | - | - | ✅ | 28s | 151 | 43 |
| chromium-js-v2.x x go-v0.45 (wss, noise, yamux) | chromium-js-v2.x | go-v0.45 | wss | noise | yamux | ✅ | 38s | 382 | 137 |
| chromium-js-v2.x x python-v0.4 (wss, noise, mplex) | chromium-js-v2.x | python-v0.4 | wss | noise | mplex | ✅ | 40s | 365 | 67 |
| chromium-js-v2.x x go-v0.45 (webrtc-direct) | chromium-js-v2.x | go-v0.45 | webrtc-direct | - | - | ✅ | 42s | 499 | 113 |
| chromium-js-v2.x x python-v0.4 (wss, noise, yamux) | chromium-js-v2.x | python-v0.4 | wss | noise | yamux | ✅ | 41s | 412 | 114 |
| chromium-js-v2.x x chromium-js-v1.x (webrtc) | chromium-js-v2.x | chromium-js-v1.x | webrtc | - | - | ✅ | 43s | 888 | 130 |
| chromium-js-v2.x x chromium-js-v2.x (webrtc) | chromium-js-v2.x | chromium-js-v2.x | webrtc | - | - | ✅ | 43s | 788 | 85 |
| chromium-js-v2.x x firefox-js-v1.x (webrtc) | chromium-js-v2.x | firefox-js-v1.x | webrtc | - | - | ✅ | 45s | 1200 | 164 |
| chromium-js-v2.x x firefox-js-v2.x (webrtc) | chromium-js-v2.x | firefox-js-v2.x | webrtc | - | - | ✅ | 48s | 1430 | 144 |
| chromium-js-v2.x x webkit-js-v1.x (webrtc) | chromium-js-v2.x | webkit-js-v1.x | webrtc | - | - | ✅ | 34s | 1706 | 191 |
| chromium-js-v2.x x webkit-js-v2.x (webrtc) | chromium-js-v2.x | webkit-js-v2.x | webrtc | - | - | ✅ | 37s | 1260 | 136 |
| firefox-js-v1.x x rust-v0.53 (webrtc-direct) | firefox-js-v1.x | rust-v0.53 | webrtc-direct | - | - | ✅ | 39s | 1611 | 49 |
| firefox-js-v1.x x rust-v0.54 (webrtc-direct) | firefox-js-v1.x | rust-v0.54 | webrtc-direct | - | - | ✅ | 39s | 1467 | 59 |
| firefox-js-v1.x x go-v0.38 (webtransport) | firefox-js-v1.x | go-v0.38 | webtransport | - | - | ❌ | 34s | - | - |
| firefox-js-v1.x x rust-v0.56 (webrtc-direct) | firefox-js-v1.x | rust-v0.56 | webrtc-direct | - | - | ✅ | 38s | 1442 | 64 |
| firefox-js-v1.x x rust-v0.55 (webrtc-direct) | firefox-js-v1.x | rust-v0.55 | webrtc-direct | - | - | ✅ | 40s | 1550 | 80 |
| firefox-js-v1.x x go-v0.38 (wss, noise, yamux) | firefox-js-v1.x | go-v0.38 | wss | noise | yamux | ✅ | 34s | 193 | 102 |
| firefox-js-v1.x x go-v0.38 (webrtc-direct) | firefox-js-v1.x | go-v0.38 | webrtc-direct | - | - | ✅ | 30s | 473 | 75 |
| firefox-js-v1.x x go-v0.39 (webtransport) | firefox-js-v1.x | go-v0.39 | webtransport | - | - | ❌ | 30s | - | - |
| firefox-js-v1.x x go-v0.39 (wss, noise, yamux) | firefox-js-v1.x | go-v0.39 | wss | noise | yamux | ✅ | 32s | 293 | 120 |
| firefox-js-v1.x x go-v0.39 (webrtc-direct) | firefox-js-v1.x | go-v0.39 | webrtc-direct | - | - | ✅ | 32s | 352 | 96 |
| firefox-js-v1.x x go-v0.40 (webtransport) | firefox-js-v1.x | go-v0.40 | webtransport | - | - | ❌ | 32s | - | - |
| firefox-js-v1.x x go-v0.40 (webrtc-direct) | firefox-js-v1.x | go-v0.40 | webrtc-direct | - | - | ✅ | 32s | 322 | 79 |
| firefox-js-v1.x x go-v0.40 (wss, noise, yamux) | firefox-js-v1.x | go-v0.40 | wss | noise | yamux | ✅ | 32s | 280 | 126 |
| firefox-js-v1.x x go-v0.41 (webtransport) | firefox-js-v1.x | go-v0.41 | webtransport | - | - | ❌ | 32s | - | - |
| firefox-js-v1.x x go-v0.41 (wss, noise, yamux) | firefox-js-v1.x | go-v0.41 | wss | noise | yamux | ✅ | 30s | 336 | 138 |
| firefox-js-v1.x x go-v0.41 (webrtc-direct) | firefox-js-v1.x | go-v0.41 | webrtc-direct | - | - | ✅ | 31s | 520 | 81 |
| firefox-js-v1.x x go-v0.42 (webtransport) | firefox-js-v1.x | go-v0.42 | webtransport | - | - | ❌ | 31s | - | - |
| firefox-js-v1.x x go-v0.42 (wss, noise, yamux) | firefox-js-v1.x | go-v0.42 | wss | noise | yamux | ✅ | 33s | 236 | 118 |
| firefox-js-v1.x x go-v0.42 (webrtc-direct) | firefox-js-v1.x | go-v0.42 | webrtc-direct | - | - | ✅ | 32s | 372 | 93 |
| firefox-js-v1.x x go-v0.43 (webtransport) | firefox-js-v1.x | go-v0.43 | webtransport | - | - | ❌ | 32s | - | - |
| firefox-js-v1.x x go-v0.43 (webrtc-direct) | firefox-js-v1.x | go-v0.43 | webrtc-direct | - | - | ✅ | 31s | 248 | 62 |
| firefox-js-v1.x x go-v0.43 (wss, noise, yamux) | firefox-js-v1.x | go-v0.43 | wss | noise | yamux | ✅ | 33s | 235 | 117 |
| firefox-js-v1.x x go-v0.44 (webtransport) | firefox-js-v1.x | go-v0.44 | webtransport | - | - | ❌ | 30s | - | - |
| firefox-js-v1.x x go-v0.44 (wss, noise, yamux) | firefox-js-v1.x | go-v0.44 | wss | noise | yamux | ✅ | 31s | 335 | 131 |
| firefox-js-v1.x x go-v0.44 (webrtc-direct) | firefox-js-v1.x | go-v0.44 | webrtc-direct | - | - | ✅ | 33s | 532 | 119 |
| firefox-js-v1.x x go-v0.45 (webtransport) | firefox-js-v1.x | go-v0.45 | webtransport | - | - | ❌ | 34s | - | - |
| firefox-js-v1.x x go-v0.45 (wss, noise, yamux) | firefox-js-v1.x | go-v0.45 | wss | noise | yamux | ✅ | 34s | 385 | 194 |
| firefox-js-v1.x x go-v0.45 (webrtc-direct) | firefox-js-v1.x | go-v0.45 | webrtc-direct | - | - | ✅ | 35s | 433 | 85 |
| firefox-js-v1.x x python-v0.4 (wss, noise, mplex) | firefox-js-v1.x | python-v0.4 | wss | noise | mplex | ✅ | 35s | 324 | 85 |
| firefox-js-v1.x x python-v0.4 (wss, noise, yamux) | firefox-js-v1.x | python-v0.4 | wss | noise | yamux | ✅ | 36s | 661 | 332 |
| firefox-js-v1.x x chromium-js-v1.x (webrtc) | firefox-js-v1.x | chromium-js-v1.x | webrtc | - | - | ✅ | 49s | 2499 | 192 |
| firefox-js-v1.x x chromium-js-v2.x (webrtc) | firefox-js-v1.x | chromium-js-v2.x | webrtc | - | - | ✅ | 50s | 2525 | 332 |
| firefox-js-v1.x x firefox-js-v1.x (webrtc) | firefox-js-v1.x | firefox-js-v1.x | webrtc | - | - | ✅ | 54s | 2666 | 223 |
| firefox-js-v1.x x webkit-js-v1.x (webrtc) | firefox-js-v1.x | webkit-js-v1.x | webrtc | - | - | ✅ | 51s | 1801 | 200 |
| firefox-js-v1.x x firefox-js-v2.x (webrtc) | firefox-js-v1.x | firefox-js-v2.x | webrtc | - | - | ✅ | 55s | 1788 | 192 |
| firefox-js-v1.x x webkit-js-v2.x (webrtc) | firefox-js-v1.x | webkit-js-v2.x | webrtc | - | - | ✅ | 53s | 1644 | 145 |
| firefox-js-v2.x x rust-v0.53 (webrtc-direct) | firefox-js-v2.x | rust-v0.53 | webrtc-direct | - | - | ✅ | 52s | 1543 | 64 |
| firefox-js-v2.x x rust-v0.54 (webrtc-direct) | firefox-js-v2.x | rust-v0.54 | webrtc-direct | - | - | ✅ | 52s | 1490 | 54 |
| firefox-js-v2.x x rust-v0.55 (webrtc-direct) | firefox-js-v2.x | rust-v0.55 | webrtc-direct | - | - | ✅ | 37s | 1559 | 64 |
| firefox-js-v2.x x rust-v0.56 (webrtc-direct) | firefox-js-v2.x | rust-v0.56 | webrtc-direct | - | - | ✅ | 35s | 1534 | 59 |
| firefox-js-v2.x x go-v0.38 (webtransport) | firefox-js-v2.x | go-v0.38 | webtransport | - | - | ❌ | 32s | - | - |
| firefox-js-v2.x x go-v0.38 (wss, noise, yamux) | firefox-js-v2.x | go-v0.38 | wss | noise | yamux | ✅ | 33s | 368 | 128 |
| firefox-js-v2.x x go-v0.39 (webtransport) | firefox-js-v2.x | go-v0.39 | webtransport | - | - | ❌ | 34s | - | - |
| firefox-js-v2.x x go-v0.38 (webrtc-direct) | firefox-js-v2.x | go-v0.38 | webrtc-direct | - | - | ✅ | 35s | 406 | 69 |
| firefox-js-v2.x x go-v0.39 (wss, noise, yamux) | firefox-js-v2.x | go-v0.39 | wss | noise | yamux | ✅ | 34s | 301 | 118 |
| firefox-js-v2.x x go-v0.39 (webrtc-direct) | firefox-js-v2.x | go-v0.39 | webrtc-direct | - | - | ✅ | 33s | 312 | 54 |
| firefox-js-v2.x x go-v0.40 (webtransport) | firefox-js-v2.x | go-v0.40 | webtransport | - | - | ❌ | 33s | - | - |
| firefox-js-v2.x x go-v0.40 (wss, noise, yamux) | firefox-js-v2.x | go-v0.40 | wss | noise | yamux | ✅ | 35s | 444 | 153 |
| firefox-js-v2.x x go-v0.40 (webrtc-direct) | firefox-js-v2.x | go-v0.40 | webrtc-direct | - | - | ✅ | 35s | 465 | 76 |
| firefox-js-v2.x x go-v0.41 (webtransport) | firefox-js-v2.x | go-v0.41 | webtransport | - | - | ❌ | 34s | - | - |
| firefox-js-v2.x x go-v0.41 (wss, noise, yamux) | firefox-js-v2.x | go-v0.41 | wss | noise | yamux | ✅ | 35s | 330 | 129 |
| firefox-js-v2.x x go-v0.41 (webrtc-direct) | firefox-js-v2.x | go-v0.41 | webrtc-direct | - | - | ✅ | 35s | 457 | 78 |
| firefox-js-v2.x x go-v0.42 (webtransport) | firefox-js-v2.x | go-v0.42 | webtransport | - | - | ❌ | 36s | - | - |
| firefox-js-v2.x x go-v0.42 (wss, noise, yamux) | firefox-js-v2.x | go-v0.42 | wss | noise | yamux | ✅ | 34s | 279 | 114 |
| firefox-js-v2.x x go-v0.42 (webrtc-direct) | firefox-js-v2.x | go-v0.42 | webrtc-direct | - | - | ✅ | 34s | 337 | 56 |
| firefox-js-v2.x x go-v0.43 (webtransport) | firefox-js-v2.x | go-v0.43 | webtransport | - | - | ❌ | 32s | - | - |
| firefox-js-v2.x x go-v0.43 (wss, noise, yamux) | firefox-js-v2.x | go-v0.43 | wss | noise | yamux | ✅ | 34s | 374 | 203 |
| firefox-js-v2.x x go-v0.43 (webrtc-direct) | firefox-js-v2.x | go-v0.43 | webrtc-direct | - | - | ✅ | 34s | 384 | 97 |
| firefox-js-v2.x x go-v0.44 (webtransport) | firefox-js-v2.x | go-v0.44 | webtransport | - | - | ❌ | 34s | - | - |
| firefox-js-v2.x x go-v0.44 (wss, noise, yamux) | firefox-js-v2.x | go-v0.44 | wss | noise | yamux | ✅ | 35s | 330 | 149 |
| firefox-js-v2.x x go-v0.44 (webrtc-direct) | firefox-js-v2.x | go-v0.44 | webrtc-direct | - | - | ✅ | 35s | 300 | 60 |
| firefox-js-v2.x x go-v0.45 (webtransport) | firefox-js-v2.x | go-v0.45 | webtransport | - | - | ❌ | 35s | - | - |
| firefox-js-v2.x x go-v0.45 (wss, noise, yamux) | firefox-js-v2.x | go-v0.45 | wss | noise | yamux | ✅ | 38s | 631 | 278 |
| firefox-js-v2.x x go-v0.45 (webrtc-direct) | firefox-js-v2.x | go-v0.45 | webrtc-direct | - | - | ✅ | 43s | 816 | 189 |
| firefox-js-v2.x x python-v0.4 (wss, noise, mplex) | firefox-js-v2.x | python-v0.4 | wss | noise | mplex | ✅ | 46s | 566 | 205 |
| firefox-js-v2.x x python-v0.4 (wss, noise, yamux) | firefox-js-v2.x | python-v0.4 | wss | noise | yamux | ✅ | 49s | 444 | 220 |
| firefox-js-v2.x x chromium-js-v1.x (webrtc) | firefox-js-v2.x | chromium-js-v1.x | webrtc | - | - | ✅ | 53s | 2438 | 237 |
| firefox-js-v2.x x chromium-js-v2.x (webrtc) | firefox-js-v2.x | chromium-js-v2.x | webrtc | - | - | ✅ | 55s | 2122 | 149 |
| firefox-js-v2.x x firefox-js-v2.x (webrtc) | firefox-js-v2.x | firefox-js-v2.x | webrtc | - | - | ✅ | 57s | 1904 | 153 |
| firefox-js-v2.x x firefox-js-v1.x (webrtc) | firefox-js-v2.x | firefox-js-v1.x | webrtc | - | - | ✅ | 57s | 2115 | 197 |
| firefox-js-v2.x x webkit-js-v1.x (webrtc) | firefox-js-v2.x | webkit-js-v1.x | webrtc | - | - | ✅ | 50s | 1813 | 205 |
| webkit-js-v1.x x rust-v0.53 (webrtc-direct) | webkit-js-v1.x | rust-v0.53 | webrtc-direct | - | - | ✅ | 31s | 541 | 68 |
| firefox-js-v2.x x webkit-js-v2.x (webrtc) | firefox-js-v2.x | webkit-js-v2.x | webrtc | - | - | ✅ | 45s | 1258 | 159 |
| webkit-js-v1.x x rust-v0.54 (webrtc-direct) | webkit-js-v1.x | rust-v0.54 | webrtc-direct | - | - | ✅ | 31s | 484 | 62 |
| webkit-js-v1.x x rust-v0.55 (webrtc-direct) | webkit-js-v1.x | rust-v0.55 | webrtc-direct | - | - | ✅ | 30s | 568 | 61 |
| webkit-js-v1.x x rust-v0.56 (webrtc-direct) | webkit-js-v1.x | rust-v0.56 | webrtc-direct | - | - | ✅ | 29s | 446 | 66 |
| webkit-js-v1.x x go-v0.38 (wss, noise, yamux) | webkit-js-v1.x | go-v0.38 | wss | noise | yamux | ✅ | 27s | 470 | 109 |
| webkit-js-v1.x x go-v0.38 (webrtc-direct) | webkit-js-v1.x | go-v0.38 | webrtc-direct | - | - | ✅ | 27s | 484 | 113 |
| webkit-js-v1.x x go-v0.39 (wss, noise, yamux) | webkit-js-v1.x | go-v0.39 | wss | noise | yamux | ✅ | 25s | 457 | 127 |
| webkit-js-v1.x x go-v0.39 (webrtc-direct) | webkit-js-v1.x | go-v0.39 | webrtc-direct | - | - | ✅ | 25s | 460 | 109 |
| webkit-js-v1.x x go-v0.40 (wss, noise, yamux) | webkit-js-v1.x | go-v0.40 | wss | noise | yamux | ✅ | 27s | 520 | 167 |
| webkit-js-v1.x x go-v0.40 (webrtc-direct) | webkit-js-v1.x | go-v0.40 | webrtc-direct | - | - | ✅ | 27s | 467 | 81 |
| webkit-js-v1.x x go-v0.41 (wss, noise, yamux) | webkit-js-v1.x | go-v0.41 | wss | noise | yamux | ✅ | 26s | 526 | 180 |
| webkit-js-v1.x x go-v0.41 (webrtc-direct) | webkit-js-v1.x | go-v0.41 | webrtc-direct | - | - | ✅ | 26s | 541 | 131 |
| webkit-js-v1.x x go-v0.42 (wss, noise, yamux) | webkit-js-v1.x | go-v0.42 | wss | noise | yamux | ✅ | 26s | 542 | 148 |
| webkit-js-v1.x x go-v0.42 (webrtc-direct) | webkit-js-v1.x | go-v0.42 | webrtc-direct | - | - | ✅ | 26s | 470 | 118 |
| webkit-js-v1.x x go-v0.43 (wss, noise, yamux) | webkit-js-v1.x | go-v0.43 | wss | noise | yamux | ✅ | 26s | 549 | 196 |
| webkit-js-v1.x x go-v0.43 (webrtc-direct) | webkit-js-v1.x | go-v0.43 | webrtc-direct | - | - | ✅ | 26s | 494 | 130 |
| webkit-js-v1.x x go-v0.44 (wss, noise, yamux) | webkit-js-v1.x | go-v0.44 | wss | noise | yamux | ✅ | 27s | 530 | 183 |
| webkit-js-v1.x x go-v0.44 (webrtc-direct) | webkit-js-v1.x | go-v0.44 | webrtc-direct | - | - | ✅ | 28s | 572 | 193 |
| webkit-js-v1.x x go-v0.45 (wss, noise, yamux) | webkit-js-v1.x | go-v0.45 | wss | noise | yamux | ✅ | 28s | 518 | 185 |
| webkit-js-v1.x x go-v0.45 (webrtc-direct) | webkit-js-v1.x | go-v0.45 | webrtc-direct | - | - | ✅ | 30s | 588 | 113 |
| webkit-js-v1.x x python-v0.4 (wss, noise, mplex) | webkit-js-v1.x | python-v0.4 | wss | noise | mplex | ✅ | 29s | 654 | 212 |
| webkit-js-v1.x x python-v0.4 (wss, noise, yamux) | webkit-js-v1.x | python-v0.4 | wss | noise | yamux | ✅ | 34s | 920 | 232 |
| webkit-js-v1.x x chromium-js-v1.x (webrtc) | webkit-js-v1.x | chromium-js-v1.x | webrtc | - | - | ✅ | 41s | 2490 | 242 |
| webkit-js-v1.x x chromium-js-v2.x (webrtc) | webkit-js-v1.x | chromium-js-v2.x | webrtc | - | - | ✅ | 47s | 2768 | 251 |
| webkit-js-v1.x x firefox-js-v1.x (webrtc) | webkit-js-v1.x | firefox-js-v1.x | webrtc | - | - | ✅ | 52s | 2249 | 381 |
| webkit-js-v1.x x webkit-js-v1.x (webrtc) | webkit-js-v1.x | webkit-js-v1.x | webrtc | - | - | ✅ | 45s | 2273 | 304 |
| webkit-js-v1.x x firefox-js-v2.x (webrtc) | webkit-js-v1.x | firefox-js-v2.x | webrtc | - | - | ✅ | 52s | 1466 | 116 |
| webkit-js-v2.x x rust-v0.53 (webrtc-direct) | webkit-js-v2.x | rust-v0.53 | webrtc-direct | - | - | ✅ | 43s | 1502 | 89 |
| webkit-js-v1.x x webkit-js-v2.x (webrtc) | webkit-js-v1.x | webkit-js-v2.x | webrtc | - | - | ✅ | 45s | 1308 | 60 |
| webkit-js-v2.x x rust-v0.54 (webrtc-direct) | webkit-js-v2.x | rust-v0.54 | webrtc-direct | - | - | ✅ | 40s | 1415 | 46 |
| webkit-js-v2.x x rust-v0.55 (webrtc-direct) | webkit-js-v2.x | rust-v0.55 | webrtc-direct | - | - | ✅ | 31s | 500 | 97 |
| webkit-js-v2.x x rust-v0.56 (webrtc-direct) | webkit-js-v2.x | rust-v0.56 | webrtc-direct | - | - | ✅ | 30s | 1546 | 89 |
| webkit-js-v2.x x go-v0.38 (webrtc-direct) | webkit-js-v2.x | go-v0.38 | webrtc-direct | - | - | ✅ | 28s | 506 | 98 |
| webkit-js-v2.x x go-v0.38 (wss, noise, yamux) | webkit-js-v2.x | go-v0.38 | wss | noise | yamux | ✅ | 29s | 443 | 133 |
| webkit-js-v2.x x go-v0.39 (wss, noise, yamux) | webkit-js-v2.x | go-v0.39 | wss | noise | yamux | ✅ | 28s | 558 | 132 |
| webkit-js-v2.x x go-v0.39 (webrtc-direct) | webkit-js-v2.x | go-v0.39 | webrtc-direct | - | - | ✅ | 29s | 458 | 79 |
| webkit-js-v2.x x go-v0.40 (wss, noise, yamux) | webkit-js-v2.x | go-v0.40 | wss | noise | yamux | ✅ | 28s | 280 | 68 |
| webkit-js-v2.x x go-v0.40 (webrtc-direct) | webkit-js-v2.x | go-v0.40 | webrtc-direct | - | - | ✅ | 28s | 347 | 32 |
| webkit-js-v2.x x go-v0.41 (wss, noise, yamux) | webkit-js-v2.x | go-v0.41 | wss | noise | yamux | ✅ | 27s | 548 | 101 |
| webkit-js-v2.x x go-v0.41 (webrtc-direct) | webkit-js-v2.x | go-v0.41 | webrtc-direct | - | - | ✅ | 28s | 521 | 77 |
| webkit-js-v2.x x go-v0.42 (wss, noise, yamux) | webkit-js-v2.x | go-v0.42 | wss | noise | yamux | ✅ | 30s | 568 | 226 |
| webkit-js-v2.x x go-v0.42 (webrtc-direct) | webkit-js-v2.x | go-v0.42 | webrtc-direct | - | - | ✅ | 30s | 542 | 97 |
| webkit-js-v2.x x go-v0.43 (wss, noise, yamux) | webkit-js-v2.x | go-v0.43 | wss | noise | yamux | ✅ | 30s | 440 | 100 |
| webkit-js-v2.x x go-v0.43 (webrtc-direct) | webkit-js-v2.x | go-v0.43 | webrtc-direct | - | - | ✅ | 30s | 476 | 100 |
| webkit-js-v2.x x go-v0.44 (wss, noise, yamux) | webkit-js-v2.x | go-v0.44 | wss | noise | yamux | ✅ | 29s | 423 | 102 |
| webkit-js-v2.x x go-v0.44 (webrtc-direct) | webkit-js-v2.x | go-v0.44 | webrtc-direct | - | - | ✅ | 29s | 410 | 38 |
| webkit-js-v2.x x go-v0.45 (wss, noise, yamux) | webkit-js-v2.x | go-v0.45 | wss | noise | yamux | ✅ | 30s | 571 | 167 |
| webkit-js-v2.x x go-v0.45 (webrtc-direct) | webkit-js-v2.x | go-v0.45 | webrtc-direct | - | - | ✅ | 35s | 1081 | 136 |
| webkit-js-v2.x x python-v0.4 (wss, noise, mplex) | webkit-js-v2.x | python-v0.4 | wss | noise | mplex | ✅ | 42s | 718 | 168 |
| webkit-js-v2.x x python-v0.4 (wss, noise, yamux) | webkit-js-v2.x | python-v0.4 | wss | noise | yamux | ✅ | 43s | 1137 | 235 |
| webkit-js-v2.x x chromium-js-v2.x (webrtc) | webkit-js-v2.x | chromium-js-v2.x | webrtc | - | - | ✅ | 47s | 1817 | 117 |
| webkit-js-v2.x x chromium-js-v1.x (webrtc) | webkit-js-v2.x | chromium-js-v1.x | webrtc | - | - | ✅ | 49s | 2390 | 158 |
| chromium-rust-v0.53 x rust-v0.53 (webrtc-direct) | chromium-rust-v0.53 | rust-v0.53 | webrtc-direct | - | - | ✅ | 9s | 357.4 | 0.2 |
| chromium-rust-v0.53 x rust-v0.53 (ws, noise, mplex) | chromium-rust-v0.53 | rust-v0.53 | ws | noise | mplex | ✅ | 8s | 499.3 | 0.4 |
| webkit-js-v2.x x firefox-js-v1.x (webrtc) | webkit-js-v2.x | firefox-js-v1.x | webrtc | - | - | ✅ | 51s | 1810 | 110 |
| webkit-js-v2.x x webkit-js-v1.x (webrtc) | webkit-js-v2.x | webkit-js-v1.x | webrtc | - | - | ✅ | 45s | 1204 | 87 |
| chromium-rust-v0.53 x rust-v0.53 (ws, noise, yamux) | chromium-rust-v0.53 | rust-v0.53 | ws | noise | yamux | ✅ | 7s | 349.6 | 4.6 |
| chromium-rust-v0.53 x rust-v0.54 (webrtc-direct) | chromium-rust-v0.53 | rust-v0.54 | webrtc-direct | - | - | ✅ | 7s | 284.5 | 0.399 |
| webkit-js-v2.x x firefox-js-v2.x (webrtc) | webkit-js-v2.x | firefox-js-v2.x | webrtc | - | - | ✅ | 54s | 1347 | 96 |
| chromium-rust-v0.53 x rust-v0.54 (ws, noise, mplex) | chromium-rust-v0.53 | rust-v0.54 | ws | noise | mplex | ✅ | 6s | 471.2 | 0.6 |
| chromium-rust-v0.53 x rust-v0.54 (ws, noise, yamux) | chromium-rust-v0.53 | rust-v0.54 | ws | noise | yamux | ✅ | 6s | 339.4 | 5.799 |
| chromium-rust-v0.53 x rust-v0.55 (webrtc-direct) | chromium-rust-v0.53 | rust-v0.55 | webrtc-direct | - | - | ✅ | 6s | 229.6 | 0.2 |
| webkit-js-v2.x x webkit-js-v2.x (webrtc) | webkit-js-v2.x | webkit-js-v2.x | webrtc | - | - | ✅ | 36s | 763 | 44 |
| chromium-rust-v0.53 x rust-v0.55 (ws, noise, mplex) | chromium-rust-v0.53 | rust-v0.55 | ws | noise | mplex | ✅ | 5s | 420.7 | 0.3 |
| chromium-rust-v0.53 x rust-v0.55 (ws, noise, yamux) | chromium-rust-v0.53 | rust-v0.55 | ws | noise | yamux | ✅ | 5s | 333.4 | 3.5 |
| chromium-rust-v0.53 x rust-v0.56 (ws, noise, mplex) | chromium-rust-v0.53 | rust-v0.56 | ws | noise | mplex | ✅ | 5s | 422.7 | 0.3 |
| chromium-rust-v0.53 x rust-v0.56 (webrtc-direct) | chromium-rust-v0.53 | rust-v0.56 | webrtc-direct | - | - | ✅ | 7s | 1341.5 | 0.099 |
| chromium-rust-v0.53 x rust-v0.56 (ws, noise, yamux) | chromium-rust-v0.53 | rust-v0.56 | ws | noise | yamux | ✅ | 6s | 326.2 | 3.2 |
| chromium-rust-v0.53 x go-v0.38 (webtransport) | chromium-rust-v0.53 | go-v0.38 | webtransport | - | - | ✅ | 6s | 69.6 | 3.3 |
| chromium-rust-v0.53 x go-v0.38 (webrtc-direct) | chromium-rust-v0.53 | go-v0.38 | webrtc-direct | - | - | ✅ | 5s | 138.1 | 0.2 |
| chromium-rust-v0.53 x go-v0.38 (ws, noise, yamux) | chromium-rust-v0.53 | go-v0.38 | ws | noise | yamux | ✅ | 6s | 346.1 | 11.0 |
| chromium-rust-v0.53 x go-v0.39 (webtransport) | chromium-rust-v0.53 | go-v0.39 | webtransport | - | - | ✅ | 6s | 106.599 | 0.099 |
| chromium-rust-v0.53 x go-v0.39 (webrtc-direct) | chromium-rust-v0.53 | go-v0.39 | webrtc-direct | - | - | ✅ | 5s | 166.3 | 5.0 |
| chromium-rust-v0.53 x go-v0.40 (webtransport) | chromium-rust-v0.53 | go-v0.40 | webtransport | - | - | ✅ | 5s | 73.699 | 0.1 |
| chromium-rust-v0.53 x go-v0.39 (ws, noise, yamux) | chromium-rust-v0.53 | go-v0.39 | ws | noise | yamux | ✅ | 6s | 339.0 | 4.9 |
| chromium-rust-v0.53 x go-v0.40 (webrtc-direct) | chromium-rust-v0.53 | go-v0.40 | webrtc-direct | - | - | ✅ | 6s | 221.399 | 0.1 |
| chromium-rust-v0.53 x go-v0.41 (webtransport) | chromium-rust-v0.53 | go-v0.41 | webtransport | - | - | ✅ | 5s | 56.0 | 0.5 |
| chromium-rust-v0.53 x go-v0.40 (ws, noise, yamux) | chromium-rust-v0.53 | go-v0.40 | ws | noise | yamux | ✅ | 6s | 327.7 | 5.6 |
| chromium-rust-v0.53 x go-v0.41 (ws, noise, yamux) | chromium-rust-v0.53 | go-v0.41 | ws | noise | yamux | ✅ | 5s | 327.5 | 4.3 |
| chromium-rust-v0.53 x go-v0.41 (webrtc-direct) | chromium-rust-v0.53 | go-v0.41 | webrtc-direct | - | - | ✅ | 6s | 179.5 | 1.899 |
| chromium-rust-v0.53 x go-v0.42 (webtransport) | chromium-rust-v0.53 | go-v0.42 | webtransport | - | - | ✅ | 5s | 48.1 | 0.2 |
| chromium-rust-v0.53 x go-v0.42 (webrtc-direct) | chromium-rust-v0.53 | go-v0.42 | webrtc-direct | - | - | ✅ | 6s | 1423.199 | 0.1 |
| chromium-rust-v0.53 x go-v0.43 (webtransport) | chromium-rust-v0.53 | go-v0.43 | webtransport | - | - | ✅ | 6s | 87.8 | 2.2 |
| chromium-rust-v0.53 x go-v0.42 (ws, noise, yamux) | chromium-rust-v0.53 | go-v0.42 | ws | noise | yamux | ✅ | 6s | 334.2 | 4.0 |
| chromium-rust-v0.53 x go-v0.43 (ws, noise, yamux) | chromium-rust-v0.53 | go-v0.43 | ws | noise | yamux | ✅ | 5s | 322.5 | 4.6 |
| chromium-rust-v0.53 x go-v0.43 (webrtc-direct) | chromium-rust-v0.53 | go-v0.43 | webrtc-direct | - | - | ✅ | 6s | 304.0 | 0.0 |
| chromium-rust-v0.53 x go-v0.44 (webtransport) | chromium-rust-v0.53 | go-v0.44 | webtransport | - | - | ✅ | 6s | 121.899 | 0.4 |
| chromium-rust-v0.53 x go-v0.44 (webrtc-direct) | chromium-rust-v0.53 | go-v0.44 | webrtc-direct | - | - | ✅ | 6s | 164.0 | 0.2 |
| chromium-rust-v0.53 x go-v0.44 (ws, noise, yamux) | chromium-rust-v0.53 | go-v0.44 | ws | noise | yamux | ✅ | 6s | 331.099 | 6.4 |
| chromium-rust-v0.53 x go-v0.45 (webtransport) | chromium-rust-v0.53 | go-v0.45 | webtransport | - | - | ✅ | 5s | 30.6 | 0.2 |
| chromium-rust-v0.53 x go-v0.45 (webrtc-direct) | chromium-rust-v0.53 | go-v0.45 | webrtc-direct | - | - | ✅ | 6s | 220.899 | 0.3 |
| chromium-rust-v0.53 x go-v0.45 (ws, noise, yamux) | chromium-rust-v0.53 | go-v0.45 | ws | noise | yamux | ✅ | 7s | 343.2 | 8.8 |
| chromium-rust-v0.53 x python-v0.4 (ws, noise, yamux) | chromium-rust-v0.53 | python-v0.4 | ws | noise | yamux | ✅ | 6s | 343.1 | 7.0 |
| chromium-rust-v0.53 x nim-v1.14 (ws, noise, mplex) | chromium-rust-v0.53 | nim-v1.14 | ws | noise | mplex | ✅ | 7s | 497.7 | 0.5 |
| chromium-rust-v0.53 x js-v1.x (ws, noise, yamux) | chromium-rust-v0.53 | js-v1.x | ws | noise | yamux | ✅ | 19s | 368.099 | 14.5 |
| chromium-rust-v0.53 x js-v1.x (ws, noise, mplex) | chromium-rust-v0.53 | js-v1.x | ws | noise | mplex | ✅ | 19s | 439.3 | 0.6 |
| chromium-rust-v0.53 x nim-v1.14 (ws, noise, yamux) | chromium-rust-v0.53 | nim-v1.14 | ws | noise | yamux | ✅ | 6s | 342.8 | 9.5 |
| chromium-rust-v0.53 x js-v2.x (ws, noise, mplex) | chromium-rust-v0.53 | js-v2.x | ws | noise | mplex | ✅ | 20s | 430.8 | 0.5 |
| chromium-rust-v0.53 x js-v2.x (ws, noise, yamux) | chromium-rust-v0.53 | js-v2.x | ws | noise | yamux | ✅ | 20s | 353.1 | 16.0 |
| chromium-rust-v0.53 x js-v3.x (ws, noise, mplex) | chromium-rust-v0.53 | js-v3.x | ws | noise | mplex | ✅ | 19s | 444.7 | 2.5 |
| chromium-rust-v0.53 x js-v3.x (ws, noise, yamux) | chromium-rust-v0.53 | js-v3.x | ws | noise | yamux | ✅ | 19s | 318.8 | 4.2 |
| chromium-rust-v0.54 x rust-v0.53 (webrtc-direct) | chromium-rust-v0.54 | rust-v0.53 | webrtc-direct | - | - | ✅ | 6s | 253.3 | 0.1 |
| chromium-rust-v0.54 x rust-v0.53 (ws, noise, mplex) | chromium-rust-v0.54 | rust-v0.53 | ws | noise | mplex | ✅ | 5s | 435.9 | 0.4 |
| chromium-rust-v0.53 x jvm-v1.2 (ws, noise, yamux) | chromium-rust-v0.53 | jvm-v1.2 | ws | noise | yamux | ✅ | 9s | 974.3 | 36.0 |
| chromium-rust-v0.54 x rust-v0.53 (ws, noise, yamux) | chromium-rust-v0.54 | rust-v0.53 | ws | noise | yamux | ✅ | 5s | 321.9 | 3.1 |
| chromium-rust-v0.54 x rust-v0.54 (webrtc-direct) | chromium-rust-v0.54 | rust-v0.54 | webrtc-direct | - | - | ✅ | 5s | 187.2 | 0.1 |
| chromium-rust-v0.54 x rust-v0.54 (ws, noise, mplex) | chromium-rust-v0.54 | rust-v0.54 | ws | noise | mplex | ✅ | 5s | 419.4 | 0.4 |
| chromium-rust-v0.54 x rust-v0.54 (ws, noise, yamux) | chromium-rust-v0.54 | rust-v0.54 | ws | noise | yamux | ✅ | 4s | 326.4 | 2.9 |
| chromium-rust-v0.54 x rust-v0.55 (webrtc-direct) | chromium-rust-v0.54 | rust-v0.55 | webrtc-direct | - | - | ✅ | 3s | 206.5 | 0.1 |
| chromium-rust-v0.54 x rust-v0.55 (ws, noise, mplex) | chromium-rust-v0.54 | rust-v0.55 | ws | noise | mplex | ✅ | 4s | 418.0 | 0.3 |
| chromium-rust-v0.54 x rust-v0.55 (ws, noise, yamux) | chromium-rust-v0.54 | rust-v0.55 | ws | noise | yamux | ✅ | 4s | 326.9 | 5.4 |
| chromium-rust-v0.54 x rust-v0.56 (ws, noise, mplex) | chromium-rust-v0.54 | rust-v0.56 | ws | noise | mplex | ✅ | 4s | 413.8 | 0.3 |
| chromium-rust-v0.54 x rust-v0.56 (webrtc-direct) | chromium-rust-v0.54 | rust-v0.56 | webrtc-direct | - | - | ✅ | 6s | 1330.4 | 0.2 |
| chromium-rust-v0.54 x rust-v0.56 (ws, noise, yamux) | chromium-rust-v0.54 | rust-v0.56 | ws | noise | yamux | ✅ | 4s | 319.0 | 2.1 |
| chromium-rust-v0.54 x go-v0.38 (webtransport) | chromium-rust-v0.54 | go-v0.38 | webtransport | - | - | ✅ | 4s | 39.1 | 0.3 |
| chromium-rust-v0.54 x go-v0.38 (webrtc-direct) | chromium-rust-v0.54 | go-v0.38 | webrtc-direct | - | - | ✅ | 4s | 132.6 | 0.1 |
| chromium-rust-v0.54 x go-v0.38 (ws, noise, yamux) | chromium-rust-v0.54 | go-v0.38 | ws | noise | yamux | ✅ | 4s | 330.0 | 6.1 |
| chromium-rust-v0.54 x go-v0.39 (webtransport) | chromium-rust-v0.54 | go-v0.39 | webtransport | - | - | ✅ | 5s | 46.8 | 0.4 |
| chromium-rust-v0.54 x go-v0.39 (webrtc-direct) | chromium-rust-v0.54 | go-v0.39 | webrtc-direct | - | - | ✅ | 4s | 102.2 | 0.2 |
| chromium-rust-v0.54 x go-v0.39 (ws, noise, yamux) | chromium-rust-v0.54 | go-v0.39 | ws | noise | yamux | ✅ | 4s | 324.2 | 5.5 |
| chromium-rust-v0.54 x go-v0.40 (webtransport) | chromium-rust-v0.54 | go-v0.40 | webtransport | - | - | ✅ | 4s | 59.2 | 0.5 |
| chromium-rust-v0.54 x go-v0.40 (webrtc-direct) | chromium-rust-v0.54 | go-v0.40 | webrtc-direct | - | - | ✅ | 4s | 158.0 | 0.2 |
| chromium-rust-v0.54 x go-v0.40 (ws, noise, yamux) | chromium-rust-v0.54 | go-v0.40 | ws | noise | yamux | ✅ | 4s | 326.5 | 6.2 |
| chromium-rust-v0.54 x go-v0.41 (webtransport) | chromium-rust-v0.54 | go-v0.41 | webtransport | - | - | ✅ | 4s | 52.2 | 0.8 |
| chromium-rust-v0.54 x go-v0.41 (webrtc-direct) | chromium-rust-v0.54 | go-v0.41 | webrtc-direct | - | - | ✅ | 3s | 138.6 | 0.2 |
| chromium-rust-v0.54 x go-v0.41 (ws, noise, yamux) | chromium-rust-v0.54 | go-v0.41 | ws | noise | yamux | ✅ | 4s | 324.0 | 4.9 |
| chromium-rust-v0.54 x go-v0.42 (webtransport) | chromium-rust-v0.54 | go-v0.42 | webtransport | - | - | ✅ | 4s | 73.0 | 0.2 |
| chromium-rust-v0.54 x go-v0.42 (webrtc-direct) | chromium-rust-v0.54 | go-v0.42 | webrtc-direct | - | - | ✅ | 4s | 127.0 | 0.1 |
| chromium-rust-v0.54 x go-v0.42 (ws, noise, yamux) | chromium-rust-v0.54 | go-v0.42 | ws | noise | yamux | ✅ | 4s | 326.1 | 6.1 |
| chromium-rust-v0.54 x go-v0.43 (webtransport) | chromium-rust-v0.54 | go-v0.43 | webtransport | - | - | ✅ | 5s | 68.0 | 0.5 |
| chromium-rust-v0.54 x go-v0.43 (webrtc-direct) | chromium-rust-v0.54 | go-v0.43 | webrtc-direct | - | - | ✅ | 4s | 189.3 | 0.1 |
| chromium-rust-v0.54 x go-v0.43 (ws, noise, yamux) | chromium-rust-v0.54 | go-v0.43 | ws | noise | yamux | ✅ | 4s | 319.8 | 2.2 |
| chromium-rust-v0.54 x go-v0.44 (webtransport) | chromium-rust-v0.54 | go-v0.44 | webtransport | - | - | ✅ | 4s | 46.8 | 0.3 |
| chromium-rust-v0.54 x go-v0.44 (webrtc-direct) | chromium-rust-v0.54 | go-v0.44 | webrtc-direct | - | - | ✅ | 4s | 142.4 | 0.1 |
| chromium-rust-v0.54 x go-v0.44 (ws, noise, yamux) | chromium-rust-v0.54 | go-v0.44 | ws | noise | yamux | ✅ | 4s | 339.7 | 8.0 |
| chromium-rust-v0.54 x go-v0.45 (webtransport) | chromium-rust-v0.54 | go-v0.45 | webtransport | - | - | ✅ | 5s | 48.2 | 0.4 |
| chromium-rust-v0.54 x go-v0.45 (webrtc-direct) | chromium-rust-v0.54 | go-v0.45 | webrtc-direct | - | - | ✅ | 4s | 153.2 | 0.1 |
| chromium-rust-v0.54 x go-v0.45 (ws, noise, yamux) | chromium-rust-v0.54 | go-v0.45 | ws | noise | yamux | ✅ | 5s | 315.3 | 2.4 |
| chromium-rust-v0.54 x python-v0.4 (ws, noise, yamux) | chromium-rust-v0.54 | python-v0.4 | ws | noise | yamux | ✅ | 6s | 328.8 | 5.6 |
| chromium-rust-v0.54 x python-v0.4 (ws, noise, mplex) | chromium-rust-v0.54 | python-v0.4 | ws | noise | mplex | ✅ | 16s | 10429.5 | 0.9 |
| chromium-rust-v0.54 x js-v1.x (ws, noise, mplex) | chromium-rust-v0.54 | js-v1.x | ws | noise | mplex | ✅ | 15s | 440.5 | 0.5 |
| chromium-rust-v0.54 x js-v1.x (ws, noise, yamux) | chromium-rust-v0.54 | js-v1.x | ws | noise | yamux | ✅ | 15s | 337.1 | 9.8 |
| chromium-rust-v0.54 x js-v2.x (ws, noise, mplex) | chromium-rust-v0.54 | js-v2.x | ws | noise | mplex | ✅ | 16s | 426.8 | 0.4 |
| chromium-rust-v0.54 x js-v2.x (ws, noise, yamux) | chromium-rust-v0.54 | js-v2.x | ws | noise | yamux | ✅ | 16s | 328.4 | 3.9 |
| chromium-rust-v0.54 x js-v3.x (ws, noise, mplex) | chromium-rust-v0.54 | js-v3.x | ws | noise | mplex | ✅ | 14s | 427.2 | 0.5 |
| chromium-rust-v0.54 x nim-v1.14 (ws, noise, mplex) | chromium-rust-v0.54 | nim-v1.14 | ws | noise | mplex | ✅ | 5s | 425.6 | 0.5 |
| chromium-rust-v0.54 x nim-v1.14 (ws, noise, yamux) | chromium-rust-v0.54 | nim-v1.14 | ws | noise | yamux | ✅ | 4s | 322.2 | 5.0 |
| chromium-rust-v0.54 x jvm-v1.2 (ws, noise, yamux) | chromium-rust-v0.54 | jvm-v1.2 | ws | noise | yamux | ✅ | 7s | 782.8 | 20.4 |
| chromium-rust-v0.54 x js-v3.x (ws, noise, yamux) | chromium-rust-v0.54 | js-v3.x | ws | noise | yamux | ✅ | 12s | 324.0 | 8.6 |
| chromium-rust-v0.54 x jvm-v1.2 (ws, noise, mplex) | chromium-rust-v0.54 | jvm-v1.2 | ws | noise | mplex | ✅ | 16s | 10931.9 | 1.5 |
| chromium-rust-v0.53 x python-v0.4 (ws, noise, mplex) | chromium-rust-v0.53 | python-v0.4 | ws | noise | mplex | ❌ | 185s | - | - |
| chromium-rust-v0.53 x jvm-v1.2 (ws, noise, mplex) | chromium-rust-v0.53 | jvm-v1.2 | ws | noise | mplex | ❌ | 185s | - | - |

---

## Matrix View by Transport + Secure Channel + Muxer

### quic-v1

| Dialer \ Listener | c-v0.0.1 | eth-p2p-z-v0.0.1 | go-v0.38 | go-v0.39 | go-v0.40 | go-v0.41 | go-v0.42 | go-v0.43 | go-v0.44 | go-v0.45 | jvm-v1.2 | python-v0.4 | rust-v0.53 | rust-v0.54 | rust-v0.55 | rust-v0.56 | zig-v0.0.1 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **c-v0.0.1** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ |
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
| **rust-v0.54** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **rust-v0.55** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **rust-v0.56** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ |
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

*Generated: 2025-12-19T03:43:48Z*
<!-- TEST_RESULTS_END -->

