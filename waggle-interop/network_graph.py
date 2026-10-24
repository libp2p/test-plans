from dataclasses import dataclass
import random
from typing import List
import networkx as nx
import yaml


G = nx.DiGraph()


@dataclass
class Location:
    name: str
    weight: int


@dataclass
class Edge:
    src: Location
    dst: Location
    latency: int  # in ms


@dataclass
class NodeType:
    name: str
    upload_bw: int  # in Mbps
    download_bw: int  # in Mbps
    weight: int


australia = Location("australia", 290)
europe = Location("europe", 5599)

east_asia = Location("east_asia", 1059)
west_asia = Location("west_asia", 161)

na_east = Location("na_east", 2894)
na_west = Location("na_west", 1240)

south_africa = Location("south_africa", 47)
south_america = Location("south_america", 36)

supernode = NodeType("supernode", 1024, 1024, 20)
fullnode = NodeType("fullnode", 50, 50, 80)
node_types = [supernode, fullnode]

locations = [
    australia,
    europe,
    east_asia,
    west_asia,
    na_east,
    na_west,
    south_africa,
    south_america,
]

edges = [
    Edge(australia, australia, 2),
    Edge(australia, east_asia, 110),
    Edge(australia, europe, 165),
    Edge(australia, na_west, 110),
    Edge(australia, na_east, 150),
    Edge(australia, south_america, 190),
    Edge(australia, south_africa, 220),
    Edge(australia, west_asia, 180),
    Edge(east_asia, australia, 110),
    Edge(east_asia, east_asia, 4),
    Edge(east_asia, europe, 125),
    Edge(east_asia, na_west, 100),
    Edge(east_asia, na_east, 140),
    Edge(east_asia, south_america, 175),
    Edge(east_asia, south_africa, 175),
    Edge(east_asia, west_asia, 110),
    Edge(europe, australia, 165),
    Edge(europe, east_asia, 125),
    Edge(europe, europe, 2),
    Edge(europe, na_west, 110),
    Edge(europe, na_east, 70),
    Edge(europe, south_america, 140),
    Edge(europe, south_africa, 95),
    Edge(europe, west_asia, 60),
    Edge(na_west, australia, 110),
    Edge(na_west, east_asia, 100),
    Edge(na_west, europe, 110),
    Edge(na_west, na_west, 2),
    Edge(na_west, na_east, 60),
    Edge(na_west, south_america, 100),
    Edge(na_west, south_africa, 160),
    Edge(na_west, west_asia, 150),
    Edge(na_east, australia, 150),
    Edge(na_east, east_asia, 140),
    Edge(na_east, europe, 70),
    Edge(na_east, na_west, 60),
    Edge(na_east, na_east, 2),
    Edge(na_east, south_america, 100),
    Edge(na_east, south_africa, 130),
    Edge(na_east, west_asia, 110),
    Edge(south_america, australia, 190),
    Edge(south_america, east_asia, 175),
    Edge(south_america, europe, 140),
    Edge(south_america, na_west, 100),
    Edge(south_america, na_east, 100),
    Edge(south_america, south_america, 7),
    Edge(south_america, south_africa, 195),
    Edge(south_america, west_asia, 145),
    Edge(south_africa, australia, 220),
    Edge(south_africa, east_asia, 175),
    Edge(south_africa, europe, 95),
    Edge(south_africa, na_west, 160),
    Edge(south_africa, na_east, 130),
    Edge(south_africa, south_america, 190),
    Edge(south_africa, south_africa, 7),
    Edge(south_africa, west_asia, 110),
    Edge(west_asia, australia, 180),
    Edge(west_asia, east_asia, 110),
    Edge(west_asia, europe, 60),
    Edge(west_asia, na_west, 150),
    Edge(west_asia, na_east, 110),
    Edge(west_asia, south_america, 145),
    Edge(west_asia, south_africa, 110),
    Edge(west_asia, west_asia, 5),
]


def generate_graph(
    binary_paths: List[str],
    graph_file_name: str,
    shadow_yaml_file_name: str,
    params_file_location: str,
):
    ids = {}
    for node_type in node_types:
        for location in locations:
            name = f"{location.name}-{node_type.name}"
            ids[name] = len(ids)
            G.add_node(
                name,
                host_bandwidth_up=f"{node_type.upload_bw} Mbit",
                host_bandwidth_down=f"{node_type.download_bw} Mbit",
            )

    for t1 in node_types:
        for t2 in node_types:
            for edge in edges:
                G.add_edge(
                    f"{edge.src.name}-{t1.name}",
                    f"{edge.dst.name}-{t2.name}",
                    label=f"{edge.src.name}-{t1.name} to {edge.dst.name}-{t2.name}",
                    latency=f"{edge.latency} ms",
                    packet_loss=0.0,
                )

    with open(graph_file_name, "w") as file:
        file.write("\n".join(nx.generate_gml(G)))
        file.close()

    with open("shadow.template.yaml", "r") as file:
        config = yaml.safe_load(file)

    config["network"] = {"graph": {"type": "gml", "file": {"path": "graph.gml"}}}

    config["hosts"] = {}

    for i, binary_path in enumerate(binary_paths):
        location = random.choices(locations, weights=[lc.weight for lc in locations])[0]
        node_type = random.choices(
            node_types, weights=[nt.weight for nt in node_types]
        )[0]

        config["hosts"][f"node{i}"] = {
            "network_node_id": ids[f"{location.name}-{node_type.name}"],
            "processes": [
                {
                    "args": f"--params {params_file_location}",
                    # For Debugging:
                    "environment": {
                        # "GOLOG_LOG_LEVEL": "debug",
                        "RUST_LOG": "debug",
                    },
                    "path": binary_path,
                }
            ],
        }

    with open(shadow_yaml_file_name, "w") as file:
        yaml.dump(config, file)
