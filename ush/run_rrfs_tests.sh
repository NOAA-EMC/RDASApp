#!/bin/sh
#
export SLURM_ACCOUNT=${1}

if [[ "${1}" == "" ]]; then
  echo "Usage: ${0}  account_name"
  exit 1
fi

#
ushdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source ${ushdir}/load_rdas.sh

set -x
cd ${ushdir}/../build/rrfs-test
pwd
ctest -j8 # or ctest -VV for verbose outputs
exit $?
