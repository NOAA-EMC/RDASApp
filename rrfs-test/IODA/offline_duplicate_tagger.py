import netCDF4 as nc
import numpy as np
import os

# Default settings
DEFAULT_ID_FIELDS = ('dateTime', 'longitude_latitude_pressure')
DEFAULT_TAG_NAME = 'usedPreviously'
DEFAULT_FILL_VALUE = -1


def tag_previous_observations(current_filepath, previous_filepaths, output_filepath=None,
                               id_fields=DEFAULT_ID_FIELDS,
                               tag_name=DEFAULT_TAG_NAME,
                               fill_value=DEFAULT_FILL_VALUE):
    """
    Reads the current IODA file and one or more previous IODA files,
    tags observations in the current file that appear in any previous files.

    Args:
        current_filepath (str): Path to the current cycle's IODA .nc file.
        previous_filepaths (list of str): Paths to previous cycles' IODA .nc files.
        output_filepath (str, optional): Where to write the tagged IODA file.
            If None, will overwrite current_filepath.
        id_fields (tuple of str): MetaData field names to use as a composite key.
        tag_name (str): Name of the new MetaData variable to create (integer: 0/1).
        fill_value (int): Value to use for missing/uninitialized entries.
    """
    if output_filepath is None:
        output_filepath = current_filepath
    else:
        import shutil
        shutil.copy(current_filepath, output_filepath)

    prev_keys = set()
    valid_prev_paths = [p for p in previous_filepaths if os.path.exists(p)]

    if not valid_prev_paths:
        print("No valid previous files found. All observations will be considered new.")
    else:
        for p in previous_filepaths:
            if not os.path.exists(p):
                print(f"Warning: Previous file not found and will be skipped: {p}")

        for prev_path in valid_prev_paths:
            with nc.Dataset(prev_path) as prev_ds:
                meta = prev_ds['MetaData']
                values = []
                for field in id_fields:
                    arr = meta[field][:]
                    if arr.dtype.kind in ('S', 'U'):
                        arr = np.array([s.tobytes().decode('utf-8').strip() for s in arr])
                    values.append(arr.astype(str))
                combined = np.char.add(values[0], np.char.add('_', values[1]))
                prev_keys.update(combined.tolist())

    with nc.Dataset(output_filepath, 'r+') as cur_ds:
        grp = cur_ds.groups['MetaData']
        if tag_name in grp.variables:
            tag_var = grp.variables[tag_name]
        else:
            tag_var = grp.createVariable(tag_name, 'i4', ('Location',), fill_value=fill_value)
            tag_var.long_name = "Observation used previously"
            tag_var.units = f"1=used before, 0=new, {fill_value}=missing"

        cur_meta = grp
        cur_values = []
        for field in id_fields:
            arr = cur_meta[field][:]
            if arr.dtype.kind in ('S', 'U'):
                arr = np.array([s.tobytes().decode('utf-8').strip() for s in arr])
            cur_values.append(arr.astype(str))
        current_keys = np.char.add(cur_values[0], np.char.add('_', cur_values[1]))

        flags = np.full(current_keys.shape, fill_value, dtype=np.int32)
        if not prev_keys:
            flags[:] = 0  # No previous keys, mark everything as new
        else:
            for i, key in enumerate(current_keys):
                flags[i] = 1 if key in prev_keys else 0
        tag_var[:] = flags

    print(f"Tagged observations saved to: {output_filepath}")


def verify_tagging(current_filepath, tagged_filepath=None,
                   id_fields=DEFAULT_ID_FIELDS,
                   tag_name=DEFAULT_TAG_NAME, sample_size=5):
    """
    Verifies tagging by comparing raw composite keys and tag variable.

    Args:
        current_filepath (str): Path to the original current-cycle .nc file.
        tagged_filepath (str, optional): Path to the tagged .nc file.
        id_fields (tuple of str): Fields used for composite key. Must match tagging.
        tag_name (str): Name of the tagging variable.
        sample_size (int): Number of sample entries to display.
    """
    if tagged_filepath is None:
        tagged_filepath = current_filepath

    with nc.Dataset(current_filepath) as orig_ds:
        orig_meta = orig_ds['MetaData']
        values = []
        for field in id_fields:
            arr = orig_meta[field][:]
            if arr.dtype.kind in ('S', 'U'):
                arr = np.array([s.tobytes().decode('utf-8').strip() for s in arr])
            values.append(arr.astype(str))
        keys = np.char.add(values[0], np.char.add('_', values[1]))

    with nc.Dataset(tagged_filepath) as tag_ds:
        tag_var = tag_ds['MetaData'].variables[tag_name][:]

    total = len(keys)
    reused = np.sum(tag_var == 1)
    new = np.sum(tag_var == 0)
    missing = np.sum(tag_var == DEFAULT_FILL_VALUE)

    print(f"Total observations: {total}")
    print(f"Reused (tag=1): {reused} ({reused/total:.1%})")
    print(f"New    (tag=0): {new} ({new/total:.1%})\n")

    reused_indices = np.where(tag_var == 1)[0]
    new_indices = np.where(tag_var == 0)[0]
    missing_indices = np.where(tag_var == DEFAULT_FILL_VALUE)[0]

    if sample_size > 0:
        print("Sample reused observations:")
        for idx in reused_indices[:sample_size]:
            print(f"  idx={idx}, key={keys[idx]}")
        print("\nSample new observations:")
        for idx in new_indices[:sample_size]:
            print(f"  idx={idx}, key={keys[idx]}")
        print("\nSample missing observations:")
        for idx in missing_indices[:sample_size]:
            print(f"  idx={idx}, key={keys[idx]}")


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(
        description='Tag observations in current IODA file and optionally verify tagging.')
    subparsers = parser.add_subparsers(dest='cmd')

    tag_parser = subparsers.add_parser('tag', help='Run tagging')
    tag_parser.add_argument('current', help='Current cycle IODA .nc file')
    tag_parser.add_argument('-p', '--previous', nargs='+', required=True,
                            help='Previous cycle IODA .nc files')
    tag_parser.add_argument('-o', '--output', default=None,
                            help='Output file path')
    tag_parser.add_argument('--id-fields', nargs=2,
                            default=list(DEFAULT_ID_FIELDS),
                            help='MetaData fields for composite key')
    tag_parser.add_argument('--tag-name', default=DEFAULT_TAG_NAME,
                            help='Name of tagging variable')
    tag_parser.add_argument('--fill-value', type=int, default=DEFAULT_FILL_VALUE,
                            help='Fill value for missing entries')

    verify_parser = subparsers.add_parser('verify', help='Verify tagging results')
    verify_parser.add_argument('current', help='Original current IODA .nc file')
    verify_parser.add_argument('-t', '--tagged', default=None,
                               help='Tagged .nc file to verify')
    verify_parser.add_argument('--id-fields', nargs=2,
                               default=list(DEFAULT_ID_FIELDS),
                               help='MetaData fields for composite key')
    verify_parser.add_argument('--tag-name', default=DEFAULT_TAG_NAME,
                               help='Name of tagging variable')
    verify_parser.add_argument('-n', '--sample-size', type=int, default=5,
                               help='Number of sample entries to show')

    args = parser.parse_args()
    if args.cmd == 'tag':
        tag_previous_observations(args.current, args.previous,
                                   args.output, tuple(args.id_fields),
                                   args.tag_name, args.fill_value)
    elif args.cmd == 'verify':
        verify_tagging(args.current, args.tagged,
                       tuple(args.id_fields), args.tag_name, args.sample_size)
    else:
        parser.print_help()
