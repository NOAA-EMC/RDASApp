! (C) Copyright 2017-2023 UCAR
!
! This software is licensed under the terms of the Apache Licence Version 2.0
! which can be obtained at http://www.apache.org/licenses/LICENSE-2.0.

!> Fortran module handling geometry for the FV3 model

module fv3jedi_geom_mod

use netcdf
use mpi
use string_f_c_mod

! atlas uses
use atlas_module,               only: atlas_field, atlas_fieldset, &
                                      atlas_integer, atlas_real, atlas_functionspace

! fckit uses
use fckit_mpi_module,           only: fckit_mpi_comm
use fckit_configuration_module, only: fckit_configuration

! fms uses
use fms_mod,                    only: fms_init
use mpp_mod,                    only: mpp_exit, mpp_pe, mpp_npes, mpp_error, FATAL, NOTE
use mpp_domains_mod,            only: domain2D, mpp_deallocate_domain, mpp_define_layout, &
                                      mpp_define_mosaic, mpp_define_io_domain, mpp_domains_exit, &
                                      mpp_domains_set_stack_size
use ensemble_manager_mod,       only: get_ensemble_id,get_ensemble_size
use field_manager_mod,          only: fm_string_len, field_manager_init

! fv3 uses
use fv3jedi_fv3_arrays_mod,     only: fv_atmos_type, deallocate_fv_atmos_type
use fv3jedi_fv3_control_mod,    only: fv_control_init

! fv3jedi uses
use fields_metadata_mod,        only: fields_metadata
use fv3jedi_constants_mod,      only: constant
use fv3jedi_kinds_mod,          only: kind_int, kind_real
use fv3jedi_netcdf_utils_mod,   only: nccheck
use fv3jedi_fmsnamelist_mod,    only: fv3jedi_fmsnamelist

implicit none
private
public :: fv3jedi_geom, getVerticalCoord, getVerticalCoordLogP, initialize, pedges2pmidlayer

! --------------------------------------------------------------------------------------------------

!> Fortran derived type to hold geometry data for the FV3JEDI model
type :: fv3jedi_geom
  integer :: isd, ied, jsd, jed                                                     !data domain
  integer :: isc, iec, jsc, jec, kec                                                !compute domain
  integer :: npx,npy,npz,ngrid                                                      !x/y/z-dir grid edge points per tile
  integer :: layout(2), io_layout(2)                                                !Processor layouts
  integer :: ntile, ntiles                                                          !Tile number and total
  integer :: iterator_dimension                                                     !iterator dimension
  real(kind=kind_real) :: ptop                                                      !Pressure at top of domain
  type(domain2D) :: domain_fix                                                      !MPP domain
  type(domain2D), pointer :: domain                                                 !MPP domain
  real(kind=kind_real) :: stretch_fac, target_lon, target_lat
  real(kind=kind_real), allocatable, dimension(:)       :: ak, bk                   !Model level coefficients
  real(kind=kind_real), allocatable, dimension(:,:)     :: grid_lon, grid_lat       !Lat/lon centers
  real(kind=kind_real), allocatable, dimension(:,:)     :: egrid_lon, egrid_lat     !Lat/lon edges
  real(kind=kind_real), allocatable, dimension(:)       :: lon_us, lat_us           !Lat/lon centers unstructured
  real(kind=kind_real), allocatable, dimension(:,:)     :: area                     !Grid area
  real(kind=kind_real), allocatable, dimension(:,:)     :: dx, dy                   !dx/dy at edges
  real(kind=kind_real), allocatable, dimension(:,:)     :: dxc, dyc                 !dx/dy c grid
  real(kind=kind_real), allocatable, dimension(:,:,:)   :: grid, vlon, vlat
  real(kind=kind_real), allocatable, dimension(:)       :: edge_vect_n, edge_vect_e
  real(kind=kind_real), allocatable, dimension(:)       :: edge_vect_s, edge_vect_w
  real(kind=kind_real), allocatable, dimension(:,:,:,:) :: es, ew
  real(kind=kind_real), allocatable, dimension(:,:)     :: a11, a12, a21, a22
  type(fckit_mpi_comm) :: f_comm
  type(fields_metadata) :: fmd
  type(atlas_fieldset) :: geometry_fields
  ! Vertical Coordinate
  real(kind=kind_real), allocatable, dimension(:)       :: vCoord                   !Model vertical coordinate
  ! For D to (A to) C grid
  real(kind=kind_real), allocatable, dimension(:,:)     :: rarea
  real(kind=kind_real), allocatable, dimension(:,:,:)   :: sin_sg
  real(kind=kind_real), allocatable, dimension(:,:)     :: cosa_u
  real(kind=kind_real), allocatable, dimension(:,:)     :: cosa_v
  real(kind=kind_real), allocatable, dimension(:,:)     :: cosa_s
  real(kind=kind_real), allocatable, dimension(:,:)     :: rsin_u
  real(kind=kind_real), allocatable, dimension(:,:)     :: rsin_v
  real(kind=kind_real), allocatable, dimension(:,:)     :: rsin2
  real(kind=kind_real), allocatable, dimension(:,:)     :: dxa, dya
  logical :: ne_corner, se_corner, sw_corner, nw_corner
  logical :: nested = .false.
  logical :: bounded_domain = .false.
  character(len=10) :: vertcoord_type

  integer :: ensNum
  integer :: grid_type = 0
  logical :: dord4 = .true.
  type(atlas_functionspace) :: afunctionspace

  ! Configuration that holds the masks to be applied to each field
  type(fckit_configuration) :: field_masks
  type(fckit_configuration) :: field_interp_methods

  ! For use with regional restart reads
  integer :: EWindex, NSindex                                                       !column and row index into the global MPI grid
  integer, allocatable :: ibegin(:), iend(:), jbegin(:), jend(:)                    !store all subdomain coordinates
  integer, allocatable :: NumColsPerRank(:), NumRowsPerRank(:)
  integer, allocatable :: MyRowGlobal(:), MyColGlobal(:)
  integer, allocatable :: MyRankInRowComm(:), MyRankInColComm(:)
  integer :: colComm, rowComm, rowrank, colrank                                     !MPI Communicators and indexes used in the two-phase scatter
  integer :: globalsizes(2), localsizes(2)
  logical :: rowComm_created = .false.
  logical :: colComm_created = .false.

  contains
    procedure, public :: create
    procedure, public :: clone
    procedure, public :: delete
    procedure, public :: is_equal
    procedure, public :: set_and_fill_geometry_fields
    procedure, public :: get_data
    procedure, public :: get_num_nodes_and_elements
    procedure, public :: get_coords_and_connectivities

    generic, public :: fv3_nodes_to_atlas_nodes => fv3_nodes_to_atlas_nodes_r, &
                                                   fv3_nodes_to_atlas_nodes_i

    procedure, private :: get_num_nodes_and_elements_global
    procedure, private :: get_num_nodes_and_elements_regional
    procedure, private :: get_coords_and_connectivities_global
    procedure, private :: get_coords_and_connectivities_regional
    procedure, private :: fv3_nodes_to_atlas_nodes_i
    procedure, private :: fv3_nodes_to_atlas_nodes_r

end type fv3jedi_geom

! --------------------------------------------------------------------------------------------------

contains

! --------------------------------------------------------------------------------------------------

subroutine initialize(conf, comm)

type(fckit_configuration), intent(in) :: conf
type(fckit_mpi_comm),      intent(in) :: comm

integer :: stackmax
character(len=1024) :: nml_filename, field_table_filename
character(len=:), allocatable :: str

! Path for input.nml file
call conf%get_or_die("namelist filename",str)
if (len(str) > 1024) call abor1_ftn("Length of fms namelist filename too long")
nml_filename = str
deallocate(str)

! Field table file
call conf%get_or_die("field table filename",str)
if (len(str) > fm_string_len) call abor1_ftn("Length of fms field table filename too long")
field_table_filename = str
deallocate(str)

! Initialize fms, mpp, etc.
call fms_init(localcomm=comm%communicator(), alt_input_nml_path = nml_filename)

! Set max stacksize
call conf%get_or_die("stackmax", stackmax)
call mpp_domains_set_stack_size(stackmax)

! Initialize the tracers
call field_manager_init(table_name = field_table_filename)

end subroutine initialize

! --------------------------------------------------------------------------------------------------

subroutine create(self, conf, comm, npx, npy, npz)

!Arguments
class(fv3jedi_geom), target, intent(inout) :: self
type(fckit_configuration),   intent(in)    :: conf
type(fckit_mpi_comm),        intent(in)    :: comm
integer,                     intent(out)   :: npx
integer,                     intent(out)   :: npy
integer,                     intent(out)   :: npz

!Locals
character(len=256)                    :: file_akbk
type(fv_atmos_type), allocatable      :: Atm(:)
logical, allocatable                  :: grids_on_this_pe(:)
integer                               :: i, j, jj, this_grid, ierr
integer                               :: p_split = 1
integer                               :: ncstat, ncid, akvarid, bkvarid, readdim, dcount
integer, dimension(nf90_max_var_dims) :: dimids, dimlens

character(len=:), allocatable :: str
real(kind=kind_real) :: sf, t_lon, t_lat
logical :: do_write_geom = .false.
integer :: iterator_dimension = 2

integer :: rowSize, colSize
integer :: myRowRank, myColRank
integer :: mpicomm, wrank, wsize

type(fv3jedi_fmsnamelist) :: fmsnamelist

! Add the communicator to the geometry
! ------------------------------------
self%f_comm = comm

! Initialize comms
! ----------------
self%rowComm = MPI_COMM_NULL
self%colComm = MPI_COMM_NULL

! Initialize field_masks config
! -----------------------------
self%field_masks = fckit_configuration()

! User specified interpolation methods for fields
! -----------------------------------------------
self%field_interp_methods = fckit_configuration()
if (conf%has("field interpolation methods")) then
  call conf%get_or_die("field interpolation methods", self%field_interp_methods)
endif

! Stretch factor, target_lon, and target_lat
! ------------------------------------------
sf = 0
t_lon = 0.0
t_lat = 0.0
if (conf%has("stretch_fac")) call conf%get_or_die("stretch_fac",sf)
if (conf%has("target_lon"))  call conf%get_or_die("target_lon",t_lon)
if (conf%has("target_lat"))  call conf%get_or_die("target_lat",t_lat)
self%stretch_fac = sf
self%target_lon = t_lon
self%target_lat = t_lat

iterator_dimension = 2
if (conf%has("iterator dimension")) call conf%get_or_die("iterator dimension", iterator_dimension)
self%iterator_dimension = iterator_dimension

! Update the fms namelist with this Geometry
! ------------------------------------------
call fmsnamelist%replace_namelist(conf)

!Intialize using the model setup routine
! --------------------------------------
call fv_control_init(Atm, 300.0_kind_real, this_grid, grids_on_this_pe, p_split, &
                     skip_nml_read_in=.true.)

! Sanity check
if (this_grid .ne. 1) call abor1_ftn("Geometry not ready for ngrid > 1")

! Copy relevant contents of Atm
! -----------------------------
self%isd = Atm(1)%bd%isd
self%ied = Atm(1)%bd%ied
self%jsd = Atm(1)%bd%jsd
self%jed = Atm(1)%bd%jed

self%isc = Atm(1)%bd%isc
self%iec = Atm(1)%bd%iec
self%jsc = Atm(1)%bd%jsc
self%jec = Atm(1)%bd%jec
self%kec = Atm(1)%npz

self%ntile  = Atm(1)%global_tile
self%ntiles = Atm(1)%flagstruct%ntiles

self%npx = Atm(1)%npx
self%npy = Atm(1)%npy
self%npz = Atm(1)%npz

npx = self%npx
npy = self%npy
npz = self%npz

self%layout(1) = Atm(1)%layout(1)
self%layout(2) = Atm(1)%layout(2)
self%io_layout(1) = Atm(1)%io_layout(1)
self%io_layout(2) = Atm(1)%io_layout(2)

!Allocatable arrays
allocate(self%ak(self%npz+1) )
allocate(self%bk(self%npz+1) )

allocate(self%grid_lon   (self%isd  :self%ied,  self%jsd  :self%jed  ))
allocate(self%grid_lat   (self%isd  :self%ied,  self%jsd  :self%jed  ))
allocate(self%egrid_lon  (self%isd  :self%ied+1,self%jsd  :self%jed+1))
allocate(self%egrid_lat  (self%isd  :self%ied+1,self%jsd  :self%jed+1))
allocate(self%area       (self%isd  :self%ied,  self%jsd  :self%jed  ))
allocate(self%dx         (self%isd  :self%ied  ,self%jsd  :self%jed+1))
allocate(self%dy         (self%isd  :self%ied+1,self%jsd  :self%jed  ))
allocate(self%dxc        (self%isd  :self%ied+1,self%jsd  :self%jed  ))
allocate(self%dyc        (self%isd  :self%ied  ,self%jsd  :self%jed+1))

allocate(self%grid       (self%isd  :self%ied+1,self%jsd  :self%jed+1,2))
allocate(self%vlon       (self%isc-2:self%iec+2,self%jsc-2:self%jec+2,3))
allocate(self%vlat       (self%isc-2:self%iec+2,self%jsc-2:self%jec+2,3))

allocate(self%edge_vect_n(self%isd:self%ied))
allocate(self%edge_vect_e(self%jsd:self%jed))
allocate(self%edge_vect_s(self%isd:self%ied))
allocate(self%edge_vect_w(self%jsd:self%jed))

allocate(self%es(3,self%isd:self%ied  ,self%jsd:self%jed+1,2))
allocate(self%ew(3,self%isd:self%ied+1,self%jsd:self%jed,  2))

allocate(self%a11(self%isc-1:self%iec+1,self%jsc-1:self%jec+1) )
allocate(self%a12(self%isc-1:self%iec+1,self%jsc-1:self%jec+1) )
allocate(self%a21(self%isc-1:self%iec+1,self%jsc-1:self%jec+1) )
allocate(self%a22(self%isc-1:self%iec+1,self%jsc-1:self%jec+1) )

allocate(self%rarea (self%isd:self%ied  ,self%jsd:self%jed  ))
allocate(self%sin_sg(self%isd:self%ied  ,self%jsd:self%jed  ,9))
allocate(self%cosa_u(self%isd:self%ied+1,self%jsd:self%jed  ))
allocate(self%cosa_v(self%isd:self%ied  ,self%jsd:self%jed+1))
allocate(self%cosa_s(self%isd:self%ied  ,self%jsd:self%jed  ))
allocate(self%rsin_u(self%isd:self%ied+1,self%jsd:self%jed  ))
allocate(self%rsin_v(self%isd:self%ied  ,self%jsd:self%jed+1))
allocate(self%rsin2 (self%isd:self%ied  ,self%jsd:self%jed  ))
allocate(self%dxa   (self%isd:self%ied  ,self%jsd:self%jed  ))
allocate(self%dya   (self%isd:self%ied  ,self%jsd:self%jed  ))

! For reading regional restart files with paralell I/O
! Build helper communicators describing the 2D PE layout and each rank's subdomain
! ----------------------------------------
mpicomm = self%f_comm%communicator()
call MPI_Comm_rank(mpicomm, wrank, ierr)
call MPI_Comm_size(mpicomm, wsize, ierr)

self%EWindex = modulo(wrank,self%layout(1))
self%NSindex = (wrank/self%layout(1))

call MPI_Comm_split(mpicomm, self%NSindex, wrank, self%rowComm, ierr)
if (ierr /= MPI_SUCCESS) call mpp_error(FATAL, "MPI_Comm_split rowComm failed")
self%rowComm_created = .true.

call MPI_Comm_split(mpicomm, self%EWindex, wrank, self%colComm, ierr)
if (ierr /= MPI_SUCCESS) call mpp_error(FATAL, "MPI_Comm_split colComm failed")
self%colComm_created = .true.

call MPI_Comm_size(self%rowComm, rowSize, ierr)
call MPI_Comm_size(self%colComm, colSize, ierr)

! Allocate based on actual comm sizes
allocate(self%ibegin(0:rowSize-1), self%iend(0:rowSize-1))
allocate(self%jbegin(0:colSize-1), self%jend(0:colSize-1))

call MPI_AllGather(self%isc,1,MPI_Integer,self%ibegin(0:),1,MPI_Integer, self%rowComm, ierr)
call MPI_AllGather(self%iec,1,MPI_Integer,self%iend(0:)  ,1,MPI_Integer, self%rowComm, ierr)
call MPI_AllGather(self%jsc,1,MPI_Integer,self%jbegin(0:),1,MPI_Integer, self%colComm, ierr)
call MPI_AllGather(self%jec,1,MPI_Integer,self%jend(0:)  ,1,MPI_Integer, self%colComm, ierr)

! Let other ranks know my row and column index
allocate(self%MyRowGlobal(0:wsize-1), self%MyColGlobal(0:wsize-1))
self%MyRowGlobal=-999; self%MyColGlobal=-999
call MPI_AllGather(self%NSindex,1,MPI_Integer,self%MyRowGlobal,1,MPI_Integer, mpicomm, ierr)
call MPI_AllGather(self%EWindex,1,MPI_Integer,self%MyColGlobal,1,MPI_Integer, mpicomm, ierr)

! Let other ranks know my rank in the row and column communicators
call MPI_Comm_rank(self%rowComm, self%rowrank, ierr)
call MPI_Comm_rank(self%colComm, self%colrank, ierr)
allocate(self%MyRankInRowComm(0:wsize-1), self%MyRankInColComm(0:wsize-1))
self%MyRankInRowComm=-999; self%MyRankInColComm=-999
call MPI_AllGather(self%rowrank,1,MPI_Integer,self%MyRankInRowComm,1,MPI_Integer, mpicomm, ierr)
call MPI_AllGather(self%colrank,1,MPI_Integer,self%MyRankInColComm,1,MPI_Integer, mpicomm, ierr)

! dimensions of my subdomain
call MPI_Comm_rank(self%rowComm, myRowRank, ierr)  ! 0..rowSize-1
call MPI_Comm_rank(self%colComm, myColRank, ierr)  ! 0..colSize-1
self%localsizes(1) = self%iend(myRowRank) - self%ibegin(myRowRank) + 1
self%localsizes(2) = self%jend(myColRank) - self%jbegin(myColRank) + 1

! Let other ranks in my row and column know how many rows and columns I have in my subdomain
allocate(self%NumColsPerRank(0:rowSize-1))
allocate(self%NumRowsPerRank(0:colSize-1))
self%NumColsPerRank=-999; self%NumRowsPerRank=-999
call MPI_Allgather(self%localsizes(1), 1, MPI_Integer, self%NumColsPerRank, 1, MPI_Integer, self%rowComm, ierr)
call MPI_Allgather(self%localsizes(2), 1, MPI_Integer, self%NumRowsPerRank, 1, MPI_Integer, self%colComm, ierr)

! Horizontal dimensions of ensemble input files
self%globalsizes(1) = self%npx-1
self%globalsizes(2) = self%npy-1

! ak and bk hybrid coordinate coefficients
! ----------------------------------------
if (self%npz > 1) then

  ! Set path/filename for ak and bk file
  call conf%get_or_die("akbk",str)
  file_akbk = str

  !Open file
  call nccheck ( nf90_open(file_akbk, nf90_nowrite, ncid), "nf90_open "//file_akbk )

  !Search for ak in the file
  ncstat = nf90_inq_varid(ncid, "ak", akvarid)
  if(ncstat /= nf90_noerr) call abor1_ftn("Failed to find ak in file "//file_akbk)

  !Search for bk in the file
  ncstat = nf90_inq_varid(ncid, "bk", bkvarid)
  if(ncstat /= nf90_noerr) call abor1_ftn("Failed to find bk in file "//file_akbk)

  ! Check that dimension of ak/bk in the file match vertical levels of model
  dimids = 0
  call nccheck ( nf90_inquire_variable(ncid, akvarid, dimids = dimids), "nf90_inq_var ak" )
  readdim = -1
  dcount = 0
  do i = 1,nf90_max_var_dims
    if (dimids(i) > 0) then
       call nccheck( nf90_inquire_dimension(ncid, dimids(i), len = dimlens(i)), &
                     "nf90_inquire_dimension" )
       if (dimlens(i) == self%npz+1) then
          readdim = i
       endif
       dcount = dcount + 1
    endif
  enddo
  if (readdim == -1) call abor1_ftn("ak/bk in file does not match dimension of npz from input.nml")

  !Read ak and bk from the file
  call nccheck( nf90_get_var(ncid, akvarid, self%ak), "fv3jedi_geom, nf90_get_var ak" )
  call nccheck( nf90_get_var(ncid, bkvarid, self%bk), "fv3jedi_geom, nf90_get_var bk" )
else
  self%ak = 0.0_kind_real
  self%bk = 0.0_kind_real
endif

! Arrays from the Atm Structure
! -----------------------------
self%grid_lon  = real(Atm(1)%gridstruct%agrid_64(:,:,1),kind_real)
self%grid_lat  = real(Atm(1)%gridstruct%agrid_64(:,:,2),kind_real)
self%egrid_lon = real(Atm(1)%gridstruct%grid_64(:,:,1),kind_real)
self%egrid_lat = real(Atm(1)%gridstruct%grid_64(:,:,2),kind_real)
self%area      = real(Atm(1)%gridstruct%area_64,kind_real)
self%dx        = real(Atm(1)%gridstruct%dx ,kind_real)
self%dy        = real(Atm(1)%gridstruct%dy ,kind_real)
self%dxc       = real(Atm(1)%gridstruct%dxc,kind_real)
self%dyc       = real(Atm(1)%gridstruct%dyc,kind_real)

self%grid      = real(Atm(1)%gridstruct%grid,kind_real)
self%vlon      = real(Atm(1)%gridstruct%vlon,kind_real)
self%vlat      = real(Atm(1)%gridstruct%vlat,kind_real)

self%edge_vect_n = real(Atm(1)%gridstruct%edge_vect_n,kind_real)
self%edge_vect_e = real(Atm(1)%gridstruct%edge_vect_e,kind_real)
self%edge_vect_s = real(Atm(1)%gridstruct%edge_vect_s,kind_real)
self%edge_vect_w = real(Atm(1)%gridstruct%edge_vect_w,kind_real)

self%es = real(Atm(1)%gridstruct%es,kind_real)
self%ew = real(Atm(1)%gridstruct%ew,kind_real)

self%a11 = real(Atm(1)%gridstruct%a11,kind_real)
self%a12 = real(Atm(1)%gridstruct%a12,kind_real)
self%a21 = real(Atm(1)%gridstruct%a21,kind_real)
self%a22 = real(Atm(1)%gridstruct%a22,kind_real)

self%rarea     = real(Atm(1)%gridstruct%rarea ,kind_real)
self%sin_sg    = real(Atm(1)%gridstruct%sin_sg,kind_real)
self%cosa_u    = real(Atm(1)%gridstruct%cosa_u,kind_real)
self%cosa_v    = real(Atm(1)%gridstruct%cosa_v,kind_real)
self%cosa_s    = real(Atm(1)%gridstruct%cosa_s,kind_real)
self%rsin_u    = real(Atm(1)%gridstruct%rsin_u,kind_real)
self%rsin_v    = real(Atm(1)%gridstruct%rsin_v,kind_real)
self%rsin2     = real(Atm(1)%gridstruct%rsin2 ,kind_real)
self%dxa       = real(Atm(1)%gridstruct%dxa   ,kind_real)
self%dya       = real(Atm(1)%gridstruct%dya   ,kind_real)
self%ne_corner = Atm(1)%gridstruct%ne_corner
self%se_corner = Atm(1)%gridstruct%se_corner
self%sw_corner = Atm(1)%gridstruct%sw_corner
self%nw_corner = Atm(1)%gridstruct%nw_corner
self%nested    = Atm(1)%gridstruct%nested
self%bounded_domain =  Atm(1)%gridstruct%bounded_domain

allocate(self%vCoord(self%npz))

self%vertcoord_type = 'sigma'
if (conf%has("vert coordinate")) then
  call conf%get_or_die("vert coordinate", str)
  self%vertcoord_type = str
  deallocate(str)
endif

!Unstructured lat/lon
self%ngrid = (self%iec-self%isc+1)*(self%jec-self%jsc+1)
allocate(self%lat_us(self%ngrid))
allocate(self%lon_us(self%ngrid))

jj = 0
do j = self%jsc,self%jec
  do i = self%isc,self%iec
     jj = jj + 1
     self%lat_us(jj) = self%grid_lat(i,j)
     self%lon_us(jj) = self%grid_lon(i,j)
  enddo
enddo

!Set Ptop
self%ptop = self%ak(1)

!Done with the Atm stucture here
call deallocate_fv_atmos_type(Atm(1))
deallocate(Atm)
deallocate(grids_on_this_pe)

!Resetup domain to avoid risk of copied pointers
call setup_domain( self%domain_fix, self%npx-1, self%npy-1, &
                   self%ntiles, self%layout, self%io_layout, 3)

self%domain => self%domain_fix

! Optionally write the geometry to file
! -------------------------------------
do_write_geom = .false.
if (conf%has("write geom")) call conf%get_or_die("write geom",do_write_geom)

if (do_write_geom) then
  call write_geom(self)
endif

! Revert the fms namelist
! -----------------------
call fmsnamelist%revert_namelist

end subroutine create

! --------------------------------------------------------------------------------------------------

subroutine clone(self, other, fmd)

class(fv3jedi_geom),        intent(inout) :: self
type(fv3jedi_geom), target, intent(in)    :: other
type(fields_metadata),      intent(in)    :: fmd

integer :: ierr
integer :: rowSize, colSize

allocate(self%ak(other%npz+1) )
allocate(self%bk(other%npz+1) )

allocate(self%grid_lon   (other%isd  :other%ied,  other%jsd  :other%jed  ))
allocate(self%grid_lat   (other%isd  :other%ied,  other%jsd  :other%jed  ))
allocate(self%egrid_lon  (other%isd  :other%ied+1,other%jsd  :other%jed+1))
allocate(self%egrid_lat  (other%isd  :other%ied+1,other%jsd  :other%jed+1))
allocate(self%area       (other%isd  :other%ied,  other%jsd  :other%jed  ))
allocate(self%dx         (other%isd  :other%ied  ,other%jsd  :other%jed+1))
allocate(self%dy         (other%isd  :other%ied+1,other%jsd  :other%jed  ))
allocate(self%dxc        (other%isd  :other%ied+1,other%jsd  :other%jed  ))
allocate(self%dyc        (other%isd  :other%ied  ,other%jsd  :other%jed+1))

allocate(self%grid       (other%isd  :other%ied+1,other%jsd  :other%jed+1,2))
allocate(self%vlon       (other%isc-2:other%iec+2,other%jsc-2:other%jec+2,3))
allocate(self%vlat       (other%isc-2:other%iec+2,other%jsc-2:other%jec+2,3))

allocate(self%edge_vect_n(other%isd:other%ied))
allocate(self%edge_vect_e(other%jsd:other%jed))
allocate(self%edge_vect_s(other%isd:other%ied))
allocate(self%edge_vect_w(other%jsd:other%jed))

allocate(self%es(3,other%isd:other%ied  ,other%jsd:other%jed+1,2))
allocate(self%ew(3,other%isd:other%ied+1,other%jsd:other%jed,  2))

allocate(self%a11(other%isc-1:other%iec+1,other%jsc-1:other%jec+1) )
allocate(self%a12(other%isc-1:other%iec+1,other%jsc-1:other%jec+1) )
allocate(self%a21(other%isc-1:other%iec+1,other%jsc-1:other%jec+1) )
allocate(self%a22(other%isc-1:other%iec+1,other%jsc-1:other%jec+1) )

allocate(self%rarea (other%isd:other%ied  ,other%jsd:other%jed  ))
allocate(self%sin_sg(other%isd:other%ied  ,other%jsd:other%jed  ,9))
allocate(self%cosa_u(other%isd:other%ied+1,other%jsd:other%jed  ))
allocate(self%cosa_v(other%isd:other%ied  ,other%jsd:other%jed+1))
allocate(self%cosa_s(other%isd:other%ied  ,other%jsd:other%jed  ))
allocate(self%rsin_u(other%isd:other%ied+1,other%jsd:other%jed  ))
allocate(self%rsin_v(other%isd:other%ied  ,other%jsd:other%jed+1))
allocate(self%rsin2 (other%isd:other%ied  ,other%jsd:other%jed  ))
allocate(self%dxa   (other%isd:other%ied  ,other%jsd:other%jed  ))
allocate(self%dya   (other%isd:other%ied  ,other%jsd:other%jed  ))

allocate(self%lat_us(other%ngrid))
allocate(self%lon_us(other%ngrid))

self%npx             = other%npx
self%npy             = other%npy
self%npz             = other%npz
self%ngrid           = other%ngrid
self%layout          = other%layout
self%io_layout       = other%io_layout
self%isc             = other%isc
self%isd             = other%isd
self%iec             = other%iec
self%ied             = other%ied
self%jsc             = other%jsc
self%jsd             = other%jsd
self%jec             = other%jec
self%jed             = other%jed
self%ntile           = other%ntile
self%ntiles          = other%ntiles
self%iterator_dimension = other%iterator_dimension

self%ptop            = other%ptop
self%ak              = other%ak
self%bk              = other%bk
self%grid_lon        = other%grid_lon
self%grid_lat        = other%grid_lat
self%egrid_lon       = other%egrid_lon
self%egrid_lat       = other%egrid_lat
self%area            = other%area
self%dx              = other%dx
self%dy              = other%dy
self%dxc             = other%dxc
self%dyc             = other%dyc
self%grid            = other%grid
self%vlon            = other%vlon
self%vlat            = other%vlat
self%edge_vect_n     = other%edge_vect_n
self%edge_vect_e     = other%edge_vect_e
self%edge_vect_s     = other%edge_vect_s
self%edge_vect_w     = other%edge_vect_w
self%es              = other%es
self%ew              = other%ew
self%a11             = other%a11
self%a12             = other%a12
self%a21             = other%a21
self%a22             = other%a22
self%f_comm          = other%f_comm
self%stretch_fac     = other%stretch_fac
self%target_lon      = other%target_lon
self%target_lat      = other%target_lat

self%rarea     = other%rarea
self%sin_sg    = other%sin_sg
self%cosa_u    = other%cosa_u
self%cosa_v    = other%cosa_v
self%cosa_s    = other%cosa_s
self%rsin_u    = other%rsin_u
self%rsin_v    = other%rsin_v
self%rsin2     = other%rsin2
self%dxa       = other%dxa
self%dya       = other%dya
self%ne_corner = other%ne_corner
self%se_corner = other%se_corner
self%sw_corner = other%sw_corner
self%nw_corner = other%nw_corner

self%domain => other%domain

self%afunctionspace = atlas_functionspace(other%afunctionspace%c_ptr())

self%geometry_fields = atlas_fieldset(other%geometry_fields%c_ptr())

self%fmd = fmd

self%lat_us = other%lat_us
self%lon_us = other%lon_us

self%nested = other%nested
self%bounded_domain = other%bounded_domain

self%vertcoord_type = other%vertcoord_type

self%field_masks = other%field_masks

self%field_interp_methods = other%field_interp_methods

self%EWindex = other%EWindex
self%NSindex = other%NSindex
call MPI_Comm_dup(other%colComm, self%colComm, ierr)
self%colComm_created = .true.
call MPI_Comm_dup(other%rowComm, self%rowComm, ierr)
self%rowComm_created = .true.
self%rowrank = other%rowrank
self%colrank = other%colrank
self%globalsizes = other%globalsizes
self%localsizes = other%localsizes

call MPI_Comm_size(self%rowComm, rowSize, ierr)
call MPI_Comm_size(self%colComm, colSize, ierr)

! Allocate based on actual comm sizes
allocate(self%ibegin(0:rowSize-1), self%iend(0:rowSize-1))
allocate(self%jbegin(0:colSize-1), self%jend(0:colSize-1))
self%ibegin = other%ibegin
self%iend   = other%iend
self%jbegin = other%jbegin
self%jend   = other%jend

allocate(self%MyRowGlobal(0:mpp_npes()-1), self%MyColGlobal(0:mpp_npes()-1))
self%MyRowGlobal = other%MyRowGlobal
self%MyColGlobal = other%MyColGlobal

allocate(self%MyRankInRowComm(0:mpp_npes()-1), self%MyRankInColComm(0:mpp_npes()-1))
self%MyRankInRowComm = other%MyRankInRowComm
self%MyRankInColComm = other%MyRankInColComm

allocate(self%NumColsPerRank(0:rowSize-1), self%NumRowsPerRank(0:colSize-1))
self%NumColsPerRank = other%NumColsPerRank
self%NumRowsPerRank = other%NumRowsPerRank

end subroutine clone

! --------------------------------------------------------------------------------------------------

subroutine delete(self)

class(fv3jedi_geom), intent(inout) :: self
logical :: inited, finalized
integer :: ierr,r

! Deallocate
deallocate(self%ak)
deallocate(self%bk)
deallocate(self%grid_lon)
deallocate(self%grid_lat)
deallocate(self%egrid_lon)
deallocate(self%egrid_lat)
deallocate(self%area)
deallocate(self%dx)
deallocate(self%dy)
deallocate(self%dxc)
deallocate(self%dyc)
deallocate(self%grid)
deallocate(self%vlon)
deallocate(self%vlat)
deallocate(self%edge_vect_n)
deallocate(self%edge_vect_e)
deallocate(self%edge_vect_s)
deallocate(self%edge_vect_w)
deallocate(self%es)
deallocate(self%ew)
deallocate(self%a11)
deallocate(self%a12)
deallocate(self%a21)
deallocate(self%a22)

deallocate(self%rarea)
deallocate(self%sin_sg)
deallocate(self%cosa_u)
deallocate(self%cosa_v)
deallocate(self%cosa_s)
deallocate(self%rsin_u)
deallocate(self%rsin_v)
deallocate(self%rsin2 )
deallocate(self%dxa   )
deallocate(self%dya   )

deallocate(self%lat_us)
deallocate(self%lon_us)

! Required memory leak, since copying this causes problems
!call mpp_deallocate_domain(self%domain_fix)

call self%afunctionspace%final()
call self%geometry_fields%final()

call MPI_Initialized(inited, ierr)
call MPI_Finalized(finalized, ierr)

if (inited .and. .not. finalized) then
  if (self%rowComm_created .and. self%rowComm /= MPI_COMM_NULL) then
    call MPI_Comm_free(self%rowComm, ierr)
    self%rowComm = MPI_COMM_NULL
    self%rowComm_created = .false.
  endif
  if (self%colComm_created .and. self%colComm /= MPI_COMM_NULL) then
    call MPI_Comm_free(self%colComm, ierr)
    self%colComm = MPI_COMM_NULL
    self%colComm_created = .false.
  endif
endif

deallocate(self%ibegin)
deallocate(self%iend)
deallocate(self%jbegin)
deallocate(self%jend)
deallocate(self%MyRankInRowComm)
deallocate(self%MyRankInColComm)
deallocate(self%NumColsPerRank)
deallocate(self%NumRowsPerRank)
deallocate(self%MyRowGlobal)
deallocate(self%MyColGlobal)

end subroutine delete

! --------------------------------------------------------------------------------------------------

subroutine is_equal(self, other, equal)

class(fv3jedi_geom), intent(in) :: self
class(fv3jedi_geom), intent(in) :: other
logical, intent(out) :: equal

equal = .false.

! At the moment, equality is based on the fundamental integer-type members; could make more
! rigorous by comparing more data
if (self%npx == other%npx .and. self%npy == other%npy .and. self%npz == other%npz &
    .and. self%ntile == other%ntile .and. self%ntiles == other%ntiles &
    .and. self%isc == other%isc .and. self%iec == other%iec &
    .and. self%jsc == other%jsc .and. self%jec == other%jec &
    .and. self%kec == other%kec &
    .and. self%layout(1) == other%layout(1) .and. self%layout(2) == other%layout(2) &
    .and. self%layout(1) == other%layout(1) .and. self%layout(2) == other%layout(2) &
    .and. self%stretch_fac == other%stretch_fac &
    .and. self%target_lon == other%target_lon &
    .and. self%target_lat == other%target_lat) then
  equal = .true.
end if

end subroutine is_equal

! --------------------------------------------------------------------------------------------------

subroutine set_and_fill_geometry_fields(self, afieldset, field_masks)

!Arguments
class(fv3jedi_geom),       intent(inout) :: self
type(atlas_fieldset),      intent(inout) :: afieldset
type(fckit_configuration), intent(in)    :: field_masks

!Locals
type(atlas_field) :: afield, afield2
integer :: jl
integer, pointer :: int_ptr(:,:)
real(kind=kind_real), pointer :: real_ptr(:,:), real_ptr2(:,:)
real(kind=kind_real) :: sigmaup, sigmadn, ps
real(kind=kind_real) :: logp(self%npz)

! Assign geometry_fields variable
self%geometry_fields = afieldset

! Save the config containing choice of field masks
self%field_masks = field_masks

! Add owned vs halo/BC field
afield = self%afunctionspace%create_field(name='owned', kind=atlas_integer(kind_int), levels=1)
call afield%data(int_ptr)
int_ptr(1, :) = 0
int_ptr(1, 1:self%ngrid) = 1
call afieldset%add(afield)

! Add area
afield = self%afunctionspace%create_field(name='area', kind=atlas_real(kind_real), levels=1)
call afield%data(real_ptr)
real_ptr(1, :) = -1.0_kind_real
real_ptr(1, 1:self%ngrid) = reshape(self%area(self%isc:self%iec, self%jsc:self%jec), (/self%ngrid/))
call afieldset%add(afield)

! Add vertical unit
ps = constant('ps')
if (trim(self%vertcoord_type) == 'sigma') then
   afield = self%afunctionspace%create_field(name='vert_coord', kind=atlas_real(kind_real), levels=self%npz)
   call afield%data(real_ptr)
   do jl=1,self%npz
      sigmaup = self%ak(jl+1)/ps+self%bk(jl+1) ! si are now sigmas
      sigmadn = self%ak(jl  )/ps+self%bk(jl  )
      real_ptr(jl,:) = 0.5*(sigmaup+sigmadn) ! 'fake' sigma coordinates
   enddo
else if (trim(self%vertcoord_type) == 'logp') then
   afield = self%afunctionspace%create_field(name='vert_coord', kind=atlas_real(kind_real), levels=self%npz)
   call afield%data(real_ptr)
   call getVerticalCoordLogP(self,logp,self%npz,ps)
   do jl=1,self%npz
      real_ptr(jl,:) = logp(jl)
   enddo
else if (trim(self%vertcoord_type) == 'orography') then
   !> The orography vertical coordinate can only be used for 2D fields, so allocation here is
   !> for one level. This option is not compatible with 3D fields.
   afield = self%afunctionspace%create_field(name='vert_coord', kind=atlas_real(kind_real), levels=1)
   call afield%data(real_ptr)
   afield2 = afieldset%field('filtered_orography')
   call afield2%data(real_ptr2)
   real_ptr(1,:) = real_ptr2(1,:)
else
   call abor1_ftn('fv3jedi_geom_mod%set_and_fill_geometry_fields: unknown vertical coordinate type')
endif
call afieldset%add(afield)
call afield%final()
call afield2%final()

end subroutine set_and_fill_geometry_fields

! --------------------------------------------------------------------------------------------------

subroutine setup_domain(domain, nx, ny, ntiles, layout_in, io_layout, halo)

 type(domain2D),   intent(inout) :: domain
 integer,          intent(in)    :: nx, ny, ntiles
 integer,          intent(in)    :: layout_in(:), io_layout(:)
 integer,          intent(in)    :: halo

 integer                              :: pe, npes, npes_per_tile, tile
 integer                              :: num_contact, num_alloc
 integer                              :: n, layout(2)
 integer, allocatable, dimension(:,:) :: global_indices, layout2D
 integer, allocatable, dimension(:)   :: pe_start, pe_end
 integer, allocatable, dimension(:)   :: tile1, tile2
 integer, allocatable, dimension(:)   :: istart1, iend1, jstart1, jend1
 integer, allocatable, dimension(:)   :: istart2, iend2, jstart2, jend2
 integer, allocatable :: tile_id(:), ensNum
 logical :: is_symmetry

  pe = mpp_pe()
  npes = mpp_npes()
  ensNum = get_ensemble_id()

  if (mod(npes,ntiles) /= 0) then
     call mpp_error(NOTE, "setup_domain: npes can not be divided by ntiles")
     return
  endif
  npes_per_tile = npes/ntiles
  tile = pe/npes_per_tile + 1

  if (layout_in(1)*layout_in(2) == npes_per_tile) then
     layout = layout_in
  else
     call mpp_define_layout( (/1,nx,1,ny/), npes_per_tile, layout )
  endif

  if (io_layout(1) <1 .or. io_layout(2) <1) call mpp_error(FATAL, &
          "setup_domain: both elements of variable io_layout must be positive integer")
  if (mod(layout(1), io_layout(1)) /= 0 ) call mpp_error(FATAL, &
       "setup_domain: layout(1) must be divided by io_layout(1)")
  if (mod(layout(2), io_layout(2)) /= 0 ) call mpp_error(FATAL, &
       "setup_domain: layout(2) must be divided by io_layout(2)")

  allocate(global_indices(4,ntiles), layout2D(2,ntiles), pe_start(ntiles), pe_end(ntiles) )

  ! select case based off of 1 or 6 tiles
  select case(ntiles)
  case ( 1 ) ! FV3-SAR
    num_contact = 0
  case ( 6 ) ! FV3 global
    num_contact = 12
  case default
    call mpp_error(FATAL, "setup_domain: ntiles != 1 or 6")
  end select

  do n = 1, ntiles
     global_indices(:,n) = (/1,nx,1,ny/)
     layout2D(:,n)       = layout
     pe_start(n)         = (n-1)*npes_per_tile + (ensNum -1) * 6 * npes_per_tile
     pe_end(n)           = n*npes_per_tile-1 + (ensNum -1) * 6 * npes_per_tile
  enddo

  num_alloc = max(1, num_contact)
  ! this code copied from domain_decomp in fv_mp_mod.f90
  allocate(tile1(num_alloc), tile2(num_alloc) )
  allocate(tile_id(ntiles))
  allocate(istart1(num_alloc), iend1(num_alloc), jstart1(num_alloc), jend1(num_alloc) )
  allocate(istart2(num_alloc), iend2(num_alloc), jstart2(num_alloc), jend2(num_alloc) )
  ! select case based off of 1 or 6 tiles
  select case(ntiles)
  case ( 1 ) ! FV3-SAR
    ! No contacts, do nothing
  case ( 6 ) ! FV3 global
    !--- Contact line 1, between tile 1 (EAST) and tile 2 (WEST)
    tile1(1) = 1; tile2(1) = 2
    istart1(1) = nx; iend1(1) = nx; jstart1(1) = 1;  jend1(1) = ny
    istart2(1) = 1;  iend2(1) = 1;  jstart2(1) = 1;  jend2(1) = ny
    !--- Contact line 2, between tile 1 (NORTH) and tile 3 (WEST)
    tile1(2) = 1; tile2(2) = 3
    istart1(2) = 1;  iend1(2) = nx; jstart1(2) = ny; jend1(2) = ny
    istart2(2) = 1;  iend2(2) = 1;  jstart2(2) = ny; jend2(2) = 1
    !--- Contact line 3, between tile 1 (WEST) and tile 5 (NORTH)
    tile1(3) = 1; tile2(3) = 5
    istart1(3) = 1;  iend1(3) = 1;  jstart1(3) = 1;  jend1(3) = ny
    istart2(3) = nx; iend2(3) = 1;  jstart2(3) = ny; jend2(3) = ny
    !--- Contact line 4, between tile 1 (SOUTH) and tile 6 (NORTH)
    tile1(4) = 1; tile2(4) = 6
    istart1(4) = 1;  iend1(4) = nx; jstart1(4) = 1;  jend1(4) = 1
    istart2(4) = 1;  iend2(4) = nx; jstart2(4) = ny; jend2(4) = ny
    !--- Contact line 5, between tile 2 (NORTH) and tile 3 (SOUTH)
    tile1(5) = 2; tile2(5) = 3
    istart1(5) = 1;  iend1(5) = nx; jstart1(5) = ny; jend1(5) = ny
    istart2(5) = 1;  iend2(5) = nx; jstart2(5) = 1;  jend2(5) = 1
    !--- Contact line 6, between tile 2 (EAST) and tile 4 (SOUTH)
    tile1(6) = 2; tile2(6) = 4
    istart1(6) = nx; iend1(6) = nx; jstart1(6) = 1;  jend1(6) = ny
    istart2(6) = nx; iend2(6) = 1;  jstart2(6) = 1;  jend2(6) = 1
    !--- Contact line 7, between tile 2 (SOUTH) and tile 6 (EAST)
    tile1(7) = 2; tile2(7) = 6
    istart1(7) = 1;  iend1(7) = nx; jstart1(7) = 1;  jend1(7) = 1
    istart2(7) = nx; iend2(7) = nx; jstart2(7) = ny; jend2(7) = 1
    !--- Contact line 8, between tile 3 (EAST) and tile 4 (WEST)
    tile1(8) = 3; tile2(8) = 4
    istart1(8) = nx; iend1(8) = nx; jstart1(8) = 1;  jend1(8) = ny
    istart2(8) = 1;  iend2(8) = 1;  jstart2(8) = 1;  jend2(8) = ny
    !--- Contact line 9, between tile 3 (NORTH) and tile 5 (WEST)
    tile1(9) = 3; tile2(9) = 5
    istart1(9) = 1;  iend1(9) = nx; jstart1(9) = ny; jend1(9) = ny
    istart2(9) = 1;  iend2(9) = 1;  jstart2(9) = ny; jend2(9) = 1
    !--- Contact line 10, between tile 4 (NORTH) and tile 5 (SOUTH)
    tile1(10) = 4; tile2(10) = 5
    istart1(10) = 1;  iend1(10) = nx; jstart1(10) = ny; jend1(10) = ny
    istart2(10) = 1;  iend2(10) = nx; jstart2(10) = 1;  jend2(10) = 1
    !--- Contact line 11, between tile 4 (EAST) and tile 6 (SOUTH)
    tile1(11) = 4; tile2(11) = 6
    istart1(11) = nx; iend1(11) = nx; jstart1(11) = 1;  jend1(11) = ny
    istart2(11) = nx; iend2(11) = 1;  jstart2(11) = 1;  jend2(11) = 1
    !--- Contact line 12, between tile 5 (EAST) and tile 6 (WEST)
    tile1(12) = 5; tile2(12) = 6
    istart1(12) = nx; iend1(12) = nx; jstart1(12) = 1;  jend1(12) = ny
    istart2(12) = 1;  iend2(12) = 1;  jstart2(12) = 1;  jend2(12) = ny
  end select
  is_symmetry = .true.
  do n = 1, ntiles
     tile_id(n) = n
  enddo

  call mpp_define_mosaic(global_indices, layout2D, domain, ntiles, num_contact, tile1, tile2, &
                         istart1, iend1, jstart1, jend1, istart2, iend2, jstart2, jend2,      &
                         pe_start, pe_end, whalo=halo, ehalo=halo, shalo=halo, nhalo=halo,    &
                         symmetry=is_symmetry, tile_id=tile_id, &
                         name='cubic_grid')

  call mpp_define_io_domain(domain, io_layout)

  deallocate(pe_start, pe_end)
  deallocate(layout2D, global_indices)
  deallocate(tile1, tile2, tile_id)
  deallocate(istart1, iend1, jstart1, jend1)
  deallocate(istart2, iend2, jstart2, jend2)

end subroutine setup_domain

! --------------------------------------------------------------------------------------------------

subroutine write_geom(self)

  type(fv3jedi_geom), intent(in) :: self

  type(fckit_mpi_comm) :: f_comm
  character(len=255) :: filename
  integer :: ncid, xf_dimid, yf_dimid, xv_dimid, yv_dimid, ti_dimid, pe_dimid
  integer :: mydims(3,3), ijdims(1), ijdimf(1), tmpij(1)
  integer :: varid(8)


  ! Pointer to fv3jedi geom communicator
  f_comm = self%f_comm

  write(filename,"(A9,I0.4,A4)") 'fv3grid_c', self%npx-1, '.nc4'

  ! Create and open the file for parallel write
  call nccheck( nf90_create( trim(filename), ior(NF90_NETCDF4, NF90_MPIIO), ncid, &
                             comm = f_comm%communicator(), info = MPI_INFO_NULL), "nf90_create" )

  !Dimensions
  call nccheck ( nf90_def_dim(ncid, 'fxdim', self%npx-1   , xf_dimid), "nf90_def_dim fxdim" )
  call nccheck ( nf90_def_dim(ncid, 'fydim', self%npy-1   , yf_dimid), "nf90_def_dim fydim" )
  call nccheck ( nf90_def_dim(ncid, 'vxdim', self%npx     , xv_dimid), "nf90_def_dim vxdim" )
  call nccheck ( nf90_def_dim(ncid, 'vydim', self%npy     , yv_dimid), "nf90_def_dim vydim" )
  call nccheck ( nf90_def_dim(ncid, 'ntile', 6            , ti_dimid), "nf90_def_dim ntile" )
  call nccheck ( nf90_def_dim(ncid, 'nproc', f_comm%size(), pe_dimid), "nf90_def_dim ntile" )

  !Define variables
  call nccheck( nf90_def_var(ncid, "flons", NF90_DOUBLE, (/ xf_dimid, yf_dimid, ti_dimid /), varid(1)), "nf90_def_var flons" )
  call nccheck( nf90_put_att(ncid, varid(1), "long_name", "longitude of faces") )
  call nccheck( nf90_put_att(ncid, varid(1), "units", "degrees_east") )

  call nccheck( nf90_def_var(ncid, "flats", NF90_DOUBLE, (/ xf_dimid, yf_dimid, ti_dimid /), varid(2)), "nf90_def_var flats" )
  call nccheck( nf90_put_att(ncid, varid(2), "long_name", "latitude of faces") )
  call nccheck( nf90_put_att(ncid, varid(2), "units", "degrees_north") )

  call nccheck( nf90_def_var(ncid, "vlons", NF90_DOUBLE, (/ xv_dimid, yv_dimid, ti_dimid /), varid(3)), "nf90_def_var vlons" )
  call nccheck( nf90_put_att(ncid, varid(3), "long_name", "longitude of vertices") )
  call nccheck( nf90_put_att(ncid, varid(3), "units", "degrees_east") )

  call nccheck( nf90_def_var(ncid, "vlats", NF90_DOUBLE, (/ xv_dimid, yv_dimid, ti_dimid /), varid(4)), "nf90_def_var vlats" )
  call nccheck( nf90_put_att(ncid, varid(4), "long_name", "latitude of vertices") )
  call nccheck( nf90_put_att(ncid, varid(4), "units", "degrees_north") )

  call nccheck( nf90_def_var(ncid, "isc", NF90_INT, (/ pe_dimid /), varid(5)), "nf90_def_var isc" )
  call nccheck( nf90_put_att(ncid, varid(5), "long_name", "starting index i direction") )
  call nccheck( nf90_put_att(ncid, varid(5), "units", "1") )

  call nccheck( nf90_def_var(ncid, "iec", NF90_INT, (/ pe_dimid /), varid(6)), "nf90_def_var iec" )
  call nccheck( nf90_put_att(ncid, varid(6), "long_name", "ending index i direction") )
  call nccheck( nf90_put_att(ncid, varid(6), "units", "1") )

  call nccheck( nf90_def_var(ncid, "jsc", NF90_INT, (/ pe_dimid /), varid(7)), "nf90_def_var jsc" )
  call nccheck( nf90_put_att(ncid, varid(7), "long_name", "starting index j direction") )
  call nccheck( nf90_put_att(ncid, varid(7), "units", "1") )

  call nccheck( nf90_def_var(ncid, "jec", NF90_INT, (/ pe_dimid /), varid(8)), "nf90_def_var jec" )
  call nccheck( nf90_put_att(ncid, varid(8), "long_name", "ending index j direction") )
  call nccheck( nf90_put_att(ncid, varid(8), "units", "1") )

  ! End define mode
  call nccheck( nf90_enddef(ncid), "nf90_enddef" )

  ! Write variables
  mydims(1,1) = 1;          mydims(2,1) = self%npx-1
  mydims(1,2) = 1;          mydims(2,2) = self%npy-1
  mydims(1,3) = self%ntile; mydims(2,3) = 1

  call nccheck( nf90_put_var( ncid, varid(1), self%grid_lon(self%isc:self%iec,self%jsc:self%jec), &
                              start = mydims(1,:), count = mydims(2,:) ), "nf90_put_var flons" )

  call nccheck( nf90_put_var( ncid, varid(2), self%grid_lat(self%isc:self%iec,self%jsc:self%jec), &
                              start = mydims(1,:), count = mydims(2,:) ), "nf90_put_var flats" )

  mydims(1,1) = 1;          mydims(2,1) = self%npx
  mydims(1,2) = 1;          mydims(2,2) = self%npy
  mydims(1,3) = self%ntile; mydims(2,3) = 1

  call nccheck( nf90_put_var( ncid, varid(3), self%egrid_lon(self%isc:self%iec+1,self%jsc:self%jec+1), &
                              start = mydims(1,:), count = mydims(2,:) ), "nf90_put_var vlons" )

  call nccheck( nf90_put_var( ncid, varid(4), self%egrid_lat(self%isc:self%iec+1,self%jsc:self%jec+1), &
                              start = mydims(1,:), count = mydims(2,:) ), "nf90_put_var vlats" )

  ijdims(1) = f_comm%rank()+1
  ijdimf(1) = 1

  tmpij = self%isc
  call nccheck( nf90_put_var( ncid, varid(5), tmpij, start = ijdims, count = ijdimf ), "nf90_put_var isc" )

  tmpij = self%iec
  call nccheck( nf90_put_var( ncid, varid(6), tmpij, start = ijdims, count = ijdimf ), "nf90_put_var iec" )

  tmpij = self%jsc
  call nccheck( nf90_put_var( ncid, varid(7), tmpij, start = ijdims, count = ijdimf ), "nf90_put_var jsc" )

  tmpij = self%jec
  call nccheck( nf90_put_var( ncid, varid(8), tmpij, start = ijdims, count = ijdimf ), "nf90_put_var jec" )

  ! Close the file
  call nccheck ( nf90_close(ncid), "nf90_close" )

end subroutine write_geom

!----------------------------------------------------------------------------
! 1d pressure_edge to pressure_mid
!----------------------------------------------------------------------------

subroutine pedges2pmidlayer(npz,ptype,pe1d,kappa,p1d)
 integer,              intent(in)  :: npz       !number of model layers
 character(len=*),     intent(in)  :: ptype     !midlayer pressure definition: 'average' or 'Philips'
 real(kind=kind_real), intent(in)  :: pe1d(npz+1) !pressure edge
 real(kind=kind_real), intent(in)  :: kappa
 real(kind=kind_real), intent(out) :: p1d(npz)    !pressure mid

 real(kind=kind_real) :: kap1, kapr

 kap1 = kappa + 1.0_kind_real
 kapr = 1.0_kind_real/kappa

 select case (ptype)
   case('Philips')
     p1d = ((pe1d(2:npz+1)**kap1 - pe1d(1:npz)**kap1)/&
            (kap1*(pe1d(2:npz+1) - pe1d(1:npz))))**kapr
   case default
     p1d = 0.5*(pe1d(2:npz+1) + pe1d(1:npz))
 end select

end subroutine pedges2pmidlayer

!--------------------------------------------------------------------------------------------------
subroutine getVerticalCoord(self, vc, npz, psurf)
  ! returns log(pressure) at mid level of the vertical column with surface
  ! prsssure of psurf
  ! coded using an example from Jeff Whitaker used in GSI ENKF pacakge

  type(fv3jedi_geom),   intent(in) :: self
  integer,              intent(in) :: npz
  real(kind=kind_real), intent(in) :: psurf
  real(kind=kind_real), intent(out) :: vc(npz)

  real(kind=kind_real) :: plevli(npz+1), p(npz), kappa
  integer :: k

  ! compute interface pressure
  do k=1,npz+1
    plevli(k) = self%ak(k) + self%bk(k)*psurf
  enddo

  ! get kappa
  kappa = constant('kappa')

  ! compute presure at mid level and convert it to logp
  call pedges2pmidlayer(npz,'Philips',plevli,kappa,vc)

end subroutine getVerticalCoord

!--------------------------------------------------------------------------------------------------
subroutine getVerticalCoordLogP(self, vc, npz, psurf)
  ! returns log(pressure) at mid level of the vertical column with surface prsssure of psurf
  ! coded using an example from Jeff Whitaker used in GSI ENKF pacakge

  type(fv3jedi_geom),   intent(in) :: self
  integer,              intent(in) :: npz
  real(kind=kind_real), intent(in) :: psurf
  real(kind=kind_real), intent(out) :: vc(npz)

  real(kind=kind_real) :: p(npz)

  call getVerticalCoord(self, p, npz, psurf)
  vc = - log(p)

end subroutine getVerticalCoordLogP

! --------------------------------------------------------------------------------------------------

subroutine get_data(self, ak, bk, ptop)

!Arguments
class(fv3jedi_geom),  intent(in)  :: self
real(kind=kind_real), intent(out) :: ak(self%npz+1)
real(kind=kind_real), intent(out) :: bk(self%npz+1)
real(kind=kind_real), intent(out) :: ptop

! Set outputs
ak = self%ak
bk = self%bk
ptop = self%ptop

end subroutine get_data

! --------------------------------------------------------------------------------------------------

subroutine get_num_nodes_and_elements(self, num_nodes, num_tris, num_quads)

  class(fv3jedi_geom),  intent(in)  :: self
  integer, intent(out) :: num_nodes
  integer, intent(out) :: num_tris
  integer, intent(out) :: num_quads

  if (self%ntiles == 6) then
    call get_num_nodes_and_elements_global(self, num_nodes, num_tris, num_quads)
  else if (self%ntiles == 1) then
    call get_num_nodes_and_elements_regional(self, num_nodes, num_tris, num_quads)
  else
    call mpp_error(FATAL, "get_num_nodes_and_elements: ntiles != 1 or 6")
  end if

end subroutine get_num_nodes_and_elements

! --------------------------------------------------------------------------------------------------

subroutine get_num_nodes_and_elements_global(self, num_nodes, num_tris, num_quads)

  class(fv3jedi_geom),  intent(in)  :: self
  integer, intent(out) :: num_nodes
  integer, intent(out) :: num_tris
  integer, intent(out) :: num_quads

  integer :: nx, ny
  logical :: lower_left_corner, upper_left_corner, lower_right_corner

  ! extra +1 from adding the ghost nodes on the lower side of each dimension
  nx = self%iec - self%isc + 2
  ny = self%jec - self%jsc + 2

  ! default case
  num_nodes = nx * ny
  num_tris = 0
  num_quads = (nx - 1) * (ny - 1)

  lower_left_corner = (self%isc == 1 .and. self%jsc == 1)
  upper_left_corner = (self%isc == 1 .and. self%jec == self%npy-1)
  lower_right_corner = (self%iec == self%npx-1 .and. self%jsc == 1)

  ! if at lower-left corner of any tile, then lower-left quad is a tri
  if (lower_left_corner) then
    num_nodes = num_nodes - 1
    num_tris = num_tris + 1
    num_quads = num_quads - 1
  end if

  ! if at upper-left corner of tile #3, then add extra tri in upper-left corner
  if (upper_left_corner .and. self%ntile == 3) then
    num_nodes = num_nodes + 1
    num_tris = num_tris + 1
  end if

  ! if at lower-right corner of tile #6, then add extra tri in lower-right corner
  if (lower_right_corner .and. self%ntile == 6) then
    num_nodes = num_nodes + 1
    num_tris = num_tris + 1
  end if

end subroutine get_num_nodes_and_elements_global

! --------------------------------------------------------------------------------------------------

subroutine get_num_nodes_and_elements_regional(self, num_nodes, num_tris, num_quads)

  class(fv3jedi_geom),  intent(in)  :: self
  integer, intent(out) :: num_nodes
  integer, intent(out) :: num_tris
  integer, intent(out) :: num_quads

  integer :: nx, ny
  logical :: right_bdry, upper_bdry

  ! extra +1 from adding the ghost nodes on the lower side of each dimension
  nx = self%iec - self%isc + 2
  ny = self%jec - self%jsc + 2

  right_bdry = (self%iec == self%npx-1)
  upper_bdry = (self%jec == self%npy-1)

  ! if at upper or right edges, need to adjust the nx,ny for a differently-sized rectangle
  if (right_bdry) then
    nx = nx + 1
  end if
  if (upper_bdry) then
    ny = ny + 1
  end if

  num_nodes = nx * ny
  num_tris = 0
  num_quads = (nx - 1) * (ny - 1)

end subroutine get_num_nodes_and_elements_regional

! --------------------------------------------------------------------------------------------------

subroutine get_coords_and_connectivities(self, &
    num_nodes, num_tri_boundary_nodes, num_quad_boundary_nodes, &
    lons, lats, ghosts, global_indices, remote_indices, partition, &
    raw_tri_boundary_nodes, raw_quad_boundary_nodes)

  class(fv3jedi_geom),  intent(in)  :: self
  integer, intent(in) :: num_nodes
  integer, intent(in) :: num_tri_boundary_nodes
  integer, intent(in) :: num_quad_boundary_nodes
  real(kind_real), intent(out) :: lons(num_nodes)
  real(kind_real), intent(out) :: lats(num_nodes)
  integer, intent(out) :: ghosts(num_nodes)
  integer, intent(out) :: global_indices(num_nodes)
  integer, intent(out) :: remote_indices(num_nodes)
  integer, intent(out) :: partition(num_nodes)
  integer, intent(out) :: raw_tri_boundary_nodes(num_tri_boundary_nodes)
  integer, intent(out) :: raw_quad_boundary_nodes(num_quad_boundary_nodes)

  if (self%ntiles == 6) then
    call get_coords_and_connectivities_global(self, &
        num_nodes, num_tri_boundary_nodes, num_quad_boundary_nodes, &
        lons, lats, ghosts, global_indices, remote_indices, partition, &
        raw_tri_boundary_nodes, raw_quad_boundary_nodes)
  else if (self%ntiles == 1) then
    call get_coords_and_connectivities_regional(self, &
        num_nodes, num_tri_boundary_nodes, num_quad_boundary_nodes, &
        lons, lats, ghosts, global_indices, remote_indices, partition, &
        raw_tri_boundary_nodes, raw_quad_boundary_nodes)
  else
    call mpp_error(FATAL, "get_coords_and_connectivities: ntiles != 1 or 6")
  end if

end subroutine get_coords_and_connectivities

! --------------------------------------------------------------------------------------------------

subroutine get_coords_and_connectivities_global(self, &
    num_nodes, num_tri_boundary_nodes, num_quad_boundary_nodes, &
    lons, lats, ghosts, global_indices, remote_indices, partition, &
    raw_tri_boundary_nodes, raw_quad_boundary_nodes)

  use mpp_domains_mod, only: mpp_update_domains

  class(fv3jedi_geom),  intent(in)  :: self
  integer, intent(in) :: num_nodes
  integer, intent(in) :: num_tri_boundary_nodes
  integer, intent(in) :: num_quad_boundary_nodes
  real(kind_real), intent(out) :: lons(num_nodes)
  real(kind_real), intent(out) :: lats(num_nodes)
  integer, intent(out) :: ghosts(num_nodes)
  integer, intent(out) :: global_indices(num_nodes)
  integer, intent(out) :: remote_indices(num_nodes)
  integer, intent(out) :: partition(num_nodes)
  integer, intent(out) :: raw_tri_boundary_nodes(num_tri_boundary_nodes)
  integer, intent(out) :: raw_quad_boundary_nodes(num_quad_boundary_nodes)

  integer :: i, j, node_counter, tri_counter, quad_counter
  logical :: lower_left_corner, upper_left_corner, lower_right_corner

  integer :: loc_ghost(self%isd:self%ied, self%jsd:self%jed)
  integer :: loc_global_index(self%isd:self%ied, self%jsd:self%jed)
  integer :: loc_remote_index(self%isd:self%ied, self%jsd:self%jed)
  integer :: loc_partition(self%isd:self%ied, self%jsd:self%jed)

  lower_left_corner = (self%isc == 1 .and. self%jsc == 1)
  upper_left_corner = (self%isc == 1 .and. self%jec == self%npy-1)
  lower_right_corner = (self%iec == self%npx-1 .and. self%jsc == 1)

  ! local 2d array for ghost, no need to exchange
  loc_ghost = 1
  loc_ghost(self%isc:self%iec, self%jsc:self%jec) = 0

  ! local 2d arrays for global_index, remote_index, and partition for exchanging across tasks
  loc_global_index = -1
  loc_global_index(self%isc:self%iec, self%jsc:self%jec) = (self%npx-1) * (self%npy-1) * (self%ntile-1)
  do j = self%jsc, self%jec
    do i = self%isc, self%iec
      ! 1-based index for global index
      loc_global_index(i,j) = loc_global_index(i,j) + (j - 1) * (self%npx-1) + i
    end do
  end do
  call mpp_update_domains(loc_global_index, self%domain)

  loc_remote_index = -1
  do j = self%jsc, self%jec
    do i = self%isc, self%iec
      ! 1-based index
      loc_remote_index(i,j) = (j - self%jsc) * (self%iec - self%isc + 1) + (i - self%isc) + 1
    end do
  end do
  call mpp_update_domains(loc_remote_index, self%domain)

  loc_partition = -1
  loc_partition(self%isc:self%iec, self%jsc:self%jec) = self%f_comm%rank()
  call mpp_update_domains(loc_partition, self%domain)

  call self%fv3_nodes_to_atlas_nodes(self%grid_lon, lons)
  call self%fv3_nodes_to_atlas_nodes(self%grid_lat, lats)
  call self%fv3_nodes_to_atlas_nodes(loc_ghost, ghosts)
  call self%fv3_nodes_to_atlas_nodes(loc_global_index, global_indices)
  call self%fv3_nodes_to_atlas_nodes(loc_remote_index, remote_indices)
  call self%fv3_nodes_to_atlas_nodes(loc_partition, partition)

  lons = constant('rad2deg') * lons
  lats = constant('rad2deg') * lats

  tri_counter = 1
  quad_counter = 1
  do j = self%jsc-1, self%jec
    do i = self%isc-1, self%iec

      ! if at lower-left corner of any tile, then lower-left quad is a tri => skip a point
      if (lower_left_corner .and. (j == self%jsc-1) .and. (i == self%isc-1)) then
        raw_tri_boundary_nodes(tri_counter)   = loc_global_index(i+1, j)
        raw_tri_boundary_nodes(tri_counter+1) = loc_global_index(i+1, j+1)
        raw_tri_boundary_nodes(tri_counter+2) = loc_global_index(i, j+1)
        tri_counter = tri_counter + 3
        cycle
      end if

      if ((j /= self%jec) .and. (i /= self%iec)) then
        raw_quad_boundary_nodes(quad_counter)   = loc_global_index(i, j)
        raw_quad_boundary_nodes(quad_counter+1) = loc_global_index(i+1, j)
        raw_quad_boundary_nodes(quad_counter+2) = loc_global_index(i+1, j+1)
        raw_quad_boundary_nodes(quad_counter+3) = loc_global_index(i, j+1)
        quad_counter = quad_counter + 4
      end if
    end do
  end do

  ! at upper-left corner of tile #3, then add extra tri => add extra point
  if (upper_left_corner .and. (self%ntile == 3)) then
    raw_tri_boundary_nodes(tri_counter)   = loc_global_index(self%isc-1, self%jec)
    raw_tri_boundary_nodes(tri_counter+1) = loc_global_index(self%isc, self%jec)
    raw_tri_boundary_nodes(tri_counter+2) = loc_global_index(self%isc, self%jec+1)
    tri_counter = tri_counter + 3
  end if

  ! if at lower-right corner of tile #6, then add extra tri => add extra point
  if (lower_right_corner .and. (self%ntile == 6)) then
    raw_tri_boundary_nodes(tri_counter)   = loc_global_index(self%iec, self%jsc-1)
    raw_tri_boundary_nodes(tri_counter+1) = loc_global_index(self%iec+1, self%jsc)
    raw_tri_boundary_nodes(tri_counter+2) = loc_global_index(self%iec, self%jsc)
    tri_counter = tri_counter + 3
  end if

  ! sanity checks: tri_counter-1 == num_tri_boundary_nodes
  if (tri_counter-1 /= num_tri_boundary_nodes) then
    call abor1_ftn('fv3jedi_geom_mod: inconsistent tri counter when getting connectivities')
  end if
  ! quad_counter-1 == num_quad_boundary_nodes
  if (quad_counter-1 /= num_quad_boundary_nodes) then
    call abor1_ftn('fv3jedi_geom_mod: inconsistent quad counter when getting connectivities')
  end if

end subroutine get_coords_and_connectivities_global

! --------------------------------------------------------------------------------------------------

subroutine get_coords_and_connectivities_regional(self, &
    num_nodes, num_tri_boundary_nodes, num_quad_boundary_nodes, &
    lons, lats, ghosts, global_indices, remote_indices, partition, &
    raw_tri_boundary_nodes, raw_quad_boundary_nodes)

  use mpp_domains_mod, only: mpp_update_domains

  class(fv3jedi_geom),  intent(in)  :: self
  integer, intent(in) :: num_nodes
  integer, intent(in) :: num_tri_boundary_nodes
  integer, intent(in) :: num_quad_boundary_nodes
  real(kind_real), intent(out) :: lons(num_nodes)
  real(kind_real), intent(out) :: lats(num_nodes)
  integer, intent(out) :: ghosts(num_nodes)
  integer, intent(out) :: global_indices(num_nodes)
  integer, intent(out) :: remote_indices(num_nodes)
  integer, intent(out) :: partition(num_nodes)
  integer, intent(out) :: raw_tri_boundary_nodes(num_tri_boundary_nodes)
  integer, intent(out) :: raw_quad_boundary_nodes(num_quad_boundary_nodes)

  integer :: i, j, node_counter, quad_counter
  integer :: imax, jmax
  integer :: counter_local_idx
  logical :: left_bdry, right_bdry, lower_bdry, upper_bdry

  logical :: loc_bc(self%isd:self%ied, self%jsd:self%jed)
  integer :: loc_ghost(self%isd:self%ied, self%jsd:self%jed)
  integer :: loc_global_index(self%isd:self%ied, self%jsd:self%jed)
  integer :: loc_remote_index(self%isd:self%ied, self%jsd:self%jed)
  integer :: exchange_remote_index(self%isd:self%ied, self%jsd:self%jed)
  integer :: loc_partition(self%isd:self%ied, self%jsd:self%jed)

  left_bdry = (self%isc == 1)
  right_bdry = (self%iec == self%npx-1)
  lower_bdry = (self%jsc == 1)
  upper_bdry = (self%jec == self%npy-1)

  imax = self%iec
  if (right_bdry) then
    imax = imax + 1
  end if

  jmax = self%jec
  if (upper_bdry) then
    jmax = jmax + 1
  end if

  ! identify which points in first halo layer are this tasks's BC points
  loc_bc = .false.
  if (left_bdry) loc_bc(self%isc-1, self%jsc:self%jec) = .true.
  if (right_bdry) loc_bc(self%iec+1, self%jsc:self%jec) = .true.
  if (lower_bdry) loc_bc(self%isc:self%iec, self%jsc-1) = .true.
  if (upper_bdry) loc_bc(self%isc:self%iec, self%jec+1) = .true.
  if (left_bdry .and. lower_bdry) loc_bc(self%isc-1, self%jsc-1) = .true.
  if (left_bdry .and. upper_bdry) loc_bc(self%isc-1, self%jec+1) = .true.
  if (right_bdry .and. lower_bdry) loc_bc(self%iec+1, self%jsc-1) = .true.
  if (right_bdry .and. upper_bdry) loc_bc(self%iec+1, self%jec+1) = .true.

  ! local 2d array for ghost, no need to exchange
  loc_ghost = 1
  loc_ghost(self%isc:self%iec, self%jsc:self%jec) = 0
  where (loc_bc) loc_ghost = 0

  ! local 2d arrays for global_index, remote_index, and partition for exchanging across tasks

  ! global_index runs over the entire regional "compute" domain +/- 1 point
  loc_global_index = -1
  do j = self%jsc-1, self%jec+1
    do i = self%isc-1, self%iec+1
      ! 1-based index
      loc_global_index(i,j) = j * (self%npx + 1) + i + 1
    end do
  end do

  loc_remote_index = -1
  do j = self%jsc, self%jec
    do i = self%isc, self%iec
      ! 1-based index
      loc_remote_index(i,j) = (j - self%jsc) * (self%iec - self%isc + 1) + (i - self%isc) + 1
    end do
  end do
  counter_local_idx = maxval(loc_remote_index)
  ! use exchange to fill halo points with neighboring task's index
  call mpp_update_domains(loc_remote_index, self%domain)
  ! for halo points that are actually a BC, generate new local indices
  do j = self%jsc-1, self%jec+1
    do i = self%isc-1, self%iec+1
      if (loc_bc(i, j)) then
        counter_local_idx = counter_local_idx + 1
        loc_remote_index(i,j) = counter_local_idx
      end if
    end do
  end do

  loc_partition = -1
  loc_partition(self%isc:self%iec, self%jsc:self%jec) = self%f_comm%rank()
  call mpp_update_domains(loc_partition, self%domain)
  where (loc_bc) loc_partition = self%f_comm%rank()

  ! special case handling of halo points within the BC region:
  !
  ! to allow JEDI's generic code (using atlas) to perform halo exchanges within the BC region, we
  ! need to pass connectivity information (atlas's partition number and index of each point)
  ! between adjacent processors on the boundary. this is slightly tedious to do, because fv3's own
  ! halo-exchanges do NOT pass around BC information.
  !
  ! our strategy is take the indices that were generated to fill loc_remote_index, copy them into
  ! the *owned* portion of a dummy array, then use fv3's halo exchanges to send them to neighboring
  ! MPI tasks. this adds an extra MPI communication, but avoids the need to implement complicated
  ! logic to recreated the neighboring task's locally-generated indices into its BC regions.
  !
  ! in this illustration,
  !
  ! boundary condition        bc0   bc1   bc2   bc3 | bc4   bc5   bc6   bc7
  !                                                 |
  ! upper boundary of domain  ----------------------+----------------------
  !                                                 |
  ! interior points           x0    x1    x2    x3  | y0    y1    y2    y3
  !                                 task 0          |       task 1
  !
  ! task 0 needs to fill the halo location `bc4` adjacent to its BC location `bc3`. the partition
  ! number is easily obtained by reading the partition of points `y0`, as these must match.
  ! however, the index of `bc4` on task 1 is hard to recompute on task 0, so we follow these steps,
  ! - task 1 copies the generated index of `bc4` into the `y0` slot of a dummy array
  ! - use fv3's halo exchange to send this index into the halo region on task 0
  ! - task 0 reads `bc4`'s local index (from task 1) in the `y0` slot of the dummy array
  exchange_remote_index = -1
  if (left_bdry) then
    if (.not.upper_bdry) then
      ! fill upper-left OWNED point with generated index of corresponding BC point
      exchange_remote_index(self%isc, self%jec) = loc_remote_index(self%isc-1, self%jec)
    end if
    if (.not.lower_bdry) then
      exchange_remote_index(self%isc, self%jsc) = loc_remote_index(self%isc-1, self%jsc)
    end if
  end if
  if (right_bdry) then
    if (.not.upper_bdry) then
      exchange_remote_index(self%iec, self%jec) = loc_remote_index(self%iec+1, self%jec)
    end if
    if (.not.lower_bdry) then
      exchange_remote_index(self%iec, self%jsc) = loc_remote_index(self%iec+1, self%jsc)
    end if
  end if
  if (lower_bdry) then
    if (.not.left_bdry) then
      exchange_remote_index(self%isc, self%jsc) = loc_remote_index(self%isc, self%jsc-1)
    end if
    if (.not.right_bdry) then
      exchange_remote_index(self%iec, self%jsc) = loc_remote_index(self%iec, self%jsc-1)
    end if
  end if
  if (upper_bdry) then
    if (.not.left_bdry) then
      exchange_remote_index(self%isc, self%jec) = loc_remote_index(self%isc, self%jec+1)
    end if
    if (.not.right_bdry) then
      exchange_remote_index(self%iec, self%jec) = loc_remote_index(self%iec, self%jec+1)
    end if
  end if
  ! halo-exchange the dummy array
  call mpp_update_domains(exchange_remote_index, self%domain)
  if (left_bdry) then
    if (.not.upper_bdry) then
      ! fill upper-left BC from neighbor's lower-right OWNED point, using the index already in halo
      loc_remote_index(self%isc-1, self%jec+1) = exchange_remote_index(self%isc, self%jec+1)
      loc_partition(self%isc-1, self%jec+1) = loc_partition(self%isc, self%jec+1)
    end if
    if (.not.lower_bdry) then
      loc_remote_index(self%isc-1, self%jsc-1) = exchange_remote_index(self%isc, self%jsc-1)
      loc_partition(self%isc-1, self%jsc-1) = loc_partition(self%isc, self%jsc-1)
    end if
  end if
  if (right_bdry) then
    if (.not.upper_bdry) then
      loc_remote_index(self%iec+1, self%jec+1) = exchange_remote_index(self%iec, self%jec+1)
      loc_partition(self%iec+1, self%jec+1) = loc_partition(self%iec, self%jec+1)
    end if
    if (.not.lower_bdry) then
      loc_remote_index(self%iec+1, self%jsc-1) = exchange_remote_index(self%iec, self%jsc-1)
      loc_partition(self%iec+1, self%jsc-1) = loc_partition(self%iec, self%jsc-1)
    end if
  end if
  if (lower_bdry) then
    if (.not.left_bdry) then
      loc_remote_index(self%isc-1, self%jsc-1) = exchange_remote_index(self%isc-1, self%jsc)
      loc_partition(self%isc-1, self%jsc-1) = loc_partition(self%isc-1, self%jsc)
    end if
    if (.not.right_bdry) then
      loc_remote_index(self%iec+1, self%jsc-1) = exchange_remote_index(self%iec+1, self%jsc)
      loc_partition(self%iec+1, self%jsc-1) = loc_partition(self%iec+1, self%jsc)
    end if
  end if
  if (upper_bdry) then
    if (.not.left_bdry) then
      loc_remote_index(self%isc-1, self%jec+1) = exchange_remote_index(self%isc-1, self%jec)
      loc_partition(self%isc-1, self%jec+1) = loc_partition(self%isc-1, self%jec)
    end if
    if (.not.right_bdry) then
      loc_remote_index(self%iec+1, self%jec+1) = exchange_remote_index(self%iec+1, self%jec)
      loc_partition(self%iec+1, self%jec+1) = loc_partition(self%iec+1, self%jec)
    end if
  end if

  call self%fv3_nodes_to_atlas_nodes(self%grid_lon, lons)
  call self%fv3_nodes_to_atlas_nodes(self%grid_lat, lats)
  call self%fv3_nodes_to_atlas_nodes(loc_ghost, ghosts)
  call self%fv3_nodes_to_atlas_nodes(loc_global_index, global_indices)
  call self%fv3_nodes_to_atlas_nodes(loc_remote_index, remote_indices)
  call self%fv3_nodes_to_atlas_nodes(loc_partition, partition)

  lons = constant('rad2deg') * lons
  lats = constant('rad2deg') * lats

  quad_counter = 1
  do j = self%jsc-1, jmax
    do i = self%isc-1, imax
      if ((j /= jmax) .and. (i /= imax)) then
        raw_quad_boundary_nodes(quad_counter)   = loc_global_index(i, j)
        raw_quad_boundary_nodes(quad_counter+1) = loc_global_index(i+1, j)
        raw_quad_boundary_nodes(quad_counter+2) = loc_global_index(i+1, j+1)
        raw_quad_boundary_nodes(quad_counter+3) = loc_global_index(i, j+1)
        quad_counter = quad_counter + 4
      end if
    end do
  end do

  ! quad_counter-1 == num_quad_boundary_nodes
  if (quad_counter-1 /= num_quad_boundary_nodes) then
    call abor1_ftn('fv3jedi_geom_mod: inconsistent quad counter when getting connectivities')
  end if

  ! Avoid compilation warning
  raw_tri_boundary_nodes = 0

end subroutine get_coords_and_connectivities_regional

! --------------------------------------------------------------------------------------------------

subroutine fv3_nodes_to_atlas_nodes_r(self, fv3_data, atlas_data)

  class(fv3jedi_geom), intent(in) :: self
  real(kind_real), intent(in) :: fv3_data(self%isd:self%ied, self%jsd:self%jed)
  real(kind_real), intent(inout) :: atlas_data(:)

  integer :: a, b, ncopy
  logical :: at_lower_left_corner, at_upper_left_corner, at_lower_right_corner
  logical :: at_right_edge, at_upper_edge
  logical :: halo_w, halo_e, halo_s, halo_n, halo_sw, halo_nw, halo_ne, halo_se, halo_nw3, halo_se6

  ! Identify which halos need including
  ! Default case for PEs interior to a tile
  halo_w = .true.
  halo_s = .true.
  halo_sw = .true.
  halo_e = .false.
  halo_n = .false.
  halo_nw = .false.
  halo_ne = .false.
  halo_se = .false.
  halo_nw3 = .false.
  halo_se6 = .false.

  ! Edges and corners depend on specifics...
  if (self%ntiles == 6) then
    ! Global grid -- handle corners between cubed-sphere tiles
    at_lower_left_corner = (self%isc == 1 .and. self%jsc == 1)
    at_upper_left_corner = (self%isc == 1 .and. self%jec == self%npy-1)
    at_lower_right_corner = (self%iec == self%npx-1 .and. self%jsc == 1)

    ! at lower-left corner of any tile, use a triangle => no diagonal point
    if (at_lower_left_corner) then
      halo_sw = .false.
    end if
    ! at upper-left corner of tile #3, place extra tri => add extra point
    if (at_upper_left_corner .and. (self%ntile == 3)) then
      halo_nw3 = .true.
    end if
    ! at lower-right corner of tile #6, place extra tri => add extra point
    if (at_lower_right_corner .and. (self%ntile == 6)) then
      halo_se6 = .true.
    end if

  else if (self%ntiles == 1) then
    ! Regional grid -- handle "boundary condition" points around patch
    at_right_edge = (self%iec == self%npx-1)
    at_upper_edge = (self%jec == self%npy-1)

    if (at_upper_edge) then
      halo_n = .true.
      halo_nw = .true.
    end if
    if (at_right_edge) then
      halo_e = .true.
      halo_se = .true.
      if (at_upper_edge) then
        halo_ne = .true.
      end if
    end if

  else
    call mpp_error(FATAL, "fv3_nodes_to_atlas_nodes: ntiles != 1 or 6")
  end if

  ! First, copy owned points
  ncopy = self%ngrid
  a = 1
  b = ncopy
  atlas_data(a:b) = reshape(fv3_data(self%isc:self%iec, self%jsc:self%jec), (/ncopy/))

  ! Copy west + east edge halos
  ncopy = (self%jec - self%jsc + 1)
  if (halo_w) then
    a = b + 1
    b = b + ncopy
    atlas_data(a:b) = reshape(fv3_data(self%isc-1, self%jsc:self%jec), (/ncopy/))
  end if
  if (halo_e) then
    a = b + 1
    b = b + ncopy
    atlas_data(a:b) = reshape(fv3_data(self%iec+1, self%jsc:self%jec), (/ncopy/))
  end if

  ! Copy south + north edge halos
  ncopy = (self%iec - self%isc + 1)
  if (halo_s) then
    a = b + 1
    b = b + ncopy
    atlas_data(a:b) = reshape(fv3_data(self%isc:self%iec, self%jsc-1), (/ncopy/))
  end if
  if (halo_n) then
    a = b + 1
    b = b + ncopy
    atlas_data(a:b) = reshape(fv3_data(self%isc:self%iec, self%jec+1), (/ncopy/))
  end if

  ! Copy corners
  if (halo_sw) then
    a = b + 1
    b = b + 1
    atlas_data(a) = fv3_data(self%isc-1, self%jsc-1)
  end if
  if (halo_nw) then
    a = b + 1
    b = b + 1
    atlas_data(a) = fv3_data(self%isc-1, self%jec+1)
  end if
  if (halo_ne) then
    a = b + 1
    b = b + 1
    atlas_data(a) = fv3_data(self%iec+1, self%jec+1)
  end if
  if (halo_se) then
    a = b + 1
    b = b + 1
    atlas_data(a) = fv3_data(self%iec+1, self%jsc-1)
  end if

  if (halo_nw3) then
    a = b + 1
    b = b + 1
    atlas_data(a) = fv3_data(self%isc, self%jec+1)
  end if
  if (halo_se6) then
    a = b + 1
    b = b + 1
    atlas_data(a) = fv3_data(self%iec+1, self%jsc)
  end if

  ! sanity check on size: b = size(atlas_data)
  if (b /= size(atlas_data)) then
    call abor1_ftn('fv3jedi_geom_mod%fv3_nodes_to_atlas_nodes: inconsistent atlas_data size')
  end if

end subroutine fv3_nodes_to_atlas_nodes_r

! --------------------------------------------------------------------------------------------------

! displeasing!
! this is a copy of the real interface above with just one replacement real -> integer
subroutine fv3_nodes_to_atlas_nodes_i(self, fv3_data, atlas_data)

  class(fv3jedi_geom), intent(in) :: self
  integer, intent(in) :: fv3_data(self%isd:self%ied, self%jsd:self%jed)
  integer, intent(inout) :: atlas_data(:)

  integer :: a, b, ncopy
  logical :: at_lower_left_corner, at_upper_left_corner, at_lower_right_corner
  logical :: at_right_edge, at_upper_edge
  logical :: halo_w, halo_e, halo_s, halo_n, halo_sw, halo_nw, halo_ne, halo_se, halo_nw3, halo_se6

  ! Identify which halos need including
  ! Default case for PEs interior to a tile
  halo_w = .true.
  halo_s = .true.
  halo_sw = .true.
  halo_e = .false.
  halo_n = .false.
  halo_nw = .false.
  halo_ne = .false.
  halo_se = .false.
  halo_nw3 = .false.
  halo_se6 = .false.

  ! Edges and corners depend on specifics...
  if (self%ntiles == 6) then
    ! Global grid -- handle corners between cubed-sphere tiles
    at_lower_left_corner = (self%isc == 1 .and. self%jsc == 1)
    at_upper_left_corner = (self%isc == 1 .and. self%jec == self%npy-1)
    at_lower_right_corner = (self%iec == self%npx-1 .and. self%jsc == 1)

    ! at lower-left corner of any tile, use a triangle => no diagonal point
    if (at_lower_left_corner) then
      halo_sw = .false.
    end if
    ! at upper-left corner of tile #3, place extra tri => add extra point
    if (at_upper_left_corner .and. (self%ntile == 3)) then
      halo_nw3 = .true.
    end if
    ! at lower-right corner of tile #6, place extra tri => add extra point
    if (at_lower_right_corner .and. (self%ntile == 6)) then
      halo_se6 = .true.
    end if

  else if (self%ntiles == 1) then
    ! Regional grid -- handle "boundary condition" points around patch
    at_right_edge = (self%iec == self%npx-1)
    at_upper_edge = (self%jec == self%npy-1)

    if (at_upper_edge) then
      halo_n = .true.
      halo_nw = .true.
    end if
    if (at_right_edge) then
      halo_e = .true.
      halo_se = .true.
      if (at_upper_edge) then
        halo_ne = .true.
      end if
    end if

  else
    call mpp_error(FATAL, "fv3_nodes_to_atlas_nodes: ntiles != 1 or 6")
  end if

  ! First, copy owned points
  ncopy = self%ngrid
  a = 1
  b = ncopy
  atlas_data(a:b) = reshape(fv3_data(self%isc:self%iec, self%jsc:self%jec), (/ncopy/))

  ! Copy west + east edge halos
  ncopy = (self%jec - self%jsc + 1)
  if (halo_w) then
    a = b + 1
    b = b + ncopy
    atlas_data(a:b) = reshape(fv3_data(self%isc-1, self%jsc:self%jec), (/ncopy/))
  end if
  if (halo_e) then
    a = b + 1
    b = b + ncopy
    atlas_data(a:b) = reshape(fv3_data(self%iec+1, self%jsc:self%jec), (/ncopy/))
  end if

  ! Copy south + north edge halos
  ncopy = (self%iec - self%isc + 1)
  if (halo_s) then
    a = b + 1
    b = b + ncopy
    atlas_data(a:b) = reshape(fv3_data(self%isc:self%iec, self%jsc-1), (/ncopy/))
  end if
  if (halo_n) then
    a = b + 1
    b = b + ncopy
    atlas_data(a:b) = reshape(fv3_data(self%isc:self%iec, self%jec+1), (/ncopy/))
  end if

  ! Copy corners
  if (halo_sw) then
    a = b + 1
    b = b + 1
    atlas_data(a) = fv3_data(self%isc-1, self%jsc-1)
  end if
  if (halo_nw) then
    a = b + 1
    b = b + 1
    atlas_data(a) = fv3_data(self%isc-1, self%jec+1)
  end if
  if (halo_ne) then
    a = b + 1
    b = b + 1
    atlas_data(a) = fv3_data(self%iec+1, self%jec+1)
  end if
  if (halo_se) then
    a = b + 1
    b = b + 1
    atlas_data(a) = fv3_data(self%iec+1, self%jsc-1)
  end if

  if (halo_nw3) then
    a = b + 1
    b = b + 1
    atlas_data(a) = fv3_data(self%isc, self%jec+1)
  end if
  if (halo_se6) then
    a = b + 1
    b = b + 1
    atlas_data(a) = fv3_data(self%iec+1, self%jsc)
  end if

  ! sanity check on size: b = size(atlas_data)
  if (b /= size(atlas_data)) then
    call abor1_ftn('fv3jedi_geom_mod%fv3_nodes_to_atlas_nodes: inconsistent atlas_data size')
  end if

end subroutine fv3_nodes_to_atlas_nodes_i

! --------------------------------------------------------------------------------------------------

end module fv3jedi_geom_mod
