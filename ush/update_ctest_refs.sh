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
ref_out=${CMAKE_SOURCE_DIR}/rrfs-test/testoutput

if [[ $DYCORE == "FV3JEDI" || $DYCORE == "BOTH" ]]; then
   for ctest in "${rrfs_fv3jedi_tests[@]}"; do
      case=${ctest}
      echo "Updating ${case}..."
      casedir=${CMAKE_CURRENT_BINARY_DIR}/rundir-${case}
      if [[ -d ${casedir} ]]; then
          if [[ $(find "$casedir" -type f -name "rrfs-fv3jedi*.out") ]]; then
              cp ${casedir}/rrfs-fv3jedi*out ${ref_out} # WAIT, NEED TO CHANGE THE NAME
          else
              echo "    No file files found for ${ctest}... skipping!"
          fi
      else
          echo "    Ctest directory: ${ctest} does not exist... skipping!"
      fi
   done
fi

if [[ $DYCORE == "MPASJEDI" || $DYCORE == "BOTH" ]]; then
   for ctest in "${rrfs_mpasjedi_tests[@]}"; do
      case=${ctest}
      echo "Updating ${case}..."
      casedir=${CMAKE_CURRENT_BINARY_DIR}/rundir-${case}
      if [[ -d ${casedir} ]]; then
          if [[ $(find "$casedir" -type f -name "rrfs-mpasjedi*.out") ]]; then
              cp ${casedir}/rrfs-mpasjedi*out ${ref_out}
          else
              echo "    No reference files found for ${ctest}... skipping!"
          fi
      else
          echo "    Ctest directory: ${ctest} does not exist... skipping!"
      fi
   done
fi

# Now change the names
for file in $(find "$ref_out" -type f -name "*rrfs-*.out*"); do
   echo "Overwriting ${file%???}ref..."
   mv ${file} ${file%???}ref
done

echo "All done."
