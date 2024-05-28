#!/bin/bash

START=$(date +%s)

# This script is used after compiling RDASApp with -r option which downloads
# RRFS test data. This script helps a user set up an experiment directory.

###### USER INPUT #####
YOUR_PATH_TO_RDASAPP="/path/to/your/installation/of/RDASApp"
YOUR_EXPERIMENT_DIR="/path/to/your/desired/experiment/directory/jedi-assim_test"
SLURM_ACCOUNT="fv3-cam"
DYCORE="FV3" #FV3 or MPAS
platform="hera" #hera or orion
GSI_TEST_DATA="YES"
YOUR_PATH_TO_GSI="/path/to/your/installation/of/GSI"
EVA="YES"
#######################

# Print current setting to the screen.
echo "Your current settings are:"
echo -e "\tYOUR_PATH_TO_RDASAPP=$YOUR_PATH_TO_RDASAPP"
echo -e "\tYOUR_EXPERIMENT_DIR=$YOUR_EXPERIMENT_DIR"
echo -e "\tSLURM_ACCOUNT=$SLURM_ACCOUNT"
echo -e "\tDYCORE=$DYCORE"
echo -e "\tplatform=$platform"
echo -e "\tGSI_TEST_DATA=$GSI_TEST_DATA"
echo -e "\tYOUR_PATH_TO_GSI=$YOUR_PATH_TO_GSI"
echo -e "\tEVA=$EVA\n"

# Check to see if user changed the paths to something valid.
if [[ ! -d $YOUR_PATH_TO_RDASAPP || ! -d `dirname $YOUR_EXPERIMENT_DIR` ]]; then
  echo "Please make sure to edit the USER INPUT BLOCK before running $0."
  echo "exiting!!!"
  exit 1
fi

# At the moment these are the only test data that exists. Maybe become user input later?
# It also seems the best to just do either FV3 or MPAS data each time script is run.
if [[ $DYCORE == "FV3" ]]; then
  TEST_DATA="rrfs-data_fv3jedi_2022052619"
elif [[ $DYCORE == "MPAS" ]]; then
  TEST_DATA="rrfs-data_mpasjedi_2022052619"
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
echo "Copying data. This will take just a moment."
echo "  --> ${dycore}-jedi data on $platform"
rsync -a $YOUR_PATH_TO_RDASAPP/bundle/rrfs-test-data/${TEST_DATA} .

# Copy the template run script which will be updated according to the user input
cp -p $YOUR_PATH_TO_RDASAPP/rrfs-test/scripts/templates/run_${dycore}jedi_template.sh ./${TEST_DATA}/run_${dycore}jedi.sh

# Stream editor to edit files. Use "#" instead of "/" since we have "/" in paths.
cd ${YOUR_EXPERIMENT_DIR}/${TEST_DATA}
sed -i "s#@YOUR_PATH_TO_RDASAPP@#${YOUR_PATH_TO_RDASAPP}#g" ./run_${dycore}jedi.sh
sed -i "s#@YOUR_EXPERIMENT_DIR@#${YOUR_EXPERIMENT_DIR}#g"   ./run_${dycore}jedi.sh
sed -i "s#@SLURM_ACCOUNT@#${SLURM_ACCOUNT}#g"               ./run_${dycore}jedi.sh

# Copy visualization package.
cp -p $YOUR_PATH_TO_RDASAPP/rrfs-test/ush/colormap.py .
if [[ $DYCORE == "FV3" ]]; then
  cp -p $YOUR_PATH_TO_RDASAPP/rrfs-test/ush/fv3jedi_increment_singleob.py .
  cp -p $YOUR_PATH_TO_RDASAPP/rrfs-test/ush/fv3jedi_increment_fulldom.py .
elif [[ $DYCORE == "MPAS" ]]; then
  cp -p $YOUR_PATH_TO_RDASAPP/rrfs-test/ush/mpasjedi_increment_singleob.py .
  cp -p $YOUR_PATH_TO_RDASAPP/rrfs-test/ush/mpasjedi_increment_fulldom.py .
fi
if [[ $GSI_TEST_DATA == "YES" && $DYCORE == "FV3" ]]; then
  cp -p $YOUR_PATH_TO_RDASAPP/rrfs-test/ush/fv3jedi_gsi_validation.py .
  cp -p $YOUR_PATH_TO_RDASAPP/rrfs-test/ush/fv3jedi_gsi_increment_singleob.py .
fi

# Copy rrts-test yamls and obs files.
mkdir -p testinput
cp -p $YOUR_PATH_TO_RDASAPP/rrfs-test/testinput/* testinput/.
cp -p $YOUR_PATH_TO_RDASAPP/rrfs-test/obs/* Data/obs/.

# Copy GSI test data
if [[ $GSI_TEST_DATA == "YES" ]]; then
  echo "  --> gsi data on $platform"
  cd $YOUR_EXPERIMENT_DIR
  if [[ $platform == "hera" ]]; then
    rsync -a /scratch2/NCEPDEV/fv3-cam/Donald.E.Lippi/RRFSv2/staged-data/gsi_2022052619 .
  elif [[ $platform == "orion" ]]; then
    rsync -a /work/noaa/fv3-cam/dlippi/RRFSv2/staged-data/gsi_2022052619 .
  fi
  cd gsi_2022052619
  cp -p $YOUR_PATH_TO_RDASAPP/rrfs-test/scripts/templates/run_gsi_template.sh run_gsi.sh
  sed -i "s#@YOUR_PATH_TO_GSI@#${YOUR_PATH_TO_GSI}#g" ./run_gsi.sh
  sed -i "s#@SLURM_ACCOUNT@#${SLURM_ACCOUNT}#g"       ./run_gsi.sh
  cp -p $YOUR_PATH_TO_RDASAPP/rrfs-test/scripts/templates/run_gsi_ncdiag_template.sh run_gsi_ncdiag.sh
  sed -i "s#@YOUR_PATH_TO_RDASAPP@#${YOUR_PATH_TO_RDASAPP}#g" ./run_gsi_ncdiag.sh
  cp -p $YOUR_PATH_TO_RDASAPP/rrfs-test/obs/* Data/obs/.
  ln -sf ${YOUR_PATH_TO_GSI}/build/src/gsi/gsi.x .
fi

# Copy EVA scripts
if [[ $EVA == "YES" ]]; then
  echo "  --> eva scripts on $platform"
  cd $YOUR_EXPERIMENT_DIR
  rsync -a $YOUR_PATH_TO_RDASAPP/ush/eva .
  cd eva
  cp -p $YOUR_PATH_TO_RDASAPP/rrfs-test/scripts/templates/run_eva_template.sh run_eva.sh
  sed -i "s#@YOUR_PATH_TO_RDASAPP@#${YOUR_PATH_TO_RDASAPP}#g" ./run_eva.sh
fi

echo "done."
END=$(date +%s)
DIFF=$((END - START))
echo "Time taken to run the code: $DIFF seconds"
