#!/usr/bin/env python3
"""Compare application runtime and memory from paired conventional ObsSpace runs."""

import argparse
from pathlib import Path
import re
import sys


CASE_PREFIX = "rrfs_fv3jedi_2024052700_3dvar_conv_all_"
RUN_END = re.compile(
    r"OOPS_STATS Run end\s+- Runtime:\s*([0-9.]+)\s*sec,\s*"
    r"Memory: total:\s*([0-9.]+)\s*GB,\s*per task: min =\s*([0-9.]+)\s*GB,\s*"
    r"max =\s*([0-9.]+)\s*GB"
)


def read_metrics(build_dir, mode):
    """Read application timing from CTest's captured output, excluding queue wait."""
    logfile = build_dir / "Testing/Temporary/LastTest.log"
    if not logfile.is_file():
        raise ValueError(f"Missing CTest log: {logfile}")
    text = logfile.read_text(encoding="utf-8", errors="replace")
    test_name = CASE_PREFIX + mode
    starts = list(re.finditer(r"(?m)^\d+/\d+ Test: " + re.escape(test_name) + r"\s*$", text))
    if len(starts) != 1:
        raise ValueError(f"Expected one captured test section for {test_name} in {logfile}, found {len(starts)}")
    start = starts[0].end()
    following = re.search(r"(?m)^\d+/\d+ Testing:", text[start:])
    section = text[start:start + following.start()] if following else text[start:]
    matches = RUN_END.findall(section)
    if len(matches) != 1:
        raise ValueError(f"Expected one OOPS_STATS Run end record for {test_name} in {logfile}, found {len(matches)}")
    runtime, total_memory, min_memory, max_memory = map(float, matches[0])
    if runtime <= 0 or total_memory <= 0:
        raise ValueError(f"Invalid runtime or memory measurement in {logfile}")
    return {
        "mode": mode,
        "runtime": runtime,
        "total_memory": total_memory,
        "min_memory": min_memory,
        "max_memory": max_memory,
    }


def report(itemized, combined):
    """Print paired application measurements and runtime speedup."""
    for result in (itemized, combined):
        print(
            f"{result['mode']}: runtime={result['runtime']:.2f} s, "
            f"memory total={result['total_memory']:.2f} GB, "
            f"per-task min/max={result['min_memory']:.2f}/{result['max_memory']:.2f} GB"
        )
    speedup = itemized["runtime"] / combined["runtime"]
    reduction = 100.0 * (itemized["runtime"] - combined["runtime"]) / itemized["runtime"]
    memory_change = 100.0 * (combined["total_memory"] - itemized["total_memory"]) / itemized["total_memory"]
    print(f"Combined runtime speedup: {speedup:.2f}x ({reduction:.1f}% less application time)")
    print(f"Combined total-memory change: {memory_change:+.1f}%")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--build-dir",
        type=Path,
        default=Path(__file__).resolve().parents[2] / "build/rrfs-test",
        help="CTest build directory containing the two run directories",
    )
    args = parser.parse_args(argv)
    try:
        itemized = read_metrics(
            args.build_dir, "itemized"
        )
        combined = read_metrics(
            args.build_dir, "combined"
        )
    except (OSError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    report(itemized, combined)
    return 0


if __name__ == "__main__":
    sys.exit(main())
