#!/bin/bash
# This script is the main driver for generating various diagnostic plots
# related to data assimilation. It processes log files and diagnostic files
# from an experiment, producing visualizations to analyze observation impact
# and model performance.
#
# Supported diagnostic scripts:
# - heatmap_jo.py           : Generates heatmaps for Nonlinear Jo values,
#                             observation counts, Jo/n, and Jo/n percent change.
# - heatmap_rms_bias_fit.py : Creates heatmaps for bias and RMS statistics
#                             from diagnostic files and fitting ratio.
# - profile_rms_bias_fit.py : Produces vertical profile plots of bias and
#                             RMS statistics using pressure as the
#                             vertical coordinate.
# - map_ombg_oman.py        : Creates 2d map scatter of ombg/an values with bias
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
#   HEATMAP_RMS_BIAS_FIT, PROFILE_RMS_BIAS_FIT, etc.
# - Run the script to generate the required diagnostics and optionally upload
#   results.

#### DEFAULTS #######
HEATMAP_JO="NO"
HEATMAP_RMS_BIAS_FIT="NO"
PROFILE_RMS_BIAS_FIT="NO"
MAP_OMBG_OMAN="NO"
UPLOAD_TO_RZDM="NO"
#### END DEFAULTS ###

#### USER-DEFINED VARIABLES #################################################

# Specify which functions to run (uncomment/comment to turn on/off)
#HEATMAP_JO="YES"
#HEATMAP_RMS_BIAS_FIT="YES"
#PROFILE_RMS_BIAS_FIT="YES"
#MAP_OMBG_OMAN="YES"
UPLOAD_TO_RZDM="YES"

# Cycle start and end dates to process
SDATE=2024052700
EDATE=2024052700

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
    python heatmap_jo.py ${logs[@]}
    mv ${pdy}*.png ${EXP_NAME}/${pdy}/.
  fi

  # Plots rms and bias (from jdiag files)
  if [[ ${HEATMAP_RMS_BIAS_FIT} == "YES" ]]; then
    echo "? Working on rms, bias, fitting ratio heatmaps: ${pdy}"
    jdiags=(${JDIAGDIR}/${pdy}/rrfs_jedivar_*_${VERSION}/det/jedivar_*/jdiag*)
    python heatmap_rms_bias_fit.py ${jdiags[@]}
    mv ${pdy}*.png ${EXP_NAME}/${pdy}/.
  fi

  # Plots 2d map scatter of ombg values (from jdiag) with bias and rms stats displayed.
  if [[ ${MAP_OMBG_OMAN} == "YES" ]]; then
    echo "? Working on map ombg & oman: ${date}"
    jdiags=(${JDIAGDIR}/${pdy}/rrfs_jedivar_01_${VERSION}/det/jedivar_*/jdiag*33*)
    #jdiags+=(${JDIAGDIR}/${pdy}/rrfs_jedivar_01_${VERSION}/det/jedivar_*/jdiag*88*)
    python map_ombg_oman.py ${jdiags[@]}
    mv ${pdy}*map.png ${EXP_NAME}/${pdy}/.
  fi

  # Increase date by 1 day
  date=$(${ndate} 24 ${date})
done # date loop

# START OF CYCLE-AVERAGED DIAGNOSTIC TOOLS

# Plots vertical profiles of rms and bias (from jdiag files) over a date range.
if [[ ${PROFILE_RMS_BIAS_FIT} == "YES" ]]; then
  spdy=${SDATE:0:8}
  epdy=${EDATE:0:8}
  echo "? Working on profiles: ${spdy}00 to ${edpy}23"
  jdiags=(${JDIAGDIR}/*/rrfs_jedivar_*_${VERSION}/det/jedivar_*/jdiag*33*)
  python profile_rms_bias_fit.py ${jdiags[@]}
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
