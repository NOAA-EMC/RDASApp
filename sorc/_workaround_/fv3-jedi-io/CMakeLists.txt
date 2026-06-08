# (C) Copyright 2017-2022 UCAR.
#
# This software is licensed under the terms of the Apache Licence Version 2.0
# which can be obtained at http://www.apache.org/licenses/LICENSE-2.0.

include_directories( ${CMAKE_CURRENT_SOURCE_DIR} ${DEPEND_LIB_ROOT}/include_r8 )
list( APPEND fv3jedi_src_files
  ErrorCovariance/ErrorCovariance.cc
  ErrorCovariance/ErrorCovariance.h
  FieldMetadata/FieldsMetadata.cc
  FieldMetadata/FieldsMetadataDefault.h
  FieldMetadata/FieldsMetadata.h
  FieldMetadata/FieldsMetadata.interface.cc
  FieldMetadata/FieldsMetadata.interface.h
  FieldMetadata/fields_metadata_mod.f90
  Fields/fv3jedi_field_mod.f90
  Fields/fv3jedi_fields_mod.f90
  Geometry/Geometry.cc
  Geometry/Geometry.h
  Geometry/Geometry.interface.h
  Geometry/fv3jedi_geom_interface_mod.F90
  Geometry/fv3jedi_geom_mod.f90
  Geometry/fv3jedi_time_invariant_fields_helpers_interface_mod.F90
  Geometry/fv3jedi_time_invariant_fields_helpers_mod.f90
  Geometry/TimeInvariantFieldsHelpers.cc
  Geometry/TimeInvariantFieldsHelpers.h
  GeometryIterator/GeometryIterator.cc
  GeometryIterator/GeometryIterator.h
  GeometryIterator/GeometryIterator.interface.h
  GeometryIterator/fv3jedi_geom_iter_interface.F90
  GeometryIterator/fv3jedi_geom_iter_mod.F90
  Increment/Increment.cc
  Increment/Increment.h
  Increment/Increment.interface.h
  Increment/fv3jedi_increment_interface_mod.F90
  Increment/fv3jedi_increment_mod.F90
  IO/FV3Restart/module_fv3lam_stats.f90
  IO/FV3Restart/m_TwoPhaseScatterGather.f90
  IO/FV3Restart/fv3jedi_io_fms2_mod.f90
  IO/FV3Restart/IOFms.cc
  IO/FV3Restart/IOFms.h
  IO/FV3Restart/IOFms.interface.F90
  IO/FV3Restart/IOFms.interface.h
  IO/CubeSphereHistory/fv3jedi_io_cube_sphere_history_mod.f90
  IO/CubeSphereHistory/IOCubeSphereHistory.cc
  IO/CubeSphereHistory/IOCubeSphereHistory.h
  IO/CubeSphereHistory/IOCubeSphereHistory.interface.F90
  IO/CubeSphereHistory/IOCubeSphereHistory.interface.h
  IO/StructuredGrid/IOStructuredGrid.cc
  IO/StructuredGrid/IOStructuredGrid.h
  IO/Utils/fv3jedi_io_utils_mod.f90
  IO/Utils/IOBase.cc
  IO/Utils/IOBase.h
  LinearVariableChange/LinearVariableChange.cc
  LinearVariableChange/LinearVariableChange.h
  LinearVariableChange/Base/LinearVariableChangeBase.cc
  LinearVariableChange/Base/LinearVariableChangeBase.h
  LinearVariableChange/Control2Analysis/fv3jedi_linvarcha_c2a.interface.F90
  LinearVariableChange/Control2Analysis/fv3jedi_linvarcha_c2a_mod.f90
  LinearVariableChange/Control2Analysis/LinVarChaC2A.cc
  LinearVariableChange/Control2Analysis/LinVarChaC2A.h
  LinearVariableChange/Control2Analysis/LinVarChaC2A.interface.h
  LinearVariableChange/Model2GeoVaLs/fv3jedi_lvc_model2geovals.interface.F90
  LinearVariableChange/Model2GeoVaLs/fv3jedi_lvc_model2geovals_mod.f90
  LinearVariableChange/Model2GeoVaLs/LinVarChaModel2GeoVaLs.cc
  LinearVariableChange/Model2GeoVaLs/LinVarChaModel2GeoVaLs.h
  LinearVariableChange/Model2GeoVaLs/LinVarChaModel2GeoVaLs.interface.h
  Model/ModelBase.cc
  Model/ModelBase.h
  Model/ModelWrapper.cc
  Model/ModelWrapper.h
  Model/fv3lm/fv3jedi_fv3lm_interface_mod.F90
  Model/fv3lm/fv3jedi_fv3lm_mod.f90
  Model/fv3lm/ModelFV3LM.cc
  Model/fv3lm/ModelFV3LM.h
  Model/fv3lm/ModelFV3LM.interface.h
  Model/pseudo/ModelPseudo.cc
  Model/pseudo/ModelPseudo.h
  ModelBias/ModelBiasCovariance.h
  ModelBias/ModelBias.h
  ModelBias/ModelBiasIncrement.h
  ModelData/ModelData.cc
  ModelData/ModelData.h
  NormGradient/NormGradient.h
  ObsLocalization/instantiateObsLocFactory.h
  ObsLocalization/ObsLocVerticalBrasnett.h
  State/State.cc
  State/State.h
  State/State.interface.h
  State/fv3jedi_state_interface_mod.F90
  State/fv3jedi_state_mod.F90
  Utilities/Constants.cc
  Utilities/Constants.h
  Utilities/Traits.h
  Utilities/interface.h
  Utilities/fv3jedi_communication_mod.f90
  Utilities/fv3jedi_constants_mod.f90
  Utilities/fv3jedi_fmsnamelist_mod.f90
  Utilities/fv3jedi_kinds_mod.f90
  Utilities/fv3jedi_netcdf_utils_mod.F90
  Utilities/fv3jedi_tile_comms_mod.f90
  Utilities/fv3jedi_vertical_remap.h
  Utilities/fv3jedi_vertical_remap.cc
  VariableChange/VaderCookbook.h
  VariableChange/VariableChange.cc
  VariableChange/VariableChange.h
  VariableChange/Base/VariableChangeBase.cc
  VariableChange/Base/VariableChangeBase.h
  VariableChange/Control2Analysis/fv3jedi_varcha_c2a.interface.F90
  VariableChange/Control2Analysis/fv3jedi_varcha_c2a_mod.f90
  VariableChange/Control2Analysis/VarChaC2A.cc
  VariableChange/Control2Analysis/VarChaC2A.h
  VariableChange/Control2Analysis/VarChaC2A.interface.h
  VariableChange/femps/femps_const_mod.f90
  VariableChange/femps/femps_fv3_mod.f90
  VariableChange/femps/femps_grid_mod.f90
  VariableChange/femps/femps_kinds_mod.f90
  VariableChange/femps/femps_operators_mod.f90
  VariableChange/femps/femps_solve_mod.f90
  VariableChange/femps/femps_testgrid_mod.f90
  VariableChange/femps/femps_utils_mod.f90
  VariableChange/Model2GeoVaLs/fv3jedi_vc_model2geovals.interface.F90
  VariableChange/Model2GeoVaLs/fv3jedi_vc_model2geovals_mod.f90
  VariableChange/Model2GeoVaLs/VarChaModel2GeoVaLs.cc
  VariableChange/Model2GeoVaLs/VarChaModel2GeoVaLs.h
  VariableChange/Model2GeoVaLs/VarChaModel2GeoVaLs.interface.h
  VariableChange/Utils/fv3jedi_fieldfail_mod.f90
  VariableChange/Utils/height_variables_mod.f90
  VariableChange/Utils/hydrometeor_radii_variables_mod.f90
  VariableChange/Utils/moisture_variables_mod.f90
  VariableChange/Utils/pressure_variables_mod.f90
  VariableChange/Utils/surface_variables_mod.f90
  VariableChange/Utils/temperature_variables_mod.f90
  VariableChange/Utils/wind_variables_mod.f90
  Tlm/fv3jedi_tlm_mod.f90
  Tlm/fv3jedi_traj_mod.f90
  Tlm/Tlm.cc
  Tlm/Tlm.h
  Tlm/Tlm.interface.F90
  Tlm/Tlm.interface.h
  Tlm/Traj.interface.F90
  Tlm/Traj.interface.h
)

# Ported cubed sphere grid gen files
list( APPEND fv3jedi_fv3_src_files
  Geometry/fv3/fv3jedi_fv3_arrays.F90
  Geometry/fv3/fv3jedi_fv3_control.F90
  Geometry/fv3/fv3jedi_fv3_eta.F90
  Geometry/fv3/fv3jedi_fv3_grid_tools.F90
  Geometry/fv3/fv3jedi_fv3_grid_utils.F90
  Geometry/fv3/fv3jedi_fv3_mp_mod.F90
  Geometry/fv3/fv3jedi_fv3_sorted_index.F90
)

# Combine
list( APPEND fv3jedi_src_files ${fv3jedi_fv3_src_files} )

# fv3 ported files have specific required properties
list(APPEND fv3_defs SPMD)
list(APPEND fv3_defs MOIST_CAPPA)
list(APPEND fv3_defs USE_COND)
list(APPEND fv3_defs OVERLOAD_R4)
list(APPEND fv3_defs OVERLOAD_R8)
list(APPEND fv3_defs INTERNAL_FILE_NML)
list(APPEND fv3_defs ENABLE_QUAD_PRECISION)
set_source_files_properties(${fv3jedi_fv3_src_files} PROPERTIES COMPILE_DEFINITIONS "${fv3_defs}")

# Add additional compiler flags to the fv3 files
# ----------------------------------------------

# Fortran‐preprocessor flag
set_fortran_preprocessing_flag(FORTRAN_PREPROCESSOR_FLAG)

# Compiler specific flags.
if(CMAKE_Fortran_COMPILER_ID MATCHES "Intel")  # Intel or IntelLLVM
  set(FV3_FLAGS "-r8")
elseif(CMAKE_Fortran_COMPILER_ID STREQUAL "GNU")
  set(FV3_FLAGS "-fdefault-real-8 -fdefault-double-8 -ffree-line-length-none")
else()
  message(WARNING
    "Unknown Fortran compiler '${CMAKE_Fortran_COMPILER_ID}',\n"
    "  fv3 files not using special flags.")
  set(FV3_FLAGS "")
endif()

# Combine
string(JOIN " " FV3_FLAGS_STR
  ${CMAKE_Fortran_FLAGS}
  ${FORTRAN_PREPROCESSOR_FLAG}
  ${FV3_FLAGS}
)

# Asign
set_source_files_properties(
  ${fv3jedi_fv3_src_files}
  PROPERTIES
    COMPILE_FLAGS "${FV3_FLAGS_STR}"
)

# -------------------------------------------

#Requirement libraries
set(FV3JEDI_LIB_DEP oops saber ufo vader atlas atlas_f fv3jedilm fms ${LAPACK_LIBRARIES} ${NETCDF_LIBRARIES})

# Fortran OpenMP library
if(OPENMP)
  list( APPEND FV3JEDI_LIB_DEP OpenMP::OpenMP_Fortran)
endif()

# Optional forecast models
# ------------------------
if( FV3_FORECAST_MODEL MATCHES "GEOS" )

  # GEOS source files
  list( APPEND fv3jedi_src_files
    Model/geos/fv3jedi_geos_interface_mod.F90
    Model/geos/fv3jedi_geos_mod.F90
    Model/geos/ModelGEOS.cc
    Model/geos/ModelGEOS.h
    Model/geos/ModelGEOS.interface.h
  )

  # GEOS libraries
  list( APPEND FV3JEDI_LIB_DEP MPI::MPI_Fortran )

elseif( FV3_FORECAST_MODEL MATCHES "UFS" )

  # Source files when building with UFS
  list( APPEND fv3jedi_src_files
    Model/ufs/fv3jedi_ufs_interface_mod.F90
    Model/ufs/fv3jedi_ufs_mod.F90
    Model/ufs/ModelUFS.cc
    Model/ufs/ModelUFS.h
    Model/ufs/ModelUFS.interface.h
  )

  if(CMAKE_Fortran_COMPILER_ID MATCHES GNU)
    set_source_files_properties(${fv3jedi_ufs_src_files} PROPERTIES COMPILE_FLAGS "${CMAKE_Fortran_FLAGS} -ffree-line-length-none -fno-range-check ")
  endif()

endif()


#Add the library
ecbuild_add_library( TARGET          fv3jedi
                     SOURCES         ${fv3jedi_src_files}
                     PUBLIC_LIBS     ${FV3JEDI_LIB_DEP}
                     INSTALL_HEADERS LISTED
                     LINKER_LANGUAGE ${FV3JEDI_LINKER_LANGUAGE}
                   )

target_include_directories( fv3jedi PUBLIC "$<BUILD_INTERFACE:${FV3JEDI_INCLUDE_DIRS}>" "$<BUILD_INTERFACE:${FV3JEDI_EXTRA_INCLUDE_DIRS}>" )


# Compiler definitions for full UFS model
if( FV3_FORECAST_MODEL MATCHES "UFS" )

  # Link all the libraries
  target_link_libraries( fv3jedi PUBLIC fv3atm)
  target_link_libraries( fv3jedi PUBLIC fv3)
  target_link_libraries( fv3jedi PUBLIC ccpp_physics)
  target_link_libraries( fv3jedi PUBLIC fv3ccpp)
  target_link_libraries( fv3jedi PUBLIC stochastic_physics)
  target_link_libraries( fv3jedi PUBLIC ccpp)
  if(UFS_APP MATCHES "^(S2S)$")
    target_link_libraries( fv3jedi PUBLIC PIO::PIO_C)
    target_link_libraries( fv3jedi PUBLIC PIO::PIO_Fortran)
    target_link_libraries( fv3jedi PUBLIC cmeps)
    target_link_libraries( fv3jedi PUBLIC cice)
    target_link_libraries( fv3jedi PUBLIC mom6)
    target_link_libraries( fv3jedi PUBLIC gsw)
  elseif(UFS_APP MATCHES "^(ATM)$")
    # Nothing to do
  elseif(UFS_APP MATCHES "^(ATMAERO)$")
    target_link_libraries( fv3jedi PUBLIC GFTL_SHARED::gftl-shared)
    target_link_libraries( fv3jedi PUBLIC MAPL)
    target_link_libraries( fv3jedi PUBLIC ga_environment)
    target_link_libraries( fv3jedi PUBLIC du2g_gridcomp)
    target_link_libraries( fv3jedi PUBLIC ni2g_gridcomp)
    target_link_libraries( fv3jedi PUBLIC ss2g_gridcomp)
    target_link_libraries( fv3jedi PUBLIC su2g_gridcomp)
    target_link_libraries( fv3jedi PUBLIC gocart_process)
    target_link_libraries( fv3jedi PUBLIC chem_shared)
    target_link_libraries( fv3jedi PUBLIC ca2g_gridcomp)
    target_link_libraries( fv3jedi PUBLIC gocart_gridcomp)
    target_link_libraries( fv3jedi PUBLIC aerosols_gridcomp)
    target_link_libraries( fv3jedi PUBLIC ufs_aerosols)
  else()
    message(FATAL_ERROR "fv3jedi target_link_libraries not configured for UFS_APP ${UFS_APP}")
  endif()
  target_link_libraries( fv3jedi PUBLIC ufs)
  target_link_libraries( fv3jedi PUBLIC NetCDF::NetCDF_C NetCDF::NetCDF_Fortran)
  target_link_libraries( fv3jedi PUBLIC nemsio::nemsio)
  target_link_libraries( fv3jedi PUBLIC w3emc::w3emc_d)
  target_link_libraries( fv3jedi PUBLIC ip::ip_d)
  target_link_libraries( fv3jedi PUBLIC bacio::bacio_4)
  target_link_libraries( fv3jedi PUBLIC FMS::fms_r8)
  target_link_libraries( fv3jedi PUBLIC ESMF)
  target_compile_definitions( fv3jedi PUBLIC "-DFRONT_FV3=fv3gfs_cap_mod")
  target_compile_definitions(fv3jedi PUBLIC UFS_BUILD)
  add_dependencies(fv3jedi ufs-weather-model )
endif()
