# rrfs-test-na3km

Optional ctest that runs the RRFS analysis at full capability: the full RRFS NA 3 km
domain (C3463, 40x40 layout, 1600 MPI tasks) with the conventional and satellite-wind
observations used by the RRFS baseline005 retros, for 2024-05-27 00Z. It writes
increments (`inc_jedi.*`) and leaves the backgrounds untouched.

It is not part of CI. It is only added when RDASApp is configured with
`-DBUILD_RRFS_TEST_NA3KM=ON`, and only on wcoss2 and ursa.

## Stage the case

The backgrounds, ensemble and grid files are symlinked, not copied. Only the obs are
written, after a domain check against the NA 3 km grid.

```
source ush/load_rdas.sh   # or module load RDAS/<machine>.intel
module load py-shapely py-cartopy
rrfs-test-na3km/scripts/stage_na3km_case.sh <download_dir> <case_dir>
```

`<download_dir>` holds the RRFSv1 2024052700 restarts: `fcst_fv3lam/INPUT` for the
control and `memNNNN/fcst_fv3lam/DA_OUTPUT` for the members. The staged case location is
set per machine in `CMakeLists.txt`:

- ursa: `/scratch4/BMC/zrtrr/Samuel.Degelia/rrfsv1_NA_domain/na3km_2024052700`
- wcoss2: not staged yet

## Configure and run

```
./build.sh -m FV3 -n YES
cd build/rrfs-test-na3km && ctest -V
```

The test uses 1600 MPI tasks (40 per node) with a 1 hour wall time. On ursa, set
`SLURM_ACCOUNT` before running ctest; on wcoss2, set `PBS_ACCOUNT`.

## Switching to hybrid 3DEnVar

The test runs 3DVar (GSI static B) until NA 3 km MGBF settings are available. The
ensemble is already linked in (`data/inputs/memNNN`). To switch:

1. Put the MGBF namelist (and its normalization profile) in `fix/`; every file there is
   linked into the run directory.
2. In `jcb/jcb-rrfs_fv3jedi_na3km_2024052700_analysis.yaml`, set
   `background_error_file: atmosphere_background_error_hybrid3denvar_mgbf` and fill in the
   `mgbf_*` values.
3. Regenerate the reference in `testoutput/`.
