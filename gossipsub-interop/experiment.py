from collections import defaultdict
from dataclasses import dataclass, field
import random
from typing import List, Dict, Set

from script_action import GossipSubParams, ScriptAction, NodeID
import script_action


@dataclass
class Binary:
    path: str
    percent_of_nodes: int


@dataclass
class ExperimentParams:
    script: List[ScriptAction] = field(default_factory=list)


def scenario(scenario_name: str, node_count: int) -> ExperimentParams:
    actions: List[ScriptAction] = []
    match scenario_name:
        case "subnet-blob-msg":
            actions.extend(init_gossipsub())
            number_of_conns_per_node = 10
            if number_of_conns_per_node >= node_count:
                number_of_conns_per_node = node_count - 1
            actions.extend(random_network_mesh(node_count, number_of_conns_per_node))
            message_size = 2 * 1024 * 48
            num_messages = 32
            actions.extend(
                random_publish_every_12s(node_count, num_messages, message_size)
            )
        case _:
            raise ValueError(f"Unknown scenario name: {scenario_name}")

    return ExperimentParams(script=actions)


def composition(preset_name: str) -> List[Binary]:
    match preset_name:
        case "all-go":
            return [Binary("go-libp2p/gossipsub-bin", percent_of_nodes=100)]
        case "all-rust":
            # Always use debug. We don't measure compute performance here.
            return [
                Binary(
                    "rust-libp2p/target/debug/rust-libp2p-gossip", percent_of_nodes=100
                )
            ]
        case "rust-and-go":
            return [
                Binary(
                    "rust-libp2p/target/debug/rust-libp2p-gossip", percent_of_nodes=50
                ),
                Binary("go-libp2p/gossipsub-bin", percent_of_nodes=50),
            ]
    raise ValueError(f"Unknown preset name: {preset_name}")


def init_gossipsub() -> List[ScriptAction]:
    # Default gossipsub parameters
    return [script_action.InitGossipSub(gossipSubParams=GossipSubParams())]


def random_network_mesh(
    node_count: int, number_of_connections: int
) -> List[ScriptAction]:
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

    actions = []
    for node_id, node_connections in connect_to.items():
        actions.append(
            script_action.IfNodeIDEquals(
                nodeID=node_id,
                action=script_action.Connect(
                    connectTo=list(node_connections),
                ),
            )
        )
    return actions


def random_publish_every_12s(
    node_count: int, numMessages: int, messageSize: int
) -> List[ScriptAction]:
    topicStr = "foobar"
    actions = []
    actions.append(script_action.SubscribeToTopic(topicID=topicStr))

    # Start at 120 seconds (2 minutes) to allow for setup time
    elapsed_seconds = 120
    actions.append(script_action.WaitUntil(elapsedSeconds=elapsed_seconds))

    for i in range(numMessages):
        random_node = random.randint(0, node_count - 1)
        actions.append(
            script_action.IfNodeIDEquals(
                nodeID=random_node,
                action=script_action.Publish(
                    messageID=i,
                    topicID=topicStr,
                    messageSizeBytes=messageSize,
                ),
            )
        )
        elapsed_seconds += 12  # Add 12 seconds for each subsequent message
        actions.append(script_action.WaitUntil(elapsedSeconds=elapsed_seconds))

    elapsed_seconds += 30  # wait a bit more to allow all messages to flush
    actions.append(script_action.WaitUntil(elapsedSeconds=elapsed_seconds))

    return actions
