#!/usr/bin/env bash

# Run a single Echo interoperability test with enhanced lifecycle management
# This script executes one test combination between js-libp2p server and py-libp2p client

set -euo pipefail

# Source the container lifecycle management functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/container-lifecycle.sh"

run_single_test() {
    local test_name="$1"
    
    log_info "Starting single test execution: $test_name"
    
    # Parse test name: "py-libp2p-v0.5.0 x js-libp2p-echo-server (tcp, noise, yamux)"
    local client_impl=$(echo "$test_name" | cut -d' ' -f1)
    local server_impl=$(echo "$test_name" | cut -d' ' -f3)
    local protocols=$(echo "$test_name" | sed 's/.*(\(.*\)).*/\1/')
    
    local transport=$(echo "$protocols" | cut -d',' -f1 | xargs)
    local security=$(echo "$protocols" | cut -d',' -f2 | xargs)
    local muxer=$(echo "$protocols" | cut -d',' -f3 | xargs)
    
    # Generate unique test ID for Redis coordination
    local test_id
    test_id=$(echo -n "$test_name" | sha256sum | cut -d' ' -f1 | head -c 8)
    
    log_info "Test configuration" \
        "test_id=$test_id" \
        "client=$client_impl" \
        "server=$server_impl" \
        "transport=$transport" \
        "security=$security" \
        "muxer=$muxer"
    
    # Create test-specific directories
    local test_dir="${TEST_PASS_DIR}/docker-compose"
    local log_dir="${TEST_PASS_DIR}/logs"
    local result_dir="${TEST_PASS_DIR}/results"
    
    mkdir -p "$test_dir" "$log_dir" "$result_dir"
    
    # Generate docker-compose file for this test
    local compose_file="${test_dir}/${test_id}.yml"
    generate_compose_file "$compose_file" "$test_id" "$server_impl" "$client_impl" "$transport" "$security" "$muxer"
    
    # Run the test with lifecycle management
    local log_file="${log_dir}/${test_id}.log"
    local result_file="${result_dir}/${test_id}.yaml"
    
    log_info "Running test with lifecycle management: $test_name"
    
    # Use the enhanced lifecycle management
    if manage_test_lifecycle "$test_id" "$compose_file" 2>&1 | tee -a "$log_file"; then
        # Extract results from client logs
        extract_test_results "$test_id" "$test_name" "$client_impl" "$server_impl" "$transport" "$security" "$muxer" "$log_file" "$result_file"
        log_info "✓ PASS: $test_name"
        return 0
    else
        # Test failed
        create_failure_result "$test_id" "$test_name" "$client_impl" "$server_impl" "$transport" "$security" "$muxer" "$log_file" "$result_file"
        log_error "✗ FAIL: $test_name"
        return 1
    fi
}

generate_compose_file() {
    local compose_file="$1"
    local test_id="$2"
    local server_impl="$3"
    local client_impl="$4"
    local transport="$5"
    local security="$6"
    local muxer="$7"
    
    log_debug "Generating compose file: $compose_file"
    
    cat > "$compose_file" << EOF
version: '3.8'

services:
  redis:
    image: redis:7-alpine
    container_name: echo-redis-${test_id}
    networks:
      - js-libp2p-echo-interop
    command: redis-server --appendonly no --save ""
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5
      start_period: 10s
    deploy:
      resources:
        limits:
          memory: 128M
          cpus: '0.25'

  server:
    image: ${server_impl}:latest
    container_name: echo-server-${test_id}
    environment:
      - TRANSPORT=${transport}
      - SECURITY=${security}
      - MUXER=${muxer}
      - IS_DIALER=false
      - REDIS_ADDR=redis:6379
      - TEST_ID=${test_id}
      - DEBUG=${DEBUG:-false}
      - CONTAINER_MODE=true
    networks:
      - js-libp2p-echo-interop
    depends_on:
      redis:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "sh", "-c", "pgrep -f node >/dev/null"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 15s
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: '1.0'
    restart: "no"

  client:
    image: ${client_impl}:latest
    container_name: echo-client-${test_id}
    environment:
      - TRANSPORT=${transport}
      - SECURITY=${security}
      - MUXER=${muxer}
      - IS_DIALER=true
      - REDIS_ADDR=redis:6379
      - TEST_ID=${test_id}
      - DEBUG=${DEBUG:-false}
      - CONTAINER_MODE=true
      - TEST_TIMEOUT=${TEST_TIMEOUT:-60}
      - MAX_RETRIES=${MAX_RETRIES:-3}
    networks:
      - js-libp2p-echo-interop
    depends_on:
      redis:
        condition: service_healthy
      server:
        condition: service_healthy
    deploy:
      resources:
        limits:
          memory: 1G
          cpus: '2.0'
    restart: "no"

networks:
  js-libp2p-echo-interop:
    external: true

EOF
    
    log_debug "Compose file generated successfully"
}

extract_test_results() {
    local test_id="$1"
    local test_name="$2"
    local client_impl="$3"
    local server_impl="$4"
    local transport="$5"
    local security="$6"
    local muxer="$7"
    local log_file="$8"
    local result_file="$9"
    
    log_debug "Extracting test results for test $test_id"
    
    # Extract JSON result from client container logs
    local client_container="echo-client-${test_id}"
    local json_result
    
    if json_result=$(docker logs "$client_container" 2>/dev/null | grep '^{' | tail -1); then
        log_debug "Found JSON result in client logs"
        
        # Parse JSON result
        local status duration error
        status=$(echo "$json_result" | jq -r '.results[0].status // "unknown"' 2>/dev/null || echo "unknown")
        duration=$(echo "$json_result" | jq -r '.duration // 0' 2>/dev/null || echo "0")
        error=$(echo "$json_result" | jq -r '.error // ""' 2>/dev/null || echo "")
        
        # Create result file with enhanced metadata
        cat > "$result_file" << EOF
testName: "${test_name}"
testId: "${test_id}"
status: "${status}"
duration: ${duration}
client: "${client_impl}"
server: "${server_impl}"
transport: "${transport}"
security: "${security}"
muxer: "${muxer}"
timestamp: "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
lifecycle:
  managed: true
  startup_completed: true
  shutdown_completed: true
EOF
        
        if [[ -n "$error" && "$error" != "null" && "$error" != "" ]]; then
            echo "error: \"${error}\"" >> "$result_file"
        fi
        
        # Add metadata if available
        if echo "$json_result" | jq -e '.results[0].metadata' >/dev/null 2>&1; then
            echo "metadata:" >> "$result_file"
            echo "$json_result" | jq -r '.results[0].metadata | to_entries[] | "  \(.key): \(.value)"' >> "$result_file" 2>/dev/null || true
        fi
        
        log_debug "Test results extracted successfully"
    else
        log_error "No JSON result found in client logs"
        create_failure_result "$test_id" "$test_name" "$client_impl" "$server_impl" "$transport" "$security" "$muxer" "$log_file" "$result_file"
    fi
}

create_failure_result() {
    local test_id="$1"
    local test_name="$2"
    local client_impl="$3"
    local server_impl="$4"
    local transport="$5"
    local security="$6"
    local muxer="$7"
    local log_file="$8"
    local result_file="$9"
    
    log_debug "Creating failure result for test $test_id"
    
    # Extract error from logs
    local error_msg="Test execution failed"
    if [[ -f "$log_file" ]]; then
        local last_error
        last_error=$(grep -i "error\|fail\|exception" "$log_file" | tail -1 || echo "")
        if [[ -n "$last_error" ]]; then
            error_msg="$last_error"
        fi
    fi
    
    cat > "$result_file" << EOF
testName: "${test_name}"
testId: "${test_id}"
status: "failed"
duration: 0
client: "${client_impl}"
server: "${server_impl}"
transport: "${transport}"
security: "${security}"
muxer: "${muxer}"
timestamp: "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
error: "${error_msg}"
lifecycle:
  managed: true
  startup_completed: false
  shutdown_completed: true
EOF
    
    log_debug "Failure result created"
}

# If script is called directly (not sourced), run the test
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -ne 1 ]]; then
        echo "Usage: $0 <test_name>" >&2
        exit 1
    fi
    
    run_single_test "$1"
fi