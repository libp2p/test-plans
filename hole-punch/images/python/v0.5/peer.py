#!/usr/bin/env python3
"""
py-libp2p hole-punch test peer implementation.
Handles both dialer and listener roles for DCUtR interop testing.
"""

import logging
import os
import sys
import time

import multiaddr
import redis
import trio

from libp2p import new_host, create_yamux_muxer_option, create_mplex_muxer_option
from libp2p.crypto.ed25519 import create_new_key_pair
from libp2p.crypto.x25519 import create_new_key_pair as create_new_x25519_key_pair
from libp2p.peer.peerinfo import info_from_p2p_addr, PeerInfo
from libp2p.peer.id import ID
from libp2p.relay.circuit_v2.dcutr import DCUtRProtocol
from libp2p.relay.circuit_v2.protocol import CircuitV2Protocol, DEFAULT_RELAY_LIMITS
from libp2p.relay.circuit_v2.config import RelayConfig, RelayRole
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

logger = logging.getLogger("hole-punch-peer")


class HolePunchPeer:
    def __init__(self):
        # Required environment variables
        self.is_dialer = os.getenv("IS_DIALER", "false").lower() == "true"
        self.redis_addr = os.getenv("REDIS_ADDR")
        self.test_key = os.getenv("TEST_KEY")
        self.transport = os.getenv("TRANSPORT", "tcp")
        self.secure_channel = os.getenv("SECURE_CHANNEL")  # May be None for QUIC
        self.muxer = os.getenv("MUXER")  # May be None for QUIC
        self.peer_ip = os.getenv("PEER_IP", "0.0.0.0")
        self.router_ip = os.getenv("ROUTER_IP")
        self.debug = os.getenv("DEBUG", "false").lower() == "true"

        # Validate required env vars
        if not self.redis_addr:
            raise ValueError("REDIS_ADDR environment variable is required")
        if not self.test_key:
            raise ValueError("TEST_KEY environment variable is required")

        # Parse Redis address
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

        # Standalone transports (QUIC) have built-in security
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
            return None  # QUIC has built-in muxing

        if self.muxer == "yamux":
            return create_yamux_muxer_option()
        elif self.muxer == "mplex":
            return create_mplex_muxer_option()
        else:
            raise ValueError(f"Unsupported muxer: {self.muxer}")

    def create_listen_address(self, port: int = 0):
        """Create listen multiaddr based on transport."""
        if self.transport == "tcp":
            return multiaddr.Multiaddr(f"/ip4/{self.peer_ip}/tcp/{port}")
        elif self.transport == "quic-v1":
            return multiaddr.Multiaddr(f"/ip4/{self.peer_ip}/udp/{port}/quic-v1")
        elif self.transport == "ws":
            return multiaddr.Multiaddr(f"/ip4/{self.peer_ip}/tcp/{port}/ws")
        elif self.transport == "wss":
            return multiaddr.Multiaddr(f"/ip4/{self.peer_ip}/tcp/{port}/wss")
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

    async def run_listener(self):
        """Run as listener (IS_DIALER=false)."""
        print("Starting as LISTENER...", file=sys.stderr)
        print(f"  TRANSPORT: {self.transport}", file=sys.stderr)
        print(f"  SECURE_CHANNEL: {self.secure_channel}", file=sys.stderr)
        print(f"  MUXER: {self.muxer}", file=sys.stderr)
        print(f"  PEER_IP: {self.peer_ip}", file=sys.stderr)

        sec_opt, key_pair = self.create_security_options()
        muxer_opt = self.create_muxer_options()
        listen_addr = self.create_listen_address(4001)

        self.host = new_host(
            key_pair=key_pair,
            sec_opt=sec_opt,
            muxer_opt=muxer_opt,
            enable_quic=(self.transport == "quic-v1"),
        )

        # Configure relay client
        relay_config = RelayConfig(
            roles=RelayRole.STOP | RelayRole.CLIENT,
        )
        relay_protocol = CircuitV2Protocol(self.host, DEFAULT_RELAY_LIMITS, allow_hop=False)
        dcutr_protocol = DCUtRProtocol(self.host)

        async with self.host.run(listen_addrs=[listen_addr]):
            async with background_trio_service(relay_protocol):
                async with background_trio_service(dcutr_protocol):
                    await relay_protocol.event_started.wait()
                    await dcutr_protocol.event_started.wait()

                    # Initialize transport
                    CircuitV2Transport(self.host, relay_protocol, relay_config)

                    peer_id = str(self.host.get_id())
                    print(f"Listener peer ID: {peer_id}", file=sys.stderr)

                    # Publish our peer ID to Redis
                    redis_key = f"{self.test_key}_listener_peer_id"
                    self.redis_client.set(redis_key, peer_id)
                    print(f"Published peer ID to Redis key: {redis_key}", file=sys.stderr)

                    # Wait for relay multiaddr
                    relay_key = f"{self.test_key}_relay_multiaddr"
                    relay_addr = None
                    print(f"Waiting for relay multiaddr at key: {relay_key}", file=sys.stderr)
                    for i in range(60):  # 60 second timeout
                        relay_addr = self.redis_client.get(relay_key)
                        if relay_addr:
                            break
                        if i % 10 == 0:
                            print(f"  Still waiting for relay... ({i}s)", file=sys.stderr)
                        await trio.sleep(1)

                    if not relay_addr:
                        raise RuntimeError("Timeout waiting for relay multiaddr")

                    print(f"Got relay multiaddr: {relay_addr}", file=sys.stderr)

                    # Connect to relay
                    relay_maddr = multiaddr.Multiaddr(relay_addr)
                    relay_info = info_from_p2p_addr(relay_maddr)
                    await self.host.connect(relay_info)
                    print(f"Connected to relay: {relay_info.peer_id}", file=sys.stderr)

                    # Add relay to peerstore for circuit reservation
                    self.host.get_peerstore().add_addrs(
                        relay_info.peer_id, relay_info.addrs, 3600
                    )

                    # Wait for DCUtR to complete (dialer will initiate)
                    # The listener just needs to stay alive and respond
                    print("Listener ready, waiting for hole punch...", file=sys.stderr)

                    # Run forever until container is shut down
                    await trio.sleep_forever()

    async def run_dialer(self):
        """Run as dialer (IS_DIALER=true)."""
        print("Starting as DIALER...", file=sys.stderr)
        print(f"  TRANSPORT: {self.transport}", file=sys.stderr)
        print(f"  SECURE_CHANNEL: {self.secure_channel}", file=sys.stderr)
        print(f"  MUXER: {self.muxer}", file=sys.stderr)
        print(f"  PEER_IP: {self.peer_ip}", file=sys.stderr)

        sec_opt, key_pair = self.create_security_options()
        muxer_opt = self.create_muxer_options()
        listen_addr = self.create_listen_address(4001)

        self.host = new_host(
            key_pair=key_pair,
            sec_opt=sec_opt,
            muxer_opt=muxer_opt,
            enable_quic=(self.transport == "quic-v1"),
        )

        # Configure relay client
        relay_config = RelayConfig(
            roles=RelayRole.STOP | RelayRole.CLIENT,
        )
        relay_protocol = CircuitV2Protocol(self.host, DEFAULT_RELAY_LIMITS, allow_hop=False)
        dcutr_protocol = DCUtRProtocol(self.host)

        async with self.host.run(listen_addrs=[listen_addr]):
            async with background_trio_service(relay_protocol):
                async with background_trio_service(dcutr_protocol):
                    await relay_protocol.event_started.wait()
                    await dcutr_protocol.event_started.wait()

                    # Initialize transport
                    transport = CircuitV2Transport(self.host, relay_protocol, relay_config)

                    peer_id = str(self.host.get_id())
                    print(f"Dialer peer ID: {peer_id}", file=sys.stderr)

                    # Wait for relay multiaddr
                    relay_key = f"{self.test_key}_relay_multiaddr"
                    relay_addr = None
                    print(f"Waiting for relay multiaddr at key: {relay_key}", file=sys.stderr)
                    for i in range(60):
                        relay_addr = self.redis_client.get(relay_key)
                        if relay_addr:
                            break
                        if i % 10 == 0:
                            print(f"  Still waiting for relay... ({i}s)", file=sys.stderr)
                        await trio.sleep(1)

                    if not relay_addr:
                        raise RuntimeError("Timeout waiting for relay multiaddr")

                    print(f"Got relay multiaddr: {relay_addr}", file=sys.stderr)

                    # Connect to relay
                    relay_maddr = multiaddr.Multiaddr(relay_addr)
                    relay_info = info_from_p2p_addr(relay_maddr)
                    await self.host.connect(relay_info)
                    print(f"Connected to relay: {relay_info.peer_id}", file=sys.stderr)

                    # Wait for listener peer ID
                    listener_key = f"{self.test_key}_listener_peer_id"
                    listener_peer_id_str = None
                    print(f"Waiting for listener peer ID at key: {listener_key}", file=sys.stderr)
                    for i in range(60):
                        listener_peer_id_str = self.redis_client.get(listener_key)
                        if listener_peer_id_str:
                            break
                        if i % 10 == 0:
                            print(f"  Still waiting for listener... ({i}s)", file=sys.stderr)
                        await trio.sleep(1)

                    if not listener_peer_id_str:
                        raise RuntimeError("Timeout waiting for listener peer ID")

                    print(f"Got listener peer ID: {listener_peer_id_str}", file=sys.stderr)
                    listener_peer_id = ID.from_base58(listener_peer_id_str)

                    # Create circuit address to listener through relay
                    circuit_addr = multiaddr.Multiaddr(
                        f"{relay_addr}/p2p-circuit/p2p/{listener_peer_id_str}"
                    )
                    print(f"Circuit address: {circuit_addr}", file=sys.stderr)

                    # Add circuit address to peerstore
                    self.host.get_peerstore().add_addrs(listener_peer_id, [circuit_addr], 3600)

                    # Start timing for DCUtR
                    handshake_start = time.time()

                    # Connect through relay using the circuit transport
                    print("Connecting to listener through relay...", file=sys.stderr)

                    # Use CircuitV2Transport.dial() directly for circuit addresses
                    conn = await transport.dial(circuit_addr)
                    print("Connected to listener through relay", file=sys.stderr)

                    # Initiate hole punch
                    print("Initiating hole punch...", file=sys.stderr)
                    result = await dcutr_protocol.initiate_hole_punch(listener_peer_id)

                    handshake_end = time.time()
                    handshake_time_ms = (handshake_end - handshake_start) * 1000

                    # Verify direct connection
                    has_direct = await dcutr_protocol._have_direct_connection(listener_peer_id)

                    print(f"Hole punch result: {result}", file=sys.stderr)
                    print(f"Has direct connection: {has_direct}", file=sys.stderr)

                    if has_direct and result:
                        print(f"Hole punch SUCCESS! Direct connection established.", file=sys.stderr)
                        print(f"Handshake time: {handshake_time_ms:.2f}ms", file=sys.stderr)

                        # Output results to stdout (YAML format)
                        print(f"handshakeTime: {handshake_time_ms:.2f}", file=sys.stdout)

                        # Success - return cleanly to allow nursery to close
                        return
                    else:
                        print(f"Hole punch FAILED. result={result}, has_direct={has_direct}", file=sys.stderr)
                        raise SystemExit(1)

    async def run(self):
        """Main entry point."""
        await self.connect_redis()

        if self.is_dialer:
            await self.run_dialer()
        else:
            await self.run_listener()


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
        peer = HolePunchPeer()
        await peer.run()
    except Exception as e:
        print(f"Fatal error: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc(file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    trio.run(main)
