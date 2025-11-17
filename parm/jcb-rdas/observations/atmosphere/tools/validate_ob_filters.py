#!/usr/bin/env python3
import sys
import re
from pathlib import Path

# --------------------------------------------------------
#  List of udescriptors that are SAFE (no where required)
# --------------------------------------------------------
SAFE_UDESC = {
    "online_domain_check",
    "quality_marker_check",
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

        # if udescriptor is safe, no where needed
        if udesc in SAFE_UDESC:
            continue

        # require ObsType reference inside where except wind gross error checks
        if "gross_error" in udesc.lower():
            if "winds" in filename.lower():  # wind gross error checks
                continue

        # require where block
        if not has_where_block(block):
            issues.append(f"FILTER {fnum} (udescriptor={udesc}): Missing where:")
            continue

        # Require ObsType reference inside where
        if not where_has_obstype(block):
            issues.append(f"FILTER {fnum} (udescriptor={udesc}): where block missing ObsType reference")

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

