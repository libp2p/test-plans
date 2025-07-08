from __future__ import annotations

import random
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import timedelta
from typing import Dict, List, Set

from script_instruction import GossipSubParams, NodeID, ScriptInstruction
import script_instruction


@dataclass
class Binary:
    path: str
    percent_of_nodes: int


@dataclass
class ExperimentParams:
    script: List[ScriptInstruction] = field(default_factory=list)


# ---------- stagger heartbeats ----------

def spread_heartbeat_delay(node_count: int, template_gs_params: GossipSubParams) -> List[ScriptInstruction]:
    instructions: List[ScriptInstruction] = []
    initial_delay = timedelta(seconds=0.1)
    for i in range(node_count):
        initial_delay += timedelta(milliseconds=0.100)
        gs_params = template_gs_params.model_copy()
        gs_params.HeartbeatInitialDelay = int(initial_delay.total_seconds() * 1_000_000_000)
        instructions.append(
            script_instruction.IfNodeIDEquals(
                nodeID=i,
                instruction=script_instruction.InitGossipSub(gossipSubParams=gs_params),
            )
        )
    return instructions


# ---------- main scenario ----------

def scenario(
    scenario_name: str,
    node_count: int,
    disable_gossip: bool,
    d_value: int | None = None,
) -> ExperimentParams:
    if scenario_name != "subnet-blob-msg":
        raise ValueError(f"Unknown scenario name: {scenario_name}")

    gs_params = GossipSubParams()
    if d_value is not None:
        gs_params.D = d_value
    if disable_gossip:
        gs_params.Dlazy = 0
        gs_params.GossipFactor = 0

    instructions: List[ScriptInstruction] = []
    instructions.extend(spread_heartbeat_delay(node_count, gs_params))

    num_conns = min(20, node_count - 1)
    instructions.extend(random_network_mesh(node_count, num_conns))

    instructions.extend(random_publish_every_12s(node_count, numMessages=16, messageSize=2 * 1024 * 48))

    return ExperimentParams(script=instructions)


# ---------- composition presets ----------

def composition(preset_name: str) -> List[Binary]:
    match preset_name:
        case "all-go":
            return [Binary("go-libp2p/gossipsub-bin", 100)]
        case "all-wfr":
            return [Binary("go-libp2p-wfr/gossipsub-bin", 100)]
        case "all-rust":
            return [Binary("rust-libp2p/target/debug/rust-libp2p-gossip", 100)]
        case "rust-and-go":
            return [
                Binary("rust-libp2p/target/debug/rust-libp2p-gossip", 50),
                Binary("go-libp2p/gossipsub-bin", 50),
            ]
    raise ValueError(f"Unknown preset name: {preset_name}")


# ---------- network helpers ----------

def random_network_mesh(node_count: int, number_of_connections: int) -> List[ScriptInstruction]:
    connections: Dict[NodeID, Set[NodeID]] = defaultdict(set)
    connect_to: Dict[NodeID, List[NodeID]] = defaultdict(list)
    for node_id in range(node_count):
        while len(connections[node_id]) < number_of_connections:
            target = random.randint(0, node_count - 1)
            if target == node_id:
                continue
            connections[node_id].add(target)
            connections[target].add(node_id)
            connect_to[node_id].append(target)

    out: List[ScriptInstruction] = []
    for nid, peers in connect_to.items():
        out.append(
            script_instruction.IfNodeIDEquals(
                nodeID=nid,
                instruction=script_instruction.Connect(connectTo=list(peers)),
            )
        )
    return out


def random_publish_every_12s(node_count: int, numMessages: int, messageSize: int) -> List[ScriptInstruction]:
    topic = "foobar"
    instr: List[ScriptInstruction] = [script_instruction.SubscribeToTopic(topicID=topic)]

    elapsed = 120
    instr.append(script_instruction.WaitUntil(elapsedSeconds=elapsed))

    for i in range(numMessages):
        publisher = random.randint(0, node_count - 1)
        instr.append(
            script_instruction.IfNodeIDEquals(
                nodeID=publisher,
                instruction=script_instruction.Publish(messageID=i, topicID=topic, messageSizeBytes=messageSize),
            )
        )
        elapsed += 12
        instr.append(script_instruction.WaitUntil(elapsedSeconds=elapsed))

    instr.append(script_instruction.WaitUntil(elapsedSeconds=elapsed + 30))
    return instr
