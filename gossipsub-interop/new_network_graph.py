from dataclasses import dataclass
import random
from typing import List, Dict
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
    latency: int

@dataclass
class NodeType:
    name: str
    upload_bw: int
    download_bw: int
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
    Edge(australia, europe, 255),
    Edge(australia, east_asia, 90),
    Edge(australia, west_asia, 195),
    Edge(australia, na_east, 180),
    Edge(australia, na_west, 135),
    Edge(australia, south_africa, 290),
    Edge(australia, south_america, 295),
    Edge(europe, australia, 255),
    Edge(europe, europe, 2),
    Edge(europe, east_asia, 150),
    Edge(europe, west_asia, 85),
    Edge(europe, na_east, 75),
    Edge(europe, na_west, 145),
    Edge(europe, south_africa, 145),
    Edge(europe, south_america, 205),
    Edge(east_asia, australia, 90),
    Edge(east_asia, europe, 150),
    Edge(east_asia, east_asia, 2),
    Edge(east_asia, west_asia, 115),
    Edge(east_asia, na_east, 155),
    Edge(east_asia, na_west, 95),
    Edge(east_asia, south_africa, 250),
    Edge(east_asia, south_america, 270),
    Edge(west_asia, australia, 195),
    Edge(west_asia, europe, 85),
    Edge(west_asia, east_asia, 115),
    Edge(west_asia, west_asia, 2),
    Edge(west_asia, na_east, 175),
    Edge(west_asia, na_west, 215),
    Edge(west_asia, south_africa, 170),
    Edge(west_asia, south_america, 285),
    Edge(na_east, australia, 180),
    Edge(na_east, europe, 75),
    Edge(na_east, east_asia, 155),
    Edge(na_east, west_asia, 175),
    Edge(na_east, na_east, 2),
    Edge(na_east, na_west, 69),
    Edge(na_east, south_africa, 210),
    Edge(na_east, south_america, 105),
    Edge(na_west, australia, 135),
    Edge(na_west, europe, 145),
    Edge(na_west, east_asia, 95),
    Edge(na_west, west_asia, 215),
    Edge(na_west, na_east, 69),
    Edge(na_west, na_west, 2),
    Edge(na_west, south_africa, 275),
    Edge(na_west, south_america, 160),
    Edge(south_africa, australia, 290),
    Edge(south_africa, europe, 145),
    Edge(south_africa, east_asia, 250),
    Edge(south_africa, west_asia, 170),
    Edge(south_africa, na_east, 210),
    Edge(south_africa, na_west, 275),
    Edge(south_africa, south_africa, 2),
    Edge(south_africa, south_america, 175),
    Edge(south_america, australia, 295),
    Edge(south_america, europe, 205),
    Edge(south_america, east_asia, 270),
    Edge(south_america, west_asia, 285),
    Edge(south_america, na_east, 105),
    Edge(south_america, na_west, 160),
    Edge(south_america, south_africa, 175),
    Edge(south_america, south_america, 2),
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

    # This assumes a 'shadow.template.yaml' exists.
    try:
        with open("shadow.template.yaml", "r") as file:
            config = yaml.safe_load(file)
    except FileNotFoundError:
        print("⚠️ shadow.template.yaml not found. Creating a default config.")
        config = {"general": {"stop_time": "100s"}}


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
                    "environment": {},
                    "path": binary_path,
                }
            ],
        }

    with open(shadow_yaml_file_name, "w") as file:
        yaml.dump(config, file)
