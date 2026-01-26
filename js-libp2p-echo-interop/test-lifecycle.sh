#!/usr/bin/env bash

# Test script for container lifecycle management
# Validates startup, ready state detection, health checks, and graceful shutdown

set -euo pipefail

# Configuration
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIFECYCLE_LIB="${TEST_DIR}/lib/container-lifecycle.sh"
HEALTH_CHECK_LIB="${TEST_DIR}/lib/health-check.sh"

# Test configuration
TEST_ID="lifecycle-test-$(date +%s)"
COMPOSE_FILE="/tmp/test-lifecycle-${TEST_ID}.yml"
LOG_FILE="/tmp/test-lifecycle-${TEST_ID}.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_test() {
    echo -e "${GREEN}[TEST]${NC} $(date -u +"%Y-%m-%dT%H:%M:%SZ") $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date -u +"%Y-%m-%dT%H:%M:%SZ") $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date -u +"%Y-%m-%dT%H:%M:%SZ") $*"
}

# Cleanup function
cleanup() {
    log_test "Cleaning up test environment"
    
    # Stop and remove containers
    docker-compose -f "$COMPOSE_FILE" down --remove-orphans --volumes >/dev/null 2>&1 || true
    
    # Remove test containers by name pattern
    docker rm -f "echo-redis-${TEST_ID}" "echo-server-${TEST_ID}" "echo-client-${TEST_ID}" >/dev/null 2>&1 || true
    
    # Remove temporary files
    rm -f "$COMPOSE_FILE" "$LOG_FILE"
    
    log_test "Cleanup completed"
}

# Set up trap for cleanup
trap cleanup EXIT

# Generate test docker-compose file
generate_test_compose() {
    log_test "Generating test docker-compose file"
    
    cat > "$COMPOSE_FILE" << EOF
version: '3.8'

services:
  redis:
    image: redis:7-alpine
    container_name: echo-redis-${TEST_ID}
    networks:
      - test-network
    command: redis-server --appendonly no --save ""
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5
      start_period: 10s

  server:
    image: js-libp2p-echo-server:latest
    container_name: echo-server-${TEST_ID}
    environment:
      - TRANSPORT=tcp
      - SECURITY=noise
      - MUXER=yamux
      - IS_DIALER=false
      - REDIS_ADDR=redis:6379
      - TEST_ID=${TEST_ID}
      - DEBUG=true
      - CONTAINER_MODE=true
    networks:
      - test-network
    depends_on:
      redis:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "bash", "/app/lib/health-check.sh", "js-server"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 15s

  client:
    image: py-test-harness:latest
    container_name: echo-client-${TEST_ID}
    environment:
      - TRANSPORT=tcp
      - SECURITY=noise
      - MUXER=yamux
      - IS_DIALER=true
      - REDIS_ADDR=redis:6379
      - TEST_ID=${TEST_ID}
      - DEBUG=true
      - CONTAINER_MODE=true
      - TEST_TIMEOUT=30
    networks:
      - test-network
    depends_on:
      redis:
        condition: service_healthy
      server:
        condition: service_healthy

networks:
  test-network:
    driver: bridge

EOF
    
    log_test "Test docker-compose file generated: $COMPOSE_FILE"
}

# Test 1: Container startup sequence
test_startup_sequence() {
    log_test "Test 1: Container startup sequence"
    
    # Start Redis first
    log_test "Starting Redis container"
    if ! docker-compose -f "$COMPOSE_FILE" up -d redis; then
        log_error "Failed to start Redis container"
        return 1
    fi
    
    # Wait for Redis to be healthy
    log_test "Waiting for Redis to be healthy"
    local timeout=30
    local start_time=$(date +%s)
    
    while [[ $(($(date +%s) - start_time)) -lt $timeout ]]; do
        if docker-compose -f "$COMPOSE_FILE" ps redis | grep -q "healthy"; then
            log_test "Redis is healthy"
            break
        fi
        sleep 2
    done
    
    if [[ $(($(date +%s) - start_time)) -ge $timeout ]]; then
        log_error "Redis failed to become healthy within timeout"
        return 1
    fi
    
    # Start JS Echo Server
    log_test "Starting JS Echo Server container"
    if ! docker-compose -f "$COMPOSE_FILE" up -d server; then
        log_error "Failed to start JS Echo Server container"
        return 1
    fi
    
    # Wait for server to be healthy
    log_test "Waiting for JS Echo Server to be healthy"
    start_time=$(date +%s)
    
    while [[ $(($(date +%s) - start_time)) -lt $timeout ]]; do
        if docker-compose -f "$COMPOSE_FILE" ps server | grep -q "healthy"; then
            log_test "JS Echo Server is healthy"
            break
        fi
        sleep 2
    done
    
    if [[ $(($(date +%s) - start_time)) -ge $timeout ]]; then
        log_error "JS Echo Server failed to become healthy within timeout"
        return 1
    fi
    
    log_test "✓ Container startup sequence test passed"
    return 0
}

# Test 2: Ready state detection
test_ready_state_detection() {
    log_test "Test 2: Ready state detection"
    
    # Check if server has published multiaddr
    log_test "Checking if server published multiaddr to Redis"
    
    local multiaddr_found=false
    local timeout=30
    local start_time=$(date +%s)
    
    while [[ $(($(date +%s) - start_time)) -lt $timeout ]]; do
        if docker exec "echo-redis-${TEST_ID}" redis-cli llen js-echo-server-multiaddr | grep -q "^[1-9]"; then
            multiaddr_found=true
            break
        fi
        sleep 2
    done
    
    if [[ "$multiaddr_found" == "false" ]]; then
        log_error "Server multiaddr not found in Redis"
        return 1
    fi
    
    # Check if server output multiaddr to stdout
    log_test "Checking if server output multiaddr to stdout"
    local server_logs
    server_logs=$(docker logs "echo-server-${TEST_ID}" 2>/dev/null | grep -E "^/ip4/" | head -1)
    
    if [[ -z "$server_logs" ]]; then
        log_error "Server multiaddr not found in stdout"
        return 1
    fi
    
    log_test "Server multiaddr found: $server_logs"
    log_test "✓ Ready state detection test passed"
    return 0
}

# Test 3: Health checks
test_health_checks() {
    log_test "Test 3: Health checks"
    
    # Source the health check functions
    source "$HEALTH_CHECK_LIB"
    
    # Test Redis health check
    log_test "Testing Redis health check"
    if docker exec "echo-redis-${TEST_ID}" bash -c "source /app/lib/health-check.sh && check_redis_health"; then
        log_test "✓ Redis health check passed"
    else
        log_error "Redis health check failed"
        return 1
    fi
    
    # Test JS Server health check
    log_test "Testing JS Server health check"
    if docker exec "echo-server-${TEST_ID}" bash -c "source /app/lib/health-check.sh && check_js_server_health"; then
        log_test "✓ JS Server health check passed"
    else
        log_error "JS Server health check failed"
        return 1
    fi
    
    log_test "✓ Health checks test passed"
    return 0
}

# Test 4: Graceful shutdown
test_graceful_shutdown() {
    log_test "Test 4: Graceful shutdown"
    
    # Send SIGTERM to server container
    log_test "Sending SIGTERM to JS Echo Server"
    if ! docker kill --signal=TERM "echo-server-${TEST_ID}"; then
        log_error "Failed to send SIGTERM to server"
        return 1
    fi
    
    # Wait for graceful shutdown
    log_test "Waiting for graceful shutdown"
    local timeout=15
    local start_time=$(date +%s)
    local shutdown_successful=false
    
    while [[ $(($(date +%s) - start_time)) -lt $timeout ]]; do
        if ! docker ps --format "table {{.Names}}" | grep -q "^echo-server-${TEST_ID}$"; then
            shutdown_successful=true
            break
        fi
        sleep 1
    done
    
    if [[ "$shutdown_successful" == "false" ]]; then
        log_error "Server did not shutdown gracefully within timeout"
        return 1
    fi
    
    local elapsed=$(($(date +%s) - start_time))
    log_test "Server shutdown gracefully in ${elapsed}s"
    
    log_test "✓ Graceful shutdown test passed"
    return 0
}

# Test 5: Resource cleanup
test_resource_cleanup() {
    log_test "Test 5: Resource cleanup"
    
    # Stop all containers
    log_test "Stopping all containers"
    docker-compose -f "$COMPOSE_FILE" down --remove-orphans --volumes
    
    # Check that containers are removed
    log_test "Verifying containers are removed"
    local remaining_containers
    remaining_containers=$(docker ps -a --format "table {{.Names}}" | grep "echo-.*-${TEST_ID}" || true)
    
    if [[ -n "$remaining_containers" ]]; then
        log_error "Some containers were not cleaned up: $remaining_containers"
        return 1
    fi
    
    log_test "✓ Resource cleanup test passed"
    return 0
}

# Main test execution
main() {
    log_test "Starting container lifecycle management tests"
    log_test "Test ID: $TEST_ID"
    
    # Check prerequisites
    if [[ ! -f "$LIFECYCLE_LIB" ]]; then
        log_error "Container lifecycle library not found: $LIFECYCLE_LIB"
        exit 1
    fi
    
    if [[ ! -f "$HEALTH_CHECK_LIB" ]]; then
        log_error "Health check library not found: $HEALTH_CHECK_LIB"
        exit 1
    fi
    
    # Check if Docker images exist
    if ! docker image inspect js-libp2p-echo-server:latest >/dev/null 2>&1; then
        log_error "JS Echo Server image not found. Please build it first."
        exit 1
    fi
    
    if ! docker image inspect py-test-harness:latest >/dev/null 2>&1; then
        log_error "Python Test Harness image not found. Please build it first."
        exit 1
    fi
    
    # Generate test compose file
    generate_test_compose
    
    # Run tests
    local test_results=()
    local failed_tests=0
    
    # Test 1: Startup sequence
    if test_startup_sequence; then
        test_results+=("✓ Startup sequence")
    else
        test_results+=("✗ Startup sequence")
        ((failed_tests++))
    fi
    
    # Test 2: Ready state detection (only if startup succeeded)
    if [[ $failed_tests -eq 0 ]]; then
        if test_ready_state_detection; then
            test_results+=("✓ Ready state detection")
        else
            test_results+=("✗ Ready state detection")
            ((failed_tests++))
        fi
    else
        test_results+=("- Ready state detection (skipped)")
    fi
    
    # Test 3: Health checks (only if previous tests succeeded)
    if [[ $failed_tests -eq 0 ]]; then
        if test_health_checks; then
            test_results+=("✓ Health checks")
        else
            test_results+=("✗ Health checks")
            ((failed_tests++))
        fi
    else
        test_results+=("- Health checks (skipped)")
    fi
    
    # Test 4: Graceful shutdown (only if previous tests succeeded)
    if [[ $failed_tests -eq 0 ]]; then
        if test_graceful_shutdown; then
            test_results+=("✓ Graceful shutdown")
        else
            test_results+=("✗ Graceful shutdown")
            ((failed_tests++))
        fi
    else
        test_results+=("- Graceful shutdown (skipped)")
    fi
    
    # Test 5: Resource cleanup (always run)
    if test_resource_cleanup; then
        test_results+=("✓ Resource cleanup")
    else
        test_results+=("✗ Resource cleanup")
        ((failed_tests++))
    fi
    
    # Print test summary
    log_test "Container lifecycle management test results:"
    for result in "${test_results[@]}"; do
        echo "  $result"
    done
    
    if [[ $failed_tests -eq 0 ]]; then
        log_test "All tests passed! Container lifecycle management is working correctly."
        exit 0
    else
        log_error "$failed_tests test(s) failed. Container lifecycle management needs attention."
        exit 1
    fi
}

# Run main function
main "$@"