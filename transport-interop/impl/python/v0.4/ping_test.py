#!/usr/bin/env python3
"""
Python libp2p ping test implementation for transport-interop tests.

This implementation follows the transport-interop test specification:
- Reads configuration from environment variables
- Connects to Redis for coordination
- Implements both dialer and listener roles
- Measures ping RTT and handshake times
- Outputs results in JSON format to stdout
"""

import json
import logging
import os
import sys
import time
from typing import Optional

import redis
import trio
import multiaddr
from libp2p import new_host, create_yamux_muxer_option, create_mplex_muxer_option
from libp2p.custom_types import TProtocol
from libp2p.network.stream.net_stream import INetStream
from libp2p.peer.peerinfo import info_from_p2p_addr
from libp2p.security.noise.transport import PROTOCOL_ID as NOISE_PROTOCOL_ID, Transport as NoiseTransport
from libp2p.security.insecure.transport import PLAINTEXT_PROTOCOL_ID, InsecureTransport
from libp2p.utils.address_validation import get_available_interfaces
from libp2p.crypto.secp256k1 import create_new_key_pair
from libp2p.crypto.x25519 import create_new_key_pair as create_new_x25519_key_pair

PING_PROTOCOL_ID = TProtocol("/ipfs/ping/1.0.0")
PING_LENGTH = 32
RESP_TIMEOUT = 60

# Get logger for this module - will automatically use py-libp2p's logging system
# when LIBP2P_DEBUG is set, otherwise will be disabled
logger = logging.getLogger("libp2p.ping_test")

# Configure logging for TCP tests
def configure_logging():
    """Configure logging for TCP interop tests."""
    # Set root logger to INFO level to see important messages
    logging.getLogger().setLevel(logging.INFO)
    
    # Keep our own logging at INFO level for important messages
    logging.getLogger("libp2p.ping_test").setLevel(logging.INFO)
    
    # Suppress some noisy modules
    logging.getLogger("multiaddr").setLevel(logging.WARNING)
    logging.getLogger("multiaddr.transforms").setLevel(logging.WARNING)
    logging.getLogger("multiaddr.codecs").setLevel(logging.WARNING)
    logging.getLogger("libp2p").setLevel(logging.WARNING)
    logging.getLogger("libp2p.transport").setLevel(logging.WARNING)


class PingTest:
    def __init__(self):
        # Read environment variables
        self.transport = os.getenv("transport", "tcp")
        self.muxer = os.getenv("muxer", "mplex")
        self.security = os.getenv("security", "noise")
        self.is_dialer = os.getenv("is_dialer", "false").lower() == "true"
        self.ip = os.getenv("ip", "0.0.0.0")
        self.redis_addr = os.getenv("redis_addr", "redis:6379")
        self.test_timeout_seconds = int(os.getenv("test_timeout_seconds", "30"))
        
        # Parse Redis address
        if ":" in self.redis_addr:
            self.redis_host, self.redis_port = self.redis_addr.split(":")
            self.redis_port = int(self.redis_port)
        else:
            self.redis_host = self.redis_addr
            self.redis_port = 6379
        
        self.host = None
        self.redis_client: Optional[redis.Redis] = None

    def setup_redis(self) -> None:
        """Set up Redis connection."""
        self.redis_client = redis.Redis(
            host=self.redis_host,
            port=self.redis_port,
            decode_responses=True
        )
        self.redis_client.ping()
        print(f"Connected to Redis at {self.redis_host}:{self.redis_port}", file=sys.stderr)

    def validate_configuration(self) -> None:
        """Validate the configuration parameters."""
        # Validate transport - TCP only
        if self.transport not in ["tcp"]:
            raise ValueError(f"Unsupported transport: {self.transport}. Supported transports: ['tcp']")
        
        # Validate security
        if self.security not in ["noise", "plaintext"]:
            raise ValueError(f"Unsupported security: {self.security}. Supported security: ['noise', 'plaintext']")
        
        # Validate muxer
        if self.muxer not in ["mplex", "yamux"]:
            raise ValueError(f"Unsupported muxer: {self.muxer}. Supported muxers: ['mplex', 'yamux']")

    def create_security_options(self):
        """Create security options based on configuration."""
        # Create key pair for libp2p identity
        key_pair = create_new_key_pair()
        
        if self.security == "noise":
            # Create X25519 key pair for Noise
            noise_key_pair = create_new_x25519_key_pair()
            noise_transport = NoiseTransport(
                libp2p_keypair=key_pair,
                noise_privkey=noise_key_pair.private_key,
                early_data=None,
            )
            return {NOISE_PROTOCOL_ID: noise_transport}, key_pair
        elif self.security == "plaintext":
            insecure_transport = InsecureTransport(
                local_key_pair=key_pair,
                secure_bytes_provider=None,
                peerstore=None,
            )
            return {PLAINTEXT_PROTOCOL_ID: insecure_transport}, key_pair

        else:
            raise ValueError(f"Unsupported security: {self.security}")

    def create_muxer_options(self):
        """Create muxer options based on configuration."""
        if self.muxer == "yamux":
            return create_yamux_muxer_option()
        elif self.muxer == "mplex":
            return create_mplex_muxer_option()
        else:
            raise ValueError(f"Unsupported muxer: {self.muxer}")


    async def handle_ping(self, stream: INetStream) -> None:
        """Handle incoming ping requests."""
        try:
            # Only process one ping request to avoid excessive pong responses
            payload = await stream.read(PING_LENGTH)
            # Get peer ID safely, suppressing warnings
            import warnings
            with warnings.catch_warnings():
                warnings.simplefilter("ignore")
                try:
                    peer_id = stream.muxed_conn.peer_id
                except (AttributeError, Exception):
                    peer_id = "unknown"
            if payload is not None:
                print(f"received ping from {peer_id}", file=sys.stderr)
                await stream.write(payload)
                print(f"responded with pong to {peer_id}", file=sys.stderr)
        except Exception as e:
            print(f"Error in ping handler: {e}", file=sys.stderr)
            await stream.reset()

    async def send_ping(self, stream: INetStream) -> float:
        """Send ping and measure RTT."""
        try:
            payload = b"\x01" * PING_LENGTH
            # Get peer ID safely, suppressing warnings
            import warnings
            with warnings.catch_warnings():
                warnings.simplefilter("ignore")
                try:
                    peer_id = stream.muxed_conn.peer_id
                except (AttributeError, Exception):
                    peer_id = "unknown"
            print(f"sending ping to {peer_id}", file=sys.stderr)
            
            ping_start = time.time()
            await stream.write(payload)
            
            with trio.fail_after(RESP_TIMEOUT):
                response = await stream.read(PING_LENGTH)
                ping_end = time.time()
                
                if response == payload:
                    print(f"received pong from {peer_id}", file=sys.stderr)
                    return (ping_end - ping_start) * 1000  # Convert to milliseconds
                else:
                    raise Exception("Invalid ping response")
        except Exception as e:
            print(f"error occurred: {e}", file=sys.stderr)
            raise

    async def run_listener(self) -> None:
        """Run the listener role."""
        # Validate configuration
        self.validate_configuration()

        # Create security and muxer options
        security_options, key_pair = self.create_security_options()
        muxer_options = self.create_muxer_options()
        
        # Use get_available_interfaces() for proper address handling (current best practice)
        port = 0  # Let OS assign a free port
        listen_addrs = get_available_interfaces(port, protocol="tcp")
        
        # Create host with proper configuration
        self.host = new_host(
            key_pair=key_pair,
            sec_opt=security_options,
            muxer_opt=muxer_options,
            listen_addrs=listen_addr
        )
        # Set up ping handler
        self.host.set_stream_handler(PING_PROTOCOL_ID, self.handle_ping)
        
        # Start the host
        async with self.host.run(listen_addrs=listen_addrs):
            # Get the actual listen addresses and publish to Redis
            all_addrs = self.host.get_addrs()
            if not all_addrs:
                raise RuntimeError("No listen addresses available")
            
            # For Docker networking, prefer non-loopback addresses
            # get_available_interfaces() already handles this, but we may need to replace loopback
            actual_addr = None
            for addr in all_addrs:
                addr_str = str(addr)
                # Prefer non-loopback addresses for Docker
                if "/ip4/127.0.0.1/" not in addr_str and "/ip4/0.0.0.0/" not in addr_str:
                    actual_addr = addr_str
                    break
            
            # Fallback to first address, replacing loopback if needed
            if not actual_addr:
                addr_str = str(all_addrs[0])
                if "/ip4/127.0.0.1/" in addr_str or "/ip4/0.0.0.0/" in addr_str:
                    # Get container IP and replace
                    actual_ip = self.get_container_ip()
                    if "/ip4/0.0.0.0/" in addr_str:
                        actual_addr = addr_str.replace("/ip4/0.0.0.0/", f"/ip4/{actual_ip}/")
                    elif "/ip4/127.0.0.1/" in addr_str:
                        actual_addr = addr_str.replace("/ip4/127.0.0.1/", f"/ip4/{actual_ip}/")
                else:
                    actual_addr = addr_str
            
            self.redis_client.rpush("listenerAddr", actual_addr)
            print(f"Listener ready, waiting for dialer to connect for {self.test_timeout_seconds} seconds...", file=sys.stderr)
            await trio.sleep(self.test_timeout_seconds)
            # If we reach here, the dialer didn't complete within timeout
            sys.exit(1)

    async def run_dialer(self) -> None:
        """Run the dialer role."""
        print("Running as dialer", file=sys.stderr)
        
        try:
            # Validate configuration
            self.validate_configuration()
            
            # Connect to Redis with retry mechanism
            print("Connecting to Redis...", file=sys.stderr)
            max_retries = 10
            retry_delay = 1.0
            
            for attempt in range(max_retries):
                try:
                    self.redis_client = redis.Redis(host=self.redis_host, port=self.redis_port, decode_responses=True)
                    # Test the connection
                    self.redis_client.ping()
                    print(f"Successfully connected to Redis on attempt {attempt + 1}", file=sys.stderr)
                    break
                except Exception as e:
                    print(f"Redis connection attempt {attempt + 1} failed: {e}", file=sys.stderr)
                    if attempt < max_retries - 1:
                        print(f"Retrying in {retry_delay} seconds...", file=sys.stderr)
                        await trio.sleep(retry_delay)
                    else:
                        raise RuntimeError(f"Failed to connect to Redis after {max_retries} attempts")
            
            # Get the listener's address from Redis
            print("Waiting for listener address from Redis...", file=sys.stderr)
            result = self.redis_client.blpop("listenerAddr", timeout=self.test_timeout_seconds)
            if not result:
                raise RuntimeError("Timeout waiting for listener address")
            
            listener_addr = result[1]
            print(f"Got listener address: {listener_addr}", file=sys.stderr)
            
            # Create security and muxer options
            security_options, key_pair = self.create_security_options()
            muxer_options = self.create_muxer_options()
            
            # Create host with proper configuration
            self.host = new_host(
                key_pair=key_pair,
                sec_opt=security_options,
                muxer_opt=muxer_options
            )
            
            # Start the host
            async with self.host.run(listen_addrs=[]):
                # Record handshake start time
                handshake_start = time.time()
                
                # Parse the multiaddr and connect
                maddr = multiaddr.Multiaddr(listener_addr)
                info = info_from_p2p_addr(maddr)
                
                print(f"Connecting to {listener_addr}", file=sys.stderr)
                await self.host.connect(info)
                print("Connected successfully", file=sys.stderr)
                
                # Create ping stream
                print("Creating ping stream", file=sys.stderr)
                stream = await self.host.new_stream(info.peer_id, [PING_PROTOCOL_ID])
                print("Ping stream created successfully", file=sys.stderr)
                
                # Perform ping and measure RTT
                print("Performing ping test", file=sys.stderr)
                ping_rtt = await self.send_ping(stream)
                print(f"Ping test completed, RTT: {ping_rtt}ms", file=sys.stderr)
                
                # Calculate handshake plus one RTT
                handshake_plus_one_rtt = (time.time() - handshake_start) * 1000  # Convert to milliseconds
                
                # Output results in JSON format
                result = {
                    "handshakePlusOneRTTMillis": handshake_plus_one_rtt,
                    "pingRTTMilllis": ping_rtt
                }
                print(f"Outputting results: {result}", file=sys.stderr)
                print(json.dumps(result))
                
                # Close stream
                await stream.close()
                print("Stream closed successfully", file=sys.stderr)
                
        except Exception as e:
            print(f"Dialer error: {e}", file=sys.stderr)
            import traceback
            traceback.print_exc(file=sys.stderr)
            sys.exit(1)

    async def run(self) -> None:
        """Main run method."""
        try:
            # Set up Redis connection with retry mechanism
            print("Setting up Redis connection...", file=sys.stderr)
            max_retries = 10
            retry_delay = 1.0
            
            for attempt in range(max_retries):
                try:
                    self.setup_redis()
                    print(f"Successfully connected to Redis on attempt {attempt + 1}", file=sys.stderr)
                    break
                except Exception as e:
                    print(f"Redis connection attempt {attempt + 1} failed: {e}", file=sys.stderr)
                    if attempt < max_retries - 1:
                        print(f"Retrying in {retry_delay} seconds...", file=sys.stderr)
                        await trio.sleep(retry_delay)
                    else:
                        raise RuntimeError(f"Failed to connect to Redis after {max_retries} attempts")
            
            # Run the appropriate role
            if self.is_dialer:
                await self.run_dialer()
            else:
                await self.run_listener()
                
        except Exception as e:
            print(f"Error: {e}", file=sys.stderr)
            sys.exit(1)
        finally:
            # Cleanup
            if self.redis_client:
                self.redis_client.close()

    def get_container_ip(self) -> str:
        """Get the container's actual IP address for Docker networking."""
        import socket
        import subprocess
        try:
            # Try hostname -I first (works in most Docker containers)
            try:
                result = subprocess.run(['hostname', '-I'], capture_output=True, text=True, timeout=5)
                if result.returncode == 0 and result.stdout.strip():
                    return result.stdout.strip().split()[0]
            except Exception:
                pass
            
            # Fallback: Connect to a remote address to determine local IP
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
                s.connect(("8.8.8.8", 80))
                return s.getsockname()[0]
        except Exception:
            # Fallback to a reasonable default
            return "172.17.0.1"


async def main():
    """Main entry point."""
    # Configure logging to reduce debug output
    configure_logging()
    
    ping_test = PingTest()
    await ping_test.run()


if __name__ == "__main__":
    trio.run(main)
