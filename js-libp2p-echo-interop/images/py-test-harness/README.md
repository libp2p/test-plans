# Python Test Harness for js-libp2p Echo Interop

This directory contains the Python test harness for validating Echo protocol interoperability between js-libp2p and py-libp2p implementations.

## Overview

The test harness is built using:
- **pytest**: Test framework with discovery and reporting
- **trio**: Structured concurrency for async operations
- **py-libp2p**: Python libp2p implementation
- **hypothesis**: Property-based testing library
- **redis**: Coordination with JS Echo Server

## Architecture

```
src/
├── __init__.py              # Package initialization
├── config.py                # Configuration management
├── redis_coordinator.py     # Redis coordination for multiaddr retrieval
├── libp2p_client.py        # libp2p client implementation
├── test_result.py          # Test result models and JSON output
├── conftest.py             # Pytest fixtures and configuration
├── test_echo_protocol.py   # Unit and integration tests
├── test_echo_properties.py # Property-based tests
└── main.py                 # Main entry point
```

## Configuration

The test harness is configured via environment variables:

### Protocol Stack
- `TRANSPORT`: Transport protocol (`tcp`, `quic`, `websocket`)
- `SECURITY`: Security protocol (`noise`, `tls`)
- `MUXER`: Stream multiplexer (`yamux`, `mplex`)
- `IS_DIALER`: Connection role (`true`, `false`)

### Redis Coordination
- `REDIS_ADDR`: Redis server address (default: `redis:6379`)
- `REDIS_KEY`: Redis key for multiaddr (default: `multiaddr`)
- `REDIS_TIMEOUT`: Timeout for multiaddr retrieval (default: `30`)

### Test Configuration
- `CONNECTION_TIMEOUT`: Connection timeout in seconds (default: `10`)
- `TEST_TIMEOUT`: Individual test timeout in seconds (default: `30`)
- `MAX_RETRIES`: Maximum retry attempts (default: `3`)
- `RETRY_DELAY`: Delay between retries in seconds (default: `1.0`)

## Test Types

### Unit Tests (`test_echo_protocol.py`)
- Basic echo functionality
- Binary payload handling
- Large payload (1MB) testing
- Concurrent stream testing
- Connection establishment
- Protocol negotiation

### Property-Based Tests (`test_echo_properties.py`)
- **Property 1**: Echo Data Integrity - validates byte-perfect echo across all payload types
- **Property 2**: Concurrent Stream Independence - validates stream isolation
- **Property 5**: Multiaddr Parsing Consistency - validates multiaddr handling
- **Property 7**: Error Handling and Recovery - validates graceful error handling

## Test Execution

### Local Development
```bash
# Install dependencies
pip install -r requirements.txt

# Run all tests
python -m pytest src/ -v

# Run specific test types
python -m pytest src/ -m "unit" -v
python -m pytest src/ -m "property" -v
python -m pytest src/ -m "integration" -v

# Run with specific configuration
TRANSPORT=tcp SECURITY=noise MUXER=yamux python -m pytest src/ -v
```

### Docker Container
```bash
# Build container
docker build -t py-test-harness .

# Run with environment configuration
docker run --rm \
  -e TRANSPORT=tcp \
  -e SECURITY=noise \
  -e MUXER=yamux \
  -e REDIS_ADDR=redis:6379 \
  --network test-network \
  py-test-harness
```

## Output Format

The test harness outputs results in JSON format to stdout for consumption by the test infrastructure:

```json
{
  "results": [
    {
      "test_name": "src/test_echo_protocol.py::test_basic_echo",
      "status": "passed",
      "duration": 0.123,
      "implementation": "py-libp2p",
      "version": "v0.5.0",
      "transport": "tcp",
      "security": "noise",
      "muxer": "yamux",
      "error": null,
      "metadata": {}
    }
  ],
  "summary": {
    "total": 10,
    "passed": 9,
    "failed": 1,
    "skipped": 0
  },
  "timestamp": "2024-01-01T12:00:00Z",
  "environment": {
    "TRANSPORT": "tcp",
    "SECURITY": "noise",
    "MUXER": "yamux",
    "IS_DIALER": "true",
    "REDIS_ADDR": "redis:6379"
  }
}
```

Diagnostic information is written to stderr to maintain output hygiene.

## Test Coordination

The test harness coordinates with the JS Echo Server via Redis:

1. **Startup**: Test harness waits for JS server multiaddr in Redis
2. **Connection**: Retrieves multiaddr and establishes libp2p connection
3. **Testing**: Executes test suite against the server
4. **Results**: Outputs JSON results to stdout
5. **Cleanup**: Properly closes connections and cleans up resources

## Error Handling

The test harness implements comprehensive error handling:

- **Connection Failures**: Exponential backoff with configurable retries
- **Protocol Errors**: Graceful handling with meaningful error messages
- **Timeout Handling**: Configurable timeouts for all operations
- **Resource Cleanup**: Proper cleanup using trio's structured concurrency
- **Configuration Validation**: Early validation of environment variables

## Property-Based Testing

Property-based tests use Hypothesis to generate test cases and validate universal properties:

- **Data Integrity**: Tests with random payloads up to 1MB
- **Concurrent Streams**: Tests with varying stream counts and payload sizes
- **Error Handling**: Tests with different retry configurations
- **Multiaddr Parsing**: Tests with generated multiaddr formats

Each property test runs 100+ examples by default and includes proper timeout handling.

## Integration with test-plans

The test harness is designed to integrate with the libp2p/test-plans repository:

- **Container Compatibility**: Follows test-plans Docker conventions
- **Result Format**: Compatible with existing result aggregation
- **Environment Variables**: Standard configuration interface
- **Output Hygiene**: Separates results (stdout) from diagnostics (stderr)
- **Version Management**: Integrates with versions.ts configuration