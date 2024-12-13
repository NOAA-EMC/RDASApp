#!/bin/sh
#SBATCH --account=rtrr
#SBATCH --qos=batch # use the normal queue on Gaea
###SBATCH -M c6 # for Gaea
###SBATCH --partition=kjet
###SBATCH --reservation=rrfsens
#SBATCH --ntasks=160
#SBATCH -t 00:58:00
#SBATCH --job-name=fv3jedi_test
#SBATCH -o log.jedi
#SBATCH --open-mode=truncate
#SBATCH --cpus-per-task 4 --exclusive

RDASApp=@RDASApp@

inputfile=./rrfs_fv3jedi_2024052700_Ens3Dvar.yaml # FOR EnVar
#inputfile=./rrfs_fv3jedi_2024052700_getkf_observer.yaml # FOR GETKF
#inputfile=./rrfs_fv3jedi_2024052700_getkf_solver.yaml # FOR GETKF

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

srun -l -n 160 ${RDASApp}/build/bin/fv3jedi_var.x    ./$inputfile    log.out # FOR HYB/ENVAR
#srun -l -n 160 ${RDASApp}/build/bin/fv3jedi_letkf.x    ./$inputfile    log.out # FOR GETKF
