PROGRAM NEXRAD_SO_MAIN
    USE NEXRAD_COMMON
    USE NEXRAD_BUFR
    USE netcdf
    IMPLICIT NONE

    INTEGER, PARAMETER :: path_len = 1024
    CHARACTER(len=path_len) :: bfrin_filename, grid_filename
    CHARACTER(len=path_len) :: ncso_filename, nml_filename
    CHARACTER(len=120) :: clean_filtered_txt, bfrtbl_filename
    CHARACTER(len=120) :: decoded_txt

    INTEGER :: cmd_count, nml_unit, iost, debug_level, i
    CHARACTER(LEN=10) :: cycletime
    INTEGER :: ref_year, ref_month, ref_day, ref_hour

    REAL(8)    :: del_azimuth, del_elev, del_range, del_time, elev_angle_max, range_max
    LOGICAL    :: l2superob_only
    INTEGER    :: minnum

    INTEGER, PARAMETER :: max_whitelist = 150
    CHARACTER(len=4), DIMENSION(max_whitelist) :: station_whitelist
    INTEGER :: num_allowed

    ! --- radar-site-from-bufr variables ---
    INTEGER, PARAMETER :: max_bufr_sites = 150

    ! model grid info
    INTEGER :: nx_grid, ny_grid
    REAL(4), ALLOCATABLE, DIMENSION(:,:) :: grid_lon2d, grid_lat2d
    INTEGER :: ncid, lon_varid, lat_varid, status, lon_dimid, lat_dimid

    CHARACTER(len=4), DIMENSION(max_bufr_sites) :: bufr_site_ids
    REAL(8), DIMENSION(max_bufr_sites) :: bufr_site_lat, bufr_site_lon, bufr_site_hgt
    REAL(8), DIMENSION(max_bufr_sites) :: active_lats, active_lons, active_hgts
    INTEGER :: num_bufr_sites

    REAL(8) :: radar_range_km, min_dist_km
    LOGICAL :: site_inside, in_whitelist
    INTEGER :: num_active
    CHARACTER(len=4), DIMENSION(max_bufr_sites) :: active_stations

    ! --- TIMING VARIABLES ---
    INTEGER(8) :: tick_rate, tick_start, tick_end, total_start
    REAL(8)    :: t_namelist, t_netcdf, t_scan, t_filter, t_decode

    NAMELIST /DEBUG_CFG/ debug_level
    NAMELIST /ANALYSIS_TIME/ cycletime
    NAMELIST /SUPEROB_PARAMS/ del_azimuth, del_elev, del_range, del_time, &
                             elev_angle_max, range_max, l2superob_only, &
                             radar_sites, radar_box, radar_rmesh, radar_zmesh, &
                             minnum, station_whitelist

    ! Initialize clock rate and start total timer
    CALL SYSTEM_CLOCK(COUNT_RATE=tick_rate)
    CALL SYSTEM_CLOCK(COUNT=total_start)

    bfrtbl_filename    = "nexrad.tbl"
    clean_filtered_txt = "superob_radar.txt"
    nml_unit           = 71

    WRITE(6,*) '========================================='
    WRITE(6,*) ' NEXRAD GSI RADIAL WIND PREPROCESSOR     '
    WRITE(6,*) '========================================='

    cmd_count = command_argument_count()
    IF (cmd_count /= 4) then
        WRITE(6,*) 'ERROR: Expected four command-line arguments.'
        WRITE(6,*) 'Usage: ./rdas_nexrad_superob.x <input BUFR> <FV3 grid> <output IODA> <namelist>'
        STOP 1
    END IF

    CALL get_command_argument(1, bfrin_filename)
    CALL get_command_argument(2, grid_filename)
    CALL get_command_argument(3, ncso_filename)
    CALL get_command_argument(4, nml_filename)

    WRITE(6,*) ' -> Input BUFR:  ', TRIM(bfrin_filename)
    WRITE(6,*) ' -> FV3 grid:    ', TRIM(grid_filename)
    WRITE(6,*) ' -> Output IODA: ', TRIM(ncso_filename)
    WRITE(6,*) ' -> Namelist:    ', TRIM(nml_filename)

    ! Set operational baseline parameters fallback
    debug_level = 1
    cycletime = '2024092412'
    del_azimuth = 5.0; del_elev = 0.25; del_range = 5000.0; del_time = 1.0
    elev_angle_max = 5.0; range_max = 200000.0; l2superob_only = .FALSE.
    radar_sites = .FALSE.; radar_box = .TRUE.; radar_rmesh = 10.0; radar_zmesh = 500.0
    minnum = 1
    station_whitelist = 'ZZZZ'

    ! --- TIMING BLOCK 1: I/O Namelist ---
    CALL SYSTEM_CLOCK(COUNT=tick_start)

    CALL check_file_missing('main', nml_filename)
    OPEN(UNIT=nml_unit, FILE=TRIM(nml_filename), STATUS='old', IOSTAT=iost)
    READ(nml_unit, NML=DEBUG_CFG, IOSTAT=iost)
    REWIND(nml_unit)
    READ(nml_unit, NML=ANALYSIS_TIME, IOSTAT=iost)
    REWIND(nml_unit)
    READ(nml_unit, NML=SUPEROB_PARAMS, IOSTAT=iost)
    CLOSE(nml_unit)

    CALL SYSTEM_CLOCK(COUNT=tick_end)
    t_namelist = REAL(tick_end - tick_start, 8) / REAL(tick_rate, 8)

    !Parse cycletime string (YYYYMMDDHH) into integers
    READ(cycletime(1:4), '(I4)') ref_year
    READ(cycletime(5:6), '(I2)') ref_month
    READ(cycletime(7:8), '(I2)') ref_day
    READ(cycletime(9:10), '(I2)') ref_hour

    WRITE(6,*) ' -> Cycle Time: ', cycletime, ' | Window: +/-', del_time, ' hrs'

    ! Pre-adjust the whitelist here to keep the loop fast!
    num_allowed = 0
    do i = 1, max_whitelist
        if (station_whitelist(i) /= 'ZZZZ') THEN
            num_allowed = num_allowed + 1
            station_whitelist(i) = ADJUSTL(station_whitelist(i))
        END IF
    end do

    WRITE(6,*) ' -> Whitelist digested. Active Stations loaded: ', num_allowed

    CALL get_bufr_tbl(bfrin_filename, bfrtbl_filename)
    CALL check_delete_existing('main', ncso_filename)

    ! --- TIMING BLOCK 2: NetCDF Grid Read ---
    CALL SYSTEM_CLOCK(COUNT=tick_start)

    CALL check_file_missing('main', grid_filename)

    status = nf90_open(TRIM(grid_filename), NF90_NOWRITE, ncid)
    CALL check_netcdf_status(status, 'opening FV3 grid file')

    ! Use the FV3 T-cell center grid, which matches the model state grid.
    status = nf90_inq_dimid(ncid, 'grid_xt', lon_dimid)
    CALL check_netcdf_status(status, 'finding grid_xt dimension')

    status = nf90_inquire_dimension(ncid, lon_dimid, len=nx_grid)
    CALL check_netcdf_status(status, 'reading grid_xt dimension')

    status = nf90_inq_dimid(ncid, 'grid_yt', lat_dimid)
    CALL check_netcdf_status(status, 'finding grid_yt dimension')

    status = nf90_inquire_dimension(ncid, lat_dimid, len=ny_grid)
    CALL check_netcdf_status(status, 'reading grid_yt dimension')

    WRITE(6,'(A,I0,A,I0)') ' -> Detected FV3 T-cell grid size: ', nx_grid, ' x ', ny_grid

    ALLOCATE(grid_lon2d(nx_grid, ny_grid))
    ALLOCATE(grid_lat2d(nx_grid, ny_grid))

    status = nf90_inq_varid(ncid, 'grid_lont', lon_varid)
    CALL check_netcdf_status(status, 'finding grid_lont variable')

    status = nf90_get_var(ncid, lon_varid, grid_lon2d)
    CALL check_netcdf_status(status, 'reading grid_lont variable')

    status = nf90_inq_varid(ncid, 'grid_latt', lat_varid)
    CALL check_netcdf_status(status, 'finding grid_latt variable')

    status = nf90_get_var(ncid, lat_varid, grid_lat2d)
    CALL check_netcdf_status(status, 'reading grid_latt variable')

    status = nf90_close(ncid)
    CALL check_netcdf_status(status, 'closing FV3 grid file')

    CALL SYSTEM_CLOCK(COUNT=tick_end)
    t_netcdf = REAL(tick_end - tick_start, 8) / REAL(tick_rate, 8)

    radar_range_km = range_max / 1000.0_8   ! 200.0 km from namelist

    ! --- TIMING BLOCK 3: Scan BUFR for Sites ---
    CALL SYSTEM_CLOCK(COUNT=tick_start)

    WRITE(6,*) ' -> Scanning BUFR file for radar site locations...'
    CALL get_radar_sites_from_bufr(bfrin_filename, max_bufr_sites, &
                                    bufr_site_ids, bufr_site_lat, bufr_site_lon, &
                                    bufr_site_hgt, num_bufr_sites)
    WRITE(6,'(A,I4,A)') '    Found ', num_bufr_sites, ' unique radar sites in BUFR file.'

    CALL SYSTEM_CLOCK(COUNT=tick_end)
    t_scan = REAL(tick_end - tick_start, 8) / REAL(tick_rate, 8)

    ! --- TIMING BLOCK 4: Domain & Range Filtering Loop ---
    CALL SYSTEM_CLOCK(COUNT=tick_start)

    num_active = 0
    IF (radar_sites) THEN
        ! USE the whitelist from namelist
        DO i = 1, num_bufr_sites

            in_whitelist = .FALSE.
            IF (num_allowed > 0) THEN
                CALL check_in_whitelist(bufr_site_ids(i), station_whitelist, &
                                         max_whitelist, in_whitelist)
                IF (.NOT. in_whitelist) THEN
                    CYCLE
                END IF
            END IF

            CALL check_radar_in_range(bufr_site_lat(i), bufr_site_lon(i), &
                                       grid_lon2d, grid_lat2d, &
                                       nx_grid, ny_grid, radar_range_km, &
                                       site_inside, min_dist_km)

            IF (.NOT. site_inside) CYCLE

            num_active = num_active + 1
            active_stations(num_active) = bufr_site_ids(i)
            active_lats(num_active) = bufr_site_lat(i)
            active_lons(num_active) = bufr_site_lon(i)
            active_hgts(num_active) = bufr_site_hgt(i)
        END DO
    ELSE
        ! Process all the radar founds in file
        DO i = 1, num_bufr_sites
            CALL check_radar_in_range(bufr_site_lat(i), bufr_site_lon(i), &
                                       grid_lon2d, grid_lat2d, &
                                       nx_grid, ny_grid, radar_range_km, &
                                       site_inside, min_dist_km)

            IF (.NOT. site_inside) CYCLE

            num_active = num_active + 1
            active_stations(num_active) = bufr_site_ids(i)
            active_lats(num_active)     = bufr_site_lat(i)
            active_lons(num_active)     = bufr_site_lon(i)
            active_hgts(num_active)     = bufr_site_hgt(i)
        END DO
    END IF

    WRITE(6,'(A,I0)') ' -> Radar sites retained for processing: ', num_active

    IF (num_active <= 0) THEN
        WRITE(6,*) 'ERROR: No radar sites are within range of the FV3 domain.'
        STOP 3
    END IF

    CALL SYSTEM_CLOCK(COUNT=tick_end)
    t_filter = REAL(tick_end - tick_start, 8) / REAL(tick_rate, 8)

    ! --- TIMING BLOCK 5: Main Decoding and Superobing ---
    CALL SYSTEM_CLOCK(COUNT=tick_start)

    CALL radar_bufr_read_all(bfrin_filename, ncso_filename, active_stations, &
                             num_active, ref_year, ref_month, ref_day, ref_hour, &
                             del_azimuth, del_elev, del_range, del_time, &
                             elev_angle_max, range_max, minnum, &
                             active_lats, active_lons, active_hgts)

    CALL SYSTEM_CLOCK(COUNT=tick_end)
    t_decode = REAL(tick_end - tick_start, 8) / REAL(tick_rate, 8)

    ! --- PRINT PROFILING RESULTS ---
    WRITE(6,*) ' '
    WRITE(6,*) '========================================='
    WRITE(6,*) ' EXECUTION TIME PROFILING (Seconds)      '
    WRITE(6,*) '========================================='
    WRITE(6,'(A,F10.4)') ' Namelist Load:    ', t_namelist
    WRITE(6,'(A,F10.4)') ' NetCDF Grid Read: ', t_netcdf
    WRITE(6,'(A,F10.4)') ' BUFR Site Scan:   ', t_scan
    WRITE(6,'(A,F10.4)') ' Range/Domain Loop:', t_filter
    WRITE(6,'(A,F10.4)') ' Superob Decoding: ', t_decode
    CALL SYSTEM_CLOCK(COUNT=tick_end)
    WRITE(6,'(A,F10.4)') ' TOTAL RUNTIME:    ', REAL(tick_end - total_start, 8) / REAL(tick_rate, 8)
    WRITE(6,*) '========================================='

    IF (ALLOCATED(grid_lon2d)) DEALLOCATE(grid_lon2d)
    IF (ALLOCATED(grid_lat2d)) DEALLOCATE(grid_lat2d)
CONTAINS

    ! Check a NetCDF operation and stop with the library error message.
    SUBROUTINE check_netcdf_status(nc_status, operation)
        INTEGER, INTENT(IN) :: nc_status
        CHARACTER(len=*), INTENT(IN) :: operation

        IF (nc_status /= NF90_NOERR) THEN
            WRITE(6,'(A)') 'ERROR: NetCDF failure while ' // TRIM(operation)
            WRITE(6,'(A)') '       ' // TRIM(nf90_strerror(nc_status))
            STOP 2
        END IF
    END SUBROUTINE check_netcdf_status

    SUBROUTINE check_in_whitelist(stn_id, whitelist, num_wl, found)
        CHARACTER(len=4), INTENT(IN) :: stn_id
        INTEGER, INTENT(IN) :: num_wl
        CHARACTER(len=4), DIMENSION(num_wl), INTENT(IN) :: whitelist
        LOGICAL, INTENT(OUT) :: found
        INTEGER :: j
        CHARACTER(len=4) :: adj_stn_id

        found = .FALSE.
        adj_stn_id = ADJUSTL(stn_id)

        DO j = 1, num_wl
            IF (whitelist(j) == adj_stn_id) THEN
                found = .TRUE.
                EXIT
            END IF
        END DO
    END SUBROUTINE check_in_whitelist

END PROGRAM NEXRAD_SO_MAIN
