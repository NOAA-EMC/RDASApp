#!/bin/bash
#SBATCH --account=@SLURM_ACCOUNT@
#SBATCH --qos=debug
#SBATCH --ntasks=360
#SBATCH -t 00:30:00
#SBATCH --job-name=gsi_test
#SBATCH -o gsi.out
#SBATCH --open-mode=truncate
#SBATCH --cpus-per-task 4 --exclusive

. /apps/lmod/lmod/init/sh
set +x

module purge

module use @YOUR_PATH_TO_GSI@/modulefiles
module load gsi_@MACHINE_ID@.intel

module list

export OMP_NUM_THREADS=1

ulimit -s unlimited
ulimit -v unlimited
ulimit -a

module list

cp -p Data/bkg/* .

srun --label @YOUR_PATH_TO_GSI@/build/src/gsi/gsi.x

ANAL_TIME=@ANAL_TIME@
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
  listall=`ls pe* | cut -f2 -d"." | awk '{print substr($0, 0, length($0)-3)}' | sort | uniq`
  for type in $listall; do
    count=`ls pe*${type}_${loop}* | wc -l`
    if [[ $count -gt 0 ]]; then
      if [[ $count -eq 1 ]]; then
        # just one file, no cat needed (just copy it)
        file=`ls -1 pe*${type}_${loop}*`
        cp -f $file ./diag_${type}_${string}.${ANAL_TIME}
      else
        ncdiag_cat_serial.x -o diag_${type}_${string}.${ANAL_TIME} pe*${type}_${loop}*.nc4
      fi
    fi
  done
done
