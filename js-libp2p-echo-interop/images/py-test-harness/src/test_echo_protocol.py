"""Echo protocol interoperability tests."""

import trio
import pytest
import time
import structlog
from .libp2p_client import EchoClient
from .config import TestConfig

logger = structlog.get_logger(__name__)


@pytest.mark.echo
@pytest.mark.unit
async def test_basic_echo(
    echo_client: EchoClient,
    server_multiaddr: str,
    test_data_small: bytes
):
    """Test basic echo functionality with small text payload.
    
    Validates: Requirements 4.1
    """
    start_time = time.time()
    
    try:
        # Perform echo test
        echo_data = await echo_client.connect_and_echo(server_multiaddr, test_data_small)
        
        # Validate response
        assert echo_data == test_data_small, f"Echo mismatch: sent {test_data_small!r}, got {echo_data!r}"
        
        logger.info(
            "Basic echo test passed",
            sent_bytes=len(test_data_small),
            received_bytes=len(echo_data)
        )
        
    except Exception as e:
        logger.error("Basic echo test failed", error=str(e))
        raise
    finally:
        duration = time.time() - start_time
        logger.info("Basic echo test completed", duration=duration)


@pytest.mark.echo
@pytest.mark.unit
@pytest.mark.payload_size(256)
async def test_binary_echo(
    echo_client: EchoClient,
    server_multiaddr: str,
    test_data_binary: bytes
):
    """Test echo functionality with binary payload.
    
    Validates: Requirements 4.2
    """
    start_time = time.time()
    
    try:
        # Perform echo test with binary data
        echo_data = await echo_client.connect_and_echo(server_multiaddr, test_data_binary)
        
        # Validate byte-perfect response
        assert echo_data == test_data_binary, "Binary echo data mismatch"
        assert len(echo_data) == len(test_data_binary), "Binary echo length mismatch"
        
        # Verify all byte values are preserved
        for i, (sent_byte, received_byte) in enumerate(zip(test_data_binary, echo_data)):
            assert sent_byte == received_byte, f"Byte mismatch at position {i}: sent {sent_byte}, got {received_byte}"
        
        logger.info(
            "Binary echo test passed",
            sent_bytes=len(test_data_binary),
            received_bytes=len(echo_data)
        )
        
    except Exception as e:
        logger.error("Binary echo test failed", error=str(e))
        raise
    finally:
        duration = time.time() - start_time
        logger.info("Binary echo test completed", duration=duration)


@pytest.mark.echo
@pytest.mark.slow
@pytest.mark.payload_size(1048576)  # 1MB
async def test_large_payload_echo(
    echo_client: EchoClient,
    server_multiaddr: str,
    test_data_large: bytes
):
    """Test echo functionality with large payload (1MB).
    
    Validates: Requirements 4.3
    """
    start_time = time.time()
    
    try:
        # Perform echo test with large payload
        echo_data = await echo_client.connect_and_echo(server_multiaddr, test_data_large)
        
        # Validate complete response
        assert echo_data == test_data_large, "Large payload echo data mismatch"
        assert len(echo_data) == len(test_data_large), "Large payload echo length mismatch"
        assert len(echo_data) == 1024 * 1024, "Expected exactly 1MB response"
        
        logger.info(
            "Large payload echo test passed",
            sent_bytes=len(test_data_large),
            received_bytes=len(echo_data)
        )
        
    except Exception as e:
        logger.error("Large payload echo test failed", error=str(e))
        raise
    finally:
        duration = time.time() - start_time
        logger.info("Large payload echo test completed", duration=duration)


@pytest.mark.echo
@pytest.mark.integration
@pytest.mark.stream_count(5)
async def test_concurrent_streams_echo(
    echo_client: EchoClient,
    server_multiaddr: str,
    concurrent_test_data: list[bytes]
):
    """Test concurrent echo streams for independence.
    
    Validates: Requirements 4.4
    """
    start_time = time.time()
    
    try:
        # Perform concurrent echo tests
        results = await echo_client.concurrent_echo_test(
            server_multiaddr,
            concurrent_test_data,
            max_concurrent=5
        )
        
        # Validate all results
        assert len(results) == len(concurrent_test_data), "Missing concurrent test results"
        
        for i, (sent_data, received_data) in enumerate(zip(concurrent_test_data, results)):
            assert received_data is not None, f"Concurrent test {i} failed"
            assert received_data == sent_data, f"Concurrent test {i} data mismatch"
        
        logger.info(
            "Concurrent streams echo test passed",
            stream_count=len(concurrent_test_data),
            total_bytes_sent=sum(len(data) for data in concurrent_test_data),
            total_bytes_received=sum(len(data) for data in results if data)
        )
        
    except Exception as e:
        logger.error("Concurrent streams echo test failed", error=str(e))
        raise
    finally:
        duration = time.time() - start_time
        logger.info("Concurrent streams echo test completed", duration=duration)


@pytest.mark.echo
@pytest.mark.integration
async def test_connection_establishment(
    echo_client: EchoClient,
    server_multiaddr: str,
    test_config: TestConfig
):
    """Test connection establishment with configured protocol stack.
    
    Validates: Requirements 3.1, 3.2, 3.3, 3.4
    """
    start_time = time.time()
    
    try:
        # Test simple connection and protocol negotiation
        test_data = b"Connection test"
        echo_data = await echo_client.connect_and_echo(server_multiaddr, test_data)
        
        # Validate connection worked with configured protocols
        assert echo_data == test_data, "Connection establishment test failed"
        
        logger.info(
            "Connection establishment test passed",
            transport=test_config.transport.value,
            security=test_config.security.value,
            muxer=test_config.muxer.value
        )
        
    except Exception as e:
        logger.error("Connection establishment test failed", error=str(e))
        raise
    finally:
        duration = time.time() - start_time
        logger.info("Connection establishment test completed", duration=duration)


@pytest.mark.echo
@pytest.mark.unit
async def test_empty_payload_echo(
    echo_client: EchoClient,
    server_multiaddr: str
):
    """Test echo functionality with empty payload.
    
    Edge case test for empty data handling.
    """
    start_time = time.time()
    
    try:
        # Test empty payload
        empty_data = b""
        echo_data = await echo_client.connect_and_echo(server_multiaddr, empty_data)
        
        # Validate empty response
        assert echo_data == empty_data, "Empty payload echo failed"
        assert len(echo_data) == 0, "Expected empty response"
        
        logger.info("Empty payload echo test passed")
        
    except Exception as e:
        logger.error("Empty payload echo test failed", error=str(e))
        raise
    finally:
        duration = time.time() - start_time
        logger.info("Empty payload echo test completed", duration=duration)


@pytest.mark.echo
@pytest.mark.unit
async def test_protocol_negotiation(
    echo_client: EchoClient,
    server_multiaddr: str
):
    """Test Echo protocol negotiation.
    
    Validates: Requirements 1.2
    """
    start_time = time.time()
    
    try:
        # Test protocol negotiation by attempting connection
        test_data = b"Protocol negotiation test"
        echo_data = await echo_client.connect_and_echo(server_multiaddr, test_data)
        
        # If we get here, protocol negotiation succeeded
        assert echo_data == test_data, "Protocol negotiation test failed"
        
        logger.info("Protocol negotiation test passed")
        
    except Exception as e:
        logger.error("Protocol negotiation test failed", error=str(e))
        raise
    finally:
        duration = time.time() - start_time
        logger.info("Protocol negotiation test completed", duration=duration)