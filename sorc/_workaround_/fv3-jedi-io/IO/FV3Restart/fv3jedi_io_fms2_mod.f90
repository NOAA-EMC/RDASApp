! (C) Copyright 2017-2021 UCAR
!
! This software is licensed under the terms of the Apache Licence Version 2.0
! which can be obtained at http://www.apache.org/licenses/LICENSE-2.0.

module fv3jedi_io_fms_mod

! oops
use datetime_mod
use string_utils,                 only: swap_name_member

! fckit
use fckit_configuration_module,   only: fckit_configuration

! fms2
use fms2_io_mod,                  only: FmsNetcdfDomainFile_t, open_file, close_file, unlimited
use fms2_io_mod,                  only: write_data, read_data, write_restart, read_restart
use fms2_io_mod,                  only: register_axis, register_field, register_restart_field
use fms2_io_mod,                  only: register_variable_attribute, is_dimension_registered
use fms2_io_mod,                  only: dimension_exists, get_dimension_size
use fms2_io_mod,                  only: get_num_dimensions, get_dimension_names, dimension_exists
use fms2_io_mod,                  only: get_variable_num_dimensions, get_variable_dimension_names
use mpp_domains_mod,              only: east, north, center, domain2D, mpp_get_ntile_count
use mpp_mod,                      only: mpp_pe, mpp_root_pe, mpp_npes

! fv3jedi
use fv3jedi_field_mod,            only: fv3jedi_field, hasfield, field_clen
use fv3jedi_io_utils_mod,         only: vdate_to_datestring, replace_text, add_iteration, ioname, &
                                        ioscale, iounscale
use fv3jedi_kinds_mod,            only: kind_real
use fv3jedi_geom_mod,             only: fv3jedi_geom
use fields_metadata_mod,          only: field_metadata
use mpi, only : MPI_Wtime, MPI_comm_world, MPI_Barrier, MPI_Integer, MPI_REAL, MPI_DOUBLE_PRECISION, MPI_MAX, &
                MPI_INFO_NULL, mpi_character, MPI_COMM_NULL, MPI_UNDEFINED, MPI_IN_PLACE, MPI_INTEGER8, &
                MPI_SUM, MPI_ADDRESS_KIND, MPI_COMM_TYPE_SHARED, MPI_STATUSES_IGNORE, MPI_BOTTOM, &
                MPI_REQUEST_NULL, MPI_STATUS_SIZE, MPI_ERR_IN_STATUS, MPI_ERROR, MPI_SUCCESS, MPI_MAX_ERROR_STRING
use netcdf
use, intrinsic :: iso_c_binding

! --------------------------------------------------------------------------------------------------

implicit none
private
public fv3jedi_io_fms, fv3jedi_register_field

! If adding a new file it is added here and object and config in setup
integer, parameter :: numfiles = 9

type :: file_t
  logical :: lopened = .false.
  character(len=NF90_MAX_NAME) :: FileName
  integer(kind=4) :: VariableIndecies(50) = -999  ! Store JEDI domain field/variable indecies found in each file
endtype file_t

! Subcommunicator
integer :: read_comm, write_comm

! MPI_Info
integer :: info

! spread_comm communicator is used to distribute reads to all nodes in the job
integer :: node_comm, spread_comm, node_count
integer :: local_rank, spread_mype, is_node_leader, total_nodes, batch_size
integer, allocatable :: spread_to_world(:)
integer, allocatable :: reqs_p1(:), reqs_p2(:)

integer :: my_var_index
integer :: ntotallev
integer :: mype_lbegin,mype_lend
integer :: mype_vartype
integer :: mype_fileid
integer :: cached_globalsizes(2)=0  ! Local copy of the grid dimensions needed in order to track changes (dual resolution cases)
logical :: first_pass = .true. ! Some arrays need only be allocated once
logical :: need_to_reallocate_ps = .false. ! Some arrays need only be allocated once
character(len=72) :: mype_varname

logical :: write_first_pass = .true. ! Some arrays need only be allocated once
type :: write_buffer_t
  real(kind=c_float),  allocatable :: r4(:,:,:)
  real(kind=c_double), allocatable :: r8(:,:,:)
end type

type(write_buffer_t), allocatable, target, asynchronous :: write_buffers(:)

integer(kind=4), allocatable :: LevelToProcMap(:), LevelToVariableMap(:), LevelToLevelMap(:), VarToVarMap(:)
integer(kind=4), allocatable :: nc_vartype(:), numvarfile(:), nlevpervar(:)
character(len=72), allocatable :: varnames(:)
character(len=NF90_MAX_NAME), allocatable :: FileNamesToProcess(:)
logical :: rstflag(numfiles)

character(len=field_clen), allocatable :: cached_field_names(:)
integer, allocatable :: cached_field_nz(:)

type fv3jedi_io_fms
 logical :: is_restart
 logical :: use_fms_lib
 logical :: input_is_date_templated
 character(len=128) :: datapath
 character(len=128) :: filename_nonrestart ! For non-restarts
 character(len=128) :: filename_nonrestart_conf
 character(len=128) :: filenames(numfiles) ! For restarts
 character(len=128) :: filenames_conf(numfiles)
 integer :: index_core = 1  ! Files like fv_core.res.tile<n>.nc
 integer :: index_trcr = 2  ! Files like fv_tracer.res.tile<n>.nc
 integer :: index_sfcd = 3  ! Files like sfc_data.tile<n>.nc
 integer :: index_sfcw = 4  ! Files like fv_srf_wnd.res.tile<n>.nc
 integer :: index_cplr = 5  ! Files like coupler.res
 integer :: index_spec = 6  ! Files like grid_spec.res.tile<n>.nc
 integer :: index_phys = 7  ! Files like phy_data.tile<n>.nc
 integer :: index_orog = 8  ! Files like C<npx-1>_oro_data.tile<n>.nc
 integer :: index_cold = 9  ! Files like gfs_data.tile<n>.nc
 logical :: ps_in_file
 logical :: skip_coupler
 logical :: prepend_date
 logical :: has_prefix
 character(len=128) :: prefix
 integer :: calendar_type
 logical :: ignore_checksum
 logical :: write_into_existing_files
 character(len=16) :: default_output_resolution
 integer :: lustre_stripe_size
 !character(len=72), allocatable :: analysis_names(:)
 character(len=1024) :: analysis_names
 character(len=:), allocatable :: fields_to_write(:) ! Optional list of fields to write out (non-restarts)
 ! Geometry copies
 type(domain2D), pointer :: domain
 integer :: npz
 contains
   procedure :: create
   procedure :: delete
   procedure :: read
   procedure :: write
   final     :: dummy_final
end type fv3jedi_io_fms

! --------------------------------------------------------------------------------------------------

contains

! --------------------------------------------------------------------------------------------------

subroutine create(self, conf, domain, npz)

class(fv3jedi_io_fms),     intent(inout) :: self
type(fckit_configuration), intent(in)    :: conf
type(domain2D), target,    intent(in)    :: domain
integer,                   intent(in)    :: npz

integer :: n,ntiles
character(len=:), allocatable :: str
character(len=13) :: fileconf(numfiles)

! Check if files are restarts or not
! ----------------------------------
if (conf%has("is restart")) then
  call conf%get_or_die("is restart", self%is_restart)
else
  self%is_restart = .true.
endif

! See if we can use the new parallelized routines
! -----------------------------------------------
ntiles = mpp_get_ntile_count(domain)
if (conf%has("use_fms_lib")) call conf%get_or_die("use_fms_lib", self%use_fms_lib)
if ((ntiles .ne. 1) .and. (.not. self%use_fms_lib)) then
  call abor1_ftn('fv3jedi_io_fms_mod.create: MUST use FMS I/O for multi-tile cases')
endif

! Get path to files
! -----------------
call conf%get_or_die("datapath",str)
if (len(str) > 128) &
  call abor1_ftn('fv3jedi_io_fms_mod.create: datapath too long, max FMS char length= 128')

! For ensemble methods switch out member template
! -----------------------------------------------
call swap_name_member(conf, str)

self%datapath = str
deallocate(str)

! Optionally the file name to be read is datetime templated
! ---------------------------------------------------------
if (conf%has("filename is datetime templated")) then
   call conf%get_or_die("filename is datetime templated", self%input_is_date_templated)
else
   self%input_is_date_templated = .false.
endif

if ( self%is_restart ) then

   !Set default filenames
   !---------------------
   self%filenames_conf(self%index_core) = 'fv_core.res.nc'
   self%filenames_conf(self%index_trcr) = 'fv_tracer.res.nc'
   self%filenames_conf(self%index_sfcd) = 'sfc_data.nc'
   self%filenames_conf(self%index_sfcw) = 'fv_srf_wnd.res.nc'
   self%filenames_conf(self%index_cplr) = 'coupler.res'
   self%filenames_conf(self%index_spec) = 'null'
   self%filenames_conf(self%index_phys) = 'phy_data.nc'
   self%filenames_conf(self%index_orog) = 'oro_data.nc'
   self%filenames_conf(self%index_cold) = 'gfs_data.nc'

   ! Configuration to parse for the filenames
   ! ----------------------------------------
   fileconf(self%index_core) = "filename_core"
   fileconf(self%index_trcr) = "filename_trcr"
   fileconf(self%index_sfcd) = "filename_sfcd"
   fileconf(self%index_sfcw) = "filename_sfcw"
   fileconf(self%index_cplr) = "filename_cplr"
   fileconf(self%index_spec) = "filename_spec"
   fileconf(self%index_phys) = "filename_phys"
   fileconf(self%index_orog) = "filename_orog"
   fileconf(self%index_cold) = "filename_cold"

   ! Set files names based on user input
   ! -----------------------------------
   do n = 1, numfiles

      ! Retrieve user input filenames if available
      if (conf%has(fileconf(n))) then
         call conf%get_or_die(fileconf(n),str)
         if (len(str) > 128) call abor1_ftn("fv3jedi_io_fms_mod.create: "//fileconf(n)//&
                                            " too long, max FMS char length= 128")
         call add_iteration(conf,str)
         self%filenames_conf(n) = str
         deallocate(str)
      endif

      ! Config filenames to filenames
      self%filenames(n) = trim(self%filenames_conf(n))

   enddo

   ! Option to retrieve Ps from delp
   ! -------------------------------
   self%ps_in_file = .false.
   if (conf%has("psinfile")) then
      call conf%get_or_die("psinfile",self%ps_in_file)
   endif

   ! Option to skip read/write of coupler file
   ! -----------------------------------------
   self%skip_coupler = .false.
   if (conf%has("skip coupler file")) then
      call conf%get_or_die("skip coupler file",self%skip_coupler)
   endif

   ! Option to turn off prepending file with date
   ! --------------------------------------------
   if (.not.conf%get("prepend files with date", self%prepend_date)) then
      self%prepend_date = .true.
   endif

   ! Option to overwrite date etc...
   ! -------------------------------
   self%has_prefix = conf%has("prefix")
   if (self%has_prefix) then
      call conf%get_or_die("prefix",str)
      self%prefix = trim(str)
      deallocate(str)
   endif

   ! Calendar type
   ! -------------
   self%calendar_type = 2
   if (conf%has("calendar type")) then
      call conf%get_or_die("calendar type", self%calendar_type)
   endif

   ! Ignore checksum?
   ! ----------------
   if (conf%has("ignore checksum")) then
      call conf%get_or_die("ignore checksum", self%ignore_checksum)
   else
      self%ignore_checksum = .true.
   end if

   ! Option to write values into already existing restart files
   ! ----------------------------------------------------------
   self%write_into_existing_files = .false.
   if (conf%has("write into existing files")) then
      call conf%get_or_die("write into existing files", self%write_into_existing_files)
   endif
   if (self%write_into_existing_files .and. self%use_fms_lib) then
      call abor1_ftn('fv3jedi_io_fms: "write into existing files" only applies to writes not using the FMS path')
   endif

   ! Optional fields to write specified?
   ! -----------------------------------
   if (conf%has("fields to write") .and. self%write_into_existing_files) then
      call conf%get_or_die('fields to write', self%fields_to_write)
   else
      allocate(character(len=2048) :: self%fields_to_write(1))
      self%fields_to_write(1)='All'
   endif

   ! Option to write output in user specified bit depth
   ! Not allowed if the files already exist
   ! --------------------------------------------------
   self%default_output_resolution = "native"
   if (conf%has("default output resolution") .and. .not. self%write_into_existing_files) then
     call conf%get_or_die("default output resolution", str)
     self%default_output_resolution = trim(str)
     deallocate(str)
   endif

   ! Validate the output resolution string immediately
   select case (trim(self%default_output_resolution))
     case ('native', '32bit', '64bit')
       ! These are valid configurations; proceed normally.
     case default
       call abor1_ftn("fv3jedi_io_fms_mod.create: ERROR Unrecognized default_output_resolution. &
                       Valid options are 'native', '32bit' or '64bit'")
   end select

   ! Option to for tuning on Lustre file systems
   ! -------------------------------------------
   self%lustre_stripe_size = 1048576
   if (conf%has("lustre stripe size")) then
     call conf%get_or_die("lustre stripe size", self%lustre_stripe_size)
   endif
else
   ! Filename
   ! --------
   if ( conf%has("filename_nonrestart") ) then
      call conf%get_or_die("filename_nonrestart", str)
      if (len(str) > 128) then
         call abor1_ftn('fv3jedi_io_fms_mod.create: filename_nonrestart too long, max FMS char length= 128')
      end if
      self%filename_nonrestart_conf = str
      deallocate(str)

      ! Config filename to filename
      self%filename_nonrestart = trim(self%filename_nonrestart_conf)
   else
      call abor1_ftn('fv3jedi_io_fms_mod.create: filename_nonrestart not specified')
   endif

   ! Optional fields to write specified?
   ! -----------------------------------
   if (conf%has("fields to write")) then
      call conf%get_or_die('fields to write', self%fields_to_write)
   else
      allocate(character(len=2048) :: self%fields_to_write(1))
      self%fields_to_write(1)='All'
   endif
end if

! Geometry copies
! ---------------
self%domain => domain
self%npz = npz

end subroutine create

! --------------------------------------------------------------------------------------------------

subroutine delete(self)

class(fv3jedi_io_fms), intent(inout) :: self

if (associated(self%domain)) nullify(self%domain)

end subroutine delete

! --------------------------------------------------------------------------------------------------

subroutine read(self, vdate, geom, fields, field_io_names, field_io_scaling)

class(fv3jedi_io_fms),     intent(inout)  :: self
type(datetime),            intent(inout)  :: vdate
type(fv3jedi_geom),        intent(inout)  :: geom
type(fv3jedi_field),       intent(inout)  :: fields(:)
type(fckit_configuration), intent(in)     :: field_io_names
type(fckit_configuration), intent(in)     :: field_io_scaling

integer :: n

! Overwrite any datetime templates in the file names
! --------------------------------------------------
if (self%input_is_date_templated) call setup_date(self, vdate)

if ( self%is_restart ) then
   ! Use prefix if present
   ! ---------------------
   if (self%has_prefix) then
      do n = 1, numfiles
         self%filenames(n) = trim(self%prefix)//"."//trim(self%filenames_conf(n))
      enddo
   endif

   ! Read meta data
   ! --------------
   if (.not. self%skip_coupler) call read_meta(self, vdate)

   ! Read fields
   ! -----------
   if (self%use_fms_lib) then
      call read_restart_fields(self, geom, fields, field_io_names, field_io_scaling)
   else
      call read_restart_fields_reg(self, geom, fields, field_io_names, field_io_scaling)
   end if

else
   ! Read fields
   ! -----------
   call read_nonrestart_fields(self, fields, field_io_names, field_io_scaling)
end if

end subroutine read

! --------------------------------------------------------------------------------------------------

subroutine write(self, vdate, geom, fields, field_io_names, field_io_scaling)

class(fv3jedi_io_fms),     intent(inout) :: self
type(datetime),            intent(in)    :: vdate
type(fv3jedi_geom),        intent(inout) :: geom
type(fv3jedi_field),       intent(inout) :: fields(:)
type(fckit_configuration), intent(in)    :: field_io_names
type(fckit_configuration), intent(in)    :: field_io_scaling

! Overwrite any datetime templates in the file names
! --------------------------------------------------
call setup_date(self, vdate)

if ( self%is_restart ) then
   ! Write metadata and fields
   ! -------------------------
   if (self%use_fms_lib) then
      call write_restart_all(self, geom, fields, vdate, field_io_names, field_io_scaling)
   else
      call write_restart_all_reg(self, geom, fields, vdate, field_io_names, field_io_scaling)
   end if
else
   ! Write fields
   ! ------------
   call write_nonrestart_all(self, fields, field_io_names, field_io_scaling)
end if

end subroutine write

! --------------------------------------------------------------------------------------------------

subroutine setup_date(self, vdate)

type(fv3jedi_io_fms), intent(inout) :: self
type(datetime),       intent(in)    :: vdate

integer :: n
character(len=4) :: yyyy
character(len=2) :: mm, dd, hh, min, ss

! Datetime to strings
! -------------------
call vdate_to_datestring(vdate, yyyy=yyyy, mm=mm, dd=dd, hh=hh, min=min, ss=ss)

if ( self%is_restart ) then
   do n = 1, numfiles

      ! Config filenames to filenames
      self%filenames(n) = trim(self%filenames_conf(n))

      ! Swap out datetime templates if needed
      if (index(self%filenames(n),"%yyyy") > 0) &
           self%filenames(n) = replace_text(self%filenames(n),'%yyyy',yyyy)
      if (index(self%filenames(n),"%mm"  ) > 0) &
           self%filenames(n) = replace_text(self%filenames(n),'%mm'  ,mm  )
      if (index(self%filenames(n),"%dd"  ) > 0) &
           self%filenames(n) = replace_text(self%filenames(n),'%dd'  ,dd  )
      if (index(self%filenames(n),"%hh"  ) > 0) &
           self%filenames(n) = replace_text(self%filenames(n),'%hh'  ,hh  )
      if (index(self%filenames(n),"%MM"  ) > 0) &
           self%filenames(n) = replace_text(self%filenames(n),'%MM'  ,min )
      if (index(self%filenames(n),"%ss"  ) > 0) &
           self%filenames(n) = replace_text(self%filenames(n),'%ss'  ,ss  )
   enddo
else
   ! Config filename to filename
   self%filename_nonrestart = trim(self%filename_nonrestart_conf)

   ! Swap out datetime templates if needed
   if (index(self%filename_nonrestart,"%yyyy") > 0) &
        self%filename_nonrestart = replace_text(self%filename_nonrestart,'%yyyy',yyyy)
   if (index(self%filename_nonrestart,"%mm"  ) > 0) &
        self%filename_nonrestart = replace_text(self%filename_nonrestart,'%mm'  ,mm  )
   if (index(self%filename_nonrestart,"%dd"  ) > 0) &
        self%filename_nonrestart = replace_text(self%filename_nonrestart,'%dd'  ,dd  )
   if (index(self%filename_nonrestart,"%hh"  ) > 0) &
        self%filename_nonrestart = replace_text(self%filename_nonrestart,'%hh'  ,hh  )
   if (index(self%filename_nonrestart,"%MM"  ) > 0) &
        self%filename_nonrestart = replace_text(self%filename_nonrestart,'%MM'  ,min )
   if (index(self%filename_nonrestart,"%ss"  ) > 0) &
        self%filename_nonrestart = replace_text(self%filename_nonrestart,'%ss'  ,ss  )
end if

end subroutine setup_date

! --------------------------------------------------------------------------------------------------

subroutine read_meta(self, vdate)

type(fv3jedi_io_fms), intent(inout) :: self
type(datetime),       intent(inout) :: vdate         !< DateTime

integer :: date(6)
integer :: idate, itime
character(len=8) :: cdate
character(len=6) :: ctime

integer :: calendar_type
integer :: date_init(6)
character(len=64) :: vdate_string_file, vdate_string

! Get datetime from coupler.res - this file must exist, therefore set status='old'
open(101, file=trim(adjustl(self%datapath))//'/'//self%filenames(self%index_cplr), &
     form='formatted', status='old')
read(101, '(i6)')  calendar_type
read(101, '(6i6)') date_init
read(101, '(6i6)') date
close(101)

! Pad and convert to string
idate=date(1)*10000+date(2)*100+date(3)
itime=date(4)*10000+date(5)*100+date(6)
write(cdate,"(I0.8)") idate  ! Looks like YYYYMMDD
write(ctime,"(I0.6)") itime  ! Looks like HHmmSS

! Compute string form of the datetime in the fields
call datetime_to_string(vdate, vdate_string)

! Convert to string that matches format returned by datetime_to_string YYYY-MM-DDTHH:mm:SS
vdate_string_file = cdate(1:4)//'-'//cdate(5:6)//'-'//cdate(7:8)//'T'// &
                    ctime(1:2)//':'//ctime(3:4)//':'//ctime(5:6)//'Z'

! Assert
if (trim(vdate_string_file) .ne. trim(vdate_string)) &
  call abor1_ftn("io_cube_sphere_history.read_meta: Datetime set in config (" &
                 //trim(vdate_string)//") does not match that read from the file (" &
                 //trim(vdate_string_file)//").")

end subroutine read_meta

! --------------------------------------------------------------------------------------------------

subroutine read_restart_fields(self, geom, fields, field_io_names, field_io_scaling)

type(fv3jedi_io_fms),      intent(inout) :: self
type(fv3jedi_geom),        intent(in)    :: geom
type(fv3jedi_field),       intent(inout) :: fields(:)
type(fckit_configuration), intent(in)    :: field_io_names
type(fckit_configuration), intent(in)    :: field_io_scaling

type(FmsNetcdfDomainFile_t) :: fileobj(numfiles)
logical :: rstflag(numfiles)
integer :: n, indexrst, var, idrst, layout(2), io_layout(2), npes

logical :: havedelp
integer :: indexof_ps, indexof_delp
real(kind=kind_real), allocatable :: delp(:,:,:)
type(fckit_configuration) :: field_io_names_local
character(len=field_clen) :: io_name

! Register and read fields
! ------------------------
rstflag(:) = .false.

! Check whether delp in fields
! ----------------------------
indexof_ps = -1
indexof_delp = -1
havedelp = hasfield(fields, 'air_pressure_thickness', indexof_delp)

! Copy config
! -----------
field_io_names_local = field_io_names

! Loop over fields and register their restart file
! ------------------------------------------------
do var = 1,size(fields)

  ! If need ps and not in file will compute from delp so read delp in place of ps
  if (trim(fields(var)%long_name) == 'air_pressure_at_surface' .and. .not.self%ps_in_file) then
    indexof_ps = var
    if (havedelp) cycle ! Do not register delp twice
    deallocate(fields(indexof_ps)%array)
    allocate(fields(indexof_ps)%array(fields(indexof_ps)%isc:fields(indexof_ps)%iec, &
                fields(indexof_ps)%jsc:fields(indexof_ps)%jec,1:self%npz))
    fields(indexof_ps)%long_name = 'air_pressure_thickness'
    fields(indexof_ps)%npz = self%npz

    ! Create io name lookup
    if (.not. field_io_names_local%has("air_pressure_thickness")) then
      call field_io_names_local%set("air_pressure_thickness", "delp")
    end if
  endif

  ! Get file to use
  call get_io_file(self, fields(var), indexrst)

  ! Flag to read this restart
  if ( .not. rstflag(indexrst) ) then
     if ( open_file(fileobj(indexrst), &
          trim(self%datapath)//'/'//trim(self%filenames(indexrst)), &
          "read", self%domain, is_restart=.true., dont_add_res_to_filename=.true.) ) then
        rstflag(indexrst) = .true.
     else
        call abor1_ftn('fv3jedi_io_fms_mod.read_restart_fields: file ' &
                        // trim(self%datapath)//'/'//trim(self%filenames(indexrst)) // &
                       ' could not be opened')
     end if
  end if

  ! Register restart field
  io_name = ioname(trim(fields(var)%long_name), field_io_names_local)
  call fv3jedi_register_field(fileobj(indexrst), io_name, fields(var)%array, center, .true., &
                              trim(fields(var)%long_name), trim(fields(var)%units))

  ! Scale field if necessary
  call ioscale(fields(var), field_io_scaling)
enddo

! Loop over files and read fields
! -------------------------------
do n = 1, numfiles
  if (rstflag(n)) then
     call read_restart(fileobj(n), ignore_checksum=self%ignore_checksum)
     call close_file(fileobj(n))
  endif
enddo

! Compute ps from DELP
! --------------------
if (indexof_ps > 0) then
  allocate(delp(fields(indexof_ps)%isc:fields(indexof_ps)%iec, &
                fields(indexof_ps)%jsc:fields(indexof_ps)%jec,1:self%npz))
  if (.not. havedelp) then
    delp = fields(indexof_ps)%array
    deallocate(fields(indexof_ps)%array)
    allocate(fields(indexof_ps)%array(fields(indexof_ps)%isc:fields(indexof_ps)%iec, &
                fields(indexof_ps)%jsc:fields(indexof_ps)%jec,1))
  else
    delp = fields(indexof_delp)%array
  endif
  fields(indexof_ps)%array(:,:,1) = geom%ptop + sum(delp,3)
  fields(indexof_ps)%long_name = 'air_pressure_at_surface'
  fields(indexof_ps)%npz = 1
endif

end subroutine read_restart_fields

! --------------------------------------------------------------------------------------------------

subroutine read_restart_fields_reg(self, geom, fields, field_io_names, field_io_scaling)
use module_ncfile_stat, only : ncfile_stat
use TwoPhaseScatterGather
use netcdf
use, intrinsic :: ieee_arithmetic
use, intrinsic :: iso_c_binding
implicit none

type(fv3jedi_io_fms),      intent(inout) :: self
type(fv3jedi_geom),        intent(inout) :: geom
type(fv3jedi_field), target,      intent(inout) :: fields(:)
type(fckit_configuration), intent(in)    :: field_io_names
type(fckit_configuration), intent(in)    :: field_io_scaling

integer :: num_restart_vars(numfiles)
character(len=500)  :: tmpvarlist(numfiles)
character(len=500), allocatable  :: varlist(:)
integer :: i, j, k, level, l, n, indexrst, file_var_idx, jedi_var_idx
integer :: iret,ilev,r,ncioid,var_id,loc

integer(kind=4), allocatable :: nlev(:), numvar(:)
!integer(kind=4), allocatable :: nlev(:), nlevpervar(:), numvar(:)
!character(len=72), allocatable :: varnames(:)
real(kind=4), target :: dummy_r4(1,1)
real(kind=8), target :: dummy_r8(1,1)

type(ncfile_stat) :: ncfs_all
integer, allocatable :: out_fileid(:), out_lvlbegin(:), out_lvlend(:)
character(len=72), allocatable :: out_varname(:)
character(len=72), allocatable :: tmp_names(:)
integer, allocatable :: tmp_d3(:), tmp_fid(:)

! sub communicator
integer :: color, key

! array
real(4), pointer, contiguous :: d2r4ptr(:,:) => null()
real(8), pointer, contiguous :: d2r8ptr(:,:) => null()
real(4),allocatable, target :: d3r4(:,:,:)
real(8),allocatable, target :: d3r8(:,:,:)

logical :: havedelp, haveps
integer :: indexof_ps, indexof_delp
real(kind=kind_real), allocatable :: delp(:,:,:)
type(fckit_configuration) :: field_io_names_local

integer :: rank, npes, ierr
integer :: starts(4), counts(4)
!real(kind=8) :: tb1,tb2,tb3, times(3), walltime(3)
!real(kind=8) :: te1,te2,te3
integer :: totalnumfiles
integer, save :: cached_nfields = -1
logical :: fields_changed
integer :: f, nz
logical :: getdelp
character(len=:), allocatable :: str

!integer :: b_idx, e_idx, my_levels, total_levels
!integer :: my_ost_count, stripeSize=1048576
!character(len=8) :: ost_str
!character(len=12) :: stripeSize_str

integer :: b_start, b_end, n_in_batch, b_ind, owner

rank=mpp_pe()
npes=mpp_npes()

tmpvarlist=''

! Check whether delp in fields
! ----------------------------
indexof_ps = -1
indexof_delp = -1
havedelp = hasfield(fields, 'air_pressure_thickness', indexof_delp)
haveps = hasfield(fields, 'air_pressure_at_surface', indexof_ps)

num_restart_vars(:)=0
!times(:)=0.0
!walltime(:)=0.0

! Copy config
! -----------
field_io_names_local = field_io_names

! Check for field changes (order or size)
! ---------------------------------------
fields_changed = .false.
! If cache not initialized, force rebuild
if (cached_nfields < 0) then
  fields_changed = .true.
  if(rank==0) write(6,'("read_restart_fields_reg: Init fields_changed")')
elseif (cached_nfields /= size(fields)) then
  fields_changed = .true.
  if(rank==0) write(6,'("read_restart_fields_reg: cached_nfields /= size(fields)",2I4)') cached_nfields,size(fields)
elseif (.not. allocated(cached_field_names) .or. .not. allocated(cached_field_nz)) then
  fields_changed = .true.
  if(rank==0) write(6,'("read_restart_fields_reg: cached_field_names or cached_field_nz not allocated cached_field_nz")')
elseif (size(cached_field_names) /= size(fields) .or. size(cached_field_nz) /= size(fields)) then
  fields_changed = .true.
  if(rank==0) write(6,'("read_restart_fields_reg: size of cached_field_names or cached_field_nz not right")')
else
  do f = 1, size(fields)
    if (allocated(fields(f)%array)) then
      nz = size(fields(f)%array, 3)
    else
      nz = -1
    endif
    if (trim(fields(f)%long_name) /= trim(cached_field_names(f))) then
      fields_changed = .true.
      if(rank==0) write(6,'("read_restart_fields_reg: field name order is different",I4,5A)') &
                        f,' (', trim(fields(f)%model_name),') /= (', trim(cached_field_names(f)),')'
      exit
    endif
    if (nz /= cached_field_nz(f)) then
      fields_changed = .true.
      if(rank==0) write(6,'("read_restart_fields_reg: nz is different")')
      exit
    endif
  enddo
endif

! If the Geometry changes, reallocate Scatter structure and rescan input files
! Do this only for the first ensemble member to save significant time
! ----------------------------------------------------------------------------
if( (fields_changed) .or. &
    (geom%globalsizes(1) .ne. cached_globalsizes(1)) .or. &
    (geom%globalsizes(2) .ne. cached_globalsizes(2)) ) then

  !tb1 = MPI_Wtime()

  ! Update cached fields
  cached_nfields = size(fields)
  if (allocated(cached_field_names)) deallocate(cached_field_names)
  if (allocated(cached_field_nz))    deallocate(cached_field_nz)
  allocate(cached_field_names(cached_nfields))
  allocate(cached_field_nz(cached_nfields))
  do f = 1, cached_nfields
    cached_field_names(f) = fields(f)%long_name
    if (allocated(fields(f)%array)) then
      cached_field_nz(f) = size(fields(f)%array, 3)
    else
      cached_field_nz(f) = -1
    endif
  enddo

  cached_globalsizes = geom%globalsizes
  need_to_reallocate_ps = .false.

  if(.not. first_pass) then
    call TwoPhaseScatter_delete()
    deallocate(reqs_p1, reqs_p2)
  endif

  ! Loop over fields to identify their restart file
  ! Only enter here if its the first time fv3jedi_io_fms::read() is called.
  ! Reusing the arrays generated in the first call saves a bunch of walltime.
  ! This assumes the bkg and ens files are the same resolution.
  ! -------------------------------------------------------------------------
  rstflag(:) = .false.
  do jedi_var_idx = 1,size(fields)
    ! If need ps is not in file will compute from delp so read delp in place of ps, but only if delp is NOT already present in the fields array
    if (trim(fields(jedi_var_idx)%long_name) == 'air_pressure_at_surface' .and. .not.self%ps_in_file) then
      indexof_ps = jedi_var_idx
      if (havedelp) then
        fields(indexof_ps)%model_name = ''   ! PS will be computed, not read
        cycle ! Do not register delp twice
      else
        ! Reallocate fields array for ps (2D) to hold delp (3D) instead.  Set need_to_reallocate_ps to true so this gets done for every ensemble member
        need_to_reallocate_ps = .true.
        deallocate(fields(indexof_ps)%array)
        allocate(fields(indexof_ps)%array(fields(indexof_ps)%isc:fields(indexof_ps)%iec, &
                 fields(indexof_ps)%jsc:fields(indexof_ps)%jec,1:self%npz))
        fields(indexof_ps)%long_name = 'air_pressure_thickness'
        fields(indexof_ps)%model_name = 'delp'
        fields(indexof_ps)%npz = self%npz
        ! Create io name lookup.  Reuse name from config file
        if ( field_io_names%get("air_pressure_thickness", str) ) then
          call field_io_names_local%set("air_pressure_thickness", trim(str))
        else
          call field_io_names_local%set("air_pressure_thickness", "delp")
        endif
      endif
    endif

    ! Get file to use
    call get_io_file(self, fields(jedi_var_idx), indexrst)

    ! Get UFS variable name
    fields(jedi_var_idx)%model_name = ioname(trim(fields(jedi_var_idx)%long_name), field_io_names_local)

    ! Append variable name onto list for each file.  Will need a mapping between this list and the order in the fields array
    if (len_trim(tmpvarlist(indexrst)) > 0) then
      tmpvarlist(indexrst)=trim(tmpvarlist(indexrst)) //' '// trim(fields(jedi_var_idx)%model_name)
    else
      tmpvarlist(indexrst)=trim(fields(jedi_var_idx)%model_name)
    endif

    rstflag(indexrst) = .true.  ! prevent opening this file again
    num_restart_vars(indexrst) = num_restart_vars(indexrst) + 1
  enddo

  if(allocated(nlev)) deallocate(nlev)
  allocate(nlev(0:npes-1))

  totalnumfiles=count(rstflag(:) .eqv. .true.)
  if(allocated(FileNamesToProcess)) deallocate(FileNamesToProcess)
  allocate(FileNamesToProcess(totalnumfiles))

  allocate(numvar(totalnumfiles))
  allocate(varlist(totalnumfiles))

  i=1
  do n=1, numfiles
    if ( rstflag(n) ) then
      FileNamesToProcess(i) = trim(self%datapath)//'/'//trim(self%filenames(n))
      numvar(i) = num_restart_vars(n)
      varlist(i) = tmpvarlist(n)
      i=i+1
    endif
  enddo

  ! Group ranks by physical shared-memory node
  call MPI_Comm_split_type(geom%f_comm%communicator(), MPI_COMM_TYPE_SHARED, 0, MPI_INFO_NULL, node_comm, ierr)
  call MPI_Comm_rank(node_comm, local_rank, ierr)

  ! Determine the number of physical computers being used.  Will use that number as the batch size for non-blocking scatter
  is_node_leader = 0
  if (local_rank == 0) is_node_leader = 1
  call MPI_Allreduce(is_node_leader, total_nodes, 1, MPI_INTEGER, MPI_SUM, geom%f_comm%communicator(), ierr)

  batch_size=max(1,total_nodes)
  !batch_size_gather=total_nodes
  !batch_size_scatter=2*batch_size_gather

  allocate(reqs_p1(batch_size), reqs_p2(batch_size))
  call MPI_Comm_free(node_comm, ierr)

  ! Interleave ranks across nodes using local_rank as the sort key
  call MPI_Comm_split(geom%f_comm%communicator(), 0, local_rank, spread_comm, ierr)
  call MPI_Comm_rank(spread_comm, spread_mype, ierr)

  ! Create a dictionary to map the new interleaved rank back to the true world rank
  allocate(spread_to_world(0:npes-1))
  call MPI_Allgather(rank, 1, MPI_INTEGER, spread_to_world, 1, MPI_INTEGER, spread_comm, ierr)

  ! Total number of variables that will actually be read from files
  ! (this can be smaller than size(fields) when PS is computed from DELP)
  if(allocated(nlevpervar)) deallocate(nlevpervar)
  allocate(nlevpervar(sum(numvar)))

  if(allocated(varnames)) deallocate(varnames)
  allocate(varnames(sum(numvar)))

  if(allocated(nc_vartype)) deallocate(nc_vartype)
  allocate(nc_vartype(sum(numvar)))

  ! init on all ranks to avoid passing unallocated allocatable to MPI_Scatter
  allocate(out_fileid(npes), out_varname(npes), out_lvlbegin(npes), out_lvlend(npes))

  if(spread_mype==0) then
    ! find dimension of each field
    call ncfs_all%init(totalnumfiles, FileNamesToProcess, numvar, varlist)
    call ncfs_all%fill_dims()

    allocate(tmp_names(ncfs_all%numvar), tmp_d3(ncfs_all%numvar), tmp_fid(ncfs_all%numvar))

    ! Extract variables from NetCDF metadata
    tmp_names(:) = ncfs_all%list_varname(1:ncfs_all%numvar)
    tmp_d3(:)    = ncfs_all%dim_3(1:ncfs_all%numvar)

    ! Build the file ID map (which variables belong to which file index)
    i = 0
    do n = 1, ncfs_all%numfiles
      do k = 1, ncfs_all%numvarfile(n)
        i = i + 1
        tmp_fid(i) = n
      enddo
    enddo

    ! distibute variables to each core
    call distribute_io_work(npes, ncfs_all%numvar, tmp_names, tmp_d3, tmp_fid, &
                            out_fileid, out_varname, out_lvlbegin, out_lvlend, nlev)
    nlev(:)=0
    do i=0,npes-1
      if( (out_lvlend(i+1) > 0) .and. (out_lvlbegin(i+1) > 0) ) then
        nlev(i) = (out_lvlend(i+1) - out_lvlbegin(i+1) + 1)
      endif
    enddo
    ntotallev = sum(ncfs_all%dim_3)

    nlevpervar(:ncfs_all%numvar) = ncfs_all%dim_3(:)
    varnames(:ncfs_all%numvar) = ncfs_all%list_varname(:)  ! Names of vcariables to be processed
    nc_vartype(:ncfs_all%numvar) = ncfs_all%vartype(:)        ! NetCDF type of each variable
    deallocate(tmp_names, tmp_d3, tmp_fid)
    call ncfs_all%close()
  endif

  deallocate(varlist)

  ! Let all ranks know what is going on
  call MPI_Scatter(out_fileid  ,  1,   mpi_integer, mype_fileid ,  1, mpi_integer  , 0, spread_comm,ierr)
  call MPI_Scatter(out_varname , 72, mpi_character, mype_varname, 72, mpi_character, 0, spread_comm,ierr)
  call MPI_Scatter(out_lvlbegin,  1,   mpi_integer, mype_lbegin ,  1, mpi_integer  , 0, spread_comm,ierr)
  call MPI_Scatter(out_lvlend  ,  1,   mpi_integer, mype_lend   ,  1, mpi_integer  , 0, spread_comm,ierr)
  deallocate(out_fileid, out_varname, out_lvlbegin, out_lvlend)

  call MPI_Bcast(ntotallev, 1, mpi_integer, 0, spread_comm,ierr)
  call MPI_Bcast(nlev, npes, mpi_integer, 0, spread_comm,ierr)
  call MPI_Bcast(nlevpervar, sum(numvar), mpi_integer, 0, spread_comm,ierr)
  call MPI_Bcast(varnames, 72*sum(numvar), mpi_character, 0, spread_comm,ierr)
  call MPI_Bcast(nc_vartype, sum(numvar), mpi_integer, 0, spread_comm,ierr)

  ! Find this rank's assigned vartype by matching the assigned varname

  mype_vartype = -1
  do i = 1, sum(numvar)
    if (trim(varnames(i)) == trim(adjustl(mype_varname))) then
      mype_vartype = nc_vartype(i)
      exit
    endif
  enddo

  ! Map field level to the process handling that level
  ! LevelToProcMap(levelIndex) gives the rank
  if(allocated(LevelToProcMap)) deallocate(LevelToProcMap)
  allocate(LevelToProcMap(ntotallev))
  LevelToProcMap(:) = -999
  l=1
  do r=0,npes-1
    do i=1,nlev(r)
      LevelToProcMap(l) = spread_to_world(r)
      l=l+1
    enddo
  enddo
  call MPI_Comm_free(spread_comm, ierr)
  deallocate(spread_to_world)

  if (any(LevelToProcMap(:) == -999)) then
    write(6,'("read_restart_fields_reg: Some sigma level were not assigned")')
    call MPI_Abort(geom%f_comm%communicator(),10,ierr)
  endif

  ! Map combined level to variable
  ! LevelToVariableMap(levelIndex) gives an index into the fields array
  if(allocated(LevelToVariableMap)) deallocate(LevelToVariableMap)
  allocate(LevelToVariableMap(ntotallev))
  LevelToVariableMap(:) = -999
  l=1
  do file_var_idx=1,sum(numvar)
    do i=1,nlevpervar(file_var_idx)
      LevelToVariableMap(l) = file_var_idx
      l=l+1
    enddo
  enddo

  if (any(LevelToVariableMap(:) == -999)) then
    loc = findloc(LevelToVariableMap, value=-999, dim=1, back=.false.)
    write(6,'("read_restart_fields_reg: Some variables were not assigned ",2I6)') ntotallev,loc
    call MPI_Abort(geom%f_comm%communicator(),11,ierr)
  endif

  ! Map combined level to variable level
  ! LevelToLevelMap(levelIndex) gives an index into fields(var)%array
  if(allocated(LevelToLevelMap)) deallocate(LevelToLevelMap)
  allocate(LevelToLevelMap(ntotallev))
  LevelToLevelMap(:) = -999
  l=1
  do file_var_idx=1,sum(numvar)
    do i=1,nlevpervar(file_var_idx)
      LevelToLevelMap(l) = i
      l=l+1
    enddo
  enddo
  deallocate(nlevpervar)

  if (any(LevelToLevelMap(:) == -999)) then
    write(6,'("read_restart_fields_reg: Some levels were not assigned")')
    call MPI_Abort(geom%f_comm%communicator(),12,ierr)
  endif

  ! Map JEDI fields array to variable list obtained from above
  ! VarToVarMap(jedi_var_idx) gives an index into fields(var).
  ! The jedi_var_idx index would come from LevelToVariableMap()
  if(allocated(VarToVarMap)) deallocate(VarToVarMap)
  allocate(VarToVarMap(sum(numvar)))
  VarToVarMap(:) = -999
  do jedi_var_idx = 1,size(fields)
    do file_var_idx = 1,sum(numvar)
      if (trim(fields(jedi_var_idx)%model_name) == trim(varnames(file_var_idx))) then
        VarToVarMap(file_var_idx) = jedi_var_idx
        exit
      endif
    enddo
  enddo
  deallocate(varnames)

  if (any(VarToVarMap(:) == -999)) then
    write(6,'("read_restart_fields_reg: Some variables not mapped",21I6)') VarToVarMap(1:sum(numvar))
    call MPI_Abort(geom%f_comm%communicator(),112,ierr)
  endif
  deallocate(numvar)

  ! Create sub-communicator to handle each file
  key=rank+1
  if(mype_fileid > 0 .and. mype_fileid <= totalnumfiles) then
       color = mype_fileid
  else
       color = MPI_UNDEFINED
  endif

  call MPI_Comm_split(geom%f_comm%communicator(),color,key,read_comm,ierr)
  if ( ierr /= 0 ) then
       write(6,'(a,i5)')'***ERROR*** after mpi_comm_create with iret = ',ierr
       call mpi_abort(geom%f_comm%communicator(),101,ierr)
  endif

  call TwoPhaseScatter_init(npes, geom%globalsizes(1), geom%localsizes, batch_size)

  first_pass = .false.

  !te1 = MPI_Wtime()
  !times(1) = te1-tb1

endif ! First pass

! Reallocate space to hold delp if needed
if (need_to_reallocate_ps) then
  do jedi_var_idx = 1,size(fields)
    ! If need ps is not in file will compute from delp so read delp in place of ps, but only if delp is NOT already present in the fields array
    if (trim(fields(jedi_var_idx)%long_name) == 'air_pressure_at_surface' .and. .not.self%ps_in_file) then
      indexof_ps = jedi_var_idx
      if (havedelp) then
        fields(indexof_ps)%model_name = ''   ! PS will be computed, not read
        cycle ! Do not register delp twice
      else
        deallocate(fields(indexof_ps)%array)
        allocate(fields(indexof_ps)%array(fields(indexof_ps)%isc:fields(indexof_ps)%iec, &
                 fields(indexof_ps)%jsc:fields(indexof_ps)%jec,1:self%npz))
        fields(indexof_ps)%long_name = 'air_pressure_thickness'
        fields(indexof_ps)%model_name = 'delp'
        fields(indexof_ps)%npz = self%npz
        ! Create io name lookup.  Reuse name from config file
        if ( field_io_names%get("air_pressure_thickness", str) ) then
          call field_io_names_local%set("air_pressure_thickness", trim(str))
        else
          call field_io_names_local%set("air_pressure_thickness", "delp")
        endif
      endif
    endif
  enddo
endif

  ! Update file names for the next ensemble member
  i=1
  do n=1, numfiles
    if ( rstflag(n) ) then
      FileNamesToProcess(i) = trim(self%datapath)//'/'//trim(self%filenames(n))
      i=i+1
    endif
  enddo

  !tb2 = MPI_Wtime()
! read 2D slab from each file using sub communicator

  ! Only ranks assigned one or more levels from the combined set of levels enter here
  if (MPI_COMM_NULL /= read_comm) then

    if(mype_vartype==NF90_FLOAT) then
      allocate(d3r4(geom%globalsizes(1),geom%globalsizes(2),mype_lbegin:mype_lend))
    elseif(mype_vartype==NF90_DOUBLE .and. kind_real == c_double) then
      ! The file provides c_double and application wants c_double, so don't convert during read
      allocate(d3r8(geom%globalsizes(1),geom%globalsizes(2),mype_lbegin:mype_lend))
    elseif(mype_vartype==NF90_DOUBLE .and. kind_real == c_float) then
      ! The file provides c_double but application wants c_float,
      ! so convert to c_float during read to avoid scattering more data than needed
      allocate(d3r4(geom%globalsizes(1),geom%globalsizes(2),mype_lbegin:mype_lend))
    else
      write(6,*) 'Warning, unknown datatype'
    endif

    call MPI_Info_create(info, ierr)
    call MPI_Info_set(info, "romio_cb_read", "disable", ierr)

    !iret=nf90_open(trim(FileNamesToProcess(mype_fileid)),ior(nf90_nowrite,nf90_mpiio),ncioid,comm=read_comm,info=MPI_INFO_NULL)
    iret=nf90_open(trim(FileNamesToProcess(mype_fileid)),ior(nf90_nowrite,nf90_mpiio),ncioid,comm=read_comm,info=info)
    if(iret/=nf90_noerr) then
      write(6,'("read_restart_fields_reg: Error opening NetCDF file ",2A,I4,A,I4)') &
                 trim(FileNamesToProcess(mype_fileid)),' fileid=',mype_fileid,', Status =',iret
      write(6,*)  nf90_strerror(iret)
      stop 333
    endif

    do ilev=mype_lbegin,mype_lend
      starts=(/1,1,ilev,1/)
      counts=(/geom%globalsizes(1), geom%globalsizes(2), 1, 1/)

      call check( nf90_inq_varid(ncioid, trim(adjustl(mype_varname)), var_id) )
      iret = nf90_var_par_access(ncioid, var_id, nf90_independent)

      if(mype_vartype==NF90_FLOAT) then
        d2r4ptr => d3r4(:,:,ilev)
        call check( nf90_get_var(ncioid,var_id,d2r4ptr,start=starts,count=counts) )
        nullify(d2r4ptr)
      elseif(mype_vartype==NF90_DOUBLE .and. kind_real == c_double) then
        ! The file provides c_double and application wants c_double, so don't convert during read
        d2r8ptr => d3r8(:,:,ilev)
        call check( nf90_get_var(ncioid,var_id,d2r8ptr,start=starts,count=counts) )
        nullify(d2r8ptr)
      elseif(mype_vartype==NF90_DOUBLE .and. kind_real == c_float) then
        ! The file provides c_double but application wants c_float,
        ! so allow NetCDF to convert to c_float during read to avoid
        ! scattering more data than needed.
        d2r4ptr => d3r4(:,:,ilev)
        iret=nf90_get_var(ncioid,var_id,d2r4ptr,start=starts,count=counts)
        nullify(d2r4ptr)
      endif
    enddo  ! ilev

    iret=nf90_close(ncioid)
    call MPI_Info_free(info,ierr)
  endif ! read_comm
  call MPI_Barrier(geom%f_comm%communicator(),ierr)
  !te2 = MPI_Wtime()
  !times(2) = te2-tb2

!
! Scatter file data to all ranks and convert to application type as needed
! ------------------------------------------------------------------------
  !tb3 = MPI_Wtime()

  l = mype_lbegin ! Initialize local level tracker for the Scatter

  do b_start = 1, ntotallev, batch_size
    b_end = min(b_start + batch_size - 1, ntotallev)
    n_in_batch = b_end - b_start + 1

    ! POST ALL PHASE 1 REQUESTS (Column Scatter)
    ! ------------------------------------------
    reqs_p1(:) = MPI_REQUEST_NULL
    do b_ind = 1, n_in_batch
      level = b_start + b_ind - 1
      file_var_idx = LevelToVariableMap(level) ! NetCDF File space
      owner = LevelToProcMap(level)

      if(rank == owner) then
        ! Compiler automatically routes to _r4 or _r8 based on d3r4/d3r8
        if(nc_vartype(file_var_idx) == NF90_FLOAT) then
          call TwoPhaseScatter_Phase1(geom, owner, rank, d3r4(:,:,l), b_ind, reqs_p1(b_ind))
        elseif(nc_vartype(file_var_idx) == NF90_DOUBLE .and. kind_real == c_double) then
          call TwoPhaseScatter_Phase1(geom, owner, rank, d3r8(:,:,l), b_ind, reqs_p1(b_ind))
        elseif(nc_vartype(file_var_idx) == NF90_DOUBLE .and. kind_real == c_float) then
          call TwoPhaseScatter_Phase1(geom, owner, rank, d3r4(:,:,l), b_ind, reqs_p1(b_ind))
        endif
        l=l+1
      else
        ! Non-owners pass the explicitly typed dummy targets
        if(nc_vartype(file_var_idx) == NF90_FLOAT) then
          call TwoPhaseScatter_Phase1(geom, owner, rank, dummy_r4, b_ind, reqs_p1(b_ind))
        elseif(nc_vartype(file_var_idx) == NF90_DOUBLE .and. kind_real == c_double) then
          call TwoPhaseScatter_Phase1(geom, owner, rank, dummy_r8, b_ind, reqs_p1(b_ind))
        elseif(nc_vartype(file_var_idx) == NF90_DOUBLE .and. kind_real == c_float) then
          call TwoPhaseScatter_Phase1(geom, owner, rank, dummy_r4, b_ind, reqs_p1(b_ind))
        endif
      endif
    end do

    ! Wait for all columns to reach the intermediate Row-Roots
    call MPI_Waitall(n_in_batch, reqs_p1, MPI_STATUSES_IGNORE, ierr)

    ! POST ALL PHASE 2 REQUESTS (Row Scatter)
    ! ---------------------------------------
    reqs_p2(:) = MPI_REQUEST_NULL
    do b_ind = 1, n_in_batch
      level = b_start + b_ind - 1
      file_var_idx = LevelToVariableMap(level) ! NetCDF File space
      jedi_var_idx = VarToVarMap(file_var_idx)         ! JEDI space
      owner = LevelToProcMap(level)

      if(nc_vartype(file_var_idx) == NF90_FLOAT .and. kind_real == c_double) then
        ! Route directly into the shared module casting workspace
        call TwoPhaseScatter_Phase2(geom, owner, rank, scatter_recv_cast_workspace_r4(:,:,b_ind), b_ind, reqs_p2(b_ind))
      else
        ! Scatter directly to strictly typed application array
        call TwoPhaseScatter_Phase2(geom, owner, rank, fields(jedi_var_idx)%array(:,:,LevelToLevelMap(level)), &
                                    b_ind, reqs_p2(b_ind))
      endif
    end do

    ! Wait for all rows to hit the final destination ranks
    call MPI_Waitall(n_in_batch, reqs_p2, MPI_STATUSES_IGNORE, ierr)

    ! POST-PROCESS: Type Conversions
    ! ------------------------------
    do b_ind = 1, n_in_batch
      level = b_start + b_ind - 1
      file_var_idx = LevelToVariableMap(level)
      jedi_var_idx = VarToVarMap(file_var_idx)         ! JEDI space

      ! Only convert the scenarios that used the staging buffer
      if(nc_vartype(file_var_idx) == NF90_FLOAT .and. kind_real == c_double) then
        ! Pull from the shared workspace at b_ind, and cast into the true Level slice
        fields(jedi_var_idx)%array(:,:,LevelToLevelMap(level)) = real(scatter_recv_cast_workspace_r4(:,:,b_ind), kind=kind_real)
      endif
    end do
  end do ! batch
  !te3 = MPI_Wtime()
  !times(3) = te3-tb3
  !call MPI_Reduce(times, walltime, 3, MPI_DOUBLE_PRECISION, MPI_MAX, 0, geom%f_comm%communicator(), ierr)
  !if (rank == 0) write(*,'(A,4F12.6)') 'read_restart_fields_reg: Walltimes ', walltime(1), walltime(2), walltime(3), sum(walltime)

  ! Deallocate temporary arrays
  if (MPI_COMM_NULL /= read_comm) then
    if(allocated(d3r4)) deallocate(d3r4)
    if(allocated(d3r8)) deallocate(d3r8)
  endif

  if(allocated(nlev)) deallocate(nlev)

  ! Compute ps from DELP
  ! --------------------
  if (indexof_ps > 0 .and. .not. self%ps_in_file) then
    allocate(delp(fields(indexof_ps)%isc:fields(indexof_ps)%iec, &
                  fields(indexof_ps)%jsc:fields(indexof_ps)%jec,1:self%npz))
    if (.not. havedelp) then
      delp = fields(indexof_ps)%array
      deallocate(fields(indexof_ps)%array)
      allocate(fields(indexof_ps)%array(fields(indexof_ps)%isc:fields(indexof_ps)%iec, &
                  fields(indexof_ps)%jsc:fields(indexof_ps)%jec,1))
    else
      delp = fields(indexof_delp)%array
    endif
    fields(indexof_ps)%array(:,:,1) = geom%ptop + sum(delp,3)
    fields(indexof_ps)%long_name = 'air_pressure_at_surface'
    fields(indexof_ps)%model_name = 'air_pressure_at_surface'
    fields(indexof_ps)%npz = 1
  endif

end subroutine read_restart_fields_reg

! --------------------------------------------------------------------------------------------------

subroutine read_nonrestart_fields(self, fields, field_io_names, field_io_scaling)

type(fv3jedi_io_fms),      intent(inout) :: self
type(fv3jedi_field),       intent(inout) :: fields(:)
type(fckit_configuration), intent(in)    :: field_io_names
type(fckit_configuration), intent(in)    :: field_io_scaling

integer                     :: var
type(FmsNetcdfDomainFile_t) :: fileobj
character(len=field_clen)   :: io_name

! Open file for reading
if ( open_file(fileobj, trim(self%datapath)//'/'//trim(self%filename_nonrestart), 'read', self%domain) ) then
   ! Loop through fields
   do var = 1,size(fields)
      ! Register field
      io_name = ioname(trim(fields(var)%long_name), field_io_names)
      call fv3jedi_register_field(fileobj, io_name, fields(var)%array, center, .false., &
                                  trim(fields(var)%long_name), trim(fields(var)%units))

      ! Read field
      call read_data(fileobj, ioname(trim(fields(var)%long_name), field_io_names), &
                     fields(var)%array)

      ! Scale field if necessary
      call ioscale(fields(var), field_io_scaling)
   end do

   ! Close file
   call close_file(fileobj)
else
   call abor1_ftn('fv3jedi_io_fms_mod.read_nonrestart_fields: file ' &
                  // trim(self%datapath)//'/'//trim(self%filename_nonrestart) // &
                  ' could not be opened')
end if

end subroutine read_nonrestart_fields

! --------------------------------------------------------------------------------------------------

subroutine write_restart_all(self, geom, fields, vdate, field_io_names, field_io_scaling)

type(fv3jedi_io_fms),      intent(inout) :: self
type(fv3jedi_geom),        intent(inout) :: geom
type(fv3jedi_field),       intent(in)    :: fields(:)     !< Fields to be written
type(datetime),            intent(in)    :: vdate         !< DateTime
type(fckit_configuration), intent(in)    :: field_io_names
type(fckit_configuration), intent(in)    :: field_io_scaling

logical :: rstflag(numfiles)
integer :: n, indexrst, var, idrst, date(6)
integer :: idate, isecs
type(FmsNetcdfDomainFile_t) :: fileobj(numfiles)
character(len=64)  :: datefile
character(len=8), allocatable :: dim_names(:)
real(kind=kind_real) :: io_unscaling_factor
character(len=field_clen) :: io_name

! Get datetime
! ------------
call datetime_to_ifs(vdate, idate, isecs)
date(1) = idate/10000
date(2) = idate/100 - date(1)*100
date(3) = idate - (date(1)*10000 + date(2)*100)
date(4) = isecs/3600
date(5) = (isecs - date(4)*3600)/60
date(6) = isecs - (date(4)*3600 + date(5)*60)

! Convert integer datetime into string and prepend file names
! -----------------------------------------------------------
write(datefile,'(I4,I0.2,I0.2,A1,I0.2,I0.2,I0.2,A1)') date(1),date(2),date(3),".",&
                                                      date(4),date(5),date(6),"."

if (self%prepend_date) then
  do n = 1, numfiles
    self%filenames(n) = trim(datefile)//trim(self%filenames(n))
  enddo
endif

! Use prefix if present
! ---------------------
if (self%has_prefix) then
  do n = 1, numfiles
    self%filenames(n) = trim(self%prefix)//"."//trim(self%filenames_conf(n))
  enddo
endif

rstflag(:) = .false.

! Loop over fields and register their restart file
! ------------------------------------------------
do var = 1,size(fields)

  ! Get file to use
  call get_io_file(self, fields(var), indexrst)

  ! Flag to write this restart
  if ( .not. rstflag(indexrst) ) then
     if ( open_file(fileobj(indexrst), &
          trim(self%datapath)//'/'//trim(self%filenames(indexrst)), &
          'overwrite', self%domain, is_restart=.true., dont_add_res_to_filename=.true.) ) then
        rstflag(indexrst) = .true.
     else
        call abor1_ftn('fv3jedi_io_fms_mod.write_restart_all: file ' &
                        // trim(self%datapath)//'/'//trim(self%filenames(indexrst)) // &
                       ' could not be opened')
     end if
  end if

  ! Get the scaling factor
  io_unscaling_factor = iounscale(fields(var)%long_name, field_io_scaling)

  ! Register restart field
  io_name = ioname(trim(fields(var)%long_name), field_io_names)
  call fv3jedi_register_field(fileobj(indexrst), io_name, fields(var)%array, center, .true., &
                              trim(fields(var)%long_name), trim(fields(var)%units))
enddo

! Loop over files and write fields
! --------------------------------
do n = 1, numfiles
  if (rstflag(n)) then
    call write_restart(fileobj(n))
    call close_file(fileobj(n))
  endif
enddo

!Write date/time info in coupler.res
!-----------------------------------
if (mpp_pe() == mpp_root_pe() .and. .not. self%skip_coupler) then
   open(101, file = trim(adjustl(self%datapath))//'/'// &
        trim(adjustl(self%filenames(self%index_cplr))), form='formatted')
   write( 101, '(i6,8x,a)' ) self%calendar_type, &
        '(Calendar: no_calendar=0, thirty_day_months=1, julian=2, gregorian=3, noleap=4)'
   write( 101, '(6i6,8x,a)') date, 'Model start time:   year, month, day, hour, minute, second'
   write( 101, '(6i6,8x,a)') date, 'Current model time: year, month, day, hour, minute, second'
   close(101)
endif

end subroutine write_restart_all

! --------------------------------------------------------------------------------------------------

subroutine write_restart_all_reg(self, geom, fields, vdate, field_io_names, field_io_scaling)
use module_ncfile_stat, only : ncfile_stat
use TwoPhaseScatterGather
use, intrinsic :: iso_c_binding
implicit none

interface
  integer(c_int) function nc_set_alignment(threshold, alignment) bind(c, name="nc_set_alignment")
    import :: c_int
    integer(c_int), value :: threshold
    integer(c_int), value :: alignment
  end function nc_set_alignment
end interface

type(fv3jedi_io_fms),      intent(inout) :: self
type(fv3jedi_geom),        intent(inout) :: geom
type(fv3jedi_field), target, asynchronous, intent(inout) :: fields(:)     !< Fields to be written
type(datetime),            intent(in)    :: vdate         !< DateTime
type(fckit_configuration), intent(in)    :: field_io_names
type(fckit_configuration), intent(in)    :: field_io_scaling

type(file_t), save :: FileType(numfiles)
character(len=500), save  :: tmpvarlist(numfiles)
integer, save :: totalnumfiles, my_jedi_index
integer, save :: num_restart_vars(numfiles)
integer :: ncid(numfiles)

character(len=500), allocatable  :: varlist(:)
integer(kind=4), allocatable :: nlev(:)!, nlevpervar(:)
real(kind=4), target :: dummy_r4(1,1)
real(kind=8), target :: dummy_r8(1,1)
real(kind=4), target :: dummy_r4_3d(1,1,1)
real(kind=8), target :: dummy_r8_3d(1,1,1)

type(ncfile_stat) :: ncfs_all

character(len=7) :: ydim_name

! sub communicator
integer :: color, key

integer :: i, n, r, k, indexrst, file_var_idx, jedi_var_idx, date(6), sz
integer :: rank, npes, varid, level, l, ierr, rc, rc2, b, e, position
integer :: newvar_dimids(4)
integer :: idate, isecs
integer :: b_start, b_end, n_in_batch, b_ind, owner

integer :: b_idx, e_idx, my_levels, total_levels
integer :: my_ost_count!, stripeSize
character(len=8) :: ost_str
character(len=12) :: stripeSize_str

!real (kind=8) :: times(9), walltime(9), tb, te
integer                      :: nn, write_rank

integer :: startloc(4), countloc(4)
character(len=64)  :: datefile
real(kind=kind_real) :: io_unscaling_factor
integer :: dimids(4), oldMode
integer, dimension(:), allocatable :: chunksizes

integer(kind=8), allocatable :: local_chksums(:), global_chksums(:)
logical, allocatable :: is_new_var(:)
integer(kind=4) :: mold4(1)
integer(kind=8) :: mold8(1)
character(len=32) :: chksum

character(len=72), allocatable :: tmp_names(:)
integer,           allocatable :: tmp_d1(:), tmp_d2(:), tmp_d3(:)
integer,           allocatable :: tmp_nd(:), tmp_vt(:), tmp_fid(:)

integer, allocatable :: out_fileid(:), out_lvlbegin(:), out_lvlend(:)
character(len=72), allocatable :: out_varname(:)
integer :: file_idx, var_type_tmp

logical :: write_field, file_exists(numfiles)
character(len=72), save :: fields_str, res_str, action_str

integer, save :: cached_nfields = -1
logical :: fields_changed
integer :: f, nz

rank=mpp_pe()
npes=mpp_npes()

!times(:)=0.0
!walltime(:)=0.0

! Get datetime
! ------------
call datetime_to_ifs(vdate, idate, isecs)
date(1) = idate/10000
date(2) = idate/100 - date(1)*100
date(3) = idate - (date(1)*10000 + date(2)*100)
date(4) = isecs/3600
date(5) = (isecs - date(4)*3600)/60
date(6) = isecs - (date(4)*3600 + date(5)*60)

! Convert integer datetime into string and prepend file names
! -----------------------------------------------------------
write(datefile,'(I4,I0.2,I0.2,A1,I0.2,I0.2,I0.2,A1)') date(1),date(2),date(3),".",&
                                                      date(4),date(5),date(6),"."

!call MPI_Barrier(geom%f_comm%communicator(), ierr) ! Only needed if you enable the timers
!tb = MPI_Wtime()
if (self%prepend_date) then
  do n = 1, numfiles
    self%filenames(n) = trim(datefile)//trim(self%filenames(n))
  enddo
endif

! Use prefix if present
! ---------------------
if (self%has_prefix) then
  do n = 1, numfiles
    if (self%prepend_date) then
      self%filenames(n) = trim(self%prefix)//"."//trim(datefile)//trim(self%filenames_conf(n))
    else
      self%filenames(n) = trim(self%prefix)//"."//trim(self%filenames_conf(n))
    end if
  enddo
endif

! Check for field changes (order or size)
! ---------------------------------------
fields_changed = .false.
! If cache not initialized, force rebuild
if (cached_nfields < 0) then
  fields_changed = .true.
  if(rank==0) write(6,'("write_restart_all_reg: Init fields_changed")')
elseif (cached_nfields /= size(fields)) then
  fields_changed = .true.
  if(rank==0) write(6,'("write_restart_all_reg: cached_nfields /= size(fields)",2I4)') cached_nfields,size(fields)
elseif (.not. allocated(cached_field_names) .or. .not. allocated(cached_field_nz)) then
  fields_changed = .true.
  if(rank==0) write(6,'("write_restart_all_reg: cached_field_names or cached_field_nz not allocated cached_field_nz")')
elseif (size(cached_field_names) /= size(fields) .or. size(cached_field_nz) /= size(fields)) then
  fields_changed = .true.
  if(rank==0) write(6,'("write_restart_all_reg: size of cached_field_names or cached_field_nz not right")')
else
  do f = 1, size(fields)
    if (allocated(fields(f)%array)) then
      nz = size(fields(f)%array, 3)
    else
      nz = -1
    endif
    if (trim(fields(f)%long_name) /= trim(cached_field_names(f))) then
      fields_changed = .true.
      if(rank==0) write(6,'("write_restart_all_reg: field name order is different",I4,5A)') &
                        f,' (', trim(fields(f)%model_name),') /= (', trim(cached_field_names(f)),')'
      exit
    endif
    if (nz /= cached_field_nz(f)) then
      fields_changed = .true.
      if(rank==0) write(6,'("write_restart_all_reg: nz is different")')
      exit
    endif
  enddo
endif

! If the Geometry changes, reallocate Scatter structure and rescan input files
! Do this only for the first ensemble member to save significant time
! ----------------------------------------------------------------------------
if( (fields_changed) .or. &
    (geom%globalsizes(1) .ne. cached_globalsizes(1)) .or. &
    (geom%globalsizes(2) .ne. cached_globalsizes(2)) ) then

  !tb1 = MPI_Wtime()

  ! Update cached fields
  cached_nfields = size(fields)
  if (allocated(cached_field_names)) deallocate(cached_field_names)
  if (allocated(cached_field_nz))    deallocate(cached_field_nz)
  allocate(cached_field_names(cached_nfields))
  allocate(cached_field_nz(cached_nfields))
  do f = 1, cached_nfields
    cached_field_names(f) = fields(f)%long_name
    if (allocated(fields(f)%array)) then
      cached_field_nz(f) = size(fields(f)%array, 3)
    else
      cached_field_nz(f) = -1
    endif
  enddo

  cached_globalsizes = geom%globalsizes

  if(.not. write_first_pass) then
    call TwoPhaseGather_delete()
  endif

  rstflag(:) = .false.
  file_exists(:) = .false.
  ncid(:)=-999
  num_restart_vars(:)=0
  tmpvarlist=''

  ! Loop over fields to figure out where all the variables go
  ! ---------------------------------------------------------
  do jedi_var_idx = 1,size(fields)
    ! Check if the user specified a list of fields to write
    if ( trim(self%fields_to_write(1) ) == 'All') then
      !if(rank==0) write(*,'("write_restart_all_reg: Default writing all fields")')
    else
      write_field = .false.
      do n = 1,size(self%fields_to_write)
        if (trim(self%fields_to_write(n)) == trim(fields(jedi_var_idx)%long_name)) then
          !if(rank==0) write(*,'("write_restart_all_reg: writing field ",A)') trim(fields(jedi_var_idx)%long_name)
          write_field = .true.
        end if
      end do
      if(.not. write_field) then
        !if(rank==0) write(*,'("write_restart_all_reg: NOT writing field ",A)') trim(fields(jedi_var_idx)%long_name)
        cycle
      endif
    end if

    ! Get file to use
    call get_io_file(self, fields(jedi_var_idx), indexrst)
    fields(jedi_var_idx)%model_name = ioname(trim(fields(jedi_var_idx)%long_name), field_io_names)
  
    rstflag(indexrst) = .true.
    num_restart_vars(indexrst) = num_restart_vars(indexrst) + 1
    FileType(indexrst)%VariableIndecies(num_restart_vars(indexrst)) = jedi_var_idx

    ! Append variable name onto list for each file.  Will need a mapping between this list and the order in the fields array
    if (len_trim(tmpvarlist(indexrst)) > 0) then
      tmpvarlist(indexrst)=trim(tmpvarlist(indexrst)) //' '// trim(fields(jedi_var_idx)%model_name)
    else
      tmpvarlist(indexrst)=trim(fields(jedi_var_idx)%model_name)
    endif

    ! Get the scaling factor
    io_unscaling_factor = iounscale(fields(jedi_var_idx)%long_name, field_io_scaling)
  enddo

  totalnumfiles=count(rstflag(:) .eqv. .true.)
  if(allocated(FileNamesToProcess)) deallocate(FileNamesToProcess)
  allocate(FileNamesToProcess(totalnumfiles))

  if(allocated(numvarfile)) deallocate(numvarfile)
  allocate(numvarfile(totalnumfiles))

  allocate(varlist(totalnumfiles))
  !te = MPI_Wtime()
  !times(1) = te-tb

  ! Create output file names, determine if the files exists.
  ! Make sure user controllable options make sense and print some diagnostics
  ! -------------------------------------------------------------------------
  !tb = MPI_Wtime()
  if (trim(self%fields_to_write(1)) == 'All') then
    fields_str = "ALL fields"
  else
    fields_str = "specified fields"
  endif

  select case (trim(self%default_output_resolution))
    case ('native')
      res_str = "JEDI native bitdepth"
    case ('32bit')
      res_str = "user specified 32-bit bitdepth"
    case ('64bit')
      res_str = "user specified 64-bit bitdepth"
  end select

  i = 1
  do n = 1, numfiles
    if (rstflag(n)) then
      FileNamesToProcess(i) = trim(self%datapath)//'/'//trim(self%filenames(n))
      inquire (file=trim(FileNamesToProcess(i)), EXIST=file_exists(i), SIZE=sz)

      if (file_exists(i) .and. sz == 0) then
        if (self%write_into_existing_files) then
          ! Fatal Error: User wants to append/update, but the target file is empty
          if(rank==0) write(6,'("ERROR: write_into_existing_files=true but file is zero length! ",A)') trim(FileNamesToProcess(i))
          call flush(6)
          call MPI_Abort(geom%f_comm%communicator(), 44, ierr)
        else
          ! Treat the empty file as non-existent so we create it from scratch
          ! instead of attempting to read its headers in ncfs_all%fill_dims()
          file_exists(i) = .false.
        endif
      endif

      numvarfile(i) = num_restart_vars(n)
      varlist(i)    = tmpvarlist(n)

      ! Changing bit resolution in existing files is not supported
      if (file_exists(i) .and. self%write_into_existing_files .and. trim(self%default_output_resolution) /= 'native') then
        if(rank==0) write(6,'("write_restart_all_reg: ERROR Scenario not supported: Cannot change resolution of existing files")')
        call flush(6)
        call MPI_Abort(geom%f_comm%communicator(), 39, ierr)
      endif

      ! Cannot write into existing files if they don't exist
      if (self%write_into_existing_files .and. .not. file_exists(i)) then
        if(rank==0) write(6,'("ERROR: write_into_existing_files=true yet the file does not exist ",A)') trim(FileNamesToProcess(i))
        call flush(6)
        call MPI_Abort(geom%f_comm%communicator(), 40, ierr)
      endif

      ! Dynamically build the diagnostic message and print once
      if (self%write_into_existing_files) then
        action_str = "Replace " // trim(fields_str) // " in existing file."
      else if (.not. file_exists(i)) then
        action_str = "Create new file and write " // trim(fields_str) // " in " // trim(res_str) // "."
      else
        action_str = "Clobber existing file and write " // trim(fields_str) // " in " // trim(res_str) // "."
      endif

      if (rank == 0) write(6,'(A," ",A)') trim(action_str), trim(FileNamesToProcess(i))

      i=i+1
    endif
  enddo
  !te = MPI_Wtime()
  !times(2) = te-tb

  ! Load balancing
  ! --------------
  !tb = MPI_Wtime()
  ! Group ranks by physical shared-memory node
  call MPI_Comm_split_type(geom%f_comm%communicator(), MPI_COMM_TYPE_SHARED, 0, MPI_INFO_NULL, node_comm, ierr)
  call MPI_Comm_rank(node_comm, local_rank, ierr)

  ! Determine the number of physical computers being used.
  ! Will use that number as the batch size for non-blocking gather
  is_node_leader = 0
  if (local_rank == 0) is_node_leader = 1
  call MPI_Allreduce(is_node_leader, total_nodes, 1, MPI_INTEGER, MPI_SUM, geom%f_comm%communicator(), ierr)

  batch_size=max(1,total_nodes)
  !batch_size_gather=total_nodes
  !batch_size_scatter=2*batch_size_gather  ! Some evidence that scatter can benefit from a larger batch_size

  call MPI_Comm_free(node_comm, ierr)

  ! Interleave ranks across nodes using local_rank as the sort key
  call MPI_Comm_split(geom%f_comm%communicator(), 0, local_rank, spread_comm, ierr)
  call MPI_Comm_rank(spread_comm, spread_mype, ierr)

  ! Create a dictionary to map the new interleaved rank back to the true world rank
  allocate(spread_to_world(0:npes-1))
  call MPI_Allgather(rank, 1, MPI_INTEGER, spread_to_world, 1, MPI_INTEGER, spread_comm, ierr)

  ! Total number of variables that will actually be read from files
  ! (this can be smaller than size(fields) when PS is computed from DELP)
  if(allocated(nlevpervar)) deallocate(nlevpervar)
  allocate(nlevpervar(sum(numvarfile)))

  if(allocated(varnames)) deallocate(varnames)
  allocate(varnames(sum(numvarfile)))

  if(allocated(nc_vartype)) deallocate(nc_vartype)
  allocate(nc_vartype(sum(numvarfile)))

  if(allocated(nlev)) deallocate(nlev)
  allocate(nlev(0:npes-1))

  !te = MPI_Wtime()
  !times(3) = te-tb

  ! Scan the supplied output files to determine variable type, number of levels then
  ! distribute the load evenly among the available nodes/ranks
  if(all(file_exists(1:totalnumfiles) .eqv. .true.)) then
    !tb = MPI_Wtime()
    ! init on all ranks to avoid passing unallocated allocatable to MPI_Scatter
    allocate(out_fileid(npes), out_varname(npes), out_lvlbegin(npes), out_lvlend(npes))
    if (spread_mype == 0) then
      call ncfs_all%init(totalnumfiles, FileNamesToProcess, numvarfile, varlist)
      call ncfs_all%fill_dims()

      allocate(tmp_names(ncfs_all%numvar), tmp_d3(ncfs_all%numvar), tmp_fid(ncfs_all%numvar))

      ! Extract variables from NetCDF metadata
      tmp_names = ncfs_all%list_varname(1:ncfs_all%numvar)
      tmp_d3    = ncfs_all%dim_3(1:ncfs_all%numvar)

      ! Build the file ID map (which variables belong to which file index)
      i = 0
      do n = 1, ncfs_all%numfiles
        do k = 1, ncfs_all%numvarfile(n)
          i = i + 1
          tmp_fid(i) = n
        enddo
      enddo

      ! distibute variables to each core
      call distribute_io_work(npes, ncfs_all%numvar, tmp_names, tmp_d3, tmp_fid, &
                              out_fileid, out_varname, out_lvlbegin, out_lvlend, nlev)
      nlev(:)=0
      do i=0,npes-1
        if( (out_lvlend(i+1) > 0) .and. (out_lvlbegin(i+1) > 0) ) then
          nlev(i) = (out_lvlend(i+1) - out_lvlbegin(i+1) + 1)
        endif
      enddo
      ntotallev = sum(ncfs_all%dim_3)

      nlevpervar(:) = ncfs_all%dim_3(:)
      varnames(:) = ncfs_all%list_varname(:)  ! Names of variables to be processed
      nc_vartype(:) = ncfs_all%vartype(:)        ! NetCDF type of each variable
      numvarfile(:) = ncfs_all%numvarfile(:)  ! Number of variables in each file

      deallocate(tmp_names, tmp_d3, tmp_fid)
      call ncfs_all%close()
    end if

    ! Let all ranks know what is going on
    call MPI_Scatter(out_fileid  ,  1,   mpi_integer, mype_fileid ,  1, mpi_integer  , 0, spread_comm,ierr)
    call MPI_Scatter(out_varname , 72, mpi_character, mype_varname, 72, mpi_character, 0, spread_comm,ierr)
    call MPI_Scatter(out_lvlbegin,  1,   mpi_integer, mype_lbegin ,  1, mpi_integer  , 0, spread_comm,ierr)
    call MPI_Scatter(out_lvlend  ,  1,   mpi_integer, mype_lend   ,  1, mpi_integer  , 0, spread_comm,ierr)
    deallocate(out_fileid, out_varname, out_lvlbegin, out_lvlend)

    call MPI_Bcast(ntotallev    , 1, mpi_integer, 0, spread_comm,ierr)
    call MPI_Bcast(nlev(0)      , npes, mpi_integer, 0, spread_comm,ierr)
    call MPI_Bcast(nlevpervar(1), sum(numvarfile), mpi_integer, 0, spread_comm,ierr)
    call MPI_Bcast(varnames(1)  , 72*sum(numvarfile), mpi_character, 0, spread_comm,ierr)
    call MPI_Bcast(nc_vartype(1), sum(numvarfile), mpi_integer, 0, spread_comm,ierr)

    !te = MPI_Wtime()
    !times(4) = te-tb
  else  ! No files provided.  All ranks compute the distribution locally
    !tb = MPI_Wtime()
    nn = sum(numvarfile) ! Total variables across all files

    ! Create temporary arrays to hold field info for the arranger
    allocate(tmp_names(nn), tmp_d1(nn), tmp_d2(nn), tmp_d3(nn), tmp_nd(nn), tmp_vt(nn), tmp_fid(nn))
    allocate(out_fileid(npes), out_varname(npes), out_lvlbegin(npes), out_lvlend(npes))

    select case (trim(self%default_output_resolution))
    case ('native')
      var_type_tmp = merge(NF90_DOUBLE, NF90_FLOAT, kind_real == c_double)
    case ('32bit')
      var_type_tmp    = NF90_FLOAT
    case ('64bit')
      var_type_tmp    = NF90_DOUBLE
    end select

    i = 0
    file_idx = 0
    do n = 1, numfiles
      if (.not. rstflag(n)) cycle
      file_idx = file_idx + 1
      do k = 1, num_restart_vars(n)
        i = i + 1
        jedi_var_idx = FileType(n)%VariableIndecies(k)

        tmp_names(i) = trim(fields(jedi_var_idx)%model_name)
        tmp_d3(i)    = size(fields(jedi_var_idx)%array, 3)
        tmp_nd(i)    = merge(3, 2, tmp_d3(i) > 1)
        tmp_fid(i)   = file_idx
      end do
    end do

    ! Call the new direct arranger
    call distribute_io_work(npes, nn, tmp_names, tmp_d3, tmp_fid, &
                            out_fileid, out_varname, out_lvlbegin, out_lvlend, nlev)

    mype_fileid  = out_fileid(spread_mype + 1)
    mype_varname = out_varname(spread_mype + 1)
    mype_vartype = var_type_tmp
    mype_lbegin  = out_lvlbegin(spread_mype + 1)
    mype_lend    = out_lvlend(spread_mype + 1)

    ! Fill the global metadata arrays that everyone needs
    ntotallev = sum(tmp_d3)
    nlevpervar(1:nn) = tmp_d3
    varnames(1:nn)   = tmp_names
    nc_vartype(1:nn) = var_type_tmp

    ! Calculate nlev per rank
    nlev(:) = 0
    do r = 0, npes - 1
      if (out_lvlend(r+1) > 0) nlev(r) = out_lvlend(r+1) - out_lvlbegin(r+1) + 1
    end do

    deallocate(tmp_names, tmp_d1, tmp_d2, tmp_d3, tmp_nd, tmp_vt, tmp_fid)
    deallocate(out_fileid, out_varname, out_lvlbegin, out_lvlend)
    !te = MPI_Wtime()
    !times(5) = te-tb
  end if ! Output files do not exist

  deallocate(varlist)

  !tb = MPI_Wtime()
  do file_var_idx = 1,sum(numvarfile)
    if (trim(varnames(file_var_idx)) == trim(adjustl(mype_varname))) my_var_index=file_var_idx
  enddo

  ! Map field level to the process handling that level
  ! LevelToProcMap(levelIndex) gives the rank
  if(allocated(LevelToProcMap)) deallocate(LevelToProcMap)
  allocate(LevelToProcMap(ntotallev))
  LevelToProcMap(:) = -999
  l=1
  do r=0,npes-1
    do i=1,nlev(r)
      LevelToProcMap(l) = spread_to_world(r)
      l=l+1
    enddo
  enddo
  call MPI_Comm_free(spread_comm, ierr)
  deallocate(spread_to_world)
  deallocate(nlev)

  if (any(LevelToProcMap(:) == -999)) then
    write(6,'("write_restart_all_reg: Some sigma level were not assigned")')
    call MPI_Abort(geom%f_comm%communicator(),10,ierr)
  endif

  ! Map combined level to variable
  ! LevelToVariableMap(levelIndex) gives an index into the fields array
  if(allocated(LevelToVariableMap)) deallocate(LevelToVariableMap)
  allocate(LevelToVariableMap(ntotallev))
  LevelToVariableMap(:) = -999
  l=1
  do file_var_idx=1,sum(numvarfile)
    do i=1,nlevpervar(file_var_idx)
      LevelToVariableMap(l) = file_var_idx
      l=l+1
    enddo
  enddo

  if (any(LevelToVariableMap(:) == -999)) then
    position = findloc(LevelToVariableMap, value=-999, dim=1, back=.false.)
    write(6,'("write_restart_all_reg: Some variables were not assigned ",2I6)') ntotallev,position
    call MPI_Abort(geom%f_comm%communicator(),11,ierr)
  endif

  ! Map combined level to variable level
  ! LevelToLevelMap(levelIndex) gives an index into fields(var)%array
  if(allocated(LevelToLevelMap)) deallocate(LevelToLevelMap)
  allocate(LevelToLevelMap(ntotallev))
  LevelToLevelMap(:) = -999
  l=1
  do file_var_idx=1,sum(numvarfile)
    do i=1,nlevpervar(file_var_idx)
      LevelToLevelMap(l) = i
      l=l+1
    enddo
  enddo

  if (any(LevelToLevelMap(:) == -999)) then
    write(6,'("write_restart_all_reg: Some levels were not assigned")')
    call MPI_Abort(geom%f_comm%communicator(),12,ierr)
  endif

  ! Map JEDI fields array to variable list obtained from above
  ! VarToVarMap(jedi_var_idx) gives an index into fields(var).
  ! The jedi_var_idx index would come from LevelToVariableMap()
  if(allocated(VarToVarMap)) deallocate(VarToVarMap)
  allocate(VarToVarMap(sum(numvarfile)))
  VarToVarMap(:) = -999
  do jedi_var_idx = 1, size(fields)
    do file_var_idx = 1, sum(numvarfile)
      if (trim(fields(jedi_var_idx)%model_name) == trim(varnames(file_var_idx))) then
        VarToVarMap(file_var_idx) = jedi_var_idx
        exit
      endif
    enddo
  enddo

  if (any(VarToVarMap(:) == -999)) then
    write(6,'("write_restart_all_reg: Some variables not mapped",21I6)') VarToVarMap(1:sum(numvarfile))
    call MPI_Abort(geom%f_comm%communicator(),112,ierr)
  endif

  my_jedi_index = -999
  if (my_var_index > 0) my_jedi_index = VarToVarMap(my_var_index)

  ! Create sub-communicator to handle each file
  key=rank+1
  if(mype_fileid > 0 .and. mype_fileid <= totalnumfiles) then
    color = mype_fileid
  else
    color = MPI_UNDEFINED
  endif

  call MPI_Comm_split(geom%f_comm%communicator(),color,key,write_comm,ierr)
  if ( ierr /= 0 ) then
    write(6,'(a,i5)')'***ERROR*** after mpi_comm_create with iret = ',ierr
    call mpi_abort(geom%f_comm%communicator(),101,ierr)
  endif

  ! Allocate memory to hold the reconstructed array
  ! Assume the user wants to save variables in the application bit size (kind_real)
  if (MPI_COMM_NULL /= write_comm) then
    if(allocated(write_buffers)) then
      do jedi_var_idx= 1,size(write_buffers)
        if(allocated(write_buffers(jedi_var_idx)%r4)) deallocate(write_buffers(jedi_var_idx)%r4)
        if(allocated(write_buffers(jedi_var_idx)%r8)) deallocate(write_buffers(jedi_var_idx)%r8)
      enddo
      deallocate(write_buffers)
    endif

    allocate(write_buffers(size(fields)))
    do file_var_idx = 1,sum(numvarfile)
      jedi_var_idx = VarToVarMap(file_var_idx)
      if (nc_vartype(file_var_idx) == NF90_FLOAT) then
        allocate(real(kind=c_float)::write_buffers(jedi_var_idx)%r4(geom%globalsizes(1),geom%globalsizes(2),mype_lbegin:mype_lend))
      else
        allocate(real(kind=c_double)::write_buffers(jedi_var_idx)%r8(geom%globalsizes(1),geom%globalsizes(2),mype_lbegin:mype_lend))
      endif
    enddo
  endif ! write_comm
  !te = MPI_Wtime()
  !times(6) = te-tb

  ! Allocate a place to store arrays and MPI datatypes used in TwoPhaseGather_Phase1() and TwoPhaseGather_Phase2()
  ! Assume we are done scattering and run its cleanup routine
  call TwoPhaseScatter_delete()  ! Assuming we don't need to call read_restart_fields_reg() again
  call TwoPhaseGather_init(npes, geom%globalsizes(1), geom%localsizes, batch_size)
  write_first_pass = .false.
endif

! Check file existence on every pass
if(.not. write_first_pass) then
  i = 1
  do n = 1, numfiles
    if (rstflag(n)) then
      FileNamesToProcess(i) = trim(self%datapath)//'/'//trim(self%filenames(n))
      inquire (file=trim(FileNamesToProcess(i)), EXIST=file_exists(i), SIZE=sz)

      if (file_exists(i) .and. sz == 0) then
        if (self%write_into_existing_files) then
          ! Fatal Error: User wants to append/update, but the target file is empty
          if(rank==0) write(6,'("ERROR: write_into_existing_files=true but file is zero length! ",A)') trim(FileNamesToProcess(i))
          call flush(6)
          call MPI_Abort(geom%f_comm%communicator(), 44, ierr)
        else
          ! Treat the empty file as non-existent so we create it from scratch
          ! instead of attempting to read its headers in ncfs_all%fill_dims()
          file_exists(i) = .false.
        endif
      endif

      ! Changing bit resolution in existing files is not supported
      if (file_exists(i) .and. self%write_into_existing_files .and. trim(self%default_output_resolution) /= 'native') then
        if(rank==0) write(6,'("write_restart_all_reg: ERROR Scenario not supported: Cannot change resolution of existing files")')
        call flush(6)
        call MPI_Abort(geom%f_comm%communicator(), 39, ierr)
      endif

      ! Cannot write into existing files if they don't exist
      if (self%write_into_existing_files .and. .not. file_exists(i)) then
        if(rank==0) write(6,'("ERROR: write_into_existing_files=true yet the file does not exist ",A)') trim(FileNamesToProcess(i))
        call flush(6)
        call MPI_Abort(geom%f_comm%communicator(), 40, ierr)
      endif

      ! Dynamically build the diagnostic message and print once
      if (self%write_into_existing_files) then
        action_str = "Replace " // trim(fields_str) // " in existing file."
      else if (.not. file_exists(i)) then
        action_str = "Create new file and write " // trim(fields_str) // " in " // trim(res_str) // "."
      else
        action_str = "Clobber existing file and write " // trim(fields_str) // " in " // trim(res_str) // "."
      endif

      if (rank == 0) write(6,'(A," ",A)') trim(action_str), trim(FileNamesToProcess(i))

      i=i+1
    endif
  enddo
endif

! Gather subdomains into global slabs
! ToDo: I think this batch loop should be a subroutine in TwoPhaseScatterGather()
!tb = MPI_Wtime()
if(allocated(reqs_p1)) deallocate(reqs_p1)
if(allocated(reqs_p2)) deallocate(reqs_p2)
allocate(reqs_p1(batch_size), reqs_p2(batch_size))

if (rank== 0) write(6,'("Gather subdomains into global slabs")')
l=mype_lbegin
do b_start = 1, ntotallev, batch_size
  b_end = min(b_start + batch_size - 1, ntotallev)
  n_in_batch = b_end - b_start + 1

  ! POST ALL PHASE 1 REQUESTS
  ! -------------------------
  reqs_p1(:) = MPI_REQUEST_NULL
  do b_ind = 1, n_in_batch
    level = b_start + b_ind - 1
    file_var_idx = LevelToVariableMap(level)
    jedi_var_idx = VarToVarMap(file_var_idx)
    owner = LevelToProcMap(level)

    ! OPTIMIZATION: Downcast local data before sending if the file expects 32-bit!
    if (nc_vartype(file_var_idx) == NF90_FLOAT .and. kind_real == c_double) then
      ! Cast the local 64-bit slice into the 32-bit send workspace
      gather_send_cast_workspace_r4(:,:,b_ind) = real(fields(jedi_var_idx)%array(:,:,LevelToLevelMap(level)), kind=c_float)
      ! Pass the 32-bit workspace to the Phase 1 Gather (halving network traffic)
      call TwoPhaseGather_Phase1(geom, owner, rank, gather_send_cast_workspace_r4(:,:,b_ind), b_ind, reqs_p1(b_ind))
    else
      ! Send the native application type (no downcast needed)
      call TwoPhaseGather_Phase1(geom, owner, rank, fields(jedi_var_idx)%array(:,:,LevelToLevelMap(level)), b_ind, reqs_p1(b_ind))
    endif
  end do

  call MPI_Waitall(n_in_batch, reqs_p1, MPI_STATUSES_IGNORE, ierr)

  ! POST ALL PHASE 2 REQUESTS
  ! -------------------------
  reqs_p2(:) = MPI_REQUEST_NULL
  do b_ind = 1, n_in_batch
    level = b_start + b_ind - 1
    file_var_idx = LevelToVariableMap(level)
    jedi_var_idx = VarToVarMap(file_var_idx)
    owner = LevelToProcMap(level)

    if(rank == owner) then
      if (nc_vartype(file_var_idx) == NF90_FLOAT) then
        call TwoPhaseGather_Phase2(geom, owner, rank, write_buffers(jedi_var_idx)%r4(:,:,l), b_ind, reqs_p2(b_ind))
      else
        call TwoPhaseGather_Phase2(geom, owner, rank, write_buffers(jedi_var_idx)%r8(:,:,l), b_ind, reqs_p2(b_ind))
      endif
      l=l+1
    else
      ! Non-owners hit MPI_BOTTOM via dummies routed by kind_real
      if (nc_vartype(file_var_idx) == NF90_FLOAT) then
        call TwoPhaseGather_Phase2(geom, owner, rank, dummy_r4, b_ind, reqs_p2(b_ind))
      else
        call TwoPhaseGather_Phase2(geom, owner, rank, dummy_r8, b_ind, reqs_p2(b_ind))
      endif
    endif
  end do

  call MPI_Waitall(n_in_batch, reqs_p2, MPI_STATUSES_IGNORE, ierr)
end do ! Outer batch loop
!te = MPI_Wtime()
!times(7) = te-tb

! Create files using a single rank
! --------------------------------
!tb = MPI_Wtime()
if (write_comm /= MPI_COMM_NULL) then
  n = mype_fileid
  call MPI_Comm_rank(write_comm, write_rank, ierr)

  ! Globally configure the NetCDF-C library to align chunks to stripeSize bytes
  ! 0 means apply to all chunks.
  rc = nc_set_alignment(int(0, c_int), int(self%lustre_stripe_size, c_int))
  if (rc /= nf90_noerr) then
    write(6,*) "Warning: nc_set_alignment failed!"
  endif

  ! Calculate total levels across ALL files
  total_levels = sum(nlevpervar(1 : sum(numvarfile(1:totalnumfiles))))

  ! Calculate the total levels for THIS rank's assigned file
  if (mype_fileid == 1) then
    b_idx = 1
  else
    b_idx = sum(numvarfile(1:mype_fileid-1)) + 1
  endif
  e_idx = b_idx + numvarfile(mype_fileid) - 1
  my_levels = sum(nlevpervar(b_idx:e_idx))
  !write(6, '("write_restart_all_reg: total_levels=", I0,", my_levels=",I0)') total_levels,my_levels

  ! Assign proportional OSTs (Guaranteeing at least 1 OST per file)
  ! assume the underlying Lustre file system has 32 OSTs
  ! ToDo: Need to figure out how to query the file system for the number of OSTs
  my_ost_count = max(1, nint( 32.0 * real(my_levels) / real(total_levels) ))

  ! Print the distribution from rank 0 of each file communicator
  if (write_rank == 0) then
    write(6,'("File ",A," id= ",I2," has ",I4," levels and gets ",I2," OSTs using stripeSize= ",I8)') &
            trim(FileNamesToProcess(n)),mype_fileid, my_levels, my_ost_count, self%lustre_stripe_size
  endif

  ! Communicate variable checksum so the rank that creates the file will be able to add it to the file
  allocate(local_chksums(b_idx:e_idx))
  allocate(global_chksums(b_idx:e_idx))
  local_chksums = 0_8
  global_chksums = 0_8

  ! Tracks which variables in this file were just created (vs. already present)
  ! by the write_into_existing_files probe below: brand new variables have never
  ! had their storage allocated (NF90_NOFILL), so their first write must use
  ! collective parallel access (see the write loop further below). Every rank in
  ! write_comm allocates this (needed as the MPI_Bcast target), but only
  ! write_rank==0 actually populates it.
  !
  ! Caveat: if a prior run created this variable's schema but crashed before
  ! completing its first write, this probe will find it "already exists" and
  ! independent access will be selected again, reproducing the same NetCDF
  ! "Attempt to extend dataset" abort. Restore the background file from backup
  ! before retrying in that situation.
  if (allocated(is_new_var)) deallocate(is_new_var)
  allocate(is_new_var(b_idx:e_idx))
  is_new_var = .false.

  ! If I own a piece of a variable in this file, compute MY local sum
  if (my_var_index >= b_idx .and. my_var_index <= e_idx) then
    if (nc_vartype(my_var_index) == NF90_FLOAT) then
      local_chksums(my_var_index) = sum(INT(TRANSFER(write_buffers(my_jedi_index)%r4(:,:,mype_lbegin:mype_lend),mold4),8))
    else
      local_chksums(my_var_index) = sum(INT(TRANSFER(write_buffers(my_jedi_index)%r8(:,:,mype_lbegin:mype_lend),mold8),8))
    endif
  endif
  call MPI_Reduce(local_chksums, global_chksums, (e_idx - b_idx + 1), MPI_INTEGER8, MPI_SUM, 0, write_comm, ierr)

  ! Set the MPI_Info hints
  write(ost_str, '(I0)') my_ost_count
  write(stripeSize_str, '(I0)') self%lustre_stripe_size

  call MPI_Info_create(info, ierr)
  call MPI_Info_set(info, "romio_cb_write", "disable", ierr)
  call MPI_Info_set(info, "striping_factor", trim(ost_str), ierr)
  call MPI_Info_set(info, "striping_unit", trim(stripeSize_str), ierr)

  if (write_rank == 0) then
    if (self%write_into_existing_files) then
      write(6,'("Write to existing file ",A)') trim(FileNamesToProcess(n))
      rc = nf90_open(trim(FileNamesToProcess(n)), ior(NF90_WRITE, NF90_MPIIO), ncid(n), comm=MPI_COMM_SELF, info=info)
      if(rc == nf90_noerr) then
        ! Just update the checksum
        if(n==1) then
          b=1
          e=numvarfile(n)
        else
          b=sum(numvarfile(1:n-1)) + 1
          e=b+numvarfile(n) - 1
        endif
        do file_var_idx = b, e
          jedi_var_idx=VarToVarMap(file_var_idx)
          ! Convert the pre-staged 64-bit integer back to a string
          chksum = ""
          write(chksum, "(Z16)") global_chksums(file_var_idx)
          !write(6,'("Checksum for jedi_var_idx "5A)') trim(fields(jedi_var_idx)%model_name),' ',trim(chksum),' ',trim(varnames(file_var_idx))

          ! Probe (not via check(), which would abort) so a variable that does not
          ! yet exist in this pre-existing file can be added instead of aborting.
          rc2 = nf90_inq_varid(ncid(n),trim(varnames(file_var_idx)),varid)
          if (rc2 /= nf90_noerr) then
            ! Variable not present in the existing file: define it now, reusing the
            ! file's existing dimensions (never redefines/resizes a dimension, and
            ! never touches any variable that is already present in the file).
            is_new_var(file_var_idx) = .true.
            if(rank==0) write(6,'("write_restart_all_reg: Adding new variable ",A," to existing file ",A)') &
                        trim(varnames(file_var_idx)), trim(FileNamesToProcess(n))
            call check( nf90_redef(ncid(n)) )
            call check( nf90_set_fill(ncid(n), NF90_NOFILL, oldMode) )
            call check( nf90_inq_dimid(ncid(n), 'xaxis_1', newvar_dimids(1)) )
            call check( nf90_inq_dimid(ncid(n), 'yaxis_2', newvar_dimids(2)) )
            call check( nf90_inq_dimid(ncid(n), 'Time', newvar_dimids(4)) )
            if (allocated(chunksizes)) deallocate(chunksizes)
            if (nlevpervar(file_var_idx) > 1) then
              call check( nf90_inq_dimid(ncid(n), 'zaxis_1', newvar_dimids(3)) )
              allocate(chunksizes(4))
              chunksizes = [geom%globalsizes(1), geom%globalsizes(2), 1, 1]
              if (nc_vartype(file_var_idx) == NF90_FLOAT) then
                call check( nf90_def_var(ncid(n), trim(varnames(file_var_idx)), NF90_FLOAT, &
                                         newvar_dimids, varid, chunksizes=chunksizes) )
              else
                call check( nf90_def_var(ncid(n), trim(varnames(file_var_idx)), NF90_DOUBLE, &
                                         newvar_dimids, varid, chunksizes=chunksizes) )
              endif
            else
              allocate(chunksizes(3))
              chunksizes = [geom%globalsizes(1), geom%globalsizes(2), 1]
              if (nc_vartype(file_var_idx) == NF90_FLOAT) then
                call check( nf90_def_var(ncid(n), trim(varnames(file_var_idx)), NF90_FLOAT, &
                                         (/ newvar_dimids(1), newvar_dimids(2), newvar_dimids(4) /), varid, &
                                         chunksizes=chunksizes) )
              else
                call check( nf90_def_var(ncid(n), trim(varnames(file_var_idx)), NF90_DOUBLE, &
                                         (/ newvar_dimids(1), newvar_dimids(2), newvar_dimids(4) /), varid, &
                                         chunksizes=chunksizes) )
              endif
            endif
            call check( nf90_put_att(ncid(n), varid, "long_name", trim(fields(jedi_var_idx)%long_name)) )
            call check( nf90_put_att(ncid(n), varid, "units", trim(fields(jedi_var_idx)%units)) )
            call check( nf90_enddef(ncid(n)) )
          endif
          call check( nf90_put_att(ncid(n), varid, "checksum", trim(chksum)) )
        enddo ! var loop
      else
        write(6,'("ERROR: File ",2A)') trim(FileNamesToProcess(n)),' could not be opened'
        call flush(6)
        call MPI_Abort(geom%f_comm%communicator(),17,ierr)
      endif
      call check( nf90_close(ncid(n)) )  ! Will be reopened below
    else
      write(6,'("Create new file or overwrite an existing file ",A)') trim(FileNamesToProcess(n))
      rc = nf90_create(trim(FileNamesToProcess(n)), ior(ior(NF90_CLOBBER,NF90_NETCDF4),NF90_MPIIO), &
                       ncid(n), comm=MPI_COMM_SELF, info=info)
      if(rc == nf90_noerr) then
        dimids(:)=-999

        call check( nf90_set_fill(ncid(n), NF90_FILL, oldMode) )

        if (n == self%index_core) then
          ydim_name = 'yaxis_2'
        else
          ydim_name = 'yaxis_1'
        endif

        call check( nf90_def_dim(ncid(n), 'xaxis_1', geom%globalsizes(1), dimids(1)) )
        call check( nf90_def_dim(ncid(n), ydim_name, geom%globalsizes(2), dimids(2)) )
        call check( nf90_def_var(ncid(n), 'xaxis_1', NF90_DOUBLE, dimids(1), varid) )
        call check( nf90_put_att(ncid(n), varid, "cartesian_axis", "X") )
        call check( nf90_put_att(ncid(n), varid, "long_name", "xaxis_1") )
        call check( nf90_put_att(ncid(n), varid, "units", "none") )

        call check( nf90_def_var(ncid(n), ydim_name, NF90_DOUBLE, dimids(2), varid) )
        call check( nf90_put_att(ncid(n), varid, "cartesian_axis", "Y") )
        call check( nf90_put_att(ncid(n), varid, "long_name", ydim_name) )
        call check( nf90_put_att(ncid(n), varid, "units", "none") )

        ! Create a zaxis_1 dimension if any of the variables assigned to this file have a third dimension greater than 1
        ! This is true for fv_core.res, fv_srf_wnd.res and sfc_data
        if(n==1) then
          b=1
          e=numvarfile(n)
        else
          b=sum(numvarfile(1:n-1)) + 1
          e=b+numvarfile(n) - 1
        endif
        sz=1
        do file_var_idx = b, e
          jedi_var_idx = FileType(n)%VariableIndecies(file_var_idx)
          sz=max(sz,nlevpervar(file_var_idx))
        enddo

        if( sz > 1 ) then
          call check( nf90_def_dim(ncid(n), 'zaxis_1', sz, dimids(3)) )
          !call check( nf90_def_dim(ncid(n), 'Time', NF90_UNLIMITED, dimids(4)) )
          call check( nf90_def_dim(ncid(n), 'Time', 1, dimids(4)) )
          call check( nf90_def_var(ncid(n), 'zaxis_1', NF90_DOUBLE, dimids(3), varid) )
          call check( nf90_put_att(ncid(n), varid, "long_name", "zaxis_1") )
          call check( nf90_put_att(ncid(n), varid, "units", "none") )
          call check( nf90_def_var(ncid(n), 'Time', NF90_DOUBLE, dimids(4), varid) )
          call check( nf90_put_att(ncid(n), varid, "long_name", "Time") )
          call check( nf90_put_att(ncid(n), varid, "units", "time level") )
        else
          !call check( nf90_def_dim(ncid(n), 'Time', NF90_UNLIMITED, dimids(4)) )
          call check( nf90_def_dim(ncid(n), 'Time', 1, dimids(4)) )
          call check( nf90_def_var(ncid(n), 'Time', NF90_DOUBLE, dimids(4), varid) )
          call check( nf90_put_att(ncid(n), varid, "long_name", "Time") )
          call check( nf90_put_att(ncid(n), varid, "units", "time level") )
        endif

        FileType(n)%FileName = trim(FileNamesToProcess(n))
      else
        write(6,'("ERROR: File ",2A)') trim(FileNamesToProcess(n)),' could not be created'
        call flush(6)
        call MPI_Abort(geom%f_comm%communicator(),17,ierr)
      end if

      call check ( nf90_set_fill(ncid(n), NF90_NOFILL, oldMode) )

      do file_var_idx = b, e
        jedi_var_idx=VarToVarMap(file_var_idx)
        ! Convert the pre-staged 64-bit integer back to a string
        chksum = ""
        write(chksum, "(Z16)") global_chksums(file_var_idx)
        !write(6,'("Checksum for jedi_var_idx "5A)') trim(fields(jedi_var_idx)%model_name),' ',trim(chksum),' ',trim(varnames(file_var_idx))

        if(nlevpervar(file_var_idx) > 1) then
          chunksizes = [geom%globalsizes(1), geom%globalsizes(2), 1, 1]
          if (nc_vartype(file_var_idx) == NF90_FLOAT) then
            call check( nf90_def_var(ncid(n), trim(varnames(file_var_idx)), NF90_FLOAT, dimids, varid, chunksizes=chunksizes) )
          else
            call check( nf90_def_var(ncid(n), trim(varnames(file_var_idx)), NF90_DOUBLE, dimids, varid, chunksizes=chunksizes) )
          endif
          call check( nf90_put_att(ncid(n), varid, "long_name", trim(fields(jedi_var_idx)%long_name)) )
          call check( nf90_put_att(ncid(n), varid, "units", trim(fields(jedi_var_idx)%units)) )
          call check( nf90_put_att(ncid(n), varid, "checksum", trim(chksum)) )
        else
          chunksizes = [geom%globalsizes(1), geom%globalsizes(2), 1]
          if (nc_vartype(file_var_idx) == NF90_FLOAT) then
            call check( nf90_def_var(ncid(n), trim(varnames(file_var_idx)), NF90_FLOAT, (/ dimids(1), dimids(2), dimids(4) /), &
                                     varid, chunksizes=chunksizes) )
          else
            call check( nf90_def_var(ncid(n), trim(varnames(file_var_idx)), NF90_DOUBLE, (/ dimids(1), dimids(2), dimids(4) /), &
                                     varid, chunksizes=chunksizes) )
          endif
          call check( nf90_put_att(ncid(n), varid, "long_name", trim(fields(jedi_var_idx)%long_name)) )
          call check( nf90_put_att(ncid(n), varid, "units", trim(fields(jedi_var_idx)%units)) )
          call check( nf90_put_att(ncid(n), varid, "checksum", trim(chksum)) )
        endif
      enddo ! var loop
  
      ! Exit define mode
      ! ----------------
      call check( nf90_enddef(ncid(n)) )
      call check( nf90_close(ncid(n)) )
    endif  ! write_into_existing_files
  endif ! write_comm rank 0

  ! Only write_rank==0 ran the probe above; tell every rank in this file's
  ! communicator which variables were newly created, so the collective write
  ! loop below can select the correct parallel access mode per variable.
  call MPI_Bcast(is_new_var, size(is_new_var), MPI_LOGICAL, 0, write_comm, ierr)

  call MPI_Barrier(write_comm, ierr)
  ! Force every single rank's OS client to query the MDS and invalidate stale caches
  block
    integer :: dummy_unit, ios
    open(newunit=dummy_unit, file=trim(FileNamesToProcess(mype_fileid)), status='old', iostat=ios)
    if (ios == 0) close(dummy_unit)
  end block
  ! Ensure all ranks have updated their namespace before HDF5 dives in
  call MPI_Barrier(write_comm, ierr)

  if (allocated(local_chksums)) deallocate(local_chksums)
  if (allocated(global_chksums)) deallocate(global_chksums)
endif ! write_comm
!te = MPI_Wtime()
!times(8) = te-tb

! owners proceed to reopen and write
!tb = MPI_Wtime()
if (write_comm /= MPI_COMM_NULL) then

  ! Only I/O ranks reopen the file
  call check( nf90_open(trim(FileNamesToProcess(mype_fileid)), IOR(NF90_WRITE, NF90_MPIIO), &
                        ncid(mype_fileid), comm=write_comm, info=info) )

  ! Determine the range of variables that belong in this specific file
  if(mype_fileid == 1) then
    b = 1
    e = numvarfile(1)
  else
    b = sum(numvarfile(1:mype_fileid-1)) + 1
    e = b + numvarfile(mype_fileid) - 1
  endif

! ALL ranks in write_comm MUST loop over every variable in the file together!
  do file_var_idx = b, e

    ! Collectively inquire and set parallel access for the current variable
    call check( nf90_inq_varid(ncid(mype_fileid), trim(varnames(file_var_idx)), varid) )
    if (is_new_var(file_var_idx)) then
      ! A variable just added to a pre-existing file (write into existing files) has
      ! never had its storage allocated (NF90_NOFILL means no chunks are pre-filled),
      ! so its first write must extend the underlying HDF5 dataset. Extending is a
      ! collective metadata operation: independent access aborts with "Attempt to
      ! extend dataset during NC_INDEPENDENT I/O operation". Restrict collective
      ! access to just-created variables so pre-existing variables (the common
      ! case, including plain write-into-existing-files overwrites with no renamed
      ! fields) keep the cheaper independent path with no behavior change.
      call check( nf90_var_par_access(ncid(mype_fileid), varid, nf90_collective) )
    else
      call check( nf90_var_par_access(ncid(mype_fileid), varid, nf90_independent) ) ! Don't use nf90_collective as that causes ROMIO to redo all the gathering we worked so hard to achieve
    endif

    ! Check if this specific rank owns the data for this variable
    if (file_var_idx == my_var_index) then
      ! --- THIS RANK OWNS DATA ---
      ! Write the actual payload using the rank's true domain bounds
      startloc = (/ 1, 1, mype_lbegin, 1 /)
      countloc = (/ geom%globalsizes(1), geom%globalsizes(2), (mype_lend - mype_lbegin + 1), 1 /)

      if (nc_vartype(file_var_idx) == NF90_FLOAT) then
        call check( nf90_put_var(ncid(mype_fileid), varid, write_buffers(my_jedi_index)%r4, start=startloc, count=countloc) )
      else
        call check( nf90_put_var(ncid(mype_fileid), varid, write_buffers(my_jedi_index)%r8, start=startloc, count=countloc) )
      endif
    else
      ! --- THIS RANK DOES NOT OWN DATA ---
      ! It MUST still participate in the collective call, but with a count of 0
      startloc = (/ 1, 1, 1, 1 /)
      countloc = (/ 0, 0, 0, 0 /)

      if (nc_vartype(file_var_idx) == NF90_FLOAT) then
        call check( nf90_put_var(ncid(mype_fileid), varid, dummy_r4_3d, start=startloc, count=countloc) )
      else
        call check( nf90_put_var(ncid(mype_fileid), varid, dummy_r8_3d, start=startloc, count=countloc) )
      endif
    endif
  enddo ! End of synchronized variable loop
  ! close only the file this rank worked on
  call check( nf90_close(ncid(mype_fileid)) )
  call MPI_Info_free(info,ierr)
endif ! write_comm
!te = MPI_Wtime()
!times(9) = te-tb
!call MPI_Reduce(times, walltime, size(walltime), MPI_DOUBLE_PRECISION, MPI_MAX, 0, geom%f_comm%communicator(), ierr)
!if (rank == 0) write(*,'(A,10F12.4)') 'write_restart_all_reg: Walltimes ', walltime, sum(walltime)

! release memory
deallocate(reqs_p1, reqs_p2)

!call TwoPhaseGather_delete() ! Need to figure out where/when to call this cleanup routine

!Write date/time info in coupler.res
!-----------------------------------
if (mpp_pe() == mpp_root_pe() .and. .not. self%skip_coupler) then
   open(101, file = trim(adjustl(self%datapath))//'/'// &
        trim(adjustl(self%filenames(self%index_cplr))), form='formatted')
   write( 101, '(i6,8x,a)' ) self%calendar_type, &
        '(Calendar: no_calendar=0, thirty_day_months=1, julian=2, gregorian=3, noleap=4)'
   write( 101, '(6i6,8x,a)') date, 'Model start time:   year, month, day, hour, minute, second'
   write( 101, '(6i6,8x,a)') date, 'Current model time: year, month, day, hour, minute, second'
   close(101)
endif

end subroutine write_restart_all_reg

! --------------------------------------------------------------------------------------------------

subroutine write_nonrestart_all(self, fields, field_io_names, field_io_scaling)

type(fv3jedi_io_fms),      intent(inout) :: self
type(fv3jedi_field),       intent(in)    :: fields(:)
type(fckit_configuration), intent(in)    :: field_io_names
type(fckit_configuration), intent(in)    :: field_io_scaling

integer                     :: var, n
type(FmsNetcdfDomainFile_t) :: fileobj
logical                     :: write_field
real(kind=kind_real)        :: io_unscaling_factor
character(len=field_clen)   :: io_name

! Open file for overwriting
if ( open_file(fileobj, trim(self%datapath)//'/'//trim(self%filename_nonrestart), 'overwrite', self%domain) ) then
   ! Loop through fields
   do var = 1,size(fields)
      ! Check whether field is to be written
      write_field = .false.
      if ( trim(self%fields_to_write(1) ) == 'All') then
         write_field = .true.
      else
         do n = 1,size(self%fields_to_write)
            if (trim(self%fields_to_write(n)) == trim(fields(var)%long_name)) then
               write_field = .true.
            end if
         end do
      end if

      if ( write_field ) then
         ! Register field
         io_name = ioname(trim(fields(var)%long_name), field_io_names)
         call fv3jedi_register_field(fileobj, io_name, fields(var)%array, center, .false., &
                                     trim(fields(var)%long_name), trim(fields(var)%units))

         ! Write field
         io_unscaling_factor = iounscale(fields(var)%long_name, field_io_scaling)
         call write_data(fileobj, ioname(trim(fields(var)%long_name), field_io_names), &
                         io_unscaling_factor*fields(var)%array)
      end if
   end do

   ! Close file
   call close_file(fileobj)
else
   call abor1_ftn('fv3jedi_io_fms_mod.write_nonrestart_all: file ' &
                  // trim(self%datapath)//'/'//trim(self%filename_nonrestart) // &
                  ' could not be opened')
end if

end subroutine write_nonrestart_all

! --------------------------------------------------------------------------------------------------

subroutine fv3jedi_register_field(fileobj, io_name_in, array, position, is_restart, long_name, units)

  type(FmsNetcdfDomainFile_t), intent(inout) :: fileobj
  character(len=*), intent(in)               :: io_name_in
  real(kind=kind_real), intent(in)           :: array(:,:,:)
  integer, intent(in)                        :: position
  logical, intent(in)                        :: is_restart
  character(len=*), optional, intent(in)     :: long_name
  character(len=*), optional, intent(in)     :: units

  logical :: is_open, is_registered
  integer :: ndims, idim, num_zaxes, nz_dim, nz_field, array_shape(3)
  character(len=8) :: xdim_name, ydim_name, zdim_name
  character(len=8), dimension(:), allocatable :: dim_names
  character(len=field_clen) :: io_name

  io_name = trim(io_name_in)

  if ( fileobj%is_readonly ) then ! For read
     ! Get variable dimensions
     ndims = get_variable_num_dimensions(fileobj, trim(io_name))
     allocate(dim_names(ndims))
     call get_variable_dimension_names(fileobj, trim(io_name), dim_names)

     ! Register x-axis
     if ( .not. is_dimension_registered(fileobj, trim(dim_names(1))) ) then
        if ( position /= north ) then
           call register_axis(fileobj, trim(dim_names(1)), 'x', domain_position=position)
        else
           call register_axis(fileobj, trim(dim_names(1)), 'x', domain_position=center)
        end if
     end if

     ! Register y-axis
     if ( .not. is_dimension_registered(fileobj, trim(dim_names(2))) ) then
        if ( position /= east ) then
           call register_axis(fileobj, trim(dim_names(2)), 'y', domain_position=position)
        else
           call register_axis(fileobj, trim(dim_names(2)), 'y', domain_position=center)
        end if
     end if

     ! Register restart field
     if ( is_restart ) then
        call register_restart_field(fileobj, trim(io_name), array)
     end if
  else ! For write

     ! Register x-axis
     ! ---------------

     is_registered = .false.
     do idim = 1,fileobj%nx
        if ( fileobj%xdims(idim)%pos == position ) then
           is_registered = .true.
           xdim_name = trim(fileobj%xdims(idim)%varname)
           exit
        end if
     end do

     if ( .not. is_registered ) then
        write (xdim_name,'(A,I0)') 'xaxis_', fileobj%nx+1

        if ( position /= north ) then
           call register_axis(fileobj, trim(xdim_name), 'x', domain_position=position)
        else
           call register_axis(fileobj, trim(xdim_name), 'x', domain_position=center)
        end if

        call register_field(fileobj, trim(xdim_name), 'double', (/ trim(xdim_name) /))
        call register_variable_attribute(fileobj, trim(xdim_name), 'long_name', trim(xdim_name), str_len=len(trim(xdim_name)))
        call register_variable_attribute(fileobj, trim(xdim_name), 'units', 'none', str_len=len('none'))
        call register_variable_attribute(fileobj, trim(xdim_name), 'cartesian_axis', 'X', str_len=len('X'))
     end if

     ! Register y-axis
     ! ---------------

     is_registered = .false.
     do idim = 1,fileobj%ny
        if ( fileobj%ydims(idim)%pos == position ) then
           is_registered = .true.
           ydim_name = trim(fileobj%ydims(idim)%varname)
           exit
        end if
     end do

     if ( .not. is_registered ) then
        write (ydim_name,'(A,I0)') 'yaxis_', fileobj%ny+1

        if ( position /= east ) then
           call register_axis(fileobj, trim(ydim_name), 'y', domain_position=position)
        else
           call register_axis(fileobj, trim(ydim_name), 'y', domain_position=center)
        end if

        call register_field(fileobj, trim(ydim_name), 'double', (/ trim(ydim_name) /))
        call register_variable_attribute(fileobj, trim(ydim_name), 'long_name', trim(ydim_name), str_len=len(trim(ydim_name)))
        call register_variable_attribute(fileobj, trim(ydim_name), 'units', 'none', str_len=len('none'))
        call register_variable_attribute(fileobj, trim(ydim_name), 'cartesian_axis', 'Y', str_len=len('Y'))
     end if

     ! Register z-axis
     ! ---------------

     ! Count length of third array dimension
     array_shape = shape(array)
     nz_field = array_shape(3)

     if ( nz_field > 1 ) then
        ndims = get_num_dimensions(fileobj)
        allocate(dim_names(ndims))
        call get_dimension_names(fileobj, dim_names)

        num_zaxes = 0
        is_registered = .false.
        do idim = 1,ndims
           if ( dim_names(idim)(1:6) == 'zaxis_' ) then
              call get_dimension_size(fileobj, trim(dim_names(idim)), nz_dim)
              if ( nz_dim == nz_field ) then
                 is_registered = .true.
                 zdim_name = trim(dim_names(idim))
                 exit
              end if

              num_zaxes = num_zaxes + 1
           end if
        end do

        if ( .not. is_registered) then
           if ( num_zaxes+1 > 99 ) then
              call abor1_ftn('fv3jedi_io_fms_mod.fv3jedi_register_field: only 99 z-axes permitted for write.')
           end if
           write (zdim_name,'(A,I0)') 'zaxis_', num_zaxes+1

           call register_axis(fileobj, trim(zdim_name), nz_field)

           call register_field(fileobj, trim(zdim_name), 'double', (/ trim(zdim_name) /))
           call register_variable_attribute(fileobj, trim(zdim_name), 'long_name', trim(zdim_name), str_len=len(trim(zdim_name)))
           call register_variable_attribute(fileobj, trim(zdim_name), 'units', 'none', str_len=len('none'))
           call register_variable_attribute(fileobj, trim(zdim_name), 'cartesian_axis', 'Z', str_len=len('Z'))
        end if
     end if

     ! Register time-axis
     if ( .not. dimension_exists(fileobj, 'Time') ) then
        call register_axis(fileobj, 'Time', unlimited)

        call register_field(fileobj, 'Time', 'double', (/ 'Time' /))
        call register_variable_attribute(fileobj, 'Time', 'long_name', 'Time', str_len=len('Time'))
        call register_variable_attribute(fileobj, 'Time', 'units', 'time level', str_len=len('time level'))
        call register_variable_attribute(fileobj, 'Time', 'cartesian_axis', 'T', str_len=len('T'))
     end if

     ! Register restart field
     if ( is_restart ) then
        if ( nz_field > 1 ) then
           call register_restart_field(fileobj, trim(io_name), array, (/ xdim_name, ydim_name, zdim_name, 'Time    '/))
        else
           call register_restart_field(fileobj, trim(io_name), array, (/ xdim_name, ydim_name, 'Time    '/))
        end if
     else
        if ( nz_field > 1 ) then
           call register_field(fileobj, trim(io_name), 'double', (/ xdim_name, ydim_name, zdim_name, 'Time    '/))
        else
           call register_field(fileobj, trim(io_name), 'double', (/ xdim_name, ydim_name, 'Time    '/))
        end if
     end if

     ! Set field attributes
     if ( present(long_name) ) then
        call register_variable_attribute(fileobj, trim(io_name), 'long_name', trim(long_name), str_len=len(trim(long_name)))
     endif
     if ( present(units) ) then
        call register_variable_attribute(fileobj, trim(io_name), 'units', trim(units), str_len=len(trim(units)))
     end if

  end if

end subroutine fv3jedi_register_field

! --------------------------------------------------------------------------------------------------

subroutine get_io_file(self, field, indexrst)

! Arguments
type(fv3jedi_io_fms),      intent(in)  :: self
type(fv3jedi_field),       intent(in)  :: field
integer,                   intent(out) :: indexrst

! Locals
character(len=field_clen) :: io_file

! Start by setting to core
io_file = 'core'

! Tracers go in tracer file
if (field%tracer) io_file = 'tracer'

! Fields with 1 level go in surface file
if (field%npz == 1) io_file = 'surface'

! Surface fields in core
if (trim(field%long_name) == 'air_pressure_at_surface') io_file = 'surface'
if (trim(field%long_name) == 'geopotential_height_times_gravity_at_surface') io_file = 'core'

! Surface winds go in surface wind file
if (trim(field%long_name) == 'eastward_wind_at_surface') io_file = 'surface_wind'
if (trim(field%long_name) == 'northward_wind_at_surface') io_file = 'surface_wind'

! Orog variables if name contains orog
if (index(trim(field%long_name), 'orog') /= 0) io_file = 'orography'

! Fraction of land is in the orography file
if (index(trim(field%long_name), 'fraction_of_land') /= 0) io_file = 'orography'

! Cold start variables if name contains cold
if (index(trim(field%long_name), 'cold') /= 0) io_file = 'cold'

! Multi-level soils go in surface
if (trim(field%long_name) == 'soilt') io_file = 'surface'
if (trim(field%long_name) == 'soilm') io_file = 'surface'
if (trim(field%long_name) == 'stc') io_file = 'surface'
if (trim(field%long_name) == 'soilMoistureVolumetric') io_file = 'surface'
if (trim(field%long_name) == 'tslb') io_file = 'surface'
if (trim(field%long_name) == 'smois') io_file = 'surface'

! Reflectivity variable goes in physics file
if (trim(field%long_name) == 'equivalent_reflectivity_factor') io_file = 'physics'

! Set the filename index
! ----------------------
select case (io_file)
  case("core")
    indexrst = self%index_core
  case("tracer")
    indexrst = self%index_trcr
  case("surface")
    indexrst = self%index_sfcd
  case("surface_wind")
    indexrst = self%index_sfcw
  case("physics")
    indexrst = self%index_phys
  case("orography")
    indexrst = self%index_orog
  case("cold")
    indexrst = self%index_cold
end select

end subroutine get_io_file

! --------------------------------------------------------------------------------------------------

! Not really needed but prevents gnu compiler bug
subroutine dummy_final(self)
type(fv3jedi_io_fms), intent(inout) :: self
end subroutine dummy_final

! --------------------------------------------------------------------------------------------------

  subroutine check(status)
!    use netcdf
    integer, intent ( in) :: status
    integer :: ierr

    if(status /= nf90_noerr) then
      print *, trim(nf90_strerror(status))
      call MPI_Abort(MPI_COMM_WORLD,2,ierr)
    end if
  end subroutine check

  subroutine distribute_io_work(npes, total_vars, var_names_in, var_nz_in, var_fileid_in, &
                                out_fileid, out_varname, out_lvlbegin, out_lvlend, out_nlev)
    implicit none

    ! --- Inputs ---
    integer, intent(in) :: npes, total_vars
    character(len=*), intent(in) :: var_names_in(total_vars)
    integer, intent(in) :: var_nz_in(total_vars)
    integer, intent(in) :: var_fileid_in(total_vars)

    ! --- Outputs ---
    ! Sized exactly to the number of MPI ranks (1 to npes)
    integer, intent(out) :: out_fileid(npes)
    character(len=72), intent(out) :: out_varname(npes)
    integer, intent(out) :: out_lvlbegin(npes)
    integer, intent(out) :: out_lvlend(npes)
    integer, intent(out) :: out_nlev(0:npes-1)

    ! --- Locals ---
    integer :: nlvl2d, nlvl3d, nlvl3d_small, nlvlcore
    integer, allocatable :: nlvl3d_list(:)
    integer :: i, k, nn, n3d, nz, mynlvl3d

    ! Initialize outputs to handle ranks that receive no work
    out_fileid = 0
    out_varname = ""
    out_lvlbegin = 0
    out_lvlend = 0
    out_nlev = 0

    ! 1. Count levels and categorize variables
    nlvl2d = 0; nlvl3d = 0; nlvl3d_small = 0
    do i = 1, total_vars
      if (var_nz_in(i) > 1) then
        if (var_nz_in(i) <= 10) then
          nlvl3d_small = nlvl3d_small + var_nz_in(i)
        else
          nlvl3d = nlvl3d + 1
        endif
      else
        nlvl2d = nlvl2d + 1
      endif
    enddo

    ! 2. Calculate cores per large 3D field
    if (nlvl3d > 0) then
      allocate(nlvl3d_list(nlvl3d))
      nlvlcore = (npes - nlvl2d - nlvl3d_small) / nlvl3d
      nlvl3d_list = nlvlcore
      nlvlcore = (npes - nlvl2d - nlvl3d_small) - (nlvl3d * nlvlcore)
      if (nlvlcore > 0) then
        do k = 1, nlvlcore
          nlvl3d_list(k) = nlvl3d_list(k) + 1
        enddo
      endif
    endif

    ! 3. Assign levels to ranks
    nn = 0; n3d = 0
    do i = 1, total_vars
      nz = var_nz_in(i)
      if (nz > 10) then
        ! Distributed large 3D field
        n3d = n3d + 1
        mynlvl3d = min(nlvl3d_list(n3d), nz)
        nlvlcore = nz / mynlvl3d

        do k = 1, mynlvl3d
          nn = nn + 1
          if (nn > npes) exit

          out_varname(nn) = trim(var_names_in(i))
          out_fileid(nn)  = var_fileid_in(i)

          if (k == 1) then
            out_lvlbegin(nn) = 1
          else
            out_lvlbegin(nn) = out_lvlend(nn-1) + 1
          endif

          out_lvlend(nn) = out_lvlbegin(nn) + nlvlcore - 1
          if (k <= (nz - nlvlcore * mynlvl3d)) out_lvlend(nn) = out_lvlend(nn) + 1
        enddo
      else
        ! 2D field or small 3D field (assigned 1 level per rank)
        do k = 1, nz
          nn = nn + 1
          if (nn > npes) exit
          out_varname(nn) = trim(var_names_in(i))
          out_fileid(nn)  = var_fileid_in(i)
          out_lvlbegin(nn) = k
          out_lvlend(nn)   = k
        enddo
      endif
    enddo

    ! 4. Calculate final array of level counts assigned to each rank (0-indexed for JEDI standard)
    do k = 1, npes
      if (out_lvlend(k) > 0 .and. out_lvlbegin(k) > 0) then
        out_nlev(k-1) = out_lvlend(k) - out_lvlbegin(k) + 1
      endif
    enddo

    !if(mpp_pe()==0) then
    !  write(6,'(2a5,2x,a45,2a10)') "core","fid","varname","lvlbegin","lvlend"
    !  do k=1,npes
    !     write(6,'(2I5,2x,a45,2I10)') k,out_fileid(k),trim(out_varname(k)),out_lvlbegin(k),out_lvlend(k)
    !  enddo
    !  write(6,*) "======================================================================="
    !endif

    if (allocated(nlvl3d_list)) deallocate(nlvl3d_list)

  end subroutine distribute_io_work

end module fv3jedi_io_fms_mod
