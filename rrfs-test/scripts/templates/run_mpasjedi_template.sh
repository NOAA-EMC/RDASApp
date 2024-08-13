#!/bin/bash
#SBATCH --account=@SLURM_ACCOUNT@
#SBATCH --qos=batch
###SBATCH --partition=kjet
###SBATCH --reservation=rrfsens
#SBATCH --ntasks=120
#SBATCH -t 00:58:00
#SBATCH --job-name=mpasjedi_test
#SBATCH -o jedi.log
#SBATCH --open-mode=truncate
#SBATCH --cpus-per-task 4 --exclusive
#

. /apps/lmod/lmod/init/sh
set +x

module purge

module use @YOUR_PATH_TO_RDASAPP@/modulefiles
module load RDAS/@MACHINE_ID@.intel

module list

export OOPS_TRACE=1
export OMP_NUM_THREADS=1

ulimit -s unlimited
ulimit -v unlimited
ulimit -a

module list

inputfile=$1
if [[ $inputfile == "" ]]; then
  inputfile=./rrfs_mpasjedi_2024052700_Ens3Dvar_sonde_singleob.yaml
fi

jedibin="@YOUR_PATH_TO_RDASAPP@/build/bin"
# Run JEDI - currently cannot change processor count
srun -l -n 120 $jedibin/mpasjedi_variational.x ./$inputfile out.log

