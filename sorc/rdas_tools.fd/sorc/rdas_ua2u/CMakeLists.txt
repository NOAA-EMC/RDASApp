cmake_minimum_required(VERSION 3.15)
project(rdas_ua2u LANGUAGES C Fortran)

# --- Required dependencies ---
find_package(MPI REQUIRED)
find_package(HDF5 REQUIRED COMPONENTS Fortran)
find_package(ZLIB REQUIRED)

# --- NetCDF (manual, since no Config file is provided) ---
if(NOT DEFINED NetCDF_INCLUDE_DIR)
  set(NetCDF_INCLUDE_DIR
      "$ENV{netcdf_fortran_ROOT}/include"
  )
endif()

if(NOT DEFINED NetCDF_LIBRARIES)
  file(GLOB NETCDFF_LIB
    "$ENV{netcdf_fortran_ROOT}/lib/libnetcdff.so*"
  )
  file(GLOB NETCDFC_LIB
    "$ENV{netcdf_c_ROOT}/lib/libnetcdf.so*"
  )
  set(NetCDF_LIBRARIES
      ${NETCDFF_LIB}
      ${NETCDFC_LIB}
  )
endif()

message(STATUS "Using NetCDF include: ${NetCDF_INCLUDE_DIR}")
message(STATUS "Using NetCDF libs: ${NetCDF_LIBRARIES}")

# --- Build executable ---
add_executable(rdas_ua2u.x
  module_structure.f90
  module_mpi.f90
  sub_wind_process.f90
  sub_tools.f90
  sub_grids.f90
  sub_netcdf.f90
  sub_rdas_u_ua.f90
  rdas_ua2u_driver.f90
)

# --- Include paths ---
target_include_directories(rdas_ua2u.x PRIVATE
  ${NetCDF_INCLUDE_DIR}
  ${HDF5_INCLUDE_DIRS}
  ${MPI_Fortran_INCLUDE_DIRS}
)

# --- Link libraries ---
target_link_libraries(rdas_ua2u.x
  ${MPI_Fortran_LIBRARIES}
  ${HDF5_Fortran_LIBRARIES}
  ${ZLIB_LIBRARIES}
  ${NetCDF_LIBRARIES}
)

set_target_properties(rdas_ua2u.x PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
install(TARGETS rdas_ua2u.x
        RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
