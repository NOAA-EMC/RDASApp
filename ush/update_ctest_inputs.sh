#!/bin/bash

# This script is designed as a standalone version of rrfs-test/CMakeLists.txt
# Running this will update the input files (data, yamls, etc.) for each ctest
# Note that the ctest configurations (test names, mpi_args) are not updated here

DYCORE="BOTH" # [FV3JEDI, MPASJEDI, BOTH]

# FV3-JEDI tests
rrfs_fv3jedi_tests=(
    "rrfs_fv3jedi_2024052700_3dvar"
    "rrfs_fv3jedi_2024052700_3denvar"
    "rrfs_fv3jedi_2024052700_3denvar_mgbf"
    "rrfs_fv3jedi_2024052700_hybrid3denvar"
    "rrfs_fv3jedi_2024052700_hybrid3denvar_mgbf"
    "rrfs_fv3jedi_2024052700_getkf_observer"
    "rrfs_fv3jedi_2024052700_getkf_solver"
    "rrfs_fv3jedi_2024052700_3dvar_conv_upperair"
    "rrfs_fv3jedi_2024052700_3dvar_conv_surface"
    "rrfs_fv3jedi_2024052700_3dvar_remote"
    "rrfs_fv3jedi_2024052700_3dvar_satrad"
    "rrfs_fv3jedi_2024052700_3denvar_refl"
)

# MPAS-JEDI tests
rrfs_mpasjedi_tests=(
    "rrfs_mpasjedi_2024052700_3denvar"
    "rrfs_mpasjedi_2024052700_getkf_observer"
    "rrfs_mpasjedi_2024052700_getkf_solver"
    "rrfs_mpasjedi_2024052700_bumploc"
)

# Select tests based on DYCORE
ctest_yamls=()
if [[ "$DYCORE" == "FV3JEDI" || "$DYCORE" == "BOTH" ]]; then
  ctest_yamls+=("${rrfs_fv3jedi_tests[@]}")
fi
if [[ "$DYCORE" == "MPASJEDI" || "$DYCORE" == "BOTH" ]]; then
  ctest_yamls+=("${rrfs_mpasjedi_tests[@]}")
fi

echo "Use test data from rrfs-test-data repository"
RDASApp=$( git rev-parse --show-toplevel 2>/dev/null )
CMAKE_SOURCE_DIR=${RDASApp}/bundle
CMAKE_CURRENT_BINARY_DIR=${RDASApp}/build/rrfs-test
rrfs_test_data_local=${CMAKE_SOURCE_DIR}/rrfs-test-data/
src_yaml=${CMAKE_SOURCE_DIR}/rrfs-test/testinput

# Source RDAS modules so that we don't have any python version issues in gen_yaml_ctest.sh
source load_rdas.sh

# First run the gen_yaml script to regenerate the ctest yamls
currdir=`pwd`
cd ${RDASApp}/rrfs-test/validated_yamls
./gen_yaml_ctest.sh
cd ${currdir}

# Run jcb to regenerate the ctest yamls
PYTHONPATH="${PYTHONPATH}:${RDASApp}/sorc/jcb/src/:${RDASApp}/build/lib/python3.*:${RDASApp}/sorc/wxflow/src"
cd "${src_yaml}"
cp "${RDASApp}/parm/jcb-rdas/test/ci/run_jcb_ctest.py" .

for ctest_yaml in "${rrfs_fv3jedi_tests[@]}"; do
  ctest_yaml="${ctest_yaml}.yaml"
  jcb_config="jcb-${ctest_yaml}"
  cp "${RDASApp}/parm/jcb-rdas/test/ci/${jcb_config}" .
  python run_jcb_ctest.py 2024052700 "${jcb_config}" "${ctest_yaml}"
done
cd ${currdir}

if [[ $DYCORE == "FV3JEDI" || $DYCORE == "BOTH" ]]; then
   # Relink fix into expr in case new obs are added
   echo "Linking in test data for FV3-JEDI case"
   ${RDASApp}/rrfs-test/scripts/link_fv3jedi_expr.sh
   for ctest in "${rrfs_fv3jedi_tests[@]}"; do
      case=${ctest}
      echo "Updating ${case}..."
      casedir=${CMAKE_CURRENT_BINARY_DIR}/rundir-${case}
      src_casedir=${rrfs_test_data_local}/rrfs-data_fv3jedi_2024052700
      ln -snf ${src_casedir}/DataFix ${casedir}/DataFix
      ln -snf ${casedir}/DataFix/field_table ${casedir}/.
      ln -snf ${casedir}/DataFix/fmsmpp.nml ${casedir}/.
      ln -snf ${casedir}/DataFix/input_lam_C775_NP16X10.nml ${casedir}/.
      ln -snf ${casedir}/DataFix/fix/dynamics_lam_cmaq.yaml ${casedir}/.
      ln -snf ${src_casedir}/Data_static ${casedir}/Data_static
      ln -snf ${src_casedir}/INPUT ${casedir}/INPUT
      ln -snf ${src_casedir}/data ${casedir}/data
      ln -snf ${casedir}/data/bkg/20240527*nc ${casedir}/.
      ln -snf ${casedir}/data/bkg/20240527.000000.fv_core.res.nc ${casedir}/fv_core.res.nc
      ln -snf ${casedir}/data/bkg/20240527.000000.fv_core.res.tile1.nc ${casedir}/fv_core.res.tile1.nc
      ln -snf ${casedir}/data/bkg/20240527.000000.fv_srf_wnd.res.tile1.nc ${casedir}/fv_srf_wnd.res.tile1.nc
      ln -snf ${casedir}/data/bkg/20240527.000000.fv_tracer.res.tile1.nc ${casedir}/fv_tracer.res.tile1.nc
      ln -snf ${casedir}/data/bkg/20240527.000000.phy_data.nc ${casedir}/phy_data.nc
      ln -snf ${casedir}/data/bkg/20240527.000000.sfc_data.nc ${casedir}/sfc_data.nc
      ln -snf ${CMAKE_SOURCE_DIR}/rrfs-test/testoutput ${casedir}/testoutput
      cp ${src_yaml}/${case}.yaml ${casedir}
   done
fi

if [[ $DYCORE == "MPASJEDI" || $DYCORE == "BOTH" ]]; then
   # Relink fix into expr in case new obs are added
   echo "Linking in test data for MPAS-JEDI case"
   ${RDASApp}/rrfs-test/scripts/link_mpasjedi_expr.sh
   for ctest in "${rrfs_mpasjedi_tests[@]}"; do
      case=${ctest}
      echo "Updating ${case}..."
      casedir=${CMAKE_CURRENT_BINARY_DIR}/rundir-${case}
      src_casedir=${rrfs_test_data_local}/rrfs-data_mpasjedi_2024052700
      ln -snf ${src_casedir}/data ${casedir}/data
      ln -snf ${src_casedir}/graphinfo ${casedir}/graphinfo
      ln -snf ${src_casedir}/stream_list ${casedir}/stream_list
      ln -snf ${CMAKE_SOURCE_DIR}/rrfs-test/testoutput ${casedir}/testoutput
      cp ${src_casedir}/streams.atmosphere ${casedir}
      cp ${src_casedir}/namelist.atmosphere ${casedir}
      cp ${src_casedir}/geovars.yaml ${casedir}
      cp ${src_casedir}/keptvars.yaml ${casedir}
      cp ${src_casedir}/obsop_name_map.yaml ${casedir}
      for bl_FILE in ${src_casedir}/*.*BL; do
         ln -snf ${bl_FILE} ${casedir}/$(basename $bl_FILE)
      done
      cp ${src_yaml}/${case}.yaml ${casedir}
   done
fi

echo "All done."
