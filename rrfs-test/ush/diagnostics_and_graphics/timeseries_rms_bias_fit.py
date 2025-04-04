#!/usr/bin/env python

import sys
import numpy as np
import xarray as xr
import matplotlib.pyplot as plt
import matplotlib.dates as mdates
import datetime
import os
import re
import warnings

# Suppress unnecessary warnings
warnings.filterwarnings("ignore", category=RuntimeWarning)

# Unit conversions and labels
UNIT_CONVERSIONS = {
    "specificHumidity": 1000.0,  # Convert kg/kg to g/kg
}

UNITS = {
    "airTemperature": "K",
    "specificHumidity": "g/kg",
    "windEastward": "m/s",
    "windNorthward": "m/s",
    "stationPressure": "Pa"
}

def extract_timestamp(file):
    """
    Extract timestamp from the file path.
    Expected format: .../YYYYMMDD/rrfs_jedivar_HH_...
    Returns datetime object or None if extraction fails.
    """
    match = re.search(r"/(\d{8})/rrfs_jedivar_(\d{2})_", file)
    if match:
        date, hour = match.groups()
        return datetime.datetime.strptime(date + hour, "%Y%m%d%H")
    print(f"? Warning: Could not extract timestamp from {file}")
    return None

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

def compute_stats_per_time(file):
    """
    Compute statistics for all valid observations at each time step (whole atmospheric column).
    Returns tuple: (timestamp, obtype, stats_dict) or None if processing fails.
    """
    timestamp = extract_timestamp(file)
    if timestamp is None:
        return None

    obtype_match = re.search(r"jdiag_(.+)\.nc4?$", os.path.basename(file))
    if not obtype_match:
        return None
    obtype = obtype_match.group(1)

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

        if "pressure" not in ds_meta.variables:
            print(f"? Skipping {file}: No pressure variable in MetaData.")
            return None

        pressure = ds_meta["pressure"].values / 100.0  # Convert Pa to hPa
        stats = {}

        for obs_var in ds_ombg.data_vars:
            if obs_var not in ds_ombg.variables:
                continue

            ombg = ds_ombg[obs_var].values
            obserr = ds_obserr[obs_var].values if obs_var in ds_obserr.data_vars else np.full_like(ombg, np.nan)
            effqc = ds_effqc[obs_var].values if obs_var in ds_effqc.data_vars else np.full_like(ombg, np.nan)
            oman = ds_oman[obs_var].values if ds_oman and obs_var in ds_oman.data_vars else np.full_like(ombg, np.nan)
            fill_value = ds_ombg[obs_var].attrs.get('_FillValue', np.nan)

            # Valid data mask
            valid_mask = (ombg != fill_value) & (ombg < 1e+5) & (~np.isnan(obserr)) & (obserr < 1e+10) & (pressure > 0) & (pressure < 1100)
            valid_mask = (effqc <= 1)
            ombg_valid = ombg[valid_mask]
            oman_valid = oman[valid_mask]

            if ombg_valid.size == 0:
                print(f"\x1b[31m? No valid data for {obs_var} in {file}, skipping variable.\x1b[0m")
                continue

            # Apply unit conversion
            scale_factor = UNIT_CONVERSIONS.get(obs_var, 1.0)
            ombg_valid *= scale_factor
            oman_valid *= scale_factor

            # Compute statistics
            bias_ombg = np.nanmean(ombg_valid)
            rms_ombg = np.sqrt(np.nanmean(ombg_valid ** 2))
            bias_oman = np.nanmean(oman_valid) if ds_oman else np.nan
            rms_oman = np.sqrt(np.nanmean(oman_valid ** 2)) if ds_oman else np.nan
            fitting_ratio = (rms_ombg - rms_oman) / rms_ombg if rms_ombg > 0 and ds_oman else np.nan

            stats[obs_var] = {
                "bias_ombg": bias_ombg,
                "rms_ombg": rms_ombg,
                "bias_oman": bias_oman,
                "rms_oman": rms_oman,
                "fitting_ratio": fitting_ratio,
                "count": len(ombg_valid)
            }

        ds_ombg.close()
        ds_obserr.close()
        ds_effqc.close()
        ds_meta.close()
        if ds_oman:
            ds_oman.close()

        return (timestamp, obtype, stats)

    except FileNotFoundError:
        print(f"? Warning: Missing file {file}")
        return None
    except Exception as e:
        print(f"? Error processing {file}: {e}")
        return None

def plot_time_series(jdiag_files):
    """
    Generate a single time series plot with three subplots for each observation type and variable:
    Bias (OMB and OMA), RMS (OMB and OMA), and Fitting Ratio over time.
    """
    all_data = {}
    date_range = extract_date_range(jdiag_files)

    # Process each file and collect data
    for file in jdiag_files:
        result = compute_stats_per_time(file)
        if result:
            timestamp, obtype, stats = result
            for obs_var, stat_dict in stats.items():
                key = (obtype, obs_var)
                if key not in all_data:
                    all_data[key] = []
                all_data[key].append((timestamp, stat_dict))

    # Generate a combined plot for each (obtype, obs_var)
    for key, data_list in all_data.items():
        obtype, obs_var = key
        data_list.sort(key=lambda x: x[0])  # Sort by timestamp

        timestamps = [x[0] for x in data_list]
        bias_ombg = [x[1]["bias_ombg"] for x in data_list]
        rms_ombg = [x[1]["rms_ombg"] for x in data_list]
        bias_oman = [x[1]["bias_oman"] for x in data_list]
        rms_oman = [x[1]["rms_oman"] for x in data_list]
        fitting_ratio = [x[1]["fitting_ratio"] for x in data_list]

        # Create a single figure with three subplots, sharing the x-axis
        fig, (ax0, ax1, ax2) = plt.subplots(3, 1, figsize=(10, 12), sharex=True)

        # Subplot 0: Bias (OMB and OMA)
        ax0.plot(timestamps, bias_ombg, marker='o', linestyle='-', color='g', label="OMB Bias")
        ax0.plot(timestamps, bias_oman, marker='o', linestyle='-', color='b', label="OMA Bias")
        ax0.axhline(0, color='gray', linestyle='--')
        ax0.set_ylabel(f"Bias ({UNITS.get(obs_var, 'unknown')})")
        ax0.set_ylim(-1, 1)
        ax0.legend()
        ax0.grid(True)

        # Subplot 1: RMS (OMB and OMA)
        ax1.plot(timestamps, rms_ombg, marker='o', linestyle='-', color='r', label="OMB RMS")
        ax1.plot(timestamps, rms_oman, marker='o', linestyle='-', color='orange', label="OMA RMS")
        ax1.set_ylabel(f"RMS ({UNITS.get(obs_var, 'unknown')})")
        ax1.set_ylim(0, 3)
        ax1.legend()
        ax1.grid(True)

        # Subplot 2: Fitting Ratio
        ax2.plot(timestamps, fitting_ratio, marker='o', linestyle='-', color='purple', label="Fitting Ratio")
        ax2.set_ylabel("Fitting Ratio")
        ax2.set_xlabel("Time")
        ax2.set_ylim(0, 1)
        ax2.legend()
        ax2.grid(True)

        # Format the shared x-axis
        ax2.xaxis.set_major_locator(mdates.AutoDateLocator())
        ax2.xaxis.set_major_formatter(mdates.DateFormatter('%Y-%m-%d %H:%M'))
        plt.setp(ax2.get_xticklabels(), rotation=45, ha='right')

        # Add a title for the entire figure
        fig.suptitle(f"Time Series for {obtype} - {obs_var} ({date_range})")

        # Adjust layout and save
        fig.tight_layout(rect=[0, 0, 1, 0.95])  # Leave space for suptitle
        filename = f"timeseries_{obtype}_{obs_var}.png"
        fig.savefig(filename, dpi=300, bbox_inches="tight")
        print(f"Saved time series: \x1b[35m{filename}\x1b[0m")
        plt.close(fig)

if __name__ == "__main__":
    jdiag_files = sys.argv[1:]
    if not jdiag_files:
        print("Error: No JDIAG files provided. Usage: python timeseries.py <jdiag_file1> ...")
        sys.exit(1)
    plot_time_series(jdiag_files)
