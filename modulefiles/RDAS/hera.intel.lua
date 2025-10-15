help([[
Load environment for running the RDAS application with Intel compilers and MPI.
]])

local pkgName    = myModuleName()
local pkgVersion = myModuleVersion()
local pkgNameVer = myModuleFullName()

prepend_path("MODULEPATH", '/contrib/spack-stack/spack-stack-1.9.3/envs/ue-oneapi-2024.2.1/install/modulefiles/Core')

-- below two lines get us access to the spack-stack modules
load("stack-oneapi/2024.2.1")
load("stack-python/3.11.7")
load("stack-intel-oneapi-mpi/2021.13")
load("jedi-mpas-env/1.0.0")
load("jedi-fv3-env/1.0.0")
load("py-jinja2/3.1.4")

setenv("CC","mpiicc")
setenv("FC","mpiifort")
setenv("CXX","mpiicpc")

local mpiexec = '/apps/slurm_hera/default/bin/srun'
local mpinproc = '-n'
setenv('MPIEXEC_EXEC', mpiexec)
setenv('MPIEXEC_NPROC', mpinproc)

whatis("Name: ".. pkgName)
whatis("Version: ".. pkgVersion)
whatis("Category: RDASApp")
whatis("Description: Load all libraries needed for RDASApp")
