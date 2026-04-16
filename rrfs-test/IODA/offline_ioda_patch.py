#!/usr/bin/env python
import netCDF4 as nc
import numpy as np
from timeit import default_timer as timer
import argparse
import warnings

"""
This program makes a copy of an original IODA file and can add/modify additional
adhoc variables. This program was originally written to add the
MetaData/longitude_latitude_pressure for use in l_closeobs duplicate checking
but others can be added as necessary.
3/4/2025: change all QualityMarker with missing values to 15
"""

# Disable warnings
warnings.filterwarnings('ignore')

# Functions for calculating run times.


def tic():
    return timer()


def toc(tic=tic, label=""):
    toc = timer()
    elapsed = toc - tic
    hrs = int(elapsed // 3600)
    mins = int((elapsed % 3600) // 60)
    secs = int(elapsed % 3600 % 60)
    print(f"{label}({elapsed:.2f}s), {hrs:02}:{mins:02}:{secs:02}")


tic1 = tic()

parser = argparse.ArgumentParser()
parser.add_argument('-o', '--obs', type=str, help='ioda observation file', required=True)
parser.add_argument('--patch-timeoffset', action='store_true',
                    help='Patch MetaData/timeOffset for soundings (ObsType 120/220)')
parser.add_argument('--to-min', type=float, default=-5400.0)
parser.add_argument('--to-max', type=float, default=5400.0)
parser.add_argument('--to-set', type=float, default=3600.0,
                    help='Magnitude to set timeOffset to (sign preserved)')

args = parser.parse_args()

# Assign filenames
obs_filename = args.obs

obs_ds = nc.Dataset(obs_filename, 'r')

# Extract observation latitudes and longitudes
obs_lat = obs_ds.groups['MetaData'].variables['latitude'][:]
obs_lon = obs_ds.groups['MetaData'].variables['longitude'][:]
obs_lon = np.where(obs_lon < 0, obs_lon + 360, obs_lon)
obs_prs = obs_ds.groups['MetaData'].variables['pressure'][:]

# Create a new NetCDF file to store the selected data using the more efficient method
if '.nc' in obs_filename:
    outfile = obs_filename.replace('.nc', '_llp.nc')
else:
    outfile = obs_filename.replace('.nc4', '_llp.nc4')
fout = nc.Dataset(outfile, 'w')

# Create dimensions and variables in the new file
fout.createDimension('Location', len(obs_lat))
fout.createVariable('Location', 'int64', 'Location')
fout.variables['Location'][:] = 0
for attr in obs_ds.variables['Location'].ncattrs():  # Attributes for Location variable
    fout.variables['Location'].setncattr(attr, obs_ds.variables['Location'].getncattr(attr))

# Copy all non-grouped attributes into the new file
for attr in obs_ds.ncattrs():  # Attributes for the main file
    fout.setncattr(attr, obs_ds.getncattr(attr))

# Copy all groups and variables into the new file, keeping only the variables in range
groups = obs_ds.groups
for group in groups:
    if group == "QualityMarker":
        qc_group = True
    else:
        qc_group = False
    g = fout.createGroup(group)
    for var in obs_ds.groups[group].variables:
        invar = obs_ds.groups[group].variables[var]
        try:  # Non-string variables
            vartype = invar.dtype
            fill = invar.getncattr('_FillValue')
            g.createVariable(var, vartype, 'Location', fill_value=fill)
        except (AttributeError, KeyError):  # String variables
            g.createVariable(var, 'str', 'Location')

        if qc_group and vartype == "int32":
            np_invar = np.array(invar)
            np_invar[(np_invar < 0) | (np_invar > 15)] = 15
            g.variables[var][:] = np_invar.astype(invar.dtype)
        else:
            if var in ['latitude', 'longitude']:
                g.variables[var][:] = invar[:][:].data
            else:
                g.variables[var][:] = invar[:][:]

        # Copy attributes for this variable
        for attr in invar.ncattrs():
            if '_FillValue' in attr:
                continue
            g.variables[var].setncattr(attr, invar.getncattr(attr))

# Generate longitude_latitude_pressure location strings (for dup checking)
longitude_latitude_pressure = [f"{lon}_{lat}_{pres}" for lon, lat, pres in zip(obs_lon, obs_lat, obs_prs)]
longitude_latitude_pressure = np.array(longitude_latitude_pressure)

metadata_group = fout.groups['MetaData']

# Add the longitude_latitude_pressure variable to the file
var = "longitude_latitude_pressure"
data = longitude_latitude_pressure
if var not in metadata_group.variables:
    metadata_group.createVariable(f"{var}", 'str', 'Location')
metadata_group.variables[f"{var}"][:] = data

# Generate longitude_latitude location strings (for dup checking)
longitude_latitude = [f"{lon}_{lat}" for lon, lat in zip(obs_lon, obs_lat)]
longitude_latitude = np.array(longitude_latitude)

metadata_group = fout.groups['MetaData']

# Add the longitude_latitude variable to the file
var = "longitude_latitude"
data = longitude_latitude
if var not in metadata_group.variables:
    metadata_group.createVariable(f"{var}", 'str', 'Location')
metadata_group.variables[f"{var}"][:] = data

# Add the exp_err_norm to file (for goes-r amvs)
if 'expectedError' in metadata_group.variables:
    u = fout.groups['ObsValue'].variables['windEastward'][:]
    v = fout.groups['ObsValue'].variables['windNorthward'][:]
    speed = np.sqrt(u*u + v*v)
    ee = fout.groups['MetaData'].variables['expectedError'][:]
    experr_norm = (10.0 - 0.1 * ee) / speed
    var = "exp_err_norm"
    data = experr_norm.astype('f4')
    if var not in metadata_group.variables:
        metadata_group.createVariable(f"{var}", 'f4', 'Location', fill_value=fill)
    metadata_group.variables[f"{var}"][:] = data

# patch MetaData/timeOffset for soundings only (ObsType 120 or 220), hard-coded
if args.patch_timeoffset:
    md = fout.groups.get("MetaData", None)
    ot = fout.groups.get("ObsType", None)

    if md is None or ot is None:
        print("patch-timeoffset requested but MetaData or ObsType group missing; skipping")
    elif "timeOffset" not in md.variables:
        print("patch-timeoffset requested but MetaData/timeOffset missing; skipping")
    else:
        to_var = md.variables["timeOffset"]
        to = to_var[:].astype(np.float64)

        # Save original for debugging
        if "origTimeOffset" not in md.variables:
            md.createVariable("origTimeOffset", "f4", "Location", fill_value=np.float32(3.402823e38))
            md.variables["origTimeOffset"].long_name = "Original timeOffset before offline patch"
            md.variables["origTimeOffset"].units = getattr(to_var, "units", "s")
        md.variables["origTimeOffset"][:] = to.astype(np.float32)

        # Build sounding mask: true if ANY ObsType/* is 120 or 220 at that Location
        sounding = np.zeros(to.shape, dtype=bool)
        for vname in ot.variables:
            v = ot.variables[vname]
            if getattr(v, "dimensions", ()) != ("Location",):
                continue
            otv = v[:]

            # Exclude fill values if present
            try:
                fv = v.getncattr("_FillValue")
                good = (otv != fv)
            except Exception:
                good = np.ones(otv.shape, dtype=bool)

            sounding |= (good & ((otv == 120) | (otv == 220)))

        # Outside bounds?
        mask_lo = sounding & (to < float(args.to_min))
        mask_hi = sounding & (to > float(args.to_max))

        # Patch: preserve sign, set magnitude to to_set
        to[mask_lo] = -abs(float(args.to_set))
        to[mask_hi] =  abs(float(args.to_set))

        to_var[:] = to.astype(to_var.dtype)

        n_type = int(np.count_nonzero(np.ma.filled(sounding, False)))
        n_adj  = int(np.count_nonzero(np.ma.filled(mask_lo, False)) + np.count_nonzero(np.ma.filled(mask_hi, False)))

        print(f"Patched MetaData/timeOffset for soundings: matched={n_type}, adjusted={n_adj}")

# Close the datasets
obs_ds.close()
fout.close()
toc(tic1, label="Time to create new obs file: ")
