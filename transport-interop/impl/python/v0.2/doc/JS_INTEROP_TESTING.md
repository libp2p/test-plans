# Manual Testing: Python vs JS-libp2p Ping Interoperability

This guide explains how to manually test the Python ping implementation against js-libp2p hosts to verify cross-implementation interoperability.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Test Scenarios](#test-scenarios)
- [Step-by-Step Testing](#step-by-step-testing)
- [Configuration Options](#configuration-options)
- [Troubleshooting](#troubleshooting)
- [Expected Results](#expected-results)
- [Advanced Testing](#advanced-testing)

## Overview

The transport-interop framework supports testing between different libp2p implementations. This guide focuses on testing the Python implementation against js-libp2p v2.x to ensure they can successfully communicate using the ping protocol.

### Test Architecture

```
┌─────────────┐    Redis    ┌─────────────┐
│ Python      │◄──────────► │ JS-libp2p   │
│ (Dialer)    │             │ (Listener)  │
└─────────────┘             └─────────────┘
```

## Prerequisites

### 1. Build Required Images

```bash
# Build Python image (if not already built)
cd transport-interop/impl/python/v0.2
make image.json

# Build JS-libp2p image
cd transport-interop/impl/js/v2.x
make image.json
```

### 2. Start Redis Server

```bash
# Start Redis for coordination
docker run -d --name redis-test -p 6379:6379 redis:alpine

# Verify Redis is running
docker ps | grep redis
```

### 3. Verify Images Are Available

```bash
# Check available images
docker images | grep -E "(python-v0.2.9|node-js-v2.x)"

# Expected output:
# python-v0.2.9    latest    <image-id>    <created>    <size>
# node-js-v2.x     latest    <image-id>    <created>    <size>
```

## Test Scenarios

### Scenario 1: Python Dialer → JS Listener
- **Python**: Acts as dialer (client)
- **JS-libp2p**: Acts as listener (server)
- **Purpose**: Test Python's ability to connect to and ping JS hosts

### Scenario 2: JS Dialer → Python Listener
- **JS-libp2p**: Acts as dialer (client)
- **Python**: Acts as listener (server)
- **Purpose**: Test JS's ability to connect to and ping Python hosts

### Scenario 3: Cross-Implementation Matrix
Test all combinations of:
- **Transports**: TCP
- **Security**: Noise, Plaintext
- **Muxers**: Mplex, Yamux

## Step-by-Step Testing

### Test 1: Python Dialer → JS Listener (TCP + Noise + Yamux)

#### Step 1: Start JS Listener

```bash
# Terminal 1: Start JS listener
docker run --rm --network host \
  -e transport=tcp \
  -e muxer=yamux \
  -e security=noise \
  -e is_dialer=false \
  -e test_timeout_secs=15 \
  -e redis_addr=localhost:6379 \
  node-js-v2.x
```

**Expected Output:**
```
Running as listener
Publishing address to Redis: /ip4/0.0.0.0/tcp/XXXXX/p2p/16Uiu2HAkvpyXQ1BuqHbLKASmVe5tLZrQKxgKL75crGV2fVNNBcRF
Waiting for incoming ping...
```

#### Step 2: Start Python Dialer

```bash
# Terminal 2: Start Python dialer
docker run --rm --network host \
  -e transport=tcp \
  -e muxer=yamux \
  -e security=noise \
  -e is_dialer=true \
  -e redis_addr=localhost:6379 \
  -e test_timeout_seconds=15 \
  python-v0.2.9 python ping_test.py
```

**Expected Output:**
```
Connected to Redis at localhost:6379
Running as dialer
Waiting for listener address from Redis...
Got listener address: /ip4/0.0.0.0/tcp/XXXXX/p2p/16Uiu2HAkvpyXQ1BuqHbLKASmVe5tLZrQKxgKL75crGV2fVNNBcRF
Connecting to /ip4/0.0.0.0/tcp/XXXXX/p2p/16Uiu2HAkvpyXQ1BuqHbLKASmVe5tLZrQKxgKL75crGV2fVNNBcRF
Creating ping stream
sending ping to 16Uiu2HAkvpyXQ1BuqHbLKASmVe5tLZrQKxgKL75crGV2fVNNBcRF
received pong from 16Uiu2HAkvpyXQ1BuqHbLKASmVe5tLZrQKxgKL75crGV2fVNNBcRF
{"handshakePlusOneRTTMillis": 10.88, "pingRTTMilllis": 0.26}
```

### Test 2: JS Dialer → Python Listener (TCP + Plaintext + Mplex)

#### Step 1: Start Python Listener

```bash
# Terminal 1: Start Python listener
docker run --rm --network host \
  -e transport=tcp \
  -e muxer=mplex \
  -e security=plaintext \
  -e is_dialer=false \
  -e ip="0.0.0.0" \
  -e redis_addr=localhost:6379 \
  -e test_timeout_seconds=15 \
  python-v0.2.9 python ping_test.py
```

#### Step 2: Start JS Dialer

```bash
# Terminal 2: Start JS dialer
docker run --rm --network host \
  -e transport=tcp \
  -e muxer=mplex \
  -e security=plaintext \
  -e is_dialer=true \
  -e test_timeout_secs=15 \
  -e redis_addr=localhost:6379 \
  node-js-v2.x
```

## Configuration Options

### Environment Variables

#### Python Implementation
```bash
-e transport=tcp                    # Transport protocol
-e muxer=yamux|mplex              # Multiplexer
-e security=noise|plaintext       # Security protocol
-e is_dialer=true|false           # Role (dialer/listener)
-e ip="0.0.0.0"                   # Listen IP (listener only)
-e redis_addr=localhost:6379      # Redis server address
-e test_timeout_seconds=15        # Test timeout in seconds
```

#### JS-libp2p Implementation
```bash
-e transport=tcp                    # Transport protocol
-e muxer=yamux|mplex              # Multiplexer
-e security=noise|plaintext       # Security protocol
-e is_dialer=true|false           # Role (dialer/listener)
-e test_timeout_secs=15           # Test timeout in seconds
-e redis_addr=localhost:6379      # Redis server address
```

### Supported Combinations

| Transport | Security | Muxer | Python | JS-libp2p | Status |
|-----------|----------|-------|--------|-----------|--------|
| TCP       | Noise    | Yamux | ✅     | ✅        | ✅     |
| TCP       | Noise    | Mplex | ✅     | ✅        | ✅     |
| TCP       | Plaintext| Yamux | ✅     | ✅        | ✅     |
| TCP       | Plaintext| Mplex | ✅     | ✅        | ✅     |

## Troubleshooting

### Common Issues

#### Issue 1: Redis Connection Failed
**Symptoms:**
```
Error: Error -2 connecting to redis:6379. Name or service not known.
```

**Solutions:**
```bash
# Check if Redis is running
docker ps | grep redis

# Start Redis if not running
docker run -d --name redis-test -p 6379:6379 redis:alpine

# Check Redis logs
docker logs redis-test
```

#### Issue 2: Image Not Found
**Symptoms:**
```
Error: Unable to find image 'python-v0.2.9:latest' locally
```

**Solutions:**
```bash
# Build Python image
cd transport-interop/impl/python/v0.2
make image.json

# Build JS image
cd transport-interop/impl/js/v2.x
make image.json

# Verify images exist
docker images | grep -E "(python-v0.2.9|node-js-v2.x)"
```

#### Issue 3: Timeout Waiting for Listener
**Symptoms:**
```
Error: Timeout waiting for listener address
```

**Solutions:**
```bash
# Check if listener is running
docker ps | grep -E "(python-v0.2.9|node-js-v2.x)"

# Check Redis for listener address
docker exec redis-test redis-cli LRANGE listenerAddr 0 -1

# Increase timeout
-e test_timeout_seconds=30
```

#### Issue 4: Connection Refused
**Symptoms:**
```
Error: Connection refused
```

**Solutions:**
```bash
# Check if both components are using same transport/security/muxer
# Ensure listener started before dialer
# Check network connectivity
docker network ls
```

### Debugging Commands

#### Monitor Redis Activity
```bash
# Monitor Redis in real-time
docker exec redis-test redis-cli monitor

# Check Redis data
docker exec redis-test redis-cli LRANGE listenerAddr 0 -1
```

#### Check Container Logs
```bash
# Check Python container logs
docker logs <python-container-id>

# Check JS container logs
docker logs <js-container-id>
```

#### Network Debugging
```bash
# Check network connectivity
docker exec <container-id> ping <target-ip>

# Check listening ports
docker exec <container-id> netstat -tlnp
```

## Expected Results

### Successful Test Output

#### Python Dialer Success
```json
{
  "handshakePlusOneRTTMillis": 10.88,
  "pingRTTMilllis": 0.26
}
```

#### JS Dialer Success
```json
{
  "handshakePlusOneRTTMillis": 12.45,
  "pingRTTMilllis": 0.31
}
```

### Performance Benchmarks

| Configuration | Handshake + RTT (ms) | Ping RTT (ms) |
|---------------|---------------------|---------------|
| TCP + Noise + Yamux | 10-15 | 0.2-0.5 |
| TCP + Noise + Mplex | 8-12 | 0.2-0.4 |
| TCP + Plaintext + Yamux | 5-10 | 0.1-0.3 |
| TCP + Plaintext + Mplex | 4-8 | 0.1-0.2 |

## Advanced Testing

### Automated Test Matrix

Create a script to test all combinations:

```bash
#!/bin/bash

# Test matrix
transports=("tcp")
securities=("noise" "plaintext")
muxers=("yamux" "mplex")
roles=("python_js" "js_python")

for transport in "${transports[@]}"; do
  for security in "${securities[@]}"; do
    for muxer in "${muxers[@]}"; do
      for role in "${roles[@]}"; do
        echo "Testing: $transport + $security + $muxer ($role)"
        # Run test with current configuration
        # Store results
      done
    done
  done
done
```

### Load Testing

```bash
# Test with multiple concurrent connections
for i in {1..10}; do
  docker run --rm --network host \
    -e transport=tcp -e muxer=yamux -e security=noise \
    -e is_dialer=true -e redis_addr=localhost:6379 \
    python-v0.2.9 python ping_test.py &
done
```

### Stress Testing

```bash
# Run tests for extended periods
for i in {1..100}; do
  echo "Test iteration $i"
  # Run test
  sleep 1
done
```

## Summary

This guide provides comprehensive instructions for manually testing Python ping interoperability with js-libp2p hosts. The key points are:

1. **Build both images** before testing
2. **Start Redis** for coordination
3. **Test both directions** (Python→JS and JS→Python)
4. **Test all configurations** (transport/security/muxer combinations)
5. **Monitor Redis** for debugging
6. **Check logs** for detailed error information

Successful tests demonstrate that the Python implementation can interoperate with js-libp2p, validating the transport-interop framework's cross-implementation compatibility goals.

## References

- [Transport-Interop Framework](../README.md)
- [Python Implementation](./README.md)
- [JS-libp2p Implementation](../../js/v2.x/)
- [Redis Coordination](./REDIS_COORDINATION.md) 