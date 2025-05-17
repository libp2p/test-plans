from collections import defaultdict
import json
import os
import sys
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


def analyse_message_dessemination_rate(folder):
    analysis_txt = []

    # First pass - collect message delivery timestamps
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

    # Prepare data for plotting
    total_nodes = len(node_id_to_peer_id)
    messagesIDs = list(messages.keys())
    messagesIDs.sort(key=lambda x: int(x))

    # Create plot
    plt.figure(figsize=(12, 6))

    for msgID in messagesIDs:
        deliveries = messages[msgID]
        deliveries.sort(key=lambda x: x[0])
        
        # Calculate percentage of nodes reached over time
        start_time = deliveries[0][0]
        times = [(d[0] - start_time).total_seconds() for d in deliveries]
        percentages = [(i+1)/(total_nodes-1)*100 for i in range(len(deliveries))]
        
        plt.plot(times, percentages, label=f"Message {msgID}")
        
        # Store analysis data
        time_to_50 = None
        time_to_90 = None
        for t, p in zip(times, percentages):
            if not time_to_50 and p >= 50:
                time_to_50 = t
            if not time_to_90 and p >= 90:
                time_to_90 = t
                break
                
        final_reach = len(deliveries)/(total_nodes-1)*100
        analysis_txt.append(f"{msgID}, {time_to_50:.2f}s, {time_to_90:.2f}s, {final_reach:.1f}%")

    plt.xlabel("Time (seconds)")
    plt.ylabel("Nodes Reached (%)")
    plt.title("Message Dissemination Rate")
    plt.grid(True)
    plt.legend(bbox_to_anchor=(1.05, 1), loc='upper left')
    plt.tight_layout()

    if not os.path.exists("plots"):
        os.makedirs("plots")
    plt.savefig(f"plots/message_dissemination_rate_{folder}.png", bbox_inches='tight')
    plt.close()

    # Save analysis data
    with open(f"plots/dissemination_analysis_{folder}.txt", "w") as f:
        f.write("Message ID, Time to 50%, Time to 90%, Final Reach %\n")
        for line in analysis_txt:
            f.write(line + "\n")



def main():
    # Read folder from input
    folder = sys.argv[1]
    analyse_message_dessemination_rate(folder)


if __name__ == "__main__":
    main()
