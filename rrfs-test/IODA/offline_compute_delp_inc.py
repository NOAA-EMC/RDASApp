#!/usr/bin/env python3
# offline_compute_delp_inc.py
#
# Create/overwrite delp increment in an FV3 core increment file from ps increment:
#   delp_inc(k,...) = (bk(k+1) - bk(k)) * ps_inc(...)
#
# For your files:
#   ps  in inc_jedi.sfc_data.nc : ps(Time,yaxis_1,xaxis_1) [Pa]
#   bk  in fv3_akbk             : bk(Time,66)
#   delp in inc_jedi.fv_core.res.nc will be created as:
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

    ap.add_argument("--scale", type=float, default=1.0, help="Optional multiplier applied to delp_inc.")
    ap.add_argument("--dry_run", action="store_true", help="Compute and report stats, do not write.")
    args = ap.parse_args()

    # Read ps increment
    with Dataset(args.sfc_inc, "r") as sfc:
        if args.ps_var not in sfc.variables:
            raise KeyError(f"Missing '{args.ps_var}' in {args.sfc_inc}. Vars: {list(sfc.variables.keys())}")
        ps = np.asarray(sfc.variables[args.ps_var][...])  # expect (Time,252,420) or (252,420)
        ps_units = getattr(sfc.variables[args.ps_var], "units", "")
    if ps.ndim == 2:
        ps = ps[None, :, :]
    if ps.ndim != 3:
        raise ValueError(f"Unexpected ps shape {ps.shape}, expected (Time,ny,nx) or (ny,nx).")

    # Read bk and form dbk
    bk = read_bk(args.akbk, args.bk_var)
    if bk.size != 66:
        raise ValueError(f"bk length is {bk.size}, expected 66 (interfaces for 65 levels).")
    dbk = bk[1:] - bk[:-1]  # (65,)

    # Open core, check dims, create/overwrite delp
    mode = "r" if args.dry_run else "r+"
    with Dataset(args.core_inc, mode) as core:
        # Confirm required dims exist and match expectations
        for d in ("Time", "zaxis_1", "yaxis_2", "xaxis_1"):
            if d not in core.dimensions:
                raise KeyError(f"Core file missing dimension '{d}'. Dims: {list(core.dimensions.keys())}")

        nt = len(core.dimensions["Time"])
        nz = len(core.dimensions["zaxis_1"])
        ny = len(core.dimensions["yaxis_2"])
        nx = len(core.dimensions["xaxis_1"])

        if nz != 65:
            raise ValueError(f"Core zaxis_1 is {nz}, expected 65.")
        if ps.shape[0] != nt and nt != 0:
            # Time is UNLIMITED; len() can be 1 in your file. Accept if ps time matches.
            raise ValueError(f"ps time len {ps.shape[0]} does not match core Time len {nt}.")
        if ps.shape[1] != ny or ps.shape[2] != nx:
            raise ValueError(f"ps shape {ps.shape} does not match core y/x ({ny},{nx}).")

        delp_inc = (dbk[None, :, None, None] * ps[:, None, :, :]) * float(args.scale)  # (Time,65,ny,nx)

        # stats
        print(f"ps:   {args.sfc_inc}:{args.ps_var} shape={ps.shape} units={ps_units}")
        print(f"bk:   {args.akbk}:{args.bk_var} len={bk.size} -> dbk len={dbk.size}")
        print(f"core: {args.core_inc} expects delp dims (Time,zaxis_1,yaxis_2,xaxis_1)=({ps.shape[0]},{nz},{ny},{nx})")
        print(f"delp_inc stats: min={float(np.nanmin(delp_inc)):.6g} "
              f"max={float(np.nanmax(delp_inc)):.6g} mean={float(np.nanmean(delp_inc)):.6g}")

        if args.dry_run:
            return 0

        # Create or overwrite variable
        if args.delp_var in core.variables:
            v = core.variables[args.delp_var]
            # Must match dims
            if v.dimensions != ("Time", "zaxis_1", "yaxis_2", "xaxis_1"):
                raise ValueError(f"Existing {args.delp_var} dims are {v.dimensions}, expected "
                                 f"('Time','zaxis_1','yaxis_2','xaxis_1').")
        else:
            # match file's float usage (your core vars are float)
            v = core.createVariable(args.delp_var, "f4", ("Time", "zaxis_1", "yaxis_2", "xaxis_1"))
            v.long_name = "air_pressure_thickness"
            v.units = "Pa"

        v[:, :, :, :] = delp_inc.astype(np.float32, copy=False)

    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(2)

