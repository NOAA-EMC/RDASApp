#!-------------------------------------------------------------------------
#!    NOAA/NCEP, National Centers for Environmental Prediction  RDASapp        !
#!-------------------------------------------------------------------------

###########################
### Begin function list ###
###########################

# Function to add key-value pairs to the dictionary
function(add_to_dictionary dict key value)
    # Check if the key already exists
    foreach(entry IN LISTS ${dict})
        string(FIND "${entry}" "=" EQUAL_POS)
        if(EQUAL_POS GREATER -1)
            string(SUBSTRING "${entry}" 0 ${EQUAL_POS} ENTRY_KEY)
            if(ENTRY_KEY STREQUAL ${key})
                # Key exists, check the value
                math(EXPR VALUE_START "${EQUAL_POS} + 1")
                string(SUBSTRING "${entry}" ${VALUE_START} -1 ENTRY_VALUE)
                if(NOT ENTRY_VALUE STREQUAL ${value})
                    message(FATAL_ERROR "Error: Key '${key}' already exists with a different value '${ENTRY_VALUE}'")
                else()
                    return()
                endif()
            endif()
        endif()
    endforeach()

    # Key does not exist, add the new entry
    set(entry "${key}=${value}")
    list(APPEND ${dict} "${entry}")
    set(${dict} "${${dict}}" PARENT_SCOPE)
endfunction()

# Function to get the value by key from the dictionary
function(get_from_dictionary dict key result)
    foreach(entry IN LISTS ${dict})
        string(FIND "${entry}" "=" EQUAL_POS)
        if(EQUAL_POS GREATER -1)
            string(SUBSTRING "${entry}" 0 ${EQUAL_POS} ENTRY_KEY)
            if(ENTRY_KEY STREQUAL ${key})
                math(EXPR VALUE_START "${EQUAL_POS} + 1")
                string(SUBSTRING "${entry}" ${VALUE_START} -1 ENTRY_VALUE)
                set(${result} "${ENTRY_VALUE}" PARENT_SCOPE)
                return()
            endif()
        endif()
    endforeach()
    # If the key is not found, set the result to an empty string or some default value
    set(${result} "" PARENT_SCOPE)
endfunction()

################################################
### End function list, begin executable code ###
################################################

### Define CTests here ###

# FV3-JEDI tests
set(rrfs_fv3jedi_tests "")
add_to_dictionary(rrfs_fv3jedi_tests "rrfs_fv3jedi_hyb_2022052619"     "fv3jedi_var.x")
add_to_dictionary(rrfs_fv3jedi_tests "rrfs_fv3jedi_letkf_2022052619"   "fv3jedi_letkf.x")

# MPAS-JEDI tests 
set(rrfs_mpasjedi_tests "")
add_to_dictionary(rrfs_mpasjedi_tests "rrfs_mpasjedi_2022052619_Ens3Dvar"     "mpasjedi_variational.x")
add_to_dictionary(rrfs_mpasjedi_tests "rrfs_mpasjedi_2022052619_atms_npp_qc"  "mpasjedi_variational.x")
add_to_dictionary(rrfs_mpasjedi_tests "rrfs_mpasjedi_2022052619_letkf"        "mpasjedi_enkf.x")


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

      foreach(keypair ${rrfs_fv3jedi_tests})
	 string(REGEX MATCH "([^=]+)=([^=]*)" match ${keypair})
	 if(match)
		 set(case ${CMAKE_MATCH_1})
		 set(exe ${CMAKE_MATCH_2})
         endif()
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

      foreach(keypair ${rrfs_mpasjedi_tests})
	 string(REGEX MATCH "([^=]+)=([^=]*)" match ${keypair})
	 if(match)
		 set(case ${CMAKE_MATCH_1})
		 set(exe ${CMAKE_MATCH_2})
         endif()
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
