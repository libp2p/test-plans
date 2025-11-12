#!/bin/bash
# Stop Redis and Relay containers

set -euo pipefail

NETWORK_NAME="hole-punch-network"
REDIS_NAME="hole-punch-redis"
RELAY_NAME="hole-punch-relay"

echo "Stopping global services..."
echo ""

# Stop Redis
if docker ps -q -f name="^${REDIS_NAME}$" | grep -q .; then
    echo "→ Stopping Redis..."
    docker stop "$REDIS_NAME" &>/dev/null || true
    echo "  ✓ Redis stopped"
else
    echo "→ Redis not running"
fi

# Stop Relay
if docker ps -q -f name="^${RELAY_NAME}$" | grep -q .; then
    echo "→ Stopping Relay..."
    docker stop "$RELAY_NAME" &>/dev/null || true
    echo "  ✓ Relay stopped"
else
    echo "→ Relay not running"
fi

# Remove network
if docker network inspect "$NETWORK_NAME" &>/dev/null; then
    echo "→ Removing network..."
    docker network rm "$NETWORK_NAME" &>/dev/null || true
    echo "  ✓ Network removed"
else
    echo "→ Network not found"
fi

echo ""
echo "✓ Global services stopped"
