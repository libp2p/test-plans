#!/bin/bash
# Run a single hole punch test using docker compose
# Args: test_name dialer_id listener_id transport

set -euo pipefail

# Use the docker compose command passed via environment variable
# Default to 'docker compose' if not set
DOCKER_COMPOSE_CMD="${DOCKER_COMPOSE_CMD:-docker compose}"

TEST_NAME="$1"
DIALER_ID="$2"
LISTENER_ID="$3"
TRANSPORT="$4"

# Read DEBUG from test-matrix.yaml
DEBUG=$(yq eval '.metadata.debug' "${TEST_PASS_DIR:-.}/test-matrix.yaml" 2>/dev/null || echo "false")

# Load router and relay image configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROUTER_IMAGE=$(yq eval '.routers[0].image' "$SCRIPT_DIR/../impls.yaml")
ROUTER_DELAY=$(yq eval '.routers[0].delayMs' "$SCRIPT_DIR/../impls.yaml")
RELAY_IMAGE=$(yq eval '.relay.image' "$SCRIPT_DIR/../impls.yaml")
RELAY_DELAY=$(yq eval '.relay.delayMs' "$SCRIPT_DIR/../impls.yaml")

# Sanitize test name for file names
TEST_SLUG=$(echo "$TEST_NAME" | sed 's/[^a-zA-Z0-9-]/_/g')

# Generate Redis key prefix from test name hash (first 10 hex chars)
TEST_KEY=$(echo -n "$TEST_NAME" | sha256sum | cut -c1-10)

# Derive two-octet unique subnet IDs from TEST_KEY with offset
# Offset by 32 to avoid common 10.0.0.x and 10.10.x.x ranges
SUBNET_ID_1=$(( (16#${TEST_KEY:0:2} + 32) % 256 ))
SUBNET_ID_2=$(( (16#${TEST_KEY:2:2} + 32) % 256 ))

# Calculate network addresses
WAN_SUBNET="10.${SUBNET_ID_1}.${SUBNET_ID_2}.64/29"
WAN_GATEWAY="10.${SUBNET_ID_1}.${SUBNET_ID_2}.70"
LAN_DIALER_SUBNET="10.${SUBNET_ID_1}.${SUBNET_ID_2}.92/30"
LAN_LISTENER_SUBNET="10.${SUBNET_ID_1}.${SUBNET_ID_2}.128/30"

# Calculate fixed IP addresses
RELAY_IP="10.${SUBNET_ID_1}.${SUBNET_ID_2}.65"
DIALER_ROUTER_WAN_IP="10.${SUBNET_ID_1}.${SUBNET_ID_2}.66"
DIALER_ROUTER_LAN_IP="10.${SUBNET_ID_1}.${SUBNET_ID_2}.93"
LISTENER_ROUTER_WAN_IP="10.${SUBNET_ID_1}.${SUBNET_ID_2}.67"
LISTENER_ROUTER_LAN_IP="10.${SUBNET_ID_1}.${SUBNET_ID_2}.129"
DIALER_IP="10.${SUBNET_ID_1}.${SUBNET_ID_2}.94"
LISTENER_IP="10.${SUBNET_ID_1}.${SUBNET_ID_2}.130"

# Use TEST_PASS_DIR if set, otherwise fall back to local logs directory
LOGS_DIR="${TEST_PASS_DIR:-.}/logs"
COMPOSE_DIR="${TEST_PASS_DIR:-.}/docker-compose"

LOG_FILE="$LOGS_DIR/${TEST_SLUG}.log"
COMPOSE_FILE="$COMPOSE_DIR/${TEST_SLUG}-compose.yaml"

mkdir -p "$LOGS_DIR"
mkdir -p "$COMPOSE_DIR"

echo "Running: $TEST_NAME (key: $TEST_KEY, subnet: $SUBNET_ID_1.$SUBNET_ID_2)" >> "$LOG_FILE"

# Generate docker compose file for this test
cat > "$COMPOSE_FILE" <<EOF
name: ${TEST_SLUG}

networks:
  redis-network:
    external: true
    name: hole-punch-network
  wan:
    driver: bridge
    ipam:
      config:
        - subnet: ${WAN_SUBNET}
          gateway: ${WAN_GATEWAY}
  lan-dialer:
    driver: bridge
    ipam:
      config:
        - subnet: ${LAN_DIALER_SUBNET}
  lan-listener:
    driver: bridge
    ipam:
      config:
        - subnet: ${LAN_LISTENER_SUBNET}

services:
  relay:
    image: ${RELAY_IMAGE}
    container_name: ${TEST_SLUG}_relay
    networks:
      wan:
        ipv4_address: ${RELAY_IP}
      redis-network: {}
    environment:
      - DELAY_MS=${RELAY_DELAY}
      - REDIS_ADDR=hole-punch-redis:6379
      - TEST_KEY=${TEST_KEY}
    cap_add:
      - NET_ADMIN
    init: true

  dialer-router:
    image: ${ROUTER_IMAGE}
    container_name: ${TEST_SLUG}_dialer_router
    networks:
      wan:
        ipv4_address: ${DIALER_ROUTER_WAN_IP}
      lan-dialer:
        ipv4_address: ${DIALER_ROUTER_LAN_IP}
    environment:
      - DELAY_MS=${ROUTER_DELAY}
    cap_add:
      - NET_ADMIN
    init: true
    depends_on:
      - relay

  listener-router:
    image: ${ROUTER_IMAGE}
    container_name: ${TEST_SLUG}_listener_router
    networks:
      wan:
        ipv4_address: ${LISTENER_ROUTER_WAN_IP}
      lan-listener:
        ipv4_address: ${LISTENER_ROUTER_LAN_IP}
    environment:
      - DELAY_MS=${ROUTER_DELAY}
    cap_add:
      - NET_ADMIN
    init: true
    depends_on:
      - relay

  dialer:
    image: ${DIALER_ID}
    container_name: ${TEST_SLUG}_dialer
    networks:
      lan-dialer:
        ipv4_address: ${DIALER_IP}
      redis-network: {}
    environment:
      - REDIS_ADDR=hole-punch-redis:6379
      - TEST_KEY=${TEST_KEY}
      - TRANSPORT=${TRANSPORT}
      - MODE=dial
      - TEST_TIMEOUT_SECONDS=\${TEST_TIMEOUT_SECONDS:-30}
      - DEBUG=${DEBUG}
    cap_add:
      - NET_ADMIN
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    depends_on:
      - dialer-router
      - relay

  listener:
    image: ${LISTENER_ID}
    container_name: ${TEST_SLUG}_listener
    networks:
      lan-listener:
        ipv4_address: ${LISTENER_IP}
      redis-network: {}
    environment:
      - REDIS_ADDR=hole-punch-redis:6379
      - TEST_KEY=${TEST_KEY}
      - TRANSPORT=${TRANSPORT}
      - MODE=listen
      - TEST_TIMEOUT_SECONDS=\${TEST_TIMEOUT_SECONDS:-30}
      - DEBUG=${DEBUG}
    cap_add:
      - NET_ADMIN
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    depends_on:
      - listener-router
      - relay
EOF

# Run the test
echo "  → Starting containers..." >> "$LOG_FILE"

# Start containers
if $DOCKER_COMPOSE_CMD -f "$COMPOSE_FILE" up --exit-code-from dialer --abort-on-container-exit >> "$LOG_FILE" 2>&1; then
    EXIT_CODE=0
else
    EXIT_CODE=1
fi

# Cleanup
echo "  → Cleaning up..." >> "$LOG_FILE"
$DOCKER_COMPOSE_CMD -f "$COMPOSE_FILE" down --volumes --remove-orphans >> "$LOG_FILE" 2>&1 || true

# Remove compose file (optional - keep for debugging)
# rm -f "$COMPOSE_FILE"

exit $EXIT_CODE
