#!/bin/sh
#
ushdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source ${ushdir}/detect_machine.sh
basedir="$(dirname "$ushdir")"

case ${MACHINE_ID} in
  hera)
    RDAS_DATA=/scratch2/BMC/rtrr/RDAS_DATA
    ;;
  jet)
    RDAS_DATA=/lfs5/BMC/nrtrr/RDAS_DATA
    ;;
  orion|hercules)
    RDAS_DATA=/work/noaa/zrtrr/RDAS_DATA
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
