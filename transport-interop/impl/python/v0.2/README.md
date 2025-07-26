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

## Files

- `ping_test.py` - Main implementation of the ping test
- `pyproject.toml` - Python project configuration and dependencies
- `PingDockerfile` - Docker configuration for the test
- `Makefile` - Build configuration with parallel build support
- `.gitignore` - Git ignore rules (excludes build artifacts)
- `doc/` - Documentation directory
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

# Clean build artifacts
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

## Output Format

The dialer outputs JSON to stdout with the following format:
```json
{
  "handshakePlusOneRTTMillis": 123.45,
  "pingRTTMilllis": 12.34
}
```

All diagnostic output goes to stderr.

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
- `trio` - Asynchronous I/O support
- `multiaddr` - Multiaddr parsing and manipulation
- `typing-extensions` - Type hints support

### Docker System Dependencies
The Docker image includes the following system packages:
- `git` - Required for installing py-libp2p from git repository
- `build-essential` - C/C++ compiler and build tools
- `cmake` - Build system generator
- `pkg-config` - Package configuration utility
- `libgmp-dev` - GNU Multiple Precision Arithmetic Library 