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

# Parse Redis host and port
REDIS_HOST="${REDIS_ADDR%:*}"
REDIS_PORT="${REDIS_ADDR#*:}"

# Function: Wait for relay address
wait_for_relay() {
    log "Waiting for relay address in Redis..."
    log "  Key: relay:${TEST_KEY}"

    local retry_count=0
    local max_retries=$TEST_TIMEOUT_SECONDS
    local relay_addr=""

    while [ $retry_count -lt $max_retries ]; do
        relay_addr=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" GET "relay:${TEST_KEY}" 2>/dev/null || echo "")

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

    tail -f /dev/null
#    # Parse relay address
#    RELAY_IP="${RELAY_ADDR%:*}"
#    RELAY_PORT="${RELAY_ADDR#*:}"
#
#    log ""
#    log "Connecting to relay..."
#    log "  Relay IP:   $RELAY_IP"
#    log "  Relay Port: $RELAY_PORT"
#
#    # Track timing
#    START_TIME=$(date +%s%3N)
#
#    # Connect to relay and handle communication
#    {
#        # Send identification
#        echo "LISTENER"
#        log "  ✓ Sent identification"
#
#        # Wait for data from dialer (via relay)
#        log "Waiting for test data from dialer..."
#
#        if read -r -t $TEST_TIMEOUT_SECONDS line; then
#            RECV_TIME=$(date +%s%3N)
#            log "  ✓ Received: $line"
#
#            # Verify format
#            if [[ "$line" =~ ^PING: ]]; then
#                # Send response
#                RESPONSE="PONG:$(date +%s%3N)"
#                echo "$RESPONSE"
#                log "  ✓ Sent response: $RESPONSE"
#
#                END_TIME=$(date +%s%3N)
#                DURATION=$((END_TIME - START_TIME))
#
#                log ""
#                log "========================================"
#                log "Test Completed Successfully"
#                log "========================================"
#                log "Duration: ${DURATION}ms"
#
#                exit 0
#            else
#                log "ERROR: Invalid data format: $line"
#                exit 1
#            fi
#        else
#            log "ERROR: Timeout waiting for data from dialer"
#            exit 1
#        fi
#    } | nc -w $TEST_TIMEOUT_SECONDS "$RELAY_IP" "$RELAY_PORT"
#
#    EXIT_CODE=${PIPESTATUS[0]}
#
#    if [ $EXIT_CODE -eq 0 ]; then
#        log "Connection completed successfully"
#    else
#        log "Connection failed with exit code: $EXIT_CODE"
#    fi
#
#    exit $EXIT_CODE
}

# Dialer Logic
run_dialer() {
    log "Running as DIALER"

    # Wait a bit for listener to connect first
    #log "Waiting for listener to connect to relay..."
    #sleep 2

    # Wait for relay address
    RELAY_ADDR=$(wait_for_relay)
    if [ $? -ne 0 ]; then
        exit 1
    fi

    tail -f /dev/null

#    # Parse relay address
#    RELAY_IP="${RELAY_ADDR%:*}"
#    RELAY_PORT="${RELAY_ADDR#*:}"
#
#    log ""
#    log "Connecting to relay..."
#    log "  Relay IP:   $RELAY_IP"
#    log "  Relay Port: $RELAY_PORT"
#
#    # Track timing
#    START_TIME=$(date +%s%3N)
#    PING_START=0
#    PING_END=0
#
#    # Connect to relay and send test data
#    {
#        # Send identification
#        echo "DIALER"
#        log "  ✓ Sent identification"
#
#        # Send test data
#        PING_START=$(date +%s%3N)
#        TEST_DATA="PING:${PING_START}"
#        echo "$TEST_DATA"
#        log "  ✓ Sent test data: $TEST_DATA"
#
#        # Wait for response from listener (via relay)
#        log "Waiting for response from listener..."
#
#        if read -r -t $TEST_TIMEOUT_SECONDS line; then
#            PING_END=$(date +%s%3N)
#            log "  ✓ Received response: $line"
#
#            # Verify format
#            if [[ "$line" =~ ^PONG: ]]; then
#                END_TIME=$(date +%s%3N)
#
#                # Calculate metrics
#                TOTAL_DURATION=$((END_TIME - START_TIME))
#                PING_RTT=$((PING_END - PING_START))
#
#                log ""
#                log "========================================"
#                log "Test Completed Successfully"
#                log "========================================"
#                log "Total duration:  ${TOTAL_DURATION}ms"
#                log "Ping RTT:        ${PING_RTT}ms"
#                log ""
#
#                # Output JSON metrics for test framework compatibility
#                echo "{\"handshakePlusOneRTTMillis\":${TOTAL_DURATION},\"pingRTTMilllis\":${PING_RTT}}"
#
#                exit 0
#            else
#                log "ERROR: Invalid response format: $line"
#                exit 1
#            fi
#        else
#            log "ERROR: Timeout waiting for response from listener"
#            exit 1
#        fi
#    } | nc -w $TEST_TIMEOUT_SECONDS "$RELAY_IP" "$RELAY_PORT"
#
#    EXIT_CODE=${PIPESTATUS[0]}
#
#    if [ $EXIT_CODE -ne 0 ]; then
#        log "Connection failed with exit code: $EXIT_CODE"
#        exit $EXIT_CODE
#    fi
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
