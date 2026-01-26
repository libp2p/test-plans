# JS-libp2p Echo Server

A containerized js-libp2p node that implements the Echo protocol (`/echo/1.0.0`) for interoperability testing with py-libp2p.

## Overview

This Echo Server:
- Implements the Echo protocol that pipes incoming streams back to the source
- Supports configurable transport, security, and multiplexer protocols
- Publishes its multiaddr to Redis for test coordination
- Outputs multiaddr to stdout for container orchestration
- Handles multiple concurrent streams independently

## Configuration

The server is configured via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `TRANSPORT` | `tcp` | Transport protocol (`tcp`, `quic`, `ws`) |
| `SECURITY` | `noise` | Security protocol (`noise`, `tls`) |
| `MUXER` | `yamux` | Stream multiplexer (`yamux`, `mplex`) |

> **Note**: The `mplex` multiplexer is deprecated in the libp2p ecosystem but still supported for interoperability testing with legacy implementations. You may see deprecation warnings when using mplex - these are expected and don't affect functionality.
| `IS_DIALER` | `false` | Connection role (always `false` for server) |
| `REDIS_ADDR` | `redis://localhost:6379` | Redis connection string |
| `HOST` | `0.0.0.0` | Listen host address |
| `PORT` | `0` | Listen port (0 for random port) |

## Usage

### Local Development

```bash
# Install dependencies
npm install

# Start the server
npm start

# Start with custom configuration
TRANSPORT=tcp SECURITY=noise MUXER=yamux npm start
```

### Docker

```bash
# Build the image
docker build -t js-libp2p-echo-server .

# Run the container
docker run --rm \
  -e TRANSPORT=tcp \
  -e SECURITY=noise \
  -e MUXER=yamux \
  -e REDIS_ADDR=redis://redis:6379 \
  js-libp2p-echo-server
```

### Docker Compose

```yaml
version: '3.8'
services:
  js-echo-server:
    build: .
    environment:
      - TRANSPORT=tcp
      - SECURITY=noise
      - MUXER=yamux
      - REDIS_ADDR=redis://redis:6379
    depends_on:
      - redis
  
  redis:
    image: redis:7-alpine
```

## Echo Protocol

The server implements the Echo protocol (`/echo/1.0.0`) which:

1. Accepts incoming stream connections
2. Pipes the stream back to the source without modification
3. Handles multiple concurrent streams independently
4. Preserves all data bytes exactly as received
5. Supports payloads up to 1MB in size

## Output Format

The server follows strict output hygiene:

- **stdout**: Contains only the multiaddr string for coordination
- **stderr**: Contains all diagnostic and debug information

Example stdout output:
```
/ip4/172.17.0.2/tcp/35673/p2p/12D3KooWBhvxp6uRaiaqyqZLYAHXRDfz7PL8p4BtQiGeVSHFxfaa
```

## Redis Coordination

The server publishes its multiaddr to Redis for test coordination:

- **Key**: `js-echo-server-multiaddr`
- **Operation**: `RPUSH` (append to list)
- **TTL**: 300 seconds (5 minutes)

This allows Python test clients to discover the server address via Redis.

## Error Handling

The server implements robust error handling:

- Graceful shutdown on SIGINT/SIGTERM
- Redis connection failures don't crash the server
- Stream errors are logged but don't affect other streams
- Configuration validation with clear error messages

## Health Checks

The Docker container includes a health check that verifies the Node.js process is running correctly.

## Security

- Runs as non-root user (nodejs:1001)
- Uses dumb-init for proper signal handling
- Minimal Alpine Linux base image
- No unnecessary packages or dependencies

## Testing

The server can be tested locally by connecting with any libp2p client that supports the Echo protocol.

## Integration

This server is designed to work with the libp2p/test-plans interoperability testing framework and coordinates with Python test clients via Redis signaling.