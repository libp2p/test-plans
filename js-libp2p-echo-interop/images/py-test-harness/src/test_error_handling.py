"""Error handling and retry logic tests."""

import trio
import pytest
import time
import structlog
from unittest.mock import AsyncMock, patch, MagicMock
from .libp2p_client import (
    EchoClient, 
    ConnectionError, 
    ProtocolNegotiationError, 
    TimeoutError,
    NonRetryableError,
    exponential_backoff_retry
)
from .redis_coordinator import RedisCoordinator, RedisConnectionError, RedisTimeoutError
from .config import TestConfig

logger = structlog.get_logger(__name__)


@pytest.mark.error_handling
@pytest.mark.unit
async def test_exponential_backoff_retry_success():
    """Test exponential backoff retry succeeds on retry."""
    call_count = 0
    
    async def failing_func():
        nonlocal call_count
        call_count += 1
        if call_count < 3:
            raise ConnectionError("Temporary failure")
        return "success"
    
    start_time = time.time()
    result = await exponential_backoff_retry(
        failing_func,
        max_retries=3,
        base_delay=0.1,  # Short delay for testing
        backoff_factor=2.0,
        jitter=False
    )
    duration = time.time() - start_time
    
    assert result == "success"
    assert call_count == 3
    # Should have delays of ~0.1s and ~0.2s
    assert duration >= 0.3
    assert duration < 1.0


@pytest.mark.error_handling
@pytest.mark.unit
async def test_exponential_backoff_retry_exhausted():
    """Test exponential backoff retry fails after max retries."""
    call_count = 0
    
    async def always_failing_func():
        nonlocal call_count
        call_count += 1
        raise ConnectionError("Persistent failure")
    
    with pytest.raises(ConnectionError, match="Persistent failure"):
        await exponential_backoff_retry(
            always_failing_func,
            max_retries=2,
            base_delay=0.1,
            backoff_factor=2.0,
            jitter=False
        )
    
    assert call_count == 3  # Initial attempt + 2 retries


@pytest.mark.error_handling
@pytest.mark.unit
async def test_exponential_backoff_non_retryable_error():
    """Test exponential backoff doesn't retry non-retryable errors."""
    call_count = 0
    
    async def non_retryable_func():
        nonlocal call_count
        call_count += 1
        raise NonRetryableError("Should not retry")
    
    with pytest.raises(NonRetryableError, match="Should not retry"):
        await exponential_backoff_retry(
            non_retryable_func,
            max_retries=3,
            base_delay=0.1
        )
    
    assert call_count == 1  # Should not retry


@pytest.mark.error_handling
@pytest.mark.unit
async def test_multiaddr_parsing_validation():
    """Test multiaddr parsing with various invalid formats."""
    config = TestConfig()
    client = EchoClient(config)
    await client.start()
    
    # Test various invalid multiaddr formats
    invalid_addrs = [
        "",
        "invalid",
        "/ip4/127.0.0.1",  # Missing tcp and port
        "/ip4/127.0.0.1/tcp",  # Missing port
        "/ip4/127.0.0.1/tcp/abc/p2p/test",  # Invalid port
        "/ip4/127.0.0.1/tcp/-1/p2p/test",  # Invalid port
        "/ip4/127.0.0.1/tcp/99999/p2p/test",  # Invalid port
    ]
    
    for addr in invalid_addrs:
        with pytest.raises(NonRetryableError):
            client._parse_multiaddr(addr)
    
    # Test valid multiaddr
    valid_addr = "/ip4/127.0.0.1/tcp/12345/p2p/test"
    host, port = client._parse_multiaddr(valid_addr)
    assert host == "127.0.0.1"
    assert port == 12345
    
    await client.stop()


@pytest.mark.error_handling
@pytest.mark.unit
def test_config_validation():
    """Test configuration validation for error handling parameters."""
    # Test invalid timeout values
    with pytest.raises(ValueError, match="Connection timeout must be positive"):
        config = TestConfig(connection_timeout=0)
        config.validate_config()
    
    with pytest.raises(ValueError, match="Max retries must be non-negative"):
        config = TestConfig(max_retries=-1)
        config.validate_config()
    
    with pytest.raises(ValueError, match="Retry delay must be positive"):
        config = TestConfig(retry_delay=0)
        config.validate_config()
    
    with pytest.raises(ValueError, match="Retry backoff factor must be greater than 1.0"):
        config = TestConfig(retry_backoff_factor=1.0)
        config.validate_config()
    
    with pytest.raises(ValueError, match="Invalid log level"):
        config = TestConfig(log_level="INVALID")
        config.validate_config()
    
    # Test valid configuration
    config = TestConfig()
    config.validate_config()  # Should not raise


@pytest.mark.error_handling
@pytest.mark.unit
async def test_redis_coordinator_connection_retry():
    """Test Redis coordinator connection retry logic."""
    config = TestConfig(redis_addr="nonexistent:6379")
    coordinator = RedisCoordinator(config)
    
    # Should fail after retries
    with pytest.raises(RedisConnectionError):
        await coordinator.connect()


@pytest.mark.error_handling
@pytest.mark.unit
async def test_redis_coordinator_health_check():
    """Test Redis coordinator health check functionality."""
    config = TestConfig()
    coordinator = RedisCoordinator(config)
    
    # Test health check without connection
    assert await coordinator.health_check() == False
    
    # Mock successful connection and health check
    mock_redis = AsyncMock()
    mock_redis.ping.return_value = True
    
    with patch('redis.asyncio.from_url', return_value=mock_redis):
        await coordinator.connect()
        assert await coordinator.health_check() == True
        await coordinator.disconnect()


@pytest.mark.error_handling
@pytest.mark.unit
async def test_echo_client_lifecycle():
    """Test echo client start/stop lifecycle."""
    config = TestConfig()
    client = EchoClient(config)
    
    # Initially not started
    assert not client.started
    
    # Start client
    await client.start()
    assert client.started
    
    # Stop client
    await client.stop()
    assert not client.started


@pytest.mark.error_handling
@pytest.mark.unit
async def test_mock_stream_timeout_handling():
    """Test MockLibp2pStream timeout handling."""
    from .libp2p_client import MockLibp2pStream
    
    # Mock socket stream that times out
    mock_socket = AsyncMock()
    mock_socket.receive_some.side_effect = lambda n: trio.sleep(2)  # Long delay
    
    stream = MockLibp2pStream(mock_socket, timeout=0.5)
    
    # Test read timeout
    with pytest.raises(TimeoutError, match="Read operation timed out"):
        await stream.read(100)
    
    # Test write timeout
    mock_socket.send_all.side_effect = lambda data: trio.sleep(2)  # Long delay
    
    with pytest.raises(TimeoutError, match="Write operation timed out"):
        await stream.write(b"test")


@pytest.mark.error_handling
@pytest.mark.unit
async def test_mock_stream_connection_errors():
    """Test MockLibp2pStream connection error handling."""
    from .libp2p_client import MockLibp2pStream
    
    # Mock socket stream that breaks
    mock_socket = AsyncMock()
    mock_socket.receive_some.side_effect = trio.BrokenResourceError("Connection broken")
    
    stream = MockLibp2pStream(mock_socket)
    
    # Test read with broken connection
    with pytest.raises(ConnectionError, match="Connection broken during read"):
        await stream.read(100)
    
    # Test write with broken connection
    mock_socket.send_all.side_effect = trio.BrokenResourceError("Connection broken")
    
    with pytest.raises(ConnectionError, match="Connection broken during write"):
        await stream.write(b"test")


@pytest.mark.error_handling
@pytest.mark.integration
async def test_error_handling_integration():
    """Integration test for error handling components."""
    config = TestConfig(
        max_retries=2,
        retry_delay=0.1,
        connection_timeout=1
    )
    
    # Validate config
    config.validate_config()
    
    # Test client lifecycle
    client = EchoClient(config)
    await client.start()
    
    # Test invalid multiaddr handling
    with pytest.raises(NonRetryableError):
        await client.connect_and_echo("invalid", b"test")
    
    await client.stop()
    
    # Test Redis coordinator
    coordinator = RedisCoordinator(config)
    health_ok = await coordinator.health_check()
    assert health_ok == False  # No connection yet