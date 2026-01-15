#!/bin/bash
# Run a single hole punch test using docker compose

set -euo pipefail

export LOG_FILE

source "${SCRIPT_LIB_DIR}/lib-output-formatting.sh"
source "${SCRIPT_LIB_DIR}/lib-test-caching.sh"

TEST_INDEX="${1}"
TEST_PASS="${2:-tests}"  # "tests" (no baselines in transport)
RESULTS_FILE="${3:-"${TEST_PASS_DIR}/results.yaml.tmp"}"

print_debug "test index: ${TEST_INDEX}"
print_debug "test_pass: ${TEST_PASS}"

# Read test configuration from matrix
DIALER_ID=$(yq eval ".${TEST_PASS}[${TEST_INDEX}].dialer.id" "${TEST_PASS_DIR}/test-matrix.yaml")
LISTENER_ID=$(yq eval ".${TEST_PASS}[${TEST_INDEX}].listener.id" "${TEST_PASS_DIR}/test-matrix.yaml")
RELAY_ID=$(yq eval ".${TEST_PASS}[${TEST_INDEX}].relay.id" "${TEST_PASS_DIR}/test-matrix.yaml")
DIALER_ROUTER_ID=$(yq eval ".${TEST_PASS}[${TEST_INDEX}].dialerRouter.id" "${TEST_PASS_DIR}/test-matrix.yaml")
LISTENER_ROUTER_ID=$(yq eval ".${TEST_PASS}[${TEST_INDEX}].listenerRouter.id" "${TEST_PASS_DIR}/test-matrix.yaml")
TRANSPORT_NAME=$(yq eval ".${TEST_PASS}[${TEST_INDEX}].transport" "${TEST_PASS_DIR}/test-matrix.yaml")
SECURE_CHANNEL_NAME=$(yq eval ".${TEST_PASS}[${TEST_INDEX}].secureChannel" "${TEST_PASS_DIR}/test-matrix.yaml")
MUXER_NAME=$(yq eval ".${TEST_PASS}[${TEST_INDEX}].muxer" "${TEST_PASS_DIR}/test-matrix.yaml")
TEST_NAME=$(yq eval ".${TEST_PASS}[${TEST_INDEX}].id" "${TEST_PASS_DIR}/test-matrix.yaml")

print_debug "test_name: ${TEST_NAME}"
print_debug "dialer id: ${DIALER_ID}"
print_debug "listener id: ${LISTENER_ID}"
print_debug "relay id: ${RELAY_ID}"
print_debug "dialer router id: ${DIALER_ROUTER_ID}"
print_debug "listener router id: ${LISTENER_ROUTER_ID}"
print_debug "transport: ${TRANSPORT_NAME}"
print_debug "secure: ${SECURE_CHANNEL_NAME}"
print_debug "muxer: ${MUXER_NAME}"
print_debug "debug: ${DEBUG}"

# Compute TEST_KEY for Redis key namespacing (8-char hex hash)
TEST_KEY=$(compute_test_key "${TEST_NAME}")
TEST_SLUG=$(echo "${TEST_NAME}" | sed 's/[^a-zA-Z0-9-]/_/g')
LOG_FILE="${TEST_PASS_DIR}/logs/${TEST_SLUG}.log"
> "${LOG_FILE}"

print_debug "test key: ${TEST_KEY}"
print_debug "test slug: ${TEST_SLUG}"
print_debug "log file: ${LOG_FILE}"

# Derive two-octet unique subnet IDs from TEST_KEY with offset
# This mods it by 224 and adds 32 so that the result will land between 32 and
# 255, thus avoiding common 10.0.0.x and 10.10.x.x subnets
SUBNET_ID_1=$(( (16#${TEST_KEY:0:2} % 224 ) + 32 ))
SUBNET_ID_2=$(( (16#${TEST_KEY:2:2} % 224 ) + 32 ))

# Calculate network addresses
WAN_SUBNET="10.${SUBNET_ID_1}.${SUBNET_ID_2}.64/27"
DIALER_LAN_SUBNET="10.${SUBNET_ID_1}.${SUBNET_ID_2}.96/27"
LISTENER_LAN_SUBNET="10.${SUBNET_ID_1}.${SUBNET_ID_2}.128/27"

print_debug "WAN subnet: ${WAN_SUBNET}"
print_debug "dialer LAN subnet: ${DIALER_LAN_SUBNET}"
print_debug "listener LAN subnet: ${LISTENER_LAN_SUBNET}"

# Calculate fixed IP addresses
# Note: Docker auto-assigns first usable IP (.65, .97, .129) to bridge gateway
RELAY_IP="10.${SUBNET_ID_1}.${SUBNET_ID_2}.68"
DIALER_IP="10.${SUBNET_ID_1}.${SUBNET_ID_2}.99"
LISTENER_IP="10.${SUBNET_ID_1}.${SUBNET_ID_2}.131"
DIALER_ROUTER_WAN_IP="10.${SUBNET_ID_1}.${SUBNET_ID_2}.66"
DIALER_ROUTER_LAN_IP="10.${SUBNET_ID_1}.${SUBNET_ID_2}.98"
LISTENER_ROUTER_WAN_IP="10.${SUBNET_ID_1}.${SUBNET_ID_2}.67"
LISTENER_ROUTER_LAN_IP="10.${SUBNET_ID_1}.${SUBNET_ID_2}.130"

print_debug "relay IP: ${RELAY_IP}"
print_debug "dialer IP: ${DIALER_IP}"
print_debug "listener IP: ${LISTENER_IP}"
print_debug "dialer router WAN IP: ${DIALER_ROUTER_WAN_IP}"
print_debug "dialer router LAN IP: ${DIALER_ROUTER_LAN_IP}"
print_debug "listener router WAN IP: ${LISTENER_ROUTER_WAN_IP}"
print_debug "listener router LAN IP: ${LISTENER_ROUTER_LAN_IP}"

log_message "[$((${TEST_INDEX} + 1))] ${TEST_NAME} (key: ${TEST_KEY})"

# Load Docker image names
DIALER_IMAGE=$(yq eval ".${TEST_PASS}[${TEST_INDEX}].dialer.imageName" "${TEST_PASS_DIR}/test-matrix.yaml")
LISTENER_IMAGE=$(yq eval ".${TEST_PASS}[${TEST_INDEX}].listener.imageName" "${TEST_PASS_DIR}/test-matrix.yaml")
RELAY_IMAGE=$(yq eval ".${TEST_PASS}[${TEST_INDEX}].relay.imageName" "${TEST_PASS_DIR}/test-matrix.yaml")
DIALER_ROUTER_IMAGE=$(yq eval ".${TEST_PASS}[${TEST_INDEX}].dialerRouter.imageName" "${TEST_PASS_DIR}/test-matrix.yaml")
LISTENER_ROUTER_IMAGE=$(yq eval ".${TEST_PASS}[${TEST_INDEX}].listenerRouter.imageName" "${TEST_PASS_DIR}/test-matrix.yaml")

print_debug "dialer image: ${DIALER_IMAGE}"
print_debug "listener image: ${LISTENER_IMAGE}"
print_debug "relay image: ${RELAY_IMAGE}"
print_debug "dialer router image: ${DIALER_ROUTER_IMAGE}"
print_debug "listener router image: ${LISTENER_ROUTER_IMAGE}"

# Generate docker-compose file
COMPOSE_FILE="${TEST_PASS_DIR}/docker-compose/${TEST_SLUG}-compose.yaml"

print_debug "docker compose file: ${COMPOSE_FILE}"

# Build environment variables for relay
RELAY_ENV="      - REDIS_ADDR=hole-punch-redis:6379
      - TEST_KEY=${TEST_KEY}
      - TRANSPORT=${TRANSPORT_NAME}
      - RELAY_IP=${RELAY_IP}
      - DIALER_LAN_SUBNET=${DIALER_LAN_SUBNET}
      - DIALER_ROUTER_IP=${DIALER_ROUTER_WAN_IP}
      - LISTENER_LAN_SUBNET=${LISTENER_LAN_SUBNET}
      - LISTENER_ROUTER_IP=${LISTENER_ROUTER_WAN_IP}
      - DEBUG=${DEBUG:-false}"

if [ "${SECURE_CHANNEL_NAME}" != "null" ]; then
    RELAY_ENV="${RELAY_ENV}
      - SECURE_CHANNEL=${SECURE_CHANNEL_NAME}"
fi

if [ "${MUXER_NAME}" != "null" ]; then
    RELAY_ENV="${RELAY_ENV}
      - MUXER=${MUXER_NAME}"
fi

# Build environment variables for dialer
DIALER_ROUTER_ENV="      - WAN_IP=${DIALER_ROUTER_WAN_IP}
      - WAN_SUBNET=${WAN_SUBNET}
      - LAN_IP=${DIALER_ROUTER_LAN_IP}
      - LAN_SUBNET=${DIALER_LAN_SUBNET}
      - TEST_KEY=${TEST_KEY}
      - DEBUG=${DEBUG:-false}"

# Build environment variables for listener
LISTENER_ROUTER_ENV="      - WAN_IP=${LISTENER_ROUTER_WAN_IP}
      - WAN_SUBNET=${WAN_SUBNET}
      - LAN_IP=${LISTENER_ROUTER_LAN_IP}
      - LAN_SUBNET=${LISTENER_LAN_SUBNET}
      - TEST_KEY=${TEST_KEY}
      - DEBUG=${DEBUG:-false}"

# Build environment variables for dialer
DIALER_ENV="      - IS_DIALER=true
      - REDIS_ADDR=hole-punch-redis:6379
      - TEST_KEY=${TEST_KEY}
      - TRANSPORT=${TRANSPORT_NAME}
      - DIALER_IP=${DIALER_IP}
      - WAN_SUBNET=${WAN_SUBNET}
      - WAN_ROUTER_IP=${DIALER_ROUTER_LAN_IP}
      - DEBUG=${DEBUG:-false}"

if [ "${SECURE_CHANNEL_NAME}" != "null" ]; then
    DIALER_ENV="${DIALER_ENV}
      - SECURE_CHANNEL=${SECURE_CHANNEL_NAME}"
fi

if [ "${MUXER_NAME}" != "null" ]; then
    DIALER_ENV="${DIALER_ENV}
      - MUXER=${MUXER_NAME}"
fi

# Build environment variables for listener
LISTENER_ENV="      - IS_DIALER=false
      - REDIS_ADDR=hole-punch-redis:6379
      - TEST_KEY=${TEST_KEY}
      - TRANSPORT=${TRANSPORT_NAME}
      - LISTENER_IP=${LISTENER_IP}
      - WAN_SUBNET=${WAN_SUBNET}
      - WAN_ROUTER_IP=${LISTENER_ROUTER_LAN_IP}
      - DEBUG=${DEBUG:-false}"

if [ "${SECURE_CHANNEL_NAME}" != "null" ]; then
    LISTENER_ENV="${LISTENER_ENV}
      - SECURE_CHANNEL=${SECURE_CHANNEL_NAME}"
fi

if [ "${MUXER_NAME}" != "null" ]; then
    LISTENER_ENV="${LISTENER_ENV}
      - MUXER=${MUXER_NAME}"
fi

# Generate docker-compose file
cat > "${COMPOSE_FILE}" <<EOF
name: ${TEST_SLUG}

networks:
  hole-punch-network:
    external: true
  wan:
    driver: bridge
    ipam:
      config:
        - subnet: ${WAN_SUBNET}
  lan-dialer:
    driver: bridge
    ipam:
      config:
        - subnet: ${DIALER_LAN_SUBNET}
  lan-listener:
    driver: bridge
    ipam:
      config:
        - subnet: ${LISTENER_LAN_SUBNET}

services:
  relay:
    image: ${RELAY_IMAGE}
    container_name: ${TEST_SLUG}_relay
    init: true
    networks:
      wan:
        ipv4_address: ${RELAY_IP}
        interface_name: wan0
        gw_priority: 1000
      hole-punch-network:
        interface_name: redis0
        gw_priority: 100
    cap_add:
      - NET_ADMIN
    environment:
${RELAY_ENV}

  dialer-router:
    image: ${DIALER_ROUTER_IMAGE}
    container_name: ${TEST_SLUG}_dialer_router
    init: true
    networks:
      wan:
        ipv4_address: ${DIALER_ROUTER_WAN_IP}
        interface_name: wan0
        gw_priority: 1000
      lan-dialer:
        ipv4_address: ${DIALER_ROUTER_LAN_IP}
        interface_name: lan0
        gw_priority: 100
    cap_add:
      - NET_ADMIN
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv4.conf.all.forwarding=1
      - net.ipv4.conf.default.forwarding=1
      - net.ipv4.conf.all.rp_filter=0
      - net.ipv4.conf.default.rp_filter=0
    depends_on:
      - relay
    environment:
${DIALER_ROUTER_ENV}

  listener-router:
    image: ${LISTENER_ROUTER_IMAGE}
    container_name: ${TEST_SLUG}_listener_router
    init: true
    networks:
      wan:
        ipv4_address: ${LISTENER_ROUTER_WAN_IP}
        interface_name: wan0
        gw_priority: 1000
      lan-listener:
        ipv4_address: ${LISTENER_ROUTER_LAN_IP}
        interface_name: lan0
        gw_priority: 100
    cap_add:
      - NET_ADMIN
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv4.conf.all.forwarding=1
      - net.ipv4.conf.default.forwarding=1
      - net.ipv4.conf.all.rp_filter=0
      - net.ipv4.conf.default.rp_filter=0
    depends_on:
      - relay
    environment:
${LISTENER_ROUTER_ENV}

  dialer:
    image: ${DIALER_IMAGE}
    container_name: ${TEST_SLUG}_dialer
    init: true
    networks:
      lan-dialer:
        ipv4_address: ${DIALER_IP}
        interface_name: lan0
        gw_priority: 1000
      hole-punch-network:
        interface_name: redis0
        gw_priority: 1000
    cap_add:
      - NET_ADMIN
    depends_on:
      - relay
      - dialer-router
    environment:
${DIALER_ENV}

  listener:
    image: ${LISTENER_IMAGE}
    container_name: ${TEST_SLUG}_listener
    init: true
    networks:
      lan-listener:
        ipv4_address: ${LISTENER_IP}
        interface_name: lan0
        gw_priority: 1000
      hole-punch-network:
        interface_name: redis0
        gw_priority: 1000
    cap_add:
      - NET_ADMIN
    depends_on:
      - relay
      - listener-router
    environment:
${LISTENER_ENV}

EOF

# Run the test
log_debug "  Starting containers..."
log_message "Running: ${TEST_NAME}" > "${LOG_FILE}"

# Set timeout (180 seconds / 3 minutes for transport tests)
TEST_TIMEOUT=180

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

# Extract the results YAML
# Docker compose prefixes each line with: "container_name  | "
# We need to strip this prefix and keep only the YAML content
# Match only measurement sections and their fields (not logging output)
DIALER_YAML=$(echo "${DIALER_LOGS}" | grep -E "dialer.*\| (latency:|  (handshake_plus_one_rtt|ping_rtt|unit):)" | sed 's/^.*| //' || echo "")

# Save complete result to individual file
cat > "${TEST_PASS_DIR}/results/${TEST_NAME}.yaml" <<EOF
test: ${TEST_NAME}
dialer: ${DIALER_ID}
listener: ${LISTENER_ID}
relay: ${RELAY_ID}
dialerRouter: ${DIALER_ROUTER_ID}
listenerRouter: ${LISTENER_ROUTER_ID}
transport: ${TRANSPORT_NAME}
secureChannel: ${SECURE_CHANNEL_NAME}
muxer: ${MUXER_NAME}
status: $([ "${EXIT_CODE}" -eq 0 ] && echo "pass" || echo "fail")
duration: ${TEST_DURATION}

# Measurements from dialer
${DIALER_YAML}
EOF

# Proper indentation for nested YAML (add 4 spaces to measurement lines)
INDENTED_YAML=$(echo "${DIALER_YAML}" | sed 's/^/    /')

# Append to combined results file with file locking
(
    flock -x 200
    cat >> "${RESULTS_FILE}" <<EOF
  - name: ${TEST_NAME}
    dialer: ${DIALER_ID}
    listener: ${LISTENER_ID}
    relay: ${RELAY_ID}
    dialerRouter: ${DIALER_ROUTER_ID}
    listenerRouter: ${LISTENER_ROUTER_ID}
    transport: ${TRANSPORT_NAME}
    secureChannel: ${SECURE_CHANNEL_NAME}
    muxer: ${MUXER_NAME}
    status: $([ "${EXIT_CODE}" -eq 0 ] && echo "pass" || echo "fail")
    duration: ${TEST_DURATION}s
${INDENTED_YAML}
EOF
) 200>/tmp/results.lock

# Cleanup
log_debug "  Cleaning up containers..."
# WARNING: Do NOT put quotes around this because the command has two parts
${DOCKER_COMPOSE_CMD} -f "${COMPOSE_FILE}" down --volumes --remove-orphans >> "${LOG_FILE}" 2>&1 || true

exit "${EXIT_CODE}"






