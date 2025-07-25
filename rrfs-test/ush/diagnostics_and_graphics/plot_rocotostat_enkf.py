#!/usr/bin/env python3
import argparse
import os
import sys
import re

import pandas as pd
import matplotlib.pyplot as plt
from matplotlib import rcParams


def main():
    parser = argparse.ArgumentParser(
        description="Plot Rocotostat run times per task and cycle."
    )
    parser.add_argument("filepath", help="Path to the Rocotostat file")
    parser.add_argument(
        "--start-date", type=str, default=None,
        help="Start of date range to plot (inclusive), e.g. '2024-05-06 00:00' or '202405060000'"
    )
    parser.add_argument(
        "--end-date", type=str, default=None,
        help="End of date range to plot (inclusive), e.g. '2024-05-06 12:00' or '202405061200'"
    )
    parser.add_argument(
        "--single-member", type=int, default=None,
        help="If set, plot only the specified ensemble member (1-based index)"
    )
    args = parser.parse_args()

    if not os.path.isfile(args.filepath):
        print(f"File not found: {args.filepath}", file=sys.stderr)
        sys.exit(1)

    # Read and parse
    data = []
    header_seen = False
    with open(args.filepath) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("="):
                continue
            if not header_seen and line.startswith("CYCLE"):
                header_seen = True
                continue

            parts = line.split()
            if len(parts) < 3:
                continue

            cycle_str = parts[0]
            task = parts[1]
            raw_dur = parts[-1]
            try:
                duration = float(raw_dur)
            except ValueError:
                duration = float("nan")
            data.append((cycle_str, task, duration))

    df = pd.DataFrame(data, columns=["cycle", "task", "duration"])
    df["cycle"] = pd.to_datetime(df["cycle"], format="%Y%m%d%H%M", errors="coerce")
    df = df.dropna(subset=["cycle"])

    # Detect ensemble-member suffixes of form _m001.._mNNN
    regex = re.compile(r"^(?P<base>.+?)_m(?P<member>\d{3})(?:_|$)")

    extracted = df["task"].str.extract(regex)
    df["base_task"] = extracted["base"].fillna(df["task"])
    df["member"] = extracted["member"].fillna(-1).astype(int)

    # If plotting a single member, filter accordingly
    if args.single_member is not None:
        # allow user to specify 1-based index; map to zero-padded 3-digit
        member_str = f"{args.single_member:03d}"
        df = df[(df["member"] == args.single_member) | (df["member"] == -1)]
        df["task"] = df["base_task"]
        df_plot = df.copy()
    else:
        # Compute ensemble-average over membered tasks by averaging durations per cycle-base_task
        mem_df = df[df["member"] >= 0]
        avg_df = (
            mem_df
            .groupby(["cycle", "base_task"], as_index=False)
            ["duration"].mean()
            .rename(columns={"base_task": "task"})
        )
        # keep non-member tasks unchanged
        nomem_df = (
            df[df["member"] < 0]
            .loc[:, ["cycle", "base_task", "duration"]]
            .rename(columns={"base_task": "task"})
        )
        # combine averaged and single-run tasks
        df_plot = pd.concat([avg_df, nomem_df], ignore_index=True)

    # Pivot for plotting
    df_plot = df_plot.sort_values("cycle")
    df_pivot = df_plot.pivot(index="cycle", columns="task", values="duration")

    # Filter by date range
    if args.start_date:
        start = pd.to_datetime(args.start_date)
        df_pivot = df_pivot.loc[df_pivot.index >= start]
    if args.end_date:
        end = pd.to_datetime(args.end_date)
        df_pivot = df_pivot.loc[df_pivot.index <= end]

    # Prepare styles
    colors = rcParams['axes.prop_cycle'].by_key()['color']
    linestyles = ['-', '--', ':', '-.']
    n_colors = len(colors)
    n_styles = len(linestyles)

    # Plot each task with its overall mean in legend
    fig, ax = plt.subplots(figsize=(12, 6))
    for i, task in enumerate(df_pivot.columns):
        series = df_pivot[task].dropna()
        if not series.empty:
            mean_ = series.mean()
            stats_label = f" ({mean_:.0f}s mean)"
        else:
            stats_label = ""
        color = colors[i % n_colors]
        ls = linestyles[(i // n_colors) % n_styles]
        ax.plot(
            df_pivot.index,
            df_pivot[task],
            marker='o',
            markersize=2,
            color=color,
            linestyle=ls,
            label=task + stats_label
        )

    ax.set_xlabel("Cycle")
    ax.set_ylabel("Duration (s)")
    ax.set_title("Rocotostat Task Durations by Cycle")
    plt.xticks(rotation=45)
    ax.legend(ncol=1, fontsize='small', loc='upper left')
    plt.tight_layout()

    # Save figure
    output_file = "plot_rocotostat_enkf.png"
    plt.savefig(output_file, dpi=150)
    print(f"Plot saved to {output_file}")


if __name__ == "__main__":
    main()

