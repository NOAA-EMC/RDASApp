#!/usr/bin/env python3
"""Rename an IODA variable consistently across all groups.

The positional variable names are IODA base names.  For example, renaming
``airTemperature`` to ``airTemperatureAt2M`` updates matching variables such
as ``ObsValue/airTemperature``, ``ObsType/airTemperature``, and
``QualityMarker/airTemperature``.

By default a new file is written next to the input file.  Use ``--in-place``
only when modifying the input file directly is intended.
"""

from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path


def iter_groups(group, path=""):
    """Yield a group and all of its descendants with their IODA paths."""
    yield path, group
    for name, child in group.groups.items():
        child_path = f"{path}/{name}" if path else name
        yield from iter_groups(child, child_path)


def find_matches(dataset, old_name, new_name):
    """Return matching variables and detect destination-name collisions."""
    matches = []
    collisions = []
    for group_path, group in iter_groups(dataset):
        if old_name in group.variables:
            matches.append((group_path, old_name, new_name))
            if new_name in group.variables:
                collisions.append(group_path or "/")
    return matches, collisions


def default_output_path(input_path, new_name):
    """Construct a non-destructive default output filename."""
    suffix = input_path.suffix or ".nc"
    return input_path.with_name(f"{input_path.stem}.{new_name}{suffix}")


def parse_args():
    parser = argparse.ArgumentParser(
        description="Rename an IODA variable in every group where it exists."
    )
    parser.add_argument("input_file", type=Path, help="Input IODA NetCDF file")
    parser.add_argument("variable", help="Existing IODA base variable name")
    parser.add_argument("remapped_name", help="Replacement IODA base variable name")
    parser.add_argument(
        "--output",
        type=Path,
        help="Output file; defaults to <input-stem>.<remapped-name><suffix>",
    )
    parser.add_argument(
        "--in-place",
        action="store_true",
        help="Rename variables directly in the input file",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Allow overwriting an existing output file",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Report matching variables without modifying or copying a file",
    )
    return parser.parse_args()


def main():
    args = parse_args()

    if args.variable == args.remapped_name:
        raise ValueError("variable and remapped_name must be different")
    if not args.input_file.is_file():
        raise FileNotFoundError(f"input file does not exist: {args.input_file}")
    if args.in_place and args.output is not None:
        raise ValueError("--output cannot be combined with --in-place")

    try:
        from netCDF4 import Dataset
    except ImportError as exc:
        raise RuntimeError(
            "This tool requires the Python netCDF4 package"
        ) from exc

    with Dataset(args.input_file, "r") as dataset:
        matches, collisions = find_matches(
            dataset, args.variable, args.remapped_name
        )

    if not matches:
        raise ValueError(
            f"no variable named {args.variable!r} was found in {args.input_file}"
        )
    if collisions:
        locations = ", ".join(collisions)
        raise ValueError(
            f"destination variable {args.remapped_name!r} already exists in: "
            f"{locations}"
        )

    print("Variables to rename:")
    for group_path, old_name, new_name in matches:
        location = f"{group_path}/" if group_path else "/"
        print(f"  {location}{old_name} -> {location}{new_name}")

    if args.dry_run:
        return 0

    if args.in_place:
        output_file = args.input_file
    else:
        output_file = args.output or default_output_path(
            args.input_file, args.remapped_name
        )
        if output_file.exists() and not args.force:
            raise FileExistsError(
                f"output file already exists: {output_file}; use --force to replace it"
            )
        if output_file.resolve() == args.input_file.resolve():
            raise ValueError(
                "output resolves to the input file; use --in-place for direct modification"
            )
        shutil.copy2(args.input_file, output_file)

    try:
        with Dataset(output_file, "r+") as dataset:
            for group_path, old_name, new_name in matches:
                group = dataset
                for component in group_path.split("/") if group_path else []:
                    group = group.groups[component]
                group.renameVariable(old_name, new_name)
    except Exception:
        if not args.in_place and output_file.exists():
            output_file.unlink()
        raise

    print(f"Wrote renamed IODA file: {output_file}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (FileNotFoundError, FileExistsError, RuntimeError, ValueError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        sys.exit(2)
