#!/bin/bash
# Run a single transport interop test using docker-compose
# Args: test_name dialer_id listener_id transport [secure_channel] [muxer]

set -euo pipefail

TEST_NAME="$1"
DIALER_ID="$2"
LISTENER_ID="$3"
TRANSPORT="$4"
SECURE_CHANNEL="${5:-null}"  # Optional for standalone transports
MUXER="${6:-null}"           # Optional for standalone transports

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
  test-network:
    driver: bridge

services:
  listener:
    image: ${LISTENER_ID}
    container_name: ${TEST_SLUG}_listener
    networks:
      - test-network
    environment:
      - TRANSPORT=${TRANSPORT}
      - SECURE_CHANNEL=${SECURE_CHANNEL}
      - MUXER=${MUXER}
      - IS_DIALER=false
      - REDIS_ADDR=redis:6379

  dialer:
    image: ${DIALER_ID}
    container_name: ${TEST_SLUG}_dialer
    networks:
      - test-network
    environment:
      - TRANSPORT=${TRANSPORT}
      - SECURE_CHANNEL=${SECURE_CHANNEL}
      - MUXER=${MUXER}
      - IS_DIALER=true
      - REDIS_ADDR=redis:6379
    depends_on:
      - listener

  redis:
    image: redis:7-alpine
    container_name: ${TEST_SLUG}_redis
    networks:
      - test-network
    command: redis-server --save "" --appendonly no
EOF

# Run the test
echo "  → Starting containers..." | tee -a "$LOG_FILE"

# Start containers and wait for dialer to exit
if docker-compose -f "$COMPOSE_FILE" up --exit-code-from dialer --abort-on-container-exit 2>&1 | tee -a "$LOG_FILE"; then
    echo "  ✓ Test passed" | tee -a "$LOG_FILE"
    EXIT_CODE=0
else
    echo "  ✗ Test failed" | tee -a "$LOG_FILE"
    EXIT_CODE=1
fi

# Cleanup
echo "  → Cleaning up..." | tee -a "$LOG_FILE"
docker-compose -f "$COMPOSE_FILE" down --volumes --remove-orphans 2>&1 >> "$LOG_FILE" || true

# Keep compose file for debugging (can uncomment to remove)
# rm -f "$COMPOSE_FILE"

exit $EXIT_CODE
