# Docker Compose Configuration Guide

This document describes the Docker Compose setup for JS-libp2p Echo Interoperability Tests, providing a comprehensive multi-container test environment with Redis coordination.

## Overview

The Docker Compose configuration consists of multiple files that can be combined to create different testing environments:

- **`docker-compose.yml`** - Main configuration with core services
- **`docker-compose.dev.yml`** - Development environment overrides
- **`docker-compose.test.yml`** - Test scenario configurations
- **`docker-compose.prod.yml`** - Production/CI environment settings
- **`docker-compose.protocols.yml`** - Protocol combination testing
- **`docker-compose.redis.yml`** - Standalone Redis coordination (legacy)

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Docker Network                           │
│                js-libp2p-echo-interop                      │
│                                                             │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    │
│  │    Redis    │    │ JS Echo     │    │ Python Test │    │
│  │ Coordinator │◄──►│ Server      │◄──►│ Harness     │    │
│  │             │    │ (Listener)  │    │ (Dialer)    │    │
│  └─────────────┘    └─────────────┘    └─────────────┘    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Services

### Core Services

#### Redis (`redis`)
- **Purpose**: Coordination service for multiaddr sharing and test synchronization
- **Image**: `redis:7-alpine`
- **Network**: `js-libp2p-echo-interop`
- **Health Check**: Redis ping command
- **Configuration**: Optimized for testing (no persistence)

#### JS Echo Server (`js-echo-server`)
- **Purpose**: libp2p Echo protocol server implementation
- **Role**: Listener/Server
- **Build**: Local build from `./images/js-echo-server`
- **Dependencies**: Redis health check
- **Output**: Multiaddr to stdout, diagnostics to stderr

#### Python Test Harness (`py-test-harness`)
- **Purpose**: pytest-based Echo protocol client tests
- **Role**: Dialer/Client
- **Build**: Local build from `./images/py-test-harness`
- **Dependencies**: Redis and JS server health checks
- **Output**: JSON test results to stdout

### Optional Services

#### Test Coordinator (`test-coordinator`)
- **Purpose**: Orchestrates complex test scenarios
- **Profile**: `coordinator`
- **Usage**: Advanced test coordination and timeout management

#### Health Monitor (`health-monitor`)
- **Purpose**: Monitors service health in production
- **Profile**: `monitoring`, `production`
- **Usage**: CI/CD health monitoring

#### Timeout Enforcer (`timeout-enforcer`)
- **Purpose**: Enforces global test timeouts
- **Profile**: `timeout`, `production`
- **Usage**: Prevents hanging tests in CI

## Usage Examples

### Basic Usage

```bash
# Run basic test suite
docker-compose up --build --abort-on-container-exit

# Run with specific protocol configuration
TRANSPORT=tcp SECURITY=noise MUXER=yamux docker-compose up --build

# Run in background and view logs
docker-compose up -d --build
docker-compose logs -f
```

### Development Environment

```bash
# Start development environment with live reload
docker-compose -f docker-compose.yml -f docker-compose.dev.yml up --build

# Run with debug tools
docker-compose -f docker-compose.yml -f docker-compose.dev.yml --profile dev-tools up --build

# Interactive debugging
docker-compose -f docker-compose.yml -f docker-compose.dev.yml exec js-echo-server sh
docker-compose -f docker-compose.yml -f docker-compose.dev.yml exec py-test-harness bash
```

### Test Scenarios

```bash
# Run specific test scenarios
docker-compose -f docker-compose.yml -f docker-compose.test.yml --profile basic up --build
docker-compose -f docker-compose.yml -f docker-compose.test.yml --profile binary up --build
docker-compose -f docker-compose.yml -f docker-compose.test.yml --profile large up --build
docker-compose -f docker-compose.yml -f docker-compose.test.yml --profile concurrent up --build

# Run all test scenarios
docker-compose -f docker-compose.yml -f docker-compose.test.yml --profile all-tests up --build

# Run property-based tests
docker-compose -f docker-compose.yml -f docker-compose.test.yml --profile properties up --build
```

### Protocol Combinations

```bash
# Test specific protocol combinations
docker-compose -f docker-compose.yml -f docker-compose.protocols.yml --profile tcp-noise-yamux up --build
docker-compose -f docker-compose.yml -f docker-compose.protocols.yml --profile tcp-noise-mplex up --build

# Test all supported protocols
docker-compose -f docker-compose.yml -f docker-compose.protocols.yml --profile all-protocols up --build

# Future protocol support
docker-compose -f docker-compose.yml -f docker-compose.protocols.yml --profile future-protocols up --build
```

### Production/CI Environment

```bash
# Run production test suite
docker-compose -f docker-compose.yml -f docker-compose.prod.yml --profile production up --build

# Run with monitoring and validation
docker-compose -f docker-compose.yml -f docker-compose.prod.yml --profile production --profile monitoring --profile validation up --build

# Run with global timeout
GLOBAL_TIMEOUT=300 docker-compose -f docker-compose.yml -f docker-compose.prod.yml --profile timeout up --build
```

## Environment Configuration

### Protocol Stack Variables

```bash
# Transport protocol
TRANSPORT=tcp          # tcp, quic-v1, ws, wss (future)

# Security protocol  
SECURITY=noise         # noise, tls (future)

# Stream multiplexer
MUXER=yamux           # yamux, mplex
```

### Test Configuration Variables

```bash
# Test scenarios
TEST_SCENARIOS=basic,binary,large,concurrent

# Payload sizes
PAYLOAD_SIZES=small,medium,large

# Concurrent streams
CONCURRENT_STREAMS=1,5,10

# Timeouts
TEST_TIMEOUT=30
GLOBAL_TIMEOUT=600
```

### Debug and Development Variables

```bash
# Enable debug mode
DEBUG=true

# Node.js environment
NODE_ENV=development

# Enable Node.js debugging
JS_DEBUG_PORT=9229
```

### Resource Limits

```bash
# Memory limits
JS_MEMORY_LIMIT=512M
PY_MEMORY_LIMIT=1G
REDIS_MEMORY_LIMIT=256M

# CPU limits
JS_CPU_LIMIT=1.0
PY_CPU_LIMIT=2.0
REDIS_CPU_LIMIT=0.5
```

## Profiles

Docker Compose profiles allow selective service activation:

### Test Profiles
- `basic` - Basic Echo tests
- `binary` - Binary payload tests
- `large` - Large payload tests
- `concurrent` - Concurrent stream tests
- `properties` - Property-based tests
- `performance` - Performance benchmarks
- `all-tests` - All test scenarios

### Protocol Profiles
- `tcp-noise-yamux` - TCP + Noise + Yamux
- `tcp-noise-mplex` - TCP + Noise + Mplex
- `all-protocols` - All supported protocols
- `future-protocols` - Future protocol support

### Environment Profiles
- `dev-tools` - Development utilities
- `coordinator` - Test coordination
- `monitoring` - Health monitoring
- `production` - Production settings
- `validation` - Result validation
- `timeout` - Timeout enforcement

## Networking

### Default Network
- **Name**: `js-libp2p-echo-interop`
- **Driver**: Bridge
- **Subnet**: `172.20.0.0/16`
- **Gateway**: `172.20.0.1`

### Service Communication
- **Redis**: `redis:6379`
- **JS Echo Server**: Dynamic port, multiaddr via Redis
- **Python Test Harness**: Connects via multiaddr from Redis

## Volumes

### Data Volumes
- `redis-data` - Redis data persistence (optional)
- `test-results` - Test result sharing between containers

### Development Volumes
- Source code mounting for live reload
- Node.js modules caching
- Python cache persistence

## Health Checks

All services include comprehensive health checks:

- **Redis**: `redis-cli ping`
- **JS Echo Server**: Node.js process check
- **Python Test Harness**: Test execution status

## Logging

Structured logging configuration:
- **Format**: JSON for production, text for development
- **Rotation**: 10MB max size, 3 files max
- **Labels**: Service and role identification

## Troubleshooting

### Common Issues

1. **Port Conflicts**
   ```bash
   # Check for port conflicts
   docker-compose ps
   netstat -tulpn | grep :6379
   ```

2. **Network Issues**
   ```bash
   # Inspect network
   docker network inspect js-libp2p-echo-interop
   
   # Test connectivity
   docker-compose exec py-test-harness ping redis
   ```

3. **Service Dependencies**
   ```bash
   # Check service health
   docker-compose ps
   docker-compose logs redis
   docker-compose logs js-echo-server
   ```

4. **Resource Constraints**
   ```bash
   # Monitor resource usage
   docker stats
   
   # Adjust limits in environment
   JS_MEMORY_LIMIT=1G PY_MEMORY_LIMIT=2G docker-compose up
   ```

### Debug Commands

```bash
# View service logs
docker-compose logs -f [service-name]

# Execute commands in running containers
docker-compose exec redis redis-cli
docker-compose exec js-echo-server node -e "console.log('Debug')"
docker-compose exec py-test-harness python -c "import sys; print(sys.version)"

# Inspect service configuration
docker-compose config
docker-compose config --services
docker-compose config --volumes
```

## Integration with Existing Tools

### Makefile Integration
```bash
# Use Makefile targets
make compose-test
make compose-dev
make compose-prod
make test-tcp-noise-yamux
```

### CI/CD Integration
```yaml
# GitHub Actions example
- name: Run Echo Interop Tests
  run: |
    docker-compose -f docker-compose.yml -f docker-compose.prod.yml \
      --profile production up --build --abort-on-container-exit
```

## Best Practices

1. **Use profiles** for selective service activation
2. **Set resource limits** to prevent resource exhaustion
3. **Use health checks** for reliable service dependencies
4. **Configure timeouts** for CI/CD environments
5. **Mount source code** only in development
6. **Use structured logging** for production debugging
7. **Clean up resources** after testing

## Future Enhancements

- Support for additional transport protocols (QUIC, WebSocket)
- TLS security protocol integration
- Multi-architecture container builds
- Advanced monitoring and metrics collection
- Automated test matrix generation
- Integration with external test orchestration systems