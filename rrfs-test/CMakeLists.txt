#!-------------------------------------------------------------------------
#!    NOAA/NCEP, National Centers for Environmental Prediction  RDASapp        !
#!-------------------------------------------------------------------------

# rrfs data - from rrfs-test-data repo if found, from local directory, or from tarball
if (CLONE_RRFSDATA)
   message(STATUS "Use test data from rrfs-test-data repository")
   set (rrfs-test_data_local "${CMAKE_SOURCE_DIR}/rrfs-test-data/")
# It's unclear if anyone is using the local data functionality, therefore comment it out
# for now and add in if someone complains / remove if completely if not.
#elseif (DEFINED ENV{FV3_JEDI_TESTFILES})
#  message(STATUS "Use test data from local directory $ENV{FV3_JEDI_TESTFILES}")
#  # A bit of guesswork here, I don't know if folks using this option stored it in the same directory structure
#  set (fv3-jedi_data_testinput_tier_1_local "$ENV{FV3_JEDI_TESTFILES}/fv3-jedi-data/testinput_tier_1")
   if(FV3_DYCORE)
      list( APPEND rrfs_fv3jedi_test_cases
             rrfs_fv3jedi_hyb_2022052619
          )
      # JEDI config files
      # ----------------
      list( APPEND rrfs_fv3jedi_test_yamf_files
      rrfs_fv3jedi_hyb_2022052619.yaml
      )
      foreach(case IN LISTS rrfs_fv3jedi_test_cases)
         set(casedir "${CMAKE_CURRENT_BINARY_DIR}/rundir-${case}")
         set(src_casedir "${rrfs-test_data_local}/rundir-${case}")
         if (NOT EXISTS "${casedir}")
           file(MAKE_DIRECTORY ${casedir})
         endif()
         file(CREATE_LINK ${src_casedir}/DataFix ${casedir}/DataFix SYMBOLIC)
         file(CREATE_LINK ${src_casedir}/Data_static ${casedir}/Data_static SYMBOLIC)
      #clt     file(CREATE_LINK ${src_casedir}/testinput ${casedir} SYMBOLIC)
         file(COPY ${src_casedir}/INPUT DESTINATION ${casedir} )
         file(COPY ${src_casedir}/${case}.yaml  DESTINATION ${casedir} )
         file(COPY ${src_casedir}/Data DESTINATION ${casedir} )
      endforeach()
      # ---------------
      message(STATUS "MACHINE_ID is " ${MACHINE_ID})
         if("${MACHINE_ID}" STREQUAL "orion")
            message(STATUS "Because MACHINE_ID is orion, adding exclusive MPI option" )
            set(RESTORE_MPI_ARGS ${MPI_ARGS})
            set(MPI_ARGS "${MPI_ARGS} --exclusive")
         endif()   
         set(target_test rrfs_fv3jedi_hyb_2022052619)
         ecbuild_add_test( TARGET   ${target_test}
                        MPI      80
                        WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/rundir-${target_test}
                        ARGS     ${target_test}.yaml
                        COMMAND  fv3jedi_var.x )
         if("${MACHINE_ID}" STREQUAL "orion")
            set(MPI_ARGS ${RESTORE_MPI_ARGS})
         endif()
   endif()
   if(MPAS_DYCORE)
      list( APPEND rrfs_mpasjedi_test_cases
          rrfs_mpasjedi_2022052619_Ens3Dvar
       )
      # JEDI config files
      # ----------------
      list( APPEND rrfs_mpasjedi_test_yamf_files
      rrfs_mpasjedi_2022052619_Ens3Dvar.yaml
      )
      foreach(case IN LISTS rrfs_mpasjedi_test_cases)
         set(casedir "${CMAKE_CURRENT_BINARY_DIR}/rundir-${case}")
         set(src_casedir "${rrfs-test_data_local}/rundir-${case}")
         if (NOT EXISTS "${casedir}")
           file(MAKE_DIRECTORY ${casedir})
         endif()
         file(CREATE_LINK ${src_casedir}/ensemble ${casedir}/ensemble SYMBOLIC)
         file(CREATE_LINK ${src_casedir}/BUMP_files ${casedir}/BUMP_files SYMBOLIC)
         file(GLOB YAML_FILES "${src_casedir}/*.yaml")
         file(COPY ${YAML_FILES} DESTINATION ${casedir})
         file(GLOB nc_FILES "${src_casedir}/*.nc")
         file(COPY ${nc_FILES} DESTINATION ${casedir})
         file(GLOB bl_FILES "${src_casedir}/*.*BL")
         file(COPY ${bl_FILES} DESTINATION ${casedir})

         file(GLOB stream_FILES "${src_casedir}/stream*.atmo*")
         file(COPY ${stream_FILES} DESTINATION ${casedir})
         file(GLOB DATA_FILES "${src_casedir}/*.DATA")
         file(COPY ${DATA_FILES} DESTINATION ${casedir})

         file(COPY ${src_casedir}/Data DESTINATION ${casedir})
         file(COPY ${src_casedir}/CONUS.graph.info.part.36  DESTINATION ${casedir})
         file(COPY ${src_casedir}/namelist.atmosphere_15km  DESTINATION ${casedir})

      endforeach()

      message(STATUS "MACHINE_ID is " ${MACHINE_ID})
         if("${MACHINE_ID}" STREQUAL "orion")
            message(STATUS "Because MACHINE_ID is orion, adding exclusive MPI option" )
            set(RESTORE_MPI_ARGS ${MPI_ARGS})
            set(MPI_ARGS "${MPI_ARGS} --exclusive")
         endif()   
         set(target_test rrfs_mpasjedi_2022052619_Ens3Dvar)
         ecbuild_add_test( TARGET   ${target_test}
                        MPI      36
                        WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/rundir-${target_test}
                        ARGS     ${target_test}.yaml
                        COMMAND  mpasjedi_variational.x )
         if("${MACHINE_ID}" STREQUAL "orion")
            set(MPI_ARGS ${RESTORE_MPI_ARGS})
	 endif()
   endif()
endif()
