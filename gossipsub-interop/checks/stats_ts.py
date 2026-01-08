#!/usr/bin/env python3
import sys
import argparse
import statistics as stats
from datetime import datetime


def parse_ts(s: str) -> float:
    return datetime.fromisoformat(s.strip()).timestamp()


def quantile(sorted_vals, q: float) -> float:
    n = len(sorted_vals)
    if n == 1:
        return sorted_vals[0]
    h = (n - 1) * q
    lo = int(h)
    hi = min(lo + 1, n - 1)
    return sorted_vals[lo] + (h - lo) * (sorted_vals[hi] - sorted_vals[lo])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--relative-to",
        help="RFC3339 timestamp to use as t=0 (default: earliest input time)",
    )
    args = ap.parse_args()

    ts = [parse_ts(l) for l in sys.stdin if l.strip()]
    if not ts:
        return

    t0 = parse_ts(args.relative_to) if args.relative_to else min(ts)
    vals = sorted(t - t0 for t in ts)

    out = {
        "n": len(vals),
        "avg": stats.fmean(vals),
        "p25": quantile(vals, 0.25),
        "p50": quantile(vals, 0.50),
        "p75": quantile(vals, 0.75),
        "p90": quantile(vals, 0.90),
        "min": vals[0],
        "max": vals[-1],
    }

    for k in ["n", "avg", "p25", "p50", "p75", "p90", "min", "max"]:
        v = out[k]
        print(f"{k}\t{v if k == 'n' else f'{v:.9f}'}")


if __name__ == "__main__":
    main()
