#!/usr/bin/env python3
import sys
import re
from pathlib import Path

# -----------------------------------------------------------------
# List of udescriptors whose filters are intentionally unconditional
# -----------------------------------------------------------------
NO_WHERE_REQUIRED_UDESC = {
    "online_domain_check",
    "at2m_temperature_alias",
    "combined_time_window_check",
    "obs_type_check_initial_reject",
}

# ------------------------------------------------------------------------
# List of udescriptors that require where, but do not require an ObsType
# ------------------------------------------------------------------------
NO_OBSTYPE_REQUIRED_UDESC = {
    "quality_marker_check",
}

# -------------------------------------------------------------------------
# obs_type_check is a historical name for the ObsValue-presence reduction.
# The separate obs_kx_check filter performs the ObsType/KX selection.
# -------------------------------------------------------------------------
OBSVALUE_PRESENCE_UDESC = {
    "obs_type_check",
}

# -------------------------------------------------------------------------
# obs_subtype_check selects satellite-wind records by satellite identifier.
# -------------------------------------------------------------------------
SUBTYPE_SELECTION_UDESC = {
    "obs_subtype_check",
}

# ---------------------------------------------------------------------------
# List of obs spaces that do not have an ObsType variable (no where required)
# ---------------------------------------------------------------------------
SAFE_WHERE_OBSPACES = {
    "abi_g16",
    "abi_g18",
    "amsua_metop-b",
    "amsua_metop-c",
    "amsua_n19",
    "atms_n20",
    "atms_n21",
    "atms_npp",
    "mrms_refl",
}

def extract_filters(lines):
    filters = []
    current = None
    for idx, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("- filter:"):
            if current:
                filters.append(current)
            current = {
                "start": idx,
                "udescriptor": None,
                "lines": [line]
            }
        elif current:
            current["lines"].append(line)
            if stripped.startswith("udescriptor:"):
                # capture udescriptor value
                parts = stripped.split(":", 1)
                if len(parts) == 2:
                    val = parts[1].strip().strip('"').strip("'")
                    current["udescriptor"] = val
    if current:
        filters.append(current)
    return filters


def has_where_block(lines):
    return any(l.strip().startswith("where:") for l in lines)


def where_has_obstype(lines):
    for line in lines:
        s = line.strip()
        if s.startswith("variable:") and "ObsType/" in s:
            return True
        if "ObsType/" in s:
            return True
    return False


def where_has_obsvalue(lines):
    return any("ObsValue/" in line for line in lines)


def where_has_validity_test(lines):
    pattern = re.compile(r"^value:\s*['\"]?is_(?:not_)?valid['\"]?\s*$")
    return any(pattern.match(line.strip()) for line in lines)


def where_has_satellite_identifier(lines):
    return any("MetaData/satelliteIdentifier" in line for line in lines)


def where_has_not_in_test(lines):
    return any(line.strip().startswith("is_not_in:") for line in lines)


def block_has_wind_variable(lines):
    return any(
        variable in line
        for line in lines
        for variable in ("windEastward", "windNorthward")
    )


def has_self_scoped_wind_gross_error(lines):
    has_spdb_function = any(
        "ObsFunction/WindsSPDBCheck" in line for line in lines
    )
    has_wndtype = any(line.strip().startswith("wndtype:") for line in lines)
    return block_has_wind_variable(lines) and has_spdb_function and has_wndtype


def validate_file(filename):
    with open(filename) as f:
        lines = f.readlines()

    filters = extract_filters(lines)
    issues = []
    fnum = 0

    for flt in filters:
        fnum += 1
        udesc = flt["udescriptor"]
        block = flt["lines"]

        # must have a udescriptor
        if not udesc:
            issues.append(f"FILTER {fnum}: Missing udescriptor")
            continue

        # These operations are intentionally unconditional.
        if udesc in NO_WHERE_REQUIRED_UDESC:
            continue

        # if this ob does not have an ObsType variable, no where needed
        if any(token in filename for token in SAFE_WHERE_OBSPACES):
            continue

        # WindsSPDBCheck scopes itself with its wndtype option, so these wind
        # gross-error checks do not need a separate where block.
        if "gross_error" in udesc.lower():
            if has_self_scoped_wind_gross_error(block):
                continue

        # require where block
        if not has_where_block(block):
            issues.append(f"FILTER {fnum} (udescriptor={udesc}): Missing where:")
            continue

        # obs_type_check removes locations where the source ObsValue is absent.
        # It is not the ObsType/KX selector, so validate its actual semantics.
        if udesc in OBSVALUE_PRESENCE_UDESC:
            if not where_has_obsvalue(block):
                issues.append(
                    f"FILTER {fnum} (udescriptor={udesc}): "
                    "where block missing ObsValue reference"
                )
            if not where_has_validity_test(block):
                issues.append(
                    f"FILTER {fnum} (udescriptor={udesc}): "
                    "where block missing ObsValue validity test"
                )
            continue

        # obs_subtype_check performs a separate satellite-identifier selection.
        if udesc in SUBTYPE_SELECTION_UDESC:
            if not where_has_satellite_identifier(block):
                issues.append(
                    f"FILTER {fnum} (udescriptor={udesc}): "
                    "where block missing MetaData/satelliteIdentifier"
                )
            if not where_has_not_in_test(block):
                issues.append(
                    f"FILTER {fnum} (udescriptor={udesc}): "
                    "where block missing is_not_in selection"
                )
            continue

        # These filters use another field, such as QualityMarker, for selection.
        if udesc in NO_OBSTYPE_REQUIRED_UDESC:
            continue

        # Require ObsType reference inside where
        if not where_has_obstype(block):
            issues.append(
                f"FILTER {fnum} (udescriptor={udesc}): "
                "where block missing ObsType reference"
            )

    return issues


def main():
    if len(sys.argv) < 2:
        print("Usage: validate_ob_filters.py <yaml files>")
        sys.exit(1)

    for fname in sys.argv[1:]:
        issues = validate_file(fname)
        print()
        print("OBS FILTER VALIDATION REPORT")
        print("-------------------------------------")
        if issues:
            for e in issues:
                print("ERROR:", fname + ": " + e)
            print("\nTotal issues:", len(issues))
        else:
            print("No issues found:", fname)


if __name__ == "__main__":
    main()
