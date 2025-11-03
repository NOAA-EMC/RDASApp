submodule(mg_intstate) mg_transfer 
!$$$  submodule documentation block
!                .      .    .                                       .
! module:   mg_transfer
!   prgmmr: rancic           org: NOAA/EMC            date: 2021
!
! abstract:  Transfer data between analysis and filter grid
!
! module history log:
!   2023-04-19  lei     - object-oriented coding
!   2024-01-11  rancic  - optimization for ensemble localization
!   2024-02-20  yokota  - refactoring to apply for GSI
!
! Subroutines Included:
!   anal_to_filt_allmap -
!   filt_to_anal_allmap -
!   anal_to_filt_all -
!   filt_to_anal_all -
!   anal_to_filt_all2 -
!   filt_to_anal_all2 -
!   stack_to_composite -
!   composite_to_stack -
!   S2C_ens -
!   C2S_ens -
!   anal_to_filt -
!   filt_to_anal -
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
use mg_timers
use mgbf_kinds, only: r_kind,i_kind
use mgbf_utils,only : contains_nonzero
use phint1

!+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
contains
!+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

!&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&
module subroutine anal_to_filt_allmap(this,WORKA)
!***********************************************************************
!                                                                      !
!  Transfer data from analysis to first generaton of filter grid       !
!                                                                      !
!***********************************************************************
implicit none
class(mg_intstate_type),target::this
real(r_kind):: WORKA(this%km_a_all,1:this%nm,1:this%mm)
include "type_parameter_locpointer.inc"
include "type_intstat_locpointer.inc"
include "type_parameter_point2this.inc"
include "type_intstat_point2this.inc"
!----------------------------------------------------------------------
! write(6,*)'thinkdeb in mg_transfer ',km_a_all, km_all,nm,im,mm,jm
!clttothink if(km_a_all==km_all.and.nm==im.and.mm==jm) then
!cltothink   VALL=0.
!clttohink   VALL(1:km_all,1:im,1:jm)=WORKA
!clttothinkelseif(l_new_map) then
!clttothink   call this%anal_to_filt_all2(WORKA)
!cltothinkelse
   call this%anal_to_filt_all(WORKA)
! write(6,*)'thinkdeb in mg_transfer after anal_to_filt ',l_new_map
!cltothinkendif
!----------------------------------------------------------------------
endsubroutine anal_to_filt_allmap

!&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&
module subroutine filt_to_anal_allmap(this,WORKA)
!***********************************************************************
!                                                                      !
!  Transfer data from filter to analysis grid                          !
!                                                                      !
!***********************************************************************
implicit none
class(mg_intstate_type),target::this
real(r_kind):: WORKA(this%km_a_all,1:this%nm,1:this%mm)
include "type_parameter_locpointer.inc"
include "type_intstat_locpointer.inc"
include "type_parameter_point2this.inc"
include "type_intstat_point2this.inc"
!----------------------------------------------------------------------
!write(6,*)'filt_toanal_allmap ',km_a_all,' ',km_all,' ',nm,' ',im,' ',mm,' ',jm
!cltothink if(km_a_all==km_all.and.nm==im.and.mm==jm) then
!clttothink    WORKA=VALL(1:km_all,1:im,1:jm)
!clttothink   VALL=0.
!cltothink elseif(l_new_map) then
!cltothink   call this%filt_to_anal_all2(WORKA)
!clttothink else
   call this%filt_to_anal_all(WORKA)
!cltthink endif
!----------------------------------------------------------------------
endsubroutine filt_to_anal_allmap

!&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&
module subroutine anal_to_filt_all(this,WORKA)
!***********************************************************************
!                                                                      !
!  Transfer data from analysis to first generaton of filter grid       !
!                                                                      !
!***********************************************************************
implicit none
class(mg_intstate_type),target::this
real(r_kind):: WORKA(this%km_a_all,1:this%nm,1:this%mm)
real(r_kind),allocatable,dimension(:,:,:,:):: A3D
real(r_kind),allocatable,dimension(:,:,:,:):: F3D
real(r_kind),allocatable,dimension(:,:,:):: WORK
integer(i_kind):: L
integer(i_kind):: ivar,lev1_a,lev2_a,lev1_f,lev2_f
include "type_parameter_locpointer.inc"
include "type_intstat_locpointer.inc"
include "type_parameter_point2this.inc"
include "type_intstat_point2this.inc"
!----------------------------------------------------------------------
allocate(WORK(km_all,1:nm,1:mm))
allocate(A3D(km3_all,1:nm,1:mm,lm_a))
allocate(F3D(km3_all,1:nm,1:mm,lm))
!tothink

                                                 call btim(an2filt_tim)
if(2.gt.3) then
     call this%S2C_ens(WORKA,A3D,1,nm,1,mm,lm_a,km_a,km_a_all)
  if(lm_a>lm) then
    if(l_lin_vertical) then
       call this%l_vertical_adjoint_spec(km3_all,lm_a,lm,1,nm,1,mm,A3D,F3D)
    else
       call this%lwq_vertical_adjoint_spec(km3_all,lm_a,lm,1,nm,1,mm,               &
                                      cvf1,cvf2,cvf3,cvf4,lref,A3D,F3D)
    endif
  else
!clttothink

    do L=1,lm
      F3D(:,:,:,L)=A3D(:,:,:,L)
    enddo

  endif

      call this%C2S_ens(F3D,WORK,1,nm,1,mm,lm,km,km_all)
endif !2.gt.3 
     if(lm_a>lm) then
      do ivar=1,this%km2 !2dvar is directly passed
        work(this%km_all-ivar+1,:,:)=worka(this%km_all-ivar+1,:,:)
      enddo
      
      do ivar=1,this%km3
         lev1_a=1+(ivar-1)*this%lm_a
         lev1_f=1+(ivar-1)*this%lm
         lev2_a=lev1_a+this%lm_a-1
         lev2_f=lev1_f+this%lm-1
        
!clt        call this%lwq_vertical_adjoint(nm_in,km_in,imin,imax,jmin,jmax,c1,c2,c3,c4,kref,w,f)
!cltorg        call this%lwq_vertical_adjoint(this%lm_a,this%lm,1,nm,1,mm,this%cvf1,this%cvf2,this%cvf3,this%cvf4,this%lref,  &
!clt             worka(lev1_a:lev2_a,:,:),work(lev1_f:lev2_f,:,:))
!#        if (this%l_vert_stretched_filtgrid) then
!        write(6,*)'thinkdeb999 l_vert_stretched_filtgrid 2 is ',this%l_vert_stretched_filtgrid
  
          call intgrid_f2a_3d_ad_top2bot_fast(this%lm_a-1,this%lm-1,nm,mm,this%zofis,worka(lev1_a:lev2_a,:,:),work(lev1_f:lev2_f,:,:))
!        else
!          call this%test_vertical_interpolation_adj(this%lm,this%lm_a,1,nm,1,mm, work(lev1_f:lev2_f,:,:), &
!             worka(lev1_a:lev2_a,:,:))
!        endif
       enddo
      else
        work=worka
      endif
!clt      call this%anal_to_filt(WORKA)
      call this%anal_to_filt(WORK)
                                                 call etim(an2filt_tim)

deallocate(A3D,F3D,WORK)
!----------------------------------------------------------------------
endsubroutine anal_to_filt_all

!&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&
module subroutine filt_to_anal_all(this,WORKA)
!***********************************************************************
!                                                                      !
!  Transfer data from filter to analysis grid                          !
!                                                                      !
!***********************************************************************
implicit none
class(mg_intstate_type),target::this
real(r_kind):: WORKA(this%km_a_all,1:this%nm,1:this%mm)
real(r_kind),allocatable,dimension(:,:,:,:):: A3D
real(r_kind),allocatable,dimension(:,:,:,:):: F3D
real(r_kind),allocatable,dimension(:,:,:):: WORK
integer(i_kind):: L
integer(i_kind)::ivar, lev1_a,lev2_a,lev1_f,lev2_f

include "type_parameter_locpointer.inc"
include "type_intstat_locpointer.inc"
include "type_parameter_point2this.inc"
include "type_intstat_point2this.inc"
!----------------------------------------------------------------------
     allocate(WORK(km_all,1:nm,1:mm))
    call this%filt_to_anal(WORK)  !cltadded
     if(lm_a>lm) then
      do ivar=1,this%km2 !2dvar is directly passed
        worka(this%km_a_all-ivar+1,:,:)=work(this%km_all-ivar+1,:,:)
      enddo
      
      do ivar=1,this%km3
         lev1_a=1+(ivar-1)*this%lm_a
         lev1_f=1+(ivar-1)*this%lm
         lev2_a=lev1_a+this%lm_a-1
         lev2_f=lev1_f+this%lm-1
!clt        call this%lwq_vertical_direct(this%lm,this%lm_a,1,nm,1,mm,this%cvf1,this%cvf2,this%cvf3,this%cvf4,this%lref,  &
!clt             work(lev1_f:lev2_f,:,:),worka(lev1_a:lev2_a,:,:))
!        if (this%l_vert_stretched_filtgrid) then
          call intgrid_f2a_3d_top2bot_fast(this%lm_a-1,this%lm-1,nm,mm,this%zofis,worka(lev1_a:lev2_a,:,:),work(lev1_f:lev2_f,:,:))
!        else
!        call this%test_vertical_interpolation(this%lm,this%lm_a,1,nm,1,mm, work(lev1_f:lev2_f,:,:), &
!             worka(lev1_a:lev2_a,:,:))
!        endif
       enddo
      else
        worka=work
      endif
    deallocate(WORK)
!----------------------------------------------------------------------
endsubroutine filt_to_anal_all

!&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&
module subroutine anal_to_filt_all2(this,WORKA)
!***********************************************************************
!                                                                      !
!  Transfer data from analysis to first generaton of filter grid       !
!                                                                      !
!***********************************************************************
implicit none
class(mg_intstate_type),target::this
real(r_kind):: WORKA(this%km_a_all,1:this%nm,1:this%mm)
real(r_kind),allocatable,dimension(:,:,:):: WORK
include "type_parameter_locpointer.inc"
include "type_intstat_locpointer.inc"
include "type_parameter_point2this.inc"
include "type_intstat_point2this.inc"
!----------------------------------------------------------------------
allocate(WORK(km_all,1:nm,1:mm))

                                                 call btim(an2filt_tim)
  if(lm_a>lm) then
     call this%l_vertical_adjoint_spec2(km3*n_ens,lm_a,lm,1,nm,1,mm,WORKA,WORK)
  else
     WORK = WORKA
  endif

     call this%anal_to_filt(WORK)
                                                 call etim(an2filt_tim)

deallocate(WORK)
!----------------------------------------------------------------------
endsubroutine anal_to_filt_all2

!&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&
module subroutine filt_to_anal_all2(this,WORKA)
!***********************************************************************
!                                                                      !
!  Transfer data from filter to analysis grid                          !
!                                                                      !
!***********************************************************************
implicit none
class(mg_intstate_type),target::this
real(r_kind):: WORKA(this%km_a_all,1:this%nm,1:this%mm)
real(r_kind),allocatable,dimension(:,:,:):: WORK
include "type_parameter_locpointer.inc"
include "type_intstat_locpointer.inc"
include "type_parameter_point2this.inc"
include "type_intstat_point2this.inc"
!----------------------------------------------------------------------
allocate(WORK(km_all,1:nm,1:mm))

                                                 call btim(filt2an_tim)
    call this%filt_to_anal(WORK)

  if(lm_a>lm) then
     call this%l_vertical_direct_spec2(km3*n_ens,lm,lm_a,1,nm,1,mm,WORK,WORKA)
  else
     WORKA = WORK
  endif
                                                 call etim(filt2an_tim)

deallocate(WORK)
!----------------------------------------------------------------------
endsubroutine filt_to_anal_all2

!&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&
module subroutine stack_to_composite &
!***********************************************************************
!                                                                      !
!  Transfer data from stack to composite variables                     !
!                                                                      !
!***********************************************************************
(this,ARR_ALL,A2D,A3D)
!----------------------------------------------------------------------
implicit none
class(mg_intstate_type),target::this
real(r_kind),dimension(this%km ,1-this%hx:this%im+this%hx,1-this%hy:this%jm+this%hy),   intent(in):: ARR_ALL
real(r_kind),dimension(this%km3,1-this%hx:this%im+this%hx,1-this%hy:this%jm+this%hy,this%lm),intent(out):: A3D
real(r_kind),dimension(this%km2,1-this%hx:this%im+this%hx,1-this%hy:this%jm+this%hy)   ,intent(out):: A2D
integer(i_kind):: i,j,k,L
include "type_parameter_locpointer.inc"
include "type_intstat_locpointer.inc"
include "type_parameter_point2this.inc"
include "type_intstat_point2this.inc"
!----------------------------------------------------------------------
    do L=1,lm
      do j=1-hy,jm+hy
      do i=1-hx,im+hx
        do k=1,km3
          A3D(k,i,j,L)=ARR_ALL( (k-1)*lm+L,i,j )
        enddo
      enddo
      enddo
    enddo

        do k=1,km2
          A2D(k,:,:)=ARR_ALL(km3*lm+k,:,:)
        enddo 

!----------------------------------------------------------------------
endsubroutine stack_to_composite

!&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&
module subroutine composite_to_stack &
!***********************************************************************
!                                                                      !
!  Transfer data from composite to stack variables                     !
!                                                                      !
!***********************************************************************
(this,A2D,A3D,ARR_ALL)
!----------------------------------------------------------------------
implicit none
class(mg_intstate_type),target::this
real(r_kind),dimension(this%km2,1-this%hx:this%im+this%hx,1-this%hy:this%jm+this%hy),   intent(in):: A2D
real(r_kind),dimension(this%km3,1-this%hx:this%im+this%hx,1-this%hy:this%jm+this%hy,this%lm),intent(in):: A3D
real(r_kind),dimension(this%km ,1-this%hx:this%im+this%hx,1-this%hy:this%jm+this%hy),   intent(out):: ARR_ALL
integer(i_kind):: i,j,k,L
include "type_parameter_locpointer.inc"
include "type_intstat_locpointer.inc"
include "type_parameter_point2this.inc"
include "type_intstat_point2this.inc"
!----------------------------------------------------------------------
    do L=1,lm
      do j=1-hy,jm+hy
      do i=1-hx,im+hx
        do k=1,km3
          ARR_ALL( (k-1)*lm+L,i,j )=A3D(k,i,j,L)
        enddo
      enddo
      enddo
    enddo

        do k=1,km2
          ARR_ALL(km3*lm+k,:,:)=A2D(k,:,:)
        enddo 

!----------------------------------------------------------------------
endsubroutine composite_to_stack 

!&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&
module subroutine S2C_ens &
!***********************************************************************
!                                                                      !
! General transfer data from stack to composite variables for ensemble !
!                                                                      !
!***********************************************************************
(this,ARR_ALL,A3D,imn,imx,jmn,jmx,lmx,kmx,kmx_all)
!----------------------------------------------------------------------
implicit none
class(mg_intstate_type),target::this
integer, intent(in):: imn,imx,jmn,jmx,lmx,kmx,kmx_all
real(r_kind),dimension(kmx_all,imn:imx,jmn:jmx)    ,intent(in):: ARR_ALL
real(r_kind),dimension(this%km3_all,imn:imx,jmn:jmx,lmx),intent(out):: A3D
integer(i_kind):: i,j,k,L
integer(i_kind):: n,n_inc
include "type_parameter_locpointer.inc"
include "type_intstat_locpointer.inc"
include "type_parameter_point2this.inc"
include "type_intstat_point2this.inc"
!----------------------------------------------------------------------
  do n=1,n_ens
    n_inc = kmx*(n-1)

    do L=1,lmx
      do j=jmn,jmx
      do i=imn,imx
        do k=1,km3
          A3D(km3*(n-1)+k,i,j,L)=ARR_ALL(n_inc+(k-1)*lmx+L,i,j)
        enddo
      enddo
      enddo
    enddo

  enddo
!----------------------------------------------------------------------
endsubroutine S2C_ens

!&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&
module subroutine C2S_ens &
!***********************************************************************
!                                                                      !
! General transfer data from composite to stack variables for ensemble !
!                                                                      !
!***********************************************************************
(this,A3D,ARR_ALL,imn,imx,jmn,jmx,lmx,kmx,kmx_all)
!----------------------------------------------------------------------
implicit none
class(mg_intstate_type),target::this
integer, intent(in):: imn,imx,jmn,jmx,lmx,kmx,kmx_all
real(r_kind),dimension(this%km3_all,imn:imx,jmn:jmx,lmx),intent(in):: A3D
real(r_kind),dimension(kmx_all,imn:imx,jmn:jmx)    ,intent(out):: ARR_ALL
integer(i_kind):: i,j,k,L
integer(i_kind):: n,n_inc
include "type_parameter_locpointer.inc"
include "type_intstat_locpointer.inc"
include "type_parameter_point2this.inc"
include "type_intstat_point2this.inc"
!----------------------------------------------------------------------
  do n=1,n_ens
    n_inc = kmx*(n-1)

     do L=1,lmx
       do j=jmn,jmx
       do i=imn,imx
         do k=1,km3
           ARR_ALL(n_inc+(k-1)*lmx+L,i,j )= A3D(km3*(n-1)+k,i,j,L)
         enddo
       enddo
       enddo
     enddo

  enddo
!----------------------------------------------------------------------
endsubroutine C2S_ens

!&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&
module subroutine anal_to_filt(this,WORK)
!***********************************************************************
!                                                                      !
!  Transfer data from analysis to first generaton of filter grid       !
!                                                                      !
!***********************************************************************
implicit none
class(mg_intstate_type),target::this
real(r_kind):: WORK(this%km_all,1:this%nm,1:this%mm)
integer(i_kind):: ibm,jbm
include "type_parameter_locpointer.inc"
include "type_intstat_locpointer.inc"
include "type_parameter_point2this.inc"
include "type_intstat_point2this.inc"
!----------------------------------------------------------------------
       VALL=0.
!clttothink
!clttothink
     if(.not.this%l_anal_sub_of_filt) then
          if(l_lin_horizontal) then
            ibm=1
            jbm=1
            call this%lin_adjoint_offset(WORK,VALL(1:km_all,1-ibm:im+ibm,1-jbm:jm+jbm),km_all,ibm,jbm)
          elseif(l_quad_horizontal) then
            ibm=2
            jbm=2
            call this%quad_adjoint_offset(WORK,VALL(1:km_all,1-ibm:im+ibm,1-jbm:jm+jbm),km_all,ibm,jbm)
          else
            ibm=3
            jbm=3
            call this%lsqr_adjoint_offset(WORK,VALL(1:km_all,1-ibm:im+ibm,1-jbm:jm+jbm),km_all,ibm,jbm)
          endif
     else
            ibm=3
            jbm=3
          VALL(1:km_all,1:im,1:jm)=WORK
 !clt         call this%lin_adjoint_offset(WORK,VALL(1:km_all,1-ibm:im+ibm,1-jbm:jm+jbm),km_all,ibm,jbm)

     endif
!***
!***  Apply adjoint lateral bc on PKF and WKF
!***
!cltthinkdeb555
!clt     if(.not.this%l_anal_sub_of_filt) then
         call this%bocoT_2d(VALL(1:km_all,1-ibm:im+ibm,1-jbm:jm+jbm),km_all,im,jm,ibm,jbm)
 !clt    endif 

!----------------------------------------------------------------------
endsubroutine anal_to_filt

!&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&
module subroutine filt_to_anal(this,WORK)
!***********************************************************************
!                                                                      !
!  Transfer data from filter to analysis grid                          !
!                                                                      !
!***********************************************************************
implicit none
class(mg_intstate_type),target::this
real(r_kind):: WORK(this%km_all,1:this%nm,1:this%mm)
integer(i_kind):: ibm,jbm
include "type_parameter_locpointer.inc"
include "type_intstat_locpointer.inc"
include "type_parameter_point2this.inc"
include "type_intstat_point2this.inc"
!----------------------------------------------------------------------

       if(l_lin_horizontal) then
         ibm=1
         jbm=1
       elseif(l_quad_horizontal) then
         ibm=2
         jbm=2
       else
         ibm=3
         jbm=3
       endif

!***
!***  Supply boundary conditions for VALL
!***
!cltthinkdeb255
!   if(.not.this%l_anal_sub_of_filt) then
         call this%boco_2d(VALL(1:km_all,1-ibm:im+ibm,1-jbm:jm+jbm),km_all,im,jm,ibm,jbm)
!   endif
   if(this%l_anal_sub_of_filt) then
       WORK(:,:,:)=VALL(:,1:im,1:jm)
!cltorg       call this%lin_direct_offset_add(VALL(1:km_all,1-ibm:im+ibm,1-jbm:jm+jbm),WORK,km_all,ibm,jbm)
   else
       if(l_lin_horizontal) then
         call this%lin_direct_offset(VALL(1:km_all,1-ibm:im+ibm,1-jbm:jm+jbm),WORK,km_all,ibm,jbm)
       elseif(l_quad_horizontal) then
         call this%quad_direct_offset(VALL(1:km_all,1-ibm:im+ibm,1-jbm:jm+jbm),WORK,km_all,ibm,jbm)
       else
         call this%lsqr_direct_offset(VALL(1:km_all,1-ibm:im+ibm,1-jbm:jm+jbm),WORK,km_all,ibm,jbm)
       endif
   endif

!----------------------------------------------------------------------
endsubroutine filt_to_anal

!+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
end submodule mg_transfer
