# EMC/NCEP/NOAA 2024
file(GLOB jbfiles *.f90)
   message(STATUS "thinkdeb-2  "  ${jbfiles}  )
set (jbfilenames "")
foreach ( _fname ${jbfiles} )
   get_filename_component( basefilename ${_fname} NAME )
   list ( APPEND jbfilenames  ${basefilename} )
   message(STATUS "thinkdeb-1  " ${basefilename})
   message(STATUS "thinkdeb0  " ${jbfilenames})
endforeach ()    
set( mgbf_lib_src_files

${jbfilenames}

#PARENT_SCOPE
)
add_library(mgbflib STATIC ${mgbf_lib_src_files})
set_target_properties(mgbf_lib PROPERTIES
    Fortran_MODULE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/modules)



