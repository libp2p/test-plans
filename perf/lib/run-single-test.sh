#!/bin/bash
# Run a single performance test using docker-compose
# Uses Redis for listener/dialer coordination (like transport)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

source "lib/lib-perf.sh"

TEST_INDEX=$1
TEST_TYPE="${2:-main}"  # "main" or "baseline"

# Docker compose command
DOCKER_COMPOSE_CMD="${DOCKER_COMPOSE_CMD:-docker compose}"

# Read test configuration from appropriate section
if [ "$TEST_TYPE" = "baseline" ]; then
    MATRIX_SECTION="baselines"
    RESULTS_FILE="$TEST_PASS_DIR/baseline-results.yaml.tmp"
else
    MATRIX_SECTION="tests"
    RESULTS_FILE="$TEST_PASS_DIR/results.yaml.tmp"
fi

# Read test configuration from matrix
dialer_id=$(yq eval ".$MATRIX_SECTION[$TEST_INDEX].dialer" "$TEST_PASS_DIR/test-matrix.yaml")
listener_id=$(yq eval ".$MATRIX_SECTION[$TEST_INDEX].listener" "$TEST_PASS_DIR/test-matrix.yaml")
transport=$(yq eval ".$MATRIX_SECTION[$TEST_INDEX].transport" "$TEST_PASS_DIR/test-matrix.yaml")
secure=$(yq eval ".$MATRIX_SECTION[$TEST_INDEX].secureChannel" "$TEST_PASS_DIR/test-matrix.yaml")
muxer=$(yq eval ".$MATRIX_SECTION[$TEST_INDEX].muxer" "$TEST_PASS_DIR/test-matrix.yaml")
upload_bytes=$(yq eval ".$MATRIX_SECTION[$TEST_INDEX].uploadBytes" "$TEST_PASS_DIR/test-matrix.yaml")
download_bytes=$(yq eval ".$MATRIX_SECTION[$TEST_INDEX].downloadBytes" "$TEST_PASS_DIR/test-matrix.yaml")
upload_iterations=$(yq eval ".$MATRIX_SECTION[$TEST_INDEX].uploadIterations" "$TEST_PASS_DIR/test-matrix.yaml")
download_iterations=$(yq eval ".$MATRIX_SECTION[$TEST_INDEX].downloadIterations" "$TEST_PASS_DIR/test-matrix.yaml")
latency_iterations=$(yq eval ".$MATRIX_SECTION[$TEST_INDEX].latencyIterations" "$TEST_PASS_DIR/test-matrix.yaml")
duration=$(yq eval ".$MATRIX_SECTION[$TEST_INDEX].durationPerIteration" "$TEST_PASS_DIR/test-matrix.yaml")
test_name=$(yq eval ".$MATRIX_SECTION[$TEST_INDEX].name" "$TEST_PASS_DIR/test-matrix.yaml")

log_info "[$((TEST_INDEX + 1))] $test_name"

# Construct Docker image names
DIALER_IMAGE="perf-${dialer_id}"
LISTENER_IMAGE="perf-${listener_id}"

# Sanitize test name for file/container names
TEST_SLUG=$(echo "$test_name" | sed 's/[^a-zA-Z0-9-]/_/g')

# Prepare directories
mkdir -p "$TEST_PASS_DIR/docker-compose"
LOG_FILE="$TEST_PASS_DIR/logs/${TEST_SLUG}.log"

# Generate docker-compose file
COMPOSE_FILE="$TEST_PASS_DIR/docker-compose/${TEST_SLUG}-compose.yaml"

# Assign static IP to listener
LISTENER_IP="10.5.0.10"

# Build environment variables for listener
LISTENER_ENV="      - IS_DIALER=false
      - REDIS_ADDR=redis:6379
      - TRANSPORT=$transport
      - LISTENER_IP=$LISTENER_IP"

if [ "$secure" != "null" ]; then
    LISTENER_ENV="$LISTENER_ENV
      - SECURE_CHANNEL=$secure"
fi

if [ "$muxer" != "null" ]; then
    LISTENER_ENV="$LISTENER_ENV
      - MUXER=$muxer"
fi

# Build environment variables for dialer
DIALER_ENV="      - IS_DIALER=true
      - REDIS_ADDR=redis:6379
      - TRANSPORT=$transport
      - UPLOAD_BYTES=$upload_bytes
      - DOWNLOAD_BYTES=$download_bytes
      - UPLOAD_ITERATIONS=$upload_iterations
      - DOWNLOAD_ITERATIONS=$download_iterations
      - LATENCY_ITERATIONS=$latency_iterations
      - DURATION=$duration"

if [ "$secure" != "null" ]; then
    DIALER_ENV="$DIALER_ENV
      - SECURE_CHANNEL=$secure"
fi

if [ "$muxer" != "null" ]; then
    DIALER_ENV="$DIALER_ENV
      - MUXER=$muxer"
fi

# Generate docker-compose file
cat > "$COMPOSE_FILE" <<EOF
name: ${TEST_SLUG}

networks:
  perf-net:
    driver: bridge
    ipam:
      config:
        - subnet: 10.5.0.0/24

services:
  redis:
    image: redis:7-alpine
    container_name: ${TEST_SLUG}_redis
    command: redis-server --save "" --appendonly no --loglevel warning
    networks:
      - perf-net

  listener:
    image: ${LISTENER_IMAGE}
    container_name: ${TEST_SLUG}_listener
    init: true
    depends_on:
      - redis
    networks:
      perf-net:
        ipv4_address: ${LISTENER_IP}
    environment:
$LISTENER_ENV

  dialer:
    image: ${DIALER_IMAGE}
    container_name: ${TEST_SLUG}_dialer
    depends_on:
      - redis
      - listener
    networks:
      - perf-net
    environment:
$DIALER_ENV
EOF

# Run the test
log_debug "  Starting containers..."
echo "Running: $test_name" > "$LOG_FILE"

# Set timeout (300 seconds / 5 minutes)
TEST_TIMEOUT=300

# Start containers and wait for dialer to exit (with timeout)
if timeout $TEST_TIMEOUT $DOCKER_COMPOSE_CMD -f "$COMPOSE_FILE" up --exit-code-from dialer --abort-on-container-exit >> "$LOG_FILE" 2>&1; then
    EXIT_CODE=0
    log_info "  ✓ Test complete"
else
    TEST_EXIT=$?
    # Check if it was a timeout (exit code 124)
    if [ $TEST_EXIT -eq 124 ]; then
        EXIT_CODE=1
        log_error "  ✗ Test timed out after ${TEST_TIMEOUT}s"
        echo "" >> "$LOG_FILE"
        echo "ERROR: Test timed out after ${TEST_TIMEOUT} seconds" >> "$LOG_FILE"
    else
        EXIT_CODE=1
        log_error "  ✗ Test failed"
    fi
fi

# Extract results from dialer container logs
# Dialer outputs YAML to stdout, which appears in docker logs
DIALER_LOGS=$($DOCKER_COMPOSE_CMD -f "$COMPOSE_FILE" logs dialer 2>/dev/null || echo "")

# Extract the measurement YAML (including outliers and samples arrays)
# Docker compose prefixes each line with: "container_name  | "
# We need to strip this prefix and keep only the YAML content
# Match only measurement sections and their fields (not logging output)
DIALER_YAML=$(echo "$DIALER_LOGS" | grep -E "dialer.*\| (upload:|download:|latency:|  (iterations|min|q1|median|q3|max|outliers|samples|unit):)" | sed 's/^.*| //' || echo "")

# Save complete result to individual file
cat > "$TEST_PASS_DIR/results/${test_name}.yaml" <<EOF
test: $test_name
dialer: $dialer_id
listener: $listener_id
transport: $transport
secureChannel: $secure
muxer: $muxer
status: $([ $EXIT_CODE -eq 0 ] && echo "pass" || echo "fail")

# Measurements from dialer
$DIALER_YAML
EOF

# Proper indentation for nested YAML (add 4 spaces to measurement lines)
INDENTED_YAML=$(echo "$DIALER_YAML" | sed 's/^/    /')

# Append to combined results file (baseline or main) with embedded measurements
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
$INDENTED_YAML
EOF
) 200>/tmp/results.lock

# Cleanup
log_debug "  Cleaning up containers..."
$DOCKER_COMPOSE_CMD -f "$COMPOSE_FILE" down --volumes --remove-orphans >> "$LOG_FILE" 2>&1 || true

exit $EXIT_CODE
