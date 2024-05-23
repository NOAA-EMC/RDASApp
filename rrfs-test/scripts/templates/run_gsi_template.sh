#!/bin/bash
#SBATCH --account=@SLURM_ACCOUNT@
#SBATCH --qos=debug
#SBATCH --ntasks=360
#SBATCH -t 00:30:00
#SBATCH --job-name=gsi_test
#SBATCH -o gsi.out
#SBATCH --open-mode=truncate
#SBATCH --cpus-per-task 2 --exclusive

. /apps/lmod/lmod/init/sh
set +x

module purge

hostname=`hostname | cut -c 1 | awk '{print tolower($0)}'`
if [[ $hostname == "h" ]]; then
  platform="hera"
elif [[ $hostname == "o" ]]; then
  platform="orion"
fi

module use @YOUR_PATH_TO_GSI@/modulefiles
module load gsi_${platform}.intel

module list

export OMP_NUM_THREADS=1

ulimit -s unlimited
ulimit -v unlimited
ulimit -a

module list

cp -p Data/bkg/* .

srun --label @YOUR_PATH_TO_GSI@/build/src/gsi/gsi.x

ANAL_TIME=2022052619
# Loop over first and last outer loops to generate innovation
# diagnostic files for indicated observation types (groups)
#
# NOTE: Since we set miter=2 in GSI namelist SETUP, outer
# loop 03 will contain innovations with respect to
# the analysis. Creation of o-a innovation files
# is triggered by write_diag(3)=.true. The setting
# write_diag(1)=.true. turns on creation of o-g
# innovation files.
#
loops="01 03"
for loop in $loops; do
  case $loop in
    01) string=ges;;
    03) string=anl;;
    *) string=$loop;;
  esac
  # Collect diagnostic files for obs types (groups) below
  # listall="conv amsua_metop-a mhs_metop-a hirs4_metop-a hirs2_n14 msu_n14 \
  # sndr_g08 sndr_g10 sndr_g12 sndr_g08_prep sndr_g10_prep sndr_g12_prep \
  # sndrd1_g08 sndrd2_g08 sndrd3_g08 sndrd4_g08 sndrd1_g10 sndrd2_g10 \
  # sndrd3_g10 sndrd4_g10 sndrd1_g12 sndrd2_g12 sndrd3_g12 sndrd4_g12 \
  # hirs3_n15 hirs3_n16 hirs3_n17 amsua_n15 amsua_n16 amsua_n17 \
  # amsub_n15 amsub_n16 amsub_n17 hsb_aqua airs_aqua amsua_aqua \
  # goes_img_g08 goes_img_g10 goes_img_g11 goes_img_g12 \
  # pcp_ssmi_dmsp pcp_tmi_trmm sbuv2_n16 sbuv2_n17 sbuv2_n18 \
  # omi_aura ssmi_f13 ssmi_f14 ssmi_f15 hirs4_n18 amsua_n18 mhs_n18 \
  # amsre_low_aqua amsre_mid_aqua amsre_hig_aqua ssmis_las_f16 \
  # ssmis_uas_f16 ssmis_img_f16 ssmis_env_f16 mhs_metop_b \
  # hirs4_metop_b hirs4_n19 amusa_n19 mhs_n19"
  listall=`ls pe* | cut -f2 -d"." | awk '{print substr($0, 0, length($0)-3)}' | sort | uniq`
  for type in $listall; do
    count=`ls pe*${type}_${loop}* | wc -l`
    if [[ $count -gt 0 ]]; then
      #cat pe*${type}_${loop}*.nc4 > diag_${type}_${string}.${ANAL_TIME}
      nc_diag_cat_serial.x -o diag_${type}_${string}.${ANAL_TIME} pe*${type}_${loop}*.nc4
    fi
  done
done
