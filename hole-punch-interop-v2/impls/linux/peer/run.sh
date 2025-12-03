#!/bin/bash
# Linux Peer Implementation - Combined Dialer and Listener
# Uses ROLE environment variable to determine behavior

set -euo pipefail

log() {
    echo "[PEER-${ROLE^^}] $(date -u +%Y-%m-%dT%H:%M:%S.%3NZ) $*" >&2
}

# Required environment variables
REDIS_ADDR="${REDIS_ADDR:-}"
TEST_KEY="${TEST_KEY:-}"
ROLE="${ROLE:-}"
TRANSPORT="${TRANSPORT:-tcp}"
TEST_TIMEOUT_SECONDS="${TEST_TIMEOUT_SECONDS:-30}"
DEBUG="${DEBUG:-false}"

# Optional IP addresses (for logging)
DIALER_IP="${DIALER_IP:-}"
LISTENER_IP="${LISTENER_IP:-}"

# Router LAN IP (for default route)
ROUTER_LAN_IP="${ROUTER_LAN_IP:-}"

# Validate ROLE
if [ -z "$ROLE" ]; then
    echo "ERROR: ROLE environment variable required (must be 'dial' or 'listen')"
    exit 1
fi

case "$ROLE" in
    "dial"|"listen")
        # Valid roles
        ;;
    *)
        echo "ERROR: Invalid ROLE: $ROLE (must be 'dial' or 'listen')"
        exit 1
        ;;
esac

log "========================================"
log "Linux Peer Starting"
log "========================================"

# Validate required variables
if [ -z "$REDIS_ADDR" ] || [ -z "$TEST_KEY" ]; then
    log "ERROR: Missing required environment variables"
    log "Required: REDIS_ADDR, TEST_KEY, ROLE"
    exit 1
fi

log "Configuration:"
log "  Redis:       $REDIS_ADDR"
log "  Test Key:    $TEST_KEY"
log "  Role:        $ROLE"
log "  Transport:   $TRANSPORT"
log "  Timeout:     ${TEST_TIMEOUT_SECONDS}s"
log "  Debug:       $DEBUG"
if [ "$ROLE" = "dial" ]; then
    log "  Dialer IP:   ${DIALER_IP:-<not set>}"
else
    log "  Listener IP: ${LISTENER_IP:-<not set>}"
fi
log ""

# Configure default route through router
if [ -n "$ROUTER_LAN_IP" ]; then
    log "Configuring network route..."
    log "  Router LAN IP: $ROUTER_LAN_IP"

    # Remove any existing default route
    ip route del default 2>/dev/null || true

    # Add new default route via router
    ip route add default via "$ROUTER_LAN_IP"

    log "  ✓ Default route configured"
    log ""

    # Display routing table for debugging
    if [ "$DEBUG" = "true" ]; then
        log "Current routing table:"
        ip route | while read line; do
            log "    $line"
        done
        log ""
    fi
else
    log "WARNING: ROUTER_LAN_IP not set, skipping route configuration"
    log ""
fi

# Parse Redis host and port
REDIS_HOST="${REDIS_ADDR%:*}"
REDIS_PORT="${REDIS_ADDR#*:}"

# Function: Wait for relay address
wait_for_relay() {
    local role_key="${ROLE}"  # "dial" or "listen"

    # Map role to Redis key suffix
    if [ "$role_key" = "listen" ]; then
        role_key="listener"
    elif [ "$role_key" = "dial" ]; then
        role_key="dialer"
    fi

    local redis_key="relay:${TEST_KEY}:${role_key}"

    log "Waiting for relay address in Redis..."
    log "  Key: $redis_key"

    local retry_count=0
    local max_retries=$TEST_TIMEOUT_SECONDS
    local relay_addr=""

    while [ $retry_count -lt $max_retries ]; do
        relay_addr=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" GET "$redis_key" 2>/dev/null || echo "")

        if [ -n "$relay_addr" ] && [ "$relay_addr" != "(nil)" ]; then
            log "  ✓ Found relay address: $relay_addr"
            echo "$relay_addr"
            return 0
        fi

        [ "$DEBUG" = "true" ] && log "  Retry $((retry_count+1))/$max_retries..."
        sleep 1
        retry_count=$((retry_count + 1))
    done

    log "ERROR: Timeout waiting for relay address"
    return 1
}

# Listener Logic
run_listener() {
    log "Running as LISTENER"

    # Wait for relay address
    RELAY_ADDR=$(wait_for_relay)
    if [ $? -ne 0 ]; then
        exit 1
    fi

    # Parse relay address
    RELAY_IP="${RELAY_ADDR%:*}"
    RELAY_PORT="${RELAY_ADDR#*:}"

    log ""
    log "Connecting to relay..."
    log "  Relay IP:   $RELAY_IP"
    log "  Relay Port: $RELAY_PORT"
    log ""

    # Track timing
    START_TIME=$(date +%s%3N)

    log "Waiting for PING from dialer..."
    log "Connecting to relay at $RELAY_IP:$RELAY_PORT"

    # Use nc with bash coprocess for bidirectional communication
    coproc NC { nc "$RELAY_IP" "$RELAY_PORT"; }
    nc_in=${NC[1]}
    nc_out=${NC[0]}

    log "Connected to relay (nc PID: $NC_PID, FDs: in=$nc_in, out=$nc_out)"

    # Wait for PING from dialer (via relay)
    log "Reading from connection..."
    if read -r -t $TEST_TIMEOUT_SECONDS line <&$nc_out; then
        RECV_TIME=$(date +%s%3N)
        log "  ✓ Received: $line"

        # Verify it's a PING
        if [[ "$line" =~ ^PING ]]; then
            # Send PONG response
            log "  → Sending PONG..."
            echo "PONG" >&$nc_in
            log "  ✓ Sent: PONG to FD $nc_in"

            # Give time for PONG to be sent
            sleep 0.5

            END_TIME=$(date +%s%3N)
            DURATION=$((END_TIME - START_TIME))

            log ""
            log "========================================"
            log "Test Completed Successfully"
            log "========================================"
            log "Duration: ${DURATION}ms"
            log ""

            # Close coprocess
            eval "exec ${nc_in}>&-"
            eval "exec ${nc_out}<&-"
            wait $NC_PID 2>/dev/null || true

            exit 0
        else
            log "ERROR: Expected PING, received: $line"
            eval "exec ${nc_in}>&-"
            eval "exec ${nc_out}<&-"
            exit 1
        fi
    else
        log "ERROR: Timeout waiting for PING from dialer"
        eval "exec ${nc_in}>&-"
        eval "exec ${nc_out}<&-"
        exit 1
    fi
}

# Dialer Logic
run_dialer() {
    log "Running as DIALER"

    # Wait for relay address
    RELAY_ADDR=$(wait_for_relay)
    if [ $? -ne 0 ]; then
        exit 1
    fi

    # Parse relay address
    RELAY_IP="${RELAY_ADDR%:*}"
    RELAY_PORT="${RELAY_ADDR#*:}"

    log ""
    log "Connecting to relay..."
    log "  Relay IP:   $RELAY_IP"
    log "  Relay Port: $RELAY_PORT"
    log ""

    # Track timing
    START_TIME=$(date +%s%3N)

    log "Connecting to relay at $RELAY_IP:$RELAY_PORT"

    # Use nc with bash coprocess for bidirectional communication
    coproc NC { nc "$RELAY_IP" "$RELAY_PORT"; }
    nc_in=${NC[1]}
    nc_out=${NC[0]}

    log "Connected to relay (nc PID: $NC_PID, FDs: in=$nc_in, out=$nc_out)"

    # Send PING
    PING_START=$(date +%s%3N)
    echo "PING" >&$nc_in
    log "  ✓ Sent: PING to FD $nc_in"

    # Wait for PONG response from listener (via relay)
    log "Waiting for PONG from listener..."
    if read -r -t $TEST_TIMEOUT_SECONDS line <&$nc_out; then
        PING_END=$(date +%s%3N)
        log "  ✓ Received: $line"

        # Verify it's a PONG
        if [[ "$line" =~ ^PONG ]]; then
            END_TIME=$(date +%s%3N)

            # Calculate metrics
            TOTAL_DURATION=$((END_TIME - START_TIME))
            PING_RTT=$((PING_END - PING_START))

            log ""
            log "========================================"
            log "Test Completed Successfully"
            log "========================================"
            log "Total duration:  ${TOTAL_DURATION}ms"
            log "Ping RTT:        ${PING_RTT}ms"
            log ""

            # Output JSON metrics for test framework compatibility
            echo "{\"handshakePlusOneRTTMillis\":${TOTAL_DURATION},\"pingRTTMilllis\":${PING_RTT}}"

            # Close coprocess
            eval "exec ${nc_in}>&-"
            eval "exec ${nc_out}<&-"
            wait $NC_PID 2>/dev/null || true

            exit 0
        else
            log "ERROR: Expected PONG, received: $line"
            eval "exec ${nc_in}>&-"
            eval "exec ${nc_out}<&-"
            exit 1
        fi
    else
        log "ERROR: Timeout waiting for PONG from listener"
        eval "exec ${nc_in}>&-"
        eval "exec ${nc_out}<&-"
        exit 1
    fi
}

# Execute based on ROLE
case "$ROLE" in
    "listen")
        run_listener
        ;;
    "dial")
        run_dialer
        ;;
esac
