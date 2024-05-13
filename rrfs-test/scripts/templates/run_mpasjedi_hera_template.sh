#! /bin/sh
#SBATCH --account=fv3-cam
#SBATCH --qos=debug
#SBATCH --ntasks=36
#SBATCH -t 00:30:00
#SBATCH --job-name=mpasjedi_test
#SBATCH -o jedi.log
#SBATCH --open-mode=truncate
#SBATCH --cpus-per-task 4 --exclusive

. /apps/lmod/lmod/init/sh
set +x

module purge

module use @YOUR_PATH_TO_RDASAPP@/modulefiles
module load RDAS/hera.intel

module list

export OOPS_TRACE=1
export OMP_NUM_THREADS=1

ulimit -s unlimited
ulimit -v unlimited
ulimit -a

inputfile=$1
if [[ $inputfile == "" ]]; then
  inputfile=./testinput/@YAML@
fi

jedibin="@YOUR_PATH_TO_RDASAPP@/build/bin"
# Run JEDI - currently cannot change processor count
srun -l -n 36 $jedibin/@EXECUTABLE@ ./$inputfile out.log

