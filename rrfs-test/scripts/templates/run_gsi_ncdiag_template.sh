#!/bin/bash

RDASApp=@YOUR_PATH_TO_RDASAPP@

module purge

MACHINE_ID="@MACHINE_ID@"

if [[ $MACHINE_ID == "hera" ]]; then
  export PYTHONPATH="$PYTHONPATH:$RDASApp/build/lib/python3.10/"
elif [[ $MACHINE_ID == "orion" ]]; then
  export PYTHONPATH="$PYTHONPATH:$RDASApp/build/lib/python3.7/"
elif [[ $MACHINE_ID == "jet" ]]; then
  export PYTHONPATH="$PYTHONPATH:$RDASApp/build/lib/python3.10/"
fi

module use @YOUR_PATH_TO_RDASAPP@/modulefiles
module load RDAS/@MACHINE_ID@.intel

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
