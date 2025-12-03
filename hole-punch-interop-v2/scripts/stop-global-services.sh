#!/bin/bash
# Stop Redis container (relay is per-test and auto-cleaned)

set -euo pipefail

NETWORK_NAME="hole-punch-network"
REDIS_NAME="hole-punch-redis"

# Stop Redis
if docker ps -q -f name="^${REDIS_NAME}$" | grep -q .; then
    echo -n "→ Stopping Redis..."
    docker stop "$REDIS_NAME" &>/dev/null || true
    echo "stopped"
else
    echo "→ Redis not running"
fi

# Remove network
if docker network inspect "$NETWORK_NAME" &>/dev/null; then
    docker network rm "$NETWORK_NAME" &>/dev/null || true
    echo "✓ Network removed: $NETWORK_NAME"
else
    echo "→ Network not found"
fi
