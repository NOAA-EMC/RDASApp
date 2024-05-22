#!/bin/bash

module purge
module use @YOUR_PATH_TO_RDASAPP@/modulefiles
module load EVA/@platform@
module list

python gen_eva_obs_yaml.py -i msonet_airTemperature.yaml -o ./ -t jedi_gsi_compare_conv.yaml

# This might be a temporary fix to modify eva_*yaml files to use hofx0, EffectiveQC0, etc.
needs_changed="hofx EffectiveQC EffectiveError"
for i in $needs_changed; do
    sed -i "s#name: ${i}#name: ${i}0#g"  ./eva_mesonet_*yaml
    sed -i "s#::${i}::#::${i}0::#g"  ./eva_mesonet_*yaml
done

inputfile=$1
if [[ $1 == "" ]]; then
  inputfile="eva_mesonet_MSONET_hofxs_airTemperature_2022052619.yaml"
fi

eva ./$inputfile
