#!/usr/bin/env python
import sys
import numpy as np
import xarray as xr
import os
import warnings

# Suppress unnecessary warnings
warnings.filterwarnings("ignore", category=RuntimeWarning)

def sanity_check(jdiag_file):
    """Sanity check: Compute Bias (mean O-B) and RMS for a single jdiag file."""
    try:
        ds_ombg = xr.open_dataset(jdiag_file, group="ombg")  # Open "ombg" group
        ds_obserr = xr.open_dataset(jdiag_file, group="EffectiveError0")  # Open the ObsError group

        obs_var = list(ds_ombg.data_vars.keys())[0]  # Extract variable name (e.g., airTemperature)
        if obs_var not in ds_ombg.variables:
            print(f"? Warning: {obs_var} not found in {jdiag_file}")
            return

        ombg = ds_ombg[obs_var].values   # Get O-B values
        obserr = ds_obserr[obs_var].values  # Get observation error values

        # Apply valid data filtering (ignore fill values)
        fill_value = ds_ombg[obs_var].attrs.get('_FillValue', np.nan)
        valid_mask = (ombg != fill_value) & (~np.isnan(obserr)) & (obserr < 1e+10)
        ombg = ombg[valid_mask]  # Keep only assimilated observations

        # Compute statistics
        if ombg.size == 0 or np.isnan(ombg).all():
            print(f"? Warning: No valid data found in {jdiag_file}")
            bias, rms, bias_corrected_rms = np.nan, np.nan, np.nan
        else:
            bias = np.nanmean(ombg)  # Mean O-B
            rms = np.sqrt(np.nanmean(ombg ** 2))  # RMS
            bias_corrected_rms = np.sqrt(np.nanmean((ombg - bias) ** 2))  # BCRMS

        ds_ombg.close()  # Free memory
        ds_obserr.close()  # Free memory

        # Print results
        print(f"?? File: {os.path.basename(jdiag_file)}")
        print(f"?? Observation Type: {obs_var}")
        print(f"?? Bias (Mean O-B): {bias:.5f}")
        print(f"?? RMS: {rms:.5f}")
        print(f"?? BCRMS: {bias_corrected_rms:.5f}\n")

    except FileNotFoundError:
        print(f"? Error: File not found - {jdiag_file}")
    except Exception as e:
        print(f"? Error processing {jdiag_file}: {e}")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python sanity_check.py <jdiag_file>")
        sys.exit(1)

    jdiag_file = sys.argv[1]
    sanity_check(jdiag_file)

