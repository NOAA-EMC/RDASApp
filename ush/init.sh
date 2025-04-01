#!/bin/sh
#
ushdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source ${ushdir}/detect_machine.sh
basedir="$(dirname "$ushdir")"

case ${MACHINE_ID} in
  wcoss2)
    RDAS_DATA=/lfs/h2/emc/da/noscrub/Ting.Lei/dr-rdas-data/RDAS_DATA
    ;;
  hera)
    RDAS_DATA=/scratch1/NCEPDEV/fv3-cam/RDAS_DATA
    ;;
  jet)
    RDAS_DATA=/lfs5/BMC/nrtrr/RDAS_DATA
    ;;
  orion|hercules)
    RDAS_DATA=/work/noaa/zrtrr/RDAS_DATA
    ;;
  gaea)
    if [[ -d /gpfs/f5 ]]; then
      RDAS_DATA=/gpfs/f5/gsl-glo/world-shared/role.rrfsfix/RDAS_DATA
    elif [[ -d /gpfs/f6 ]]; then
      RDAS_DATA=/gpfs/f6/bil-fire10-oar/world-shared/role.rrfsfix/RDAS_DATA
    else
      echo "unsupported gaea cluster: ${MACHINE_ID}"
    fi
    ;;
  *)
    echo "platform not supported: ${MACHINE_ID}"
    ;;
esac

agentfile=${basedir}/fix/.agent
filetype=$(file ${agentfile})
if [[ ! "${filetype}" == *"symbolic link"* ]]; then
  rm -rf ${agentfile}
fi
mkdir -p ${basedir}/fix
ln -snf ${RDAS_DATA}/fix ${agentfile}
touch ${basedir}/fix/INIT_DONE
