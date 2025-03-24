#!/usr/bin/env python
import sys
import numpy as np
import xarray as xr
import matplotlib.pyplot as plt
import seaborn as sns
import os
import re
import warnings
from datetime import datetime, timedelta
from matplotlib.colors import Normalize
import pdb

# Suppress unnecessary warnings
warnings.filterwarnings("ignore", category=RuntimeWarning)

# Unit conversion factors
UNIT_CONVERSIONS = {
    "specificHumidity": 1000.0,  # Convert kg/kg to g/kg
}

def generate_full_cycle_range(jdiag_files):
    """Generate a full hourly range of cycles based on the available files."""
    detected_dates = set()

    for file in jdiag_files:
        match = re.search(r"(\d{8})/.*jedivar_(\d{2})", file)
        if match:
            date, _ = match.groups()
            detected_dates.add(date)

    full_cycles = []
    for date in sorted(detected_dates):
        for hour in range(24):
            full_cycles.append(f"{date} {hour:02d}Z")

    return full_cycles, date

def compute_bias_rms(jdiag_files, cycles, obs_types):
    """Compute bias (mean O-B) and RMS (sqrt of mean squared O-B) for each jdiag file, ensuring missing files show as NaN."""
    stats = {f"{cycle}_{obs}": {"bias": np.nan, "rms": np.nan, "bias_corrected_rms": np.nan} for cycle in cycles for obs in obs_types}  # Initialize with NaNs

    for file in jdiag_files:
        try:
            ds_ombg = xr.open_dataset(file, group="ombg")  # Read the ombg
            ds_obserr = xr.open_dataset(file, group="EffectiveError0") # Read the ObsError
            # Use EffectiveQC2 in the future.

            obs_var = list(ds_ombg.data_vars.keys())[0]  # Extract variable name
            if obs_var not in ds_ombg.variables:
                continue

            ombg = ds_ombg[obs_var].values   # Get O-B values
            obserr = ds_obserr[obs_var].values  # Get observation error values

            # Apply valid data filtering (ignore fill values)
            fill_value = ds_ombg[obs_var].attrs.get('_FillValue', np.nan)
            valid_mask = (ombg != fill_value) & (~np.isnan(obserr)) & (obserr < 1e+10)
            ombg = ombg[valid_mask]  # Keep only assimilated observations

            # Apply unit conversion if needed
            scale_factor = UNIT_CONVERSIONS.get(obs_var, 1.0)
            ombg *= scale_factor

            # Extract cycle and obs type
            match = re.search(r"(\d{8})/.*jedivar_(\d{2})", file)
            obtype_match = re.search(r"jdiag_(.+)\.nc4", os.path.basename(file))
            if match and obtype_match:
                date, hour = match.groups()
                cycle = f"{date} {hour}Z"
                obtype = obtype_match.group(1)
                key = f"{cycle}_{obtype}"

                if ombg.size == 0 or np.isnan(ombg).all():
                    continue
                else:
                    bias = np.nanmean(ombg)
                    rms = np.sqrt(np.nanmean(ombg ** 2))
                    bias_corrected_rms = np.sqrt(np.nanmean((ombg - bias) ** 2))

                    stats[key] = {
                        "bias": bias,
                        "rms": rms,
                        "bias_corrected_rms": bias_corrected_rms
                    }

            ds_ombg.close()
            ds_obserr.close()

        except FileNotFoundError:
            print(f"? Warning: Missing file {file}")
        except Exception as e:
            print(f"? Error processing {file}: {e}")

    return stats

def extract_obs_types(jdiag_files):
    """Extracts unique observation types from filenames."""
    obs_types = set()

    for file in jdiag_files:
        filename = os.path.basename(file)
        obtype_match = re.search(r"jdiag_(.+)\.nc4", filename)
        if obtype_match:
            obs_types.add(obtype_match.group(1))
        else:
            print(f"? Warning: Could not extract obtype from {file}")

    return sorted(obs_types)

def get_core_obs_type(obs_type):
    """Extracts the core observation variable name from the full type (e.g., adpsfc_airTemperature_181 ? airTemperature)."""
    match = re.match(r".*?_(.*?)_\d+$", obs_type)
    return match.group(1) if match else obs_type  # Extract core variable name

def plot_bias_rms_heatmaps(stats, title, output_file, cycles, obs_types, metric="bias"):
    """Plot grouped heatmaps for Bias or RMS statistics with fixed color scales per observation category."""

    # Define fixed color ranges for bias and RMS
    bias_ranges = {
        "Temperature": (-1, 1),
        "Humidity": (-1, 1),
        "Winds": (-1, 1),
        "Pressure": (-100, 100)
    }

    rms_ranges = {
        "Temperature": (0, 3),
        "Humidity": (0, 3),
        "Winds": (0, 3),
        "Pressure": (0, 300)
    }

    colorbar_labels = {
        "Temperature": "K",
        "Humidity": "g/kg",
        "Winds": "m/s",
        "Pressure": "Pa"
    }

    # Group based on core variable names
    grouped_obs = {
        "Temperature": [],
        "Humidity": [],
        "Winds": [],
        "Pressure": []
    }

    # Identify and group valid observation types
    for obs in obs_types:
        core_obs = get_core_obs_type(obs)
        if "airTemperature" in core_obs:
            grouped_obs["Temperature"].append(obs)
        elif "specificHumidity" in core_obs:
            grouped_obs["Humidity"].append(obs)
        elif "winds" in core_obs:
            grouped_obs["Winds"].append(obs)
        elif "stationPressure" in core_obs:
            grouped_obs["Pressure"].append(obs)

    # Remove empty groups
    grouped_obs = {key: val for key, val in grouped_obs.items() if val}

    num_groups = len(grouped_obs)
    if num_groups == 0:
        print("No valid observation types found in the input data!")
        return

    fig, axes = plt.subplots(num_groups, 1, figsize=(24, 6 * num_groups), constrained_layout=True)
    if num_groups == 1:
        axes = [axes]

    for ax, (group_name, obs_list) in zip(axes, grouped_obs.items()):
        obs_list.sort(key=lambda x: int(x.split('_')[-1]))  # Sort by trailing number
        print(f"\x1b[32mProcessing {group_name}:\x1b[0m {obs_list}")

        cycle_to_index = {cycle: i for i, cycle in enumerate(cycles)}
        obs_to_index = {obs: i for i, obs in enumerate(obs_list)}

        matrix = np.full((len(obs_list), len(cycles)), np.nan)

        for key, values in stats.items():
            cycle, obtype = key.split("_", 1)
            if cycle in cycle_to_index and obtype in obs_to_index:
                j = cycle_to_index[cycle]
                i = obs_to_index[obtype]
                matrix[i, j] = values[metric]

        if np.isnan(matrix).all():
            #print(f"? Warning: No valid data for {group_name}, skipping plot.")
            continue

        # **Fixed colorbar scaling per group and metric**
        vmin, vmax = bias_ranges[group_name] if metric == "bias" else rms_ranges[group_name]
        cbar_label = f"{metric.capitalize()} ({colorbar_labels[group_name]})"
        cmap = "coolwarm" if metric == "bias" else "Reds"

        cycle_xticks = [cycle.split()[1] for cycle in cycles]  # Remove YYYYMMDD from cycles
        sns.heatmap(matrix, annot=True, fmt=".2f", cmap=cmap, norm=Normalize(vmin=vmin, vmax=vmax),
                    xticklabels=cycle_xticks, yticklabels=obs_list, linewidths=0.5, linecolor="gray", ax=ax,
                    cbar=True, cbar_kws={"label": cbar_label})

        ax.set_title(f"{group_name} - {metric.capitalize()}")
        ax.set_xlabel("Analysis Cycle Time (UTC)")
        ax.set_ylabel("Observation Type")
        ax.tick_params(axis='x', rotation=45)

    plt.suptitle(title, fontsize=16)
    plt.savefig(output_file, dpi=300, bbox_inches='tight')
    print(f"{title} saved as \x1b[35m{output_file}\x1b[0m \n")

if __name__ == "__main__":
    jdiag_files = sys.argv[1:]

    print(f"Processing {len(jdiag_files)} jdiag files...")

    cycles, date = generate_full_cycle_range(jdiag_files)
    obs_types = extract_obs_types(jdiag_files)
    bias_rms_stats = compute_bias_rms(jdiag_files, cycles, obs_types)

    plot_bias_rms_heatmaps(bias_rms_stats, f"Grouped Bias Heatmaps: {date}", f"{date}_bias_heatmap.png", cycles, obs_types, metric="bias")
    plot_bias_rms_heatmaps(bias_rms_stats, f"Grouped RMS Heatmaps {date}", f"{date}_rms_heatmap.png", cycles, obs_types, metric="rms")
    plot_bias_rms_heatmaps(bias_rms_stats, f"Grouped BCRMS Heatmaps {date}", f"{date}_bcrms_heatmap.png", cycles, obs_types, metric="bias_corrected_rms")

