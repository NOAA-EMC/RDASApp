#!/usr/bin/env python3
import argparse
import glob
import os
import sys

import jinja2
import numpy as np
import pandas as pd
import yaml


# =============================================================================
# User options
# =============================================================================

COLORIZE_MATCH = True

RTOL = 1.0e-12
ATOL = 1.0e-12


# =============================================================================
# ANSI colors
# =============================================================================

RED = "\033[91m"
GREEN = "\033[92m"
YELLOW = "\033[93m"
RESET = "\033[0m"


def colorize(text):
    if text == "Match":
        return f"{GREEN}{text}{RESET}"
    if text == "Mismatch":
        return f"{RED}{text}{RESET}"
    return f"{YELLOW}{text}{RESET}"


# =============================================================================
# Variable mappings
# =============================================================================

# YAML variable name -> errtable column number.
#
# errtable.rrfs format:
#
#   type OBSERVATION TYPE
#     pressure_hPa err_col_1 err_col_2 err_col_3 err_col_4 err_col_5
#
# Based on your get_obs_error.py usage:
#   ./get_obs_error.py errtable.rrfs 247 3
# means UV/winds use column 3.
VAR_TO_ERRCOL = {
    "airTemperature": 1,
    "specificHumidity": 2,
    "winds": 3,
    "stationPressure": 4,
}

# Optional display labels.
VAR_TO_ERRVAR = {
    "airTemperature": "t",
    "specificHumidity": "q",
    "winds": "uv",
    "stationPressure": "ps",
}

# Scale errtable errors into YAML units before comparison.
#
# GSI errtable q values are 10x the YAML specificHumidity values.
# Example:
#   errtable q = 0.56103
#   YAML q     = 0.056103
ERRTABLE_TO_YAML_ERROR_SCALE = {
    "airTemperature": 1.0,
    "specificHumidity": 0.1,
    "winds": 1.0,
    "stationPressure": 1.0,
}

# Scale errtable errors into YAML units before comparison.
#
# GSI errtable q values are 10x the YAML specificHumidity values.
# Example:
#   errtable q = 0.56103
#   YAML q     = 0.056103
ERRTABLE_TO_YAML_ERROR_SCALE = {
    "airTemperature": 1.0,
    "specificHumidity": 0.1,
    "winds": 1.0,
    "stationPressure": 100.0,
}
# =============================================================================
# Generic helpers
# =============================================================================

def is_missing_value(value):
    """Return True for None or pandas/numpy scalar NaN."""
    if value is None:
        return True

    if isinstance(value, float) and np.isnan(value):
        return True

    return False


def as_float_list(value):
    """Convert a YAML scalar/list/string into a list of floats."""
    if is_missing_value(value):
        return None

    if isinstance(value, list):
        return [float(v) for v in value]

    if isinstance(value, tuple):
        return [float(v) for v in value]

    if isinstance(value, np.ndarray):
        return [float(v) for v in value.tolist()]

    if isinstance(value, str):
        text = value.strip().strip("[]")
        if not text:
            return []
        return [float(v.strip()) for v in text.split(",")]

    # A single scalar is not a valid error table, but return a one-item list
    # so the comparison can report a length mismatch instead of crashing.
    if isinstance(value, (int, float)):
        return [float(value)]

    raise TypeError(f"Cannot convert {type(value)} to float list")


def walk_dicts(obj):
    """Yield every dictionary nested inside obj."""
    if isinstance(obj, dict):
        yield obj
        for val in obj.values():
            yield from walk_dicts(val)
    elif isinstance(obj, list):
        for item in obj:
            yield from walk_dicts(item)


def short_list(vals, n=4):
    """Compact list display for debug output."""
    if is_missing_value(vals):
        return "None"

    vals = list(vals)

    if len(vals) <= 2 * n:
        return "[" + ", ".join(f"{v:g}" for v in vals) + "]"

    head = ", ".join(f"{v:g}" for v in vals[:n])
    tail = ", ".join(f"{v:g}" for v in vals[-n:])
    return f"[{head}, ..., {tail}]"


# =============================================================================
# YAML parsing
# =============================================================================

def is_candidate_conv_yaml(filename):
    """
    Return True only for conventional obs YAML filenames that look like:

      platform_variable_type.yaml.j2
      platform_variable_type_subtype.yaml.j2

    This intentionally skips radiance/non-conv YAMLs like:

      abi_g16.yaml.j2
      atms_n20.yaml.j2
      gnss_zenithTotalDelay.yaml.j2
      mrms_refl.yaml.j2
    """
    base = os.path.basename(filename)
    name = base.replace(".yaml.j2", "").replace(".yaml", "")
    parts = name.split("_")

    if len(parts) < 3:
        return False

    varname = parts[1]
    if varname not in VAR_TO_ERRCOL:
        return False

    nums = [p for p in parts[2:] if p.isdigit()]
    if len(nums) not in (1, 2):
        return False

    return True


def parse_yaml_filename(filename):
    """
    Extract variable, type, and subtype from a conventional YAML filename.

    Examples:
      adpupa_airTemperature_120.yaml.j2 -> airTemperature, 120, 0
      satwnd_winds_247_270.yaml.j2      -> winds, 247, 270
    """
    base = os.path.basename(filename)
    name = base.replace(".yaml.j2", "").replace(".yaml", "")
    parts = name.split("_")

    if len(parts) < 3:
        raise ValueError(f"Unexpected YAML filename pattern: {base}")

    varname = parts[1]
    nums = [p for p in parts[2:] if p.isdigit()]

    if len(nums) == 1:
        typecode = int(nums[0])
        subtype = 0
    elif len(nums) == 2:
        typecode = int(nums[0])
        subtype = int(nums[1])
    else:
        raise ValueError(f"Unexpected numeric pattern in YAML filename: {base}")

    if varname not in VAR_TO_ERRCOL:
        raise ValueError(f"Unmapped variable name '{varname}' in {base}")

    return {
        "file": base,
        "varname": varname,
        "errvar": VAR_TO_ERRVAR[varname],
        "errcol": VAR_TO_ERRCOL[varname],
        "type": typecode,
        "subtype": subtype,
    }


def render_jinja_loose(text):
    """
    Render a YAML/Jinja file with an empty context.

    This script skips radiance YAMLs before rendering, so undefined radiance
    helper functions should not usually matter. Keep this function separate so
    the behavior is easy to adjust later if needed.
    """
    template = jinja2.Template(text)
    return template.render()


def parse_yaml_file(filename):
    """
    Extract ObsErrorModelStepwiseLinear xvals/errors from one YAML/Jinja obs file.
    """
    info = parse_yaml_filename(filename)

    with open(filename, "r") as f:
        text = f.read()

    rendered = render_jinja_loose(text)
    data = yaml.safe_load(rendered)

    xvals = None
    errors = None
    source = None

    # Search the whole rendered YAML. This is more robust than assuming the
    # error model is located at a fixed nesting depth.
    for dct in walk_dicts(data):
        if dct.get("name") != "ObsFunction/ObsErrorModelStepwiseLinear":
            continue

        options = dct.get("options", {})
        if not isinstance(options, dict):
            continue

        candidate_xvals = options.get("xvals")
        candidate_errors = options.get("errors")

        if candidate_xvals is None or candidate_errors is None:
            continue

        xvals = as_float_list(candidate_xvals)
        errors = as_float_list(candidate_errors)
        source = "ObsFunction/ObsErrorModelStepwiseLinear"
        break

    info.update({
        "yaml_xvals": xvals,
        "yaml_errors": errors,
        "yaml_source": source,
    })

    return info


# =============================================================================
# errtable parsing
# =============================================================================

def parse_errtable(filename):
    """
    Parse GSI errtable.rrfs.

    Expected format:

      247 OBSERVATION TYPE
        0.11000E+04  err_col_1 err_col_2 err_col_3 err_col_4 err_col_5
        0.10500E+04  err_col_1 err_col_2 err_col_3 err_col_4 err_col_5

    The first column is pressure in hPa. JEDI YAML xvals are normally Pa,
    so pressure is converted to Pa here.

    Returned errcol values are 1-based:
      col 1 = airTemperature
      col 2 = specificHumidity
      col 3 = winds
      col 4 = stationPressure
      col 5 = unused/other, depending on the table
    """
    rows = []

    current_type = None
    current_pressures = []
    current_errors_by_col = {}

    def flush_current_type():
        if current_type is None:
            return

        for errcol, errors in current_errors_by_col.items():
            rows.append({
                "type": current_type,
                "errcol": errcol,
                "err_xvals": list(current_pressures),
                "err_errors": list(errors),
            })

    with open(filename, "r") as f:
        for line in f:
            raw = line.strip()

            if not raw:
                continue

            parts = raw.split()

            # Header line, for example:
            #   247 OBSERVATION TYPE
            if len(parts) >= 3 and parts[1] == "OBSERVATION" and parts[2] == "TYPE":
                flush_current_type()

                current_type = int(parts[0])
                current_pressures = []
                current_errors_by_col = {}
                continue

            if current_type is None:
                continue

            try:
                values = [float(p) for p in parts]
            except ValueError:
                continue

            if len(values) < 2:
                continue

            pressure_hpa = values[0]
            pressure_pa = pressure_hpa * 100.0
            errors = values[1:]

            current_pressures.append(pressure_pa)

            for idx, err in enumerate(errors, start=1):
                current_errors_by_col.setdefault(idx, []).append(err)

    flush_current_type()

    return pd.DataFrame(rows)


# =============================================================================
# Comparison
# =============================================================================

def normalize_table(xvals, errors, descending=True):
    """Return pressure/error arrays in a consistent order."""
    if is_missing_value(xvals) or is_missing_value(errors):
        return None, None

    x = np.asarray(xvals, dtype=float)
    e = np.asarray(errors, dtype=float)

    if x.ndim != 1 or e.ndim != 1:
        return None, None

    if x.size != e.size:
        raise ValueError(f"xvals/errors length mismatch: {x.size} vs {e.size}")

    order = np.argsort(x)
    if descending:
        order = order[::-1]

    return x[order], e[order]


def compare_arrays(yaml_xvals, yaml_errors, err_xvals, err_errors):
    """
    Compare YAML and errtable pressure/error arrays.

    Returns:
      status, yaml_n, err_n, max_abs_error_diff, pressure_match
    """
    if is_missing_value(yaml_xvals) or is_missing_value(yaml_errors):
        return "No YAML error model", np.nan, np.nan, np.nan, "N/A"

    if is_missing_value(err_xvals) or is_missing_value(err_errors):
        return "No errtable entry", np.nan, np.nan, np.nan, "N/A"

    yx, ye = normalize_table(yaml_xvals, yaml_errors)
    gx, ge = normalize_table(err_xvals, err_errors)

    if yx is None or ye is None:
        return "No YAML error model", np.nan, np.nan, np.nan, "N/A"

    if gx is None or ge is None:
        return "No errtable entry", np.nan, np.nan, np.nan, "N/A"

    if yx.size != gx.size:
        return "Mismatch", yx.size, gx.size, np.nan, "Length mismatch"

    same_x = np.allclose(yx, gx, rtol=RTOL, atol=ATOL, equal_nan=True)
    same_e = np.allclose(ye, ge, rtol=RTOL, atol=ATOL, equal_nan=True)

    max_abs_diff = float(np.nanmax(np.abs(ye - ge))) if ye.size else 0.0
    pressure_match = "Match" if same_x else "Mismatch"

    if same_x and same_e:
        return "Match", yx.size, gx.size, max_abs_diff, pressure_match

    return "Mismatch", yx.size, gx.size, max_abs_diff, pressure_match


def max_pressure_diff(yaml_xvals, err_xvals):
    if is_missing_value(yaml_xvals) or is_missing_value(err_xvals):
        return np.nan

    yx = np.asarray(yaml_xvals, dtype=float)
    gx = np.asarray(err_xvals, dtype=float)

    if yx.ndim != 1 or gx.ndim != 1 or yx.size != gx.size:
        return np.nan

    yx = np.sort(yx)[::-1]
    gx = np.sort(gx)[::-1]

    return float(np.nanmax(np.abs(yx - gx))) if yx.size else 0.0


# =============================================================================
# Main
# =============================================================================

def main():
    parser = argparse.ArgumentParser(
        description="Compare GSI errtable.rrfs errors against JEDI YAML obs spaces."
    )

    parser.add_argument(
        "--yaml-glob",
        default="../*.yaml.j2",
        help="Glob for JEDI YAML/Jinja obs spaces. Default: ../*.yaml.j2",
    )

    parser.add_argument(
        "--errtable",
        default="errtable.rrfs",
        help="Path to GSI errtable. Default: errtable.rrfs",
    )

    parser.add_argument(
        "--only-mismatch",
        action="store_true",
        help="Only print mismatches and missing entries.",
    )

    parser.add_argument(
        "--debug",
        action="store_true",
        help="Print compact error arrays for mismatches/debugging.",
    )

    parser.add_argument(
        "--csv",
        default=None,
        help="Optional CSV output path.",
    )

    parser.add_argument(
        "--no-color",
        action="store_true",
        help="Disable ANSI color in terminal output.",
    )

    args = parser.parse_args()

    # -------------------------------------------------------------------------
    # Parse YAML files
    # -------------------------------------------------------------------------

    yaml_rows = []
    skipped = 0

    for fname in sorted(glob.glob(args.yaml_glob)):
        if not is_candidate_conv_yaml(fname):
            skipped += 1
            continue

        try:
            yaml_rows.append(parse_yaml_file(fname))
        except Exception as e:
            print(f"Warning: could not parse {fname}: {e}", file=sys.stderr)

    if not yaml_rows:
        raise RuntimeError(f"No conventional YAML files parsed from glob: {args.yaml_glob}")

    df_yaml = pd.DataFrame(yaml_rows)

    # -------------------------------------------------------------------------
    # Parse errtable
    # -------------------------------------------------------------------------

    df_err = parse_errtable(args.errtable)

    if df_err.empty:
        raise RuntimeError(f"No errtable rows parsed from: {args.errtable}")

    # -------------------------------------------------------------------------
    # Merge and compare
    # -------------------------------------------------------------------------

    df = pd.merge(
        df_yaml,
        df_err,
        left_on=["type", "errcol"],
        right_on=["type", "errcol"],
        how="outer",
    )

    results = []

    for _, row in df.iterrows():
        err_errors = row.get("err_errors")
        varname = row.get("varname")

        if not is_missing_value(err_errors) and varname in ERRTABLE_TO_YAML_ERROR_SCALE:
            scale = ERRTABLE_TO_YAML_ERROR_SCALE[varname]
            err_errors = [float(v) * scale for v in err_errors]

        status, yaml_n, err_n, max_abs_diff, pressure_match = compare_arrays(
            row.get("yaml_xvals"),
            row.get("yaml_errors"),
            row.get("err_xvals"),
            err_errors,
        )

        max_p_diff = max_pressure_diff(
            row.get("yaml_xvals"),
            row.get("err_xvals"),
        )

        results.append({
            "file": row.get("file", "(no YAML)"),
            "varname": row.get("varname"),
            "errvar": row.get("errvar"),
            "errcol": row.get("errcol"),
            "type": row.get("type"),
            "subtype": row.get("subtype"),
            "yaml_n": yaml_n,
            "err_n": err_n,
            "max_pressure_diff": max_p_diff,
            "max_abs_diff": max_abs_diff,
            "pressure_match": pressure_match,
            "match": status,
            "yaml_errors": short_list(row.get("yaml_errors")),
            "err_errors": short_list(row.get("err_errors")),
            "yaml_xvals": short_list(row.get("yaml_xvals")),
            "err_xvals": short_list(row.get("err_xvals")),
        })

    out = pd.DataFrame(results)

    if args.only_mismatch:
        out = out[out["match"] != "Match"]

    out = out.sort_values(
        by=["varname", "type", "subtype", "errcol"],
        na_position="last",
    )

    display = out.copy()

    if COLORIZE_MATCH and not args.no_color:
        display["match"] = display["match"].apply(colorize)
        display["pressure_match"] = display["pressure_match"].apply(colorize)

    cols = [
        "file",
        "varname",
        "errvar",
        "errcol",
        "type",
        "subtype",
        "yaml_n",
        "err_n",
        "max_pressure_diff",
        "max_abs_diff",
        "pressure_match",
        "match",
    ]

    if args.debug:
        cols += [
            "yaml_xvals",
            "err_xvals",
            "yaml_errors",
            "err_errors",
        ]

    print(display[cols].to_string(index=False))

    print("")
    print(f"Parsed YAML rows: {len(df_yaml)}")
    print(f"Skipped non-conv YAMLs: {skipped}")
    print(f"Parsed errtable rows: {len(df_err)}")

    if args.csv:
        out.to_csv(args.csv, index=False)
        print(f"Wrote CSV: {args.csv}")


if __name__ == "__main__":
    main()
