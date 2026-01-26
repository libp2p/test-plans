"""Pytest configuration and fixtures for Echo protocol tests."""

import trio
import pytest
import structlog
from typing import AsyncGenerator
from .config import TestConfig, config
from .redis_coordinator import RedisCoordinator, get_server_multiaddr
from .libp2p_client import EchoClient, create_echo_client
from .test_result import TestResultCollector

# Configure structured logging
structlog.configure(
    processors=[
        structlog.stdlib.filter_by_level,
        structlog.stdlib.add_logger_name,
        structlog.stdlib.add_log_level,
        structlog.stdlib.PositionalArgumentsFormatter(),
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.StackInfoRenderer(),
        structlog.processors.format_exc_info,
        structlog.processors.UnicodeDecoder(),
        structlog.processors.JSONRenderer()
    ],
    context_class=dict,
    logger_factory=structlog.stdlib.LoggerFactory(),
    wrapper_class=structlog.stdlib.BoundLogger,
    cache_logger_on_first_use=True,
)


@pytest.fixture(scope="session")
def test_config() -> TestConfig:
    """Provide test configuration."""
    config.validate_config()
    return config


@pytest.fixture(scope="session")
def result_collector(test_config: TestConfig) -> TestResultCollector:
    """Provide test result collector."""
    return TestResultCollector(test_config)


@pytest.fixture(scope="session")
async def server_multiaddr(test_config: TestConfig) -> str:
    """Get server multiaddr from Redis coordination."""
    return await get_server_multiaddr(test_config)


@pytest.fixture(scope="session")
async def echo_client(test_config: TestConfig) -> AsyncGenerator[EchoClient, None]:
    """Provide Echo client with proper lifecycle management."""
    client = await create_echo_client(test_config)
    try:
        yield client
    finally:
        await client.stop()


@pytest.fixture(scope="session")
async def redis_coordinator(test_config: TestConfig) -> AsyncGenerator[RedisCoordinator, None]:
    """Provide Redis coordinator with proper lifecycle management."""
    coordinator = RedisCoordinator(test_config)
    await coordinator.connect()
    try:
        yield coordinator
    finally:
        await coordinator.disconnect()


@pytest.fixture
def test_data_small() -> bytes:
    """Small test data for basic tests."""
    return b"Hello, Echo Protocol!"


@pytest.fixture
def test_data_binary() -> bytes:
    """Binary test data with various byte values."""
    return bytes(range(256))


@pytest.fixture
def test_data_large() -> bytes:
    """Large test data (1MB) for stress testing."""
    # Create 1MB of pseudo-random data
    data = b"LARGE_PAYLOAD_TEST_" * 1000  # ~19KB
    while len(data) < 1024 * 1024:  # 1MB
        data += data[:1024 * 1024 - len(data)]
    return data[:1024 * 1024]  # Exactly 1MB


@pytest.fixture
def concurrent_test_data() -> list[bytes]:
    """Multiple test payloads for concurrent testing."""
    return [
        b"Concurrent test 1",
        b"Concurrent test 2",
        b"Concurrent test 3",
        b"Concurrent test 4",
        b"Concurrent test 5"
    ]


# Pytest hooks for result collection
def pytest_runtest_makereport(item, call):
    """Hook to capture test results."""
    if call.when == "call":
        # Get result collector from session
        result_collector = item.session.config._result_collector
        
        # Calculate test duration
        duration = call.duration if hasattr(call, 'duration') else 0.0
        
        # Determine test status
        if call.excinfo is None:
            status = "passed"
            error = None
        else:
            status = "failed"
            error = str(call.excinfo.value) if call.excinfo.value else "Unknown error"
        
        # Extract metadata from test markers
        metadata = {}
        for marker in item.iter_markers():
            if marker.name in ["payload_size", "stream_count", "test_type"]:
                metadata[marker.name] = marker.args[0] if marker.args else True
        
        # Add result
        result_collector.add_result(
            test_name=item.nodeid,
            status=status,
            duration=duration,
            error=error,
            metadata=metadata
        )


def pytest_configure(config):
    """Configure pytest with result collector."""
    test_config = TestConfig.from_env()
    config._result_collector = TestResultCollector(test_config)


def pytest_sessionfinish(session, exitstatus):
    """Output results at end of test session."""
    result_collector = session.config._result_collector
    
    # Log summary to stderr for debugging
    result_collector.log_summary()
    
    # Output JSON results to stdout
    result_collector.output_json_results()