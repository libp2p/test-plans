"""libp2p client implementation for Echo protocol testing."""

import trio
import structlog
import socket
import asyncio
import random
import math
from typing import Optional, List, Tuple
from .config import TestConfig

logger = structlog.get_logger(__name__)

ECHO_PROTOCOL_ID = "/echo/1.0.0"


class ConnectionError(Exception):
    """Raised when connection establishment fails."""
    pass


class ProtocolNegotiationError(Exception):
    """Raised when protocol negotiation fails."""
    pass


class TimeoutError(Exception):
    """Raised when operations timeout."""
    pass


class RetryableError(Exception):
    """Base class for errors that can be retried."""
    pass


class NonRetryableError(Exception):
    """Base class for errors that should not be retried."""
    pass


async def exponential_backoff_retry(
    func,
    max_retries: int = 3,
    base_delay: float = 1.0,
    max_delay: float = 60.0,
    backoff_factor: float = 2.0,
    jitter: bool = True,
    retryable_exceptions: Tuple = (ConnectionError, OSError, trio.BrokenResourceError),
    non_retryable_exceptions: Tuple = (NonRetryableError, ValueError, TypeError)
):
    """
    Retry a function with exponential backoff.
    
    Args:
        func: Async function to retry
        max_retries: Maximum number of retry attempts
        base_delay: Initial delay between retries in seconds
        max_delay: Maximum delay between retries in seconds
        backoff_factor: Factor to multiply delay by each retry
        jitter: Whether to add random jitter to delays
        retryable_exceptions: Exceptions that should trigger retries
        non_retryable_exceptions: Exceptions that should not be retried
    
    Returns:
        Result of the function call
        
    Raises:
        The last exception encountered if all retries fail
    """
    last_exception = None
    
    for attempt in range(max_retries + 1):
        try:
            return await func()
        except non_retryable_exceptions as e:
            logger.error(
                "Non-retryable error encountered",
                error=str(e),
                attempt=attempt + 1
            )
            raise
        except retryable_exceptions as e:
            last_exception = e
            
            if attempt == max_retries:
                logger.error(
                    "All retry attempts exhausted",
                    error=str(e),
                    total_attempts=attempt + 1,
                    max_retries=max_retries
                )
                raise
            
            # Calculate delay with exponential backoff
            delay = min(base_delay * (backoff_factor ** attempt), max_delay)
            
            # Add jitter to prevent thundering herd
            if jitter:
                delay = delay * (0.5 + random.random() * 0.5)
            
            logger.warning(
                "Retryable error encountered, retrying",
                error=str(e),
                attempt=attempt + 1,
                max_retries=max_retries,
                delay=delay
            )
            
            await trio.sleep(delay)
        except Exception as e:
            # Unexpected exception - log and re-raise
            logger.error(
                "Unexpected error during retry operation",
                error=str(e),
                attempt=attempt + 1
            )
            raise
    
    # This should never be reached, but just in case
    if last_exception:
        raise last_exception


class MockLibp2pStream:
    """Mock libp2p stream for testing purposes."""
    
    def __init__(self, socket_stream, timeout: float = 30.0):
        self.socket_stream = socket_stream
        self.timeout = timeout
        self._closed = False
    
    async def write(self, data: bytes) -> None:
        """Write data to the stream with timeout."""
        if self._closed:
            raise ConnectionError("Stream is closed")
        
        try:
            # Send length prefix followed by data
            length = len(data)
            length_bytes = length.to_bytes(4, byteorder='big')
            
            with trio.move_on_after(self.timeout) as cancel_scope:
                await self.socket_stream.send_all(length_bytes + data)
            
            if cancel_scope.cancelled_caught:
                raise TimeoutError(f"Write operation timed out after {self.timeout}s")
                
        except (trio.BrokenResourceError, trio.ClosedResourceError) as e:
            self._closed = True
            raise ConnectionError(f"Connection broken during write: {e}")
        except Exception as e:
            logger.error("Unexpected error during stream write", error=str(e))
            raise
    
    async def read(self, max_bytes: int) -> bytes:
        """Read data from the stream with timeout."""
        if self._closed:
            raise ConnectionError("Stream is closed")
        
        try:
            with trio.move_on_after(self.timeout) as cancel_scope:
                # Read length prefix first
                length_bytes = await self._receive_exactly(4)
                length = int.from_bytes(length_bytes, byteorder='big')
                
                # Read the actual data
                if length == 0:
                    return b""
                
                # Read up to max_bytes or the full message, whichever is smaller
                to_read = min(max_bytes, length)
                return await self._receive_exactly(to_read)
            
            if cancel_scope.cancelled_caught:
                raise TimeoutError(f"Read operation timed out after {self.timeout}s")
                
        except (trio.BrokenResourceError, trio.ClosedResourceError) as e:
            self._closed = True
            raise ConnectionError(f"Connection broken during read: {e}")
        except Exception as e:
            logger.error("Unexpected error during stream read", error=str(e))
            raise
    
    async def _receive_exactly(self, n: int) -> bytes:
        """Receive exactly n bytes from the socket with proper error handling."""
        data = b""
        while len(data) < n:
            try:
                chunk = await self.socket_stream.receive_some(n - len(data))
                if not chunk:
                    raise ConnectionError("Connection closed unexpectedly")
                data += chunk
            except (trio.BrokenResourceError, trio.ClosedResourceError):
                self._closed = True
                raise ConnectionError("Connection broken while receiving data")
        return data
    
    async def close(self) -> None:
        """Close the stream with proper cleanup."""
        if not self._closed:
            try:
                await self.socket_stream.aclose()
            except Exception as e:
                logger.warning("Error during stream close", error=str(e))
            finally:
                self._closed = True


class EchoClient:
    """Mock libp2p client for Echo protocol testing."""
    
    def __init__(self, config: TestConfig):
        self.config = config
        self.started = False
    
    async def start(self) -> None:
        """Initialize the mock client."""
        self.started = True
        logger.info("Started mock libp2p client")
    
    async def stop(self) -> None:
        """Stop the mock client."""
        self.started = False
        logger.info("Stopped mock libp2p client")
    
    def _parse_multiaddr(self, multiaddr: str) -> tuple[str, int]:
        """Parse multiaddr to extract host and port with validation."""
        try:
            # Simple parsing for /ip4/host/tcp/port/p2p/peerid format
            parts = multiaddr.strip().split('/')
            if len(parts) < 6 or parts[1] != 'ip4' or parts[3] != 'tcp':
                raise ValueError(f"Invalid multiaddr format: {multiaddr}")
            
            host = parts[2]
            port = int(parts[4])
            
            # Validate host and port
            if not host or port <= 0 or port > 65535:
                raise ValueError(f"Invalid host or port in multiaddr: {multiaddr}")
            
            return host, port
            
        except (IndexError, ValueError) as e:
            raise NonRetryableError(f"Failed to parse multiaddr '{multiaddr}': {e}")
    
    async def _establish_connection(self, host: str, port: int) -> MockLibp2pStream:
        """Establish connection with timeout and error handling."""
        try:
            logger.debug("Attempting to connect", host=host, port=port)
            
            with trio.move_on_after(self.config.connection_timeout) as cancel_scope:
                stream = await trio.open_tcp_stream(host, port)
            
            if cancel_scope.cancelled_caught:
                raise ConnectionError(f"Connection timeout after {self.config.connection_timeout}s")
            
            # Perform protocol negotiation simulation
            await self._negotiate_protocol(stream)
            
            return MockLibp2pStream(stream, timeout=self.config.test_timeout)
            
        except OSError as e:
            # Network-level errors (connection refused, network unreachable, etc.)
            raise ConnectionError(f"Network error connecting to {host}:{port}: {e}")
        except Exception as e:
            logger.error("Unexpected error during connection establishment", error=str(e))
            raise
    
    async def _negotiate_protocol(self, stream) -> None:
        """Simulate protocol negotiation with error handling."""
        try:
            # Simulate protocol negotiation handshake
            # In a real implementation, this would involve multistream-select
            protocol_bytes = ECHO_PROTOCOL_ID.encode('utf-8')
            
            with trio.move_on_after(5.0) as cancel_scope:  # 5s timeout for negotiation
                await stream.send_all(protocol_bytes + b'\n')
                # In real implementation, we'd wait for acknowledgment
                await trio.sleep(0.1)  # Simulate negotiation time
            
            if cancel_scope.cancelled_caught:
                raise ProtocolNegotiationError("Protocol negotiation timed out")
                
        except (trio.BrokenResourceError, trio.ClosedResourceError) as e:
            raise ProtocolNegotiationError(f"Connection broken during protocol negotiation: {e}")
        except Exception as e:
            raise ProtocolNegotiationError(f"Protocol negotiation failed: {e}")
    
    async def connect_and_echo(self, server_multiaddr: str, data: bytes) -> bytes:
        """Connect to server and perform echo test with retry logic."""
        if not self.started:
            raise RuntimeError("Client not started")
        
        async def _attempt_echo():
            # Parse multiaddr to get connection details
            host, port = self._parse_multiaddr(server_multiaddr)
            
            logger.info(
                "Connecting to server",
                multiaddr=server_multiaddr,
                host=host,
                port=port
            )
            
            # Establish connection with retry logic
            stream = await self._establish_connection(host, port)
            
            try:
                logger.info("Connected to server, performing echo test")
                
                # Send data and receive echo
                echo_data = await self._echo_data(stream, data)
                
                logger.info(
                    "Echo test completed",
                    sent_bytes=len(data),
                    received_bytes=len(echo_data)
                )
                
                return echo_data
                
            finally:
                # Ensure stream is always closed
                await stream.close()
        
        # Apply retry logic with exponential backoff
        return await exponential_backoff_retry(
            _attempt_echo,
            max_retries=self.config.max_retries,
            base_delay=self.config.retry_delay,
            retryable_exceptions=(ConnectionError, ProtocolNegotiationError, TimeoutError, OSError),
            non_retryable_exceptions=(NonRetryableError, ValueError, TypeError)
        )
    
    async def _echo_data(self, stream: MockLibp2pStream, data: bytes) -> bytes:
        """Send data and receive echo response with robust error handling."""
        try:
            # Send data with timeout
            await stream.write(data)
            
            # Read echo response with timeout
            # We expect to receive exactly the same amount of data we sent
            received_data = b""
            bytes_to_read = len(data)
            
            # Handle empty data case
            if bytes_to_read == 0:
                return await stream.read(0)
            
            # Read data in chunks with timeout protection
            while len(received_data) < bytes_to_read:
                chunk_size = min(8192, bytes_to_read - len(received_data))
                
                try:
                    chunk = await stream.read(chunk_size)
                    if not chunk:
                        raise ConnectionError("Unexpected end of stream")
                    received_data += chunk
                except TimeoutError:
                    logger.error(
                        "Timeout reading echo response",
                        expected_bytes=bytes_to_read,
                        received_bytes=len(received_data)
                    )
                    raise
            
            # Validate response length
            if len(received_data) != len(data):
                raise ValueError(
                    f"Echo response length mismatch: expected {len(data)}, got {len(received_data)}"
                )
            
            return received_data
            
        except (ConnectionError, TimeoutError, ValueError):
            # Re-raise known errors
            raise
        except Exception as e:
            logger.error("Unexpected error during echo data exchange", error=str(e))
            raise ConnectionError(f"Echo data exchange failed: {e}")
    
    async def concurrent_echo_test(
        self,
        server_multiaddr: str,
        test_data_list: List[bytes],
        max_concurrent: int = 5
    ) -> List[bytes]:
        """Perform concurrent echo tests with robust error handling."""
        if not self.started:
            raise RuntimeError("Client not started")
        
        results = []
        failed_count = 0
        
        async def echo_single_with_retry(data: bytes) -> bytes:
            """Single echo test with retry logic."""
            return await self.connect_and_echo(server_multiaddr, data)
        
        # Use trio nursery for structured concurrency
        async with trio.open_nursery() as nursery:
            # Limit concurrency using semaphore
            semaphore = trio.Semaphore(max_concurrent)
            
            async def limited_echo(data: bytes, result_index: int):
                async with semaphore:
                    try:
                        result = await echo_single_with_retry(data)
                        results.append((result_index, result))
                        logger.debug(f"Concurrent echo {result_index} succeeded")
                    except Exception as e:
                        nonlocal failed_count
                        failed_count += 1
                        logger.error(
                            f"Concurrent echo failed for index {result_index}",
                            error=str(e),
                            error_type=type(e).__name__
                        )
                        results.append((result_index, None))
            
            # Start all echo tasks
            for i, data in enumerate(test_data_list):
                nursery.start_soon(limited_echo, data, i)
        
        # Log summary of concurrent test results
        success_count = len(test_data_list) - failed_count
        logger.info(
            "Concurrent echo test completed",
            total_tests=len(test_data_list),
            successful=success_count,
            failed=failed_count
        )
        
        # Sort results by original index and extract data
        results.sort(key=lambda x: x[0])
        return [result[1] for result in results]


async def create_echo_client(config: TestConfig) -> EchoClient:
    """Create and start an echo client with proper resource management."""
    client = EchoClient(config)
    await client.start()
    return client