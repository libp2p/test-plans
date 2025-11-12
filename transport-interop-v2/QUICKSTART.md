# Quick Start Guide - Transport Interoperability Tests

Get up and running with transport interop tests in 5 minutes.

## Prerequisites

### Ubuntu/Debian
```bash
sudo apt-get update
sudo apt-get install -y docker.io git wget unzip
sudo usermod -aG docker $USER
newgrp docker
```

### macOS
```bash
# Install Docker Desktop from https://docker.com/products/docker-desktop
brew install git wget yq
```

### Install yq
```bash
# Linux
sudo wget -qO /usr/local/bin/yq \
  https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
sudo chmod +x /usr/local/bin/yq

# macOS
brew install yq
```

## First Run

```bash
# Navigate to directory
cd test-plans/transport-interop-v2

# Check dependencies
./run_tests.sh --check-deps

# Run tests (this will take a few minutes)
./run_tests.sh --cache-dir /tmp/cache --workers 4
```

Expected output:
```
╔════════════════════════════════════════════════════════════╗
║  Transport Interoperability Test Suite                     ║
╚════════════════════════════════════════════════════════════╝

Test Pass: transport-interop-full
Cache Dir: /tmp/cache
Workers: 4

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Checking dependencies...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✓ bash 5.1.16 (minimum: 4.0)
✓ git 2.34.1 (minimum: 2.0.0)
✓ docker 24.0.5 (minimum: 20.10.0)
✓ yq 4.35.1 (minimum: 4.0.0)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Building Docker images...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Building: rust-v0.53
  → Downloading snapshot...
  ✓ Cached: b7914e40.zip
  → Building Docker image...
  ✓ Built image: rust-v0.53

Building: rust-v0.54
Building: python-v0.4

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Generating test matrix...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✓ Generated test matrix with 156 tests

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Running tests...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Total tests: 156

[1/156] rust-v0.53 x rust-v0.54 (tcp, noise, yamux)
[2/156] rust-v0.53 x rust-v0.54 (tcp, noise, mplex)
...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✓ All tests passed!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Results: results.yaml, results.md
```

## View Results

```bash
# View markdown dashboard
cat results.md

# View structured results
cat results.yaml

# Generate HTML (if pandoc installed)
pandoc -f markdown -t html -s -o results.html results.md
```

## Common Tasks

### Test Specific Implementations

```bash
# Test only Rust
./run_tests.sh --test-filter "rust" --workers 4

# Test only Python
./run_tests.sh --test-filter "python" --workers 2

# Test specific version
./run_tests.sh --test-filter "rust-v0.53" --workers 4
```

### Test Specific Transports

```bash
# Test only QUIC
./run_tests.sh --test-filter "quic" --workers 4

# Test only TCP
./run_tests.sh --test-filter "tcp" --workers 8

# Skip WebRTC
./run_tests.sh --test-ignore "webrtc" --workers 4
```

### Test Specific Protocols

```bash
# Test only noise secure channel
./run_tests.sh --test-filter "noise" --workers 4

# Test only yamux muxer
./run_tests.sh --test-filter "yamux" --workers 4

# Skip plaintext (insecure)
./run_tests.sh --test-ignore "plaintext" --workers 8
```

### Create Debug Snapshot

```bash
# Run with snapshot creation
./run_tests.sh --snapshot --cache-dir /tmp/cache --workers 4

# Snapshot saved to:
# /tmp/cache/test-passes/transport-interop-full-<timestamp>.tar.gz

# Extract and re-run
cd /tmp/cache/test-passes
tar -xzf transport-interop-full-*.tar.gz
cd transport-interop-full-*
./re-run.sh
```

## Understanding Test Combinations

### 3D Test Matrix

Each test has up to 3 dimensions:

1. **Transport** (required): tcp, ws, quic-v1, webrtc-direct, etc.
2. **Secure Channel** (for non-standalone): noise, tls, plaintext
3. **Muxer** (for non-standalone): yamux, mplex

**Standalone transports** (no secure/muxer needed):
- quic, quic-v1 (built-in encryption)
- webtransport (built-in encryption)
- webrtc, webrtc-direct (built-in encryption)

**Example tests:**
```
rust-v0.53 x rust-v0.54 (tcp, noise, yamux)     ← 3D test
rust-v0.53 x rust-v0.54 (tcp, noise, mplex)     ← 3D test
rust-v0.53 x rust-v0.54 (tcp, tls, yamux)       ← 3D test
rust-v0.53 x rust-v0.54 (quic-v1)               ← Standalone (2D)
```

### Matrix Size

With 3 implementations (rust-v0.53, rust-v0.54, python-v0.4):
- Rust has: 4 transports, 2 secure channels, 2 muxers
- Python has: 1 transport (tcp), 2 secure channels, 2 muxers

**Calculation:**
- Rust × Rust: ~40 tests per pair
- Rust × Python: ~4 tests per pair
- Python × Python: ~4 tests

**Total: ~150+ tests** (vs ~10-20 for hole-punch)

## Troubleshooting

### Docker Permission Denied

```bash
sudo usermod -aG docker $USER
newgrp docker
```

### Tests Hanging

```bash
# Check Docker daemon
docker ps

# Check logs
ls logs/
cat logs/<test-name>.log
```

### Cache Issues

```bash
# Clear cache and rebuild
rm -rf /tmp/cache/snapshots/*.zip
./run_tests.sh --cache-dir /tmp/cache
```

### View Individual Test

```bash
# Check generated compose file
cat docker-compose-rust-v0.53_x_rust-v0.54_tcp_noise_yamux.yaml

# View logs
cat logs/rust-v0.53_x_rust-v0.54_tcp_noise_yamux.log
```

## Performance Tips

1. **Use persistent cache**
   ```bash
   mkdir -p /srv/cache
   ./run_tests.sh --cache-dir /srv/cache
   ```

2. **Adjust worker count**
   ```bash
   # Use all cores
   ./run_tests.sh --workers $(nproc)

   # Conservative
   ./run_tests.sh --workers 4
   ```

3. **Filter during development**
   ```bash
   # Only test what you're working on
   ./run_tests.sh --test-filter "rust-v0.54" --workers 2
   ```

## Next Steps

- Read [CONTRIBUTING.md](CONTRIBUTING.md) to add implementations
- Read [ARCHITECTURE.md](ARCHITECTURE.md) to understand internals
- Check [README.md](README.md) for complete documentation

## Example Development Workflow

```bash
# 1. Check dependencies
./run_tests.sh --check-deps

# 2. First run (downloads and builds everything)
./run_tests.sh --cache-dir ~/.cache/libp2p --workers 4

# 3. Add new implementation to impls.yaml
vim impls.yaml

# 4. Test only new version
./run_tests.sh --test-filter "rust-v0.55" --cache-dir ~/.cache/libp2p

# 5. Run full suite
./run_tests.sh --cache-dir ~/.cache/libp2p --workers 8

# 6. Create snapshot for CI
./run_tests.sh --snapshot --cache-dir ~/.cache/libp2p
```
