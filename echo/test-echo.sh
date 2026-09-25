#!/bin/bash

set -euo pipefail

echo "Starting Echo Interop Test..."

# Create a network for the containers
docker network create echo-test-network 2>/dev/null || true

# Start Redis if not already running
if ! docker ps | grep -q redis-echo-test; then
    echo "Starting Redis..."
    docker run -d --name redis-echo-test --network echo-test-network -p 6379:6379 redis:alpine
    sleep 3
fi

# Start JS echo server
echo "Starting JS libp2p echo server..."
JS_CONTAINER=$(docker run -d --name js-echo-server --network echo-test-network \
    -e REDIS_ADDR=redis://redis-echo-test:6379 \
    js-libp2p-echo:v1.x)

# Wait for server to start and publish its multiaddr
echo "Waiting for server to start..."
sleep 5

# Run Python client test
echo "Running Python libp2p echo client test..."
docker run --rm --name py-echo-client --network echo-test-network \
    -e REDIS_ADDR=redis://redis-echo-test:6379 \
    py-libp2p-echo:v0.x

# Cleanup
echo "Cleaning up..."
docker stop js-echo-server redis-echo-test 2>/dev/null || true
docker rm js-echo-server redis-echo-test 2>/dev/null || true
docker network rm echo-test-network 2>/dev/null || true

echo "Echo interop test completed!"