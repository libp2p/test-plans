# Manual Testing Guide for py-libp2p Ping Implementation

This guide covers how to manually test the py-libp2p ping implementation for transport-interop tests.

## Prerequisites

- Docker installed and running
- Network access to pull Docker images
- Terminal with multiple tabs/windows

## Quick Start Test

### 1. Start Redis Server
```bash
docker run -d --name redis-test -p 6379:6379 redis:alpine
```

### 2. Test Listener (Terminal 1)
```bash
docker run --rm --network host \
  -e transport=tcp \
  -e muxer=mplex \
  -e security=noise \
  -e is_dialer=false \
  -e ip="0.0.0.0" \
  -e redis_addr=localhost:6379 \
  -e test_timeout_seconds=15 \
  python-v0.2.9-git python ping_test.py
```

**Expected Output:**
```
Connected to Redis at localhost:6379
Running as listener
Publishing address to Redis: /ip4/0.0.0.0/tcp/XXXXX/p2p/QmXXXXX...
Waiting for 15 seconds...
received ping from QmXXXXX...
responded with pong to QmXXXXX...
```

### 3. Test Dialer (Terminal 2)
```bash
docker run --rm --network host \
  -e transport=tcp \
  -e muxer=mplex \
  -e security=noise \
  -e is_dialer=true \
  -e redis_addr=localhost:6379 \
  -e test_timeout_seconds=10 \
  python-v0.2.9-git python ping_test.py
```

**Expected Output:**
```
Connected to Redis at localhost:6379
Running as dialer
Waiting for listener address from Redis...
Got listener address: /ip4/0.0.0.0/tcp/XXXXX/p2p/QmXXXXX...
Connecting to /ip4/0.0.0.0/tcp/XXXXX/p2p/QmXXXXX...
Creating ping stream
sending ping to QmXXXXX...
received pong from QmXXXXX...
{"handshakePlusOneRTTMillis": 43.84, "pingRTTMilllis": 0.26}
```

### 4. Cleanup
```bash
docker stop redis-test && docker rm redis-test
```

## Detailed Testing Scenarios

### Basic Functionality Tests

#### Test 1: Basic Ping/Pong Exchange
**Purpose:** Verify basic connectivity and ping protocol
```bash
# Terminal 1 - Listener
docker run --rm --network host \
  -e transport=tcp -e muxer=mplex -e security=noise \
  -e is_dialer=false -e ip="0.0.0.0" \
  -e redis_addr=localhost:6379 -e test_timeout_seconds=20 \
  python-v0.2.9-git python ping_test.py

# Terminal 2 - Dialer (run after listener starts)
docker run --rm --network host \
  -e transport=tcp -e muxer=mplex -e security=noise \
  -e is_dialer=true -e redis_addr=localhost:6379 \
  -e test_timeout_seconds=10 \
  python-v0.2.9-git python ping_test.py
```

#### Test 2: Multiple Ping Tests
**Purpose:** Verify consistent performance
```bash
# Run 5 consecutive tests
for i in {1..5}; do
  echo "=== Test $i ==="
  
  # Start listener in background
  docker run --rm --network host \
    -e transport=tcp -e muxer=mplex -e security=noise \
    -e is_dialer=false -e ip="0.0.0.0" \
    -e redis_addr=localhost:6379 -e test_timeout_seconds=10 \
    python-v0.2.9-git python ping_test.py &
  
  sleep 2
  
  # Run dialer
  docker run --rm --network host \
    -e transport=tcp -e muxer=mplex -e security=noise \
    -e is_dialer=true -e redis_addr=localhost:6379 \
    -e test_timeout_seconds=5 \
    python-v0.2.9-git python ping_test.py
  
  sleep 1
done
```

### Configuration Tests

#### Test 3: Different IP Addresses
**Purpose:** Test with various IP configurations
```bash
# Test with localhost
docker run --rm --network host \
  -e transport=tcp -e muxer=mplex -e security=noise \
  -e is_dialer=false -e ip="127.0.0.1" \
  -e redis_addr=localhost:6379 -e test_timeout_seconds=15 \
  python-v0.2.9-git python ping_test.py

# Test with specific interface
docker run --rm --network host \
  -e transport=tcp -e muxer=mplex -e security=noise \
  -e is_dialer=false -e ip="0.0.0.0" \
  -e redis_addr=localhost:6379 -e test_timeout_seconds=15 \
  python-v0.2.9-git python ping_test.py
```

#### Test 4: Different Timeout Values
**Purpose:** Test timeout handling
```bash
# Short timeout
docker run --rm --network host \
  -e transport=tcp -e muxer=mplex -e security=noise \
  -e is_dialer=true -e redis_addr=localhost:6379 \
  -e test_timeout_seconds=2 \
  python-v0.2.9-git python ping_test.py

# Long timeout
docker run --rm --network host \
  -e transport=tcp -e muxer=mplex -e security=noise \
  -e is_dialer=true -e redis_addr=localhost:6379 \
  -e test_timeout_seconds=30 \
  python-v0.2.9-git python ping_test.py
```

### Error Handling Tests

#### Test 5: Redis Connection Failure
**Purpose:** Test behavior when Redis is unavailable
```bash
# Test without Redis running
docker run --rm --network host \
  -e transport=tcp -e muxer=mplex -e security=noise \
  -e is_dialer=true -e redis_addr=localhost:6379 \
  -e test_timeout_seconds=5 \
  python-v0.2.9-git python ping_test.py
```

#### Test 6: Invalid Configuration
**Purpose:** Test error handling for unsupported configurations
```bash
# Test unsupported transport
docker run --rm --network host \
  -e transport=quic -e muxer=mplex -e security=noise \
  -e is_dialer=true -e redis_addr=localhost:6379 \
  python-v0.2.9-git python ping_test.py

# Test unsupported security
docker run --rm --network host \
  -e transport=tcp -e muxer=mplex -e security=tls \
  -e is_dialer=true -e redis_addr=localhost:6379 \
  python-v0.2.9-git python ping_test.py

# Test unsupported muxer
docker run --rm --network host \
  -e transport=tcp -e muxer=yamux -e security=noise \
  -e is_dialer=true -e redis_addr=localhost:6379 \
  python-v0.2.9-git python ping_test.py
```

#### Test 7: Missing Environment Variables
**Purpose:** Test behavior with missing configuration
```bash
# Test with no environment variables
docker run --rm python-v0.2.9-git python ping_test.py

# Test with partial environment variables
docker run --rm --network host \
  -e transport=tcp -e redis_addr=localhost:6379 \
  python-v0.2.9-git python ping_test.py
```

### Performance Tests

#### Test 8: Performance Benchmarking
**Purpose:** Measure consistent performance
```bash
# Run performance test
echo "Performance Test Results:" > performance_results.txt
for i in {1..10}; do
  echo "Test $i:" >> performance_results.txt
  
  # Start listener
  docker run --rm --network host \
    -e transport=tcp -e muxer=mplex -e security=noise \
    -e is_dialer=false -e ip="0.0.0.0" \
    -e redis_addr=localhost:6379 -e test_timeout_seconds=10 \
    python-v0.2.9-git python ping_test.py &
  
  sleep 1
  
  # Run dialer and capture output
  result=$(docker run --rm --network host \
    -e transport=tcp -e muxer=mplex -e security=noise \
    -e is_dialer=true -e redis_addr=localhost:6379 \
    -e test_timeout_seconds=5 \
    python-v0.2.9-git python ping_test.py 2>/dev/null | tail -1)
  
  echo "  $result" >> performance_results.txt
  sleep 1
done

cat performance_results.txt
```

### Docker Image Tests

#### Test 9: Docker Image Verification
**Purpose:** Verify Docker image is built correctly
```bash
# Test py-libp2p installation
docker run --rm python-v0.2.9-git python -c "
import libp2p
print('py-libp2p version:', libp2p.__version__)
print('Installation successful!')
"

# Test required dependencies
docker run --rm python-v0.2.9-git python -c "
import trio
import redis
import multiaddr
print('All dependencies available!')
"

# Test ping test module
docker run --rm python-v0.2.9-git python -c "
import ping_test
print('Ping test module imported successfully!')
"
```

#### Test 10: Container Resource Usage
**Purpose:** Monitor resource consumption
```bash
# Monitor memory and CPU usage
docker run --rm --network host \
  -e transport=tcp -e muxer=mplex -e security=noise \
  -e is_dialer=false -e ip="0.0.0.0" \
  -e redis_addr=localhost:6379 -e test_timeout_seconds=30 \
  python-v0.2.9-git python ping_test.py &
  
# In another terminal, monitor the container
docker stats $(docker ps -q --filter ancestor=python-v0.2.9-git)
```

## Troubleshooting

### Common Issues

#### Issue 1: Redis Connection Failed
**Symptoms:** `Error: Error -2 connecting to redis:6379`
**Solution:** Ensure Redis is running and accessible
```bash
# Check if Redis is running
docker ps | grep redis

# Restart Redis if needed
docker stop redis-test && docker rm redis-test
docker run -d --name redis-test -p 6379:6379 redis:alpine
```

#### Issue 2: Port Already in Use
**Symptoms:** `Address already in use` errors
**Solution:** Wait for previous test to complete or kill processes
```bash
# Kill any running containers
docker kill $(docker ps -q)

# Or wait for timeout
sleep 20
```

#### Issue 3: Docker Image Not Found
**Symptoms:** `Unable to find image 'python-v0.2.9-git'`
**Solution:** Rebuild the Docker image
```bash
cd transport-interop/impl/python/v0.2
make clean && make
```

#### Issue 4: Permission Denied
**Symptoms:** Docker permission errors
**Solution:** Run with sudo or add user to docker group
```bash
# Option 1: Use sudo
sudo docker run --rm python-v0.2.9-git python ping_test.py

# Option 2: Add user to docker group (requires logout/login)
sudo usermod -aG docker $USER
```

### Debug Mode

The implementation integrates with py-libp2p's built-in logging system. Enable debug logging using the `LIBP2P_DEBUG` environment variable:

#### Basic Debug Logging
```bash
# Enable all debug output
docker run --rm --network host \
  -e transport=tcp -e muxer=mplex -e security=noise \
  -e is_dialer=true -e redis_addr=localhost:6379 \
  -e LIBP2P_DEBUG=DEBUG \
  python-v0.2.9-git python ping_test.py
```

#### Module-Specific Debug Logging
```bash
# Enable debug only for ping_test module
docker run --rm --network host \
  -e transport=tcp -e muxer=mplex -e security=noise \
  -e is_dialer=true -e redis_addr=localhost:6379 \
  -e LIBP2P_DEBUG=ping_test:DEBUG \
  python-v0.2.9-git python ping_test.py
```

#### Debug with Custom Log File
```bash
# Log debug output to specific file
docker run --rm --network host \
  -e transport=tcp -e muxer=mplex -e security=noise \
  -e is_dialer=true -e redis_addr=localhost:6379 \
  -e LIBP2P_DEBUG=DEBUG \
  -e LIBP2P_DEBUG_FILE=/tmp/custom_debug.log \
  python-v0.2.9-git python ping_test.py
```

#### Debug Logging Examples

**No Debug (Default):**
```bash
docker run --rm python-v0.2.9-git python ping_test.py
# Output: Only regular print statements, no debug logs
```

**Full Debug Mode:**
```bash
docker run --rm -e LIBP2P_DEBUG=DEBUG python-v0.2.9-git python ping_test.py
# Output: 
# Logging to: /tmp/py-libp2p_20250725_233931_373335_a208d3d4.log
# 2025-07-25 23:39:31,374 - libp2p.ping_test - DEBUG - ENV is_dialer=None
# 2025-07-25 23:39:31,374 - libp2p.ping_test - DEBUG - All environment variables: ...
```

**Module-Specific Debug:**
```bash
docker run --rm -e LIBP2P_DEBUG=ping_test:DEBUG python-v0.2.9-git python ping_test.py
# Output: Only ping_test module debug logs with timestamps
```

#### Debug Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `LIBP2P_DEBUG` | Controls debug logging level | `DEBUG`, `ping_test:DEBUG` |
| `LIBP2P_DEBUG_FILE` | Custom log file path | `/tmp/custom.log` |

#### Debug Log Features

- **Automatic Integration**: No manual logging setup required
- **Thread-Safe**: Uses py-libp2p's queue-based logging system
- **Automatic File Logging**: Creates timestamped log files in `/tmp/`
- **Hierarchical Control**: Enable debug for specific modules
- **Zero Overhead**: No debug output when `LIBP2P_DEBUG` is not set
- **Proper Formatting**: Timestamps, module names, log levels

## Success Criteria

A successful test should demonstrate:

1. ✅ **Connection Establishment**: Dialer successfully connects to listener
2. ✅ **Protocol Handshake**: Noise security handshake completes
3. ✅ **Ping/Pong Exchange**: Ping messages sent and received correctly
4. ✅ **Timing Measurements**: Reasonable RTT values (typically < 100ms for localhost)
5. ✅ **Error Handling**: Graceful handling of connection failures
6. ✅ **Redis Coordination**: Address exchange via Redis works
7. ✅ **Docker Integration**: Container runs without issues
8. ✅ **Resource Usage**: Reasonable memory and CPU consumption

## Expected Performance Metrics

For localhost testing, expect:
- **handshakePlusOneRTTMillis**: 20-100ms
- **pingRTTMilllis**: 0.1-5ms
- **Memory Usage**: < 100MB
- **CPU Usage**: < 10% during active testing

## Cleanup

After testing, always clean up resources:
```bash
# Stop and remove Redis container
docker stop redis-test && docker rm redis-test

# Kill any remaining containers
docker kill $(docker ps -q --filter ancestor=python-v0.2.9-git)

# Remove test images (optional)
docker rmi python-v0.2.9-git
``` 