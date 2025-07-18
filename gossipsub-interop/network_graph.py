"""Generate a trimmed Shadow GML graph + host config using **deterministic quotas**.

This keeps the original public API:
    generate_graph(binary_paths, graph_file_name, shadow_yaml_file_name,
                   params_file_location [, seed])
but now guarantees that every `Location` and every `NodeType` appears at least
once, whatever the requested `node_count`.

Only the (location, node‑type) pairs actually used by the hosts are kept in the
GML → smaller graphs and faster Shadow start‑up.
"""
from __future__ import annotations

import random
from dataclasses import dataclass
from typing import List, Dict, Tuple

import networkx as nx
import yaml

# ---------------------------------------------------------------------------
#  Data structures
# ---------------------------------------------------------------------------

@dataclass(frozen=True, slots=True)
class Location:
    name: str
    weight: int


@dataclass(frozen=True, slots=True)
class Edge:
    src: Location
    dst: Location
    latency: int  # ms


@dataclass(frozen=True, slots=True)
class NodeType:
    name: str
    upload_bw: int  # Mbps
    download_bw: int  # Mbps
    weight: int


# ---------------- location & node‑type tables ------------------------------

# Location weights produced by Dune Analytics
_australia     = Location("australia",     458)
_europe        = Location("europe",       5323)
_east_asia     = Location("east_asia",    1464)
_west_asia     = Location("west_asia",      43)
_na_east       = Location("na_east",      3862)
_na_west       = Location("na_west",      2317)
_south_africa  = Location("south_africa",    6)
_south_america = Location("south_america",   44)

locations: List[Location] = [
    _australia,
    _europe,
    _east_asia,
    _west_asia,
    _na_east,
    _na_west,
    _south_africa,
    _south_america,
]

_supernode_max = NodeType("supernode_max", 1024, 500, 10)
_supernode_min = NodeType("supernode_min",  500, 500, 10)
_fullnode_max  = NodeType("fullnode_max",    50,  50, 30)
_fullnode_min  = NodeType("fullnode_min",    50,  25, 50)

node_types: List[NodeType] = [
    _fullnode_min,
    _fullnode_max,
    _supernode_min,
    _supernode_max,
]

# ---------------- Latency matrix (static) ----------------------------------
# (same array the user supplied originally)
edges: List[Edge] = [
    Edge(_australia, _australia, 1),    Edge(_australia, _europe, 127),     Edge(_australia, _east_asia, 55),
    Edge(_australia, _west_asia, 90),   Edge(_australia, _na_east, 97),     Edge(_australia, _na_west, 65),
    Edge(_australia, _south_america, 120), Edge(_australia, _south_africa, 140),

    Edge(_europe, _australia, 127),     Edge(_europe, _europe, 1),          Edge(_europe, _east_asia, 72),
    Edge(_europe, _west_asia, 45),      Edge(_europe, _na_east, 35),        Edge(_europe, _na_west, 55),
    Edge(_europe, _south_america, 105), Edge(_europe, _south_africa, 75),

    Edge(_east_asia, _australia, 55),   Edge(_east_asia, _europe, 72),      Edge(_east_asia, _east_asia, 2),
    Edge(_east_asia, _west_asia, 55),   Edge(_east_asia, _na_east, 90),     Edge(_east_asia, _na_west, 50),
    Edge(_east_asia, _south_america, 125), Edge(_east_asia, _south_africa, 135),

    Edge(_west_asia, _australia, 90),   Edge(_west_asia, _europe, 45),      Edge(_west_asia, _east_asia, 55),
    Edge(_west_asia, _west_asia, 2),    Edge(_west_asia, _na_east, 75),     Edge(_west_asia, _na_west, 95),
    Edge(_west_asia, _south_america, 115), Edge(_west_asia, _south_africa, 90),

    Edge(_na_east, _australia, 97),     Edge(_na_east, _europe, 35),        Edge(_na_east, _east_asia, 90),
    Edge(_na_east, _west_asia, 75),     Edge(_na_east, _na_east, 1),        Edge(_na_east, _na_west, 30),
    Edge(_na_east, _south_america, 50), Edge(_na_east, _south_africa, 110),

    Edge(_na_west, _australia, 65),     Edge(_na_west, _europe, 55),        Edge(_na_west, _east_asia, 50),
    Edge(_na_west, _west_asia, 95),     Edge(_na_west, _na_east, 30),       Edge(_na_west, _na_west, 1),
    Edge(_na_west, _south_america, 80), Edge(_na_west, _south_africa, 130),

    Edge(_south_america, _australia, 120), Edge(_south_america, _europe, 105),
    Edge(_south_america, _east_asia, 125), Edge(_south_america, _west_asia, 115),
    Edge(_south_america, _na_east, 50),    Edge(_south_america, _na_west, 80),
    Edge(_south_america, _south_america, 3), Edge(_south_america, _south_africa, 145),

    Edge(_south_africa, _australia, 140),  Edge(_south_africa, _europe, 75),
    Edge(_south_africa, _east_asia, 135),  Edge(_south_africa, _west_asia, 90),
    Edge(_south_africa, _na_east, 110),    Edge(_south_africa, _na_west, 130),
    Edge(_south_africa, _south_america, 145), Edge(_south_africa, _south_africa, 3),
]

# Build a quick lookup: (src_name, dst_name) → latency
_latency: Dict[Tuple[str, str], int] = {(e.src.name, e.dst.name): e.latency for e in edges}

# ---------------------------------------------------------------------------
#  Helpers
# ---------------------------------------------------------------------------

def _choose_with_min_one(population: List, weights: List[int], k: int, rng: random.Random) -> List:
    """Weighted draw with *at least one* occurrence of every item in *population*."""
    picks = rng.choices(population, weights=weights, k=k)
    missing = [item for item in population if item not in picks]
    for m in missing:
        victim = rng.randrange(k)
        picks[victim] = m
    return picks


# ---------------------------------------------------------------------------
#  Public API
# ---------------------------------------------------------------------------

def generate_graph(
    binary_paths: List[str],
    graph_file_name: str,
    shadow_yaml_file_name: str,
    params_file_location: str,
    *,
    seed: int | None = None,
) -> None:
    """Create `graph_file_name` + `shadow_yaml_file_name` for the given binaries.

    The number of hosts equals `len(binary_paths)`.
    If *seed* is provided the placement is fully reproducible.
    """

    # --- RNG setup ---------------------------------------------------------
    rng: random.Random
    if seed is None:
        rng = random  # use global RNG (may have been seeded by caller)
    else:
        rng = random.Random(seed)

    node_count = len(binary_paths)

    # --- Deterministic quotas w/ min‑one guarantee -------------------------
    loc_draw  = _choose_with_min_one(locations,  [l.weight for l in locations],  node_count, rng)
    type_draw = _choose_with_min_one(node_types, [t.weight for t in node_types], node_count, rng)

    active_pairs = {(loc.name, nt.name) for loc, nt in zip(loc_draw, type_draw)}

    # --- Graph ----------------------------------------------------------------
    G = nx.DiGraph()
    ids: Dict[str, int] = {}

    for loc_name, nt_name in sorted(active_pairs):  # stable order → stable ids
        loc = next(l for l in locations if l.name == loc_name)
        nt  = next(t for t in node_types if t.name == nt_name)
        node = f"{loc_name}-{nt_name}"
        ids[node] = len(ids)
        G.add_node(
            node,
            host_bandwidth_up=f"{nt.upload_bw} Mbit",
            host_bandwidth_down=f"{nt.download_bw} Mbit",
        )

    for src_loc, src_nt in active_pairs:
        for dst_loc, dst_nt in active_pairs:
            latency = _latency[(src_loc, dst_loc)]  # always present in matrix
            G.add_edge(
                f"{src_loc}-{src_nt}",
                f"{dst_loc}-{dst_nt}",
                label=f"{src_loc}-{src_nt} to {dst_loc}-{dst_nt}",
                latency=f"{latency} ms",
                packet_loss=0.0,
            )

    with open(graph_file_name, "w", encoding="utf-8") as f:
        f.write("\n".join(nx.generate_gml(G)))

    # --- Shadow YAML -------------------------------------------------------
    with open("shadow.template.yaml", "r", encoding="utf-8") as f:
        config: dict = yaml.safe_load(f)

    config["network"] = {"graph": {"type": "gml", "file": {"path": graph_file_name}}}
    config["hosts"] = {}

    for i, (binary_path, loc, nt) in enumerate(zip(binary_paths, loc_draw, type_draw)):
        node_name = f"{loc.name}-{nt.name}"
        config["hosts"][f"node{i}"] = {
            "network_node_id": ids[node_name],
            "processes": [
                {
                    "args": f"--params {params_file_location}",
                    "environment": {},  # enable RUST_LOG/GOLOG_LOG_LEVEL here if needed
                    "path": binary_path,
                }
            ],
        }

    with open(shadow_yaml_file_name, "w", encoding="utf-8") as f:
        yaml.dump(config, f, sort_keys=False)
