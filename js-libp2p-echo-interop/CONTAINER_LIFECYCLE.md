# Container Lifecycle Management

This document describes the comprehensive container lifecycle management system implemented for the JS-libp2p Echo Interoperability Tests. The system ensures robust process startup, ready state detection, health monitoring, graceful shutdown, and resource cleanup.

## Overview

The container lifecycle management system addresses the requirements for:
- **Process startup and ready state detection** (Requirement 7.1)
- **Graceful shutdown and resource cleanup** (Requirement 7.5)
- **Health checks and failure detection** (Requirement 7.1, 7.5)

## Components

### 1. Container Lifecycle Library (`lib/container-lifecycle.sh`)

The core library provides functions for managing container lifecycles:

#### Key Functions

- `wait_for_container_ready()` - Generic ready state detection
- `wait_for_redis_ready()` - Redis-specific ready state detection
- `wait_for_js_server_ready()` - JS Echo Server ready state detection
- `wait_for_py_client_ready()` - Python Test Harness ready state detection
- `health_check_container()` - Generic health checking
- `monitor_container_health()` - Continuous health monitoring
- `graceful_shutdown_container()` - Graceful shutdown with timeout
- `cleanup_container_resources()` - Resource cleanup
- `manage_test_lifecycle()` - Complete test lifecycle management

#### Configuration

Environment variables for lifecycle management:

```bash
LIFECYCLE_TIMEOUT=300          # Overall lifecycle timeout (5 minutes)
HEALTH_CHECK_INTERVAL=5        # Health check interval (seconds)
READY_CHECK_INTERVAL=2         # Ready state check interval (seconds)
SHUTDOWN_TIMEOUT=30            # Graceful shutdown timeout (seconds)
MAX_STARTUP_RETRIES=3          # Maximum startup retry attempts
```

### 2. Health Check Library (`lib/health-check.sh`)

Comprehensive health checking for all container types:

#### Health Check Types

- **Redis Health Check**: Ping response, memory usage, connection count
- **JS Server Health Check**: Process status, multiaddr publication, signal response
- **Python Client Health Check**: Process status, test execution state, signal response
- **System Health Check**: Comprehensive check of all components

#### Usage

```bash
# Check individual components
./lib/health-check.sh redis
./lib/health-check.sh js-server
./lib/health-check.sh py-client

# Check entire system
./lib/health-check.sh system
```

### 3. Enhanced Container Implementations

#### JS Echo Server Enhancements

**Startup Sequence**:
1. Configuration validation
2. libp2p node creation and startup
3. Ready state detection with retry logic
4. Address binding and publication
5. Redis coordination
6. Health monitoring setup

**Shutdown Sequence**:
1. Stop accepting new connections
2. Close existing connections gracefully
3. Stop libp2p node
4. Resource cleanup
5. Exit with appropriate code

**Health Monitoring**:
- Periodic health reporting every 30 seconds
- Process signal handling for health checks
- Multiaddr publication verification

#### Python Test Harness Enhancements

**Startup Sequence**:
1. Configuration validation
2. Signal handler setup
3. Dependency waiting (Redis, JS server)
4. Test framework initialization
5. Ready state achievement

**Shutdown Sequence**:
1. Stop running tests gracefully
2. Finalize test results
3. Resource cleanup
4. Enhanced JSON output with lifecycle metadata

**Signal Handling**:
- SIGINT, SIGTERM, SIGQUIT handling
- Graceful test interruption
- Proper exit code management

## Docker Integration

### Health Checks in Docker Compose

Enhanced health checks are integrated into Docker Compose configurations:

```yaml
services:
  redis:
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5
      start_period: 10s

  js-echo-server:
    healthcheck:
      test: ["CMD", "bash", "/app/lib/health-check.sh", "js-server"]
      interval: 30s
      timeout: 10s
      start_period: 15s
      retries: 3
    depends_on:
      redis:
        condition: service_healthy

  py-test-harness:
    depends_on:
      redis:
        condition: service_healthy
      js-echo-server:
        condition: service_healthy
```

### Container Dependencies

The system enforces proper startup order:
1. **Redis** starts first and must be healthy
2. **JS Echo Server** starts after Redis is healthy
3. **Python Test Harness** starts after both Redis and JS Server are healthy

## Lifecycle Phases

### Phase 1: Startup

1. **Container Creation**: Docker creates containers with proper resource limits
2. **Dependency Waiting**: Containers wait for their dependencies to be healthy
3. **Service Initialization**: Each service initializes its core functionality
4. **Ready State Detection**: Services signal readiness through specific mechanisms:
   - Redis: Responds to `PING` command
   - JS Server: Publishes multiaddr to stdout and Redis
   - Python Client: Begins test execution

### Phase 2: Runtime Monitoring

1. **Health Checks**: Periodic health checks verify service status
2. **Failure Detection**: Failed health checks trigger alerts and potential restarts
3. **Resource Monitoring**: Memory and CPU usage monitoring
4. **Log Aggregation**: Structured logging with proper output hygiene

### Phase 3: Shutdown

1. **Signal Handling**: Containers respond to SIGTERM signals
2. **Graceful Shutdown**: Services stop accepting new work and complete current tasks
3. **Resource Cleanup**: All resources are properly released
4. **Container Removal**: Containers and associated resources are cleaned up

## Ready State Detection

### Redis Ready State
- Responds to `redis-cli ping` with `PONG`
- Memory usage information available
- Client connection information available

### JS Echo Server Ready State
- Node.js process is running
- libp2p node is started and has listening addresses
- Multiaddr is published to stdout (signals readiness to test framework)
- Multiaddr is published to Redis (enables client coordination)
- Echo protocol handler is registered

### Python Test Harness Ready State
- Python process is running
- Configuration is validated
- Dependencies (Redis, JS server) are available
- Test framework is initialized
- Test execution has begun

## Error Handling and Recovery

### Startup Failures
- **Retry Logic**: Failed startups are retried with exponential backoff
- **Dependency Checks**: Services verify dependencies before starting
- **Fast Failure**: Invalid configurations cause immediate failure with clear error messages

### Runtime Failures
- **Health Check Failures**: Multiple consecutive failures trigger container restart
- **Resource Exhaustion**: Resource limits prevent system-wide failures
- **Network Issues**: Connection failures are handled with appropriate retries

### Shutdown Failures
- **Graceful Timeout**: Services have limited time for graceful shutdown
- **Force Kill**: Unresponsive services are force-killed after timeout
- **Resource Cleanup**: Resources are cleaned up even after force kills

## Testing

### Lifecycle Test Suite (`test-lifecycle.sh`)

Comprehensive test suite validates all lifecycle aspects:

1. **Container Startup Sequence**: Verifies proper startup order and timing
2. **Ready State Detection**: Validates ready state mechanisms
3. **Health Checks**: Tests all health check functions
4. **Graceful Shutdown**: Verifies proper shutdown behavior
5. **Resource Cleanup**: Ensures complete resource cleanup

### Running Tests

```bash
# Run the complete lifecycle test suite
./test-lifecycle.sh

# The test will:
# 1. Build test containers
# 2. Test startup sequence
# 3. Validate ready state detection
# 4. Test health checks
# 5. Test graceful shutdown
# 6. Verify resource cleanup
```

## Monitoring and Observability

### Logging

All lifecycle events are logged with structured format:
- **Timestamps**: UTC timestamps for all events
- **Log Levels**: INFO, ERROR, DEBUG levels
- **Context**: Container names, test IDs, and relevant metadata
- **Output Hygiene**: stdout for results, stderr for diagnostics

### Metrics

Key metrics tracked:
- **Startup Time**: Time from container start to ready state
- **Health Check Success Rate**: Percentage of successful health checks
- **Shutdown Time**: Time for graceful shutdown completion
- **Resource Usage**: Memory and CPU utilization

### Alerts

Alerting conditions:
- **Startup Timeout**: Container fails to reach ready state
- **Health Check Failures**: Multiple consecutive health check failures
- **Shutdown Timeout**: Container fails to shutdown gracefully
- **Resource Exhaustion**: Memory or CPU limits exceeded

## Best Practices

### Container Design
1. **Single Responsibility**: Each container has a single, well-defined purpose
2. **Proper Signal Handling**: All containers handle SIGTERM gracefully
3. **Health Check Implementation**: All containers provide meaningful health checks
4. **Resource Limits**: All containers have appropriate resource limits

### Lifecycle Management
1. **Dependency Ordering**: Containers start in proper dependency order
2. **Ready State Signaling**: Clear mechanisms for ready state detection
3. **Graceful Shutdown**: All containers shutdown gracefully within timeout
4. **Resource Cleanup**: All resources are properly cleaned up

### Error Handling
1. **Fast Failure**: Invalid configurations fail immediately
2. **Retry Logic**: Transient failures are retried with backoff
3. **Clear Error Messages**: All errors include actionable information
4. **Proper Exit Codes**: Exit codes indicate specific failure types

## Troubleshooting

### Common Issues

#### Container Startup Failures
- **Check Dependencies**: Ensure Redis is healthy before starting other services
- **Verify Configuration**: Check environment variables and configuration files
- **Review Logs**: Check container logs for specific error messages
- **Resource Limits**: Ensure sufficient memory and CPU are available

#### Health Check Failures
- **Network Connectivity**: Verify containers can communicate
- **Service Status**: Check if the underlying service is running
- **Resource Constraints**: Verify containers have sufficient resources
- **Configuration Issues**: Check service-specific configuration

#### Shutdown Issues
- **Signal Handling**: Verify containers handle SIGTERM properly
- **Resource Cleanup**: Check for resource leaks or hanging processes
- **Timeout Configuration**: Adjust shutdown timeouts if needed
- **Force Kill**: Use force kill as last resort for unresponsive containers

### Debugging Commands

```bash
# Check container status
docker-compose ps

# View container logs
docker-compose logs [service-name]

# Execute health checks manually
docker exec [container-name] bash /app/lib/health-check.sh [check-type]

# Monitor resource usage
docker stats [container-name]

# Check container dependencies
docker-compose config --services
```

## Future Enhancements

### Planned Improvements
1. **Metrics Collection**: Integration with Prometheus/Grafana
2. **Advanced Health Checks**: Application-specific health endpoints
3. **Auto-scaling**: Dynamic scaling based on load
4. **Circuit Breakers**: Automatic failure isolation
5. **Distributed Tracing**: Request tracing across containers

### Configuration Enhancements
1. **Dynamic Configuration**: Runtime configuration updates
2. **Configuration Validation**: Enhanced validation with detailed error messages
3. **Configuration Templates**: Reusable configuration templates
4. **Environment-specific Configs**: Development, staging, production configurations

This container lifecycle management system provides a robust foundation for reliable, scalable, and maintainable containerized testing infrastructure.