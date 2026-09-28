#!/bin/bash
set -euo pipefail

# --- Setup paths ---
RDASApp=$( git rev-parse --show-toplevel 2>/dev/null )
OBS_DIR="$RDASApp/parm/jcb-rdas/observations/atmosphere"
PYTHON_SCRIPT="$OBS_DIR/tools/combine_obs_spaces.py"

# --- Load environment ---
cd "$RDASApp/ush"
source load_rdas.sh
cd "$OBS_DIR"

# --- List the observation prefixes to combine (e.g., adpsfc, aircar, etc.) ---
prefixes=(
    adpsfc
    aircar
    adpupa
    aircft
    msonet
    sfcshp
    vadwnd
    proflr
    rassda
)
printf 'Prefixes: %s\n' "${prefixes[*]}"

# Treat an unmatched filename pattern as an empty array.
shopt -s nullglob

# Optional: limit to specific type while testing
#prefixes="adpsfc"
for prefix in "${prefixes[@]}"; do
    echo "Processing prefix: $prefix"

    # Find YAML templates for this prefix (skip already-combined files)
    files=( "${prefix}"_*.yaml.j2 )
    if [ ${#files[@]} -eq 0 ]; then
        echo "  No files found for prefix: $prefix"
        continue
    fi

    echo "  Merging ${#files[@]} files:"
    for f in "${files[@]}"; do
        echo "     - $f"
    done

    output="${prefix}.yaml.j2"
    echo "  Output: $output"

    # Run Python combiner (no extra args needed)
    python "$PYTHON_SCRIPT" "${files[@]}" -o "$output"
done

echo "All combined obs space YAMLs generated."

