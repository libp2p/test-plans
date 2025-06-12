#!/usr/bin/env python3
from dataclasses import asdict
import argparse
import json
import os
import random
import subprocess
from network_graph import generate_graph
import experiment

from analyze_message_deliveries import analyse_message_deliveries

params_file_name = "params.json"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--dry-run",
        type=bool,
        required=False,
        help="If set, will generate files but not run Shadow",
        default=False,
    )
    parser.add_argument("--node_count", type=int, required=True)
    parser.add_argument("--seed", type=int, required=False, default=1)
    parser.add_argument(
        "--scenario", type=str, required=False, default="subnet-blob-msg"
    )
    parser.add_argument("--composition", type=str, required=False, default="all-go")
    parser.add_argument("--output_dir", type=str, required=False)
    args = parser.parse_args()

    if args.output_dir is None:
        try:
            git_describe = subprocess.check_output(
                ["git", "describe", "--always", "--dirty"]
            )
        except subprocess.CalledProcessError:
            git_describe = "unknown"

        import datetime

        timestamp = datetime.datetime.now().strftime("%Y%m%d%H%M%S")
        args.output_dir = f"{args.scenario}-{args.node_count}-{args.composition}-{args.seed}-{timestamp}-{git_describe}.data"

    random.seed(args.seed)

    binaries = experiment.composition(args.composition)
    experiment_params = experiment.scenario(args.scenario, args.node_count)

    with open(params_file_name, "w") as f:
        d = asdict(experiment_params)
        d["script"] = [
            instruction.model_dump(exclude_none=True)
            for instruction in experiment_params.script
        ]
        json.dump(d, f)

    # Define the binaries we are running
    binary_paths = random.choices(
        [b.path for b in binaries],
        weights=[b.percent_of_nodes for b in binaries],
        k=args.node_count,
    )

    # Generate the network graph and the Shadow config for the binaries
    generate_graph(
        binary_paths,
        "graph.gml",
        "shadow.yaml",
        params_file_location=os.path.join(os.getcwd(), params_file_name),
    )

    if args.dry_run:
        return

    subprocess.run(["make", "binaries"])

    subprocess.run(
        ["shadow", "--progress", "true", "-d", args.output_dir, "shadow.yaml"],
    )

    # Analyse message deliveries
    analyse_message_deliveries(args.output_dir)

    # Move files to output_dir
    os.rename("shadow.yaml", os.path.join(args.output_dir, "shadow.yaml"))
    os.rename("graph.gml", os.path.join(args.output_dir, "graph.gml"))
    os.rename("params.json", os.path.join(args.output_dir, "params.json"))
    os.rename("plots", os.path.join(args.output_dir, "plots"))


if __name__ == "__main__":
    main()
