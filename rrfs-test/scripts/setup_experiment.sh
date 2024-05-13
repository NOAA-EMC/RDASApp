#!/bin/bash

# This script is used after compiling RDASApp with -r option which downloads
# RRFS test data. This script helps a user set up an experiment directory.

###### USER INPUT #####
YOUR_PATH_TO_RDASAPP="/path/to/your/installation/of/RDASApp"
YOUR_EXPERIMENT_DIR="/path/to/your/desired/experiment/directory/jedi-assim_test"
SLURM_ACCOUNT="fv3-cam"
DYCORE="FV3" #FV3 or MPAS
YAML="${YOUR_PATH_TO_RDASAPP}/rrfs-test/testinput/rrfs_fv3jedi_hyb_2022052619.yaml" # test yaml you want to run
EXE="fv3jedi_var.x" # executable corresponding to this test
platform="hera" #hera or orion
GSI_TEST_DATA="YES"
YOUR_PATH_TO_GSI="/path/to/your/installation/of/GSI"
#######################

# Print current setting to the screen.
echo "Your current settings are:"
echo -e "\tYOUR_PATH_TO_RDASAPP=$YOUR_PATH_TO_RDASAPP"
echo -e "\tYOUR_EXPERIMENT_DIR=$YOUR_EXPERIMENT_DIR"
echo -e "\tSLURM_ACCOUNT=$SLURM_ACCOUNT"
echo -e "\tDYCORE=$DYCORE"
echo -e "\tDA_METHOD=$DA_METHOD"
echo -e "\tplatform=$platform"
echo -e "\tGSI_TEST_DATA=$GSI_TEST_DATA"
echo -e "\tYOUR_PATH_TO_GSI=$YOUR_PATH_TO_GSI\n"


# Check to see if user changed the paths to something valid.
if [[ ! -d $YOUR_PATH_TO_RDASAPP || ! -d `dirname $YOUR_EXPERIMENT_DIR` ]]; then
  echo "Please make sure to edit the USER INPUT BLOCK before running $0."
  echo "exiting!!!"
  exit 1
fi

# Error check if choosing LETKF for MPAS 
if [[ $DYCORE == "MPAS" && $DA_METHOD == "LETKF" ]]; then
   echo "ERROR: LETKF is not yet implemented for MPAS"
   exit 1
fi 

# At the moment these are the only test data that exists. Maybe become user input later?
# It also seems the best to just do either FV3 or MPAS data each time script is run.
# NOTE: Currently using same hybrid input data for LETKF test case
if [[ $DYCORE == "FV3" ]]; then
  INPUT_DATA="rrfs-data_fv3jedi_2022052619"
elif [[ $DYCORE == "MPAS" ]]; then
  INPUT_DATA="rrfs-data_mpasjedi_2022052619"
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
YAML_NOFILETYPE=${YAML::-5}
YOUR_EXPERIMENT_DIR="${YOUR_EXPERIMENT_DIR}/rundir-$(basename ${YAML_NOFILETYPE})"
mkdir -p $YOUR_EXPERIMENT_DIR
cd $YOUR_EXPERIMENT_DIR

# Copy the test data into the experiment directory.
# Need some special handling of LETKF since using the same input data as hybrid cases
echo "Copying data. This may take awhile."
echo "  --> ${dycore}-jedi data on $platform"
if [[ $DYCORE == "FV3" ]]; then 
   ln -sf ${YOUR_PATH_TO_RDASAPP}/bundle/rrfs-test-data/${INPUT_DATA}/DataFix ./
   ln -sf ${YOUR_PATH_TO_RDASAPP}/bundle/rrfs-test-data/${INPUT_DATA}/Data_static ./
   ln -sf ${YOUR_PATH_TO_RDASAPP}/bundle/rrfs-test-data/${INPUT_DATA}/Data ./
   ln -sf ${YOUR_PATH_TO_RDASAPP}/bundle/rrfs-test-data/${INPUT_DATA}/INPUT ./
elif [[ $DYCORE == "MPAS" ]]; then 
   ln -sf ${YOUR_PATH_TO_RDASAPP}/bundle/rrfs-test-data/${INPUT_DATA}/DataFix ./
   ln -sf ${YOUR_PATH_TO_RDASAPP}/bundle/rrfs-test-data/${INPUT_DATA}/Data_static ./
   ln -sf ${YOUR_PATH_TO_RDASAPP}/bundle/rrfs-test-data/${INPUT_DATA}/Data ./
   cp ${YOUR_PATH_TO_RDASAPP}/bundle/rrfs-test-data/${INPUT_DATA}/streams.atmosphere_15km ./
   cp ${YOUR_PATH_TO_RDASAPP}/bundle/rrfs-test-data/${INPUT_DATA}/namelist.atmosphere_15km ./
   cp ${YOUR_PATH_TO_RDASAPP}/bundle/rrfs-test-data/${INPUT_DATA}/geovars.yaml ./
   cp ${YOUR_PATH_TO_RDASAPP}/bundle/rrfs-test-data/${INPUT_DATA}/keptvars.yaml ./
   cp ${YOUR_PATH_TO_RDASAPP}/bundle/rrfs-test-data/${INPUT_DATA}/obsop_name_map.yaml ./
   cp ${YOUR_PATH_TO_RDASAPP}/bundle/rrfs-test-data/${INPUT_DATA}/*.*BL ./
   cp ${YOUR_PATH_TO_RDASAPP}/bundle/rrfs-test-data/${INPUT_DATA}/*DATA* ./
fi
cp ${YAML} ./

# Copy the template run script which will be updated according to the user input
cp -p $YOUR_PATH_TO_RDASAPP/rrfs-test/scripts/templates/run_${dycore}jedi_${platform}_template.sh ./${runpath}/run_${dycore}jedi_${platform}.sh

# Stream editor to edit files. Use "#" instead of "/" since we have "/" in paths.
cd ${YOUR_EXPERIMENT_DIR}/${runpath}
sed -i "s#@YOUR_PATH_TO_RDASAPP@#${YOUR_PATH_TO_RDASAPP}#g" ./run_${dycore}jedi_${platform}.sh
sed -i "s#@YOUR_EXPERIMENT_DIR@#${YOUR_EXPERIMENT_DIR}#g"   ./run_${dycore}jedi_${platform}.sh
sed -i "s#@SLURM_ACCOUNT@#${SLURM_ACCOUNT}#g"               ./run_${dycore}jedi_${platform}.sh
sed -i "s#@YAML@#$(basename ${YAML})#g"                                 ./run_${dycore}jedi_${platform}.sh
sed -i "s#@EXECUTABLE@#${EXE}#g"                            ./run_${dycore}jedi_${platform}.sh

# Copy visualization package.
cp -p $YOUR_PATH_TO_RDASAPP/rrfs-test/ush/colormap.py .
if [[ $DYCORE == "FV3" ]]; then

  cp -p $YOUR_PATH_TO_RDASAPP/rrfs-test/ush/fv3jedi_increment_singleob.py .
  cp -p $YOUR_PATH_TO_RDASAPP/rrfs-test/ush/fv3jedi_increment_fulldom.py .
elif [[ $DYCORE == "MPAS" ]]; then 
  cp -p $YOUR_PATH_TO_RDASAPP/rrfs-test/ush/mpasjedi_increment_singleob.py .
fi
if [[ $GSI_TEST_DATA == "YES" ]]; then
  cp -p $YOUR_PATH_TO_RDASAPP/rrfs-test/ush/fv3jedi-gsi-hofx-validation.py .
fi

# Copy rrts-test yamls and obs files.
mkdir -p testinput
cp -p $YOUR_PATH_TO_RDASAPP/rrfs-test/testinput/* testinput/.
cp -p $YOUR_PATH_TO_RDASAPP/rrfs-test/obs/* Data/obs/.

# Copy GSI test data
if [[ $GSI_TEST_DATA == "YES" ]]; then
  echo "  --> gsi data on $platform"
  cd $YOUR_EXPERIMENT_DIR
  # We will need to change this when we have it staged elsewhere.
#  rsync -a /scratch2/NCEPDEV/fv3-cam/Donald.E.Lippi/RRFSv2/jedi-assim_validation/gsi.clean .
#  mv gsi.clean gsi
  cd gsi
  cp -p $YOUR_PATH_TO_RDASAPP/rrfs-test/scripts/templates/run_gsi_${platform}_template.sh run_gsi_${platform}.sh
  sed -i "s#@YOUR_PATH_TO_GSI@#${YOUR_PATH_TO_GSI}#g" ./run_gsi_${platform}.sh
  sed -i "s#@SLURM_ACCOUNT@#${SLURM_ACCOUNT}#g"       ./run_gsi_${platform}.sh
  cp -p $YOUR_PATH_TO_RDASAPP/rrfs-test/scripts/templates/run_gsi_ncdiag_${platform}_template.sh run_gsi_ncdiag_${platform}.sh
  sed -i "s#@YOUR_PATH_TO_RDASAPP@#${YOUR_PATH_TO_RDASAPP}#g" ./run_gsi_ncdiag_${platform}.sh
  cp -p $YOUR_PATH_TO_RDASAPP/rrfs-test/obs/* Data/obs/.
  ln -sf ${YOUR_PATH_TO_GSI}/build/src/gsi/gsi.x .

fi

echo "done."
