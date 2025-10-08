help([[
Load environment for running the RDAS application with Intel compilers and MPI.
]])

local pkgName    = myModuleName()
local pkgVersion = myModuleVersion()
local pkgNameVer = myModuleFullName()

prepend_path("MODULEPATH", '/contrib/spack-stack/spack-stack-1.9.2/envs/ue-gcc-12.4.0/install/modulefiles/Core')

load("stack-gcc/12.4.0")
load("stack-python/3.11.7")
load("stack-openmpi/4.1.6")
load("jedi-mpas-env/1.0.0")
load("jedi-fv3-env/1.0.0")
load("py-jinja2/3.1.4")
unload("gsibec/1.2.1")

setenv("CC","mpicc")
setenv("FC","mpif90")
setenv("CXX","mpicxx")

local mpiexec = '/apps/slurm/default/bin/srun'
local mpinproc = '-n'
setenv('MPIEXEC_EXEC', mpiexec)
setenv('MPIEXEC_NPROC', mpinproc)

whatis("Name: ".. pkgName)
whatis("Version: ".. pkgVersion)
whatis("Category: RDASApp")
whatis("Description: Load all libraries needed for RDASApp")
