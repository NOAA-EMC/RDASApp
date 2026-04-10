module mg_parameter
!$$$  submodule documentation block
!                .      .    .                                       .
! module:   mg_parameter
!   prgmmr: rancic           org: NCEP/EMC            date: 2022
!
! abstract:  Set resolution, grid and decomposition (offset version)
!
! module history log:
!   2023-04-19  lei     - object-oriented coding
!   2024-01-11  rancic  - optimization for ensemble localization
!   2024-02-20  yokota  - refactoring to apply for GSI
!
! Subroutines Included:
!   init_mg_parameter -
!   def_maxgen -
!   def_ngens -
!
! Functions Included:
!
! remarks:
!   ixm(1)=nxm, jym(1)=nym
!   If mod(nxm,2)=0 then mod(im0,2)=0
!   If mod(nxm,2)>0 then mod(im0,8)=0 (for 4 generations)
!   (This will keep the right boundary of all decompmisitions
!   at same physical location)
!
! attributes:
!   language: f90
!   machine:
!
!$$$ end documentation block

use mgbf_kinds, only: i_kind,r_kind
use jp_pietc, only: u1
use phint1 
use mpi

implicit none
integer(i_kind),parameter :: lm_max=200  
type::  mg_parameter_type
!-----------------------------------------------------------------------
!*** 
logical:: l_for_localization=.false.  !used for localizaiton while multiple variates need additional treeatment
logical:: l_mgbf_inhomogeneous=.false.  !used inhomogeneous mgbf
!*** Namelist parameters
!***
real(r_kind):: mg_ampl01,mg_ampl02,mg_ampl03
real(r_kind):: mg_weig1,mg_weig2,mg_weig3,mg_weig4
                                              ! avoid a global version of it to avoid memory usage 
integer(i_kind):: mgbf_proc   !1-2: 3D filter                  (1: radial, 2: line)
                              !3-5: 2D filter for static B     (3: radial, 4: line, 5: isotropic line)
                              !6-8: 2D filter for localization (6: radial, 7: line, 8: isotropic line)
logical:: mgbf_line
integer(i_kind):: nxPE,nyPE,im_filt,jm_filt
logical:: lquart,lhelm

!*** 
!*** Number of generations
!***
integer(i_kind):: gm            
integer(i_kind):: gm_max   !clt should be removed? 

!*** 
!*** Horizontal resolution 
!***

!
! Original number of data on GSI analysis grid
!
integer(i_kind):: nA_max0
integer(i_kind):: mA_max0

!
! Global number of data on Analysis grid
!
integer(i_kind):: nm0        
integer(i_kind):: mm0       

!
! Number of PEs on Analysis grid
!
integer(i_kind):: nxm           
integer(i_kind):: nym           

!
! Number of data on local Analysis grid
!
integer(i_kind):: nm         
integer(i_kind):: mm        

!
! Number of data on global Filter grid
!
integer(i_kind):: im00
integer(i_kind):: jm00

!
! Number of data on local  Filter grid
!
integer(i_kind):: im
integer(i_kind):: jm    

!
! Initial index on local  Filter grid
!
integer(i_kind):: i0
integer(i_kind):: j0    
!
! Initial index on local analysis grid
!
integer(i_kind):: n0
integer(i_kind):: m0    

!
! Halo on local Filter grid 
!
integer(i_kind):: ib
integer(i_kind):: jb         

!
! Halo on local Analysis grid 
!
integer(i_kind):: nb
integer(i_kind):: mb     

integer(i_kind):: hx,hy,hz
integer(i_kind):: p
integer(i_kind):: nh,nfil
real(r_kind):: pasp01,pasp02,pasp03
real(r_kind):: pee2,rmom2_1,rmom2_2,rmom2_3,rmom2_4

integer, allocatable, dimension(:):: maxpe_fgen
integer, allocatable, dimension(:):: ixm,jym,nxy
integer, allocatable, dimension(:):: im0,jm0
integer, allocatable, dimension(:):: Fimax,Fjmax
integer, allocatable, dimension(:):: FimaxL,FjmaxL
real(r_kind), allocatable, dimension(:):: zofis  ! index of s(fitering grids) in analysis grids (its index is its coor)
real(r_kind), allocatable, dimension(:):: isofz  ! index of z of analysis grids in the filtering grids 

integer(i_kind):: npes_filt
integer(i_kind):: maxpe_filt

integer(i_kind):: imL,jmL
integer(i_kind):: imH,jmH
integer(i_kind):: lm_a          ! number of vertical layers in analysis fields
integer(i_kind):: lm            ! number of vertical layers in filter grids
!cltreal(r_kind):: coef_normalization(lm_max)=1.0 !normalizaton coefficients
real(r_kind):: coef_normalization(lm_max)=1 !normalizaton coefficients
real(r_kind):: coef_normalization_const=-9999.0 ! constant, if set, this contant will be 
                                                ! assigned to all elements of coef_normalization 

integer(i_kind):: km2           ! number of 2d variables for filtering
integer(i_kind):: km3           ! number of 3d variables for filtering
integer(i_kind):: n_ens         ! number of ensemble members
integer(i_kind):: km_a          ! total number of horizontal levels for analysis
integer(i_kind):: km_all        ! total number of k levels of ensemble for filtering
integer(i_kind):: km_a_all      ! total number of k levels of ensemble
integer(i_kind):: km2_all       ! total number of k horizontal levels of ensemble for filtering
integer(i_kind):: km3_all       ! total number of k vertical levels of ensemble
logical :: l_loc=.false.               ! logical flag for localization
logical :: l_filt_g1=.true.            ! logical flag for filtering of generation one
logical :: l_lin_vertical=.true.       ! logical flag for linear interpolation in vertcial
logical :: l_lin_horizontal=.true.     ! logical flag for linear interpolation in horizontal
logical :: l_quad_horizontal=.false.    ! logical flag for quadratic interpolation in horizontal
logical :: l_new_map            ! logical flag for new mapping between analysis and filter grid
logical :: l_vertical_filter    ! logical flag for vertical filtering
logical :: l_vert_stretched_filtgrid=.false.  ! true : filtering grids are stretched in tems of analysis grid unit 
logical :: l_anal_sub_of_filt   ! true : analysis grids and filtering grids are the same excpet for later has boundary points 
integer(i_kind):: km            ! number of vertically stacked all variables (km=km2+lm*km3)
integer(i_kind):: km_4
integer(i_kind):: km_16
integer(i_kind):: km_64

real(r_kind):: lengthx,lengthy,xa0,ya0,xf0,yf0
real(r_kind):: dxf,dyf,dxa,dya
real(r_kind),allocatable,dimension (:,:):: dxfm,dyfm  ! actual filtering grid intervals in meters
real(r_kind):: dxfmctrl=35000,dyfmctrl=35000  !the control filtering grid intervals corresponding to the contstant horizontal aspect tensor
real(r_kind):: dx_a2f_ratio=1,dy_a2f_ratio=1  !ratio between analsysis grids to filtering grids in x and y
                                             !it will be derived from other namelist parameters
logical :: l_constant_aspt2 =.true. ! using constant horizontal aspect tensor : ampl02

integer(i_kind):: npadx         ! x padding on analysis grid
integer(i_kind):: mpady         ! y padding on analysis grid

integer(i_kind):: ipadx         ! x padding on filter decomposition
integer(i_kind):: jpady         ! y padding on filter deocmposition

!
! Just for standalone test
!
logical:: ldelta

!from mg_mppstuff.f90
character(len=5):: c_mype
integer(i_kind):: mype
integer(i_kind):: npes,iTYPE,rTYPE,dTYPE,mpi_comm_comp,ierr,ierror
integer(i_kind):: mpi_comm_work,group_world,group_work
integer(i_kind):: mype_gr,npes_gr
integer(i_kind):: my_hgen
integer(i_kind):: mype_hgen
logical:: l_hgen
integer(i_kind):: nx,my
!from mg_domain.f90
logical,dimension(2):: Flwest,Fleast,Flnorth,Flsouth
integer(i_kind),dimension(2):: Fitarg_n,Fitarg_e,Fitarg_s,Fitarg_w                         
integer(i_kind),dimension(2):: Fitarg_sw,Fitarg_se,Fitarg_ne,Fitarg_nw
logical,dimension(2):: Flsendup_sw,Flsendup_se,Flsendup_nw,Flsendup_ne
integer(i_kind),dimension(2):: Fitarg_up
integer(i_kind):: itargdn_sw,itargdn_se,itargdn_ne,itargdn_nw
integer(i_kind):: itarg_wA,itarg_eA,itarg_sA,itarg_nA
logical:: lwestA,leastA,lsouthA,lnorthA
integer(i_kind):: ix,jy
integer(i_kind),dimension(2):: mype_filt
!from mg_domain_loc.f90
integer(i_kind):: nsq21,nsq32,nsq43
logical,dimension(4):: Flsouth_loc,Flnorth_loc,Flwest_loc,Fleast_loc
integer(i_kind),dimension(4):: Fitarg_s_loc,Fitarg_n_loc,Fitarg_w_loc,Fitarg_e_loc
integer(i_kind),dimension(4):: Fitargup_loc12
integer(i_kind),dimension(4):: Fitargup_loc23
integer(i_kind),dimension(4):: Fitargup_loc34
integer(i_kind):: itargdn_sw_loc21,itargdn_se_loc21,itargdn_nw_loc21,itargdn_ne_loc21
integer(i_kind):: itargdn_sw_loc32,itargdn_se_loc32,itargdn_nw_loc32,itargdn_ne_loc32
integer(i_kind):: itargdn_sw_loc43,itargdn_se_loc43,itargdn_nw_loc43,itargdn_ne_loc43
logical:: lsendup_sw_loc,lsendup_se_loc,lsendup_nw_loc,lsendup_ne_loc
logical:: l_mg_weig_readin=.false.
!clt for use of resolution-varied vertical filtering grids
real(r_kind), allocatable,dimension(:):: aspect_vert_profile_angrid ! should be of size (lm)
real(r_kind), allocatable,dimension(:):: aspect_vert_profile_filtgrid ! should be of size (lm)

contains
  procedure :: init_mg_parameter 
!from mg_mppstuff.f90
  procedure :: init_mg_MPI 
  procedure :: finishMPI 
  procedure :: barrierMPI 
!from mg_domain.f90
  procedure :: init_mg_domain
  procedure :: init_domain
  procedure :: init_topology_2d
  procedure :: real_itarg
!from mg_domain_loc.f90
  procedure :: init_domain_loc
  procedure :: sidesend_loc
  procedure :: targup_loc
  procedure :: targdn21_loc
  procedure :: targdn32_loc
  procedure :: targdn43_loc
!from jp_pbfil.f90
  generic :: cholaspect => cholaspect1,cholaspect2,cholaspect3,cholaspect4
  procedure,nopass :: cholaspect1,cholaspect2,cholaspect3,cholaspect4
  generic :: getlinesum => getlinesum1,getlinesum1d,getlinesum2,getlinesum3
  procedure :: getlinesum1,getlinesum1d,getlinesum2,getlinesum3
  generic :: rbeta => rbeta1,rbeta3d_1,rbeta2,rbeta3,rbeta4,vrbeta1,vrbeta2,vrbeta3,vrbeta4                 
  procedure:: rbeta1,rbeta3d_1,rbeta2,rbeta3,rbeta4,vrbeta1,vrbeta2,vrbeta3,vrbeta4                 
  generic :: rbetaT => rbeta1t,rbeta3d_1t,rbeta2t,rbeta3t,rbeta4t,vrbeta1t,vrbeta2t,vrbeta3t,vrbeta4t
  procedure:: rbeta1t,rbeta3d_1t,rbeta2t,rbeta3t,rbeta4t,vrbeta1t,vrbeta2t,vrbeta3t,vrbeta4t
end type  mg_parameter_type

interface
!from mg_mppstuff.f90
   module subroutine init_mg_MPI(this)
     class(mg_parameter_type),target :: this
   end subroutine
   module subroutine finishMPI(this)
     class(mg_parameter_type),target :: this
   end subroutine
   module subroutine barrierMPI(this)
     class(mg_parameter_type),target :: this
   end subroutine
!from mg_domain.f90
   module subroutine init_mg_domain(this) 
     class(mg_parameter_type)::this
   end subroutine
   module subroutine init_domain(this)
     class(mg_parameter_type),target::this
   end subroutine
   module subroutine init_topology_2d(this)
     class(mg_parameter_type),target::this
   end subroutine
   module subroutine real_itarg (this,itarg)
     class(mg_parameter_type),target::this
     integer(i_kind), intent(inout):: itarg
   end subroutine
!from mg_domain_loc.f90
   module subroutine init_domain_loc(this) 
     class(mg_parameter_type)::this
   end subroutine
   module subroutine sidesend_loc(this) 
     class(mg_parameter_type),target::this
   end subroutine
   module subroutine targup_loc(this) 
     class(mg_parameter_type),target::this
   end subroutine
   module subroutine targdn21_loc(this) 
     class(mg_parameter_type),target::this
   end subroutine
   module subroutine targdn32_loc(this) 
     class(mg_parameter_type),target::this
   end subroutine
   module subroutine targdn43_loc(this) 
     class(mg_parameter_type),target::this
   end subroutine
!from jp_pbfil.f90
   module subroutine cholaspect1(lx,mx, el)
     use mgbf_kinds, only: dp=>r_kind
     integer,                      intent(in   ):: lx,mx
     real(dp),dimension(1,1,lx:mx),intent(inout):: el
   end subroutine
   module subroutine cholaspect2(lx,mx, ly,my, el)
     use mgbf_kinds, only: dp=>r_kind
     integer,                            intent(in   ):: lx,mx, ly,my
     real(dp),dimension(2,2,lx:mx,ly:my),intent(inout):: el
     real(dp),dimension(2,2):: tel
   end subroutine
   module subroutine cholaspect3(lx,mx, ly,my, lz,mz, el)
     use mgbf_kinds, only: dp=>r_kind
     integer,                                  intent(in   ):: lx,mx, ly,my, lz,mz
     real(dp),dimension(3,3,lx:mx,ly:my,lz:mz),intent(inout):: el
     real(dp),dimension(3,3):: tel
   end subroutine
   module subroutine cholaspect4(lx,mx, ly,my, lz,mz, lw,mw,el)
     use mgbf_kinds, only: dp=>r_kind
     integer,                                        intent(in   ):: lx,mx, ly,my, lz,mz, lw,mw
     real(dp),dimension(4,4,lx:mx,ly:my,lz:mz,lw:mw),intent(inout):: el
     real(dp),dimension(4,4):: tel
   end subroutine
   module subroutine getlinesum1(this,hx,lx,mx, el, ss)
     use mgbf_kinds, only: dp=>r_kind
     class(mg_parameter_type)::this
     integer,                      intent(in   ):: hx,Lx,mx
     real(dp),dimension(1,1,Lx:Mx),intent(in   ):: el
     real(dp),dimension(    lx:mx),intent(  out):: ss
   end subroutine
   module subroutine getlinesum1d(this,hx,lx,mx, el, ss)
     use mgbf_kinds, only: dp=>r_kind
     class(mg_parameter_type)::this
     integer,                      intent(in   ):: hx,Lx,mx
     real(dp),dimension(Lx:Mx),intent(in   ):: el
     real(dp),dimension(    lx:mx),intent(  out):: ss
   end subroutine
   module subroutine getlinesum2(this,hx,lx,mx, hy,ly,my, el, ss)
     use mgbf_kinds, only: dp=>r_kind
     class(mg_parameter_type)::this
     integer,                            intent(in   ):: hx,Lx,mx, hy,ly,my
     real(dp),dimension(2,2,Lx:Mx,Ly:My),intent(in   ):: el
     real(dp),dimension(    lx:mx,ly:my),intent(  out):: ss
   end subroutine
   module subroutine getlinesum3(this,hx,lx,mx, hy,ly,my, hz,lz,mz, el, ss)
     use mgbf_kinds, only: dp=>r_kind
     class(mg_parameter_type)::this
     integer,                                  intent(in   ):: hx,Lx,mx, hy,ly,my, hz,lz,mz
     real(dp),dimension(3,3,Lx:Mx,Ly:My,Lz:Mz),intent(in   ):: el
     real(dp),dimension(    lx:mx,ly:my,lz:mz),intent(  out):: ss
   end subroutine
   module subroutine getlinesum4(this,hx,lx,mx, hy,ly,my, hz,lz,mz, hw,lw,mw, el, ss)
     use mgbf_kinds, only: dp=>r_kind
     class(mg_parameter_type)::this
     integer,                                        intent(in   ):: hx,Lx,mx, hy,ly,my, hz,lz,mz, hw,lw,mw
     real(dp),dimension(4,4,Lx:Mx,Ly:My,Lz:Mz,Lw:Mw),intent(in   ):: el
     real(dp),dimension(    lx:mx,ly:my,lz:mz,Lw:Mw),intent(  out):: ss
   end subroutine
   module subroutine rbeta1(this,hx,lx,mx, el,ss, a)
     use mgbf_kinds, only: dp=>r_kind
     class(mg_parameter_type)::this
     integer,                  intent(in   ):: hx,Lx,mx
     real(dp),dimension(Lx:Mx),intent(in   ):: el
     real(dp),dimension(Lx:Mx),intent(in   ):: ss
     real(dp),dimension(lx-hx:mx+hx),intent(inout):: a
   end subroutine
   module subroutine rbeta3d_1(this,nz,hx,lx,mx, el,ss, a)
     use mgbf_kinds, only: dp=>r_kind
     class(mg_parameter_type)::this
     integer,                  intent(in   )::nz, hx,Lx,mx
     real(dp),dimension(nz,Lx:Mx),intent(in   ):: el
     real(dp),dimension(nz,Lx:Mx),intent(in   ):: ss
     real(dp),dimension(nz,lx-hx:mx+hx),intent(inout):: a
   end subroutine
   module subroutine rbeta2(this,hx,lx,mx, hy,ly,my, el,ss, a)
     use mgbf_kinds, only: dp=>r_kind
     class(mg_parameter_type)::this
     integer,                            intent(in   ):: hx,Lx,mx, hy,ly,my
     real(dp),dimension(2,2,Lx:Mx,Ly:My),intent(in   ):: el
     real(dp),dimension(    Lx:Mx,Ly:My),intent(in   ):: ss
     real(dp),dimension(lx-hx:mx+hx,ly-hy:my+hy),intent(inout):: a
   end subroutine
   module subroutine rbeta3(this,hx,lx,mx, hy,ly,my, hz,lz,mz, el,ss,a)
     use mgbf_kinds, only: dp=>r_kind
     class(mg_parameter_type)::this
     integer,                                  intent(in   ):: hx,Lx,mx, hy,ly,my, hz,lz,mz
     real(dp),dimension(3,3,Lx:Mx,Ly:My,Lz:Mz),intent(in   ):: el
     real(dp),dimension(    Lx:Mx,Ly:My,Lz:Mz),intent(in   ):: ss
     real(dp),dimension(lx-hx:mx+hx,ly-hy:my+hy,lz-hz:mz+hz),intent(inout):: a
   end subroutine
   module subroutine rbeta4(this,hx,lx,mx, hy,ly,my, hz,lz,mz, hw,lw,mw, el,ss,a)
     use mgbf_kinds, only: dp=>r_kind
     class(mg_parameter_type)::this
     integer,                                        intent(in   ):: hx,Lx,mx, hy,ly,my, hz,lz,mz, hw,lw,mw
     real(dp),dimension(4,4,Lx:Mx,Ly:My,Lz:Mz,Lw:Mw),intent(in   ):: el
     real(dp),dimension(    Lx:Mx,Ly:My,Lz:Mz,Lw:Mw),intent(in   ):: ss
     real(dp),dimension(lx-hx:mx+hx,ly-hy:my+hy,lz-hz:mz+hz,lw-hw:mw+hw),intent(inout):: a
   end subroutine
   module subroutine rbeta1T(this,hx,lx,mx, el,ss, a)
     use mgbf_kinds, only: dp=>r_kind
     class(mg_parameter_type)::this
     integer,                      intent(in   ):: hx,Lx,mx
     real(dp),dimension(1,1,Lx:Mx),intent(in   ):: el
     real(dp),dimension(    Lx:Mx),intent(in   ):: ss
     real(dp),dimension(lx-hx:mx+hx),intent(inout):: a
   end subroutine
   module subroutine rbeta3d_1T(this,nz,hx,lx,mx, el,ss, a)
     use mgbf_kinds, only: dp=>r_kind
     class(mg_parameter_type)::this
     integer,                      intent(in   )::nz, hx,Lx,mx
     real(dp),dimension(nz,Lx:Mx),intent(in   ):: el
     real(dp),dimension(nz, Lx:Mx),intent(in   ):: ss
     real(dp),dimension(nz,lx-hx:mx+hx),intent(inout):: a
   end subroutine
   module subroutine rbeta2T(this,hx,lx,mx, hy,ly,my, el,ss, a)
     use mgbf_kinds, only: dp=>r_kind
     class(mg_parameter_type)::this
     integer,                            intent(in   ):: hx,Lx,mx, hy,ly,my
     real(dp),dimension(2,2,Lx:Mx,Ly:My),intent(in   ):: el
     real(dp),dimension(    Lx:Mx,Ly:My),intent(in   ):: ss
     real(dp),dimension(lx-hx:mx+hx,ly-hy:my+hy),intent(inout):: a
   end subroutine
   module subroutine rbeta3T(this,hx,lx,mx, hy,ly,my, hz,lz,mz, el,ss, a)
     use mgbf_kinds, only: dp=>r_kind
     class(mg_parameter_type)::this
     integer,                                  intent(in   ):: hx,Lx,mx, hy,ly,my, hz,lz,mz
     real(dp),dimension(3,3,Lx:Mx,Ly:My,Lz:Mz),intent(in   ):: el
     real(dp),dimension(    Lx:Mx,Ly:My,Lz:Mz),intent(in   ):: ss
     real(dp),dimension(lx-hx:mx+hx,ly-hy:my+hy,lz-hz:mz+hz),intent(inout):: a
   end subroutine
   module subroutine rbeta4T(this,hx,lx,mx, hy,ly,my, hz,lz,mz, hw,lw,mw, el,ss, a)
     use mgbf_kinds, only: dp=>r_kind
     class(mg_parameter_type)::this
     integer,                                        intent(in   ):: hx,Lx,mx, hy,ly,my, hz,lz,mz, hw,lw,mw
     real(dp),dimension(4,4,Lx:Mx,Ly:My,Lz:Mz,Lw:Mw),intent(in   ):: el
     real(dp),dimension(    Lx:Mx,Ly:My,Lz:Mz,Lw:Mw),intent(in   ):: ss
     real(dp),dimension(lx-hx:mx+hx,ly-hy:my+hy,lz-hz:mz+hz,lw-hw:mw+hw),intent(inout):: a
   end subroutine
   module subroutine vrbeta1(this,nv,hx,lx,mx, el,ss, a)
     use mgbf_kinds, only: dp=>r_kind
     class(mg_parameter_type)::this
     integer,                      intent(in   ):: nv,hx,Lx,mx
     real(dp),dimension(1,1,Lx:Mx),intent(in   ):: el
     real(dp),dimension(    Lx:Mx),intent(in   ):: ss
     real(dp),dimension(nv,lx-hx:mx+hx),intent(inout):: a
   end subroutine
   module subroutine vrbeta2(this,nv,hx,lx,mx, hy,ly,my, el,ss, a)
     use mgbf_kinds, only: dp=>r_kind
     class(mg_parameter_type)::this
     integer,                            intent(in   ):: nv, hx,Lx,mx, hy,ly,my
     real(dp),dimension(2,2,Lx:Mx,Ly:My),intent(in   ):: el
     real(dp),dimension(    Lx:Mx,Ly:My),intent(in   ):: ss
     real(dp),dimension(nv,lx-hx:mx+hx,ly-hy:my+hy),intent(inout):: a
   end subroutine
   module subroutine vrbeta3(this,nv, hx,lx,mx, hy,ly,my, hz,lz,mz, el,ss,a)
     use mgbf_kinds, only: dp=>r_kind
     class(mg_parameter_type)::this
     integer,                                  intent(in   ):: nv, hx,Lx,mx, hy,ly,my, hz,lz,mz
     real(dp),dimension(3,3,Lx:Mx,Ly:My,Lz:Mz),intent(in   ):: el
     real(dp),dimension(    Lx:Mx,Ly:My,Lz:Mz),intent(in   ):: ss
     real(dp),dimension(nv,lx-hx:mx+hx,ly-hy:my+hy,lz-hz:mz+hz),intent(inout):: a
   end subroutine
   module subroutine vrbeta4(this,nv,hx,lx,mx, hy,ly,my, hz,lz,mz, hw,lw,mw, el,ss,a)
     use mgbf_kinds, only: dp=>r_kind
     class(mg_parameter_type)::this
     integer,                                        intent(in   ):: nv, hx,Lx,mx, hy,ly,my, hz,lz,mz, hw,lw,mw
     real(dp),dimension(4,4,Lx:Mx,Ly:My,Lz:Mz,Lw:Mw),intent(in   ):: el
     real(dp),dimension(    Lx:Mx,Ly:My,Lz:Mz,Lw:Mw),intent(in   ):: ss
     real(dp),dimension(nv,lx-hx:mx+hx,ly-hy:my+hy,lz-hz:mz+hz,lw-hw:mw+hw),intent(inout):: a
   end subroutine
   module subroutine vrbeta1T(this,nv, hx,lx,mx, el,ss, a)
     use mgbf_kinds, only: dp=>r_kind
     class(mg_parameter_type)::this
     integer,                      intent(in   ):: nv,hx,Lx,mx
     real(dp),dimension(1,1,Lx:Mx),intent(in   ):: el
     real(dp),dimension(    Lx:Mx),intent(in   ):: ss
     real(dp),dimension(nv,lx-hx:mx+hx),intent(inout):: a
   end subroutine
   module subroutine vrbeta2T(this,nv,hx,lx,mx, hy,ly,my, el,ss, a)
     use mgbf_kinds, only: dp=>r_kind
     class(mg_parameter_type)::this
     integer,                            intent(in   ):: nv, hx,Lx,mx, hy,ly,my
     real(dp),dimension(2,2,Lx:Mx,Ly:My),intent(in   ):: el
     real(dp),dimension(    Lx:Mx,Ly:My),intent(in   ):: ss
     real(dp),dimension(nv,lx-hx:mx+hx,ly-hy:my+hy),intent(inout):: a
   end subroutine
   module subroutine vrbeta3T(this,nv,hx,lx,mx, hy,ly,my, hz,lz,mz, el,ss, a)
     use mgbf_kinds, only: dp=>r_kind
     class(mg_parameter_type)::this
     integer,                                  intent(in   ):: nv, hx,Lx,mx, hy,ly,my, hz,lz,mz
     real(dp),dimension(3,3,Lx:Mx,Ly:My,Lz:Mz),intent(in   ):: el
     real(dp),dimension(    Lx:Mx,Ly:My,Lz:Mz),intent(in   ):: ss
     real(dp),dimension(nv,lx-hx:mx+hx,ly-hy:my+hy,lz-hz:mz+hz),intent(inout):: a
   end subroutine
   module subroutine vrbeta4T(this,nv,hx,lx,mx, hy,ly,my, hz,lz,mz, hw,lw,mw, el,ss, a)
     use mgbf_kinds, only: dp=>r_kind
     class(mg_parameter_type)::this
     integer,                                        intent(in   ):: nv, hx,Lx,mx, hy,ly,my, hz,lz,mz, hw,lw,mw
     real(dp),dimension(4,4,Lx:Mx,Ly:My,Lz:Mz,Lw:Mw),intent(in   ):: el
     real(dp),dimension(    Lx:Mx,Ly:My,Lz:Mz,Lw:Mw),intent(in   ):: ss
     real(dp),dimension(nv,lx-hx:mx+hx,ly-hy:my+hy,lz-hz:mz+hz,lw-hw:mw+hw),intent(inout):: a
   end subroutine
end interface

!+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
contains
!+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

!&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&
subroutine init_mg_parameter(this,inputfilename)
!**********************************************************************!
!                                                                      !
! Initialize ....                                                      !
!                                                                      !
!**********************************************************************!
implicit none
class (mg_parameter_type),target:: this
integer(i_kind):: g
character(*):: inputfilename

! Namelist parameters as local variable
real(r_kind):: mg_ampl01,mg_ampl02,mg_ampl03
real(r_kind):: mg_weig1,mg_weig2,mg_weig3,mg_weig4
integer(i_kind):: mgbf_proc
logical:: mgbf_line
integer(i_kind):: nxPE,nyPE,im_filt,jm_filt
logical:: lquart=.false.,lhelm=.false. !clt what should be the default
logical:: ldelta=.false.
logical:: l_for_localization=.false.
logical:: l_mgbf_inhomogeneous=.false.  

integer(i_kind):: lm_a          ! number of vertical layers in analysis fields
integer(i_kind):: lm            ! number of vertical layers in filter grids
!clthhhreal(r_kind):: coef_normalization(lm_max)=1.0 !normalizaton coefficients
real(r_kind):: coef_normalization(lm_max)=1 !normalizaton coefficients
real(r_kind):: coef_normalization_const=-9999.0 ! constant, if set, this contant will be 
real(r_kind):: dxfmctrl=35000,dyfmctrl=35000  !the control filtering grid intervals corresponding to the contstant horizontal aspect tensor
logical :: l_constant_aspt2 =.true. ! using constant horizontal aspect tensor : ampl02
character(len=256) ::file_coef_normalization="XXXX"
character(len=256) ::dir_coef_normalization="XXXX"
integer(i_kind):: km2           ! number of 2d variables for filtering
integer(i_kind):: km3           ! number of 3d variables for filtering
integer(i_kind):: n_ens=1         ! number of ensemble members
logical :: l_loc=.false.       
logical :: l_filt_g1=.false.            ! logical flag for filtering of generation one
logical :: l_lin_vertical=.false.       ! logical flag for linear interpolation in vertcial
logical :: l_lin_horizontal=.false.     ! logical flag for linear interpolation in horizontal
logical :: l_quad_horizontal=.false.    ! logical flag for quadratic interpolation in horizontal
logical :: l_new_map=.false.            ! logical flag for new mapping between analysis and filter grid
logical :: l_vertical_filter=.true.    ! logical flag for vertical filtering
logical ::  l_anal_sub_of_filt=.false.
logical ::  l_vert_stretched_filtgrid=.false.
!cltlogical :: l_vert_varied_ampl01=.false.  ! true, ampl01 is varied over the vertical analysis levels 
integer(i_kind):: gm_max=4   !clt by defaul

! Global number of data on Analysis grid
integer(i_kind):: nm0        
integer(i_kind):: mm0       

integer(i_kind):: hx,hy,hz
integer(i_kind):: p
logical:: l_mg_weig_readin=.false.
integer(i_kind), parameter       :: nf=20! refinement factor for z grid,used in make_ssgrid
integer(i_kind) :: myunit,i,item,mype,ierr
character*4 :: str_rank
integer :: n_sample_levelsx4normalization
logical :: l_exist
  namelist /parameters_mgbeta/ mg_ampl01,mg_ampl02,mg_ampl03            &
                              ,mg_weig1,mg_weig2,mg_weig3,mg_weig4      &
                              ,hx,hy,hz,p                               &
                              ,mgbf_line,mgbf_proc                      &
                              ,lm_a,lm,coef_normalization               & 
                              ,coef_normalization_const & 
                              ,dir_coef_normalization  &
                              ,file_coef_normalization  &
                              , dxfmctrl,dyfmctrl       & 
                              , l_constant_aspt2        &
                              ,km2,km3                                  &
                              ,n_ens                                    &
                              ,l_loc                                    &
                              ,l_filt_g1                                &
                              ,l_lin_vertical                           &
                              ,l_lin_horizontal                         &
                              ,l_quad_horizontal                        &
                              ,l_new_map                                &
                              ,l_vertical_filter                        &
                              ,l_anal_sub_of_filt                       &
                              ,l_vert_stretched_filtgrid                     &
                              ,l_for_localization,ldelta,lquart,lhelm   &
                              , l_mgbf_inhomogeneous                    &
                              ,gm_max                                   &
                              ,nm0,mm0                                  &
                              ,nxPE,nyPE,im_filt,jm_filt ,              &               
                              l_mg_weig_readin
   
  open(unit=10,file=trim(inputfilename),status='old',action='read')
  read(10,nml=parameters_mgbeta)
  close(unit=10)
!
  allocate(this%zofis(lm))
  allocate(this%isofz(lm_a))
  write(6,*)"thinkdeb999 filgrid is ",l_vert_stretched_filtgrid
  this%l_vert_stretched_filtgrid=l_vert_stretched_filtgrid 
#if 1 
   
  if(lm_a .ne. lm ) then
    write(6,*)'thinkdeb999 l_vert_stretched_filtgrid ',this%l_vert_stretched_filtgrid 
   call convert_vert_varied_aspt 
!in which the mg_ampl01 will be re-defined
  endif
#endif
!-----------------------------------------------------------------
!for safety, copy all namelist loc vars to them of this object
  this%mg_ampl01=mg_ampl01
  this%mg_ampl02=mg_ampl02
  this%mg_ampl03=mg_ampl03            
  this%mg_weig1=mg_weig1
  this%mg_weig2=mg_weig2
  this%mg_weig3=mg_weig3
  this%mg_weig4=mg_weig4
  this%hx=hx
  this%hy=hy
  this%hz=hz
  this%p =p                          
  this%mgbf_line=mgbf_line
  this%mgbf_proc=mgbf_proc          
  this%lm_a=lm_a
  this%lm=lm
  if (coef_normalization_const >0 ) then  ! constant, if set, this contant will be

    if(trim(file_coef_normalization)=="XXXX" .and. trim(dir_coef_normalization)=="XXXX" ) then
      l_exist=.false.
      coef_normalization=coef_normalization_const
    else
      if (trim(dir_coef_normalization) /= "XXXX") then  
         call MPI_COMM_RANK(MPI_COMM_WORLD,mype,ierr)
         write(str_rank, '(I4.4)') mype
         this%mype=mype  
         file_coef_normalization=trim(dir_coef_normalization)//"/profile_subdomain_"//str_rank//".txt"
      endif
         write(6,*)'thinkdeb888 normalization file is ',trim(file_coef_normalization)
         inquire(file=trim(file_coef_normalization),exist=l_exist)
         if(l_exist) then
           open(newunit=myunit,file=trim(file_coef_normalization),status='old',action='read')
             if(trim(dir_coef_normalization) /= "XXXX") then 
 ! to use file slike profiles_out/profile_subdomain_0475.txt
               read(myunit,*)
               read(myunit,*)i,n_sample_levelsx4normalization
               read(myunit,*)
               do i=1,n_sample_levelsx4normalization
                read(myunit,*)
               enddo
                read(myunit,*)
               do i=1,lm_a
                read(myunit,*)item, coef_normalization(i) !notice, the data in the file is reversed already
               enddo
              close (myunit)
             else
              write(6,*)'the normalization profile file is ',trim(file_coef_normalization)
   !clt in the ../covairance/mgbf_covariance_mod.f90 the fldset is reversed in the vertical direction
              open(newunit=myunit,file=trim(file_coef_normalization),status='old',action='read')
                 read(myunit,*)(coef_normalization(i),i=lm_a,1,-1)
              close (myunit)
             endif 
              coef_normalization(1:lm_a)=coef_normalization(1:lm_a)*coef_normalization_const  !re-calc
         else

                 write(6,*)'the normalization profile file does not exist ,stop ',trim(file_coef_normalization)
                 call flush(6)
                 stop
          endif
        endif
  else
     coef_normalization=1.0


  endif




  this%coef_normalization=coef_normalization
  this%dxfmctrl=dxfmctrl; this%dyfmctrl=dyfmctrl 
  write(6,*)'thinkdeb999 readin l_constant_aspt2  ',l_constant_aspt2
  this%l_constant_aspt2 = l_constant_aspt2
  this%km2=km2
  this%km3=km3
  this%n_ens=n_ens
  this%l_loc=l_loc
  this%l_filt_g1=l_filt_g1
  this%l_lin_vertical=l_lin_vertical
  this%l_lin_horizontal=l_lin_horizontal
  this%l_quad_horizontal=l_quad_horizontal
  this%l_new_map=l_new_map
  this%l_vertical_filter=l_vertical_filter
  this%l_anal_sub_of_filt=l_anal_sub_of_filt
!clt  this%l_vert_varied_ampl01=l_vert_varied_ampl01
  this%l_for_localization=l_for_localization
  this%l_mgbf_inhomogeneous = l_mgbf_inhomogeneous
  this%ldelta=ldelta
  this%lquart=lquart
  this%lhelm=lhelm 
  this%nm0=nm0
  this%mm0=mm0    
  this%nxPE=nxPE
  this%nyPE=nyPE
  this%im_filt=im_filt
  this%jm_filt=jm_filt                
  this%nxm = nxPE
  this%nym = nyPE

   this%im = im_filt
   this%jm = jm_filt

!-----------------------------------------------------------------
!
!
! For 168 PES
!
!    nxm = 14
!    nym = 12
!
! For 256 PES
!
!    nxm =  16
!    nym =  16
!
! For 336 PES
!
!    nxm =  28
!    nym =  12
!
! For 448 PES
!
!    nxm =  28
!    nym =  16
!
! For 512 PES
!
!    nxm =  32
!    nym =  16
!
! For 704 PES
!
!    nxm =  32
!    nym =  22
!
! For 768 PES
!
!    nxm =  32
!    nym =  24
!
! For 924 PES
!
!    nxm =  28
!    nym =  33
!
! For 1056 PES
!
!    nxm =  32
!    nym =  33
!
! For 1408 PES
!
!    nxm =  32
!    nym =  44
!
! For 1848 PES
!
!    nxm =  56
!    nym =  33
!
! For 2464 PES
!
!    nxm =  56
!    nym =  44

!
! Define total number of horizontal levels in the case of ensemble
!

  this%km_a = this%km2+this%lm_a*this%km3
!  write(6,*)'thinkdeb255 lm_a,km3,km2 ',this%km2,this%lm_a,this%km3
!  write(6,*)'thinkdeb255 km_a ',this%km_a
  this%km   = this%km2+this%lm  *this%km3

  this%km_a_all = this%km_a * this%n_ens
!  write(6,*)'thinkdeb255 km_a_all ',this%km_a_all
  this%km_all   = this%km   * this%n_ens

  this%km2_all = this%km2 * this%n_ens
  this%km3_all = this%km3 * this%n_ens

  this%km_4  = this%km/4
  this%km_16 = this%km/16
  this%km_64 = this%km/64
  this%l_mg_weig_readin=l_mg_weig_readin

!
! Define maximum number of generations 'gm'
!

  call def_maxgen(this%nxm,this%nym,this%gm)

! Restrict to gm_max

  if(this%gm>gm_max) then
    this%gm=gm_max
  endif
  if(this%nxm*this%nym<=1) then
    this%gm=gm_max
  endif
!  write(6,*)"thindkeb888 gm is ",this%gm

!***
!***     Analysis grid
!***

!
! Number of grid intervals on GSI grid for the reduced RTMA domain
! before padding 
!
!clt  this%nA_max0 = 1792
!clt  this%mA_max0 = 1056

!
! Number of grid points on the analysis grid after padding
!
  this%nm = this%nm0/this%nxm
  this%mm = this%mm0/this%nym
  this%dx_a2f_ratio=this%nm/this%im_filt
  this%dy_a2f_ratio=this%mm/this%jm_filt
  if(this%l_anal_sub_of_filt ) then
    if(this%im_filt.ne.this%nm.or.this%jm_filt.ne.this%mm) then
       write(6,*)'l_anal_sub_of_filter is true but the numbers of analysis/filtering grids are wrong, stop'
       stop 
    endif
    if(l_lin_horizontal.or.l_quad_horizontal) then
       write(6,*)'l_anal_sub_of_filter is true,now, only work for lsqr, stop'
       stop
    endif
  endif

!***
!***     Filter grid
!***

!    im =  nm
!    jm =  mm

!
! For 168 PES
!
!    im = 120
!    jm =  80
!
! For 256 PES
!
!    im = 96
!    jm = 64
!
!    im = 88
!    jm = 56
!
! For 336 PES
!
!    im = 56
!    jm = 80
!
! For 448 PES
!
!    im = 56  
!    jm = 64
!
! For 512 PES
!
!    im = 48
!    jm = 64
!
! For 704 PES
!
!    im = 48  
!    jm = 40
!
! For 768 PES
!
!    im = 48
!    jm = 40
!
! For 924 PES
!
!    im = 56
!    jm = 24
!
! For 1056 PES
!
!    im = 48
!    jm = 24
!
! For 1408 PES
!
!    im = 48
!    jm = 20
!
! For 1848 PES
!
!    im = 28
!    jm = 24
!
! For 2464 PES
!
!    im = 28
!    jm = 20

  this%im00 = this%nxm*this%im
  this%jm00 = this%nym*this%jm

  this%n0 = 1 
  this%m0 = 1 

  this%i0 = 1
  this%j0 = 1

!
! Make sure that nm0 and mm0 and divisibvle with nxm and nym
!
  if(this%nm*this%nxm /= this%nm0 ) then
    write(17,*) 'nm,nxm,nm0=',this%nm,this%nxm,this%nm0
    stop 'nm0 is not divisible by nxm'
  endif
  
  if(this%mm*this%nym /= this%mm0 ) then
    write(17,*) 'mm,nym,mm0=',this%mm,this%nym,this%mm0
    stop 'mm0 is not divisible by nym'
  endif

!
! Set number of processors at higher generations
!

  write(6,*)'thinkdeb999 2 8 ',this%l_vert_stretched_filtgrid  ,' ',"l_use",this%l_vert_stretched_filtgrid
  call flush(6)
  allocate(this%ixm(this%gm))
  allocate(this%jym(this%gm))
  allocate(this%nxy(this%gm))
  allocate(this%maxpe_fgen(0:this%gm))
  allocate(this%im0(this%gm))
  allocate(this%jm0(this%gm))
  allocate(this%Fimax(this%gm))
  allocate(this%Fjmax(this%gm))
  allocate(this%FimaxL(this%gm))
  allocate(this%FjmaxL(this%gm))

  call def_ngens(this%ixm,this%gm,this%nxm)
  call def_ngens(this%jym,this%gm,this%nym)

  write(6,*)'thinkdeb999 2 9 ',this%l_vert_stretched_filtgrid  ,' ',"l_use",this%l_vert_stretched_filtgrid
  call flush(6)
!$omp parallel do private(g) schedule(static)
  do g=1,this%gm
    this%nxy(g)=this%ixm(g)*this%jym(g)
  enddo
!$omp end parallel do

    this%maxpe_fgen(0)= 0
  do g=1,this%gm
    this%maxpe_fgen(g)=this%maxpe_fgen(g-1)+this%nxy(g)
  enddo

    this%maxpe_filt=this%maxpe_fgen(this%gm)
    this%npes_filt=this%maxpe_filt-this%nxy(1)

    this%im0(1)=this%im00
  do g=2,this%gm
    this%im0(g)=this%im0(g-1)/2
  enddo

    this%jm0(1)=this%jm00
  do g=2,this%gm
    this%jm0(g)=this%jm0(g-1)/2
  enddo

!$omp parallel do private(g) schedule(static)
  do g=1,this%gm
    this%Fimax(g)=this%im0(g)-this%im*(this%ixm(g)-1)
    this%Fjmax(g)=this%jm0(g)-this%jm*(this%jym(g)-1)
  enddo
!$omp end parallel do

!$omp parallel do private(g) schedule(static)
  do g=1,this%gm
    this%FimaxL(g)=this%Fimax(g)/2
    this%FjmaxL(g)=this%Fjmax(g)/2
  enddo
!$omp end parallel do

!***
!*** Filter related parameters
!**
  this%lengthx = 1.*this%nm     ! arbitrary chosen scale of the domain
  this%lengthy = 1.*this%mm     ! arbitrary chosen scale of the domain

  this%ib=6
  this%jb=6

  this%dxa =this%lengthx/this%nm
  this%dxf = this%lengthx/this%im
  allocate(this%dxfm(this%im,this%jm))
  this%nb = 2*this%dxf/this%dxa

  this%dya = this%lengthy/this%mm
  this%dyf = this%lengthy/this%jm
  allocate(this%dyfm(this%im,this%jm))
  this%mb = 2*this%dyf/this%dya

  this%xa0 = this%dxa*0.5
  this%ya0 = this%dya*0.5

  this%xf0 = this%dxf*0.5
  this%yf0 = this%dyf*0.5

  this%imL=this%im/2
  this%jmL=this%jm/2

  this%imH=this%im0(this%gm)
  this%jmH=this%jm0(this%gm)
  this%pasp01 = mg_ampl01
  this%pasp02 = mg_ampl02
  this%pasp03 = mg_ampl03

  this%nh= max(hx,hy,hz)
  this%nfil = this%nh + 2

  this%pee2=this%p*2
  this%rmom2_1=u1/sqrt(this%pee2+3)
  this%rmom2_2=u1/sqrt(this%pee2+4)
  this%rmom2_3=u1/sqrt(this%pee2+5)
  this%rmom2_4=u1/sqrt(this%pee2+6)
#if 1 

  write(6,*)'thinkdeb999 2 10 ',this%l_vert_stretched_filtgrid  ,' ',"l_use",this%l_vert_stretched_filtgrid
  call flush(6)
contains

subroutine convert_vert_varied_aspt

  integer(i_kind) :: lm_tmp,iz,is,mype,ierr
  real(r_kind)::sstop,dss
  real (r_kind),allocatable,dimension(:)::sigofz
  real (r_kind),allocatable,dimension(:)::sigofis
  integer(i_kind):: user_mpi_real
  real (r_kind) :: mg_ampl01_org
  
  if( .not. allocated(this%aspect_vert_profile_angrid )) then 
           allocate(this%aspect_vert_profile_angrid(lm_a),this%aspect_vert_profile_filtgrid(lm))
  endif
  allocate(sigofz(lm_a),sigofis(lm))
  call MPI_COMM_RANK(MPI_COMM_WORLD,mype,ierr)
  write(6,*)'thinkdeb999 2.0 ',this%l_vert_stretched_filtgrid  ,' ',"l_use",this%l_vert_stretched_filtgrid
  call flush(6)
  if(this%l_vert_stretched_filtgrid) then 
      if(mype.eq.0) then 
        open(newunit=myunit,file="mgbf_vert_aspt_profile.txt",status='old',iostat=ierr)
        if(ierr /= 0) error stop "wrong with open file mgbf_vert_aspt_profile.txt ,stop"
        read(myunit,*)lm_tmp 
        if(lm_tmp.ne.lm_a) then 
          error stop " the lm_a is not the same as the size in mgbf_vert_aspt_profile.txt, stop"
        endif
        do i=1,lm_a
          read(myunit,*)this%aspect_vert_profile_angrid(i)
        enddo
       close(myunit)
      endif 
      call MPI_Type_match_size(MPI_TYPECLASS_REAL, kind(this%aspect_vert_profile_angrid(1)), user_mpi_real, ierr)
      if (ierr /= MPI_SUCCESS) then
        write(6,*) "ERROR: No matching MPI type for real kind =", kind(this%aspect_vert_profile_angrid(1))
        call MPI_Abort(MPI_COMM_WORLD, 1, ierr)
      endif
      call MPI_Bcast(this%aspect_vert_profile_angrid, lm_a, user_mpi_real, 0, MPI_COMM_WORLD, ierr)
     
   !   nz=lm_a-1
   !   ns=lm-1
       
   ! calibrate sigscale to make sigofz go to sigbottom at z=0:
         sigofz=sqrt(this%aspect_vert_profile_angrid)
         if(mype==0) then
         do iz=lm_a,1,-1
         write(6,*)iz,sigofz(iz)
         enddo
         endif
  else
  write(6,*)'thinkdeb999 2 0.1 ',this%l_vert_stretched_filtgrid  ,' '
  call flush(6)
      sigofz=sqrt(mg_ampl01)
      
  endif 
   
! Make the new grid whose resolution of the correlation scale sigofz
! is uniform throughout.
! isofz is the s-index coordinate of each of the original z-grid points.
! zofis is the z-index coordinate of each of the new s-grid points.
!cltorg     call make_ssgrid(nz,nf,ns,sigofz, sstop,dss,isofz,zofis)
    call make_ssgrid(lm_a-1,nf,lm-1,sigofz, sstop,dss,this%isofz,this%zofis)

! Use the new s-grid locations zofis, and the original profile of
! correlation scales sigofz, to interpolate, smoothly and positively,
! these scales sig to each of the new s-grid points:
!clt    call logintgrid(nz,ns,zofis,sigofz,sigofis)
    call zsigtossig(lm_a-1,nf,lm-1,this%zofis,sigofz,sigofis)
       mg_ampl01_org=mg_ampl01
       mg_ampl01=(sum(sigofis**2)/size(sigofis))
    if(.not.this%l_vert_stretched_filtgrid) then !the former could be only true when the latter is in effect
       write(6,*)' suggested and actual/original ampl01 is ',mg_ampl01,' ' ,mg_ampl01_org
       mg_ampl01=mg_ampl01_org
    endif
       write(6,*)' the original and final  ampl01 is ',mg_ampl01_org,' ' ,mg_ampl01
      
    do is=1,lm
      write(6,*)is,this%zofis(is),(sigofis(is))**2
    enddo
    if(mype==6) then
      open(newunit=myunit,file="converted_mgbf_vert_aspt_profile.txt",status='replace')
     do is=1,lm
      write(myunit,*)is,this%zofis(is),(sigofis(is))**2
     enddo
     close(myunit)
    endif
!clt    if(this%l_2dvar_last_vertical_level == .true. ) then !the fieldset passed into mgbf will be top-down,so
!clttodo need to access this from mgbf lib too     
     this%zofis=this%zofis(lm:1:-1)

!#   endif 

  

  deallocate(sigofz,sigofis)
end subroutine convert_vert_varied_aspt

#endif
  

!----------------------------------------------------------------------
end subroutine init_mg_parameter

!&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&
subroutine def_maxgen &
!**********************************************************************
!                                                                     !
!  Given number of PEs in x and y direction decides what is the       !
!  maximum number of generations that a multigrid scheme can support  !
!                                                                     !
!                                                    M. Rancic 2020   !
!**********************************************************************
(nxm,nym,gm)
!----------------------------------------------------------------------
implicit none
integer, intent(in):: nxm,nym
integer, intent(out):: gm
integer:: npx,npy,gx,gy

   npx = nxm;  gx=1
   Do 
     npx = (npx + 1)/2
     gx = gx + 1
     if(npx == 1) exit
   end do

   npy = nym;  gy=1
   Do 
     npy = (npy + 1)/2
     gy = gy + 1
     if(npy == 1) exit
   end do

   gm = Min(gx,gy)


!----------------------------------------------------------------------
endsubroutine def_maxgen

!&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&
subroutine def_ngens &
!*********************************************************************!
!                                                                     !
!  Given number of generations, find number of PEs is s direction     !
!                                                                     !
!                                                    M. Rancic 2020   !
!*********************************************************************!
(nsm,gm,nsm0)
!----------------------------------------------------------------------
implicit none
integer, intent(in):: gm,nsm0
integer, dimension(gm), intent(out):: nsm
integer:: g
!----------------------------------------------------------------------

     nsm(1)=nsm0
   Do g=2,gm
     nsm(g) = (nsm(g-1) + 1)/2
   end do

!----------------------------------------------------------------------
endsubroutine def_ngens

!+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
end module mg_parameter
