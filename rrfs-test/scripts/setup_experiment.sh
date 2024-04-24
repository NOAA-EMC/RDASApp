#!/bin/bash

# This script is used after compiling RDASApp with -r option which downloads
# RRFS test data. This script helps a user set up an experiment directory.

###### USER INPUT #####
YOUR_PATH_TO_RDASAPP="/path/to/your/installation/of/RDASApp"
YOUR_EXPERIMENT_DIR="/path/to/your/desired/experiment/directory/jedi-assim_test"
SLURM_ACCOUNT="fv3-cam"
DYCORE="FV3" #FV3 or MPAS
platform="hera" #hera or orion
#######################

# Print current setting to the screen.
echo "Your current settings are:"
echo -e "\tYOUR_PATH_TO_RDASAPP=$YOUR_PATH_TO_RDASAPP"
echo -e "\tYOUR_EXPERIMENT_DIR=$YOUR_EXPERIMENT_DIR"
echo -e "\tSLURM_ACCOUNT=$SLURM_ACCOUNT"
echo -e "\tDYCORE=$DYCORE"
echo -e "\tplatform=$platform\n"

# Check to see if user changed the paths to something valid.
if [[ ! -d $YOUR_PATH_TO_RDASAPP && ! -d `dirname $YOUR_EXPERIMENT_DIR` ]]; then
  echo "Please make sure to edit the USER INPUT BLOCK before running $0."
  echo "exiting!!!"
  exit 1
fi

# At the moment these are the only test data that exists. Maybe become user input later?
# It also seems the best to just do either FV3 or MPAS data each time script is run.
if [[ $DYCORE == "FV3" ]]; then
  TEST_DATA="rundir-rrfs_fv3jedi_hyb_2022052619"
elif [[ $DYCORE == "MPAS" ]]; then
  TEST_DATA="rundir-rrfs_mpasjedi_2022052619_Ens3Dvar"
else
  echo "Not a valid DYCORE: ${DYCORE}. Please use FV3 or MPAS."
  echo "exiting!!!"
  exit 2
fi

if [[ ! ( $platform == "hera" || $platform == "orion" ) ]]; then
   echo "Not a valid platform: ${platform}. Please use hera or orion."
   exit 3
fi

# Lowercase dycore for script names.
declare -l dycore="$DYCORE"

# Ensure experiment directory exists, the move into that space.
mkdir -p $YOUR_EXPERIMENT_DIR
cd $YOUR_EXPERIMENT_DIR

# Copy the test data into the experiment directory.
echo "Copying data. This may take awhile."
rsync -a $YOUR_PATH_TO_RDASAPP/bundle/rrfs-test-data/${TEST_DATA} .

# Copy the template run script which will be updated according to the user input
cp -p $YOUR_PATH_TO_RDASAPP/rrfs-test/scripts/templates/run_${dycore}jedi_${platform}_template.sh ./${TEST_DATA}/run_${dycore}jedi_${platform}.sh

# Stream editor to edit files. Use "#" instead of "/" since we have "/" in paths.
cd ${YOUR_EXPERIMENT_DIR}/${TEST_DATA}
sed -i "s#@YOUR_PATH_TO_RDASAPP@#${YOUR_PATH_TO_RDASAPP}#g" ./run_${dycore}jedi_${platform}.sh
sed -i "s#@YOUR_EXPERIMENT_DIR@#${YOUR_EXPERIMENT_DIR}#g"   ./run_${dycore}jedi_${platform}.sh
sed -i "s#@SLURM_ACCOUNT@#${SLURM_ACCOUNT}#g"               ./run_${dycore}jedi_${platform}.sh

if [[ $DYCORE == "FV3" ]]; then
  # Copy visualization package.
  cp -p $YOUR_PATH_TO_RDASAPP/rrfs-test/ush/*py .
fi

# Copy rrts-test yamls and obs files.
cp -p $YOUR_PATH_TO_RDASAPP/rrfs-test/testinput/* testinput/.
cp -p $YOUR_PATH_TO_RDASAPP/rrfs-test/obs/* Data/obs/.

echo "done."
