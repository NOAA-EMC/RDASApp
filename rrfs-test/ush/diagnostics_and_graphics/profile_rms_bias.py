#!/usr/bin/env python
import sys
import numpy as np
import xarray as xr
import matplotlib.pyplot as plt
import os
import re
import warnings
import matplotlib.ticker as mticker  # Needed for custom y-axis formatting

# Suppress unnecessary warnings
warnings.filterwarnings("ignore", category=RuntimeWarning)

# Unit conversion factors
UNIT_CONVERSIONS = {
    "specificHumidity": 1000.0,  # Convert kg/kg to g/kg
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
    else:
        return "Unknown Date Range"

def compute_vertical_profiles(jdiag_files, obs_types):
    """Accumulate all valid data first, then compute bias, RMS, and observation counts."""
    stats = {obs: {"pressure": [], "ombg": [], "counts": []} for obs in obs_types}

    for file in jdiag_files:
        try:
            ds_ombg = xr.open_dataset(file, group="ombg")  # Read O-B data
            ds_obserr = xr.open_dataset(file, group="EffectiveError0")  # Read ObsError
            ds_meta = xr.open_dataset(file, group="MetaData")  # Read MetaData (for pressure)

            obs_var = list(ds_ombg.data_vars.keys())[0]
            if obs_var not in ds_ombg.variables or "pressure" not in ds_meta.variables:
                print(f"? Skipping {file}: No valid pressure variable found in MetaData.")
                continue

            pressure = ds_meta["pressure"].values / 100.0  # Convert Pa to hPa
            ombg = ds_ombg[obs_var].values
            obserr = ds_obserr[obs_var].values

            fill_value = ds_ombg[obs_var].attrs.get('_FillValue', np.nan)
            valid_mask = (ombg != fill_value) & (~np.isnan(obserr)) & (obserr < 1e+10) & (pressure > 0) & (pressure < 1100)
            pressure = pressure[valid_mask]
            ombg = ombg[valid_mask]

            if pressure.size == 0:
                print(f"\x1b[31m? No valid data for {file}, skipping...\x1b[0m")
                continue

            scale_factor = UNIT_CONVERSIONS.get(obs_var, 1.0)
            ombg *= scale_factor

            obtype_match = re.search(r"jdiag_(.+)\.nc4", os.path.basename(file))
            if not obtype_match:
                continue
            obtype = obtype_match.group(1)

            stats[obtype]["pressure"].extend(pressure.tolist())
            stats[obtype]["ombg"].extend(ombg.tolist())
            stats[obtype]["counts"].extend([1] * len(pressure))

            #print(f"File {file} processed: {len(pressure)} valid observations.")

            # Debug print for counts per pressure bin for each file
            #pressure_bins = np.logspace(np.log10(180), np.log10(1100), num=20)
            #file_counts = np.zeros(len(pressure_bins) - 1, dtype=int)
            #for i in range(len(pressure_bins) - 1):
            #    mask = (pressure >= pressure_bins[i]) & (pressure < pressure_bins[i + 1])
            #    file_counts[i] = np.sum(mask)
            #    print(f"Pressure bin range: {pressure_bins[i]:.2f} to {pressure_bins[i+1]:.2f}, Count: {file_counts[i]}")

            ds_ombg.close()
            ds_obserr.close()
            ds_meta.close()
        except FileNotFoundError:
            print(f"? Warning: Missing file {file}")
        except Exception as e:
            print(f"? Error processing {file}: {e}")

    final_stats = {}
    pressure_bins = np.logspace(np.log10(180), np.log10(1100), num=20)

    for obtype, data in stats.items():
        if len(data["pressure"]) == 0:
            continue

        pressure = np.array(data["pressure"])
        ombg = np.array(data["ombg"])
        counts = np.array(data["counts"])

        binned_bias = np.full(len(pressure_bins) - 1, np.nan)
        binned_rms = np.full(len(pressure_bins) - 1, np.nan)
        binned_counts = np.zeros(len(pressure_bins) - 1, dtype=int)

        for i in range(len(pressure_bins) - 1):
            mask = (pressure >= pressure_bins[i]) & (pressure < pressure_bins[i + 1])
            binned_counts[i] += np.sum(counts[mask])
            if np.any(mask):
                binned_bias[i] = np.nanmean(ombg[mask])
                binned_rms[i] = np.sqrt(np.nanmean(ombg[mask] ** 2))

            print(f"Accumulated - Pressure bin range: {pressure_bins[i]:.2f} to {pressure_bins[i+1]:.2f}, Count: {binned_counts[i]}")

        final_stats[obtype] = {
            "pressure": pressure_bins[:-1],
            "bias": binned_bias,
            "rms": binned_rms,
            "counts": binned_counts,
        }

    return final_stats

def plot_vertical_profiles(stats, output_prefix, date_range):
    """Plot vertical profiles of bias, RMS, and observation counts for each observation type."""
    for obs, data in stats.items():
        if not data or "pressure" not in data or len(data["pressure"]) == 0:
            continue

        pressure = np.array(data["pressure"])
        bias = np.array(data["bias"])
        rms = np.array(data["rms"])
        counts = np.array(data["counts"])  # Include observation counts

        valid_mask = (pressure > 0) & (~np.isnan(bias)) & (~np.isnan(rms))
        pressure = pressure[valid_mask]
        bias = bias[valid_mask]
        rms = rms[valid_mask]
        counts = counts[valid_mask]  # Filter counts to match valid pressure levels

        if pressure.size == 0:
            print(f"? Skipping {obs} due to no valid pressure levels.")
            continue

        fig, ax = plt.subplots(1, 2, figsize=(12, 6), sharey=True)
        ax[0].plot(bias, pressure, marker='o', linestyle='-', color='g', label="Bias")
        ax[0].axvline(0, linestyle="--", color="gray")
        ax[0].set_xlabel("Bias")
        ax[0].set_xlim(-1, 1)  # Custom x-axis range for bias
        ax[0].set_ylim(150, 1100)  # Custom y-axis range for bias
        ax[0].grid(True)
        ax[1].plot(rms, pressure, marker='o', linestyle='-', color='r', label="RMS")
        ax[1].set_xlabel("RMS")
        ax[1].grid(True)
        ax[1].set_xlim(0, 3)  # Custom x-axis range for RMS
        ax[1].set_ylim(150, 1100)  # Custom y-axis range for bias
        ax[0].set_ylabel("Pressure (hPa)")
        ax[0].invert_yaxis()
        ax[0].set_yscale("log")
        ax[0].set_yticks([200, 300, 400, 500, 600, 700, 800, 900, 1000])
        ax[0].get_yaxis().set_major_formatter(mticker.FuncFormatter(lambda x, _: f"{int(x)}"))

        # Add observation counts on the right side of the RMS plot
        for p, count in zip(pressure, counts):
            if count > 0:
                ax[1].text(ax[1].get_xlim()[1] * 1.05, p, f"{count}", fontsize=10, verticalalignment="center")

        plt.suptitle(f"Vertical Profile for {obs} ({date_range})")
        plt.savefig(f"{output_prefix}_{obs}.png", dpi=300, bbox_inches="tight")
        print(f"Saved profile: {output_prefix}_{obs}.png")
        plt.close()



if __name__ == "__main__":
    jdiag_files = sys.argv[1:]
    date_range = extract_date_range(jdiag_files)
    obs_types = sorted(set(
        re.search(r"jdiag_(.+)\.nc4", os.path.basename(f)).group(1)
        for f in jdiag_files if re.search(r"jdiag_(.+)\.nc4", os.path.basename(f))
    ))
    profile_stats = compute_vertical_profiles(jdiag_files, obs_types)
    plot_vertical_profiles(profile_stats, "vertical_profile", date_range)
