help([[
Load environment for running the RDAS application with GNU compilers and MPI.
]])

local pkgName    = myModuleName()
local pkgVersion = myModuleVersion()
local pkgNameVer = myModuleFullName()

--prepend_path("MODULEPATH", '/glade/work/epicufsrt/contrib/spack-stack/derecho/modulefiles')
prepend_path("MODULEPATH", '/glade/work/epicufsrt/contrib/spack-stack/derecho/spack-stack-1.9.3/envs/rebuild-ue-gcc-12.4.0/install/modulefiles/Core')

--load("ncarenv/23.09")
load("stack-gcc/12.4.0")
load("stack-python/3.11.7")
load("stack-cray-mpich/8.1.29")
load("jedi-mpas-env/1.0.0")
load("jedi-fv3-env/1.0.0")

--setenv("CC","mpicc")
--setenv("FC","mpif90")
--setenv("CXX","mpicxx")

setenv('MPIEXEC_EXEC', '/opt/cray/pe/pals/1.2.11/bin/aprun')
setenv('MPIEXEC_NPROC', '-n')

whatis("Name: ".. pkgName)
whatis("Version: ".. pkgVersion)
whatis("Category: RDASApp")
whatis("Description: Load all libraries needed for RDASApp")
