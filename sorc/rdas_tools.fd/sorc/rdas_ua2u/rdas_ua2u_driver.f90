  program rdas_ua2u

!=========================================================================
! RDAS_UAUA tool
! authors and history:
!      -- 202102, created by Yonghui Weng
!      -- 202112, added HAVSVI pre- and post-processing by Yonghui Weng
!      -- 202206, added MPI and openMP by Yonghui Weng
!      -- 202306, added vi_cloud by JungHoon Shin
!      -- 202404, added ideal vortex by Weiguo Wang
!      -- 202410, added fftw_increment by JungHoon Shin, Xu Lu and Yonghui Weng
!      -- 202411, added u_update_ua and ideal_vortex by Yonghui Weng
!      -- 202510, donald.e.lippi removed all but u_update_ua adapted for rdas
!------------------------------------------------------------------------------
!
! command convention
!  rdas_ua2u.x FUNCTION --in_grid=input_grids_file \
!                       --in_file=input_file \
!                       --out_file=output_file
!
!    3.6) u_update_ua and ua_update_u
!       * rdas_ua2u.x u_update_ua --in_grid=fv3_grid_spec \
!                                   --in_file=in_analysis_jedi.fv_core.res.nc
!                                   --out_file=out_analysis_jedi.fv_core.res.nc
!
!       * rdas_ua2u.x ua_update_u --in_grid=fv3_grid_spec \
!                                   --in_file=in_analysis_jedi.fv_core.res.nc
!                                   --out_file=out_analysis_jedi.fv_core.res.nc
!
!=========================================================================
  use module_mpi

  implicit none
  integer :: i, j, n
  character(len=2500) :: actions='w', arg, in_grid='w', in_file='w', out_file='w'

  call parallel_start()

  if (iargc() < 2) then
     if (my_proc_id == 0) then
       write(*,'(a)') 'Usage: rdas_ua2u.x <u_update_ua|ua_update_u> --in_grid=GRID.nc --in_file=RESTART.nc [--out_file=OUT.nc]'
     endif
     call parallel_finish()
     stop
  endif

  call getarg(1, actions)
  do i = 2, iargc()
     call getarg(i, arg)
     j = index(trim(arg), '=', .true.);   n = len_trim(arg)
     if (j > 1) then
       select case (arg(1:j-1))
         case ('--in_grid');  in_grid  = arg(j+1:n)
         case ('--in_file','-i'); in_file = arg(j+1:n)
         case ('--out_file'); out_file = arg(j+1:n)
       end select
     end if
  end do

  if (trim(actions) /= 'u_update_ua' .and. trim(actions) /= 'ua_update_u') then
     if (my_proc_id == 0) write(*,'(a)') 'ERROR: action must be u_update_ua or ua_update_u'
     call parallel_finish()
     stop
  end if
  if (trim(in_grid) == 'w' .or. trim(in_file) == 'w') then
     if (my_proc_id == 0) write(*,'(a)') 'ERROR: --in_grid and --in_file are required'
     call parallel_finish()
     stop
  end if

  if (my_proc_id == 0) then
     write(*,'(a)') '--- u/a update on '//trim(in_file)
     call rdas_u_ua(trim(actions), trim(in_grid), trim(in_file), trim(out_file))
  end if

  call parallel_finish()
end program rdas_ua2u
