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

# Use separate ports for listener and dialer
LISTENER_PORT="$RELAY_PORT"
DIALER_PORT=$((RELAY_PORT + 1))

# Validate required variables
if [ -z "$REDIS_ADDR" ] || [ -z "$TEST_KEY" ] || [ -z "$RELAY_IP" ]; then
    log "ERROR: Missing required environment variables"
    log "Required: REDIS_ADDR, TEST_KEY, RELAY_IP"
    log "Optional: RELAY_PORT (default: 4001), DELAY_MS (default: 0)"
    exit 1
fi

log "Configuration:"
log "  Redis:          $REDIS_ADDR"
log "  Test Key:       $TEST_KEY"
log "  Relay IP:       $RELAY_IP"
log "  Listener Port:  $LISTENER_PORT"
log "  Dialer Port:    $DIALER_PORT"
log "  Delay:          ${DELAY_MS}ms"
log "  Debug:          $DEBUG"
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

# Publish relay addresses to Redis
LISTENER_ADDR="${RELAY_IP}:${LISTENER_PORT}"
DIALER_ADDR="${RELAY_IP}:${DIALER_PORT}"

log "Publishing relay addresses to Redis..."
log "  Listener key: relay:${TEST_KEY}:listener"
log "  Listener value: ${LISTENER_ADDR}"
log "  Dialer key: relay:${TEST_KEY}:dialer"
log "  Dialer value: ${DIALER_ADDR}"

if ! redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" SET "relay:${TEST_KEY}:listener" "$LISTENER_ADDR" EX 300 >/dev/null 2>&1; then
    log "ERROR: Failed to publish listener address to Redis"
    exit 1
fi

if ! redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" SET "relay:${TEST_KEY}:dialer" "$DIALER_ADDR" EX 300 >/dev/null 2>&1; then
    log "ERROR: Failed to publish dialer address to Redis"
    exit 1
fi

log "  ✓ Published relay addresses with 5-minute TTL"
log ""

log "========================================"
log "Relay Ready"
log "========================================"
log "  Listener port: ${LISTENER_PORT}"
log "  Dialer port:   ${DIALER_PORT}"
log "Waiting for connections..."
log ""

# Clean up FIFOs on exit
cleanup() {
    log "Cleaning up..."
    rm -f /tmp/listener_in /tmp/listener_out /tmp/dialer_in /tmp/dialer_out
    kill 0 2>/dev/null || true
}
trap cleanup EXIT

# Create named pipes for each client
mkfifo /tmp/listener_in /tmp/listener_out
mkfifo /tmp/dialer_in /tmp/dialer_out

log "Created FIFOs for bidirectional relay"
log ""

#Start relay processes FIRST using cat with logging wrapper
log "Starting relay processes..."

# Relay dialer -> listener
( cat /tmp/dialer_out | while IFS= read -r line; do
    log "Relaying: dialer -> listener: $line"
    echo "$line"
done > /tmp/listener_in ) &
relay1_pid=$!

# Relay listener -> dialer
( cat /tmp/listener_out | while IFS= read -r line; do
    log "Relaying: listener -> dialer: $line"
    echo "$line"
done > /tmp/dialer_in ) &
relay2_pid=$!

log "Relay processes started (PIDs: $relay1_pid, $relay2_pid)"
log ""

# Small delay to let relay processes start
sleep 0.1

# Now start nc listeners
log "Starting nc listener on port ${LISTENER_PORT}..."
nc -l -s "$RELAY_IP" -p "$LISTENER_PORT" < /tmp/listener_in > /tmp/listener_out &
listener_pid=$!
log "  ✓ Listener nc started (PID: $listener_pid)"

log "Starting nc listener on port ${DIALER_PORT}..."
nc -l -s "$RELAY_IP" -p "$DIALER_PORT" < /tmp/dialer_in > /tmp/dialer_out &
dialer_pid=$!
log "  ✓ Dialer nc started (PID: $dialer_pid)"

log ""
log "Relay active - waiting for connections..."
log ""

# Wait for connections to complete
wait $listener_pid $dialer_pid
exit_code=$?

log ""
log "========================================"
log "Relay completed"
log "========================================"
log "Exit code: $exit_code"

exit $exit_code
