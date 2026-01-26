#!/usr/bin/env bash

# Container Lifecycle Management for JS-libp2p Echo Interop Tests
# Implements comprehensive process startup, ready state detection, graceful shutdown,
# health checks, and failure detection for containerized test environments.

set -euo pipefail

# Configuration
LIFECYCLE_TIMEOUT="${LIFECYCLE_TIMEOUT:-300}"  # 5 minutes default
HEALTH_CHECK_INTERVAL="${HEALTH_CHECK_INTERVAL:-5}"
READY_CHECK_INTERVAL="${READY_CHECK_INTERVAL:-2}"
SHUTDOWN_TIMEOUT="${SHUTDOWN_TIMEOUT:-30}"
MAX_STARTUP_RETRIES="${MAX_STARTUP_RETRIES:-3}"

# Logging functions
log_info() {
    echo "[LIFECYCLE-INFO] $(date -u +"%Y-%m-%dT%H:%M:%SZ") $*" >&2
}

log_error() {
    echo "[LIFECYCLE-ERROR] $(date -u +"%Y-%m-%dT%H:%M:%SZ") $*" >&2
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo "[LIFECYCLE-DEBUG] $(date -u +"%Y-%m-%dT%H:%M:%SZ") $*" >&2
    fi
}

# Wait for container to be ready
wait_for_container_ready() {
    local container_name="$1"
    local ready_check_command="$2"
    local timeout="${3:-$LIFECYCLE_TIMEOUT}"
    
    log_info "Waiting for container '$container_name' to be ready..."
    
    local start_time
    start_time=$(date +%s)
    local end_time=$((start_time + timeout))
    
    while [[ $(date +%s) -lt $end_time ]]; do
        if docker exec "$container_name" sh -c "$ready_check_command" >/dev/null 2>&1; then
            local elapsed=$(($(date +%s) - start_time))
            log_info "Container '$container_name' is ready (took ${elapsed}s)"
            return 0
        fi
        
        # Check if container is still running
        if ! docker ps --format "table {{.Names}}" | grep -q "^${container_name}$"; then
            log_error "Container '$container_name' stopped unexpectedly during startup"
            return 1
        fi
        
        sleep "$READY_CHECK_INTERVAL"
    done
    
    log_error "Timeout waiting for container '$container_name' to be ready"
    return 1
}

# Wait for Redis to be ready
wait_for_redis_ready() {
    local container_name="$1"
    local timeout="${2:-$LIFECYCLE_TIMEOUT}"
    
    wait_for_container_ready "$container_name" "redis-cli ping | grep -q PONG" "$timeout"
}

# Wait for JS Echo Server to be ready
wait_for_js_server_ready() {
    local container_name="$1"
    local timeout="${2:-$LIFECYCLE_TIMEOUT}"
    
    log_info "Waiting for JS Echo Server '$container_name' to publish multiaddr..."
    
    local start_time
    start_time=$(date +%s)
    local end_time=$((start_time + timeout))
    
    while [[ $(date +%s) -lt $end_time ]]; do
        # Check if multiaddr has been published to stdout
        if docker logs "$container_name" 2>/dev/null | grep -E "^/ip4/" >/dev/null; then
            local elapsed=$(($(date +%s) - start_time))
            log_info "JS Echo Server '$container_name' is ready (took ${elapsed}s)"
            return 0
        fi
        
        # Check if container is still running
        if ! docker ps --format "table {{.Names}}" | grep -q "^${container_name}$"; then
            log_error "JS Echo Server '$container_name' stopped unexpectedly during startup"
            return 1
        fi
        
        sleep "$READY_CHECK_INTERVAL"
    done
    
    log_error "Timeout waiting for JS Echo Server '$container_name' to be ready"
    return 1
}

# Wait for Python Test Harness to be ready
wait_for_py_client_ready() {
    local container_name="$1"
    local timeout="${2:-$LIFECYCLE_TIMEOUT}"
    
    log_info "Waiting for Python Test Harness '$container_name' to start..."
    
    local start_time
    start_time=$(date +%s)
    local end_time=$((start_time + timeout))
    
    while [[ $(date +%s) -lt $end_time ]]; do
        # Check if test harness has started (look for pytest or test execution logs)
        if docker logs "$container_name" 2>&1 | grep -E "(Starting Python test harness|pytest|test session starts)" >/dev/null; then
            local elapsed=$(($(date +%s) - start_time))
            log_info "Python Test Harness '$container_name' is ready (took ${elapsed}s)"
            return 0
        fi
        
        # Check if container is still running
        if ! docker ps --format "table {{.Names}}" | grep -q "^${container_name}$"; then
            log_error "Python Test Harness '$container_name' stopped unexpectedly during startup"
            return 1
        fi
        
        sleep "$READY_CHECK_INTERVAL"
    done
    
    log_error "Timeout waiting for Python Test Harness '$container_name' to be ready"
    return 1
}

# Perform health check on container
health_check_container() {
    local container_name="$1"
    local health_command="$2"
    
    log_debug "Performing health check on container '$container_name'"
    
    if ! docker ps --format "table {{.Names}}" | grep -q "^${container_name}$"; then
        log_error "Health check failed: Container '$container_name' is not running"
        return 1
    fi
    
    if ! docker exec "$container_name" sh -c "$health_command" >/dev/null 2>&1; then
        log_error "Health check failed: Command failed for container '$container_name'"
        return 1
    fi
    
    log_debug "Health check passed for container '$container_name'"
    return 0
}

# Monitor container health continuously
monitor_container_health() {
    local container_name="$1"
    local health_command="$2"
    local duration="${3:-$LIFECYCLE_TIMEOUT}"
    
    log_info "Starting health monitoring for container '$container_name' (duration: ${duration}s)"
    
    local start_time
    start_time=$(date +%s)
    local end_time=$((start_time + duration))
    local consecutive_failures=0
    local max_consecutive_failures=3
    
    while [[ $(date +%s) -lt $end_time ]]; do
        if health_check_container "$container_name" "$health_command"; then
            consecutive_failures=0
        else
            consecutive_failures=$((consecutive_failures + 1))
            log_error "Health check failure $consecutive_failures/$max_consecutive_failures for '$container_name'"
            
            if [[ $consecutive_failures -ge $max_consecutive_failures ]]; then
                log_error "Container '$container_name' failed $max_consecutive_failures consecutive health checks"
                return 1
            fi
        fi
        
        sleep "$HEALTH_CHECK_INTERVAL"
    done
    
    log_info "Health monitoring completed for container '$container_name'"
    return 0
}

# Gracefully shutdown container
graceful_shutdown_container() {
    local container_name="$1"
    local timeout="${2:-$SHUTDOWN_TIMEOUT}"
    
    log_info "Initiating graceful shutdown of container '$container_name'"
    
    # Check if container is running
    if ! docker ps --format "table {{.Names}}" | grep -q "^${container_name}$"; then
        log_info "Container '$container_name' is not running"
        return 0
    fi
    
    # Send SIGTERM signal
    log_debug "Sending SIGTERM to container '$container_name'"
    if ! docker kill --signal=TERM "$container_name" >/dev/null 2>&1; then
        log_error "Failed to send SIGTERM to container '$container_name'"
        return 1
    fi
    
    # Wait for graceful shutdown
    local start_time
    start_time=$(date +%s)
    local end_time=$((start_time + timeout))
    
    while [[ $(date +%s) -lt $end_time ]]; do
        if ! docker ps --format "table {{.Names}}" | grep -q "^${container_name}$"; then
            local elapsed=$(($(date +%s) - start_time))
            log_info "Container '$container_name' shutdown gracefully (took ${elapsed}s)"
            return 0
        fi
        sleep 1
    done
    
    # Force kill if graceful shutdown failed
    log_error "Graceful shutdown timeout for container '$container_name', forcing kill"
    if docker kill --signal=KILL "$container_name" >/dev/null 2>&1; then
        log_info "Container '$container_name' force killed"
        return 0
    else
        log_error "Failed to force kill container '$container_name'"
        return 1
    fi
}

# Cleanup container resources
cleanup_container_resources() {
    local container_name="$1"
    
    log_info "Cleaning up resources for container '$container_name'"
    
    # Remove container if it exists
    if docker ps -a --format "table {{.Names}}" | grep -q "^${container_name}$"; then
        log_debug "Removing container '$container_name'"
        if docker rm -f "$container_name" >/dev/null 2>&1; then
            log_debug "Container '$container_name' removed successfully"
        else
            log_error "Failed to remove container '$container_name'"
        fi
    fi
    
    # Clean up any associated volumes (if specified)
    local volume_pattern="${container_name}-*"
    local volumes
    volumes=$(docker volume ls --format "table {{.Name}}" | grep "^${volume_pattern}$" || true)
    
    if [[ -n "$volumes" ]]; then
        log_debug "Removing volumes matching pattern '$volume_pattern'"
        echo "$volumes" | xargs -r docker volume rm >/dev/null 2>&1 || true
    fi
}

# Start container with lifecycle management
start_container_with_lifecycle() {
    local container_name="$1"
    local start_command="$2"
    local ready_check_command="$3"
    local health_check_command="$4"
    
    log_info "Starting container '$container_name' with lifecycle management"
    
    local retry_count=0
    
    while [[ $retry_count -lt $MAX_STARTUP_RETRIES ]]; do
        log_debug "Startup attempt $((retry_count + 1))/$MAX_STARTUP_RETRIES for container '$container_name'"
        
        # Clean up any existing container
        cleanup_container_resources "$container_name"
        
        # Start the container
        log_debug "Executing start command: $start_command"
        if eval "$start_command"; then
            # Wait for container to be ready
            if wait_for_container_ready "$container_name" "$ready_check_command"; then
                # Perform initial health check
                if health_check_container "$container_name" "$health_check_command"; then
                    log_info "Container '$container_name' started successfully"
                    return 0
                else
                    log_error "Initial health check failed for container '$container_name'"
                fi
            else
                log_error "Ready check failed for container '$container_name'"
            fi
        else
            log_error "Failed to start container '$container_name'"
        fi
        
        retry_count=$((retry_count + 1))
        if [[ $retry_count -lt $MAX_STARTUP_RETRIES ]]; then
            local delay=$((retry_count * 2))  # Exponential backoff
            log_info "Retrying container startup in ${delay}s..."
            sleep "$delay"
        fi
    done
    
    log_error "Failed to start container '$container_name' after $MAX_STARTUP_RETRIES attempts"
    return 1
}

# Complete lifecycle management for a test
manage_test_lifecycle() {
    local test_id="$1"
    local compose_file="$2"
    
    log_info "Managing lifecycle for test '$test_id'"
    
    local redis_container="echo-redis-${test_id}"
    local server_container="echo-server-${test_id}"
    local client_container="echo-client-${test_id}"
    
    # Cleanup function for error handling
    cleanup_test() {
        log_info "Cleaning up test '$test_id'"
        graceful_shutdown_container "$client_container" || true
        graceful_shutdown_container "$server_container" || true
        graceful_shutdown_container "$redis_container" || true
        
        # Remove compose stack
        docker-compose -f "$compose_file" down --remove-orphans --volumes >/dev/null 2>&1 || true
        
        cleanup_container_resources "$client_container"
        cleanup_container_resources "$server_container"
        cleanup_container_resources "$redis_container"
    }
    
    # Set up trap for cleanup on exit
    trap cleanup_test EXIT
    
    # Start containers in dependency order
    log_info "Starting Redis container for test '$test_id'"
    if ! docker-compose -f "$compose_file" up -d redis; then
        log_error "Failed to start Redis container"
        return 1
    fi
    
    if ! wait_for_redis_ready "$redis_container"; then
        log_error "Redis container failed to become ready"
        return 1
    fi
    
    log_info "Starting JS Echo Server container for test '$test_id'"
    if ! docker-compose -f "$compose_file" up -d server; then
        log_error "Failed to start JS Echo Server container"
        return 1
    fi
    
    if ! wait_for_js_server_ready "$server_container"; then
        log_error "JS Echo Server container failed to become ready"
        return 1
    fi
    
    log_info "Starting Python Test Harness container for test '$test_id'"
    if ! docker-compose -f "$compose_file" up -d client; then
        log_error "Failed to start Python Test Harness container"
        return 1
    fi
    
    if ! wait_for_py_client_ready "$client_container"; then
        log_error "Python Test Harness container failed to become ready"
        return 1
    fi
    
    # Monitor test execution
    log_info "Monitoring test execution for test '$test_id'"
    
    # Wait for client container to complete
    local client_exit_code
    if docker wait "$client_container" >/dev/null 2>&1; then
        client_exit_code=$(docker inspect "$client_container" --format='{{.State.ExitCode}}')
        log_info "Test client completed with exit code: $client_exit_code"
    else
        log_error "Failed to wait for client container completion"
        return 1
    fi
    
    # Perform final health checks
    log_info "Performing final health checks for test '$test_id'"
    
    if health_check_container "$redis_container" "redis-cli ping | grep -q PONG"; then
        log_debug "Final Redis health check passed"
    else
        log_error "Final Redis health check failed"
    fi
    
    if health_check_container "$server_container" "pgrep -f node >/dev/null"; then
        log_debug "Final server health check passed"
    else
        log_error "Final server health check failed"
    fi
    
    # Cleanup will be handled by trap
    log_info "Test lifecycle management completed for test '$test_id'"
    
    return "$client_exit_code"
}

# Export functions for use in other scripts
export -f log_info log_error log_debug
export -f wait_for_container_ready wait_for_redis_ready wait_for_js_server_ready wait_for_py_client_ready
export -f health_check_container monitor_container_health
export -f graceful_shutdown_container cleanup_container_resources
export -f start_container_with_lifecycle manage_test_lifecycle