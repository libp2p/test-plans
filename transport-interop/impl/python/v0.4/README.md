# Python libp2p Ping Test Implementation

This directory contains the Python implementation of the libp2p ping test for transport-interop testing.

## Overview

The Python implementation follows the transport-interop test specification and provides:
- Support for TCP transport
- Support for Noise and Plaintext security protocols
- Support for Mplex and Yamux multiplexers
- Both dialer and listener roles
- Redis-based coordination
- JSON output format for test results
- Integration with py-libp2p's logging system via `LIBP2P_DEBUG` environment variable

### Protocol Support

| Protocol Type | Supported Values | Notes |
|---------------|------------------|-------|
| **Transports** | `tcp` | Only TCP is currently supported |
| **Security** | `noise`, `plaintext` | Noise and plaintext security |
| **Muxers** | `mplex`, `yamux` | Both multiplexers supported |

**Note:** Python has limited transport support compared to other implementations:
- **Go**: TCP, WebSocket, QUIC, WebTransport, WebRTC
- **Rust**: TCP, WebSocket, QUIC, WebRTC
- **JS (Node.js)**: TCP, WebSocket, WebSocket Secure
- **JS (Browser)**: WebTransport, WebSocket Secure, WebRTC Direct, WebRTC

## Files

- `ping_test.py` - Main implementation of the ping test
- `pyproject.toml` - Python project configuration and dependencies
- `PingDockerfile` - Docker configuration for the test
- `Makefile` - Build configuration 
- `.gitignore` - Git ignore rules (excludes build artifacts)
- `README.md` - This file

## Building

To build the Docker image:

```bash
make
```

This will:
1. Install py-libp2p from the specified git commit
2. Build the Docker image
3. Generate the `image.json` file with the image ID

### Build Options

```bash
# Build with cache (fast)
make all

# Build without cache (ensures latest git packages)
make force-rebuild

# Verify all dependencies are correctly installed
make verify-deps

# Show image information (ID, size, creation date)
make image-info

# Test run the ping test (without Redis)
make test-run

# Check libp2p version in the image
make version-check

# Clean build artifacts and Docker image
make clean

# Show help
make help
```

## Running Locally

To run the test locally (for debugging):

1. Start Redis:
```bash
docker run --rm -p 6379:6379 redis:7-alpine
```

2. Run as listener:
```bash
transport=tcp muxer=mplex security=noise is_dialer=false ip="0.0.0.0" redis_addr=localhost:6379 python ping_test.py
```

3. Run as dialer:
```bash
transport=tcp muxer=mplex security=noise is_dialer=true redis_addr=localhost:6379 python ping_test.py
```

**Alternative configurations:**

With Yamux multiplexer:
```bash
transport=tcp muxer=yamux security=noise is_dialer=true redis_addr=localhost:6379 python ping_test.py
```

With Plaintext security:
```bash
transport=tcp muxer=mplex security=plaintext is_dialer=true redis_addr=localhost:6379 python ping_test.py
```

### Expected Output

**Listener output:**
```
Connected to Redis at localhost:6379
Running as listener
Publishing address to Redis: /ip4/0.0.0.0/tcp/XXXXX/p2p/16Uiu2HAkvpyXQ1BuqHbLKASmVe5tLZrQKxgKL75crGV2fVNNBcRF
Waiting for 15 seconds...
received ping from QmXXXXX...
responded with pong to QmXXXXX...
```

**Dialer output:**
```
Connected to Redis at localhost:6379
Running as dialer
Waiting for listener address from Redis...
Got listener address: /ip4/0.0.0.0/tcp/XXXXX/p2p/16Uiu2HAkvpyXQ1BuqHbLKASmVe5tLZrQKxgKL75crGV2fVNNBcRF
Connecting to /ip4/0.0.0.0/tcp/XXXXX/p2p/16Uiu2HAkvpyXQ1BuqHbLKASmVe5tLZrQKxgKL75crGV2fVNNBcRF
Creating ping stream
sending ping to QmXXXXX...
received pong from QmXXXXX...
{"handshakePlusOneRTTMillis": 43.84, "pingRTTMilllis": 0.26}
```



## Environment Variables

The implementation reads the following environment variables:

- `transport` - Transport protocol (tcp)
- `muxer` - Multiplexer (mplex, yamux)
- `security` - Security protocol (noise, plaintext)
- `is_dialer` - Whether to run as dialer (true) or listener (false)
- `ip` - IP address to bind to (default: 0.0.0.0)
- `redis_addr` - Redis server address (default: redis:6379)
- `test_timeout_seconds` - Test timeout in seconds (default: 180)
- `LIBP2P_DEBUG` - Enable debug logging (e.g., "DEBUG", "ping_test:DEBUG")
- `LIBP2P_DEBUG_FILE` - Custom log file path for debug output

### Environment Variable Examples

```bash
# Basic configuration
export transport=tcp
export muxer=mplex
export security=noise
export is_dialer=true
export redis_addr=localhost:6379

# Advanced configuration
export ip="127.0.0.1"
export test_timeout_seconds=30
export LIBP2P_DEBUG=DEBUG
export LIBP2P_DEBUG_FILE=/tmp/custom.log
```

## Output Format

The dialer outputs JSON to stdout with the following format:
```json
{
  "handshakePlusOneRTTMillis": 123.45,
  "pingRTTMilllis": 12.34
}
```

All diagnostic output goes to stderr.

### Performance Benchmarks

For localhost testing, expect:
- **handshakePlusOneRTTMillis**: 20-100ms
- **pingRTTMilllis**: 0.1-5ms
- **Memory Usage**: < 100MB
- **CPU Usage**: < 10% during active testing

| Configuration | Handshake + RTT (ms) | Ping RTT (ms) |
|---------------|---------------------|---------------|
| TCP + Noise + Yamux | 10-15 | 0.2-0.5 |
| TCP + Noise + Mplex | 8-12 | 0.2-0.4 |
| TCP + Plaintext + Yamux | 5-10 | 0.1-0.3 |
| TCP + Plaintext + Mplex | 4-8 | 0.1-0.2 |

## Debugging and Logging

The implementation integrates with py-libp2p's built-in logging system:

### Enable Debug Logging
```bash
# Enable all debug output
export LIBP2P_DEBUG=DEBUG
python ping_test.py

# Enable debug only for ping_test module
export LIBP2P_DEBUG=ping_test:DEBUG
python ping_test.py

# Log to custom file
export LIBP2P_DEBUG=DEBUG
export LIBP2P_DEBUG_FILE=/tmp/custom.log
python ping_test.py
```

### Debug Features
- **Automatic Integration**: No manual logging setup required
- **Thread-Safe**: Uses py-libp2p's queue-based logging system
- **Automatic File Logging**: Creates timestamped log files in `/tmp/`
- **Hierarchical Control**: Enable debug for specific modules
- **Zero Overhead**: No debug output when `LIBP2P_DEBUG` is not set

## Dependencies

### Python Dependencies
- `libp2p` - Python libp2p implementation (from git commit)
- `redis` - Redis client for coordination
- `typing-extensions` - Type hints support

**Note:** `trio` and `multiaddr` are transitive dependencies included with `libp2p`.

### Docker System Dependencies
The Docker image includes the following system packages:
- `git` - Required for installing py-libp2p from git repository
- `build-essential` - C/C++ compiler and build tools
- `cmake` - Build system generator
- `pkg-config` - Package configuration utility
- `libgmp-dev` - GNU Multiple Precision Arithmetic Library

## Testing

### Manual Testing
For detailed manual testing instructions, see the comprehensive guide in https://github.com/libp2p/py-libp2p/discussions/850

### Automated Testing
The implementation integrates with the transport-interop framework for automated testing:

```bash
# Test Python implementation
npm test -- --name-filter="python-v0.2.9"

# Test against specific implementation
npm test -- --name-filter="python-v0.2.9 x js-v1.x"

# Test bidirectional
npm test -- --name-filter="python-v0.2.9 x js-v1.x|js-v1.x x python-v0.2.9"
```

### Cross-Implementation Testing
The Python implementation has been tested against:
- **JS-libp2p v1.x and v2.x**
- **Rust-libp2p v0.53 and v0.54**
- **Go-libp2p v0.40, v0.41, and v0.42**

All supported protocol combinations (TCP + Noise/Plaintext + Mplex/Yamux) have been verified for interoperability.

## Troubleshooting

### Common Issues

1. **Redis Connection Failed**: Ensure Redis is running and accessible
2. **Docker Image Not Found**: Run `make clean && make` to rebuild
3. **Port Already in Use**: Wait for previous test to complete or kill processes
4. **Timeout Waiting for Listener**: Check if listener is running and increase timeout if needed

### Debug Mode
Enable debug logging to troubleshoot issues:
```bash
export LIBP2P_DEBUG=DEBUG
python ping_test.py
```

For more detailed troubleshooting information, see https://github.com/libp2p/py-libp2p/discussions/850 