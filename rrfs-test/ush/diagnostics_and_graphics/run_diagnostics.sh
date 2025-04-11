#!/bin/bash
# run_diagnostics.sh - driver for generating JEDI diagnostic plots
# Edit USER-DEFINED VARIABLES below, then execute.

#### USER-DEFINED VARIABLES ####################################################
#===============================================================================
#                            RUN CONTROL SWITCHES
#
# To ENABLE a feature:   remove the leading "#"
# To DISABLE a feature:  add a leading "#"
#
# Format:
#   VARIABLE_NAME="YES"    # short description
#
# Sections:
#   1) Single-Experiment Plots
#   2) Two-Experiment Comparison Plots
#   3) Upload Options
#===============================================================================

# --- 1) Single-Experiment Plots (e.g. Retro experiment only) ---
#HEATMAP_JO="YES"                    # Jo heatmaps from log files
#HEATMAP_RMS_BIAS_FIT="YES"          # RMS/bias/fitting-ratio/nobs heatmaps
#PROFILE_RMS_BIAS_FIT="YES"          # Vertical profiles of RMS/bias/fitting-ratio
#MAP_OMBG_OMAN="YES"                 # OMB/OMA scatter maps
#HOVMOLLER_RMS_BIAS_FIT="YES"        # Hovmoller plots of RMS/bias/fitting-ratio
TIMESERIES_RMS_BIAS_FIT="YES"       # Time-series of RMS/bias/fitting-ratio
#INCREMENT_MPAS="YES"                # Single-experiment MPAS increments

# --- 2) Two-Experiment Comparison Plots (Retro vs Control) ---
#DIFF_HEATMAP_RMS_BIAS_FIT="YES"     # Diff heatmaps (Retro vs Control)
#DIFF_PROFILE_RMS_BIAS_FIT="YES"     # Diff vertical profiles
#DIFF_TIMESERIES_RMS_BIAS_FIT="YES"  # Diff time-series
#INCREMENT_FV3_VS_MPAS="YES"         # FV3 vs MPAS increments
#INCREMENT_MPAS_VS_MPAS="YES"        # MPAS vs MPAS increments
#MAP_DOMAINCOMPARISON_MPAS_FV3="YES" # Domain comparison map

# --- 3) Upload Options ---
#UPLOAD_TO_RZDM="YES"                # scp results to RZDM web server

#===============================================================================

# Cycle start and end dates to process
SDATE=2024050601
EDATE=2024050606

# EffectiveQC2 value and operator
export EFFQC=0 # 0 (asm), 1 (mon), 12 (rej)
export USE_LESS_EQUAL=true #true: <=; false: ==

# Retro experiment details (similar to rrfs-workflow/workflow/exp.setup)
VERSION="v2.0.9"
EXP_NAME="baseline1_3denvar12km209"
OPSROOT="/scratch2/NCEPDEV/fv3-cam/Donald.E.Lippi/RRFSv2/workflow/${VERSION}"
#EXP_NAME="baseline1_3dvar12km209"
#OPSROOT="/scratch2/NCEPDEV/fv3-cam/Xiaoyan.Zhang/noscrub/JEDI/RRFSV2/workflow/${VERSION}"
#VERSION="v0.8.6"
#EXP_NAME="CONUS13km_ColdStart00-12Z_133-233TQW"
COMROOT="${OPSROOT}/exp/${EXP_NAME}/com"
DATAROOT="${OPSROOT}/exp/${EXP_NAME}/stmp"
LOGDIR="${COMROOT}/rrfs/${VERSION}/logs"
JDIAGDIR="${DATAROOT}"

# Control experiment details - only used in 2) Two-Experiment Comparison Plots (Retro vs Control)
#CTL_VERSION="v2.0.9"
#CTL_NAME="baseline1_3dvar12km209"
#CTL_OPSROOT="/scratch2/NCEPDEV/fv3-cam/Xiaoyan.Zhang/noscrub/JEDI/RRFSV2/workflow/${CTL_VERSION}"
CTL_VERSION="v0.8.6"
CTL_NAME="CONUS13km_ColdStart00-12Z_133-233TQW"
CTL_OPSROOT="${OPSROOT}"
CTL_COMROOT="${CTL_OPSROOT}/exp/${CTL_NAME}/com"
CTL_DATAROOT="${CTL_OPSROOT}/exp/${CTL_NAME}/stmp"
CTL_LOGDIR="${CTL_COMROOT}/rrfs/${CTL_VERSION}/logs"
CTL_JDIAGDIR="${CTL_DATAROOT}"

# Specify your RDASApp build (mostly for module loads)
RDASApp="/scratch2/NCEPDEV/fv3-cam/Donald.E.Lippi/RRFSv2/PRs/RDASApp.20241204.phase2_sonde"

# Options only for MAP_DOMAINCOMPARISON_MPAS_FV3
#MPAS_DOMAIN="${RDASApp}/expr/mpas_2024052700/data/invariant.nc"
#FV3_DOMAIN="${RDASApp}/expr/fv3_2024052700/Data/bkg/grid_spec.nc"
MPAS_DOMAIN="${DATAROOT}/20240506/rrfs_fcst_01_v2.0.9/det/fcst_01/invariant.nc"
FV3_DOMAIN="${CTL_DATAROOT}/20240506/rrfs_jedivar_01_v0.8.6/det/jedivar_01/grid_spec.nc"

# Options for analysis increment plot
LEVEL=1 # actual level (not python index; mpas only plots; 1=lowest model level)
FV3BKG_SOURCE="/scratch1/BMC/wrfruc/rli/RRFS_V1/rrfs.${CTL_VERSION}/${CTL_NAME}/nwges"

# Options for timesereies plot
BIN=19 # -1: Entire Column, 1: Top Level, 19: Bottom Level (uses same binning as profiles).
#-1: 180-1100 hPa
# 1: 180-198 hPa
# 2: 198-218 hPa
# 3: 218-240 hPa
# 4: 240-263 hPa
# 5: 263-290 hPa
# 6: 290-319 hPa
# 7: 319-351 hPa
# 8: 351-386 hPa
# 9: 386-424 hPa
#10: 424-467 hPa
#11: 467-513 hPa
#12: 513-565 hPa
#13: 565-621 hPa
#14: 621-683 hPa
#15: 683-751 hPa
#16: 751-827 hPa
#17: 827-909 hPa
#18: 909-1000 hPa
#19: 1000-1100 hPa

# Options only for RZDM
USER="donald.lippi"
HOST="emcrzdm.ncep.noaa.gov"
DESTINATION="/home/www/emc/htdocs/mmb/dlippi/rrfs-workflow_v2/DA_monitoring/."
#### END OF USER-DEFINED VARIABLES #############################################

# Start main execution
START=$(date +%s)

# Detect machine
source ${RDASApp}/ush/detect_machine.sh

# Load necessary environment
module purge
module use ${RDASApp}/modulefiles
module load RDAS/${MACHINE_ID}.intel
export ndate=$(which ndate) # Load ndate
module purge
module load EVA/${MACHINE_ID}

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
    echo "? Working on (${EXP_NAME}) rms, bias, fitting ratio, nobs heatmaps: ${pdy} (24h)"
    jdiags=(${JDIAGDIR}/${pdy}/rrfs_jedivar_*_${VERSION}/det/jedivar_*/jdiag*)
    python heatmap_rms_bias_fit.py ${jdiags[@]}
    mkdir -p ${EXP_NAME}/${pdy}/heatmap
    mv heatmap*.png ${EXP_NAME}/${pdy}/heatmap/.
  fi

  # Plots rms and bias (from jdiag files)
  if [[ ${DIFF_HEATMAP_RMS_BIAS_FIT:=NO} == "YES" ]]; then
    echo "? Working on (${EXP_NAME} vs ${CTL_NAME}) diff rms, bias, fitting ratio, nobs heatmaps: ${pdy} (24h)"
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

# Loop over dates from start to and including end date
# In this loop, date is incremented by 1h
while [[ ${date} -le ${EDATE} ]]; do
  pdy=${date:0:8}
  cyc=${date:8:10}
  datem1=$(${ndate} -1 ${date})
  pdym1=${datem1:0:8}
  cycm1=${datem1:8:10}
  mkdir -p ${EXP_NAME}/${pdy}

  # Plots single mpas analysis increments.
  if [[ ${INCREMENT_MPAS:=NO} == "YES" ]]; then
    echo "? Working on (${EXP_NAME}) increments: ${pdy} ${cyc}Z level${LEVEL}"
    #-v/--variable: Variable to plot (e.g., airTemperature, specificHumidity).
    #-f/--figname: Figure identifier (e.g., a timestamp or experiment name).
    #-m1b/--mpas1_bkg: MPAS background file for experiment 1.
    #-m1a/--mpas1_ana: MPAS analysis file for experiment 1.
    #-mg/--mpas_grid: Path to the MPAS-JEDI grid file.
    #-e/--exp_name: Name of the new experiment.
    #-l/--level: Model level (not python index).
    m1b=${COMROOT}/rrfs/${VERSION}/rrfs.${pdym1}/${cycm1}/fcst/det/mpasout*nc
    m1a=${DATAROOT}/${pdy}/rrfs_jedivar_${cyc}_${VERSION}/det/jedivar_${cyc}/mpasin.nc
    mg=${DATAROOT}/${pdy}/rrfs_jedivar_${cyc}_${VERSION}/det/jedivar_${cyc}/invariant.nc
    if [[ ! -f $m1a ]]; then
      break
    fi
    python increment_mpas.py -v airTemperature -f ${date} -m1b ${m1b} -m1a ${m1a} -mg ${mg} -e ${EXP_NAME} -l ${LEVEL}
    mkdir -p ${EXP_NAME}/increment
    mv *increment*.png ${EXP_NAME}/increment/.
  fi

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
    python increment_mpas_vs_mpas.py -v airTemperature -f ${date} -m1b ${m1b} -m1a ${m1a} -m2b ${m2b} -m2a ${m2a} -mg ${mg} -c ${CTL_NAME} -e ${EXP_NAME} -l ${LEVEL}
    mkdir -p ${EXP_NAME}/increment
    mv *increment*.png ${EXP_NAME}/increment/.
  fi

  # Plots gsi vs mpas analysis increments.
  if [[ ${INCREMENT_FV3_VS_MPAS:=NO} == "YES" ]]; then
    echo "? Working on (${EXP_NAME} vs ${CTL_NAME}) diff increments: ${pdy} ${cyc}Z"
    mkdir -p ${EXP_NAME}/increment
    #-v/--variable: Variable to plot (e.g., airTemperature, specificHumidity).
    #-f/--figname: Figure identifier (e.g., a timestamp or experiment name).
    #-gb/--gsi_bkg: Path to the GSI background file.
    #-ga/--gsi_ana: Path to the GSI analysis file.
    #-mb/--mpas_bkg: Path to the MPAS-JEDI background file.
    #-ma/--mpas_ana: Path to the MPAS-JEDI analysis file.
    #-gg/--gsi_grid: Path to the GSI grid file.
    #-mg/--mpas_grid: Path to the MPAS-JEDI grid file.
    #-c/--ctl_name: Name of the control experiment
    #-e/--exp_name: Name of the new experiment
    gb=${FV3BKG_SOURCE}/${pdym1}${cycm1}/fcst_fv3lam/RESTART/${pdy}.${cyc}0000.fv_core.res.tile1.nc
    ga=${FV3BKG_SOURCE}/${pdy}${cyc}/fcst_fv3lam/INPUT/fv_core.res.tile1.nc
    gg=${FV3BKG_SOURCE}/../stmp/${pdy}${cyc}/anal_conv_gsi/fv3_grid_spec
    mb=${COMROOT}/rrfs/${VERSION}/rrfs.${pdym1}/${cycm1}/fcst/det/mpasout*nc
    ma=${DATAROOT}/${pdy}/rrfs_jedivar_${cyc}_${VERSION}/det/jedivar_${cyc}/mpasin.nc
    mg=${DATAROOT}/${pdy}/rrfs_jedivar_${cyc}_${VERSION}/det/jedivar_${cyc}/invariant.nc
    python increment_fv3_vs_mpas.py -v airTemperature -f ${date} -gb ${gb} -ga ${ga} -gg ${gg} -mb ${mb} -ma ${ma} -mg ${mg} -c ${CTL_NAME} -e ${EXP_NAME}
    mv *increment*.png ${EXP_NAME}/increment/.
  fi

  # Increase date by 1 hour
  date=$(${ndate} 1 ${date})
done # date loop

# START OF CYCLE-AVERAGED DIAGNOSTIC TOOLS AND TIMESERIES PLOTS (no date loop).

spdy=${SDATE:0:8}
epdy=${EDATE:0:8}
# Plots vertical profiles of rms and bias (from jdiag files) over a date range.
if [[ ${PROFILE_RMS_BIAS_FIT:=NO} == "YES" ]]; then
  echo "? Working on (${EXP_NAME}) profiles: ${spdy}00 to ${epdy}23"
  jdiags=(${JDIAGDIR}/*/rrfs_jedivar_*_${VERSION}/det/jedivar_*/jdiag*33*)
  #jdiags+=(${JDIAGDIR}/*/rrfs_jedivar_*_${VERSION}/det/jedivar_*/jdiag*20*)
  python profile_rms_bias_fit.py ${jdiags[@]}
  mkdir -p ${EXP_NAME}/profile
  mv profile*.png ${EXP_NAME}/profile/.
fi

# Plots vertical profiles of rms and bias (from jdiag files) over a date range.
if [[ ${DIFF_PROFILE_RMS_BIAS_FIT:=NO} == "YES" ]]; then
  echo "? Working on (${EXP_NAME} vs ${CTL_NAME}) diff profiles: ${spdy}00 to ${epdy}23"
  #jdiags_exp=(${JDIAGDIR}/*/rrfs_jedivar_*_${VERSION}/det/jedivar_06/jdiag*33*)
  #jdiags_ctl=(${CTL_JDIAGDIR}/*06/rrfs_jedivar_*_${CTL_VERSION}/det/jedivar_06/jdiag*33*)
  jdiags_exp=(${JDIAGDIR}/*06/rrfs_jedivar_*_${VERSION}/det/jedivar_{00..12}/jdiag*33*)
  jdiags_ctl=(${CTL_JDIAGDIR}/*06/rrfs_jedivar_*_${CTL_VERSION}/det/jedivar_{00..12}/jdiag*33*)
  #jdiags_exp+=(${JDIAGDIR}/*06/rrfs_jedivar_*_${VERSION}/det/jedivar_{00..12}/jdiag*20*)
  #jdiags_ctl+=(${CTL_JDIAGDIR}/*06/rrfs_jedivar_*_${CTL_VERSION}/det/jedivar_{00..12}/jdiag*20*)
  #echo "exp: ${jdiags_exp[1]}"
  #echo "ctl: ${jdiags_ctl[1]}"; exit
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
  jdiags=(${JDIAGDIR}/*/rrfs_jedivar_*_${VERSION}/det/jedivar_*/jdiag*Temp*33*)
  #jdiags+=(${JDIAGDIR}/*/rrfs_jedivar_*_${VERSION}/det/jedivar_*/jdiag*20*)
  python timeseries_rms_bias_fit.py --bin ${BIN} ${jdiags[@]}
  mkdir -p ${EXP_NAME}/timeseries
  mv timeseries*.png ${EXP_NAME}/timeseries/.
fi

if [[ ${DIFF_TIMESERIES_RMS_BIAS_FIT:=NO} == "YES" ]]; then
  echo "? Working on (${EXP_NAME} vs ${CTL_NAME}) diff timeseries: ${spdy}00 to ${epdy}23"
  jdiags_exp=(${JDIAGDIR}/*/rrfs_jedivar_*_${VERSION}/det/jedivar_*/jdiag*Temp*33*)
  jdiags_ctl=(${CTL_JDIAGDIR}/*/rrfs_jedivar_*_${CTL_VERSION}/det/jedivar_*/jdiag*Temp*33*)
  #jdiags_exp=(${JDIAGDIR}/*/rrfs_jedivar_*_${VERSION}/det/jedivar_*/jdiag*20*)
  #jdiags_ctl=(${CTL_JDIAGDIR}/*/rrfs_jedivar_*_${CTL_VERSION}/det/jedivar_*/jdiag*20*)
  python diff_timeseries_rms_bias_fit.py --bin ${BIN} "${CTL_NAME}" "${EXP_NAME}" ${jdiags_ctl[@]} -- ${jdiags_exp[@]}
  mkdir -p ${EXP_NAME}/timeseries
  mv timeseries*.png ${EXP_NAME}/timeseries/.
fi


if [[ ${MAP_DOMAINCOMPARISON_MPAS_FV3:=NO} == "YES" ]]; then
  echo "? Working on (${EXP_NAME} vs ${CTL_NAME}) map domain comparison mpas vs fv3."
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
