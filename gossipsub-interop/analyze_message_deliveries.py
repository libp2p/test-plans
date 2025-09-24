from collections import defaultdict, OrderedDict
import json
import os
import argparse
from datetime import datetime
from typing import Dict, List, Tuple, OrderedDict as OrderedDictType
from dataclasses import dataclass
import matplotlib.pyplot as plt
import yaml
import re

peer_id_to_node_id = dict()
node_id_to_peer_id = dict()


@dataclass(frozen=True)
class MessageId:
    id: str


@dataclass(frozen=True)
class NodeId:
    id: int


@dataclass
class MessageDelivery:
    timestamp: datetime
    node_id: NodeId


@dataclass
class FileParseResult:
    node_id: NodeId
    message_deliveries: OrderedDictType[MessageId, List[MessageDelivery]]
    duplicate_counts: Dict[MessageId, int]


def nodeIDFromFilename(filename):
    return filename.split(".")[0]


def parse_node_id_to_network_id(
    shadow_yaml_path: str,
) -> Tuple[Dict[NodeId, int], Dict[int, List[NodeId]]]:
    """
    Parse shadow.yaml file and return mappings between node_id and network_node_id.

    Args:
        shadow_yaml_path: Path to the shadow.yaml file

    Returns:
        Tuple containing:
        - Dictionary mapping NodeId to network_node_id (int)
        - Dictionary mapping network_node_id (int) to List[NodeId]
    """
    node_to_network_mapping = {}
    network_to_nodes_mapping = defaultdict(list)

    try:
        with open(shadow_yaml_path, "r") as f:
            shadow_config = yaml.safe_load(f)

        if "hosts" in shadow_config:
            for host_name, host_config in shadow_config["hosts"].items():
                # Extract node_id from host name (e.g., "node0" -> 0)
                if host_name.startswith("node"):
                    try:
                        node_id_str = host_name[4:]  # Remove "node" prefix
                        node_id = NodeId(int(node_id_str))
                        network_node_id = host_config.get("network_node_id")
                        if network_node_id is not None:
                            node_to_network_mapping[node_id] = network_node_id
                            network_to_nodes_mapping[network_node_id].append(node_id)
                    except ValueError:
                        # Skip hosts that don't follow the "nodeX" pattern
                        continue

    except (FileNotFoundError, yaml.YAMLError) as e:
        print(f"Warning: Could not parse shadow.yaml file: {e}")

    return node_to_network_mapping, dict(network_to_nodes_mapping)


def parse_gml_node_labels(gml_file_path: str) -> Dict[int, str]:
    """
    Parse a GML file and return a mapping from node ID to label.

    Args:
        gml_file_path: Path to the GML file

    Returns:
        Dictionary mapping node ID (int) to label (str)
    """
    node_id_to_label = {}

    try:
        with open(gml_file_path, "r") as f:
            content = f.read()

        # Find all node blocks using regex
        node_pattern = r"node\s*\[([^\]]*)\]"
        node_matches = re.findall(node_pattern, content, re.DOTALL)

        for node_content in node_matches:
            # Extract id and label from node content
            id_match = re.search(r"id\s+(\d+)", node_content)
            label_match = re.search(r'label\s+"([^"]*)"', node_content)

            if id_match and label_match:
                node_id = int(id_match.group(1))
                label = label_match.group(1)
                node_id_to_label[node_id] = label

    except (FileNotFoundError, IOError) as e:
        print(f"Warning: Could not parse GML file {gml_file_path}: {e}")

    return node_id_to_label


def logfile_iterator(folder):
    """
    Returns a list of all the log files in the folder.

    Special case for shadow data folders by identifying the "hosts" subfolder.

    Otherwise, returns a list of all the files in the folder.
    """
    files = os.listdir(folder)
    if "hosts" in files:
        for host in os.listdir(os.path.join(folder, "hosts")):
            for file in os.listdir(os.path.join(folder, "hosts", host)):
                if file.endswith(".stdout"):
                    yield os.path.join(folder, "hosts", host, file)
    else:
        for file in files:
            yield os.path.join(folder, file)


def plot_msg_delivery_cdf(plt, deliveries, label=None):
    if not deliveries:
        return

    # Sort deliveries by timestamp
    sorted_deliveries = sorted(deliveries, key=lambda x: x.timestamp)

    # Get the initial timestamp as reference point
    start_time = sorted_deliveries[0].timestamp

    # Calculate time differences from start and cumulative count
    times = []
    cumulative_count = []

    for i, delivery in enumerate(sorted_deliveries):
        time_diff = (delivery.timestamp - start_time).total_seconds()
        times.append(time_diff)
        cumulative_count.append(i + 1)

    # Plot the CDF with label
    plt.plot(times, cumulative_count, marker="o", markersize=2, alpha=0.7, label=label)


def parse_log_file(lines) -> FileParseResult:
    """
    Parse all lines from a log file iterator and extract relevant information.

    Args:
        lines: Iterator of log lines from a file

    Returns:
        FileParseResult containing parsed data from the file
    """
    node_id = NodeId(-1)
    seen_message_ids = set()
    message_deliveries = defaultdict(list)
    duplicate_counts = defaultdict(int)

    for line in lines:
        try:
            parsed = json.loads(line)
        except json.JSONDecodeError:
            continue

        if "msg" not in parsed:
            continue

        msg_type = parsed["msg"]

        if msg_type == "PeerID":
            parsed_node_id = parsed.get("node_id", "")
            peer_id = parsed.get("id", "")
            node_id = NodeId(parsed_node_id)
            peer_id_to_node_id[peer_id] = parsed_node_id
            node_id_to_peer_id[parsed_node_id] = peer_id
            continue

        if msg_type == "Received Message" and "time" in parsed:
            timestamp = datetime.fromisoformat(parsed["time"])
            message_id_str = parsed.get("id", "")
            if message_id_str:
                message_id = MessageId(message_id_str)
                if message_id_str not in seen_message_ids:
                    seen_message_ids.add(message_id_str)
                    message_deliveries[message_id].append(
                        MessageDelivery(timestamp, node_id)
                    )
                else:
                    duplicate_counts[message_id] += 1

    # Sort message_deliveries by first delivery time
    sorted_message_deliveries = OrderedDict()
    message_items = list(message_deliveries.items())
    message_items.sort(key=lambda x: x[1][0].timestamp if x[1] else datetime.max)

    for msg_id, deliveries in message_items:
        sorted_message_deliveries[msg_id] = deliveries

    return FileParseResult(
        node_id=node_id,
        message_deliveries=sorted_message_deliveries,
        duplicate_counts=dict(duplicate_counts),
    )


def create_node_delivery_times_mapping(
    ordered_messages: OrderedDict[MessageId, List[MessageDelivery]],
) -> Dict[NodeId, Dict[MessageId, float]]:
    """
    Create a mapping from NodeID to Dict[MessageID, TimeToDeliver(as seconds)].

    Args:
        ordered_messages: OrderedDict mapping MessageId to list of MessageDelivery

    Returns:
        Dictionary mapping NodeId to Dict[MessageId, delivery_time_in_seconds]
        where delivery_time_in_seconds is the time from first delivery to this node's delivery
    """
    node_delivery_times: Dict[NodeId, Dict[MessageId, float]] = defaultdict(dict)

    for msg_id, deliveries in ordered_messages.items():
        if not deliveries:
            continue

        # First delivery timestamp for this message
        first_delivery_time = deliveries[0].timestamp

        # Calculate delivery time for each node
        for delivery in deliveries:
            time_to_deliver = (delivery.timestamp - first_delivery_time).total_seconds()
            node_delivery_times[delivery.node_id][msg_id] = time_to_deliver

    return dict(node_delivery_times)


def plot_delivery_times_per_network_id(
    plt,
    network_to_nodes_mapping: Dict[int, List[NodeId]],
    node_delivery_times: Dict[NodeId, Dict[MessageId, float]],
    network_to_label: Dict[int, str],
):
    """
    Create box plots showing delivery time distributions for each network ID.

    Network ID represents the geographical/logical network segment (e.g., "australia"),
    while Node ID is an arbitrary identifier for a specific node within that network.

    Args:
        plt: matplotlib.pyplot object
        network_to_nodes_mapping: Dictionary mapping network_id (int) to list of NodeIds in that network
        node_delivery_times: Dictionary mapping NodeId to Dict[MessageId, delivery_time_in_seconds]
    """
    if not network_to_nodes_mapping or not node_delivery_times:
        return

    # Collect delivery times for each network ID (geographical/logical network segment)
    network_delivery_times = {}

    for network_id, nodes_in_network in network_to_nodes_mapping.items():
        all_delivery_times_for_network = []

        # For each node in this network segment, collect all their delivery times
        for node_id in nodes_in_network:
            if node_id in node_delivery_times:
                # Collect all delivery times for this specific node across all messages
                for msg_id, delivery_time in node_delivery_times[node_id].items():
                    all_delivery_times_for_network.append(delivery_time)

        if (
            all_delivery_times_for_network
        ):  # Only include networks that have delivery data
            network_delivery_times[network_id] = all_delivery_times_for_network

    if not network_delivery_times:
        return

    # Prepare data for box plot - one box per network ID
    delivery_data: List[List[float]] = []
    for network_id in sorted(network_delivery_times.keys()):
        delivery_data.append(network_delivery_times[network_id])

    # Create the box plot
    plt.figure(figsize=(12, 8))
    box_plot = plt.boxplot(
        delivery_data,
        tick_labels=[
            f"{network_to_label[nid]}" for nid in sorted(network_delivery_times.keys())
        ],
        patch_artist=True,
    )

    # Color the boxes
    colors = plt.cm.Set3(range(len(delivery_data)))
    for patch, color in zip(box_plot["boxes"], colors):
        patch.set_facecolor(color)
        patch.set_alpha(0.7)

    plt.xlabel("Network ID (Geographic/Logical Network Segment)")
    plt.ylabel("Delivery Time (seconds)")
    plt.title("Message Delivery Time Distribution by Network ID")
    plt.ylim(0, 1)
    plt.xticks(rotation=45, ha="right")
    plt.grid(True, alpha=0.3)
    plt.tight_layout()


def analyse_message_deliveries(folder, output_folder="plots", skip_messages=0):
    analysis_txt = []
    messages: Dict[MessageId, List[MessageDelivery]] = defaultdict(list)
    duplicate_count: Dict[MessageId, int] = defaultdict(lambda: 0)

    for file in logfile_iterator(folder):
        with open(file, "r") as f:
            result = parse_log_file(f)

            # Add message deliveries to messages dict
            for msg_id, deliveries in result.message_deliveries.items():
                for delivery in deliveries:
                    messages[msg_id].append(delivery)

            # Add duplicate counts to counters
            for msg_id, count in result.duplicate_counts.items():
                duplicate_count[msg_id] += count

    # Sort messages by first delivery time
    ordered_messages: OrderedDict[MessageId, List[MessageDelivery]] = OrderedDict()
    message_items = list(messages.items())
    message_items.sort(key=lambda x: x[1][0].timestamp if x[1] else datetime.max)

    for msg_id, deliveries in message_items:
        deliveries.sort(key=lambda x: x.timestamp)
        ordered_messages[msg_id] = deliveries

    # Skip the first N messages if requested
    if skip_messages > 0:
        ordered_messages_list = list(ordered_messages.items())
        if skip_messages < len(ordered_messages_list):
            ordered_messages = OrderedDict(ordered_messages_list[skip_messages:])
        else:
            ordered_messages = OrderedDict()

    # Prepare data for plotting
    msg_ids: List[MessageId] = []
    time_diffs: List[float] = []
    avg_duplicates: List[float] = []

    total_nodes = len(node_id_to_peer_id)

    for msgID, deliveries in ordered_messages.items():
        time_diff = (deliveries[-1].timestamp - deliveries[0].timestamp).total_seconds()
        p50Idx = len(deliveries) // 2
        p50 = (deliveries[p50Idx].timestamp - deliveries[0].timestamp).total_seconds()

        msg_ids.append(msgID)
        time_diffs.append(time_diff)
        avg_duplicate_count = duplicate_count[msgID] / total_nodes
        avg_duplicates.append(avg_duplicate_count)
        # Minus 1 for the original sender
        reached = len(deliveries) / (total_nodes - 1)
        if reached > 1.0:
            if len(deliveries) > total_nodes:
                raise ValueError(
                    f"Message {msgID.id} was delivered to more nodes than exist"
                )
            # We overshot because the original publisher received a duplicate message
            reached = 1.0
        analysis_txt.append(
            f"{msgID.id}, {time_diff}s, {p50}s, {avg_duplicate_count}, {reached}"
        )

    # Create the plots
    plt.figure(figsize=(12, 6))
    plt.bar(range(len(msg_ids)), time_diffs)
    plt.xlabel("Message Index")
    plt.ylabel("Delivery Time Difference (seconds)")
    plt.title("Message Delivery Time Differences")
    plt.xticks(
        range(len(msg_ids)), [mid.id for mid in msg_ids], rotation=45, ha="right"
    )
    plt.tight_layout()

    if not os.path.exists(output_folder):
        os.makedirs(output_folder)
    plt.savefig(f"{output_folder}/message_delivery_times.png")
    plt.close()

    plt.figure(figsize=(12, 6))
    plt.bar(range(len(msg_ids)), avg_duplicates)
    plt.xlabel("Message Index")
    plt.ylabel("Avg Duplicate Count")
    plt.title("Avg Message Duplicate Differences")
    plt.xticks(
        range(len(msg_ids)), [mid.id for mid in msg_ids], rotation=45, ha="right"
    )
    plt.tight_layout()

    plt.savefig(f"{output_folder}/avg_msg_duplicate_count.png")
    plt.close()

    _, network_to_nodes_mapping = parse_node_id_to_network_id(f"{folder}/shadow.yaml")
    node_delivery_times = create_node_delivery_times_mapping(ordered_messages)
    network_to_label = parse_gml_node_labels(f"{folder}/graph.gml")
    plot_delivery_times_per_network_id(
        plt, network_to_nodes_mapping, node_delivery_times, network_to_label
    )
    plt.savefig(f"{output_folder}/delivery_times_per_network.png")
    plt.close()

    plt.figure(figsize=(12, 6))
    plt.xlabel("Time since initial publish (seconds)")
    plt.ylabel("Number of Nodes with Message")
    plt.title("Message Delivery CDF")
    plt.xlim(0, 1)
    for msgID, deliveries in ordered_messages.items():
        plot_msg_delivery_cdf(plt, deliveries, label=msgID.id)
    plt.legend(bbox_to_anchor=(1.05, 1), loc="upper left")
    plt.tight_layout()

    plt.savefig(f"{output_folder}/message_delivery_cdf.png")
    plt.close()

    # Print the analysis and save it to a file
    with open(f"{output_folder}/analysis.txt", "w") as f:
        f.write(
            "Message ID, Time to Disseminate, p50 to Disseminate, Avg Duplicate Count, Reached percent\n"
        )
        for line in analysis_txt:
            f.write(line + "\n")


def main():
    parser = argparse.ArgumentParser(
        description="Analyze message deliveries from gossipsub logs"
    )
    parser.add_argument("folder", help="Folder containing log files")
    parser.add_argument(
        "-o",
        "--output",
        default="plots",
        help="Output folder for plots and analysis (default: plots)",
    )
    parser.add_argument(
        "-s",
        "--skip",
        type=int,
        default=0,
        help="Number of messages to skip from the beginning (default: 0)",
    )

    args = parser.parse_args()
    analyse_message_deliveries(args.folder, args.output, args.skip)


if __name__ == "__main__":
    main()
