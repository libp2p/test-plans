#!/bin/bash
# Global service management functions for all test suites
# Provides Redis coordination service for tests

# Source formatting library if not already loaded
if ! type indent &>/dev/null; then
  _this_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  source "$_this_script_dir/lib-output-formatting.sh"
fi

# Start Redis service for test coordination
# Args:
#   $1: network_name - Docker network name (e.g., "perf-network", "hole-punch-network")
#   $2: redis_name - Redis container name (e.g., "perf-redis", "hole-punch-redis")
# Usage:
#   start_redis_service "perf-network" "perf-redis"
#   start_redis_service "hole-punch-network" "hole-punch-redis"
start_redis_service() {
  local network_name="$1"
  local redis_name="$2"

  # Create network if doesn't exist
  # For perf, create with subnet to support static IP assignment
  if ! docker network inspect "${network_name}" &>/dev/null; then
    if [ "${network_name}" == "perf-network" ]; then
      # Perf network needs subnet for static listener IP (10.5.0.10)
      docker network create "${network_name}" \
        --subnet 10.5.0.0/24 \
        --gateway 10.5.0.1 > /dev/null
    else
      # Other networks don't need specific subnet
      docker network create "${network_name}" > /dev/null
    fi
    print_success "Created network: ${network_name}"
  else
    print_message "Network already exists: ${network_name}"
  fi

  # Start Redis if not running
  indent
  if ! docker ps -q -f name="^${redis_name}$" | grep -q .; then
    echo_message "Starting Redis..."
    docker run -d \
      --name "${redis_name}" \
      --network "${network_name}" \
      --rm \
      redis:7-alpine \
      redis-server --save "" --appendonly no > /dev/null

    # Wait for Redis to be ready
    for i in {1..30}; do
      if docker exec "${redis_name}" redis-cli ping >/dev/null 2>&1; then
        echo_message "started\n"
        break
      fi
      echo_message "."
      sleep 1
    done

    if (( i == 30)); then
      unindent
      println
      print_error "ERROR: Redis failed to start after 30 seconds"
      exit 1
    fi
  else
    print_message "Redis already running"
  fi
  unindent
  println

  print_success "Global services ready"
}

# Stop Redis service
# Args:
#   $1: network_name - Docker network name
#   $2: redis_name - Redis container name
# Usage:
#   stop_redis_service "perf-network" "perf-redis"
#   stop_redis_service "hole-punch-network" "hole-punch-redis"
stop_redis_service() {
  local network_name="$1"
  local redis_name="$2"

  # Stop Redis
  indent
  if docker ps -q -f name="^${redis_name}$" | grep -q .; then
    echo_message "Stopping Redis..."
    docker stop "${redis_name}" >/dev/null || true
    print_message "stopped"
  else
    print_message "Redis not running"
  fi
  unindent

  # Remove network
  if docker network inspect "${network_name}" >/dev/null; then
    docker network rm "${network_name}" >/dev/null || true
    print_success "Network removed: ${network_name}"
  else
    print_message "Network not found"
  fi
  println

  print_success "Global services stopped"
}
