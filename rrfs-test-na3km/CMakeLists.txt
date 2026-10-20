#!-------------------------------------------------------------------------
#!    NOAA/NCEP, National Centers for Environmental Prediction  RDASapp        !
#!-------------------------------------------------------------------------

# Optional full-capability analysis on the RRFS NA 3 km domain (2024-05-27 00Z).
# Not part of CI: added only with -DBUILD_RRFS_TEST_NA3KM=ON, on wcoss2 and ursa,
# where the case is staged with scripts/stage_na3km_case.sh.

set(case "rrfs_fv3jedi_na3km_2024052700_analysis")
set(exe "fv3jedi_var.x")

if(NOT FV3_DYCORE)
  message(STATUS "${case}: needs FV3_DYCORE, skipping")
  return()
endif()
if(NOT ("${MACHINE_ID}" STREQUAL "wcoss2" OR "${MACHINE_ID}" STREQUAL "ursa"))
  message(STATUS "${case}: only supported on wcoss2 and ursa (MACHINE_ID=${MACHINE_ID}), skipping")
  return()
endif()

set(RRFS_NA3KM_DATA "${CMAKE_SOURCE_DIR}/../fix/.agent/expr_data/na3km_2024052700" CACHE PATH
    "Staged NA 3 km case directory (see rrfs-test-na3km/scripts/stage_na3km_case.sh)")
set(RRFS_NA3KM_PPN "40" CACHE STRING "MPI tasks per node for the NA 3 km test (40x40 layout = 1600 tasks)")
set(RRFS_NA3KM_WALLTIME "01:00:00" CACHE STRING "Wall time for the NA 3 km test")
if(NOT EXISTS "${RRFS_NA3KM_DATA}/bkg")
  message(WARNING "${case}: case data not found at ${RRFS_NA3KM_DATA}, skipping. "
                  "Stage it and set -DRRFS_NA3KM_DATA=<case_dir>.")
  return()
endif()

set(rdasapp_dir "${CMAKE_SOURCE_DIR}/..")
set(test_dir "${CMAKE_CURRENT_SOURCE_DIR}")
set(casedir "${CMAKE_CURRENT_BINARY_DIR}/rundir-${case}")
file(MAKE_DIRECTORY ${casedir}/data)

# Link everything in; the backgrounds, ensemble and grid files are far too large to copy
file(GLOB bkg_files "${RRFS_NA3KM_DATA}/bkg/*")
file(GLOB data_fix_files "${RRFS_NA3KM_DATA}/fix/*")
file(GLOB test_fix_files "${test_dir}/fix/*")
foreach(f ${bkg_files} ${data_fix_files} ${test_fix_files})
  get_filename_component(fname ${f} NAME)
  file(CREATE_LINK ${f} ${casedir}/${fname} SYMBOLIC)
endforeach()
file(CREATE_LINK ${RRFS_NA3KM_DATA}/INPUT ${casedir}/INPUT SYMBOLIC)
file(CREATE_LINK ${RRFS_NA3KM_DATA}/inputs ${casedir}/data/inputs SYMBOLIC)
file(CREATE_LINK ${RRFS_NA3KM_DATA}/obs ${casedir}/data/obs SYMBOLIC)
file(CREATE_LINK ${test_dir}/testoutput ${casedir}/testoutput SYMBOLIC)
file(CREATE_LINK ${rdasapp_dir}/rrfs-test/testinput/gsd_sfcobs_uselist.txt ${casedir}/gsd_sfcobs_uselist.txt SYMBOLIC)
file(CREATE_LINK ${rdasapp_dir}/rrfs-test/testinput/gsd_sfcobs_provider.txt ${casedir}/gsd_sfcobs_provider.txt SYMBOLIC)

# Render the JEDI yaml with JCB; re-run on the next build if the JCB config changes
set(jcb_config "${test_dir}/jcb/jcb-${case}.yaml")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${jcb_config})
find_package(Python3 REQUIRED COMPONENTS Interpreter)
execute_process(
  COMMAND ${CMAKE_COMMAND} -E env
          "PYTHONPATH=${rdasapp_dir}/sorc/jcb/src:${rdasapp_dir}/sorc/wxflow/src:$ENV{PYTHONPATH}"
          ${Python3_EXECUTABLE} ${rdasapp_dir}/parm/jcb-rdas/test/ci/run_jcb_ctest.py
          2024052700 ${jcb_config} ${case}.yaml
  WORKING_DIRECTORY ${casedir}
  RESULT_VARIABLE jcb_result)
if(NOT jcb_result EQUAL 0)
  message(FATAL_ERROR "${case}: JCB failed to render ${case}.yaml from ${jcb_config}")
endif()

if("${MACHINE_ID}" STREQUAL "wcoss2")
  configure_file(${rdasapp_dir}/rrfs-test/ush/wrapper_ctest_pbs.sh ${CMAKE_CURRENT_BINARY_DIR}/wrapper_ctest_pbs.sh COPYONLY)
  math(EXPR nodes "1600 / ${RRFS_NA3KM_PPN}")
  ecbuild_add_test( TARGET  ${case}
                    MPI     0
                    WORKING_DIRECTORY ${casedir}
                    ARGS    "${case} ${exe} ${case}.yaml ${RRFS_NA3KM_PPN} ${nodes}"
                    COMMAND ${CMAKE_CURRENT_BINARY_DIR}/wrapper_ctest_pbs.sh )
  set_property(TEST ${case} APPEND PROPERTY ENVIRONMENT "CTEST_PBS_WALLTIME=${RRFS_NA3KM_WALLTIME}")
else()
  set(MPI_ARGS "${MPI_ARGS} --time=${RRFS_NA3KM_WALLTIME} --exclusive --mem=0 --ntasks-per-node=${RRFS_NA3KM_PPN}")
  ecbuild_add_test( TARGET  ${case}
                    MPI     1600
                    WORKING_DIRECTORY ${casedir}
                    ARGS    ${case}.yaml
                    COMMAND ${exe} )
endif()
set_property(TEST ${case} PROPERTY ENVIRONMENT_MODIFICATION
             "LD_LIBRARY_PATH=path_list_prepend:${rdasapp_dir}/build/lib64")
set_property(TEST ${case} PROPERTY LABELS "rrfs-test-na3km")
