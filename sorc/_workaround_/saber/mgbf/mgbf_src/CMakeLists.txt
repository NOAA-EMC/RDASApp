# (C) Copyright 2022 United States Government as represented by the Administrator of the National
#     Aeronautics and Space Administration
#
# This software is licensed under the terms of the Apache Licence Version 2.0
# which can be obtained at http://www.apache.org/licenses/LICENSE-2.0.
file(GLOB jbfiles mgbf_lib/*.f90)
   message(STATUS "thinkdeb-2  "  ${jbfiles}  )
set (jbfilenames "")
foreach ( _fname ${jbfiles} ) 
   get_filename_component( basefilename ${_fname} NAME )
   list ( APPEND jbfilenames  mgbf_lib/${basefilename} )
   message(STATUS "thinkdeb-1  " ${basefilename})
   message(STATUS "thinkdeb0  " ${jbfilenames})
endforeach ()
message(STATUS "thinkdeb  " ${jbfilenames})
#set (jbfilenames "mgbf_lib/jp_pbfil.f90" )
set (build_saber_mgbf 1)
if( build_saber_mgbf )
    list(APPEND mgbf_src_files_list

    # Covariance block
    covariance/MGBF_Covariance.h
    covariance/MGBF_Covariance.cc
    covariance/MGBF_Covariance.interface.F90
    covariance/MGBF_Covariance.interface.h
    covariance/mgbf_covariance_mod.f90

#clth    # Grid
#     covariance/mgbf_Grid.h
#     covariance/mgbf_Grid.cc
    # Interpolation block
#     covariance/mgbf_Interpolation.h
#     covariance/mgbf_Interpolation.cc
#    interpolation/MGBF_Interpolation.h

    # Unstructured interpolation code ported from oops (until new interp code can be used)
#    interpolation/unstructured_interp/saber_unstructured_interpolation_mod.F90
#    interpolation/unstructured_interp/UnstructuredInterpolation.cc
#    interpolation/unstructured_interp/UnstructuredInterpolation.h
#    interpolation/unstructured_interp/UnstructuredInterpolation.interface.F90
#    interpolation/unstructured_interp/UnstructuredInterpolation.interface.h

    # Utilities
#    utils/mgbf_utils_mod.f90

    )
endif()
#clt find_package(mgbf_lib  REQUIRED )
message (STATUS "thinkdeb1 " ${mgbf_src_files_list} )

set( mgbf_src_files

${mgbf_src_files_list}
${jbfilenames}

PARENT_SCOPE
)
 message (STATUS "thinkdeb2.4"   ${mgbf_src_files} )
