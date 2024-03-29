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
    echo "Running Automated Testing on $TARGET"
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

# ==============================================================================
# pull on the repo and get list of open PRs
cd $RDAS_CI_ROOT/repo
CI_LABEL="${RDAS_CI_HOST}-RT"
gh pr list --label "$CI_LABEL" --state "open" | awk '{print $1;}' > $RDAS_CI_ROOT/open_pr_list
open_pr_list=$(cat $RDAS_CI_ROOT/open_pr_list)

# ==============================================================================
# clone, checkout, build, test, etc.
repo_url="https://github.com/NOAA-EMC/RDASApp.git"
# loop through all open PRs
for pr in $open_pr_list; do
  gh pr edit $pr --remove-label $CI_LABEL --add-label ${CI_LABEL}-Running
  echo "Processing Pull Request #${pr}"
  mkdir -p $RDAS_CI_ROOT/PR/$pr
  cd $RDAS_CI_ROOT/PR/$pr

  # clone copy of repo
  git clone --recursive $repo_url
  cd RDASApp

  # checkout pull request
  git pull
  gh pr checkout $pr

  # get commit hash
  commit=$(git log --pretty=format:'%h' -n 1)
  echo "$commit" > $RDAS_CI_ROOT/PR/$pr/commit

  # load modules
  case ${TARGET} in
    hera | orion)
      echo "Loading modules on $TARGET"
      module purge
      module use $RDAS_CI_ROOT/PR/$pr/RDASApp/modulefiles
      module load RDAS/$TARGET
      module list
      ;;
    *)
      echo "Unsupported platform. Exiting with error."
      exit 1
      ;;
  esac

  # run build and testing command
  $my_dir/run_ci.sh -d $RDAS_CI_ROOT/PR/$pr/RDASApp -o $RDAS_CI_ROOT/PR/$pr/output_${commit}
  ci_status=$?
  gh pr comment $pr --body-file $RDAS_CI_ROOT/PR/$pr/output_${commit}
  if [ $ci_status -eq 0 ]; then
    gh pr edit $pr --remove-label ${CI_LABEL}-Running --add-label ${CI_LABEL}-Passed
  else
    gh pr edit $pr --remove-label ${CI_LABEL}-Running --add-label ${CI_LABEL}-Failed
  fi
done

# ==============================================================================
# scrub working directory for older files
find $RDAS_CI_ROOT/PR/* -maxdepth 1 -mtime +3 -exec rm -rf {} \;

