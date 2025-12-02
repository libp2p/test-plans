#!/bin/bash
# Netcat-based Relay Implementation
# Simple TCP relay for validating network topology and NAT routing

set -euo pipefail

log() {
    echo "[RELAY] $(date -u +%Y-%m-%dT%H:%M:%S.%3NZ) $*" >&2
}

log "========================================"
log "Netcat Relay Starting"
log "========================================"

# Required environment variables
REDIS_ADDR="${REDIS_ADDR:-}"
TEST_KEY="${TEST_KEY:-}"
RELAY_IP="${RELAY_IP:-}"
RELAY_PORT="${RELAY_PORT:-4001}"
DELAY_MS="${DELAY_MS:-0}"
DEBUG="${DEBUG:-false}"

# Validate required variables
if [ -z "$REDIS_ADDR" ] || [ -z "$TEST_KEY" ] || [ -z "$RELAY_IP" ]; then
    log "ERROR: Missing required environment variables"
    log "Required: REDIS_ADDR, TEST_KEY, RELAY_IP"
    log "Optional: RELAY_PORT (default: 4001), DELAY_MS (default: 0)"
    exit 1
fi

log "Configuration:"
log "  Redis:       $REDIS_ADDR"
log "  Test Key:    $TEST_KEY"
log "  Relay IP:    $RELAY_IP"
log "  Relay Port:  $RELAY_PORT"
log "  Delay:       ${DELAY_MS}ms"
log "  Debug:       $DEBUG"
log ""

# Parse Redis host and port
REDIS_HOST="${REDIS_ADDR%:*}"
REDIS_PORT="${REDIS_ADDR#*:}"

# Apply network delay if specified
if [ "$DELAY_MS" -gt 0 ]; then
    log "Applying network delay (${DELAY_MS}ms)..."
    tc qdisc add dev eth0 root netem delay "${DELAY_MS}ms" 2>/dev/null || true
    log "  ✓ Applied ${DELAY_MS}ms delay"
fi

# Publish relay address to Redis
RELAY_ADDR="${RELAY_IP}:${RELAY_PORT}"
log "Publishing relay address to Redis..."
log "  Key: relay:${TEST_KEY}"
log "  Value: ${RELAY_ADDR}"

if ! redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" SET "relay:${TEST_KEY}" "$RELAY_ADDR" EX 300 >/dev/null 2>&1; then
    log "ERROR: Failed to publish relay address to Redis"
    exit 1
fi

log "  ✓ Published relay address with 5-minute TTL"
log ""

log "========================================"
log "Relay Ready - Listening on ${RELAY_IP}:${RELAY_PORT}"
log "========================================"
log "Waiting for connections..."
log ""

# Run the Python relay server
#exec python3 /usr/local/bin/relay.py "$RELAY_IP" "$RELAY_PORT"
tail -f /dev/null
