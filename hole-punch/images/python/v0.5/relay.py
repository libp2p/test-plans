#!/usr/bin/env python3
"""
py-libp2p hole-punch test relay server implementation.
"""

import logging
import os
import sys

import multiaddr
import redis
import trio

from libp2p import new_host, create_yamux_muxer_option, create_mplex_muxer_option
from libp2p.crypto.ed25519 import create_new_key_pair
from libp2p.crypto.x25519 import create_new_key_pair as create_new_x25519_key_pair
from libp2p.relay.circuit_v2.protocol import (
    CircuitV2Protocol,
    PROTOCOL_ID,
    STOP_PROTOCOL_ID,
)
from libp2p.relay.circuit_v2.config import RelayConfig, RelayRole
from libp2p.relay.circuit_v2.resources import RelayLimits
from libp2p.relay.circuit_v2.transport import CircuitV2Transport
from libp2p.security.noise.transport import (
    PROTOCOL_ID as NOISE_PROTOCOL_ID,
    Transport as NoiseTransport,
)
from libp2p.security.tls.transport import (
    PROTOCOL_ID as TLS_PROTOCOL_ID,
    TLSTransport,
)
from libp2p.tools.async_service import background_trio_service

logger = logging.getLogger("hole-punch-relay")


class HolePunchRelay:
    def __init__(self):
        self.redis_addr = os.getenv("REDIS_ADDR")
        self.test_key = os.getenv("TEST_KEY")
        self.transport = os.getenv("TRANSPORT", "tcp")
        self.secure_channel = os.getenv("SECURE_CHANNEL")
        self.muxer = os.getenv("MUXER")
        self.relay_ip = os.getenv("RELAY_IP", "0.0.0.0")
        self.debug = os.getenv("DEBUG", "false").lower() == "true"

        # Validate required env vars
        if not self.redis_addr:
            raise ValueError("REDIS_ADDR environment variable is required")
        if not self.test_key:
            raise ValueError("TEST_KEY environment variable is required")

        if ":" in self.redis_addr:
            host, port = self.redis_addr.split(":")
            self.redis_host, self.redis_port = host, int(port)
        else:
            self.redis_host = self.redis_addr
            self.redis_port = 6379

        self.redis_client = None
        self.host = None

    def create_security_options(self):
        """Create security transport options based on SECURE_CHANNEL."""
        key_pair = create_new_key_pair()

        if self.transport == "quic-v1":
            return {}, key_pair

        if self.secure_channel == "noise":
            noise_key_pair = create_new_x25519_key_pair()
            noise_transport = NoiseTransport(
                libp2p_keypair=key_pair,
                noise_privkey=noise_key_pair.private_key,
                early_data=None,
            )
            return {NOISE_PROTOCOL_ID: noise_transport}, key_pair
        elif self.secure_channel == "tls":
            tls_transport = TLSTransport(
                libp2p_keypair=key_pair,
                early_data=None,
                muxers=None,
            )
            return {TLS_PROTOCOL_ID: tls_transport}, key_pair
        else:
            raise ValueError(f"Unsupported secure channel: {self.secure_channel}")

    def create_muxer_options(self):
        """Create muxer options based on MUXER."""
        if self.transport == "quic-v1":
            return None

        if self.muxer == "yamux":
            return create_yamux_muxer_option()
        elif self.muxer == "mplex":
            return create_mplex_muxer_option()
        else:
            raise ValueError(f"Unsupported muxer: {self.muxer}")

    def create_listen_address(self, port: int = 4001):
        """Create listen multiaddr based on transport."""
        if self.transport == "tcp":
            return multiaddr.Multiaddr(f"/ip4/{self.relay_ip}/tcp/{port}")
        elif self.transport == "quic-v1":
            return multiaddr.Multiaddr(f"/ip4/{self.relay_ip}/udp/{port}/quic-v1")
        elif self.transport == "ws":
            return multiaddr.Multiaddr(f"/ip4/{self.relay_ip}/tcp/{port}/ws")
        elif self.transport == "wss":
            return multiaddr.Multiaddr(f"/ip4/{self.relay_ip}/tcp/{port}/wss")
        else:
            raise ValueError(f"Unsupported transport: {self.transport}")

    async def connect_redis(self):
        """Connect to Redis with retry."""
        print(f"Connecting to Redis at {self.redis_host}:{self.redis_port}...", file=sys.stderr)
        for attempt in range(10):
            try:
                self.redis_client = redis.Redis(
                    host=self.redis_host,
                    port=self.redis_port,
                    decode_responses=True
                )
                self.redis_client.ping()
                print(f"Connected to Redis on attempt {attempt + 1}", file=sys.stderr)
                return
            except Exception as e:
                print(f"Redis connection attempt {attempt + 1} failed: {e}", file=sys.stderr)
                if attempt < 9:
                    await trio.sleep(1)
        raise RuntimeError("Failed to connect to Redis after 10 attempts")

    async def run(self):
        """Run the relay server."""
        print("Starting RELAY server...", file=sys.stderr)
        print(f"  TRANSPORT: {self.transport}", file=sys.stderr)
        print(f"  SECURE_CHANNEL: {self.secure_channel}", file=sys.stderr)
        print(f"  MUXER: {self.muxer}", file=sys.stderr)
        print(f"  RELAY_IP: {self.relay_ip}", file=sys.stderr)

        await self.connect_redis()

        sec_opt, key_pair = self.create_security_options()
        muxer_opt = self.create_muxer_options()
        listen_addr = self.create_listen_address(4001)

        self.host = new_host(
            key_pair=key_pair,
            sec_opt=sec_opt,
            muxer_opt=muxer_opt,
            enable_quic=(self.transport == "quic-v1"),
        )

        # Configure relay with HOP capability (allows relaying)
        limits = RelayLimits(
            duration=3600,
            data=100 * 1024 * 1024,  # 100 MB
            max_circuit_conns=10,
            max_reservations=5,
        )

        relay_config = RelayConfig(
            roles=RelayRole.HOP | RelayRole.STOP | RelayRole.CLIENT,
            limits=limits,
        )

        relay_protocol = CircuitV2Protocol(self.host, limits=limits, allow_hop=True)

        async with self.host.run(listen_addrs=[listen_addr]):
            # Register protocol handlers
            self.host.set_stream_handler(PROTOCOL_ID, relay_protocol._handle_hop_stream)
            self.host.set_stream_handler(STOP_PROTOCOL_ID, relay_protocol._handle_stop_stream)

            async with background_trio_service(relay_protocol):
                await relay_protocol.event_started.wait()

                # Initialize transport
                CircuitV2Transport(self.host, relay_protocol, relay_config)

                # Get our multiaddr
                peer_id = str(self.host.get_id())
                addrs = self.host.get_addrs()

                print(f"Relay peer ID: {peer_id}", file=sys.stderr)
                print(f"Relay addresses: {[str(a) for a in addrs]}", file=sys.stderr)

                # Find the non-localhost address
                relay_multiaddr = None
                for addr in addrs:
                    addr_str = str(addr)
                    if "127.0.0.1" not in addr_str and "::1" not in addr_str:
                        # Check if peer ID is already in the address
                        if f"/p2p/{peer_id}" in addr_str:
                            relay_multiaddr = addr_str
                        else:
                            relay_multiaddr = f"{addr_str}/p2p/{peer_id}"
                        break

                if not relay_multiaddr:
                    # Fallback to first address
                    addr_str = str(addrs[0])
                    if f"/p2p/{peer_id}" in addr_str:
                        relay_multiaddr = addr_str
                    else:
                        relay_multiaddr = f"{addr_str}/p2p/{peer_id}"

                print(f"Relay multiaddr: {relay_multiaddr}", file=sys.stderr)

                # Publish to Redis
                redis_key = f"{self.test_key}_relay_multiaddr"
                self.redis_client.set(redis_key, relay_multiaddr)
                print(f"Published relay multiaddr to Redis key: {redis_key}", file=sys.stderr)

                print("Relay server ready, accepting connections...", file=sys.stderr)

                # Run forever
                await trio.sleep_forever()


def configure_logging():
    """Configure logging based on DEBUG env var."""
    debug = os.getenv("DEBUG", "false").lower() in ["true", "1", "yes", "debug"]
    level = logging.DEBUG if debug else logging.INFO
    logging.basicConfig(
        level=level,
        format="%(asctime)s | %(name)s | %(levelname)s | %(message)s",
        stream=sys.stderr,
    )
    # Suppress overly verbose loggers
    if not debug:
        logging.getLogger("libp2p").setLevel(logging.WARNING)


async def main():
    configure_logging()
    try:
        relay = HolePunchRelay()
        await relay.run()
    except Exception as e:
        print(f"Fatal error: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc(file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    trio.run(main)
