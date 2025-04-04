#!/bin/bash
# This script is the main driver for generating various diagnostic plots
# related to data assimilation. It processes log files and diagnostic files
# from an experiment, producing visualizations to analyze observation impact
# and model performance.
#
# Supported diagnostic scripts:
# - heatmap_jo.py                  : Generates heatmaps for Nonlinear Jo values,
#                                    observation counts, Jo/n, and Jo/n percent change.
# - (diff_)heatmap_rms_bias_fit.py : Creates heatmaps for bias and RMS statistics
#                                    from diagnostic files and fitting ratio. Compares
#                                    stats across multiple observation types. (Compares
#                                    two experiments.)
# - (diff_)profile_rms_bias_fit.py : Produces vertical profile plots of bias and
#                                    RMS statistics using pressure as the
#                                    vertical coordinate. (Compares two experiments.)
# - map_ombg_oman.py               : Creates 2d map scatter of ombg/an values with bias
#                                    and rms stats displayed.
# - hovmoller_rms_bias_fit.py      : Generates a hovmoller (pressure vs time) time series
#                                    (of vertical profiles) of rms, bias, and fitting ratio.
# - (diff_)timeseries_rms_bias_fit.py : Generates a time series of whole column of rms,
#                                       bias, and fitting ratio. (Compares two experiments.)
# - map_domainComparison_mpas_fv3  : Overlays mpas and fv3 grids for domain comparison.
# - fv3_vs_mpas_increment.py       : Plots side-by-side comparison of fv3 vs mpas analysis
#                                    increments.
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
#HEATMAP_RMS_BIAS_FIT="YES"
#DIFF_HEATMAP_RMS_BIAS_FIT="YES"
#PROFILE_RMS_BIAS_FIT="YES"
#DIFF_PROFILE_RMS_BIAS_FIT="YES"
#MAP_OMBG_OMAN="YES"
#HOVMOLLER_RMS_BIAS_FIT="YES"
#TIMESERIES_RMS_BIAS_FIT="YES"
#DIFF_TIMESERIES_RMS_BIAS_FIT="YES"
#MAP_DOMAINCOMPARISON_MPAS_FV3="YES"
#INCREMENT_FV3_VS_MPAS="YES"
#INCREMENT_MPAS_VS_MPAS="YES"
#UPLOAD_TO_RZDM="YES"

# Cycle start and end dates to process
SDATE=2024050600
EDATE=2024050600

# Retro experiment details (similar to rrfs-workflow/workflow/exp.setup)
VERSION="v2.0.9"
EXP_NAME="baseline1_3denvar12km209"
OPSROOT="/scratch2/NCEPDEV/fv3-cam/Donald.E.Lippi/RRFSv2/workflow/${VERSION}"
#EXP_NAME="baseline1_3dvar12km209"
#OPSROOT="/scratch2/NCEPDEV/fv3-cam/Xiaoyan.Zhang/noscrub/JEDI/RRFSV2/workflow/${VERSION}"
COMROOT="${OPSROOT}/exp/${EXP_NAME}/com"
DATAROOT="${OPSROOT}/exp/${EXP_NAME}/stmp"
LOGDIR="${COMROOT}/rrfs/${VERSION}/logs"
JDIAGDIR="${DATAROOT}"

# Control experiment for "diff_" tools.
CTL_VERSION="v2.0.9"
CTL_NAME="baseline1_3dvar12km209"
CTL_OPSROOT="/scratch2/NCEPDEV/fv3-cam/Xiaoyan.Zhang/noscrub/JEDI/RRFSV2/workflow/${CTL_VERSION}"
CTL_COMROOT="${CTL_OPSROOT}/exp/${CTL_NAME}/com"
CTL_DATAROOT="${CTL_OPSROOT}/exp/${CTL_NAME}/stmp"
CTL_LOGDIR="${CTL_COMROOT}/rrfs/${CTL_VERSION}/logs"
CTL_JDIAGDIR="${CTL_DATAROOT}"

# Specify your RDASApp build (mostly for module loads)
RDASApp="/scratch2/NCEPDEV/fv3-cam/Donald.E.Lippi/RRFSv2/PRs/RDASApp.20241204.phase2_sonde"

# Options only for MAP_DOMAINCOMPARISON_MPAS_FV3
MPAS_DOMAIN="${RDASApp}/expr/mpas_2024052700/data/invariant.nc"
FV3_DOMAIN="${RDASApp}/expr/fv3_2024052700/Data/bkg/grid_spec.nc"

# Options for analysis increment plot
LEVEL=1 # actual level (not python index)

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
# In this loop, date is incremented by 24h
while [[ ${date} -le ${EDATE} ]]; do
  pdy=${date:0:8}
  pdy_list+=("${pdy}")
  mkdir -p ${EXP_NAME}/${pdy}

  # Plots nobs, Jo, Jo/n, and Jo/n percent change (from log files)
  if [[ ${HEATMAP_JO:=NO} == "YES" ]]; then
    echo "? Working on (${EXP_NAME}) jo info heatmaps: ${pdy}"
    logs=(${LOGDIR}/rrfs.${pdy}/*/det/rrfs_jedivar_*_${pdy}*.log)
    python heatmap_jo.py ${logs[@]}
    mkdir -p ${EXP_NAME}/${pdy}/heatmap
    mv heatmap*.png ${EXP_NAME}/${pdy}/heatmap/.
  fi

  # Plots rms and bias (from jdiag files)
  if [[ ${HEATMAP_RMS_BIAS_FIT:=NO} == "YES" ]]; then
    echo "? Working on (${EXP_NAME}) rms, bias, fitting ratio heatmaps: ${pdy}"
    jdiags=(${JDIAGDIR}/${pdy}/rrfs_jedivar_*_${VERSION}/det/jedivar_*/jdiag*)
    python heatmap_rms_bias_fit.py ${jdiags[@]}
    mkdir -p ${EXP_NAME}/${pdy}/heatmap
    mv heatmap*.png ${EXP_NAME}/${pdy}/heatmap/.
  fi

  # Plots rms and bias (from jdiag files)
  if [[ ${DIFF_HEATMAP_RMS_BIAS_FIT:=NO} == "YES" ]]; then
    echo "? Working on (${EXP_NAME} vs ${CTL_NAME}) diff rms, bias, fitting ratio heatmaps: ${pdy}"
    jdiags_exp=(${JDIAGDIR}/${pdy}/rrfs_jedivar_*_${VERSION}/det/jedivar_*/jdiag*)
    jdiags_ctl=(${CTL_JDIAGDIR}/${pdy}/rrfs_jedivar_*_${CTL_VERSION}/det/jedivar_*/jdiag*)
    python diff_heatmap_rms_bias_fit.py "${CTL_NAME}" "${EXP_NAME}" ${jdiags_ctl[@]} -- ${jdiags_exp[@]}
    mkdir -p ${EXP_NAME}/${pdy}/heatmap
    mv heatmap*.png ${EXP_NAME}/${pdy}/heatmap/.
  fi


  # Plots 2d map scatter of ombg values (from jdiag) with bias and rms stats displayed.
  if [[ ${MAP_OMBG_OMAN:=NO} == "YES" ]]; then
    echo "? Working on (${EXP_NAME}) map ombg & oman: ${date}"
    jdiags=(${JDIAGDIR}/${pdy}/rrfs_jedivar_*_${VERSION}/det/jedivar_*/jdiag*Temp*33*)
    #jdiags+=(${JDIAGDIR}/${pdy}/rrfs_jedivar_*_${VERSION}/det/jedivar_*/jdiag*Temp*88*)
    python map_ombg_oman.py ${jdiags[@]}
    mkdir -p ${EXP_NAME}/${pdy}/map
    mv ${pdy}*map.png ${EXP_NAME}/${pdy}/map/.
  fi

  # Increase date by 1 day
  date=$(${ndate} 24 ${date})
done # date loop

# Reset date for new loop
date=${SDATE}
date=$(${ndate} 1 ${date}) # start +1 hr (otherwise missing background)
if [[ ${SDATE} -eq ${EDATE} ]]; then
  EDATE=$(${ndate} 24 ${EDATE})
fi

# Loop over dates from start to and including end date
# In this loop, date is incremented by 1h
while [[ ${date} -le ${EDATE} ]]; do
  pdy=${date:0:8}
  cyc=${date:8:10}
  datem1=$(${ndate} -1 ${date})
  pdym1=${datem1:0:8}
  cycm1=${datem1:8:10}
  mkdir -p ${EXP_NAME}/${pdy}

# Plots mpas vs mpas analysis increments.
if [[ ${INCREMENT_MPAS_VS_MPAS:=NO} == "YES" ]]; then
  echo "? Working on (${EXP_NAME} vs ${CTL_NAME}) increments: ${pdy} ${cyc}Z level${LEVEL}"
  #-v/--variable: Variable to plot (e.g., airTemperature, specificHumidity).
  #-f/--figname: Figure identifier (e.g., a timestamp or experiment name).
  #-m1b/--mpas1_bkg: MPAS background file for experiment 1 (control).
  #-m1a/--mpas1_ana: MPAS analysis file for experiment 1 (control).
  #-m2b/--mpas2_bkg: MPAS background file for experiment 2 (new experiment).
  #-m2a/--mpas2_ana: MPAS analysis file for experiment 2 (new experiment).
  #-mg/--mpas_grid: Path to the MPAS-JEDI grid file.
  #-c/--ctl_name: Name of the control experiment.
  #-e/--exp_name: Name of the new experiment.
  #-l/--level: Model level (not python index).
  m1b=${CTL_COMROOT}/rrfs/${CTL_VERSION}/rrfs.${pdym1}/${cycm1}/fcst/det/mpasout*nc
  m1a=${CTL_DATAROOT}/${pdy}/rrfs_jedivar_${cyc}_${CTL_VERSION}/det/jedivar_${cyc}/mpasin.nc
  m2b=${COMROOT}/rrfs/${VERSION}/rrfs.${pdym1}/${cycm1}/fcst/det/mpasout*nc
  m2a=${DATAROOT}/${pdy}/rrfs_jedivar_${cyc}_${VERSION}/det/jedivar_${cyc}/mpasin.nc
  mg=${DATAROOT}/${pdy}/rrfs_jedivar_${cyc}_${VERSION}/det/jedivar_${cyc}/invariant.nc
  if [[ ! -f $m1a || ! -f $m2a ]]; then
    break
  fi
  python increment_mpas_mpas.py -v airTemperature -f ${date} -m1b ${m1b} -m1a ${m1a} -m2b ${m2b} -m2a ${m2a} -mg ${mg} -c ${CTL_NAME} -e ${EXP_NAME} -l ${LEVEL}
  mkdir -p ${EXP_NAME}/increment
  mv *increment*.png ${EXP_NAME}/increment/.
fi
# Plots gsi vs mpas analysis increments.
if [[ ${INCREMENT_FV3_VS_MPAS:=NO} == "YES" ]]; then
  echo "? Working on (${EXP_NAME}) diff increments: ${pdy} ${cyc}Z"
  echo "still needs testing... exiting..."
  exit 1
  mkdir -p ${EXP_NAME}/increment
  #-v/--variable: Variable to plot (e.g., airTemperature, specificHumidity).
  #-f/--figname: Figure identifier (e.g., a timestamp or experiment name).
  #-gb/--gsi_bkg: Path to the GSI background file.
  #-ga/--gsi_ana: Path to the GSI analysis file.
  #-mb/--mpas_bkg: Path to the MPAS-JEDI background file.
  #-ma/--mpas_ana: Path to the MPAS-JEDI analysis file.
  #-gg/--gsi_grid: Path to the GSI grid file.
  #-mg/--mpas_grid: Path to the MPAS-JEDI grid file.
  temp=/scratch2/NCEPDEV/fv3-cam/Donald.E.Lippi/RRFSv2/jedi-assim-phase3/gsi_2024052700
  gb=${temp}/Data/bkg/fv3_dynvars
  ga=${temp}/aircar_airTemperature_133/fv3_dynvars
  gg=${temp}/fv3_grid_spec
  mb=${COMROOT}/rrfs/${VERSION}/rrfs.${pdym1}/${cycm1}/fcst/det/mpasout*nc
  ma=${DATAROOT}/${pdy}/rrfs_jedivar_${cyc}_${VERSION}/det/jedivar_${cyc}/mpasin.nc
  mg=${DATAROOT}/${pdy}/rrfs_jedivar_${cyc}_${VERSION}/det/jedivar_${cyc}/invariant.nc
  python increment_fv3_mpas.py -v airTemperature -f ${date} -gb ${gb} -ga ${ga} -gg ${gg} -mb ${mb} -ma ${ma} -mg ${mg}
  mv *increment*.png ${EXP_NAME}/increment/.
fi

  # Increase date by 1 day
  date=$(${ndate} 1 ${date})
done # date loop

# START OF CYCLE-AVERAGED DIAGNOSTIC TOOLS AND TIMESERIES PLOTS (no date loop).

spdy=${SDATE:0:8}
epdy=${EDATE:0:8}
# Plots vertical profiles of rms and bias (from jdiag files) over a date range.
if [[ ${PROFILE_RMS_BIAS_FIT:=NO} == "YES" ]]; then
  echo "? Working on (${EXP_NAME}) profiles: ${spdy}00 to ${epdy}23"
  jdiags=(${JDIAGDIR}/*/rrfs_jedivar_*_${VERSION}/det/jedivar_*/jdiag*33*)
  jdiags+=(${JDIAGDIR}/*/rrfs_jedivar_*_${VERSION}/det/jedivar_*/jdiag*20*)
  python profile_rms_bias_fit.py ${jdiags[@]}
  mkdir -p ${EXP_NAME}/profile
  mv profile*.png ${EXP_NAME}/profile/.
fi

# Plots vertical profiles of rms and bias (from jdiag files) over a date range.
if [[ ${DIFF_PROFILE_RMS_BIAS_FIT:=NO} == "YES" ]]; then
  echo "? Working on (${EXP_NAME} vs ${CTL_NAME}) diff profiles: ${spdy}00 to ${epdy}23"
  jdiags_exp=(${JDIAGDIR}/*/rrfs_jedivar_*_${VERSION}/det/jedivar_*/jdiag*33*)
  jdiags_ctl=(${CTL_JDIAGDIR}/*/rrfs_jedivar_*_${CTL_VERSION}/det/jedivar_*/jdiag*33*)
  jdiags_exp+=(${JDIAGDIR}/*/rrfs_jedivar_*_${VERSION}/det/jedivar_*/jdiag*20*)
  jdiags_ctl+=(${CTL_JDIAGDIR}/*/rrfs_jedivar_*_${CTL_VERSION}/det/jedivar_*/jdiag*20*)
  python diff_profile_rms_bias_fit.py "${CTL_NAME}" "${EXP_NAME}" ${jdiags_ctl[@]} -- ${jdiags_exp[@]}
  mkdir -p ${EXP_NAME}/profile
  mv profile*.png ${EXP_NAME}/profile/.
fi


if [[ ${HOVMOLLER_RMS_BIAS_FIT:=NO} == "YES" ]]; then
  echo "? Working on (${EXP_NAME}) hovmoller: ${spdy}00 to ${epdy}23"
  jdiags=(${JDIAGDIR}/*/rrfs_jedivar_*_${VERSION}/det/jedivar_*/jdiag*33*)
  #jdiags+=(${JDIAGDIR}/*/rrfs_jedivar_*_${VERSION}/det/jedivar_*/jdiag*20*)
  python hovmoller_rms_bias_fit.py ${jdiags[@]}
  mkdir -p ${EXP_NAME}/hovmoller
  mv hovmoller*.png ${EXP_NAME}/hovmoller/.
fi

if [[ ${TIMESERIES_RMS_BIAS_FIT:=NO} == "YES" ]]; then
  echo "? Working on (${EXP_NAME}) timeseries: ${spdy}00 to ${epdy}23"
  jdiags=(${JDIAGDIR}/*/rrfs_jedivar_*_${VERSION}/det/jedivar_*/jdiag*33*)
  #jdiags+=(${JDIAGDIR}/*/rrfs_jedivar_*_${VERSION}/det/jedivar_*/jdiag*20*)
  python timeseries_rms_bias_fit.py ${jdiags[@]}
  mkdir -p ${EXP_NAME}/timeseries
  mv timeseries*.png ${EXP_NAME}/timeseries/.
fi

if [[ ${DIFF_TIMESERIES_RMS_BIAS_FIT:=NO} == "YES" ]]; then
  echo "? Working on (${EXP_NAME} vs ${CTL_NAME}) diff timeseries: ${spdy}00 to ${epdy}23"
  jdiags_exp=(${JDIAGDIR}/*/rrfs_jedivar_*_${VERSION}/det/jedivar_*/jdiag*33*)
  jdiags_ctl=(${CTL_JDIAGDIR}/*/rrfs_jedivar_*_${CTL_VERSION}/det/jedivar_*/jdiag*33*)
  #jdiags_exp+=(${JDIAGDIR}/*/rrfs_jedivar_*_${VERSION}/det/jedivar_*/jdiag*20*)
  #jdiags_ctl+=(${CTL_JDIAGDIR}/*/rrfs_jedivar_*_${CTL_VERSION}/det/jedivar_*/jdiag*20*)
  python diff_timeseries_rms_bias_fit.py "${CTL_NAME}" "${EXP_NAME}" ${jdiags_ctl[@]} -- ${jdiags_exp[@]}
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
               "${EXP_NAME}/20*"
               "${EXP_NAME}/hovmoller"
               "${EXP_NAME}/increment"
               "${EXP_NAME}/timeseries"
               "${EXP_NAME}/profile"
               "${EXP_NAME}/20*/heatmap"
               "${EXP_NAME}/20*/map")

  # Create the files necessary for rzdm to display the images.
  for dir in ${directories[@]}; do
    if [[ -d ${dir} ]]; then
      echo "<?php require \$_SERVER['DOCUMENT_ROOT'].\"/ncep_common/dirlist.php\"; ?>" > "${dir}/index.php"
      printf "*.png\n20*\n${EXP_NAME}\nheatmap\nmap\nprofile\nhovmoller\ntimeseries\nincrement" > "${dir}/allow.cfg"
    fi
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
