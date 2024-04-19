#!/bin/bash

# This script is used after compiling RDASApp with -r option which downloads
# RRFS test data. This script helps a user set up an experiment directory.

###### USER INPUT #####
YOUR_PATH_TO_RDASAPP="/scratch2/NCEPDEV/fv3-cam/Donald.E.Lippi/RRFSv2/PRs/RDASApp"
YOUR_EXPERIMENT_DIR="/scratch2/NCEPDEV/fv3-cam/Donald.E.Lippi/RRFSv2/jedi-assim_validation_test"
SLURM_ACCOUNT="fv3-cam"
DYCORE="FV3" #FV3 or MPAS
#######################

if [[ $DYCORE == "FV3" ]]; then
TEST_DATA="rundir-rrfs_fv3jedi_hyb_2022052619"
fi
if [[ $DYCORE == "MPAS" ]]; then
TEST_DATA="rundir-rrfs_fv3jedi_hyb_2022052619"
fi

mkdir -p $YOUR_EXPERIMENT_DIR
cd $YOUR_EXPERIMENT_DIR


#rsync -a --delete  $YOUR_PATH_TO_RDASAPP/bundle/rrfs-test-data/${TEST_DATA} .
rsync -a $YOUR_PATH_TO_RDASAPP/bundle/rrfs-test-data/${TEST_DATA} .

cp -p $YOUR_PATH_TO_RDASAPP/rrfs-test/scripts/templates/run_fv3jedi_hera_template.sh ./${TEST_DATA}/run_fv3jedi_hera.sh

cd ${TEST_DATA}
# use "#" instead of "/" since we have "/" in paths
sed -i "s#@YOUR_PATH_TO_RDASAPP@#${YOUR_PATH_TO_RDASAPP}#g" ./run_fv3jedi_hera.sh
sed -i "s#@YOUR_EXPERIMENT_DIR@#${YOUR_EXPERIMENT_DIR}#g"   ./run_fv3jedi_hera.sh
sed -i "s#@SLURM_ACCOUNT@#${SLURM_ACCOUNT}#g"               ./run_fv3jedi_hera.sh
#sed -i "s/@@/${}/g"./run_fv3jedi_hera.sh

cp -p $YOUR_PATH_TO_RDASAPP/rrfs-test/ush/*py .

ln -sf $YOUR_PATH_TO_RDASAPP/rrfs-test/yamls Data/yamls
ln -sf $YOUR_PATH_TO_RDASAPP/rrfs-test/obs/* Data/obs/.
