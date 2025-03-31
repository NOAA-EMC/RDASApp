#!/bin/bash
# This script is the main driver for converting GSI-diagnostic (gdiag) files
# to JEDI-diagnostic (jdiag) files. It processes gdiags from a single cycle
# and formats (both data and directory structure) to match JEDI to be used
# with the JEDI DA monitoring tools.
#
# Supported functions:
# - COPY_DATA     : Copies RRFSv1 gdiags and organizes them in RRFSv2 directory
#                   structures.
# - CONVERT_GDIAG_TO_JDIAG  : Converts gdiags to jdiags and saves the output in RRFSv2
#                   directory structure
#
# Usage:
# - Set the required variables below to define the experiment, date range,
#   and desired functions.
# - Ensure the RRFSv2 data structure matches that used in this script
#   (rrfsv2_structure).
# - Run the script to copy RRFSv1 gdiags and convert to jdiags.
#
#
#### USER-DEFINED VARIABLES #################################################
# Specify which functions to run (uncomment/comment to turn on/off)
#COPY_DATA="YES"
#CONVERT_GDIAG_TO_JDIAG="YES"
CONVERT_JDIAG_TO_GDIAG="YES"

# Cycle start and end dates to process
SDATE=2024050700
EDATE=2024050723
SDATE=2024052806
EDATE=2024052806

# V2 retro experiment details (similar to rrfs-workflow/workflow/exp.setup)
VERSION="v2.0.9.7"
TAG="d12km2097"
EXP_NAME="hrly_12km"
OPSROOT="/scratch2/NCEPDEV/fv3-cam/Donald.E.Lippi/RRFSv2/workflow/${VERSION}"
COMROOT="${OPSROOT}/exp/${EXP_NAME}/com"
DATAROOT="${OPSROOT}/exp/${EXP_NAME}/stmp"

# RRFSv1 EXP_NAME (RRFSv1 = benchmark)
BENCHMARK="benchmark1"

# Location and pattern of gdiags
DATA_SOURCE="/scratch1/BMC/wrfruc/rli/RRFS_V1/rrfs.v0.8.6/CONUS13km_det"
INCLUDE_PATTERN="diag_conv_*.nc4.gz"

# Specify your RDASApp build (mostly for module loads)
RDASApp="/scratch2/NCEPDEV/fv3-cam/Donald.E.Lippi/RRFSv2/PRs/RDASApp.20241204.phase2_sonde"

# Specify the diag directories
JDIAGDIR="${DATAROOT}"
GDIAGDIR="${OPSROOT}/exp/${BENCHMARK}/stmp"
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

# Initialize date with start date
date=${SDATE}

# Loop over dates from start to and including end date
while [[ ${date} -le ${EDATE} ]]; do
  pdy=${date:0:8}
  cyc=${date:8:10}

  # RRFSv2-like data structure to copy gdiags into
  rrfsv2_structure=${GDIAGDIR}/${pdy}/rrfs_jedivar_${cyc}_${VERSION}/det/jedivar_${cyc}
  #echo "${rrfsv2_structure}"
  mkdir -p $rrfsv2_structure

  if [[ ${COPY_DATA:=NO} == "YES" ]] ; then
    echo "? Working on copy gdiag: ${pdy} ${cyc}Z"
    cp -p ${DATA_SOURCE}/stmp/${date}/anal_conv_dbz_gsi/diag_conv_t* ${rrfsv2_structure}/.
    cp -p ${DATA_SOURCE}/stmp/${date}/anal_conv_dbz_gsi/diag_conv_q* ${rrfsv2_structure}/.
    cp -p ${DATA_SOURCE}/stmp/${date}/anal_conv_dbz_gsi/diag_conv_ps* ${rrfsv2_structure}/.
    cp -p ${DATA_SOURCE}/stmp/${date}/anal_conv_dbz_gsi/diag_conv_uv* ${rrfsv2_structure}/.
    find ${rrfsv2_structure} -type f -name "${INCLUDE_PATTERN}" -exec gunzip -f {} \;
  fi

  if [[ ${CONVERT_GDIAG_TO_JDIAG:=NO} == "YES" ]] ; then
    echo "? Working on convert gdiag to jdiag: ${pdy} ${cyc}Z"
    # Array of full file paths (only need to specify _anl files)
    jdiags=(${rrfsv2_structure}/diag_conv_t_anl*)
    jdiags+=(${rrfsv2_structure}/diag_conv_q_anl*)
    jdiags+=(${rrfsv2_structure}/diag_conv_ps_anl*)
    jdiags+=(${rrfsv2_structure}/diag_conv_uv_anl*)

    # Run the Python script with analysis time and file list
    python gdiag_to_jdiag.py "$date" "${jdiags[@]}"
    mv jdiag*.nc ${rrfsv2_structure}/.
  fi

  if [[ ${CONVERT_JDIAG_TO_GDIAG:=NO} == "YES" ]] ; then
    echo "? Working on convert jdiag to gdiag: ${pdy} ${cyc}Z"
    # Array of full file paths (only need to specify _anl files)
    #jdiags=(/scratch2/NCEPDEV/fv3-cam/Donald.E.Lippi/RRFSv2/PRs/RDASApp.20250324.DA_mon/rrfs-test/ush/diagnostics_and_graphics/jedivar_06/jdiag*)
    jdiags=(${JDIAGDIR}/${pdy}/rrfs_jedivar_${cyc}_${VERSION}/det/jedivar_${cyc}/jdiag*)
    #echo ${jdiags[1]}; exit

    # Run the Python script with analysis time and file list
    python jdiag_to_gdiag.py "$date" "${jdiags[@]}"
    mv diag_conv*.nc ${JDIAGDIR}/${pdy}/rrfs_jedivar_${cyc}_${VERSION}/det/jedivar_${cyc}/.
    exit
  fi


  # Increase date by 1 hour
  date=$(${ndate} 1 ${date})
done # date loop

exit 0
