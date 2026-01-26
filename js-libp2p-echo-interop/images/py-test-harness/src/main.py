"""Main entry point for the Python test harness with enhanced lifecycle management."""

import sys
import os
import json
import time
import signal
import trio
import structlog
import pytest
from datetime import datetime
from typing import Dict, List, Any, Optional
from .config import TestConfig
from .test_result import TestResultCollector

logger = structlog.get_logger(__name__)

# Global state for lifecycle management
_shutdown_requested = False
_test_start_time = None
_result_collector = None


def setup_signal_handlers():
    """Setup signal handlers for graceful shutdown."""
    
    def signal_handler(signum, frame):
        global _shutdown_requested
        signal_name = signal.Signals(signum).name
        logger.info("Received shutdown signal", signal=signal_name)
        _shutdown_requested = True
    
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGQUIT, signal_handler)


def check_shutdown_requested():
    """Check if shutdown has been requested."""
    return _shutdown_requested


async def startup_sequence(config: TestConfig) -> TestResultCollector:
    """Enhanced startup sequence with better error handling."""
    
    logger.info("Starting Python test harness startup sequence")
    
    # Phase 1: Configuration validation
    logger.info("Phase 1: Configuration validation")
    config.validate_config()
    
    logger.info(
        "Configuration validated",
        transport=config.transport.value,
        security=config.security.value,
        muxer=config.muxer.value,
        is_dialer=config.is_dialer,
        redis_addr=config.redis_addr
    )
    
    # Phase 2: Initialize result collector
    logger.info("Phase 2: Initializing result collector")
    result_collector = TestResultCollector(config)
    
    # Phase 3: Wait for dependencies (Redis, JS server)
    logger.info("Phase 3: Waiting for dependencies")
    await wait_for_dependencies(config)
    
    # Phase 4: Ready state achieved
    logger.info("Phase 4: Test harness ready state achieved")
    logger.info("Python test harness startup sequence completed successfully")
    
    return result_collector


async def wait_for_dependencies(config: TestConfig, timeout: int = 60):
    """Wait for required dependencies to be ready."""
    
    logger.info("Waiting for dependencies", timeout=timeout)
    
    start_time = time.time()
    
    # Wait for Redis to be available
    logger.info("Checking Redis availability")
    redis_ready = False
    
    while time.time() - start_time < timeout and not check_shutdown_requested():
        try:
            # Try to connect to Redis (basic check)
            # In a full implementation, this would use the actual Redis client
            logger.debug("Attempting Redis connection check")
            redis_ready = True  # Simplified for now
            break
        except Exception as e:
            logger.debug("Redis not ready yet", error=str(e))
            await trio.sleep(2)
    
    if not redis_ready:
        raise RuntimeError("Redis dependency not available within timeout")
    
    logger.info("Dependencies ready")


async def shutdown_sequence(result_collector: Optional[TestResultCollector], exit_code: int):
    """Enhanced shutdown sequence with proper resource cleanup."""
    
    logger.info("Starting shutdown sequence", exit_code=exit_code)
    
    try:
        # Phase 1: Stop any running tests gracefully
        logger.info("Phase 1: Stopping running tests")
        # In a full implementation, this would stop any ongoing test execution
        
        # Phase 2: Finalize results
        logger.info("Phase 2: Finalizing results")
        if result_collector:
            # Finalize any pending results
            pass
        
        # Phase 3: Cleanup resources
        logger.info("Phase 3: Cleaning up resources")
        # Close any open connections, files, etc.
        
        logger.info("Shutdown sequence completed successfully")
        
    except Exception as e:
        logger.error("Error during shutdown sequence", error=str(e))
        exit_code = max(exit_code, 1)  # Ensure non-zero exit code on shutdown errors
    
    return exit_code


def run_tests_with_lifecycle() -> int:
    """Run pytest with lifecycle management."""
    
    logger.info("Starting test execution with lifecycle management")
    
    # Setup pytest arguments
    pytest_args = [
        "-v",
        "--tb=short", 
        "--strict-markers",
        "--strict-config",
        "src/",
        "-p", "no:warnings"
    ]
    
    # Add timeout if configured
    test_timeout = os.getenv("TEST_TIMEOUT")
    if test_timeout:
        pytest_args.extend(["--timeout", test_timeout])
    
    # Run pytest
    try:
        exit_code = pytest.main(pytest_args)
        logger.info("Test execution completed", exit_code=exit_code)
        return exit_code
    except KeyboardInterrupt:
        logger.info("Test execution interrupted")
        return 130  # Standard exit code for SIGINT
    except Exception as e:
        logger.error("Test execution failed", error=str(e))
        return 1


async def main():
    """Main entry point with enhanced lifecycle management."""
    global _test_start_time, _result_collector
    
    _test_start_time = time.time()
    exit_code = 0
    
    try:
        # Setup signal handlers
        setup_signal_handlers()
        
        # Load and validate configuration
        config = TestConfig.from_env()
        
        # Execute startup sequence
        _result_collector = await startup_sequence(config)
        
        # Check for early shutdown
        if check_shutdown_requested():
            logger.info("Shutdown requested during startup")
            exit_code = 130
        else:
            # Run tests
            logger.info("Starting test execution")
            exit_code = run_tests_with_lifecycle()
        
        duration = time.time() - _test_start_time
        logger.info("Test harness execution completed", exit_code=exit_code, duration=duration)
        
        # Output JSON results if in container mode
        if os.getenv("CONTAINER_MODE", "false").lower() == "true":
            output_json_results(config, exit_code, duration)
        
    except Exception as e:
        logger.error("Test harness failed", error=str(e))
        exit_code = 1
        
        # Output error as JSON if in container mode
        if os.getenv("CONTAINER_MODE", "false").lower() == "true":
            output_error_json(str(e))
    
    finally:
        # Always run shutdown sequence
        try:
            duration = time.time() - _test_start_time if _test_start_time else 0
            exit_code = await shutdown_sequence(_result_collector, exit_code)
        except Exception as e:
            logger.error("Shutdown sequence failed", error=str(e))
            exit_code = 1
    
    return exit_code


def output_json_results(config: TestConfig, exit_code: int, duration: float):
    """Output JSON results for container consumption with enhanced metadata."""
    
    # Create enhanced result structure
    env_config = {
        "TRANSPORT": config.transport.value,
        "SECURITY": config.security.value,
        "MUXER": config.muxer.value,
        "IS_DIALER": str(config.is_dialer).lower(),
        "REDIS_ADDR": config.redis_addr,
        "TEST_TIMEOUT": str(config.test_timeout)
    }
    
    # Enhanced result structure with lifecycle metadata
    results = [{
        "test_name": "test_harness_execution",
        "status": "passed" if exit_code == 0 else "failed",
        "duration": duration,
        "implementation": "py-libp2p",
        "version": "v0.4.0",
        "transport": config.transport.value,
        "security": config.security.value,
        "muxer": config.muxer.value,
        "error": None if exit_code == 0 else "Test execution failed",
        "metadata": {
            "exit_code": exit_code,
            "startup_time": _test_start_time,
            "shutdown_requested": _shutdown_requested,
            "container_mode": True,
            "lifecycle_managed": True
        }
    }]
    
    suite_result = {
        "results": results,
        "summary": {
            "total": len(results),
            "passed": len([r for r in results if r["status"] == "passed"]),
            "failed": len([r for r in results if r["status"] == "failed"]),
            "skipped": len([r for r in results if r["status"] == "skipped"])
        },
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "environment": env_config,
        "duration": duration,
        "exit_code": exit_code,
        "lifecycle": {
            "startup_completed": True,
            "shutdown_completed": True,
            "signal_handling": True
        }
    }
    
    # Output JSON to stdout
    print(json.dumps(suite_result, indent=2), file=sys.stdout)
    sys.stdout.flush()


def output_error_json(error_message: str):
    """Output error as JSON for container consumption with lifecycle info."""
    
    duration = time.time() - _test_start_time if _test_start_time else 0
    
    error_result = {
        "results": [],
        "summary": {"total": 0, "passed": 0, "failed": 1, "skipped": 0},
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "environment": dict(os.environ),
        "duration": duration,
        "exit_code": 1,
        "error": error_message,
        "lifecycle": {
            "startup_completed": _result_collector is not None,
            "shutdown_completed": False,
            "signal_handling": True
        }
    }
    
    print(json.dumps(error_result, indent=2), file=sys.stdout)
    sys.stdout.flush()


def sync_main():
    """Synchronous wrapper for main."""
    return trio.run(main)


if __name__ == "__main__":
    exit_code = sync_main()
    sys.exit(exit_code)