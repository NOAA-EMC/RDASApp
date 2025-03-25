#!/usr/bin/env python
import sys
import numpy as np
import xarray as xr
import matplotlib.pyplot as plt
import os
import re
import warnings
import matplotlib.ticker as mticker

# Suppress unnecessary warnings
warnings.filterwarnings("ignore", category=RuntimeWarning)

# Unit conversion factors
UNIT_CONVERSIONS = {
    "specificHumidity": 1000.0,  # Convert kg/kg to g/kg
}

# Units for plotting (aligned with map_ombg.py where applicable)
UNITS = {
    "airTemperature": "K",
    "specificHumidity": "g/kg",
    "windEastward": "m/s",
    "windNorthward": "m/s",
    "stationPressure": "Pa"
}

def extract_date_range(jdiag_files):
    """Extracts the earliest and latest timestamps from the provided files."""
    unique_timestamps = set()
    for file in jdiag_files:
        match = re.search(r"/(\d{8})/rrfs_jedivar_(\d{2})_", file)
        if match:
            date, hour = match.groups()
            unique_timestamps.add((date, int(hour)))
    if unique_timestamps:
        sorted_timestamps = sorted(unique_timestamps)
        start_date, start_hour = sorted_timestamps[0]
        end_date, end_hour = sorted_timestamps[-1]
        return f"{start_date} {start_hour:02d}Z to {end_date} {end_hour:02d}Z"
    return "Unknown Date Range"

def get_core_obs_type(obs_type):
    """Extract the core observation variable name from the full type.
    Special case: 'winds' maps to 'windEastward'."""
    match = re.match(r".*?_(.*?)_\d+$", obs_type)
    if match:
        core = match.group(1)
        if core == "winds":
            return "windEastward"
        return core
    return obs_type

def compute_vertical_profiles(jdiag_files):
    """Accumulate data for all variables in ombg group and compute statistics."""
    stats = {}  # Use (obtype, obs_var) tuples as keys

    for file in jdiag_files:
        try:
            ds_ombg = xr.open_dataset(file, group="ombg")
            ds_obserr = xr.open_dataset(file, group="EffectiveError0")
            ds_meta = xr.open_dataset(file, group="MetaData")

            obtype_match = re.search(r"jdiag_(.+)\.nc4", os.path.basename(file))
            if not obtype_match:
                continue
            obtype = obtype_match.group(1)

            if "pressure" not in ds_meta.variables:
                print(f"? Skipping {file}: No pressure variable in MetaData.")
                continue

            pressure = ds_meta["pressure"].values / 100.0  # Pa to hPa

            for obs_var in ds_ombg.data_vars:
                if obs_var not in ds_ombg.variables:
                    continue

                ombg = ds_ombg[obs_var].values
                obserr = ds_obserr[obs_var].values if obs_var in ds_obserr.data_vars else np.full_like(ombg, np.nan)
                fill_value = ds_ombg[obs_var].attrs.get('_FillValue', np.nan)
                valid_mask = (ombg != fill_value) & (~np.isnan(obserr)) & (obserr < 1e+10) & (pressure > 0) & (pressure < 1100)
                pressure_valid = pressure[valid_mask]
                ombg_valid = ombg[valid_mask]

                if pressure_valid.size == 0:
                    print(f"\x1b[31m? No valid data for {obs_var} in {file}, skipping variable.\x1b[0m")
                    continue

                scale_factor = UNIT_CONVERSIONS.get(obs_var, 1.0)
                ombg_valid *= scale_factor

                key = (obtype, obs_var)
                if key not in stats:
                    stats[key] = {"pressure": [], "ombg": [], "counts": []}
                stats[key]["pressure"].extend(pressure_valid.tolist())
                stats[key]["ombg"].extend(ombg_valid.tolist())
                stats[key]["counts"].extend([1] * len(pressure_valid))

            ds_ombg.close()
            ds_obserr.close()
            ds_meta.close()
        except FileNotFoundError:
            print(f"? Warning: Missing file {file}")
        except Exception as e:
            print(f"? Error processing {file}: {e}")

    # Compute binned statistics
    final_stats = {}
    pressure_bins = np.logspace(np.log10(180), np.log10(1100), num=20)

    for key, data in stats.items():
        if not data["pressure"]:
            continue

        obtype, obs_var = key
        pressure = np.array(data["pressure"])
        ombg = np.array(data["ombg"])
        counts = np.array(data["counts"])

        binned_bias = np.full(len(pressure_bins) - 1, np.nan)
        binned_rms = np.full(len(pressure_bins) - 1, np.nan)
        binned_counts = np.zeros(len(pressure_bins) - 1, dtype=int)

        for i in range(len(pressure_bins) - 1):
            mask = (pressure >= pressure_bins[i]) & (pressure < pressure_bins[i + 1])
            binned_counts[i] = np.sum(counts[mask])
            if np.any(mask):
                binned_bias[i] = np.nanmean(ombg[mask])
                binned_rms[i] = np.sqrt(np.nanmean(ombg[mask] ** 2))

            #print(f"Accumulated - Pressure bin range: {pressure_bins[i]:.2f} to {pressure_bins[i+1]:.2f}, Count: {binned_counts[i]}")

        final_stats[key] = {
            "pressure": pressure_bins[:-1],
            "bias": binned_bias,
            "rms": binned_rms,
            "counts": binned_counts,
        }

    return final_stats

def plot_vertical_profiles(stats, output_prefix, date_range):
    """Plot vertical profiles for each (obtype, obs_var) combination."""
    for key, data in stats.items():
        obtype, obs_var = key
        pressure = np.array(data["pressure"])
        bias = np.array(data["bias"])
        rms = np.array(data["rms"])
        counts = np.array(data["counts"])

        valid_mask = (pressure > 0) & (~np.isnan(bias)) & (~np.isnan(rms))
        pressure = pressure[valid_mask]
        bias = bias[valid_mask]
        rms = rms[valid_mask]
        counts = counts[valid_mask]

        if pressure.size == 0:
            print(f"? Skipping {obtype}_{obs_var} due to no valid data.")
            continue

        fig, ax = plt.subplots(1, 2, figsize=(12, 6), sharey=True)
        ax[0].plot(bias, pressure, marker='o', linestyle='-', color='g', label="Bias")
        ax[0].axvline(0, linestyle="--", color="gray")
        ax[0].set_xlabel(f"Bias ({UNITS.get(obs_var, 'unknown')})")
        ax[0].set_xlim(-1, 1)
        ax[0].set_ylim(150, 1100)
        ax[0].grid(True)
        ax[1].plot(rms, pressure, marker='o', linestyle='-', color='r', label="RMS")
        ax[1].set_xlabel(f"RMS ({UNITS.get(obs_var, 'unknown')})")
        ax[1].set_xlim(0, 3)
        ax[1].set_ylim(150, 1100)
        ax[1].grid(True)
        ax[0].set_ylabel("Pressure (hPa)")
        ax[0].invert_yaxis()
        ax[0].set_yscale("log")
        ax[0].set_yticks([200, 300, 400, 500, 600, 700, 800, 900, 1000])
        ax[0].get_yaxis().set_major_formatter(mticker.FuncFormatter(lambda x, _: f"{int(x)}"))

        # Add observation counts on the right side of the RMS plot
        for p, count in zip(pressure, counts):
            if count > 0:
                ax[1].text(ax[1].get_xlim()[1] * 1.05, p, f"{count}", fontsize=10, verticalalignment="center")

        if obs_var in ["windEastward", "windNorthward"]:
            title = f"Vertical Profile for {obtype} - {obs_var} ({date_range})"
            filename = f"{output_prefix}_{obtype}_{obs_var}.png"
        else:
            title = f"Vertical Profile for {obtype} ({date_range})"
            filename = f"{output_prefix}_{obtype}.png"

        plt.suptitle(title)
        plt.savefig(filename, dpi=300, bbox_inches="tight")
        print(f"Saved profile: \x1b[35m{filename}\x1b[0m")

        plt.close()

if __name__ == "__main__":
    jdiag_files = sys.argv[1:]
    if not jdiag_files:
        print("Error: No JDIAG files provided. Usage: python profile_rms_bias.py <jdiag_file1> ...")
        sys.exit(1)
    date_range = extract_date_range(jdiag_files)
    profile_stats = compute_vertical_profiles(jdiag_files)
    plot_vertical_profiles(profile_stats, "profile", date_range)
