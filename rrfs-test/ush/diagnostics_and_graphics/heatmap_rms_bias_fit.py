#!/usr/bin/env python
import sys
import numpy as np
import xarray as xr
import matplotlib as mpl
import matplotlib.pyplot as plt
import seaborn as sns
import os
import re
import warnings
from datetime import datetime, timedelta

# Suppress unnecessary warnings
warnings.filterwarnings("ignore", category=RuntimeWarning)

pink = "\x1b[35m"
red = "\x1b[31m"
green = "\x1b[32m"
normal = "\x1b[0m"

# Unit conversion factors
UNIT_CONVERSIONS = {
    "specificHumidity": 1000.0,  # Convert kg/kg to g/kg
}

def get_valid_mask(effqc):
    # Get the threshold EFFQC from environment variable, default to 0
    EFFQC = int(os.getenv("EFFQC", default=0))
    # Get the comparison type from environment variable, default to False (i.e., use ==)
    use_less_equal = os.getenv("USE_LESS_EQUAL", default="false").lower() == "true"

    # Apply the comparison based on use_less_equal
    if use_less_equal:
        valid_mask = (effqc <= EFFQC)  # Element-wise <= on the NumPy array
    else:
        valid_mask = (effqc == EFFQC)  # Element-wise ==

    return valid_mask

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
    """Compute bias, RMS, fitting ratio, and number of assimilated observations for each jdiag file."""
    # Initialize stats dictionary with NaNs for all metrics and 0 for nobs
    stats = {
        f"{cycle}_{obs}": {
            "ombg_bias": np.nan,
            "ombg_rms": np.nan,
            "oman_bias": np.nan,
            "oman_rms": np.nan,
            "fitting_ratio": np.nan,
            "nobs": 0  # Initialize number of observations to 0
        } for cycle in cycles for obs in obs_types
    }

    for file in jdiag_files:
        try:
            ds_ombg = xr.open_dataset(file, group="ombg")
            ds_obserr = xr.open_dataset(file, group="EffectiveError0")
            ds_effqc = xr.open_dataset(file, group="EffectiveQC2")
            ds_oman = xr.open_dataset(file, group="oman")

            obs_var = list(ds_ombg.data_vars.keys())[0]  # Extract variable name
            if obs_var not in ds_ombg.variables:
                continue

            ombg = ds_ombg[obs_var].values
            obserr = ds_obserr[obs_var].values
            effqc = ds_effqc[obs_var].values
            oman = ds_oman[obs_var].values

            # Apply valid data filtering (ignore fill values)
            fill_value = ds_ombg[obs_var].attrs.get('_FillValue', np.nan)
            #valid_mask = (ombg != fill_value) & (ombg < 1e+5) & (~np.isnan(obserr)) & (obserr < 1e+10)
            #valid_mask = (effqc <= 1)
            valid_mask = get_valid_mask(effqc)  # Use the configurable mask
            ombg = ombg[valid_mask]
            oman = oman[valid_mask]

            # Apply unit conversion if needed
            scale_factor = UNIT_CONVERSIONS.get(obs_var, 1.0)
            ombg *= scale_factor
            oman *= scale_factor

            # Extract cycle and obs type
            match = re.search(r"(\d{8})/.*jedivar_(\d{2})", file)
            obtype_match = re.search(r"jdiag_(.+)\.nc4?$", os.path.basename(file))
            if match and obtype_match:
                date, hour = match.groups()
                cycle = f"{date} {hour}Z"
                obtype = obtype_match.group(1)
                key = f"{cycle}_{obtype}"

                # Store the number of assimilated observations
                stats[key]["nobs"] = ombg.size
                if ombg.size > 0:
                    # Compute OMB statistics
                    ombg_bias = np.nanmean(ombg)
                    ombg_rms = np.sqrt(np.nanmean(ombg ** 2))

                    # Compute OMA statistics
                    oman_bias = np.nanmean(oman)
                    oman_rms = np.sqrt(np.nanmean(oman ** 2))

                    # Compute fitting ratio
                    fitting_ratio = (
                        (ombg_rms - oman_rms) / ombg_rms
                        if not np.isnan(ombg_rms) and not np.isnan(oman_rms) and ombg_rms != 0
                        else np.nan
                    )

                    # Update stats with computed values
                    stats[key].update({
                        "ombg_bias": ombg_bias,
                        "ombg_rms": ombg_rms,
                        "oman_bias": oman_bias,
                        "oman_rms": oman_rms,
                        "fitting_ratio": fitting_ratio
                    })
            ds_ombg.close()
            ds_obserr.close()
            ds_effqc.close()
            ds_oman.close()

        except FileNotFoundError:
            print(f"? Warning: Missing file {file}")
        except Exception as e:
            print(f"? {red}Error processing {file}: {e}{normal}")

    return stats

def extract_obs_types(jdiag_files):
    """Extract unique observation types from filenames."""
    obs_types = set()

    for file in jdiag_files:
        filename = os.path.basename(file)
        obtype_match = re.search(r"jdiag_(.+)\.nc4?$", filename)
        if obtype_match:
            obs_types.add(obtype_match.group(1))
        else:
            print(f"? Warning: Could not extract obtype from {file}")

    return sorted(obs_types)

def get_core_obs_type(obs_type):
    """Extracts the core observation variable name from the full type."""
    match = re.match(r".*?_(.*?)_\d+$", obs_type)
    return match.group(1) if match else obs_type

def plot_bias_rms_heatmaps(stats, title, output_file, cycles, obs_types, metric="ombg_bias"):
    """Plot grouped heatmaps for specified metric with appropriate color scales and highlighting."""
    # Define fixed color ranges for each metric type
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

    # Compute global max for nobs if plotting number of observations
    if metric == "nobs":
        all_nobs = [stats[f"{cycle}_{obs}"]["nobs"] for cycle in cycles for obs in obs_types if f"{cycle}_{obs}" in stats]
        max_nobs = max(all_nobs) if all_nobs else 0

    for ax, (group_name, obs_list) in zip(axes, grouped_obs.items()):
        obs_list.sort(key=lambda x: int(x.split('_')[-1]))  # Sort by trailing number
        print(f"{green}Processing {group_name}:{normal} {obs_list}")

        cycle_to_index = {cycle: i for i, cycle in enumerate(cycles)}
        obs_to_index = {obs: i for i, obs in enumerate(obs_list)}

        matrix = np.full((len(obs_list), len(cycles)), np.nan)

        for key, values in stats.items():
            cycle, obtype = key.split("_", 1)
            if cycle in cycle_to_index and obtype in obs_to_index:
                j = cycle_to_index[cycle]
                i = obs_to_index[obtype]
                matrix[i, j] = values[metric] #if values[metric] > 0 else np.nan

        if np.isnan(matrix).all():
            continue

        # Set color scale, labels, and format based on metric
        if metric == "nobs":
            vmin = 0
            vmax = max_nobs
            cmap = "Reds"
            center = None
            cbar_label = "Number of Assimilated Observations"
            fmt = ".0f"  # Integer format for counts
        elif metric in ["ombg_bias", "oman_bias"]:
            vmin, vmax = bias_ranges[group_name]
            cmap = "coolwarm"
            center = 0
            cbar_label = f"{metric.replace('_', ' ').upper()} ({colorbar_labels[group_name]})"
            fmt = ".2f"
        elif metric in ["ombg_rms", "oman_rms"]:
            vmin, vmax = rms_ranges[group_name]
            cmap = "Reds"
            center = None
            cbar_label = f"{metric.replace('_', ' ').upper()} ({colorbar_labels[group_name]})"
            fmt = ".2f"
        elif metric == "fitting_ratio":
            vmin = 0
            vmax = 1.0
            center = 0.5
            cmap = "coolwarm"
            cmap = mpl.cm.get_cmap("coolwarm").copy()
            cmap.set_under("black")  # Set values below vmin (0) to black
            cbar_label = "Fitting Ratio (OMB RMS - OMA RMS) / OMB RMS"
            fmt = ".2f"

        cycle_xticks = [cycle.split()[1] for cycle in cycles]  # Remove YYYYMMDD
        sns.heatmap(matrix, annot=True, fmt=fmt, cmap=cmap, vmin=vmin, vmax=vmax, center=center,
                    xticklabels=cycle_xticks, yticklabels=obs_list, linewidths=0.5, linecolor="gray", ax=ax,
                    cbar=True, cbar_kws={"label": cbar_label})

        # Add highlighting for fitting ratio only
        if metric == "fitting_ratio":
            mask_low = matrix < 0.15  # Highlight weak DA effect
            mask_high = matrix > 0.6  # Highlight potential overfitting
            for i in range(matrix.shape[0]):
                for j in range(matrix.shape[1]):
                    if mask_low[i, j]:
                        ax.add_patch(plt.Rectangle((j, i), 1, 1, fill=False, edgecolor='blue', lw=2))
                    if mask_high[i, j]:
                        ax.add_patch(plt.Rectangle((j, i), 1, 1, fill=False, edgecolor='red', lw=2))

        ax.set_title(f"{group_name} - {metric.replace('_', ' ').capitalize()}")
        ax.set_xlabel("Analysis Cycle Time (UTC)")
        ax.set_ylabel("Observation Type")
        ax.tick_params(axis='x', rotation=45)

    plt.suptitle(title, fontsize=16)
    plt.savefig(output_file, dpi=300, bbox_inches='tight')
    print(f"{title} saved as {pink}{output_file}{normal} \n")

if __name__ == "__main__":
    jdiag_files = sys.argv[1:]

    print(f"Processing {len(jdiag_files)} jdiag files...")

    cycles, date = generate_full_cycle_range(jdiag_files)
    obs_types = extract_obs_types(jdiag_files)
    stats = compute_bias_rms(jdiag_files, cycles, obs_types)

    # Plot heatmaps for each metric, including the new nobs heatmap
    plot_bias_rms_heatmaps(stats, f"OMB Bias Heatmaps: {date}", f"heatmap_ombg_bias.png", cycles, obs_types, metric="ombg_bias")
    plot_bias_rms_heatmaps(stats, f"OMB RMS Heatmaps: {date}", f"heatmap_ombg_rms.png", cycles, obs_types, metric="ombg_rms")
    plot_bias_rms_heatmaps(stats, f"OMA Bias Heatmaps: {date}", f"heatmap_oman_bias.png", cycles, obs_types, metric="oman_bias")
    plot_bias_rms_heatmaps(stats, f"OMA RMS Heatmaps: {date}", f"heatmap_oman_rms.png", cycles, obs_types, metric="oman_rms")
    plot_bias_rms_heatmaps(stats, f"Fitting Ratio Heatmaps: {date}", f"heatmap_fitting_ratio.png", cycles, obs_types, metric="fitting_ratio")
    plot_bias_rms_heatmaps(stats, f"Number of Assimilated Observations Heatmaps: {date}", f"heatmap_nobs.png", cycles, obs_types, metric="nobs")
