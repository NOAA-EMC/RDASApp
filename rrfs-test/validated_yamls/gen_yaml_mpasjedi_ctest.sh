#!/bin/bash

# Function to add key-value pairs to a dictionary and maintain order
add_to_dict() {
    local -n dict_ref=$1
    local -n keys=$2
    local key=$3
    local value=$4
    dict_ref["$key"]="$value"
    keys+=("$key")
}

###############################################
### Edit this section if adding more ctests ###
###############################################

# Dictionary to define the basic configuration yamls and the ctest output names
declare -A ctest_configs
keys_ctest=()
add_to_dict ctest_configs keys_ctest "mpasjedi_en3dvar.yaml"        "rrfs_mpasjedi_2024052700_Ens3Dvar.yaml"
add_to_dict ctest_configs keys_ctest "mpasjedi_getkf_observer.yaml" "rrfs_mpasjedi_2024052700_getkf_observer.yaml"
add_to_dict ctest_configs keys_ctest "mpasjedi_getkf_solver.yaml"   "rrfs_mpasjedi_2024052700_getkf_solver.yaml"


########################################################
### Edit this section if adding more obs-space yamls ###
########################################################

# Dictionary to define the ob-space yamls to be merged in along with the obs file used for them 
declare -A obtype_configs
keys_obtype=()
add_to_dict obtype_configs keys_obtype "aircar_airTemperature_133.yaml"    "data/obs/ioda_aircar_dc.nc"
add_to_dict obtype_configs keys_obtype "aircar_specificHumidity_133.yaml"  "data/obs/ioda_aircar_dc.nc"
add_to_dict obtype_configs keys_obtype "aircar_winds_233.yaml"             "data/obs/ioda_aircar_dc"
add_to_dict obtype_configs keys_obtype "aircft_airTemperature_130.yaml"    "data/obs/ioda_aircft_dc.nc"
add_to_dict obtype_configs keys_obtype "aircft_airTemperature_131.yaml"    "data/obs/ioda_aircft_dc.nc"
add_to_dict obtype_configs keys_obtype "aircft_airTemperature_134.yaml"    "data/obs/ioda_aircft_dc.nc"
add_to_dict obtype_configs keys_obtype "aircft_airTemperature_135.yaml"    "data/obs/ioda_aircft_dc.nc"
add_to_dict obtype_configs keys_obtype "aircft_specificHumidity_134.yaml"  "data/obs/ioda_aircft_dc.nc"
add_to_dict obtype_configs keys_obtype "aircft_winds_230.yaml"             "data/obs/ioda_aircft_dc.nc"
add_to_dict obtype_configs keys_obtype "aircft_winds_231.yaml"             "data/obs/ioda_aircft_dc.nc"
add_to_dict obtype_configs keys_obtype "aircft_winds_234.yaml"             "data/obs/ioda_aircft_dc.nc"
add_to_dict obtype_configs keys_obtype "aircft_winds_235.yaml"             "data/obs/ioda_aircft_dc.nc"
add_to_dict obtype_configs keys_obtype "msonet_airTemperature_188.yaml"    "data/obs/ioda_msonet_dc.nc"
add_to_dict obtype_configs keys_obtype "msonet_specificHumidity_188.yaml"  "data/obs/ioda_msonet_dc.nc"
add_to_dict obtype_configs keys_obtype "msonet_stationPressure_188.yaml"   "data/obs/ioda_msonet_dc.nc"
add_to_dict obtype_configs keys_obtype "msonet_winds_288.yaml"             "data/obs/ioda_msonet_dc.nc"
add_to_dict obtype_configs keys_obtype "adpsfc_airTemperature_187.yaml"    "data/obs/ioda_adpsfc_dc.nc"
add_to_dict obtype_configs keys_obtype "adpsfc_specificHumidity_187.yaml"  "data/obs/ioda_adpsfc_dc.nc"
add_to_dict obtype_configs keys_obtype "adpsfc_stationPressure_187.yaml"   "data/obs/ioda_adpsfc_dc.nc"
add_to_dict obtype_configs keys_obtype "adpsfc_winds_287.yaml"             "data/obs/ioda_adpsfc_dc.nc"
add_to_dict obtype_configs keys_obtype "adpupa_airTemperature_120.yaml"    "data/obs/ioda_adpupa_dc.nc"
add_to_dict obtype_configs keys_obtype "adpupa_specificHumidity_120.yaml"  "data/obs/ioda_adpupa_dc.nc"
add_to_dict obtype_configs keys_obtype "adpupa_winds_220.yaml"             "data/obs/ioda_adpupa_dc.nc"
add_to_dict obtype_configs keys_obtype "vadwnd_winds_224.yaml"             "data/obs/ioda_vadwnd_dc.nc" 
add_to_dict obtype_configs keys_obtype "atms_npp_qc_bc.yaml"               "data/obs/atms_npp_obs_2024052700_dc.nc"
#add_to_dict obtype_configs keys_obtype "atms_n20.yaml"                     "data/obs/ioda_atms_n20.nc" # file missing?
add_to_dict obtype_configs keys_obtype "amsua_n19.yaml"                    "data/obs/amsua_n19_obs.2024052700_dc.nc" 


#############################
### Begin executable code ###
#############################

# Function to concatenate all obtypes into one file
process_obtypes() {
    local -n obtype_config_in=$1
    local -n keys_obtype_in=$2
    local ctest=$3
    local temp_yaml=$4

    # Determine the ctest type to select the observation distribution
    if [[ $ctest == *"solver"* ]]; then
        distribution="Halo"
    else
        distribution="RoundRobin"
    fi

    echo "Appending the following yamls:"
    for key in "${keys_obtype_in[@]}"; do 
        obtype_config=$key
        obs_filename=${obtype_config_in[$key]}
        echo "   $obtype_config"
        cat ./templates/obtype_config/$obtype_config >> ./$temp_yaml

        # For EnKF solver ctests, replace obsfile path with output from corresponding observer ctest
        if [[ $ctest == *"solver"* ]]; then
           previous_path=`sed -n '/obsdataout/{n; n; n; s/^[[:space:]]\+//; p;}' ./templates/obtype_config/$obtype_config`
           int_path=$(echo "$previous_path" | sed "s/obsfile: /..\/rundir-${ctest::-5}\//gI")
           new_path=$(echo "$int_path" | sed "s/solver/observer/gI")
           obs_filename=${new_path}
	fi 
        sed -i "s#@OBSFILE@#${obs_filename}#" ./$temp_yaml

    done

    # Replace the @OBSFILE@ placeholder with the appropriate observation file (if it hasn't been done already)
    #sed -i "s#@OBSFILE@#${obs_filename}#" ./$temp_yaml
    # Replace the @DISTRIBUTION@ placeholder with the appropriate observation distribution
    sed -i "s#@DISTRIBUTION@#${distribution}#" ./$temp_yaml
}

# Loop over basic config yamls
iconfig=0
for basic_config in "${!ctest_configs[@]}"; do

  # Create the super yaml (conv.yaml)
  conv_yaml="${ctest_configs[$basic_config]}"
  temp_yaml="temp.yaml"

  rm -f $conv_yaml  # Remove any existing file
  rm -f $temp_yaml  # Remove any existing file

  # Concatenate all obtypes into the super yaml
  process_obtypes obtype_configs keys_obtype "${conv_yaml}" "$temp_yaml"

  # Copy the basic configuration yaml into the super yaml
  cp -p templates/basic_config/$basic_config ./$conv_yaml

  # Replace @OBSERVATIONS@ placeholder with the contents of the combined yaml
  sed -i '/@OBSERVATIONS@/{
    r ./'"${temp_yaml}"'
    d
  }' ./$conv_yaml

  # Replace the @OBSFILE@ placeholder with a dummy filename (can customize as needed)
  sed -i "s#@OBSFILE@#data/obs/combined_obs_file.nc#" ./$conv_yaml

  # Move to testinput and remove the old temporary yaml
  echo "Super YAML created in ${conv_yaml}"
  mv $conv_yaml ../testinput/$conv_yaml
  rm -f $temp_yaml

  iconfig=$((iconfig+1))
done

