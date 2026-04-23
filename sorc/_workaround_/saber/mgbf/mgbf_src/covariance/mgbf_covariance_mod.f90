! (C) Copyright 2022 United States Government as represented by the Administrator of the National
!     Aeronautics and Space Administration
!
! This software is licensed under the terms of the Apache Licence Version 2.0
! which can be obtained at http://www.apache.org/licenses/LICENSE-2.0.

module mgbf_covariance_mod

! atlas
use atlas_module,                   only: atlas_fieldset, atlas_field
use atlas_module,    only: atlas_functionspace
use atlas_module,    only: atlas_functionspace_StructuredColumns 
use atlas_module, only : atlas_functionspace,                      &
                         atlas_functionspace_nodecolumns,          &
                         atlas_functionspace_pointcloud,           &
                         atlas_functionspace_structuredcolumns,    &
                         atlas_mesh_nodes, atlas_field

use tools_func, only : sphere_dist
use tools_const, only : req          ! Earth radius (m)

! fckit
use fckit_mpi_module,               only: fckit_mpi_comm
use fckit_configuration_module,     only: fckit_configuration

! oops
use mgbf_kinds,                          only: r_kind,i_kind
use random_mod

! saber
!clt use mgbf_grid_mod,                   only: mgbf_grid
use mg_intstate , only:            mg_intstate_type
use mg_timers
use mpi
use, intrinsic :: ieee_arithmetic
implicit none
private
public mgbf_covariance

! Fortran class header
integer(kind=i_kind),parameter:: max_scales=100
type :: mgbf_covariance
  type(mg_intstate_type),allocatable :: intstate(:,:) 
  integer :: nscale=1
  integer :: nvargrp=1
  logical :: noMGBF
  logical :: bypassMGBFbe
  logical :: cv   ! cv=.true.; sv=.false.
  integer :: mp_comm_world
  integer :: rank
  logical :: l_2dvar_last_vertical_level=.true.  !when used for localization,2dvars are put on the last vertical level
                                          !when the fields in fset are stored from top to bottom  
!clt  integer :: lat2,lon2 ! these belog to mgbf_grid
  character(len=:), allocatable :: mgbf_nml
  character(len=80), allocatable :: mgbf_nml_group(:,:)
  real, allocatable :: multigrp_cor(:,:)
  integer, allocatable :: iscalegroup(:)
  integer, allocatable :: ivargroup(:)
  real(kind=r_kind), pointer :: work_mgbf(:,:,:)
  real(kind=r_kind), pointer:: work1var_mgbf(:,:,:)
  real(kind=r_kind), pointer :: work2d_mgbf(:,:)
  real(kind=r_kind), pointer :: rnormalization(:,:,:)
  real(kind=r_kind), pointer :: vargrp_work_mgbf(:,:,:)
  real(kind=r_kind), pointer :: vargrp_work_mgbf2(:,:,:)
  integer(kind=i_kind), pointer :: nlev_vargrp(:,:)
  integer(kind=i_kind), pointer :: varvlev_index(:,:,:)
  integer(kind=i_kind) :: total_km_a_all = 0
  integer(kind=i_kind) :: nvar = 0
  logical:: l_multiply_first_call(max_scales)=.true.
  
  contains
    procedure, public :: create
    procedure, public :: delete
    procedure, public :: randomize
    procedure, public :: multiply
    procedure, public :: multiply_ad
    procedure, private :: imem2scale
    procedure, private :: ivar2grp
end type mgbf_covariance

character(len=*), parameter :: myname='mgbf_covariance_mod'

! --------------------------------------------------------------------------------------------------

contains

! --------------------------------------------------------------------------------------------------

subroutine create(self, comm, config, funcspace, background, firstguess)

! Arguments
class(mgbf_covariance),     intent(inout) :: self
type(fckit_mpi_comm),      intent(in)    :: comm
type(fckit_configuration), intent(in)    :: config
type(atlas_functionspace), intent(in)    :: funcspace
type(atlas_fieldset),      intent(in)    :: background
type(atlas_fieldset),      intent(in)    :: firstguess

! Locals
real(r_kind) :: dist_rad, dist_m
integer      :: ipt
character(len=*), parameter :: myname_=myname//'*create'
character(len=:), allocatable :: mgbf_nml,centralblockname
logical :: central
integer :: layout(2)
integer :: myunit
integer :: iscale,ivargrp
integer :: nscale=1, nvargrp=1
type(atlas_field) :: afield, lonlat_field
type(atlas_functionspace_structuredcolumns) :: fs_sc
real(r_kind), pointer :: lonlat_ptr(:,:)
real(r_kind), allocatable :: lonlat_anl(:,:)
integer :: npts_owned
integer :: npts_total




character(len=80) :: readin_mgbf_nml_group(99)
real :: readin_multigrp_cor(99)=1.0
integer :: readin_iscalegroup(99)=999
integer :: readin_ivargroup(99)=999
integer ::i,j,k, ii,nz3d
namelist /parameters_mgbf_init/ nscale,nvargrp,readin_mgbf_nml_group ,readin_multigrp_cor,readin_iscalegroup,readin_ivargroup

character(len=:), allocatable :: dump_json
integer(i_kind):: max_nlevs

! Hold communicator
! -----------------
!self%mp_comm_world=comm%communicator()

! Create the grid
! ---------------
!clt call self%grid%create(config, comm)
self%rank = comm%rank()

write(6,*)'thinkdeb mgbf create999 '
write(6,*)'thinkdeb mgbf create999 config'
   dump_json=config%json()          ! serialize to a JSON string
write(6,'(A)')trim(dump_json)
call config%get_or_die("saber block name", centralblockname)
!clt call config%get_or_die("debuggingxx bypass mgbf", self%noMGBF)
if (config%has("mgbf sdl and vdl init namelist file")) then
     call config%get_or_die("mgbf sdl and vdl init namelist file",  mgbf_nml)
  open(newunit=myunit,file=trim(mgbf_nml),status='old')
!#  open(unit=10,file=mgbf_nml,status='old',action='read')
  read(myunit,nml=parameters_mgbf_init)
  close(unit=myunit)
  self%nscale=nscale
  self%nvargrp=nvargrp
  allocate(self%mgbf_nml_group(nscale,nvargrp))
  allocate(self%multigrp_cor(nvargrp,nvargrp)) !clt in the future, it could be used for more cor relationship 
  allocate(self%iscalegroup(nscale) )
  allocate(self%ivargroup(nvargrp) )
  ii=1
  do iscale=1,nscale
    do ivargrp=1,nvargrp
      self%mgbf_nml_group(iscale,ivargrp)=readin_mgbf_nml_group(ii)
      ii=ii+1
    enddo
  enddo
  do iscale=1,nscale
    self%iscalegroup(iscale)=readin_iscalegroup(iscale)
  enddo
  ii=1
  do i=1,nvargrp
    do j=1,nvargrp
      self%multigrp_cor(i,j)=readin_multigrp_cor(ii)
      ii=ii+1
    enddo
  enddo
  do i=1,nvargrp
    self%ivargroup(i)=readin_ivargroup(i)
  enddo
else
call config%get_or_die("mgbf namelist file ",  mgbf_nml)
!still need allocate them though nscale=nvargrp=1
  allocate(self%mgbf_nml_group(nscale,nvargrp))
  allocate(self%multigrp_cor(nvargrp,nvargrp)) !clt in the future, it could be used for more cor relationship 
  self%multigrp_cor=1.0
  allocate(self%iscalegroup(nscale) )
  self%iscalegroup(nscale) =1
  allocate(self%ivargroup(nvargrp) )
  self%ivargroup=1
endif
  
  
if(nscale == 1 .and. nvargrp ==1 ) then 
  self%mgbf_nml_group(1,1)=mgbf_nml   !the same mgbf namelist file is used 
                                      !and hence, it would be backward-compatible
                                      ! the previous namelist files could be still used,correctly,
                                      ! by the current sdl/vdl enhanced version
endif

if (trim(funcspace%name()) /= 'StructuredColumns') then
  error stop 'MGBF requires StructuredColumns function space'
end if
fs_sc = funcspace
npts_owned = fs_sc%size_owned()
npts_total   = fs_sc%size()
if(npts_owned.ge.npts_total) then
   write(6,*)'the halo points are not present, on which the outer block interpolator would be problematic, stop'
   call flush(6)
   stop
endif


lonlat_field = fs_sc%xy()
call lonlat_field%data(lonlat_ptr)
!bug allocate(lonlat_anl(npts_total,2))
allocate(lonlat_anl(npts_owned,2))
lonlat_anl(:,1) = lonlat_ptr(1,1:npts_owned)
lonlat_anl(:,2) = lonlat_ptr(2,1:npts_owned)
call lonlat_field%final()


allocate(self%intstate(nscale,nvargrp))
do iscale=1,nscale
  do ivargrp=1,nvargrp
   call  self%intstate(iscale,ivargrp)%mg_initialize(n_owned_anl=npts_owned, &
        anl_lonlat1d=lonlat_anl, inputfilename=self%mgbf_nml_group(iscale,ivargrp))  !mgbf_nml like mgbeta.nml
  enddo
enddo
if (allocated(lonlat_anl)) deallocate(lonlat_anl)

! Allocate persistent workspaces based on intstate sizes
do iscale=1,nscale
  self%total_km_a_all = 0
  do ivargrp=1,nvargrp
    self%total_km_a_all = self%total_km_a_all + self%intstate(iscale,ivargrp)%km_a_all
    if(self%intstate(iscale,ivargrp)%nm /= self%intstate(1,1)%nm ) then   
      write(6,*)'nm should be the same for all mgbf filters, stop'
      call flush(6)
      stop
    endif
    if(self%intstate(iscale,ivargrp)%mm /= self%intstate(1,1)%mm ) then 
      write(6,*)'mm should be the same for all mgbf filters, stop'
      call flush(6)
      stop
    endif
    if(self%intstate(iscale,ivargrp)%lm_a /= self%intstate(1,1)%lm_a ) then  
      write(6,*)'lm_a should be the same for all mgbf filters, stop'
      call flush(6)
      stop
    endif
  enddo
enddo
self%total_km_a_all=0
do iscale=1,nscale
  do ivargrp=1,nvargrp
    if (iscale == 1 ) self%total_km_a_all = self%total_km_a_all + self%intstate(iscale,ivargrp)%km_a_all
    if(self%intstate(iscale,ivargrp)%nm /= self%intstate(1,1)%nm ) then   
      write(6,*)'nm should be the same for all mgbf filters, stop'
      call flush(6)
      stop
    endif
    if(self%intstate(iscale,ivargrp)%mm /= self%intstate(1,1)%mm ) then 
      write(6,*)'mm should be the same for all mgbf filters, stop'
      call flush(6)
      stop
    endif
    if(self%intstate(iscale,ivargrp)%lm_a /= self%intstate(1,1)%lm_a ) then  
      write(6,*)'lm_a should be the same for all mgbf filters, stop'
      call flush(6)
      stop
    endif
  enddo
enddo
  self%nvar = 0
  do ivargrp=1,nvargrp
    self%nvar = self%nvar + self%intstate(1,ivargrp)%km2+self%intstate(1,ivargrp)%km3 
  enddo
  nz3d=self%intstate(1,1)%lm_a 

  allocate(self%work_mgbf(self%total_km_a_all, self%intstate(1,1)%nm, self%intstate(1,1)%mm))
  allocate(self%work2d_mgbf(self%total_km_a_all, self%intstate(1,1)%nm * self%intstate(1,1)%mm))
  allocate(self%rnormalization(self%total_km_a_all, nvargrp,nscale))
  self%rnormalization(1:self%total_km_a_all,1:nvargrp,1:nscale)=0.0
  allocate(self%varvlev_index(self%nvar,3,nscale))
  allocate(self%nlev_vargrp(nvargrp,nscale))
  do iscale=1,nscale
  do ivargrp=1,nvargrp
    self%nlev_vargrp(ivargrp,iscale)=self%intstate(iscale,ivargrp)%km_a_all
  enddo
  enddo
! Note, for different scales, they should have the sma esetup (using the same "zero level"  filtering grids from the atlas  )
  max_nlevs=1
  do iscale=1,nscale
  do ivargrp=1,nvargrp
   max_nlevs=max(max_nlevs,self%nlev_vargrp(ivargrp,iscale))
  enddo
  enddo
  allocate(self%vargrp_work_mgbf(max_nlevs, self%intstate(1,1)%nm, self%intstate(1,1)%mm))
  allocate(self%vargrp_work_mgbf2(max_nlevs, self%intstate(1,1)%nm, self%intstate(1,1)%mm))
  
  allocate(self%work1var_mgbf(nz3d, self%intstate(1,1)%nm, self%intstate(1,1)%mm))


  



end subroutine create

! --------------------------------------------------------------------------------------------------

subroutine delete(self)

! Arguments
class(mgbf_covariance) :: self
integer:: iscale,ivargrp

! Locals

!clt //if (.not. self%noMGBF) then
   call  print_mg_timers("mg_timer_output",999,self%rank)
  
do iscale=1,self%nscale
  do ivargrp=1,self%nvargrp
   call self%intstate(iscale,ivargrp)%mg_finalize()
  enddo
enddo
!clt endif

if (associated(self%work_mgbf)) deallocate(self%work_mgbf)
if (associated(self%work1var_mgbf)) deallocate(self%work1var_mgbf)
if (associated(self%work2d_mgbf)) deallocate(self%work2d_mgbf)
if (associated(self%rnormalization)) deallocate(self%rnormalization)
if (associated(self%nlev_vargrp)) deallocate(self%nlev_vargrp)
if (associated(self%varvlev_index)) deallocate(self%varvlev_index)
  deallocate(self%vargrp_work_mgbf,self%vargrp_work_mgbf2)

! Delete the grid
! ---------------
!clt call self%grid%delete()

end subroutine delete

! --------------------------------------------------------------------------------------------------

subroutine randomize(self, fields)

! Arguments
class(mgbf_covariance), intent(inout) :: self
type(atlas_fieldset),  intent(inout) :: fields

! Locals
type(atlas_field) :: afield
real(kind=r_kind), pointer :: psi(:,:), chi(:,:), t(:,:), q(:,:), qi(:,:), ql(:,:), o3(:,:)
real(kind=r_kind), pointer :: ps(:)

integer, parameter :: rseed = 3
write(6,*)'thinkdeb this is to be implemente'
call flush(6)
stop
! Get Atlas field
afield = fields%field('stream_function')
call afield%data(psi)

afield = fields%field('velocity_potential')
call afield%data(chi)

afield = fields%field('air_temperature')
call afield%data(t)

afield = fields%field('surface_pressure')
call afield%data(ps)

afield = fields%field('specific_humidity')
call afield%data(q)

afield = fields%field('cloud_liquid_ice')
call afield%data(qi)

afield = fields%field('cloud_liquid_water')
call afield%data(ql)

afield = fields%field('ozone_mass_mixing_ratio')
call afield%data(o3)


! Set fields to random numbers
call normal_distribution(psi, 0.0_r_kind, 1.0_r_kind, rseed)


end subroutine randomize

! --------------------------------------------------------------------------------------------------

subroutine multiply(self, fields,index_member_in)
! Arguments
class(mgbf_covariance), intent(inout) :: self
type(atlas_fieldset),  intent(inout) :: fields
integer ,               intent(in)    :: index_member_in
type(atlas_fieldset)                 :: fields_tmp
type(atlas_functionspace) :: afunctionspace

! Locals
type(atlas_field) :: afield
real(kind=r_kind), pointer :: ptr_2d(:,:)
real(kind=r_kind), pointer :: ptr_3d(:,:,:)
integer(kind=i_kind):: nz,ilev,isize
real(kind=r_kind), pointer :: work_mgbf(:,:,:)
real(kind=r_kind), pointer :: vargrp_work_mgbf(:,:,:)
real(kind=r_kind), pointer :: vargrp_work_mgbf2(:,:,:)
real(kind=r_kind), pointer :: work1var_mgbf(:,:,:)
real(kind=r_kind), pointer :: work2d_mgbf(:,:)
real(kind=r_kind), pointer :: rnormalization(:,:)
integer(kind=i_kind), pointer :: nlev_vargrp(:)
integer(kind=i_kind) :: dim2d(2),dim3d(3)
integer(kind=i_kind):: myrank,nxloc,nyloc,nzloc,nz3d
integer(kind=i_kind)::nvar
integer(kind=i_kind):: i,ivar,jvar,j,k,ij,lev1,lev2,iounit
integer(kind=i_kind):: n2d
integer(kind=i_kind), pointer :: varvlev_index(:,:)
logical  ::  l2d_encountered  
logical :: test_once=.false.
integer(kind=i_kind)::itest=0
character(len=32) :: fileoutput
character(len=4) :: str_rank
integer :: n_owned_size
integer, pointer :: ghost(:)
!clttype(atlas_FunctionSpace) :: fs
type(atlas_functionspace) :: fs_generic
type(atlas_functionspace_StructuredColumns) :: fs
integer :: ierr
integer :: member_index
integer :: iscale,jscale, ivargrp,ivargrp0,jvargrp
integer :: ii,nvargrp
integer :: ilev1,ilev2
integer ::  loc(2)
       
          if(index_member_in >= 999)  then ! not set previously and should not be used,
          member_index=1  ! the privous ensemble index starts from 0)
          else
                                        ! namely, it is not a sdl/vdl run.
          member_index=index_member_in+1  ! the privous ensemble index starts from 0)
          endif 
          jscale=self%imem2scale(member_index)
          nvargrp=self%nvargrp
          call btim(mg_multiply_time)
          call btim(mg_preprocess_time)
          if(self%intstate(jscale,1)%l_for_localization .and. self%intstate(jscale,1)%km2 > 0) then 
           write(6,*)"when mgbf is used for localizaiton, all 2d variables will be treated as 3d variable",  &
&        "in which, the first level contains the 2d variables and others zeros "  
                                                                                                        
           stop !to use a better exit procdure  
          endif
          myrank=self%rank
          write(str_rank,"(I4.4)")myrank
        if (.not. associated(self%nlev_vargrp)) then
          error stop "MGBF workspace nlev_vargrp not allocated"
        endif
        nlev_vargrp=>self%nlev_vargrp(:,jscale)
        if (size(nlev_vargrp) < nvargrp) then
          error stop "MGBF workspace nlev_vargrp too small for nvargrp"
        endif
        work_mgbf => self%work_mgbf
        work2d_mgbf => self%work2d_mgbf
        work1var_mgbf => self%work1var_mgbf
        rnormalization => self%rnormalization(:,:,jscale)
        vargrp_work_mgbf=> self%vargrp_work_mgbf
        vargrp_work_mgbf2=> self%vargrp_work_mgbf2

        
!clt         do iscale=1,self%nscale
              
             nz3d=self%intstate(jscale,1)%lm_a   !should be the same for different vargrps
         
             n2d=0
             l2d_encountered=.false.
             ivargrp0=1
             if (.not. associated(self%work_mgbf)) then
               error stop "MGBF workspace work_mgbf not allocated"
             endif
             if (size(work_mgbf,1) /= self%total_km_a_all .or. &
                 size(work_mgbf,2) /= self%intstate(jscale,ivargrp0)%nm .or. &
                 size(work_mgbf,3) /= self%intstate(jscale,ivargrp0)%mm) then
               error stop "MGBF workspace work_mgbf does not match "
             endif

             if (size(work2d_mgbf,1) /=  self%total_km_a_all .or. &
                 size(work2d_mgbf,2) /= self%intstate(jscale,ivargrp0)%nm * &
                                           self%intstate(jscale,ivargrp0)%mm) then
               error stop "MGBF workspace work2d_mgbf too small for current scale"
             endif

             if (size(rnormalization,1) /= self%total_km_a_all .or. &
                 size(rnormalization,2) /= nvargrp) then
               error stop "MGBF workspace rnormalization too small for current scale"
             endif
             work1var_mgbf=0
             if(self%l_multiply_first_call(jscale)) then
!$omp parallel do private(ivargrp,ii,k) schedule(static)
                do ivargrp=1,nvargrp
                  ii=1
   !clt if for localization , km2=0
                  do k=1,self%intstate(jscale,ivargrp)%km3
                        rnormalization(ii:ii+nz3d-1,ivargrp)=self%intstate(jscale,ivargrp)%coef_normalization(1:nz3d)
                        ii=ii+nz3d
                
                  enddo
                  do k=1,self%intstate(jscale,ivargrp)%km2
   !clt if for localization , km2=0  only for 
   !clt only for     l_2dvar_last_vertical_lev
                    rnormalization(ii,ivargrp)=self%intstate(jscale,ivargrp)%coef_normalization(nz3d)
                    ii=ii+1
                  enddo
                  if (any(rnormalization(1:nlev_vargrp(ivargrp), ivargrp) == 0.0_r_kind)) then
                    write(6,*) 'DBG zero normalization in group', ivargrp, &
                      ' nlev=', nlev_vargrp(ivargrp), ' jscale=', jscale, ' rank=', self%rank
                  endif
                enddo
!$omp end parallel do
             endif

             dim2d=shape(work2d_mgbf)

             dim3d=shape(work_mgbf)
             nxloc=dim3d(2)
             nyloc=dim3d(3)
             nzloc=dim3d(1)
             nvar=fields%size() 
             if(nvar /= self%nvar ) then
               write(6,*)'wrong, local nvar is not the same as self%nvar stop'
               call flush(6)
               stop
             endif
             varvlev_index => self%varvlev_index(:,:,jscale)
             if (self%l_multiply_first_call(jscale))  varvlev_index = 0
          
                ilev=1
             do isize=1,fields%size()
                
                afield= fields%field(isize)  !clttodo
                fs= afield%functionspace()  !cltthinkfore debug
                n_owned_size= fs%size_owned() !clt for debug
                if(afield%rank() == 2)  then
                    nz=afield%levels()
                    call afield%data(ptr_2d)
                    if(nz /= 1 .and. nz /= nz3d ) then
                      write(6,*)'the vertical dimension of the input fields are not as expectd ,stop ',nz,' ',nz3d 
                      call flush(6)
                      stop
                    endif

                    if(nz == 1) then 
                        if(self%intstate(jscale,1)%l_for_localization) then 
                             if( self%l_2dvar_last_vertical_level) then  !when used for localization,2dvars are put on the last vertical level
                                if(ilev+nz3d-1 > self%total_km_a_all) then 
                                   write(6,*)'MGBF abort 1 : the dimensions are not as expected'
                                   call flush(6)
                                   stop
                                endif
                                if(n_owned_size >0 ) then 
                                  work2d_mgbf(ilev+nz3d-1:ilev+nz3d-1,:)=ptr_2d(:,1:n_owned_size)
                                  work2d_mgbf(ilev:ilev+nz3d-2,:)=0.0  !other levels are set to 0 and to be updated by the info spreading.
                                else
                                  work2d_mgbf(ilev+nz3d-1:ilev+nz3d-1,:)=ptr_2d 
                                  work2d_mgbf(ilev:ilev+nz3d-2,:)=ptr_2d 
                                endif
                              else
                                if(ilev+nz-1 > self%total_km_a_all) then 
                                   write(6,*)'MGBF abort 2 : the dimensions are not as expected'
                                   call flush(6)
                                   stop
                                endif
                                if(n_owned_size >0 ) then 
                                  work2d_mgbf(ilev:ilev+nz-1,:)=ptr_2d (:,1:n_owned_size)
                                else
                                  work2d_mgbf(ilev:ilev+nz-1,:)=ptr_2d 
                                endif
                                work2d_mgbf(ilev+nz:ilev+nz3d-1,:)=0.0
                              endif
                            
                        
                        else
                                if(ilev+nz-1 > self%total_km_a_all) then 
                                   write(6,*)'MGBF abort 3 : the dimensions are not as expected'
                                   call flush(6)
                                   stop
                                endif
                            if(n_owned_size >0 ) then 
                               work2d_mgbf(ilev:ilev+nz-1,:)=ptr_2d(:,1:n_owned_size) 
                            else
                               work2d_mgbf(ilev:ilev+nz-1,:)=ptr_2d 
                            endif
                        endif
                     else
                                if(ilev+nz-1 > self%total_km_a_all) then 
                                   write(6,*)'MGBF abort 4 : the dimensions are not as expected'
                                   call flush(6)
                                   stop
                                endif
                       if(n_owned_size >0 ) then 
                        work2d_mgbf(ilev:ilev+nz-1,:)=ptr_2d(:,1:n_owned_size)
                       else
                        work2d_mgbf(ilev:ilev+nz-1,:)=ptr_2d
                       endif
                    endif
                     
                    if(nz ==  1) then 
                      l2d_encountered=.true.
                      n2d=n2d+1
                    endif
                    if(nz > 1) then 
                       if(l2d_encountered  ) then
                        call flush(6)
                        error stop ("2dvariable is not put in the ending stop.")    !  is required 2d fields are saved consecutively,and at the ending  
                       endif
                    endif
                    if(self%l_multiply_first_call(jscale)) then
                       if(isize==1) then
                           varvlev_index(isize,1)= 1
         !cltothink                  if(.not.self%intstate(iscale,ivargrp)%l_for_localization )then 
                           if(.not.self%intstate(jscale,1)%l_for_localization )then 
                             varvlev_index(isize,2)= nz
                           else
                             varvlev_index(isize,2)= nz3d
                           endif
                           varvlev_index(isize,3)= varvlev_index(isize,2) -varvlev_index(isize,1)+1 
                       else
        !cltorg                 varvlev_index(isize,1)= varvlev_index(isize-1,1)+nz3d
                           varvlev_index(isize,1)= varvlev_index(isize-1,2)+1
                           if(.not.self%intstate(jscale,ivargrp0)%l_for_localization )then 
                             varvlev_index(isize,2)= varvlev_index(isize,1)+nz-1
                           else
                             varvlev_index(isize,2)= varvlev_index(isize,1)+nz3d-1
                           endif
                           varvlev_index(isize,3)= varvlev_index(isize,2) -varvlev_index(isize,1)+1 
                       endif
                    endif

                      
                    ilev=varvlev_index(isize,2)+1
                elseif (afield%rank() == 3) then  
                    write(6,*)'this case needs more work, stop' ! a better exption handling to be added
                    call flush(6)
                    stop 
                else
                    write(6,*)'wrong in mgbf_covariance_mod.f90 ' !todo  
                    stop
                endif 
             enddo
!$omp parallel do private(k) schedule(static)
             do k=1,nzloc
                work_mgbf(k,:,:) = reshape(work2d_mgbf(k,:),[dim3d(2),dim3d(3)])
             enddo
!$omp end parallel do
               
             if(self%intstate(jscale,ivargrp0)%km2.ne.n2d.and. .not.self%intstate(jscale,ivargrp0)%l_for_localization ) then 
                write(6,*)'The numbers of 2d variables is different from  mgbf-expected ,stop'
                stop   ! a better exception handling is to be added
             endif

                call etim(mg_preprocess_time)
             ii=1
             do ivargrp=1,nvargrp
                vargrp_work_mgbf(1:nlev_vargrp(ivargrp),:,:) = work_mgbf(ii:ii+nlev_vargrp(ivargrp)-1,:,:)

                call btim(mg_anal_to_filt_time)
                call self%intstate(jscale,ivargrp)%anal_to_filt_allmap & 
                (vargrp_work_mgbf(1:nlev_vargrp(ivargrp),:,:))
                call etim(mg_anal_to_filt_time)
                call btim(mg_filtering_time)
                call self%intstate(jscale,ivargrp)%filtering_procedure(self%intstate(jscale,ivargrp)%mgbf_proc,1)
                call etim(mg_filtering_time)
               
      !cltorg          call self%intstate%filt_to_anal_allmap(work_mgbf)
                call btim(mg_filt_to_anal_time)
                call self%intstate(jscale,ivargrp)%filt_to_anal_allmap  &
               (vargrp_work_mgbf2(1:nlev_vargrp(ivargrp),:,:))
                call etim(mg_filt_to_anal_time)
      !clt#        work_mgbf=999.0 !thinkdeb for debug
       
                call btim(mg_postprocess_time)
!$omp parallel do private(k) schedule(static)
                do k=1,nlev_vargrp(ivargrp)
                 vargrp_work_mgbf2(k,:,:) = vargrp_work_mgbf2(k,:,:) / rnormalization(k,ivargrp)
                enddo
!$omp end parallel do
                work_mgbf(ii:ii+nlev_vargrp(ivargrp)-1,:,:) = vargrp_work_mgbf2(1:nlev_vargrp(ivargrp),:,:)
                ii=ii+nlev_vargrp(ivargrp)
             enddo ! ivargrp
             if(self%intstate(jscale,ivargrp0)%l_for_localization ) then   !clthinkdebxxx
               work1var_mgbf = 0.0
               if(nvargrp == 1 ) then
                   do ivar=1,nvar
                     lev1=varvlev_index(ivar,1)
                     lev2=varvlev_index(ivar,2)
                     work1var_mgbf=work1var_mgbf+work_mgbf(lev1:lev2,:,:)
                   enddo
!$omp parallel do private(jvar,lev1,lev2) schedule(static)
                   do jvar=1,nvar
                     lev1=varvlev_index(jvar,1)
                     lev2=varvlev_index(jvar,2)
                     work_mgbf(lev1:lev2,:,:)=work1var_mgbf
                   enddo
!$omp end parallel do
               else
!clttodo, further optimizaiton
                 do jvar=1,nvar
                   jvargrp=self%ivar2grp(jvar)
                   do ivar=1,nvar
                     lev1=varvlev_index(ivar,1)
                     lev2=varvlev_index(ivar,2)
                     ivargrp=self%ivar2grp(ivar)
                     work1var_mgbf=work1var_mgbf+self%multigrp_cor(jvargrp,ivargrp)*work_mgbf(lev1:lev2,:,:)
                   enddo
                   lev1=varvlev_index(jvar,1)
                   lev2=varvlev_index(jvar,2)
                   work_mgbf(lev1:lev2,:,:)=work1var_mgbf
                 enddo
               endif
               nullify(work1var_mgbf)
             endif
!$omp parallel do private(k) schedule(static)
             do k=1,nzloc
               work2d_mgbf(k,:) = reshape(work_mgbf(k,:,:),[dim2d(2)])
             enddo
!$omp end parallel do
                ilev=1
                     n_owned_size=0
             do isize=1,fields%size()
     

                afield=fields%field(isize)  !clttodo
                fs= afield%functionspace()  !cltthinkfore debug
                n_owned_size= fs%size_owned() !clt for debug


                if(afield%rank() == 2) then 
                  call afield%data(ptr_2d)
                  nz=afield%levels()
                  lev1=varvlev_index(isize,1)
                   if( maxval(work2d_mgbf(lev1:lev1+nz-1,:)) .gt.0.5) then 
                       loc=maxloc(work2d_mgbf(lev1:lev1+nz-1,:)) 
                       write(6,*)'thinkdeb333 max is large 0.5 loc ',loc
                   endif
                  if(nz.gt.1) then 
                      if(n_owned_size >0 ) then 
                          ptr_2d(1:nz,1:n_owned_size)=work2d_mgbf(lev1:lev1+nz-1,:)!if nz=1, only the first level is used (like for surface pressure) 
                       else 
                       !cltthinkdebto now, the n_owned_size can't be got rightly for mgbf_grid using PointCloud function space
                          ptr_2d(1:nz,:)=work2d_mgbf(lev1:lev1+nz-1,:)!if nz=1, only the first level is used (like for surface pressure) 
                      endif
                  else
                     if(self%intstate(1,1)%l_for_localization) then 
                         if( self%l_2dvar_last_vertical_level) then !,2dvars are put on the last vertical level

                              if(n_owned_size >0 ) then 
                                ptr_2d(1,1:n_owned_size)=work2d_mgbf(lev1+nz3d-1,:)!if nz=1, only the first level is used (like for surface pressure) 
                              else 
                               !cltthinkdebto now, the n_owned_size can't be got rightly for mgbf_grid using PointCloud function space
                                ptr_2d(1,:)=work2d_mgbf(lev1+nz3d-1,:)!if nz=1, only the first level is used (like for surface pressure) 
                              endif
                         else
                              if(n_owned_size >0 ) then 
                                  ptr_2d(1,1:n_owned_size)=work2d_mgbf(lev1,:)! 
                              else 
                                  ptr_2d(1,:)=work2d_mgbf(lev1,:)!if nz=1, only the first level is used (like for surface pressure) 
                             endif
                         endif
                     else
                         if(n_owned_size >0 ) then 
                            ptr_2d(1,1:n_owned_size)=work2d_mgbf(lev1,:)!if nz=1, only the first level is used (like for surface pressure) 
                         else 
                         !cltthinkdebto now, the n_owned_size can't be got rightly for mgbf_grid using PointCloud function space
                            write(6,*)'suspicous situation while n_owned_szie =0 ,stop'
                            call flush(6)
                            stop
                            ptr_2d(1,:)=work2d_mgbf(lev1,:)!if nz=1, only the first level is used (like for surface pressure) 
                        endif
                       
                     endif
                  endif  !nz >1 or not
                
                elseif (afield%rank() == 3) then  
                  call afield%data(ptr_3d)
                  nz=afield%levels()
                  write(6,*)'wrong in mgbf_covariance_mod.f90 todo ' !todo  
                  call flush(6)
                  stop
                    

   !clt               ptr_3d=work2d_mgbf(ilev:ilev+nz-1,:) 
                  ilev=ilev+nz
                else
                  write(6,*)'wrong in mgbf_covariance_mod.f90 ' !todo  
                  call flush(6)
                  stop
                endif 
              enddo

             call etim(mg_postprocess_time)



             call afield%final()

             nullify(work_mgbf)
             nullify(work2d_mgbf)
             nullify(rnormalization)
             nullify(varvlev_index)
 !clt       enddo   !for iscale
          call etim(mg_multiply_time)
        nullify(nlev_vargrp)
        self%l_multiply_first_call(jscale)=.false.

end subroutine multiply

! --------------------------------------------------------------------------------------------------

subroutine multiply_ad(self, fields)

class(mgbf_covariance), intent(inout) :: self
type(atlas_fieldset),  intent(inout) :: fields

! This routine only needed when B = G^T G (sqrt-factored)

! To do list for this method
! 1. Convert fields (Atlas fieldsets) to MGBF bundle
! 2. Call MGBF covariance operator adjoint (sqrt version)
!        afield = fields%field('stream_function')
!        call afield%data(var3d)
!        var3d=0.0_r_kind

end subroutine multiply_ad
function imem2scale(self,imem) result(iscale)
  class(mgbf_covariance),intent(in)::self
  integer, intent(in)::imem
  integer :: iscale
     iscale=1
    do  while (iscale.le.self%nscale-1.and.imem > self%iscalegroup(iscale) )
       iscale=iscale+1      
    enddo
        
end function imem2scale
function ivar2grp(self,ivar) result(jvargrp)
  class(mgbf_covariance),intent(in)::self
  integer, intent(in)::ivar
  integer :: jvargrp
     jvargrp=1
    do  while (jvargrp.le.self%nvargrp-1.and.ivar > self%ivargroup(jvargrp) )
       jvargrp=jvargrp+1      
    enddo
        
end function ivar2grp

! --------------------------------------------------------------------------------------------------

end module mgbf_covariance_mod
