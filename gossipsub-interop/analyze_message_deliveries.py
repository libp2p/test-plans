# ------------------------------------------------------------
# analyze_message_deliveries.py  (metrics & CSV – FINAL PATCH v5)
# ------------------------------------------------------------
#!/usr/bin/env python3
"""Parse Shadow / libp2p logs, produce plots **and** structured metrics.

*Patch v5 highlights*
=====================
* **Fix negative latencies** – we now sort every per‑message delivery list *after* merging
  deliveries from all hosts.
* No behavioural changes otherwise (v4 kept)."""
from __future__ import annotations

import argparse
import csv
import json
import os
import re
import statistics as _stats
from collections import OrderedDict, defaultdict
from dataclasses import dataclass
from datetime import datetime
from typing import Dict, List, Tuple, OrderedDict as OrderedDictType

import matplotlib.pyplot as plt
import yaml

# ----------------------------- globals -----------------------------

peer_id_to_node_id: dict[str, int] = {}
node_id_to_peer_id: dict[int, str] = {}

# ----------------------------- data‑classes -----------------------------


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


# ----------------------------- helpers -----------------------------


def parse_node_id_to_network_id(
    shadow_yaml_path: str,
) -> Tuple[Dict[NodeId, int], Dict[int, List[NodeId]]]:
    """Return ``NodeId → network_id`` and the reverse mapping."""
    node_to_network_mapping: Dict[NodeId, int] = {}
    network_to_nodes_mapping: defaultdict[int, List[NodeId]] = defaultdict(list)

    try:
        with open(shadow_yaml_path, "r") as f:
            shadow_config = yaml.safe_load(f)

        for host_name, host_cfg in shadow_config.get("hosts", {}).items():
            if not host_name.startswith("node"):
                continue
            try:
                node_id = NodeId(int(host_name[4:]))
            except ValueError:
                continue
            net_id = host_cfg.get("network_node_id")
            if net_id is None:
                continue
            node_to_network_mapping[node_id] = net_id
            network_to_nodes_mapping[net_id].append(node_id)
    except (FileNotFoundError, yaml.YAMLError) as e:
        print(f"[warn] couldn't parse shadow.yaml – {e}")

    return node_to_network_mapping, dict(network_to_nodes_mapping)


def parse_gml_node_labels(gml_path: str) -> Dict[int, str]:
    """Return mapping: `network_node_id` → human‑friendly *label* from graph.gml."""
    mapping: Dict[int, str] = {}
    try:
        with open(gml_path, "r") as f:
            content = f.read()
        for block in re.findall(r"node\s*\[([^]]*)]", content, re.DOTALL):
            id_m = re.search(r"id\s+(\d+)", block)
            lbl_m = re.search(r"label\s+\"([^\"]*)\"", block)
            if id_m and lbl_m:
                mapping[int(id_m.group(1))] = lbl_m.group(1)
    except (FileNotFoundError, IOError) as e:
        print(f"[warn] couldn't parse graph.gml – {e}")
    return mapping


# ----------------------------- log traversal -----------------------------


def logfile_iterator(folder: str):
    """Yield absolute paths to all *.stdout* logs under *folder*."""
    if "hosts" in os.listdir(folder):  # Shadow layout
        for host in os.listdir(os.path.join(folder, "hosts")):
            host_dir = os.path.join(folder, "hosts", host)
            for fn in os.listdir(host_dir):
                if fn.endswith(".stdout"):
                    yield os.path.join(host_dir, fn)
    else:
        for fn in os.listdir(folder):
            if fn.endswith(".stdout"):
                yield os.path.join(folder, fn)


# ----------------------------- plotting helpers -----------------------------


def _plot_msg_delivery_cdf(ax, deliveries, label=None):
    if not deliveries:
        return
    deliveries = sorted(deliveries, key=lambda d: d.timestamp)
    start = deliveries[0].timestamp
    xs, ys = [], []
    for i, d in enumerate(deliveries, 1):
        xs.append((d.timestamp - start).total_seconds())
        ys.append(i)
    ax.plot(xs, ys, marker="o", markersize=2, alpha=0.7, label=label)


# ----------------------------- log parser -----------------------------


def parse_log_file(lines) -> FileParseResult:
    node_id = NodeId(-1)
    seen: set[str] = set()
    msg_delivs: Dict[MessageId, List[MessageDelivery]] = defaultdict(list)
    dup_counts: Dict[MessageId, int] = defaultdict(int)

    for line in lines:
        try:
            data = json.loads(line)
        except json.JSONDecodeError:
            continue

        typ = data.get("msg")
        if typ is None:
            continue

        if typ == "PeerID":
            node_id = NodeId(data.get("node_id", -1))
            pid = data.get("id", "")
            if pid:
                peer_id_to_node_id[pid] = node_id.id
                node_id_to_peer_id[node_id.id] = pid
            continue

        if typ == "Received Message" and "time" in data:
            tstamp = datetime.fromisoformat(data["time"])
            mid_str = data.get("id", "")
            if not mid_str:
                continue
            mid = MessageId(mid_str)
            if mid_str not in seen:
                seen.add(mid_str)
                msg_delivs[mid].append(MessageDelivery(tstamp, node_id))
            else:
                dup_counts[mid] += 1

    # ensure deliveries are sorted per message
    ordered: OrderedDict[MessageId, List[MessageDelivery]] = OrderedDict()
    for mid, dels in msg_delivs.items():
        ordered[mid] = sorted(dels, key=lambda d: d.timestamp)

    return FileParseResult(node_id=node_id, message_deliveries=ordered, duplicate_counts=dup_counts)


# ----------------------------- latency map -----------------------------


def create_node_delivery_times_mapping(
    ordered_messages: OrderedDict[MessageId, List[MessageDelivery]],
) -> Dict[NodeId, Dict[MessageId, float]]:
    mapping: Dict[NodeId, Dict[MessageId, float]] = defaultdict(dict)
    for mid, dels in ordered_messages.items():
        if not dels:
            continue
        # safety: sort again
        dels_sorted = sorted(dels, key=lambda d: d.timestamp)
        first_ts = dels_sorted[0].timestamp
        for d in dels_sorted:
            mapping[d.node_id][mid] = (d.timestamp - first_ts).total_seconds()
    return dict(mapping)


# ----------------------------- main analysis -----------------------------


def analyse_message_deliveries(folder: str, output_folder: str = "plots", skip_messages: int = 0):
    # ---- parse all logs ----
    messages: Dict[MessageId, List[MessageDelivery]] = defaultdict(list)
    dup_global: Dict[MessageId, int] = defaultdict(int)
    dup_per_node: Dict[NodeId, int] = defaultdict(int)

    for log in logfile_iterator(folder):
        with open(log, "r") as fh:
            res = parse_log_file(fh)
            for mid, dels in res.message_deliveries.items():
                messages[mid].extend(dels)
            for mid, cnt in res.duplicate_counts.items():
                dup_global[mid] += cnt
                dup_per_node[res.node_id] += cnt

    # ---- sort deliveries within each message (fix negative lat) ----
    for mid in messages:
        messages[mid].sort(key=lambda d: d.timestamp)

    # ---- sort messages & optionally skip first N ----
    ordered_msgs: OrderedDict[MessageId, List[MessageDelivery]] = OrderedDict(
        sorted(messages.items(), key=lambda kv: kv[1][0].timestamp if kv[1] else datetime.max)
    )
    for _ in range(min(skip_messages, len(ordered_msgs))):
        ordered_msgs.popitem(last=False)

    # ---- latency per node ----
    node_latencies = create_node_delivery_times_mapping(ordered_msgs)

    total_nodes = len(node_id_to_peer_id) or (max((n.id for n in node_latencies), default=-1) + 1)
    total_msgs = len(ordered_msgs)

    # ---- output dir ----
    os.makedirs(output_folder, exist_ok=True)

    # ---- label helpers ----
    node_to_net, _ = parse_node_id_to_network_id(os.path.join(folder, "shadow.yaml"))
    net_to_lbl = parse_gml_node_labels(os.path.join(folder, "graph.gml"))

    def _label(nid: NodeId) -> str:
        net = node_to_net.get(nid)
        return net_to_lbl.get(net, f"net{net}" if net is not None else "unknown")

    # ---- raw CSV ----
    with open(os.path.join(output_folder, "raw_node_metrics.csv"), "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["node_id", "node_label", "message_id", "latency_s"])
        for nid, per_msg in node_latencies.items():
            for mid, lat in per_msg.items():
                w.writerow([nid.id, _label(nid), mid.id, f"{lat:.6f}"])

    # ---- per‑node summary ----
    summary_rows = []
    for nid, per_msg in sorted(node_latencies.items(), key=lambda kv: kv[0].id):
        lats = list(per_msg.values())
        if not lats:
            continue
        dup_total = dup_per_node.get(nid, 0)
        summary_rows.append({
            "node_id": nid.id,
            "node_label": _label(nid),
            "msgs": len(lats),
            "avg": _stats.mean(lats),
            "med": _stats.median(lats),
            "p95": _stats.quantiles(lats, n=100)[94],
            "dup_total": dup_total,
            "dup_avg": dup_total / len(lats),
            "reach_pct": (len(lats) / total_msgs * 100) if total_msgs else 0.0,
        })

    with open(os.path.join(output_folder, "node_summary_metrics.csv"), "w", newline="") as f:
        w = csv.writer(f)
        w.writerow([
            "node_id", "node_label", "msgs", "avg_s", "med_s", "p95_s", "dup_total", "dup_avg", "reach_pct",
        ])
        for r in summary_rows:
            w.writerow([
                r["node_id"], r["node_label"], r["msgs"], f"{r['avg']:.3f}", f"{r['med']:.3f}", f"{r['p95']:.3f}",
                r["dup_total"], f"{r['dup_avg']:.3f}", f"{r['reach_pct']:.1f}",
            ])

    # ---- pretty table to stdout ----
    if summary_rows:
        print("Per‑node delivery metrics:")
        header = (
            f"{'Node':<5} {'Label':<20} {'Msgs':<5} "
            f"{'Avg(s)':<9} {'Med(s)':<9} {'P95(s)':<9} "
            f"{'DupTot':<8} {'Dup/Msg':<9} {'Reach%':<7}"
        )
        print(header)
        for r in summary_rows:
            print(
                f"{r['node_id']:<5} {r['node_label']:<20} {r['msgs']:<5} "
                f"{r['avg']:<9.3f} {r['med']:<9.3f} {r['p95']:<9.3f} "
                f"{r['dup_total']:<8} {r['dup_avg']:<9.3f} {r['reach_pct']:<7.1f}"
            )

    # ---- plots ----
    fig_dir = output_folder

    if ordered_msgs:
        # 1) Delivery CDF per message
        fig, ax = plt.subplots(figsize=(12, 6))
        ax.set_xlabel("Time since initial publish (s)")
        ax.set_ylabel("Nodes that received")
        ax.set_title("Message delivery CDF")
        ax.set_xlim(0, 1)
        for mid, dels in ordered_msgs.items():
            _plot_msg_delivery_cdf(ax, dels, label=mid.id)
        ax.legend(bbox_to_anchor=(1.05, 1), loc="upper left", fontsize="small")
        plt.tight_layout()
        fig.savefig(os.path.join(fig_dir, "message_delivery_cdf.png"))
        plt.close(fig)

        # 2) Avg duplicate count per message
        fig, ax = plt.subplots(figsize=(12, 6))
        mids = [m.id for m in ordered_msgs]
        avg_dups = [dup_global[m] / total_nodes for m in ordered_msgs]
        ax.bar(range(len(mids)), avg_dups)
        ax.set_xlabel("Message index")
        ax.set_ylabel("Avg duplicate count")
        ax.set_title("Average duplicates per message")
        ax.set_xticks(range(len(mids)), mids, rotation=45, ha="right")
        plt.tight_layout()
        fig.savefig(os.path.join(fig_dir, "avg_msg_duplicate_count.png"))
        plt.close(fig)

        # 3) Delivery span (max‑min) per message
        fig, ax = plt.subplots(figsize=(12, 6))
        deltas = [ (dels[-1].timestamp - dels[0].timestamp).total_seconds() for dels in ordered_msgs.values() ]
        ax.bar(range(len(deltas)), deltas)
        ax.set_xlabel("Message index")
        ax.set_ylabel("Delivery span (s)")
        ax.set_title("Message delivery span")
        ax.set_xticks(range(len(deltas)), [m.id for m in ordered_msgs], rotation=45, ha="right")
        plt.tight_layout()
        fig.savefig(os.path.join(fig_dir, "message_delivery_times.png"))
        plt.close(fig)


# ----------------------------- CLI -----------------------------


def _cli():
    p = argparse.ArgumentParser(description="Analyse message deliveries from libp2p GossipSub logs")
    p.add_argument("folder", help="Folder containing Shadow output logs")
    p.add_argument("-o", "--output", default="plots", help="Output folder for plots + CSV (default: plots)")
    p.add_argument("-s", "--skip", type=int, default=0, help="Skip first N messages")
    args = p.parse_args()
    analyse_message_deliveries(args.folder, args.output, args.skip)


if __name__ == "__main__":
    _cli()
