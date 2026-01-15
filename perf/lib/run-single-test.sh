#!/bin/bash
# Run a single performance test using docker-compose
# Uses Redis for listener/dialer coordination (like transport)

set -euo pipefail

export LOG_FILE

source "${SCRIPT_LIB_DIR}/lib-output-formatting.sh"
source "${SCRIPT_LIB_DIR}/lib-test-caching.sh"

TEST_INDEX=$1
TEST_PASS="${2:-tests}"  # "main" or "baseline"
RESULTS_FILE="${3:-"${TEST_PASS_DIR}/results.yaml.tmp"}"

print_debug "test index: ${TEST_INDEX}"
print_debug "test_pass: ${TEST_PASS}"

# Read test configuration from matrix
DIALER_ID=$(yq eval ".${TEST_PASS}[${TEST_INDEX}].dialer.id" "${TEST_PASS_DIR}/test-matrix.yaml")
LISTENER_ID=$(yq eval ".${TEST_PASS}[${TEST_INDEX}].listener.id" "${TEST_PASS_DIR}/test-matrix.yaml")
TRANSPORT_NAME=$(yq eval ".${TEST_PASS}[${TEST_INDEX}].transport" "${TEST_PASS_DIR}/test-matrix.yaml")
SECURE=$(yq eval ".${TEST_PASS}[${TEST_INDEX}].secureChannel" "${TEST_PASS_DIR}/test-matrix.yaml")
MUXER_NAME=$(yq eval ".${TEST_PASS}[${TEST_INDEX}].muxer" "${TEST_PASS_DIR}/test-matrix.yaml")
TEST_NAME=$(yq eval ".${TEST_PASS}[${TEST_INDEX}].id" "${TEST_PASS_DIR}/test-matrix.yaml")
upload_bytes=$(yq eval ".metadata.uploadBytes" "${TEST_PASS_DIR}/test-matrix.yaml")
download_bytes=$(yq eval ".metadata.downloadBytes" "${TEST_PASS_DIR}/test-matrix.yaml")
upload_iterations=$(yq eval ".metadata.uploadIterations" "${TEST_PASS_DIR}/test-matrix.yaml")
download_iterations=$(yq eval ".metadata.downloadIterations" "${TEST_PASS_DIR}/test-matrix.yaml")
latency_iterations=$(yq eval ".metadata.latencyIterations" "${TEST_PASS_DIR}/test-matrix.yaml")
duration=$(yq eval ".metadata.durationPerIteration" "${TEST_PASS_DIR}/test-matrix.yaml")

print_debug "test_name: ${TEST_NAME}"
print_debug "dialer id: ${DIALER_ID}"
print_debug "listener id: ${LISTENER_ID}"
print_debug "transport: ${TRANSPORT_NAME}"
print_debug "secure: ${SECURE}"
print_debug "muxer: ${MUXER_NAME}"
print_debug "upload bytes: ${upload_bytes}"
print_debug "download bytes: ${download_bytes}"
print_debug "upload iterations: ${upload_iterations}"
print_debug "download iterations: ${download_iterations}"
print_debug "latency iterations: ${latency_iterations}"
print_debug "duration: ${duration}"

# Compute TEST_KEY for Redis key namespacing (8-char hex hash)
TEST_KEY=$(compute_test_key "${TEST_NAME}")
TEST_SLUG=$(echo "${TEST_NAME}" | sed 's/[^a-zA-Z0-9-]/_/g')
LOG_FILE="${TEST_PASS_DIR}/logs/${TEST_SLUG}.log"
> "${LOG_FILE}"

print_debug "test key: ${TEST_KEY}"
print_debug "test slug: ${TEST_SLUG}"
print_debug "log file: ${LOG_FILE}"

log_message "[$((${TEST_INDEX} + 1))] ${TEST_NAME} (key: ${TEST_KEY})"

# Construct Docker image names
DIALER_IMAGE=$(yq eval ".${TEST_PASS}[${TEST_INDEX}].dialer.imageName" "${TEST_PASS_DIR}/test-matrix.yaml")
LISTENER_IMAGE=$(yq eval ".${TEST_PASS}[${TEST_INDEX}].listener.imageName" "${TEST_PASS_DIR}/test-matrix.yaml")

print_debug "dialer image: ${DIALER_IMAGE}"
print_debug "listener image: ${LISTENER_IMAGE}"

# Generate docker-compose file
COMPOSE_FILE="${TEST_PASS_DIR}/docker-compose/${TEST_SLUG}-compose.yaml"

print_debug "docker compose file: ${COMPOSE_FILE}"

# Assign static IP to listener
#LISTENER_IP="10.5.0.10"

# Build environment variables for listener
LISTENER_ENV="      - IS_DIALER=false
      - REDIS_ADDR=perf-redis:6379
      - TEST_KEY=${TEST_KEY}
      - TRANSPORT=${TRANSPORT_NAME}
      - LISTENER_IP=0.0.0.0"

if [ "${SECURE}" != "null" ]; then
    LISTENER_ENV="${LISTENER_ENV}
      - SECURE_CHANNEL=${SECURE}"
fi

if [ "${MUXER_NAME}" != "null" ]; then
    LISTENER_ENV="${LISTENER_ENV}
      - MUXER=${MUXER_NAME}"
fi

# Build environment variables for dialer
DIALER_ENV="      - IS_DIALER=true
      - REDIS_ADDR=perf-redis:6379
      - TEST_KEY=${TEST_KEY}
      - TRANSPORT=${TRANSPORT_NAME}
      - UPLOAD_BYTES=${upload_bytes}
      - DOWNLOAD_BYTES=${download_bytes}
      - UPLOAD_ITERATIONS=${upload_iterations}
      - DOWNLOAD_ITERATIONS=${download_iterations}
      - LATENCY_ITERATIONS=${latency_iterations}
      - DURATION=${duration}"

if [ "${SECURE}" != "null" ]; then
    DIALER_ENV="${DIALER_ENV}
      - SECURE_CHANNEL=${SECURE}"
fi

if [ "${MUXER_NAME}" != "null" ]; then
    DIALER_ENV="${DIALER_ENV}
      - MUXER=${MUXER_NAME}"
fi

# Generate docker-compose file
cat > "${COMPOSE_FILE}" <<EOF
name: ${TEST_SLUG}

networks:
  perf-network:
    external: true

services:
  listener:
    image: ${LISTENER_IMAGE}
    container_name: ${TEST_SLUG}_listener
    init: true
    networks:
      - perf-network
    environment:
${LISTENER_ENV}

  dialer:
    image: ${DIALER_IMAGE}
    container_name: ${TEST_SLUG}_dialer
    depends_on:
      - listener
    networks:
      - perf-network
    environment:
${DIALER_ENV}
EOF

# Run the test
log_debug "  Starting containers..."
log_message "Running: ${TEST_NAME}" > "${LOG_FILE}"

# Set timeout (300 seconds / 5 minutes)
TEST_TIMEOUT=300

# Track test duration
TEST_START=$(date +%s)

# Start containers and wait for dialer to exit (with timeout)
# WARNING: Do NOT put quotes around this because the command has two parts
if timeout "${TEST_TIMEOUT}" ${DOCKER_COMPOSE_CMD} -f "${COMPOSE_FILE}" up --exit-code-from dialer --abort-on-container-exit >> "${LOG_FILE}" 2>&1; then
    EXIT_CODE=0
    log_message "  ✓ Test complete"
else
    TEST_EXIT=$?
    # Check if it was a timeout (exit code 124)
    if [ "${TEST_EXIT}" -eq 124 ]; then
        EXIT_CODE=1
        log_error "  ✗ Test timed out after ${TEST_TIMEOUT}s"
        echo "" >> "${LOG_FILE}"
        log_error "Test timed out after ${TEST_TIMEOUT} seconds" >> "${LOG_FILE}"
    else
        EXIT_CODE=1
        log_error "  ✗ Test failed"
    fi
fi

TEST_END=$(date +%s)
TEST_DURATION=$((${TEST_END} - ${TEST_START}))

# Extract results from dialer container logs
# Dialer outputs YAML to stdout, which appears in docker logs
# WARNING: Do NOT put quotes around this because the command has two parts
DIALER_LOGS=$(${DOCKER_COMPOSE_CMD} -f "${COMPOSE_FILE}" logs dialer 2>/dev/null || echo "")

# Extract the measurement YAML (including outliers and samples arrays)
# Docker compose prefixes each line with: "container_name  | "
# We need to strip this prefix and keep only the YAML content
# Match only measurement sections and their fields (not logging output)
DIALER_YAML=$(echo "${DIALER_LOGS}" | grep -E "dialer.*\| (upload:|download:|latency:|  (iterations|min|q1|median|q3|max|outliers|samples|unit):)" | sed 's/^.*| //' || echo "")

# Save complete result to individual file
cat > "${TEST_PASS_DIR}/results/${TEST_NAME}.yaml" <<EOF
test: ${TEST_NAME}
dialer: ${DIALER_ID}
listener: ${LISTENER_ID}
transport: ${TRANSPORT_NAME}
secureChannel: ${SECURE}
muxer: ${MUXER_NAME}
status: $([ "${EXIT_CODE}" -eq 0 ] && echo "pass" || echo "fail")
duration: ${TEST_DURATION}

# Measurements from dialer
${DIALER_YAML}
EOF

# Proper indentation for nested YAML (add 4 spaces to measurement lines)
INDENTED_YAML=$(echo "${DIALER_YAML}" | sed 's/^/    /')

# Append to combined results file (baseline or main) with embedded measurements
(
    flock -x 200
    cat >> "${RESULTS_FILE}" <<EOF
  - name: ${TEST_NAME}
    dialer: ${DIALER_ID}
    listener: ${LISTENER_ID}
    transport: ${TRANSPORT_NAME}
    secureChannel: ${SECURE}
    muxer: ${MUXER_NAME}
    status: $([ "${EXIT_CODE}" -eq 0 ] && echo "pass" || echo "fail")
${INDENTED_YAML}
EOF
) 200>/tmp/results.lock

# Cleanup
log_debug "  Cleaning up containers..."
# WARNING: Do NOT put quotes around this because the command has two parts
${DOCKER_COMPOSE_CMD} -f "${COMPOSE_FILE}" down --volumes --remove-orphans >> "${LOG_FILE}" 2>&1 || true

exit "${EXIT_CODE}"
