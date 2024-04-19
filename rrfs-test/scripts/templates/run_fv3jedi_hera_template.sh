#! /bin/sh
#SBATCH --account=fv3-cam
#SBATCH --qos=debug
#SBATCH --ntasks=80
#SBATCH -t 00:30:00
#SBATCH --job-name=jedi_test
#SBATCH -o jedi.log
#SBATCH --open-mode=truncate
#SBATCH --cpus-per-task 2 --exclusive

. /apps/lmod/lmod/init/sh
set +x

module purge

#https://spack-stack.readthedocs.io/en/1.5.0/PreConfiguredSites.html#noaa-rdhpcs-hera
#https://spack-stack.readthedocs.io/en/1.6.0/PreConfiguredSites.html#noaa-rdhpcs-hera
module use /scratch1/NCEPDEV/jcsda/jedipara/spack-stack/modulefiles
module load miniconda/3.9.12
module load ecflow/5.5.3
module load mysql/8.0.31
module use /scratch1/NCEPDEV/nems/role.epic/spack-stack/spack-stack-1.6.0/envs/unified-env-rocky8/install/modulefiles/Core
module load stack-intel/2021.5.0
module load stack-intel-oneapi-mpi/2021.5.1
module load stack-python/3.10.13
module use @YOUR_PATH_TO_RDASAPP@/modulefiles
module load RDAS/hera
#https://jointcenterforsatellitedataassimilation-jedi-docs.readthedocs-hosted.com/en/latest/using/jedi_environment/modules.html
module load jedi-fv3-env
module load ewok-env
module load soca-env

module list

export SLURM_ACCOUNT=@SLURM_ACCOUNT@
export SALLOC_ACCOUNT=$SLURM_ACCOUNT
export SBATCH_ACCOUNT=$SLURM_ACCOUNT
export SLURM_QOS debug
export FV3JEDI_TEST_TIER=2
export MAIN_DEBUG=1
export OOPS_DEBUG=1
export OOPS_TRACE=1
export IODA_PRINT_RUNSTATS=1
#export CMAKE_OPTS+= "${CMAKE_OPTS:+$CMAKE_OPTS:}  -DMPIEXEC_EXECUTABLE=$MPIEXEC_EXEC -DMPIEXEC_NUMPROC_FLAG=$MPIEXEC_NPROC"
export OMP_NUM_THREADS=1
export I_MPI_DEBUG=10

ulimit -s unlimited
ulimit -v unlimited
ulimit -a

inputfile=./$1
if [[ $inputfile == "" ]]; then
  inputfile=rrfs_fv3jedi_hyb_2022052619.yaml
fi

jedibin="@YOUR_PATH_TO_RDASAPP@/build/bin"
# Run JEDI - currently cannot change processor count
srun -l -n 80 $jedibin/fv3jedi_var.x $inputfile out.log

