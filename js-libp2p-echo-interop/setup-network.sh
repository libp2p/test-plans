#!/usr/bin/env bash

# Setup Docker network and Redis coordination for JS-libp2p Echo interoperability tests

set -euo pipefail

NETWORK_NAME="js-libp2p-echo-interop"
REDIS_CONTAINER_NAME="js-libp2p-echo-interop-redis"

# Function to check if Docker network exists
network_exists() {
    docker network ls --format "{{.Name}}" | grep -q "^${NETWORK_NAME}$"
}

# Function to check if Redis container is running
redis_running() {
    docker ps --format "{{.Names}}" | grep -q "^${REDIS_CONTAINER_NAME}$"
}

# Function to create Docker network
create_network() {
    if network_exists; then
        echo "Docker network '$NETWORK_NAME' already exists"
    else
        echo "Creating Docker network '$NETWORK_NAME'..."
        docker network create \
            --driver bridge \
            --attachable \
            "$NETWORK_NAME"
        echo "✓ Docker network '$NETWORK_NAME' created"
    fi
}

# Function to start Redis container
start_redis() {
    if redis_running; then
        echo "Redis container '$REDIS_CONTAINER_NAME' is already running"
    else
        echo "Starting Redis container '$REDIS_CONTAINER_NAME'..."
        
        # Remove existing stopped container if it exists
        if docker ps -a --format "{{.Names}}" | grep -q "^${REDIS_CONTAINER_NAME}$"; then
            docker rm -f "$REDIS_CONTAINER_NAME" >/dev/null 2>&1 || true
        fi
        
        # Start Redis container
        docker run -d \
            --name "$REDIS_CONTAINER_NAME" \
            --network "$NETWORK_NAME" \
            --restart unless-stopped \
            --health-cmd "redis-cli ping" \
            --health-interval 5s \
            --health-timeout 3s \
            --health-retries 5 \
            redis:7-alpine \
            redis-server --appendonly no
        
        echo "✓ Redis container '$REDIS_CONTAINER_NAME' started"
        
        # Wait for Redis to be healthy
        echo "Waiting for Redis to be ready..."
        timeout=30
        while [ $timeout -gt 0 ]; do
            if docker exec "$REDIS_CONTAINER_NAME" redis-cli ping >/dev/null 2>&1; then
                echo "✓ Redis is ready"
                break
            fi
            sleep 1
            timeout=$((timeout - 1))
        done
        
        if [ $timeout -eq 0 ]; then
            echo "❌ Redis failed to start within 30 seconds"
            exit 1
        fi
    fi
}

# Function to stop Redis container
stop_redis() {
    if redis_running; then
        echo "Stopping Redis container '$REDIS_CONTAINER_NAME'..."
        docker stop "$REDIS_CONTAINER_NAME" >/dev/null
        docker rm "$REDIS_CONTAINER_NAME" >/dev/null
        echo "✓ Redis container stopped and removed"
    else
        echo "Redis container '$REDIS_CONTAINER_NAME' is not running"
    fi
}

# Function to remove Docker network
remove_network() {
    if network_exists; then
        echo "Removing Docker network '$NETWORK_NAME'..."
        docker network rm "$NETWORK_NAME" >/dev/null
        echo "✓ Docker network '$NETWORK_NAME' removed"
    else
        echo "Docker network '$NETWORK_NAME' does not exist"
    fi
}

# Function to show status
show_status() {
    echo "=== Docker Network and Redis Status ==="
    echo ""
    
    if network_exists; then
        echo "✓ Docker network '$NETWORK_NAME' exists"
        
        # Show network details
        echo "Network details:"
        docker network inspect "$NETWORK_NAME" --format "  Subnet: {{range .IPAM.Config}}{{.Subnet}}{{end}}"
        docker network inspect "$NETWORK_NAME" --format "  Gateway: {{range .IPAM.Config}}{{.Gateway}}{{end}}"
        
        # Show connected containers
        connected_containers=$(docker network inspect "$NETWORK_NAME" --format "{{range $k, $v := .Containers}}{{$v.Name}} {{end}}")
        if [[ -n "$connected_containers" ]]; then
            echo "  Connected containers: $connected_containers"
        else
            echo "  Connected containers: none"
        fi
    else
        echo "❌ Docker network '$NETWORK_NAME' does not exist"
    fi
    
    echo ""
    
    if redis_running; then
        echo "✓ Redis container '$REDIS_CONTAINER_NAME' is running"
        
        # Show Redis status
        redis_status=$(docker exec "$REDIS_CONTAINER_NAME" redis-cli ping 2>/dev/null || echo "UNAVAILABLE")
        echo "  Redis status: $redis_status"
        
        # Show Redis info
        redis_version=$(docker exec "$REDIS_CONTAINER_NAME" redis-cli info server | grep "redis_version" | cut -d: -f2 | tr -d '\r' || echo "unknown")
        echo "  Redis version: $redis_version"
        
        # Show container IP
        container_ip=$(docker inspect "$REDIS_CONTAINER_NAME" --format "{{.NetworkSettings.Networks.${NETWORK_NAME}.IPAddress}}" 2>/dev/null || echo "unknown")
        echo "  Container IP: $container_ip"
    else
        echo "❌ Redis container '$REDIS_CONTAINER_NAME' is not running"
    fi
}

# Main script logic
case "${1:-status}" in
    "setup"|"start")
        echo "Setting up Docker network and Redis coordination..."
        create_network
        start_redis
        echo ""
        echo "✅ Setup complete!"
        show_status
        ;;
    "stop")
        echo "Stopping Redis and cleaning up..."
        stop_redis
        echo ""
        echo "✅ Cleanup complete!"
        ;;
    "cleanup"|"clean")
        echo "Cleaning up Docker network and Redis..."
        stop_redis
        remove_network
        echo ""
        echo "✅ Full cleanup complete!"
        ;;
    "status")
        show_status
        ;;
    "restart")
        echo "Restarting Redis coordination..."
        stop_redis
        start_redis
        echo ""
        echo "✅ Restart complete!"
        show_status
        ;;
    *)
        echo "Usage: $0 {setup|start|stop|cleanup|clean|status|restart}"
        echo ""
        echo "Commands:"
        echo "  setup/start  - Create network and start Redis"
        echo "  stop         - Stop Redis container"
        echo "  cleanup/clean - Stop Redis and remove network"
        echo "  status       - Show current status"
        echo "  restart      - Restart Redis container"
        exit 1
        ;;
esac