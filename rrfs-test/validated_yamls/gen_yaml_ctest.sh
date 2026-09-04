#!/bin/bash
set echo

# Define all observation type configurations
obtype_configs=(
    "aircar_airTemperature_133.yaml"
    "aircar_specificHumidity_133.yaml"
    "aircar_winds_233.yaml"
    #"aircft_airTemperature_130.yaml"
    #"aircft_airTemperature_131.yaml"
    #"aircft_airTemperature_134.yaml"
    #"aircft_airTemperature_135.yaml"
    #"aircft_specificHumidity_134.yaml"
    #"aircft_winds_230.yaml"
    #"aircft_winds_231.yaml"
    #"aircft_winds_234.yaml"
    #"aircft_winds_235.yaml"
    #"msonet_airTemperature_188.yaml"
    #"msonet_specificHumidity_188.yaml"
    #"gnss_zenithTotalDelay.yaml"
    #"msonet_stationPressure_188.yaml" # Different result on Hera/Hercules
    #"msonet_winds_288.yaml"
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
    #"atms_npp.yaml"
    #"abi_g16.yaml"
    #"abi_g18.yaml"
    #"atms_n21.yaml"
    #"atms_n20.yaml" # Waiting to add to ctest (different results on Hera/Jet?)
    #"amsua_n19.yaml" # Waiting to add to ctest
    #"amsua_metop-b.yaml"
    #"amsua_metop-c.yaml"
)

# Define the basic configuration and final ctest YAMLs
declare -A basic_configs
basic_configs=(
    #["fv3jedi_3dvar.yaml"]="rrfs_fv3jedi_2024052700_3dvar.yaml"
    #["fv3jedi_3denvar.yaml"]="rrfs_fv3jedi_2024052700_3denvar.yaml"
    #["fv3jedi_hybrid3denvar.yaml"]="rrfs_fv3jedi_2024052700_hybrid3denvar.yaml"
    ["mpasjedi_3denvar.yaml"]="rrfs_mpasjedi_2024052700_3denvar.yaml"
    ["mpasjedi_getkf.yaml"]="rrfs_mpasjedi_2024052700_getkf.yaml"
)

# Loop over basic configs
for basic_config in "${!basic_configs[@]}"; do

    rm -f jedi.yaml    # Remove any existing file
    rm -f temp.yaml    # Remove any existing file
    ctest_yaml=${basic_configs[$basic_config]}

    # Concatenate each obtype YAML into the combined observations block
    for config in "${obtype_configs[@]}"; do
        cat "./templates/obtype_config/$config" >> ./temp.yaml
    done

    # Replace the @DISTRIBUTION@ placeholder with the appropriate observation distribution
    if [[ $basic_config == *"getkf.yaml" ]]; then
        distribution="Halo"
    else
        distribution="RoundRobin"
    fi
    sed -i "s#@DISTRIBUTION@#${distribution}#" ./temp.yaml

    # One-step L/GETKF: H(x) is computed here under ioda's default (RoundRobin) distribution and
    # the obs are then redistributed into the local-solver Halo within the same job. That is
    # requested with "redistribution" rather than "distribution", and needs the dataframe backend.
    if [[ $basic_config == *"getkf.yaml" ]]; then
        awk '
            {
                line = $0
                if (line ~ /^[[:space:]]*distribution:[[:space:]]*$/) {
                    match(line, /^[[:space:]]*/)
                    indent = substr(line, 1, RLENGTH)
                    sub(/distribution:/, "redistribution:", line)
                    print line
                    next
                }
                print line
                if (indent != "" && line ~ /^[[:space:]]*halo size:/) {
                    print indent "use data frame container: true"
                    indent = ""
                }
            }
        ' ./temp.yaml > ./temp_onestep.yaml && mv ./temp_onestep.yaml ./temp.yaml
    fi

    # Copy the basic configuration yaml into the super yaml
    cp -p templates/basic_config/$basic_config ./jedi.yaml

    # Replace @OBSERVATIONS@ placeholder with the contents of the combined yaml
    sed -i '/@OBSERVATIONS@/{
        r ./'"temp.yaml"'
        d
    }' ./jedi.yaml
    rm -f temp.yaml # Clean up temporary yaml

    # Comment out some filters for the various ctests (different for fv3-jedi and mpas-jedi)
    python commentQC.py ${ctest_yaml}

    # Move to testinput and remove the old temporary yaml
    sed -i -e "s/@emptyObsSpaceAction@/create output/"  ./jedi.yaml
    ctest_yaml=${basic_configs[$basic_config]}
    echo "Super YAML created in ../testinput/${ctest_yaml}"
    mv ./jedi.yaml ../testinput/$ctest_yaml

done
