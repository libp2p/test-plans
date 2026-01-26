"""Configuration management for the Python test harness."""

import os
import structlog
from typing import Optional
from pydantic import BaseModel, Field
from enum import Enum


class TransportType(str, Enum):
    """Supported transport protocols."""
    TCP = "tcp"
    QUIC = "quic"
    WEBSOCKET = "websocket"


class SecurityType(str, Enum):
    """Supported security protocols."""
    NOISE = "noise"
    TLS = "tls"


class MuxerType(str, Enum):
    """Supported stream multiplexers."""
    YAMUX = "yamux"
    MPLEX = "mplex"


class ConnectionRole(str, Enum):
    """Connection role."""
    DIALER = "dialer"
    LISTENER = "listener"


class TestConfig(BaseModel):
    """Test configuration from environment variables."""
    
    # Protocol stack configuration
    transport: TransportType = Field(default=TransportType.TCP)
    security: SecurityType = Field(default=SecurityType.NOISE)
    muxer: MuxerType = Field(default=MuxerType.YAMUX)
    
    # Connection configuration
    is_dialer: bool = Field(default=True)
    
    # Redis coordination
    redis_addr: str = Field(default="redis:6379")
    redis_key: str = Field(default="multiaddr")
    redis_timeout: int = Field(default=30)
    
    # Test timeouts
    connection_timeout: int = Field(default=10)
    test_timeout: int = Field(default=30)
    protocol_negotiation_timeout: int = Field(default=5)
    
    # Retry configuration
    max_retries: int = Field(default=3)
    retry_delay: float = Field(default=1.0)
    max_retry_delay: float = Field(default=60.0)
    retry_backoff_factor: float = Field(default=2.0)
    retry_jitter: bool = Field(default=True)
    
    # Error handling configuration
    fail_fast: bool = Field(default=False)
    log_level: str = Field(default="INFO")
    
    @classmethod
    def from_env(cls) -> "TestConfig":
        """Create configuration from environment variables."""
        return cls(
            transport=TransportType(os.getenv("TRANSPORT", "tcp").lower()),
            security=SecurityType(os.getenv("SECURITY", "noise").lower()),
            muxer=MuxerType(os.getenv("MUXER", "yamux").lower()),
            is_dialer=os.getenv("IS_DIALER", "true").lower() == "true",
            redis_addr=os.getenv("REDIS_ADDR", "redis:6379"),
            redis_key=os.getenv("REDIS_KEY", "multiaddr"),
            redis_timeout=int(os.getenv("REDIS_TIMEOUT", "30")),
            connection_timeout=int(os.getenv("CONNECTION_TIMEOUT", "10")),
            test_timeout=int(os.getenv("TEST_TIMEOUT", "30")),
            protocol_negotiation_timeout=int(os.getenv("PROTOCOL_NEGOTIATION_TIMEOUT", "5")),
            max_retries=int(os.getenv("MAX_RETRIES", "3")),
            retry_delay=float(os.getenv("RETRY_DELAY", "1.0")),
            max_retry_delay=float(os.getenv("MAX_RETRY_DELAY", "60.0")),
            retry_backoff_factor=float(os.getenv("RETRY_BACKOFF_FACTOR", "2.0")),
            retry_jitter=os.getenv("RETRY_JITTER", "true").lower() == "true",
            fail_fast=os.getenv("FAIL_FAST", "false").lower() == "true",
            log_level=os.getenv("LOG_LEVEL", "INFO").upper()
        )
    
    def validate_config(self) -> None:
        """Validate configuration compatibility and constraints with comprehensive error checking."""
        logger = structlog.get_logger(__name__)
        
        # Protocol stack compatibility validation
        self._validate_protocol_stack_compatibility()
        
        # Timeout validation with reasonable bounds
        self._validate_timeout_configuration()
        
        # Retry configuration validation
        self._validate_retry_configuration()
        
        # Redis configuration validation
        self._validate_redis_configuration()
        
        # Role-specific validation
        self._validate_role_configuration()
        
        # Log level validation
        self._validate_log_level()
        
        # Performance and reliability warnings
        self._check_performance_warnings()
        
        logger.info("Configuration validation completed successfully", config=self.dict())
    
    def _validate_protocol_stack_compatibility(self) -> None:
        """Validate protocol stack combinations for compatibility."""
        # Transport-specific validations
        if self.transport == TransportType.QUIC:
            # QUIC has built-in encryption, but we still allow explicit security protocols
            if self.security == SecurityType.TLS:
                # QUIC already uses TLS 1.3, this is redundant but not invalid
                pass
            elif self.security == SecurityType.NOISE:
                # Noise over QUIC is unusual but technically possible
                pass
        
        elif self.transport == TransportType.TCP:
            # TCP requires explicit security
            if self.security not in [SecurityType.NOISE, SecurityType.TLS]:
                raise ValueError(f"TCP transport requires explicit security protocol, got: {self.security}")
        
        elif self.transport == TransportType.WEBSOCKET:
            # WebSocket can work with both security protocols
            if self.security not in [SecurityType.NOISE, SecurityType.TLS]:
                raise ValueError(f"WebSocket transport requires explicit security protocol, got: {self.security}")
            
            # WebSocket currently only supports dialer role in our implementation
            if not self.is_dialer:
                raise ValueError("WebSocket transport only supports dialer role in current implementation")
        
        # Muxer compatibility validation
        if self.muxer not in [MuxerType.YAMUX, MuxerType.MPLEX]:
            raise ValueError(f"Unsupported muxer: {self.muxer}. Supported: {[m.value for m in MuxerType]}")
        
        # Known problematic combinations
        problematic_combinations = [
            # Add any known problematic combinations here
            # Example: (TransportType.WEBSOCKET, SecurityType.NOISE, MuxerType.MPLEX)
        ]
        
        current_combination = (self.transport, self.security, self.muxer)
        if current_combination in problematic_combinations:
            raise ValueError(f"Known problematic protocol combination: {current_combination}")
    
    def _validate_timeout_configuration(self) -> None:
        """Validate timeout values with reasonable bounds."""
        timeout_configs = [
            ("connection_timeout", self.connection_timeout, 1, 300),  # 1s to 5min
            ("test_timeout", self.test_timeout, 5, 1800),  # 5s to 30min
            ("protocol_negotiation_timeout", self.protocol_negotiation_timeout, 1, 60),  # 1s to 1min
            ("redis_timeout", self.redis_timeout, 1, 600),  # 1s to 10min
        ]
        
        for name, value, min_val, max_val in timeout_configs:
            if value <= 0:
                raise ValueError(f"{name} must be positive, got: {value}")
            
            if value < min_val:
                raise ValueError(f"{name} too small: {value}s. Minimum recommended: {min_val}s")
            
            if value > max_val:
                raise ValueError(f"{name} too large: {value}s. Maximum recommended: {max_val}s")
        
        # Logical timeout relationships
        if self.protocol_negotiation_timeout >= self.connection_timeout:
            raise ValueError(
                f"Protocol negotiation timeout ({self.protocol_negotiation_timeout}s) "
                f"should be less than connection timeout ({self.connection_timeout}s)"
            )
        
        if self.connection_timeout >= self.test_timeout:
            raise ValueError(
                f"Connection timeout ({self.connection_timeout}s) "
                f"should be less than test timeout ({self.test_timeout}s)"
            )
    
    def _validate_retry_configuration(self) -> None:
        """Validate retry configuration parameters."""
        if self.max_retries < 0:
            raise ValueError(f"max_retries must be non-negative, got: {self.max_retries}")
        
        if self.max_retries > 20:
            raise ValueError(f"max_retries too high: {self.max_retries}. Maximum recommended: 20")
        
        if self.retry_delay <= 0:
            raise ValueError(f"retry_delay must be positive, got: {self.retry_delay}")
        
        if self.retry_delay > 30:
            raise ValueError(f"retry_delay too large: {self.retry_delay}s. Maximum recommended: 30s")
        
        if self.max_retry_delay <= 0:
            raise ValueError(f"max_retry_delay must be positive, got: {self.max_retry_delay}")
        
        if self.max_retry_delay > 300:
            raise ValueError(f"max_retry_delay too large: {self.max_retry_delay}s. Maximum recommended: 300s")
        
        if self.retry_backoff_factor <= 1.0:
            raise ValueError(f"retry_backoff_factor must be > 1.0, got: {self.retry_backoff_factor}")
        
        if self.retry_backoff_factor > 10.0:
            raise ValueError(f"retry_backoff_factor too large: {self.retry_backoff_factor}. Maximum recommended: 10.0")
        
        if self.retry_delay >= self.max_retry_delay:
            raise ValueError(
                f"retry_delay ({self.retry_delay}s) should be less than "
                f"max_retry_delay ({self.max_retry_delay}s)"
            )
        
        # Calculate maximum total retry time to warn about excessive delays
        if self.max_retries > 0:
            total_retry_time = self._calculate_max_retry_time()
            if total_retry_time > 600:  # 10 minutes
                raise ValueError(
                    f"Retry configuration would result in excessive total retry time: {total_retry_time:.1f}s. "
                    f"Consider reducing max_retries, retry_delay, or retry_backoff_factor."
                )
    
    def _calculate_max_retry_time(self) -> float:
        """Calculate maximum possible total retry time."""
        if self.max_retries == 0:
            return 0.0
        
        total_time = 0.0
        current_delay = self.retry_delay
        
        for _ in range(self.max_retries):
            total_time += min(current_delay, self.max_retry_delay)
            current_delay *= self.retry_backoff_factor
        
        return total_time
    
    def _validate_redis_configuration(self) -> None:
        """Validate Redis connection configuration."""
        if not self.redis_addr:
            raise ValueError("redis_addr cannot be empty")
        
        if not self.redis_key:
            raise ValueError("redis_key cannot be empty")
        
        # Basic format validation for Redis address
        if ":" not in self.redis_addr:
            raise ValueError(f"redis_addr should include port (host:port), got: {self.redis_addr}")
        
        try:
            host, port_str = self.redis_addr.rsplit(":", 1)
            port = int(port_str)
            
            if not host:
                raise ValueError("Redis host cannot be empty")
            
            if port <= 0 or port > 65535:
                raise ValueError(f"Redis port must be 1-65535, got: {port}")
                
        except ValueError as e:
            if "invalid literal for int()" in str(e):
                raise ValueError(f"Invalid Redis port in address: {self.redis_addr}")
            raise
        
        # Redis key validation
        if len(self.redis_key) > 512:
            raise ValueError(f"redis_key too long: {len(self.redis_key)} chars. Maximum: 512")
        
        # Check for potentially problematic characters in Redis key
        invalid_chars = [" ", "\n", "\r", "\t"]
        for char in invalid_chars:
            if char in self.redis_key:
                raise ValueError(f"redis_key contains invalid character: {repr(char)}")
    
    def _validate_role_configuration(self) -> None:
        """Validate role-specific configuration."""
        # Currently, both dialer and listener roles are supported for most configurations
        # Add specific validations as needed
        
        if self.transport == TransportType.WEBSOCKET and not self.is_dialer:
            raise ValueError("WebSocket transport only supports dialer role")
        
        # Future role-specific validations can be added here
    
    def _validate_log_level(self) -> None:
        """Validate logging configuration."""
        valid_log_levels = {"DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"}
        if self.log_level not in valid_log_levels:
            raise ValueError(
                f"Invalid log level: {self.log_level}. "
                f"Must be one of: {', '.join(sorted(valid_log_levels))}"
            )
    
    def _check_performance_warnings(self) -> None:
        """Check for configurations that may impact performance and issue warnings."""
        logger = structlog.get_logger(__name__)
        
        # High retry count warning
        if self.max_retries > 10:
            logger.warning(
                "High retry count may cause long test execution times",
                max_retries=self.max_retries,
                estimated_max_retry_time=f"{self._calculate_max_retry_time():.1f}s"
            )
        
        # Long timeout warnings
        if self.connection_timeout > 60:
            logger.warning(
                "Long connection timeout may cause slow test failures",
                connection_timeout=self.connection_timeout
            )
        
        if self.test_timeout > 300:
            logger.warning(
                "Very long test timeout may mask real issues",
                test_timeout=self.test_timeout
            )
        
        # Debug mode performance warning
        if self.log_level == "DEBUG":
            logger.warning(
                "DEBUG logging enabled - may impact performance in high-throughput tests"
            )
        
        # Retry configuration warnings
        if self.retry_backoff_factor > 5.0:
            logger.warning(
                "High retry backoff factor may cause very long delays",
                retry_backoff_factor=self.retry_backoff_factor
            )
        
        # Protocol-specific performance notes
        if self.transport == TransportType.WEBSOCKET:
            logger.info("WebSocket transport may have higher latency than TCP")
        
        if self.muxer == MuxerType.MPLEX:
            logger.info("Mplex muxer may have different performance characteristics than Yamux")
    
    def get_debug_info(self) -> dict:
        """Get comprehensive configuration information for debugging."""
        return {
            "protocol_stack": {
                "transport": self.transport.value,
                "security": self.security.value,
                "muxer": self.muxer.value,
            },
            "role": "dialer" if self.is_dialer else "listener",
            "timeouts": {
                "connection": self.connection_timeout,
                "test": self.test_timeout,
                "protocol_negotiation": self.protocol_negotiation_timeout,
                "redis": self.redis_timeout,
            },
            "retry_config": {
                "max_retries": self.max_retries,
                "retry_delay": self.retry_delay,
                "max_retry_delay": self.max_retry_delay,
                "backoff_factor": self.retry_backoff_factor,
                "jitter_enabled": self.retry_jitter,
                "estimated_max_retry_time": f"{self._calculate_max_retry_time():.1f}s",
            },
            "redis": {
                "address": self.redis_addr,
                "key": self.redis_key,
                "timeout": self.redis_timeout,
            },
            "logging": {
                "level": self.log_level,
                "fail_fast": self.fail_fast,
            },
        }


# Global configuration instance
config = TestConfig.from_env()