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
!                       (--out_file=output_file | --in_bkg=background_file)
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
!    3.7) ua_update_u has three mutually exclusive input/output modes --
!         specify exactly one of --out_file, --in_bkg, or --in_anl:
!         a) --out_file: write the raw computed u/v D-grid wind increments to
!            out_file (original behavior).
!         b) --in_bkg: add the computed u/v increments directly to the u/v
!            fields of the background file and update that file in place --
!            i.e. rdas_ua2u.x applies the wind increments to the background,
!            replacing the NCO-based apply_jedi_incs.sh step for u/v. Only
!            u/v are affected; all other variables are untouched.
!       * rdas_ua2u.x ua_update_u --in_grid=fv3_grid_spec \
!                                   --in_file=agrid_inc_jedi.fv_core.res.nc \
!                                   --in_bkg=fv_core.res.tile1.nc
!
!         c) --in_anl: single-file mode. Used when JEDI wrote the analysis
!            directly into the background file with write-into-existing-files,
!            aliasing the analyzed A-grid wind to ua_anl/va_anl so the
!            original background ua/va (and u/v) are left untouched in the
!            same file. This mode needs no separate --in_file: it computes
!            the A-grid wind increment as (ua_anl-ua, va_anl-va) from in_anl
!            itself, converts it to a D-grid increment, adds it to the
!            background u/v already in in_anl, and writes the result back
!            into in_anl in place -- so in_anl goes from "background with an
!            aliased analysis wind" to "final analysis" with no other file
!            needed. Optionally pass --remove_anl_winds to delete ua_anl/va_anl
!            from in_anl afterwards (via NCO's ncks) once they are no longer
!            needed, to save space.
!       * rdas_ua2u.x ua_update_u --in_grid=fv3_grid_spec \
!                                   --in_anl=fv_core.res.tile1.nc \
!                                   [--remove_anl_winds]
!
!=========================================================================
  use module_mpi

  implicit none
  integer :: i, j, n
  character(len=2500) :: actions='w', arg, in_grid='w', in_file='w', out_file='w', in_bkg='w', in_anl='w'
  logical :: remove_anl_vars = .false.

  call parallel_start()

  if (iargc() < 2) then
     if (my_proc_id == 0) then
       write(*,'(a)') 'Usage: rdas_ua2u.x <u_update_ua|ua_update_u> --in_grid=GRID.nc --in_file=RESTART.nc [--out_file=OUT.nc] [--in_bkg=BKG.nc]'
       write(*,'(a)') '   or: rdas_ua2u.x ua_update_u --in_grid=GRID.nc --in_anl=ANALYSIS.nc [--remove_anl_winds]'
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
         case ('--in_bkg');   in_bkg   = arg(j+1:n)
         case ('--in_anl');   in_anl   = arg(j+1:n)
       end select
     else if (trim(arg) == '--remove_anl_winds') then
       remove_anl_vars = .true.
     end if
  end do

  if (trim(actions) /= 'u_update_ua' .and. trim(actions) /= 'ua_update_u') then
     if (my_proc_id == 0) write(*,'(a)') 'ERROR: action must be u_update_ua or ua_update_u'
     call parallel_finish()
     stop
  end if
  if (trim(in_grid) == 'w') then
     if (my_proc_id == 0) write(*,'(a)') 'ERROR: --in_grid is required'
     call parallel_finish()
     stop
  end if

  if (trim(in_anl) /= 'w') then
     !--- single-file analysis mode: only valid for ua_update_u, and mutually
     !    exclusive with the --in_file-based modes.
     if (trim(actions) /= 'ua_update_u') then
        if (my_proc_id == 0) write(*,'(a)') 'ERROR: --in_anl is only supported with ua_update_u'
        call parallel_finish()
        stop
     end if
     if (trim(in_file) /= 'w' .or. trim(out_file) /= 'w' .or. trim(in_bkg) /= 'w') then
        if (my_proc_id == 0) write(*,'(a)') 'ERROR: --in_anl cannot be combined with --in_file, --out_file, or --in_bkg'
        call parallel_finish()
        stop
     end if
  else
     if (remove_anl_vars) then
        if (my_proc_id == 0) write(*,'(a)') 'ERROR: --remove_anl_winds is only supported with --in_anl'
        call parallel_finish()
        stop
     end if
     if (trim(in_file) == 'w') then
        if (my_proc_id == 0) write(*,'(a)') 'ERROR: --in_file is required unless --in_anl is given'
        call parallel_finish()
        stop
     end if
     if (trim(in_bkg) /= 'w' .and. trim(actions) /= 'ua_update_u') then
        if (my_proc_id == 0) write(*,'(a)') 'ERROR: --in_bkg is only supported with ua_update_u'
        call parallel_finish()
        stop
     end if
     if (trim(actions) == 'ua_update_u') then
        if (trim(out_file) /= 'w' .and. trim(in_bkg) /= 'w') then
           if (my_proc_id == 0) write(*,'(a)') 'ERROR: specify exactly one of --out_file or --in_bkg, not both'
           call parallel_finish()
           stop
        end if
        if (trim(out_file) == 'w' .and. trim(in_bkg) == 'w') then
           if (my_proc_id == 0) write(*,'(a)') 'ERROR: ua_update_u requires exactly one of --out_file (write raw increments), --in_bkg (apply increments to background), or --in_anl (single-file analysis mode)'
           call parallel_finish()
           stop
        end if
     end if
  end if

  if (my_proc_id == 0) then
     if (trim(in_anl) /= 'w') then
        write(*,'(a)') '--- computing wind analysis in place from '//trim(in_anl)
     else
        write(*,'(a)') '--- u/a update on '//trim(in_file)
        if (trim(in_bkg) /= 'w') write(*,'(a)') '--- applying u/v increments to background '//trim(in_bkg)
     end if
     call rdas_u_ua(trim(actions), trim(in_grid), trim(in_file), trim(out_file), trim(in_bkg), trim(in_anl), remove_anl_vars)
  end if

  call parallel_finish()
end program rdas_ua2u
