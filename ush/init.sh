#!/bin/sh
#
ushdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source $ushdir/detect_machine.sh
basedir="$(dirname "$ushdir")"

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
mkdir -p ${basedir}/fix
ln -snf ${RDAS_DATA}/fix/* ${basedir}/fix/
