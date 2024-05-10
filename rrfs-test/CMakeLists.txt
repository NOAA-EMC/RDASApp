#!-------------------------------------------------------------------------
#!    NOAA/NCEP, National Centers for Environmental Prediction  RDASapp        !
#!-------------------------------------------------------------------------

# rrfs data - from rrfs-test-data repo if found, from local directory, or from tarball
if (CLONE_RRFSDATA)
   message(STATUS "Use test data from rrfs-test-data repository")
   set (rrfs-test_data_local "${CMAKE_SOURCE_DIR}/rrfs-test-data/")
   set (src_yaml "${CMAKE_SOURCE_DIR}/rrfs-test/testinput")
# It's unclear if anyone is using the local data functionality, therefore comment it out
# for now and add in if someone complains / remove if completely if not.
#elseif (DEFINED ENV{FV3_JEDI_TESTFILES})
#  message(STATUS "Use test data from local directory $ENV{FV3_JEDI_TESTFILES}")
#  # A bit of guesswork here, I don't know if folks using this option stored it in the same directory structure
#  set (fv3-jedi_data_testinput_tier_1_local "$ENV{FV3_JEDI_TESTFILES}/fv3-jedi-data/testinput_tier_1")
   if(FV3_DYCORE)

      message(STATUS "MACHINE_ID is " ${MACHINE_ID})
      if("${MACHINE_ID}" STREQUAL "orion")
         message(STATUS "Because MACHINE_ID is orion, adding exclusive MPI option" )
         set(RESTORE_MPI_ARGS ${MPI_ARGS})
         set(MPI_ARGS "${MPI_ARGS} --exclusive")
      endif()   

      # JEDI test cases
      # ----------------
      # NOTE: To add a new ctest for FV3, simple add the new yaml file here (without the extension)
      #       Also need to add the associated executable to the rrfs_fv3jedi_exes list below 
      list( APPEND rrfs_fv3jedi_tests
             rrfs_fv3jedi_hyb_2022052619
             rrfs_fv3jedi_letkf_2022052619
          )

      # JEDI executables for each test case above
      list ( APPEND rrfs_fv3jedi_exes
             fv3jedi_var.x
             fv3jedi_letkf.x
      )

      foreach(case IN LISTS rrfs_fv3jedi_tests)
         set(casedir "${CMAKE_CURRENT_BINARY_DIR}/rundir-${case}")
         set(src_casedir "${rrfs-test_data_local}/rrfs-data_fv3jedi_2022052619")
         if (NOT EXISTS "${casedir}")
           file(MAKE_DIRECTORY ${casedir})
         endif()
         file(CREATE_LINK ${src_casedir}/DataFix ${casedir}/DataFix SYMBOLIC)
         file(CREATE_LINK ${src_casedir}/Data_static ${casedir}/Data_static SYMBOLIC)
         file(CREATE_LINK ${src_casedir}/INPUT ${casedir}/INPUT SYMBOLIC)
         file(CREATE_LINK ${src_casedir}/Data ${casedir}/Data SYMBOLIC)
         file(COPY ${src_yaml}/${case}.yaml DESTINATION ${casedir} )
         set(target_test ${case})
         list(FIND rrfs_fv3jedi_tests "${case}" index)
         list(GET  rrfs_fv3jedi_exes ${index} exe)
         ecbuild_add_test( TARGET ${target_test}
                        MPI      80
                        WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/rundir-${target_test}
                        ARGS     ${target_test}.yaml
                        COMMAND  ${exe} )
      endforeach()

      if("${MACHINE_ID}" STREQUAL "orion")
          set(MPI_ARGS ${RESTORE_MPI_ARGS})
      endif()


   endif()
   if(MPAS_DYCORE)

      message(STATUS "MACHINE_ID is " ${MACHINE_ID})
      if("${MACHINE_ID}" STREQUAL "orion")
         message(STATUS "Because MACHINE_ID is orion, adding exclusive MPI option" )
         set(RESTORE_MPI_ARGS ${MPI_ARGS})
         set(MPI_ARGS "${MPI_ARGS} --exclusive")
      endif()   

      # JEDI test cases
      # ----------------
      # NOTE: To add a new ctest for MPAS, simple add the new yaml file here (without the extension)
      #       Also need to add the associated executable to the rrfs_fv3jedi_exes list below 
      list( APPEND rrfs_mpasjedi_tests
             rrfs_mpasjedi_2022052619_Ens3Dvar
          )

      # JEDI executables for each test case above
      list ( APPEND rrfs_mpasjedi_exes
             mpasjedi_variational.x
      )

      foreach(case IN LISTS rrfs_mpasjedi_tests)

         set(casedir "${CMAKE_CURRENT_BINARY_DIR}/rundir-${case}")
         set(src_casedir "${rrfs-test_data_local}/rrfs-data_mpasjedi_2022052619")
         if (NOT EXISTS "${casedir}")
           file(MAKE_DIRECTORY ${casedir})
         endif()
         file(CREATE_LINK ${src_casedir}/DataFix ${casedir}/DataFix SYMBOLIC)
         file(CREATE_LINK ${src_casedir}/Data_static ${casedir}/Data_static SYMBOLIC)
         file(CREATE_LINK ${src_casedir}/Data ${casedir}/Data SYMBOLIC)
         file(COPY ${src_casedir}/streams.atmosphere_15km DESTINATION ${casedir})
         file(COPY ${src_casedir}/namelist.atmosphere_15km  DESTINATION ${casedir})
	 file(COPY ${src_casedir}/geovars.yaml DESTINATION ${casedir})
	 file(COPY ${src_casedir}/keptvars.yaml DESTINATION ${casedir})
	 file(COPY ${src_casedir}/obsop_name_map.yaml DESTINATION ${casedir})
         file(GLOB bl_FILES "${src_casedir}/*.*BL")
         file(COPY ${bl_FILES} DESTINATION ${casedir})
         file(GLOB DATA_FILES "${src_casedir}/*DATA*")
         file(COPY ${DATA_FILES} DESTINATION ${casedir})
         file(COPY ${src_yaml}/${case}.yaml DESTINATION ${casedir} )
         set(target_test ${case})
         list(FIND rrfs_mpasjedi_tests "${case}" index)
         list(GET  rrfs_mpasjedi_exes ${index} exe)
         ecbuild_add_test( TARGET ${target_test}
                        MPI      36
                        WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/rundir-${target_test}
                        ARGS     ${target_test}.yaml
                        COMMAND  ${exe} )
      endforeach()

      if("${MACHINE_ID}" STREQUAL "orion")
          set(MPI_ARGS ${RESTORE_MPI_ARGS})
      endif()

   endif()
endif()
