#!/bin/bash
# Run a single transport interop test using docker-compose
# Uses same pattern as perf/lib/run-single-test.sh

set -euo pipefail

export LOG_FILE

source "${SCRIPT_LIB_DIR}/lib-output-formatting.sh"
source "${SCRIPT_LIB_DIR}/lib-test-caching.sh"

TEST_INDEX=$1
TEST_PASS="${2:-tests}"  # "tests" (no baselines in transport)
RESULTS_FILE="${3:-"${TEST_PASS_DIR}/results.yaml.tmp"}"

print_debug "test index: ${TEST_INDEX}"
print_debug "test_pass: ${TEST_PASS}"

# Read test configuration from matrix
dialer_id=$(yq eval ".${TEST_PASS}[${TEST_INDEX}].dialer.id" "${TEST_PASS_DIR}/test-matrix.yaml")
listener_id=$(yq eval ".${TEST_PASS}[${TEST_INDEX}].listener.id" "${TEST_PASS_DIR}/test-matrix.yaml")
transport=$(yq eval ".${TEST_PASS}[${TEST_INDEX}].transport" "${TEST_PASS_DIR}/test-matrix.yaml")
secure=$(yq eval ".${TEST_PASS}[${TEST_INDEX}].secureChannel" "${TEST_PASS_DIR}/test-matrix.yaml")
muxer=$(yq eval ".${TEST_PASS}[${TEST_INDEX}].muxer" "${TEST_PASS_DIR}/test-matrix.yaml")
test_name=$(yq eval ".${TEST_PASS}[${TEST_INDEX}].id" "${TEST_PASS_DIR}/test-matrix.yaml")

print_debug "test_name: $test_name"
print_debug "dialer id: $dialer_id"
print_debug "listener id: $listener_id"
print_debug "transport: $transport"
print_debug "secure: $secure"
print_debug "muxer: $muxer"

# Compute TEST_KEY for Redis key namespacing (8-char hex hash)
TEST_KEY=$(compute_test_key "$test_name")
TEST_SLUG=$(echo "$test_name" | sed 's/[^a-zA-Z0-9-]/_/g')
LOG_FILE="${TEST_PASS_DIR}/logs/${TEST_SLUG}.log"
> "${LOG_FILE}"

print_debug "test key: $TEST_KEY"
print_debug "test slug: $TEST_SLUG"
print_debug "log file: $LOG_FILE"

log_message "[$((TEST_INDEX + 1))] $test_name (key: $TEST_KEY)"

# Construct Docker image names
DIALER_IMAGE="transport-interop-${dialer_id}"
LISTENER_IMAGE="transport-interop-${listener_id}"

print_debug "dialer image: $DIALER_IMAGE"
print_debug "listener image: $LISTENER_IMAGE"

# Generate docker-compose file
COMPOSE_FILE="${TEST_PASS_DIR}/docker-compose/${TEST_SLUG}-compose.yaml"

print_debug "docker compose file: $COMPOSE_FILE"

# Build environment variables for listener
LISTENER_ENV="      - version=$listener_id
      - transport=$transport
      - is_dialer=false
      - ip=0.0.0.0
      - REDIS_ADDR=transport-redis:6379
      - TEST_KEY=$TEST_KEY
      - debug=${DEBUG:-false}"

if [ "$muxer" != "null" ]; then
    LISTENER_ENV="$LISTENER_ENV
      - muxer=$muxer"
fi

if [ "$secure" != "null" ]; then
    LISTENER_ENV="$LISTENER_ENV
      - security=$secure"
fi

# Build environment variables for dialer
DIALER_ENV="      - version=$dialer_id
      - transport=$transport
      - is_dialer=true
      - ip=0.0.0.0
      - REDIS_ADDR=transport-redis:6379
      - TEST_KEY=$TEST_KEY
      - debug=${DEBUG:-false}"

if [ "$muxer" != "null" ]; then
    DIALER_ENV="$DIALER_ENV
      - muxer=$muxer"
fi

if [ "$secure" != "null" ]; then
    DIALER_ENV="$DIALER_ENV
      - security=$secure"
fi

# Generate docker-compose file
cat > "$COMPOSE_FILE" <<EOF
name: ${TEST_SLUG}

networks:
  transport-network:
    external: true

services:
  listener:
    image: ${LISTENER_IMAGE}
    container_name: ${TEST_SLUG}_listener
    init: true
    networks:
      - transport-network
    environment:
$LISTENER_ENV

  dialer:
    image: ${DIALER_IMAGE}
    container_name: ${TEST_SLUG}_dialer
    depends_on:
      - listener
    networks:
      - transport-network
    environment:
$DIALER_ENV
EOF

# Run the test
log_debug "  Starting containers..."
log_message "Running: $test_name" > "$LOG_FILE"

# Set timeout (180 seconds / 3 minutes for transport tests)
TEST_TIMEOUT=180

# Track test duration
TEST_START=$(date +%s)

# Start containers and wait for dialer to exit (with timeout)
if timeout $TEST_TIMEOUT $DOCKER_COMPOSE_CMD -f "$COMPOSE_FILE" up --exit-code-from dialer --abort-on-container-exit >> "$LOG_FILE" 2>&1; then
    EXIT_CODE=0
    log_message "  ✓ Test complete"
else
    TEST_EXIT=$?
    # Check if it was a timeout (exit code 124)
    if [ $TEST_EXIT -eq 124 ]; then
        EXIT_CODE=1
        log_error "  ✗ Test timed out after ${TEST_TIMEOUT}s"
        echo "" >> "$LOG_FILE"
        log_error "Test timed out after ${TEST_TIMEOUT} seconds" >> "$LOG_FILE"
    else
        EXIT_CODE=1
        log_error "  ✗ Test failed"
    fi
fi

TEST_END=$(date +%s)
TEST_DURATION=$((TEST_END - TEST_START))

# Extract metrics from log file if test passed
handshake_ms=""
ping_ms=""
if [ $EXIT_CODE -eq 0 ]; then
    # Extract JSON metrics from log (dialer outputs metrics)
    metrics=$(grep -o '{"handshakePlusOneRTTMillis":[0-9.]*,"pingRTTMilllis":[0-9.]*}' "$LOG_FILE" 2>/dev/null | tail -1 || echo "")

    if [ -n "$metrics" ]; then
        handshake_ms=$(echo "$metrics" | grep -o '"handshakePlusOneRTTMillis":[0-9.]*' | cut -d':' -f2)
        ping_ms=$(echo "$metrics" | grep -o '"pingRTTMilllis":[0-9.]*' | cut -d':' -f2)
    fi
fi

# Save complete result to individual file
cat > "${TEST_PASS_DIR}/results/${test_name}.yaml" <<EOF
test: $test_name
dialer: $dialer_id
listener: $listener_id
transport: $transport
secureChannel: $secure
muxer: $muxer
status: $([ $EXIT_CODE -eq 0 ] && echo "pass" || echo "fail")
duration: ${TEST_DURATION}s
handshakePlusOneRTTMs: ${handshake_ms:-null}
pingRTTMs: ${ping_ms:-null}
EOF

# Append to combined results file with file locking
(
    flock -x 200
    cat >> "$RESULTS_FILE" <<EOF
  - name: $test_name
    dialer: $dialer_id
    listener: $listener_id
    transport: $transport
    secureChannel: $secure
    muxer: $muxer
    status: $([ $EXIT_CODE -eq 0 ] && echo "pass" || echo "fail")
    duration: ${TEST_DURATION}s
    handshakePlusOneRTTMs: ${handshake_ms:-null}
    pingRTTMs: ${ping_ms:-null}
EOF
) 200>/tmp/results.lock

# Cleanup
log_debug "  Cleaning up containers..."
$DOCKER_COMPOSE_CMD -f "$COMPOSE_FILE" down --volumes --remove-orphans >> "$LOG_FILE" 2>&1 || true

exit $EXIT_CODE
