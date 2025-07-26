# Redis Coordination in Transport-Interop Ping Tests

This document explains the role of Redis as a coordination mechanism in the transport-interop ping tests and how it enables communication between dialer and listener components.

## Table of Contents

- [Overview](#overview)
- [Test Architecture](#test-architecture)
- [Redis Role](#redis-role)
- [Step-by-Step Process](#step-by-step-process)
- [Redis Commands Used](#redis-commands-used)
- [Why Redis is Needed](#why-redis-is-needed)
- [Data Structure](#data-structure)
- [Configuration](#configuration)
- [Alternative Approaches](#alternative-approaches)
- [Real-World Example](#real-world-example)
- [Monitoring and Debugging](#monitoring-and-debugging)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)

## Overview

Redis serves as a **coordination mechanism** between the dialer and listener components in transport-interop ping tests. It acts as a **message broker** that allows the two components to discover each other and exchange connection information in a distributed testing environment.

## Test Architecture

```
┌─────────────┐    Redis    ┌─────────────┐
│   Dialer    │◄──────────► │  Listener   │
│ (Client)    │             │  (Server)   │
└─────────────┘             └─────────────┘
```

### Component Roles

- **Listener**: Creates a libp2p host, starts listening, and publishes its address to Redis
- **Dialer**: Retrieves the listener's address from Redis and establishes a connection
- **Redis**: Acts as a central coordination point for address exchange

## Redis Role

### Primary Functions

1. **Service Discovery**: Enables the dialer to find the listener's address
2. **Message Broker**: Provides reliable messaging for address exchange
3. **Coordination Point**: Centralized location for test components to communicate
4. **Timeout Handling**: Supports graceful failure when components are unavailable

### Key Benefits

- ✅ **Asynchronous Discovery**: Listener can publish its address before dialer starts
- ✅ **Reliable Messaging**: Redis ensures the address is delivered
- ✅ **Timeout Handling**: Dialer can fail gracefully if no listener is available
- ✅ **Multiple Listeners**: Can support multiple listeners (though typically one per test)
- ✅ **Distributed Testing**: Enables testing across different machines/containers

## Step-by-Step Process

### Step 1: Listener Starts

```python
# Listener publishes its address to Redis
addr_str = str(addrs[0])  # e.g., "/ip4/0.0.0.0/tcp/34827/p2p/16Uiu2HAkvpyXQ1BuqHbLKASmVe5tLZrQKxgKL75crGV2fVNNBcRF"
print(f"Publishing address to Redis: {addr_str}", file=sys.stderr)
self.redis_client.rpush("listenerAddr", addr_str)
```

**What happens:**
1. Listener creates a libp2p host and starts listening
2. Gets its own multiaddr (IP + port + peer ID)
3. Publishes this address to Redis using `RPUSH` on the `listenerAddr` key
4. Waits for incoming connections

### Step 2: Dialer Starts

```python
# Dialer retrieves listener address from Redis
print("Waiting for listener address from Redis...", file=sys.stderr)
result = self.redis_client.blpop("listenerAddr", timeout=self.test_timeout_seconds)
if not result:
    raise RuntimeError("Timeout waiting for listener address")

listener_addr = result[1]  # Gets the multiaddr from Redis
print(f"Got listener address: {listener_addr}", file=sys.stderr)
```

**What happens:**
1. Dialer starts and connects to Redis
2. Uses `BLPOP` to wait for a listener address (blocking operation)
3. Once it gets the address, it can connect to the listener

### Step 3: Connection Establishment

```python
# Dialer connects to the listener using the retrieved address
maddr = multiaddr.Multiaddr(listener_addr)
info = info_from_p2p_addr(maddr)
await self.host.connect(info)
```

## Redis Commands Used

### Listener Side

```python
# Publish address to Redis
self.redis_client.rpush("listenerAddr", addr_str)
```

- **`RPUSH`**: Adds the listener's multiaddr to the right end of the `listenerAddr` list
- This makes the address available for the dialer to consume

### Dialer Side

```python
# Retrieve address from Redis
result = self.redis_client.blpop("listenerAddr", timeout=self.test_timeout_seconds)
```

- **`BLPOP`**: Blocking left pop - waits for an item to become available in the `listenerAddr` list
- **`timeout`**: Prevents infinite waiting if no listener is available
- Returns `(key, value)` tuple or `None` if timeout

## Why Redis is Needed

### The Problem

In a distributed test environment, the dialer and listener are typically:
- **Separate processes/containers**
- **Running on different machines**
- **Started independently**
- **Need to discover each other**

### The Solution

Redis provides a **centralized coordination point** that allows:
- **Asynchronous discovery**: Listener can publish its address before dialer starts
- **Reliable messaging**: Redis ensures the address is delivered
- **Timeout handling**: Dialer can fail gracefully if no listener is available
- **Multiple listeners**: Can support multiple listeners (though typically one per test)

## Data Structure

```
Redis Database:
┌─────────────────┐
│ listenerAddr    │ ← List containing listener addresses
│ ├─ "/ip4/0.0.0.0/tcp/34827/p2p/16Uiu2HAkvpyXQ1BuqHbLKASmVe5tLZrQKxgKL75crGV2fVNNBcRF"
│ └─ "/ip4/0.0.0.0/tcp/38635/p2p/16Uiu2HAm4dpssgmwrXdXjpgyxNnKoXAfhYD8GnNmaJ315E19N43w"
└─────────────────┘
```

### Multiaddr Format

The addresses stored in Redis follow the libp2p multiaddr format:
```
/ip4/0.0.0.0/tcp/34827/p2p/16Uiu2HAkvpyXQ1BuqHbLKASmVe5tLZrQKxgKL75crGV2fVNNBcRF
│   │        │   │    │   │
│   │        │   │    │   └─ Peer ID (libp2p identifier)
│   │        │   │    └─ Protocol (/p2p)
│   │        │   └─ Port number
│   │        └─ Protocol (/tcp)
│   └─ IP address
└─ Protocol (/ip4)
```

## Configuration

### Environment Variables

```bash
-e redis_addr=localhost:6379  # Redis server address
-e test_timeout_seconds=10    # Timeout for waiting for listener
```

### Redis Connection Setup

```python
def setup_redis(self) -> None:
    """Set up Redis connection."""
    self.redis_client = redis.Redis(
        host=self.redis_host,      # e.g., "localhost"
        port=self.redis_port,      # e.g., 6379
        decode_responses=True      # Return strings instead of bytes
    )
    self.redis_client.ping()       # Test connection
```

### Redis Server Setup

```bash
# Start Redis server
docker run -d --name redis-test -p 6379:6379 redis:alpine

# Or using docker-compose
version: '3.8'
services:
  redis:
    image: redis:alpine
    ports:
      - "6379:6379"
```

## Alternative Approaches

### Other Coordination Methods

1. **Static Configuration**: Hardcode listener address (not flexible)
2. **DNS**: Use DNS for service discovery (requires infrastructure)
3. **Service Mesh**: Use Kubernetes services (complex setup)
4. **Direct Connection**: Dialer connects to known listener (not realistic for testing)
5. **Message Queues**: Use RabbitMQ, Apache Kafka (overkill for simple coordination)
6. **Database**: Use PostgreSQL, MySQL (slower, more complex)

### Why Redis is Ideal

- ✅ **Simple**: Easy to set up and use
- ✅ **Fast**: In-memory, low latency
- ✅ **Reliable**: Persistence and replication options
- ✅ **Flexible**: Supports various data structures
- ✅ **Lightweight**: Minimal resource usage
- ✅ **Standard**: Widely used in testing scenarios
- ✅ **Atomic Operations**: Built-in support for atomic list operations

## Real-World Example

### Complete Test Flow

```bash
# Terminal 1: Start Redis
docker run -d --name redis-test -p 6379:6379 redis:alpine

# Terminal 2: Start Listener
docker run --rm --network host \
  -e transport=tcp -e muxer=yamux -e security=noise \
  -e is_dialer=false -e ip="0.0.0.0" \
  -e redis_addr=localhost:6379 \
  python-v0.2.9 python ping_test.py

# Output:
# Connected to Redis at localhost:6379
# Running as listener
# Publishing address to Redis: /ip4/0.0.0.0/tcp/34827/p2p/16Uiu2HAkvpyXQ1BuqHbLKASmVe5tLZrQKxgKL75crGV2fVNNBcRF
# Waiting for 15 seconds...

# Terminal 3: Start Dialer
docker run --rm --network host \
  -e transport=tcp -e muxer=yamux -e security=noise \
  -e is_dialer=true \
  -e redis_addr=localhost:6379 \
  python-v0.2.9 python ping_test.py

# Output:
# Connected to Redis at localhost:6379
# Running as dialer
# Waiting for listener address from Redis...
# Got listener address: /ip4/0.0.0.0/tcp/34827/p2p/16Uiu2HAkvpyXQ1BuqHbLKASmVe5tLZrQKxgKL75crGV2fVNNBcRF
# Connecting to /ip4/0.0.0.0/tcp/34827/p2p/16Uiu2HAkvpyXQ1BuqHbLKASmVe5tLZrQKxgKL75crGV2fVNNBcRF
# Creating ping stream
# sending ping to 16Uiu2HAkvpyXQ1BuqHbLKASmVe5tLZrQKxgKL75crGV2fVNNBcRF
# received pong from 16Uiu2HAkvpyXQ1BuqHbLKASmVe5tLZrQKxgKL75crGV2fVNNBcRF
# {"handshakePlusOneRTTMillis": 10.88, "pingRTTMilllis": 0.26}
```

### Redis Data Flow

```
Time 0: Redis starts (empty)
Time 1: Listener starts → RPUSH listenerAddr "/ip4/0.0.0.0/tcp/34827/p2p/16Uiu2HAkvpyXQ1BuqHbLKASmVe5tLZrQKxgKL75crGV2fVNNBcRF"
Time 2: Dialer starts → BLPOP listenerAddr → Gets address
Time 3: Dialer connects to listener using retrieved address
Time 4: Ping/pong exchange occurs
```

## Monitoring and Debugging

### Redis CLI Commands

```bash
# Connect to Redis CLI
docker exec -it redis-test redis-cli

# Monitor Redis commands in real-time
MONITOR

# Check what's in the listenerAddr list
LRANGE listenerAddr 0 -1

# Check list length
LLEN listenerAddr

# Clear the list (for testing)
DEL listenerAddr

# Check Redis info
INFO

# Check memory usage
INFO memory
```

### Debugging Commands

```bash
# Check if Redis is running
docker ps | grep redis

# Check Redis logs
docker logs redis-test

# Test Redis connection
docker exec redis-test redis-cli ping

# Monitor Redis activity during test
docker exec redis-test redis-cli monitor
```

### Common Redis Operations

```bash
# List all keys
KEYS *

# Get value of a key
GET keyname

# Set a key value
SET keyname value

# Delete a key
DEL keyname

# Check if key exists
EXISTS keyname

# Set key expiration (seconds)
EXPIRE keyname 60
```

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

#### Issue 2: Timeout Waiting for Listener
**Symptoms:**
```
Error: Timeout waiting for listener address
```

**Solutions:**
```bash
# Check if listener is running
docker ps | grep python-v0.2.9

# Check Redis for listener address
docker exec redis-test redis-cli LRANGE listenerAddr 0 -1

# Increase timeout
-e test_timeout_seconds=30
```

#### Issue 3: Redis Permission Denied
**Symptoms:**
```
Error: Permission denied
```

**Solutions:**
```bash
# Check Redis configuration
docker exec redis-test redis-cli CONFIG GET bind

# Restart Redis with proper permissions
docker stop redis-test && docker rm redis-test
docker run -d --name redis-test -p 6379:6379 redis:alpine
```

### Performance Issues

#### High Latency
```bash
# Check Redis performance
docker exec redis-test redis-cli INFO stats

# Monitor Redis memory usage
docker exec redis-test redis-cli INFO memory

# Check Redis connections
docker exec redis-test redis-cli INFO clients
```

#### Memory Issues
```bash
# Check Redis memory usage
docker exec redis-test redis-cli INFO memory

# Clear old data
docker exec redis-test redis-cli FLUSHDB

# Restart Redis
docker restart redis-test
```

## Best Practices

### Redis Configuration

1. **Use Appropriate Timeouts**: Set reasonable timeouts for BLPOP operations
2. **Monitor Memory Usage**: Redis is in-memory, so monitor usage
3. **Use Connection Pooling**: For high-throughput scenarios
4. **Enable Persistence**: If data loss is critical
5. **Set Memory Limits**: Prevent Redis from consuming too much memory

### Test Configuration

1. **Use Unique Keys**: Avoid conflicts between different test runs
2. **Clean Up After Tests**: Remove test data from Redis
3. **Handle Timeouts Gracefully**: Implement proper error handling
4. **Log Redis Operations**: For debugging purposes
5. **Use Health Checks**: Verify Redis is available before starting tests

### Security Considerations

1. **Network Security**: Restrict Redis access to test network
2. **Authentication**: Use Redis AUTH if needed
3. **Encryption**: Use Redis with TLS for sensitive environments
4. **Access Control**: Limit Redis access to test containers only

### Production Considerations

1. **High Availability**: Use Redis Cluster or Sentinel
2. **Backup Strategy**: Implement Redis backup procedures
3. **Monitoring**: Use Redis monitoring tools
4. **Scaling**: Plan for Redis scaling as test load increases

## Summary

Redis acts as a **service discovery mechanism** that:
1. **Enables coordination** between independent dialer and listener processes
2. **Provides reliable messaging** for address exchange
3. **Supports timeout handling** for robust test execution
4. **Allows flexible deployment** in various environments
5. **Enables the transport-interop framework** to orchestrate tests across different libp2p implementations

Without Redis, the dialer wouldn't know where to find the listener, making the ping test impossible to execute in a distributed environment. Redis provides the essential coordination layer that makes distributed testing possible and reliable.

## References

- [Redis Documentation](https://redis.io/documentation)
- [Redis Commands](https://redis.io/commands)
- [libp2p Multiaddr Specification](https://github.com/multiformats/multiaddr)
- [Transport-Interop Framework](https://github.com/libp2p/test-plans) 