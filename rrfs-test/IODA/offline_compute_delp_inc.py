#!/usr/bin/env python3
# offline_compute_delp_inc.py
#
# Create/overwrite delp increment in an FV3 core increment file from ps increment:
#   delp_inc(k,...) = (bk(k+1) - bk(k)) * ps_inc(...)
#
# For your files:
#   ps  in inc_jedi.sfc_data.nc : ps(Time,yaxis_1,xaxis_1) [Pa]
#   bk  in fv3_akbk             : bk(Time,66)
#   delp in inc_jedi.fv_core.res.nc will be created using the dimensions of T:
#        delp(Time,zaxis_1,yaxis_2,xaxis_1)  (float, like other core vars)
#
# Requirements: netCDF4, numpy

import argparse
import sys

import numpy as np
from netCDF4 import Dataset


def read_bk(akbk_path: str, bk_var: str) -> np.ndarray:
    with Dataset(akbk_path, "r") as ds:
        if bk_var not in ds.variables:
            raise KeyError(f"Missing '{bk_var}' in {akbk_path}. Vars: {list(ds.variables.keys())}")
        bk = np.asarray(ds.variables[bk_var][...])

    # Expect (Time,66) or (66,)
    if bk.ndim == 2:
        bk = bk[0, :]

    if bk.ndim != 1:
        raise ValueError(f"Unexpected bk shape {bk.shape}, expected (66,) or (Time,66).")

    return bk


def main() -> int:
    ap = argparse.ArgumentParser(description="Create/overwrite delp increment in FV3 core inc from ps inc.")
    ap.add_argument("--sfc_inc", required=True, help="inc_jedi.sfc_data.nc (contains ps increment).")
    ap.add_argument("--core_inc", required=True, help="inc_jedi.fv_core.res.nc (target for delp).")
    ap.add_argument("--akbk", required=True, help="fv3_akbk file (contains bk).")

    ap.add_argument("--ps_var", default="ps", help="ps variable name in sfc_inc (default ps).")
    ap.add_argument("--bk_var", default="bk", help="bk variable name in akbk (default bk).")
    ap.add_argument("--delp_var", default="delp", help="delp variable name to create in core (default delp).")

    # Use an existing core variable to determine the correct DELP dimensions.
    ap.add_argument("--core_template_var", default="T", help="Core variable whose dimensions will be used for delp (default T).")

    ap.add_argument("--scale", type=float, default=1.0, help="Optional multiplier applied to delp_inc.")
    ap.add_argument("--dry_run", action="store_true", help="Compute and report stats, do not write.")
    args = ap.parse_args()

    # Print immediately so the start is visible in redirected batch logs.
    print("Starting DELP increment computation.", flush=True)
    print(f"Surface increment: {args.sfc_inc}", flush=True)
    print(f"Core increment: {args.core_inc}", flush=True)
    print(f"AK/BK file: {args.akbk}", flush=True)
    print(f"Output variable: {args.delp_var}", flush=True)
    print(f"Core template variable: {args.core_template_var}", flush=True)
    print(f"Scale: {args.scale}", flush=True)
    print(f"Dry run: {args.dry_run}", flush=True)

    # Read ps increment
    with Dataset(args.sfc_inc, "r") as sfc:
        if args.ps_var not in sfc.variables:
            raise KeyError(f"Missing '{args.ps_var}' in {args.sfc_inc}. Vars: {list(sfc.variables.keys())}")

        ps_variable = sfc.variables[args.ps_var]
        ps_source_dims = ps_variable.dimensions
        ps = np.asarray(ps_variable[...])  # Expect (Time,252,420) or (252,420)
        ps_units = getattr(ps_variable, "units", "")

    if ps.ndim == 2:
        ps = ps[None, :, :]

    if ps.ndim != 3:
        raise ValueError(f"Unexpected ps shape {ps.shape}, expected (Time,ny,nx) or (ny,nx).")

    print(f"Read surface pressure increment: variable={args.ps_var} source_dims={ps_source_dims} working_shape={ps.shape} units={ps_units}", flush=True)

    # Read bk and form dbk
    bk = read_bk(args.akbk, args.bk_var)

    if bk.size != 66:
        raise ValueError(f"bk length is {bk.size}, expected 66 (interfaces for 65 levels).")

    dbk = bk[1:] - bk[:-1]  # (65,)

    print(f"Read hybrid coefficients: variable={args.bk_var} bk_length={bk.size} dbk_length={dbk.size}", flush=True)

    # Open core, determine its dimensions, and create/overwrite delp.
    mode = "r" if args.dry_run else "r+"

    with Dataset(args.core_inc, mode) as core:
        # DELP must use the same grid dimensions as an existing core variable.
        if args.core_template_var not in core.variables:
            raise KeyError(f"Core template variable '{args.core_template_var}' is missing from {args.core_inc}. Vars: {list(core.variables.keys())}")

        template = core.variables[args.core_template_var]
        delp_dims = template.dimensions

        if len(delp_dims) != 4:
            raise ValueError(f"Core template variable '{args.core_template_var}' has dimensions {delp_dims}, expected four dimensions ordered as (Time, vertical, y, x).")

        time_dim, z_dim, core_y_dim, x_dim = delp_dims

        # Check the expected dimension order before using it for DELP.
        if time_dim != "Time":
            raise ValueError(f"Unexpected time dimension '{time_dim}' in {delp_dims}; expected 'Time'.")

        if z_dim != "zaxis_1":
            raise ValueError(f"Unexpected vertical dimension '{z_dim}' in {delp_dims}; expected 'zaxis_1'.")

        if x_dim != "xaxis_1":
            raise ValueError(f"Unexpected x dimension '{x_dim}' in {delp_dims}; expected 'xaxis_1'.")

        nt = len(core.dimensions[time_dim])
        nz = len(core.dimensions[z_dim])
        ny = len(core.dimensions[core_y_dim])
        nx = len(core.dimensions[x_dim])

        print(f"Core template dimensions: variable={args.core_template_var} dims={delp_dims} shape=({nt},{nz},{ny},{nx})", flush=True)

        if nz != 65:
            raise ValueError(f"Core {z_dim} is {nz}, expected 65.")

        if ps.shape[0] != nt and nt != 0:
            # Time may be unlimited, so a current length of zero is acceptable.
            raise ValueError(f"ps time length {ps.shape[0]} does not match core Time length {nt}.")

        # Dimension names can differ between files, but their lengths must match.
        if ps.shape[1] != ny or ps.shape[2] != nx:
            raise ValueError(f"ps shape {ps.shape} does not match core y/x dimensions ({core_y_dim}={ny}, {x_dim}={nx}).")

        print(f"Dimension check passed: surface_y={ps.shape[1]} core_{core_y_dim}={ny} surface_x={ps.shape[2]} core_{x_dim}={nx}", flush=True)

        # Insert the vertical dimension between Time and the horizontal dimensions.
        delp_inc = (dbk[None, :, None, None] * ps[:, None, :, :]) * float(args.scale)

        print(f"DELP increment shape: {delp_inc.shape}", flush=True)
        print(f"DELP increment stats: min={float(np.nanmin(delp_inc)):.6g} max={float(np.nanmax(delp_inc)):.6g} mean={float(np.nanmean(delp_inc)):.6g}", flush=True)

        if args.dry_run:
            print("DRY RUN SUCCESS: DELP was computed and checked, but no file was changed.", flush=True)
            return 0

        # Create or overwrite the DELP variable using the core dimensions.
        if args.delp_var in core.variables:
            v = core.variables[args.delp_var]

            if v.dimensions != delp_dims:
                raise ValueError(f"Existing {args.delp_var} dimensions are {v.dimensions}, expected {delp_dims}.")

            action = "Overwrote"
        else:
            v = core.createVariable(args.delp_var, "f4", delp_dims)
            v.long_name = "air_pressure_thickness"
            v.units = "Pa"
            action = "Created"

        v[:, :, :, :] = delp_inc.astype(np.float32, copy=False)

        # Flush the NetCDF buffers before reporting completion.
        core.sync()

        print(f"{action} {args.core_inc}:{args.delp_var} with dimensions {delp_dims}.", flush=True)

    # Reaching this point means the file was also closed without an error.
    print("SUCCESS: DELP increment was computed and written successfully.", flush=True)

    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr, flush=True)
        sys.exit(2)
