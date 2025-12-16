#!/bin/bash
# iperf3 baseline performance test implementation
# Uses iperf3 for raw TCP throughput and latency measurements
# Follows WRITE_A_PERF_TEST.md guidelines

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

# Read configuration from environment variables
IS_DIALER="${IS_DIALER:-false}"
REDIS_ADDR="${REDIS_ADDR:-redis:6379}"
TRANSPORT="${TRANSPORT:-tcp}"
LISTENER_IP="${LISTENER_IP:-10.5.0.10}"

# Dialer-only parameters
UPLOAD_BYTES="${UPLOAD_BYTES:-1073741824}"
DOWNLOAD_BYTES="${DOWNLOAD_BYTES:-1073741824}"
UPLOAD_ITERATIONS="${UPLOAD_ITERATIONS:-10}"
DOWNLOAD_ITERATIONS="${DOWNLOAD_ITERATIONS:-10}"
LATENCY_ITERATIONS="${LATENCY_ITERATIONS:-100}"

IPERF_PORT=5201

# Logging to stderr
log() {
    echo "$@" >&2
}

# ============================================================================
# LISTENER IMPLEMENTATION
# ============================================================================

run_listener() {
    log "Starting iperf listener..."

    # Construct multiaddr
    MULTIADDR="/ip4/${LISTENER_IP}/tcp/${IPERF_PORT}"
    log "Will listen on: $MULTIADDR"

    # Publish to Redis
    REDIS_HOST="${REDIS_ADDR%:*}"
    REDIS_PORT="${REDIS_ADDR#*:}"

    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" SET listener_multiaddr "$MULTIADDR" >/dev/null
    log "Published multiaddr to Redis"

    # Run iperf3 server in loop (accept multiple connections)
    log "Listener ready, waiting for connections..."

    while true; do
        iperf3 -s -p $IPERF_PORT --one-off 2>&1 | while read -r line; do
            log "  $line"
        done
    done
}

# ============================================================================
# DIALER IMPLEMENTATION
# ============================================================================

run_dialer() {
    log "Starting iperf dialer..."

    # Wait for listener multiaddr from Redis
    LISTENER_ADDR=$(wait_for_listener)
    log "Got listener multiaddr: $LISTENER_ADDR"

    # Extract IP and port from multiaddr (/ip4/10.5.0.10/tcp/5201)
    SERVER_IP=$(echo "$LISTENER_ADDR" | cut -d'/' -f3)
    SERVER_PORT=$(echo "$LISTENER_ADDR" | cut -d'/' -f5)

    log "Server: $SERVER_IP:$SERVER_PORT"

    # Give listener a moment to be ready
    sleep 2

    # Run three measurements
    log "Running upload test ($UPLOAD_ITERATIONS iterations)..."
    upload_stats=$(run_measurement "$SERVER_IP" "$SERVER_PORT" "$UPLOAD_BYTES" "0" "$UPLOAD_ITERATIONS")

    log "Running download test ($DOWNLOAD_ITERATIONS iterations)..."
    download_stats=$(run_measurement "$SERVER_IP" "$SERVER_PORT" "0" "$DOWNLOAD_BYTES" "$DOWNLOAD_ITERATIONS")

    log "Running latency test ($LATENCY_ITERATIONS iterations)..."
    latency_stats=$(run_latency_measurement "$SERVER_IP" "$SERVER_PORT" "$LATENCY_ITERATIONS")

    log "All measurements complete!"

    # Output YAML results to stdout
    output_yaml "$upload_stats" "$download_stats" "$latency_stats"
}

# Wait for listener multiaddr from Redis (with retries)
wait_for_listener() {
    log "Waiting for listener multiaddr..."

    REDIS_HOST="${REDIS_ADDR%:*}"
    REDIS_PORT="${REDIS_ADDR#*:}"

    for i in {1..30}; do
        ADDR=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" GET listener_multiaddr 2>/dev/null || echo "")

        if [ -n "$ADDR" ] && [ "$ADDR" != "(nil)" ]; then
            echo "$ADDR"
            return 0
        fi

        sleep 0.5
    done

    log "Error: Timeout waiting for listener multiaddr"
    exit 1
}

# ============================================================================
# MEASUREMENT FUNCTIONS
# ============================================================================

run_measurement() {
    local server_ip=$1
    local server_port=$2
    local send_bytes=$3
    local recv_bytes=$4
    local iterations=$5

    local values=()

    for i in $(seq 1 $iterations); do
        local result=""

        if [ "$send_bytes" -gt 100 ]; then
            # Upload test
            result=$(iperf3 -c "$server_ip" -p "$server_port" -n "$send_bytes" -J 2>/dev/null || echo "")
        elif [ "$recv_bytes" -gt 100 ]; then
            # Download test (reverse mode)
            result=$(iperf3 -c "$server_ip" -p "$server_port" -n "$recv_bytes" -R -J 2>/dev/null || echo "")
        fi

        if [ -z "$result" ]; then
            log "  Iteration $i/$iterations failed"
            continue
        fi

        # Extract bits_per_second from JSON and convert to Gbps
        local bps=$(echo "$result" | jq -r '.end.sum_sent.bits_per_second // .end.sum_received.bits_per_second // 0' 2>/dev/null)
        local gbps=$(echo "scale=6; $bps / 1000000000" | bc)

        values+=("$gbps")
        log "  Iteration $i/$iterations: $gbps Gbps"
    done

    # Calculate and return statistics
    calculate_stats "${values[@]}"
}

run_latency_measurement() {
    local server_ip=$1
    local server_port=$2
    local iterations=$3

    local values=()

    log "  Using ping for latency measurement (true RTT)"

    for i in $(seq 1 $iterations); do
        # Use ping for true round-trip latency (no connection setup overhead)
        # -c 1 = 1 ping, -W 1 = 1 second timeout
        local result=$(ping -c 1 -W 1 "$server_ip" 2>/dev/null || echo "")

        if [ -z "$result" ]; then
            log "  Iteration $i/$iterations failed"
            continue
        fi

        # Extract RTT from ping output (format: "time=0.123 ms")
        local latency_ms=$(echo "$result" | grep "time=" | sed 's/.*time=\([0-9.]*\).*/\1/')

        if [ -n "$latency_ms" ]; then
            values+=("$latency_ms")
        fi
    done

    log "  Completed ${#values[@]} latency measurements"

    # Calculate and return statistics
    calculate_stats "${values[@]}"
}

# ============================================================================
# STATISTICS FUNCTIONS
# ============================================================================

calculate_stats() {
    local values=("$@")
    local count=${#values[@]}

    if [ $count -eq 0 ]; then
        echo '{"min":0,"q1":0,"median":0,"q3":0,"max":0,"outliers":[],"samples":[]}'
        return
    fi

    # Sort values numerically
    IFS=$'\n' sorted=($(printf '%s\n' "${values[@]}" | sort -n))
    unset IFS

    # Calculate percentile indices
    local q1_idx=$(echo "($count - 1) * 0.25" | bc -l)
    local med_idx=$(echo "($count - 1) * 0.50" | bc -l)
    local q3_idx=$(echo "($count - 1) * 0.75" | bc -l)

    # Calculate percentiles
    local q1=$(percentile_value "${sorted[@]}" "$q1_idx")
    local median=$(percentile_value "${sorted[@]}" "$med_idx")
    local q3=$(percentile_value "${sorted[@]}" "$q3_idx")

    # Calculate IQR and identify outliers
    local iqr=$(echo "$q3 - $q1" | bc -l)
    local lower_fence=$(echo "$q1 - 1.5 * $iqr" | bc -l)
    local upper_fence=$(echo "$q3 + 1.5 * $iqr" | bc -l)

    # Separate outliers from non-outliers
    local outliers=()
    local non_outliers=()
    for val in "${sorted[@]}"; do
        local is_outlier=0
        if (( $(echo "$val < $lower_fence" | bc -l) )); then
            is_outlier=1
        elif (( $(echo "$val > $upper_fence" | bc -l) )); then
            is_outlier=1
        fi

        if [ $is_outlier -eq 1 ]; then
            outliers+=("$val")
        else
            non_outliers+=("$val")
        fi
    done

    # Calculate min/max from non-outliers (if any exist)
    local min max
    if [ ${#non_outliers[@]} -gt 0 ]; then
        min=${non_outliers[0]}
        max=${non_outliers[$((${#non_outliers[@]}-1))]}
    else
        # Fallback if all values are outliers
        min=${sorted[0]}
        max=${sorted[$((count-1))]}
    fi

    # Build outliers array string
    local outliers_str=""
    if [ ${#outliers[@]} -gt 0 ]; then
        outliers_str=$(IFS=,; echo "${outliers[*]}")
    fi

    # Build samples array string (all values)
    local samples_str=$(IFS=,; echo "${sorted[*]}")

    # Return as JSON
    echo "{\"min\":$min,\"q1\":$q1,\"median\":$median,\"q3\":$q3,\"max\":$max,\"outliers\":[$outliers_str],\"samples\":[$samples_str]}"
}

percentile_value() {
    local values=("${@:1:$#-1}")
    local index_str="${!#}"

    local lower=$(echo "$index_str / 1" | bc)
    local upper=$((lower + 1))

    # Boundary check
    if [ "$upper" -ge "${#values[@]}" ]; then
        echo "${values[$lower]}"
        return
    fi

    # Linear interpolation
    local weight=$(echo "$index_str - $lower" | bc -l)

    if (( $(echo "$weight == 0" | bc -l) )); then
        echo "${values[$lower]}"
    else
        local result=$(echo "${values[$lower]} * (1 - $weight) + ${values[$upper]} * $weight" | bc -l)
        echo "$result"
    fi
}

# ============================================================================
# OUTPUT FUNCTIONS
# ============================================================================

output_yaml() {
    local upload_stats=$1
    local download_stats=$2
    local latency_stats=$3

    # Parse upload stats
    local upload_min=$(echo "$upload_stats" | jq -r '.min')
    local upload_q1=$(echo "$upload_stats" | jq -r '.q1')
    local upload_median=$(echo "$upload_stats" | jq -r '.median')
    local upload_q3=$(echo "$upload_stats" | jq -r '.q3')
    local upload_max=$(echo "$upload_stats" | jq -r '.max')
    local upload_outliers=$(echo "$upload_stats" | jq -r '.outliers | join(", ")')
    local upload_samples=$(echo "$upload_stats" | jq -r '.samples | join(", ")')

    # Parse download stats
    local download_min=$(echo "$download_stats" | jq -r '.min')
    local download_q1=$(echo "$download_stats" | jq -r '.q1')
    local download_median=$(echo "$download_stats" | jq -r '.median')
    local download_q3=$(echo "$download_stats" | jq -r '.q3')
    local download_max=$(echo "$download_stats" | jq -r '.max')
    local download_outliers=$(echo "$download_stats" | jq -r '.outliers | join(", ")')
    local download_samples=$(echo "$download_stats" | jq -r '.samples | join(", ")')

    # Parse latency stats
    local latency_min=$(echo "$latency_stats" | jq -r '.min')
    local latency_q1=$(echo "$latency_stats" | jq -r '.q1')
    local latency_median=$(echo "$latency_stats" | jq -r '.median')
    local latency_q3=$(echo "$latency_stats" | jq -r '.q3')
    local latency_max=$(echo "$latency_stats" | jq -r '.max')
    local latency_outliers=$(echo "$latency_stats" | jq -r '.outliers | join(", ")')
    local latency_samples=$(echo "$latency_stats" | jq -r '.samples | join(", ")')

    # Output YAML to stdout
    cat <<EOF
# Upload measurement
upload:
  iterations: $UPLOAD_ITERATIONS
  min: $(printf "%.2f" "$upload_min")
  q1: $(printf "%.2f" "$upload_q1")
  median: $(printf "%.2f" "$upload_median")
  q3: $(printf "%.2f" "$upload_q3")
  max: $(printf "%.2f" "$upload_max")
  outliers: [$upload_outliers]
  samples: [$upload_samples]
  unit: Gbps

# Download measurement
download:
  iterations: $DOWNLOAD_ITERATIONS
  min: $(printf "%.2f" "$download_min")
  q1: $(printf "%.2f" "$download_q1")
  median: $(printf "%.2f" "$download_median")
  q3: $(printf "%.2f" "$download_q3")
  max: $(printf "%.2f" "$download_max")
  outliers: [$download_outliers]
  samples: [$download_samples]
  unit: Gbps

# Latency measurement
latency:
  iterations: $LATENCY_ITERATIONS
  min: $(printf "%.3f" "$latency_min")
  q1: $(printf "%.3f" "$latency_q1")
  median: $(printf "%.3f" "$latency_median")
  q3: $(printf "%.3f" "$latency_q3")
  max: $(printf "%.3f" "$latency_max")
  outliers: [$latency_outliers]
  samples: [$latency_samples]
  unit: ms
EOF
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

log "Configuration:"
log "  IS_DIALER: $IS_DIALER"
log "  REDIS_ADDR: $REDIS_ADDR"
log "  LISTENER_IP: $LISTENER_IP"

# Route to listener or dialer
if [ "$IS_DIALER" = "true" ]; then
    run_dialer
else
    run_listener
fi
