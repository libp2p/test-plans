#!/bin/bash
# Run a single hole punch test using docker compose
# Args: test_name dialer_id listener_id transport

set -euo pipefail

center() {
    local str="$1"
    local width="${2:-16}"
    local inner=$((width - 2))
    ((inner < 1)) && inner=1
    str="${str:0:inner}"
    printf "%*s" $(( (inner + ${#str}) / 2 )) "$str"
}

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

# Output full test configuration
echo "" >> "$LOG_FILE"
echo "╲ Test Configuration" >> "$LOG_FILE"
echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔" >> "$LOG_FILE"
echo "Test Name:      $TEST_NAME" >> "$LOG_FILE"
echo "Test Slug:      $TEST_SLUG" >> "$LOG_FILE"
echo "Test Key Hash:  $TEST_KEY" >> "$LOG_FILE"
echo "Dialer ID:      $DIALER_ID" >> "$LOG_FILE"
echo "Listener ID:    $LISTENER_ID" >> "$LOG_FILE"
echo "Transport:      $TRANSPORT" >> "$LOG_FILE"
echo "Debug Mode:     $DEBUG" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

____CWRIP_____=$(center "$RELAY_IP" 16)
____CWDIP_____=$(center "$DIALIER_ROUTER_WAN_IP" 16)
____CWLIP_____=$(center "$DIALIER_ROUTER_WAN_IP" 16)
____CLDIP_____=$(center "$DIALER_ROUTER_LAN_IP" 16)
____CLLIP_____=$(center "$DIALER_ROUTER_LAN_IP" 16)
_____CDIP_____=$(center "$DIALER_IP" 16)
_____CLIP_____=$(center "$LISTENER_IP" 16)

echo "╲ Network Toplogy" >> "$LOG_FILE"
echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"
echo "                    Internet (WAN Network)" >> "$LOG_FILE"
echo "                    $WAN_SUBNET" >> "$LOG_FILE"
echo "                    Gateway: $WAN_GATEWAY" >> "$LOG_FILE"
echo "                             |" >> "$LOG_FILE"
echo "         +-------------------+-------------------+" >> "$LOG_FILE"
echo "         |                   |                   |" >> "$LOG_FILE"
echo "+-----------------+ +-----------------+ +-----------------+" >> "$LOG_FILE"
echo "| $____CWDIP_____ | | $____CWRIP_____ | | $____CWLIP_____ |" >> "$LOG_FILE"
echo "| DialerRouterNAT | |      Relay      | | ListenRouterNAT |" >> "$LOG_FILE"
echo "| $____CLDIP_____ | |                 | | $____CLLIP_____ |" >> "$LOG_FILE"
echo "+-----------------+ +-----------------+ +-----------------+" >> "$LOG_FILE"
echo "         |                                       |" >> "$LOG_FILE"
echo " LAN Dialer Subnet                      LAN Listener Subnet" >> "$LOG_FILE"
echo " $LAN_DIALER_SUBNET                     $LAN_LISTENER_SUBNET" >> "$LOG_FILE"
echo "         |                                       |" >> "$LOG_FILE"
echo "+-----------------+                     +-----------------+" >> "$LOG_FILE"
echo "| $_____CDIP_____ |                     | $_____CLIP_____ |" >> "$LOG_FILE"
echo "|      Dialer     |                     |     Listener    |" >> "$LOG_FILE"
echo "+-----------------+                     +-----------------+" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

echo "╲ Subnet Configuration" >> "$LOG_FILE"
echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔" >> "$LOG_FILE"
echo "Subnet ID Base:       $SUBNET_ID_1.$SUBNET_ID_2" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"
echo "WAN Network:" >> "$LOG_FILE"
echo "  Subnet:             $WAN_SUBNET" >> "$LOG_FILE"
echo "  Gateway:            $WAN_GATEWAY" >> "$LOG_FILE"
echo "  Relay IP:           $RELAY_IP" >> "$LOG_FILE"
echo "  Dialer Router WAN:  $DIALER_ROUTER_WAN_IP" >> "$LOG_FILE"
echo "  Listener Router WAN: $LISTENER_ROUTER_WAN_IP" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"
echo "LAN Dialer Network:" >> "$LOG_FILE"
echo "  Subnet:             $LAN_DIALER_SUBNET" >> "$LOG_FILE"
echo "  Router LAN IP:      $DIALER_ROUTER_LAN_IP" >> "$LOG_FILE"
echo "  Dialer IP:          $DIALER_IP" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"
echo "LAN Listener Network:" >> "$LOG_FILE"
echo "  Subnet:             $LAN_LISTENER_SUBNET" >> "$LOG_FILE"
echo "  Router LAN IP:      $LISTENER_ROUTER_LAN_IP" >> "$LOG_FILE"
echo "  Listener IP:        $LISTENER_IP" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

echo "╲ Docker Containers" >> "$LOG_FILE"
echo " ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"
echo "Container 1: Relay" >> "$LOG_FILE"
echo "  Container Name: ${TEST_SLUG}_relay" >> "$LOG_FILE"
echo "  Image:          $RELAY_IMAGE" >> "$LOG_FILE"
echo "  Dockerfile:     hole-punch-interop-v2/rust-relay/Dockerfile" >> "$LOG_FILE"
echo "  Purpose:        libp2p relay server that facilitates hole punching" >> "$LOG_FILE"
echo "                  coordination between peers behind NATs. Acts as a" >> "$LOG_FILE"
echo "                  rendezvous point for connection establishment." >> "$LOG_FILE"
echo "  Network:        WAN ($RELAY_IP)" >> "$LOG_FILE"
echo "  Delay:          ${RELAY_DELAY}ms" >> "$LOG_FILE"
echo "  Environment:" >> "$LOG_FILE"
echo "    - DELAY_MS=$RELAY_DELAY" >> "$LOG_FILE"
echo "    - REDIS_ADDR=hole-punch-redis:6379" >> "$LOG_FILE"
echo "    - TEST_KEY=$TEST_KEY" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

echo "Container 2: Dialer Router (NAT)" >> "$LOG_FILE"
echo "  Container Name: ${TEST_SLUG}_dialer_router" >> "$LOG_FILE"
echo "  Image:          $ROUTER_IMAGE" >> "$LOG_FILE"
echo "  Dockerfile:     hole-punch-interop-v2/router/Dockerfile" >> "$LOG_FILE"
echo "  Purpose:        Simulates a NAT router for the dialer's local network." >> "$LOG_FILE"
echo "                  Provides network address translation and adds artificial" >> "$LOG_FILE"
echo "                  latency to simulate real-world network conditions." >> "$LOG_FILE"
echo "  Networks:       WAN ($DIALER_ROUTER_WAN_IP)" >> "$LOG_FILE"
echo "                  LAN-Dialer ($DIALER_ROUTER_LAN_IP)" >> "$LOG_FILE"
echo "  Delay:          ${ROUTER_DELAY}ms" >> "$LOG_FILE"
echo "  Environment:" >> "$LOG_FILE"
echo "    - DELAY_MS=$ROUTER_DELAY" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

echo "Container 3: Listener Router (NAT)" >> "$LOG_FILE"
echo "  Container Name: ${TEST_SLUG}_listener_router" >> "$LOG_FILE"
echo "  Image:          $ROUTER_IMAGE" >> "$LOG_FILE"
echo "  Dockerfile:     hole-punch-interop-v2/router/Dockerfile" >> "$LOG_FILE"
echo "  Purpose:        Simulates a NAT router for the listener's local network." >> "$LOG_FILE"
echo "                  Provides network address translation and adds artificial" >> "$LOG_FILE"
echo "                  latency to simulate real-world network conditions." >> "$LOG_FILE"
echo "  Networks:       WAN ($LISTENER_ROUTER_WAN_IP)" >> "$LOG_FILE"
echo "                  LAN-Listener ($LISTENER_ROUTER_LAN_IP)" >> "$LOG_FILE"
echo "  Delay:          ${ROUTER_DELAY}ms" >> "$LOG_FILE"
echo "  Environment:" >> "$LOG_FILE"
echo "    - DELAY_MS=$ROUTER_DELAY" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

echo "Container 4: Dialer" >> "$LOG_FILE"
echo "  Container Name: ${TEST_SLUG}_dialer" >> "$LOG_FILE"
echo "  Image:          $DIALER_ID" >> "$LOG_FILE"
echo "  Dockerfile:     Based on implementation from impls.yaml" >> "$LOG_FILE"
echo "  Purpose:        The peer that initiates the hole punch connection." >> "$LOG_FILE"
echo "                  Tests the ability to establish a direct connection" >> "$LOG_FILE"
echo "                  through NAT using the relay for coordination." >> "$LOG_FILE"
echo "  Network:        LAN-Dialer ($DIALER_IP)" >> "$LOG_FILE"
echo "  Environment:" >> "$LOG_FILE"
echo "    - REDIS_ADDR=hole-punch-redis:6379" >> "$LOG_FILE"
echo "    - TEST_KEY=$TEST_KEY" >> "$LOG_FILE"
echo "    - TRANSPORT=$TRANSPORT" >> "$LOG_FILE"
echo "    - MODE=dial" >> "$LOG_FILE"
echo "    - DEBUG=$DEBUG" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

echo "Container 5: Listener" >> "$LOG_FILE"
echo "  Container Name: ${TEST_SLUG}_listener" >> "$LOG_FILE"
echo "  Image:          $LISTENER_ID" >> "$LOG_FILE"
echo "  Dockerfile:     Based on implementation from impls.yaml" >> "$LOG_FILE"
echo "  Purpose:        The peer that receives the hole punch connection." >> "$LOG_FILE"
echo "                  Tests the ability to accept a direct connection" >> "$LOG_FILE"
echo "                  through NAT using the relay for coordination." >> "$LOG_FILE"
echo "  Network:        LAN-Listener ($LISTENER_IP)" >> "$LOG_FILE"
echo "  Environment:" >> "$LOG_FILE"
echo "    - REDIS_ADDR=hole-punch-redis:6379" >> "$LOG_FILE"
echo "    - TEST_KEY=$TEST_KEY" >> "$LOG_FILE"
echo "    - TRANSPORT=$TRANSPORT" >> "$LOG_FILE"
echo "    - MODE=listen" >> "$LOG_FILE"
echo "    - DEBUG=$DEBUG" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

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
