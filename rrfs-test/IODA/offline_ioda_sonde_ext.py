#!/usr/bin/env python3
# offline_ioda_sonde_ext.py
#
# Offline, IODA-space approximation of GSI sonde_ext.f90 for mass sonde obs.
#
# Main purpose:
#   Add synthetic sonde mass levels directly to an IODA ObsGroup file before JEDI.
#
# Practical notes:
#   1. This version only handles kx=120 mass variables:
#        - airTemperature
#        - specificHumidity
#      Winds are intentionally not extended here because the tested wind count was
#      already close to GSI without offline sonde_ext.
#   2. GSI sonde_ext works on compact per-report arrays. IODA profiles can be
#      denser, so this tool thins each station/release profile before applying
#      sonde_ext-like interpolation.
#   3. Temperature creation is strict: both endpoint T values must be valid and
#      both endpoint T quality markers must be good.
#   4. Humidity uses the same special acceptance rule used in the JEDI YAML:
#      type 120, pressure 1000-30000 Pa, and QM=9 is treated as accepted.
#
# Example:
#   ./offline_ioda_sonde_ext_mass.py \
#       -i ioda_adpupa.nc \
#       -r rsig.txt \
#       -o ioda_adpupa.sondeext.nc

import argparse
import math
from collections import defaultdict
from typing import Dict, List, Optional, Tuple

import numpy as np
from netCDF4 import Dataset


KX_MASS = 120
FLOAT_FILL_DEFAULT = np.float32(3.402823e38)
INT_FILL_DEFAULT = np.int32(2147483647)
INT64_FILL_DEFAULT = np.int64(-9223372036854775808)


# -----------------------------------------------------------------------------
# Basic helpers
# -----------------------------------------------------------------------------


def get_fill(var):
    # Return the NetCDF fill value used by this variable.
    # If the file does not define one, fall back to the same large
    # sentinel values commonly used in IODA-style files.
    if "_FillValue" in var.ncattrs():
        return var.getncattr("_FillValue")
    if np.issubdtype(var.dtype, np.floating):
        return FLOAT_FILL_DEFAULT
    if np.issubdtype(var.dtype, np.integer):
        return INT64_FILL_DEFAULT
    return None


def is_missing(val, fill) -> bool:
    # Treat a value as missing if it matches the file fill value, is NaN/Inf,
    # or is one of the very large floating-point sentinels used by IODA.
    if fill is None:
        return val is None
    if isinstance(val, (float, np.floating)):
        if not np.isfinite(val):
            return True
        return float(val) == float(fill) or float(val) > 1.0e20
    return val == fill


def clamp_qm(qm) -> int:
    # Normalize quality-marker values so later comparisons are safe.
    # Non-numeric or non-finite markers become a large bad value.
    try:
        if not np.isfinite(qm):
            return 9999
    except TypeError:
        return 9999
    return int(min(qm, 10000))


def values_good(arr: np.ndarray, fill, idx1: int, idx2: int) -> bool:
    # Synthetic obs are only created when both bracketing endpoint values exist.
    return (not is_missing(arr[idx1], fill)) and (not is_missing(arr[idx2], fill))


def qms_good(qmark: Dict[str, np.ndarray], var_name: str, idx1: int, idx2: int) -> bool:
    # For most variables, both endpoint quality markers must be conventionally
    # good, meaning less than 4.
    if var_name not in qmark:
        return False
    return clamp_qm(qmark[var_name][idx1]) < 4 and clamp_qm(qmark[var_name][idx2]) < 4


def interp(v1, v2, w1: float, w2: float):
    # Weighted interpolation between the lower-pressure and upper-pressure
    # endpoints. The weights are calculated in log-pressure space below.
    return v1 * w1 + v2 * w2


def log_cb_from_pa(p_pa: float) -> float:
    # GSI uses log(p_mb * 0.1), and p_mb = p_pa / 100.
    # Therefore log(p_mb * 0.1) = log(p_pa / 1000).
    return math.log(p_pa / 1000.0)


# -----------------------------------------------------------------------------
# rsig and IODA loading
# -----------------------------------------------------------------------------


def read_rsig(path: str) -> np.ndarray:
    # Read the model sigma-like pressure targets from rsig.txt.
    # The second column is used, matching the expected GSI-style file layout.
    vals = []
    with open(path, "r", encoding="ascii") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split()
            if len(parts) >= 2:
                vals.append(float(parts[1]))

    if not vals:
        raise RuntimeError(f"No rsig values read from {path}")

    rsig = np.array(vals, dtype=np.float64)
    if np.any(~np.isfinite(rsig)) or np.any(rsig <= 0.0):
        raise RuntimeError("rsig contains invalid values")

    # FV3-derived rsig is often written top-to-bottom. The logic below expects
    # bottom-to-top order, with pressure decreasing as index increases.
    if np.all(np.diff(rsig) > 0.0):
        print("WARNING: rsig is increasing top-to-bottom; reversing to GSI bottom-to-top order")
        rsig = rsig[::-1].copy()
    elif not np.all(np.diff(rsig) < 0.0):
        raise RuntimeError("rsig must be strictly monotonic")

    if rsig[0] <= 0.0 or rsig[-1] <= 0.0 or rsig[0] >= 1.5:
        raise RuntimeError("rsig values look suspicious; expected roughly 0 < rsig < 1")

    return rsig


def load_group_vars(nc: Dataset, group_name: str) -> Dict[str, np.ndarray]:
    # Pull every 1-D Location variable from a NetCDF group into memory.
    # Masked arrays are converted back to normal arrays using each variable fill.
    if group_name not in nc.groups:
        return {}

    out = {}
    for vname, var in nc.groups[group_name].variables.items():
        data = var[:]
        if isinstance(data, np.ma.MaskedArray):
            data = data.filled(get_fill(var))
        out[vname] = data
    return out


def require_meta(meta: Dict[str, np.ndarray], names: List[str]) -> None:
    # Fail early when a required metadata field is missing.
    for name in names:
        if name not in meta:
            raise RuntimeError(f"Missing required MetaData variable: {name}")


def station_strings(station_array: np.ndarray) -> np.ndarray:
    # Convert station IDs to regular Python strings so they can be used as
    # dictionary keys consistently, even when NetCDF stores them differently.
    return np.array([str(s) for s in station_array], dtype=object)


def build_station_release_profiles(meta: Dict[str, np.ndarray]) -> Dict[Tuple[str, int], np.ndarray]:
    # Group rows into sounding profiles. A profile is defined here as one
    # stationIdentification and one releaseTime.
    require_meta(meta, ["stationIdentification", "releaseTime"])

    sid = station_strings(meta["stationIdentification"])
    release = meta["releaseTime"].astype(np.int64)

    profiles: Dict[Tuple[str, int], List[int]] = {}
    for idx, (s, t) in enumerate(zip(sid, release)):
        profiles.setdefault((s, int(t)), []).append(idx)

    return {key: np.array(vals, dtype=np.int64) for key, vals in profiles.items()}


# -----------------------------------------------------------------------------
# Mass-variable rules
# -----------------------------------------------------------------------------


def q_endpoint_accepted(
    qmark: Dict[str, np.ndarray],
    obtype: Dict[str, np.ndarray],
    p_pa: np.ndarray,
    idx: int,
) -> bool:
    # Decide whether a specificHumidity endpoint is usable for interpolation.
    # Normal good QM values pass immediately. Otherwise, allow the special
    # upper-raob QM=9 case used by the JEDI YAML for type-120 humidity.
    qm = clamp_qm(qmark["specificHumidity"][idx])
    if qm < 4:
        return True

    if "specificHumidity" not in obtype:
        return False

    # Match the JEDI YAML rule:
    #   type 120, pressure between 1000 and 30000 Pa, and QM=9 is accepted.
    return bool(
        obtype["specificHumidity"][idx] == KX_MASS
        and qm == 9
        and p_pa[idx] >= 1000.0
        and p_pa[idx] <= 30000.0
    )


def accepted_qm_for_q_output(qm: int, accepted: bool) -> int:
    # If QM=9 was accepted by the upper-raob rule, store synthetic q as QM=2.
    # Otherwise, preserve the endpoint QM behavior through max().
    if accepted and qm == 9:
        return 2
    return qm


# -----------------------------------------------------------------------------
# Profile selection and synthetic rows
# -----------------------------------------------------------------------------


def thin_profile_by_pressure(idxs: np.ndarray, p_pa: np.ndarray, threshold_pa: float) -> np.ndarray:
    # Reduce very dense IODA profiles before applying sonde_ext logic.
    # Keep the first level, then only keep another level when it is separated
    # from the last kept level by more than threshold_pa. Always keep the top.
    if idxs.size < 2:
        return idxs

    p_prof = p_pa[idxs]
    keep = [0]
    for i in range(1, len(idxs)):
        if abs(p_prof[i] - p_prof[keep[-1]]) > threshold_pa:
            keep.append(i)

    if keep[-1] != len(idxs) - 1:
        keep.append(len(idxs) - 1)

    return idxs[np.array(keep, dtype=np.int64)]


def target_indices_between(p_lower: float, p_upper: float, p_targets: np.ndarray) -> np.ndarray:
    # Return model target levels that sit strictly between two observed levels.
    # p_lower is the larger pressure, closer to the surface.
    if not (p_lower > p_upper > 0.0):
        return np.array([], dtype=np.int64)
    return np.where((p_targets < p_lower) & (p_targets > p_upper))[0]


def fill_for_array(fills: Dict[Tuple[str, str], object], group_name: str, var_name: str, arr: np.ndarray):
    # Pick the fill value to use for a newly-created synthetic row.
    if (group_name, var_name) in fills:
        return fills[(group_name, var_name)]
    if np.issubdtype(arr.dtype, np.floating):
        return FLOAT_FILL_DEFAULT
    if np.issubdtype(arr.dtype, np.integer):
        return INT_FILL_DEFAULT
    return None


def append_default_rows(
    group_name: str,
    rows: Dict[str, List],
    arrays: Dict[str, np.ndarray],
    fills: Dict[Tuple[str, str], object],
) -> None:
    # Start each new synthetic row as entirely missing for this group.
    # Later code overwrites only the fields that are valid for that target level.
    for vname, arr in arrays.items():
        rows[vname].append(fill_for_array(fills, group_name, vname, arr))


def copy_meta_row(
    meta: Dict[str, np.ndarray],
    rows: Dict[str, List],
    source_idx: int,
    p_target_pa: float,
) -> None:
    # Create the metadata for a synthetic level by copying a real observed level.
    # Pressure and level category are the two fields intentionally changed.
    for name, arr in meta.items():
        if name == "pressure":
            rows[name].append(p_target_pa)
        elif name == "prepbufrDataLevelCategory":
            rows[name].append(np.int32(2))
        else:
            rows[name].append(arr[source_idx])


def set_obs_type(rows: Dict[str, List], obtype: Dict[str, np.ndarray], var_name: str) -> None:
    # Mark the synthetic variable as mass-sounding type 120 when ObsType exists.
    if var_name in obtype:
        rows[var_name][-1] = np.int32(KX_MASS)


def set_error_max(
    rows: Dict[str, List],
    obserr: Dict[str, np.ndarray],
    fills: Dict[Tuple[str, str], object],
    var_name: str,
    idx1: int,
    idx2: int,
) -> None:
    # Use the larger endpoint ObsError for the synthetic value.
    # This is conservative and avoids inventing a smaller error.
    if var_name not in obserr:
        return
    fill = fills.get(("ObsError", var_name), FLOAT_FILL_DEFAULT)
    e1 = obserr[var_name][idx1]
    e2 = obserr[var_name][idx2]
    if not is_missing(e1, fill) and not is_missing(e2, fill):
        rows[var_name][-1] = max(e1, e2)


def set_qm_max(rows: Dict[str, List], qmark: Dict[str, np.ndarray], var_name: str, idx1: int, idx2: int) -> None:
    # Propagate the worse endpoint quality marker to the synthetic value.
    if var_name not in qmark:
        return
    q1 = clamp_qm(qmark[var_name][idx1])
    q2 = clamp_qm(qmark[var_name][idx2])
    rows[var_name][-1] = np.int32(max(q1, q2))


def set_height(meta, qmark, fills, new_meta_rows, idx_lower, idx_upper, w_lower, w_upper) -> None:
    # Height is metadata, not an ObsValue, but it still needs a sensible value
    # for the inserted level. Interpolate when both endpoints are good.
    if "height" not in meta:
        return

    z_fill = fills.get(("MetaData", "height"), FLOAT_FILL_DEFAULT)
    z_lower = meta["height"][idx_lower]
    z_upper = meta["height"][idx_upper]
    z_lower_ok = not is_missing(z_lower, z_fill)
    z_upper_ok = not is_missing(z_upper, z_fill)
    z_qm_good = qms_good(qmark, "height", idx_lower, idx_upper) if "height" in qmark else True

    if z_lower_ok and z_upper_ok and z_qm_good:
        new_meta_rows["height"][-1] = interp(z_lower, z_upper, w_lower, w_upper)
    elif z_lower_ok and z_upper_ok:
        new_meta_rows["height"][-1] = max(z_lower, z_upper)
    elif z_lower_ok:
        new_meta_rows["height"][-1] = z_lower
    elif z_upper_ok:
        new_meta_rows["height"][-1] = z_upper


# -----------------------------------------------------------------------------
# Diagnostics
# -----------------------------------------------------------------------------


def print_hist(name: str, hist: Dict[int, int]) -> None:
    # Print a compact histogram showing how many target levels were found
    # between each eligible observed pressure pair.
    print(f"\n{name}")
    if not hist:
        print("  none")
        return
    for key in sorted(hist):
        print(f"  {key:3d} targets: {hist[key]} pairs")


def count_good_var(nc: Dataset, var_name: str, synthetic_only: Optional[bool]) -> int:
    # Count usable type-120 values for a regular variable using the standard
    # QM < 4 rule. synthetic_only controls whether to count original rows,
    # inserted rows, or both.
    if "ObsValue" not in nc.groups or var_name not in nc.groups["ObsValue"].variables:
        return 0
    if "QualityMarker" not in nc.groups or var_name not in nc.groups["QualityMarker"].variables:
        return 0
    if "ObsType" not in nc.groups or var_name not in nc.groups["ObsType"].variables:
        return 0
    if "MetaData" not in nc.groups or "pressure" not in nc.groups["MetaData"].variables:
        return 0

    obs = np.asarray(nc.groups["ObsValue"].variables[var_name][:])
    qm = np.asarray(nc.groups["QualityMarker"].variables[var_name][:])
    typ = np.asarray(nc.groups["ObsType"].variables[var_name][:])
    p = np.asarray(nc.groups["MetaData"].variables["pressure"][:])

    good = np.isfinite(obs) & (obs < 1.0e20) & np.isfinite(p) & (p > 0.0) & (qm < 4) & (typ == KX_MASS)

    if synthetic_only is not None:
        if "isSondeExt" not in nc.groups["MetaData"].variables:
            return 0
        ext = np.asarray(nc.groups["MetaData"].variables["isSondeExt"][:])
        good = good & (ext == (1 if synthetic_only else 0))

    return int(good.sum())


def count_good_specific_humidity_with_qm9_rule(nc: Dataset, synthetic_only: Optional[bool]) -> int:
    # Count type-120 specificHumidity using the same special acceptance rule
    # used when creating synthetic humidity: QM < 4, plus upper-raob QM=9.
    if "ObsValue" not in nc.groups or "specificHumidity" not in nc.groups["ObsValue"].variables:
        return 0
    if "QualityMarker" not in nc.groups or "specificHumidity" not in nc.groups["QualityMarker"].variables:
        return 0
    if "ObsType" not in nc.groups or "specificHumidity" not in nc.groups["ObsType"].variables:
        return 0
    if "MetaData" not in nc.groups or "pressure" not in nc.groups["MetaData"].variables:
        return 0

    q = np.asarray(nc.groups["ObsValue"].variables["specificHumidity"][:])
    qm = np.asarray(nc.groups["QualityMarker"].variables["specificHumidity"][:])
    typ = np.asarray(nc.groups["ObsType"].variables["specificHumidity"][:])
    p = np.asarray(nc.groups["MetaData"].variables["pressure"][:])

    good_value = np.isfinite(q) & (q < 1.0e20)
    good_pressure = np.isfinite(p) & (p > 0.0)
    type120 = typ == KX_MASS
    qm_good = qm < 4
    qm9_upper_raob = type120 & (p >= 1000.0) & (p <= 30000.0) & (qm == 9)

    good = good_value & good_pressure & type120 & (qm_good | qm9_upper_raob)

    if synthetic_only is not None:
        if "isSondeExt" not in nc.groups["MetaData"].variables:
            return 0
        ext = np.asarray(nc.groups["MetaData"].variables["isSondeExt"][:])
        good = good & (ext == (1 if synthetic_only else 0))

    return int(good.sum())


# -----------------------------------------------------------------------------
# NetCDF writing
# -----------------------------------------------------------------------------


def create_location_var(out_group, vin, n_tot: int):
    # Create an output Location variable with the same dtype, fill value,
    # and attributes as the input variable.
    fill_value = vin.getncattr("_FillValue") if "_FillValue" in vin.ncattrs() else None
    if fill_value is None:
        vout = out_group.createVariable(vin.name, vin.dtype, ("Location",))
    else:
        vout = out_group.createVariable(vin.name, vin.dtype, ("Location",), fill_value=fill_value)
    for attr_name in vin.ncattrs():
        if attr_name != "_FillValue":
            vout.setncattr(attr_name, vin.getncattr(attr_name))
    return vout


def append_1d(base: np.ndarray, ext: np.ndarray) -> np.ndarray:
    # Append synthetic rows to the original 1-D Location array.
    if ext.size == 0:
        return base
    return np.concatenate([base, ext], axis=0)


def write_output(
    # Write a copy of the input IODA file with extra Location rows appended.
    # Existing variables and attributes are preserved as much as possible.
    input_path: str,
    output_path: str,
    meta,
    obsval,
    obserr,
    obtype,
    qmark,
    new_meta_rows,
    new_obsval_rows,
    new_obserr_rows,
    new_obtype_rows,
    new_qmark_rows,
    orig_is_ext,
) -> None:
    n_orig = int(meta["pressure"].shape[0])
    n_new = len(new_meta_rows["pressure"])
    n_tot = n_orig + n_new

    with Dataset(input_path, "r") as nc, Dataset(output_path, "w", format="NETCDF4") as out:
        for attr_name in nc.ncattrs():
            out.setncattr(attr_name, nc.getncattr(attr_name))

        out.createDimension("Location", n_tot)

        # Copy top-level Location variables, if any.
        for vname, vin in nc.variables.items():
            if vin.dimensions != ("Location",):
                continue
            vout = create_location_var(out, vin, n_tot)
            if vname == "Location":
                vout[:] = np.arange(n_tot, dtype=vin.dtype)
                continue
            base = vin[:]
            if isinstance(base, np.ma.MaskedArray):
                base = base.filled(get_fill(vin))
            fill = get_fill(vin)
            ext = np.full((n_new,), fill, dtype=base.dtype)
            vout[:] = append_1d(base, ext)

        group_data = {
            "MetaData": (meta, new_meta_rows),
            "ObsValue": (obsval, new_obsval_rows),
            "ObsError": (obserr, new_obserr_rows),
            "ObsType": (obtype, new_obtype_rows),
            "QualityMarker": (qmark, new_qmark_rows),
        }

        for gname, gin in nc.groups.items():
            gout = out.createGroup(gname)
            for attr_name in gin.ncattrs():
                gout.setncattr(attr_name, gin.getncattr(attr_name))

            for vname, vin in gin.variables.items():
                if vin.dimensions != ("Location",):
                    continue

                vout = create_location_var(gout, vin, n_tot)
                base = vin[:]
                if isinstance(base, np.ma.MaskedArray):
                    base = base.filled(get_fill(vin))

                if gname in group_data and vname in group_data[gname][0]:
                    arrays, rows = group_data[gname]
                    base = arrays[vname]
                    if vname == "stationIdentification":
                        ext = np.array([str(x) for x in rows[vname]], dtype=object)
                    else:
                        ext = np.array(rows[vname], dtype=base.dtype)
                    vout[:] = append_1d(base, ext)
                else:
                    fill = get_fill(vin)
                    ext = np.full((n_new,), fill, dtype=base.dtype)
                    vout[:] = append_1d(base, ext)

            if gname == "MetaData":
                vout = gout.createVariable("isSondeExt", np.int32, ("Location",), fill_value=np.int32(-1))
                vout.long_name = "Synthetic level inserted by sonde_ext-like preprocessing"
                vout.units = "1"
                vout[:] = append_1d(orig_is_ext, np.ones((n_new,), dtype=np.int32))


# -----------------------------------------------------------------------------
# Main processing
# -----------------------------------------------------------------------------


def run(args) -> None:
    # Load the model target-pressure structure first. These targets determine
    # where sonde_ext-like synthetic levels can be inserted.
    rsig = read_rsig(args.rsig)

    with Dataset(args.input, "r") as nc:
        # Read the input groups needed for selection, interpolation, and output.
        # Everything is loaded into memory so the input file can close before
        # the output file is written.
        meta = load_group_vars(nc, "MetaData")
        obsval = load_group_vars(nc, "ObsValue")
        obserr = load_group_vars(nc, "ObsError")
        obtype = load_group_vars(nc, "ObsType")
        qmark = load_group_vars(nc, "QualityMarker")

        # These metadata fields define the vertical coordinate and profile identity.
        require_meta(meta, ["pressure", "stationIdentification", "releaseTime", "latitude", "longitude"])

        # This tool only creates synthetic mass temperature and humidity obs.
        for var_name in ["airTemperature", "specificHumidity"]:
            if var_name not in obsval or var_name not in qmark:
                raise RuntimeError(f"Missing ObsValue or QualityMarker for {var_name}")

        # Work internally in Pa and use a default category of 2 when the input
        # file does not provide prepbufrDataLevelCategory.
        p_pa = meta["pressure"].astype(np.float64)
        cat = meta.get("prepbufrDataLevelCategory")
        if cat is None:
            cat = np.full(p_pa.shape, 2, dtype=np.int32)
        else:
            cat = cat.astype(np.int32)

        # Build profile groups after all required metadata has been validated.
        qm_pressure = qmark.get("pressure")
        profiles = build_station_release_profiles(meta)

        # Cache fill values by group and variable so synthetic rows can be
        # initialized consistently with the source file.
        fills = {}
        for gname in ["MetaData", "ObsValue", "ObsError", "ObsType", "QualityMarker", "QCFlags"]:
            if gname in nc.groups:
                for vname, var in nc.groups[gname].variables.items():
                    fills[(gname, vname)] = get_fill(var)

    # Accumulate synthetic rows separately from the original arrays.
    # Each list grows in Location order and is appended during write_output().
    new_meta_rows = {k: [] for k in meta.keys()}
    new_obsval_rows = {k: [] for k in obsval.keys()}
    new_obserr_rows = {k: [] for k in obserr.keys()}
    new_obtype_rows = {k: [] for k in obtype.keys()}
    new_qmark_rows = {k: [] for k in qmark.keys()}
    orig_is_ext = np.zeros((p_pa.shape[0],), dtype=np.int32)

    # Diagnostics: counters summarize how many candidates passed each gate,
    # while histograms show how many model targets fell between pressure pairs.
    stats = defaultdict(int)
    hist_all = defaultdict(int)
    hist_selected = defaultdict(int)
    added_p_pa = defaultdict(list)

    profile_sizes = sorted([len(v) for v in profiles.values()], reverse=True)
    if args.debug:
        print(f"Number of profiles: {len(profiles)}")
        print(f"Top 10 profile sizes: {profile_sizes[:10]}")

    for key, idxs_raw in profiles.items():
        # Process one station/release profile at a time. Sort from high pressure
        # to low pressure so adjacent rows bracket the vertical column downward
        # from the surface toward the top of the sounding.
        order = np.argsort(-p_pa[idxs_raw])
        idxs = idxs_raw[order]

        # Thin dense profiles before inserting levels. This prevents a dense IODA
        # profile from producing far more sonde_ext levels than GSI would see.
        idxs = thin_profile_by_pressure(idxs, p_pa, args.thin_pa)
        if idxs.size < 2:
            continue

        # Respect the requested cap on total levels for this profile.
        max_new_for_profile = args.max_levels - int(idxs.size)
        if max_new_for_profile <= 0:
            continue

        # Scale rsig by the bottom pressure in this profile to get the actual
        # target pressures where synthetic obs might be inserted.
        p_sfc_pa = float(p_pa[idxs[0]])
        if not np.isfinite(p_sfc_pa) or p_sfc_pa <= 0.0:
            continue

        p_targets_pa = p_sfc_pa * rsig
        inserted_prof = 0

        for j in range(1, idxs.size):
            # Look at one adjacent pair of observed levels. A synthetic level can
            # only be inserted if a model target pressure lies between them.
            idx_lower = int(idxs[j - 1])
            idx_upper = int(idxs[j])
            p_lower = float(p_pa[idx_lower])
            p_upper = float(p_pa[idx_upper])

            if not (p_lower > p_upper > 0.0):
                continue

            stats["candidate_pairs"] += 1

            # Category gate: only use pressure pairs where at least one endpoint
            # is a mass/sonde-like level category used by this approximation.
            if not (int(cat[idx_lower]) in (2, 5) or int(cat[idx_upper]) in (2, 5)):
                continue
            stats["cat_pass"] += 1

            # Pressure quality gate: if pressure QM exists, both endpoints need
            # good pressure before pressure-space interpolation is trusted.
            if qm_pressure is not None:
                if clamp_qm(qm_pressure[idx_lower]) >= 4 or clamp_qm(qm_pressure[idx_upper]) >= 4:
                    continue
            stats["pqm_pass"] += 1

            # Find every model target pressure that this observed pair brackets.
            ks = target_indices_between(p_lower, p_upper, p_targets_pa)
            hist_all[int(ks.size)] += 1
            hist_selected[int(ks.size)] += 1
            if ks.size == 0:
                continue

            # Interpolate in the same log-pressure coordinate used by GSI.
            lp_lower = log_cb_from_pa(p_lower)
            lp_upper = log_cb_from_pa(p_upper)
            denom = lp_lower - lp_upper
            if denom == 0.0:
                continue

            for k in ks:
                # Insert one synthetic Location row for each bracketed target,
                # unless the profile-level cap has already been reached.
                if inserted_prof >= max_new_for_profile:
                    break

                pt = float(p_targets_pa[k])
                lpt = log_cb_from_pa(pt)
                w_lower = (lpt - lp_upper) / denom
                w_upper = (lp_lower - lpt) / denom

                # Create a new row initialized from the upper endpoint metadata,
                # then initialize all observation groups to missing values.
                copy_meta_row(meta, new_meta_rows, idx_upper, pt)
                append_default_rows("ObsValue", new_obsval_rows, obsval, fills)
                append_default_rows("ObsError", new_obserr_rows, obserr, fills)
                append_default_rows("ObsType", new_obtype_rows, obtype, fills)
                append_default_rows("QualityMarker", new_qmark_rows, qmark, fills)

                # Populate pressure and height metadata/diagnostics for the
                # synthetic level before handling individual variables.
                set_qm_max(new_qmark_rows, qmark, "pressure", idx_lower, idx_upper)
                set_error_max(new_obserr_rows, obserr, fills, "pressure", idx_lower, idx_upper)
                set_height(meta, qmark, fills, new_meta_rows, idx_lower, idx_upper, w_lower, w_upper)

                # Temperature: strict GSI-like endpoint requirement.
                t_fill = fills.get(("ObsValue", "airTemperature"), FLOAT_FILL_DEFAULT)
                if qms_good(qmark, "airTemperature", idx_lower, idx_upper) and values_good(
                    obsval["airTemperature"], t_fill, idx_lower, idx_upper
                ):
                    new_obsval_rows["airTemperature"][-1] = interp(
                        obsval["airTemperature"][idx_lower],
                        obsval["airTemperature"][idx_upper],
                        w_lower,
                        w_upper,
                    )
                    set_qm_max(new_qmark_rows, qmark, "airTemperature", idx_lower, idx_upper)
                    set_error_max(new_obserr_rows, obserr, fills, "airTemperature", idx_lower, idx_upper)
                    set_obs_type(new_obtype_rows, obtype, "airTemperature")
                    stats["insert_t"] += 1

                # Specific humidity: same endpoint-value requirement, but QM=9
                # is accepted in the upper-raob pressure window.
                q_fill = fills.get(("ObsValue", "specificHumidity"), FLOAT_FILL_DEFAULT)
                q_lower_ok = q_endpoint_accepted(qmark, obtype, p_pa, idx_lower)
                q_upper_ok = q_endpoint_accepted(qmark, obtype, p_pa, idx_upper)
                if q_lower_ok and q_upper_ok and values_good(obsval["specificHumidity"], q_fill, idx_lower, idx_upper):
                    new_obsval_rows["specificHumidity"][-1] = interp(
                        obsval["specificHumidity"][idx_lower],
                        obsval["specificHumidity"][idx_upper],
                        w_lower,
                        w_upper,
                    )
                    q_qm_lower = clamp_qm(qmark["specificHumidity"][idx_lower])
                    q_qm_upper = clamp_qm(qmark["specificHumidity"][idx_upper])
                    q_out_lower = accepted_qm_for_q_output(q_qm_lower, q_lower_ok)
                    q_out_upper = accepted_qm_for_q_output(q_qm_upper, q_upper_ok)
                    new_qmark_rows["specificHumidity"][-1] = np.int32(max(q_out_lower, q_out_upper))
                    set_error_max(new_obserr_rows, obserr, fills, "specificHumidity", idx_lower, idx_upper)
                    set_obs_type(new_obtype_rows, obtype, "specificHumidity")
                    stats["insert_q"] += 1

                # Count the synthetic Location even if only one of the supported
                # mass variables ended up valid at this target pressure.
                stats["insert_total"] += 1
                inserted_prof += 1
                added_p_pa[key].append(pt)

    if args.debug:
        print(f"Candidate adjacent pairs: {stats['candidate_pairs']}")
        print(f"Pairs passing CAT test: {stats['cat_pass']}")
        print(f"Pairs passing pressure QM test: {stats['pqm_pass']}")
        print(f"Inserted synthetic locations: {stats['insert_total']}")
        print(f"Inserted synthetic temperature values: {stats['insert_t']}")
        print(f"Inserted synthetic humidity values: {stats['insert_q']}")
        print(f"Original Location={p_pa.shape[0]}, new Location={p_pa.shape[0] + len(new_meta_rows['pressure'])}")
        print_hist("Raw model targets between eligible pressure pairs", hist_all)
        print_hist("Selected model targets", hist_selected)

    # Summarize how many profiles actually received one or more synthetic rows.
    profiles_with_adds = [(key, len(vals)) for key, vals in added_p_pa.items()]
    profiles_with_adds.sort(key=lambda x: x[1], reverse=True)
    print(f"Profiles with any added levels: {len(profiles_with_adds)}")

    if args.debug and profiles_with_adds:
        print("Detailed additions:")
        for key, count in profiles_with_adds:
            pts = np.array(added_p_pa[key], dtype=np.float64)
            p_list = ",".join(f"{p / 100.0:.1f}" for p in sorted(pts, reverse=True))
            print(f"  station={key[0]} releaseTime={key[1]} added={count}")
            print(f"    p_mb: {p_list}")

    # Write the final IODA file only after all profiles have been processed.
    write_output(
        args.input,
        args.output,
        meta,
        obsval,
        obserr,
        obtype,
        qmark,
        new_meta_rows,
        new_obsval_rows,
        new_obserr_rows,
        new_obtype_rows,
        new_qmark_rows,
        orig_is_ext,
    )

    # Re-open the output file and report quick sanity counts for original,
    # synthetic, and total type-120 values.
    with Dataset(args.output, "r") as out_nc:
        print("Output good counts:")
        print(f"  original airTemperature type 120: {count_good_var(out_nc, 'airTemperature', False)}")
        print(f"  synthetic airTemperature type 120: {count_good_var(out_nc, 'airTemperature', True)}")
        print(f"  total airTemperature type 120: {count_good_var(out_nc, 'airTemperature', None)}")
        print(
            f"  original specificHumidity type 120: "
            f"{count_good_specific_humidity_with_qm9_rule(out_nc, False)}"
        )
        print(
            f"  synthetic specificHumidity type 120: "
            f"{count_good_specific_humidity_with_qm9_rule(out_nc, True)}"
        )
        print(
            f"  total specificHumidity type 120: "
            f"{count_good_specific_humidity_with_qm9_rule(out_nc, None)}"
        )

    print(f"Wrote {args.output}")


def main() -> None:
    # Command-line interface. Required inputs are the source IODA file, rsig file,
    # and desired output path. Optional flags control thinning and diagnostics.
    ap = argparse.ArgumentParser()
    ap.add_argument("-i", "--input", required=True)
    ap.add_argument("-r", "--rsig", required=True)
    ap.add_argument("-o", "--output", required=True)
    ap.add_argument("--thin-pa", type=float, default=100.0, help="Profile thinning threshold in Pa")
    ap.add_argument("--max-levels", type=int, default=999999)
    ap.add_argument("--debug", action="store_true")
    args = ap.parse_args()

    if args.max_levels <= 0:
        raise RuntimeError("--max-levels must be positive")
    if args.thin_pa < 0.0:
        raise RuntimeError("--thin-pa must be non-negative")

    run(args)


if __name__ == "__main__":
    main()
