#!/usr/bin/env python3
"""
Python implementation for GossipSub interoperability testing.

This implementation follows the specification in test-specs/implementation.md
and provides compatibility with the existing Go and Rust implementations.
"""

import argparse
import json
import logging
import socket
import struct
import sys
import time
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

import trio
import multiaddr
from libp2p import new_host
from libp2p.crypto.ed25519 import create_new_key_pair
from libp2p.crypto.keys import KeyPair
from libp2p.abc import IHost
from libp2p.peer.id import ID as PeerID
from libp2p.peer.peerinfo import PeerInfo, info_from_p2p_addr
from libp2p.pubsub.gossipsub import GossipSub
from libp2p.pubsub.pubsub import Pubsub
from libp2p.stream_muxer.yamux.yamux import PROTOCOL_ID as YAMUX_PROTOCOL_ID, Yamux
from libp2p.tools.async_service.trio_service import background_trio_service
from libp2p.custom_types import TProtocol

# Configure logging to stderr (diagnostics) and stdout (structured output)
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    stream=sys.stderr,
)
logger = logging.getLogger("py-libp2p-gossip")

# Protocol constants
GOSSIPSUB_PROTOCOL_ID = TProtocol("/meshsub/1.0.0")


def node_priv_key(node_id: int) -> KeyPair:
    """
    Generate a deterministic ED25519 private key from node ID.
    
    This follows the specification in test-specs/implementation.md:
    "Implementations MUST deterministically generate their ED25519 peer ID 
    from their node ID by using their little-endian encoded node ID as their ED25519 key."
    """
    # Create a 32-byte seed with the node ID in little-endian format
    seed = bytearray(32)
    struct.pack_into("<I", seed, 0, node_id)
    
    return create_new_key_pair(bytes(seed))


def calc_message_id(data: bytes) -> str:
    """
    Calculate message ID from message data.
    
    From the specification:
    "Message ID is calculated by reading the first 8 bytes of the message and
    interpreting them as a big endian encoded 64 bit unsigned integer."
    """
    if len(data) < 8:
        # Pad with zeros if data is less than 8 bytes
        padded_data = data + b'\x00' * (8 - len(data))
    else:
        padded_data = data[:8]
    
    # Interpret as big-endian uint64 and format as base 10 integer
    message_id = struct.unpack(">Q", padded_data)[0]
    return str(message_id)


def log_structured(msg: str, **kwargs) -> None:
    """
    Log structured JSON to stdout as required by the specification.
    
    All STDOUT logs must include:
    - time: The RFC3339 timestamp of the log entry
    - msg: The message being logged
    """
    log_entry = {
        "time": datetime.now(timezone.utc).isoformat(),
        "msg": msg,
        **kwargs
    }
    print(json.dumps(log_entry), flush=True)


class ShadowConnector:
    """Connector implementation for Shadow simulator environment."""
    
    async def connect_to(self, host: IHost, node_id: int) -> None:
        """Connect to another node by its node ID."""
        try:
            # Resolve the hostname for the target node
            hostname = f"node{node_id}"
            addrs = socket.getaddrinfo(hostname, None)
            if not addrs:
                raise Exception(f"Failed to resolve hostname: {hostname}")
            
            ip_addr = addrs[0][4][0]
            
            # Generate the peer ID for the target node
            target_key_pair = node_priv_key(node_id)
            target_peer_id = PeerID.from_pubkey(target_key_pair.public_key)
            
            # Create multiaddr for the target peer
            maddr_str = f"/ip4/{ip_addr}/tcp/9000/p2p/{target_peer_id}"
            
            # Parse and connect
            peer_info = info_from_p2p_addr(maddr_str)
            await host.connect(peer_info)
            
            logger.debug(f"Connected to node{node_id} at {maddr_str}")
            
        except Exception as e:
            logger.error(f"Failed to connect to node{node_id}: {e}")
            raise


class ExperimentParams:
    """Container for experiment parameters loaded from JSON."""
    
    def __init__(self, data: Dict[str, Any]):
        self.script = data.get("script", [])


class GossipSubInteropNode:
    """Main node implementation for GossipSub interoperability testing."""
    
    def __init__(self, node_id: int, params: ExperimentParams):
        self.node_id = node_id
        self.params = params
        self.start_time = time.time()
        self.connector = ShadowConnector()
        self.host: Optional[IHost] = None
        self.pubsub: Optional[Pubsub] = None
        self.gossipsub: Optional[GossipSub] = None
        self.subscriptions: Dict[str, Any] = {}
        self.topic_validation_delays: Dict[str, float] = {}
        
    async def setup_host(self) -> None:
        """Set up the libp2p host with gossipsub."""
        # Generate deterministic key pair
        key_pair = node_priv_key(self.node_id)
        peer_id = PeerID.from_pubkey(key_pair.public_key)
        
        # Log peer ID as required by specification
        log_structured(
            "PeerID",
            id=str(peer_id),
            node_id=self.node_id
        )
        
        # Create host
        self.host = new_host(
            key_pair=key_pair,
            muxer_opt={YAMUX_PROTOCOL_ID: Yamux},
            listen_addrs=[multiaddr.Multiaddr("/ip4/0.0.0.0/tcp/9000")]
        )
        
        # Create gossipsub with default parameters
        # These can be overridden by InitGossipSub instructions
        self.gossipsub = GossipSub(
            protocols=[GOSSIPSUB_PROTOCOL_ID],
            degree=6,  # D
            degree_low=4,  # Dlo  
            degree_high=12,  # Dhi
            time_to_live=30,  # FanoutTTL in seconds
            gossip_window=3,  # HistoryLength
            gossip_history=5,  # HistoryGossip
            heartbeat_initial_delay=0.1,  # HeartbeatInitialDelay in seconds
            heartbeat_interval=1.0,  # HeartbeatInterval in seconds
        )
        
        # Create pubsub
        self.pubsub = Pubsub(self.host, self.gossipsub)
        
        logger.info(f"Node {self.node_id} initialized with peer ID: {peer_id}")
    
    async def execute_instruction(self, instruction: Dict[str, Any]) -> None:
        """Execute a single script instruction."""
        instr_type = instruction.get("type")
        
        if instr_type == "connect":
            await self._handle_connect(instruction)
        elif instr_type == "subscribeToTopic":
            await self._handle_subscribe(instruction)
        elif instr_type == "publish":
            await self._handle_publish(instruction)
        elif instr_type == "waitUntil":
            await self._handle_wait_until(instruction)
        elif instr_type == "setTopicValidationDelay":
            await self._handle_set_validation_delay(instruction)
        elif instr_type == "initGossipSub":
            await self._handle_init_gossipsub(instruction)
        elif instr_type == "ifNodeIDEquals":
            await self._handle_if_node_id_equals(instruction)
        else:
            logger.warning(f"Unknown instruction type: {instr_type}")
    
    async def _handle_connect(self, instruction: Dict[str, Any]) -> None:
        """Handle connect instruction."""
        connect_to = instruction.get("connectTo", [])
        for target_node_id in connect_to:
            try:
                await self.connector.connect_to(self.host, target_node_id)
            except Exception as e:
                logger.error(f"Failed to connect to node {target_node_id}: {e}")
    
    async def _handle_subscribe(self, instruction: Dict[str, Any]) -> None:
        """Handle subscribeToTopic instruction."""
        topic_id = instruction.get("topicID")
        if topic_id and self.pubsub:
            subscription = await self.pubsub.subscribe(topic_id)
            self.subscriptions[topic_id] = subscription
            logger.info(f"Subscribed to topic: {topic_id}")
            
            # Start message receiving task for this topic in the nursery
            async def receive_messages():
                while True:
                    try:
                        message = await subscription.get()
                        # Log received message as required by specification
                        message_id = calc_message_id(message.data)
                        log_structured(
                            "Received Message",
                            id=message_id,
                            from_=str(message.from_id) if message.from_id else "",
                            topic=topic_id
                        )
                    except Exception as e:
                        logger.error(f"Error receiving message on topic {topic_id}: {e}")
                        await trio.sleep(0.1)
            
            # Store the receive task function to start it later in the nursery
            self.subscriptions[f"{topic_id}_receiver"] = receive_messages
    
    async def _handle_publish(self, instruction: Dict[str, Any]) -> None:
        """Handle publish instruction."""
        message_id = instruction.get("messageID")
        topic_id = instruction.get("topicID")
        message_size_bytes = instruction.get("messageSizeBytes", 0)
        
        if self.pubsub and topic_id is not None:
            # Create message data with the message ID in the first 8 bytes
            message_data = bytearray(message_size_bytes)
            if message_size_bytes >= 8:
                struct.pack_into(">Q", message_data, 0, message_id)
            
            # Apply topic validation delay if set
            if topic_id in self.topic_validation_delays:
                delay = self.topic_validation_delays[topic_id]
                await trio.sleep(delay)
            
            await self.pubsub.publish(topic_id, bytes(message_data))
            logger.info(f"Published message {message_id} to topic {topic_id}")
    
    async def _handle_wait_until(self, instruction: Dict[str, Any]) -> None:
        """Handle waitUntil instruction."""
        elapsed_seconds = instruction.get("elapsedSeconds", 0)
        current_elapsed = time.time() - self.start_time
        
        if elapsed_seconds > current_elapsed:
            wait_time = elapsed_seconds - current_elapsed
            logger.debug(f"Waiting {wait_time:.2f} seconds until {elapsed_seconds}s elapsed")
            await trio.sleep(wait_time)
    
    async def _handle_set_validation_delay(self, instruction: Dict[str, Any]) -> None:
        """Handle setTopicValidationDelay instruction."""
        topic_id = instruction.get("topicID")
        delay_seconds = instruction.get("delaySeconds", 0.0)
        
        if topic_id:
            self.topic_validation_delays[topic_id] = delay_seconds
            logger.info(f"Set validation delay for topic {topic_id}: {delay_seconds}s")
    
    async def _handle_init_gossipsub(self, instruction: Dict[str, Any]) -> None:
        """Handle initGossipSub instruction."""
        # This would reconfigure gossipsub parameters
        # For now, we log that we received the instruction
        gossip_params = instruction.get("gossipSubParams", {})
        logger.info(f"InitGossipSub instruction received with params: {gossip_params}")
        # TODO: Apply the gossipsub parameters to reconfigure the router
    
    async def _handle_if_node_id_equals(self, instruction: Dict[str, Any]) -> None:
        """Handle ifNodeIDEquals instruction."""
        target_node_id = instruction.get("nodeID")
        inner_instruction = instruction.get("instruction")
        
        if target_node_id == self.node_id and inner_instruction:
            await self.execute_instruction(inner_instruction)
    
    async def run_experiment(self) -> None:
        """Run the complete experiment."""
        await self.setup_host()
        
        async with trio.open_nursery() as nursery:
            async with background_trio_service(self.pubsub):
                async with background_trio_service(self.gossipsub):
                    await self.pubsub.wait_until_ready()
                    logger.info("Pubsub and GossipSub services started")
                    
                    # Start message receiving tasks for any existing subscriptions
                    for key, receiver in self.subscriptions.items():
                        if key.endswith("_receiver") and callable(receiver):
                            nursery.start_soon(receiver)
                    
                    # Execute all script instructions
                    for instruction in self.params.script:
                        await self.execute_instruction(instruction)
                        
                        # Start any new receiver tasks that were created
                        for key, receiver in list(self.subscriptions.items()):
                            if key.endswith("_receiver") and callable(receiver):
                                nursery.start_soon(receiver)
                                # Remove from dict to avoid starting again
                                del self.subscriptions[key]
                    
                    # Keep running to handle ongoing message delivery
                    logger.info("All instructions executed, keeping node alive for message delivery")
                    await trio.sleep(3600)  # Run for up to 1 hour


async def main() -> None:
    """Main entry point."""
    parser = argparse.ArgumentParser(description="Python GossipSub interop test node")
    parser.add_argument("--params", required=True, help="Path to params.json file")
    
    args = parser.parse_args()
    
    # Read experiment parameters
    try:
        with open(args.params, 'r') as f:
            params_data = json.load(f)
        params = ExperimentParams(params_data)
    except Exception as e:
        logger.error(f"Failed to load params file {args.params}: {e}")
        sys.exit(1)
    
    # Get node ID from hostname
    try:
        hostname = socket.gethostname()
        node_id = int(hostname.replace("node", ""))
    except Exception as e:
        # For testing outside Shadow, use a default node_id
        node_id = 1
        logger.info(f"Using default node ID (not in Shadow): {node_id}")
    
    # Create and run the node
    node = GossipSubInteropNode(node_id, params)
    
    try:
        # Run the experiment (we're already inside trio.run from main)
        await node.run_experiment()
    except KeyboardInterrupt:
        logger.info("Node terminated by user")
    except Exception as e:
        logger.error(f"Node failed: {e}")
        sys.exit(1)


if __name__ == "__main__":
    trio.run(main)
