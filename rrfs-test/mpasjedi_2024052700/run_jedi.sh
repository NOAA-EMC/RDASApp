#! /bin/sh
#SBATCH --account=rtrr
#SBATCH --qos=batch
###SBATCH --partition=kjet
###SBATCH --reservation=rrfsens
#SBATCH --ntasks=120
#SBATCH -t 00:58:00
#SBATCH --job-name=mpasjedi_test
#SBATCH -o log.jedi
#SBATCH --open-mode=truncate
#SBATCH --cpus-per-task 4 --exclusive
#
#=======RDASApp block=================
RDASApp=$( git rev-parse --show-toplevel 2>/dev/null )
if [[ -z ${RDASApp} ]]; then
  echo "Not under a clone of RDASApp!"
  echo "delete lines inside the 'RDASApp block' and set the RDASApp variable mannually"
  exit
fi
#=======RDASApp block=================

inputfile=./testinput/sonde_singeob_airTemperature_mpasjedi.yaml

. /apps/lmod/lmod/init/sh

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

srun -l -n 120 ${RDASApp}/build/bin/mpasjedi_variational.x    ./$inputfile    log.out
