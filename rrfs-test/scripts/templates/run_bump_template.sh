#! /bin/sh
#SBATCH --account=@SLURM_ACCOUNT@
#SBATCH --qos=batch
###SBATCH --partition=bigmem
###SBATCH --partition=kjet
###SBATCH --reservation=rrfsens
#SBATCH --ntasks=120
#SBATCH -t 00:58:00
#SBATCH --job-name=mpasjedi_bump
#SBATCH -o log.bump
#SBATCH --open-mode=truncate
#SBATCH --cpus-per-task 4 --exclusive

. /apps/lmod/lmod/init/sh

module purge

module use @YOUR_PATH_TO_RDASAPP@/modulefiles
module load RDAS/@MACHINE_ID@.intel

module list

export OOPS_TRACE=1
export OMP_NUM_THREADS=1

ulimit -s unlimited
ulimit -v unlimited
ulimit -a

jedibin="@YOUR_PATH_TO_RDASAPP@/build/bin"
srun -l -n 120 ${jedibin}/mpasjedi_error_covariance_toolbox.x ./testinput/bumploc.yaml
