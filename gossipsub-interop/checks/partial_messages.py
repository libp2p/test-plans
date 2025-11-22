#!/usr/bin/env python3
"""Verify that each node stdout log contains the expected completion message."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

MESSAGE_SUBSTRING = '"msg":"All parts received"'


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Validate that every node stdout log inside a Shadow output directory "
            "contains the expected completion message."
        )
    )
    parser.add_argument(
        "shadow_output",
        help="Path to the Shadow output directory (the one containing the hosts/ folder).",
    )
    parser.add_argument(
        "--count",
        type=int,
        default=1,
        help="Minimum number of times each stdout log must contain the target message (default: 1).",
    )
    return parser.parse_args()


def iter_stdout_logs(hosts_dir: Path):
    """Yield all stdout log files under the given hosts directory."""
    for stdout_file in sorted(hosts_dir.rglob("*.stdout")):
        if stdout_file.is_file():
            yield stdout_file


def count_occurrences(path: Path, needle: str) -> int:
    """Count how many times the string appears inside the file."""
    with path.open("r", encoding="utf-8", errors="replace") as handle:
        total = 0
        for chunk in iter(lambda: handle.read(4096), ""):
            total += chunk.count(needle)
    return total


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

    stdout_logs = list(iter_stdout_logs(hosts_dir))
    if not stdout_logs:
        print(f"no stdout logs found under: {hosts_dir}", file=sys.stderr)
        return 1

    missing = []
    for log_path in stdout_logs:
        occurrences = count_occurrences(log_path, MESSAGE_SUBSTRING)
        if occurrences < args.count:
            missing.append((log_path, occurrences))

    if missing:
        print(
            "The following stdout logs do not contain the required message:",
            file=sys.stderr,
        )
        for log_path, occurrences in missing:
            rel_path = log_path.relative_to(base_dir)
            print(
                f"  - {rel_path}: found {occurrences} occurrences (expected >= {args.count})",
                file=sys.stderr,
            )
        print(f"{len(missing)} / {len(stdout_logs)} logs missing the message.", file=sys.stderr)
        return 1

    print(
        f"All {len(stdout_logs)} stdout logs under {hosts_dir} contain the required message."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
