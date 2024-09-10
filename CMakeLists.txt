# ------------------------------------------------------------------------- #
# Application for all the components needed for the RDAS system             #
# ------------------------------------------------------------------------- #

# Check for minimim cmake requirement
cmake_minimum_required( VERSION 3.20 FATAL_ERROR )

find_package(ecbuild 3.5 REQUIRED HINTS ${CMAKE_CURRENT_SOURCE_DIR} ${CMAKE_CURRENT_SOURCE_DIR}/../ecbuild)

project(RDASApp VERSION 1.0.0 LANGUAGES C CXX Fortran )

include(GNUInstallDirs)
enable_testing()
#clt for rrfs test
set(MPIEXEC_MAX_NUMPROCS 120 CACHE STRING "Maximum number of processors")

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
option(ADD_RRFS_TESTS "Add RRFS tests" OFF)
option(MPAS_DYCORE "Use MPAS" OFF)
option(FV3_DYCORE "Use FV3" ON)

# Install utility scripts.
#add_subdirectory(ush)

# Include testing.
add_subdirectory(test)

# Finalize bundle
# ---------------
ecbuild_bundle_finalize()
