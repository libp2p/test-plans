#!/bin/bash
# Run a single hole punch test using docker-compose
# Args: test_name dialer_id listener_id transport

set -euo pipefail

TEST_NAME="$1"
DIALER_ID="$2"
LISTENER_ID="$3"
TRANSPORT="$4"

# Sanitize test name for file names
TEST_SLUG=$(echo "$TEST_NAME" | sed 's/[^a-zA-Z0-9-]/_/g')
LOG_FILE="logs/${TEST_SLUG}.log"

mkdir -p logs

echo "Running: $TEST_NAME" | tee -a "$LOG_FILE"

# Generate docker-compose file for this test
COMPOSE_FILE="docker-compose-${TEST_SLUG}.yaml"

cat > "$COMPOSE_FILE" <<EOF
version: '3.8'

networks:
  hole-punch-network:
    external: true
  lan_dialer:
    driver: bridge
    ipam:
      config:
        - subnet: 172.16.1.0/24
  lan_listener:
    driver: bridge
    ipam:
      config:
        - subnet: 172.16.2.0/24

services:
  dialer-router:
    image: alpine/socat:latest
    container_name: ${TEST_SLUG}_dialer_router
    networks:
      - hole-punch-network
      - lan_dialer
    command: >
      sh -c "while true; do sleep 3600; done"

  listener-router:
    image: alpine/socat:latest
    container_name: ${TEST_SLUG}_listener_router
    networks:
      - hole-punch-network
      - lan_listener
    command: >
      sh -c "while true; do sleep 3600; done"

  dialer:
    image: ${DIALER_ID}
    container_name: ${TEST_SLUG}_dialer
    networks:
      - lan_dialer
    environment:
      - REDIS_ADDR=hole-punch-redis:6379
      - TRANSPORT=${TRANSPORT}
      - MODE=dial
      - TEST_TIMEOUT_SECONDS=\${TEST_TIMEOUT_SECONDS:-30}
    depends_on:
      - dialer-router

  listener:
    image: ${LISTENER_ID}
    container_name: ${TEST_SLUG}_listener
    networks:
      - lan_listener
    environment:
      - REDIS_ADDR=hole-punch-redis:6379
      - TRANSPORT=${TRANSPORT}
      - MODE=listen
      - TEST_TIMEOUT_SECONDS=\${TEST_TIMEOUT_SECONDS:-30}
    depends_on:
      - listener-router
EOF

# Run the test
echo "  → Starting containers..." | tee -a "$LOG_FILE"

# Start containers
if ! docker-compose -f "$COMPOSE_FILE" up --exit-code-from dialer --abort-on-container-exit 2>&1 | tee -a "$LOG_FILE"; then
    echo "  ✗ Test failed" | tee -a "$LOG_FILE"
    EXIT_CODE=1
else
    echo "  ✓ Test passed" | tee -a "$LOG_FILE"
    EXIT_CODE=0
fi

# Cleanup
echo "  → Cleaning up..." | tee -a "$LOG_FILE"
docker-compose -f "$COMPOSE_FILE" down --volumes --remove-orphans 2>&1 >> "$LOG_FILE" || true

# Remove compose file (optional - keep for debugging)
# rm -f "$COMPOSE_FILE"

exit $EXIT_CODE
