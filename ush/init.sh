#!/bin/sh
#
ushdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
basedir="$(dirname "$mydir")"
source $ushdir/detect_machine.sh

set -x
case ${MACHINE_ID} in
  hera)
    RDAS_DATA=/scratch1/NCEPDEV/fv3-cam/RDAS_DATA
    ;;
  jet)
    RDAS_DATA=/lfs4/BMC/nrtrr/RDAS_DATA
    ;;
  orion|hercules)
    RDAS_DATA=/work/noaa/rtrr/RDAS_DATA
    ;;
  *)
    echo "platform not supported: ${MACHINE_ID}"
    ;;
esac
ln -snf ${RDAS_DATA}/fix ${basedir}/fix
