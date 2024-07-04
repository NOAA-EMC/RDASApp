# Build the big rdas executable used for all generic JEDI applications
# --------------------------------------------------------------------

#---------------------------------

set(CMAKE_CXX_STANDARD 17)

if ( FV3_DYCORE )

   find_package( fv3jedi REQUIRED )
   ecbuild_add_executable( TARGET  rdas_fv3jedi.x
                           SOURCES rdas_fv3jedi.cc
                           LIBS    fv3jedi
                         )

endif()

if ( MPAS_DYCORE )

   find_package( mpasjedi REQUIRED )
   ecbuild_add_executable( TARGET  rdas_mpasjedi.x
                           SOURCES rdas_mpasjedi.cc
                           LIBS    mpasjedi
                         )

endif()
