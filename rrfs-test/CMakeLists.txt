#!-------------------------------------------------------------------------
#!    NOAA/NCEP, National Centers for Environmental Prediction  RDASapp        !
#!-------------------------------------------------------------------------

include(funcs.cmake)

### Define CTests here ###

# FV3-JEDI tests
set(rrfs_fv3jedi_tests)
add_to_dictionary(rrfs_fv3jedi_tests "rrfs_fv3jedi_hyb_2022052619"     "fv3jedi_var.x")
add_to_dictionary(rrfs_fv3jedi_tests "rrfs_fv3jedi_letkf_2022052619"   "fv3jedi_letkf.x")

# MPAS-JEDI tests 
set(rrfs_mpasjedi_tests)
add_to_dictionary(rrfs_mpasjedi_tests "rrfs_mpasjedi_2024052700_Ens3Dvar" "mpasjedi_variational.x")
add_to_dictionary(rrfs_mpasjedi_tests "rrfs_mpasjedi_2024052700_letkf"    "mpasjedi_enkf.x")
add_to_dictionary(rrfs_mpasjedi_tests "rrfs_mpasjedi_2024052700_getkf"    "mpasjedi_enkf.x")
add_to_dictionary(rrfs_mpasjedi_tests "rrfs_mpasjedi_2024052700_bumploc"  "mpasjedi_error_covariance_toolbox.x")

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

      get_all_keys(rrfs_fv3jedi_tests caselist)
      foreach(case ${caselist})
         get_from_dictionary(rrfs_fv3jedi_tests case exe)
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
      set(MPI_ARGS "${MPI_ARGS} --ntasks-per-node=4")

      get_all_keys(rrfs_mpasjedi_tests caselist)
      foreach(case ${caselist})
	 get_from_dictionary(rrfs_mpasjedi_tests case exe)
         set(casedir "${CMAKE_CURRENT_BINARY_DIR}/rundir-${case}")
         set(src_casedir "${rrfs-test_data_local}/rrfs-data_mpasjedi_2024052700")
         if (NOT EXISTS "${casedir}")
           file(MAKE_DIRECTORY ${casedir})
         endif()
	 file(CREATE_LINK ${src_casedir}/data ${casedir}/data SYMBOLIC)
	 file(CREATE_LINK ${src_casedir}/graphinfo ${casedir}/graphinfo SYMBOLIC)
	 file(CREATE_LINK ${src_casedir}/stream_list ${casedir}/stream_list SYMBOLIC)
	 file(COPY ${src_casedir}/streams.atmosphere DESTINATION ${casedir})
	 file(COPY ${src_casedir}/namelist.atmosphere DESTINATION ${casedir})
	 file(COPY ${src_casedir}/geovars.yaml DESTINATION ${casedir})
	 file(COPY ${src_casedir}/keptvars.yaml DESTINATION ${casedir})
	 file(COPY ${src_casedir}/obsop_name_map.yaml DESTINATION ${casedir})
	 file(GLOB bl_FILES "${src_casedir}/*.*BL")
	 file(COPY ${bl_FILES} DESTINATION ${casedir})
	 file(COPY ${src_yaml}/${case}.yaml DESTINATION ${casedir})
         set(target_test ${case})
         ecbuild_add_test( TARGET ${target_test}
                        MPI      120
                        WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/rundir-${target_test}
                        ARGS     ${target_test}.yaml
                        COMMAND  ${exe} )
      endforeach()

      if("${MACHINE_ID}" STREQUAL "orion")
          set(MPI_ARGS ${RESTORE_MPI_ARGS})
      endif()

   endif()
endif()
