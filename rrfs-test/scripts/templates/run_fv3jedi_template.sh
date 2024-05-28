#!/bin/bash
#SBATCH --account=fv3-cam
#SBATCH --qos=debug
#SBATCH --ntasks=80
#SBATCH -t 00:30:00
#SBATCH --job-name=fv3jedi_test
#SBATCH -o jedi.log
#SBATCH --open-mode=truncate
#SBATCH --cpus-per-task 4 --exclusive

. /apps/lmod/lmod/init/sh
set +x

module purge

hostname=`hostname | cut -c 1 | awk '{print tolower($0)}'`
if [[ $hostname == "h" ]]; then
  platform="hera"
elif [[ $hostname == "o" ]]; then
  platform="orion"
fi

module use @YOUR_PATH_TO_RDASAPP@/modulefiles
module load RDAS/${platform}.intel

module list

export OOPS_TRACE=1
export OMP_NUM_THREADS=1

ulimit -s unlimited
ulimit -v unlimited
ulimit -a

module list

inputfile=$1
if [[ $inputfile == "" ]]; then
  inputfile=./testinput/rrfs_fv3jedi_hyb_2022052619.yaml
fi

jedibin="@YOUR_PATH_TO_RDASAPP@/build/bin"
# Run JEDI - currently cannot change processor count
srun -l -n 80 $jedibin/fv3jedi_var.x ./$inputfile out.log

