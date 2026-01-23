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
use mpp_domains_mod,              only: east, north, center, domain2D, mpp_get_domain_tile_commid
use mpp_mod,                      only: mpp_pe, mpp_root_pe, mpp_npes

! fv3jedi
use fv3jedi_field_mod,            only: fv3jedi_field, hasfield, field_clen
use fv3jedi_io_utils_mod,         only: vdate_to_datestring, replace_text, add_iteration, ioname, &
                                        ioscale, iounscale
use fv3jedi_kinds_mod,            only: kind_real
use fv3jedi_geom_mod,             only: fv3jedi_geom
use fields_metadata_mod,          only: field_metadata
use mpi, only : MPI_Wtime, MPI_comm_world, MPI_Barrier, MPI_Integer, MPI_DOUBLE_PRECISION, MPI_MAX, &
                MPI_INFO_NULL, mpi_character, MPI_COMM_NULL, MPI_UNDEFINED, MPI_IN_PLACE, MPI_INTEGER8, MPI_SUM
use netcdf

! --------------------------------------------------------------------------------------------------

implicit none
private
public fv3jedi_io_fms

! If adding a new file it is added here and object and config in setup
integer, parameter :: numfiles = 9

!Scatter type
type :: scatter_t
  logical :: lalloc = .false.
  integer, allocatable :: sendcounts_row(:), senddispls_row(:)
  integer, allocatable :: sendcounts_col(:), senddispls_col(:)
  integer :: vec, localvec
endtype scatter_t

type(scatter_t), allocatable :: Scatter(:)  ! Holding place for counts, displacement and MPI datatypes used in TwoPhaseScatterPolymorphic()

type :: file_t
  logical :: lopened = .false.
  character(len=NF90_MAX_NAME) :: FileName
  integer(kind=4) :: VariableIndecies(50) = -999  ! Store JEDI domain field/variable indecies found in each file 
endtype file_t

! sub communicator
  integer :: read_comm

  integer :: ntotallev
  integer :: mype_lbegin,mype_lend
  integer :: mype_vartype
  integer :: mype_fileid
  integer :: globalsizes(2)=0  ! Local copy of the grid dimensions needed in order to track changes (dual resolution cases)
  logical :: first_pass = .true. ! Some arrays need only be allocated once
  logical :: need_to_reallocate_ps = .false. ! Some arrays need only be allocated once
  character(len=20) :: mype_varname

  integer(kind=4), allocatable :: LevelToProcMap(:), LevelToVariableMap(:), LevelToLevelMap(:), VarToVarMap(:)
  integer(kind=4), allocatable :: nc_vartype(:)
  character(len=NF90_MAX_NAME), allocatable :: FileNamesToProcess(:)
  logical :: rstflag(numfiles)

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
   !call read_restart_fields(self, geom, fields, field_io_names, field_io_scaling)
   call read_restart_fields_newest(self, geom, fields, field_io_names, field_io_scaling)
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
   !call write_restart_all(self, geom, fields, vdate, field_io_names, field_io_scaling)
   call write_restart_all_new3(self, geom, fields, vdate, field_io_names, field_io_scaling)
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
    !call field_io_names_local%set("air_pressure_thickness", "delp") ! SKD
    if (.not. field_io_names_local%has("air_pressure_thickness")) then
      call field_io_names_local%set("air_pressure_thickness", "delp")
    end if

  endif

  ! Get file to use
  call get_io_file(self, fields(var), indexrst)

  ! Flag to read this restart
  if ( .not. rstflag(indexrst) ) then
     fileobj(indexrst)%use_collective = .true.
     fileobj(indexrst)%tile_comm = mpp_get_domain_tile_commid(self%domain)
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
     if(mpp_pe() == 0) write(6,'("read_restart_fields: Reading restart ",A)') trim(self%filenames(n))
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

subroutine read_restart_fields_newest(self, geom, fields, field_io_names, field_io_scaling)
use module_ncfile_stat, only : ncfile_stat
use module_mpi_arrange, only : mpi_io_arrange
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
integer :: i, j, level, l, n, indexrst, var, var2
integer :: iret,ilev,r,ncioid,var_id,loc

integer(kind=4), allocatable :: nlev(:), nlevpervar(:), numvar(:)
character(len=20), allocatable :: varnames(:)
class(*), pointer :: globalptr(:,:) => null()
class(*), pointer :: localptr(:,:,:) => null()

type(ncfile_stat) :: ncfs_all
type(mpi_io_arrange) :: mpiioarg

! sub communicator
integer :: color, key

! array
real(4), pointer, contiguous :: d2r4ptr(:,:) => null()
real(8), pointer, contiguous :: d2r8ptr(:,:) => null()
real(4),allocatable, target :: d3r4(:,:,:)
real(8),allocatable, target :: d3r8(:,:,:)

logical :: havedelp
integer :: indexof_ps, indexof_delp
real(kind=kind_real), allocatable :: delp(:,:,:)
type(fckit_configuration) :: field_io_names_local

integer :: rank, npes, ierr
integer :: starts(3), counts(3)
real(kind=8) :: tb1,tb2,tb3, times(3), walltime(3)
real(kind=8) :: te1,te2,te3
integer :: totalnumfiles
integer :: cached_nfields = -1
character(len=field_clen), allocatable :: cached_field_names(:)
integer, allocatable :: cached_field_nz(:)
logical :: fields_changed
integer :: f, nz
logical :: getdelp
character(len=:), allocatable :: str

rank=mpp_pe()
npes=mpp_npes()

tmpvarlist=''

! Check whether delp in fields
! ----------------------------
indexof_ps = -1
indexof_delp = -1
havedelp = hasfield(fields, 'air_pressure_thickness', indexof_delp)

num_restart_vars(:)=0
times(:)=0.0
walltime(:)=0.0

! Copy config
! -----------
field_io_names_local = field_io_names

! Check for field changes (order or size)
! ---------------------------------------
fields_changed = .false.
! If cache not initialized, force rebuild
if (cached_nfields < 0) then
  fields_changed = .true.
elseif (cached_nfields /= size(fields)) then
  fields_changed = .true.
elseif (.not. allocated(cached_field_names) .or. .not. allocated(cached_field_nz)) then
  fields_changed = .true.
elseif (size(cached_field_names) /= size(fields) .or. size(cached_field_nz) /= size(fields)) then
  fields_changed = .true.
else
  do f = 1, size(fields)
    if (allocated(fields(f)%array)) then
      nz = size(fields(f)%array, 3)
    else
      nz = -1
    endif

    if (trim(fields(f)%model_name) /= trim(cached_field_names(f))) then
      fields_changed = .true.
      exit
    endif
    if (nz /= cached_field_nz(f)) then
      fields_changed = .true.
      exit
    endif
  enddo
endif


!if(rank==0) write(6,'("read_restart_fields_newest: Global Dimensions ",2I6)') geom%globalsizes(1),geom%globalsizes(2)

! If the Geometry changes, reallocate Scatter structure and rescan input files
! Do this only for the first ensemble member to save significant time
! ----------------------------------------------------------------------------
if( ((geom%globalsizes(1) .ne. globalsizes(1)) .or. (geom%globalsizes(2) .ne. globalsizes(2))) .or. fields_changed) then
  tb1 = MPI_Wtime()
  globalsizes = geom%globalsizes

  need_to_reallocate_ps = .false.
  if(.not. first_pass) then
    do r=0,mpp_npes()-1
      if (allocated(Scatter(r)%senddispls_col)) deallocate(Scatter(r)%senddispls_col)
      if (allocated(Scatter(r)%sendcounts_col)) deallocate(Scatter(r)%sendcounts_col)
      if (allocated(Scatter(r)%senddispls_row)) deallocate(Scatter(r)%senddispls_row)
      if (allocated(Scatter(r)%sendcounts_row)) deallocate(Scatter(r)%sendcounts_row)
      !if (mpp_pe() == 0) write(6,'("fv3jedi_geom::delete: About to free localvec "I6)') r
      if (allocated(nlev)) then
        if (nlev(r) > 0) call MPI_Type_free(Scatter(r)%localvec, ierr)
        if (nlev(r) > 0) call MPI_Type_free(Scatter(r)%vec, ierr)
      endif
    enddo
    deallocate(Scatter)
  endif
  allocate(Scatter(0:npes-1))

!  do var = 1,size(fields)
!    if(rank==0) write(6,'("read_restart_fields_newest: Variables to process ",L,I4,2A)') first_pass, var,' ',trim(fields(var)%long_name)
!  enddo

  ! Loop over fields to identify their restart file
  ! Only enter here if its the first time fv3jedi_io_fms::read() is called.
  ! Reusing the arrays generated in the first call saves a bunch of walltime.
  ! This assumes the bkg and ens files are the same resolution.
  ! -------------------------------------------------------------------------
  rstflag(:) = .false.
  do var = 1,size(fields)
    !if(rank==0) write(6,'("read_restart_fields_newest: Scan files for variable ",I4,2A)') var,' ',trim(fields(var)%long_name)
    ! If need ps is not in file will compute from delp so read delp in place of ps, but only if delp is NOT already present in the fields array
    if (trim(fields(var)%long_name) == 'air_pressure_at_surface' .and. .not.self%ps_in_file) then
      indexof_ps = var
      !write(6,'("read_restart_fields_newest: indexof_ps ",I4,L,I4)') indexof_ps,havedelp,indexof_delp
      if (havedelp) then ! SKD NEW EDIT
        fields(indexof_ps)%model_name = ''   ! PS will be computed, not read ! SKD NEW EDIT
        cycle ! Do not register delp twice ! SKD NEW EDIT
      else
        ! Reallocate fields array for ps (2D) to hold delp (3D) instead.  Set need_to_reallocate_ps to true so this gets done for every ensemble member
        need_to_reallocate_ps = .true.
        !write(6,'("read_restart_fields_newest: reallocating space for air_pressure_at_surface to make room for delp ",3I4)') indexof_ps,size(fields(indexof_ps)%array,3),self%npz
        deallocate(fields(indexof_ps)%array)
        allocate(fields(indexof_ps)%array(fields(indexof_ps)%isc:fields(indexof_ps)%iec, &
                 fields(indexof_ps)%jsc:fields(indexof_ps)%jec,1:self%npz))
        fields(indexof_ps)%long_name = 'air_pressure_thickness'
        fields(indexof_ps)%npz = self%npz
        ! Create io name lookup.  Reuse name from config file
        if ( field_io_names%get("air_pressure_thickness", str) ) then
          write(6,'("read_restart_fields_newest: Using string from config ",A)') trim(str)
          call field_io_names_local%set("air_pressure_thickness", trim(str))
        else
          write(6,'("read_restart_fields_newest: Taking a WAG as to name of delp in the input files",A)')
          call field_io_names_local%set("air_pressure_thickness", "delp")
        endif
      endif ! SKD NEW EDIT
    endif

    ! Get file to use
    call get_io_file(self, fields(var), indexrst)

    ! Get UFS variable name
    fields(var)%model_name = ioname(trim(fields(var)%long_name), field_io_names_local)
    !write(6,'("read_restart_fields_newest: JEDI -> UFS variable mapping ",I4,4A)') var,' ',trim(fields(var)%long_name),' -> ',trim(fields(var)%model_name)

    ! Append variable name onto list for each file.  Will need a mapping between this list and the order in the fields array
    if (len_trim(tmpvarlist(indexrst)) > 0) then
      tmpvarlist(indexrst)=trim(tmpvarlist(indexrst)) //' '// trim(fields(var)%model_name)
    else
      tmpvarlist(indexrst)=trim(fields(var)%model_name)
    endif

    rstflag(indexrst) = .true.  ! prevent opening this file again
    num_restart_vars(indexrst) = num_restart_vars(indexrst) + 1
  enddo

  if(allocated(nlev)) deallocate(nlev)
  allocate(nlev(0:npes-1))

  totalnumfiles=count(rstflag(:) .eq. .true.)
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

  ! Total number of variables that will actually be read from files
  ! (this can be smaller than size(fields) when PS is computed from DELP)
  allocate(nlevpervar(sum(numvar)))
  allocate(varnames(sum(numvar)))
  if(allocated(nc_vartype)) deallocate(nc_vartype)
  allocate(nc_vartype(sum(numvar)))

  if(rank==0) then
    ! find dimension of each field
    call ncfs_all%init(totalnumfiles, FileNamesToProcess, numvar, varlist)
    call ncfs_all%fill_dims()

    ! distibute variables to each core
    call mpiioarg%init(npes)
    call mpiioarg%arrange(ncfs_all)

    nlev(:)=0
    do i=0,npes-1
      if( (mpiioarg%lvlend(i+1) > 0) .and. (mpiioarg%lvlbegin(i+1) > 0) ) then
        nlev(i) = (mpiioarg%lvlend(i+1) - mpiioarg%lvlbegin(i+1) + 1)
      endif
    enddo
    ntotallev = sum(ncfs_all%dim_3)

    nlevpervar(:ncfs_all%numvar) = ncfs_all%dim_3(:)
    varnames(:ncfs_all%numvar) = ncfs_all%list_varname(:)  ! Names of vcariables to be processed
    nc_vartype(:ncfs_all%numvar) = ncfs_all%vartype(:)        ! NetCDF type of each variable
    !write(6,'("read_restart_fields_newest: total number of variables to read ",2I4)') ncfs_all%numvar, sum(numvar)
    call ncfs_all%close()
  endif

  deallocate(varlist)

  ! Let all ranks know what is going on
  call MPI_Scatter(mpiioarg%fileid  ,  1,   mpi_integer, mype_fileid ,  1, mpi_integer  , 0, MPI_COMM_WORLD,ierr)
  call MPI_Scatter(mpiioarg%varname , 20, mpi_character, mype_varname, 20, mpi_character, 0, MPI_COMM_WORLD,ierr)
  call MPI_Scatter(mpiioarg%vartype ,  1,   mpi_integer, mype_vartype,  1, mpi_integer  , 0, MPI_COMM_WORLD,ierr)
  call MPI_Scatter(mpiioarg%lvlbegin,  1,   mpi_integer, mype_lbegin ,  1, mpi_integer  , 0, MPI_COMM_WORLD,ierr)
  call MPI_Scatter(mpiioarg%lvlend  ,  1,   mpi_integer, mype_lend   ,  1, mpi_integer  , 0, MPI_COMM_WORLD,ierr)

  call MPI_Bcast(ntotallev, 1, mpi_integer, 0, MPI_COMM_WORLD,ierr)
  call MPI_Bcast(nlev, npes, mpi_integer, 0, MPI_COMM_WORLD,ierr)
  call MPI_Bcast(nlevpervar, sum(numvar), mpi_integer, 0, MPI_COMM_WORLD,ierr)
  call MPI_Bcast(varnames, 20*sum(numvar), mpi_character, 0, MPI_COMM_WORLD,ierr)
  call MPI_Bcast(nc_vartype, sum(numvar), mpi_integer, 0, MPI_COMM_WORLD,ierr)

  ! Map field level to the process handling that level
  ! LevelToProcMap(levelIndex) gives the rank
  if(allocated(LevelToProcMap)) deallocate(LevelToProcMap)
  allocate(LevelToProcMap(ntotallev))
  LevelToProcMap(:) = -999
  l=1
  do r=0,npes-1
    do i=1,nlev(r)
      LevelToProcMap(l) = r
      l=l+1
    enddo
  enddo

  if (any(LevelToProcMap(:) == -999)) then
    write(6,'("read_restart_fields_newest: Some sigma level were not assigned")')
    call MPI_Abort(MPI_COMM_WORLD,10,ierr)
  endif

  ! Map combined level to variable
  ! LevelToVariableMap(levelIndex) gives an index into the fields array
  if(allocated(LevelToVariableMap)) deallocate(LevelToVariableMap)
  allocate(LevelToVariableMap(ntotallev))
  LevelToVariableMap(:) = -999
  l=1
  do var=1,sum(numvar)
    do i=1,nlevpervar(var)
      LevelToVariableMap(l) = var
      l=l+1
    enddo
  enddo

  if (any(LevelToVariableMap(:) == -999)) then
    loc = findloc(LevelToVariableMap, value=-999, dim=1, back=.false.)
    write(6,'("read_restart_fields_newest: Some variables were not assigned ",2I6)') ntotallev,loc
    call MPI_Abort(MPI_COMM_WORLD,11,ierr)
  endif


  ! Map combined level to variable level
  ! LevelToLevelMap(levelIndex) gives an index into fields(var)%array
  if(allocated(LevelToLevelMap)) deallocate(LevelToLevelMap)
  allocate(LevelToLevelMap(ntotallev))
  LevelToLevelMap(:) = -999
  l=1
  do var=1,sum(numvar)
    do i=1,nlevpervar(var)
      LevelToLevelMap(l) = i
      l=l+1
    enddo
  enddo
  deallocate(nlevpervar)

  if (any(LevelToLevelMap(:) == -999)) then
    write(6,'("read_restart_fields_newest: Some levels were not assigned")')
    call MPI_Abort(MPI_COMM_WORLD,12,ierr)
  endif

  ! Map JEDI fields array to variable list obtained from above
  ! VarToVarMap(var2) gives an index into fields(var).
  ! The var2 index would come from LevelToVariableMap()
  if(allocated(VarToVarMap)) deallocate(VarToVarMap)
  allocate(VarToVarMap(sum(numvar)))
  VarToVarMap(:) = -999
  do var = 1,size(fields)
    do var2 = 1,sum(numvar)
      !write(6,'("read_restart_fields_newest: VarToVarMap ",2I6,4A)') var, var2,' ',trim(fields(var)%model_name),' ',trim(varnames(var2))
      if (trim(fields(var)%model_name) .ne. trim(varnames(var2))) then
        cycle
      else
        VarToVarMap(var2) = var
        exit
      endif
    enddo
  enddo
  deallocate(varnames)
  deallocate(numvar)

  if (any(VarToVarMap(:) == -999)) then
    write(6,'("read_restart_fields_newest: Some variables not mapped",21I6)') VarToVarMap(1:sum(numvar))
    call MPI_Abort(MPI_COMM_WORLD,112,ierr)
  endif

  ! Create sub-communicator to handle each file
  key=rank+1
  if(mype_fileid > 0 .and. mype_fileid <= totalnumfiles) then
       color = mype_fileid
  else
       color = MPI_UNDEFINED
  endif

  call MPI_Comm_split(mpi_comm_world,color,key,read_comm,ierr)
  if ( ierr /= 0 ) then
       write(6,'(a,i5)')'***ERROR*** after mpi_comm_create with iret = ',ierr
       call mpi_abort(mpi_comm_world,101,ierr)
  endif

  first_pass = .false.

  te1 = MPI_Wtime()
  times(1) = te1-tb1

  ! Update cached fields after successful rebuild
  cached_nfields = size(fields)
  if (allocated(cached_field_names)) deallocate(cached_field_names)
  if (allocated(cached_field_nz))    deallocate(cached_field_nz)
  allocate(cached_field_names(cached_nfields))
  allocate(cached_field_nz(cached_nfields))
  do f = 1, cached_nfields
    cached_field_names(f) = fields(f)%model_name
    if (allocated(fields(f)%array)) then
      cached_field_nz(f) = size(fields(f)%array, 3)
    else
      cached_field_nz(f) = -1
    endif
  enddo

endif ! First pass

! Reallocate space to hold delp if needed
if (need_to_reallocate_ps) then
  do var = 1,size(fields)
    ! If need ps is not in file will compute from delp so read delp in place of ps, but only if delp is NOT already present in the fields array
    if (trim(fields(var)%long_name) == 'air_pressure_at_surface' .and. .not.self%ps_in_file) then
      indexof_ps = var
      !write(6,'("read_restart_fields_newest: indexof_ps ",I4,L,I4)') indexof_ps,havedelp,indexof_delp
      if (havedelp) then
        fields(indexof_ps)%model_name = ''   ! PS will be computed, not read ! SKD NEW EDIT
        cycle ! Do not register delp twice ! SKD NEW EDIT
      else
        !write(6,'("read_restart_fields_newest: reallocating space for air_pressure_at_surface to make room for delp ",3I4)') indexof_ps,size(fields(indexof_ps)%array,3),self%npz
        deallocate(fields(indexof_ps)%array)
        allocate(fields(indexof_ps)%array(fields(indexof_ps)%isc:fields(indexof_ps)%iec, &
                 fields(indexof_ps)%jsc:fields(indexof_ps)%jec,1:self%npz))
        fields(indexof_ps)%long_name = 'air_pressure_thickness'
        fields(indexof_ps)%npz = self%npz
        ! Create io name lookup.  Reuse name from config file
        if ( field_io_names%get("air_pressure_thickness", str) ) then
          write(6,'("read_restart_fields_newest: Using string from config ",A)') trim(str)
          call field_io_names_local%set("air_pressure_thickness", trim(str))
        else
          write(6,'("read_restart_fields_newest: Taking a WAG as to name of delp in the input files",A)')
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

  ! Allocate memory to hold the rank-local patch of the global domain.
  ! Only need this when the variable on file has a different byte size than
  ! expected by the application (kind_real)
  tb2 = MPI_Wtime()
  !do var = 1,size(fields)
  do var = 1,size(nc_vartype) ! SKD NEW EDIT
    var2 = VarToVarMap(var)
    !write(6,'("read_restart_fields_newest: Should we allocate scatter space for variable: ",3I4,2A)') nc_vartype(var), var, var2,' ',trim(fields(var2)%long_name)
    select case (nc_vartype(var))
    case (NF90_SHORT)
      write(6,'("NF90_SHORT data type not supported")')
      call MPI_Abort(MPI_COMM_WORLD, 1, ierr)
    case (NF90_INT)
      if(kind_real /= c_int) then
        allocate(real(kind=c_int) :: fields(var2)%array_file_scatter(geom%localsizes(1), geom%localsizes(2), 1))
      endif
    case (NF90_FLOAT)
      if(kind_real /= c_float) then
        allocate(real(kind=c_float) :: fields(var2)%array_file_scatter(geom%localsizes(1), geom%localsizes(2), 1))
      endif
    case (NF90_DOUBLE)
      if(kind_real /= c_double) then
        ! This scenario is handled by reading the r8 field into an r4 array relying on the NetCDF library to do the conversion during the parallel reads
        !allocate(real(kind=c_double) :: fields(var)%array_file_scatter(geom%localsizes(1), geom%localsizes(2), size(fields(var)%array,3)))
      endif
    case default
      write(6,'("read_restart_fields_newest: Unknown NetCDF type for variable: ",3I4,2A)') nc_vartype(var), var, var2,' ',trim(fields(var)%long_name)
      call MPI_Abort(MPI_COMM_WORLD, 1, ierr)
    end select
  enddo

!
! read 2D slab from each file using sub communicator
!

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

    iret=nf90_open(trim(FileNamesToProcess(mype_fileid)),nf90_nowrite,ncioid,comm=read_comm,info=MPI_INFO_NULL)
    if(iret/=nf90_noerr) then
      write(6,*)' problem opening ', trim(FileNamesToProcess(mype_fileid)),' fileid=',mype_fileid,', Status =',iret
      write(6,*)  nf90_strerror(iret)
      stop 333
    endif

    do ilev=mype_lbegin,mype_lend
      starts=(/1,1,ilev/)
      counts=(/geom%globalsizes(1), geom%globalsizes(2), 1/)

      call check( nf90_inq_varid(ncioid, trim(adjustl(mype_varname)), var_id) )

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
        ! so convert to c_float during read to avoid scattering more data than needed.
        d2r4ptr => d3r4(:,:,ilev)
        iret=nf90_get_var(ncioid,var_id,d2r4ptr,start=starts,count=counts)
        nullify(d2r4ptr)
      endif
    enddo  ! ilev

    iret=nf90_close(ncioid)
  endif ! read_comm
  call MPI_Barrier(MPI_COMM_WORLD,ierr)
  te2 = MPI_Wtime()
  times(2) = te2-tb2

!
! Scatter file data to all ranks and convert to application type as needed
! ------------------------------------------------------------------------
  tb3 = MPI_Wtime()
  l=mype_lbegin
  do level = 1, ntotallev ! Loop over combined set of levels
    var = LevelToVariableMap(level) ! File space
    var2 = VarToVarMap(var)         ! JEDI space
    if(nc_vartype(var) == NF90_FLOAT .and. kind_real == c_float) then
      if(rank==LevelToProcMap(level)) then
        globalptr => d3r4(:,:,l) ! Only the owner of the slab sets globalptr
        l=l+1
      endif
      localptr => fields(var2)%array(:,:,:)
      call TwoPhaseScatterPolymorphic(geom, rank, LevelToProcMap(level), globalptr, LevelToLevelMap(level), fields(var2)%array)
      nullify(localptr)
    elseif(nc_vartype(var) == NF90_FLOAT .and. kind_real == c_double) then
      if(rank==LevelToProcMap(level)) then
        globalptr => d3r4(:,:,l) ! Only the owner of the slab sets globalptr
        l=l+1
      endif
      select type (an => fields(var2)%array_file_scatter)
      type is (real(kind=c_float))
        call TwoPhaseScatterPolymorphic(geom, rank, LevelToProcMap(level), globalptr, 1, fields(var2)%array_file_scatter)
        fields(var2)%array(:,:,LevelToLevelMap(level)) = real(an(:,:,1), kind=kind_real)
      end select
    elseif(nc_vartype(var) == NF90_DOUBLE .and. kind_real == c_double) then
      !write(6,'("TwoPhaseScatter: same type ",5I6,2A)') var,var2,level, LevelToProcMap(level), LevelToLevelMap(level),' ',trim(fields(var2)%long_name)
      if(rank==LevelToProcMap(level)) then
        globalptr => d3r8(:,:,l) ! Only the owner of the slab sets globalptr
        l=l+1
      endif
      localptr => fields(var2)%array(:,:,:)
      call TwoPhaseScatterPolymorphic(geom, rank, LevelToProcMap(level), globalptr, LevelToLevelMap(level), fields(var2)%array)
      nullify(localptr)
    elseif(nc_vartype(var) == NF90_DOUBLE .and. kind_real == c_float) then
      if(rank==LevelToProcMap(level)) then
        globalptr => d3r4(:,:,l)
        l=l+1
      endif
      ! File provides c_double but application wants c_float.
      ! Convert first then scatter directly to destination
      ! Conversion from c_double to c_float took place during NetCDF read
      localptr => fields(var2)%array(:,:,:)
      call TwoPhaseScatterPolymorphic(geom, rank, LevelToProcMap(level), globalptr, LevelToLevelMap(level), localptr)
      nullify(localptr)
    endif
    if(associated(globalptr)) nullify(globalptr)
  enddo
  te3 = MPI_Wtime()
  times(3) = te3-tb3
  call MPI_Reduce(times, walltime, 3, MPI_DOUBLE_PRECISION, MPI_MAX, 0, MPI_COMM_WORLD, ierr)
  if (rank == 0) write(*,'(A,4F12.6)') 'read_restart_fields_newest: Walltimes ', walltime(1), walltime(2), walltime(3), sum(walltime)

  ! Deallocate temporary arrays
  if (MPI_COMM_NULL /= read_comm) then
    if(allocated(d3r4)) deallocate(d3r4)
    if(allocated(d3r8)) deallocate(d3r8)
  endif

  do var = 1,size(fields)
    if (allocated(fields(var)%array_file_scatter)) deallocate(fields(var)%array_file_scatter)
  enddo

! This cleanup needs to happen at the end of the job.
! I don't know where to put it so just placing here for visibility
!do r=0,mpp_npes()-1
!  if (allocated(Scatter(r)%senddispls_col)) deallocate(Scatter(r)%senddispls_col)
!  if (allocated(Scatter(r)%sendcounts_col)) deallocate(Scatter(r)%sendcounts_col)
!  if (allocated(Scatter(r)%senddispls_row)) deallocate(Scatter(r)%senddispls_row)
!  if (allocated(Scatter(r)%sendcounts_row)) deallocate(Scatter(r)%sendcounts_row)
!  !if (mpp_pe() == 0) write(6,'("fv3jedi_geom::delete: About to free localvec "I6)') r
!  !if (nlev(r) > 0) call MPI_Type_free(Scatter(r)%localvec, ierror)
!  !if (nlev(r) > 0) call MPI_Type_free(Scatter(r)%vec, ierror)
!enddo
!deallocate(Scatter)


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

contains

  subroutine TwoPhaseScatterPolymorphic(geom, rank, owner, globalpointer, lev, localdata)
    use mpi
    implicit none

    type(fv3jedi_geom), intent(inout):: geom
    integer, intent(in)              :: rank, owner, lev
    class(*), contiguous, intent(in) :: globalpointer(:,:)
    class(*), contiguous, intent(inout) :: localdata(:,:,:)

    class(*), allocatable :: coldata(:,:)
    integer :: temptype, mpiprec
    integer(kind=MPI_ADDRESS_KIND) :: lb, extent
    integer :: row, col, ierr!, locnrows, rowsize, colsize
    integer :: myrow, mycol, blocks(2), globalsizes(2), localsizes(2)

    myrow = geom%NSindex
    mycol = geom%EWindex
    blocks= geom%layout
    globalsizes = geom%globalsizes
    localsizes = geom%localsizes

    select type (localdata)
    type is (real(kind=4))
      mpiprec=MPI_REAL
      lb=0
      extent=4
    type is (real(kind=8))
      mpiprec=MPI_DOUBLE_PRECISION
      lb=0
      extent=8
    class default
      write(6,'("TwoPhaseScatterPolymorphic: Unknown type")')
      call MPI_Abort(MPI_COMM_WORLD, 22, ierr)
    end select

    ! First scatter by columns from owner to rank 0 in the row communicator
    if (myrow == geom%MyRowGlobal(owner)) then

      if (.not. Scatter(owner)%lalloc) then
        allocate(Scatter(owner)%senddispls_col(0:blocks(2)-1))
        allocate(Scatter(owner)%sendcounts_col(0:blocks(2)-1))

        Scatter(owner)%senddispls_col(0) = 0
        Scatter(owner)%sendcounts_col(0) = geom%NumColsPerRank(0) * globalsizes(1)
        do col= 1, blocks(2)-1
          Scatter(owner)%sendcounts_col(col) = geom%NumColsPerRank(col) * globalsizes(1)
          Scatter(owner)%senddispls_col(col) = Scatter(owner)%senddispls_col(col-1) + Scatter(owner)%sendcounts_col(col-1)
        enddo
      endif

      ! Allocate column data
      select type (localdata)
      type is (real(kind=4))
        allocate(real(kind=4) :: coldata(globalsizes(1), geom%NumColsPerRank(mycol)))
      type is (real(kind=8))
        allocate(real(kind=8) :: coldata(globalsizes(1), geom%NumColsPerRank(mycol)))
      end select

      select type (localdata)
      type is (real(kind=4))
        if (rank == owner) then
          call MPI_Scatterv(globalpointer, Scatter(owner)%sendcounts_col, Scatter(owner)%senddispls_col, mpiprec, coldata, Scatter(owner)%sendcounts_col(mycol), mpiprec, geom%MyRankInRowComm(owner), geom%rowComm, ierr)
        else
          call MPI_Scatterv(MPI_BOTTOM, Scatter(owner)%sendcounts_col, Scatter(owner)%senddispls_col, mpiprec, coldata, Scatter(owner)%sendcounts_col(mycol), mpiprec, geom%MyRankInRowComm(owner), geom%rowComm, ierr)
        endif
      type is (real(kind=8))
        if (rank == owner) then
          call MPI_Scatterv(globalpointer, Scatter(owner)%sendcounts_col, Scatter(owner)%senddispls_col, mpiprec, coldata, Scatter(owner)%sendcounts_col(mycol), mpiprec, geom%MyRankInRowComm(owner), geom%rowComm, ierr)
        else
          call MPI_Scatterv(MPI_BOTTOM, Scatter(owner)%sendcounts_col, Scatter(owner)%senddispls_col, mpiprec, coldata, Scatter(owner)%sendcounts_col(mycol), mpiprec, geom%MyRankInRowComm(owner), geom%rowComm, ierr)
        endif
      end select

    endif

    ! The head of each column now has all data belonging to all ranks in the column
    ! Now scatter from each column head to other ranks in the same column
    if (.not. Scatter(owner)%lalloc) then
      allocate(Scatter(owner)%senddispls_row(0:blocks(1)-1))
      allocate(Scatter(owner)%sendcounts_row(0:blocks(1)-1))

      Scatter(owner)%senddispls_row(0) = 0
      Scatter(owner)%sendcounts_row(0) = geom%NumRowsPerRank(0)
      do row = 1, blocks(1)-1
        Scatter(owner)%sendcounts_row(row) = geom%NumRowsPerRank(row)
        Scatter(owner)%senddispls_row(row) = Scatter(owner)%senddispls_row(row-1) + geom%NumRowsPerRank(row-1)
      enddo

      call MPI_Type_vector(localsizes(2), 1, globalsizes(1), mpiprec, temptype, ierr)
      call MPI_Type_create_resized(temptype, lb, extent, Scatter(owner)%vec, ierr)
      call MPI_Type_commit(Scatter(owner)%vec, ierr)

      call MPI_Type_vector(localsizes(2), 1, geom%NumRowsPerRank(myrow), mpiprec, temptype, ierr)
      call MPI_Type_create_resized(temptype, lb, extent, Scatter(owner)%localvec, ierr)
      call MPI_Type_commit(Scatter(owner)%localvec, ierr)

      Scatter(owner)%lalloc=.true.
    endif

    select type (localdata)
    type is (real(kind=4))
      if (myrow == geom%MyRowGlobal(owner)) then
        call MPI_Scatterv(coldata, Scatter(owner)%sendcounts_row, Scatter(owner)%senddispls_row, Scatter(owner)%vec, localdata(1,1,lev), Scatter(owner)%sendcounts_row(myrow), Scatter(owner)%localvec, geom%MyRankInColComm(owner), geom%colComm, ierr)
      else
        call MPI_Scatterv(MPI_BOTTOM, Scatter(owner)%sendcounts_row, Scatter(owner)%senddispls_row, Scatter(owner)%vec, localdata(1,1,lev), Scatter(owner)%sendcounts_row(myrow), Scatter(owner)%localvec, geom%MyRankInColComm(owner), geom%colComm, ierr)
      endif
    type is (real(kind=8))
      if (myrow == geom%MyRowGlobal(owner)) then
        call MPI_Scatterv(coldata, Scatter(owner)%sendcounts_row, Scatter(owner)%senddispls_row, Scatter(owner)%vec, localdata(1,1,lev), Scatter(owner)%sendcounts_row(myrow), Scatter(owner)%localvec, geom%MyRankInColComm(owner), geom%colComm, ierr)
      else
        call MPI_Scatterv(MPI_BOTTOM, Scatter(owner)%sendcounts_row, Scatter(owner)%senddispls_row, Scatter(owner)%vec, localdata(1,1,lev), Scatter(owner)%sendcounts_row(myrow), Scatter(owner)%localvec, geom%MyRankInColComm(owner), geom%colComm, ierr)
      endif
    end select
    if (myrow == geom%MyRowGlobal(owner)) deallocate(coldata)

  end subroutine TwoPhaseScatterPolymorphic

end subroutine read_restart_fields_newest

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

subroutine write_restart_all_new3(self, geom, fields, vdate, field_io_names, field_io_scaling)

type(fv3jedi_io_fms),      intent(inout) :: self
type(fv3jedi_geom),        intent(inout) :: geom
type(fv3jedi_field), target,       intent(inout) :: fields(:)     !< Fields to be written
type(datetime),            intent(in)    :: vdate         !< DateTime
type(fckit_configuration), intent(in)    :: field_io_names
type(fckit_configuration), intent(in)    :: field_io_scaling

type(file_t) :: FileType(numfiles)
logical :: rstflag(numfiles)
integer :: ncid(numfiles), num_restart_vars(numfiles)
integer :: n, indexrst, var, var2, idrst, date(6), sz
integer :: rank, npes, varid, level, l, ierr, rc, b, e
integer :: idate, isecs
type(FmsNetcdfDomainFile_t) :: fileobj(numfiles)
class(*), pointer :: globalptr(:,:) => null()
integer :: start(3), counts(3)
character(len=64)  :: datefile
character(len=8), allocatable :: dim_names(:)
real(kind=kind_real) :: io_unscaling_factor
real(kind=8) :: tb1,tb2
real(kind=8) :: te1,te2
character(len=256) :: tmppath
character(len=NF90_MAX_NAME) :: FileName
integer :: dimids(4), oldMode
integer, dimension(:), allocatable :: chunksizes
character(len=32) :: chksum
integer(kind=8) :: chksum_i8
integer(kind=8) :: mold(1)

rank=mpp_pe()
npes=mpp_npes()

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
ncid(:)=-999
num_restart_vars(:)=0

! Loop over fields to figure out where all the variables go
! ---------------------------------------------------------
do var = 1,size(fields)
  ! Get file to use
  call get_io_file(self, fields(var), indexrst)

  ! Get UFS variable name
  fields(var)%model_name = ioname(trim(fields(var)%long_name), field_io_names)
  rstflag(indexrst) = .true.
  num_restart_vars(indexrst) = num_restart_vars(indexrst) + 1
  FileType(indexrst)%VariableIndecies(num_restart_vars(indexrst)) = var

  ! Get the scaling factor
  io_unscaling_factor = iounscale(fields(var)%long_name, field_io_scaling)
enddo

! Create files, add dimensions and variable metadata
! --------------------------------------------------
do n = 1, numfiles
  if (rstflag(n)) then
    FileName=trim(self%datapath)//'/'//trim(self%filenames(n))
    rc = nf90_create(trim(FileName), ior(ior(NF90_CLOBBER,NF90_NETCDF4),NF90_MPIIO), ncid(n), comm=MPI_COMM_WORLD, info=MPI_INFO_NULL)
    if(rc == nf90_noerr) then
      dimids(:)=-999
      call check ( nf90_set_fill(ncid(n), NF90_FILL, oldMode) )

      call check( nf90_def_dim(ncid(n), 'xaxis_1', geom%globalsizes(1), dimids(1)) )
      call check( nf90_def_dim(ncid(n), 'yaxis_1', geom%globalsizes(2), dimids(2)) )
      call check( nf90_def_var(ncid(n), 'xaxis_1', NF90_DOUBLE, dimids(1), varid) )
      call check( nf90_put_att(ncid(n), varid, "cartesian_axis", "X") )
      call check( nf90_put_att(ncid(n), varid, "long_name", "xaxis_1") )
      call check( nf90_put_att(ncid(n), varid, "units", "none") )

      call check( nf90_def_var(ncid(n), 'yaxis_1', NF90_DOUBLE, dimids(2), varid) )
      call check( nf90_put_att(ncid(n), varid, "cartesian_axis", "Y") )
      call check( nf90_put_att(ncid(n), varid, "long_name", "yaxis_1") )
      call check( nf90_put_att(ncid(n), varid, "units", "none") )

      ! Create a zaxis_1 dimension if any of the variables assigned to this file have a third dimension greater than 1
      ! This is true for fv_core.res, fv_srf_wnd.res and sfc_data
      sz=1
      do var = 1, num_restart_vars(n)
        var2 = FileType(n)%VariableIndecies(var)
        sz=max(sz,size(fields(var2)%array,3))
      enddo
      if( sz > 1 ) then
        call check( nf90_def_dim(ncid(n), 'zaxis_1', sz, dimids(3)) )
        call check( nf90_def_dim(ncid(n), 'Time', NF90_UNLIMITED, dimids(4)) )
        call check( nf90_def_var(ncid(n), 'zaxis_1', NF90_DOUBLE, dimids(3), varid) )
        call check( nf90_put_att(ncid(n), varid, "long_name", "zaxis_1") )
        call check( nf90_put_att(ncid(n), varid, "units", "none") )
        call check( nf90_def_var(ncid(n), 'Time', NF90_DOUBLE, dimids(4), varid) )
        call check( nf90_put_att(ncid(n), varid, "long_name", "Time") )
        call check( nf90_put_att(ncid(n), varid, "units", "time level") )
      else
        call check( nf90_def_dim(ncid(n), 'Time', NF90_UNLIMITED, dimids(4)) )
        call check( nf90_def_var(ncid(n), 'Time', NF90_DOUBLE, dimids(4), varid) )
        call check( nf90_put_att(ncid(n), varid, "long_name", "Time") )
        call check( nf90_put_att(ncid(n), varid, "units", "time level") )
      endif

      FileType(n)%FileName = FileName
    else
      call abor1_ftn('fv3jedi_io_fms_mod.write_restart_all: file ' &
                      // trim(FileName) // ' could not be created')
    end if

    call check ( nf90_set_fill(ncid(n), NF90_NOFILL, oldMode) )

    do var = 1, num_restart_vars(n)
      var2 = FileType(n)%VariableIndecies(var)
      if(size(fields(var2)%array,3) > 1) then
        chunksizes = [geom%globalsizes(1), geom%globalsizes(2), 1, 1]
        call check( nf90_def_var(ncid(n), trim(fields(var2)%model_name), NF90_DOUBLE, dimids, varid, chunksizes=chunksizes) )
        !call check( nf90_def_var(ncid(n), trim(fields(var2)%model_name), NF90_DOUBLE, dimids, varid, chunksizes=chunksizes, fletcher32=.true.) )
        call check( nf90_put_att(ncid(n), varid, "long_name", trim(fields(var2)%long_name)) )
        call check( nf90_put_att(ncid(n), varid, "units", trim(fields(var2)%units)) )

        ! Use FMS method to create a checksum
        chksum_i8 = sum(INT(TRANSFER(fields(var2)%array,mold),8))
        call MPI_ALLREDUCE( MPI_IN_PLACE, chksum_i8, 1, MPI_INTEGER8, MPI_SUM, MPI_COMM_WORLD, ierr )
        chksum = ""
        write(chksum, "(Z16)") chksum_i8
        call check( nf90_put_att(ncid(n), varid, "checksum", trim(chksum)) )
      else
        chunksizes = [geom%globalsizes(1), geom%globalsizes(2), 1]
        call check( nf90_def_var(ncid(n), trim(fields(var2)%model_name), NF90_DOUBLE, (/ dimids(1), dimids(2), dimids(4) /), varid, chunksizes=chunksizes) )
        !call check( nf90_def_var(ncid(n), trim(fields(var2)%model_name), NF90_DOUBLE, (/ dimids(1), dimids(2), dimids(4) /), varid, chunksizes=chunksizes, fletcher32=.true.) )
        call check( nf90_put_att(ncid(n), varid, "long_name", trim(fields(var2)%long_name)) )
        call check( nf90_put_att(ncid(n), varid, "units", trim(fields(var2)%units)) )

        ! Use FMS method to create a checksum
        chksum_i8 = sum(INT(TRANSFER(fields(var2)%array,mold),8))
        call MPI_ALLREDUCE( MPI_IN_PLACE, chksum_i8, 1, MPI_INTEGER8, MPI_SUM, MPI_COMM_WORLD, ierr )
        chksum = ""
        write(chksum, "(Z16)") chksum_i8
        call check( nf90_put_att(ncid(n), varid, "checksum", trim(chksum)) )
      endif
    enddo ! var loop
  endif
enddo


! Exit define mode
! ----------------
do n = 1, numfiles
  if (rstflag(n)) then
    call check( nf90_enddef(ncid(n)) )
  endif
enddo

! Loop over files and write fields
! --------------------------------
do n = 1, numfiles
  if (rstflag(n)) then
    do var = 1, num_restart_vars(n)
      var2 = FileType(n)%VariableIndecies(var)

      call check( nf90_inq_varid(ncid(n), trim(fields(var2)%model_name), varid) )
      call check( nf90_var_par_access(ncid(n), varid, nf90_collective) )

      start = (/ geom%isc,  geom%jsc,  1 /)
      counts= (/ geom%localsizes(1), geom%localsizes(2), size(fields(var2)%array,3) /)
      call check( nf90_put_var(ncid(n), varid, fields(var2)%array, start=start, count=counts) )

    enddo ! var loop
  endif
enddo

! Close opened files
! ------------------
do n = 1, numfiles
  if (rstflag(n)) then
    call check( nf90_close(ncid(n)) )
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

end subroutine write_restart_all_new3

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

! Reflectivity is in phy_data
if (trim(field%long_name) == 'equivalent_reflectivity_factor') io_file = 'physics'

! Soil fixes since these are now 3d variables
if (trim(field%long_name) == 'soilt') io_file = 'surface'
if (trim(field%long_name) == 'soilm') io_file = 'surface'


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

end module fv3jedi_io_fms_mod
