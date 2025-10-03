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
use mpp_domains_mod,              only: east, north, center, domain2D
use mpp_mod,                      only: mpp_pe, mpp_root_pe

! fv3jedi
use fv3jedi_field_mod,            only: fv3jedi_field, hasfield, field_clen
use fv3jedi_io_utils_mod,         only: vdate_to_datestring, replace_text, add_iteration, ioname, &
                                        ioscale, iounscale
use fv3jedi_kinds_mod,            only: kind_real
use fv3jedi_geom_mod,             only: fv3jedi_geom
use fields_metadata_mod,          only: field_metadata

! --------------------------------------------------------------------------------------------------

implicit none
private
public fv3jedi_io_fms

! If adding a new file it is added here and object and config in setup
integer, parameter :: numfiles = 9

type fv3jedi_io_fms
 logical :: is_restart
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

integer :: n
character(len=:), allocatable :: str
character(len=13) :: fileconf(numfiles)

! Check if files are restarts or not
! ----------------------------------
if (conf%has("is restart")) then
  call conf%get_or_die("is restart", self%is_restart)
else
  self%is_restart = .true.
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
type(fv3jedi_geom),        intent(in)     :: geom
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
   call read_restart_fields(self, geom, fields, field_io_names, field_io_scaling)
else
   ! Read fields
   ! -----------
   call read_nonrestart_fields(self, fields, field_io_names, field_io_scaling)
end if

end subroutine read

! --------------------------------------------------------------------------------------------------

subroutine write(self, vdate, fields, field_io_names, field_io_scaling)

class(fv3jedi_io_fms),     intent(inout) :: self
type(datetime),            intent(in)    :: vdate
type(fv3jedi_field),       intent(in)    :: fields(:)
type(fckit_configuration), intent(in)    :: field_io_names
type(fckit_configuration), intent(in)    :: field_io_scaling

! Overwrite any datetime templates in the file names
! --------------------------------------------------
call setup_date(self, vdate)

if ( self%is_restart ) then
   ! Write metadata and fields
   ! -------------------------
   call write_restart_all(self, fields, vdate, field_io_names, field_io_scaling)
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
integer :: n, indexrst, var, idrst

logical :: havedelp
integer :: indexof_ps, indexof_delp
real(kind=kind_real), allocatable :: delp(:,:,:)
type(fckit_configuration) :: field_io_names_local

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
  call fv3jedi_register_field(fileobj(indexrst), trim(fields(var)%long_name), fields(var)%array, &
                              center, trim(fields(var)%units), .true., field_io_names_local)

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

subroutine read_nonrestart_fields(self, fields, field_io_names, field_io_scaling)

type(fv3jedi_io_fms),      intent(inout) :: self
type(fv3jedi_field),       intent(inout) :: fields(:)
type(fckit_configuration), intent(in)    :: field_io_names
type(fckit_configuration), intent(in)    :: field_io_scaling

integer                     :: var
type(FmsNetcdfDomainFile_t) :: fileobj

! Open file for reading
if ( open_file(fileobj, trim(self%datapath)//'/'//trim(self%filename_nonrestart), 'read', self%domain) ) then
   ! Loop through fields
   do var = 1,size(fields)
      ! Register field
      call fv3jedi_register_field(fileobj, trim(fields(var)%long_name), fields(var)%array, &
                                  center, trim(fields(var)%units), .false., field_io_names)

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

subroutine write_restart_all(self, fields, vdate, field_io_names, field_io_scaling)

type(fv3jedi_io_fms),      intent(inout) :: self
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

  ! Flag to read this restart
  if ( .not. rstflag(indexrst) ) then
     if ( open_file(fileobj(indexrst), &
          trim(self%datapath)//'/'//trim(self%filenames(indexrst)), &
          'overwrite', self%domain, is_restart=.true., dont_add_res_to_filename=.true.) ) then
        rstflag(indexrst) = .true.
     else
        call abor1_ftn('fv3jedi_io_fms_mod.write_restart_all: file ' &
                        // trim(self%datapath)//'/'//trim(self%filename_nonrestart) // &
                       ' could not be opened')
     end if
  end if

  ! Get the scaling factor
  io_unscaling_factor = iounscale(fields(var)%long_name, field_io_scaling)

  ! Register restart field
  call fv3jedi_register_field(fileobj(indexrst), trim(fields(var)%long_name), &
                              fields(var)%array, &
                              center, trim(fields(var)%units), .true., field_io_names)
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

subroutine write_nonrestart_all(self, fields, field_io_names, field_io_scaling)

type(fv3jedi_io_fms),      intent(inout) :: self
type(fv3jedi_field),       intent(in)    :: fields(:)
type(fckit_configuration), intent(in)    :: field_io_names
type(fckit_configuration), intent(in)    :: field_io_scaling

integer                     :: var, n
type(FmsNetcdfDomainFile_t) :: fileobj
logical                     :: write_field
real(kind=kind_real)        :: io_unscaling_factor

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
         call fv3jedi_register_field(fileobj, trim(fields(var)%long_name), fields(var)%array, &
                                     center, trim(fields(var)%units), .false., field_io_names)

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

subroutine fv3jedi_register_field(fileobj, long_name, array, position, units, is_restart, &
                                  field_io_names)

  type(FmsNetcdfDomainFile_t), intent(inout) :: fileobj
  character(len=*), intent(in)               :: long_name
  real(kind=kind_real), intent(in)           :: array(:,:,:)
  integer, intent(in)                        :: position
  character(len=*), optional, intent(in)     :: units
  logical, intent(in)                        :: is_restart
  type(fckit_configuration), intent(in)      :: field_io_names

  logical :: is_open, is_registered
  integer :: ndims, idim, num_zaxes, nz_dim, nz_field, array_shape(3)
  character(len=8) :: xdim_name, ydim_name, zdim_name
  character(len=8), dimension(:), allocatable :: dim_names
  character(len=field_clen) :: io_name

  ! Get the potential io_name from the field_io_names
  ! ------------------------------------------------
  io_name = ioname(long_name, field_io_names)

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
     call register_variable_attribute(fileobj, trim(io_name), 'long_name', trim(long_name), str_len=len(trim(long_name)))
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

! 4 level soils go in surface
if (trim(field%long_name) == 'stc') io_file = 'surface'
if (trim(field%long_name) == 'soilMoistureVolumetric') io_file = 'surface'

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

end module fv3jedi_io_fms_mod
