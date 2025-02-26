#!/bin/bash

# Define the basic configuration YAMLs
basic_configs=(
    "fv3jedi_en3dvar.yaml"
    "fv3jedi_getkf_observer.yaml"
    "fv3jedi_getkf_solver.yaml"
)

# CTest yaml outputs
ctest_names=(
    "rrfs_fv3jedi_2024052700_Ens3Dvar.yaml"
    "rrfs_fv3jedi_2024052700_getkf_observer.yaml"
    "rrfs_fv3jedi_2024052700_getkf_solver.yaml"
)

# Define the aircar observation type configs as an array
aircar_obtype_configs=(
    "aircar_airTemperature_133.yaml"
    "aircar_winds_233.yaml"
    "aircar_specificHumidity_133.yaml"
)

# Define the aircft observation type configs as an array
aircft_obtype_configs=(
    "aircft_airTemperature_130.yaml"
    "aircft_airTemperature_131.yaml"
    "aircft_airTemperature_134.yaml"
    "aircft_airTemperature_135.yaml"
    "aircft_specificHumidity_134.yaml"
    "aircft_winds_230.yaml"
    "aircft_winds_231.yaml"
    "aircft_winds_234.yaml"
    "aircft_winds_235.yaml"
)

# Define msonet observation type configs as an array
msonet_obtype_configs=(
    "msonet_airTemperature_188.yaml"
    "msonet_specificHumidity_188.yaml"
    "msonet_stationPressure_188.yaml"
    "msonet_winds_288.yaml"
)

# Define ATMS observation type configs as an array
atms_obtype_configs=(
    "atms_npp_qc_bc.yaml"
)
# Define AMSUA observation type configs as an array
amsua_obtype_configs=(
    "amsua_n19.yaml"
)

# Function to concatenate all obtypes into one file
process_obtypes() {
    local ctest="$1"
    local obtype_configs=("${!2}")  # Accept array as input
    local obs_filename="$3"
    local temp_yaml="$4"
    
    # Determine the ctest type to select the observation distribution
    if [[ $ctest == *"solver"* ]]; then
        distribution="Halo"
    else
        distribution="RoundRobin"
    fi

    echo "Appending the following yamls:"
    for obtype_config in "${obtype_configs[@]}"; do
        echo "   $obtype_config"
        cat ./templates/obtype_config/$obtype_config >> ./$temp_yaml

        # For EnKF solver ctests, replace obsfile path with output from corresponding observer ctest
        if [[ $ctest == *"solver"* ]]; then
           previous_path=`sed -n '/obsdataout/{n; n; n; s/^[[:space:]]\+//; p;}' ./templates/obtype_config/$obtype_config`
           int_path=$(echo "$previous_path" | sed "s/obsfile: /..\/rundir-${ctest::-5}\//gI")
           new_path=$(echo "$int_path" | sed "s/solver/observer/gI")
           obs_filename=${new_path}
           sed -i "s#@OBSFILE@#${obs_filename}#" ./$temp_yaml
        fi

    done

    # Replace the @OBSFILE@ placeholder with the appropriate observation file (if it hasn't been done already)
    sed -i "s#@OBSFILE@#${obs_filename}#" ./$temp_yaml
    # Replace the @DISTRIBUTION@ placeholder with the appropriate observation distribution
    sed -i "s#@DISTRIBUTION@#${distribution}#" ./$temp_yaml
}

# Loop over basic config yamls
iconfig=0
for basic_config in "${basic_configs[@]}"; do

  # Create the super yaml (conv.yaml)
  conv_yaml="${ctest_names[$iconfig]}"
  temp_yaml="temp.yaml"

  rm -f $conv_yaml  # Remove any existing file
  rm -f $temp_yaml  # Remove any existing file

  # Concatenate all obtypes into the super yaml
  process_obtypes "${ctest_names[$iconfig]}" "aircar_obtype_configs[@]" "data/obs/ioda_aircar_dc.nc"             "$temp_yaml"
  #process_obtypes "${ctest_names[$iconfig]}" "aircft_obtype_configs[@]" "data/obs/ioda_aircft_dc.nc"             "$temp_yaml"
  process_obtypes "${ctest_names[$iconfig]}" "msonet_obtype_configs[@]" "data/obs/ioda_msonet_dc.nc"             "$temp_yaml"
  process_obtypes "${ctest_names[$iconfig]}" "atms_obtype_configs[@]"   "data/obs/atms_npp_obs_2024052700_dc.nc" "$temp_yaml"
  #process_obtypes "${ctest_names[$iconfig]}" "amsua_obtype_configs[@]"  "data/obs/ioda_amsua_n19_dc.nc"      "$temp_yaml"

  # Copy the basic configuration yaml into the super yaml
  cp -p templates/basic_config/$basic_config ./$conv_yaml

  # Replace @OBSERVATIONS@ placeholder with the contents of the combined yaml
  sed -i '/@OBSERVATIONS@/{
    r ./'"${temp_yaml}"'
    d
  }' ./$conv_yaml

  # Replace the @OBSFILE@ placeholder with a dummy filename (can customize as needed)
  sed -i "s#@OBSFILE@#data/obs/combined_obs_file.nc#" ./$conv_yaml

  echo "Super YAML created in ${conv_yaml}"

  # Move to testinput and remove the old temporary yaml
  mv $conv_yaml ../testinput/$conv_yaml
  rm -f $temp_yaml

  iconfig=$((iconfig+1))
done

