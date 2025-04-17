#!/usr/bin/env python
import re
import matplotlib.pyplot as plt
import numpy as np
import seaborn as sns
from collections import defaultdict
import os
import pdb

pink = "\x1b[35m"
red = "\x1b[31m"
green = "\x1b[32m"
normal = "\x1b[0m"

def extract_analysis_date(log_file):
    match = re.search(r'rrfs\.(\d{8})/\d{2}', log_file)
    if match:
        return match.group(1)
    return "unknown_date"

def extract_analysis_time(log_file):
    match = re.search(r'rrfs\.(\d{8})\/(\d{2})', log_file)
    if match:
        return f"{match.group(1)} {match.group(2)}Z"
    return os.path.basename(log_file)  # Fallback to filename if pattern is missing

def categorize_obs_types(obs_types):
    grouped_obs = {
        "Temperature": [],
        "Humidity": [],
        "Winds": [],
        "Pressure": []
    }
    for obs in obs_types:
        if "airTemperature" in obs:
            grouped_obs["Temperature"].append(obs)
        elif "specificHumidity" in obs:
            grouped_obs["Humidity"].append(obs)
        elif "winds" in obs:
            grouped_obs["Winds"].append(obs)
        elif "stationPressure" in obs:
            grouped_obs["Pressure"].append(obs)
    return {k: v for k, v in grouped_obs.items() if v}

def parse_logs(log_files):
    pattern = (r"CostJo\s+:\s+Nonlinear Jo\((?P<obs_type>\w+_\w+_\d+)\)\s+=\s+"
               r"(?P<jo_value>[\d\.e+-]+)(?:,\s+nobs\s+=\s+(?P<nobs>\d+),"
               r"\s+Jo/n\s+=\s+(?P<jo_per_n>[\d\.e+-]+),\s+err\s+=\s+(?P<err>[\d\.e+-]+))?")

    jo_data = defaultdict(lambda: defaultdict(lambda: np.nan))
    nobs_data = defaultdict(lambda: defaultdict(lambda: np.nan))
    jo_per_n_data = defaultdict(lambda: defaultdict(lambda: np.nan))
    jo_per_n_diff = defaultdict(lambda: defaultdict(lambda: np.nan))
    cycle_labels = [f"{hour:02d}Z" for hour in range(24)]
    analysis_date = extract_analysis_date(log_files[0])

    for log_file in log_files:
        with open(log_file, 'r') as file:
            log_text = file.read()
            hour_match = re.search(r"\d{8}/(\d{2})", log_file)
            if hour_match:
                hour = int(hour_match.group(1))
            else:
                continue

            valid_data = False
            obs_counts = defaultdict(list)
            for line in log_text.splitlines():
                match = re.search(pattern, line)
                if match:
                    obs_type = match.group('obs_type')
                    jo_value = float(match.group('jo_value')) if match.group('jo_value') != '0' else np.nan
                    nobs = int(match.group('nobs')) if match.group('nobs') else np.nan
                    jo_per_n = float(match.group('jo_per_n')) if match.group('jo_per_n') else np.nan

                    if hour not in jo_data[obs_type]:
                        jo_data[obs_type][hour] = jo_value
                    if hour not in nobs_data[obs_type]:
                        nobs_data[obs_type][hour] = nobs
                    if hour not in jo_per_n_data[obs_type]:
                        jo_per_n_data[obs_type][hour] = jo_per_n
                    obs_counts[obs_type].append(jo_per_n)
                    valid_data = True

            for obs_type, values in obs_counts.items():
                if len(values) >= 3:
                    jo_per_n_diff[obs_type][hour] = (values[2] - values[0]) / values[0] if values[0] != 0 else np.nan

            if not valid_data:
                print(f"{red}No valid Jo data found for {log_file}. It will appear as missing in the heatmap.{normal}")

    return jo_data, nobs_data, jo_per_n_data, jo_per_n_diff, cycle_labels, analysis_date

def plot_heatmaps(stats, title, output_file, cycles, cbar_label, colormap, fmt=".2f", vmin=None, vmax=None, center=None, highlight_high=None, highlight_low=None):
    grouped_obs = categorize_obs_types(stats.keys())
    num_groups = len(grouped_obs)
    if num_groups == 0:
        print("No valid observation types found in the input data!")
        return

    fig, axes = plt.subplots(num_groups, 1, figsize=(24, 6 * num_groups), constrained_layout=True)
    if num_groups == 1:
        axes = [axes]

    for ax, (group_name, obs_list) in zip(axes, grouped_obs.items()):
        obs_list.sort(key=lambda x: int(x.split('_')[-1]))  # Sort by trailing number
        print(f"{green}Processing {group_name}:{normal} {obs_list}")

        matrix = np.full((len(obs_list), 24), np.nan)

        for i, obs in enumerate(obs_list):
            for hour in range(24):
                matrix[i, hour] = stats[obs].get(hour, np.nan)

        mask_high = np.full_like(matrix, False, dtype=bool) if highlight_high is not None else None
        mask_low = np.full_like(matrix, False, dtype=bool) if highlight_low is not None else None

        for i in range(len(obs_list)):
            for j in range(24):
                value = matrix[i, j]
                if highlight_high is not None and value > highlight_high:
                    mask_high[i, j] = True
                if highlight_low is not None and value < highlight_low:
                    mask_low[i, j] = True

        sns.heatmap(matrix, annot=True, fmt=fmt, cmap=colormap, xticklabels=cycles,
                    yticklabels=obs_list, linewidths=0.5, linecolor="gray", ax=ax,
                    cbar=True, cbar_kws={"label": cbar_label}, vmin=vmin, vmax=vmax, center=center)

        if highlight_high is not None or highlight_low is not None:
            for i in range(len(obs_list)):
                for j in range(24):
                    if highlight_high is not None and mask_high[i, j]:
                        ax.add_patch(plt.Rectangle((j, i), 1, 1, fill=False, edgecolor='red', lw=2))
                    if highlight_low is not None and mask_low[i, j]:
                        ax.add_patch(plt.Rectangle((j, i), 1, 1, fill=False, edgecolor='blue', lw=2))

        ax.set_title(f"{group_name} - {title}")
        ax.set_xlabel("Analysis Cycle Time (UTC)")
        ax.set_ylabel("Observation Type")
        ax.tick_params(axis='x', rotation=45)

    plt.suptitle(title, fontsize=16)
    plt.savefig(output_file, dpi=300, bbox_inches='tight')
    print(f"{title} saved as {pink}{output_file}{normal} \n")

def main(log_files):
    jo_data, nobs_data, jo_per_n_data, jo_per_n_diff, cycle_labels, analysis_date = parse_logs(log_files)

    if jo_data:
        plot_heatmaps(jo_data, f"Nonlinear Jo Values: {analysis_date}", f"heatmap_jo.png", cycle_labels, "Jo Value", "Reds", vmin=0, vmax=25000)
    #if nobs_data:
    #    plot_heatmaps(nobs_data, f"Number of Observations (nobs): {analysis_date}", f"heatmap_nobs.png", cycle_labels, "Observation Count", "Reds", fmt=".0f", vmin=0, vmax=25000)
    if jo_per_n_data:
        plot_heatmaps(jo_per_n_data, f"Jo/n (Jo per Observation): {analysis_date}", f"heatmap_jo_per_n.png", cycle_labels, "Jo/n Value", "coolwarm", vmin=0, vmax=2, center=1, highlight_high=1.5, highlight_low=0.5)
    if jo_per_n_diff:
        plot_heatmaps(jo_per_n_diff, f"Percent Change in Jo/n: {analysis_date}", f"heatmap_jo_per_n_diff.png", cycle_labels, "Percent Change", "coolwarm", vmin=-1, vmax=1, center=0, highlight_high=0, highlight_low=-0.3)

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Parse and plot grouped Nonlinear Jo values from log files as heatmaps.")
    parser.add_argument("log_files", nargs='+', help="Paths to the log files")
    args = parser.parse_args()
    main(args.log_files)

