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

while getopts "p:c:m:j:t:b:hvfsxd" opt; do
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
  PYTHONPATH="${PYTHONPATH}:$dir_root/sorc/jcb/src/:$dir_root/build/lib/python3.*:${dir_root}/sorc/wxflow/src"
  cd $dir_root/sorc/jcb/src/jcb/configuration/apps/rdas/test/client_integration
  python run.py
  cd ${BUILD_DIR}
fi

# Create super yamls and link in test data
if [[ $BUILD_RRFS_TEST == 'YES' ]]; then

  # Build the ctest yamls
  cd $dir_root/rrfs-test/validated_yamls
  ./gen_yaml_ctest.sh
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
