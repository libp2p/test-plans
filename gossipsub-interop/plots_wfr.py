from __future__ import annotations
from pathlib import Path
import argparse
import re
import pandas as pd
import seaborn as sns
import matplotlib.pyplot as plt
from collections import defaultdict
from network_graph import locations, node_types, edges

ap = argparse.ArgumentParser()
ap.add_argument("--root", required=True,
                help="Folder that contains all *.data run directories")
ap.add_argument("-o", "--output", default=None,
                help="Folder where figures are saved (default: <root>/figures)")
ap.add_argument("--run_type", type=str, choices=['gossip', 'no_gossip'], required=True,
                help="Specify which type of runs to analyze ('gossip' or 'no_gossip')")
args = ap.parse_args()

ROOT = Path(args.root).expanduser()
# Create a subdirectory for the output based on the run type
OUT = (Path(args.output).expanduser() if args.output else ROOT / "figures") / args.run_type
OUT.mkdir(parents=True, exist_ok=True)


sns.set(style="whitegrid", font_scale=1.1, rc={"figure.dpi": 120})
CMAP = plt.colormaps.get_cmap("viridis")
D_COLOURS = {}  # d-value → colour

# ── helpers ──────────────────────────────────────────────────────────────
def d_from_name(name: str) -> int | None:
    m = re.search(r"-d(\d+)-", name)
    return int(m.group(1)) if m else None

def violin(df: pd.DataFrame, metric: str, ylabel: str,
           fname: Path, hue: str | None = None, palette=None, order=None, hue_order=None):
    plt.figure(figsize=(14, 6))
    ax = sns.violinplot(
        data=df,
        x="segment",
        y=metric,
        order=order if order is not None else sorted(df["segment"].unique()),
        hue=hue,
        hue_order=hue_order,
        palette=palette,
        density_norm="width",
        inner=None,
    )
    sns.despine(trim=True)
    ax.set_ylabel(ylabel)
    ax.set_xlabel("")
    ax.set_xticklabels(ax.get_xticklabels(), rotation=45, ha="right")
    if ax.legend_ and hue is None:
        ax.legend_.remove()
    # Adjust legend title if hue is used
    if hue is not None and ax.legend_:
        ax.legend_.set_title(hue.capitalize())
    plt.tight_layout()
    plt.savefig(fname, dpi=300)
    plt.close()
    print(f"✔ saved {fname.relative_to(Path.cwd())}")

def process_run_data(csv_path: Path) -> pd.DataFrame | None:
    if not csv_path.exists():
        print(f"[warn] {csv_path} missing – skipping this run.")
        return None

    df = pd.read_csv(csv_path)
    if "segment" not in df.columns:
        df["segment"] = df["node_label"]

    df["avg_edge_latency"] = df["segment"].map(avg_edge_latency)

    rename_map = {
        "med_s": "latency",
        "dup_avg": "dups",
    }
    if "coverage_pct" in df.columns:
        rename_map["coverage_pct"] = "coverage"

    df_rename = df.rename(columns=rename_map)

    keep_cols = ["segment", "latency", "dups", "avg_edge_latency"]
    if "coverage" in df_rename.columns:
        keep_cols.insert(2, "coverage")

    return df_rename[keep_cols].copy()

segment_latencies = defaultdict(list)
for src_type in node_types:
    for dst_type in node_types:
        for edge in edges:
            src_seg = f"{edge.src.name}-{src_type.name}"
            segment_latencies[src_seg].append(edge.latency)

avg_edge_latency = {seg: sum(lats)/len(lats) for seg, lats in segment_latencies.items()}


baseline_protocol_name = "gossipsub" if args.run_type == "gossip" else "wfr_no_gossip"
dfr_protocol_name = "dfr_with_gossip" if args.run_type == "gossip" else "dfr_no_gossip"

# Find and load the baseline data (the one without a d-value)
baseline_df = None
baseline_extremes = {}
# Find a folder that ends with the run_type and does NOT contain "-d"
baseline_folders = [p for p in ROOT.glob(f"*-{args.run_type}.data") if d_from_name(p.name) is None]

if baseline_folders:
    baseline_run_folder = baseline_folders[0]
    csv_path = baseline_run_folder / "plots" / "node_summary_metrics.csv"
    baseline_df = process_run_data(csv_path)
    if baseline_df is not None:
        baseline_df["protocol"] = baseline_protocol_name
        
        # Get best/worst nodes for baseline
        worst_base = baseline_df.loc[baseline_df["avg_edge_latency"].idxmax()]
        best_base = baseline_df.loc[baseline_df["avg_edge_latency"].idxmin()]
        baseline_extremes = {
            "latency_worst": worst_base["latency"],
            "latency_best": best_base["latency"],
            "dups_worst": worst_base["dups"],
            "dups_best": best_base["dups"],
        }
        print(f"✔ Loaded baseline '{baseline_protocol_name}' data from {baseline_run_folder.name}")
else:
    print(f"[warn] No baseline folder for run_type '{args.run_type}' found.")


# ── iterate dfr run folders of the specified type ────────────────────────
big_rows = []
conn_rows = []

# Find all folders for the specified run type that DO have a d-value
run_folders = sorted([p for p in ROOT.glob(f"*-{args.run_type}.data") if d_from_name(p.name) is not None])

if not run_folders:
    raise SystemExit(f"[err] no DFR run folders found for run_type '{args.run_type}'.")

for run in run_folders:
    d_val = d_from_name(run.name)
    # This check is technically redundant due to the list comprehension above, but safe
    if d_val is None:
        continue

    csv_path = run / "plots" / "node_summary_metrics.csv"
    df_dfr = process_run_data(csv_path)

    if df_dfr is None:
        continue

    df_dfr["d"] = d_val
    df_dfr["protocol"] = dfr_protocol_name
    
    big_rows.append(df_dfr)

    D_COLOURS.setdefault(d_val, CMAP((d_val - 1) / 7))

    # Best/worst connected nodes for this d-value
    worst = df_dfr.loc[df_dfr["avg_edge_latency"].idxmax()].copy()
    best = df_dfr.loc[df_dfr["avg_edge_latency"].idxmin()].copy()
    worst["conn"] = f"{dfr_protocol_name}-worst"
    best["conn"] = f"{dfr_protocol_name}-best"
    conn_rows.extend([worst, best])

    # Per-D vs Baseline violin plots
    if baseline_df is not None:
        combined_df = pd.concat([df_dfr, baseline_df], ignore_index=True)
        segment_order = sorted(df_dfr["segment"].unique())
        comp_palette = {dfr_protocol_name: D_COLOURS[d_val], baseline_protocol_name: "crimson"}
        
        violin(combined_df, "latency", "median latency (s)",
               OUT / f"latency_by_segment_d{d_val}_vs_baseline.png",
               hue="protocol", palette=comp_palette, order=segment_order)
        violin(combined_df, "dups", "mean duplicates / msg",
               OUT / f"duplicates_by_segment_d{d_val}_vs_baseline.png",
               hue="protocol", palette=comp_palette, order=segment_order)


# ── consolidated all-conditions figures ──────────────────────────────────
if not big_rows:
    raise SystemExit(f"[err] no DFR data for run_type '{args.run_type}' was loaded.")

BIG_DFR = pd.concat(big_rows, ignore_index=True)
ALL_DATA = pd.concat([BIG_DFR, baseline_df], ignore_index=True) if baseline_df is not None else BIG_DFR

# Create a new 'condition' column for a unified hue
ALL_DATA["condition"] = ALL_DATA.apply(
    lambda row: f"d={int(row['d'])}" if pd.notna(row.get('d')) else baseline_protocol_name,
    axis=1
)

# Create a new palette for all conditions
all_cond_palette = {f"d={d}": col for d, col in D_COLOURS.items()}
if baseline_df is not None:
    all_cond_palette[baseline_protocol_name] = "crimson"

# Sort conditions to have d-values first, then baseline
cond_order = sorted([c for c in ALL_DATA['condition'].unique() if c.startswith('d=')], key=lambda x: int(x.split('=')[1]))
if baseline_df is not None:
    cond_order.append(baseline_protocol_name)

violin(ALL_DATA, "latency", "median latency (s)",
       OUT / "latency_by_segment_all_conditions.png", hue="condition", palette=all_cond_palette, hue_order=cond_order)
violin(ALL_DATA, "dups", "mean duplicates / msg",
       OUT / "duplicates_by_segment_all_conditions.png", hue="condition", palette=all_cond_palette, hue_order=cond_order)


# ── plot best/worst node trends with baseline ──────────────────
if conn_rows:
    extremes = pd.DataFrame(conn_rows)
    extreme_palette = {f"{dfr_protocol_name}-best": "royalblue", f"{dfr_protocol_name}-worst": "darkorange"}

    # Latency plot
    plt.figure(figsize=(10, 5.5))
    sns.lineplot(
        data=extremes, x="d", y="latency", hue="conn",
        marker="o", palette=extreme_palette, linewidth=2.2
    )
    if baseline_extremes:
        plt.axhline(y=baseline_extremes["latency_worst"], color='darkorange', linestyle='--', label=f'{baseline_protocol_name}-worst')
        plt.axhline(y=baseline_extremes["latency_best"], color='royalblue', linestyle='--', label=f'{baseline_protocol_name}-best')

    sns.despine()
    plt.grid(axis="y", linestyle="--", alpha=0.6)
    plt.title(f"Latency of Best vs Worst Node: {dfr_protocol_name} vs {baseline_protocol_name}", fontsize=13)
    plt.xlabel("D value")
    plt.ylabel("Median Latency (s)")
    plt.legend(title="Node Type", loc="upper left")
    plt.tight_layout()
    plt.savefig(OUT / "latency_extremes_by_d.png", dpi=300)
    plt.close()

    # Duplicates plot
    plt.figure(figsize=(10, 5.5))
    sns.lineplot(
        data=extremes, x="d", y="dups", hue="conn",
        marker="o", palette=extreme_palette, linewidth=2.2
    )
    if baseline_extremes:
        plt.axhline(y=baseline_extremes["dups_worst"], color='darkorange', linestyle='--', label=f'{baseline_protocol_name}-worst')
        plt.axhline(y=baseline_extremes["dups_best"], color='royalblue', linestyle='--', label=f'{baseline_protocol_name}-best')

    sns.despine()
    plt.grid(axis="y", linestyle="--", alpha=0.6)
    plt.title(f"Duplicates of Best vs Worst Node: {dfr_protocol_name} vs {baseline_protocol_name}", fontsize=13)
    plt.xlabel("D value")
    plt.ylabel("Mean Duplicates per Message")
    plt.legend(title="Node Type", loc="upper left")
    plt.tight_layout()
    plt.savefig(OUT / "dups_extremes_by_d.png", dpi=300)
    plt.close()

    print(f"✔ saved latency_extremes_by_d.png and dups_extremes_by_d.png for run_type '{args.run_type}'")


# CDF Plot
plt.figure(figsize=(10, 6))
sns.ecdfplot(data=ALL_DATA, x="latency", hue="condition", hue_order=cond_order, palette=all_cond_palette)
sns.despine()
plt.grid(axis="y", linestyle="--", alpha=0.6)
plt.title(f"Latency CDF Across All Conditions ({args.run_type})", fontsize=14)
plt.xlabel("Latency (s)")
plt.ylabel("Cumulative Probability")
plt.tight_layout()
plt.savefig(OUT / "latency_cdf_all_conditions.png", dpi=300)
plt.close()
print(f"✔ saved {OUT / 'latency_cdf_all_conditions.png'}")

# KDE Plot
plt.figure(figsize=(10, 6))
sns.kdeplot(data=ALL_DATA, x="latency", hue="condition", hue_order=cond_order, palette=all_cond_palette, fill=True, alpha=0.1, linewidth=2)
sns.despine()
plt.grid(axis="y", linestyle="--", alpha=0.6)
plt.title(f"Latency Distribution (KDE) Across All Conditions ({args.run_type})", fontsize=14)
plt.xlabel("Latency (s)")
plt.ylabel("Density")
plt.tight_layout()
plt.savefig(OUT / "latency_kde_all_conditions.png", dpi=300)
plt.close()
print(f"✔ saved {OUT / 'latency_kde_all_conditions.png'}")


# Summary Scatter with IQR
def iqr(x):
    return x.quantile(0.75) - x.quantile(0.25)

summary_stats = ALL_DATA.groupby('condition').agg(
    latency_median=('latency', 'median'),
    dups_mean=('dups', 'mean'),
    latency_iqr=('latency', iqr),
    dups_iqr=('dups', iqr)
).reindex(cond_order)

plt.figure(figsize=(10, 7))
ax = plt.gca()

for condition, row in summary_stats.iterrows():
    ax.errorbar(
        x=row['latency_median'],
        y=row['dups_mean'],
        xerr=row['latency_iqr'] / 2,
        yerr=row['dups_iqr'] / 2,
        fmt='o',
        markersize=8,
        capsize=5,
        color=all_cond_palette.get(condition),
        label=condition
    )

sns.despine()
plt.grid(linestyle="--", alpha=0.6)
plt.title(f"Mean Duplicates vs. Median Latency (with IQR) ({args.run_type})", fontsize=14)
plt.xlabel("Median Latency (s) [IQR spread]")
plt.ylabel("Mean Duplicates per Message [IQR spread]")
plt.legend(title="Condition")
plt.tight_layout()
plt.savefig(OUT / "dups_vs_latency_summary.png", dpi=300)
plt.close()
print(f"✔ saved {OUT / 'dups_vs_latency_summary.png'}")