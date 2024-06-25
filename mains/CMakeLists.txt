# Build the big rdas executable used for all generic JEDI applications
# --------------------------------------------------------------------
ecbuild_add_executable( TARGET  rdas.x
                        SOURCES rdas.cc
                        LIBS    fv3jedi
                      )
