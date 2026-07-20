#!/bin/bash
# Run a single Echo protocol interoperability test
# Usage: run-single-test.sh <test-name>

set -euo pipefail

##### 1. SETUP

TEST_NAME="${1:-}"
if [[ -z "${TEST_NAME}" ]]; then
    echo "ERROR: Test name required" >&2
    echo "Usage: $0 <test-name>" >&2
    exit 1
fi

# Source common libraries
source "${SCRIPT_LIB_DIR}/lib-output-formatting.sh"
source "${SCRIPT_LIB_DIR}/lib-test-caching.sh"

##### 2. LOAD TEST DEFINITION

CACHE_KEY=$(compute_test_cache_key)
TEST_MATRIX_FILE="${CACHE_DIR}/test-matrix/echo-${CACHE_KEY}.yaml"

if [[ ! -f "${TEST_MATRIX_FILE}" ]]; then
    echo "ERROR: Test matrix not found: ${TEST_MATRIX_FILE}" >&2
    echo "Run generate-tests.sh first" >&2
    exit 1
fi

# Extract test definition
TEST_DEF=$(yq eval ".tests[] | select(.name == \"${TEST_NAME}\")" "${TEST_MATRIX_FILE}")
if [[ -z "${TEST_DEF}" ]]; then
    echo "ERROR: Test not found: ${TEST_NAME}" >&2
    exit 1
fi

# Parse test parameters
SERVER_ID=$(echo "${TEST_DEF}" | yq eval '.server' -)
CLIENT_ID=$(echo "${TEST_DEF}" | yq eval '.client' -)
TRANSPORT=$(echo "${TEST_DEF}" | yq eval '.transport' -)
SECURE_CHANNEL=$(echo "${TEST_DEF}" | yq eval '.secureChannel' -)
MUXER=$(echo "${TEST_DEF}" | yq eval '.muxer' -)
PROTOCOL=$(echo "${TEST_DEF}" | yq eval '.protocol' -)
TIMEOUT=$(echo "${TEST_DEF}" | yq eval '.timeout' -)

##### 3. DOCKER COMPOSE SETUP

COMPOSE_FILE="${CACHE_DIR}/test-docker-compose/echo-${CACHE_KEY}-${TEST_NAME}.yaml"

if [[ ! -f "${COMPOSE_FILE}" ]]; then
    echo "ERROR: Docker compose file not found: ${COMPOSE_FILE}" >&2
    echo "Run generate-tests.sh first" >&2
    exit 1
fi

##### 4. RUN TEST

print_message "Running Echo test: ${TEST_NAME}"
print_message "  Server: ${SERVER_ID}"
print_message "  Client: ${CLIENT_ID}"
print_message "  Transport: ${TRANSPORT}"
print_message "  Security: ${SECURE_CHANNEL}"
print_message "  Muxer: ${MUXER}"
print_message "  Protocol: ${PROTOCOL}"

# Create test network
NETWORK_NAME="echo-test-${TEST_NAME}"
docker network create "${NETWORK_NAME}" 2>/dev/null || true

# Start Redis coordination service
print_message "Starting Redis coordination service..."
REDIS_CONTAINER="redis-${TEST_NAME}"
docker run -d --name "${REDIS_CONTAINER}" \
    --network "${NETWORK_NAME}" \
    redis:alpine >/dev/null

# Wait for Redis to be ready
sleep 2

# Start Echo server
print_message "Starting Echo server (${SERVER_ID})..."
SERVER_CONTAINER="server-${TEST_NAME}"
docker run -d --name "${SERVER_CONTAINER}" \
    --network "${NETWORK_NAME}" \
    -e REDIS_ADDR="redis://${REDIS_CONTAINER}:6379" \
    -e TRANSPORT="${TRANSPORT}" \
    -e SECURITY="${SECURE_CHANNEL}" \
    -e MUXER="${MUXER}" \
    "${SERVER_ID}" >/dev/null

# Wait for server to start and publish multiaddr
print_message "Waiting for server to start..."
sleep 5

# Run Echo client test
print_message "Running Echo client test (${CLIENT_ID})..."
CLIENT_CONTAINER="client-${TEST_NAME}"

# Run client and capture output
if docker run --name "${CLIENT_CONTAINER}" \
    --network "${NETWORK_NAME}" \
    -e REDIS_ADDR="redis://${REDIS_CONTAINER}:6379" \
    -e TRANSPORT="${TRANSPORT}" \
    -e SECURITY="${SECURE_CHANNEL}" \
    -e MUXER="${MUXER}" \
    -e TIMEOUT="${TIMEOUT}" \
    "${CLIENT_ID}" 2>/dev/null; then
    
    TEST_RESULT="PASS"
    print_message "✅ Test PASSED: ${TEST_NAME}"
else
    TEST_RESULT="FAIL"
    print_message "❌ Test FAILED: ${TEST_NAME}"
    
    # Show container logs for debugging
    echo "=== Server logs ===" >&2
    docker logs "${SERVER_CONTAINER}" 2>&1 | tail -20 >&2
    echo "=== Client logs ===" >&2
    docker logs "${CLIENT_CONTAINER}" 2>&1 | tail -20 >&2
fi

##### 5. CLEANUP

print_message "Cleaning up test containers..."

# Stop and remove containers
docker stop "${REDIS_CONTAINER}" "${SERVER_CONTAINER}" 2>/dev/null || true
docker rm "${REDIS_CONTAINER}" "${SERVER_CONTAINER}" "${CLIENT_CONTAINER}" 2>/dev/null || true

# Remove network
docker network rm "${NETWORK_NAME}" 2>/dev/null || true

##### 6. RESULTS

# Output test result in structured format
cat << EOF
{
  "test": "${TEST_NAME}",
  "server": "${SERVER_ID}",
  "client": "${CLIENT_ID}",
  "transport": "${TRANSPORT}",
  "secureChannel": "${SECURE_CHANNEL}",
  "muxer": "${MUXER}",
  "protocol": "${PROTOCOL}",
  "result": "${TEST_RESULT}",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF

# Exit with appropriate code
if [[ "${TEST_RESULT}" == "PASS" ]]; then
    exit 0
else
    exit 1
fi