#!/bin/bash

# Define the basic configuration YAML
#basic_config="mpasjedi_en3dvar.yaml"
basic_config="mpasjedi_getkf_observer.yaml"
#basic_config="mpasjedi_getkf_solver.yaml"
#basic_config="mpasjedi_letkf_observer.yaml"
#basic_config="mpasjedi_letkf_solver.yaml"


# Define the aircar observation type configs as an array
aircar_obtype_configs=(
    "aircar_airTemperature_133.yaml"
    "aircar_uv_233.yaml"
    "aircar_specificHumidity_133.yaml"
)

# Define the aircft observation type configs as an array
aircft_obtype_configs=(
    "aircft_airTemperature_130.yaml"
    "aircft_airTemperature_131.yaml"
    "aircft_airTemperature_134.yaml"
    "aircft_airTemperature_135.yaml"
    "aircft_specificHumidity_134.yaml"
    "aircft_uv_230.yaml"
    "aircft_uv_231.yaml"
    "aircft_uv_234.yaml"
    "aircft_uv_235.yaml"
)

# Define msonet observation type configs as an array
msonet_obtype_configs=(
    "msonet_airTemperature_188.yaml"
    "msonet_specificHumidity_188.yaml"
    "msonet_stationPressure_188.yaml"
    "msonet_uv_288.yaml"
)

# Function to concatenate all obtypes into one file
process_obtypes() {
    local ctesttype="$1"
    local obtype_configs=("${!2}")  # Accept array as input
    local obs_filename="$3"
    local temp_yaml="$4"

    # Determine the ctest type to select the observation distribution
    if [ $ctesttype == *"solver"* ]; then
        distribution="Halo"
    else
        distribution="RoundRobin"
    fi

    echo "Appending the following yamls:"
    for obtype_config in "${obtype_configs[@]}"; do
        echo "   $obtype_config"
        cat ./templates/obtype_config/$obtype_config >> ./$temp_yaml
    done
    # Replace the @OBSFILE@ placeholder with the appropriate observation file
    sed -i "s#@OBSFILE@#\"${obs_filename}\"#" ./$temp_yaml
    # Replace the @DISTRIBUTION@ placeholder with the appropriate observation distribution
    sed -i "s#@DISTRIBUTION@#\"${distribution}\"#" ./$temp_yaml
}

# Create the super yaml (conv.yaml)
conv_yaml="conv.yaml"
temp_yaml="temp.yaml"

rm -f $conv_yaml  # Remove any existing file
rm -f $temp_yaml  # Remove any existing file

# Concatenate all obtypes into the super yaml
process_obtypes "$basic_config" "aircar_obtype_configs[@]" "data/obs_ctest/ioda_aircar_dc.nc" "$temp_yaml"
process_obtypes "$basic_config" "aircft_obtype_configs[@]" "data/obs_ctest/ioda_aircft_dc.nc" "$temp_yaml"
process_obtypes "$basic_config" "msonet_obtype_configs[@]" "data/obs_ctest/ioda_msonet_dc.nc" "$temp_yaml"

# Copy the basic configuration yaml into the super yaml
cp -p templates/basic_config/$basic_config ./$conv_yaml

# Replace @OBSERVATIONS@ placeholder with the contents of the combined yaml
sed -i '/@OBSERVATIONS@/{
    r ./'"${temp_yaml}"'
    d
}' ./$conv_yaml

# Replace the @OBSFILE@ placeholder with a dummy filename (can customize as needed)
sed -i "s#@OBSFILE@#\"data/obs_ctest/combined_obs_file.nc\"#" ./$conv_yaml

echo "Super YAML created in ${conv_yaml}"

# Remove the old temporary yaml
rm -f $temp_yaml

