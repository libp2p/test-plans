# Contributing to Hole Punch Interop Tests

Thank you for contributing to the libp2p hole punch interoperability tests!

## Adding a New Implementation

### 1. Add to impls.yaml

Add your implementation to `impls.yaml`:

```yaml
implementations:
  - id: rust-v0.54
    source:
      type: github
      repo: libp2p/rust-libp2p
      commit: <full-40-char-commit-sha>
      dockerfile: hole-punching-tests/Dockerfile
    transports:
      - tcp
      - quic
      - webtransport  # Add any supported transports
```

**Important:**
- Use full 40-character commit SHA (not short SHA)
- Dockerfile path is relative to repository root
- Only list transports that your implementation supports

### 2. Update test-selection.yaml (Optional)

Update global test selection defaults (`test-selection.yaml`):

```yaml
test-select: []  # Empty = all tests (or add specific filters)

test-ignore:
  - experimental  # Global ignores apply to all tests
  - flaky
```

**Note:** Test filtering is primarily done via CLI args, not YAML files.

### 3. Test Locally

```bash
# Build only your implementation
export CACHE_DIR=/tmp/cache
bash scripts/build-images.sh rust-v0.54

# Run tests filtered to your implementation
./run_tests.sh --test-select "rust-v0.54" --cache-dir /tmp/cache --workers 4

# Run with debug output enabled
./run_tests.sh --test-select "rust-v0.54" --debug --yes

# Force rebuild images
./run_tests.sh --test-select "rust-v0.54" --force-rebuild
```

### 4. Submit Pull Request

Include in your PR:
- Updated `impls.yaml`
- Any test-selection changes
- Description of what changed
- Link to the commit in the implementation repo

## Implementation Requirements

Your implementation must:

1. **Build via Dockerfile** - Provide a Dockerfile in your repo
2. **Connect to Redis** - Use `REDIS_ADDR` environment variable
3. **Support MODE** - Handle `MODE=dial` or `MODE=listen` env var
4. **Use TRANSPORT** - Honor `TRANSPORT` environment variable (tcp, quic, etc.)
5. **Output Results** - Print test results to stdout
6. **Exit Codes** - Return 0 on success, non-zero on failure
7. **Timeout** - Respect `TEST_TIMEOUT_SECONDS` environment variable
8. **Debug Mode** - Honor `DEBUG=true` environment variable for verbose logging (optional)

### Example Dockerfile

```dockerfile
FROM rust:1.70 AS builder

WORKDIR /app
COPY . .
RUN cargo build --release --example hole-punch-test

FROM debian:bookworm-slim
COPY --from=builder /app/target/release/examples/hole-punch-test /usr/local/bin/

ENTRYPOINT ["hole-punch-test"]
```

### Example Test Implementation

Your test binary should:

```rust
fn main() {
    let redis_addr = env::var("REDIS_ADDR").unwrap();
    let mode = env::var("MODE").unwrap(); // "dial" or "listen"
    let transport = env::var("TRANSPORT").unwrap();
    let timeout = env::var("TEST_TIMEOUT_SECONDS")
        .unwrap_or("30".to_string())
        .parse::<u64>()
        .unwrap();

    if mode == "listen" {
        run_listener(redis_addr, transport, timeout);
    } else {
        run_dialer(redis_addr, transport, timeout);
    }
}
```

## Testing Best Practices

### Cache Directory

Always use a cache directory to avoid re-downloading:

```bash
export CACHE_DIR=/srv/cache
./run_tests.sh --cache-dir /srv/cache
```

### Parallel Workers

Adjust worker count based on your machine:

```bash
# Use all CPU cores
./run_tests.sh --workers $(nproc)

# Conservative (half cores)
./run_tests.sh --workers $(($(nproc) / 2))
```

### Filtering Tests

```bash
# Test only Rust implementations
./run_tests.sh --test-select "rust"

# Test only TCP transport
./run_tests.sh --test-select "tcp"

# Test specific version
./run_tests.sh --test-select "rust-v0.54"

# Ignore flaky tests
./run_tests.sh --test-ignore "experimental"
```

### Creating Snapshots

For debugging or CI artifacts:

```bash
./run_tests.sh --snapshot --cache-dir /srv/cache
```

This creates a self-contained archive in `/srv/cache/test-passes/` that can be:
- Shared with other developers
- Attached to bug reports
- Re-run on any machine with bash, docker, git, yq

## Debugging Failed Tests

### 1. Check Logs

Individual test logs are in `logs/`:

```bash
ls logs/
cat logs/rust-v0.53_x_go-v0.43_tcp.log
```

### 2. Inspect Docker Compose

Generated compose files show exact configuration:

```bash
cat docker-compose-rust-v0.53_x_go-v0.43_tcp.yaml
```

### 3. Manual Container Inspection

```bash
# List running containers
docker ps

# Check logs
docker logs <container-id>

# Inspect network
docker network inspect hole-punch-network
```

### 4. Run Single Test

```bash
bash scripts/start-global-services.sh
bash scripts/run-single-test.sh \
  "rust-v0.53 x go-v0.43 (tcp)" \
  "rust-v0.53" \
  "go-v0.43" \
  "tcp"
bash scripts/stop-global-services.sh
```

### 5. Re-run from Snapshot

If you have a snapshot:

```bash
cd /srv/cache/test-passes/hole-punch-rust-143022-08-11-2025
./re-run.sh
```

## CI Integration

### GitHub Actions Example

```yaml
name: Hole Punch Interop

on:
  pull_request:
    paths:
      - 'hole-punch-interop-v2/**'
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
          cd hole-punch-interop-v2
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
            hole-punch-interop-v2/results.yaml
            hole-punch-interop-v2/results.md
            hole-punch-interop-v2/results.html

      - name: Upload snapshot
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: test-snapshot
          path: /tmp/cache/test-passes/*.tar.gz
```

## Updating Commit Hashes

To update an implementation to a new commit:

```bash
# 1. Update impls.yaml with new commit SHA
vim impls.yaml

# 2. Clear cached snapshot (force rebuild)
rm /srv/cache/snapshots/<old-commit>.zip

# 3. Run tests
./run_tests.sh --test-select "rust-v0.54"
```

## Architecture Overview

### Hybrid Architecture

- **Global Services** (started once per test run):
  - Redis: Coordination bus
  - Relay: Shared relay server
  - Network: `hole-punch-network`

- **Per-Test Services** (via docker-compose):
  - Dialer: Implementation under test
  - Listener: Implementation under test
  - Dialer Router: NAT simulation
  - Listener Router: NAT simulation

### Test Flow

```
1. Build images from source snapshots
2. Generate test matrix (all combinations)
3. Start global services (Redis, Relay)
4. For each test (in parallel):
   a. Generate docker-compose.yaml
   b. Start 4 containers
   c. Wait for completion
   d. Collect results
   e. Cleanup
5. Aggregate results
6. Generate dashboard
7. Stop global services
```

### Content-Addressed Caching

All artifacts are cached by content hash:

- **Snapshots**: `/srv/cache/snapshots/<commit-sha>.zip`
- **Test matrices**: `/srv/cache/test-matrix/<sha256>.yaml`
- **Test passes**: `/srv/cache/test-passes/hole-punch-<timestamp>/`

## Questions?

- Check existing implementations in `impls.yaml`
- Read the main README.md
- Open an issue for questions
