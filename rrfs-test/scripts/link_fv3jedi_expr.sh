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
cp ${RDASApp}/rrfs-test/testinput/rrfs_fv3jedi_2024052700_3dvar.yaml .
cp ${RDASApp}/rrfs-test/testinput/rrfs_fv3jedi_2024052700_3denvar.yaml .
cp ${RDASApp}/rrfs-test/testinput/rrfs_fv3jedi_2024052700_hybrid3denvar.yaml .
cp ${RDASApp}/rrfs-test/testinput/rrfs_fv3jedi_2024052700_getkf_observer.yaml .
cp ${RDASApp}/rrfs-test/testinput/rrfs_fv3jedi_2024052700_getkf_solver.yaml .
cp ${RDASApp}/rrfs-test/testinput/rrfs_fv3jedi_2024052700_bumploc.yaml ./bumploc.yaml
cp ${RDASApp}/rrfs-test/testinput/rrfs_fv3jedi_2024052700_3dvar_conv_surface.yaml .
cp ${RDASApp}/rrfs-test/testinput/rrfs_fv3jedi_2024052700_3dvar_conv_upperair.yaml .
cp ${RDASApp}/rrfs-test/testinput/rrfs_fv3jedi_2024052700_3dvar_remote.yaml .
cp ${RDASApp}/rrfs-test/testinput/rrfs_fv3jedi_2024052700_3dvar_satrad.yaml .
sed -e "s#@RDASApp@#${RDASApp}#" ${RDASApp}/rrfs-test/scripts/templates/fv3jedi_expr/run_bump.sh > run_bump.sh
sed -e "s#@RDASApp@#${RDASApp}#" ${RDASApp}/rrfs-test/scripts/templates/fv3jedi_expr/run_jedi.sh > run_jedi.sh
cp ${RDASApp}/rrfs-test/ush/colormap.py .
cp ${RDASApp}/rrfs-test/ush/fv3jedi_increment_singleob.py .
cp ${RDASApp}/rrfs-test/ush/fv3jedi_increment_fulldom.py .
rm -rf data; mkdir data
ln -snf ${RDASApp}/fix/expr_data/${exprname}/data/* data/
ln -snf ${RDASApp}/fix/expr_data/${exprname}/data/bkg/20240527.000000.fv_core.res.nc fv_core.res.nc
ln -snf ${RDASApp}/fix/expr_data/${exprname}/data/bkg/20240527.000000.fv_core.res.tile1.nc fv_core.res.tile1.nc
ln -snf ${RDASApp}/fix/expr_data/${exprname}/data/bkg/20240527.000000.fv_srf_wnd.res.tile1.nc fv_srf_wnd.res.tile1.nc
ln -snf ${RDASApp}/fix/expr_data/${exprname}/data/bkg/20240527.000000.fv_tracer.res.tile1.nc fv_tracer.res.tile1.nc
ln -snf ${RDASApp}/fix/expr_data/${exprname}/data/bkg/20240527.000000.phy_data.nc phy_data.nc
ln -snf ${RDASApp}/fix/expr_data/${exprname}/data/bkg/20240527.000000.sfc_data.nc sfc_data.nc
# link correct ioda files
rm -rf data/{obs,satbias_in}
mkdir -p data/{obs,satbias_in,satbias_out}
ln -snf ${RDASApp}/fix/expr_data/${exprname}/data/satbias_in/* data/satbias_in/
ln -snf ${RDASApp}/fix/expr_data/${exprname}/data/obs/* data/obs/  # keep this line for now to be backward compatible
for dcfile in data/obs/ioda*dc.nc; do # link to DA runtime prescribed file names
  dcfile=${dcfile##*obs/}
  regfile="${dcfile%%_dc.nc}.nc"
  ln -snf ${RDASApp}/fix/expr_data/${exprname}/data/obs/${dcfile} data/obs/${regfile}
done
ln -snf ${RDASApp}/fix/expr_data/${exprname}/data/obs/amsua_n19_obs.2024052700_dc.nc data/obs/ioda_amsua_n19.nc
ln -snf ${RDASApp}/fix/expr_data/${exprname}/data/obs/atms_n20_obs_2024052700_dc.nc data/obs/ioda_atms_n20.nc
ln -snf ${RDASApp}/fix/expr_data/${exprname}/data/obs/atms_npp_obs_2024052700_dc.nc  data/obs/ioda_atms_npp.nc
#
ln -snf ${RDASApp}/fix/expr_data/${exprname}/DataFix DataFix
ln -snf ${RDASApp}/fix/expr_data/${exprname}/Data_static Data_static
cp ${RDASApp}/fix/expr_data/${exprname}/DataFix/fmsmpp.nml .
cp ${RDASApp}/fix/expr_data/${exprname}/DataFix/field_table .
cp ${RDASApp}/fix/expr_data/${exprname}/DataFix/input_lam_C775_NP16X10.nml .
cp ${RDASApp}/fix/expr_data/${exprname}/DataFix/fix/dynamics_lam_cmaq.yaml .
ln -snf ${RDASApp}/fix/expr_data/${exprname}/INPUT INPUT
ln -snf ${RDASApp}/fix/gsi_bec/* ./
ln -snf ${RDASApp}/fix/mgbf/* ./
