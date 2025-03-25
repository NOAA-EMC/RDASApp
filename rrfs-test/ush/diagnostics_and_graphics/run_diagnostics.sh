#!/bin/bash
# This script is the main driver for generating various diagnostic plots
# related to data assimilation. It processes log files and diagnostic files
# from an experiment, producing visualizations to analyze observation impact
# and model performance.
#
# Supported diagnostic scripts:
# - heatmap_jo.py           : Generates heatmaps for Nonlinear Jo values,
#                             observation counts, Jo/n, and Jo/n percent change.
# - heatmap_rms_bias.py     : Creates heatmaps for bias and RMS statistics
#                             from diagnostic files.
# - heatmap_sanity_check.py : Performs a sanity check on a single heatmap
#                             cell to ensure correctness.
# - profile_rms_bias.py     : Produces vertical profile plots of bias and
#                             RMS statistics using pressure as the
#                             vertical coordinate.
# - map_ombg.py             : Creates 2d map scatter of ombg values with bias
#                             and rms stats displayed.
#
# This script automates the process by:
# - Iterating over a range of dates and processing log and diagnostic files
#   for each analysis cycle.
# - Supporting optional uploads of generated plots to an external web server.
#
# Usage:
# - Set the required variables below to define the experiment, date range,
#   and desired plots.
# - Enable or disable specific plot generation by setting HEATMAP_JO,
#   HEATMAP_RMS_BIAS, PROFILE_RMS_BIAS, etc.
# - Run the script to generate the required diagnostics and optionally upload
#   results.

#### DEFAULTS #######
HEATMAP_JO="NO"
HEATMAP_RMS_BIAS="NO"
PROFILE_RMS_BIAS="NO"
HEATMAP_SANITY="NO"
MAP_OMBG="NO"
UPLOAD_TO_RZDM="NO"
#### END DEFAULTS ###


#### USER-DEFINED VARIABLES #################################################
# Cycle start and end dates to process
SDATE=2024052700
EDATE=2024052700

# Specify which functions to run (uncomment/comment to turn on/off)
HEATMAP_JO="YES"
HEATMAP_RMS_BIAS="YES"
PROFILE_RMS_BIAS="YES"
MAP_OMBG="YES"
#UPLOAD_TO_RZDM="YES"
#HEATMAP_SANITY="YES"

# Retro experiment details (similar to rrfs-workflow/workflow/exp.setup)
VERSION="v2.0.9.7"
TAG="d12km2097"
EXP_NAME="hrly_12km"
OPSROOT="/scratch2/NCEPDEV/fv3-cam/Donald.E.Lippi/RRFSv2/workflow/${VERSION}"
COMROOT="${OPSROOT}/exp/${EXP_NAME}/com"
DATAROOT="${OPSROOT}/exp/${EXP_NAME}/stmp"

# Specify your RDASApp build (mostly for module loads)
RDASApp="/scratch2/NCEPDEV/fv3-cam/Donald.E.Lippi/RRFSv2/PRs/RDASApp.20241204.phase2_sonde"

# Specify the log and jdiag directories
LOGDIR="${COMROOT}/rrfs/${VERSION}/logs"
JDIAGDIR="${DATAROOT}"

# Options only for sanity checks
CYC=02
OBTYPE="msonet_airTemperature_188"

# Options only for RZDM
USER="donald.lippi"
HOST="emcrzdm.ncep.noaa.gov"
DESTINATION="/home/www/emc/htdocs/mmb/dlippi/rrfs-workflow_v2/DA_monitoring/."
#### END OF USER-DEFINED VARIABLES ##########################################

# Start main execution
START=$(date +%s)

# Load necessary environment
module purge
module use ${RDASApp}/modulefiles
module load EVA/hera

# Load ndate
export ndate=$(which ndate)

if [[ -z "$ndate" ]]; then
  echo "Error: ndate command not found. Please ensure it is installed and available in your PATH." >&2
  exit 1
fi

# Initialize pdy list
pdy_list=()

# Initialize date with start date
date=${SDATE}

# Loop over dates from start to and including end date
while [[ ${date} -le ${EDATE} ]]; do
  pdy=${date:0:8}
  pdy_list+=("${pdy}")
  mkdir -p ${EXP_NAME}/${pdy}

  # Plots nobs, Jo, Jo/n, and Jo/n percent change (from log files)
  if [[ ${HEATMAP_JO} == "YES" ]]; then
    echo "? Working on jo info heatmaps: ${pdy}"
    logs=(${LOGDIR}/rrfs.${pdy}/*/det/rrfs_jedivar_${TAG}_${pdy}*.log)
    #echo "${logs[1]}"; exit
    python heatmap_jo.py ${logs[@]}
    mv ${pdy}*.png ${EXP_NAME}/${pdy}/.
  fi

  # Plots rms and bias (from jdiag files)
  if [[ ${HEATMAP_RMS_BIAS} == "YES" ]]; then
    echo "? Working on rms & bias heatmaps: ${pdy}"
    jdiags=(${JDIAGDIR}/${pdy}/rrfs_jedivar_*_${VERSION}/det/jedivar_*/jdiag*)
    #echo "${jdiags[1]}"; exit
    python heatmap_rms_bias.py ${jdiags[@]}
    mv ${pdy}*.png ${EXP_NAME}/${pdy}/.
  fi

  # Sanity check rms and bias for a single heatmap cell (from log files)
  if [[ $HEATMAP_SANITY == "YES" ]]; then
    jdiag="${JDIAGDIR}/${pdy}/rrfs_jedivar_${CYC}_${VERSION}/det/jedivar_${CYC}/jdiag_${OBTYPE}*"
    echo "? Working on sanity check: ${pdy}, ${CYC}, ${OBTYPE}"
    python heatmap_sanity_check.py $jdiag
  fi

  # Plts 2d map plots of rms and bias (from jdiag files)
  if [[ ${MAP_OMBG} == "YES" ]]; then
    echo "? Working on map ombg: ${date}"
    jdiags=(${JDIAGDIR}/${pdy}/rrfs_jedivar_01_${VERSION}/det/jedivar_*/jdiag*33*)
    jdiags+=(${JDIAGDIR}/${pdy}/rrfs_jedivar_01_${VERSION}/det/jedivar_*/jdiag*88*)
    python map_ombg.py ${jdiags[@]}
    mv ${pdy}*map.png ${EXP_NAME}/${pdy}/.
  fi

  # Increase date by 1 day
  date=$(${ndate} 24 ${date})
done #date

# START OF CYCLE-AVERAGED DIAGNOSTIC TOOLS

# Plots vertical profiles of rms and bias (from jdiag files) over a date range.
if [[ ${PROFILE_RMS_BIAS} == "YES" ]]; then
  echo "? Working on profiles: ${SDATE} to ${EDATE}"
  jdiags=(${JDIAGDIR}/*/rrfs_jedivar_*_${VERSION}/det/jedivar_*/jdiag*33*)
  python profile_rms_bias.py ${jdiags[@]}
  mv profile*.png ${EXP_NAME}/.
fi

# Upload restults to RZDM
if [[ ${UPLOAD_TO_RZDM} == "YES" ]]; then
  for pdy in ${pdy_list[@]}; do

    # Create the files necessary for rzdm to display the images.
    for dir in "${EXP_NAME}" "${EXP_NAME}/${pdy}"; do
      echo "<?php require \$_SERVER['DOCUMENT_ROOT'].\"/ncep_common/dirlist.php\"; ?>" > "${dir}/index.php"
      printf "*.png\n20*\n${EXP_NAME}" > "${dir}/allow.cfg"
    done
  done

  # Copy the data to rzdm
  #scp ${pdy_list[@]/%/*.png} ${USER}@${HOST}:${DESTINATION} #YYYYMMDD*png
  #scp -r ${pdy_list[@]/%//} ${USER}@${HOST}:${DESTINATION}  #YYYYMMDD/
  scp -r ${EXP_NAME} ${USER}@${HOST}:${DESTINATION}
fi

# Calculate runtime statistics
END=$(date +%s)
DIFF=$((END - START))
echo "Time taken to run the code: $DIFF seconds"

exit 0

# Incase you specified your experiment/com and stmp wrong, you can use the following
# examples to rsync retaining the directory structre copying only that specified by
# "--include" option. This would be run at the level of the com/ and stmp/ directories.
# Ensure the exp/${EXP_NAME} relative path is correct.

#rsync -avm --include='*/' --include='rrfs_jedivar*.log' --exclude='*' com exp/hrly_12km/.
#rsync -avm --include='*/' --include='jdiag*' --exclude='*' stmp exp/hrly_12km/.
