#!/bin/bash

# This script is used to set up a GSI experiment using the FV3-LAM test data in RDASApp
# This is useful for running parallel GSI experiments against FV3-JEDI 
# GSI fix files and namelists follow the configurations from RRFSv1
# There are two options for YOUR_GSI_CASE right now:
#	2024052700 (matches MPAS-JEDI case)
#	2022052619

###### USER INPUT #####
SLURM_ACCOUNT="fv3-cam"
YOUR_EXPERIMENT_DIR="/path/to/your/desired/experiment/directory/jedi-assim_test"
YOUR_PATH_TO_GSI="/path/to/your/installation/of/GSI"
YOUR_GSI_CASE="2024052700"
#######################

START=$(date +%s)
RDASApp=$( git rev-parse --show-toplevel 2>/dev/null )
source $RDASApp/ush/detect_machine.sh

# At the moment these are the only test data that exists.
if [[ $YOUR_GSI_CASE == "2022052619" ]]; then
  TEST_DATA="rrfs-data_fv3jedi_2022052619"
elif [[ $YOUR_GSI_CASE == "2024052700" ]]; then
  TEST_DATA="rrfs-data_fv3jedi_2024052700"
else
  echo "Not a valid GSI case: ${YOUR_GSI_CASE}."
  echo "exiting!!!"
  exit 2
fi

# Print current settings to the screen.
echo "Your current settings are:"
echo -e "\tYOUR_EXPERIMENT_DIR=$YOUR_EXPERIMENT_DIR"
echo -e "\tSLURM_ACCOUNT=$SLURM_ACCOUNT"
echo -e "\tYOUR_PATH_TO_GSI=$YOUR_PATH_TO_GSI"

# Get current machine so we can find GSI fix data 
case ${MACHINE_ID} in
  hera)
    RDAS_DATA=/scratch1/NCEPDEV/fv3-cam/RDAS_DATA
    ;;
  jet)
    RDAS_DATA=/lfs4/BMC/nrtrr/RDAS_DATA
    ;;
  orion|hercules)
    RDAS_DATA=/work/noaa/rtrr/RDAS_DATA
    ;;
  *)
    echo "platform not supported: ${MACHINE_ID}"
    exit 3
    ;;
esac

# Ensure experiment directory exists, then move into that space.
mkdir -p $YOUR_EXPERIMENT_DIR
cd $YOUR_EXPERIMENT_DIR

# Copy GSI data
rsync -a ${RDAS_DATA}/gsi_${YOUR_GSI_CASE}/* .

# Copy some fix files from RDASApp repo
cp -p $RDASApp/rrfs-test/gsi_fix/anavinfo           ./anavinfo
cp -p $RDASApp/rrfs-test/gsi_fix/convinfo           ./convinfo
cp -p $RDASApp/rrfs-test/gsi_fix/errtable           ./errtable
cp -p $RDASApp/rrfs-test/gsi_fix/gsiparm.anl        ./gsiparm.anl

# Copy run scripts and plotting scripts
cp -p $RDASApp/rrfs-test/scripts/templates/run_gsi_template.sh run_gsi.sh
sed -i "s#@YOUR_PATH_TO_GSI@#${YOUR_PATH_TO_GSI}#g" ./run_gsi.sh
sed -i "s#@SLURM_ACCOUNT@#${SLURM_ACCOUNT}#g"       ./run_gsi.sh
sed -i "s#@MACHINE_ID@#${MACHINE_ID}#g"             ./run_gsi.sh
sed -i "s#@ANAL_TIME@#${YOUR_GSI_CASE}#g"           ./run_gsi.sh
cp -p $RDASApp/rrfs-test/ush/fv3gsi_increment_fulldom.py .

echo "done."
END=$(date +%s)
DIFF=$((END - START))
echo "Time taken to run the code: $DIFF seconds"
