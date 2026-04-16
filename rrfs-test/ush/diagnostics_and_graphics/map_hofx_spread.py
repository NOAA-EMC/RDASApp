#!/usr/bin/env python
import argparse
import re


def to_nan(values, fill_value):
    """Convert fill values and non-finite entries to NaN."""
    import numpy as np

    data = np.asarray(values, dtype=np.float64)
    if fill_value is not None:
        data = np.where(data == fill_value, np.nan, data)
    data = np.where(np.isfinite(data), data, np.nan)
    return data


def read_metadata(dataset):
    """Read latitude/longitude from the MetaData group."""
    import numpy as np

    if "MetaData" not in dataset.groups:
        raise ValueError("Missing MetaData group in input file.")

    metadata = dataset.groups["MetaData"]
    if "latitude" not in metadata.variables or "longitude" not in metadata.variables:
        raise ValueError("MetaData group must contain latitude and longitude variables.")

    latitude_var = metadata.variables["latitude"]
    longitude_var = metadata.variables["longitude"]
    latitudes = to_nan(latitude_var[:], getattr(latitude_var, "_FillValue", None))
    longitudes = to_nan(longitude_var[:], getattr(longitude_var, "_FillValue", None))
    longitudes = np.where(longitudes > 180.0, longitudes - 360.0, longitudes)
    return latitudes, longitudes


def read_hofx_ensemble(dataset, n_members):
    """Read hofx for all ensemble members and return stacked member array."""
    import numpy as np

    hofx_name_pattern = re.compile(r"hofx0_(\d+)$")
    hofx_groups = {}
    for group_name, group in dataset.groups.items():
        match = hofx_name_pattern.match(group_name)
        if match:
            hofx_groups[int(match.group(1))] = group

    missing_members = [member for member in range(1, n_members + 1) if member not in hofx_groups]
    if missing_members:
        raise ValueError(f"Missing hofx groups for members: {missing_members}")

    member_values = []
    obs_var_name = None
    for member in range(1, n_members + 1):
        group = hofx_groups[member]
        variable_names = list(group.variables.keys())
        if not variable_names:
            raise ValueError(f"Group hofx0_{member} does not contain any variables.")
        if len(variable_names) > 1:
            raise ValueError(f"Group hofx0_{member} contains multiple variables: {variable_names}")

        current_var_name = variable_names[0]
        if obs_var_name is None:
            obs_var_name = current_var_name
        elif current_var_name != obs_var_name:
            raise ValueError(
                f"Inconsistent variable names across hofx groups ({obs_var_name} vs {current_var_name})."
            )

        variable = group.variables[current_var_name]
        values = to_nan(variable[:], getattr(variable, "_FillValue", None))
        member_values.append(values)

    ensemble_values = np.asarray(member_values)
    if ensemble_values.ndim != 2:
        raise ValueError(
            f"Expected hofx arrays to be 1D by Location for each member, got shape {ensemble_values.shape}."
        )
    return obs_var_name, ensemble_values


def plot_spread(latitudes, longitudes, spread, obs_var_name, output_path):
    """Plot spread over CONUS and write to output file."""
    import numpy as np
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    try:
        import cartopy.crs as ccrs
        import cartopy.feature as cfeature
    except ModuleNotFoundError as exc:
        raise ModuleNotFoundError(
            "cartopy is required to plot the spread map (Basemap is not used)."
        ) from exc

    valid = np.isfinite(spread) & np.isfinite(latitudes) & np.isfinite(longitudes)
    if not np.any(valid):
        raise ValueError("No valid spread values available to plot.")

    fig = plt.figure(figsize=(10, 6))
    axis = fig.add_subplot(1, 1, 1, projection=ccrs.PlateCarree())
    axis.set_extent([-132.5, -65.0, 22.0, 53.0], crs=ccrs.PlateCarree())
    axis.add_feature(cfeature.COASTLINE)
    axis.add_feature(cfeature.BORDERS)
    axis.add_feature(cfeature.STATES, linewidth=0.5)

    scatter = axis.scatter(
        longitudes[valid],
        latitudes[valid],
        c=spread[valid],
        s=6,
        cmap="viridis",
        transform=ccrs.PlateCarree(),
    )

    axis.set_title(f"Ensemble Spread ({obs_var_name})")
    colorbar = plt.colorbar(scatter, ax=axis, orientation="vertical", pad=0.02, shrink=0.8)
    colorbar.set_label("Spread (standard deviation)")
    plt.tight_layout()
    plt.savefig(output_path, dpi=300, bbox_inches="tight")
    plt.close(fig)


def main():
    parser = argparse.ArgumentParser(
        description="Compute hofx ensemble spread from JEDI diagnostic file and save a US map."
    )
    parser.add_argument("input_file", help="Path to JEDI diagnostic netCDF file (e.g. jdiag_*.nc).")
    parser.add_argument(
        "-o",
        "--output",
        default="hofx_spread_map.png",
        help="Output image path (default: hofx_spread_map.png).",
    )
    parser.add_argument(
        "-n",
        "--members",
        type=int,
        default=30,
        help="Number of ensemble members to read from hofx0_1..hofx0_N (default: 30).",
    )
    args = parser.parse_args()
    if args.members < 2:
        raise ValueError("Ensemble spread requires at least 2 members.")

    import numpy as np
    from netCDF4 import Dataset

    with Dataset(args.input_file, "r") as dataset:
        if "Location" not in dataset.dimensions:
            raise ValueError("Root-level Location dimension is missing.")

        location_size = dataset.dimensions["Location"].size
        latitudes, longitudes = read_metadata(dataset)
        obs_var_name, hofx_members = read_hofx_ensemble(dataset, args.members)

    if latitudes.shape[0] != location_size or longitudes.shape[0] != location_size:
        raise ValueError(
            f"MetaData coordinate size mismatch: latitude={latitudes.shape[0]}, "
            f"longitude={longitudes.shape[0]}, Location={location_size}."
        )
    spread = np.nanstd(hofx_members, axis=0, ddof=1)
    if spread.shape[0] != location_size:
        raise ValueError(
            f"Location size mismatch: spread has {spread.shape[0]} values, "
            f"root Location dimension has {location_size}."
        )

    plot_spread(latitudes, longitudes, spread, obs_var_name, args.output)
    print(f"Saved spread map: {args.output}")


if __name__ == "__main__":
    main()
