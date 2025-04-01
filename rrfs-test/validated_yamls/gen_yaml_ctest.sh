#!/bin/bash
set echo

# Define all observation type configurations
obtype_configs=(
    "aircar_airTemperature_133.yaml"
    "aircar_specificHumidity_133.yaml"
    "aircar_winds_233.yaml"
    "aircft_airTemperature_130.yaml"
    "aircft_airTemperature_131.yaml"
    "aircft_airTemperature_134.yaml"
    "aircft_airTemperature_135.yaml"
    "aircft_specificHumidity_134.yaml"
    "aircft_winds_230.yaml"
    "aircft_winds_231.yaml"
    "aircft_winds_234.yaml"
    "aircft_winds_235.yaml"
    "msonet_airTemperature_188.yaml"
    "msonet_specificHumidity_188.yaml"
    "gnss_zenithTotalDelay.yaml"
    #"msonet_stationPressure_188.yaml" # Different result on Hera/Hercules
    "msonet_winds_288.yaml"
    #"adpsfc_airTemperature_187.yaml" # Waiting to add to ctest
    #"adpsfc_specificHumidity_187.yaml" # Waiting to add to ctest
    #"adpsfc_stationPressure_187.yaml" # Waiting to add to ctest (different results on Hera/Jet?)
    #"adpsfc_winds_287.yaml" # Waiting to add to ctest
    #"adpupa_airTemperature_120.yaml" # Waiting to add to ctest
    #"adpupa_specificHumidity_120.yaml" # Waiting to add to ctest
    #"adpupa_winds_220.yaml" # Waiting to add to ctest
    #"proflr_winds_227.yaml" # DO NOT ADD - Not yet phase 3
    #"rassda_airTemperature_126.yaml" # DO NOT ADD - Not yet phase 3
    #"vadwnd_winds_224.yaml" # DO NOT ADD - Not yet phase 3
    "atms_npp.yaml"
    "abi_g16.yaml"
    "abi_g18.yaml"

    #"atms_n20.yaml" # Waiting to add to ctest (different results on Hera/Jet?)
    #"amsua_n19.yaml" # Waiting to add to ctest
)

# Define the basic configuration and final ctest YAMLs
declare -A basic_configs
basic_configs=(
    ["fv3jedi_en3dvar.yaml"]="rrfs_fv3jedi_2024052700_Ens3Dvar.yaml"
    ["fv3jedi_getkf_observer.yaml"]="rrfs_fv3jedi_2024052700_getkf_observer.yaml"
    ["fv3jedi_getkf_solver.yaml"]="rrfs_fv3jedi_2024052700_getkf_solver.yaml"
    ["mpasjedi_en3dvar.yaml"]="rrfs_mpasjedi_2024052700_Ens3Dvar.yaml"
    ["mpasjedi_getkf_observer.yaml"]="rrfs_mpasjedi_2024052700_getkf_observer.yaml"
    ["mpasjedi_getkf_solver.yaml"]="rrfs_mpasjedi_2024052700_getkf_solver.yaml"
)

# Loop over basic configs
for basic_config in "${!basic_configs[@]}"; do

    rm -f jedi.yaml    # Remove any existing file
    rm -f temp.yaml    # Remove any existing file
    rm -f replace.yaml # Remove any existing file
    ctest_yaml=${basic_configs[$basic_config]}

    # Process each YAML file
    declare -A processed_groups
    for config in "${obtype_configs[@]}"; do
# hliu

        # If this is a LETKF solver ctest, we need to replace the input obs file with the observer's jdiag file 
        cp  "./templates/obtype_config/$config" ./replace.yaml
        if [[ $basic_config == *"solver"* ]]; then
            # New obs filename
            previous_path=`sed -n '/obsdataout/{n; n; n; s/^[[:space:]]\+//; p;}' ./templates/obtype_config/$config`
            int_path=$(echo "$previous_path" | sed "s/obsfile: /..\/rundir-${ctest_yaml::-5}\//gI")
            new_path=$(echo "$int_path" | sed "s/solver/observer/gI")
            obs_filename_new="obsfile: ${new_path}"
            # Old obs file name to replace
            obsline=`grep "obsfile: data\/obs\/ioda" templates/obtype_config/${config}`
            trimmed=$(echo "$obsline" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            obs_filename=${trimmed}
            # Replace
            sed -i "s#${obs_filename}#${obs_filename_new}#" ./replace.yaml
        fi

        # Append YAML content
        cat ./replace.yaml >> ./temp.yaml

    done

    # Replace the @DISTRIBUTION@ placeholder with the appropriate observation distribution
    if [[ $basic_config == *"solver"* ]]; then
        distribution="Halo"
    else
        distribution="RoundRobin"
    fi
    sed -i "s#@DISTRIBUTION@#${distribution}#" ./temp.yaml

    # Copy the basic configuration yaml into the super yaml
    cp -p templates/basic_config/$basic_config ./jedi.yaml

    # Replace @OBSERVATIONS@ placeholder with the contents of the combined yaml
    sed -i '/@OBSERVATIONS@/{
        r ./'"temp.yaml"'
        d
    }' ./jedi.yaml
    rm -f temp.yaml # Clean up temporary yaml
    rm -f replace.yaml # Clean up temporary yaml

    # Comment out some filters for the various ctests (different for fv3-jedi and mpas-jedi)
    python commentQC.py ${ctest_yaml}

    # Move to testinput and remove the old temporary yaml
    ctest_yaml=${basic_configs[$basic_config]}
    echo "Super YAML created in ../testinput/${ctest_yaml}"
    mv ./jedi.yaml ../testinput/$ctest_yaml

done
