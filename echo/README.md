# Echo Protocol Interoperability Tests

Pure-bash implementation of Echo protocol interoperability tests for libp2p implementations.

## Overview

The echo test suite validates that different libp2p implementations can successfully communicate using the Echo protocol (`/echo/1.0.0`). This test specifically focuses on **js-libp2p** and **py-libp2p** interoperability, addressing the Universal Connectivity initiative requirements for 2026.

**Implementations tested**:
- **js-libp2p**: v1.x (Node.js Echo Server)
- **py-libp2p**: v0.5.0 (Python Test Harness)

**Transport protocols**:
- **tcp**: TCP transport

**Security and multiplexing**:
- **Secure Channels**: noise
- **Muxers**: yamux, mplex

## What It Measures

The Echo protocol test validates **full bidirectional stream read/write capabilities** including:

- **Stream Handling**: Proper stream setup, read, and write operations
- **Muxing**: Stream multiplexing over a single connection
- **Window Management**: Flow control and backpressure handling
- **Payload Integrity**: Exact echo verification across different data types
- **Connection Lifecycle**: Proper setup and teardown

Each test runs a **JavaScript Echo Server** against a **Python Test Client** using Docker containers and measures:

- **Connectivity**: Can client connect to server successfully?
- **Protocol Compliance**: Does server properly handle `/echo/1.0.0` protocol?
- **Data Integrity**: Does echoed data exactly match original payload?
- **Payload Types**: Text, binary, and large data handling
- **Error Handling**: Timeout and failure scenario management

## Why Echo vs Ping?

Echo protocol testing is critical because it tests **full stream capabilities** that simple Ping tests often miss:

- **Stream Muxing**: Multiple concurrent streams over one connection
- **Window Management**: Flow control and backpressure scenarios  
- **Payload Integrity**: Large data transfers with verification
- **Edge Cases**: Yamux hangs, stream reset handling, partial reads/writes

Ping tests only verify basic connectivity, while Echo tests validate the complete stream handling stack.

## Test Cases

The test harness validates multiple payload scenarios:

```python
test_cases = [
    b"Hello, Echo!",           # Text payload
    b"\x00\x01\x02\x03\x04",  # Binary data
    b"A" * 1024,              # Large payload (1KB)
]
```

Each test case verifies:
1. **Connection establishment** between py-libp2p client and js-libp2p server
2. **Protocol negotiation** for `/echo/1.0.0`
3. **Data transmission** from client to server
4. **Echo response** from server back to client
5. **Payload verification** ensuring exact match
6. **Connection cleanup** and resource management

## How to Run Tests

### Prerequisites

Check dependencies:
```bash
./run.sh --check-deps
```

Required: bash 4.0+, docker 20.10+, yq 4.0+, redis (for coordination)

### Basic Usage

```bash
# Run all echo interop tests
./run.sh

# Run with debug output
./run.sh --debug

# Run with custom timeout
./run.sh --timeout 300

# Run specific test combinations
./run.sh --test-select "js-libp2p-echo-v1.x"
```

### Docker-based Testing

For development and debugging:

```bash
# Run complete Docker orchestration test
./test-echo.sh

# This will:
# 1. Start Redis coordination service
# 2. Build and start JS echo server container
# 3. Run Python test client container
# 4. Verify echo protocol functionality
# 5. Clean up all containers and networks
```

### Manual Testing

For step-by-step debugging:

```bash
# Build Docker images
docker build -t js-libp2p-echo:v1.x images/js-libp2p/v1.x/
docker build -t py-libp2p-echo:v0.x images/py-libp2p/v0.x/

# Start Redis
docker run -d --name redis-test -p 6379:6379 redis:alpine

# Start JS echo server
docker run -d --name js-server \
  -e REDIS_ADDR=redis://localhost:6379 \
  js-libp2p-echo:v1.x

# Run Python test client
docker run --rm --name py-client \
  -e REDIS_ADDR=redis://localhost:6379 \
  py-libp2p-echo:v0.x
```

## Architecture

```
echo-interop/
├── run.sh                    # Framework integration entry point
├── test-echo.sh             # Docker orchestration script  
├── images.yaml              # Implementation definitions
├── images/
│   ├── js-libp2p/v1.x/     # JavaScript Echo Server
│   │   ├── Dockerfile       # Node.js 18 Alpine container
│   │   ├── package.json     # libp2p + redis dependencies
│   │   └── src/index.js     # Echo server implementation
│   └── py-libp2p/v0.x/     # Python Test Harness
│       ├── Dockerfile       # Python 3.11 container
│       ├── requirements.txt # libp2p + trio + redis deps
│       └── main.py          # Trio-based test client
└── README.md               # This file
```

### JavaScript Echo Server (`/echo/1.0.0`)

The server implementation:
- **Listens** on configurable TCP port
- **Handles** `/echo/1.0.0` protocol requests
- **Reads** incoming stream data
- **Echoes** exact data back to client
- **Publishes** multiaddr to Redis for client discovery
- **Logs** all operations for debugging

### Python Test Harness

The client implementation:
- **Discovers** server multiaddr from Redis
- **Connects** to js-libp2p server
- **Negotiates** `/echo/1.0.0` protocol
- **Sends** multiple test payloads
- **Verifies** echo responses match exactly
- **Reports** results in structured JSON format

### Coordination

Redis is used for container coordination:
- **Server** publishes its multiaddr to `js-echo-server-multiaddr` key
- **Client** polls Redis until server multiaddr is available
- **Timeout** handling prevents indefinite waiting
- **Cleanup** removes coordination data after tests

## Test Results

Successful test output:
```json
{
  "test": "echo-protocol",
  "transport": "tcp",
  "security": "noise", 
  "muxer": "yamux",
  "duration": 5.234,
  "results": [
    {"status": "passed", "data_length": 13},
    {"status": "passed", "data_length": 5},
    {"status": "passed", "data_length": 1024}
  ],
  "passed": true
}
```

## Troubleshooting

### Common Issues

**Container build failures**:
```bash
# Clean Docker cache and rebuild
docker system prune -f
./test-echo.sh
```

**Redis connection errors**:
```bash
# Check Redis is running
docker ps | grep redis
# Check network connectivity
docker network ls
```

**libp2p version conflicts**:
```bash
# Check dependency versions
docker run --rm js-libp2p-echo:v1.x npm list
docker run --rm py-libp2p-echo:v0.x pip list
```

### Debug Mode

Enable verbose logging:
```bash
# Framework debug
./run.sh --debug

# Container debug
docker run --rm -e DEBUG=true js-libp2p-echo:v1.x
```

## Contributing

This implementation follows test-plans conventions:

1. **Framework Integration**: Uses `lib-test-execution.sh`
2. **Docker Containers**: Isolated, reproducible environments
3. **Configuration**: Structured `images.yaml` definitions
4. **Error Handling**: Proper cleanup and timeout management
5. **Documentation**: Comprehensive inline comments

For modifications:
1. Update implementation code in `images/*/src/`
2. Rebuild Docker images
3. Test locally with `./test-echo.sh`
4. Verify framework integration with `./run.sh`

## Related Work

This implementation complements existing libp2p interop tests:
- **nim-libp2p**: Existing Echo protocol tests
- **go-libp2p**: Active Echo/Ping work (#1136)
- **rust-libp2p**: Active interop development (#1142)

Part of the **Universal Connectivity 2026 initiative** to ensure comprehensive cross-implementation compatibility.