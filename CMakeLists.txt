# ------------------------------------------------------------------------- #
# Application for all the components needed for the RDAS system             #
# ------------------------------------------------------------------------- #

# Check for minimim cmake requirement
cmake_minimum_required( VERSION 3.20 FATAL_ERROR )

find_package(ecbuild 3.5 REQUIRED HINTS ${CMAKE_CURRENT_SOURCE_DIR} ${CMAKE_CURRENT_SOURCE_DIR}/../ecbuild)

project(RDASApp VERSION 1.0.0 LANGUAGES C CXX Fortran )

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
option(CLONE_JCSDADATA "Clone JCSDA test data repositories" OFF)
option(WORKFLOW_TESTS "Include regional-workflow dependent tests" OFF)
option(MPAS_DYCORE "Use MPAS" OFF)
option(FV3_DYCORE "Use FV3" ON)

# Initialize bundle
# -----------------
ecbuild_bundle_initialize()

# Build bundle source code.
if(BUILD_RDASBUNDLE)

# jedi-cmake
  ecbuild_bundle( PROJECT jedicmake GIT "https://github.com/jcsda/jedi-cmake.git" TAG 1.4.0 RECURSIVE )
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
  ecbuild_bundle( PROJECT atlas GIT "https://github.com/ecmwf/atlas.git" TAG 0.29.0 )

# External (required) observation operators
  option("BUNDLE_SKIP_CRTM" "Don't build CRTM" "OFF") # Don't build crtm unless user passes -DBUNDLE_SKIP_CRTM=OFF
  ecbuild_bundle( PROJECT crtm GIT "https://github.com/JCSDA/crtm.git"   TAG v2.4.1-jedi.1 )

# Build GSI-B
  option(BUILD_GSIBEC "Build GSI-B" OFF)
  if(BUILD_GSIBEC)
    ecbuild_bundle( PROJECT gsibec GIT "https://github.com/GEOS-ESM/GSIbec.git" TAG 1.1.2 )
  endif()

# Core JEDI repositories
  ecbuild_bundle( PROJECT oops  GIT "https://github.com/jcsda/oops.git"  BRANCH develop)
  ecbuild_bundle( PROJECT vader GIT "https://github.com/jcsda/vader.git" BRANCH develop )
  ecbuild_bundle( PROJECT saber GIT "https://github.com/jcsda/saber.git" BRANCH develop )
  option(ENABLE_IODA_DATA "Obtain ioda test data from ioda-data repository (vs tarball)" ON)
  ecbuild_bundle( PROJECT ioda  GIT "https://github.com/jcsda/ioda.git" BRANCH develop  )
  option(ENABLE_UFO_DATA "Obtain ufo test data from ufo-data repository (vs tarball)" ON)
  ecbuild_bundle( PROJECT ufo   GIT "https://github.com/jcsda/ufo.git" BRANCH develop )

  if(FV3_DYCORE)
# FMS and FV3 dynamical core
    ecbuild_bundle( PROJECT fms GIT "https://github.com/jcsda/FMS.git" BRANCH release-stable )
    ecbuild_bundle( PROJECT fv3 GIT "https://github.com/jcsda/GFDL_atmos_cubed_sphere.git" BRANCH release-stable )

# fv3-jedi and associated repositories
    ecbuild_bundle( PROJECT femps       GIT "https://github.com/jcsda/femps.git"                BRANCH develop )
    ecbuild_bundle( PROJECT fv3-jedi-lm GIT "https://github.com/jcsda/fv3-jedi-linearmodel.git" BRANCH develop )
    option(ENABLE_FV3_JEDI_DATA "Obtain fv3-jedi test data from fv3-jedi-data repository (vs tarball)" ON)
    ecbuild_bundle( PROJECT fv3-jedi    GIT "https://github.com/jcsda/fv3-jedi.git"             BRANCH develop )
  endif()

  if(MPAS_DYCORE)
    set(MPAS_DOUBLE_PRECISION "ON" CACHE STRING "MPAS-Model: Use double precision 64-bit Floating point.")
    set(MPAS_CORES init_atmosphere atmosphere CACHE STRING "MPAS-Model: cores to build.")
    ecbuild_bundle( PROJECT MPAS GIT "https://github.com/JCSDA-internal/MPAS-Model.git" BRANCH release-stable UPDATE )
    option(ENABLE_MPAS_JEDI_DATA "Obtain mpas-jedi test data from mpas-jedi-data repository (vs tarball)" ON)
    ecbuild_bundle( PROJECT mpas-jedi GIT "https://github.com/JCSDA/mpas-jedi" BRANCH develop UPDATE )
  endif()

# Build IODA converters
  option(BUILD_IODA_CONVERTERS "Build IODA Converters" ON)
  if(BUILD_IODA_CONVERTERS)
    ecbuild_bundle( PROJECT iodaconv GIT "https://github.com/JCSDA-internal/ioda-converters.git" BRANCH develop )
  endif()

# ioda, ufo, fv3-jedi, and saber test data
#---------------------------------
if(CLONE_JCSDADATA)

  # If IODA branch is being built set GIT_BRANCH_FUNC to IODA's current branch.
  # If a tagged version of IODA is being built set GIT_TAG_FUNC to ioda's current tag. In this case,
  # IODA test files will be download from UCAR DASH and ioda-data repo will not be cloned.
  # When LOCAL_PATH_JEDI_TESTFILES is set to the directory of IODA test files stored
  # in a local directory, ioda-data repo will not be cloned

    find_branch_name(REPO_DIR_NAME ioda)
  # When LOCAL_PATH_JEDI_TESTFILES is set to the directory of IODA test files stored
  # in a local directory, ioda-data repo will not be cloned
    if( NOT DEFINED ENV{LOCAL_PATH_JEDI_TESTFILES} AND NOT DEFINED GIT_TAG_FUNC )
      ecbuild_bundle( PROJECT ioda-data GIT "https://github.com/JCSDA-internal/ioda-data.git" BRANCH develop )

      # If IODA's current branch is available in ioda-data repo, that branch will be checked out
      branch_checkout (REPO_DIR_NAME ioda-data
                      BRANCH ${GIT_BRANCH_FUNC} )
    endif()

  # same procedure for ufo-data
    find_branch_name(REPO_DIR_NAME ufo)
    if( NOT DEFINED ENV{LOCAL_PATH_JEDI_TESTFILES} AND NOT DEFINED GIT_TAG_FUNC )
      ecbuild_bundle( PROJECT ufo-data GIT "https://github.com/JCSDA-internal/ufo-data.git" BRANCH develop )

      # If UFO's current branch is available in ioda-data repo, that branch will be checked out
      branch_checkout (REPO_DIR_NAME ufo-data
                      BRANCH ${GIT_BRANCH_FUNC} )
    endif()

    # same procedure for fv3-jedi-data
    if(FV3_DYCORE)
      find_branch_name(REPO_DIR_NAME fv3-jedi)
      if( NOT DEFINED ENV{LOCAL_PATH_JEDI_TESTFILES} AND NOT DEFINED GIT_TAG_FUNC )
        ecbuild_bundle( PROJECT fv3-jedi-data GIT "https://github.com/JCSDA-internal/fv3-jedi-data.git" BRANCH develop )

        # If fv3-jedi's current branch is available in ioda-data repo, that branch will be checked out
        branch_checkout (REPO_DIR_NAME fv3-jedi-data
                        BRANCH ${GIT_BRANCH_FUNC} )
      endif()
    endif()

    if(MPAS_DYCORE)
      ecbuild_bundle( PROJECT mpas-jedi-data  GIT "https://github.com/jcsda-internal/mpas-jedi-data.git"  BRANCH develop UPDATE )
    endif()

  endif(CLONE_JCSDADATA)

endif(BUILD_RDASBUNDLE)

# Install utility scripts.
#add_subdirectory(ush)

# Include testing.
add_subdirectory(test)

# Finalize bundle
# ---------------
ecbuild_bundle_finalize()
