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

# Define pressure bins for vertical levels (19 bins, 20 boundaries)
pressure_bins = np.logspace(np.log10(180), np.log10(1100), num=20)

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
            #valid_mask = (ombg != fill_value) & (ombg < 1e+5) & (~np.isnan(obserr)) & (obserr < 1e+10) & (pressure > 0) & (pressure < 1100)
            #valid_mask = (effqc <= 1)
            valid_mask = get_valid_mask(effqc)
            pressure_valid = pressure[valid_mask]
            ombg_valid = ombg[valid_mask]
            oman_valid = oman[valid_mask]

            if ombg_valid.size == 0:
                print(f"{red}? No valid data for {obs_var} in {file}, skipping variable.{normal}")
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

            # Binned statistics
            binned_stats = []
            for i in range(len(pressure_bins) - 1):
                bin_mask = (pressure_valid >= pressure_bins[i]) & (pressure_valid < pressure_bins[i + 1])
                ombg_bin = ombg_valid[bin_mask]
                oman_bin = oman_valid[bin_mask]
                if ombg_bin.size > 0:
                    bias_ombg_bin = np.nanmean(ombg_bin * scale_factor)
                    rms_ombg_bin = np.sqrt(np.nanmean((ombg_bin * scale_factor) ** 2))
                    bias_oman_bin = np.nanmean(oman_bin * scale_factor) if ds_oman else np.nan
                    rms_oman_bin = np.sqrt(np.nanmean((oman_bin * scale_factor) ** 2)) if ds_oman else np.nan
                    fitting_ratio_bin = (rms_ombg_bin - rms_oman_bin) / rms_ombg_bin if rms_ombg_bin > 0 and ds_oman else np.nan
                    count_bin = len(ombg_bin)
                else:
                    bias_ombg_bin = rms_ombg_bin = bias_oman_bin = rms_oman_bin = fitting_ratio_bin = np.nan
                    count_bin = 0
                binned_stats.append({
                    "bias_ombg": bias_ombg_bin,
                    "rms_ombg": rms_ombg_bin,
                    "bias_oman": bias_oman_bin,
                    "rms_oman": rms_oman_bin,
                    "fitting_ratio": fitting_ratio_bin,
                    "count": count_bin
                })

            stats[obs_var] = {
                "overall": {
                    "bias_ombg": bias_ombg,
                    "rms_ombg": rms_ombg,
                    "bias_oman": bias_oman,
                    "rms_oman": rms_oman,
                    "fitting_ratio": fitting_ratio,
                    "count": len(ombg_valid)
                },
                "binned": binned_stats
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
        print(f"{red}? Error processing {file}: {e}{normal}")
        return None

def collect_stats(jdiag_files):
    """
    Collect statistics for all files.
    Returns a dictionary with keys (obtype, obs_var) and values as lists of (timestamp, stats_dict).
    """
    all_data = {}
    for file in jdiag_files:
        result = compute_stats_per_time(file)
        if result:
            timestamp, obtype, stats = result
            for obs_var, stat_dict in stats.items():
                key = (obtype, obs_var)
                if key not in all_data:
                    all_data[key] = []
                all_data[key].append((timestamp, stat_dict))
    return all_data

def plot_time_series(stats_ctl, stats_exp, ctl_name, exp_name, date_range, user_bin=None):
    """
    Generate a single time series plot with three subplots for each common observation type and variable,
    comparing Control and Experiment.
    """
    if user_bin is None or user_bin == -1:
        bin_index = None
        bin_label = "Entire Profile"
    else:
        # Validate user-provided bin number
        if user_bin < 1 or user_bin > 19:
            print(f"Error: Bin must be between 1 and 19, got {user_bin}")
            sys.exit(1)
        # Convert to Python zero-based index
        bin_index = user_bin - 1
        bin_min = pressure_bins[bin_index]
        bin_max = pressure_bins[bin_index + 1]
        bin_label = f"Bin {user_bin}: {bin_min:.1f}-{bin_max:.1f} hPa"
    print(f"Plotting time series for {bin_label}")

    common_keys = set(stats_ctl.keys()) & set(stats_exp.keys())
    for key in common_keys:
        obtype, obs_var = key
        data_ctl = sorted(stats_ctl[key], key=lambda x: x[0])
        data_exp = sorted(stats_exp[key], key=lambda x: x[0])

        # Extract data based on bin selection
        if bin_index is None:
            # Entire profile
            timestamps_ctl = [x[0] for x in data_ctl]
            bias_ombg_ctl = [x[1]["overall"]["bias_ombg"] for x in data_ctl]
            rms_ombg_ctl = [x[1]["overall"]["rms_ombg"] for x in data_ctl]
            bias_oman_ctl = [x[1]["overall"]["bias_oman"] for x in data_ctl]
            rms_oman_ctl = [x[1]["overall"]["rms_oman"] for x in data_ctl]
            fitting_ratio_ctl = [x[1]["overall"]["fitting_ratio"] for x in data_ctl]

            timestamps_exp = [x[0] for x in data_exp]
            bias_ombg_exp = [x[1]["overall"]["bias_ombg"] for x in data_exp]
            rms_ombg_exp = [x[1]["overall"]["rms_ombg"] for x in data_exp]
            bias_oman_exp = [x[1]["overall"]["bias_oman"] for x in data_exp]
            rms_oman_exp = [x[1]["overall"]["rms_oman"] for x in data_exp]
            fitting_ratio_exp = [x[1]["overall"]["fitting_ratio"] for x in data_exp]
        else:
            # Specific bin
            timestamps_ctl = [x[0] for x in data_ctl]
            bias_ombg_ctl = [x[1]["binned"][bin_index]["bias_ombg"] for x in data_ctl]
            rms_ombg_ctl = [x[1]["binned"][bin_index]["rms_ombg"] for x in data_ctl]
            bias_oman_ctl = [x[1]["binned"][bin_index]["bias_oman"] for x in data_ctl]
            rms_oman_ctl = [x[1]["binned"][bin_index]["rms_oman"] for x in data_ctl]
            fitting_ratio_ctl = [x[1]["binned"][bin_index]["fitting_ratio"] for x in data_ctl]

            timestamps_exp = [x[0] for x in data_exp]
            bias_ombg_exp = [x[1]["binned"][bin_index]["bias_ombg"] for x in data_exp]
            rms_ombg_exp = [x[1]["binned"][bin_index]["rms_ombg"] for x in data_exp]
            bias_oman_exp = [x[1]["binned"][bin_index]["bias_oman"] for x in data_exp]
            rms_oman_exp = [x[1]["binned"][bin_index]["rms_oman"] for x in data_exp]
            fitting_ratio_exp = [x[1]["binned"][bin_index]["fitting_ratio"] for x in data_exp]

        # Create figure with three subplots
        fig, (ax0, ax1, ax2) = plt.subplots(3, 1, figsize=(10, 12), sharex=True)

        # Subplot 0: Bias (OMB and OMA)
        ax0.plot(timestamps_ctl, bias_ombg_ctl, marker='o', linestyle='-', color='g', label=f"{ctl_name} OMB Bias")
        ax0.plot(timestamps_exp, bias_ombg_exp, marker='o', linestyle='--', color='g', label=f"{exp_name} OMB Bias")
        ax0.plot(timestamps_ctl, bias_oman_ctl, marker='o', linestyle='-', color='b', label=f"{ctl_name} OMA Bias")
        ax0.plot(timestamps_exp, bias_oman_exp, marker='o', linestyle='--', color='b', label=f"{exp_name} OMA Bias")
        ax0.axhline(0, color='gray', linestyle='--')
        ax0.set_ylabel(f"Bias ({UNITS.get(obs_var, 'unknown')})")
        ax0.set_ylim(-1, 1)
        ax0.legend()
        ax0.grid(True)

        # Subplot 1: RMS (OMB and OMA)
        ax1.plot(timestamps_ctl, rms_ombg_ctl, marker='o', linestyle='-', color='r', label=f"{ctl_name} OMB RMS")
        ax1.plot(timestamps_exp, rms_ombg_exp, marker='o', linestyle='--', color='r', label=f"{exp_name} OMB RMS")
        ax1.plot(timestamps_ctl, rms_oman_ctl, marker='o', linestyle='-', color='orange', label=f"{ctl_name} OMA RMS")
        ax1.plot(timestamps_exp, rms_oman_exp, marker='o', linestyle='--', color='orange', label=f"{exp_name} OMA RMS")
        ax1.set_ylabel(f"RMS ({UNITS.get(obs_var, 'unknown')})")
        ax1.set_ylim(0, 3)
        ax1.legend()
        ax1.grid(True)

        # Subplot 2: Fitting Ratio
        ax2.plot(timestamps_ctl, fitting_ratio_ctl, marker='o', linestyle='-', color='purple', label=f"{ctl_name} Fitting Ratio")
        ax2.plot(timestamps_exp, fitting_ratio_exp, marker='o', linestyle='--', color='purple', label=f"{exp_name} Fitting Ratio")
        ax2.set_ylabel("Fitting Ratio")
        ax2.set_xlabel("Time")
        ax2.set_ylim(0, 1)
        ax2.legend()
        ax2.grid(True)

        # Format the shared x-axis
        ax2.xaxis.set_major_locator(mdates.AutoDateLocator())
        ax2.xaxis.set_major_formatter(mdates.DateFormatter('%Y-%m-%d %H:%M'))
        plt.setp(ax2.get_xticklabels(), rotation=45, ha='right')

        # Title and save
        fig.suptitle(f"Time Series for {obtype} - {obs_var} ({bin_label}) ({date_range})")
        filename = f"timeseries_{obtype}_{obs_var}_{exp_name}_vs_{ctl_name}" + ("" if bin_index is None else f"_bin{user_bin}") + ".png"
        fig.tight_layout(rect=[0, 0, 1, 0.95])
        fig.savefig(filename, dpi=300, bbox_inches="tight")
        print(f"Saved time series: {pink}{filename}{normal}")
        plt.close(fig)

### Main Execution

if __name__ == "__main__":
    if len(sys.argv) < 4:
        print("Usage: python diff_timeseries_rms_bias_fit.py [--bin N] ctl_name exp_name ctl_files -- exp_files")
        sys.exit(1)

    user_bin = None
    if sys.argv[1] == "--bin":
        if len(sys.argv) < 6:
            print("Usage: python diff_timeseries_rms_bias_fit.py [--bin N] ctl_name exp_name ctl_files -- exp_files")
            sys.exit(1)
        user_bin = int(sys.argv[2])
        sys.argv = [sys.argv[0]] + sys.argv[3:]
    else:
        user_bin = None

    ctl_name = sys.argv[1]
    exp_name = sys.argv[2]

    try:
        idx = sys.argv.index("--")
        ctl_files = sys.argv[3:idx]
        exp_files = sys.argv[idx+1:]
    except ValueError:
        print("Usage: python diff_timeseries_rms_bias_fit.py [--bin N] ctl_name exp_name ctl_files -- exp_files")
        sys.exit(1)

    if not ctl_files or not exp_files:
        print("Error: No JDIAG files provided for control or experiment.")
        sys.exit(1)

    # Extract date range from control files
    date_range = extract_date_range(ctl_files)

    # Collect statistics for both experiments
    stats_ctl = collect_stats(ctl_files)
    stats_exp = collect_stats(exp_files)

    # Plot the time series
    plot_time_series(stats_ctl, stats_exp, ctl_name, exp_name, date_range, user_bin)
