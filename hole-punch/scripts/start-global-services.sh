#!/bin/bash
# Start Redis container for test coordination (relay is per-test)

set -euo pipefail

NETWORK_NAME="hole-punch-network"
REDIS_NAME="hole-punch-redis"

# Create network if doesn't exist
if ! docker network inspect "$NETWORK_NAME" &>/dev/null; then
    docker network create "$NETWORK_NAME" > /dev/null
    echo "✓ Created network: $NETWORK_NAME"
else
    echo "→ Network already exists: $NETWORK_NAME"
fi

# Start Redis if not running
if ! docker ps -q -f name="^${REDIS_NAME}$" | grep -q .; then
    echo -n "→ Starting Redis..."
    docker run -d \
        --name "$REDIS_NAME" \
        --network "$NETWORK_NAME" \
        --rm \
        redis:7-alpine \
        redis-server --save "" --appendonly no > /dev/null

    # Wait for Redis to be ready
    for i in {1..10}; do
        if docker exec "$REDIS_NAME" redis-cli ping &>/dev/null; then
            echo "started"
            break
        fi
        echo -n "."
        sleep 1
    done
else
    echo "→ Redis already running"
fi
