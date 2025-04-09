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

pink = "\x1b[35m"
red = "\x1b[31m"
green = "\x1b[32m"
normal = "\x1b[0m"

# Unit conversion factors
UNIT_CONVERSIONS = {
    "specificHumidity": 1000.0,  # Convert kg/kg to g/kg
}

# Units for plotting
UNITS = {
    "airTemperature": "K",
    "specificHumidity": "g/kg",
    "windEastward": "m/s",
    "windNorthward": "m/s",
    "stationPressure": "Pa"
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
    """Accumulate data for all variables in ombg and oman groups and compute statistics."""
    stats = {}  # Use (obtype, obs_var) tuples as keys

    for file in jdiag_files:
        try:
            ds_ombg = xr.open_dataset(file, group="ombg")
            ds_obserr = xr.open_dataset(file, group="EffectiveError0")
            ds_effqc = xr.open_dataset(file, group="EffectiveQC2")
            ds_meta = xr.open_dataset(file, group="MetaData")
            try:
                ds_oman = xr.open_dataset(file, group="oman")
            except KeyError:
                print(f"? Warning: No 'oman' group in {file}, OMAN stats will be NaN.")
                ds_oman = None

            obtype_match = re.search(r"jdiag_(.+)\.nc4?$", os.path.basename(file))
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
                effqc = ds_effqc[obs_var].values if obs_var in ds_effqc.data_vars else np.full_like(ombg, np.nan)
                if ds_oman is not None and obs_var in ds_oman.data_vars:
                    oman = ds_oman[obs_var].values
                else:
                    oman = np.full_like(ombg, np.nan)

                fill_value = ds_ombg[obs_var].attrs.get('_FillValue', np.nan)
                #valid_mask = (ombg != fill_value) & (ombg < 1e+5) & (~np.isnan(obserr)) & (obserr < 1e+10) & (pressure > 0) & (pressure < 1100)
                #valid_mask = (effqc <= 1)
                valid_mask = get_valid_mask(effqc)
                pressure_valid = pressure[valid_mask]
                ombg_valid = ombg[valid_mask]
                oman_valid = oman[valid_mask]

                if pressure_valid.size == 0:
                    print(f"{red}? No valid data for {obs_var} in {file}, skipping variable.{normal}")
                    continue

                scale_factor = UNIT_CONVERSIONS.get(obs_var, 1.0)
                ombg_valid *= scale_factor
                oman_valid *= scale_factor

                key = (obtype, obs_var)
                if key not in stats:
                    stats[key] = {"pressure": [], "ombg": [], "oman": [], "counts": []}
                stats[key]["pressure"].extend(pressure_valid.tolist())
                stats[key]["ombg"].extend(ombg_valid.tolist())
                stats[key]["oman"].extend(oman_valid.tolist())
                stats[key]["counts"].extend([1] * len(pressure_valid))

            ds_ombg.close()
            ds_obserr.close()
            ds_effqc.close()
            ds_meta.close()
            if ds_oman is not None:
                ds_oman.close()
        except FileNotFoundError:
            print(f"? Warning: Missing file {file}")
        except Exception as e:
            print(f"{red}? Error processing {file}: {e}{normal}")

    # Compute binned statistics
    final_stats = {}
    pressure_bins = np.logspace(np.log10(180), np.log10(1100), num=20)

    for key, data in stats.items():
        if not data["pressure"]:
            continue

        obtype, obs_var = key
        pressure = np.array(data["pressure"])
        ombg = np.array(data["ombg"])
        oman = np.array(data["oman"])
        counts = np.array(data["counts"])

        binned_bias_ombg = np.full(len(pressure_bins) - 1, np.nan)
        binned_rms_ombg = np.full(len(pressure_bins) - 1, np.nan)
        binned_bias_oman = np.full(len(pressure_bins) - 1, np.nan)
        binned_rms_oman = np.full(len(pressure_bins) - 1, np.nan)
        binned_counts = np.zeros(len(pressure_bins) - 1, dtype=int)

        for i in range(len(pressure_bins) - 1):
            mask = (pressure >= pressure_bins[i]) & (pressure < pressure_bins[i + 1])
            binned_counts[i] = np.sum(counts[mask])
            if np.any(mask):
                binned_bias_ombg[i] = np.nanmean(ombg[mask])
                binned_rms_ombg[i] = np.sqrt(np.nanmean(ombg[mask] ** 2))
                binned_bias_oman[i] = np.nanmean(oman[mask])
                binned_rms_oman[i] = np.sqrt(np.nanmean(oman[mask] ** 2))

        fitting_ratio = np.where(binned_rms_ombg > 0, (binned_rms_ombg - binned_rms_oman) / binned_rms_ombg, np.nan)

        final_stats[key] = {
            "pressure": pressure_bins[:-1],
            "bias_ombg": binned_bias_ombg,
            "rms_ombg": binned_rms_ombg,
            "bias_oman": binned_bias_oman,
            "rms_oman": binned_rms_oman,
            "fitting_ratio": fitting_ratio,
            "counts": binned_counts,
        }

    return final_stats

def plot_vertical_profiles(stats, output_prefix, date_range):
    """Plot vertical profiles for each (obtype, obs_var) with OMBG, OMAN, and fitting ratio."""
    for key, data in stats.items():
        obtype, obs_var = key
        pressure = np.array(data["pressure"])
        bias_ombg = np.array(data["bias_ombg"])
        rms_ombg = np.array(data["rms_ombg"])
        bias_oman = np.array(data["bias_oman"])
        rms_oman = np.array(data["rms_oman"])
        fitting_ratio = np.array(data["fitting_ratio"])
        counts = np.array(data["counts"])

        valid_mask = (pressure > 0) & (~np.isnan(bias_ombg)) & (~np.isnan(rms_ombg))
        pressure = pressure[valid_mask]
        bias_ombg = bias_ombg[valid_mask]
        rms_ombg = rms_ombg[valid_mask]
        bias_oman = bias_oman[valid_mask]
        rms_oman = rms_oman[valid_mask]
        fitting_ratio = fitting_ratio[valid_mask]
        counts = counts[valid_mask]

        if pressure.size == 0:
            print(f"? Skipping {obtype}_{obs_var} due to no valid data.")
            continue

        fig, (ax0, ax1, ax2) = plt.subplots(1, 3, figsize=(18, 6), sharey=True)
        plt.subplots_adjust(wspace=0.1)  # Reduce whitespace between subplots

        # Bias plot: OMBG and OMAN
        ax0.plot(bias_ombg, pressure, marker='o', linestyle='-', color='g', label="OMB Bias")
        if not np.all(np.isnan(bias_oman)):
            ax0.plot(bias_oman, pressure, marker='o', linestyle='-', color='b', label="OMA Bias")
        ax0.axvline(0, linestyle="--", color="gray")
        ax0.set_xlabel(f"Bias ({UNITS.get(obs_var, 'unknown')})")
        ax0.set_xlim(-1, 1)
        ax0.legend()
        ax0.grid(True)

        # RMS plot: OMBG and OMAN
        ax1.plot(rms_ombg, pressure, marker='o', linestyle='-', color='r', label="OMB RMS")
        if not np.all(np.isnan(rms_oman)):
            ax1.plot(rms_oman, pressure, marker='o', linestyle='-', color='orange', label="OMA RMS")
        ax1.set_xlabel(f"RMS ({UNITS.get(obs_var, 'unknown')})")
        ax1.set_xlim(0, 3)
        ax1.legend()
        ax1.grid(True)

        # Fitting ratio plot
        ax2.plot(fitting_ratio, pressure, marker='o', linestyle='-', color='purple', label="Fitting Ratio")
        ax2.set_xlabel("Fitting Ratio (OMB RMS - OMA RMS) / OMB RMS")
        ax2.set_xlim(0, 1)
        ax2.legend()
        ax2.grid(True)

        # Y-axis settings
        ax0.set_ylabel("Pressure (hPa)")
        ax0.set_ylim(150, 1100)
        ax0.invert_yaxis()
        ax0.set_yscale("log")
        ax0.set_yticks([200, 300, 400, 500, 600, 700, 800, 900, 1000])
        ax0.get_yaxis().set_major_formatter(mticker.FuncFormatter(lambda x, _: f"{int(x)}"))

        # Add observation counts on the RMS plot
        for p, count in zip(pressure, counts):
            if count > 0:
                ax2.text(ax2.get_xlim()[1] * 1.05, p, f"{count}", fontsize=10, verticalalignment="center")

        # Title and filename
        title = f"Vertical Profile for {obtype} - {obs_var} ({date_range})"
        filename = f"{output_prefix}_{obtype}_{obs_var}.png"
        plt.suptitle(title)
        plt.savefig(filename, dpi=300, bbox_inches="tight")
        print(f"Saved profile: {pink}{filename}{normal}")

        plt.close()

if __name__ == "__main__":
    jdiag_files = sys.argv[1:]
    if not jdiag_files:
        print("Error: No JDIAG files provided. Usage: python profile_rms_bias.py <jdiag_file1> ...")
        sys.exit(1)
    date_range = extract_date_range(jdiag_files)
    profile_stats = compute_vertical_profiles(jdiag_files)
    plot_vertical_profiles(profile_stats, "profile", date_range)
