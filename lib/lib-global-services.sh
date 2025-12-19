#!/bin/bash
# Global service management functions for all test suites
# Provides Redis coordination service for tests

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

    # Source formatting library if not already loaded
    if ! type print_success_indented &>/dev/null; then
        local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        source "$script_dir/lib-output-formatting.sh"
    fi

    # Create network if doesn't exist
    if ! docker network inspect "$network_name" &>/dev/null; then
        docker network create "$network_name" > /dev/null
        print_success_indented "Created network: $network_name"
    else
        print_message_indented "Network already exists: $network_name"
    fi

    # Start Redis if not running
    if ! docker ps -q -f name="^${redis_name}$" | grep -q .; then
        echo -n "  → Starting Redis..."
        docker run -d \
            --name "$redis_name" \
            --network "$network_name" \
            --rm \
            redis:7-alpine \
            redis-server --save "" --appendonly no > /dev/null

        # Wait for Redis to be ready
        for i in {1..10}; do
            if docker exec "$redis_name" redis-cli ping &>/dev/null 2>&1; then
                echo "started"
                break
            fi
            echo -n "."
            sleep 1
        done
    else
        print_message_indented "Redis already running"
    fi

    print_success_indented "Global services ready"
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

    # Source formatting library if not already loaded
    if ! type print_success_indented &>/dev/null; then
        local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        source "$script_dir/lib-output-formatting.sh"
    fi

    # Stop Redis
    if docker ps -q -f name="^${redis_name}$" | grep -q .; then
        echo -n "  → Stopping Redis..."
        docker stop "$redis_name" &>/dev/null || true
        echo "stopped"
    else
        print_message_indented "Redis not running"
    fi

    # Remove network
    if docker network inspect "$network_name" &>/dev/null; then
        docker network rm "$network_name" &>/dev/null || true
        print_success_indented "Network removed: $network_name"
    else
        print_message_indented "Network not found"
    fi

    print_success_indented "Global services stopped"
}
