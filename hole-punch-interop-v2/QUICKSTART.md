# Quick Start Guide

Get up and running with hole punch interop tests in 5 minutes.

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
# Clone repository
git clone https://github.com/libp2p/test-plans
cd test-plans/hole-punch-interop-v2

# Check dependencies
./run_tests.sh --check-deps

# Run tests (this will take a few minutes)
./run_tests.sh --cache-dir /tmp/cache --workers 2
```

Expected output:
```
╔════════════════════════════════════════════════════════════╗
║  Hole Punch Interoperability Test Suite                   ║
╚════════════════════════════════════════════════════════════╝

Test Pass: hole-punch-full
Cache Dir: /tmp/cache
Workers: 2

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Checking dependencies...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✓ bash 5.1.16 (minimum: 4.0)
✓ git 2.34.1 (minimum: 2.0.0)
✓ docker 24.0.5 (minimum: 20.10.0)
✓ Docker daemon is running
✓ yq 4.35.1 (minimum: 4.0.0)
✓ wget is installed
✓ unzip is installed

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Building Docker images...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Building: rust-v0.53
  Repo: libp2p/rust-libp2p
  Commit: b7914e40
→ Downloading snapshot...
  ✓ Cached: b7914e40.zip
→ Extracting snapshot...
→ Building Docker image...
  ✓ Built image: rust-v0.53

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✓ All images built successfully
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

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

# Generate HTML (if pandoc installed)
pandoc -f markdown -t html -s -o results.html results.md
open results.html  # or xdg-open on Linux
```

## Common Tasks

### Run Specific Tests

```bash
# Test only Rust
./run_tests.sh --test-filter "rust" --workers 4

# Test only QUIC transport
./run_tests.sh --test-filter "quic" --workers 4

# Test specific version
./run_tests.sh --test-filter "rust-v0.53" --workers 2
```

### Ignore Problematic Tests

```bash
# Skip TCP tests
./run_tests.sh --test-ignore "tcp" --workers 4

# Skip self-tests
./run_tests.sh --test-ignore "rust-v0.53 x rust-v0.53" --workers 4
```

### Create Debug Snapshot

```bash
# Run with snapshot creation
./run_tests.sh --snapshot --cache-dir /tmp/cache --workers 4

# Snapshot saved to:
# /tmp/cache/test-passes/hole-punch-full-<timestamp>.tar.gz

# Extract and re-run
cd /tmp/cache/test-passes
tar -xzf hole-punch-full-*.tar.gz
cd hole-punch-full-*
./re-run.sh
```

### Adjust Parallelism

```bash
# Use all CPU cores
./run_tests.sh --workers $(nproc)

# Conservative (2 workers)
./run_tests.sh --workers 2

# Maximum speed (CPU count + 1)
./run_tests.sh --workers $(($(nproc) + 1))
```

## Troubleshooting

### Docker Permission Denied

```bash
sudo usermod -aG docker $USER
newgrp docker
# Or logout and login again
```

### yq Not Found

```bash
# Download and install manually
sudo wget -qO /usr/local/bin/yq \
  https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
sudo chmod +x /usr/local/bin/yq
```

### Tests Hanging

Check if Docker daemon is running:
```bash
docker ps
```

Check if Redis is reachable:
```bash
docker exec hole-punch-redis redis-cli ping
```

### Cache Issues

Clear cache and rebuild:
```bash
rm -rf /tmp/cache/snapshots/*.zip
./run_tests.sh --cache-dir /tmp/cache
```

### View Test Logs

```bash
# List all logs
ls logs/

# View specific test log
cat logs/rust-v0.53_x_rust-v0.53_tcp.log

# View all failed tests
grep -l "failed" logs/*.log
```

## Next Steps

- Read [CONTRIBUTING.md](CONTRIBUTING.md) to add implementations
- Read [ARCHITECTURE.md](ARCHITECTURE.md) to understand internals
- Check [README.md](README.md) for complete documentation

## Getting Help

- Check logs in `logs/` directory
- Review generated `docker-compose-*.yaml` files
- Run with reduced workers (`--workers 1`) for easier debugging
- Create snapshot with `--snapshot` flag and share for bug reports

## Performance Tips

1. **Use persistent cache directory**
   ```bash
   export CACHE_DIR=/srv/cache
   ./run_tests.sh --cache-dir /srv/cache
   ```

2. **Adjust worker count**
   - More workers = faster tests
   - But too many can overwhelm Docker
   - Start with `--workers 4`

3. **Filter tests during development**
   ```bash
   # Only test what you're working on
   ./run_tests.sh --test-filter "rust-v0.54"
   ```

4. **Reuse snapshots**
   - First run downloads everything
   - Subsequent runs use cache
   - Never re-downloads same commit

## Example Workflow

```bash
# 1. Initial setup
./run_tests.sh --check-deps

# 2. First run (downloads everything)
./run_tests.sh --cache-dir ~/.cache/libp2p --workers 4

# 3. Add new implementation
vim impls.yaml
# Add rust-v0.54 entry

# 4. Test only new version
./run_tests.sh --test-filter "rust-v0.54" --cache-dir ~/.cache/libp2p

# 5. Run full test suite
./run_tests.sh --cache-dir ~/.cache/libp2p --workers 8

# 6. Create snapshot for CI
./run_tests.sh --snapshot --cache-dir ~/.cache/libp2p --workers 8
```

## CI Integration

See [CONTRIBUTING.md](CONTRIBUTING.md) for GitHub Actions example.

Quick setup:
1. Add yq installation step
2. Run `./run_tests.sh --snapshot`
3. Upload `results.yaml` and snapshots as artifacts
