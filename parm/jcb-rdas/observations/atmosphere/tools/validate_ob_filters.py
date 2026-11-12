#!/usr/bin/env python3
import sys
import re
from pathlib import Path

# -----------------------------------------------------------------
# List of identifier suffixes whose filters are intentionally unconditional
# -----------------------------------------------------------------
NO_WHERE_REQUIRED_IDENTIFIER_SUFFIXES = {
    "online_domain_check",
    "at2m_temperature_alias",
    "combined_time_window_check",
    "obs_type_check_initial_reject",
    "DerivedSurfaceTemperature",
    "AdjustedHeightCoordinate",
    "SurfaceWindScalingHeight",
    "save_raw_surface_temperature",
    "initialize_derived_surface_temperature",
}

# ------------------------------------------------------------------------
# List of identifier suffixes that require where, but do not require an ObsType
# ------------------------------------------------------------------------
NO_OBSTYPE_REQUIRED_IDENTIFIER_SUFFIXES = {
    "quality_marker_check",
}

# -------------------------------------------------------------------------
# obs_type_check is a historical name for the ObsValue-presence reduction.
# The separate obs_kx_check filter performs the ObsType/KX selection.
# -------------------------------------------------------------------------
OBSVALUE_PRESENCE_IDENTIFIER_SUFFIXES = {
    "obs_type_check",
}

# -------------------------------------------------------------------------
# obs_subtype_check selects satellite-wind records by satellite identifier.
# -------------------------------------------------------------------------
SUBTYPE_SELECTION_IDENTIFIER_SUFFIXES = {
    "obs_subtype_check",
}

# ---------------------------------------------------------------------------
# Nonconventional obs spaces exempt from conventional where/ObsType checks
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
    "cris-fsr_n20",
    "cris-fsr_n21",
    "iasi_metop-b",
    "iasi_metop-c",
    "gnss_zenithTotalDelay",
    "nexrad_radialVelocity_999",
}

def scalar_value(value):
    """Read the simple quoted or unquoted scalars used by filter names."""
    value = value.strip()
    quoted = re.fullmatch(r"([\"'])(.*?)\1(?:\s+#.*)?", value)
    if quoted:
        return quoted.group(2)
    return value.split("#", 1)[0].strip()


def filter_option_block(lines, key):
    """Return a direct filter option, excluding other options and nested matches."""
    option_indent = len(lines[0]) - len(lines[0].lstrip()) + 2
    for index, line in enumerate(lines[1:], 1):
        indent = len(line) - len(line.lstrip())
        if indent != option_indent or line.strip().split("#", 1)[0].strip() != key + ":":
            continue
        block = []
        for member in lines[index + 1:]:
            member_indent = len(member) - len(member.lstrip())
            # YAML permits sequence entries at the same indentation as their key.
            if member_indent < option_indent or (
                member_indent == option_indent and not member.lstrip().startswith("- ")
            ):
                break
            block.append(member)
        return block
    return None


def extract_filters(lines):
    filters = []
    current = None
    obs_space = 0
    for idx, line in enumerate(lines):
        stripped = line.strip()
        # Comments and Jinja control lines do not define YAML filter options.
        if not stripped or stripped.startswith(("#", "{%", "{#")):
            continue
        indent = len(line) - len(line.lstrip())
        if current is not None and indent <= current["indent"]:
            filters.append(current)
            current = None
        if stripped.startswith("- obs space:"):
            obs_space += 1
        if stripped.startswith("- filter:"):
            current = {
                "start": idx,
                "indent": indent,
                "obs_space": obs_space,
                "type": scalar_value(stripped.split(":", 1)[1]),
                "name": None,
                "lines": [line],
            }
        elif current is not None:
            current["lines"].append(line)
    if current is not None:
        filters.append(current)
    for flt in filters:
        identifier = filter_option_block(flt["lines"], "identifier")
        if identifier is None:
            continue
        for line in identifier:
            indent = len(line) - len(line.lstrip())
            # Capture identifier.name only; assignments and actions also have names.
            if indent == flt["indent"] + 4 and line.strip().startswith("name:"):
                flt["name"] = scalar_value(line.strip().split(":", 1)[1])
                break
    return filters


def has_where_block(lines):
    return filter_option_block(lines, "where") is not None


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
    names_by_obs_space = {}

    for fnum, flt in enumerate(filters, 1):
        name = flt["name"]
        block = flt["lines"]

        # Each filter must have a nonempty identifier.name.
        if not name or not name.strip() or name.lower() in {"null", "~"}:
            issues.append(f"FILTER {fnum}: Missing identifier.name")
            continue

        # Identifiers may be reused in different observation spaces, but not within one.
        names = names_by_obs_space.setdefault(flt["obs_space"], {})
        if name in names:
            issues.append(
                f"FILTER {fnum} (identifier.name={name}): "
                f"Duplicate identifier.name (first used by FILTER {names[name]})"
            )
        else:
            names[name] = fnum

        # Match the historical rule suffix after the conventional filter-type prefix.
        prefix = flt["type"].replace(" ", "") + "_"
        # Combined filters retain the original rule name before their source namespace.
        rule_name = name.split("__from_", 1)[0]
        suffix = rule_name[len(prefix):] if rule_name.startswith(prefix) else rule_name

        # These operations are intentionally unconditional.
        if suffix in NO_WHERE_REQUIRED_IDENTIFIER_SUFFIXES:
            continue

        # Nonconventional observations do not use the conventional ObsType rules.
        if any(token in Path(filename).name for token in SAFE_WHERE_OBSPACES):
            continue

        # WindsSPDBCheck scopes itself with its wndtype option, so these wind
        # gross-error checks do not need a separate where block.
        if "gross_error" in suffix.lower():
            if has_self_scoped_wind_gross_error(block):
                continue

        # Require a direct filter where block, not a nested ObsFunction condition.
        if not has_where_block(block):
            issues.append(f"FILTER {fnum} (identifier.name={name}): Missing where:")
            continue
        where_block = filter_option_block(block, "where")

        # obs_type_check removes locations where the source ObsValue is absent.
        # It is not the ObsType/KX selector, so validate its actual semantics.
        if suffix in OBSVALUE_PRESENCE_IDENTIFIER_SUFFIXES:
            if not where_has_obsvalue(where_block):
                issues.append(
                    f"FILTER {fnum} (identifier.name={name}): "
                    "where block missing ObsValue reference"
                )
            if not where_has_validity_test(where_block):
                issues.append(
                    f"FILTER {fnum} (identifier.name={name}): "
                    "where block missing ObsValue validity test"
                )
            continue

        # obs_subtype_check performs a separate satellite-identifier selection.
        if suffix in SUBTYPE_SELECTION_IDENTIFIER_SUFFIXES:
            if not where_has_satellite_identifier(where_block):
                issues.append(
                    f"FILTER {fnum} (identifier.name={name}): "
                    "where block missing MetaData/satelliteIdentifier"
                )
            if not where_has_not_in_test(where_block):
                issues.append(
                    f"FILTER {fnum} (identifier.name={name}): "
                    "where block missing is_not_in selection"
                )
            continue

        # These filters use another field, such as QualityMarker, for selection.
        if suffix in NO_OBSTYPE_REQUIRED_IDENTIFIER_SUFFIXES:
            continue

        # Require ObsType reference inside where
        if not where_has_obstype(where_block):
            issues.append(
                f"FILTER {fnum} (identifier.name={name}): "
                "where block missing ObsType reference"
            )

    return issues


def main():
    if len(sys.argv) < 2:
        print("Usage: validate_ob_filters.py <yaml files>")
        sys.exit(1)

    exit_code = 0
    for fname in sys.argv[1:]:
        issues = validate_file(fname)
        print()
        print("OBS FILTER VALIDATION REPORT")
        print("-------------------------------------")
        if issues:
            exit_code = 1
            for e in issues:
                print("ERROR:", fname + ": " + e)
            print("\nTotal issues:", len(issues))
        else:
            print("No issues found:", fname)
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
