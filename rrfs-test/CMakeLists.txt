# (C) Copyright 2017-2023 UCAR
#
# This software is licensed under the terms of the Apache Licence Version 2.0
# which can be obtained at http://www.apache.org/licenses/LICENSE-2.0.

# FV3-JEDI test data - from fv3-jedi-data repo if found, from local directory, or from tarball
set(rrfs-test-data_FOUND 1)  #clttodo
if (rrfs-test-data_FOUND)
  message(STATUS "Use test data from rrfs-test-data repository")
  set (rrfs-test_data_local "${CMAKE_SOURCE_DIR}/rrfs-test-data/")
# It's unclear if anyone is using the local data functionality, therefore comment it out
# for now and add in if someone complains / remove if completely if not.
#elseif (DEFINED ENV{FV3_JEDI_TESTFILES})
#  message(STATUS "Use test data from local directory $ENV{FV3_JEDI_TESTFILES}")
#  # A bit of guesswork here, I don't know if folks using this option stored it in the same directory structure
#  set (fv3-jedi_data_testinput_tier_1_local "$ENV{FV3_JEDI_TESTFILES}/fv3-jedi-data/testinput_tier_1")
else()
  message(FATAL_ERROR  "rrfs data would only be avaiable from local sourcerfs-fv3-jedi-data repository")
endif()
list( APPEND rrfs_fv3jedi_test_cases
       rrfs_fv3jedi_hyb_2022052619
    )
foreach(case IN LISTS rrfs_fv3jedi_test_cases)
   set(casedir "${CMAKE_CURRENT_BINARY_DIR}/rundir-${case}")
   set(src_casedir "${rrfs-test_data_local}/rundir-${case}")
   if (NOT EXISTS "${casedir}")
     file(MAKE_DIRECTORY ${casedir})
     file(CREATE_LINK ${src_casedir}/DataFix ${casedir}/DataFix SYMBOLIC)
     file(CREATE_LINK ${src_casedir}/Data_static ${casedir}/Data_static SYMBOLIC)
#clt     file(CREATE_LINK ${src_casedir}/testinput ${casedir} SYMBOLIC)
     file(COPY ${src_casedir}/INPUT DESTINATION ${casedir} )
     file(COPY ${src_casedir}/${case}.yaml  DESTINATION ${casedir} )
     file(COPY ${src_casedir}/Data DESTINATION ${casedir} )
   endif()
endforeach()

# FV3 config files
# ----------------
list( APPEND rrfs_fv3_test_yamf_files 
rrfs_fv3jedi_hyb_2022052619.yaml
)

# gsibec config files
# -------------------
# ------------

# Interface tests
# ---------------
set(target_test rrfs_fv3jedi_hyb_2022052619)
ecbuild_add_test( TARGET   ${target_test} 
                  MPI      80 
                  WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/rundir-${target_test}
                  ARGS     ${target_test}.yaml 
                  COMMAND  fv3jedi_var.x )


