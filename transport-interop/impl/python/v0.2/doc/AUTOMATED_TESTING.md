# Automated Testing Guide for py-libp2p Ping Implementation

This guide covers how to use the transport-interop framework to automatically test the py-libp2p ping implementation against other libp2p implementations.

## Prerequisites

- Node.js (v16 or higher)
- npm
- Docker installed and running
- All required libp2p implementations built and available

## Framework Setup

### 1. Install Dependencies
```bash
cd transport-interop
npm install
```

### 2. Verify Framework Installation
```bash
# Check if the framework is working
npm test -- --help
```

## Docker Configuration

### Docker Daemon Network Pool Configuration

If you encounter the error "all predefined address pools have been fully subnetted", Docker has run out of IP address pools. This can be fixed by configuring larger network pools in the Docker daemon.

#### Configure Docker Daemon for Larger Network Pools

Edit `/etc/docker/daemon.json` to add default address pools:

```json
{
    
    "default-address-pools": [
        {
            "base": "172.16.0.0/12",
            "size": 24
        },
        {
            "base": "192.168.0.0/16", 
            "size": 24
        },
        {
            "base": "10.0.0.0/8",
            "size": 24
        }
    ]
}
```

#### Implementation Steps

1. **Backup current configuration:**
```bash
sudo cp /etc/docker/daemon.json /etc/docker/daemon.json.backup
```

2. **Edit the daemon configuration:**
```bash
sudo nano /etc/docker/daemon.json
```

3. **Add the default-address-pools section** to your existing configuration

4. **Restart Docker daemon:**
```bash
sudo systemctl restart docker
```

5. **Verify the configuration:**
```bash
docker info | grep -A 10 "Default Address Pools"
```

#### Configuration Details

- **Base networks**: Uses `/12` networks (4096 subnets) instead of default `/16` (256 subnets)
- **Size**: Each subnet uses `/24` (256 IP addresses)
- **Total capacity**: Allows for thousands of concurrent Docker networks
- **Compatibility**: Works with existing nvidia runtime and btrfs storage driver

### Alternative Solutions (if daemon config is not possible)

#### Solution 1: Clean up existing networks
```bash
# Remove unused networks
docker network prune -f

# Remove all unused Docker resources
docker system prune -f

# Remove all stopped containers
docker container prune -f
```

#### Solution 2: Limit concurrent tests
```bash
# Set environment variable to limit concurrent workers
export WORKER_COUNT=4

# Run tests with limited concurrency
npm test -- --name-filter="python-v0.2.9 x js-v1.x" --concurrent=4
```

#### Solution 3: Use host networking (if available)
```bash
# Set environment variable to use host networking
export DOCKER_NETWORK=host

# Run tests with host networking
npm test -- --name-filter="python-v0.2.9 x js-v1.x"
```

## Basic Automated Testing

### Test Python Implementation Alone
```bash
# Test Python implementation (will fail if no other implementations are available)
npm test -- --name-filter="python-v0.2.9"
```

### Test Against Specific Implementation
```bash
# Test Python vs JavaScript (one direction)
npm test -- --name-filter="python-v0.2.9 x js-v1.x"

# Test Python vs Rust (one direction)
npm test -- --name-filter="python-v0.2.9 x rust-v0.53"

# Test Python vs Go (one direction)
npm test -- --name-filter="python-v0.2.9 x go-v0.42"
```

### Test Bidirectional Between Implementations
```bash
# Test Python vs JavaScript (both directions)
npm test -- --name-filter="python-v0.2.9 x js-v1.x|js-v1.x x python-v0.2.9"

# Test Python vs Rust (both directions)
npm test -- --name-filter="python-v0.2.9 x rust-v0.53|rust-v0.53 x python-v0.2.9"

# Test Python vs Go (both directions)
npm test -- --name-filter="python-v0.2.9 x go-v0.42|go-v0.42 x python-v0.2.9"
```

### Test All Compatible Implementations
```bash
# Test Python against all implementations that support TCP+Noise+Mplex
npm test -- --name-filter="python-v0.2.9"
```

## Advanced Testing Scenarios

### Cross-Implementation Testing

#### Test 1: Python as Dialer vs Other Listeners
```bash
# Test Python dialer against various listeners
npm test -- --name-filter="python-v0.2.9 x js-v1.x|python-v0.2.9 x rust-v0.53|python-v0.2.9 x go-v0.42"
```

#### Test 2: Python as Listener vs Other Dialers
```bash
# Test Python listener against various dialers
npm test -- --name-filter="js-v1.x x python-v0.2.9|rust-v0.53 x python-v0.2.9|go-v0.42 x python-v0.2.9"
```

#### Test 3: Round-Robin Testing
```bash
# Test all combinations of Python with other implementations
npm test -- --name-filter="python-v0.2.9 x js-v1.x|js-v1.x x python-v0.2.9|python-v0.2.9 x rust-v0.53|rust-v0.53 x python-v0.2.9|python-v0.2.9 x go-v0.42|go-v0.42 x python-v0.2.9"
```

## Test Configuration

### Environment Variables
```bash
# Set test timeout (in seconds)
export TIMEOUT=600

# Set worker count for parallel execution
export WORKER_COUNT=4

# Enable verbose logging
export VERBOSE=true
```

## Monitoring and Logging

### Enable Verbose Logging
```bash
# Enable verbose logging
npm test -- --name-filter="python-v0.2.9" --verbose
```

### Log Analysis
```bash
# Save test results to file
npm test -- --name-filter="python-v0.2.9" > test-results.log 2>&1

# Analyze results
grep "python-v0.2.9" test-results.log
grep "ERROR" test-results.log
```



## Error Handling and Debugging

### Common Test Failures

#### Issue 1: Implementation Not Found
**Symptoms:** `Error: ENOENT: no such file or directory, open './impl/python/v0.2/image.json'`
**Solution:** Ensure Python implementation is built
```bash
cd transport-interop/impl/python/v0.2
make clean && make
```

#### Issue 2: Docker Image Not Available
**Symptoms:** `Unable to find image 'python-v0.2.9'`
**Solution:** Rebuild Docker image
```bash
cd transport-interop/impl/python/v0.2
docker build -f PingDockerfile -t python-v0.2.9 .
```

#### Issue 3: Redis Connection Failed
**Symptoms:** `Error connecting to Redis`
**Solution:** Start Redis server
```bash
docker run -d --name redis-test -p 6379:6379 redis:alpine
```

#### Issue 4: Port Conflicts
**Symptoms:** `Address already in use`
**Solution:** Clean up existing containers
```bash
docker kill $(docker ps -q)
docker rm $(docker ps -aq)
```

### Debug Mode
```bash
# Enable comprehensive debugging
npm test -- --name-filter="python-v0.2.9" --verbose
```





## Continuous Monitoring

### Automated Test Runner
Create `run-tests.sh`:
```bash
#!/bin/bash
set -e

echo "Starting automated tests for python-v0.2.9"

# Build implementation
cd transport-interop/impl/python/v0.2
make

# Run tests
cd ../..
npm test -- --name-filter="python-v0.2.9" > results-$(date +%Y%m%d-%H%M%S).log

echo "Tests completed successfully"
```

### Scheduled Testing
```bash
# Add to crontab for daily testing
0 2 * * * /path/to/transport-interop/run-tests.sh
```

## Success Criteria

Automated tests should pass when:

1. ✅ **Build Success**: Docker image builds without errors
2. ✅ **Container Start**: Container starts and runs correctly
3. ✅ **Redis Connection**: Successfully connects to Redis
4. ✅ **Address Exchange**: Listener publishes address, dialer retrieves it
5. ✅ **Connection Establishment**: Dialer connects to listener
6. ✅ **Protocol Handshake**: Noise handshake completes successfully
7. ✅ **Ping/Pong Exchange**: Ping messages sent and received
8. ✅ **Timing Measurements**: Valid RTT measurements returned
9. ✅ **JSON Output**: Correct JSON format output
10. ✅ **Clean Shutdown**: Container exits cleanly

## Expected Test Results

### Successful Test Output
The test framework will output timing results in JSON format:
```json
{
  "handshakePlusOneRTTMillis": 45.2,
  "pingRTTMilllis": 0.8
}
```

### Performance Benchmarks
- **Connection Time**: < 5 seconds
- **Handshake Time**: < 100ms
- **Ping RTT**: < 10ms (localhost)
- **Test Duration**: < 30 seconds per test

## Cleanup

### Post-Test Cleanup
```bash
# Clean up test containers
docker kill $(docker ps -q --filter ancestor=python-v0.2.9)
docker rm $(docker ps -aq --filter ancestor=python-v0.2.9)

# Clean up Redis
docker stop redis-test && docker rm redis-test

# Clean up test artifacts
rm -f test-results.log metrics.json test-report.*
```

### Maintenance
```bash
# Clean up old images
docker image prune -f

# Clean up old containers
docker container prune -f

# Clean up old volumes
docker volume prune -f
``` 
