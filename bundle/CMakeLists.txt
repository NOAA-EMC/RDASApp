# ------------------------------------------------------------------------- #
# JEDI RDAS Bundle             #
# ------------------------------------------------------------------------- #

# Check for minimim cmake requirement
cmake_minimum_required( VERSION 3.20 FATAL_ERROR )

find_package(ecbuild 3.5 REQUIRED HINTS ${CMAKE_CURRENT_SOURCE_DIR} ${CMAKE_CURRENT_SOURCE_DIR}/../ecbuild)

project(RDAS-bundle VERSION 1.0.0 LANGUAGES C CXX Fortran )

include(GNUInstallDirs)
enable_testing()

# Build type.
if(NOT CMAKE_BUILD_TYPE MATCHES "^(Debug|Release|RelWithDebInfo|MinSizeRel)$")
  message(STATUS "Setting build type to 'Release' as none was specified.")
  set(CMAKE_BUILD_TYPE
      "Release"
      CACHE STRING "Choose the type of build." FORCE)
  set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS "Debug" "Release"
                                               "MinSizeRel" "RelWithDebInfo")
endif()

# Find dependencies.
find_package(Python3 REQUIRED COMPONENTS Interpreter)

# Include ecbuild_bundle macro
include( ecbuild_bundle )

# Enable MPI
set( ENABLE_MPI ON CACHE BOOL "Compile with MPI" )

# Handle user options.
option(BUILD_RDASBUNDLE "Build RDAS Bundle" ON)

# Initialize bundle
# -----------------
ecbuild_bundle_initialize()

# Build bundle source code.
if(BUILD_RDASBUNDLE)

# jedi-cmake
  ecbuild_bundle( PROJECT jedicmake SOURCE "../sorc/jedicmake" )
  include( jedicmake/cmake/Functions/git_functions.cmake )

# ECMWF libraries
  option("BUNDLE_SKIP_ECKIT" "Don't build eckit" "ON" ) # Skip eckit build unless user passes -DBUNDLE_SKIP_ECKIT=OFF
  option("BUNDLE_SKIP_FCKIT" "Don't build fckit" "ON") # Skip fckit build unless user passes -DBUNDLE_SKIP_FCKIT=OFF
  option("BUNDLE_SKIP_ATLAS" "Don't build atlas" "ON") # Skip atlas build unless user passes -DBUNDLE_SKIP_ATLAS=OFF

# turn off optional OOPS toy models
  option( ENABLE_LORENZ95_MODEL "Build LORENZ95 toy model" OFF )
  option( ENABLE_QG_MODEL "Build QG toy model" OFF )

  ecbuild_bundle( PROJECT eckit GIT "https://github.com/ecmwf/eckit.git" TAG 1.16.0 )
  ecbuild_bundle( PROJECT fckit GIT "https://github.com/ecmwf/fckit.git" TAG 0.9.2 )
  ecbuild_bundle( PROJECT atlas GIT "https://github.com/ecmwf/atlas.git" TAG 0.35.0 )

# External (required) observation operators
  # TODO remove the CRTM from here and use it as a library
  #option("BUNDLE_SKIP_CRTM" "Don't build CRTM" "OFF") # Don't build crtm unless user passes -DBUNDLE_SKIP_CRTM=OFF
  #ecbuild_bundle( PROJECT crtm GIT "https://github.com/JCSDA/crtm.git"   TAG v2.4.1-jedi.1 )
  ecbuild_bundle( PROJECT crtm SOURCE "../sorc/crtm" )

# Build GSI-B
#   option(BUILD_GSIBEC "Build GSI-B" OFF)
#   if(BUILD_GSIBEC)
#     ecbuild_bundle( PROJECT gsibec SOURCE "../sorc/gsibec" )
#   endif()

# Core JEDI repositories
  ecbuild_bundle( PROJECT oops SOURCE "../sorc/oops" )
  ecbuild_bundle( PROJECT vader SOURCE "../sorc/vader" )
  ecbuild_bundle( PROJECT saber SOURCE "../sorc/saber" )
  option(ENABLE_IODA_DATA "Obtain ioda test data from ioda-data repository (vs tarball)" ON)
  ecbuild_bundle( PROJECT ioda SOURCE "../sorc/ioda" )
  option(ENABLE_UFO_DATA "Obtain ufo test data from ufo-data repository (vs tarball)" ON)
  ecbuild_bundle( PROJECT ufo SOURCE "../sorc/ufo" )

  if(FV3_DYCORE)
    # FMS and FV3 dynamical core
    include(../sorc/fv3-interface.cmake)
    ecbuild_bundle( PROJECT fv3 SOURCE "../sorc/fv3" )

    # fv3-jedi and associated repositories
    ecbuild_bundle( PROJECT femps SOURCE "../sorc/femps" )
    ecbuild_bundle( PROJECT fv3-jedi-lm SOURCE "../sorc/fv3-jedi-lm" )
    option(ENABLE_FV3_JEDI_DATA "Obtain fv3-jedi test data from fv3-jedi-data repository (vs tarball)" ON)
    ecbuild_bundle( PROJECT fv3-jedi SOURCE "../sorc/fv3-jedi" )
endif()

if(MPAS_DYCORE)
  set(MPAS_DOUBLE_PRECISION "ON" CACHE STRING "MPAS-Model: Use double precision 64-bit Floating point.")
  set(MPAS_CORES init_atmosphere atmosphere CACHE STRING "MPAS-Model: cores to build.")
  ecbuild_bundle( PROJECT MPAS SOURCE "../sorc/mpas" )
  option(ENABLE_MPAS_JEDI_DATA "Obtain mpas-jedi test data from mpas-jedi-data repository (vs tarball)" ON)
  ecbuild_bundle( PROJECT mpas-jedi SOURCE "../sorc/mpas-jedi" )
endif()

# Build IODA converters
  option(BUILD_IODA_CONVERTERS "Build IODA Converters" ON)
  if(BUILD_IODA_CONVERTERS)
    ecbuild_bundle( PROJECT iodaconv SOURCE "../sorc/iodaconv" )
  endif()

# EMC BUFR-query library
  ecbuild_bundle( PROJECT bufr-query SOURCE "../sorc/bufr-query" )

# rdas tests and super executables
  ecbuild_bundle( PROJECT rrfs-test SOURCE "../rrfs-test" )
  if(BUILD_SUPER_EXE)
    ecbuild_bundle( PROJECT rdas SOURCE "../mains" )
  endif()

endif(BUILD_RDASBUNDLE)

# Finalize bundle
# ---------------
ecbuild_bundle_finalize()
