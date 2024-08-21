#!/bin/bash

#use this script to combine the basic config yaml with an obtype config yaml.
basic_config="fv3jedi_hyb3denvar.yaml"
obtype_configs="
aircft_airTemperature_130.yaml
aircft_airTemperature_131.yaml
aircft_airTemperature_133.yaml
aircft_airTemperature_134.yaml
aircft_airTemperature_135.yaml

aircft_specificHumidity_133.yaml
aircft_specificHumidity_134.yaml

aircft_uv_230.yaml
aircft_uv_231.yaml
aircft_uv_233.yaml
aircft_uv_234.yaml
aircft_uv_235.yaml

msonet_airTemperature_188.yaml
msonet_specificHumidity_188.yaml
msonet_stationPressure_188.yaml
msonet_uv_288.yaml
"

obtype="conv.yaml"

temp_config="combined.yaml"
rm -f $temp_config
echo "catting the following yamls:"
for obtype_config in $obtype_configs; do
    echo "   $obtype_config"
    cat ./templates/obtype_config/$obtype_config >> ./$temp_config
done

# copy the basic configuration yaml into the new yaml
cp -p templates/basic_config/$basic_config ./${obtype}

# use the stread editor to replace the instance of @OBSERVATION@ placeholder
# in the basic configuration file with the contents of the obtype config yaml.
sed -i '/@OBSERVATIONS@/{
        r ./'"${temp_config}"'
        d
}' ./${obtype}
