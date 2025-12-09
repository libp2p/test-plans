# Contributing to Transport Interop Tests

Thank you for contributing to the libp2p transport interoperability tests!

## Adding a New Implementation

### 1. Add to impls.yaml

Add your implementation to `impls.yaml`:

```yaml
implementations:
  - id: go-v0.35
    source:
      type: github
      repo: libp2p/go-libp2p
      commit: <full-40-char-commit-sha>
      dockerfile: interop-tests/Dockerfile
    transports:
      - tcp
      - ws
      - quic-v1
      - webrtc-direct
    secureChannels:
      - noise
      - tls
    muxers:
      - yamux
      - mplex
```

**Important:**
- Use full 40-character commit SHA (not short SHA)
- Dockerfile path is relative to repository root
- List all supported transports, secureChannels, and muxers
- Standalone transports (quic-v1, webrtc) don't need secure/muxer in tests

### 2. Test Locally

```bash
# Build only your implementation
export CACHE_DIR=/tmp/cache
bash scripts/build-images.sh go-v0.35

# Run tests filtered to your implementation
./run_tests.sh --test-select "go-v0.35" --cache-dir /tmp/cache --workers 4
```

### 3. Submit Pull Request

Include in your PR:
- Updated `impls.yaml`
- Description of transport/secure/muxer support
- Link to the commit in the implementation repo

## Implementation Requirements

Your implementation must:

1. **Build via Dockerfile** - Provide a Dockerfile in your repo
2. **Handle Environment Variables**:
   - `IS_DIALER` - "true" for dialer, "false" for listener
   - `TRANSPORT` - tcp, ws, quic-v1, webrtc-direct, etc.
   - `SECURE_CHANNEL` - noise, tls, plaintext (or "null" for standalone)
   - `MUXER` - yamux, mplex (or "null" for standalone)
   - `REDIS_ADDR` - Redis address for coordination (e.g., redis:6379)
   - `DEBUG` - "true" for debug output, "false" otherwise
3. **Coordination via Redis**:
   - Listener publishes its multiaddr to Redis
   - Dialer retrieves multiaddr from Redis
   - Both connect and test the transport
4. **Exit Codes** - Return 0 on success, non-zero on failure
5. **Output** - Print test results to stdout

### Example Dockerfile

```dockerfile
FROM rust:1.70 AS builder

WORKDIR /app
COPY . .
RUN cargo build --release --example transport-interop

FROM debian:bookworm-slim
COPY --from=builder /app/target/release/examples/transport-interop /usr/local/bin/

ENTRYPOINT ["transport-interop"]
```

### Example Test Implementation

```rust
fn main() {
    let redis_addr = env::var("REDIS_ADDR").unwrap();
    let is_dialer = env::var("IS_DIALER").unwrap() == "true";
    let transport = env::var("TRANSPORT").unwrap();
    let secure = env::var("SECURE_CHANNEL").unwrap();
    let muxer = env::var("MUXER").unwrap();

    if is_dialer {
        run_dialer(redis_addr, transport, secure, muxer);
    } else {
        run_listener(redis_addr, transport, secure, muxer);
    }
}
```

## Testing Best Practices

### Filter Tests by Dimension

```bash
# Test only TCP transport
./run_tests.sh --test-select "tcp" --workers 8

# Test only noise secure channel
./run_tests.sh --test-select "noise" --workers 4

# Test only yamux muxer
./run_tests.sh --test-select "yamux" --workers 4

# Combine filters (OR logic)
./run_tests.sh --test-select "tcp|quic" --workers 8
```

### Ignore Problematic Tests

```bash
# Skip WebRTC tests
./run_tests.sh --test-ignore "webrtc" --workers 4

# Skip plaintext (insecure)
./run_tests.sh --test-ignore "plaintext" --workers 8

# Skip self-tests
./run_tests.sh --test-ignore "rust-v0.53 x rust-v0.53" --workers 4
```

### Performance Tuning

```bash
# Use all CPU cores
./run_tests.sh --workers $(nproc)

# Conservative (4 workers)
./run_tests.sh --workers 4

# Maximum (cores + 1)
./run_tests.sh --workers $(($(nproc) + 1))
```

## Understanding the 3D Test Matrix

### Standalone Transports

These have built-in encryption/muxing:
- quic, quic-v1
- webtransport
- webrtc, webrtc-direct

**Test format**: `rust-v0.53 x go-v0.35 (quic-v1)`

### Non-Standalone Transports

These need separate secure channel + muxer:
- tcp
- ws

**Test format**: `rust-v0.53 x go-v0.35 (tcp, noise, yamux)`

### Matrix Calculation

For implementations A and B with:
- 2 common transports (1 standalone, 1 non-standalone)
- 2 common secure channels
- 2 common muxers

**Tests generated**:
- Standalone: 1 test
- Non-standalone: 1 × 2 × 2 = 4 tests
- **Total: 5 tests per direction = 10 tests for A↔B**

## Debugging Failed Tests

### 1. Check Logs

```bash
# List all logs
ls logs/

# View specific test
cat logs/rust-v0.53_x_go-v0.35_tcp_noise_yamux.log

# Find failures
grep -l "failed" logs/*.log
```

### 2. Inspect Docker Compose

```bash
# View generated compose file
cat docker-compose-rust-v0.53_x_go-v0.35_tcp_noise_yamux.yaml

# Check what containers were created
docker ps -a | grep rust-v0.53
```

### 3. Manual Test Execution

```bash
# Run single test manually
bash scripts/run-single-test.sh \
  "rust-v0.53 x go-v0.35 (tcp, noise, yamux)" \
  "rust-v0.53" \
  "go-v0.35" \
  "tcp" \
  "noise" \
  "yamux"
```

### 4. Check Container Logs

```bash
# While test is running
docker logs <container-name>

# After test completes
# Logs are in logs/ directory
```

## CI Integration

### GitHub Actions Example

```yaml
name: Transport Interop

on:
  pull_request:
    paths:
      - 'transport/**'
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install yq
        run: |
          sudo wget -qO /usr/local/bin/yq \
            https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
          sudo chmod +x /usr/local/bin/yq

      - name: Setup cache
        run: mkdir -p /tmp/cache

      - name: Run tests
        run: |
          cd transport
          ./run_tests.sh \
            --cache-dir /tmp/cache \
            --workers 4 \
            --snapshot

      - name: Upload results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: test-results
          path: |
            transport/results.yaml
            transport/results.md
            transport/results.html

      - name: Upload snapshot
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: test-snapshot
          path: /tmp/cache/test-runs/*.tar.gz
```

## Updating Implementations

To update an implementation to a new commit:

```bash
# 1. Update impls.yaml with new commit SHA
vim impls.yaml
# Change commit for rust-v0.54

# 2. Clear cached snapshot
rm /srv/cache/snapshots/<old-commit>.zip

# 3. Run tests
./run_tests.sh --test-select "rust-v0.54" --cache-dir /srv/cache
```

## Test Matrix Examples

### Small Implementation

```yaml
- id: python-v0.4
  transports: [tcp]           # 1 transport
  secureChannels: [noise]     # 1 secure channel
  muxers: [yamux, mplex]      # 2 muxers
```

**Tests generated**: 1 × 1 × 2 = **2 tests** (against itself)

### Full-Featured Implementation

```yaml
- id: rust-v0.53
  transports: [tcp, ws, quic-v1, webrtc-direct]  # 4 transports
  secureChannels: [noise, tls]                    # 2 secure
  muxers: [yamux, mplex]                          # 2 muxers
```

**Tests generated** (against itself):
- Standalone: 2 transports (quic-v1, webrtc-direct) = 2 tests
- Non-standalone: 2 transports (tcp, ws) × 2 secure × 2 muxers = 8 tests
- **Total: 10 tests**

### Cross-Implementation

rust-v0.53 × python-v0.4:
- Common transport: tcp
- Common secure: noise
- Common muxers: yamux, mplex
- **Tests: 1 × 1 × 2 = 2 tests per direction = 4 total**

## Questions?

- Check existing implementations in `impls.yaml`
- Read the main README.md
- Review ARCHITECTURE.md for internals
- Open an issue for questions
