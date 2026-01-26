# JS-libp2p Echo Interoperability Tests

Interoperability tests between js-libp2p and py-libp2p using the Echo protocol (/echo/1.0.0) within the libp2p/test-plans repository framework.

## Overview

This test suite validates Echo protocol interoperability between js-libp2p (server) and py-libp2p (client) implementations. The tests follow the "Multidimensional Interop" pattern, using Docker containers for isolation and Redis for coordination between test components.

The system consists of two primary components:
1. **JS Echo Server**: A containerized js-libp2p node that implements the Echo protocol server
2. **Python Test Harness**: A pytest-based test suite using trio for async operations that validates Echo protocol behavior

## What It Tests

The test suite validates:
- **Echo Protocol Implementation**: Bidirectional stream communication with byte-perfect echo responses
- **Transport Protocols**: TCP (initial), with QUIC and WebSocket support planned
- **Security Protocols**: Noise (primary), with TLS support planned  
- **Stream Multiplexers**: Yamux and Mplex
- **Payload Integrity**: Text, binary, and large payloads (up to 1MB)
- **Concurrent Streams**: Multiple simultaneous Echo protocol streams
- **Error Handling**: Connection failures, protocol errors, and recovery mechanisms

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   JS Echo       │    │     Redis       │    │   Python Test   │
│   Server        │◄──►│  Coordination   │◄──►│   Harness       │
│  (js-libp2p)    │    │                 │    │  (py-libp2p)    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                                              │
         └──────────────────────────────────────────────┘
                    libp2p Echo Protocol
                    (/echo/1.0.0)
```

## Test Execution Flow

1. **JS Echo Server** starts and binds to a random port
2. Server publishes its multiaddr to Redis for coordination
3. **Python Test Harness** retrieves the multiaddr from Redis
4. Python client connects to JS server via libp2p
5. Client opens Echo protocol stream and sends test data
6. Server echoes the data back unchanged
7. Client validates the response and outputs JSON test results

## Test Scenarios

- **Basic Echo**: Simple text payload validation
- **Binary Echo**: Binary data integrity verification
- **Large Payload**: 1MB payload handling without corruption
- **Concurrent Streams**: Multiple simultaneous Echo streams
- **Error Conditions**: Connection failures and protocol errors

## Configuration

Tests are configured via environment variables:
- `TRANSPORT`: Transport protocol (tcp, quic-v1, ws)
- `SECURITY`: Security protocol (noise, tls)
- `MUXER`: Stream multiplexer (yamux, mplex)
- `IS_DIALER`: Connection role (true/false)
- `REDIS_ADDR`: Redis coordination address

## Running Tests

### Standard Test-Plans Framework

Tests are executed through the standard test-plans framework:

```bash
# Run all js-libp2p-echo-interop tests
./run.sh

# Run with specific filters
./run.sh --impl-select "py-libp2p"

# Run with debug output
./run.sh --debug
```

### Docker Compose (Recommended)

The test suite includes comprehensive Docker Compose configurations for different environments:

```bash
# Quick start - run basic test suite
make compose-test

# Development environment with live reload
make compose-dev

# Production test suite for CI/CD
make compose-prod

# Test specific protocol combinations
make test-tcp-noise-yamux
make test-tcp-noise-mplex

# Run specific test scenarios
make test-basic      # Basic Echo tests
make test-binary     # Binary payload tests
make test-large      # Large payload tests
make test-concurrent # Concurrent stream tests
```

### Environment Configuration

Create a `.env` file from the example template:

```bash
cp .env.example .env
# Edit .env with your desired configuration
```

Key configuration options:
```bash
TRANSPORT=tcp          # tcp, quic-v1, ws, wss
SECURITY=noise         # noise, tls
MUXER=yamux           # yamux, mplex
DEBUG=false           # Enable debug output
TEST_SCENARIOS=basic,binary,large,concurrent
```

### Advanced Usage

```bash
# Run all protocol combinations
docker-compose -f docker-compose.yml -f docker-compose.protocols.yml --profile all-protocols up --build

# Run property-based tests
docker-compose -f docker-compose.yml -f docker-compose.test.yml --profile properties up --build

# Development with debug tools
docker-compose -f docker-compose.yml -f docker-compose.dev.yml --profile dev-tools up --build
```

For detailed Docker Compose usage, see [DOCKER_COMPOSE.md](DOCKER_COMPOSE.md).

## Results

Test results are output in JSON format to stdout, with diagnostic information sent to stderr. Results include:
- Test status (passed/failed)
- Execution duration
- Protocol configuration used
- Error details (if failed)
- Payload size and stream count metadata

## Current Status

<!-- TEST_RESULTS_START -->
<!-- TEST_RESULTS_END -->