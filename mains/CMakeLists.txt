# Build the big rdas executable used for all generic JEDI applications
# --------------------------------------------------------------------

#---------------------------------

# Standard compiler flags
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)
set(CMAKE_FORTRAN_STANDARD 08)
set(CMAKE_FORTRAN_STANDARD_REQUIRED ON)
set(CMAKE_FORTRAN_EXTENSIONS OFF)

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
