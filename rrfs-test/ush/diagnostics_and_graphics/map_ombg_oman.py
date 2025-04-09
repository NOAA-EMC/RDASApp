#!/usr/bin/env python
import sys
import numpy as np
import xarray as xr
import matplotlib.pyplot as plt
import cartopy.crs as ccrs
import cartopy.feature as cfeature
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

# Color ranges for different observation categories
COLOR_RANGES = {
    "Temperature": (-5, 5),
    "Humidity": (-5, 5),
    "Winds": (-5, 5),
    "Pressure": (-500, 500)
}

# Units for different observation categories
UNITS = {
    "Temperature": "K",
    "Humidity": "g/kg",
    "Winds": "m/s",
    "Pressure": "Pa"
}

# Mapping from core observation types to categories
CATEGORY_MAPPING = {
    "airTemperature": "Temperature",
    "specificHumidity": "Humidity",
    "windEastward": "Winds",
    "windNorthward": "Winds",
    "stationPressure": "Pressure",
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

def extract_info_from_path(file_path):
    """
    Extract date, cycle, and observation type from the file path and name.
    Tries to parse from path, falls back to filename or defaults if not found.
    """
    # Attempt to extract date and cycle from path
    match = re.search(r"/(\d{8})/.*jedivar_(\d{2})", file_path)
    if match:
        date, cycle = match.groups()
        cycle = f"{cycle}Z"
    else:
        # Fallback to filename or default
        filename = os.path.basename(file_path)
        date_match = re.search(r"(\d{8})", filename)
        date = date_match.group(1) if date_match else "Unknown"
        cycle = "Unknown"

    # Extract observation type from filename
    obtype_match = re.search(r"jdiag_(.+)\.nc4?$", os.path.basename(file_path))
    obtype = obtype_match.group(1) if obtype_match else "Unknown"
    return date, cycle, obtype

def get_core_obs_type(obs_type):
    """Extract the core observation variable name from the full type (e.g., adpsfc_airTemperature_181 -> airTemperature).
    If the core is 'winds', return 'windEastward'."""
    match = re.match(r".*?_(.*?)_\d+$", obs_type)
    if match:
        core = match.group(1)
        if core == "winds":
            return "windEastward"
        else:
            return core
    else:
        return obs_type

def process_and_plot_jdiag(file):
    """Process a single JDIAG file and generate a 2D map plot of OMBG values."""
    # Extract metadata
    date, cycle, obtype = extract_info_from_path(file)

    try:
        # Open the ombg and MetaData groups
        ds_ombg = xr.open_dataset(file, group="ombg")
        ds_oman = xr.open_dataset(file, group="oman")
        ds_meta = xr.open_dataset(file, group="MetaData")
        ds_obserr = xr.open_dataset(file, group="EffectiveError0")
        ds_effqc = xr.open_dataset(file, group="EffectiveQC2")

        # Extract the observation variable (assuming one variable per ombg group)
        obs_var = list(ds_ombg.data_vars.keys())[0]
        ombg = ds_ombg[obs_var].values
        oman = ds_oman[obs_var].values
        obserr = ds_obserr[obs_var].values
        effqc = ds_effqc[obs_var].values
        lats = ds_meta['latitude'].values
        lons = ds_meta['longitude'].values

        # Filter valid data
        fill_value = ds_ombg[obs_var].attrs.get('_FillValue', np.nan)
        #valid_mask = (ombg != fill_value) & (ombg < 1e+5) & (~np.isnan(ombg)) & (obserr < 1e+10)
        #valid_mask = (effqc <= 1)
        valid_mask = get_valid_mask(effqc)
        lats = lats[valid_mask]
        lons = lons[valid_mask]
        ombg = ombg[valid_mask]
        oman = oman[valid_mask]

        if ombg.size == 0:
            print(f"{red}? Warning: No valid data in {file}, skipping plot.{normal}")
            ds_ombg.close()
            ds_meta.close()
            return

        # Apply unit conversion if needed
        scale_factor = UNIT_CONVERSIONS.get(obs_var, 1.0)
        ombg *= scale_factor
        oman *= scale_factor

        # Compute bias and rms stats
        ombg_bias = np.nanmean(ombg)
        ombg_rms = np.sqrt(np.nanmean(ombg**2))
        oman_bias = np.nanmean(oman)
        oman_rms = np.sqrt(np.nanmean(oman**2))

        # Determine category, color range, and units
        core_obs = get_core_obs_type(obtype)
        category = CATEGORY_MAPPING.get(core_obs, "Unknown")
        vmin, vmax = COLOR_RANGES.get(category, (-5, 5))
        units = UNITS.get(category, "unknown")

        # Create figure with two subplots
        fig, axes = plt.subplots(2, 1, figsize=(12, 8), subplot_kw={'projection': ccrs.PlateCarree()})

        # Store scatter plots for later colorbar
        scatters = []

        # Loop through the subplots and plot data
        for ax, data, bias, rms, label in zip(axes, [ombg, oman], [ombg_bias, oman_bias], [ombg_rms, oman_rms], ["OMBG", "OMAN"]):
            # Add map features
            ax.add_feature(cfeature.COASTLINE)
            ax.add_feature(cfeature.BORDERS)
            ax.add_feature(cfeature.STATES)

            # Set the fixed extent for the contiguous USA
            ax.set_extent([-132.5, -65, 22, 53], crs=ccrs.PlateCarree())

            # Scatter plot of OMBG values
            sc = ax.scatter(lons, lats, c=data, cmap='coolwarm', vmin=vmin, vmax=vmax, s=1, transform=ccrs.PlateCarree())
            scatters.append(sc)

            # Set title with number of observations
            nobs = len(ombg)
            title = f"{label} for {obtype} on {date} {cycle} (nobs: {nobs})"
            ax.set_title(title)

            # Annotate RMS and bias in lower left corner
            ax.text(0.02, 0.04, f"Bias: {bias:.2f} {units}\nRMS: {rms:.2f} {units}",
            transform=ax.transAxes,  # relative to subplot
            fontsize=10, color='black',
            bbox=dict(facecolor='white', alpha=0.7, edgecolor='black'))

        cbar = plt.colorbar(scatters[0], ax=axes, orientation='vertical', pad=0.05)
        cbar.set_label(f'{units}')

        # Save the plot
        output_file = f"{date}_{cycle}_{obtype}_ombg_oman_map.png"
        plt.savefig(output_file, dpi=300, bbox_inches='tight')
        plt.close(fig)
        print(f"Saved plot: {pink}{output_file}{normal}")

        # Clean up
        ds_ombg.close()
        ds_meta.close()
        ds_obserr.close()
        ds_effqc.close()

    except Exception as e:
        print(f"{red}? Error processing {file}: {e}{normal}")

if __name__ == "__main__":
    # Get JDIAG files from command-line arguments
    jdiag_files = sys.argv[1:]

    if not jdiag_files:
        print("Error: No JDIAG files provided. Usage: python map_ombg.py <jdiag_file1> <jdiag_file2> ...")
        sys.exit(1)

    print(f"Processing {len(jdiag_files)} JDIAG files...")

    # Process each JDIAG file individually
    for file in jdiag_files:
        process_and_plot_jdiag(file)
