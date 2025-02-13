#!/bin/bash

# This script is designed as a standalone version of rrfs-test/CMakeLists.txt
# Running this will update the input files (data, yamls, etc.) for each ctest
# Note that the ctest configurations (test names, mpi_args) are not updated here

DYCORE="BOTH" # [FV3JEDI, MPASJEDI, BOTH]

# FV3-JEDI tests
rrfs_fv3jedi_tests=(
    "rrfs_fv3jedi_2024052700_Ens3Dvar"
    "rrfs_fv3jedi_2024052700_getkf_observer"
    "rrfs_fv3jedi_2024052700_getkf_solver"
)

# MPAS-JEDI tests
rrfs_mpasjedi_tests=(
    "rrfs_mpasjedi_2024052700_Ens3Dvar"
    "rrfs_mpasjedi_2024052700_getkf_observer"
    "rrfs_mpasjedi_2024052700_getkf_solver"
    "rrfs_mpasjedi_2024052700_bumploc"
)

echo "Use test data from rrfs-test-data repository"
RDASApp=$( git rev-parse --show-toplevel 2>/dev/null )
CMAKE_SOURCE_DIR=${RDASApp}/bundle
CMAKE_CURRENT_BINARY_DIR=${RDASApp}/build/rrfs-test
rrfs_test_data_local=${CMAKE_SOURCE_DIR}/rrfs-test-data/
src_yaml=${CMAKE_SOURCE_DIR}/rrfs-test/testinput

if [[ $DYCORE == "FV3JEDI" || $DYCORE == "BOTH" ]]; then 
   for ctest in "${rrfs_fv3jedi_tests[@]}"; do
      case=${ctest}
      echo "Updating ${case}..."
      casedir=${CMAKE_CURRENT_BINARY_DIR}/rundir-${case}
      src_casedir=${rrfs_test_data_local}/rrfs-data_fv3jedi_2024052700
      ln -snf ${src_casedir}/DataFix ${casedir}/DataFix
      ln -snf ${src_casedir}/Data_static ${casedir}/Data_static
      ln -snf ${src_casedir}/INPUT ${casedir}/INPUT
      ln -snf ${src_casedir}/data ${casedir}/data
      ln -snf ${CMAKE_SOURCE_DIR}/rrfs-test/testoutput ${casedir}/testoutput
      cp ${src_yaml}/${case}.yaml ${casedir}
   done
fi 

if [[ $DYCORE == "MPASJEDI" || $DYCORE == "BOTH" ]]; then 
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
