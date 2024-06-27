#!/bin/bash
RDASApp=$( git rev-parse --show-toplevel 2>/dev/null )
if [[ -z ${RDASApp} ]]; then
  echo "Not under a clone of RDASApp!"
  echo "Please delete line 1-6 and set RDASApp variable mannually"
  exit
fi

BUMPLOC="conus12km-401km11levels"
exprname="mpas_2024052700"

ln -snf ${RDASApp}/fix/physics/* .
mkdir -p graphinfo stream_list
ln -snf ${RDASApp}/fix/graphinfo/* graphinfo/
cp -rp ${RDASApp}/fix/stream_list/* stream_list/
cp ${RDASApp}/sorc/mpas-jedi/test/testinput/obsop_name_map.yaml .
cp ${RDASApp}/sorc/mpas-jedi/test/testinput/namelists/keptvars.yaml .
cp ${RDASApp}/sorc/mpas-jedi/test/testinput/namelists/geovars.yaml .
cp ${RDASApp}/ush/colormap.py .
cp ${RDASApp}/ush/mpasjedi_increment_singleob.py .

mkdir -p data; cd data
mkdir -p bumploc bkg obs ens
ln -snf ${RDASApp}/fix/bumploc/${BUMPLOC} bumploc/
ln -snf ${RDASApp}/fix/expr_data/${exprname}/bkg/restart.2024-05-27_00.00.00.nc .
ln -snf ${RDASApp}/fix/expr_data/${exprname}/bkg/restart.2024-05-27_00.00.00.nc static.nc
ln -snf ${RDASApp}/fix/expr_data/${exprname}/obs/* obs/
ln -snf ${RDASApp}/fix/expr_data/${exprname}/ens/* ens/
