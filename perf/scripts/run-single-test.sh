#!/bin/bash
# Run a single performance test using docker-compose
# Uses Redis for listener/dialer coordination (like transport)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

source "scripts/lib-perf.sh"

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

# Build environment variables for listener
LISTENER_ENV="      - IS_DIALER=false
      - REDIS_ADDR=redis:6379
      - TRANSPORT=$transport"

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
  default:
    driver: bridge

services:
  redis:
    image: redis:7-alpine
    container_name: ${TEST_SLUG}_redis
    command: redis-server --save "" --appendonly no --loglevel warning

  listener:
    image: ${LISTENER_IMAGE}
    container_name: ${TEST_SLUG}_listener
    init: true
    depends_on:
      - redis
    environment:
$LISTENER_ENV

  dialer:
    image: ${DIALER_IMAGE}
    container_name: ${TEST_SLUG}_dialer
    depends_on:
      - redis
      - listener
    environment:
$DIALER_ENV
EOF

# Run the test
log_debug "  Starting containers..."
echo "Running: $test_name" > "$LOG_FILE"

# Start containers and wait for dialer to exit
if $DOCKER_COMPOSE_CMD -f "$COMPOSE_FILE" up --exit-code-from dialer --abort-on-container-exit >> "$LOG_FILE" 2>&1; then
    EXIT_CODE=0
    log_info "  ✓ Test complete"
else
    EXIT_CODE=1
    log_error "  ✗ Test failed"
fi

# Extract results from dialer container logs
# Dialer outputs YAML to stdout, which appears in docker logs
DIALER_LOGS=$($DOCKER_COMPOSE_CMD -f "$COMPOSE_FILE" logs dialer 2>/dev/null || echo "")

# Extract only the YAML output (lines that start with # or key:)
DIALER_YAML=$(echo "$DIALER_LOGS" | grep -E "^(upload:|download:|latency:|  )" | sed 's/^dialer[^|]*| //' || echo "")

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

# Append to combined results file (baseline or main)
cat >> "$RESULTS_FILE" <<EOF
  - name: $test_name
    dialer: $dialer_id
    listener: $listener_id
    transport: $transport
    secureChannel: $secure
    muxer: $muxer
    status: $([ $EXIT_CODE -eq 0 ] && echo "pass" || echo "fail")
EOF

# Cleanup
log_debug "  Cleaning up containers..."
$DOCKER_COMPOSE_CMD -f "$COMPOSE_FILE" down --volumes --remove-orphans >> "$LOG_FILE" 2>&1 || true

exit $EXIT_CODE
