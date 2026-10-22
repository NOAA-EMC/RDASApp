#!-------------------------------------------------------------------------
#!    NOAA/NCEP, National Centers for Environmental Prediction  RDASapp        !
#!-------------------------------------------------------------------------

# Optional full-capability analysis on the RRFS NA 3 km domain (2024-05-27 01Z).
# Not part of CI: added only with -DBUILD_RRFS_TEST_NA3KM=ON, on wcoss2 and ursa,
# where ush/init.sh links the staged case data to fix/.agent_na3km (see README.md).

set(case "rrfs_fv3jedi_na3km_2024052701_analysis")
set(exe "fv3jedi_var.x")

if(NOT FV3_DYCORE)
  message(STATUS "${case}: needs FV3_DYCORE, skipping")
  return()
endif()
if(NOT "${MACHINE_ID}" MATCHES "^(ursa|wcoss2)$")
  message(STATUS "${case}: only supported on wcoss2 and ursa (MACHINE_ID=${MACHINE_ID}), skipping")
  return()
endif()
set(rdasapp_dir "${CMAKE_SOURCE_DIR}/..")
set(na3km_data "${rdasapp_dir}/fix/expr_data/fv3_2024052701_na3km")
if(NOT EXISTS "${na3km_data}/bkg")
  message(WARNING "${case}: case data not found at ${na3km_data}, skipping")
  return()
endif()

# 44x44 layout = 1936 MPI tasks
set(na3km_ppn 44)
set(na3km_walltime "00:45:00")

set(test_dir "${CMAKE_CURRENT_SOURCE_DIR}")
set(casedir "${CMAKE_CURRENT_BINARY_DIR}/rundir-${case}")
file(MAKE_DIRECTORY ${casedir}/data)

# Link everything in; the backgrounds, ensemble and grid files are far too large to copy
file(GLOB bkg_files "${na3km_data}/bkg/*")
file(GLOB data_fix_files "${na3km_data}/fix/*")
file(GLOB mgbf_files "${rdasapp_dir}/fix/mgbf/mgbf_na6km_p1936_*")
foreach(f ${bkg_files} ${data_fix_files} ${mgbf_files} ${na3km_data}/fmsmpp.nml)
  get_filename_component(fname ${f} NAME)
  file(CREATE_LINK ${f} ${casedir}/${fname} SYMBOLIC)
endforeach()
file(CREATE_LINK ${rdasapp_dir}/fix/gsi_bec/gsiparm_regional_na3km_dbz.anl ${casedir}/gsiparm_regional.anl SYMBOLIC)
file(CREATE_LINK ${na3km_data}/INPUT ${casedir}/INPUT SYMBOLIC)
file(CREATE_LINK ${na3km_data}/inputs ${casedir}/data/inputs SYMBOLIC)
file(CREATE_LINK ${na3km_data}/obs ${casedir}/data/obs SYMBOLIC)
file(CREATE_LINK ${test_dir}/testoutput ${casedir}/testoutput SYMBOLIC)
file(CREATE_LINK ${rdasapp_dir}/rrfs-test/testinput/gsd_sfcobs_uselist.txt ${casedir}/gsd_sfcobs_uselist.txt SYMBOLIC)
file(CREATE_LINK ${rdasapp_dir}/rrfs-test/testinput/gsd_sfcobs_provider.txt ${casedir}/gsd_sfcobs_provider.txt SYMBOLIC)

# Render the JEDI yaml with JCB; re-run on the next build if the JCB config changes
set(jcb_config "${rdasapp_dir}/parm/jcb-rdas/test/ci/jcb-${case}.yaml")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${jcb_config})
find_package(Python3 REQUIRED COMPONENTS Interpreter)
execute_process(
  COMMAND ${CMAKE_COMMAND} -E env
          "PYTHONPATH=${rdasapp_dir}/sorc/jcb/src:${rdasapp_dir}/sorc/wxflow/src:$ENV{PYTHONPATH}"
          ${Python3_EXECUTABLE} ${rdasapp_dir}/parm/jcb-rdas/test/ci/run_jcb_ctest.py
          2024052701 ${jcb_config} ${case}.yaml
  WORKING_DIRECTORY ${casedir}
  RESULT_VARIABLE jcb_result)
if(NOT jcb_result EQUAL 0)
  message(FATAL_ERROR "${case}: JCB failed to render ${case}.yaml from ${jcb_config}")
endif()

if("${MACHINE_ID}" STREQUAL "wcoss2")
  configure_file(${rdasapp_dir}/rrfs-test/ush/wrapper_ctest_pbs.sh ${CMAKE_CURRENT_BINARY_DIR}/wrapper_ctest_pbs.sh COPYONLY)
  math(EXPR nodes "1936 / ${na3km_ppn}")
  ecbuild_add_test( TARGET  ${case}
                    MPI     0
                    WORKING_DIRECTORY ${casedir}
                    ARGS    "${case} ${exe} ${case}.yaml ${na3km_ppn} ${nodes}"
                    COMMAND ${CMAKE_CURRENT_BINARY_DIR}/wrapper_ctest_pbs.sh )
  set_property(TEST ${case} APPEND PROPERTY ENVIRONMENT "CTEST_PBS_WALLTIME=${na3km_walltime}")
else()
  set(MPI_ARGS "${MPI_ARGS} --time=${na3km_walltime} --exclusive --mem=0 --ntasks-per-node=${na3km_ppn}")
  ecbuild_add_test( TARGET  ${case}
                    MPI     1936
                    WORKING_DIRECTORY ${casedir}
                    ARGS    ${case}.yaml
                    COMMAND ${exe} )
endif()
set_property(TEST ${case} PROPERTY ENVIRONMENT_MODIFICATION
             "LD_LIBRARY_PATH=path_list_prepend:${rdasapp_dir}/build/lib64")
set_property(TEST ${case} PROPERTY LABELS "rrfs-test-na3km")
# The ctest clock includes time waiting in the queue, so allow far more than the 1500 s default
set_property(TEST ${case} PROPERTY TIMEOUT 86400)
