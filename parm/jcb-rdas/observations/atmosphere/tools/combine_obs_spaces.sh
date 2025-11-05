#!/bin/bash
set -euo pipefail

# --- Setup paths ---
RDASApp="/scratch4/NCEPDEV/fv3-cam/Donald.E.Lippi/RRFSv2/PRs/RDASApp.20251105.jcb_combine_obs_spaces"
OBS_DIR="$RDASApp/parm/jcb-rdas/observations/atmosphere"
PYTHON_SCRIPT="$OBS_DIR/tools/combine_obs_spaces.py"

# --- Load environment ---
cd "$RDASApp/ush"
source load_rdas.sh
cd "$OBS_DIR"

# --- Detect all unique observation prefixes (e.g., adpsfc, aircar, etc.) ---
prefixes=$(ls *Hum*.yaml.j2 2>/dev/null | awk -F'_' '{print $1}' | sort -u)
echo $prefixes
# Optional: limit to specific type while testing
#prefixes="adpsfc"
for prefix in $prefixes; do
    echo "Processing prefix: $prefix"

    # Find YAML templates for this prefix (skip already-combined files)
    files=($(ls ${prefix}_*.yaml.j2 2>/dev/null ))
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

