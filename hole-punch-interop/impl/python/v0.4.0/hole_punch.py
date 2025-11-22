#!/usr/bin/env python3
"""
Hole-Punch Interop Test for py-libp2p v0.3.x
Supports initiator & receiver roles.
Writes to /results/results.csv
"""

import asyncio
import json
import logging
import os
import time
from typing import Sequence, Literal

from libp2p import new_host
from libp2p.abc import IHost
from libp2p.crypto.secp256k1 import create_new_key_pair
from libp2p.peer.id import ID
from libp2p.peer.peerinfo import info_from_p2p_addr
from libp2p.transport.upgrader import TransportUpgrader
from multiaddr import Multiaddr
from libp2p.custom_types import (
    TProtocol,
)

DCUTR_PROTOCOL = TProtocol("/libp2p/dcutr/1.0.0")
PING_PROTOCOL = TProtocol("/test/ping/1.0.0")

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("hole-punch")

async def create_host(listen_addrs: Sequence[Multiaddr] | None = None) -> IHost:
    key_pair = create_new_key_pair()

    host: IHost = new_host(
        key_pair=key_pair,
        muxer_preference="MPLEX",   
        listen_addrs=listen_addrs or [Multiaddr("/ip4/0.0.0.0/tcp/0")]
    )
    return host

async def main() -> None:
    mode = os.environ["MODE"].lower()
    relay_addr_str = os.environ["RELAY_MULTIADDR"]
    target_id_str = os.environ["TARGET_ID"]

    # Create and start listening
    host = await create_host()
    addrs = host.get_addrs()
    log.info(f"Listening on: {[str(a) for a in addrs]}")

    # Connect to the relay
    relay_ma = Multiaddr(relay_addr_str)
    relay_info = info_from_p2p_addr(relay_ma)
    await host.connect(relay_info)
    log.info(f"Connected to relay: {relay_ma}")

    # Connect to the *target* via the relay (control channel)
    target_id = ID(target_id_str.encode())
    relayed_target_ma = Multiaddr(f"{relay_addr_str}/p2p-circuit/p2p/{target_id}")
    target_info = info_from_p2p_addr(relayed_target_ma)
    await host.connect(target_info)
    log.info(f"Connected to target via relay: {relayed_target_ma}")

    if mode == "initiator":
        await initiator_role(host, target_id)
    else:
        await receiver_role(host)

async def initiator_role(host: IHost, target_id: ID) -> None:
    stream = await host.new_stream(target_id, [DCUTR_PROTOCOL])

    # Send CONNECT
    my_addrs = [str(a) for a in host.get_addrs()]
    await stream.write(json.dumps({"type": "CONNECT", "addrs": my_addrs}).encode())
    log.info(f"Sent CONNECT with {len(my_addrs)} addrs")

    # Receive SYNC
    try:
        raw = await asyncio.wait_for(stream.read(4096), timeout=15)
        msg = json.loads(raw.decode())
        if msg.get("type") != "SYNC":
            raise ValueError("expected SYNC")
        peer_addrs = msg.get("addrs", [])
        log.info(f"Received SYNC with {len(peer_addrs)} addrs")
    except Exception as e:
        log.error(f"SYNC failed: {e}")
        await write_result("failure")
        await stream.close()
        return
    finally:
        await stream.close()

    # Direct dial the first address
    if peer_addrs:
        try:
            direct_ma = Multiaddr(peer_addrs[0])
            direct_info = info_from_p2p_addr(direct_ma)
            await host.connect(direct_info)
            log.info(f"Direct connection SUCCESS → {direct_ma}")
        except Exception as e:
            log.warning(f"Direct dial failed: {e}")
            await write_result("failure")
            return

    # Ping test
    try:
        ping = await host.new_stream(target_id, [PING_PROTOCOL])
        start = time.time()
        await ping.write(b"ping")
        resp = await asyncio.wait_for(ping.read(4), timeout=5)
        rtt = (time.time() - start) * 1000
        if resp == b"pong":
            log.info(f"Ping RTT: {rtt:.1f} ms → SUCCESS")
            await write_result("success")
        else:
            log.error("Ping failed – bad response")
            await write_result("failure")
        await ping.close()
    except Exception as e:
        log.error(f"Ping failed: {e}")
        await write_result("failure")

async def receiver_role(host: IHost) -> None:
    async def dcutr_handler(stream):
        try:
            data = await stream.read(4096)
            msg = json.loads(data.decode())
            if msg.get("type") != "CONNECT":
                return

            my_addrs = [str(a) for a in host.get_addrs()]
            await stream.write(json.dumps({"type": "SYNC", "addrs": my_addrs}).encode())
            log.info(f"Sent SYNC with {len(my_addrs)} addrs")

            if msg.get("addrs"):
                addr = Multiaddr(msg["addrs"][0])
                info = info_from_p2p_addr(addr)
                asyncio.create_task(host.connect(info))
        except Exception as e:
            log.error(f"DCUtR handler error: {e}")
        finally:
            await stream.close()

    async def ping_handler(stream):
        try:
            data = await stream.read(4)
            if data == b"ping":
                await stream.write(b"pong")
        finally:
            await stream.close()

    host.set_stream_handler(DCUTR_PROTOCOL, dcutr_handler)
    host.set_stream_handler(PING_PROTOCOL, ping_handler)
    log.info("Receiver ready – awaiting initiator…")
    await asyncio.Event().wait()  

async def write_result(result: str) -> None:
    impl = os.environ.get("TARGET_IMPL", "go")
    os.makedirs("/results", exist_ok=True)
    line = f'"python-v0.3.x x {impl}-v0.42 (dcutr,tcp,noise)",{result}\n'
    with open("/results/results.csv", "a") as f:
        f.write(line)
    log.info(f"RESULT: {result.upper()}")

if __name__ == "__main__":
    asyncio.run(main())