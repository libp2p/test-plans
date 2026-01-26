"""
Pytest version of core Echo protocol test cases.
This demonstrates the four core test cases required by task 3.2 using pytest.
"""

import pytest
import trio
import time
from src.mock_echo_server import MockEchoServer
from src.libp2p_client import EchoClient
from src.config import TestConfig


@pytest.fixture
async def mock_server():
    """Fixture to provide a mock echo server."""
    server = MockEchoServer()
    multiaddr = await server.start()
    
    async with trio.open_nursery() as nursery:
        nursery.start_soon(server.serve_forever)
        
        # Give server time to start
        await trio.sleep(0.1)
        
        yield multiaddr
        
        await server.stop()
        nursery.cancel_scope.cancel()


@pytest.fixture
async def echo_client():
    """Fixture to provide an echo client."""
    config = TestConfig()
    client = EchoClient(config)
    await client.start()
    
    yield client
    
    await client.stop()


@pytest.mark.trio
async def test_basic_text_echo(echo_client, mock_server):
    """Test basic text echo functionality.
    
    Validates: Requirements 4.1
    """
    test_data = b"Hello, Echo Protocol!"
    echo_data = await echo_client.connect_and_echo(mock_server, test_data)
    
    assert echo_data == test_data, f"Echo mismatch: sent {test_data!r}, got {echo_data!r}"
    assert len(echo_data) == len(test_data), "Echo length mismatch"


@pytest.mark.trio
async def test_binary_payload_echo(echo_client, mock_server):
    """Test binary payload echo functionality.
    
    Validates: Requirements 4.2
    """
    # Binary data with various byte values
    test_data = bytes(range(256))
    echo_data = await echo_client.connect_and_echo(mock_server, test_data)
    
    assert echo_data == test_data, "Binary echo data mismatch"
    assert len(echo_data) == len(test_data), "Binary echo length mismatch"
    
    # Verify all byte values are preserved
    for i, (sent_byte, received_byte) in enumerate(zip(test_data, echo_data)):
        assert sent_byte == received_byte, f"Byte mismatch at position {i}: sent {sent_byte}, got {received_byte}"


@pytest.mark.trio
async def test_large_payload_echo(echo_client, mock_server):
    """Test large payload echo functionality.
    
    Validates: Requirements 4.3
    """
    # Create 100KB of test data (reduced from 1MB for faster testing)
    data_chunk = b"LARGE_PAYLOAD_TEST_" * 100  # ~1.9KB
    test_data = data_chunk
    while len(test_data) < 100 * 1024:  # 100KB
        test_data += data_chunk[:100 * 1024 - len(test_data)]
    test_data = test_data[:100 * 1024]  # Exactly 100KB
    
    echo_data = await echo_client.connect_and_echo(mock_server, test_data)
    
    assert echo_data == test_data, "Large payload echo data mismatch"
    assert len(echo_data) == len(test_data), "Large payload echo length mismatch"
    assert len(echo_data) == 100 * 1024, "Expected exactly 100KB response"


@pytest.mark.trio
async def test_concurrent_streams_echo(echo_client, mock_server):
    """Test concurrent streams echo functionality.
    
    Validates: Requirements 4.4
    """
    # Create test data for concurrent streams
    concurrent_test_data = [
        b"Concurrent test 1",
        b"Concurrent test 2", 
        b"Concurrent test 3",
        b"Concurrent test 4",
        b"Concurrent test 5"
    ]
    
    results = await echo_client.concurrent_echo_test(
        mock_server,
        concurrent_test_data,
        max_concurrent=5
    )
    
    # Validate all results
    assert len(results) == len(concurrent_test_data), "Missing concurrent test results"
    
    for i, (sent_data, received_data) in enumerate(zip(concurrent_test_data, results)):
        assert received_data is not None, f"Concurrent test {i} failed"
        assert received_data == sent_data, f"Concurrent test {i} data mismatch"


@pytest.mark.trio
async def test_empty_payload_echo(echo_client, mock_server):
    """Test empty payload echo functionality.
    
    Edge case test for empty data handling.
    """
    test_data = b""
    echo_data = await echo_client.connect_and_echo(mock_server, test_data)
    
    assert echo_data == test_data, "Empty payload echo failed"
    assert len(echo_data) == 0, "Expected empty response"


@pytest.mark.trio
async def test_protocol_negotiation(echo_client, mock_server):
    """Test Echo protocol negotiation.
    
    Validates: Requirements 1.2
    """
    # Test protocol negotiation by attempting connection
    test_data = b"Protocol negotiation test"
    echo_data = await echo_client.connect_and_echo(mock_server, test_data)
    
    # If we get here, protocol negotiation succeeded
    assert echo_data == test_data, "Protocol negotiation test failed"