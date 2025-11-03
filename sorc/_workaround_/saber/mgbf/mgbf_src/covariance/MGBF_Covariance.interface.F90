! (C) Copyright 2022 United States Government as represented by the Administrator of the National
!     Aeronautics and Space Administration
!
! This software is licensed under the terms of the Apache Licence Version 2.0
! which can be obtained at http://www.apache.org/licenses/LICENSE-2.0.

module mgbf_covariance_interface_mod

! iso
use iso_c_binding

! atlas
use atlas_module,               only: atlas_functionspace, atlas_fieldset

! fckit
use fckit_mpi_module,           only: fckit_mpi_comm
use fckit_configuration_module, only: fckit_configuration

! saber
use mgbf_covariance_mod,         only: mgbf_covariance
use mg_timers


implicit none
private
public mgbf_covariance_registry


! --------------------------------------------------------------------------------------------------
#define LIST_KEY_TYPE c_int
#define LISTED_TYPE mgbf_covariance

!> Linked list interface - defines registry_t type
!clt #include "saber/external/tools_linkedlist_interface.fypp"
#include "tlei_tools_linkedlist_interface.fypp"

!> Global registry

type(registry_type) :: mgbf_covariance_registry

! --------------------------------------------------------------------------------------------------

contains

! --------------------------------------------------------------------------------------------------

!> Linked list implementation
!clt #include "saber/external/tools_linkedlist_implementation.fypp"
#include "tlei_tools_linkedlist_implementation.fypp"

! --------------------------------------------------------------------------------------------------

subroutine mgbf_covariance_create_cpp(c_self, c_comm, c_conf, c_bg, c_fg) &
           bind(c, name='mgbf_covariance_create_f90')

! Arguments
integer(c_int),     intent(inout) :: c_self
type(c_ptr), value, intent(in)    :: c_conf
type(c_ptr), value, intent(in)    :: c_comm
type(c_ptr), value, intent(in)    :: c_bg
type(c_ptr), value, intent(in)    :: c_fg

! Locals
type(mgbf_covariance), pointer :: f_self
type(fckit_mpi_comm)          :: f_comm
type(fckit_configuration)     :: f_conf
type(atlas_fieldset)          :: f_bg
type(atlas_fieldset)          :: f_fg

! LinkedList
! ----------
f_comm=fckit_mpi_comm(c_comm)
call mgbf_covariance_registry%init(f_comm)
call mgbf_covariance_registry%add(c_self)
call mgbf_covariance_registry%get(c_self, f_self)

! Fortran APIs
! ------------
f_conf = fckit_configuration(c_conf)
f_comm = fckit_mpi_comm(c_comm)
f_bg = atlas_fieldset(c_bg)
f_fg = atlas_fieldset(c_fg)

! Call implementation
! -------------------
call f_self%create(f_comm, f_conf, f_bg, f_fg)

end subroutine mgbf_covariance_create_cpp

! --------------------------------------------------------------------------------------------------

subroutine mgbf_covariance_delete_cpp(c_self) &
           bind(c, name='mgbf_covariance_delete_f90')

! Arguments
integer(c_int), intent(inout)  :: c_self

! Locals
type(mgbf_covariance), pointer :: f_self

! LinkedList
! ----------
call mgbf_covariance_registry%get(c_self, f_self)
! Call implementation
! -------------------
call f_self%delete()

! LinkedList
! ----------
call mgbf_covariance_registry%remove(c_self)

end subroutine mgbf_covariance_delete_cpp

! --------------------------------------------------------------------------------------------------

subroutine mgbf_covariance_randomize_cpp(c_self, c_inc) &
           bind(c,name='mgbf_covariance_randomize_f90')

implicit none

!Arguments
integer(c_int),     intent(in) :: c_self
type(c_ptr), value, intent(in) :: c_inc

type(mgbf_covariance), pointer :: f_self
type(atlas_fieldset)          :: f_inc

! LinkedList
! ----------
call mgbf_covariance_registry%get(c_self, f_self)

! Fortran APIs
! ------------
f_inc = atlas_fieldset(c_inc)

! Call implementation
! -------------------
call f_self%randomize(f_inc)

end subroutine mgbf_covariance_randomize_cpp

! --------------------------------------------------------------------------------------------------

subroutine mgbf_covariance_multiply_cpp(c_self, c_afieldset,c_index_member_in) &
           bind(c,name='mgbf_covariance_multiply_f90')

implicit none

!Arguments
integer(c_int),     intent(in) :: c_self
integer(c_int),value,    intent(in) :: c_index_member_in
type(c_ptr), value, intent(in) :: c_afieldset

type(mgbf_covariance), pointer :: f_self
type(atlas_fieldset)          :: f_fieldset
integer                       :: index_member_in=0
!cltthink type(fieldset_type)          :: f_fieldset
!write(6,*)'thinkdeb 999 in inteface f90 star'
call flush(6)
call btim(mg_interface_multiply_time)
!write(6,*)'thinkdeb 999 in inteface f90 star0.5 c_index_member_in ',c_index_member_in
call flush(6)
index_member_in=int(c_index_member_in,kind=kind(index_member_in))
!write(6,*)'thinkdeb 999 in inteface f90 star1'
call flush(6)
! LinkedList
! ----------
call btim(mg_interface_registry_get_time)
call mgbf_covariance_registry%get(c_self, f_self)
call etim(mg_interface_registry_get_time)

! Fortran APIs
! ------------
call btim(mg_interface_fldset_time)
f_fieldset = atlas_fieldset(c_afieldset)
call etim(mg_interface_fldset_time)

! Call implementation
! -------------------
!write(6,*)'thinkdeb 999 in inteface f90 star2'
call flush(6)
call f_self%multiply(f_fieldset,index_member_in)
call etim(mg_interface_multiply_time)

end subroutine mgbf_covariance_multiply_cpp

! --------------------------------------------------------------------------------------------------

subroutine mgbf_covariance_multiply_ad_cpp(c_self, c_afieldset) &
           bind(c,name='mgbf_covariance_multiply_ad_f90')

implicit none

!Arguments
integer(c_int),     intent(in) :: c_self
type(c_ptr), value, intent(in) :: c_afieldset

type(mgbf_covariance), pointer :: f_self
type(atlas_fieldset)          :: f_fieldset

! LinkedList
! ----------
call mgbf_covariance_registry%get(c_self, f_self)

! Fortran APIs
! ------------
f_fieldset = atlas_fieldset(c_afieldset)

! Call implementation
! -------------------
call f_self%multiply_ad(f_fieldset)

end subroutine mgbf_covariance_multiply_ad_cpp

! --------------------------------------------------------------------------------------------------

end module mgbf_covariance_interface_mod
