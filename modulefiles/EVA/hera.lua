help([[
Load environment for running EVA.
]])

local pkgName    = myModuleName()
local pkgVersion = myModuleVersion()
local pkgNameVer = myModuleFullName()

conflict(pkgName)

prepend_path("MODULEPATH", '/contrib/spack-stack/spack-stack-1.6.0/envs/unified-env-rocky8/install/modulefiles/Core')

load("stack-intel/2021.5.0")
load("stack-intel-oneapi-mpi/2021.5.1")
load("stack-python/3.10.13")
load("py-jinja2/3.0.3")
load("py-netcdf4/1.5.8")
load("py-pybind11/2.11.0")
load("py-pycodestyle/2.11.0")
load("py-pyyaml/6.0")
load("py-scipy/1.11.3")
load("py-xarray/2023.7.0")
load("py-matplotlib/3.7.3")
load("py-cartopy/0.21.1")

-- And load additional modules (e.g., seaborn) from our new RDASAppPy env
local venv_path = "/scratch3/NCEPDEV/fv3-cam/RDASAppPy"
setenv("VIRTUAL_ENV", venv_path)
prepend_path("PATH", pathJoin(venv_path, "bin"))
prepend_path("PYTHONPATH", pathJoin(venv_path, "lib/python3.10/site-packages"))

whatis("Name: ".. pkgName)
whatis("Version: ".. pkgVersion)
whatis("Category: EVA")
whatis("Description: Load all libraries needed for EVA")
