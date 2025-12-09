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

### 2. Test Locally

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

### 3. Submit Pull Request

Include in your PR:
- Updated `impls.yaml`
- Description of what changed
- Link to the commit in the implementation repo

## Implementation Requirements

Your implementation must:

1. **Build via Dockerfile** - Provide a Dockerfile in your repo
2. **Connect to Redis** - Use `REDIS_ADDR` environment variable
3. **Support MODE** - Handle `MODE=dial` or `MODE=listen` env var
4. **Use TRANSPORT** - Honor `TRANSPORT` environment variable (tcp, quic, etc.)
5. **Implement DCutR Signaling** - Follow the signaling protocol (see below)
6. **Output Results** - Print test results to stdout as JSON
7. **Exit Codes** - Return 0 on success, non-zero on failure
8. **Timeout** - Respect `TEST_TIMEOUT_SECONDS` environment variable
9. **Debug Mode** - Honor `DEBUG=true` environment variable for verbose logging (optional)

### DCutR Signaling Protocol

Your implementation must follow this signaling flow via Redis:

**Environment Variables Provided:**
- `REDIS_ADDR`: Redis server address (e.g., `hole-punch-redis:6379`)
- `TEST_KEY`: Unique test identifier for Redis key namespacing (e.g., `a4be363ecc`)
- `TRANSPORT`: Transport protocol to use (`tcp` or `quic`)
- `MODE`: Role in the test (`dial` or `listen`)

**Listener Implementation:**
1. Connect to Redis
2. Fetch relay multiaddr from Redis (blocking):
   ```
   BLPOP relay:{TEST_KEY}:{transport} 30
   ```
3. Parse the relay multiaddr (includes relay peer ID)
4. Connect to the relay server
5. Publish your peer ID to Redis:
   ```
   RPUSH listener:{TEST_KEY}:peer_id {your_peer_id}
   EXPIRE listener:{TEST_KEY}:peer_id 300
   ```
6. Wait for incoming relay circuit connection from dialer
7. DCutR protocol negotiates hole punch automatically
8. Verify direct connection established
9. Send/receive test data
10. Report results and exit

**Dialer Implementation:**
1. Connect to Redis
2. Fetch relay multiaddr from Redis (blocking):
   ```
   BLPOP relay:{TEST_KEY}:{transport} 30
   ```
3. Fetch listener peer ID from Redis (blocking):
   ```
   BLPOP listener:{TEST_KEY}:peer_id 30
   ```
4. Parse the relay multiaddr and listener peer ID
5. Connect to the relay server
6. Construct relay circuit address:
   ```
   {relay_multiaddr}/p2p-circuit/p2p/{listener_peer_id}
   ```
7. Initiate connection to listener via relay circuit
8. DCutR protocol negotiates hole punch automatically
9. Verify direct connection established
10. Send/receive test data
11. Report results and exit

**Example Redis Keys:**
```
relay:a4be363ecc:tcp          → /ip4/10.151.84.65/tcp/4001/p2p/12D3KooW...
relay:a4be363ecc:quic         → /ip4/10.151.84.65/udp/4001/quic-v1/p2p/12D3KooW...
listener:a4be363ecc:peer_id   → 12D3KooWListenerPeerID...
```

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

### Example Implementation: Python (py-libp2p)

Here's a complete example showing how to add py-libp2p to the test suite:

**1. Add to impls.yaml:**
```yaml
implementations:
  - id: py-libp2p-v0.1.5
    source:
      type: github
      repo: libp2p/py-libp2p
      commit: a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0  # Full 40-char SHA
      dockerfile: tests/hole-punch/Dockerfile
    transports:
      - tcp
```

**2. Create Dockerfile in your repo (`tests/hole-punch/Dockerfile`):**
```dockerfile
FROM python:3.11-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt redis

# Copy test implementation
COPY tests/hole-punch/hole_punch_test.py .

ENTRYPOINT ["python", "hole_punch_test.py"]
```

**3. Implement the test (`tests/hole-punch/hole_punch_test.py`):**
```python
#!/usr/bin/env python3
import os
import sys
import time
import json
import redis
from libp2p import new_host
from libp2p.network.stream.net_stream_interface import INetStream
from multiaddr import Multiaddr

def main():
    # Read environment variables
    redis_addr = os.environ['REDIS_ADDR']
    test_key = os.environ['TEST_KEY']
    transport = os.environ['TRANSPORT']
    mode = os.environ['MODE']
    timeout = int(os.environ.get('TEST_TIMEOUT_SECONDS', '30'))

    # Connect to Redis
    redis_host, redis_port = redis_addr.split(':')
    r = redis.Redis(host=redis_host, port=int(redis_port))

    if mode == 'listen':
        run_listener(r, test_key, transport, timeout)
    else:
        run_dialer(r, test_key, transport, timeout)

def run_listener(r, test_key, transport, timeout):
    """Listener: Wait for dialer to hole punch and connect"""
    start_time = time.time()

    # 1. Create libp2p host
    host = new_host(transport=[transport])

    # 2. Fetch relay multiaddr from Redis
    relay_key = f"relay:{test_key}:{transport}"
    result = r.blpop(relay_key, timeout=30)
    if not result:
        print(f"ERROR: Timeout waiting for relay address at {relay_key}")
        sys.exit(1)

    relay_addr = result[1].decode('utf-8')
    print(f"Fetched relay address: {relay_addr}")

    # 3. Connect to relay
    relay_multiaddr = Multiaddr(relay_addr)
    await host.connect(relay_multiaddr)
    print(f"Connected to relay")

    # 4. Publish our peer ID to Redis
    my_peer_id = str(host.get_id())
    listener_key = f"listener:{test_key}:peer_id"
    r.rpush(listener_key, my_peer_id)
    r.expire(listener_key, 300)
    print(f"Published peer ID: {my_peer_id}")

    # 5. Set up stream handler for incoming connections
    connection_established = False

    async def stream_handler(stream: INetStream):
        nonlocal connection_established
        connection_established = True
        # Read test data from dialer
        data = await stream.read(1024)
        print(f"Received: {data.decode('utf-8')}")
        # Echo back
        await stream.write(b"PONG from listener")
        await stream.close()

    host.set_stream_handler("/hole-punch-test/1.0.0", stream_handler)

    # 6. Wait for connection with timeout
    while time.time() - start_time < timeout:
        if connection_established:
            # Success! Direct connection established via hole punch
            elapsed = (time.time() - start_time) * 1000
            result = {
                "handshakePlusOneRTTMillis": elapsed,
                "pingRTTMilllis": 0  # Not measured in this simple example
            }
            print(json.dumps(result))
            sys.exit(0)
        time.sleep(0.1)

    print("ERROR: Timeout waiting for connection")
    sys.exit(1)

def run_dialer(r, test_key, transport, timeout):
    """Dialer: Fetch relay and listener info, initiate hole punch"""
    start_time = time.time()

    # 1. Create libp2p host
    host = new_host(transport=[transport])

    # 2. Fetch relay multiaddr from Redis
    relay_key = f"relay:{test_key}:{transport}"
    result = r.blpop(relay_key, timeout=30)
    if not result:
        print(f"ERROR: Timeout waiting for relay address at {relay_key}")
        sys.exit(1)

    relay_addr = result[1].decode('utf-8')
    print(f"Fetched relay address: {relay_addr}")

    # 3. Fetch listener peer ID from Redis
    listener_key = f"listener:{test_key}:peer_id"
    result = r.blpop(listener_key, timeout=30)
    if not result:
        print(f"ERROR: Timeout waiting for listener peer ID at {listener_key}")
        sys.exit(1)

    listener_peer_id = result[1].decode('utf-8')
    print(f"Fetched listener peer ID: {listener_peer_id}")

    # 4. Connect to relay
    relay_multiaddr = Multiaddr(relay_addr)
    await host.connect(relay_multiaddr)
    print(f"Connected to relay")

    # 5. Construct relay circuit address to listener
    circuit_addr = f"{relay_addr}/p2p-circuit/p2p/{listener_peer_id}"
    circuit_multiaddr = Multiaddr(circuit_addr)
    print(f"Connecting via relay circuit: {circuit_addr}")

    # 6. Initiate connection via relay circuit
    # DCutR will automatically negotiate hole punch
    stream = await host.new_stream(circuit_multiaddr, ["/hole-punch-test/1.0.0"])

    # 7. Send test data
    await stream.write(b"PING from dialer")
    response = await stream.read(1024)
    print(f"Received: {response.decode('utf-8')}")
    await stream.close()

    # 8. Success! Report metrics
    elapsed = (time.time() - start_time) * 1000
    result = {
        "handshakePlusOneRTTMillis": elapsed,
        "pingRTTMilllis": 0  # Not measured in this simple example
    }
    print(json.dumps(result))
    sys.exit(0)

if __name__ == '__main__':
    main()
```

**4. Test your implementation:**
```bash
# Add to impls.yaml first
vim impls.yaml

# Run tests filtered to your implementation
./run_tests.sh --test-select "py-libp2p" --debug --yes

# Cross-test with other implementations
./run_tests.sh --test-select "py-libp2p|rust" --yes
```

**Key Points:**
- Use Redis `BLPOP` for blocking fetch (waits up to 30 seconds)
- Always use namespaced keys: `relay:{TEST_KEY}:{transport}` and `listener:{TEST_KEY}:peer_id`
- Construct relay circuit address: `{relay_addr}/p2p-circuit/p2p/{listener_peer_id}`
- DCutR negotiation happens automatically when using relay circuit
- Print JSON results to stdout for metric collection
- Exit 0 on success, non-zero on failure

### Updating Existing Implementations

If you have an existing implementation that needs to be updated for the new signaling protocol:

1. **Update to use TEST_KEY in Redis keys** - Change from global keys to namespaced keys
2. **Add listener peer ID publishing** - Listener must publish its peer ID to Redis
3. **Update dialer to fetch listener peer ID** - Dialer must fetch both relay address and listener peer ID
4. **Ensure proper key expiry** - All Redis keys should have TTL set to 300 seconds

The relay has been updated to use the new protocol, so all test implementations must follow the DCutR signaling flow documented above.

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

This creates a self-contained archive in `/srv/cache/test-runs/` that can be:
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
cd /srv/cache/test-runs/hole-punch-rust-143022-08-11-2025
./re-run.sh
```

## CI Integration

### GitHub Actions Example

```yaml
name: Hole Punch Interop

on:
  pull_request:
    paths:
      - 'hole-punch/**'
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
          cd hole-punch
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
            hole-punch/results.yaml
            hole-punch/results.md
            hole-punch/results.html

      - name: Upload snapshot
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: test-snapshot
          path: /tmp/cache/test-runs/*.tar.gz
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
- **Test passes**: `/srv/cache/test-runs/hole-punch-<timestamp>/`

## Questions?

- Check existing implementations in `impls.yaml`
- Read the main README.md
- Open an issue for questions
