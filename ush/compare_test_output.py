#!/usr/bin/env python3
"""Compare JEDI test output files with reference files.

Accounts for differences in the ordering of state variable entries between
.out files (which may be sorted alphabetically by a recent fv3-jedi update)
and .ref files (which may preserve the original unsorted order).

Tolerance defaults match JEDI's built-in comparison tools:
    test_float_relative_tolerance: 0.02
    test_float_absolute_tolerance: 1.0e-6
    test_integer_tolerance:        3

Usage:
    python compare_test_output.py [options]

By default, scans build/rrfs-test/rundir-*/*.out and matches each file
against the corresponding rrfs-test/testoutput/*.ref reference.
"""

import argparse
import glob
import os
import re
import sys

# ---------------------------------------------------------------------------
# Regular expressions for parsing
# ---------------------------------------------------------------------------

# FV3-JEDI state variable line:
#   "variable_name                  | Min:+val Max:+val RMS:+val"
_FV3JEDI_STATE_RE = re.compile(
    r'^\s*(\S+)\s*\|\s*'
    r'Min:([+-]?\d+\.\d+[eE][+-]\d+)\s+'
    r'Max:([+-]?\d+\.\d+[eE][+-]\d+)\s+'
    r'RMS:([+-]?\d+\.\d+[eE][+-]\d+)'
)

# FV3-JEDI state block header:
#   "State print | number of fields = N | ..."
_FV3JEDI_HEADER_RE = re.compile(r'^State print \| number of fields = \d+')

# MPAS-JEDI state variable line:
#   "Fld=N  Min=val, Max=val, RMS=val : variable_name"
_MPAS_STATE_RE = re.compile(
    r'^Fld=\d+\s+'
    r'Min=([+-]?\d+\.\d+[eE][+-]\d+),\s+'
    r'Max=([+-]?\d+\.\d+[eE][+-]\d+),\s+'
    r'RMS=([+-]?\d+\.\d+[eE][+-]\d+)\s+:\s+(\S+)'
)

# MPAS-JEDI state block header:
#   "  Resolution: nCellsGlobal = N, nFields = N"
_MPAS_HEADER_RE = re.compile(r'^\s+Resolution: nCellsGlobal = \d+')

# CostJo line:
#   "CostJo   : Nonlinear Jo(obs) = val, nobs = N, Jo/n = val, err = val"
_COSTJO_RE = re.compile(
    r'^CostJo\s+:\s+Nonlinear Jo\(([^)]+)\)\s*=\s*([+-]?[\d.]+(?:[eE][+-]?\d+)?)'
    r'(?:,\s*nobs\s*=\s*(\d+))?'
)

# CostFunction line:
#   "CostFunction: Nonlinear J = val"
_COSTFUNC_RE = re.compile(
    r'^CostFunction:\s+Nonlinear J\s*=\s*([+-]?[\d.]+(?:[eE][+-]?\d+)?)'
)

# DRPCGMinimizer line:
#   "DRPCGMinimizer: reduction in residual norm = val"
_DRPCG_RE = re.compile(
    r'^DRPCGMinimizer:\s+reduction in residual norm\s*=\s*([+-]?[\d.]+(?:[eE][+-]?\d+)?)'
)

# Norm line (MPAS bump):
#   "Norm of output parameter ... - 1: val"
_NORM_RE = re.compile(
    r'^Norm of output parameter ([^:]+):\s*([+-]?[\d.]+(?:[eE][+-]?\d+)?)'
)

# Separator line (FV3-JEDI blocks)
_SEPARATOR_RE = re.compile(r'^-{10,}')


# ---------------------------------------------------------------------------
# File parser
# ---------------------------------------------------------------------------

def parse_file(filepath):
    """Parse a test output or reference file.

    Returns a dict with keys:
        'costjo'       : list of (obs_name, jo_value, nobs_or_None)
        'costfunc'     : list of float (J values)
        'drpcg'        : list of float (residual norms)
        'norms'        : list of (param_name, norm_value)
        'state_blocks' : list of dict {var_name: (min_val, max_val, rms_val)}
    """
    costjo = []
    costfunc = []
    drpcg = []
    norms = []
    state_blocks = []
    current_block = None

    with open(filepath, 'r') as fh:
        for line in fh:
            line = line.rstrip('\n')

            # --- State block headers ---

            if _FV3JEDI_HEADER_RE.match(line):
                current_block = {}
                state_blocks.append(current_block)
                continue

            if _MPAS_HEADER_RE.match(line):
                current_block = {}
                state_blocks.append(current_block)
                continue

            # --- State variable lines ---

            m = _FV3JEDI_STATE_RE.match(line)
            if m and current_block is not None:
                var_name = m.group(1)
                current_block[var_name] = (
                    float(m.group(2)),
                    float(m.group(3)),
                    float(m.group(4)),
                )
                continue

            m = _MPAS_STATE_RE.match(line)
            if m and current_block is not None:
                var_name = m.group(4)
                current_block[var_name] = (
                    float(m.group(1)),
                    float(m.group(2)),
                    float(m.group(3)),
                )
                continue

            # Separator ends the current FV3-JEDI state block
            if _SEPARATOR_RE.match(line):
                current_block = None
                continue

            # --- Scalar metric lines (outside state blocks) ---

            m = _COSTJO_RE.match(line)
            if m:
                nobs = int(m.group(3)) if m.group(3) is not None else None
                costjo.append((m.group(1), float(m.group(2)), nobs))
                continue

            m = _COSTFUNC_RE.match(line)
            if m:
                costfunc.append(float(m.group(1)))
                continue

            m = _DRPCG_RE.match(line)
            if m:
                drpcg.append(float(m.group(1)))
                continue

            m = _NORM_RE.match(line)
            if m:
                norms.append((m.group(1).strip(), float(m.group(2))))
                continue

    return {
        'costjo': costjo,
        'costfunc': costfunc,
        'drpcg': drpcg,
        'norms': norms,
        'state_blocks': state_blocks,
    }


# ---------------------------------------------------------------------------
# Comparison helpers
# ---------------------------------------------------------------------------

def _float_close(a, b, rtol, atol):
    """Return True if floats a and b agree within relative or absolute tolerance."""
    if a == 0.0 and b == 0.0:
        return True
    return abs(a - b) <= atol + rtol * max(abs(a), abs(b))


def _int_close(a, b, itol):
    """Return True if integers a and b agree within integer tolerance."""
    return abs(a - b) <= itol


def compare_scalar_lists(name, out_list, ref_list, rtol, atol, errors):
    """Compare two ordered lists of scalar floats."""
    if len(out_list) != len(ref_list):
        errors.append(
            f"  {name}: count mismatch – out has {len(out_list)}, "
            f"ref has {len(ref_list)}"
        )
        # Compare as many as possible
        n = min(len(out_list), len(ref_list))
    else:
        n = len(out_list)

    for i in range(n):
        if not _float_close(out_list[i], ref_list[i], rtol, atol):
            errors.append(
                f"  {name}[{i}]: out={out_list[i]:.15e}  "
                f"ref={ref_list[i]:.15e}"
            )


def compare_costjo(out_entries, ref_entries, rtol, atol, itol, errors):
    """Compare CostJo entries, grouped by obs name."""
    # Build ordered lists per obs name so multiple iterations are preserved
    from collections import defaultdict
    out_by_obs = defaultdict(list)
    ref_by_obs = defaultdict(list)
    for obs, val, nobs in out_entries:
        out_by_obs[obs].append((val, nobs))
    for obs, val, nobs in ref_entries:
        ref_by_obs[obs].append((val, nobs))

    all_obs = sorted(set(list(out_by_obs.keys()) + list(ref_by_obs.keys())))
    for obs in all_obs:
        if obs not in ref_by_obs:
            errors.append(f"  CostJo({obs}): present in out but not in ref")
            continue
        if obs not in out_by_obs:
            errors.append(f"  CostJo({obs}): present in ref but not in out")
            continue
        out_vals = out_by_obs[obs]
        ref_vals = ref_by_obs[obs]
        if len(out_vals) != len(ref_vals):
            errors.append(
                f"  CostJo({obs}): count mismatch – out has {len(out_vals)}, "
                f"ref has {len(ref_vals)}"
            )
        for i, ((o_jo, o_nobs), (r_jo, r_nobs)) in enumerate(
                zip(out_vals, ref_vals)):
            if not _float_close(o_jo, r_jo, rtol, atol):
                errors.append(
                    f"  CostJo({obs})[{i}]: "
                    f"out={o_jo:.15e}  ref={r_jo:.15e}"
                )
            if o_nobs is not None and r_nobs is not None:
                if not _int_close(o_nobs, r_nobs, itol):
                    errors.append(
                        f"  CostJo({obs})[{i}] nobs: "
                        f"out={o_nobs}  ref={r_nobs}"
                    )


def compare_norms(out_norms, ref_norms, rtol, atol, errors):
    """Compare norm entries by parameter name."""
    from collections import defaultdict
    out_by_param = defaultdict(list)
    ref_by_param = defaultdict(list)
    for param, val in out_norms:
        out_by_param[param].append(val)
    for param, val in ref_norms:
        ref_by_param[param].append(val)

    all_params = sorted(set(list(out_by_param.keys()) + list(ref_by_param.keys())))
    for param in all_params:
        if param not in ref_by_param:
            errors.append(f"  Norm({param}): present in out but not in ref")
            continue
        if param not in out_by_param:
            errors.append(f"  Norm({param}): present in ref but not in out")
            continue
        compare_scalar_lists(
            f"Norm({param})",
            out_by_param[param],
            ref_by_param[param],
            rtol,
            atol,
            errors,
        )


def compare_state_block(block_idx, out_block, ref_block, rtol, atol, errors):
    """Compare two state variable blocks (order-agnostic)."""
    out_vars = set(out_block.keys())
    ref_vars = set(ref_block.keys())

    for var in sorted(ref_vars - out_vars):
        errors.append(
            f"  state_block[{block_idx}] variable '{var}': in ref but not in out"
        )
    for var in sorted(out_vars - ref_vars):
        errors.append(
            f"  state_block[{block_idx}] variable '{var}': in out but not in ref"
        )

    for var in sorted(out_vars & ref_vars):
        out_min, out_max, out_rms = out_block[var]
        ref_min, ref_max, ref_rms = ref_block[var]
        mismatches = []
        if not _float_close(out_min, ref_min, rtol, atol):
            mismatches.append(
                f"Min out={out_min:.15e} ref={ref_min:.15e}"
            )
        if not _float_close(out_max, ref_max, rtol, atol):
            mismatches.append(
                f"Max out={out_max:.15e} ref={ref_max:.15e}"
            )
        if not _float_close(out_rms, ref_rms, rtol, atol):
            mismatches.append(
                f"RMS out={out_rms:.15e} ref={ref_rms:.15e}"
            )
        if mismatches:
            errors.append(
                "  state_block[{}] '{}': {}".format(
                    block_idx, var, ", ".join(mismatches))
            )


# ---------------------------------------------------------------------------
# High-level comparison
# ---------------------------------------------------------------------------

def compare_files(out_path, ref_path, rtol, atol, itol):
    """Compare a single output file against its reference.

    Returns (passed: bool, messages: list[str]).
    """
    errors = []

    out_data = parse_file(out_path)
    ref_data = parse_file(ref_path)

    # CostJo
    compare_costjo(out_data['costjo'], ref_data['costjo'], rtol, atol, itol, errors)

    # CostFunction J values
    compare_scalar_lists(
        'CostFunction J',
        out_data['costfunc'],
        ref_data['costfunc'],
        rtol,
        atol,
        errors,
    )

    # DRPCGMinimizer residuals
    compare_scalar_lists(
        'DRPCGMinimizer residual',
        out_data['drpcg'],
        ref_data['drpcg'],
        rtol,
        atol,
        errors,
    )

    # Norm lines (MPAS bump)
    compare_norms(out_data['norms'], ref_data['norms'], rtol, atol, errors)

    # State variable blocks
    n_out = len(out_data['state_blocks'])
    n_ref = len(ref_data['state_blocks'])
    if n_out != n_ref:
        errors.append(
            f"  state_blocks: count mismatch – out has {n_out}, "
            f"ref has {n_ref}"
        )
    for i in range(min(n_out, n_ref)):
        compare_state_block(
            i,
            out_data['state_blocks'][i],
            ref_data['state_blocks'][i],
            rtol,
            atol,
            errors,
        )

    passed = len(errors) == 0
    return passed, errors


# ---------------------------------------------------------------------------
# File discovery
# ---------------------------------------------------------------------------

def find_output_files(build_dir):
    """Return rrfs-*.out file paths found under build_dir/rrfs-test/rundir-*/.

    Only files whose basename starts with 'rrfs-' are returned so that
    ancillary logs (e.g. warnfile.*.out, logfile.*.out,
    log.atmosphere.*.out) are automatically excluded.
    """
    pattern = os.path.join(build_dir, 'rrfs-test', 'rundir-*', 'rrfs-*.out')
    return sorted(glob.glob(pattern))


def find_ref_file(out_path, ref_dir):
    """Return the path of the reference file matching out_path, or None."""
    basename = os.path.basename(out_path)
    stem, _ = os.path.splitext(basename)
    ref_path = os.path.join(ref_dir, stem + '.ref')
    return ref_path if os.path.isfile(ref_path) else None


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def parse_args(argv=None):
    try:
        _script_dir = os.path.dirname(os.path.abspath(__file__))
        rdas_root = os.path.normpath(os.path.join(_script_dir, '..'))
    except NameError:
        rdas_root = os.path.normpath(os.path.join(os.getcwd(), '..'))

    parser = argparse.ArgumentParser(
        description='Compare JEDI test outputs with reference files.',
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        '--build-dir',
        default=os.path.join(rdas_root, 'build'),
        help='Root build directory',
    )
    parser.add_argument(
        '--ref-dir',
        default=os.path.join(rdas_root, 'rrfs-test', 'testoutput'),
        help='Directory containing .ref reference files',
    )
    parser.add_argument(
        '--float-relative-tolerance',
        type=float,
        default=0.02,
        help='Relative tolerance for floating-point comparisons',
    )
    parser.add_argument(
        '--float-absolute-tolerance',
        type=float,
        default=1.0e-6,
        help='Absolute tolerance for floating-point comparisons',
    )
    parser.add_argument(
        '--integer-tolerance',
        type=int,
        default=3,
        help='Tolerance for integer comparisons (e.g. nobs)',
    )
    parser.add_argument(
        '--out-files',
        nargs='+',
        metavar='FILE',
        help='Compare specific .out file(s) instead of scanning build-dir',
    )
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)

    if args.out_files:
        out_files = args.out_files
    else:
        out_files = find_output_files(args.build_dir)
        if not out_files:
            print(
                f"No .out files found under "
                f"{os.path.join(args.build_dir, 'rrfs-test', 'rundir-*')}",
                file=sys.stderr,
            )
            return 1

    n_pass = 0
    n_fail = 0
    n_skip = 0

    for out_path in out_files:
        ref_path = find_ref_file(out_path, args.ref_dir)
        if ref_path is None:
            basename = os.path.basename(out_path)
            stem = os.path.splitext(basename)[0]
            print(f"SKIP  {basename}  (no matching {stem}.ref in {args.ref_dir})")
            n_skip += 1
            continue

        passed, errors = compare_files(
            out_path, ref_path,
            args.float_relative_tolerance,
            args.float_absolute_tolerance,
            args.integer_tolerance,
        )

        label = os.path.basename(out_path)
        if passed:
            print(f"PASS  {label}")
            n_pass += 1
        else:
            print(f"FAIL  {label}")
            for msg in errors:
                print(msg)
            n_fail += 1

    print()
    print(f"Results: {n_pass} passed, {n_fail} failed, {n_skip} skipped")

    return 0 if n_fail == 0 else 1


if __name__ == '__main__':
    sys.exit(main())
