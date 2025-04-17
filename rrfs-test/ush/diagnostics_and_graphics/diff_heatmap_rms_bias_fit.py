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
            "nobs": 0
        } for cycle in cycles for obs in obs_types
    }

    for file in jdiag_files:
        # Extract cycle and obtype before trying to open datasets
        match = re.search(r"(\d{8})/.*jedivar_(\d{2})", file)
        obtype_match = re.search(r"jdiag_(.+)\.nc4?$", os.path.basename(file))
        if not (match and obtype_match):
            print(f"? Warning: Could not extract cycle and obtype from {file}")
            continue
        date, hour = match.groups()
        cycle = f"{date} {hour}Z"
        obtype = obtype_match.group(1)
        key = f"{cycle}_{obtype}"

        # Skip if the key isn't in stats (due to mismatch between ctl_files and exp_files)
        if key not in stats:
            print(f"? Warning: Key {key} not in stats, skipping file {file}")
            continue

        try:
            ds_ombg = xr.open_dataset(file, group="ombg")
            ds_obserr = xr.open_dataset(file, group="EffectiveError0")
            ds_effqc = xr.open_dataset(file, group="EffectiveQC2")
            ds_oman = xr.open_dataset(file, group="oman")

            obs_var = list(ds_ombg.data_vars.keys())[0]  # Extract variable name
            if obs_var not in ds_ombg.variables:
                ds_ombg.close()
                ds_obserr.close()
                ds_effqc.close()
                ds_oman.close()
                continue

            ombg = ds_ombg[obs_var].values
            obserr = ds_obserr[obs_var].values
            effqc = ds_effqc[obs_var].values
            oman = ds_oman[obs_var].values

            # Apply valid data filtering
            valid_mask = get_valid_mask(effqc)
            ombg = ombg[valid_mask]
            oman = oman[valid_mask]

            # Apply unit conversion if needed
            scale_factor = UNIT_CONVERSIONS.get(obs_var, 1.0)
            ombg *= scale_factor
            oman *= scale_factor

            if ombg.size == 0 or np.isnan(ombg).all():
                ds_ombg.close()
                ds_obserr.close()
                ds_effqc.close()
                ds_oman.close()
                continue

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
            stats[key] = {
                "ombg_bias": ombg_bias,
                "ombg_rms": ombg_rms,
                "oman_bias": oman_bias,
                "oman_rms": oman_rms,
                "fitting_ratio": fitting_ratio,
                "nobs": ombg.size
            }

            ds_ombg.close()
            ds_obserr.close()
            ds_effqc.close()
            ds_oman.close()

        except FileNotFoundError:
            print(f"? Warning: Missing file {file}")
        except Exception as e:
            print(f"? {red}Error processing {file}: {e}{normal}")
            stats[key]["oman_bias"] = np.nan
            stats[key]["oman_rms"] = np.nan
            stats[key]["fitting_ratio"] = np.nan

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

def plot_diff_heatmaps(stats, title, output_file, cycles, obs_types, metric):
    """Plot heatmaps for differences, handling both percent and straight differences."""
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
        print(f"{green}Processing {group_name}:{normal} {obs_list}")

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
            continue

        cmap = "RdBu_r"  # Blue for positive, red for negative
        center = 0

        # Set colorbar range based on metric
        if metric != "nobs":
            vmin = -100
            vmax = 100
        else:
            vmin = None
            vmax = None

        # Adjust labels and format based on the metric
        if metric == "nobs":
            cbar_label = "Difference in Observation Counts"
            annot_fmt = ".0f"  # Format as float with 0 decimal places 
            suptitle_note = "Positive values indicate more observations in the experiment"
            group_title = f"{group_name} - Observation Count Difference"
        else:
            cbar_label = "Percent Difference (%)"
            annot_fmt = ".1f"  # Float format with one decimal
            suptitle_note = "Positive values indicate improvement (lower |bias|, lower RMS, higher fitting ratio)"
            group_title = f"{group_name} - {metric.replace('_', ' ').capitalize()} Percent Difference"

        cycle_xticks = [cycle.split()[1] for cycle in cycles]

        sns.heatmap(matrix, annot=True, fmt=annot_fmt, cmap=cmap, center=center, vmin=vmin, vmax=vmax,
            xticklabels=cycle_xticks, yticklabels=obs_list, linewidths=0.5, linecolor="gray", ax=ax,
            cbar=True, cbar_kws={"label": cbar_label})

        ax.set_title(group_title)
        ax.set_xlabel("Analysis Cycle Time (UTC)")
        ax.set_ylabel("Observation Type")
        ax.tick_params(axis='x', rotation=45)

    plt.suptitle(title + "\n" + suptitle_note, fontsize=16)
    plt.savefig(output_file, dpi=300, bbox_inches='tight')
    print(f"{title} saved as {pink}{output_file}{normal} \n")

if __name__ == "__main__":
    if len(sys.argv) < 4 or "--" not in sys.argv:
        print("Usage: python diff_heatmap_rms_bias_fit.py ctl_name exp_name ctl_files -- exp_files")
        sys.exit(1)

    # Extract ctl_name and exp_name
    ctl_name = sys.argv[1]
    exp_name = sys.argv[2]

    # Parse two sets of JDIAG files separated by '--'
    try:
        idx = sys.argv.index("--")
        ctl_files = sys.argv[3:idx]
        exp_files = sys.argv[idx+1:]
    except ValueError:
        print("Usage: python diff_heatmap_rms_bias_fit.py ctl_name exp_name ctl_files -- exp_files")
        sys.exit(1)

    print(f"Processing {len(ctl_files)} files for {ctl_name} and {len(exp_files)} files for {exp_name}...")

    # Generate cycles and observation types from ctl files
    cycles, date = generate_full_cycle_range(ctl_files)
    obs_types = extract_obs_types(ctl_files)

    # Compute statistics for both experiments
    stats_ctl = compute_bias_rms(ctl_files, cycles, obs_types)
    stats_exp = compute_bias_rms(exp_files, cycles, obs_types)

    # Compute differences
    diff_stats = {}
    for key in stats_ctl:
        diff_stats[key] = {}
        # Bias: (|ctl| - |exp|) / |ctl| * 100%
        for metric in ["ombg_bias", "oman_bias"]:
            ctl_val = stats_ctl[key][metric]
            exp_val = stats_exp.get(key, {}).get(metric, np.nan)
            if not np.isnan(ctl_val) and not np.isnan(exp_val) and abs(ctl_val) != 0:
                diff_stats[key][metric] = (abs(ctl_val) - abs(exp_val)) / abs(ctl_val) * 100
            else:
                diff_stats[key][metric] = np.nan
        # RMS: (ctl - exp) / ctl * 100%
        for metric in ["ombg_rms", "oman_rms"]:
            ctl_val = stats_ctl[key][metric]
            exp_val = stats_exp.get(key, {}).get(metric, np.nan)
            if not np.isnan(ctl_val) and not np.isnan(exp_val) and ctl_val != 0:
                diff_stats[key][metric] = (ctl_val - exp_val) / ctl_val * 100
            else:
                diff_stats[key][metric] = np.nan
        # Fitting ratio: (exp - ctl) / ctl * 100%
        for metric in ["fitting_ratio"]:
            ctl_val = stats_ctl[key][metric]
            exp_val = stats_exp.get(key, {}).get(metric, np.nan)
            if not np.isnan(ctl_val) and not np.isnan(exp_val) and ctl_val != 0:
                diff_stats[key][metric] = (exp_val - ctl_val) / ctl_val * 100
            else:
                diff_stats[key][metric] = np.nan
        # Observation counts: exp - ctl (straight difference)
        diff_stats[key]["nobs"] = stats_exp[key]["nobs"] - stats_ctl[key]["nobs"]

    # Plot heatmaps for each metric
    for metric in ["ombg_bias", "ombg_rms", "oman_bias", "oman_rms", "fitting_ratio", "nobs"]:
        if metric == "nobs":
            title = f"{date} Observation Count Difference ({exp_name} vs {ctl_name})"
        else:
            title = f"{date} {metric.replace('_', ' ').capitalize()} Percent Difference ({exp_name} vs {ctl_name})"
        output_file = f"heatmap_{metric}_{exp_name}_vs_{ctl_name}.png"
        plot_diff_heatmaps(diff_stats, title, output_file, cycles, obs_types, metric)
