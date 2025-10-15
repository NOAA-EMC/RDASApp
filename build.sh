#!/bin/bash

# build.sh
# 1 - determine host, load modules on supported hosts; proceed w/o otherwise
# 2 - configure; build; install
# 4 - optional, run unit tests

# Deactivate virtual env or conda env to prevent build issues
if [[ -n "$VIRTUAL_ENV" || -n "$CONDA_PREFIX" ]]; then
  unset VIRTUAL_ENV
  unset CONDA_PREFIX
  unset CONDA_DEFAULT_ENV
  unset CONDA_SHLVL
  export PATH=$(echo "$PATH" | tr ':' '\n' | grep -vi 'conda' | grep -vi 'miniforge' | paste -sd ':' -)
  if [[ -n "$LD_LIBRARY_PATH" ]]; then
    export LD_LIBRARY_PATH=$(echo "$LD_LIBRARY_PATH" | tr ':' '\n' | grep -vi 'conda' | grep -vi 'miniforge' | paste -sd ':' -)
  fi
fi

module purge
set -eu
START=$(date +%s)
dir_root="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

source $dir_root/ush/detect_machine.sh
source $dir_root/ush/init.sh

# ==============================================================================
usage() {
  set +x
  echo
  echo "Usage example: $0 -j <num> -m MPAS -t NO | -h"
  echo
  echo "  -p  installation prefix <prefix>       DEFAULT: <none>"
  echo "  -c  additional CMake options           DEFAULT: <none>"
  echo "  -v  build with verbose output          DEFAULT: NO"
  echo "  -j  number of build jobs               DEFAULT: 4 on Orion, 6 on other machines"
  echo "  -b  build JCB                          DEFAULT: YES"
  echo "  -f  force a clean build                DEFAULT: NO"
  echo "  -s  only build a subset of the bundle  DEFAULT: NO"
  echo "  -m  select dycore                      DEFAULT: FV3andMPAS"
  echo "  -x  build super executables            DEFAULT: NO"
  echo "  -t  include RRFS,BUFR_QUERY test data  DEFAULT: YES"
  echo "  -d  compile in the debug mode          DEFAULT: NO"
  echo "  -w  compile with workaround codes      DEFAULT: YES"
  echo "  -h  display this message and quit"
  echo
  exit 1
}

# ==============================================================================

# Defaults:
INSTALL_PREFIX=""
CMAKE_OPTS=""
BUILD_TARGET="${MACHINE_ID:-'localhost'}"
BUILD_VERBOSE="NO"
CLEAN_BUILD="NO"
BUILD_JCSDA="YES"
BUILD_SUPER_EXE="NO"
BUILD_RRFS_TEST="YES"
DYCORE="FV3andMPAS"
COMPILER="${COMPILER:-intel}"
DEBUG_OPT=""
BUFRQUERY_OPT=""
BUILD_JCB="YES"
BUILD_WORKAROUND="YES"

while getopts "p:c:m:j:t:b:w:hvfsxd" opt; do
  case $opt in
    p)
      INSTALL_PREFIX=$OPTARG
      ;;
    c)
      CMAKE_OPTS=$OPTARG
      ;;
    m)
      DYCORE=$OPTARG
      ;;
    j)
      BUILD_JOBS=$OPTARG
      ;;
    b)
      BUILD_JCB=$OPTARG
      ;;
    t)
      BUILD_RRFS_TEST=$OPTARG
      if [[ "$OPTARG" == "NO" ]]; then
        BUFRQUERY_OPT="-DSKIP_DOWNLOAD_TEST_DATA=ON"
      fi
      ;;
    w)
      BUILD_WORKAROUND=$OPTARG
      ;;
    v)
      BUILD_VERBOSE=YES
      ;;
    d)
      DEBUG_OPT="-DCMAKE_BUILD_TYPE=Debug"
      ;;
    f)
      CLEAN_BUILD=YES
      ;;
    s)
      BUILD_JCSDA=NO
      ;;
    x)
      BUILD_SUPER_EXE=YES
      ;;
    h|\?|:)
      usage
      ;;
  esac
done

case ${BUILD_TARGET} in
  hera | orion | hercules | jet | gaea | wcoss2 | ursa | derecho)
    echo "Building RDASApp on $BUILD_TARGET"
    echo "  Build initiated `date`"
    if [[ "${BUILD_TARGET}" != *gaea* ]] &&  [[ "${BUILD_TARGET}" != *derecho* ]]; then
      source $dir_root/ush/module-setup.sh
    fi
    module use $dir_root/modulefiles
    module load RDAS/$BUILD_TARGET.$COMPILER
    CMAKE_OPTS+=" ${DEBUG_OPT} ${BUFRQUERY_OPT} -DMPIEXEC_EXECUTABLE=$MPIEXEC_EXEC -DMPIEXEC_NUMPROC_FLAG=$MPIEXEC_NPROC -DBUILD_GSIBEC=ON -DMACHINE_ID=$MACHINE_ID"
    module list
    ;;
  *)
    echo "Building RDASApp on unknown target: $BUILD_TARGET"
    exit
    ;;
esac

# Set default number of build jobs based on machine
if [[ $BUILD_TARGET == 'orion' ]]; then # lower due to memory limit on login nodes
  BUILD_JOBS=${BUILD_JOBS:-4}
else # hera, hercules, jet, gaea
  BUILD_JOBS=${BUILD_JOBS:-6}
fi
#clt from GDASapp
# TODO: Remove LD_LIBRARY_PATH line as soon as permanent solution is available
 if [[ $BUILD_TARGET == 'wcoss2' ]]; then
     export LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:/opt/cray/pe/mpich/8.1.19/ofi/intel/19.0/lib"
 fi

BUILD_DIR=${BUILD_DIR:-$dir_root/build}
if [[ $CLEAN_BUILD == 'YES' ]]; then
  [[ -d ${BUILD_DIR} ]] && rm -rf ${BUILD_DIR}
elif [[ -d ${BUILD_DIR} ]]; then
  printf "Build directory (${BUILD_DIR}) already exists\n"
  printf "Please choose what to do:\n\n"
  printf "[r]emove the existing directory\n"
  printf "[c]ontinue building in the existing directory\n"
  printf "[q]uit this build script\n"
  read -p "Choose an option (r/c/q):" choice
  case ${choice} in
    [Rr]* ) rm -rf ${BUILD_DIR} ;;
    [Cc]* ) ;;
        * ) exit ;;
  esac
fi
mkdir -p ${BUILD_DIR} && cd ${BUILD_DIR}

# If INSTALL_PREFIX is not empty; install at INSTALL_PREFIX
[[ -n "${INSTALL_PREFIX:-}" ]] && CMAKE_OPTS+=" -DCMAKE_INSTALL_PREFIX=${INSTALL_PREFIX}"

# activate tests based on if this is cloned within the global-workflow
WORKFLOW_BUILD=${WORKFLOW_BUILD:-"OFF"}
CMAKE_OPTS+=" -DWORKFLOW_TESTS=${WORKFLOW_BUILD}"

# determine which dycore to use
if [[ $DYCORE == 'FV3' ]]; then
  CMAKE_OPTS+=" -DFV3_DYCORE=ON"
  builddirs="fv3-jedi iodaconv"
elif [[ $DYCORE == 'MPAS' ]]; then
  CMAKE_OPTS+=" -DFV3_DYCORE=OFF -DMPAS_DYCORE=ON"
  builddirs="mpas-jedi iodaconv"
elif [[ $DYCORE == 'FV3andMPAS' ]]; then
  CMAKE_OPTS+=" -DFV3_DYCORE=ON -DMPAS_DYCORE=ON"
  builddirs="fv3-jedi mpas-jedi iodaconv"
else
  echo "$DYCORE is not a valid dycore option. Valid options are FV3 or MPAS"
  exit 1
fi

# Install the jcb clients
if [[ $BUILD_JCB == 'YES' ]]; then
  cd $dir_root/sorc/jcb
  python jcb_client_init.py
  # Build an example jedi.yaml
  #PYTHONPATH="${PYTHONPATH}:$dir_root/sorc/jcb/src/:$dir_root/build/lib/python3.*:${dir_root}/sorc/wxflow/src"
  #cd $dir_root/sorc/jcb/src/jcb/configuration/apps/rdas/test/client_integration
  #python run.py
  # Link the RDASApp/parm/jcb-rdas regular folder instead of submodule
  cd $dir_root/sorc/jcb/src/jcb/configuration/apps/
  mv rdas rdas.bak
  ln -sf $dir_root/parm/jcb-rdas rdas
  cd ${BUILD_DIR}
fi

# Create super yamls and link in test data
if [[ $BUILD_RRFS_TEST == 'YES' ]]; then

  # Build the ctest yamls - gen_yaml
  cd $dir_root/rrfs-test/validated_yamls
  ./gen_yaml_ctest.sh

  # Build the ctest yamls - jcb
  PYTHONPATH="${PYTHONPATH}:$dir_root/sorc/jcb/src/:$dir_root/build/lib/python3.*:${dir_root}/sorc/wxflow/src"

  cd $dir_root/rrfs-test/testinput

  ctest_yamls=(
    # Algorithm ctests
    rrfs_fv3jedi_2024052700_3dvar.yaml
    rrfs_fv3jedi_2024052700_3denvar.yaml
    rrfs_fv3jedi_2024052700_getkf_observer.yaml
    rrfs_fv3jedi_2024052700_getkf_solver.yaml
    rrfs_fv3jedi_2024052700_hybrid3denvar.yaml
#    rrfs_mpasjedi_2024052700_bumploc.yaml
#    rrfs_mpasjedi_2024052700_3denvar.yaml
#    rrfs_mpasjedi_2024052700_getkf_observer.yaml
#    rrfs_mpasjedi_2024052700_getkf_solver.yaml

    # Observation ctests (fv3jedi & 3dvar only)
    rrfs_fv3jedi_2024052700_3dvar_conv_surface.yaml
    rrfs_fv3jedi_2024052700_3dvar_conv_upperair.yaml
    rrfs_fv3jedi_2024052700_3dvar_remote.yaml
    rrfs_fv3jedi_2024052700_3dvar_satrad.yaml
  )

  cp $dir_root/parm/jcb-rdas/test/ci/run_jcb_ctest.py .
  for ctest_yaml in "${ctest_yamls[@]}"; do
    jcb_config="jcb-$ctest_yaml"
    cp $dir_root/parm/jcb-rdas/test/ci/$jcb_config .
    python run_jcb_ctest.py 2024052700 $jcb_config $ctest_yaml
    ctest=${ctest_yaml%.yaml}
  done
  cd ${BUILD_DIR}

  # Link in test data for experiments: MPAS-JEDI
  if [[ $DYCORE == 'MPAS' || $DYCORE == 'FV3andMPAS' ]]; then
    # Link in case data
    echo "Linking in test data for MPAS-JEDI case"
    $dir_root/rrfs-test/scripts/link_mpasjedi_expr.sh
  fi

  # Link in test data for experiments: FV3-JEDI
  if [[ $DYCORE == 'FV3' || $DYCORE == 'FV3andMPAS' ]]; then
    # Link in case data
    echo "Linking in test data for FV3-JEDI case"
    $dir_root/rrfs-test/scripts/link_fv3jedi_expr.sh
  fi
fi

# Copy workaround codes (remove these as soon as PRs are merged)
if [[ $BUILD_WORKAROUND == 'YES' ]]; then
  # Workaround for regional GSIBEC
  # Saber PR #1088: https://github.com/JCSDA-internal/saber/pull/1088
  cp ../sorc/_workaround_/saber/GSIParameters.h        ../sorc/saber/src/saber/gsi/utils/GSIParameters.h
  cp ../sorc/_workaround_/saber/GridCheckHelper.cc     ../sorc/saber/src/saber/gsi/utils/GridCheckHelper.cc
  cp ../sorc/_workaround_/saber/gsi_covariance_mod.f90 ../sorc/saber/src/saber/gsi/covariance/gsi_covariance_mod.f90
  cp ../sorc/_workaround_/saber/gsi_grid_mod.f90       ../sorc/saber/src/saber/gsi/grid/gsi_grid_mod.f90
  cp ../sorc/_workaround_/saber/Geometry.cc            ../sorc/saber/src/saber/interpolation/Geometry.cc
  # No PR for gsibec yet
  cp ../sorc/_workaround_/gsibec/*                     ../sorc/gsibec/src/gsibec/gsi

  # Check which spack-stack version we are on
  # Spack-stack 1.9 uses a different workaround version
  # Remove me once all machines are updated to >1.9
  modfile="$dir_root/modulefiles/RDAS/$BUILD_TARGET.$COMPILER.lua"
  spack_version=$(grep -oE 'spack-stack(-nco)?-[0-9]+(\.[0-9]+)*' "$modfile" | head -n1 | sed -E 's/^.*spack-stack(-nco)?-//')
  spack_minor=$(echo "$spack_version" | sed -E 's/^1\.([0-9]+).*/\1/')
  spack_minor_float=$(echo "$spack_minor" | awk '{printf "%.1f", $1}')
  if (( $(echo "$spack_minor_float >= 9.0" | bc -l) )); then
    cp ../sorc/_workaround_/saber/Geometry_ss1p9.cc            ../sorc/saber/src/saber/interpolation/Geometry.cc
    cp ../sorc/_workaround_/saber/gsi_covariance_mod_ss1p9.f90 ../sorc/saber/src/saber/gsi/covariance/gsi_covariance_mod.f90
    if [[ $DYCORE == 'FV3' || $DYCORE == 'FV3andMPAS' ]]; then
      sed -i 's/128.500001/51.499998/' ${dir_root}/rrfs-test/testinput/rrfs_fv3jedi_2024052700_3dvar.yaml
      sed -i 's/128.500001/51.499998/' ${dir_root}/rrfs-test/testinput/rrfs_fv3jedi_2024052700_hybrid3denvar.yaml
      sed -i 's/128.500001/51.499998/' ${dir_root}/expr/fv3_2024052700/rrfs_fv3jedi_2024052700_3dvar.yaml
      sed -i 's/128.500001/51.499998/' ${dir_root}/expr/fv3_2024052700/rrfs_fv3jedi_2024052700_hybrid3denvar.yaml
    fi
  fi

  # Workaround for not including air_pressure_thickness as an analysis variable
  # No PR yet for this
  cp ../sorc/_workaround_/fv3-jedi/fv3jedi_io_fms2_mod.f90 ../sorc/fv3-jedi/src/fv3jedi/IO/FV3Restart
fi

# temporary bug fix, https://github.com/JCSDA-internal/oops/issues/3030
ccfile="../sorc/oops/src/oops/base/ParameterTraitsObsVariables.cc"
if ! grep "#include <algorithm>" ${ccfile} >/dev/null; then
  sed -i -e "s/#include <map>/#include <algorithm>\n#include <map>/" ${ccfile}
fi

CMAKE_OPTS+=" -DMPIEXEC_MAX_NUMPROCS:STRING=120 -DBUILD_SUPER_EXE=$BUILD_SUPER_EXE -DBUILD_RRFS_TEST=$BUILD_RRFS_TEST"
# Configure
echo "Configuring ..."
set -x
cmake \
  ${CMAKE_OPTS:-} \
  $dir_root/bundle
set +x

# Build
echo "Building ..."
set -x
if [[ $BUILD_JCSDA == 'YES' ]]; then
  make -j $BUILD_JOBS VERBOSE=$BUILD_VERBOSE
else
  for b in $builddirs; do
    cd $b
    make -j $BUILD_JOBS VERBOSE=$BUILD_VERBOSE
    cd ../
  done
fi
set +x

# Install
if [[ -n ${INSTALL_PREFIX:-} ]]; then
  echo "Installing ..."
  set -x
  make install
  set +x
fi

echo build finished: `date`
END=$(date +%s)
DIFF=$((END - START))
echo "Time taken to run the code: $DIFF seconds"
exit 0
