#!-------------------------------------------------------------------------
#!    NOAA/NCEP, National Centers for Environmental Prediction  RDASapp        !
#!-------------------------------------------------------------------------

# Full-capability analyses on the RRFS NA 3 km domain (2024-05-27 01Z): hybrid 3DEnVar and GETKF.
# Added only on wcoss2 and ursa, where ush/init.sh links the staged case data to
# fix/.agent_na3km. build.sh renders the yamls into testinput/ with JCB.

set(na3km_cases
    "rrfs_fv3jedi_na3km_2024052701_analysis"
    "rrfs_fv3jedi_na3km_2024052701_getkf")

if(NOT FV3_DYCORE)
  message(STATUS "rrfs-test-na3km: needs FV3_DYCORE, skipping")
  return()
endif()
if(NOT "${MACHINE_ID}" MATCHES "^(ursa|wcoss2)$")
  message(STATUS "rrfs-test-na3km: only supported on wcoss2 and ursa (MACHINE_ID=${MACHINE_ID}), skipping")
  return()
endif()
set(rdasapp_dir "${CMAKE_SOURCE_DIR}/..")
set(na3km_data "${rdasapp_dir}/fix/expr_data/fv3_2024052701_na3km")
if(NOT EXISTS "${na3km_data}/bkg")
  message(WARNING "rrfs-test-na3km: case data not found at ${na3km_data}, skipping")
  return()
endif()

set(test_dir "${CMAKE_CURRENT_SOURCE_DIR}")
set(RESTORE_MPI_ARGS ${MPI_ARGS})

foreach(case ${na3km_cases})

  if("${case}" MATCHES "getkf")
    set(exe "fv3jedi_letkf.x")
    # 32x60 layout = 1920 MPI tasks on 48 nodes, as in the rrfs-workflow na3km GETKF job
    set(na3km_ntasks 1920)
    set(na3km_ppn 40)
    set(na3km_nodes 48)
    set(na3km_threads 1)
    set(na3km_depth 3)
    set(na3km_walltime "00:30:00")
  else()
    set(exe "fv3jedi_var.x")
    # 44x44 layout = 1936 MPI tasks
    set(na3km_ntasks 1936)
    set(na3km_ppn 44)
    set(na3km_walltime "01:15:00")
    if("${MACHINE_ID}" STREQUAL "wcoss2")
      set(na3km_ppn 32)
      set(na3km_nodes 61)
      set(na3km_threads 4)
      set(na3km_depth 4)
    endif()
  endif()

  set(casedir "${CMAKE_CURRENT_BINARY_DIR}/rundir-${case}")
  file(MAKE_DIRECTORY ${casedir}/data/satbias_out)

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
  file(CREATE_LINK ${na3km_data}/crtm ${casedir}/data/crtm SYMBOLIC)
  file(CREATE_LINK ${na3km_data}/satbias_in ${casedir}/data/satbias_in SYMBOLIC)
  file(CREATE_LINK ${test_dir}/testoutput ${casedir}/testoutput SYMBOLIC)
  file(CREATE_LINK ${test_dir}/testinput/gsd_sfcobs_uselist.txt ${casedir}/gsd_sfcobs_uselist.txt SYMBOLIC)
  file(CREATE_LINK ${test_dir}/testinput/gsd_sfcobs_provider.txt ${casedir}/gsd_sfcobs_provider.txt SYMBOLIC)

  # The yaml is rendered by build.sh with JCB
  file(COPY ${test_dir}/testinput/${case}.yaml DESTINATION ${casedir})

  if("${MACHINE_ID}" STREQUAL "wcoss2")
    configure_file(${rdasapp_dir}/rrfs-test/ush/wrapper_ctest_pbs.sh ${CMAKE_CURRENT_BINARY_DIR}/wrapper_ctest_pbs.sh COPYONLY)
    ecbuild_add_test( TARGET  ${case}
                      MPI     0
                      WORKING_DIRECTORY ${casedir}
                      ARGS    "${case} ${exe} ${case}.yaml ${na3km_ppn} ${na3km_nodes}"
                      COMMAND ${CMAKE_CURRENT_BINARY_DIR}/wrapper_ctest_pbs.sh )
    set_property(TEST ${case} APPEND PROPERTY ENVIRONMENT "CTEST_PBS_WALLTIME=${na3km_walltime}")
    set_property(TEST ${case} APPEND PROPERTY ENVIRONMENT "CTEST_PBS_NTASKS=${na3km_ntasks}")
    set_property(TEST ${case} APPEND PROPERTY ENVIRONMENT "CTEST_PBS_NCPUS=128")
    set_property(TEST ${case} APPEND PROPERTY ENVIRONMENT "CTEST_MPIRUN_ARGS=--depth ${na3km_depth}")
    if("${case}" MATCHES "getkf")
      # Same environment as the rrfs-workflow na3km GETKF job
      set(wcoss2_env
          OMP_NUM_THREADS=${na3km_threads}
          OMP_STACKSIZE=500M
          FI_MR_CACHE_MONITOR=memhooks
          FI_MR_CACHE_MAX_COUNT=0
          MPICH_ENV_DISPLAY=1
          MPICH_OFI_STARTUP_CONNECT=1
          MPICH_OFI_VERBOSE=1
          MALLOC_MMAP_THRESHOLD_=1048576
          MALLOC_TRIM_THRESHOLD_=1048576
          "MPICH_MPIIO_HINTS='*.tile1.nc:romio_cb_read=disable,*.sfc_data.nc:romio_cb_read=disable,*.phy_data.nc:romio_cb_read=disable,*.fv_*.res.nc:romio_cb_write=disable,*.sfc_data.nc:romio_cb_write=disable'")
    else()
      set(wcoss2_env
          OMP_NUM_THREADS=${na3km_threads}
          OMP_PLACES=cores
          OMP_PROC_BIND=close
          OMP_STACKSIZE=512M
          MPICH_ALLTOALLV_THROTTLE=484
          FI_MR_CACHE_MONITOR=memhooks
          FI_MR_CACHE_MAX_COUNT=0
          MPICH_OFI_STARTUP_CONNECT=1
          MPICH_OFI_VERBOSE=1
          "MPICH_MPIIO_HINTS='*.tile1.nc:romio_cb_read=disable,...'")
    endif()
    list(JOIN wcoss2_env " " wcoss2_env)
    set_property(TEST ${case} APPEND PROPERTY ENVIRONMENT "CTEST_PBS_ENV=${wcoss2_env}")
  else()
    set(MPI_ARGS "${RESTORE_MPI_ARGS} --time=${na3km_walltime} --exclusive --mem=0 --ntasks-per-node=${na3km_ppn}")
    ecbuild_add_test( TARGET  ${case}
                      MPI     ${na3km_ntasks}
                      WORKING_DIRECTORY ${casedir}
                      ARGS    ${case}.yaml
                      COMMAND ${exe} )
  endif()
  set_property(TEST ${case} PROPERTY ENVIRONMENT_MODIFICATION
               "LD_LIBRARY_PATH=path_list_prepend:${rdasapp_dir}/build/lib64")
  set_property(TEST ${case} PROPERTY LABELS "rrfs-test-na3km")
  # The ctest clock includes time waiting in the queue, so allow far more than the 1500 s default
  set_property(TEST ${case} PROPERTY TIMEOUT 86400)

endforeach()
