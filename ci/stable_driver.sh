#!/bin/bash --login

my_dir="$( cd "$( dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd )"

# ==============================================================================
usage() {
  set +x
  echo
  echo "Usage: $0 -t <target> -h"
  echo
  echo "  -t  target/machine script is running on    DEFAULT: $(hostname)"
  echo "  -h  display this message and quit"
  echo
  exit 1
}

# ==============================================================================
# First, set up runtime environment

export TARGET="$(hostname)"

while getopts "t:h" opt; do
  case $opt in
    t)
      TARGET=$OPTARG
      ;;
    h|\?|:)
      usage
      ;;
  esac
done

case ${TARGET} in
  hera | orion)
    echo "Running stability check on $TARGET"
    source $MODULESHOME/init/sh
    source $my_dir/${TARGET}.sh
    module purge
    module use $RDAS_MODULE_USE
    module load RDAS/$TARGET
    module list
    ;;
  *)
    echo "Unsupported platform. Exiting with error."
    exit 1
    ;;
esac

set -x
# ==============================================================================
datestr="$(date +%Y%m%d)"
repo_url="https://github.com/NOAA-EMC/RDASApp.git"
stableroot=$RDAS_CI_ROOT/stable

mkdir -p $stableroot/$datestr
cd $stableroot/$datestr

# clone RDASApp develop branch
rdasdir=$stableroot/$datestr/rdas
git clone --recursive $repo_url $rdasdir

# checkout develop
cd $rdasdir
git checkout develop
git pull

# ==============================================================================
# update the hashes to the most recent
$my_dir/../ush/submodules/update_develop.sh $rdasdir

# ==============================================================================
# run the automated testing
$my_dir/run_ci.sh -d $rdasdir -o $stableroot/$datestr/output
ci_status=$?
total=0
if [ $ci_status -eq 0 ]; then
  cd $rdasdir
  # checkout feature/stable-nightly
  git stash
  total=$(($total+$?))
  if [ $total -ne 0 ]; then
    echo "Unable to git stash" >> $stableroot/$datestr/output
  fi
  git checkout feature/stable-nightly
  total=$(($total+$?))
  if [ $total -ne 0 ]; then
    echo "Unable to checkout feature/stable-nightly" >> $stableroot/$datestr/output
  fi
  # merge in develop
  git merge develop
  total=$(($total+$?))
  if [ $total -ne 0 ]; then
    echo "Unable to merge develop" >> $stableroot/$datestr/output
  fi
  # add in submodules
  git stash pop
  total=$(($total+$?))
  if [ $total -ne 0 ]; then
    echo "Unable to git stash pop" >> $stableroot/$datestr/output
  fi
  $my_dir/../ush/submodules/add_submodules.sh $rdasdir
  total=$(($total+$?))
  if [ $total -ne 0 ]; then
    echo "Unable to add updated submodules to commit" >> $stableroot/$datestr/output
  fi
  git diff-index --quiet HEAD || git commit -m "Update to new stable build on $datestr"
  total=$(($total+$?))
  caution=""
  if [ $total -ne 0 ]; then
    echo "Unable to commit" >> $stableroot/$datestr/output
  fi
  git push --set-upstream origin feature/stable-nightly
  total=$(($total+$?))
  if [ $total -ne 0 ]; then
    echo "Unable to push" >> $stableroot/$datestr/output
  fi
  if [ $total -ne 0 ]; then
    echo "Issue merging with develop. please manually fix"
    PEOPLE="Cory.R.Martin@noaa.gov Shun.Liu@noaa.gov Ting.Lei@noaa.gov Donald.E.Lippi@noaa.gov Hui.Liu@noaa.gov"
    SUBJECT="Problem updating feature/stable-nightly branch of RDASApp"
    BODY=$stableroot/$datestr/output_stable_nightly
    cat > $BODY << EOF
Problem updating feature/stable-nightly branch of RDASApp. Please check $stableroot/$datestr/RDASApp

EOF
    mail -r "Darth Vader - NOAA Affiliate <darth.vader@noaa.gov>" -s "$SUBJECT" "$PEOPLE" < $BODY
  else
    echo "Stable branch updated"
  fi
else
  # do nothing
  echo "Testing failed, stable branch will not be updated"
fi
# ==============================================================================
# publish some information to RZDM for quick viewing
# THIS IS A TODO FOR NOW

# ==============================================================================
# scrub working directory for older files
find $stableroot/* -maxdepth 1 -mtime +3 -exec rm -rf {} \;
