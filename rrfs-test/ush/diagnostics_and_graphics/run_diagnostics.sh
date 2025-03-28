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
#                             from diagnostic files and fitting ratio. Compares
#                             stats across multiple observation types.
# - profile_rms_bias_fit.py : Produces vertical profile plots of bias and
#                             RMS statistics using pressure as the
#                             vertical coordinate.
# - map_ombg_oman.py        : Creates 2d map scatter of ombg/an values with bias
#                             and rms stats displayed.
# - hovmoller_rms_bias_fit.py    : Generates a hovmoller (pressure vs time) time series
#                                  (of vertical profiles) of rms, bias, and fitting ratio.
# - timeseries_rms_bias_fit.py   : Generates a time series (of whole column) of rms,
#                                  bias, and fitting ratio.
# - map_domainComparison_mpas_fv3: Overlays mpas and fv3 grids for domain comparison.
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
#
#
#### USER-DEFINED VARIABLES #################################################
# Specify which functions to run (uncomment/comment to turn on/off)
#HEATMAP_JO="YES"
HEATMAP_RMS_BIAS_FIT="YES"
#PROFILE_RMS_BIAS_FIT="YES"
#MAP_OMBG_OMAN="YES"
#HOVMOLLER_RMS_BIAS_FIT="YES"
#TIMESERIES_RMS_BIAS_FIT="YES"
#MAP_DOMAINCOMPARISON_MPAS_FV3="YES"
#UPLOAD_TO_RZDM="YES"

# Cycle start and end dates to process
SDATE=2024052700
EDATE=2024052700
#SDATE=2024050600
#EDATE=2024050600

# Retro experiment details (similar to rrfs-workflow/workflow/exp.setup)
VERSION="v2.0.9.7"
TAG="d12km2097"
EXP_NAME="hrly_12km"
#EXP_NAME="benchmark1"
OPSROOT="/scratch2/NCEPDEV/fv3-cam/Donald.E.Lippi/RRFSv2/workflow/${VERSION}"
COMROOT="${OPSROOT}/exp/${EXP_NAME}/com"
DATAROOT="${OPSROOT}/exp/${EXP_NAME}/stmp"

# Specify your RDASApp build (mostly for module loads)
RDASApp="/scratch2/NCEPDEV/fv3-cam/Donald.E.Lippi/RRFSv2/PRs/RDASApp.20241204.phase2_sonde"

# Specify the log and jdiag directories
LOGDIR="${COMROOT}/rrfs/${VERSION}/logs"
JDIAGDIR="${DATAROOT}"

# Options only for MAP_DOMAINCOMPARISON_MPAS_FV3
MPAS_DOMAIN=${RDASApp}/expr/mpas_2024052700/data/invariant.nc
FV3_DOMAIN=${RDASApp}/expr/fv3_2024052700/Data/bkg/grid_spec.nc

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
  if [[ ${HEATMAP_JO:=NO} == "YES" ]]; then
    echo "? Working on (${EXP_NAME}) jo info heatmaps: ${pdy}"
    logs=(${LOGDIR}/rrfs.${pdy}/*/det/rrfs_jedivar_${TAG}_${pdy}*.log)
    python heatmap_jo.py ${logs[@]}
    mkdir -p ${EXP_NAME}/${pdy}/heatmap
    mv ${pdy}*.png ${EXP_NAME}/${pdy}/heatmap/.
  fi

  # Plots rms and bias (from jdiag files)
  if [[ ${HEATMAP_RMS_BIAS_FIT:=NO} == "YES" ]]; then
    echo "? Working on (${EXP_NAME}) rms, bias, fitting ratio heatmaps: ${pdy}"
    jdiags=(${JDIAGDIR}/${pdy}/rrfs_jedivar_*_${VERSION}/det/jedivar_*/jdiag*)
    python heatmap_rms_bias_fit.py ${jdiags[@]}
    mkdir -p ${EXP_NAME}/${pdy}/heatmap
    mv ${pdy}*.png ${EXP_NAME}/${pdy}/heatmap/.
  fi

  # Plots 2d map scatter of ombg values (from jdiag) with bias and rms stats displayed.
  if [[ ${MAP_OMBG_OMAN:=NO} == "YES" ]]; then
    echo "? Working on (${EXP_NAME}) map ombg & oman: ${date}"
    jdiags=(${JDIAGDIR}/${pdy}/rrfs_jedivar_0[1-3]_${VERSION}/det/jedivar_*/jdiag*Temp*33*)
    jdiags+=(${JDIAGDIR}/${pdy}/rrfs_jedivar_0[1-3]_${VERSION}/det/jedivar_*/jdiag*Temp*88*)
    python map_ombg_oman.py ${jdiags[@]}
    mkdir -p ${EXP_NAME}/${pdy}/map
    mv ${pdy}*map.png ${EXP_NAME}/${pdy}/map/.
  fi

  # Increase date by 1 day
  date=$(${ndate} 24 ${date})
done # date loop

# START OF CYCLE-AVERAGED DIAGNOSTIC TOOLS AND TIMESERIES TYPE PLOTS

spdy=${SDATE:0:8}
epdy=${EDATE:0:8}
# Plots vertical profiles of rms and bias (from jdiag files) over a date range.
if [[ ${PROFILE_RMS_BIAS_FIT:=NO} == "YES" ]]; then
  echo "? Working on (${EXP_NAME}) profiles: ${spdy}00 to ${epdy}23"
  jdiags=(${JDIAGDIR}/*/rrfs_jedivar_*_${VERSION}/det/jedivar_*/jdiag*33*)
  python profile_rms_bias_fit.py ${jdiags[@]}
  mkdir -p ${EXP_NAME}/profile
  mv profile*.png ${EXP_NAME}/profile/.
fi

if [[ ${HOVMOLLER_RMS_BIAS_FIT:=NO} == "YES" ]]; then
  echo "? Working on (${EXP_NAME}) hovmoller: ${spdy}00 to ${epdy}23"
  jdiags=(${JDIAGDIR}/*/rrfs_jedivar_*_${VERSION}/det/jedivar_*/jdiag*33*)
  python hovmoller_rms_bias_fit.py ${jdiags[@]}
  mkdir -p ${EXP_NAME}/hovmoller
  mv hovmoller*.png ${EXP_NAME}/hovmoller/.
fi

if [[ ${TIMESERIES_RMS_BIAS_FIT:=NO} == "YES" ]]; then
  echo "? Working on (${EXP_NAME}) timeseries: ${spdy}00 to ${epdy}23"
  jdiags=(${JDIAGDIR}/*/rrfs_jedivar_*_${VERSION}/det/jedivar_*/jdiag*33*)
  python timeseries_rms_bias_fit.py ${jdiags[@]}
  mkdir -p ${EXP_NAME}/timeseries
  mv timeseries*.png ${EXP_NAME}/timeseries/.
fi

if [[ ${MAP_DOMAINCOMPARISON_MPAS_FV3:=NO} == "YES" ]]; then
  echo "? Working on (${EXP_NAME}) map domain comparison mpas vs fv3."
  python map_domainComparison_mpas_fv3.py ${MPAS_DOMAIN} ${FV3_DOMAIN}
  mkdir -p ${EXP_NAME}/
  mv *domain*comparison*.png ${EXP_NAME}/.
fi

# Upload restults to RZDM
if [[ ${UPLOAD_TO_RZDM:=NO} == "YES" ]]; then
  directories=("${EXP_NAME}"
               "${EXP_NAME}/${pdy}"
               "${EXP_NAME}/hovmoller"
               "${EXP_NAME}/timeseries"
               "${EXP_NAME}/profile"
               "${EXP_NAME}/${pdy}/heatmap"
               "${EXP_NAME}/${pdy}/map")

  for pdy in ${pdy_list[@]}; do
    # Create the files necessary for rzdm to display the images.
    for dir in ${directories[@]}; do
      if [[ -d ${dir} ]]; then
        echo "<?php require \$_SERVER['DOCUMENT_ROOT'].\"/ncep_common/dirlist.php\"; ?>" > "${dir}/index.php"
        printf "*.png\n20*\n${EXP_NAME}\nheatmap\nmap\nprofile\nhovmoller\ntimeseries" > "${dir}/allow.cfg"
      fi
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
