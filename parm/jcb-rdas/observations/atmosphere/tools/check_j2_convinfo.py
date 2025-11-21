#!/usr/bin/env python3
import os
import glob
import yaml
import pandas as pd
import numpy as np
import jinja2

colorize_match=True
drop_noYAML=False

# ANSI colors
RED = "\033[91m"
GREEN = "\033[92m"
YELLOW = "\033[93m"
RESET = "\033[0m"

def colorize(text):
    if text == "Match":
        return f"{GREEN}{text}{RESET}"
    elif text == "Mismatch":
        return f"{RED}{text}{RESET}"
    else:
        return f"{YELLOW}{text}{RESET}"

# Map YAML variable name -> convinfo otype
VAR_TO_OTYPE = {
    "airTemperature": "t",
    "specificHumidity": "q",
    "stationPressure": "ps",
    "winds": "uv",
}

# Assuming identity mapping for filter names based on udescriptor
# If there's a specific mapping, define it here
udesc_to_filtername = {
    "gross_error_check": "gross_error_check",
    "ermin_set": "ermin_set",
    "ermax_set": "ermax_set",
    "time_window_check": "time_window_check",
}

def parse_yaml(filename):
    """Extract gross/ermin/ermax/twindow from YAML structure using udescriptor mapping."""
    with open(filename, "r") as f:
        text = f.read()

    template = jinja2.Template(text)
    rendered = template.render()  # Render with empty context to remove placeholders
    data = yaml.safe_load(rendered)

    if not isinstance(data, list):
        raise ValueError(f"{filename}: expected list of filters at top level")

    base = os.path.basename(filename)
    parts = base.replace(".yaml.j2", "").split("_")
    varname = parts[1]
    typecode = parts[-1]

    otype = VAR_TO_OTYPE.get(varname)
    if otype is None:
        raise ValueError(f"Unmapped variable name '{varname}' in {base}")

    gross = ermin = ermax = twindow = None

    # Find the 'obs filters' section
    filters = []
    for section in data:
        if isinstance(section, dict) and 'obs filters' in section:
            filters = section['obs filters']
            break

    for block in filters:
        if not isinstance(block, dict):
            continue

        udesc = block.get("udescriptor")
        if not udesc:
            continue

        filter_name = udesc_to_filtername.get(udesc)
        if not filter_name:
            continue

        # ===== NEW LOGIC FOR GROSS / ERMIN / ERMAX =====

        # Only pull the main gross value from "gross_error_check"
        if filter_name == "gross_error_check":
            # For Background Check, threshold is directly in the block
            gross = block.get("threshold")
            if gross is None:
                fat = block.get("function absolute threshold", [])
                if fat and isinstance(fat, list):
                    func = fat[0]
                    if isinstance(func, dict) and func.get("name") == "ObsFunction/WindsSPDBCheck":
                        options = func.get("options", {})
                        cgross_list = options.get("cgross", [])
                        if cgross_list:
                            gross = cgross_list[0]
                        ermin_list = options.get("error_min", [])
                        if ermin_list:
                            ermin = ermin_list[0]
                        ermax_list = options.get("error_max", [])
                        if ermax_list:
                            ermax = ermax_list[0]

        # Error min
        elif filter_name == "ermin_set":
            fvars = block.get("filter variables", [])
            if fvars:
                ermin = fvars[0].get("threshold")
            if ermin is None:
                ermin = block.get("action", {}).get("error parameter")

        # Error max
        elif filter_name == "ermax_set":
            fvars = block.get("filter variables", [])
            if fvars:
                ermax = fvars[0].get("threshold")
            if ermax is None:
                ermax = block.get("action", {}).get("error parameter")

        # ===== EXTRACT TIME WINDOW =====
        if filter_name == "time_window_check":
            tw_min = None
            tw_max = None
            tw_min = block.get("minvalue")
            tw_max = block.get("maxvalue")
            if tw_min is not None and tw_max is not None:
                # typical YAML has minvalue: -twin, maxvalue: +twin
                twindow_sec = max(abs(tw_min), abs(tw_max))
                twindow = twindow_sec #/ 3600.0

    return {
        "file": base,
        "otype": otype,
        "type": int(typecode),
        "yaml_twindow": twindow,
        "yaml_gross": gross,
        "yaml_ermin": ermin,
        "yaml_ermax": ermax,
    }


def parse_convinfo(filename="convinfo.rrfs"):
    """Read convinfo.rrfs into a dataframe."""
    rows = []
    with open(filename) as f:
        for line in f:
            if line.strip().startswith("!"):  # skip comments
                continue
            parts = line.split()
            if len(parts) < 11:
                continue
            otype = parts[0]
            typecode = int(parts[1])
            # Based on header: otype type sub iuse twindow numgrp ngroup nmiter gross ermax ermin ...
            twindow = float(parts[4])*3600.
            gross = float(parts[8])
            ermax = float(parts[9])
            ermin = float(parts[10])
            rows.append({
                "otype": otype,
                "type": typecode,
                "conv_twindow": twindow,
                "conv_gross": gross,
                "conv_ermin": ermin,
                "conv_ermax": ermax,
            })
    return pd.DataFrame(rows)

def main():
    # YAML side
    yaml_rows = []
    for fname in glob.glob("../*.yaml.j2"):
        try:
            yaml_rows.append(parse_yaml(fname))
        except Exception as e:
            print(f"Warning: could not parse {fname}: {e}")
    df_yaml = pd.DataFrame(yaml_rows)

    # convinfo side
    df_conv = parse_convinfo("convinfo.rrfs")

    # Merge for comparison
    df = pd.merge(df_yaml, df_conv, on=["otype", "type"], how="outer")

    # Add match column with scaling for 'ps'
    scale_factor = np.where(df['otype'] == 'ps', 100.0, 1.0)
    cond_gross = (df['yaml_gross'] == df['conv_gross'])
    cond_ermin = (df['yaml_ermin'] / scale_factor == df['conv_ermin'])
    cond_ermax = (df['yaml_ermax'] / scale_factor == df['conv_ermax'])

    # twindow comparison
    df['twin_match'] = np.where(
        df['yaml_twindow'].isna(),
        'N/A',
        np.where(df['yaml_twindow'] == df['conv_twindow'], 'Match', 'Mismatch')
    )

    df['match'] = np.where(
        df['yaml_gross'].isna(),
        'N/A',
        np.where(cond_gross & cond_ermin & cond_ermax, 'Match', 'Mismatch')
    )

    # Colorize
    if colorize_match:
        df['match'] = df['match'].apply(colorize)
        df['twin_match'] = df['twin_match'].apply(colorize)

    # Sort nicely
    df = df.sort_values(by=["otype", "type"])

    # Finalize table
    if drop_noYAML:
        df = df[df['file'].notna()]
    else:
        df['file'] = df['file'].fillna("(no YAML)")

    # Show and save
    print(df.to_string(index=False))

if __name__ == "__main__":
    main()
