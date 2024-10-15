#!/bin/sh
#
# Check if the script is sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Usage: source ${0}"
  exit 1
fi

### scripts continues here...
ushdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source ${ushdir}/detect_machine.sh

module purge
module use ${ushdir}/../modulefiles
if [[ "${MACHINE_ID}" == "gaea" ]]; then
  if [[ -d /gpfs/f5 ]]; then
    module load EVA/${MACHINE_ID}C5
  elif [[ -d /gpfs/f6 ]]; then
    module load EVA/${MACHINE_ID}C6
  else
    echo "not supported gaea cluster: ${MACHINE_ID}"
  fi
else
  module load EVA/${MACHINE_ID}
fi
module list
