# rrfs-test-na3km

Optional ctest that runs the RRFS analysis at full capability on the full RRFS NA 3 km
domain (C3463) for 2024-05-27 01Z. The test runs dual-resolution hybrid 3DEnVar with
radar reflectivity assimilation:

- 3 km background and outer loop, 6 km (C1732) inner loop
- GSI static B (weight 0.2) plus a 30-member ensemble with MGBF localization (weight 0.8)
- the members are read on the 3 km grid and converted online to the 6 km inner-loop grid
  (oops PR3346, applied by `build.sh` from `sorc/_workaround_/oops`)
- the GSI static B includes reflectivity (saber PR1313, applied by `build.sh` from
  `sorc/_workaround_/saber`)
- reflectivity, cloud water, cloud ice, rain, snow and graupel are analysis variables
  alongside winds, temperature, humidity and surface pressure
- the conventional and satellite-wind observations used by the RRFS baseline005 retros,
  plus MRMS reflectivity
- 44x44 layout, 1936 MPI tasks

It writes increments (`inc_jedi.*`) on the 3 km grid and leaves the backgrounds untouched.

It is not part of CI. It is only added when RDASApp is configured with
`-DBUILD_RRFS_TEST_NA3KM=ON`, and only on wcoss2 and ursa.

## Test data

The case data is staged outside RDAS_DATA. `ush/init.sh` links it to `fix/.agent_na3km`
for each machine:

- ursa: `/scratch4/BMC/zrtrr/Samuel.Degelia/rrfsv1_NA_domain/na3km_2024052701`
- wcoss2: not staged yet

`fix/expr_data/fv3_2024052701_na3km` links to it through that agent, and the test links
from there into its run directory when it is configured. The staged data holds:

- `bkg/` and `inputs/memNNN/` (30 members): links to the RRFSv1 2024052700 cycle's 01Z
  3 km restarts, plus a `phy_data.nc_prepdbz` with `ref_f3d` flipped top-down and floored at
  0 dBZ, as in rrfs-workflow's `prep_phydata_dbz.py`
- `INPUT/`: the 3 km (C3463) and 6 km (C1732) grids
- `fix/`: static files, including the MGBF normalization profiles for 1936 tasks
- `obs/`: IODA conventional, satellite-wind and MRMS reflectivity obs

The obs come from the 2024-05-27 00Z prepbufr, satwnd bufr and MRMS data, and their times
are shifted 1 h later so they fall in the 01Z analysis window. This case only checks that
the full system runs, so the obs do not need to match the 01Z state.

The test's own static files are in the repository:

- `fix/mgbf/mgbf_na6km_p1936_*`: the MGBF namelists. Reflectivity and hydrometeors form one
  localization group, and winds, temperature, humidity and surface pressure the other.
- `fix/gsi_bec/gsiparm_regional_na3km_dbz.anl`: the GSI static B namelist
- `fix/expr_data/fv3_2024052701_na3km/fmsmpp.nml` and `INPUT/input_lam_*.nml`: the FV3
  namelists for the 3 km and 6 km grids
- `parm/jcb-rdas/test/ci/jcb-rrfs_fv3jedi_na3km_2024052701_analysis.yaml`: the JCB config

## Configure and run

```
./build.sh -m FV3 -n YES
cd build/rrfs-test-na3km && ctest -V
```

The test uses 1936 MPI tasks (44 per node) with a 45 minute wall time. On ursa, set
`SLURM_ACCOUNT` before running ctest; on wcoss2, set `PBS_ACCOUNT`.
