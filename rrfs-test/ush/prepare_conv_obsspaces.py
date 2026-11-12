#!/usr/bin/env python3
"""Stage the paired conventional JCB configs and privately generated combined templates."""

import argparse
from pathlib import Path
import runpy
import sys

import yaml


CASE_PREFIX = "rrfs_fv3jedi_2024052700_3dvar_conv_all_"


def prepare(rdas_root, output_dir):
    """Generate derived test inputs without touching the observation template directory."""
    rdas_root = rdas_root.resolve()
    output_dir = output_dir.resolve()
    ci = rdas_root / "parm/jcb-rdas/test/ci"
    obs_dir = rdas_root / "parm/jcb-rdas/observations/atmosphere"
    configs = {}
    for mode in ("itemized", "combined"):
        path = ci / ("jcb-" + CASE_PREFIX + mode + ".yaml")
        with path.open() as stream:
            configs[mode] = yaml.safe_load(stream)
    streams = configs["itemized"]["observations"]
    families = sorted({name.split("_", 1)[0] for name in streams})
    if len(streams) != 48 or len(set(streams)) != 48 or len(families) != 9:
        raise ValueError("The itemized case must name 48 distinct streams in nine families")
    if configs["combined"]["observations"] != families:
        raise ValueError("The combined case must name the same nine families")
    private_dir = output_dir / "jcb-conv-combined-observations"
    if private_dir.is_symlink():
        raise ValueError("Refusing to overwrite combined templates through a directory symlink")
    combiner = runpy.run_path(str(obs_dir / "tools/combine_obs_spaces.py"))
    generated = {}
    for family in families:
        inputs = [obs_dir / (name + ".yaml.j2") for name in streams if name.startswith(family + "_")]
        output = private_dir / (family + ".yaml.j2")
        combined, warnings, spaces, statistics = combiner["build_combined_yaml"](
            inputs, output.name, "split"
        )
        if not spaces or warnings:
            raise ValueError(f"{family}: combined ObsSpace generation failed")
        generated[output] = combined
    for mode, config in configs.items():
        # Absolute paths make staging independent of registered JCB clients and the caller's cwd.
        config["app_path_algorithm"] = str(rdas_root / "parm/jcb-algorithms")
        config["app_path_model"] = str(rdas_root / "parm/jcb-rdas/model/fv3/atmosphere")
        config["app_path_observation_chronicle"] = str(
            rdas_root / "parm/jcb-rdas/observation_chronicle/atmosphere"
        )
        config["app_path_observations"] = str(obs_dir if mode == "itemized" else private_dir)
        for key in ("mesonet_gsd_sfcobs_uselist", "mesonet_gsd_sfcobs_provider"):
            provider_path = Path(config[key])
            if not provider_path.is_absolute():
                provider_path = rdas_root / "rrfs-test/testinput" / provider_path
            if not provider_path.is_file():
                raise ValueError(f"Missing mesonet use-list input: {provider_path}")
            config[key] = str(provider_path)
        generated[output_dir / ("jcb-" + CASE_PREFIX + mode + ".yaml")] = yaml.safe_dump(
            config, sort_keys=False
        )
    # Staged outputs must never redirect writes into source templates or configurations.
    for path in generated:
        if path.is_symlink():
            raise ValueError(f"Refusing to overwrite a staged file symlink: {path}")
    # Complete all parsing and combination checks before creating or replacing staged files.
    private_dir.mkdir(parents=True, exist_ok=True)
    for path, contents in generated.items():
        path.write_text(contents, encoding="ascii")
    print(f"Staged nine combined templates in {private_dir}")
    for mode in ("itemized", "combined"):
        print(output_dir / ("jcb-" + CASE_PREFIX + mode + ".yaml"))
    return tuple(generated)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rdas-root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--output-dir", type=Path)
    args = parser.parse_args(argv)
    output_dir = args.output_dir or args.rdas_root / "rrfs-test/testinput"
    try:
        prepare(args.rdas_root, output_dir)
    except (OSError, ValueError, KeyError, TypeError) as error:
        print("ERROR:", error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
