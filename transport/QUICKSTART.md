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
cd test-plans/transport

# Check dependencies
./run_tests.sh --check-deps

# Run tests (this will take a few minutes)
./run_tests.sh --cache-dir /tmp/cache --workers 4
```

Expected output:
```
                        ╔╦╦╗  ╔═╗
▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁ ║╠╣╚╦═╬╝╠═╗ ▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁
═══════════════════════ ║║║║║║║╔╣║║ ════════════════════════
▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔ ╚╩╩═╣╔╩═╣╔╝ ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔
                            ╚╝  ╚╝

╲ Transport Interoperability Test Suite
 ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔
→ Test Pass: transport-interop-223702-11-11-2025
→ Cache Dir: /srv/cache
→ Test Pass Dir: /srv/cache/test-runs/transport-interop-223702-11-11-2025
→ Workers: 4
→ Create Snapshot: false
→ Debug: false
→ Force Rebuild: false

╲ Checking dependencies...
 ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔
✓ bash 5.2 (minimum: 4.0)
✓ docker 28.5.2 (minimum: 20.10.0)
  ✓ Docker daemon is running
✓ docker compose 2.40.3 (using 'docker compose')
✓ yq 4.48.1 (minimum: 4.0.0)
✓ wget is installed
✓ unzip is installed

╲ ✓ All dependencies are satisfied
 ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔
→ Using: docker compose

╲ Generating test matrix...
 ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔
→ bash scripts/generate-tests.sh "" "" "false"

╲ Test Matrix Generation
 ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔
→ No test-select specified (will include all tests)
→ No test-ignore specified
→ Computed cache key: fdd31961
  → [MISS] Generating new test matrix

→ Found 30 implementations in impls.yaml
→ Loading implementation data into memory...
  ✓ Loaded 30 implementations into memory
  ✓ Loaded 5 ignore patterns

╲ Generating test combinations...
 ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔
✓ Generated 1745 tests (1001 ignored)

╲ ✓ Generated test matrix with 1745 tests (1001 ignored)
 ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔
✓ Cached as: fdd31961.yaml

╲ Building Docker images...
 ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔
→ Building 20 required implementations (including base images)

→ bash scripts/build-images.sh "dotnet-v1.0|eth-p2p-z-v0.0.1|go-v0.38|go-v0.39|go-v0.40|go-v0.41|go-v0.42|go-v0.43|go-v0.44|go-v0.45|js-v1.x|js-v3.x|jvm-v1.2|nim-v1.14|python-v0.4|rust-v0.53|rust-v0.54|rust-v0.55|rust-v0.56|zig-v0.0.1" "false"
  → Cache directory: /srv/cache
  → Filter: dotnet-v1.0|eth-p2p-z-v0.0.1|go-v0.38|go-v0.39|go-v0.40|go-v0.41|go-v0.42|go-v0.43|go-v0.44|go-v0.45|js-v1.x|js-v3.x|jvm-v1.2|nim-v1.14|python-v0.4|rust-v0.53|rust-v0.54|rust-v0.55|rust-v0.56|zig-v0.0.1
  ✓ rust-v0.53 (already built)
  ✓ rust-v0.54 (already built)
  ✓ rust-v0.55 (already built)
  ✓ rust-v0.56 (already built)
  ✓ go-v0.38 (already built)
  ✓ go-v0.39 (already built)
  ✓ go-v0.40 (already built)
  ✓ go-v0.41 (already built)
  ✓ go-v0.42 (already built)
  ✓ go-v0.43 (already built)
  ✓ go-v0.44 (already built)
  ✓ go-v0.45 (already built)
  ✓ python-v0.4 (already built)
  ✓ js-v1.x (already built)
  ✓ js-v3.x (already built)
  ✓ nim-v1.14 (already built)
  ✓ jvm-v1.2 (already built)
  ✓ dotnet-v1.0 (already built)
  ✓ zig-v0.0.1 (already built)
  ✓ eth-p2p-z-v0.0.1 (already built)

✓ All required images built successfully

╲ Test selection...
 ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔
→ Selected tests:
  ✓ rust-v0.53 x rust-v0.53 (ws, tls, mplex)
  ✓ rust-v0.53 x rust-v0.53 (ws, tls, yamux)
  ✓ rust-v0.53 x rust-v0.53 (ws, noise, mplex)
  ✓ rust-v0.53 x rust-v0.53 (ws, noise, yamux)
...

→ Ignored tests:
  ✗ rust-v0.53 x js-v2.x (ws, noise, mplex) [ignored]
  ✗ rust-v0.53 x js-v2.x (ws, noise, yamux) [ignored]
  ✗ rust-v0.53 x js-v2.x (tcp, noise, mplex) [ignored]
  ✗ rust-v0.53 x js-v2.x (tcp, noise, yamux) [ignored]
...

→ Total: 1745 tests to execute, 1001 ignored

╲ Running tests... (4 workers)
 ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔
[3/1745] rust-v0.53 x rust-v0.53 (ws, noise, mplex)
[2/1745] rust-v0.53 x rust-v0.53 (ws, tls, yamux)
[1/1745] rust-v0.53 x rust-v0.53 (ws, tls, mplex)
[4/1745] rust-v0.53 x rust-v0.53 (ws, noise, yamux)
...

╲ Collecting results...
 ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔
→ Results:
  → Total: 1745
  ✓ Passed: 1624
  ✗ Failed: 121
    - rust-v0.53 x python-v0.4 (tcp, noise, mplex)
    - rust-v0.53 x python-v0.4 (tcp, noise, yamux)
    - rust-v0.53 x python-v0.4 (quic-v1)
    - rust-v0.53 x go-v0.38 (webrtc-direct)
      ...

→ Total time: 00:42:29

╲ Generating results dashboard...
 ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔
→ bash scripts/generate-dashboard.sh
  ✓ Generated /srv/cache/test-runs/transport-interop-224128-11-11-2025/results.md
  ✓ Generated /srv/cache/test-runs/transport-interop-224128-11-11-2025/results.html

╲ ✗ 121 test(s) failed
 ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔
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
./run_tests.sh --test-select "rust" --workers 4

# Test only Python
./run_tests.sh --test-select "python" --workers 2

# Test specific version
./run_tests.sh --test-select "rust-v0.53" --workers 4
```

### Test Specific Transports

```bash
# Test only QUIC
./run_tests.sh --test-select "quic" --workers 4

# Test only TCP
./run_tests.sh --test-select "tcp" --workers 8

# Skip WebRTC
./run_tests.sh --test-ignore "webrtc" --workers 4
```

### Test Specific Protocols

```bash
# Test only noise secure channel
./run_tests.sh --test-select "noise" --workers 4

# Test only yamux muxer
./run_tests.sh --test-select "yamux" --workers 4

# Skip plaintext (insecure)
./run_tests.sh --test-ignore "plaintext" --workers 8
```

### Debug Mode

```bash
# Enable debug output in test containers
./run_tests.sh --debug --workers 4

# Combine with filters
./run_tests.sh --test-select "rust-v0.56" --debug --workers 2
```

### Create Debug Snapshot

```bash
# Run with snapshot creation
./run_tests.sh --snapshot --cache-dir /tmp/cache --workers 4

# Snapshot saved to:
# /tmp/cache/test-runs/transport-interop-full-<timestamp>.tar.gz

# Extract and re-run
cd /tmp/cache/test-runs
tar -xzf transport-interop-full-*.tar.gz
cd transport-interop-full-*
./re-run.sh

# Force rebuild all images before re-running
./re-run.sh --force-rebuild
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
   ./run_tests.sh --test-select "rust-v0.54" --workers 2
   ```

## Debugging with Local Implementations

For development and debugging, you can switch implementations from GitHub sources to local directories:

```yaml
# In impls.yaml
implementations:
  - id: rust-v0.56
    source:
      type: local              # Changed from 'github' to 'local'
      path: /home/user/rust-libp2p  # Local clone
      commit: b7914e40        # Still tracked for documentation
      dockerfile: interop-tests/Dockerfile.native
    transports: [tcp, ws, quic-v1]
    secureChannels: [noise, tls]
    muxers: [yamux, mplex]
```

Benefits:
- Make changes without committing to GitHub
- Test modifications immediately
- Use your local IDE and debugging tools
- Faster iteration during development
- Switch back to `github` type when done

Example workflow:
```bash
# 1. Clone repo locally
git clone https://github.com/libp2p/rust-libp2p.git ~/rust-libp2p

# 2. Edit impls.yaml to use local path
vim impls.yaml
# Change rust-v0.56 source type to 'local' and set path

# 3. Make your changes
vim ~/rust-libp2p/transports/tcp/src/transport.rs

# 4. Test with your changes
./run_tests.sh --test-select "rust-v0.56" --force-rebuild --workers 2
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

# 4. Test only new version (with debug output)
./run_tests.sh --test-select "rust-v0.55" --debug --cache-dir ~/.cache/libp2p

# 5. Run full suite
./run_tests.sh --cache-dir ~/.cache/libp2p --workers 8

# 6. Create snapshot for CI
./run_tests.sh --snapshot --cache-dir ~/.cache/libp2p
```
