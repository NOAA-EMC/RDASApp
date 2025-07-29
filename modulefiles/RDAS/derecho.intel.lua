help([[
Load environment for running the RDAS application with Intel compilers and MPI.
]])

local pkgName    = myModuleName()
local pkgVersion = myModuleVersion()
local pkgNameVer = myModuleFullName()

prepend_path("MODULEPATH", '/glade/work/epicufsrt/contrib/spack-stack/derecho/modulefiles')
prepend_path("MODULEPATH", '/glade/work/epicufsrt/contrib/spack-stack/derecho/spack-stack-1.8.0/envs/ue-intel-2021.10.0/install/modulefiles/Core')

load("ncarenv/23.09")
load("stack-intel/2021.10.0")
load("stack-python/3.11.7")
load("stack-cray-mpich/8.1.25")
load("jedi-mpas-env/1.0.0")
load("jedi-fv3-env/1.0.0")

--setenv("CC","mpiicc")
--setenv("FC","mpiifort")
--setenv("CXX","mpiicpc")

local mpiexec = '/opt/cray/pe/pals/1.2.11/bin/aprun'
local mpinproc = '-n'
setenv('MPIEXEC_EXEC', mpiexec)
setenv('MPIEXEC_NPROC', mpinproc)

whatis("Name: ".. pkgName)
whatis("Version: ".. pkgVersion)
whatis("Category: RDASApp")
whatis("Description: Load all libraries needed for RDASApp")
