#!/bin/bash
# Start Redis and Relay containers for all tests (hybrid architecture)

set -euo pipefail

NETWORK_NAME="hole-punch-network"
REDIS_NAME="hole-punch-redis"
RELAY_NAME="hole-punch-relay"

echo "Starting global services..."
echo ""

# Create network if doesn't exist
if ! docker network inspect "$NETWORK_NAME" &>/dev/null; then
    docker network create "$NETWORK_NAME"
    echo "✓ Created network: $NETWORK_NAME"
else
    echo "→ Network already exists: $NETWORK_NAME"
fi

# Start Redis if not running
if ! docker ps -q -f name="^${REDIS_NAME}$" | grep -q .; then
    echo "→ Starting Redis..."
    docker run -d \
        --name "$REDIS_NAME" \
        --network "$NETWORK_NAME" \
        --rm \
        redis:7-alpine \
        redis-server --save "" --appendonly no

    # Wait for Redis to be ready
    echo -n "  Waiting for Redis"
    for i in {1..10}; do
        if docker exec "$REDIS_NAME" redis-cli ping &>/dev/null; then
            echo ""
            echo "  ✓ Redis is ready"
            break
        fi
        echo -n "."
        sleep 1
    done
else
    echo "→ Redis already running"
fi

# Start Relay if not running
if ! docker ps -q -f name="^${RELAY_NAME}$" | grep -q .; then
    echo "→ Starting Relay..."

    # TODO: Replace with actual relay image when available
    # For now, this is a placeholder showing the structure
    # docker run -d \
    #     --name "$RELAY_NAME" \
    #     --network "$NETWORK_NAME" \
    #     --rm \
    #     libp2p/relay:latest

    echo "  ⚠ Relay image not yet configured (placeholder)"
    echo "  → Relay would be started here in production"
else
    echo "→ Relay already running"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✓ Global services ready"
echo "  Redis: $REDIS_NAME"
echo "  Network: $NETWORK_NAME"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
