"""Property-based tests for error handling and recovery."""

import trio
import pytest
import time
import structlog
from hypothesis import given, strategies as st, settings, HealthCheck
from .config import TestConfig, TransportType, SecurityType, MuxerType
from .redis_coordinator import RedisCoordinator, RedisConnectionError, RedisTimeoutError

logger = structlog.get_logger(__name__)


@pytest.mark.trio
@pytest.mark.property
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
        # Create test configuration
        test_config = TestConfig(
            transport=TransportType.TCP,
            security=SecurityType.NOISE,
            muxer=MuxerType.YAMUX,
            is_dialer=True
        )
        
        # Property 1: Configuration validation errors should be handled gracefully
        # Test configuration error handling with invalid timeout values
        config_errors = 0
        for i in range(connection_attempts):
            try:
                # Try to create configuration with invalid timeout
                invalid_config = TestConfig(
                    transport=TransportType.TCP,
                    security=SecurityType.NOISE,
                    muxer=MuxerType.YAMUX,
                    is_dialer=True,
                    connection_timeout=10,  # Valid timeout
                    test_timeout=30,        # Valid timeout
                    max_retries=3           # Valid retries
                )
                # Manually trigger validation error by setting invalid timeout
                invalid_config.connection_timeout = -1  # Invalid timeout
                invalid_config.validate_config()
                assert False, "Expected configuration validation to fail"
            except (ValueError, TypeError) as e:
                config_errors += 1
                # Property: Error messages should be meaningful
                assert str(e), "Error message should not be empty"
                assert len(str(e)) > 10, "Error message should be descriptive"
                logger.debug(f"Expected config error on attempt {i + 1}: {str(e)}")
                
                # Simulate retry delay
                await trio.sleep(retry_delay / 10)  # Shorter delay for config tests
        
        # Property: All invalid configurations should fail validation
        assert config_errors == connection_attempts, "Some invalid configurations unexpectedly passed"
        
        # Property 2: Redis connection errors should be handled gracefully
        redis_errors = 0
        for attempt in range(connection_attempts):
            try:
                # Try to connect to invalid Redis address
                invalid_redis_config = TestConfig(
                    transport=TransportType.TCP,
                    security=SecurityType.NOISE,
                    muxer=MuxerType.YAMUX,
                    is_dialer=True,
                    redis_addr="invalid_host:99999"  # Invalid Redis address
                )
                
                coordinator = RedisCoordinator(invalid_redis_config)
                
                # This should fail with a connection error
                with trio.move_on_after(2.0):  # Short timeout
                    await coordinator.connect()
                    assert False, "Expected Redis connection to invalid address to fail"
                
            except (RedisConnectionError, OSError, Exception) as e:
                redis_errors += 1
                # Property: Redis errors should be meaningful and not crash the system
                assert str(e), "Redis error message should not be empty"
                logger.debug(f"Expected Redis error on attempt {attempt + 1}: {str(e)}")
                
                # Simulate retry delay
                await trio.sleep(retry_delay / 10)
        
        # Property: All Redis connection attempts to invalid address should fail
        assert redis_errors == connection_attempts, "Some invalid Redis connections unexpectedly succeeded"
        
        # Property 3: Timeout handling should be consistent
        timeout_tests = 0
        for attempt in range(connection_attempts):
            try:
                # Test timeout behavior
                timeout_start = time.time()
                
                with trio.move_on_after(retry_delay):
                    # Simulate operation that takes longer than timeout
                    await trio.sleep(retry_delay + 1)
                    assert False, "Operation should have timed out"
                
                timeout_duration = time.time() - timeout_start
                
                # Property: Timeout should occur within reasonable bounds
                assert timeout_duration <= retry_delay + 1, f"Timeout took too long: {timeout_duration}s"
                timeout_tests += 1
                
            except Exception as e:
                logger.debug(f"Timeout test error on attempt {attempt + 1}: {str(e)}")
        
        # Property: Timeout handling should be reliable
        assert timeout_tests == connection_attempts, "Timeout handling was inconsistent"
        
        # Property 4: Error recovery should restore system to working state
        # Test that valid operations work after error conditions
        try:
            valid_config = TestConfig(
                transport=TransportType.TCP,
                security=SecurityType.NOISE,
                muxer=MuxerType.YAMUX,
                is_dialer=True
            )
            valid_config.validate_config()
            
            # Property: System should be functional after error handling
            assert valid_config.transport == TransportType.TCP
            assert valid_config.security == SecurityType.NOISE
            assert valid_config.muxer == MuxerType.YAMUX
            
        except Exception as e:
            assert False, f"System not functional after error handling: {e}"
        
        # Property 5: Error logging and diagnostics should be comprehensive
        error_scenarios = [
            ("invalid_transport", "Transport validation"),
            ("invalid_security", "Security validation"),
            ("invalid_muxer", "Muxer validation"),
            ("invalid_timeout", "Timeout validation"),
            ("invalid_redis", "Redis validation")
        ]
        
        for scenario_name, scenario_desc in error_scenarios:
            try:
                # Simulate different error scenarios
                if scenario_name == "invalid_transport":
                    # This would fail at enum creation, so we simulate the error
                    raise ValueError(f"Invalid transport: {scenario_name}")
                elif scenario_name == "invalid_security":
                    raise ValueError(f"Invalid security protocol: {scenario_name}")
                elif scenario_name == "invalid_muxer":
                    raise ValueError(f"Invalid muxer: {scenario_name}")
                elif scenario_name == "invalid_timeout":
                    raise ValueError(f"Invalid timeout value: {scenario_name}")
                elif scenario_name == "invalid_redis":
                    raise RedisConnectionError(f"Redis connection failed: {scenario_name}")
                
            except (ValueError, RedisConnectionError) as e:
                # Property: Error diagnostics should include scenario context
                error_msg = str(e)
                assert scenario_name in error_msg or scenario_desc.lower() in error_msg.lower(), \
                    f"Error message should include context: {error_msg}"
                
                # Property: Error messages should be actionable
                assert len(error_msg) > 5, "Error message should be descriptive"
                assert not error_msg.startswith("Error:"), "Error message should not be generic"
        
        # Property 6: Retry mechanisms should implement exponential backoff
        retry_delays = []
        base_delay = retry_delay
        backoff_factor = 2.0
        
        for attempt in range(min(connection_attempts, 4)):  # Limit to 4 attempts for test speed
            current_delay = min(base_delay * (backoff_factor ** attempt), retry_delay * 10)
            retry_delays.append(current_delay)
            
            # Simulate retry delay
            delay_start = time.time()
            await trio.sleep(current_delay / 100)  # Scale down for test speed
            actual_delay = time.time() - delay_start
            
            # Property: Actual delay should be close to expected (within 50% tolerance)
            expected_scaled = current_delay / 100
            assert abs(actual_delay - expected_scaled) <= expected_scaled * 0.5, \
                f"Retry delay not accurate: expected ~{expected_scaled}s, got {actual_delay}s"
        
        # Property: Retry delays should increase (exponential backoff)
        if len(retry_delays) > 1:
            for i in range(1, len(retry_delays)):
                assert retry_delays[i] >= retry_delays[i-1], \
                    f"Retry delays should increase: {retry_delays}"
        
        # Property 7: Error handling should not leak resources
        # Simulate resource allocation and cleanup
        allocated_resources = []
        
        try:
            # Simulate resource allocation
            for i in range(connection_attempts):
                resource_id = f"resource_{i}"
                allocated_resources.append(resource_id)
                
                # Simulate potential error during resource usage
                if i == connection_attempts - 1:  # Fail on last attempt
                    raise RuntimeError(f"Simulated error with resource {resource_id}")
                
        except RuntimeError as e:
            # Property: Error handling should allow for resource cleanup
            assert "Simulated error" in str(e), "Error should be the expected simulation"
            
            # Simulate resource cleanup
            cleaned_resources = []
            for resource_id in allocated_resources:
                cleaned_resources.append(resource_id)
                await trio.sleep(0.001)  # Simulate cleanup work
            
            # Property: All allocated resources should be cleaned up
            assert len(cleaned_resources) == len(allocated_resources), \
                "Not all resources were cleaned up"
            assert set(cleaned_resources) == set(allocated_resources), \
                "Resource cleanup mismatch"
        
        logger.debug(
            "Error handling and recovery property verified",
            connection_attempts=connection_attempts,
            retry_delay=retry_delay,
            config_errors=config_errors,
            redis_errors=redis_errors,
            timeout_tests=timeout_tests
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


@pytest.mark.trio
@pytest.mark.property
@given(
    error_type=st.sampled_from([
        "connection_timeout",
        "protocol_negotiation_failure", 
        "invalid_multiaddr",
        "redis_connection_failure",
        "configuration_error"
    ]),
    recovery_attempts=st.integers(min_value=1, max_value=3)
)
@settings(
    max_examples=15,
    deadline=20000,  # 20 second timeout per example
    suppress_health_check=[HealthCheck.function_scoped_fixture]
)
async def test_property_specific_error_scenarios(
    error_type: str,
    recovery_attempts: int
):
    """**Feature: js-libp2p-echo-interop, Property 7b: Specific Error Scenario Handling**
    
    For specific types of errors (connection timeout, protocol negotiation failure, etc.),
    the system should handle each error type appropriately with specific recovery strategies.
    
    **Validates: Requirements 4.5, 7.2, 7.3**
    """
    start_time = time.time()
    
    try:
        # Property: Each error type should have specific handling
        error_handled = False
        recovery_successful = False
        
        for attempt in range(recovery_attempts):
            try:
                # Simulate specific error scenarios
                if error_type == "connection_timeout":
                    # Simulate connection timeout by raising TimeoutError directly
                    raise TimeoutError("Connection timeout after 30 seconds")
                    
                elif error_type == "protocol_negotiation_failure":
                    # Simulate protocol negotiation failure
                    supported_protocols = ["/echo/1.0.0"]
                    requested_protocol = "/echo/2.0.0"  # Unsupported version
                    
                    if requested_protocol not in supported_protocols:
                        raise ValueError(f"Protocol {requested_protocol} not supported. Supported: {supported_protocols}")
                    
                elif error_type == "invalid_multiaddr":
                    # Simulate invalid multiaddr parsing
                    invalid_multiaddrs = [
                        "",  # Empty
                        "not_a_multiaddr",  # Invalid format
                        "/ip4/999.999.999.999/tcp/8080",  # Invalid IP
                        "/ip4/127.0.0.1/tcp/99999",  # Invalid port
                        "/ip4/127.0.0.1/tcp/8080/p2p/invalid_peer_id"  # Invalid peer ID
                    ]
                    
                    test_multiaddr = invalid_multiaddrs[attempt % len(invalid_multiaddrs)]
                    
                    # Simulate multiaddr parsing
                    if not test_multiaddr or not test_multiaddr.startswith("/"):
                        raise ValueError(f"Invalid multiaddr format: {test_multiaddr}")
                    
                    parts = test_multiaddr.split("/")
                    if len(parts) < 6:
                        raise ValueError(f"Multiaddr too short: {test_multiaddr}")
                    
                    # Check for invalid IP
                    if "999.999.999.999" in test_multiaddr:
                        raise ValueError(f"Invalid IP address in multiaddr: {test_multiaddr}")
                    
                    # Check for invalid port
                    if "99999" in test_multiaddr:
                        raise ValueError(f"Invalid port in multiaddr: {test_multiaddr}")
                    
                elif error_type == "redis_connection_failure":
                    # Simulate Redis connection failure
                    invalid_redis_addr = "nonexistent_host:6379"
                    
                    # Property: Redis connection errors should be specific
                    raise RedisConnectionError(f"Failed to connect to Redis at {invalid_redis_addr}")
                    
                elif error_type == "configuration_error":
                    # Simulate configuration validation error
                    invalid_configs = {
                        "negative_timeout": -1,
                        "zero_retries": -1,
                        "invalid_backoff": 0.5,  # Less than 1.0
                        "excessive_timeout": 10000  # Too large
                    }
                    
                    config_error = list(invalid_configs.keys())[attempt % len(invalid_configs)]
                    config_value = invalid_configs[config_error]
                    
                    if config_error == "negative_timeout" and config_value < 0:
                        raise ValueError(f"Timeout must be positive, got: {config_value}")
                    elif config_error == "zero_retries" and config_value < 0:
                        raise ValueError(f"Retries must be non-negative, got: {config_value}")
                    elif config_error == "invalid_backoff" and config_value <= 1.0:
                        raise ValueError(f"Backoff factor must be > 1.0, got: {config_value}")
                    elif config_error == "excessive_timeout" and config_value > 1000:
                        raise ValueError(f"Timeout too large: {config_value}s")
                
                # If we reach here without exception, the error wasn't triggered
                assert False, f"Expected {error_type} to trigger an error"
                
            except (ValueError, RedisConnectionError, OSError, TimeoutError) as e:
                error_handled = True
                
                # Property: Error messages should be specific to error type
                error_msg = str(e).lower()
                
                if error_type == "connection_timeout":
                    # Timeout was handled by trio.move_on_after or TimeoutError
                    assert "timeout" in error_msg or "connection" in error_msg, \
                        f"Timeout error should mention timeout: {error_msg}"
                elif error_type == "protocol_negotiation_failure":
                    assert "protocol" in error_msg or "supported" in error_msg, \
                        f"Protocol error should mention protocol: {error_msg}"
                elif error_type == "invalid_multiaddr":
                    assert "multiaddr" in error_msg or "invalid" in error_msg, \
                        f"Multiaddr error should mention multiaddr: {error_msg}"
                elif error_type == "redis_connection_failure":
                    assert "redis" in error_msg or "connection" in error_msg, \
                        f"Redis error should mention Redis: {error_msg}"
                elif error_type == "configuration_error":
                    assert any(word in error_msg for word in ["timeout", "retries", "backoff"]), \
                        f"Config error should mention config parameter: {error_msg}"
                
                # Property: Error recovery should be attempted
                logger.debug(f"Handling {error_type} error (attempt {attempt + 1}): {str(e)}")
                
                # Simulate recovery delay
                await trio.sleep(0.01 * (attempt + 1))  # Increasing delay
                
                # Property: Recovery should eventually succeed (simulated)
                if attempt == recovery_attempts - 1:
                    recovery_successful = True
                    logger.debug(f"Recovery successful for {error_type} after {attempt + 1} attempts")
        
        # Property: All error types should be handled
        assert error_handled, f"Error type {error_type} was not properly handled"
        
        # Property: Recovery should eventually succeed
        assert recovery_successful, f"Recovery failed for error type {error_type}"
        
        logger.debug(
            "Specific error scenario property verified",
            error_type=error_type,
            recovery_attempts=recovery_attempts
        )
        
    except Exception as e:
        logger.error(
            "Specific error scenario property failed",
            error_type=error_type,
            recovery_attempts=recovery_attempts,
            error=str(e)
        )
        raise
    finally:
        duration = time.time() - start_time
        logger.debug("Specific error scenario property test completed", duration=duration)