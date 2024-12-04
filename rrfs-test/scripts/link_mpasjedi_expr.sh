#!/bin/bash
RDASApp=$( git rev-parse --show-toplevel 2>/dev/null )
if [[ -z ${RDASApp} ]]; then
  echo "Not under a clone of RDASApp!"
  echo "Please delete line 2-7 and set RDASApp variable mannually"
  exit
fi

#RDASApp="/path/to/RDASApp"  # set this variable if line2-7 was removed
BUMPLOC="conus12km-401km11levels"
exprname="mpas_2024052700"
if [[ "$1" == "atl12km" ]]; then
  BUMPLOC="atl12km-401km11levels"
  exprname="atl_2024052700"
fi
expdir=${RDASApp}/expr/${exprname}  # can be set to any directory 
mkdir -p ${expdir}
cd ${expdir}
echo "expdir is at: ${expdir}"

${RDASApp}/ush/init.sh
ln -snf ${RDASApp}/fix/physics/* .
mkdir -p graphinfo stream_list testoutput
ln -snf ${RDASApp}/fix/graphinfo/* graphinfo/
ln -snf ${RDASApp}/rrfs-test/testoutput/* testoutput/
cp -rp ${RDASApp}/fix/stream_list/* stream_list/
cp ${RDASApp}/sorc/mpas-jedi/test/testinput/obsop_name_map.yaml .
cp ${RDASApp}/sorc/mpas-jedi/test/testinput/namelists/keptvars.yaml .
cp ${RDASApp}/sorc/mpas-jedi/test/testinput/namelists/geovars.yaml .
cp ${RDASApp}/rrfs-test/testinput_expr/rrfs_mpasjedi_2024052700_bumploc.yaml ./bumploc.yaml
cp ${RDASApp}/rrfs-test/testinput_expr/namelist.atmosphere .
cp ${RDASApp}/rrfs-test/testinput_expr/streams.atmosphere .
cp ${RDASApp}/rrfs-test/testinput_expr/rrfs_mpasjedi_2024052700_Ens3Dvar.yaml .
cp ${RDASApp}/rrfs-test/testinput_expr/rrfs_mpasjedi_2024052700_letkf.yaml .
cp ${RDASApp}/rrfs-test/testinput_expr/rrfs_mpasjedi_2024052700_getkf.yaml .
cp ${RDASApp}/rrfs-test/testinput_expr/rrfs_mpasjedi_2024052700_getkf_observer.yaml .
cp ${RDASApp}/rrfs-test/testinput_expr/rrfs_mpasjedi_2024052700_getkf_solver.yaml .
if [[ "${exprname}" == "atl_2024052700" ]]; then
  sed -i -e "s/conus12km_mpas.graph/atl12km.graph/" ./namelist.atmosphere
  sed -i -e "s/conus12km-401km11levels/atl12km-401km11levels/" ./rrfs_mpasjedi_2024052700_Ens3Dvar.yaml
fi
sed -e "s#@RDASApp@#${RDASApp}#" ${RDASApp}/rrfs-test/scripts/templates/mpasjedi_expr/run_bump.sh > run_bump.sh
sed -e "s#@RDASApp@#${RDASApp}#" ${RDASApp}/rrfs-test/scripts/templates/mpasjedi_expr/run_jedi.sh > run_jedi.sh
cp ${RDASApp}/rrfs-test/ush/colormap.py .
cp ${RDASApp}/rrfs-test/ush/mpasjedi_increment_singleob.py .
cp ${RDASApp}/rrfs-test/ush/mpasjedi_increment_fulldom.py .
cp ${RDASApp}/rrfs-test/ush/mpasjedi_spread.py .

mkdir -p data
cd data
mkdir -p bumploc obs ens
ln -snf ${RDASApp}/fix/bumploc/${BUMPLOC} bumploc/${BUMPLOC}
ln -snf ${RDASApp}/fix/expr_data/${exprname}/bkg/mpasout.2024-05-27_00.00.00.nc .
ln -snf ${RDASApp}/fix/expr_data/${exprname}/invariant.nc invariant.nc
ln -snf ${RDASApp}/fix/expr_data/${exprname}/obs/* obs/
ln -snf ${RDASApp}/fix/expr_data/${exprname}/ens/* ens/
ln -snf ${RDASApp}/fix/crtm/2.4.0 crtm

