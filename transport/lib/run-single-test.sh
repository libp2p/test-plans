#!/bin/bash
# Run a single transport interop test using docker compose
# Args: test_name dialer_id listener_id transport [secure_channel] [muxer]

set -euo pipefail

# Use the docker compose command passed via environment variable
# Default to 'docker compose' if not set
DOCKER_COMPOSE_CMD="${DOCKER_COMPOSE_CMD:-docker compose}"

TEST_NAME="$1"
DIALER_ID="$2"
LISTENER_ID="$3"
TRANSPORT="$4"
SECURE_CHANNEL="${5:-null}"  # Optional for standalone transports
MUXER="${6:-null}"           # Optional for standalone transports

# Compute TEST_KEY for Redis key namespacing (8-char hex)
SCRIPT_LIB_DIR="${SCRIPT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib}"
source "$SCRIPT_LIB_DIR/lib-test-keys.sh"
TEST_KEY=$(compute_test_key "$TEST_NAME")

# Construct Docker image names with transport-interop prefix
DIALER_IMAGE="transport-interop-${DIALER_ID}"
LISTENER_IMAGE="transport-interop-${LISTENER_ID}"

# Read debug flag from test-matrix.yaml
DEBUG=$(yq eval '.metadata.debug' "${TEST_PASS_DIR:-.}/test-matrix.yaml" 2>/dev/null || echo "false")

# Sanitize test name for file names
TEST_SLUG=$(echo "$TEST_NAME" | sed 's/[^a-zA-Z0-9-]/_/g')

# Use TEST_PASS_DIR if set, otherwise fall back to local logs directory
LOGS_DIR="${TEST_PASS_DIR:-.}/logs"
COMPOSE_DIR="${TEST_PASS_DIR:-.}/docker-compose"

LOG_FILE="$LOGS_DIR/${TEST_SLUG}.log"

# Only log to file, no console output
echo "Running: $TEST_NAME (key: $TEST_KEY)" >> "$LOG_FILE"

# Generate docker-compose file for this test
COMPOSE_FILE="$COMPOSE_DIR/${TEST_SLUG}-compose.yaml"

# Build environment variables for dialer
DIALER_ENV="      - version=$DIALER_ID
      - transport=$TRANSPORT
      - is_dialer=true
      - ip=0.0.0.0
      - REDIS_ADDR=transport-redis:6379
      - TEST_KEY=$TEST_KEY
      - debug=$DEBUG"

# Add optional muxer and security for dialer
if [ "$MUXER" != "null" ]; then
    DIALER_ENV="$DIALER_ENV
      - muxer=$MUXER"
fi

if [ "$SECURE_CHANNEL" != "null" ]; then
    DIALER_ENV="$DIALER_ENV
      - security=$SECURE_CHANNEL"
fi

# Build environment variables for listener
LISTENER_ENV="      - version=$LISTENER_ID
      - transport=$TRANSPORT
      - is_dialer=false
      - ip=0.0.0.0
      - REDIS_ADDR=transport-redis:6379
      - TEST_KEY=$TEST_KEY
      - debug=$DEBUG"

# Add optional muxer and security for listener
if [ "$MUXER" != "null" ]; then
    LISTENER_ENV="$LISTENER_ENV
      - muxer=$MUXER"
fi

if [ "$SECURE_CHANNEL" != "null" ]; then
    LISTENER_ENV="$LISTENER_ENV
      - security=$SECURE_CHANNEL"
fi

# Generate compose file (without deprecated 'version' field)
cat > "$COMPOSE_FILE" <<EOF
name: ${TEST_SLUG}

networks:
  transport-network:
    external: true

services:
  listener:
    image: ${LISTENER_IMAGE}
    container_name: ${TEST_SLUG}_listener
    init: true
    networks:
      - transport-network
    environment:
$LISTENER_ENV

  dialer:
    image: ${DIALER_IMAGE}
    container_name: ${TEST_SLUG}_dialer
    depends_on:
      - listener
    networks:
      - transport-network
    environment:
$DIALER_ENV
EOF

# Run the test (all output goes to log file only)
echo "  → Starting containers..." >> "$LOG_FILE"

# Start containers and wait for dialer to exit
if $DOCKER_COMPOSE_CMD -f "$COMPOSE_FILE" up --exit-code-from dialer --abort-on-container-exit >> "$LOG_FILE" 2>&1; then
    EXIT_CODE=0
else
    EXIT_CODE=1
fi

# Cleanup
echo "  → Cleaning up..." >> "$LOG_FILE"
$DOCKER_COMPOSE_CMD -f "$COMPOSE_FILE" down --volumes --remove-orphans >> "$LOG_FILE" 2>&1 || true

# Compose directory will be cleaned up by trap
exit $EXIT_CODE
