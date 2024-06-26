#! /bin/sh
#SBATCH --account=rtrr
#SBATCH --qos=batch
#SBATCH --partition=bigmem
#SBATCH --ntasks=120
#SBATCH -t 00:58:00
#SBATCH --job-name=mpasjedi_bump
#SBATCH -o log.bump
#SBATCH --open-mode=truncate
#SBATCH --cpus-per-task 4 --exclusive
TOPDIR="/scratch1/BMC/wrfruc/gge/RDASApp"

. /apps/lmod/lmod/init/sh
set -+

module purge
source ${TOPDIR}/ush/detect_machine.sh 
module use ${TOPDIR}/modulefiles
module load RDAS/${MACHINE_ID}.intel
module list

export OOPS_TRACE=1
export OMP_NUM_THREADS=1

ulimit -s unlimited
ulimit -v unlimited
ulimit -a

srun -l -n 120 ${TOPDIR}/build/bin/mpasjedi_error_covariance_toolbox.x ./testinput/bumploc.yaml
