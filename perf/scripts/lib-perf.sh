#!/bin/bash
# Perf test helper functions
# Shared utilities for perf test scripts

# Get server configuration for an implementation
# Usage: get_server_config <impl_id>
# Returns: server_id
get_server_config() {
  local impl_id=$1
  yq eval ".implementations[] | select(.id == \"$impl_id\") | .server" impls.yaml
}

# Check if server is remote
# Usage: is_remote_server <server_id>
# Returns: 0 if remote, 1 if local
is_remote_server() {
  local server_id=$1
  local server_type=$(yq eval ".servers[] | select(.id == \"$server_id\") | .type" impls.yaml)
  [ "$server_type" = "remote" ]
}

# Get remote server hostname
# Usage: get_remote_hostname <server_id>
# Returns: hostname or IP address
get_remote_hostname() {
  local server_id=$1
  yq eval ".servers[] | select(.id == \"$server_id\") | .hostname" impls.yaml
}

# Get remote server username
# Usage: get_remote_username <server_id>
# Returns: SSH username
get_remote_username() {
  local server_id=$1
  yq eval ".servers[] | select(.id == \"$server_id\") | .username" impls.yaml
}

# Execute command on server (local or remote)
# Usage: exec_on_server <server_id> <command>
# Example: exec_on_server "remote-1" "docker ps"
exec_on_server() {
  local server_id=$1
  shift
  local cmd="$@"

  if is_remote_server "$server_id"; then
    local hostname=$(get_remote_hostname "$server_id")
    local username=$(get_remote_username "$server_id")
    ssh -o StrictHostKeyChecking=no "${username}@${hostname}" "$cmd"
  else
    # Local execution
    eval "$cmd"
  fi
}

# Copy file to server (local or remote)
# Usage: copy_to_server <server_id> <local_path> <remote_path>
copy_to_server() {
  local server_id=$1
  local local_path=$2
  local remote_path=$3

  if is_remote_server "$server_id"; then
    local hostname=$(get_remote_hostname "$server_id")
    local username=$(get_remote_username "$server_id")
    scp -o StrictHostKeyChecking=no "$local_path" "${username}@${hostname}:${remote_path}"
  else
    # Local copy
    cp "$local_path" "$remote_path"
  fi
}

# Get server address for client connection
# Usage: get_server_address <server_id>
# Returns: hostname or "localhost"
get_server_address() {
  local server_id=$1

  if is_remote_server "$server_id"; then
    get_remote_hostname "$server_id"
  else
    echo "localhost"
  fi
}

# Calculate throughput from bytes and time
# Usage: calculate_throughput <bytes> <seconds>
# Returns: throughput in Gbps (rounded to 2 decimals)
calculate_throughput() {
  local bytes=$1
  local seconds=$2

  # Use awk for floating point calculation (no bc dependency)
  echo "$bytes $seconds" | awk '{printf "%.2f", ($1 * 8) / $2 / 1000000000}'
}

# Parse perf client YAML output
# Usage: parse_perf_output <yaml_output> <field>
# field: "timeSeconds", "uploadBytes", "downloadBytes", etc.
# Returns: field value
parse_perf_output() {
  local yaml_output=$1
  local field=$2

  echo "$yaml_output" | yq eval ".$field" -
}

# Extract metric from perf result YAML
# Usage: extract_metric <yaml_result> <field>
# field: "timeSeconds", "uploadBytes", "downloadBytes"
extract_metric() {
  local yaml_result=$1
  local field=$2

  echo "$yaml_result" | yq eval ".$field // 0" -
}

# Get implementation metadata
# Usage: get_impl_metadata <impl_id> <field>
# field: "name", "language", "version", etc.
get_impl_metadata() {
  local impl_id=$1
  local field=$2

  yq eval ".implementations[] | select(.id == \"$impl_id\") | .$field" impls.yaml
}

# Get implementation capabilities
# Usage: get_impl_capabilities <impl_id>
# Returns: newline-separated list of capabilities
get_impl_capabilities() {
  local impl_id=$1
  yq eval ".implementations[] | select(.id == \"$impl_id\") | .capabilities[]" impls.yaml
}

# Check if implementation supports capability
# Usage: has_capability <impl_id> <capability>
# capability: "upload", "download", "latency"
# Returns: 0 if supported, 1 if not
has_capability() {
  local impl_id=$1
  local capability=$2

  local capabilities=$(get_impl_capabilities "$impl_id")
  echo "$capabilities" | grep -q "^${capability}$"
}

# Get implementation transports
# Usage: get_impl_transports <impl_id>
# Returns: newline-separated list of transports
get_impl_transports() {
  local impl_id=$1
  yq eval ".implementations[] | select(.id == \"$impl_id\") | .transports[]" impls.yaml
}

# Format duration in human-readable format
# Usage: format_duration <seconds>
# Returns: "HH:MM:SS" format
format_duration() {
  local total_seconds=$1
  local hours=$((total_seconds / 3600))
  local minutes=$(((total_seconds % 3600) / 60))
  local seconds=$((total_seconds % 60))

  printf "%02d:%02d:%02d" $hours $minutes $seconds
}

# Calculate statistics from array of values
# Usage: calculate_stats <value1> <value2> ... <valueN>
# Returns: YAML with min, max, avg, median
calculate_stats() {
  local values=("$@")
  local count=${#values[@]}

  if [ $count -eq 0 ]; then
    echo "min: 0"
    echo "max: 0"
    echo "avg: 0"
    echo "median: 0"
    echo "count: 0"
    return
  fi

  # Sort values
  local sorted=($(printf '%s\n' "${values[@]}" | sort -n))

  # Min and max
  local min=${sorted[0]}
  local max=${sorted[$((count-1))]}

  # Average using awk
  local sum=0
  for val in "${values[@]}"; do
    sum=$(echo "$sum $val" | awk '{print $1 + $2}')
  done
  local avg=$(echo "$sum $count" | awk '{printf "%.4f", $1 / $2}')

  # Median
  local median
  if [ $((count % 2)) -eq 0 ]; then
    local mid1=${sorted[$((count/2-1))]}
    local mid2=${sorted[$((count/2))]}
    median=$(echo "$mid1 $mid2" | awk '{printf "%.4f", ($1 + $2) / 2}')
  else
    median=${sorted[$((count/2))]}
  fi

  echo "min: $min"
  echo "max: $max"
  echo "avg: $avg"
  echo "median: $median"
  echo "count: $count"
}

# Log with timestamp
# Usage: log_info "message"
log_info() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $*" >&2
}

# Log error with timestamp
# Usage: log_error "message"
log_error() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

# Log debug (only if DEBUG=true)
# Usage: log_debug "message"
log_debug() {
  if [ "${DEBUG:-false}" = "true" ]; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] DEBUG: $*" >&2
  fi
}

# Check if Docker image exists
# Usage: docker_image_exists <image_name>
# Returns: 0 if exists, 1 if not
docker_image_exists() {
  local image_name=$1
  docker image inspect "$image_name" >/dev/null 2>&1
}

# Check if Docker container is running
# Usage: docker_container_running <container_name>
# Returns: 0 if running, 1 if not
docker_container_running() {
  local container_name=$1
  docker ps --filter "name=$container_name" --filter "status=running" --format "{{.Names}}" | grep -q "^${container_name}$"
}

# Wait for server to be ready
# Usage: wait_for_server <server_address> <port> [timeout_seconds]
# Returns: 0 if server ready, 1 if timeout
wait_for_server() {
  local server_address=$1
  local port=$2
  local timeout=${3:-30}
  local elapsed=0

  log_info "Waiting for server at ${server_address}:${port}..."

  while [ $elapsed -lt $timeout ]; do
    if timeout 1 bash -c "cat < /dev/null > /dev/tcp/${server_address}/${port}" 2>/dev/null; then
      log_info "Server ready!"
      return 0
    fi
    sleep 1
    ((elapsed++))
  done

  log_error "Timeout waiting for server at ${server_address}:${port}"
  return 1
}

# Clean up containers by pattern
# Usage: cleanup_containers <pattern>
# Example: cleanup_containers "perf-*"
cleanup_containers() {
  local pattern=$1

  log_debug "Cleaning up containers matching: $pattern"

  # Remove stopped containers
  docker ps -a --filter "name=$pattern" --format "{{.Names}}" | while read -r container; do
    log_debug "Removing container: $container"
    docker rm -f "$container" >/dev/null 2>&1 || true
  done
}

# Get all remote servers
# Usage: get_all_remote_servers
# Returns: newline-separated list of remote server IDs
get_all_remote_servers() {
  yq eval '.servers[] | select(.type == "remote") | .id' impls.yaml
}

# Verify remote server connectivity
# Usage: verify_remote_server <server_id>
# Returns: 0 if accessible, 1 if not
verify_remote_server() {
  local server_id=$1
  local hostname=$(get_remote_hostname "$server_id")
  local username=$(get_remote_username "$server_id")

  log_debug "Verifying connectivity to $server_id ($username@$hostname)"

  if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "${username}@${hostname}" "echo 'test'" >/dev/null 2>&1; then
    return 0
  else
    log_error "Cannot connect to $username@$hostname"
    return 1
  fi
}

# Functions are available through sourcing this file
# No need to export since scripts source this file directly
