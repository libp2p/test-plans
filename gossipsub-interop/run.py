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
    parser.add_argument("--node_count", type=int, required=False, default=10)
    parser.add_argument("--disable_gossip", type=bool, required=False)
    parser.add_argument("--seed", type=int, required=False, default=1)
    parser.add_argument(
        "--scenario", type=str, required=False, default="subnet-blob-msg"
    )
    parser.add_argument("--composition", type=str,
                        required=False, default="all-go")
    parser.add_argument("--nodes", type=str, nargs='+', help="Direct list of binaries for each node. Sets the node count to the length of the list.")
    parser.add_argument("--output_dir", type=str, required=False)
    args = parser.parse_args()

    if args.nodes is not None:
        binary_paths = args.nodes
        args.node_count = len(args.nodes)
        composition_name = "custom"
    else:
        binaries = experiment.composition(args.composition)
        # Define the binaries we are running
        binary_paths = random.choices(
            [b.path for b in binaries],
            weights=[b.percent_of_nodes for b in binaries],
            k=args.node_count,
        )
        composition_name = args.composition

    if args.output_dir is None:
        try:
            git_describe = subprocess.check_output(
                ["git", "describe", "--always", "--dirty"]
            ).decode("utf-8").strip()
        except subprocess.CalledProcessError:
            git_describe = "unknown"

        import datetime

        timestamp = datetime.datetime.now().strftime("%Y%m%d%H%M%S")
        args.output_dir = f"{args.scenario}-{args.node_count}-{
            composition_name}-{args.seed}-{timestamp}-{git_describe}.data"

    random.seed(args.seed)

    experiment_params = experiment.scenario(
        args.scenario, args.node_count, args.disable_gossip)

    with open(params_file_name, "w") as f:
        d = asdict(experiment_params)
        d["script"] = [
            instruction.model_dump(exclude_none=True)
            for instruction in experiment_params.script
        ]
        json.dump(d, f)


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

    # Move files to output_dir
    os.rename("shadow.yaml", os.path.join(args.output_dir, "shadow.yaml"))
    os.rename("graph.gml", os.path.join(args.output_dir, "graph.gml"))
    os.rename("params.json", os.path.join(args.output_dir, "params.json"))

    # Analyse message deliveries. Skip the first 4 as warmup messages
    analyse_message_deliveries(args.output_dir, f"{args.output_dir}/plots", 4)

    link_path = os.path.join(os.getcwd(), "latest-sim")
    if os.path.exists(link_path) or os.path.islink(link_path):
        os.remove(link_path)
    os.symlink(args.output_dir, link_path)

if __name__ == "__main__":
    main()
