import random
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import timedelta
from typing import Dict, List, Set

import script_instruction
from script_instruction import GossipSubParams, NodeID, ScriptInstruction


@dataclass
class Binary:
    path: str
    percent_of_nodes: int


@dataclass
class ExperimentParams:
    script: List[ScriptInstruction] = field(default_factory=list)


def spread_heartbeat_delay(
    node_count: int, template_gs_params: GossipSubParams
) -> List[ScriptInstruction]:
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
                instruction=script_instruction.InitGossipSub(gossipSubParams=gs_params),
            )
        )
    return instructions


def partial_message_scenario(
    disable_gossip: bool, node_count: int
) -> List[ScriptInstruction]:
    instructions: List[ScriptInstruction] = []
    gs_params = GossipSubParams()
    if disable_gossip:
        gs_params.Dlazy = 0
        gs_params.GossipFactor = 0
    instructions.extend(spread_heartbeat_delay(node_count, gs_params))

    number_of_conns_per_node = min(20, node_count - 1)
    instructions.extend(random_network_mesh(node_count, number_of_conns_per_node))

    topic = "a-subnet"
    instructions.append(
        script_instruction.SubscribeToTopic(topicID=topic, partial=True)
    )

    groupID = random.randint(0, (2**8) - 1)

    # Wait for some setup time
    elapsed_seconds = 30
    instructions.append(script_instruction.WaitUntil(elapsedSeconds=elapsed_seconds))

    # Assign random parts to each node
    if node_count == 2:
        # If just two nodes, make sure we can always generate a full message
        part = random.randint(0, 255)
        instructions.append(
            script_instruction.IfNodeIDEquals(
                nodeID=0,
                instruction=script_instruction.AddPartialMessage(
                    topicID=topic, groupID=groupID, parts=part
                ),
            )
        )
        instructions.append(
            script_instruction.IfNodeIDEquals(
                nodeID=1,
                instruction=script_instruction.AddPartialMessage(
                    topicID=topic, groupID=groupID, parts=(0xFF ^ part)
                ),
            )
        )
    else:
        for i in range(node_count):
            parts = random.randint(0, 255)
            instructions.append(
                script_instruction.IfNodeIDEquals(
                    nodeID=i,
                    instruction=script_instruction.AddPartialMessage(
                        topicID=topic, groupID=groupID, parts=parts
                    ),
                )
            )

    # Everyone publishes their partial message. This is how nodes learn about
    # each others parts and can request them.
    instructions.append(
        script_instruction.PublishPartial(topicID=topic, groupID=groupID)
    )

    # Wait for everything to flush
    elapsed_seconds += 10
    instructions.append(script_instruction.WaitUntil(elapsedSeconds=elapsed_seconds))

    return instructions


def partial_message_chain_scenario(
    disable_gossip: bool, node_count: int
) -> List[ScriptInstruction]:
    instructions: List[ScriptInstruction] = []
    gs_params = GossipSubParams()
    if disable_gossip:
        gs_params.Dlazy = 0
        gs_params.GossipFactor = 0
    instructions.extend(spread_heartbeat_delay(node_count, gs_params))

    # Create a bidirectional chain topology: 0<->1<->2....<->n-1
    # Each node connects to both previous and next (except first and last)
    for i in range(node_count):
        connections = []
        if i < node_count - 1:
            connections.append(i + 1)  # Connect to next

        if connections:
            instructions.append(
                script_instruction.IfNodeIDEquals(
                    nodeID=i,
                    instruction=script_instruction.Connect(connectTo=connections),
                )
            )

    topic = "partial-msg-chain"
    instructions.append(
        script_instruction.SubscribeToTopic(topicID=topic, partial=True)
    )

    # Wait for setup time and mesh stabilization
    elapsed_seconds = 30
    instructions.append(script_instruction.WaitUntil(elapsedSeconds=elapsed_seconds))

    # 16 messages with 8 parts each
    num_messages = 16
    num_parts = 8

    # Assign parts to nodes in round-robin fashion
    # Each message-part combination goes to exactly one node
    for msg_idx in range(num_messages):
        groupID = msg_idx  # Unique group ID for each message

        # Assign each of the 8 parts to nodes in round-robin
        for part_idx in range(num_parts):
            node_idx = (msg_idx * num_parts + part_idx) % node_count
            part_bitmap = 1 << part_idx  # Single bit for this part

            instructions.append(
                script_instruction.IfNodeIDEquals(
                    nodeID=node_idx,
                    instruction=script_instruction.AddPartialMessage(
                        topicID=topic, groupID=groupID, parts=part_bitmap
                    ),
                )
            )

    # Have multiple nodes with parts for each message try to publish
    # This creates redundancy and ensures the exchange process starts
    for msg_idx in range(num_messages):
        groupID = msg_idx

        elapsed_seconds += 2  # Delay between message groups
        instructions.append(
            script_instruction.WaitUntil(elapsedSeconds=elapsed_seconds)
        )
        instructions.append(
            script_instruction.PublishPartial(topicID=topic, groupID=groupID)
        )

    # Wait for propagation and assembly
    elapsed_seconds += 30
    instructions.append(script_instruction.WaitUntil(elapsedSeconds=elapsed_seconds))
    return instructions


def partial_message_fanout_scenario(
    disable_gossip: bool, node_count: int
) -> List[ScriptInstruction]:
    instructions: List[ScriptInstruction] = []
    gs_params = GossipSubParams()
    if disable_gossip:
        gs_params.Dlazy = 0
        gs_params.GossipFactor = 0
    instructions.extend(spread_heartbeat_delay(node_count, gs_params))

    number_of_conns_per_node = min(20, node_count - 1)
    instructions.extend(random_network_mesh(node_count, number_of_conns_per_node))

    topic = "a-subnet"
    for i in range(node_count):
        # The first node will not subscribe to the topic.
        if i == 0:
            continue

        instructions.append(
            script_instruction.IfNodeIDEquals(
                nodeID=i,
                instruction=script_instruction.SubscribeToTopic(
                    topicID=topic, partial=True
                ),
            )
        )

    groupID = random.randint(0, (2**8) - 1)

    # Wait for some setup time
    elapsed_seconds = 30
    instructions.append(script_instruction.WaitUntil(elapsedSeconds=elapsed_seconds))

    # First node has everything
    instructions.append(
        script_instruction.IfNodeIDEquals(
            nodeID=0,
            instruction=script_instruction.AddPartialMessage(
                topicID=topic, groupID=groupID, parts=0xFF
            ),
        )
    )

    # First node publishes to a fanout set, here we are saying the first 7 nodes after the publisher
    instructions.append(
        script_instruction.IfNodeIDEquals(
            nodeID=0,
            instruction=script_instruction.PublishPartial(
                topicID=topic,
                groupID=groupID,
                publishToNodeIDs=list(range(1, min(8, node_count))),
            ),
        )
    )

    # Wait for everything to flush
    elapsed_seconds += 10
    instructions.append(script_instruction.WaitUntil(elapsedSeconds=elapsed_seconds))

    return instructions


def two_topics_scenario(
    disable_gossip: bool, node_count: int
) -> List[ScriptInstruction]:
    """
    Scenario with two topics:
    - 'blocks': 128KB messages
    - 'data_columns': 20KB messages

    All nodes subscribe to both topics. Publishes one message to each topic.
    """
    instructions: List[ScriptInstruction] = []
    gs_params = GossipSubParams()
    if disable_gossip:
        gs_params.Dlazy = 0
        gs_params.GossipFactor = 0
    instructions.extend(spread_heartbeat_delay(node_count, gs_params))

    # Create random mesh topology
    number_of_conns_per_node = min(20, node_count - 1)
    instructions.extend(random_network_mesh(node_count, number_of_conns_per_node))

    # Define topics
    blocks_topic = "blocks"
    data_columns_topic = "data_columns"

    # Message sizes
    blocks_msg_size = 128 * 1024  # 128KB
    data_columns_msg_size = 20 * 1024  # 20KB

    # All nodes subscribe to both topics
    instructions.append(script_instruction.SubscribeToTopic(topicID=blocks_topic))
    instructions.append(script_instruction.SubscribeToTopic(topicID=data_columns_topic))

    # Wait for setup
    elapsed_seconds = 30
    instructions.append(script_instruction.WaitUntil(elapsedSeconds=elapsed_seconds))

    # Publish to blocks topic (message ID 0) from node 0
    instructions.append(
        script_instruction.IfNodeIDEquals(
            nodeID=0,
            instruction=script_instruction.Publish(
                messageID=0,
                topicID=blocks_topic,
                messageSizeBytes=blocks_msg_size,
            ),
        )
    )

    # Publish to data_columns topic (message ID 1) from node 0 (back to back)
    instructions.append(
        script_instruction.IfNodeIDEquals(
            nodeID=0,
            instruction=script_instruction.Publish(
                messageID=1,
                topicID=data_columns_topic,
                messageSizeBytes=data_columns_msg_size,
            ),
        )
    )

    # Wait for propagation
    elapsed_seconds += 30
    instructions.append(script_instruction.WaitUntil(elapsedSeconds=elapsed_seconds))

    return instructions


def partial_message_lazy_scenario(
    disable_gossip: bool, node_count: int
) -> List[ScriptInstruction]:
    """
    Lazy partial message scenario:
    - One publisher (node 0) has all 8 parts
    - Other nodes start with no parts
    - Publisher only sends bitmap (not data) initially (eagerPushParts=0)
    - Peers request parts after receiving first message
    - 5 messages total (4 warm-up + 1 main)
    """
    instructions: List[ScriptInstruction] = []
    gs_params = GossipSubParams()
    if disable_gossip:
        gs_params.Dlazy = 0
        gs_params.GossipFactor = 0
    gs_params.D = 4
    gs_params.Dhi = 4
    gs_params.Dlo = 4
    gs_params.Dout = 1
    instructions.extend(spread_heartbeat_delay(node_count, gs_params))

    number_of_conns_per_node = min(20, node_count - 1)
    instructions.extend(random_network_mesh(node_count, number_of_conns_per_node))

    topic = "partial-lazy"
    instructions.append(
        script_instruction.SubscribeToTopic(topicID=topic, partial=True)
    )

    # Wait for setup time
    elapsed_seconds = 30
    instructions.append(script_instruction.WaitUntil(elapsedSeconds=elapsed_seconds))

    # Publish 5 messages (4 warm-up + 1 main)
    num_messages = 5
    for msg_idx in range(num_messages):
        groupID = random.randint(0, (2**32) - 1)

        # Node 0 (publisher) has ALL parts, lazy mode (eagerPushParts=0)
        instructions.append(
            script_instruction.IfNodeIDEquals(
                nodeID=0,
                instruction=script_instruction.AddPartialMessage(
                    topicID=topic,
                    groupID=groupID,
                    parts=0xFF,  # has all 8 parts
                    eagerPushParts=0,  # LAZY: no eager push
                ),
            )
        )

        # Publisher publishes (lazy - peers will request parts)
        instructions.append(
            script_instruction.IfNodeIDEquals(
                nodeID=0,
                instruction=script_instruction.PublishPartial(
                    topicID=topic,
                    groupID=groupID,
                ),
            )
        )

        # Wait for propagation between messages
        elapsed_seconds += 10
        instructions.append(
            script_instruction.WaitUntil(elapsedSeconds=elapsed_seconds)
        )

    # Extra wait at end for final propagation
    elapsed_seconds += 20
    instructions.append(script_instruction.WaitUntil(elapsedSeconds=elapsed_seconds))

    return instructions


def partial_message_eager_scenario(
    disable_gossip: bool, node_count: int
) -> List[ScriptInstruction]:
    """
    Eager partial message scenario:
    - One publisher (node 0) has all 8 parts
    - Other nodes start with no parts
    - Publisher pushes ALL data eagerly (eagerPushParts=0xFF)
    - 5 messages total (4 warm-up + 1 main)
    """
    instructions: List[ScriptInstruction] = []
    gs_params = GossipSubParams()
    if disable_gossip:
        gs_params.Dlazy = 0
        gs_params.GossipFactor = 0
    gs_params.D = 4
    gs_params.Dhi = 4
    gs_params.Dlo = 4
    gs_params.Dout = 1
    instructions.extend(spread_heartbeat_delay(node_count, gs_params))

    number_of_conns_per_node = min(20, node_count - 1)
    instructions.extend(random_network_mesh(node_count, number_of_conns_per_node))

    topic = "partial-eager"
    instructions.append(
        script_instruction.SubscribeToTopic(topicID=topic, partial=True)
    )

    # Wait for setup time
    elapsed_seconds = 30
    instructions.append(script_instruction.WaitUntil(elapsedSeconds=elapsed_seconds))

    # Publish 5 messages (4 warm-up + 1 main)
    num_messages = 5
    for msg_idx in range(num_messages):
        groupID = random.randint(0, (2**32) - 1)

        # Node 0 (publisher) has ALL parts, eager mode (eagerPushParts=0xFF)
        instructions.append(
            script_instruction.IfNodeIDEquals(
                nodeID=0,
                instruction=script_instruction.AddPartialMessage(
                    topicID=topic,
                    groupID=groupID,
                    parts=0xFF,  # has all 8 parts
                    eagerPushParts=0xFF,  # EAGER: push all 8 parts
                ),
            )
        )

        # Publisher publishes (eager - all data pushed immediately)
        instructions.append(
            script_instruction.IfNodeIDEquals(
                nodeID=0,
                instruction=script_instruction.PublishPartial(
                    topicID=topic,
                    groupID=groupID,
                ),
            )
        )

        # Wait for propagation between messages
        elapsed_seconds += 10
        instructions.append(
            script_instruction.WaitUntil(elapsedSeconds=elapsed_seconds)
        )

    # Extra wait at end for final propagation
    elapsed_seconds += 10
    instructions.append(script_instruction.WaitUntil(elapsedSeconds=elapsed_seconds))

    return instructions


def scenario(
    scenario_name: str, node_count: int, disable_gossip: bool
) -> ExperimentParams:
    instructions: List[ScriptInstruction] = []
    match scenario_name:
        case "partial-messages":
            instructions = partial_message_scenario(disable_gossip, node_count)
        case "partial-messages-chain":
            instructions = partial_message_chain_scenario(disable_gossip, node_count)
        case "partial-messages-fanout":
            instructions = partial_message_fanout_scenario(disable_gossip, node_count)
        case "partial-messages-lazy":
            instructions = partial_message_lazy_scenario(disable_gossip, node_count)
        case "partial-messages-eager":
            instructions = partial_message_eager_scenario(disable_gossip, node_count)
        case "subnet-blob-msg":
            gs_params = GossipSubParams()
            if disable_gossip:
                gs_params.Dlazy = 0
                gs_params.GossipFactor = 0
            instructions.extend(spread_heartbeat_delay(node_count, gs_params))

            topic = "a-subnet"
            blob_count = 48
            # According to data gathered by lighthouse, a column takes around
            # 5ms.
            instructions.append(
                script_instruction.SetTopicValidationDelay(
                    topicID=topic, delaySeconds=0.005
                )
            )
            number_of_conns_per_node = 20
            if number_of_conns_per_node >= node_count:
                number_of_conns_per_node = node_count - 1
            instructions.extend(
                random_network_mesh(node_count, number_of_conns_per_node)
            )
            message_size = 2 * 1024 * blob_count
            num_messages = 16
            instructions.append(script_instruction.SubscribeToTopic(topicID=topic))
            instructions.extend(
                random_publish_every_12s(
                    node_count, num_messages, message_size, [topic]
                )
            )
        case "simple-fanout":
            gs_params = GossipSubParams()
            if disable_gossip:
                gs_params.Dlazy = 0
                gs_params.GossipFactor = 0
            instructions.extend(spread_heartbeat_delay(node_count, gs_params))
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
                            instruction=script_instruction.SubscribeToTopic(
                                topicID=topic_a
                            ),
                        ),
                    )
                else:
                    instructions.append(
                        script_instruction.IfNodeIDEquals(
                            nodeID=i,
                            instruction=script_instruction.SubscribeToTopic(
                                topicID=topic_b
                            ),
                        ),
                    )

            num_messages = 16
            message_size = 1024

            # Every 12s a random node will publish to a random topic
            instructions.extend(
                random_publish_every_12s(
                    node_count, num_messages, message_size, [topic_a, topic_b]
                )
            )

        case "two-topics":
            instructions = two_topics_scenario(disable_gossip, node_count)

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
            if target in connections[node_id] or node_id in connections[target]:
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
    instructions.append(script_instruction.WaitUntil(elapsedSeconds=elapsed_seconds))

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
    instructions.append(script_instruction.WaitUntil(elapsedSeconds=elapsed_seconds))

    return instructions
