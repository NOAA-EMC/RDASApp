#!/bin/bash

START=$(date +%s)

# This script is used after compiling RDASApp CLONE_RRFSDATA="YES" (default).
# This script helps a user set up an experiment directory.

###### USER INPUT #####
SLURM_ACCOUNT="fv3-cam"
DYCORE="MPAS" #MPAS | FV3
YOUR_PATH_TO_RDASAPP="/path/to/your/installation/of/RDASApp"
YOUR_EXPERIMENT_DIR="/path/to/your/desired/experiment/directory/jedi-assim_test"
GSI_TEST_DATA="NO"
YOUR_PATH_TO_GSI="/path/to/your/installation/of/GSI"
EVA="NO"
#######################

source $YOUR_PATH_TO_RDASAPP/ush/detect_machine.sh

# Print current settings to the screen.
echo "Your current settings are:"
echo -e "\tYOUR_PATH_TO_RDASAPP=$YOUR_PATH_TO_RDASAPP"
echo -e "\tYOUR_EXPERIMENT_DIR=$YOUR_EXPERIMENT_DIR"
echo -e "\tSLURM_ACCOUNT=$SLURM_ACCOUNT"
echo -e "\tDYCORE=$DYCORE"
echo -e "\tMACHINE_ID=$MACHINE_ID"
echo -e "\tGSI_TEST_DATA=$GSI_TEST_DATA"
echo -e "\tYOUR_PATH_TO_GSI=$YOUR_PATH_TO_GSI"
echo -e "\tEVA=$EVA\n"

# Check to see if user changed the paths to something valid.
if [[ ! -d $YOUR_PATH_TO_RDASAPP || ! -d `dirname $YOUR_EXPERIMENT_DIR` ]]; then
  echo "Please make sure to edit the USER INPUT BLOCK before running $0."
  echo "exiting!!!"
  exit 1
fi

# At the moment these are the only test data that exists.
# It also seems the best to just do either FV3 or MPAS data each time script is run.
if [[ $DYCORE == "FV3" ]]; then
  TEST_DATA="rrfs-data_fv3jedi_2022052619"
elif [[ $DYCORE == "MPAS" ]]; then
  TEST_DATA="mpas_2024052700"
else
  echo "Not a valid DYCORE: ${DYCORE}. Please use MPAS | FV3."
  echo "exiting!!!"
  exit 2
fi

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

# Lowercase dycore for script names.
declare -l dycore="$DYCORE"

# Ensure experiment directory exists, then move into that space.
mkdir -p $YOUR_EXPERIMENT_DIR
cd $YOUR_EXPERIMENT_DIR

# Copy the test data into the experiment directory.
echo "Copying data. This will take just a moment."
echo "  --> ${dycore}-jedi data on $MACHINE_ID"
if [[ $DYCORE == "FV3" ]]; then
  # Data volume isn't too large so copy/rsync is fine.
  rsync -a $YOUR_PATH_TO_RDASAPP/bundle/rrfs-test-data/${TEST_DATA} .
elif [[ $DYCORE == "MPAS" ]]; then
  # Data volume is pretty large so link what we can.
  mkdir -p ${TEST_DATA}
  cd ${TEST_DATA}
  mkdir -p fix
  ln -sf ${RDAS_DATA}/fix/* fix/.
  ln -sf ${RDAS_DATA}/fix/physics/* .
  mkdir -p graphinfo stream_list
  ln -sf ${RDAS_DATA}/fix/graphinfo/* graphinfo/
  cp -rp ${RDAS_DATA}/fix/stream_list/* stream_list/
  cp ${YOUR_PATH_TO_RDASAPP}/rrfs-test/testinput_expr/rrfs_mpasjedi_2024052700_bumploc.yaml .
  cp ${YOUR_PATH_TO_RDASAPP}/rrfs-test/testinput_expr/namelist.atmosphere .
  cp ${YOUR_PATH_TO_RDASAPP}/rrfs-test/testinput_expr/rrfs_mpasjedi_2024052700_Ens3Dvar.yaml .
  cp ${YOUR_PATH_TO_RDASAPP}/rrfs-test/testinput_expr/rrfs_mpasjedi_2024052700_Hybrid.yaml .
  cp ${YOUR_PATH_TO_RDASAPP}/rrfs-test/testinput_expr/rrfs_mpasjedi_2024052700_letkf.yaml .
  cp ${YOUR_PATH_TO_RDASAPP}/rrfs-test/testinput_expr/rrfs_mpasjedi_2024052700_getkf.yaml .
  cp ${YOUR_PATH_TO_RDASAPP}/rrfs-test/testinput_expr/streams.atmosphere .
  cp ${YOUR_PATH_TO_RDASAPP}/sorc/mpas-jedi/test/testinput/obsop_name_map.yaml .
  cp ${YOUR_PATH_TO_RDASAPP}/sorc/mpas-jedi/test/testinput/namelists/keptvars.yaml .
  cp ${YOUR_PATH_TO_RDASAPP}/sorc/mpas-jedi/test/testinput/namelists/geovars.yaml .
  mkdir -p data; cd data
  mkdir -p bumploc bkg obs ens
  ln -snf ${YOUR_PATH_TO_RDASAPP}/fix/bumploc/* bumploc/.
  ln -snf ${YOUR_PATH_TO_RDASAPP}/fix/B_static/L55_20241204 B_static
  ln -snf ${YOUR_PATH_TO_RDASAPP}/fix/expr_data/${TEST_DATA}/bkg/mpasout.2024-05-27_00.00.00.nc .
  ln -snf ${YOUR_PATH_TO_RDASAPP}/fix/expr_data/${TEST_DATA}/invariant.nc invariant.nc
  ln -snf ${YOUR_PATH_TO_RDASAPP}/fix/expr_data/${TEST_DATA}/obs/* obs/
  ln -snf ${YOUR_PATH_TO_RDASAPP}/fix/expr_data/${TEST_DATA}/ens/* ens/
  cp -p $YOUR_PATH_TO_RDASAPP/rrfs-test/scripts/templates/run_bump_template.sh run_bump.sh
  sed -i "s#@YOUR_PATH_TO_RDASAPP@#${YOUR_PATH_TO_RDASAPP}#g" ./run_bump.sh
  sed -i "s#@SLURM_ACCOUNT@#${SLURM_ACCOUNT}#g"               ./run_bump.sh
  sed -i "s#@MACHINE_ID@#${MACHINE_ID}#g"                     ./run_bump.sh
  cd $YOUR_EXPERIMENT_DIR
fi

# Copy the template run script which will be updated according to the user input
cp -p $YOUR_PATH_TO_RDASAPP/rrfs-test/scripts/templates/run_${dycore}jedi_template.sh ./${TEST_DATA}/run_${dycore}jedi.sh

# Stream editor to edit files. Use "#" instead of "/" since we have "/" in paths.
cd ${YOUR_EXPERIMENT_DIR}/${TEST_DATA}
sed -i "s#@YOUR_PATH_TO_RDASAPP@#${YOUR_PATH_TO_RDASAPP}#g" ./run_${dycore}jedi.sh
sed -i "s#@YOUR_EXPERIMENT_DIR@#${YOUR_EXPERIMENT_DIR}#g"   ./run_${dycore}jedi.sh
sed -i "s#@SLURM_ACCOUNT@#${SLURM_ACCOUNT}#g"               ./run_${dycore}jedi.sh
sed -i "s#@MACHINE_ID@#${MACHINE_ID}#g"                     ./run_${dycore}jedi.sh

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
#mkdir -p testinput
#cp -p $YOUR_PATH_TO_RDASAPP/rrfs-test/testinput_expr/* testinput/.
#cp -p $YOUR_PATH_TO_RDASAPP/rrfs-test/obs/* Data/obs/.

# Copy GSI test data
if [[ $GSI_TEST_DATA == "YES" ]]; then
  echo "  --> gsi data on $MACHINE_ID"
  cd $YOUR_EXPERIMENT_DIR
  if [[ $MACHINE_ID == "hera" ]]; then
    rsync -a /scratch2/NCEPDEV/fv3-cam/Donald.E.Lippi/RRFSv2/staged-data/gsi_2022052619 .
  elif [[ $MACHINE_ID == "orion" ]]; then
    rsync -a /work/noaa/fv3-cam/dlippi/RRFSv2/staged-data/gsi_2022052619 .
  elif [[ $MACHINE_ID == "jet" ]]; then
    rsync -a /lfs4/BMC/nrtrr/RDAS_DATA/gsi_2022052619 .
  fi
  cd gsi_2022052619
  cp -p $YOUR_PATH_TO_RDASAPP/rrfs-test/scripts/templates/run_gsi_template.sh run_gsi.sh
  sed -i "s#@YOUR_PATH_TO_GSI@#${YOUR_PATH_TO_GSI}#g" ./run_gsi.sh
  sed -i "s#@SLURM_ACCOUNT@#${SLURM_ACCOUNT}#g"       ./run_gsi.sh
  sed -i "s#@MACHINE_ID@#${MACHINE_ID}#g"             ./run_gsi.sh
  sed -i "s#ANAL_TIME@#2022052619#g"                  ./run_gsi.sh
  cp -p $YOUR_PATH_TO_RDASAPP/rrfs-test/scripts/templates/run_gsi_ncdiag_template.sh run_gsi_ncdiag.sh
  sed -i "s#@YOUR_PATH_TO_RDASAPP@#${YOUR_PATH_TO_RDASAPP}#g" ./run_gsi_ncdiag.sh
  sed -i "s#@MACHINE_ID@#${MACHINE_ID}#g"                     ./run_gsi_ncdiag.sh
  cp -p $YOUR_PATH_TO_RDASAPP/rrfs-test/obs/* Data/obs/.
  ln -sf ${YOUR_PATH_TO_GSI}/build/src/gsi/gsi.x .
fi

# Copy EVA scripts
if [[ $EVA == "YES" ]]; then
  echo "  --> eva scripts on $MACHINE_ID"
  cd $YOUR_EXPERIMENT_DIR
  rsync -a $YOUR_PATH_TO_RDASAPP/ush/eva .
  cd eva
  cp -p $YOUR_PATH_TO_RDASAPP/rrfs-test/scripts/templates/run_eva_template.sh run_eva.sh
  sed -i "s#@YOUR_PATH_TO_RDASAPP@#${YOUR_PATH_TO_RDASAPP}#g" ./run_eva.sh
  sed -i "s#@MACHINE_ID@#${MACHINE_ID}#g"                     ./run_eva.sh
fi

echo "done."
END=$(date +%s)
DIFF=$((END - START))
echo "Time taken to run the code: $DIFF seconds"
