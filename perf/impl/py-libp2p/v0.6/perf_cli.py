#!/usr/bin/env python3
"""
libp2p perf CLI for test-plans (same contract as perf/impl/go-libp2p).

Spec: https://github.com/libp2p/specs/blob/master/perf/perf.md
"""

from __future__ import annotations

import argparse
import ipaddress
import json
import logging
import sys
from typing import Any

import multiaddr
import trio

from libp2p import create_yamux_muxer_option, generate_peer_id_from, new_host
from libp2p.crypto.ed25519 import create_new_key_pair
from libp2p.crypto.x25519 import create_new_key_pair as create_new_x25519_key_pair
from libp2p.custom_types import TProtocol
from libp2p.host.ping import ID as PING_PROTOCOL_ID
from libp2p.network.stream.exceptions import StreamError
from libp2p.network.stream.net_stream import NetStream, StreamState
from libp2p.peer.id import ID as PeerID
from libp2p.perf import PerfService
from libp2p.perf.types import PerfInit, PerfOutput
from libp2p.security.noise.transport import (
    PROTOCOL_ID as NOISE_PROTOCOL_ID,
    Transport as NoiseTransport,
)
from libp2p.transport.quic.config import QUICTransportConfig
import libp2p.transport.quic.transport as _quic_transport
import libp2p.transport.quic.utils as _quic_utils

# Under Noise frame limit (65535). Pinned lib defaults WRITE_BLOCK_SIZE=65536 which
# breaks large uploads over TCP; interop uses 65500 — see interop/perf/perf_test.py
# and https://github.com/libp2p/py-libp2p/pull/1258
PERF_SERVICE_INIT: PerfInit = {"write_block_size": 65500}

# Matches go-libp2p perf simpleReader{seed:0} Ed25519 identity (see perf/impl/go-libp2p/v0.42/main.go).
GO_PERF_PEER_ID = "12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN"

_QUIC_AIOQUIC_FLOW_PATCH_INSTALLED = False

logger = logging.getLogger("perf_cli")


def _json_line(out: PerfOutput) -> str:
    # test-plans runner expects camelCase keys (Go/JS reference)
    return json.dumps(
        {
            "type": out["type"],
            "timeSeconds": out["time_seconds"],
            "uploadBytes": out["upload_bytes"],
            "downloadBytes": out["download_bytes"],
        }
    )


def _parse_host_port(server_address: str) -> tuple[str, int]:
    if server_address.startswith("["):
        # [::1]:4001
        bracket_end = server_address.index("]")
        host = server_address[1:bracket_end]
        port = int(server_address[bracket_end + 2 :])
        return host, port
    if server_address.count(":") > 1:
        # IPv6 without brackets — avoid splitting on port
        raise ValueError(
            "IPv6 server-address must use brackets, e.g. [::1]:4001"
        )
    host, port_s = server_address.rsplit(":", 1)
    return host, int(port_s)


def _ip_prefix(host: str) -> str:
    ip = ipaddress.ip_address(host)
    if ip.version == 4:
        return f"/ip4/{host}"
    return f"/ip6/{host}"


def _ensure_quic_aioquic_flow_patch() -> None:
    """
    QUICTransportConfig exposes CONNECTION_FLOW_CONTROL_WINDOW / STREAM_FLOW_CONTROL_WINDOW,
    but libp2p's QUIC transport does not copy them onto aioquic's QuicConfiguration, which
    defaults max_data and max_stream_data to 1MB — crushing large server→client perf
    downloads. Patch the factory once so our _make_quic_transport_opt() takes effect in
    aioquic (upstream should map these fields in transport._setup_quic_configurations).
    """
    global _QUIC_AIOQUIC_FLOW_PATCH_INSTALLED
    if _QUIC_AIOQUIC_FLOW_PATCH_INSTALLED:
        return
    _orig_s = _quic_utils.create_server_config_from_base
    _orig_c = _quic_utils.create_client_config_from_base

    def _apply(cfg: Any, tc: Any) -> None:
        if tc is None:
            return
        md = getattr(tc, "CONNECTION_FLOW_CONTROL_WINDOW", None)
        ms = getattr(tc, "STREAM_FLOW_CONTROL_WINDOW", None)
        if md is not None:
            cfg.max_data = md
        if ms is not None:
            cfg.max_stream_data = ms

    def _wrap_s(
        base: Any, security_manager: Any, transport_config: Any = None
    ) -> Any:
        out = _orig_s(base, security_manager, transport_config)
        _apply(out, transport_config)
        return out

    def _wrap_c(
        base: Any, security_manager: Any, transport_config: Any = None
    ) -> Any:
        out = _orig_c(base, security_manager, transport_config)
        _apply(out, transport_config)
        return out

    # utils and transport each bind these names at import time — patch both.
    _quic_utils.create_server_config_from_base = _wrap_s
    _quic_utils.create_client_config_from_base = _wrap_c
    _quic_transport.create_server_config_from_base = _wrap_s
    _quic_transport.create_client_config_from_base = _wrap_c
    _QUIC_AIOQUIC_FLOW_PATCH_INSTALLED = True


def _make_quic_transport_opt() -> QUICTransportConfig:
    """
    Defaults keep connection-level flow control very small (~1.5MB), which
    throttles large server→client perf downloads. Match interop-style timeouts
    and raise stream/connection windows for throughput benchmarks.
    """
    return QUICTransportConfig(
        connection_timeout=30.0,
        idle_timeout=120.0,
        dial_timeout=30.0,
        inbound_upgrade_timeout=30.0,
        outbound_upgrade_timeout=30.0,
        outbound_stream_protocol_negotiation_timeout=30.0,
        inbound_stream_protocol_negotiation_timeout=30.0,
        NEGOTIATE_TIMEOUT=30.0,
        STREAM_FLOW_CONTROL_WINDOW=16 * 1024 * 1024,
        CONNECTION_FLOW_CONTROL_WINDOW=64 * 1024 * 1024,
        MAX_STREAM_RECEIVE_BUFFER=16 * 1024 * 1024,
    )


def _skip_quic_identify_for_perf_client(host: Any, dial_maddr: multiaddr.Multiaddr) -> None:
    """
    BasicHost schedules background identify only for QUIC dialers. That opens
    an extra stream on the same connection as perf and competes for negotiation
    and QUIC stream resources (hurts large downloads). Seeding a safe cached
    protocol skips identify — see BasicHost._schedule_identify.
    """
    pid = PeerID.from_base58(GO_PERF_PEER_ID)
    host.peerstore.add_addrs(pid, [dial_maddr], 120)
    host.peerstore.add_protocols(pid, [str(PING_PROTOCOL_ID)])


def _patch_netstream_close_write_half_close() -> None:
    """
    NetStream.close_write() incorrectly calls muxed_stream.close(). For QUIC,
    QUICStream.close() closes *both* read and write (see close_read in close()),
    so the perf client never reads the download phase (0 bytes). Other muxers
    may tolerate close(); QUIC needs half-close: muxed_stream.close_write().
    """
    if getattr(NetStream.close_write, "_perf_cli_quic_patched", False):
        return

    async def close_write_fixed(self: NetStream) -> None:
        async with self._state_lock:
            if self._state == StreamState.ERROR:
                raise StreamError(
                    "Cannot close write on stream; stream is in error state"
                )
        ms = self.muxed_stream
        if hasattr(ms, "close_write"):
            await ms.close_write()
        else:
            await ms.close()
        async with self._state_lock:
            if self._state == StreamState.OPEN:
                self._state = StreamState.CLOSE_WRITE
            elif self._state == StreamState.CLOSE_READ:
                self._state = StreamState.CLOSE_BOTH
                await self.remove()

    setattr(close_write_fixed, "_perf_cli_quic_patched", True)
    NetStream.close_write = close_write_fixed  # type: ignore[method-assign]


def _dial_multiaddr(host: str, port: int, transport: str) -> multiaddr.Multiaddr:
    pfx = _ip_prefix(host)
    if transport == "tcp":
        base = multiaddr.Multiaddr(f"{pfx}/tcp/{port}")
    elif transport == "quic-v1":
        base = multiaddr.Multiaddr(f"{pfx}/udp/{port}/quic-v1")
    else:
        raise ValueError(f"Invalid transport {transport!r}")
    return base.encapsulate(multiaddr.Multiaddr(f"/p2p/{GO_PERF_PEER_ID}"))


def _server_identity() -> Any:
    kp = create_new_key_pair(seed=bytes(32))
    pid = generate_peer_id_from(kp).to_base58()
    if pid != GO_PERF_PEER_ID:
        raise RuntimeError(
            f"Deterministic peer id mismatch: got {pid}, want {GO_PERF_PEER_ID}"
        )
    return kp


def _noise_sec_opt(key_pair: Any) -> dict[TProtocol, Any]:
    noise_kp = create_new_x25519_key_pair()
    return {
        NOISE_PROTOCOL_ID: NoiseTransport(
            libp2p_keypair=key_pair,
            noise_privkey=noise_kp.private_key,
            early_data=None,
        )
    }


def _print_listen_multiaddrs(hosts: dict[str, Any]) -> None:
    """Emit one line per listen addr (/p2p/…), same shape as go-libp2p perf server."""
    peer_id = next(iter(hosts.values())).get_id().to_base58()
    seen: set[str] = set()
    for h in hosts.values():
        for addr in h.get_addrs():
            s = str(addr)
            if f"/p2p/{peer_id}" not in s:
                s = str(
                    addr.encapsulate(multiaddr.Multiaddr(f"/p2p/{peer_id}"))
                )
            if s not in seen:
                seen.add(s)
                print(s, flush=True)


async def _run_server(listen_host: str, listen_port: int) -> None:
    _ensure_quic_aioquic_flow_patch()
    # py-libp2p Swarm uses a single base transport; TCP+QUIC on one host requires
    # two listeners (same identity), matching go-libp2p's dual listen.
    key_pair = _server_identity()
    pfx = _ip_prefix(listen_host)
    m_tcp = multiaddr.Multiaddr(f"{pfx}/tcp/{listen_port}")
    m_quic = multiaddr.Multiaddr(f"{pfx}/udp/{listen_port}/quic-v1")

    sec_opt = _noise_sec_opt(key_pair)
    muxer_opt = create_yamux_muxer_option()

    hosts: dict[str, Any] = {}
    print_lock = trio.Lock()
    printed = False
    ready = 0

    async def maybe_print() -> None:
        nonlocal printed, ready
        async with print_lock:
            ready += 1
            if printed or ready < 2:
                return
            _print_listen_multiaddrs(hosts)
            printed = True

    async def tcp_stack() -> None:
        h = new_host(
            key_pair=key_pair,
            sec_opt=sec_opt,
            muxer_opt=muxer_opt,
            listen_addrs=[m_tcp],
            enable_quic=False,
        )
        perf = PerfService(h, PERF_SERVICE_INIT)
        await perf.start()
        async with h.run(listen_addrs=[m_tcp]):
            async with print_lock:
                hosts["tcp"] = h
            await maybe_print()
            await trio.sleep_forever()

    async def quic_stack() -> None:
        h = new_host(
            key_pair=key_pair,
            listen_addrs=[m_quic],
            enable_quic=True,
            quic_transport_opt=_make_quic_transport_opt(),
            negotiate_timeout=30,
        )
        perf = PerfService(h, PERF_SERVICE_INIT)
        await perf.start()
        async with h.run(listen_addrs=[m_quic]):
            async with print_lock:
                hosts["quic"] = h
            await maybe_print()
            await trio.sleep_forever()

    async with trio.open_nursery() as nursery:
        nursery.start_soon(tcp_stack)
        nursery.start_soon(quic_stack)


async def _run_client(
    server_host: str,
    server_port: int,
    transport: str,
    upload_bytes: int,
    download_bytes: int,
) -> None:
    dial_maddr = _dial_multiaddr(server_host, server_port, transport)

    if transport == "tcp":
        key_pair = create_new_key_pair()
        host = new_host(
            key_pair=key_pair,
            sec_opt=_noise_sec_opt(key_pair),
            muxer_opt=create_yamux_muxer_option(),
            listen_addrs=None,
            enable_quic=False,
        )
    else:
        _ensure_quic_aioquic_flow_patch()
        host = new_host(
            key_pair=create_new_key_pair(),
            listen_addrs=None,
            enable_quic=True,
            quic_transport_opt=_make_quic_transport_opt(),
            negotiate_timeout=30,
        )
        _skip_quic_identify_for_perf_client(host, dial_maddr)
        _patch_netstream_close_write_half_close()

    perf = PerfService(host, PERF_SERVICE_INIT)
    await perf.start()

    async with host.run(listen_addrs=[]):
        async for out in perf.measure_performance(
            dial_maddr, upload_bytes, download_bytes
        ):
            print(_json_line(out), flush=True)


def main() -> None:
    logging.basicConfig(level=logging.WARNING, stream=sys.stderr)

    p = argparse.ArgumentParser()
    p.add_argument("--run-server", action="store_true")
    p.add_argument("--server-address", required=True)
    p.add_argument("--transport", default="tcp")
    p.add_argument("--upload-bytes", type=int, default=0)
    p.add_argument("--download-bytes", type=int, default=0)
    args = p.parse_args()

    host, port = _parse_host_port(args.server_address)

    if args.transport not in ("tcp", "quic-v1"):
        print(
            "Invalid transport. Accepted values: 'tcp' or 'quic-v1'",
            file=sys.stderr,
        )
        sys.exit(2)

    if args.run_server:
        trio.run(_run_server, host, port)
    else:
        trio.run(
            _run_client,
            host,
            port,
            args.transport,
            args.upload_bytes,
            args.download_bytes,
        )


if __name__ == "__main__":
    main()
