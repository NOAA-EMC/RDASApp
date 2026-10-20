#!/bin/bash
#
# Stage the RRFS NA 3 km 2024-05-27 00Z case used by the optional na3km ctest.
#
# Usage: stage_na3km_case.sh <download_dir> <case_dir>
#   download_dir: RRFSv1 restarts for 2024052700, holding fcst_fv3lam/INPUT (control)
#                 and memNNNN/fcst_fv3lam/DA_OUTPUT (ensemble members)
#   case_dir:     directory to create; pass it to cmake as -DRRFS_NA3KM_DATA=<case_dir>
#
# Restarts and large fix files are symlinked. The obs are copied from the RDASApp
# ctest obs (same cycle) and re-domain-checked against the NA 3 km grid, following
# rrfs-workflow's exrrfs_ioda_bufr.sh.
#
# Run with the RDAS modules plus py-shapely and py-cartopy loaded.

set -eu

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <download_dir> <case_dir>"
  exit 1
fi
download_dir=$(readlink -f "$1")
case_dir=$2
nmems=${NMEMS:-30}

RDASApp=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "${RDASApp}/ush/detect_machine.sh"
case ${MACHINE_ID} in
  ursa)
    FIX_RRFS=/scratch4/BMC/rtrr/FIX_RRFS
    RDAS_DATA=/scratch4/BMC/rtrr/RDAS_DATA
    ;;
  wcoss2)
    FIX_RRFS=/lfs/h2/emc/lam/noscrub/emc.lam/FIX_RRFS
    RDAS_DATA=/lfs/h2/emc/lam/noscrub/RDAS_DATA
    ;;
  *)
    echo "The na3km case is only staged on ursa and wcoss2 (MACHINE_ID=${MACHINE_ID})"
    exit 1
    ;;
esac
obs_src=${OBS_SRC:-${RDAS_DATA}/fix/expr_data/obs_2024052700_oct2026}
gridfix=${FIX_RRFS}/gsi/RRFS_NA_3km_C3463
lamfix=${FIX_RRFS}/lam/RRFS_NA_3km_C3463_Lake_fracSV

mkdir -p "${case_dir}"
case_dir=$(readlink -f "${case_dir}")
echo "Staging NA 3 km case in ${case_dir}"

# Control background
restart_files="coupler.res fv_core.res.nc fv_core.res.tile1.nc fv_srf_wnd.res.tile1.nc
               fv_tracer.res.tile1.nc phy_data.nc sfc_data.nc"
mkdir -p "${case_dir}/bkg"
for f in ${restart_files}; do
  ln -snf "${download_dir}/fcst_fv3lam/INPUT/${f}" "${case_dir}/bkg/${f}"
done

# Ensemble members (only read once the test runs hybrid 3DEnVar)
for imem in $(seq 1 ${nmems}); do
  mem3=$(printf %03d ${imem})
  mem4=$(printf %04d ${imem})
  mkdir -p "${case_dir}/inputs/mem${mem3}"
  for f in ${restart_files}; do
    src="${download_dir}/mem${mem4}/fcst_fv3lam/DA_OUTPUT/${f}"
    [[ -e "${src}" ]] || echo "WARNING: missing ensemble file ${src}"
    ln -snf "${src}" "${case_dir}/inputs/mem${mem3}/${f}"
  done
done

# Grid and static fix files
mkdir -p "${case_dir}/fix" "${case_dir}/INPUT"
ln -snf "${gridfix}/fv3_akbk"                    "${case_dir}/fix/fv3_akbk"
ln -snf "${gridfix}/fv3_grid_spec"               "${case_dir}/fix/fv3_grid_spec"
ln -snf "${FIX_RRFS}/jedi/field_table"           "${case_dir}/fix/field_table"
ln -snf "${FIX_RRFS}/jedi/dynamics_lam_cmaq.yaml" "${case_dir}/fix/dynamics_lam_cmaq.yaml"
ln -snf "${RDAS_DATA}/fix/gsi_bec/berror_stats"  "${case_dir}/fix/berror_stats"
ln -snf "${lamfix}/C3463_grid.tile7.halo3.nc"    "${case_dir}/INPUT/C3463_grid.tile7.halo3.nc"
ln -snf "${lamfix}/C3463_grid.tile7.halo3.nc"    "${case_dir}/INPUT/C3463_grid.tile7.nc"
ln -snf "${lamfix}/C3463_mosaic.halo3.nc"        "${case_dir}/INPUT/grid_spec.nc"

# Observations: domain check against the NA 3 km grid, then patch
obs_files="ioda_adpsfc.nc ioda_adpupa.nc ioda_aircar.nc ioda_aircft.nc ioda_msonet.nc
           ioda_proflr.nc ioda_rassda.nc ioda_sfcshp.nc
           ioda_satwnd.abi_goes-16.nc ioda_satwnd.abi_goes-18.nc"
workdir="${case_dir}/obs_work"
rm -rf "${workdir}"
mkdir -p "${workdir}" "${case_dir}/obs"
cd "${workdir}"
cp "${RDASApp}/rrfs-test/IODA/offline_domain_check.py" .
cp "${RDASApp}/rrfs-test/IODA/offline_ioda_patch.py" .
ln -snf "${gridfix}/fv3_grid_spec" fv3_grid_spec
for ioda_file in ${obs_files}; do
  cp "${obs_src}/${ioda_file}" .
  base_name=$(basename "${ioda_file}" .nc)
  python offline_domain_check.py -o "${ioda_file}" -g fv3_grid_spec -s 0.005 -f
  mv "${base_name}_dc.nc" "${ioda_file}"
  if [[ "${ioda_file}" == *adpupa* ]]; then
    python offline_ioda_patch.py -o "${ioda_file}" --patch-timeoffset
  else
    python offline_ioda_patch.py -o "${ioda_file}"
  fi
  mv "${base_name}_llp.nc" "${case_dir}/obs/${ioda_file}"
done
cd "${case_dir}"
rm -rf "${workdir}"

echo "Done. Configure RDASApp with -DBUILD_RRFS_TEST_NA3KM=ON -DRRFS_NA3KM_DATA=${case_dir}"
