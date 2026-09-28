!========================================================================================
  subroutine rdas_u_ua(u_ua, in_grid, in_file, out_file, in_anl, remove_anl_vars)

!-----------------------------------------------------------------------------
! HAFS DA tool - u_ua
! authors and history:
!      -- 202411, Yonghui Weng added this subroutine to update ua/va(u/v) with u/v(ua/va) values.
!      -- 202607, added optional in_anl: single-file analysis mode for when
!                 JEDI wrote ua_anl/va_anl (analysis) alongside untouched
!                 background ua/va/u/v in the same file (write-into-existing-files
!                 with renamed fields), so no separate increment file is needed.
!
!-----------------------------------------------------------------------------
! This subroutine updates ua/va(u/v) with u/v(ua/va) values.
! u_ua:    string, "u_update_ua" or "ua_update_u"
!          u_update_ua -- update ua/va with u/v values
!          ua_update_u -- update u/v with ua/va values
! in_grid: domain grid file, grid_spec.nc or grid_mspec.nest02_2024_06_30_18.tile2.nc
! in_file: hafs restart file, usually is 20240630.180000.fv_core.res.tile1.nc or 20240630.180000.fv_core.res.nest02.tile2.nc
! in_anl:  (ua_update_u only) single file containing both the JEDI analysis
!          A-grid wind (ua_anl/va_anl) and the untouched background ua/va/u/v.
!          Mutually exclusive with in_file/out_file. Pass 'w' (or an empty
!          string) to disable.
! remove_anl_vars: (in_anl only) delete ua_anl/va_anl from in_anl once the
!          D-grid analysis has been computed and written, to save space.
!-----------------------------------------------------------------------------

  use constants
  use netcdf
  use module_mpi
  use var_type

  implicit none
  character (len=*), intent(in)         :: u_ua, in_grid, in_file, out_file, in_anl
  logical, intent(in)                   :: remove_anl_vars

  type(grid2d_info)                     :: grid
  real, allocatable, dimension(:,:)     :: cangu, sangu, cangv, sangv
  integer  :: ix, iy, iz, ndims, k, ncid, varid, i, j, rcode, xtype, nvars, nv, dimids(5), vdim(5)
  integer  :: yaxis_1, yaxis_2, xaxis_1, xaxis_2, zaxis_1
  integer  :: yaxis_1id, yaxis_2id, xaxis_1id, xaxis_2id, uid, vid, zaxis_1id, timeid
  integer  :: yaxis_1iv, yaxis_2iv, xaxis_1iv, xaxis_2iv, zaxis_1iv, timeiv
  integer, dimension(nf90_max_var_dims) :: dims
  real, allocatable, dimension(:,:,:,:) :: dat41, dat42, ua, va, u, v, bkg_u, bkg_v, anl_ua, anl_va
  real, allocatable, dimension(:,:)     :: dat21, dat22
  real, allocatable, dimension(:)       :: dat11
  real*8, allocatable, dimension(:,:,:,:) :: ddat4
  logical                                :: apply_to_anl

  character (len=2500)                  :: nc_file
  character(len=nf90_max_name)          :: varname, dimname(4)

  apply_to_anl = ( trim(in_anl) /= 'w' .and. len_trim(in_anl) > 0 )

!------------------------------------------------------------------------------
! 1 --- arg process and parameters

!------------------------------------------------------------------------------
! 2 --- input grid info: read from grid file grid_spec.nc
  call rd_grid_spec_data(trim(in_grid), grid)
  ix=grid%grid_xt
  iy=grid%grid_yt
  allocate( cangu(ix,iy+1),sangu(ix,iy+1),cangv(ix+1,iy),sangv(ix+1,iy) )
  call cal_uv_coeff_fv3(ix, iy, grid%grid_lat, grid%grid_lon, cangu, sangu, cangv, sangv)

!------------------------------------------------------------------------------
! 3 --- updates
  if ( trim(u_ua) == 'u_update_ua' ) then
     !---get u dimensions
     call get_var_dim(trim(in_file), 'u', ndims, dims)
     if ( ndims /= 4 ) then
        write(*,'(a)')' !!!!! warning: please check u dimensions in '//trim(in_file)
        write(*,*)ndims, dims
        stop 1
     endif
     iz=dims(3)
     write(*,*),'dims: ',dims(1:4)
     write(*,'(a,i,a,i,a,i,a,i,a,i)')'u dimensions: ',ix,'=',dims(1),':',iy+1,'=',dims(2),':',iz

     !---get u/v
     allocate(dat41(ix, iy+1, iz,1), dat42(ix+1, iy, iz,1))
     call get_var_data(trim(in_file), 'u', ix, iy+1, iz, 1, dat41)
     call get_var_data(trim(in_file), 'v', ix+1, iy, iz, 1, dat42)

     !---convert u,v from fv3grid to earth
     allocate(dat21(ix, iy+1), dat22(ix+1, iy))
     allocate(ua(ix,iy,iz,1), va(ix,iy,iz,1))
     do k = 1, iz
        call fv3uv2earth(ix, iy, dat41(:,:,k,1), dat42(:,:,k,1), cangu, sangu, cangv, sangv, dat21, dat22)
        !---destage: C-/D- grid to A-grid
        ua(:,:,k,1) = (dat21(:,1:iy)+dat21(:,2:iy+1))/2.0
        va(:,:,k,1) = (dat22(1:ix,:)+dat22(2:ix+1,:))/2.0
     enddo
     deallocate(dat41, dat42, dat21, dat22, cangu, sangu, cangv, sangv)

     !---update in_file
     call update_rdas_restart(trim(in_file), 'ua', ix, iy, iz, 1, ua)
     call update_rdas_restart(trim(in_file), 'va', ix, iy, iz, 1, va)
     deallocate(ua, va)

  else if ( trim(u_ua) == 'ua_update_u' .and. apply_to_anl ) then
     !---================================================================
     !--- single-file analysis mode: in_anl holds BOTH the (renamed) JEDI
     !    analysis A-grid wind (ua_anl/va_anl) and the untouched background
     !    ua/va/u/v, all in the one file (produced by fv3-jedi's
     !    write-into-existing-files + field-rename capability). Compute the
     !    A-grid wind increment as (ua_anl-ua, va_anl-va), convert it to a
     !    D-grid increment the same way the in_file-based mode does, add
     !    that to the background u/v already in the file, and write the
     !    result back in place -- so in_anl becomes the final analysis with
     !    no separate increment/output file needed.
     !---================================================================
     call get_var_dim(trim(in_anl), 'ua', ndims, dims)
     if ( ndims /= 4 ) then
        write(*,'(a)')' !!!!! warning: please check ua dimensions in '//trim(in_anl)
        write(*,*)ndims, dims
        stop 1
     endif
     iz=dims(3)
     write(*,'(a,i,a,i,a,i,a,i,a,i)')'u dimensions: ',ix,'=',dims(1),':',iy,'=',dims(2),':',iz

     !---get background ua/va and analysis ua_anl/va_anl, then form the A-grid increment
     allocate(dat41(ix, iy, iz, 1), dat42(ix, iy, iz, 1))
     allocate(anl_ua(ix, iy, iz, 1), anl_va(ix, iy, iz, 1))
     call get_var_data(trim(in_anl), 'ua', ix, iy, iz, 1, dat41)
     call get_var_data(trim(in_anl), 'va', ix, iy, iz, 1, dat42)
     call get_var_data(trim(in_anl), 'ua_anl', ix, iy, iz, 1, anl_ua)
     call get_var_data(trim(in_anl), 'va_anl', ix, iy, iz, 1, anl_va)
     dat41 = anl_ua - dat41
     dat42 = anl_va - dat42
     deallocate(anl_ua, anl_va)

     !---stage the A-grid wind increment onto the C/D staggered grid
     allocate(ua(ix, iy+1, iz, 1), va(ix+1, iy, iz, 1))
     ua(:,1   ,:,1)=dat41(:,1,:,1)
     ua(:,2:iy,:,1)=0.5*(dat41(:,1:iy-1,:,1)+dat41(:,2:iy,:,1))
     ua(:,iy+1,:,1)=dat41(:,iy,:,1)
     va(1   ,:,:,1)=dat42(1,:,:,1)
     va(2:ix,:,:,1)=0.5*(dat42(1:ix-1,:,:,1)+dat42(2:ix,:,:,1))
     va(ix+1,:,:,1)=dat42(ix,:,:,1)
     deallocate(dat41, dat42)

     !---convert the earth-relative wind increment to the fv3grid (D-grid) wind increment
     allocate(u(ix, iy+1, iz,1), v(ix+1, iy, iz,1))
     do k = 1, iz
        call earthuv2fv3(ix, iy, ua(:,:,k,1), va(:,:,k,1), cangu, sangu, cangv, sangv, u(:,:,k,1), v(:,:,k,1))
     enddo
     deallocate(ua, va, cangu, sangu, cangv, sangv)

     !---add the D-grid increment to the (untouched, background) u/v already in the file
     write(*,'(a)')' --- adding u/v increments to background u/v in '//trim(in_anl)
     allocate(bkg_u(ix, iy+1, iz, 1), bkg_v(ix+1, iy, iz, 1))
     call get_var_data(trim(in_anl), 'u', ix, iy+1, iz, 1, bkg_u)
     call get_var_data(trim(in_anl), 'v', ix+1, iy, iz, 1, bkg_v)
     u = u + bkg_u
     v = v + bkg_v
     deallocate(bkg_u, bkg_v)

     !---write the analysis u/v back into the file in place
     write(*,'(a)')' --- updating u/v in place in '//trim(in_anl)
     call update_rdas_restart(trim(in_anl), 'u', ix, iy+1, iz, 1, u)
     call update_rdas_restart(trim(in_anl), 'v', ix+1, iy, iz, 1, v)
     deallocate(u, v)

     if ( remove_anl_vars ) then
        write(*,'(a)')' --- removing ua_anl/va_anl from '//trim(in_anl)
        call remove_nc_vars(trim(in_anl), 'ua_anl,va_anl')
     endif

  else if ( trim(u_ua) == 'ua_update_u' ) then
     !---get ua dimensions
     call get_var_dim(trim(in_file), 'ua', ndims, dims)
     if ( ndims /= 4 ) then
        write(*,'(a)')' !!!!! warning: please check ua dimensions in '//trim(in_file)
        write(*,*)ndims, dims
        stop 1
     endif
     iz=dims(3)
     write(*,'(a,i,a,i,a,i,a,i,a,i)')'u dimensions: ',ix,'=',dims(1),':',iy,'=',dims(2),':',iz

     !---get ua/va
     allocate(dat41(ix, iy, iz, 1), dat42(ix, iy, iz, 1))
     call get_var_data(trim(in_file), 'ua', ix, iy, iz, 1, dat41)
     call get_var_data(trim(in_file), 'va', ix, iy, iz, 1, dat42)

     !---stage ua/va grid
     allocate(ua(ix, iy+1, iz, 1), va(ix+1, iy, iz, 1))
     ua(:,1   ,:,1)=dat41(:,1,:,1)
     ua(:,2:iy,:,1)=0.5*(dat41(:,1:iy-1,:,1)+dat41(:,2:iy,:,1))
     ua(:,iy+1,:,1)=dat41(:,iy,:,1)
     va(1   ,:,:,1)=dat42(1,:,:,1)
     va(2:ix,:,:,1)=0.5*(dat42(1:ix-1,:,:,1)+dat42(2:ix,:,:,1))
     va(ix+1,:,:,1)=dat42(ix,:,:,1)
     deallocate(dat41, dat42)

     !---convert earth wind to fv3grid wind
     allocate(u(ix, iy+1, iz,1), v(ix+1, iy, iz,1))
     do k = 1, iz
        call earthuv2fv3(ix, iy, ua(:,:,k,1), va(:,:,k,1), cangu, sangu, cangv, sangv, u(:,:,k,1), v(:,:,k,1))
     enddo
     deallocate(ua, va, cangu, sangu, cangv, sangv)

     call nccheck(nf90_open(trim(in_file), nf90_nowrite, ncid), 'wrong in open '//trim(in_file), .true.)
     !---get ua xtype from input_file
     xtype=nf90_real
     call nccheck(nf90_inq_varid(ncid, "ua", varid), 'wrong in nf90_inq_varid ua id', .false.)
     call nccheck(nf90_inquire_variable(ncid, varid, xtype=xtype), 'wrong in nf90_inquire_variable xtype', .false.)

     !---update or generate a new file
     rcode=nf90_inq_varid(ncid, 'u', varid)
     call nccheck(nf90_close(ncid), 'wrong in close '//trim(in_file), .false.)
     if ( rcode == nf90_noerr ) then
        !---if u/v exist, update u/v
        call update_rdas_restart(trim(in_file), 'u', ix, iy+1, iz, 1, u)
        call update_rdas_restart(trim(in_file), 'v', ix+1, iy, iz, 1, v)
        deallocate(u, v)

     else  !---generate a new file
        !---create file
        if ( trim(out_file) == 'w' .or. len_trim(out_file) < 1 ) then
           write(*,'(a)')' !!!!! error: --in_file has no u/v to update in place, and --out_file was not given'
           write(*,'(a)')'             specify --out_file (to write raw increments)'
           stop 1
        else
           nc_file=trim(out_file)
        endif
        !--- delete nc_file if it exist
        open(unit=1234, iostat=rcode, file=trim(nc_file), status='old')
        if (rcode == 0) close(1234, status='delete')
        !call nccheck(nf90_create(trim(nc_file), nf90_hdf5, ncid), 'wrong in creat '//trim(nc_file), .true.)
        call nccheck(nf90_create(trim(nc_file), nf90_netcdf4, ncid), 'wrong in creat '//trim(nc_file), .true.)

        !---define dimension
        call nccheck(nf90_def_dim(ncid, 'xaxis_1', ix  , xaxis_1id), 'wrong in def_dim xaxis_1', .true.)
        call nccheck(nf90_def_dim(ncid, 'xaxis_2', ix+1, xaxis_2id), 'wrong in def_dim xaxis_2', .true.)
        call nccheck(nf90_def_dim(ncid, 'yaxis_1', iy+1, yaxis_1id), 'wrong in def_dim yaxis_1', .true.)
        call nccheck(nf90_def_dim(ncid, 'yaxis_2', iy  , yaxis_2id), 'wrong in def_dim yaxis_2', .true.)
        call nccheck(nf90_def_dim(ncid, 'zaxis_1', iz  , zaxis_1id), 'wrong in def_dim zaxis_1', .true.)
        call nccheck(nf90_def_dim(ncid, 'Time',    1   , timeid   ), 'wrong in def_dim Time   ', .true.)


        !---define variables dimensions and u/v
        call nccheck(nf90_def_var(ncid, 'xaxis_1',  xtype, (/xaxis_1id/), xaxis_1iv), 'wrong in def_var xaxis_1', .true.)
        !rcode=nf90_def_var(ncid, 'xaxis_1',  xtype, (/xaxis_1id/), xaxis_1iv)
        call nccheck(nf90_def_var(ncid, 'xaxis_2',  xtype, (/xaxis_2id/), xaxis_2iv), 'wrong in def_var xaxis_2', .true.)
        call nccheck(nf90_def_var(ncid, 'yaxis_1',  xtype, (/yaxis_1id/), yaxis_1iv), 'wrong in def_var yaxis_1', .true.)
        call nccheck(nf90_def_var(ncid, 'yaxis_2',  xtype, (/yaxis_2id/), yaxis_2iv), 'wrong in def_var yaxis_2', .true.)
        call nccheck(nf90_def_var(ncid, 'zaxis_1',  xtype, (/zaxis_1id/), zaxis_1iv), 'wrong in def_var zaxis_1', .true.)
        call nccheck(nf90_def_var(ncid, 'Time',     xtype, (/timeid/),    timeiv),    'wrong in def_var Time'   , .true.)
        call nccheck(nf90_def_var(ncid, 'u',        xtype, (/xaxis_1id,yaxis_1id,zaxis_1id,timeid/), uid), 'wrong in def_var u', .true.)
        call nccheck(nf90_def_var(ncid, 'v',        xtype, (/xaxis_2id,yaxis_2id,zaxis_1id,timeid/), vid), 'wrong in def_var v', .true.)
        call nccheck(nf90_enddef(ncid), 'wrong in nf90_enddef', .false.)

        !---write variables dimensions and u/v
        allocate(dat11(ix))
        do i = 1, ix; dat11(i)=i*1.0; enddo
        call nccheck(nf90_put_var(ncid, xaxis_1iv, dat11), 'wrong in write xaxis_1', .true.)
        deallocate(dat11)

        allocate(dat11(ix+1))
        do i = 1, ix+1; dat11(i)=i*1.0; enddo
        call nccheck(nf90_put_var(ncid, xaxis_2iv, dat11), 'wrong in write xaxis_2', .true.)
        deallocate(dat11)

        allocate(dat11(iy+1))
        do i = 1, iy+1; dat11(i)=i*1.0; enddo
        call nccheck(nf90_put_var(ncid, yaxis_1iv, dat11), 'wrong in write yaxis_1', .true.)
        deallocate(dat11)

        allocate(dat11(iy))
        do i = 1, iy; dat11(i)=i*1.0; enddo
        call nccheck(nf90_put_var(ncid, yaxis_2iv, dat11), 'wrong in write yaxis_2', .true.)
        deallocate(dat11)

        allocate(dat11(iz))
        do i = 1, iz; dat11(i)=i*1.0; enddo
        call nccheck(nf90_put_var(ncid, zaxis_1iv, dat11), 'wrong in write zaxis_1', .true.)
        deallocate(dat11)

        call nccheck(nf90_put_var(ncid, timeiv, 1.0), 'wrong in write Time', .true.)

        call nccheck(nf90_put_var(ncid, uid, u), 'wrong in write u', .true.)
        call nccheck(nf90_put_var(ncid, vid, v), 'wrong in write v', .true.)
        deallocate(u,v)

        !---copy other variables
        call nccheck(nf90_open(trim(in_file), nf90_nowrite, ncid), 'wrong in open '//trim(in_file), .true.)
        call nccheck(nf90_inquire(ncid, ndims, nvars), 'wrong in inquire ncid', .true.)
        do_input_var_loop: do nv=1, nvars
           dimids=1; vdim=1
           call nccheck(nf90_inquire_variable(ncid,nv,varname,xtype,ndims,dimids), 'wrong in inquire_variable '//trim(varname), .false.)
           do i = 1, ndims
              call nccheck(nf90_inquire_dimension(ncid,dimids(i), len=vdim(i)), 'wrong in inquire '//trim(varname)//' dim', .false.)
           enddo

           !---skip xaxis_1(xaxis_1), yaxis_1(yaxis_1), zaxis_1(zaxis_1)
           if ( ndims < 3 ) cycle do_input_var_loop

           call nccheck(nf90_inq_varid(ncid, trim(varname), varid), 'wrong in inquire '//trim(varname)//' varid', .false.)
           allocate(dat41(vdim(1),vdim(2),vdim(3),vdim(4)))
           if ( xtype == nf90_float .or. xtype == nf90_real .or. xtype == nf90_real4 ) then
              call nccheck(nf90_get_var(ncid, varid, dat41), 'wrong in get '//trim(varname), .true.)
           else if ( xtype == nf90_double .or. xtype == nf90_real8 ) then
              allocate(ddat4(vdim(1),vdim(2),vdim(3),vdim(4)))
              call nccheck(nf90_get_var(ncid, varid, ddat4), 'wrong in get '//trim(varname), .true.)
              dat41=real(ddat4)
              deallocate(ddat4)
           else
              write(*,*)' !!!! please add ',xtype,' xtype data here '
              stop 1
           endif

           !---write out
           dimname(1)='xaxis_1'
           dimname(2)='yaxis_2'
           if ( vdim(1) == ix+1 ) dimname(1)='xaxis_2'
           if ( vdim(2) == iy+1 ) dimname(2)='yaxis_1'
           if ( ndims == 3 ) then   !
              dimname(3)='Time'
              dimname(4)='-'
              write(*,'(a)')' --- writing '//trim(varname)//'('//trim(dimname(1))//','//trim(dimname(2))//','//trim(dimname(3))//')'
              call write_nc_real(trim(nc_file), trim(varname), vdim(1),vdim(2),vdim(3), -1, trim(dimname(1)), trim(dimname(2)), trim(dimname(3)), trim(dimname(4)), dat41, '-', '-')
           else if ( ndims == 4 ) then   !
              dimname(3)='zaxis_1'
              dimname(4)='Time'
              write(*,'(a)')' --- writing '//trim(varname)//'('//trim(dimname(1))//','//trim(dimname(2))//','//trim(dimname(3))//','//trim(dimname(4))//')'
              call write_nc_real(trim(nc_file), trim(varname), vdim(1),vdim(2),vdim(3),vdim(4),trim(dimname(1)), trim(dimname(2)), trim(dimname(3)), trim(dimname(4)), dat41, '-', '-')
           endif
           deallocate(dat41)

        enddo do_input_var_loop

     endif

  endif

  return
  end subroutine rdas_u_ua

!========================================================================================
