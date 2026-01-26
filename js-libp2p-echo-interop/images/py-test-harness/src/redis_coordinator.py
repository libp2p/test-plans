"""Redis coordination for multiaddr retrieval."""

import trio
import redis.asyncio as redis
import structlog
from typing import Optional
from .config import TestConfig

logger = structlog.get_logger(__name__)


class RedisConnectionError(Exception):
    """Raised when Redis connection fails."""
    pass


class RedisTimeoutError(Exception):
    """Raised when Redis operations timeout."""
    pass


class RedisCoordinator:
    """Handles Redis coordination for multiaddr retrieval."""
    
    def __init__(self, config: TestConfig):
        self.config = config
        self.redis_client: Optional[redis.Redis] = None
        self._connection_retries = 0
        self._max_connection_retries = 3
    
    async def connect(self) -> None:
        """Connect to Redis server with retry logic."""
        for attempt in range(self._max_connection_retries):
            try:
                # Parse Redis address
                if "://" in self.config.redis_addr:
                    redis_url = self.config.redis_addr
                else:
                    redis_url = f"redis://{self.config.redis_addr}"
                
                self.redis_client = redis.from_url(
                    redis_url,
                    decode_responses=True,
                    socket_connect_timeout=5,
                    socket_timeout=5,
                    retry_on_timeout=True,
                    health_check_interval=30
                )
                
                # Test connection with timeout
                with trio.move_on_after(10.0) as cancel_scope:
                    await self.redis_client.ping()
                
                if cancel_scope.cancelled_caught:
                    raise RedisTimeoutError("Redis ping timeout")
                
                logger.info("Connected to Redis", redis_addr=self.config.redis_addr)
                return
                
            except (redis.ConnectionError, redis.TimeoutError, OSError) as e:
                self._connection_retries = attempt + 1
                
                if attempt == self._max_connection_retries - 1:
                    logger.error(
                        "Failed to connect to Redis after all retries",
                        error=str(e),
                        attempts=self._connection_retries
                    )
                    raise RedisConnectionError(f"Redis connection failed: {e}")
                
                delay = 2 ** attempt  # Exponential backoff: 1s, 2s, 4s
                logger.warning(
                    "Redis connection failed, retrying",
                    error=str(e),
                    attempt=attempt + 1,
                    max_retries=self._max_connection_retries,
                    delay=delay
                )
                await trio.sleep(delay)
            
            except Exception as e:
                logger.error("Unexpected error connecting to Redis", error=str(e))
                raise RedisConnectionError(f"Unexpected Redis connection error: {e}")
    
    async def disconnect(self) -> None:
        """Disconnect from Redis server with proper cleanup."""
        if self.redis_client:
            try:
                await self.redis_client.close()
                logger.info("Disconnected from Redis")
            except Exception as e:
                logger.warning("Error during Redis disconnect", error=str(e))
            finally:
                self.redis_client = None
    
    async def get_multiaddr(self) -> str:
        """Retrieve multiaddr from Redis with timeout and retries."""
        if not self.redis_client:
            raise RuntimeError("Redis client not connected")
        
        logger.info(
            "Waiting for multiaddr from Redis",
            key=self.config.redis_key,
            timeout=self.config.redis_timeout
        )
        
        try:
            # Use BLPOP to block until multiaddr is available
            with trio.move_on_after(self.config.redis_timeout + 5) as cancel_scope:
                result = await self.redis_client.blpop(
                    self.config.redis_key,
                    timeout=self.config.redis_timeout
                )
            
            if cancel_scope.cancelled_caught:
                raise RedisTimeoutError(
                    f"Redis operation timed out after {self.config.redis_timeout + 5}s"
                )
            
            if result is None:
                raise RedisTimeoutError(
                    f"Timeout waiting for multiaddr after {self.config.redis_timeout}s"
                )
            
            _, multiaddr = result
            
            # Validate multiaddr format
            if not multiaddr or not isinstance(multiaddr, str):
                raise ValueError(f"Invalid multiaddr received from Redis: {multiaddr}")
            
            logger.info("Retrieved multiaddr from Redis", multiaddr=multiaddr)
            return multiaddr
            
        except (redis.ConnectionError, redis.TimeoutError) as e:
            logger.error("Redis connection error during multiaddr retrieval", error=str(e))
            raise RedisConnectionError(f"Redis error: {e}")
        except RedisTimeoutError:
            # Re-raise timeout errors
            raise
        except Exception as e:
            logger.error("Unexpected error retrieving multiaddr from Redis", error=str(e))
            raise RedisConnectionError(f"Unexpected Redis error: {e}")
    
    async def publish_multiaddr(self, multiaddr: str) -> None:
        """Publish multiaddr to Redis with error handling."""
        if not self.redis_client:
            raise RuntimeError("Redis client not connected")
        
        if not multiaddr or not isinstance(multiaddr, str):
            raise ValueError(f"Invalid multiaddr to publish: {multiaddr}")
        
        try:
            with trio.move_on_after(10.0) as cancel_scope:
                await self.redis_client.rpush(self.config.redis_key, multiaddr)
            
            if cancel_scope.cancelled_caught:
                raise RedisTimeoutError("Redis publish operation timed out")
            
            logger.info("Published multiaddr to Redis", multiaddr=multiaddr)
            
        except (redis.ConnectionError, redis.TimeoutError) as e:
            logger.error("Redis error during multiaddr publish", error=str(e))
            raise RedisConnectionError(f"Redis publish error: {e}")
        except Exception as e:
            logger.error("Unexpected error publishing multiaddr to Redis", error=str(e))
            raise RedisConnectionError(f"Unexpected Redis publish error: {e}")
    
    async def clear_multiaddr(self) -> None:
        """Clear multiaddr from Redis with error handling."""
        if not self.redis_client:
            raise RuntimeError("Redis client not connected")
        
        try:
            with trio.move_on_after(10.0) as cancel_scope:
                await self.redis_client.delete(self.config.redis_key)
            
            if cancel_scope.cancelled_caught:
                raise RedisTimeoutError("Redis clear operation timed out")
            
            logger.info("Cleared multiaddr from Redis")
            
        except (redis.ConnectionError, redis.TimeoutError) as e:
            logger.error("Redis error during multiaddr clear", error=str(e))
            raise RedisConnectionError(f"Redis clear error: {e}")
        except Exception as e:
            logger.error("Unexpected error clearing multiaddr from Redis", error=str(e))
            raise RedisConnectionError(f"Unexpected Redis clear error: {e}")
    
    async def health_check(self) -> bool:
        """Check Redis connection health."""
        if not self.redis_client:
            return False
        
        try:
            with trio.move_on_after(5.0) as cancel_scope:
                await self.redis_client.ping()
            
            if cancel_scope.cancelled_caught:
                logger.warning("Redis health check timed out")
                return False
            
            return True
            
        except Exception as e:
            logger.warning("Redis health check failed", error=str(e))
            return False


async def get_server_multiaddr(config: TestConfig) -> str:
    """Convenience function to get server multiaddr with proper resource management and retry logic."""
    coordinator = RedisCoordinator(config)
    
    max_attempts = 3
    for attempt in range(max_attempts):
        try:
            await coordinator.connect()
            return await coordinator.get_multiaddr()
        except (RedisConnectionError, RedisTimeoutError) as e:
            if attempt == max_attempts - 1:
                logger.error(
                    "Failed to get server multiaddr after all attempts",
                    error=str(e),
                    attempts=attempt + 1
                )
                raise
            
            delay = 2 ** attempt  # Exponential backoff
            logger.warning(
                "Failed to get multiaddr, retrying",
                error=str(e),
                attempt=attempt + 1,
                delay=delay
            )
            await trio.sleep(delay)
        except Exception as e:
            logger.error("Unexpected error getting server multiaddr", error=str(e))
            raise
        finally:
            await coordinator.disconnect()