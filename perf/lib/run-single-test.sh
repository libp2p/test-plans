#!/usr/bin/env bash
# Run a single performance test using docker-compose
# Uses Redis for listener/dialer coordination (like transport)

set -euo pipefail

export LOG_FILE

source "${SCRIPT_LIB_DIR}/lib-output-formatting.sh"
source "${SCRIPT_LIB_DIR}/lib-test-caching.sh"
source "${SCRIPT_LIB_DIR}/lib-test-execution.sh"
source "${SCRIPT_LIB_DIR}/lib-generate-tests.sh"

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
upload_iterations=$(yq eval ".metadata.iterations" "${TEST_PASS_DIR}/test-matrix.yaml")
download_iterations=$(yq eval ".metadata.iterations" "${TEST_PASS_DIR}/test-matrix.yaml")
latency_iterations=$(yq eval ".metadata.latencyIterations" "${TEST_PASS_DIR}/test-matrix.yaml")
duration=$(yq eval ".metadata.durationPerIteration" "${TEST_PASS_DIR}/test-matrix.yaml")

DIALER_LEGACY=$(yq eval ".${TEST_PASS}[${TEST_INDEX}].dialer.legacy // \"false\"" "${TEST_PASS_DIR}/test-matrix.yaml")
LISTENER_LEGACY=$(yq eval ".${TEST_PASS}[${TEST_INDEX}].listener.legacy // \"false\"" "${TEST_PASS_DIR}/test-matrix.yaml")
IS_LEGACY_TEST="false"
if [ "${DIALER_LEGACY}" == "true" ] || [ "${LISTENER_LEGACY}" == "true" ]; then
  IS_LEGACY_TEST="true"
fi

print_debug "test_name: ${TEST_NAME}"
print_debug "dialer id: ${DIALER_ID}"
print_debug "listener id: ${LISTENER_ID}"
print_debug "transport: ${TRANSPORT_NAME}"
print_debug "secure: ${SECURE}"
print_debug "muxer: ${MUXER_NAME}"
print_debug "dialer legacy: ${DIALER_LEGACY}"
print_debug "listener legacy: ${LISTENER_LEGACY}"
print_debug "is legacy test: ${IS_LEGACY_TEST}"
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

# Ensure cleanup runs regardless of how the script exits
cleanup() {
  if [ -n "${COMPOSE_FILE:-}" ] && [ -f "${COMPOSE_FILE}" ]; then
    log_debug "  Cleaning up containers..."
    # WARNING: Do NOT put quotes around this because the command has two parts
    ${DOCKER_COMPOSE_CMD} -f "${COMPOSE_FILE}" down --volumes --remove-orphans >> "${LOG_FILE}" 2>&1 || true
  fi
}
trap cleanup EXIT

# Build environment variables per container based on legacy status
# Legacy containers get lowercase env vars pointing to the proxy
# Modern containers get uppercase env vars pointing to global Redis
if [ "${LISTENER_LEGACY}" == "true" ]; then
  LISTENER_ENV=$(generate_legacy_env_vars "false" "proxy-${TEST_KEY}:6379" "${TRANSPORT_NAME}" "${SECURE}" "${MUXER_NAME}")
else
  LISTENER_ENV=$(generate_modern_env_vars "false" "perf-redis:6379" "${TEST_KEY}" "${TRANSPORT_NAME}" "${SECURE}" "${MUXER_NAME}" "${DEBUG:-false}")
fi

if [ "${DIALER_LEGACY}" == "true" ]; then
  DIALER_ENV=$(generate_legacy_env_vars "true" "proxy-${TEST_KEY}:6379" "${TRANSPORT_NAME}" "${SECURE}" "${MUXER_NAME}")
else
  DIALER_ENV=$(generate_modern_env_vars "true" "perf-redis:6379" "${TEST_KEY}" "${TRANSPORT_NAME}" "${SECURE}" "${MUXER_NAME}" "${DEBUG:-false}" \
    "UPLOAD_BYTES=${upload_bytes}" \
    "DOWNLOAD_BYTES=${download_bytes}" \
    "UPLOAD_ITERATIONS=${upload_iterations}" \
    "DOWNLOAD_ITERATIONS=${download_iterations}" \
    "LATENCY_ITERATIONS=${latency_iterations}" \
    "DURATION=${duration}")
fi

# Generate docker-compose file
if [ "${IS_LEGACY_TEST}" == "true" ]; then
  # Legacy test: external shared network + Redis proxy service
  cat > "${COMPOSE_FILE}" <<EOF
name: ${TEST_SLUG}

networks:
  perf-network:
    external: true

services:
  proxy-${TEST_KEY}:
    image: libp2p-redis-proxy
    container_name: ${TEST_SLUG}_proxy
    networks:
      - perf-network
    environment:
      - TEST_KEY=${TEST_KEY}
      - REDIS_ADDR=perf-redis:6379

  listener:
    image: ${LISTENER_IMAGE}
    container_name: ${TEST_SLUG}_listener
    init: true
    depends_on:
      - proxy-${TEST_KEY}
    networks:
      - perf-network
    environment:
${LISTENER_ENV}

  dialer:
    image: ${DIALER_IMAGE}
    container_name: ${TEST_SLUG}_dialer
    depends_on:
      - listener
      - proxy-${TEST_KEY}
    networks:
      - perf-network
    environment:
${DIALER_ENV}
EOF
else
  # Modern test: external shared network, no proxy needed
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
fi

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

# Extract the measurement data from dialer logs
# Docker compose prefixes each line with: "container_name  | "
if [ "${DIALER_LEGACY}" == "true" ]; then
  # Legacy: extract JSON from dialer logs and convert to YAML
  DIALER_JSON=$(echo "${DIALER_LOGS}" | grep "dialer.*|" | sed 's/^.*| //' | tr -d '\r' | grep -v '^\s*$' | grep -E '^\s*[\[{"]' | tr '\n' ' ') || true
  DIALER_YAML=$(echo "${DIALER_JSON}" | yq eval -P '.' - 2>/dev/null || echo "")
else
  # Normal: extract YAML from dialer logs
  # Match only measurement sections and their fields (not logging output)
  DIALER_YAML=$(echo "${DIALER_LOGS}" | grep -E "dialer.*\| (upload:|download:|latency:|  (iterations|min|q1|median|q3|max|outliers|samples|unit):)" | sed 's/^.*| //' || echo "")
fi

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

exit "${EXIT_CODE}"
