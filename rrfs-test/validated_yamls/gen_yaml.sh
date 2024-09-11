#!/bin/bash

# Define the basic configuration YAML
#basic_config="fv3jedi_hyb3denvar.yaml"
basic_config="mpasjedi_3dvar.yaml"

# Define the aircraft observation type configs as an array
aircraft_obtype_configs=(
    "aircft_airTemperature_130.yaml"
    "aircft_airTemperature_131.yaml"
    "aircft_airTemperature_133.yaml"
    "aircft_airTemperature_134.yaml"
    "aircft_airTemperature_135.yaml"
    #"aircft_specificHumidity_133.yaml"
    #"aircft_specificHumidity_134.yaml"
    "aircft_uv_230.yaml"
    "aircft_uv_231.yaml"
    "aircft_uv_233.yaml"
    "aircft_uv_234.yaml"
    "aircft_uv_235.yaml"
)

# Define mesonet observation type configs as an array
mesonet_obtype_configs=(
    "msonet_airTemperature_188.yaml"
    #"msonet_specificHumidity_188.yaml"
    "msonet_stationPressure_188.yaml"
    "msonet_uv_288.yaml"
)

# Function to concatenate all obtypes into one file
process_obtypes() {
    local obtype_configs=("${!1}")  # Accept array as input
    local obs_filename="$2"
    local temp_yaml="$3"

    echo "Appending the following yamls:"
    for obtype_config in "${obtype_configs[@]}"; do
        echo "   $obtype_config"
        cat ./templates/obtype_config/$obtype_config >> ./$temp_yaml
    done
    # Replace the @OBSFILE@ placeholder with the appropriate observation file
    sed -i "s#@OBSFILE@#\"${obs_filename}\"#" ./$temp_yaml
}

# Create the super yaml (conv.yaml)
conv_yaml="conv.yaml"
temp_yaml="temp.yaml"

rm -f $conv_yaml  # Remove any existing file
rm -f $temp_yaml  # Remove any existing file

# First, concatenate all aircraft obtypes into the super yaml
process_obtypes "aircraft_obtype_configs[@]" "data/obs/ioda_aircraft.nc" "$temp_yaml"

# Then, concatenate all mesonet obtypes into the same super yaml
process_obtypes "mesonet_obtype_configs[@]" "data/obs/ioda_mesonet.nc" "$temp_yaml"

# Copy the basic configuration yaml into the super yaml
cp -p templates/basic_config/$basic_config ./$conv_yaml

# Replace @OBSERVATIONS@ placeholder with the contents of the combined yaml
sed -i '/@OBSERVATIONS@/{
    r ./'"${temp_yaml}"'
    d
}' ./$conv_yaml

# Replace the @OBSFILE@ placeholder with a dummy filename (can customize as needed)
sed -i "s#@OBSFILE@#\"data/obs/combined_obs_file.nc\"#" ./$conv_yaml

echo "Super YAML created in ${conv_yaml}"

