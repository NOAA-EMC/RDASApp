#!/bin/bash
# update_develop.sh
# update specified repositories to most recent develop hash

repos="
oops
vader
saber
ioda
ufo
fv3-jedi
mpas-jedi
iodaconv
"

my_dir="$( cd "$( dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd )"

rdasdir=${1:-${my_dir}/../../}

for r in $repos; do
  echo "Updating ${rdasdir}/sorc/${r}"
  cd ${rdasdir}/sorc
  git submodule update --remote --merge ${r}
done
