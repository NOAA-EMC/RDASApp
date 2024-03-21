#!/bin/bash
# add_submodules.sh
# add submodules to the git commit

my_dir="$( cd "$( dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd )"

rdasdir=${1:-${my_dir}/../../}

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

for r in $repos; do
  echo "Adding ${rdasdir}/sorc/${r}"
  cd ${rdasdir}/sorc
  git add ${r}
done
