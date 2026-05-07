#!/usr/bin/env python3
"""Verify that every message in a subnet-blob-msg run was delivered to all nodes."""

from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Validate that every message in a subnet-blob-msg Shadow run "
            "was delivered to all nodes."
        )
    )
    parser.add_argument(
        "shadow_output",
        help="Path to the Shadow output directory (the one containing the hosts/ folder).",
    )
    parser.add_argument(
        "--min-reach",
        type=float,
        default=1.0,
        help="Minimum fraction of non-publisher nodes that must receive each message (default: 1.0).",
    )
    parser.add_argument(
        "--skip",
        type=int,
        default=4,
        help="Number of initial (warmup) messages to skip when checking reach (default: 4).",
    )
    return parser.parse_args()


def iter_stdout_logs(hosts_dir: Path):
    """Yield all stdout log files under the given hosts directory."""
    for stdout_file in sorted(hosts_dir.rglob("*.stdout")):
        if stdout_file.is_file():
            yield stdout_file


def parse_logs(hosts_dir: Path):
    """Parse all stdout logs and return per-message delivery sets and total node count.

    Returns:
        (message_deliveries, node_count) where message_deliveries maps
        message_id -> set of node_ids that received it, ordered by first
        delivery time across nodes.
    """
    # message_id -> set of node_ids
    deliveries: dict[str, set[str]] = defaultdict(set)
    # message_id -> earliest timestamp string (for ordering)
    first_seen: dict[str, str] = {}
    node_ids: set[str] = set()

    for log_path in iter_stdout_logs(hosts_dir):
        node_name = log_path.parent.name  # e.g. "node0"
        current_node_id: str | None = None

        with log_path.open("r", encoding="utf-8", errors="replace") as fh:
            for line in fh:
                try:
                    entry = json.loads(line)
                except (json.JSONDecodeError, ValueError):
                    continue

                msg = entry.get("msg")
                if msg == "PeerID":
                    current_node_id = str(entry.get("node_id", node_name))
                    node_ids.add(current_node_id)
                elif msg == "Received Message":
                    mid = entry.get("id", "")
                    if not mid:
                        continue
                    nid = current_node_id or node_name
                    node_ids.add(nid)
                    deliveries[mid].add(nid)
                    ts = entry.get("time", "")
                    if mid not in first_seen or ts < first_seen[mid]:
                        first_seen[mid] = ts

    # Order messages by first delivery time
    ordered_ids = sorted(deliveries.keys(), key=lambda m: first_seen.get(m, ""))
    return deliveries, ordered_ids, len(node_ids)


def main() -> int:
    args = parse_args()
    base_dir = Path(args.shadow_output).expanduser().resolve()
    if not base_dir.exists():
        print(f"shadow output directory does not exist: {base_dir}", file=sys.stderr)
        return 1

    hosts_dir = base_dir / "hosts"
    if not hosts_dir.is_dir():
        print(f"hosts directory not found under: {base_dir}", file=sys.stderr)
        return 1

    deliveries, ordered_ids, node_count = parse_logs(hosts_dir)

    if not ordered_ids:
        print("no messages found in logs", file=sys.stderr)
        return 1

    if node_count == 0:
        print("no nodes found in logs", file=sys.stderr)
        return 1

    # Skip warmup messages
    check_ids = ordered_ids[args.skip:]
    if not check_ids:
        print(
            f"no messages left after skipping {args.skip} warmup messages "
            f"(total messages: {len(ordered_ids)})",
            file=sys.stderr,
        )
        return 1

    # For each message, one node is the publisher so max receivers = node_count - 1
    expected_receivers = node_count - 1
    failures: list[tuple[str, int, float]] = []

    for mid in check_ids:
        receivers = len(deliveries[mid])
        # The publisher also appears in "Received Message" sometimes, so cap at node_count
        reach = min(receivers, expected_receivers) / expected_receivers if expected_receivers > 0 else 0.0
        if reach < args.min_reach:
            failures.append((mid, receivers, reach))

    print(f"Nodes: {node_count}")
    print(f"Total messages: {len(ordered_ids)} (skipped {args.skip} warmup)")
    print(f"Checked messages: {len(check_ids)}")
    print(f"Required reach: {args.min_reach:.0%}")
    print()

    for mid in check_ids:
        receivers = len(deliveries[mid])
        reach = min(receivers, expected_receivers) / expected_receivers if expected_receivers > 0 else 0.0
        status = "OK" if reach >= args.min_reach else "FAIL"
        print(f"  [{status}] {mid}: {receivers}/{expected_receivers} nodes ({reach:.0%})")

    print()
    if failures:
        print(
            f"FAILED: {len(failures)}/{len(check_ids)} messages did not reach "
            f"{args.min_reach:.0%} of nodes.",
            file=sys.stderr,
        )
        return 1

    print(f"PASSED: all {len(check_ids)} messages reached {args.min_reach:.0%} of nodes.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
