#!/bin/bash
RDASAPP=$( git rev-parse --show-toplevel 2>/dev/null )
if [[ -z ${RDASAPP} ]]; then
  echo "Not under a clone of RDASAPP!"
  echo "Please delete line 2-7 and set RDASAPP variable mannually"
  exit
fi

#RDASAPP="/path/to/RDASApp"  # set this variable if line2-7 was removed
BUMPLOC="conus12km-401km11levels"
exprname="mpas_2024052700"
expdir=${RDASAPP}/expr/${exprname}  # can be set to any directory 
mkdir -p ${expdir}
cd ${expdir}
echo "expdir is at: ${expdir}"

${RDASAPP}/ush/init.sh
ln -snf ${RDASAPP}/fix/physics/* .
mkdir -p graphinfo stream_list
ln -snf ${RDASAPP}/fix/graphinfo/* graphinfo/
cp -rp ${RDASAPP}/fix/stream_list/* stream_list/
cp ${RDASAPP}/sorc/mpas-jedi/test/testinput/obsop_name_map.yaml .
cp ${RDASAPP}/sorc/mpas-jedi/test/testinput/namelists/keptvars.yaml .
cp ${RDASAPP}/sorc/mpas-jedi/test/testinput/namelists/geovars.yaml .
cp ${RDASAPP}/rrfs-test/testinput/bumploc.yaml .
cp ${RDASAPP}/rrfs-test/testinput/namelist.atmosphere .
cp ${RDASAPP}/rrfs-test/testinput/streams.atmosphere .
cp ${RDASAPP}/rrfs-test/testinput/sonde_singeob_airTemperature_mpasjedi.yaml .
cp ${RDASAPP}/rrfs-test/scripts/templates/mpasjedi_expr/run_bump.sh .
cp ${RDASAPP}/rrfs-test/scripts/templates/mpasjedi_expr/run_jedi.sh .
cp ${RDASAPP}/rrfs-test/ush/colormap.py .
cp ${RDASAPP}/rrfs-test/ush/mpasjedi_increment_singleob.py .
cp ${RDASAPP}/rrfs-test/ush/mpasjedi_spread.py .

mkdir -p data
cd data
mkdir -p bumploc bkg obs ens
ln -snf ${RDASAPP}/fix/bumploc/${BUMPLOC} bumploc/
ln -snf ${RDASAPP}/fix/expr_data/${exprname}/bkg/restart.2024-05-27_00.00.00.nc .
ln -snf ${RDASAPP}/fix/expr_data/${exprname}/bkg/restart.2024-05-27_00.00.00.nc static.nc
ln -snf ${RDASAPP}/fix/expr_data/${exprname}/obs/* obs/
ln -snf ${RDASAPP}/fix/expr_data/${exprname}/ens/* ens/

