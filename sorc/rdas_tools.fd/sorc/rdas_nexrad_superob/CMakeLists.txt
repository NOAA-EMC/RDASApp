#=======================================================================
#$$$ CMAKEFILE DOCUMENTATION BLOCK
# Biju Thomas
# Email: biju.thomas@noaa.gov
#=======================================================================

cmake_minimum_required(VERSION 3.15)
project(rdas_nexrad_superob LANGUAGES C Fortran)

include(GNUInstallDirs)

find_package(NetCDF REQUIRED COMPONENTS C Fortran)
find_package(bufr REQUIRED)

set(fortran_sources
  module_nexrad_common.f90
  module_nexrad_io.f90
  module_nexrad_bufr.f90
  nexrad_so_main.f90
)

add_executable(rdas_nexrad_superob.x ${fortran_sources})

target_link_libraries(rdas_nexrad_superob.x
  PRIVATE
    bufr::bufr_4
    NetCDF::NetCDF_Fortran
    NetCDF::NetCDF_C
)

set_target_properties(rdas_nexrad_superob.x PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)

install(
  TARGETS rdas_nexrad_superob.x
  RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}"
)
