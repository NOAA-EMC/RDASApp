#!/bin/bash

#use this script to combine the basic config yaml with an obtype config yaml.
basic_config="fv3jedi_hyb3denvar.yaml"
obtype_config="msonet_airTemperature_obtype188.yaml"

# Don't edit below this line.

# copy the basic configuration yaml into the new yaml
cp -p templates/basic_config/$basic_config ./$obtype_config

# use the stread editor to replace the instance of @OBSERVATION@ placeholder
# in the basic configuration file with the contents of the obtype config yaml.
sed -i '/@OBSERVATIONS@/{
        r templates/obtype_config/'"${obtype_config}"'
        d
}' ./$obtype_config
