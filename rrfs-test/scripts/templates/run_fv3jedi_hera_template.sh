#! /bin/sh
#SBATCH --account=fv3-cam
#SBATCH --qos=debug
#SBATCH --ntasks=80
#SBATCH -t 00:30:00
#SBATCH --job-name=fv3jedi_test
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

export OOPS_TRACE=1
export OMP_NUM_THREADS=1

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

