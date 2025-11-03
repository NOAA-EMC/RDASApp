module mg_timers
!$$$  submodule documentation block
!                .      .    .                                       .
! module:   mg_timers
!   prgmmr: jovic            org:                     date: 2017
!
! abstract:  Measure cpu and wallclock timing
!
! module history log:
!   2020        rancic  - adjusted
!   2023-04-19  lei     - object-oriented coding
!   2024-01-11  rancic  - optimization for ensemble localization
!   2024-02-20  yokota  - refactoring to apply for GSI
!
! Subroutines Included:
!   btim -
!   etim -
!   print_mg_timers -
!
! Functions Included:
!
! remarks:
!
! attributes:
!   language: f90
!   machine:
!
!$$$ end documentation block

  use mpi
  use mgbf_kinds, only: r_kind,i_kind
  implicit none

  private

  public :: btim, etim, print_mg_timers

  type timer
    logical :: running = .false.
    real(r_kind) :: start_clock = 0.0
    real(r_kind) :: start_cpu = 0.0
    real(r_kind) :: time_clock = 0.0
    real(r_kind) :: time_cpu = 0.0
    integer(i_kind) :: icount = 0
  end type timer

  type(timer),save,public ::      total_tim
  type(timer),save,public ::       init_tim
  type(timer),save,public ::     output_tim
  type(timer),save,public ::   dynamics_tim
  type(timer),save,public ::    upsend_tim
  type(timer),save,public ::    upsend1_tim
  type(timer),save,public ::    upsend2_tim
  type(timer),save,public ::    upsend3_tim
  type(timer),save,public ::    an2filt_tim
  type(timer),save,public ::    filt2an_tim
  type(timer),save,public ::    weight_tim
  type(timer),save,public ::    hfiltT_tim
  type(timer),save,public ::    vfiltT_tim
  type(timer),save,public ::      vadv1_tim
  type(timer),save,public ::      bfilt_tim
  type(timer),save,public ::      hfilt_tim
  type(timer),save,public ::      vfilt_tim
  type(timer),save,public ::       adv2_tim
  type(timer),save,public ::       vtoa_tim
  type(timer),save,public ::    dnsend_tim
  type(timer),save,public ::    dnsend1_tim
  type(timer),save,public ::    dnsend2_tim
  type(timer),save,public ::    dnsend3_tim
  type(timer),save,public ::     update_tim
  type(timer),save,public ::    physics_tim
  type(timer),save,public ::  radiation_tim
  type(timer),save,public :: convection_tim
  type(timer),save,public :: turbulence_tim
  type(timer),save,public ::  microphys_tim
  type(timer),save,public ::       pack_tim
  type(timer),save,public ::       arrn_tim
  type(timer),save,public ::      aintp_tim
  type(timer),save,public ::       intp_tim
  type(timer),save,public ::      bocoT_tim
  type(timer),save,public ::       boco_tim
  type(timer),save,public ::    bfiltT_tim
  type(timer),save,public ::     mg_multiply_time
  type(timer),save,public ::     mg_interface_multiply_time 
  type(timer),save,public ::     mg_interface_registry_get_time 
  type(timer),save,public ::     mg_interface_fldset_time 
  type(timer),save,public ::     mg_preprocess_time
  type(timer),save,public ::     mg_postprocess_time
  type(timer),save,public ::     mg_anal_to_filt_time
  type(timer),save,public ::     mg_filt_to_anal_time
  type(timer),save,public ::     mg_filtering_time

  integer, parameter, public :: print_clock = 1,                        &
                                print_cpu   = 2,                        &
                                print_clock_pct = 3,                    &
                                print_cpu_pct   = 4

contains

!-----------------------------------------------------------------------
  subroutine btim(t)
    implicit none
    type(timer), intent(inout) :: t

    if (.not.t%running) then
     t%time_clock = 0
     t%time_cpu = 0
     t%icount=0
!     write(0,*)'btim: timer is already running'
!     STOP
    end if
    t%running = .true.

    t%start_clock = wtime()
    t%start_cpu = ctime()

  endsubroutine btim
!-----------------------------------------------------------------------
  subroutine etim(t)
    implicit none
    type(timer), intent(inout) :: t
    real(r_kind) :: wt, ct

    wt = wtime()
    ct = ctime()

    if (.not.t%running) then
      write(6,*)'etim: timer is not running'
      call flush(6)
      STOP
    end if
!clt    t%running = .true.

    t%time_clock = t%time_clock + (wt - t%start_clock)

    t%time_cpu = t%time_cpu + (ct - t%start_cpu)
    t%icount = t%icount+1
!clt noneed    t%start_clock = 0.0
!clt noneed    t%start_cpu = 0.0


  endsubroutine etim
!-----------------------------------------------------------------------
  subroutine print_mg_timers(filename, print_type,mype)
    use mpi
    implicit none
    integer(i_kind),intent(in):: mype

    character(len=*), intent(in) :: filename
    integer, intent(in) :: print_type

    integer :: fh
    integer :: ierr
    integer(kind=MPI_OFFSET_KIND) :: disp
    integer, dimension(MPI_STATUS_SIZE) :: stat
!    character(len=1024) :: header
    character(len=2048) :: header1,header2
    character(len=2048) :: buffer1,buffer2,buffer3,buffer4
!    integer :: bufsize
    integer :: bufsize1,bufsize2,bufsize3,bufsize4
    integer(i_kind):: num_ranks
    call MPI_Comm_size(MPI_COMM_WORLD, num_ranks, ierr)
    call MPI_File_open(MPI_COMM_WORLD, filename, &
                       MPI_MODE_WRONLY + MPI_MODE_CREATE, &
                       MPI_INFO_NULL, fh, ierr)

!clt    buffer = ' '
       buffer1=' '; buffer2=' ';buffer3=' ';buffer4=' '
!cltj#    if ( print_type == print_clock ) then
!    write(6,*)'thinkdebxxx icound is ',mg_interface_multiply_time%icount
    write(buffer1,"(I6,25(',',F10.4),',',I10)") mype,                            &
                                       init_tim%time_clock,             &
                                       upsend_tim%time_clock,           &
                                       dnsend_tim%time_clock,           &
                                       weight_tim%time_clock,           &
                                       hfiltT_tim%time_clock,           &
                                       hfilt_tim%time_clock,            &
                                       vfiltT_tim%time_clock,           &
                                       vfilt_tim%time_clock,           &
                                       bocoT_tim%time_clock,           &
                                       boco_tim%time_clock,           &
  
                                       filt2an_tim%time_clock,          &
                                       aintp_tim%time_clock,            &
                                       intp_tim%time_clock,             &
                                       an2filt_tim%time_clock,          &
                                       output_tim%time_clock,           &
                                       total_tim%time_clock,            &
                                       mg_multiply_time%time_clock ,  &
                                  mg_interface_multiply_time%time_clock,& 
                                  mg_interface_registry_get_time%time_clock,& 
                                  mg_interface_fldset_time%time_clock,& 
                                       mg_preprocess_time%time_clock ,  &
                                       mg_anal_to_filt_time%time_clock,   &
                                       mg_filtering_time%time_clock,   &
                                       mg_filt_to_anal_time%time_clock,   &
                                       mg_postprocess_time%time_clock  , &
                                  mg_interface_multiply_time%icount 
    write(buffer2,"(I6,25(',',F10.4),',',I10)") mype,                            &
                                       init_tim%time_cpu,             &
                                       upsend_tim%time_cpu,           &
                                       dnsend_tim%time_cpu,           &
                                       weight_tim%time_cpu,           &
                                       hfiltT_tim%time_cpu,           &
                                       hfilt_tim%time_cpu,            &
                                       vfiltT_tim%time_cpu,           &
                                       bocoT_tim%time_cpu,           &
                                       boco_tim%time_cpu,           &
                                       vfilt_tim%time_cpu,           &
                                       filt2an_tim%time_cpu,          &
                                       aintp_tim%time_cpu,            &
                                       intp_tim%time_cpu,             &
                                       an2filt_tim%time_cpu,          &
                                       output_tim%time_cpu,           &
                                       total_tim%time_cpu,            &
                                       mg_multiply_time%time_cpu ,  &
                                  mg_interface_multiply_time%time_cpu,& 
                                  mg_interface_registry_get_time%time_cpu,& 
                                  mg_interface_fldset_time%time_cpu,& 
                                       mg_preprocess_time%time_cpu ,  &
                                       mg_anal_to_filt_time%time_cpu,   &
                                       mg_filtering_time%time_cpu,   &
                                       mg_filt_to_anal_time%time_cpu,   &
                                       mg_postprocess_time%time_cpu, &   
                                  mg_interface_multiply_time%icount 
!clt#    else if ( print_type == print_cpu ) then
!    end if

    bufsize1 = LEN(TRIM(buffer1)) + 1
    bufsize2 = LEN(TRIM(buffer2)) + 1
    buffer1(bufsize1:bufsize1) = NEW_LINE(' ')
    buffer2(bufsize2:bufsize2) = NEW_LINE(' ')

    write(header1,"(A6,26(',',A10))") "mype",                            &
                                     "init",                            &
                                     "upsend",                          &
                                     "dnsend",                          &
                                     "weight",                          &
                                     "hfiltT",                           &
                                     "hfilt",                           &
                                     "vfiltT",                           &
                                     "vfilt",                           &
                                     "bocoT",                           &
                                     "boco",                           &
                                     "filt2an",                         &
                                     "aintp"  ,                        &
                                     "intp"  ,                        &
                                     "an2filt" ,                          &
                                     "output",                            &
                                     "total",                           &
                                     "multiply",                           &
                                     "ifc_mult",& 
                                     "ifc_reg",& 
                                     "ifc_fset",          & 
                                     "preprocess",                            &
                                     "anal_to_filt",                          &
                                     "filtering",                          &
                                     "filt_to_anal",                         &
                                     "postprocess"  ,   &                      
                                     "icount"                         

    header1(bufsize1:bufsize1) = NEW_LINE(' ')
    if(sizeof(header1(1:1)) /= 1) then
      write(6,*)" the one character is not using one byte as assumened ,stop"
      stop
    endif
    disp = 0
!    write(6,*)'thinkdebxxx bufsize 1/2 num_ranks is ',bufsize1, ' ',bufsize2,' ',num_ranks
 if(mype==0)    call MPI_File_write_at(fh, disp, header1, bufsize1, MPI_BYTE, stat, ierr)
    disp =disp+ bufsize1
    disp = disp+(mype)*bufsize1
    call MPI_File_write_at(fh, disp, buffer1, bufsize1, MPI_BYTE, stat, ierr)
    disp=bufsize1+num_ranks*bufsize1
    disp = disp+(mype)*bufsize2
    call MPI_File_write_at(fh, disp, buffer2, bufsize2, MPI_BYTE, stat, ierr)
    

    call MPI_File_close(fh, ierr)

  endsubroutine print_mg_timers
!-----------------------------------------------------------------------
  function wtime()
    use mpi
    real(r_kind) :: wtime
    wtime = MPI_Wtime()
  endfunction wtime
!-----------------------------------------------------------------------
  function ctime()
    real(r_kind) :: ctime
    call CPU_TIME(ctime)
  endfunction ctime
!-----------------------------------------------------------------------
end module mg_timers
