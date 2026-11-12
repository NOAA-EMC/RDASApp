#!/usr/bin/env python3
"""Compare full conventional 3D-Var runs using source observation identities."""

import argparse
import copy
from dataclasses import dataclass
import math
from pathlib import Path
import sys

import numpy as np
from netCDF4 import Dataset
import yaml


CASE_PREFIX = "rrfs_fv3jedi_2024052700_3dvar_conv_all_"
FAMILIES = {"adpsfc", "adpupa", "aircar", "aircft", "msonet", "proflr", "rassda", "sfcshp", "vadwnd"}
# Absolute floors reflect the units and float32 precision of IODA diagnostics.
ABSOLUTE_TOLERANCES = {
    "airTemperature": 1.0e-4,
    "airTemperatureAt2M": 1.0e-4,
    "specificHumidity": 1.0e-8,
    "specificHumidityAt2M": 1.0e-8,
    "stationPressure": 1.0e-2,
    "windEastward": 1.0e-5,
    "windNorthward": 1.0e-5,
}


class ComparisonError(ValueError):
    """A missing or ambiguous input prevents a meaningful comparison."""


@dataclass
class RunData:
    configuration: dict
    sources: dict
    records: dict
    costs: dict
    iterations: tuple


def read_array(dataset, group, variable, count):
    """Require one diagnostic value per original source location."""
    if group not in dataset.groups or variable not in dataset[group].variables:
        raise ComparisonError(f"{dataset.filepath()}: missing {group}/{variable}")
    values = dataset[group][variable][:]
    if values.shape != (count,):
        raise ComparisonError(f"{dataset.filepath()}: {group}/{variable} is not a location vector")
    return values


def number(value):
    """Keep missingness distinct from every valid numeric value, including zero."""
    if np.ma.is_masked(value):
        return None
    result = float(value)
    if not math.isfinite(result):
        raise ComparisonError("A usable observation contains a nonfinite diagnostic")
    return result


def load_run(directory, mode):
    """Read declared outputs rather than guessing variables from diagnostic filenames."""
    config_path = directory / (CASE_PREFIX + mode + ".yaml")
    with config_path.open() as stream:
        configuration = yaml.safe_load(stream)
    observers = configuration["cost function"]["observations"]["observers"]
    if mode == "itemized" and len(observers) != 48:
        raise ComparisonError(f"{config_path}: expected 48 itemized ObsSpaces, found {len(observers)}")
    if mode == "combined" and len(observers) < len(FAMILIES):
        raise ComparisonError(f"{config_path}: expected at least {len(FAMILIES)} combined ObsSpaces")
    outer_loops = len(configuration["variational"]["iterations"])
    if outer_loops != 2:
        raise ComparisonError(f"{config_path}: the equivalence case requires two outer loops")
    iterations = tuple(range(outer_loops + 1))
    records, sources, outputs = {}, {}, set()
    source_sizes = {}
    families = set()
    cost_terms = {iteration: [] for iteration in iterations}
    for observer in observers:
        space = observer["obs space"]
        family = space["name"].split("_", 1)[0]
        if family not in FAMILIES:
            raise ComparisonError(f"Unexpected conventional family: {family}")
        families.add(family)
        input_path = (directory / space["obsdatain"]["engine"]["obsfile"]).resolve()
        if not input_path.is_file():
            raise ComparisonError(f"Missing observation input: {input_path}")
        if family in sources and sources[family] != input_path:
            raise ComparisonError(f"{family}: one family refers to multiple observation inputs")
        if family not in source_sizes:
            with Dataset(input_path) as input_dataset:
                if "Location" not in input_dataset.dimensions:
                    raise ComparisonError(f"{input_path}: missing input Location dimension")
                source_sizes[family] = len(input_dataset.dimensions["Location"])
            if source_sizes[family] == 0:
                raise ComparisonError(f"{input_path}: empty input does not exercise {family}")
        sources[family] = input_path
        output_path = directory / space["obsdataout"]["engine"]["obsfile"]
        if output_path in outputs:
            raise ComparisonError(f"Repeated diagnostic output: {output_path}")
        outputs.add(output_path)
        if not output_path.is_file():
            raise ComparisonError(f"Missing diagnostic output: {output_path}")
        with Dataset(output_path) as dataset:
            if "Location" not in dataset.variables:
                raise ComparisonError(f"{output_path}: missing original source Location indices")
            locations = dataset["Location"][:]
            if np.ma.getmaskarray(locations).any():
                raise ComparisonError(f"{output_path}: invalid source Location indices")
            # Empty masked arrays have masked reductions; validate their plain data instead.
            locations = np.ma.getdata(locations)
            if not np.isfinite(locations).all():
                raise ComparisonError(f"{output_path}: invalid source Location indices")
            if not np.equal(locations, locations.astype(np.int64)).all():
                raise ComparisonError(f"{output_path}: source Location indices are not integers")
            if len(np.unique(locations)) != len(locations):
                raise ComparisonError(f"{output_path}: duplicate source Location indices")
            if (locations < 0).any() or (locations >= source_sizes[family]).any():
                raise ComparisonError(f"{output_path}: Location indices lie outside the input file")
            count = len(locations)
            for variable in space["simulated variables"]:
                types = read_array(dataset, "ObsType", variable, count)
                raw = read_array(dataset, "ObsValue", variable, count)
                group = "DerivedObsValue" if (
                    "DerivedObsValue" in dataset.groups
                    and variable in dataset["DerivedObsValue"].variables
                ) else "ObsValue"
                observed = read_array(dataset, group, variable, count)
                for iteration in iterations:
                    qc = read_array(dataset, f"EffectiveQC{iteration}", variable, count)
                    errors = read_array(dataset, f"EffectiveError{iteration}", variable, count)
                    hofx = read_array(dataset, f"hofx{iteration}", variable, count)
                    bias = read_array(dataset, f"ObsBias{iteration}", variable, count)
                    if iteration == 0:
                        departure_group = "ombg"
                    elif iteration == outer_loops:
                        departure_group = "oman"
                    else:
                        departure_group = f"innov{iteration}"
                    departures = read_array(dataset, departure_group, variable, count)
                    # Removed or rejected rows may differ between layouts. Usable identities must agree.
                    usable = np.flatnonzero(np.isin(np.ma.filled(qc, -1), [0, 1]))
                    for row in usable:
                        if np.ma.is_masked(types[row]):
                            raise ComparisonError(f"{output_path}: usable {variable} has no ObsType")
                        key = (iteration, family, variable, int(types[row]), int(locations[row]))
                        if key in records:
                            raise ComparisonError(f"Duplicate usable observation identity: {key}")
                        values = {
                            "observation": number(observed[row]),
                            "raw observation": number(raw[row]),
                            "error": number(errors[row]),
                            "hofx": number(hofx[row]),
                            "bias": number(bias[row]),
                            "departure": number(departures[row]),
                        }
                        if any(values[name] is None for name in ("observation", "hofx", "bias", "departure")):
                            raise ComparisonError(f"{key}: usable observation has missing values")
                        flag = int(qc[row])
                        records[key] = (flag, values)
                        if flag == 0:
                            if values["error"] is None or values["error"] <= 0:
                                raise ComparisonError(f"{key}: accepted observation has no positive error")
                            # Saved departures retain the actual outer-loop innovation used by JEDI.
                            residual = values["departure"]
                            cost_terms[iteration].append(0.5 * (residual / values["error"]) ** 2)
    if families != FAMILIES:
        raise ComparisonError(f"Missing conventional families: {sorted(FAMILIES - families)}")
    if not records or not any(flag == 0 for flag, values in records.values()):
        raise ComparisonError(f"{directory}: no accepted observations; refusing a vacuous comparison")
    costs = {iteration: math.fsum(terms) for iteration, terms in cost_terms.items()}
    return RunData(configuration, sources, records, costs, iterations)


def configuration_without_observers(configuration):
    """The pair may differ only in its observer definitions."""
    result = copy.deepcopy(configuration)
    result["cost function"]["observations"]["observers"] = []
    return result


def compare_observations(itemized, combined, rtol, atol):
    """Compare usable identities exactly, then their QC states and numeric diagnostics."""
    left_configuration = configuration_without_observers(itemized.configuration)
    right_configuration = configuration_without_observers(combined.configuration)
    if left_configuration != right_configuration:
        raise ComparisonError("Run settings outside the observers differ")
    if itemized.sources != combined.sources:
        raise ComparisonError("The runs do not read identical observation source files")
    missing = itemized.records.keys() - combined.records.keys()
    extra = combined.records.keys() - itemized.records.keys()
    problems = []
    if missing or extra:
        problems.append(
            f"Usable identities differ: {len(missing)} missing, {len(extra)} extra; "
            f"examples: {sorted(missing)[:3]}, {sorted(extra)[:3]}"
        )
    differences = 0
    for key in itemized.records.keys() & combined.records.keys():
        left_flag, left = itemized.records[key]
        right_flag, right = combined.records[key]
        if left_flag != right_flag:
            differences += 1
            if len(problems) < 12:
                problems.append(f"{key}: QC status differs: {left_flag} vs {right_flag}")
        tolerance = atol if atol is not None else ABSOLUTE_TOLERANCES[key[2]]
        for field, value in left.items():
            other = right[field]
            equal = value is None and other is None
            if value is not None and other is not None:
                equal = math.isclose(value, other, rel_tol=rtol, abs_tol=tolerance)
            if not equal:
                differences += 1
                if len(problems) < 12:
                    problems.append(f"{key}: {field} differs: {value} vs {other}")
    if differences:
        problems.append(f"Total QC/numeric diagnostic differences: {differences}")
    for iteration in itemized.iterations:
        left, right = itemized.costs[iteration], combined.costs[iteration]
        # This is the diagonal Jo reconstructed from saved diagnostics, not a text-log comparison.
        if not math.isclose(left, right, rel_tol=rtol, abs_tol=1.0e-8):
            problems.append(f"Iteration {iteration}: diagnostic Jo differs: {left} vs {right}")
        print(f"Iteration {iteration}: diagnostic Jo itemized={left:.12g}, combined={right:.12g}")
        for family in sorted(FAMILIES):
            count = sum(key[0] == iteration and key[1] == family for key in itemized.records)
            print(f"  {family}: {count} usable variable/location pairs")
    return problems


def compare_increments(itemized_dir, combined_dir, rtol, atol):
    """Bound the L2 norm of the field difference, rather than comparing norms alone."""
    left_files = {path.name: path for path in itemized_dir.glob("inc_jedi.*.nc")}
    right_files = {path.name: path for path in combined_dir.glob("inc_jedi.*.nc")}
    if not left_files or left_files.keys() != right_files.keys():
        raise ComparisonError("Final increment files are absent or their filenames differ")
    problems, fields = [], 0
    for name in sorted(left_files):
        with Dataset(left_files[name]) as left, Dataset(right_files[name]) as right:
            left_names = {
                key for key, value in left.variables.items()
                if key not in left.dimensions and key != "Time"
                and np.dtype(value.dtype).kind in "fiu"
            }
            right_names = {
                key for key, value in right.variables.items()
                if key not in right.dimensions and key != "Time"
                and np.dtype(value.dtype).kind in "fiu"
            }
            if left_names != right_names:
                raise ComparisonError(f"{name}: increment fields differ")
            for field in sorted(left_names):
                first, second = left[field][:], right[field][:]
                same_mask = np.array_equal(np.ma.getmaskarray(first), np.ma.getmaskarray(second))
                if first.shape != second.shape or not same_mask:
                    raise ComparisonError(f"{name}/{field}: increment shapes or missingness differ")
                first = np.ma.asarray(first, dtype=np.float64).compressed()
                second = np.ma.asarray(second, dtype=np.float64).compressed()
                if not first.size or not np.isfinite(first).all() or not np.isfinite(second).all():
                    raise ComparisonError(f"{name}/{field}: empty or nonfinite increment")
                reference = float(np.linalg.norm(first))
                difference = float(np.linalg.norm(first - second))
                limit = rtol * reference + atol * math.sqrt(first.size)
                if difference > limit:
                    problems.append(f"{name}/{field}: difference norm {difference:.12g} exceeds {limit:.12g}")
                print(f"Increment {name}/{field}: reference L2={reference:.12g}, difference L2={difference:.12g}")
                fields += 1
    if not fields:
        raise ComparisonError("No final increment fields were compared")
    return problems


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--itemized-dir", type=Path, required=True)
    parser.add_argument("--combined-dir", type=Path, required=True)
    parser.add_argument("--rtol", type=float, default=1.0e-6)
    parser.add_argument("--atol", type=float, default=None, help="Override variable-specific absolute tolerances")
    parser.add_argument("--increment-rtol", type=float, default=1.0e-5)
    parser.add_argument("--increment-atol", type=float, default=1.0e-10)
    args = parser.parse_args(argv)
    tolerances = [args.rtol, args.increment_rtol, args.increment_atol]
    if args.atol is not None:
        tolerances.append(args.atol)
    if any(value < 0 or not math.isfinite(value) for value in tolerances):
        parser.error("Tolerances must be finite and nonnegative")
    try:
        itemized = load_run(args.itemized_dir, "itemized")
        combined = load_run(args.combined_dir, "combined")
        problems = compare_observations(itemized, combined, args.rtol, args.atol)
        problems.extend(compare_increments(
            args.itemized_dir, args.combined_dir, args.increment_rtol, args.increment_atol
        ))
        if problems:
            for problem in problems:
                print("FAIL:", problem)
            return 1
    except (ComparisonError, OSError, KeyError, TypeError, ValueError) as error:
        print("FAIL:", error)
        return 1
    print("PASS: itemized and combined conventional diagnostics and final increments agree")
    return 0


if __name__ == "__main__":
    sys.exit(main())
