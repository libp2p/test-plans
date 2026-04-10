#!/usr/bin/env python3
"""
Hole-punch interop client (py-libp2p), matching hole-punch-interop/README.md.

Redis: relay addresses on RELAY_TCP_ADDRESS / RELAY_QUIC_ADDRESS; listener publishes
LISTEN_CLIENT_PEER_ID after a successful relay reservation.
"""

from __future__ import annotations

import json
import logging
import os
import sys
from typing import cast

import multiaddr
import redis
import trio

from libp2p import create_yamux_muxer_option, new_host
from libp2p.crypto.ed25519 import create_new_key_pair
from libp2p.crypto.x25519 import create_new_key_pair as create_new_x25519_key_pair
from libp2p.connection_types import ConnectionType
from libp2p.host.basic_host import BasicHost
from libp2p.host.ping import PingService
from libp2p.peer.id import ID
from libp2p.peer.peerinfo import PeerInfo, info_from_p2p_addr
from libp2p.relay.circuit_v2.config import RelayConfig, RelayLimits, RelayRole
from libp2p.relay.circuit_v2.discovery import RelayDiscovery
from libp2p.relay.circuit_v2.dcutr import DCUtRProtocol
from libp2p.relay.circuit_v2.protocol import (
    PROTOCOL_ID as HOP_PROTOCOL_ID,
    STOP_PROTOCOL_ID,
    CircuitV2Protocol,
)
from libp2p.relay.circuit_v2.transport import CircuitV2Transport
from libp2p.security.noise.transport import (
    PROTOCOL_ID as NOISE_PROTOCOL_ID,
    Transport as NoiseTransport,
)
from libp2p.tools.anyio_service import background_trio_service

logger = logging.getLogger("hole_punch_client")

RELAY_TCP_ADDRESS = "RELAY_TCP_ADDRESS"
RELAY_QUIC_ADDRESS = "RELAY_QUIC_ADDRESS"
LISTEN_CLIENT_PEER_ID = "LISTEN_CLIENT_PEER_ID"

_LIMITS = RelayLimits(
    duration=3600,
    data=1024 * 1024 * 100,
    max_circuit_conns=10,
    max_reservations=5,
)
_RELAY_CFG = RelayConfig(
    roles=RelayRole.STOP | RelayRole.CLIENT,
    limits=_LIMITS,
)


def _redis() -> redis.Redis:
    return redis.Redis(
        host="redis",
        port=6379,
        decode_responses=True,
        socket_timeout=None,
        socket_connect_timeout=30,
    )


def _relay_key(tp: str) -> str:
    if tp == "tcp":
        return RELAY_TCP_ADDRESS
    if tp == "quic":
        return RELAY_QUIC_ADDRESS
    raise ValueError(f"TRANSPORT must be tcp or quic, got {tp!r}")


def _pop_relay(r: redis.Redis, tp: str) -> str:
    key = _relay_key(tp)
    item = r.blpop(key, timeout=0)
    if not item:
        raise RuntimeError(f"empty blpop for {key}")
    _, val = item
    return val


def _push(r: redis.Redis, key: str, value: str) -> None:
    r.rpush(key, value)


def _pop_listener_id(r: redis.Redis) -> str:
    item = r.blpop(LISTEN_CLIENT_PEER_ID, timeout=0)
    if not item:
        raise RuntimeError("empty blpop for LISTEN_CLIENT_PEER_ID")
    _, val = item
    return val


def _listen_maddr(tp: str) -> multiaddr.Multiaddr:
    if tp == "tcp":
        return multiaddr.Multiaddr("/ip4/0.0.0.0/tcp/0")
    if tp == "quic":
        return multiaddr.Multiaddr("/ip4/0.0.0.0/udp/0/quic-v1")
    raise ValueError(tp)


def _make_host(tp: str):
    key_pair = create_new_key_pair()
    noise_kp = create_new_x25519_key_pair()
    noise_transport = NoiseTransport(
        libp2p_keypair=key_pair,
        noise_privkey=noise_kp.private_key,
        early_data=None,
    )
    sec_opt = {NOISE_PROTOCOL_ID: noise_transport}
    return new_host(
        key_pair=key_pair,
        muxer_opt=create_yamux_muxer_option(),
        sec_opt=sec_opt,
        listen_addrs=[_listen_maddr(tp)],
        enable_quic=(tp == "quic"),
    )


async def _wait_reservation(
    discovery: RelayDiscovery, relay_peer_id: ID, timeout: float = 120.0
) -> None:
    with trio.move_on_after(timeout) as scope:
        while True:
            info = discovery.get_relay_info(relay_peer_id)
            if info is not None and info.has_reservation:
                return
            await trio.sleep(0.15)
    if scope.cancelled_caught:
        raise RuntimeError(
            f"relay reservation not ready for {relay_peer_id} after {timeout}s"
        )


async def _connect_relay(host: BasicHost, relay_info: PeerInfo, attempts: int = 10) -> None:
    last_exc: BaseException | None = None
    for i in range(attempts):
        try:
            await host.connect(relay_info)
            return
        except BaseException as exc:
            last_exc = exc
            logger.warning(
                "connect to relay attempt %s/%s failed: %s", i + 1, attempts, exc
            )
            await trio.sleep(1.0 + float(i))
    assert last_exc is not None
    raise last_exc


async def _close_relayed_to_peer(host: BasicHost, peer_id: ID) -> None:
    net = host.get_network()
    for conn in list(net.get_connections(peer_id)):
        try:
            if conn.get_connection_type() == ConnectionType.RELAYED:
                await conn.close()
        except Exception as exc:
            logger.debug("could not close relayed conn: %s", exc)


async def run_listener(tp: str) -> None:
    r = _redis()
    relay_str = _pop_relay(r, tp)
    relay_maddr = multiaddr.Multiaddr(relay_str)
    relay_info = info_from_p2p_addr(relay_maddr)
    relay_peer_id = relay_info.peer_id

    host = cast(BasicHost, _make_host(tp))
    protocol = CircuitV2Protocol(host, limits=_LIMITS, allow_hop=False)
    dcutr = DCUtRProtocol(host)
    transport_layer = CircuitV2Transport(host, protocol, _RELAY_CFG)
    discovery = RelayDiscovery(host, auto_reserve=True)
    transport_layer.discovery = discovery

    host.set_stream_handler(HOP_PROTOCOL_ID, protocol._handle_hop_stream)
    host.set_stream_handler(STOP_PROTOCOL_ID, protocol._handle_stop_stream)

    async with host.run([_listen_maddr(tp)]):
        async with background_trio_service(protocol):
            async with background_trio_service(discovery):
                async with background_trio_service(dcutr):
                    await _connect_relay(host, relay_info)
                    await trio.sleep(0.5)
                    # discover_relays() may skip the relay if mux protocol probes fail
                    # against rust-libp2p; seed the relay we are connected to.
                    await discovery._add_relay(relay_peer_id)
                    await _wait_reservation(discovery, relay_peer_id)
                    _push(r, LISTEN_CLIENT_PEER_ID, str(host.get_id()))
                    logger.info("listener ready, peer_id=%s", host.get_id())
                    await trio.sleep_forever()


async def run_dial(tp: str) -> None:
    r = _redis()
    relay_str = _pop_relay(r, tp)
    relay_maddr = multiaddr.Multiaddr(relay_str)
    relay_info = info_from_p2p_addr(relay_maddr)
    relay_peer_id = relay_info.peer_id

    host = cast(BasicHost, _make_host(tp))
    protocol = CircuitV2Protocol(host, limits=_LIMITS, allow_hop=False)
    dcutr = DCUtRProtocol(host)
    transport_layer = CircuitV2Transport(host, protocol, _RELAY_CFG)
    discovery = RelayDiscovery(host, auto_reserve=True)
    transport_layer.discovery = discovery

    host.set_stream_handler(HOP_PROTOCOL_ID, protocol._handle_hop_stream)
    host.set_stream_handler(STOP_PROTOCOL_ID, protocol._handle_stop_stream)

    async with host.run([_listen_maddr(tp)]):
        async with background_trio_service(protocol):
            async with background_trio_service(discovery):
                async with background_trio_service(dcutr):
                    await _connect_relay(host, relay_info)
                    await trio.sleep(0.5)
                    await discovery._add_relay(relay_peer_id)

                    listener_str = _pop_listener_id(r)
                    listener_id = ID.from_string(listener_str)
                    circuit_ma = multiaddr.Multiaddr(
                        f"{relay_str.rstrip('/')}/p2p-circuit/p2p/{listener_id}"
                    )
                    host.get_peerstore().add_addr(listener_id, circuit_ma, 3600)
                    await transport_layer.dial(circuit_ma)
                    await dcutr.event_started.wait()

                    if not await dcutr.initiate_hole_punch(listener_id):
                        raise RuntimeError("DCUtR hole punch failed")

                    await trio.sleep(0.5)
                    await _close_relayed_to_peer(host, listener_id)

                    ping = PingService(host)
                    rtts = await ping.ping(listener_id, 1)
                    rtt_us = rtts[0]
                    rtt_ms = max(0, int(round(rtt_us / 1000.0)))

                    sys.stdout.write(
                        json.dumps({"rtt_to_holepunched_peer_millis": rtt_ms})
                        + "\n"
                    )
                    sys.stdout.flush()


def _setup_logging() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s | %(name)s | %(levelname)s | %(message)s",
        stream=sys.stderr,
    )


def main() -> None:
    _setup_logging()
    try:
        mode = os.environ["MODE"].lower()
        tp = os.environ["TRANSPORT"].lower()
        if mode not in ("listen", "dial"):
            raise ValueError("MODE must be listen or dial")
        if tp not in ("tcp", "quic"):
            raise ValueError("TRANSPORT must be tcp or quic")
        if mode == "listen":
            trio.run(run_listener, tp)
        else:
            trio.run(run_dial, tp)
    except KeyboardInterrupt:
        sys.exit(130)
    except Exception:
        logger.exception("hole-punch-client failed")
        sys.exit(1)


if __name__ == "__main__":
    main()
