help([[
Load environment for running EVA.
]])

local pkgName    = myModuleName()
local pkgVersion = myModuleVersion()
local pkgNameVer = myModuleFullName()

conflict(pkgName)

prepend_path("MODULEPATH", '/lfs5/BMC/wrfruc/gge/miniconda3/modulefiles')

load("miniconda3/4.6.14")
load("eva/1.0.0")

whatis("Name: ".. pkgName)
whatis("Version: ".. pkgVersion)
whatis("Category: EVA")
whatis("Description: Load all libraries needed for EVA")
