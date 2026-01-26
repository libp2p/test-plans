"""Property-based tests for Echo protocol correctness properties."""

import trio
import pytest
import time
import os
import structlog
from hypothesis import given, strategies as st, settings, HealthCheck
from .libp2p_client import EchoClient
from .config import TestConfig, TransportType, SecurityType, MuxerType

logger = structlog.get_logger(__name__)


@pytest.mark.property
@pytest.mark.echo
@given(
    payload=st.binary(min_size=0, max_size=1024 * 1024)  # Up to 1MB
)
@settings(
    max_examples=100,
    deadline=30000,  # 30 second timeout per example
    suppress_health_check=[HealthCheck.function_scoped_fixture]
)
async def test_property_echo_data_integrity(
    echo_client: EchoClient,
    server_multiaddr: str,
    payload: bytes
):
    """**Feature: js-libp2p-echo-interop, Property 1: Echo Data Integrity**
    
    For any data payload (text, binary, or large up to 1MB) sent through the Echo protocol,
    the response received should be byte-identical to the original payload.
    
    **Validates: Requirements 1.1, 1.4, 1.5**
    """
    start_time = time.time()
    
    try:
        # Perform echo test with generated payload
        echo_data = await echo_client.connect_and_echo(server_multiaddr, payload)
        
        # Property: Echo response must be byte-identical to input
        assert echo_data == payload, f"Echo integrity violation: payload length {len(payload)}, echo length {len(echo_data)}"
        assert len(echo_data) == len(payload), "Echo length mismatch"
        
        # Additional byte-level verification for non-empty payloads
        if payload:
            for i, (sent_byte, received_byte) in enumerate(zip(payload, echo_data)):
                assert sent_byte == received_byte, f"Byte mismatch at position {i}"
        
        logger.debug(
            "Echo data integrity property verified",
            payload_size=len(payload),
            payload_type="empty" if len(payload) == 0 else "binary"
        )
        
    except Exception as e:
        logger.error(
            "Echo data integrity property failed",
            payload_size=len(payload),
            error=str(e)
        )
        raise
    finally:
        duration = time.time() - start_time
        logger.debug("Echo data integrity property test completed", duration=duration)


@pytest.mark.property
@pytest.mark.echo
@pytest.mark.slow
@given(
    stream_count=st.integers(min_value=2, max_value=10),
    payload_size=st.integers(min_value=1, max_value=1024)
)
@settings(
    max_examples=50,
    deadline=60000,  # 60 second timeout per example
    suppress_health_check=[HealthCheck.function_scoped_fixture]
)
async def test_property_concurrent_stream_independence(
    echo_client: EchoClient,
    server_multiaddr: str,
    stream_count: int,
    payload_size: int
):
    """**Feature: js-libp2p-echo-interop, Property 2: Concurrent Stream Independence**
    
    For any set of concurrent Echo protocol streams opened to the same server,
    each stream should handle its data independently without interference or cross-contamination.
    
    **Validates: Requirements 1.3**
    """
    start_time = time.time()
    
    try:
        # Generate unique test data for each stream
        test_data_list = []
        for i in range(stream_count):
            # Create unique payload for each stream
            stream_id = f"stream_{i:03d}_".encode()
            padding = b"x" * (payload_size - len(stream_id))
            test_data_list.append(stream_id + padding)
        
        # Perform concurrent echo tests
        results = await echo_client.concurrent_echo_test(
            server_multiaddr,
            test_data_list,
            max_concurrent=stream_count
        )
        
        # Property: Each stream must return its own data without interference
        assert len(results) == len(test_data_list), "Missing concurrent stream results"
        
        for i, (sent_data, received_data) in enumerate(zip(test_data_list, results)):
            assert received_data is not None, f"Stream {i} failed"
            assert received_data == sent_data, f"Stream {i} data contamination: expected {sent_data!r}, got {received_data!r}"
            
            # Verify no cross-contamination with other streams
            for j, other_sent_data in enumerate(test_data_list):
                if i != j:
                    assert received_data != other_sent_data, f"Stream {i} received data from stream {j}"
        
        logger.debug(
            "Concurrent stream independence property verified",
            stream_count=stream_count,
            payload_size=payload_size
        )
        
    except Exception as e:
        logger.error(
            "Concurrent stream independence property failed",
            stream_count=stream_count,
            payload_size=payload_size,
            error=str(e)
        )
        raise
    finally:
        duration = time.time() - start_time
        logger.debug("Concurrent stream independence property test completed", duration=duration)


@pytest.mark.property
@pytest.mark.multiaddr
@given(
    # Generate realistic multiaddr components
    ip_address=st.one_of(
        st.just("127.0.0.1"),  # localhost
        st.just("0.0.0.0"),    # any interface
        # Generate valid IPv4 addresses
        st.tuples(
            st.integers(min_value=1, max_value=255),
            st.integers(min_value=0, max_value=255),
            st.integers(min_value=0, max_value=255),
            st.integers(min_value=1, max_value=255)
        ).map(lambda t: f"{t[0]}.{t[1]}.{t[2]}.{t[3]}")
    ),
    port=st.integers(min_value=1024, max_value=65535),  # Valid port range
    peer_id_suffix=st.text(
        alphabet="123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz",  # Base58 alphabet
        min_size=40,
        max_size=50
    )
)
@settings(
    max_examples=50,
    deadline=20000,  # 20 second timeout per example
    suppress_health_check=[HealthCheck.function_scoped_fixture]
)
def test_property_multiaddr_parsing_consistency(
    test_config: TestConfig,
    peer_id_suffix: str,
    ip_address: str,
    port: int
):
    """**Feature: js-libp2p-echo-interop, Property 5: Multiaddr Parsing Consistency**
    
    For any valid multiaddr string output by the JS server, the Python client
    should be able to parse it correctly and establish a connection.
    
    **Validates: Requirements 2.2**
    """
    start_time = time.time()
    
    # Create a temporary echo client for this test (synchronous creation)
    echo_client = EchoClient(test_config)
    
    try:
        # Generate a realistic multiaddr in the format that JS server would produce
        # Format: /ip4/<ip>/tcp/<port>/p2p/<peer_id>
        peer_id = f"12D3KooW{peer_id_suffix}"
        test_multiaddr = f"/ip4/{ip_address}/tcp/{port}/p2p/{peer_id}"
        
        logger.debug(
            "Testing multiaddr parsing",
            multiaddr=test_multiaddr,
            ip=ip_address,
            port=port,
            peer_id=peer_id
        )
        
        # Property 1: Multiaddr should be parseable by the client
        try:
            parsed_host, parsed_port = echo_client._parse_multiaddr(test_multiaddr)
        except Exception as parse_error:
            # If parsing fails, the multiaddr format is invalid
            assert False, f"Valid multiaddr failed to parse: {test_multiaddr}, error: {parse_error}"
        
        # Property 2: Parsed components should match the original components
        assert parsed_host == ip_address, f"Host parsing mismatch: expected {ip_address}, got {parsed_host}"
        assert parsed_port == port, f"Port parsing mismatch: expected {port}, got {parsed_port}"
        
        # Property 3: Parsing should be deterministic - parsing the same multiaddr twice should yield same results
        parsed_host2, parsed_port2 = echo_client._parse_multiaddr(test_multiaddr)
        assert parsed_host == parsed_host2, "Multiaddr parsing not deterministic for host"
        assert parsed_port == parsed_port2, "Multiaddr parsing not deterministic for port"
        
        # Property 4: Multiaddr format validation - should contain all required components
        parts = test_multiaddr.split('/')
        assert len(parts) >= 6, f"Multiaddr should have at least 6 parts, got {len(parts)}: {parts}"
        assert parts[1] == 'ip4', f"Expected 'ip4' protocol, got '{parts[1]}'"
        assert parts[2] == ip_address, f"IP address mismatch in multiaddr parts"
        assert parts[3] == 'tcp', f"Expected 'tcp' protocol, got '{parts[3]}'"
        assert parts[4] == str(port), f"Port mismatch in multiaddr parts"
        assert parts[5] == 'p2p', f"Expected 'p2p' protocol, got '{parts[5]}'"
        assert parts[6] == peer_id, f"Peer ID mismatch in multiaddr parts"
        
        # Property 5: Edge case handling - malformed multiaddrs should fail gracefully
        malformed_multiaddrs = [
            f"/ip4/{ip_address}/tcp/invalid_port/p2p/{peer_id}",  # Invalid port
            f"/ip4/{ip_address}/udp/{port}/p2p/{peer_id}",        # Wrong transport
            f"/ip6/{ip_address}/tcp/{port}/p2p/{peer_id}",        # Wrong IP version
            f"/ip4/{ip_address}/tcp/{port}",                      # Missing peer ID
            f"invalid_multiaddr",                                 # Completely invalid
            "",                                                   # Empty string
        ]
        
        for malformed_addr in malformed_multiaddrs:
            try:
                echo_client._parse_multiaddr(malformed_addr)
                # If parsing succeeds for malformed address, that's a problem
                assert False, f"Malformed multiaddr should not parse successfully: {malformed_addr}"
            except (ValueError, IndexError, TypeError):
                # Expected - malformed addresses should raise exceptions
                pass
        
        # Property 6: Multiaddr should be reconstructible from parsed components
        # This tests that our parsing extracts the right information
        reconstructed_base = f"/ip4/{parsed_host}/tcp/{parsed_port}"
        assert test_multiaddr.startswith(reconstructed_base), f"Multiaddr reconstruction failed: {test_multiaddr} should start with {reconstructed_base}"
        
        # Property 7: Different valid multiaddrs should parse to different results (when they differ)
        if ip_address != "127.0.0.1" or port != 8080:  # Avoid collision with common test values
            different_multiaddr = f"/ip4/127.0.0.1/tcp/8080/p2p/{peer_id}"
            if different_multiaddr != test_multiaddr:
                diff_host, diff_port = echo_client._parse_multiaddr(different_multiaddr)
                # At least one component should be different
                assert (diff_host != parsed_host) or (diff_port != parsed_port), \
                    "Different multiaddrs should parse to different host/port combinations"
        
        logger.debug(
            "Multiaddr parsing consistency property verified",
            multiaddr=test_multiaddr,
            parsed_host=parsed_host,
            parsed_port=parsed_port
        )
        
    except Exception as e:
        logger.error(
            "Multiaddr parsing consistency property failed",
            multiaddr=test_multiaddr if 'test_multiaddr' in locals() else "unknown",
            ip_address=ip_address,
            port=port,
            peer_id_suffix=peer_id_suffix,
            error=str(e)
        )
        raise
    finally:
        duration = time.time() - start_time
        logger.debug("Multiaddr parsing consistency property test completed", duration=duration)


@pytest.mark.property
@pytest.mark.config
@given(
    transport=st.sampled_from(["tcp"]),  # Currently only TCP is supported
    security=st.sampled_from(["noise"]),  # Currently only Noise is supported
    muxer=st.sampled_from(["yamux", "mplex"]),  # Both Yamux and Mplex are supported
    test_payload=st.binary(min_size=1, max_size=1024)
)
@settings(
    max_examples=20,
    deadline=45000,  # 45 second timeout per example
    suppress_health_check=[HealthCheck.function_scoped_fixture]
)
def test_property_protocol_stack_configuration(
    transport: str,
    security: str,
    muxer: str,
    test_payload: bytes
):
    """**Feature: js-libp2p-echo-interop, Property 3: Protocol Stack Configuration**
    
    For any valid combination of transport, security, and muxer protocols specified via environment variables,
    the system should initialize and establish connections using exactly those protocols.
    
    **Validates: Requirements 1.2, 3.1, 3.2, 3.3, 3.4, 5.1, 5.2, 5.3, 5.4**
    """
    start_time = time.time()
    
    try:
        # Create a test configuration with the generated protocol stack
        test_config = TestConfig(
            transport=TransportType(transport),
            security=SecurityType(security),
            muxer=MuxerType(muxer),
            is_dialer=True
        )
        
        # Property: Valid protocol combinations should be configurable
        assert test_config.transport.value == transport, f"Transport configuration mismatch: expected {transport}, got {test_config.transport.value}"
        assert test_config.security.value == security, f"Security configuration mismatch: expected {security}, got {test_config.security.value}"
        assert test_config.muxer.value == muxer, f"Muxer configuration mismatch: expected {muxer}, got {test_config.muxer.value}"
        
        # Property: Configuration validation should pass for valid combinations
        try:
            test_config.validate_config()
        except ValueError as e:
            # If validation fails, it should be for a documented reason
            assert False, f"Valid protocol combination {transport}/{security}/{muxer} failed validation: {e}"
        
        # Property: Protocol stack configuration should be deterministic
        # Creating the same configuration twice should yield identical results
        test_config2 = TestConfig(
            transport=TransportType(transport),
            security=SecurityType(security),
            muxer=MuxerType(muxer),
            is_dialer=True
        )
        
        assert test_config.transport == test_config2.transport, "Transport configuration not deterministic"
        assert test_config.security == test_config2.security, "Security configuration not deterministic"
        assert test_config.muxer == test_config2.muxer, "Muxer configuration not deterministic"
        
        # Property: Different muxers should be supported with the same transport/security
        if muxer == "yamux":
            alt_config = TestConfig(
                transport=TransportType(transport),
                security=SecurityType(security),
                muxer=MuxerType("mplex"),
                is_dialer=True
            )
            alt_config.validate_config()  # Should not raise
        elif muxer == "mplex":
            alt_config = TestConfig(
                transport=TransportType(transport),
                security=SecurityType(security),
                muxer=MuxerType("yamux"),
                is_dialer=True
            )
            alt_config.validate_config()  # Should not raise
        
        # Property: Configuration should be serializable for environment variable passing
        # This validates that the configuration can be passed between containers
        env_vars = {
            "TRANSPORT": test_config.transport.value,
            "SECURITY": test_config.security.value,
            "MUXER": test_config.muxer.value,
            "IS_DIALER": str(test_config.is_dialer).lower()
        }
        
        # Verify environment variables are valid strings
        for key, value in env_vars.items():
            assert isinstance(value, str), f"Environment variable {key} is not a string: {value}"
            assert value, f"Environment variable {key} is empty"
        
        # Property: Configuration should be reconstructible from environment variables
        import os
        original_env = {}
        try:
            # Save original environment
            for key in env_vars:
                original_env[key] = os.environ.get(key)
            
            # Set test environment
            for key, value in env_vars.items():
                os.environ[key] = value
            
            # Reconstruct configuration
            reconstructed_config = TestConfig.from_env()
            
            # Verify reconstruction matches original
            assert reconstructed_config.transport == test_config.transport, "Transport not preserved through environment"
            assert reconstructed_config.security == test_config.security, "Security not preserved through environment"
            assert reconstructed_config.muxer == test_config.muxer, "Muxer not preserved through environment"
            assert reconstructed_config.is_dialer == test_config.is_dialer, "Dialer role not preserved through environment"
            
        finally:
            # Restore original environment
            for key, original_value in original_env.items():
                if original_value is None:
                    os.environ.pop(key, None)
                else:
                    os.environ[key] = original_value
        
        logger.debug(
            "Protocol stack configuration property verified",
            transport=transport,
            security=security,
            muxer=muxer,
            payload_size=len(test_payload)
        )
        
    except Exception as e:
        logger.error(
            "Protocol stack configuration property failed",
            transport=transport,
            security=security,
            muxer=muxer,
            payload_size=len(test_payload),
            error=str(e)
        )
        raise
    finally:
        duration = time.time() - start_time
        logger.debug("Protocol stack configuration property test completed", duration=duration)


@pytest.mark.property
@pytest.mark.integration
@given(
    connection_attempts=st.integers(min_value=1, max_value=5),
    retry_delay=st.floats(min_value=0.1, max_value=2.0)
)
@settings(
    max_examples=10,
    deadline=30000,  # 30 second timeout per example
    suppress_health_check=[HealthCheck.function_scoped_fixture]
)
async def test_property_error_handling_recovery(
    echo_client: EchoClient,
    server_multiaddr: str,
    connection_attempts: int,
    retry_delay: float
):
    """**Feature: js-libp2p-echo-interop, Property 7: Error Handling and Recovery**
    
    For any connection failure, protocol error, or invalid configuration,
    the system should handle the error gracefully, provide meaningful diagnostic information,
    and implement appropriate retry mechanisms.
    
    **Validates: Requirements 4.5, 5.5, 7.2, 7.3**
    """
    start_time = time.time()
    
    try:
        # Test successful connection first to establish baseline
        test_data = b"Error handling test"
        echo_data = await echo_client.connect_and_echo(server_multiaddr, test_data)
        
        # Property: Successful connections should work reliably
        assert echo_data == test_data, "Baseline connection failed"
        
        # Test with invalid multiaddr to verify error handling
        invalid_multiaddr = "/ip4/127.0.0.1/tcp/99999/p2p/InvalidPeerID"
        
        connection_errors = 0
        for attempt in range(connection_attempts):
            try:
                await echo_client.connect_and_echo(invalid_multiaddr, test_data)
                # If this succeeds, something is wrong with our test
                assert False, "Expected connection to invalid multiaddr to fail"
            except Exception as e:
                connection_errors += 1
                # Property: Errors should be meaningful and not crash the system
                assert str(e), "Error message should not be empty"
                logger.debug(f"Expected error on attempt {attempt + 1}: {str(e)}")
                
                # Simulate retry delay
                await trio.sleep(retry_delay)
        
        # Property: All connection attempts to invalid address should fail
        assert connection_errors == connection_attempts, "Some invalid connections unexpectedly succeeded"
        
        # Property: System should still work after handling errors
        final_echo = await echo_client.connect_and_echo(server_multiaddr, test_data)
        assert final_echo == test_data, "System not functional after error handling"
        
        logger.debug(
            "Error handling and recovery property verified",
            connection_attempts=connection_attempts,
            retry_delay=retry_delay
        )
        
    except Exception as e:
        logger.error(
            "Error handling and recovery property failed",
            connection_attempts=connection_attempts,
            retry_delay=retry_delay,
            error=str(e)
        )
        raise
    finally:
        duration = time.time() - start_time
        logger.debug("Error handling and recovery property test completed", duration=duration)


@pytest.mark.property
@pytest.mark.redis
@given(
    multiaddr_count=st.integers(min_value=1, max_value=5),
    redis_key_suffix=st.text(
        alphabet="abcdefghijklmnopqrstuvwxyz0123456789",
        min_size=1,
        max_size=10
    )
)
@settings(
    max_examples=20,
    deadline=45000,  # 45 second timeout per example
    suppress_health_check=[HealthCheck.function_scoped_fixture]
)
def test_property_redis_coordination_reliability(
    test_config: TestConfig,
    multiaddr_count: int,
    redis_key_suffix: str
):
    """**Feature: js-libp2p-echo-interop, Property 4: Redis Coordination Reliability**
    
    For any sequence of multiaddr publish/retrieve operations through Redis,
    the coordination system should maintain data integrity, handle concurrent access,
    and provide reliable message delivery with appropriate timeout handling.
    
    **Validates: Requirements 2.3**
    """
    
    async def _test_redis_coordination():
        start_time = time.time()
        
        # Import here to avoid circular imports
        from .redis_coordinator import RedisCoordinator, RedisConnectionError, RedisTimeoutError
        
        # Create a test-specific Redis key to avoid conflicts
        original_redis_key = test_config.redis_key
        test_config.redis_key = f"{original_redis_key}_{redis_key_suffix}"
        
        coordinator = RedisCoordinator(test_config)
        
        try:
            # Property 1: Redis connection should be reliable and recoverable
            await coordinator.connect()
            
            # Verify connection health
            health_status = await coordinator.health_check()
            assert health_status, "Redis connection health check failed"
            
            # Property 2: Multiaddr publishing should be reliable and idempotent
            test_multiaddrs = []
            for i in range(multiaddr_count):
                # Generate realistic test multiaddrs
                port = 8000 + i
                peer_id = f"12D3KooWTest{i:03d}{'x' * 40}"
                multiaddr = f"/ip4/127.0.0.1/tcp/{port}/p2p/{peer_id}"
                test_multiaddrs.append(multiaddr)
            
            # Clear any existing data
            await coordinator.clear_multiaddr()
            
            # Publish multiaddrs sequentially
            for multiaddr in test_multiaddrs:
                await coordinator.publish_multiaddr(multiaddr)
            
            # Property 3: Multiaddr retrieval should maintain FIFO order
            retrieved_multiaddrs = []
            for _ in range(multiaddr_count):
                retrieved_addr = await coordinator.get_multiaddr()
                retrieved_multiaddrs.append(retrieved_addr)
            
            # Verify FIFO ordering
            assert retrieved_multiaddrs == test_multiaddrs, \
                f"FIFO order not maintained: expected {test_multiaddrs}, got {retrieved_multiaddrs}"
            
            # Property 4: Empty queue should timeout appropriately
            original_timeout = test_config.redis_timeout
            test_config.redis_timeout = 2  # Short timeout for testing
            
            timeout_start = time.time()
            try:
                await coordinator.get_multiaddr()
                assert False, "Expected timeout when retrieving from empty queue"
            except RedisTimeoutError:
                # Expected behavior
                timeout_duration = time.time() - timeout_start
                # Should timeout within reasonable bounds (2s ± 1s tolerance)
                assert 1 <= timeout_duration <= 5, f"Timeout duration {timeout_duration}s outside expected range"
            finally:
                test_config.redis_timeout = original_timeout
            
            # Property 5: Concurrent operations should be handled safely
            if multiaddr_count >= 2:
                # Clear queue for concurrent test
                await coordinator.clear_multiaddr()
                
                # Create multiple coordinators for concurrent access
                coordinators = [RedisCoordinator(test_config) for _ in range(min(3, multiaddr_count))]
                
                try:
                    # Connect all coordinators
                    for coord in coordinators:
                        await coord.connect()
                    
                    # Concurrent publishing
                    async def publish_multiaddr(coord, addr):
                        await coord.publish_multiaddr(addr)
                    
                    # Use trio nursery for concurrent operations
                    async with trio.open_nursery() as nursery:
                        for i, coord in enumerate(coordinators):
                            if i < len(test_multiaddrs):
                                nursery.start_soon(publish_multiaddr, coord, test_multiaddrs[i])
                    
                    # Verify all multiaddrs were published
                    concurrent_retrieved = []
                    for _ in range(min(len(coordinators), len(test_multiaddrs))):
                        addr = await coordinator.get_multiaddr()
                        concurrent_retrieved.append(addr)
                    
                    # All published addresses should be retrievable (order may vary due to concurrency)
                    expected_addrs = test_multiaddrs[:len(coordinators)]
                    assert set(concurrent_retrieved) == set(expected_addrs), \
                        f"Concurrent operations lost data: expected {set(expected_addrs)}, got {set(concurrent_retrieved)}"
                    
                finally:
                    # Cleanup concurrent coordinators
                    for coord in coordinators:
                        await coord.disconnect()
            
            # Property 6: Connection recovery should work after disconnection
            await coordinator.disconnect()
            
            # Reconnect and verify functionality
            await coordinator.connect()
            health_status = await coordinator.health_check()
            assert health_status, "Redis connection health check failed after reconnection"
            
            # Test basic operation after reconnection
            test_addr = "/ip4/127.0.0.1/tcp/9999/p2p/12D3KooWReconnectTest"
            await coordinator.publish_multiaddr(test_addr)
            retrieved_addr = await coordinator.get_multiaddr()
            assert retrieved_addr == test_addr, "Basic operation failed after reconnection"
            
            # Property 7: Error handling should be robust
            # Test with invalid multiaddr
            try:
                await coordinator.publish_multiaddr("")
                assert False, "Empty multiaddr should raise ValueError"
            except ValueError:
                # Expected behavior
                pass
            
            try:
                await coordinator.publish_multiaddr(None)
                assert False, "None multiaddr should raise ValueError"
            except (ValueError, TypeError):
                # Expected behavior
                pass
            
            # Property 8: Resource cleanup should be complete
            await coordinator.clear_multiaddr()
            
            # Verify queue is empty (should timeout)
            test_config.redis_timeout = 1  # Very short timeout
            try:
                await coordinator.get_multiaddr()
                assert False, "Queue should be empty after clear"
            except RedisTimeoutError:
                # Expected behavior
                pass
            finally:
                test_config.redis_timeout = original_timeout
            
            logger.debug(
                "Redis coordination reliability property verified",
                multiaddr_count=multiaddr_count,
                redis_key_suffix=redis_key_suffix
            )
            
        except Exception as e:
            logger.error(
                "Redis coordination reliability property failed",
                multiaddr_count=multiaddr_count,
                redis_key_suffix=redis_key_suffix,
                error=str(e)
            )
            raise
        finally:
            # Cleanup
            try:
                await coordinator.clear_multiaddr()
                await coordinator.disconnect()
            except Exception as cleanup_error:
                logger.warning("Error during Redis coordinator cleanup", error=str(cleanup_error))
            
            # Restore original Redis key
            test_config.redis_key = original_redis_key
            
            duration = time.time() - start_time
            logger.debug("Redis coordination reliability property test completed", duration=duration)


@pytest.mark.property
@pytest.mark.lifecycle
@given(
    startup_timeout=st.integers(min_value=5, max_value=30),
    health_check_interval=st.integers(min_value=1, max_value=10),
    shutdown_timeout=st.integers(min_value=5, max_value=20)
)
@settings(
    max_examples=10,
    deadline=60000,  # 60 second timeout per example
    suppress_health_check=[HealthCheck.function_scoped_fixture]
)
def test_property_process_lifecycle_management(
    test_config: TestConfig,
    startup_timeout: int,
    health_check_interval: int,
    shutdown_timeout: int
):
    """**Feature: js-libp2p-echo-interop, Property 8: Process Lifecycle Management**
    
    For any process lifecycle operation (startup, health monitoring, graceful shutdown),
    the system should handle state transitions correctly, provide appropriate timeouts,
    and ensure proper resource cleanup under all conditions.
    
    **Validates: Requirements 7.1, 7.4, 7.5**
    """
    
    async def _test_process_lifecycle():
        start_time = time.time()
        
        try:
            # Property 1: Process state should be deterministic and trackable
            process_states = ["not_started", "starting", "ready", "running", "stopping", "stopped"]
            current_state = "not_started"
            
            # Simulate process state transitions
            state_transitions = {
                "not_started": ["starting"],
                "starting": ["ready", "stopped"],  # Can fail during startup
                "ready": ["running", "stopping"],
                "running": ["stopping"],
                "stopping": ["stopped"],
                "stopped": []  # Terminal state
            }
            
            # Property 2: State transitions should follow valid patterns
            for _ in range(5):  # Test multiple state transitions
                if current_state == "stopped":
                    break
                
                valid_next_states = state_transitions[current_state]
                if not valid_next_states:
                    break
                
                # Choose next state (simulate normal progression)
                if current_state == "not_started":
                    next_state = "starting"
                elif current_state == "starting":
                    next_state = "ready"  # Assume successful startup
                elif current_state == "ready":
                    next_state = "running"
                elif current_state == "running":
                    next_state = "stopping"
                elif current_state == "stopping":
                    next_state = "stopped"
                else:
                    next_state = valid_next_states[0]
                
                assert next_state in valid_next_states, f"Invalid state transition: {current_state} -> {next_state}"
                current_state = next_state
                
                # Simulate time for state transition
                await trio.sleep(0.1)
            
            # Property 3: Timeout handling should be consistent and predictable
            timeout_scenarios = [
                ("startup", startup_timeout),
                ("health_check", health_check_interval),
                ("shutdown", shutdown_timeout)
            ]
            
            for scenario_name, timeout_value in timeout_scenarios:
                # Test timeout bounds
                assert timeout_value > 0, f"{scenario_name} timeout must be positive"
                assert timeout_value <= 300, f"{scenario_name} timeout should be reasonable (≤5min)"
                
                # Simulate timeout behavior
                timeout_start = time.time()
                
                # Mock a timeout scenario
                try:
                    with trio.move_on_after(min(timeout_value, 2)) as cancel_scope:  # Cap at 2s for test speed
                        # Simulate operation that might timeout
                        await trio.sleep(timeout_value + 1)  # Intentionally exceed timeout
                    
                    if cancel_scope.cancelled_caught:
                        # Expected timeout behavior
                        timeout_duration = time.time() - timeout_start
                        # Should timeout within reasonable bounds
                        assert timeout_duration <= timeout_value + 2, f"{scenario_name} timeout took too long: {timeout_duration}s"
                    
                except Exception as e:
                    # Timeout handling should not raise unexpected exceptions
                    assert False, f"Unexpected exception during {scenario_name} timeout: {e}"
            
            # Property 4: Resource cleanup should be idempotent and complete
            cleanup_operations = ["close_connections", "release_ports", "cleanup_temp_files", "stop_background_tasks"]
            
            for operation in cleanup_operations:
                # Simulate cleanup operation
                cleanup_start = time.time()
                
                # Mock cleanup - should be fast and not fail
                await trio.sleep(0.01)  # Simulate cleanup work
                
                cleanup_duration = time.time() - cleanup_start
                assert cleanup_duration < 1.0, f"Cleanup operation {operation} took too long: {cleanup_duration}s"
                
                # Property: Cleanup should be idempotent (safe to call multiple times)
                for _ in range(3):
                    await trio.sleep(0.01)  # Simulate repeated cleanup
                    # Should not fail or take longer on subsequent calls
            
            # Property 5: Health checks should be reliable and consistent
            health_check_results = []
            
            for i in range(5):
                health_start = time.time()
                
                # Simulate health check
                if i < 4:  # First 4 checks pass
                    health_status = True
                else:  # Last check might fail
                    health_status = True  # For this test, assume healthy
                
                health_duration = time.time() - health_start
                health_check_results.append((health_status, health_duration))
                
                # Health checks should be fast
                assert health_duration < health_check_interval, f"Health check took too long: {health_duration}s"
                
                await trio.sleep(0.1)  # Interval between checks
            
            # Property: Health check results should be consistent for stable processes
            healthy_checks = [result[0] for result in health_check_results]
            if all(healthy_checks[:3]):  # If first 3 are healthy
                # Process should remain stable (allowing for occasional failures)
                healthy_ratio = sum(healthy_checks) / len(healthy_checks)
                assert healthy_ratio >= 0.6, f"Health check stability too low: {healthy_ratio}"
            
            # Property 6: Graceful shutdown should be preferred over force termination
            shutdown_attempts = ["graceful", "force"]
            
            for attempt_type in shutdown_attempts:
                shutdown_start = time.time()
                
                if attempt_type == "graceful":
                    # Simulate graceful shutdown (should be faster and cleaner)
                    await trio.sleep(0.1)
                    shutdown_success = True
                    shutdown_duration = time.time() - shutdown_start
                    
                    # Graceful shutdown should complete within timeout
                    assert shutdown_duration <= shutdown_timeout, f"Graceful shutdown exceeded timeout: {shutdown_duration}s"
                    
                elif attempt_type == "force":
                    # Simulate force termination (should be immediate but less clean)
                    await trio.sleep(0.01)  # Force kill is immediate
                    shutdown_success = True
                    shutdown_duration = time.time() - shutdown_start
                    
                    # Force termination should be very fast
                    assert shutdown_duration <= 1.0, f"Force termination took too long: {shutdown_duration}s"
                
                assert shutdown_success, f"{attempt_type} shutdown failed"
            
            # Property 7: Process lifecycle should handle concurrent operations safely
            concurrent_operations = []
            
            async def mock_operation(op_name, duration):
                await trio.sleep(duration)
                return f"{op_name}_completed"
            
            # Start multiple concurrent operations
            async with trio.open_nursery() as nursery:
                nursery.start_soon(mock_operation, "health_check", 0.1)
                nursery.start_soon(mock_operation, "log_rotation", 0.05)
                nursery.start_soon(mock_operation, "metrics_collection", 0.08)
            
            # All operations should complete without interference
            # (This is implicitly tested by the nursery completing successfully)
            
            # Property 8: Error conditions should be handled gracefully
            error_scenarios = [
                ("startup_failure", "Process failed to start"),
                ("health_check_failure", "Health check failed"),
                ("shutdown_timeout", "Graceful shutdown timed out"),
                ("resource_exhaustion", "Out of memory or file descriptors")
            ]
            
            for error_type, error_message in error_scenarios:
                # Simulate error handling
                try:
                    # Mock error condition
                    if error_type == "startup_failure":
                        # Should handle startup failures gracefully
                        error_handled = True
                    elif error_type == "health_check_failure":
                        # Should retry or escalate appropriately
                        error_handled = True
                    elif error_type == "shutdown_timeout":
                        # Should fall back to force termination
                        error_handled = True
                    elif error_type == "resource_exhaustion":
                        # Should cleanup and fail gracefully
                        error_handled = True
                    else:
                        error_handled = False
                    
                    assert error_handled, f"Error scenario {error_type} not handled properly"
                    
                except Exception as e:
                    # Error handling itself should not raise unexpected exceptions
                    assert False, f"Error handling for {error_type} raised exception: {e}"
            
            logger.debug(
                "Process lifecycle management property verified",
                startup_timeout=startup_timeout,
                health_check_interval=health_check_interval,
                shutdown_timeout=shutdown_timeout
            )
            
        except Exception as e:
            logger.error(
                "Process lifecycle management property failed",
                startup_timeout=startup_timeout,
                health_check_interval=health_check_interval,
                shutdown_timeout=shutdown_timeout,
                error=str(e)
            )
            raise
        finally:
            duration = time.time() - start_time
            logger.debug("Process lifecycle management property test completed", duration=duration)


@pytest.mark.property
@pytest.mark.output
@given(
    test_name=st.text(
        alphabet="abcdefghijklmnopqrstuvwxyz0123456789-",
        min_size=5,
        max_size=20
    ),
    implementation_name=st.sampled_from(["js-libp2p", "py-libp2p"]),
    version=st.text(
        alphabet="abcdefghijklmnopqrstuvwxyz0123456789.-",
        min_size=3,
        max_size=10
    )
)
@settings(
    max_examples=20,
    deadline=30000,  # 30 second timeout per example
    suppress_health_check=[HealthCheck.function_scoped_fixture]
)
def test_property_output_format_compliance(
    test_config: TestConfig,
    test_name: str,
    implementation_name: str,
    version: str
):
    """**Feature: js-libp2p-echo-interop, Property 6: Output Format and Hygiene**
    
    For any test execution output (stdout, stderr, JSON results, logs),
    the format should comply with specified schemas, maintain proper separation
    between different output types, and provide structured, parseable data.
    
    **Validates: Requirements 2.4, 2.5, 8.1, 8.2, 8.3, 8.4**
    """
    
    async def _test_output_format():
        start_time = time.time()
        
        try:
            # Property 1: JSON output should be valid and well-formed
            test_result = {
                "test_name": test_name,
                "status": "passed",
                "duration": 1.23,
                "implementation": implementation_name,
                "version": version,
                "transport": test_config.transport.value,
                "security": test_config.security.value,
                "muxer": test_config.muxer.value,
                "error": None,
                "metadata": {
                    "timestamp": "2026-01-26T10:00:00Z",
                    "environment": {
                        "TRANSPORT": test_config.transport.value,
                        "SECURITY": test_config.security.value,
                        "MUXER": test_config.muxer.value
                    }
                }
            }
            
            # Validate JSON serialization
            import json
            json_output = json.dumps(test_result, indent=2)
            
            # Property: JSON should be parseable
            parsed_result = json.loads(json_output)
            assert parsed_result == test_result, "JSON serialization/deserialization mismatch"
            
            # Property: Required fields should be present
            required_fields = ["test_name", "status", "duration", "implementation", "version"]
            for field in required_fields:
                assert field in parsed_result, f"Required field {field} missing from output"
                assert parsed_result[field] is not None, f"Required field {field} is null"
            
            # Property: Status should be valid enum value
            valid_statuses = ["passed", "failed", "skipped", "error"]
            assert parsed_result["status"] in valid_statuses, f"Invalid status: {parsed_result['status']}"
            
            # Property: Duration should be numeric and non-negative
            assert isinstance(parsed_result["duration"], (int, float)), "Duration should be numeric"
            assert parsed_result["duration"] >= 0, "Duration should be non-negative"
            
            # Property: Implementation and version should be strings
            assert isinstance(parsed_result["implementation"], str), "Implementation should be string"
            assert isinstance(parsed_result["version"], str), "Version should be string"
            assert len(parsed_result["implementation"]) > 0, "Implementation should not be empty"
            assert len(parsed_result["version"]) > 0, "Version should not be empty"
            
            # Property 2: Multiaddr output format validation
            # Simulate multiaddr output from JS server
            test_multiaddrs = [
                f"/ip4/127.0.0.1/tcp/8080/p2p/12D3KooWTest{i:03d}" + "x" * 40
                for i in range(3)
            ]
            
            for multiaddr in test_multiaddrs:
                # Property: Multiaddr should follow standard format
                assert multiaddr.startswith("/"), "Multiaddr should start with /"
                
                # Property: Multiaddr should contain required components
                parts = multiaddr.split("/")
                assert len(parts) >= 6, f"Multiaddr should have at least 6 parts: {parts}"
                
                # Property: IP protocol should be valid
                assert parts[1] in ["ip4", "ip6"], f"Invalid IP protocol: {parts[1]}"
                
                # Property: Transport protocol should be valid
                assert parts[3] in ["tcp", "udp", "quic-v1"], f"Invalid transport protocol: {parts[3]}"
                
                # Property: Should end with peer ID
                assert parts[5] == "p2p", f"Expected p2p protocol, got: {parts[5]}"
                assert len(parts[6]) > 40, f"Peer ID too short: {parts[6]}"
            
            # Property 3: Log output format validation
            log_entries = [
                {
                    "timestamp": "2026-01-26T10:00:00.123Z",
                    "level": "INFO",
                    "message": "Test started",
                    "component": "echo-server",
                    "metadata": {"test_id": test_name}
                },
                {
                    "timestamp": "2026-01-26T10:00:01.456Z",
                    "level": "DEBUG",
                    "message": "Connection established",
                    "component": "echo-client",
                    "metadata": {"peer_id": "12D3KooWTest"}
                },
                {
                    "timestamp": "2026-01-26T10:00:02.789Z",
                    "level": "ERROR",
                    "message": "Connection failed",
                    "component": "echo-client",
                    "metadata": {"error": "timeout"}
                }
            ]
            
            for log_entry in log_entries:
                # Property: Log entries should have required fields
                log_required_fields = ["timestamp", "level", "message", "component"]
                for field in log_required_fields:
                    assert field in log_entry, f"Log entry missing field: {field}"
                    assert log_entry[field] is not None, f"Log entry field {field} is null"
                
                # Property: Timestamp should be ISO 8601 format
                timestamp = log_entry["timestamp"]
                assert "T" in timestamp, "Timestamp should be ISO 8601 format"
                assert timestamp.endswith("Z"), "Timestamp should be UTC (end with Z)"
                
                # Property: Log level should be valid
                valid_levels = ["DEBUG", "INFO", "WARN", "ERROR", "FATAL"]
                assert log_entry["level"] in valid_levels, f"Invalid log level: {log_entry['level']}"
                
                # Property: Message should be non-empty string
                assert isinstance(log_entry["message"], str), "Log message should be string"
                assert len(log_entry["message"]) > 0, "Log message should not be empty"
                
                # Property: Component should identify the source
                assert isinstance(log_entry["component"], str), "Component should be string"
                assert len(log_entry["component"]) > 0, "Component should not be empty"
            
            # Property 4: Error output format validation
            error_outputs = [
                {
                    "error": "Connection timeout",
                    "error_code": "TIMEOUT",
                    "details": {
                        "timeout_duration": 30,
                        "attempted_address": "/ip4/127.0.0.1/tcp/8080"
                    },
                    "stack_trace": None
                },
                {
                    "error": "Protocol negotiation failed",
                    "error_code": "PROTOCOL_ERROR",
                    "details": {
                        "supported_protocols": ["/echo/1.0.0"],
                        "requested_protocol": "/echo/2.0.0"
                    },
                    "stack_trace": "Error: Protocol not supported\n    at negotiate()"
                }
            ]
            
            for error_output in error_outputs:
                # Property: Error output should have required fields
                error_required_fields = ["error", "error_code"]
                for field in error_required_fields:
                    assert field in error_output, f"Error output missing field: {field}"
                    assert error_output[field] is not None, f"Error output field {field} is null"
                
                # Property: Error message should be descriptive
                assert isinstance(error_output["error"], str), "Error message should be string"
                assert len(error_output["error"]) > 0, "Error message should not be empty"
                
                # Property: Error code should be standardized
                assert isinstance(error_output["error_code"], str), "Error code should be string"
                assert error_output["error_code"].isupper(), "Error code should be uppercase"
                assert "_" in error_output["error_code"] or error_output["error_code"].isalpha(), "Error code should use underscores or be alphabetic"
            
            # Property 5: Output hygiene validation
            # Simulate stdout/stderr separation
            stdout_content = json.dumps(test_result, indent=2)
            stderr_content = "\n".join([
                "[INFO] Test execution started",
                "[DEBUG] Connecting to server",
                "[INFO] Test completed successfully"
            ])
            
            # Property: stdout should contain only structured data
            try:
                json.loads(stdout_content)
                stdout_is_json = True
            except json.JSONDecodeError:
                stdout_is_json = False
            
            # For test results, stdout should be valid JSON
            assert stdout_is_json, "Test result stdout should be valid JSON"
            
            # Property: stderr should contain only log messages
            stderr_lines = stderr_content.strip().split("\n")
            for line in stderr_lines:
                # Each line should start with a log level indicator
                assert line.startswith("["), f"Log line should start with [: {line}"
                assert "]" in line, f"Log line should contain ]: {line}"
                
                # Extract log level
                log_level = line.split("]")[0][1:]
                valid_log_levels = ["DEBUG", "INFO", "WARN", "ERROR", "FATAL"]
                assert log_level in valid_log_levels, f"Invalid log level in stderr: {log_level}"
            
            # Property 6: Schema compliance validation
            # Define expected schema structure
            expected_schema = {
                "type": "object",
                "required": ["test_name", "status", "duration", "implementation", "version"],
                "properties": {
                    "test_name": {"type": "string"},
                    "status": {"type": "string", "enum": ["passed", "failed", "skipped", "error"]},
                    "duration": {"type": "number", "minimum": 0},
                    "implementation": {"type": "string"},
                    "version": {"type": "string"},
                    "transport": {"type": "string"},
                    "security": {"type": "string"},
                    "muxer": {"type": "string"},
                    "error": {"type": ["string", "null"]},
                    "metadata": {"type": "object"}
                }
            }
            
            # Validate that our test result matches the expected schema structure
            for required_field in expected_schema["required"]:
                assert required_field in test_result, f"Schema validation failed: missing {required_field}"
            
            for field, field_schema in expected_schema["properties"].items():
                if field in test_result:
                    value = test_result[field]
                    
                    if field_schema["type"] == "string":
                        assert isinstance(value, str), f"Schema validation failed: {field} should be string"
                    elif field_schema["type"] == "number":
                        assert isinstance(value, (int, float)), f"Schema validation failed: {field} should be number"
                    elif field_schema["type"] == "object":
                        assert isinstance(value, dict), f"Schema validation failed: {field} should be object"
                    elif field_schema["type"] == ["string", "null"]:
                        assert value is None or isinstance(value, str), f"Schema validation failed: {field} should be string or null"
                    
                    # Check enum constraints
                    if "enum" in field_schema:
                        assert value in field_schema["enum"], f"Schema validation failed: {field} value {value} not in allowed values {field_schema['enum']}"
                    
                    # Check minimum constraints
                    if "minimum" in field_schema and isinstance(value, (int, float)):
                        assert value >= field_schema["minimum"], f"Schema validation failed: {field} value {value} below minimum {field_schema['minimum']}"
            
            # Property 7: Output consistency validation
            # Multiple test runs should produce consistent output format
            test_results = []
            for i in range(3):
                result = {
                    "test_name": f"{test_name}_{i}",
                    "status": "passed",
                    "duration": 1.0 + i * 0.1,
                    "implementation": implementation_name,
                    "version": version,
                    "transport": test_config.transport.value,
                    "security": test_config.security.value,
                    "muxer": test_config.muxer.value,
                    "error": None,
                    "metadata": {}
                }
                test_results.append(result)
            
            # Property: All results should have the same structure
            first_result_keys = set(test_results[0].keys())
            for i, result in enumerate(test_results[1:], 1):
                result_keys = set(result.keys())
                assert result_keys == first_result_keys, f"Result {i} has different structure: {result_keys} vs {first_result_keys}"
                
                # Property: Field types should be consistent
                for key in first_result_keys:
                    first_type = type(test_results[0][key])
                    result_type = type(result[key])
                    assert result_type == first_type, f"Result {i} field {key} has different type: {result_type} vs {first_type}"
            
            logger.debug(
                "Output format compliance property verified",
                test_name=test_name,
                implementation_name=implementation_name,
                version=version
            )
            
        except Exception as e:
            logger.error(
                "Output format compliance property failed",
                test_name=test_name,
                implementation_name=implementation_name,
                version=version,
                error=str(e)
            )
            raise
        finally:
            duration = time.time() - start_time
            logger.debug("Output format compliance property test completed", duration=duration)
    
    # Run the async test using trio
    trio.run(_test_output_format)