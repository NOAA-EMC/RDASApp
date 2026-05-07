#!/usr/bin/env python3
# offline_rsig.py
#
# Build a GSI-style rsig.txt file from FV3 dynamic-core pressure thickness data.
#
# Main purpose:
#   Estimate the average model pressure level coordinate used by the offline
#   sonde_ext preprocessing script.
#
# What this script does:
#   1. Opens one or more FV3 dynvars files.
#   2. Reads delp, the layer pressure thickness in Pa.
#   3. Reconstructs pressure at layer interfaces from model top downward.
#   4. Computes pressure at layer centers.
#   5. Horizontally averages those layer-center pressures across all grid points
#      and all input files.
#   6. Divides the average layer pressure by average surface pressure to produce
#      rsig values.
#   7. Writes those values in bottom-to-top order for use by sonde_ext-like logic.
#
# Practical note:
#   The output rsig values are not taken from a static vertical-coordinate file.
#   They are estimated from the actual delp fields, so they represent an average
#   pressure structure for the input cycle/files.

import glob
import numpy as np
from netCDF4 import Dataset

# Fallback model-top pressure in Pa.
# 200 Pa = 2 mb. This is used only if the input file does not provide ptop.
PTOP_PA_DEFAULT = 200.0  # 2 mb


def get_ptop_pa(nc):
    # Try common variable names that may contain the model-top pressure.
    # Some files store ptop as a scalar variable. Others expose hybrid
    # coordinate coefficients where ak[0] is effectively the model-top pressure.
    for name in ("ptop", "p_top", "PTOP", "ak"):
        if name in nc.variables:
            arr = np.asarray(nc.variables[name][:], dtype=np.float64)
            if arr.size == 1:
                return float(arr)
            if name == "ak" and arr.size > 0:
                return float(arr.flat[0])

    # If ptop was not found as a variable, try common global attribute names.
    for name in ("ptop", "p_top", "PTOP"):
        if name in nc.ncattrs():
            return float(nc.getncattr(name))

    # Last resort: use the FV3/RRFS-style default specified above.
    return PTOP_PA_DEFAULT


# Find the FV3 dynvars file(s) to process.
# As written, this matches a file named exactly "fv3_dynvars".
# If files have suffixes or cycle-specific names, this glob may need widening.
core_files = sorted(glob.glob("fv3_dynvars"))
if not core_files:
    raise SystemExit("No fv3_dynvars files found")

# Accumulators used to average over all files and all horizontal grid points.
sum_ps = 0.0
sum_prsl = None
npts_total = 0

# Reference values used to make sure all files have compatible vertical grids.
nsig_ref = None
ptop_ref = None

# Process delp in horizontal chunks instead of reading the full 3D field and
# constructing full-domain interface-pressure arrays.
#
# This matters for large domains such as the North American 3 km grid. The rsig
# calculation only needs domain-mean quantities:
#
#   1. sum of surface pressure over all horizontal points
#   2. sum of layer-center pressure for each vertical level
#   3. total number of horizontal points
#
# Therefore, there is no need to keep full-domain pint or prsl arrays in memory.
Y_CHUNK = 64

for fn in core_files:
    with Dataset(fn) as nc:
        # delp is required because it gives pressure thickness for each model
        # layer. Without it, we cannot reconstruct interface or midlayer pressure.
        if "delp" not in nc.variables:
            raise SystemExit(f"{fn} is missing variable delp")

        # Read model-top pressure and require it to match across all files.
        ptop_pa = get_ptop_pa(nc)
        if ptop_ref is None:
            ptop_ref = ptop_pa
        elif abs(ptop_pa - ptop_ref) > 1.0e-6:
            raise SystemExit(f"ptop mismatch: {fn} has {ptop_pa}, expected {ptop_ref}")

        # Keep a handle to the NetCDF variable so we can read one horizontal
        # slab at a time instead of loading the full 3D field.
        delp_var = nc.variables["delp"]

        # Expected shape:
        #   delp(time, k, y, x), units Pa
        if len(delp_var.shape) != 4:
            raise SystemExit(f"{fn} delp has unexpected shape {delp_var.shape}")

        _, nsig, ny, nx = delp_var.shape

        # All files must have the same number of vertical levels so they can be
        # averaged level by level.
        if nsig_ref is None:
            nsig_ref = nsig
        elif nsig != nsig_ref:
            raise SystemExit(f"nsig mismatch: {fn} has {nsig}, expected {nsig_ref}")

        # Loop over y slabs. Smaller chunks reduce peak memory, which is the main
        # concern for larger domains.
        for y0 in range(0, ny, Y_CHUNK):
            y1 = min(y0 + Y_CHUNK, ny)

            # Read only this horizontal slab from the first time record.
            #
            # Shape:
            #   delp(k, y_chunk, x)
            delp = delp_var[0, :, y0:y1, :].astype(np.float64)

            # Pressure thickness must be positive. Non-positive values would
            # break the cumulative pressure reconstruction and indicate a bad
            # input file.
            if np.any(delp <= 0.0):
                raise SystemExit(f"{fn} contains non-positive delp values")

            # p_lower starts as the pressure at the bottom of each model layer:
            #
            #   p_lower[0] = ptop + delp[0]
            #   p_lower[1] = ptop + delp[0] + delp[1]
            #   ...
            #
            # This is one of the only large temporary arrays needed.
            p_lower = ptop_pa + np.cumsum(delp, axis=0)

            # Surface pressure is the bottom interface of the lowest model layer.
            # Capture this before modifying p_lower below.
            ps = p_lower[-1, :, :]

            npts = ps.size
            sum_ps += ps.sum()
            npts_total += npts

            # Convert p_lower in-place from bottom-interface pressure to
            # layer-center pressure.
            #
            # Since:
            #   p_upper = p_lower - delp
            #
            # layer center is:
            #   prsl = 0.5 * (p_upper + p_lower)
            #        = p_lower - 0.5 * delp
            #
            # Doing this in-place avoids allocating separate p_upper and prsl
            # arrays.
            p_lower -= 0.5 * delp

            # Sum layer-center pressure over this slab's horizontal dimensions.
            # This keeps one accumulated value per vertical level.
            if sum_prsl is None:
                sum_prsl = p_lower.sum(axis=(1, 2))
            else:
                sum_prsl += p_lower.sum(axis=(1, 2))

# Average surface pressure across all files and horizontal grid points.
psfcavg = sum_ps / npts_total

# Average layer-center pressure for each vertical level across all files and
# horizontal grid points.
prslavg = sum_prsl / npts_total

# FV3 delp is usually top-to-bottom. GSI sonde_ext expects bottom-to-top.
# Reversing makes index 0 the lowest/fullest pressure level and the last index
# the uppermost/smallest pressure level.
prslavg = prslavg[::-1]

# Convert average pressure levels to sigma-like ratios.
# A value near 1 is close to the surface. Smaller values are higher up.
rsig = prslavg / psfcavg

# After reversing to bottom-to-top order, rsig should decrease with index:
#   bottom level: larger rsig
#   top level:    smaller rsig
if not np.all(np.diff(rsig) < 0.0):
    raise SystemExit("rsig is not strictly decreasing; check vertical ordering of delp")

# Basic sanity check. The bottom value should be positive, and even the largest
# value should remain within a physically reasonable normalized-pressure range.
if np.any(rsig <= 0.0) or rsig[0] >= 1.5:
    raise SystemExit("rsig values look suspicious")

# Write rsig in a simple two-column format in the order expected by the offline
# sonde_ext script:
#   level_index rsig_value
#
# Important: this index is not FV3 native level numbering. FV3 level 1 is
# usually the model top. Here, index 1 is written as the bottom/near-surface
# target because the downstream sonde_ext-like logic expects bottom-to-top
# pressure ordering.
with open("rsig.txt", "w", encoding="ascii") as f:
    for k, val in enumerate(rsig, start=1):
        f.write(f"{k:3d} {val:.12e}\n")

# Print enough metadata to confirm the file count, number of vertical levels,
# model-top pressure, average surface pressure, and output path.
print(f"files={len(core_files)} nsig={len(rsig)} ptop={ptop_ref:.3f} Pa psfcavg={psfcavg:.3f} Pa wrote rsig.txt")

# Print the endpoints as a quick vertical-ordering sanity check.
print(f"Sanity: rsig first_written_bottom={rsig[0]:.6f}, last_written_top={rsig[-1]:.6f}")
