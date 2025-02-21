#!/bin/bash
RDASApp=$( git rev-parse --show-toplevel 2>/dev/null )
if [[ -z ${RDASApp} ]]; then
  echo "Not under a clone of RDASApp!"
  echo "Please delete line 2-7 and set RDASApp variable mannually"
  exit
fi

#RDASApp="/path/to/RDASApp"  # set this variable if line2-7 was removed
exprname="fv3_2024052700"
expdir=${RDASApp}/expr/${exprname}  # can be set to any directory 
mkdir -p ${expdir}
cd ${expdir}
echo "expdir is at: ${expdir}"

${RDASApp}/ush/init.sh
cp -r ${RDASApp}/rrfs-test/testoutput ./testoutput
cp ${RDASApp}/rrfs-test/testinput/rrfs_fv3jedi_2024052700_Ens3Dvar.yaml .
cp ${RDASApp}/rrfs-test/testinput/rrfs_fv3jedi_2024052700_getkf_observer.yaml . 
cp ${RDASApp}/rrfs-test/testinput/rrfs_fv3jedi_2024052700_getkf_solver.yaml . 
cp ${RDASApp}/rrfs-test/testinput/rrfs_fv3jedi_2024052700_bumploc.yaml ./bumploc.yaml
sed -e "s#@RDASApp@#${RDASApp}#" ${RDASApp}/rrfs-test/scripts/templates/fv3jedi_expr/run_bump.sh > run_bump.sh
sed -e "s#@RDASApp@#${RDASApp}#" ${RDASApp}/rrfs-test/scripts/templates/fv3jedi_expr/run_jedi.sh > run_jedi.sh
cp ${RDASApp}/rrfs-test/ush/colormap.py . 
cp ${RDASApp}/rrfs-test/ush/fv3jedi_increment_singleob.py .
cp ${RDASApp}/rrfs-test/ush/fv3jedi_increment_fulldom.py . 
rm -rf Data; mkdir Data
ln -snf ${RDASApp}/fix/expr_data/${exprname}/Data/* Data/
# link correct ioda files
rm -rf Data/obs; mkdir  Data/obs
set -x
ln -snf ${RDASApp}/fix/expr_data/${exprname}/Data/obs/* Data/obs/  # keep this line for now to be backward compatible
for dcfile in Data/obs/ioda*dc.nc; do # link to DA runtime prescribed file names
  dcfile=${dcfile##*obs/}
  regfile="${dcfile%%_dc.nc}.nc"
  ln -snf ${RDASApp}/fix/expr_data/${exprname}/Data/obs/${dcfile} Data/obs/${regfile}
done
ln -snf ${RDASApp}/fix/expr_data/${exprname}/Data/obs/amsua_n19_obs.2024052700_dc.nc Data/obs/ioda_amsua_n19.nc
ln -snf ${RDASApp}/fix/expr_data/${exprname}/Data/obs/atms_n20_obs_2024052700_dc.nc Data/obs/ioda_atms_n20.nc
ln -snf ${RDASApp}/fix/expr_data/${exprname}/Data/obs/atms_npp_obs_2024052700_dc.nc  Data/obs/ioda_atms_npp.nc
#
ln -snf ${RDASApp}/fix/expr_data/${exprname}/DataFix DataFix
ln -snf ${RDASApp}/fix/expr_data/${exprname}/Data_static Data_static
ln -snf ${RDASApp}/fix/expr_data/${exprname}/INPUT INPUT
