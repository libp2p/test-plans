from collections import defaultdict
from dataclasses import dataclass, field
from datetime import timedelta
import random
from typing import List, Dict, Set

from script_instruction import GossipSubParams, ScriptInstruction, NodeID
import script_instruction


@dataclass
class Binary:
    path: str
    percent_of_nodes: int


@dataclass
class ExperimentParams:
    script: List[ScriptInstruction] = field(default_factory=list)


def spread_heartbeat_delay(node_count: int, template_gs_params: GossipSubParams) -> List[ScriptInstruction]:
    instructions = []
    initial_delay = timedelta(seconds=0.1)
    for i in range(node_count):
        initial_delay += timedelta(milliseconds=0.100)
        gs_params = template_gs_params.model_copy()
        # The value is in nanoseconds
        gs_params.HeartbeatInitialDelay = initial_delay.microseconds * 1_000
        instructions.append(
            script_instruction.IfNodeIDEquals(
                nodeID=i,
                instruction=script_instruction.InitGossipSub(
                    gossipSubParams=gs_params)
            )
        )
    return instructions


def scenario(scenario_name: str, node_count: int, disable_gossip: bool) -> ExperimentParams:
    instructions: List[ScriptInstruction] = []
    match scenario_name:
        case "subnet-blob-msg":
            gs_params = GossipSubParams()
            if disable_gossip:
                gs_params.Dlazy = 0
                gs_params.GossipFactor = 0
            instructions.extend(spread_heartbeat_delay(
                node_count, gs_params))

            topic = "a-subnet"
            blob_count = 48
            # According to data gathered by lighthouse, a column takes around
            # 5ms.
            instructions.append(
                script_instruction.SetTopicValidationDelay(
                    topicID=topic, delaySeconds=0.005)
            )
            number_of_conns_per_node = 20
            if number_of_conns_per_node >= node_count:
                number_of_conns_per_node = node_count - 1
            instructions.extend(
                random_network_mesh(node_count, number_of_conns_per_node)
            )
            message_size = 2 * 1024 * blob_count
            num_messages = 16
            instructions.append(
                script_instruction.SubscribeToTopic(topicID=topic))
            instructions.extend(
                random_publish_every_12s(
                    node_count, num_messages, message_size, [topic])
            )
        case "simple-fanout":
            gs_params = GossipSubParams()
            if disable_gossip:
                gs_params.Dlazy = 0
                gs_params.GossipFactor = 0
            instructions.extend(spread_heartbeat_delay(
                node_count, gs_params))
            topic_a = "topic-a"
            topic_b = "topic-b"
            number_of_conns_per_node = 20
            if number_of_conns_per_node >= node_count:
                number_of_conns_per_node = node_count - 1
            instructions.extend(
                random_network_mesh(node_count, number_of_conns_per_node)
            )

            # Half nodes will subscribe to topic-a, the other half subscribe to
            # topic-b
            for i in range(node_count):
                if i % 2 == 0:
                    instructions.append(
                        script_instruction.IfNodeIDEquals(
                            nodeID=i,
                            instruction=script_instruction.SubscribeToTopic(topicID=topic_a)),
                    )
                else:
                    instructions.append(
                        script_instruction.IfNodeIDEquals(
                            nodeID=i,
                            instruction=script_instruction.SubscribeToTopic(topicID=topic_b)),
                    )

            num_messages = 16
            message_size = 1024

            # Every 12s a random node will publish to a random topic
            instructions.extend(
                random_publish_every_12s(
                    node_count, num_messages, message_size, [topic_a, topic_b]))

        case _:
            raise ValueError(f"Unknown scenario name: {scenario_name}")

    return ExperimentParams(script=instructions)


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


def random_network_mesh(
    node_count: int, number_of_connections: int
) -> List[ScriptInstruction]:
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

    instructions = []
    for node_id, node_connections in connect_to.items():
        instructions.append(
            script_instruction.IfNodeIDEquals(
                nodeID=node_id,
                instruction=script_instruction.Connect(
                    connectTo=list(node_connections),
                ),
            )
        )
    return instructions


def random_publish_every_12s(
    node_count: int, num_messages: int, message_size: int, topic_strs: List[str]
) -> List[ScriptInstruction]:
    instructions = []

    # Start at 120 seconds (2 minutes) to allow for setup time
    elapsed_seconds = 120
    instructions.append(script_instruction.WaitUntil(
        elapsedSeconds=elapsed_seconds))

    for i in range(num_messages):
        random_node = random.randint(0, node_count - 1)
        topic_str = random.choice(topic_strs)
        instructions.append(
            script_instruction.IfNodeIDEquals(
                nodeID=random_node,
                instruction=script_instruction.Publish(
                    messageID=i,
                    topicID=topic_str,
                    messageSizeBytes=message_size,
                ),
            )
        )
        elapsed_seconds += 12  # Add 12 seconds for each subsequent message
        instructions.append(
            script_instruction.WaitUntil(elapsedSeconds=elapsed_seconds)
        )

    elapsed_seconds += 30  # wait a bit more to allow all messages to flush
    instructions.append(script_instruction.WaitUntil(
        elapsedSeconds=elapsed_seconds))

    return instructions
