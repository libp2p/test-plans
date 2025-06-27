from collections import defaultdict, OrderedDict
import json
import os
import sys
import argparse
from datetime import datetime
from typing import Dict, List, Tuple, Set, Optional, OrderedDict as OrderedDictType
from dataclasses import dataclass
import matplotlib.pyplot as plt

messages = defaultdict(list)
duplicate_count = defaultdict(lambda: 0)
duplicate_count_by_message_and_node = defaultdict(lambda: defaultdict(int))
peer_id_to_node_id = dict()
node_id_to_peer_id = dict()


@dataclass(frozen=True)
class MessageId:
    id: str


@dataclass(frozen=True)
class NodeId:
    id: str


@dataclass
class MessageDelivery:
    timestamp: datetime
    node_id: NodeId


@dataclass
class FileParseResult:
    node_id: NodeId
    message_deliveries: OrderedDictType[MessageId, List[MessageDelivery]]
    duplicate_counts: Dict[MessageId, int]
    duplicate_counts_by_node: Dict[MessageId, Dict[NodeId, int]]


def nodeIDFromFilename(filename):
    return filename.split(".")[0]


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


def plot_msg_delivery_cdf(plt, deliveries):
    if not deliveries:
        return

    # Sort deliveries by timestamp
    sorted_deliveries = sorted(deliveries, key=lambda x: x[0])

    # Get the initial timestamp as reference point
    start_time = sorted_deliveries[0][0]

    # Calculate time differences from start and cumulative count
    times = []
    cumulative_count = []

    for i, (ts, node_id) in enumerate(sorted_deliveries):
        time_diff = (ts - start_time).total_seconds()
        times.append(time_diff)
        cumulative_count.append(i + 1)

    # Plot the CDF
    plt.plot(times, cumulative_count, marker="o", markersize=2, alpha=0.7)


def parse_log_file(lines) -> FileParseResult:
    """
    Parse all lines from a log file iterator and extract relevant information.

    Args:
        lines: Iterator of log lines from a file

    Returns:
        FileParseResult containing parsed data from the file
    """
    node_id = NodeId("")
    seen_message_ids = set()
    message_deliveries = defaultdict(list)
    duplicate_counts = defaultdict(int)
    duplicate_counts_by_node = defaultdict(lambda: defaultdict(int))

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
            if parsed_node_id and peer_id:
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
                    duplicate_counts_by_node[message_id][node_id] += 1

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
        duplicate_counts_by_node=dict(duplicate_counts_by_node),
    )


def analyse_message_deliveries(folder, output_folder="plots"):
    analysis_txt = []

    for file in logfile_iterator(folder):
        with open(file, "r") as f:
            result = parse_log_file(f)

            # Add message deliveries to global messages dict
            for msg_id, deliveries in result.message_deliveries.items():
                for delivery in deliveries:
                    messages[msg_id.id].append(
                        (delivery.timestamp, delivery.node_id.id)
                    )

            # Add duplicate counts to global counters
            for msg_id, count in result.duplicate_counts.items():
                duplicate_count[msg_id.id] += count

            for msg_id, node_counts in result.duplicate_counts_by_node.items():
                for node, count in node_counts.items():
                    duplicate_count_by_message_and_node[msg_id.id][node.id] += count

    # Prepare data for plotting
    msg_ids = []
    time_diffs = []
    avg_duplicates = []

    total_nodes = len(node_id_to_peer_id)
    messagesIDs = list(messages.keys())
    messagesIDs.sort(key=lambda x: int(x))

    for msgID in messagesIDs:
        deliveries = messages[msgID]
        deliveries.sort(key=lambda x: x[0])
        # Update to be sorted
        messages[msgID] = deliveries
        time_diff = (deliveries[-1][0] - deliveries[0][0]).total_seconds()
        p50Idx = len(deliveries) // 2
        p50 = (deliveries[p50Idx][0] - deliveries[0][0]).total_seconds()

        msg_ids.append(msgID)
        time_diffs.append(time_diff)
        avg_duplicate_count = duplicate_count[msgID] / total_nodes
        avg_duplicates.append(avg_duplicate_count)
        reached = len(deliveries) / (total_nodes - 1)  # Minus 1 for the original sender
        if reached > 1.0:
            if len(deliveries) > total_nodes:
                raise ValueError(
                    f"Message {msgID} was delivered to more nodes than exist"
                )
            # We overshot because the original publisher received a duplicate message
            reached = 1.0
        analysis_txt.append(
            f"{msgID}, {time_diff}s, {p50}s, {avg_duplicate_count}, {reached}"
        )

    # Create the plots
    plt.figure(figsize=(12, 6))
    plt.bar(range(len(msg_ids)), time_diffs)
    plt.xlabel("Message Index")
    plt.ylabel("Delivery Time Difference (seconds)")
    plt.title("Message Delivery Time Differences")
    plt.xticks(range(len(msg_ids)), msg_ids, rotation=45, ha="right")
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
    plt.xticks(range(len(msg_ids)), msg_ids, rotation=45, ha="right")
    plt.tight_layout()

    plt.savefig(f"{output_folder}/avg_msg_duplicate_count.png")
    plt.close()

    plt.figure(figsize=(12, 6))
    plt.xlabel("Time since initial publish (seconds)")
    plt.ylabel("Number of Nodes with Message")
    plt.title("Message Delivery CDF")
    plt.xlim(0, 1)
    for msgID in messagesIDs:
        plot_msg_delivery_cdf(plt, messages[msgID])
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

    args = parser.parse_args()
    analyse_message_deliveries(args.folder, args.output)


if __name__ == "__main__":
    main()
