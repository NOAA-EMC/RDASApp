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

def extract_timestamp(file):
    """Extract the timestamp from a jdiag file path."""
    match = re.search(r"/(\d{8})/rrfs_jedivar_(\d{2})_", file)
    if match:
        date, hour = match.groups()
        return datetime.datetime.strptime(date + hour, "%Y%m%d%H")
    print(f"? Warning: Could not extract timestamp from {file}")
    return None

def compute_binned_stats_per_time(file):
    """Compute binned statistics for a single file (single time step)."""
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

        pressure = ds_meta["pressure"].values / 100.0  # Pa to hPa
        stats = {}
        pressure_bins = np.logspace(np.log10(180), np.log10(1100), num=20)

        for obs_var in ds_ombg.data_vars:
            if obs_var not in ds_ombg.variables:
                continue

            ombg = ds_ombg[obs_var].values
            obserr = ds_obserr[obs_var].values if obs_var in ds_obserr.data_vars else np.full_like(ombg, np.nan)
            effqc = ds_effqc[obs_var].values if obs_var in ds_effqc.data_vars else np.full_like(ombg, np.nan)
            oman = ds_oman[obs_var].values if ds_oman and obs_var in ds_oman.data_vars else np.full_like(ombg, np.nan)

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

            binned_bias_ombg = np.full(len(pressure_bins) - 1, np.nan)
            binned_rms_ombg = np.full(len(pressure_bins) - 1, np.nan)
            binned_bias_oman = np.full(len(pressure_bins) - 1, np.nan)
            binned_rms_oman = np.full(len(pressure_bins) - 1, np.nan)
            binned_counts = np.zeros(len(pressure_bins) - 1, dtype=int)

            for i in range(len(pressure_bins) - 1):
                mask = (pressure_valid >= pressure_bins[i]) & (pressure_valid < pressure_bins[i + 1])
                if np.any(mask):
                    binned_bias_ombg[i] = np.nanmean(ombg_valid[mask])
                    binned_rms_ombg[i] = np.sqrt(np.nanmean(ombg_valid[mask] ** 2))
                    binned_bias_oman[i] = np.nanmean(oman_valid[mask])
                    binned_rms_oman[i] = np.sqrt(np.nanmean(oman_valid[mask] ** 2))
                    binned_counts[i] = np.sum(mask)

            fitting_ratio = np.where(binned_rms_ombg > 0, (binned_rms_ombg - binned_rms_oman) / binned_rms_ombg, np.nan)

            stats[obs_var] = {
                "bias_ombg": binned_bias_ombg,
                "rms_ombg": binned_rms_ombg,
                "bias_oman": binned_bias_oman,
                "rms_oman": binned_rms_oman,
                "fitting_ratio": fitting_ratio,
                "counts": binned_counts
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

def plot_hovmoller(jdiag_files):
    """Generate Hovmoller diagrams for each (obtype, obs_var) pair and each statistic."""
    all_data = {}
    unique_timestamps = set()

    # Collect data from all files
    for file in jdiag_files:
        result = compute_binned_stats_per_time(file)
        if result:
            timestamp, obtype, stats = result
            unique_timestamps.add(timestamp)
            for obs_var, stat_dict in stats.items():
                key = (obtype, obs_var)
                if key not in all_data:
                    all_data[key] = []
                all_data[key].append((timestamp, stat_dict))

    if not unique_timestamps:
        print("Error: No valid timestamps extracted from files.")
        sys.exit(1)

    sorted_timestamps = sorted(unique_timestamps)
    n_times = len(sorted_timestamps)
    pressure_bins = np.logspace(np.log10(180), np.log10(1100), num=20)
    n_pressure_bins = len(pressure_bins) - 1

    # Process and plot for each (obtype, obs_var)
    for key, data_list in all_data.items():
        obtype, obs_var = key

        # Initialize 2D arrays for each statistic
        bias_ombg_2d = np.full((n_pressure_bins, n_times), np.nan)
        rms_ombg_2d = np.full((n_pressure_bins, n_times), np.nan)
        bias_oman_2d = np.full((n_pressure_bins, n_times), np.nan)
        rms_oman_2d = np.full((n_pressure_bins, n_times), np.nan)
        fitting_ratio_2d = np.full((n_pressure_bins, n_times), np.nan)

        time_to_index = {t: i for i, t in enumerate(sorted_timestamps)}

        # Fill the 2D arrays with data
        for timestamp, stat_dict in data_list:
            idx = time_to_index[timestamp]
            bias_ombg_2d[:, idx] = stat_dict["bias_ombg"]
            rms_ombg_2d[:, idx] = stat_dict["rms_ombg"]
            bias_oman_2d[:, idx] = stat_dict["bias_oman"]
            rms_oman_2d[:, idx] = stat_dict["rms_oman"]
            fitting_ratio_2d[:, idx] = stat_dict["fitting_ratio"]

        # Define the statistics to plot with their settings
        statistics = {
            'bias_ombg': (bias_ombg_2d, 'OMB Bias', 'RdBu_r', -1, 1),
            'rms_ombg': (rms_ombg_2d, 'OMB RMS', 'turbo', 0, 3),
            'bias_oman': (bias_oman_2d, 'OMA Bias', 'RdBu_r', -1, 1),
            'rms_oman': (rms_oman_2d, 'OMA RMS', 'turbo', 0, 3),
            'fitting_ratio': (fitting_ratio_2d, 'Fitting Ratio', 'nipy_spectral', 0, 1)
        }

        # Compute time edges for pcolormesh
        if n_times > 1:
            time_diffs = [(sorted_timestamps[i+1] - sorted_timestamps[i]) for i in range(n_times - 1)]
            time_edges = [sorted_timestamps[0] - time_diffs[0] / 2]
            for i in range(1, n_times):
                time_edges.append(sorted_timestamps[i-1] + (sorted_timestamps[i] - sorted_timestamps[i-1]) / 2)
            time_edges.append(sorted_timestamps[-1] + time_diffs[-1] / 2)
        else:
            # Handle single time step
            time_edges = [sorted_timestamps[0] - datetime.timedelta(hours=3),
                          sorted_timestamps[0] + datetime.timedelta(hours=3)]

        for stat_name, (data_2d, label, cmap, vmin, vmax) in statistics.items():
            if np.all(np.isnan(data_2d)):
                print(f"? Skipping {stat_name} for {obtype}_{obs_var}: No data available.")
                continue

            fig, ax = plt.subplots(figsize=(12, 6))
            X, Y = np.meshgrid(time_edges, pressure_bins)
            c = ax.pcolormesh(X, Y, data_2d, cmap=cmap, vmin=vmin, vmax=vmax, shading='auto')

            ax.invert_yaxis()
            ax.set_yscale('log')
            ax.set_ylabel("Pressure (hPa)")
            ax.set_xlabel("Time")
            ax.set_yticks([200, 300, 400, 500, 600, 700, 800, 900, 1000])
            ax.get_yaxis().set_major_formatter(mticker.FuncFormatter(lambda x, _: f"{int(x)}"))
            ax.xaxis.set_major_locator(mdates.AutoDateLocator())
            ax.xaxis.set_major_formatter(mdates.DateFormatter('%Y-%m-%d %H:%M'))
            plt.xticks(rotation=45, ha='right')
            plt.colorbar(c, label=f"{label} ({UNITS.get(obs_var, 'unknown')})")

            title = f"Hovmoller Diagram for {obtype} - {obs_var} {label}"
            plt.title(title)
            filename = f"hovmoller_{obtype}_{obs_var}_{stat_name}.png"
            plt.savefig(filename, dpi=300, bbox_inches="tight")
            print(f"Saved Hovmoller: {pink}{filename}{normal}")
            plt.close()

if __name__ == "__main__":
    jdiag_files = sys.argv[1:]
    if not jdiag_files:
        print("Error: No JDIAG files provided. Usage: python hovmoller.py <jdiag_file1> ...")
        sys.exit(1)
    plot_hovmoller(jdiag_files)
