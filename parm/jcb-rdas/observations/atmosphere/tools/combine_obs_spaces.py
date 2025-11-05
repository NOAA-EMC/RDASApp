#!/usr/bin/env python3
"""
Combine multiple JEDI obs-space YAML templates (e.g., adpsfc_airTemperature_181.yaml.j2)
into a single combined YAML.j2 file (e.g., adpsfc.yaml.j2).

This version:
  - Prepends a universal "reject all" filter first.
  - Detects if stationPressure is among observed variables,
     and uses a Composite operator with VertInterp + SfcCorrected.
  - Preserves indentation and layout exactly like standard JEDI YAMLs.
"""

import argparse
from pathlib import Path
import textwrap

# ------------------------
# Parse arguments
# ------------------------
parser = argparse.ArgumentParser(description="Combine JEDI obs-space YAMLs into one file with a universal reject-all filter")
parser.add_argument("inputs", nargs="+", help="Input YAML files to combine")
parser.add_argument("-o", "--output", required=True, help="Output YAML file name")
args = parser.parse_args()


# ------------------------
# Helper: extract variable name from filename
# ------------------------
def extract_varname(filename):
    base = Path(filename).stem
    for key in ["airTemperature", "specificHumidity", "winds", "wind", "stationPressure"]:
        if key in base:
            return key
    parts = base.split("_")
    return parts[1] if len(parts) > 1 else base


# ------------------------
# Helper: extract filters (skip obs_type_check & initial_reject_all_providers)
# ------------------------
def extract_filters_section(path):
    lines = Path(path).read_text().splitlines()
    out = []
    in_filters = False
    current_block = []
    skip_block = False

    for line in lines:
        if "obs filters:" in line:
            in_filters = True
            continue
        if not in_filters:
            continue

        if line.strip().startswith("- filter:"):
            if current_block and not skip_block:
                out.extend(current_block)
            current_block = [line]
            skip_block = False
            continue

        # Skip filters whose udescriptor matches any of these keys
        skip_udescriptors = ["obs_type_check", "initial_reject_all_providers"]

        if "udescriptor:" in line:
            if any(key in line for key in skip_udescriptors):
                skip_block = True

        # Rename "reduce obs space" to "reject"
        if "reduce obs space" in line:
            line = line.replace("reduce obs space", "reject")

        current_block.append(line)

    if current_block and not skip_block:
        out.extend(current_block)

    return out


# ------------------------
# Collect variables and filters
# ------------------------
obs_vars = []
filters = []
for f in args.inputs:
    vname = extract_varname(f)
    if vname == "winds":
        obs_vars += ["windEastward", "windNorthward"]
    else:
        obs_vars.append(vname)

    filters.append(f"# ---- Extracted from {Path(f).name} ----")
    filters.extend(extract_filters_section(f))
    filters.append("")

# Deduplicate vars in order
seen = set()
obs_vars_unique = [v for v in obs_vars if not (v in seen or seen.add(v))]


# ------------------------
# Build obs operator block
# ------------------------
if "stationPressure" in obs_vars_unique:
    vert_vars = [v for v in obs_vars_unique if v != "stationPressure"]
    vert_block = "".join(f"             - name: {v}\n" for v in vert_vars)

    obs_operator_block = f"""       obs operator:
           name: Composite
           components:
           - name: VertInterp
             variables:
{vert_block}             vertical coordinate: air_pressure
             observation vertical coordinate: pressure
             observation vertical coordinate group: MetaData
             interpolation method: log-linear
           - name: SfcCorrected
             variables:
             - name: stationPressure
             correction scheme to use: GSL
             geovar_sfc_geomz: geopotential_height_at_surface
             geovar_geomz: geopotential_height
       linear obs operator:
         name: Identity
"""
else:
    vars_block = "".join(f"             - name: {v}\n" for v in obs_vars_unique)
    obs_operator_block = f"""       obs operator:
           name: VertInterp
           vertical coordinate: air_pressure
           observation vertical coordinate: pressure
           observation vertical coordinate group: MetaData
           interpolation method: log-linear
           variables:
{vars_block}       linear obs operator:
         name: Identity
"""


# ------------------------
# Build universal reject-all filter
# ------------------------
reject_filter = (
    "         # ---- Initial blanket rejection ----\n"
    "         - filter: Perform Action\n"
    "           udescriptor: \"obs_type_check_initial_reject\"\n"
    "           filter variables:\n"
    + "".join(f"           - name: {v}\n" for v in obs_vars_unique)
    + "           action:\n"
      "             name: reject\n\n"
)


# ------------------------
# Build YAML header
# ------------------------
combined_from = ", ".join(Path(f).name for f in args.inputs)
name = Path(Path(args.output).stem).stem
vars_csv = ",".join(obs_vars_unique)

combined_header = f"""# Auto-generated by combine_obs_spaces.py
# Combined from: {combined_from}

     - obs space:
         name: {name}
         distribution:
           name: "{{{{distribution}}}}"
           halo size: 500e3
         obsdatain:
           engine:
             type: H5File
             obsfile: "data/obs/ioda_{name}.nc"
             missing file action: "warn"
           obsgrouping:
             group variables: ["stationIdentification"]
             sort variable: "pressure"
             sort order: "descending"
         obsdataout:
           empty obs space action: "{{{{empty_obs_space_action}}}}"
           engine:
             type: H5File
             obsfile: jdiag_{name}.nc
             allow overwrite: true
         io pool:
           max pool size: 1
         observed variables: [{vars_csv}]
         simulated variables: [{vars_csv}]

{obs_operator_block}       obs error:
         covariance model: diagonal

       obs localizations:
         - localization method: Horizontal Gaspari-Cohn
           lengthscale: 200e3

       obs filters:
{reject_filter}
"""


# ------------------------
# Write output
# ------------------------
with open(args.output, "w") as out:
    out.write(combined_header)
    out.write("\n".join(filters))
    out.write("\n")

print(f"Combined YAML written to: {args.output}")

