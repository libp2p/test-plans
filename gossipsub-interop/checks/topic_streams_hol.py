#!/usr/bin/env python3
"""Verify the small message was not HoL-blocked behind the large one.

Scenario contract (topic-streams-hol):
  - message id 1: 1 MiB on topic-large
  - message id 2: 1 KiB on topic-small
  - publisher is node 0; both topics are subscribed by all nodes

With topic streams, receivers should log "Received Message" for the small
message *before* the large one. Without topic streams, the small message is
head-of-line blocked and arrives after the large message.
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime
from pathlib import Path

LARGE_MESSAGE_ID = "1"
SMALL_MESSAGE_ID = "2"
PUBLISHER_NODE_ID = "0"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Validate that the small message arrived before the large message "
            "on every non-publisher node (no cross-topic HoL blocking)."
        )
    )
    parser.add_argument(
        "shadow_output",
        help="Path to the Shadow output directory (the one containing the hosts/ folder).",
    )
    parser.add_argument(
        "--large-id",
        default=LARGE_MESSAGE_ID,
        help=f"Message id of the large message (default: {LARGE_MESSAGE_ID}).",
    )
    parser.add_argument(
        "--small-id",
        default=SMALL_MESSAGE_ID,
        help=f"Message id of the small message (default: {SMALL_MESSAGE_ID}).",
    )
    parser.add_argument(
        "--publisher",
        default=PUBLISHER_NODE_ID,
        help=f"Node id of the publisher to exclude (default: {PUBLISHER_NODE_ID}).",
    )
    return parser.parse_args()


def parse_time(ts: str) -> datetime:
    # Go slog RFC3339 / RFC3339Nano; Python 3.11+ handles offsets. Strip a
    # trailing Z if present for fromisoformat compatibility on older Pythons.
    if ts.endswith("Z"):
        ts = ts[:-1] + "+00:00"
    return datetime.fromisoformat(ts)


def iter_stdout_logs(hosts_dir: Path):
    for stdout_file in sorted(hosts_dir.rglob("*.stdout")):
        if stdout_file.is_file():
            yield stdout_file


def first_receive_times(
    hosts_dir: Path, large_id: str, small_id: str
) -> dict[str, dict[str, datetime]]:
    """Return node_id -> {message_id: first receive time} for large/small."""
    wanted = {large_id, small_id}
    # node_id -> msg_id -> datetime
    times: dict[str, dict[str, datetime]] = {}

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
                    times.setdefault(current_node_id, {})
                elif msg == "Received Message":
                    mid = str(entry.get("id", ""))
                    if mid not in wanted:
                        continue
                    nid = current_node_id or node_name.removeprefix("node")
                    ts_raw = entry.get("time")
                    if not ts_raw:
                        continue
                    try:
                        ts = parse_time(ts_raw)
                    except ValueError:
                        continue
                    node_times = times.setdefault(nid, {})
                    prev = node_times.get(mid)
                    if prev is None or ts < prev:
                        node_times[mid] = ts

    return times


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

    times = first_receive_times(hosts_dir, args.large_id, args.small_id)
    receivers = sorted(
        nid for nid in times if nid != args.publisher
    )

    if not receivers:
        print("no non-publisher nodes found in logs", file=sys.stderr)
        return 1

    print(
        f"Checking HoL: small id={args.small_id} should arrive before "
        f"large id={args.large_id} (publisher node {args.publisher})"
    )
    print(f"Receiver nodes: {len(receivers)}")
    print()

    failures: list[str] = []
    for nid in receivers:
        node_times = times[nid]
        large_ts = node_times.get(args.large_id)
        small_ts = node_times.get(args.small_id)

        if large_ts is None and small_ts is None:
            failures.append(nid)
            print(f"  [FAIL] node{nid}: received neither message")
            continue
        if large_ts is None:
            failures.append(nid)
            print(f"  [FAIL] node{nid}: missing large message ({args.large_id})")
            continue
        if small_ts is None:
            failures.append(nid)
            print(f"  [FAIL] node{nid}: missing small message ({args.small_id})")
            continue

        delta = large_ts - small_ts
        if small_ts < large_ts:
            print(
                f"  [OK]   node{nid}: small at {small_ts.isoformat()} "
                f"before large at {large_ts.isoformat()} "
                f"(small led by {delta.total_seconds():.3f}s)"
            )
        else:
            failures.append(nid)
            blocked_by = (small_ts - large_ts).total_seconds()
            print(
                f"  [FAIL] node{nid}: small at {small_ts.isoformat()} "
                f"after large at {large_ts.isoformat()} "
                f"(HoL blocked by {blocked_by:.3f}s)"
            )

    print()
    if failures:
        print(
            f"FAILED: {len(failures)}/{len(receivers)} receivers saw HoL blocking "
            f"or missing messages. Topic streams should deliver the small message "
            f"before the large one.",
            file=sys.stderr,
        )
        return 1

    print(
        f"PASSED: all {len(receivers)} receivers got the small message before "
        f"the large message (no cross-topic HoL blocking)."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
