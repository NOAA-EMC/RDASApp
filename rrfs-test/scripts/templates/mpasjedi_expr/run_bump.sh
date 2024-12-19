#!/bin/sh
#SBATCH --account=rtrr
#SBATCH --qos=batch # use the normal queue on Gaea
###SBATCH -M c6 # for Gaea
###SBATCH --partition=bigmem
###SBATCH --partition=kjet
###SBATCH --reservation=rrfsens
#SBATCH --ntasks=160
#SBATCH -t 00:58:00
#SBATCH --job-name=mpasjedi_bump
#SBATCH -o log.bump
#SBATCH --open-mode=truncate
#SBATCH --cpus-per-task 4 --exclusive

RDASApp=@RDASApp@

if [[ -s /apps/lmod/lmod/init/sh ]]; then
  . /apps/lmod/lmod/init/sh
fi

module purge
source ${RDASApp}/ush/detect_machine.sh 
module use ${RDASApp}/modulefiles
module load RDAS/${MACHINE_ID}.intel
module list

export OOPS_TRACE=1
export OMP_NUM_THREADS=1

ulimit -s unlimited
ulimit -v unlimited
ulimit -a

srun -l -n 160 ${RDASApp}/build/bin/mpasjedi_error_covariance_toolbox.x ./bumploc.yaml
