from collections import defaultdict
import json
import os
import sys
import argparse
from datetime import datetime
import matplotlib.pyplot as plt

messages = defaultdict(list)
duplicate_count = defaultdict(lambda: 0)
duplicate_count_by_message_and_node = defaultdict(lambda: defaultdict(int))
peer_id_to_node_id = dict()
node_id_to_peer_id = dict()


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


def analyse_message_deliveries(folder, output_folder="plots"):
    analysis_txt = []

    for file in logfile_iterator(folder):
        with open(file, "r") as f:
            node_id = ""
            seen_message_ids = set()
            for line in f:
                try:
                    parsed = json.loads(line)
                except json.JSONDecodeError:
                    continue

                if parsed["msg"] == "PeerID":
                    node_id = parsed["node_id"]
                    peer_id_to_node_id[parsed["id"]] = node_id
                    node_id_to_peer_id[node_id] = parsed["id"]
                    continue

                if "msg" not in parsed or "time" not in parsed:
                    continue

                # Parse timestamp RFC3339
                ts = datetime.fromisoformat(parsed["time"])

                match parsed["msg"]:
                    case "Received Message":
                        msgID = parsed["id"]
                        if msgID not in seen_message_ids:
                            seen_message_ids.add(msgID)
                            messages[msgID].append((ts, node_id))
                        else:
                            duplicate_count[msgID] += 1
                            duplicate_count_by_message_and_node[msgID][node_id] += 1

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
