"""Run a Shadow simulation with optional sweep over GossipSub *D*.

Folder‑naming tweak: if you pass ``--d 5`` the auto‑generated
output directory becomes, e.g.::

    subnet-blob-msg-3-all-wfr-d5-1-20250702104500-g123abc.data/

(where *d5* appears right after the composition).
"""
from __future__ import annotations

import argparse
import datetime as _dt
import json
import os
import random
import subprocess
from dataclasses import asdict

import experiment  # local module
from network_graph import generate_graph
from analyze_message_deliveries import analyse_message_deliveries

_PARAMS_FILE = "params.json"


# ------------------------- helpers -------------------------

def _auto_output_dir(
    scenario: str,
    node_count: int,
    composition: str,
    seed: int,
    d_value: int | None,
) -> str:
    """Build a deterministic-ish folder name that now embeds the D value."""
    try:
        git_describe = subprocess.check_output(
            ["git", "describe", "--always", "--dirty"], text=True
        ).decode("utf-8").strip()


    except subprocess.CalledProcessError:
        git_describe = "unknown"

    timestamp = _dt.datetime.now().strftime("%Y%m%d%H%M%S")
    d_part = f"d{d_value}" if d_value is not None else "d‑default"
    return f"{scenario}-{node_count}-{composition}-{d_part}-{seed}-{timestamp}-{git_describe}.data"


# ------------------------- main ----------------------------

def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true", help="Generate graph/config only")
    parser.add_argument("--node_count", type=int, required=True)
    parser.add_argument("--disable_gossip", action="store_true")
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--scenario", default="subnet-blob-msg")
    parser.add_argument("--composition", default="all-go")
    parser.add_argument("--output_dir")
    parser.add_argument("--wfr_d_robust", type=int, required=False)


    args = parser.parse_args(argv)

    # ---------------- auto output dir ----------------
    if args.output_dir is None:
        args.output_dir = _auto_output_dir(
            args.scenario,
            args.node_count,
            args.composition,
            args.seed,
            args.d_value,
        )

    random.seed(args.seed)

    # ---------------- experiment & graph -------------
    binaries = experiment.composition(args.composition)
    experiment_params = experiment.scenario(
        scenario_name=args.scenario,
        node_count=args.node_count,
        disable_gossip=args.disable_gossip,
        wfr_d_robust=args.wfr_d_robust,
    )

    with open(_PARAMS_FILE, "w") as f:
        data = asdict(experiment_params)
        data["script"] = [inst.model_dump(exclude_none=True) for inst in experiment_params.script]
        json.dump(data, f)

    binary_paths = random.choices(
        [b.path for b in binaries],
        weights=[b.percent_of_nodes for b in binaries],
        k=args.node_count,
    )

    generate_graph(
        binary_paths,
        "graph.gml",
        "shadow.yaml",
        params_file_location=os.path.join(os.getcwd(), _PARAMS_FILE),
    )

    if args.dry_run:
        print("[dry‑run] artefacts generated →", os.getcwd())
        return

    # ---------------- build + run Shadow -------------
    subprocess.run(["make", "binaries"], check=True)
    subprocess.run(["shadow", "--progress", "true", "-d", args.output_dir, "shadow.yaml"], check=True)

    # ---------------- collect artefacts --------------
    for fname in ["shadow.yaml", "graph.gml", _PARAMS_FILE]:
        os.rename(fname, os.path.join(args.output_dir, fname))

    analyse_message_deliveries(args.output_dir, f"{args.output_dir}/plots", 4)


if __name__ == "__main__":
    main()

