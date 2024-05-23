#!/bin/bash

RDASApp=@YOUR_PATH_TO_RDASAPP@
export PYTHONPATH="$PYTHONPATH:$RDASApp/build/lib/python3.10/"

module purge

hostname=`hostname | cut -c 1 | awk '{print tolower($0)}'`
if [[ $hostname == "h" ]]; then
  platform="hera"
elif [[ $hostname == "o" ]]; then
  platform="orion"
fi

module use @YOUR_PATH_TO_RDASAPP@/modulefiles
module load RDAS/${platform}.intel

module list

diag=$1
if [[ $1 == "" ]]; then
  diag="diag_conv_t_ges.2022052619"
fi

# Make output directory
mkdir -p obsout

# Run the python gsi_ncdiag tool to create GSI-diag derived IODA obs file.
# Tip: you might need to edit $RDASApp/build/lib/python3.10/pyiodaconv/gsi_ncdiag.py
gsi_ncdiag="$RDASApp/build/install-bin/test_gsidiag.py"
python $gsi_ncdiag --input $diag --output obsout --type conv --platform "sfc"
