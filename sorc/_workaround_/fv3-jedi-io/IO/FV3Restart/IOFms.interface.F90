! (C) Copyright 2021 UCAR
!
! This software is licensed under the terms of the Apache Licence Version 2.0
! which can be obtained at http://www.apache.org/licenses/LICENSE-2.0.

! --------------------------------------------------------------------------------------------------

module fv3jedi_io_fms_interface_mod

! iso
use iso_c_binding

! fckit
use fckit_configuration_module,      only: fckit_configuration

! fv3-jedi
use fv3jedi_increment_mod,           only: fv3jedi_increment
use fv3jedi_increment_interface_mod, only: fv3jedi_increment_registry
use fv3jedi_field_mod,               only: field_clen, hasfield
use fv3jedi_geom_mod,                only: fv3jedi_geom
use fv3jedi_geom_interface_mod,      only: fv3jedi_geom_registry
use fv3jedi_io_fms_mod,              only: fv3jedi_io_fms
use fv3jedi_kinds_mod,               only: kind_real
use fv3jedi_state_mod,               only: fv3jedi_state
use fv3jedi_state_interface_mod,     only: fv3jedi_state_registry
use pressure_vt_mod,                 only: ps_to_delp_tl

implicit none
private
public :: fv3jedi_io_fms_registry

! --------------------------------------------------------------------------------------------------

#define LISTED_TYPE fv3jedi_io_fms

!> Linked list interface - defines registry_t type
#include "oops/util/linkedList_i.f"

!> Global registry
type(registry_t) :: fv3jedi_io_fms_registry

! --------------------------------------------------------------------------------------------------

contains

! --------------------------------------------------------------------------------------------------

!> Linked list implementation
#include "oops/util/linkedList_c.f"

! --------------------------------------------------------------------------------------------------

subroutine c_fv3jedi_io_fms_create(c_key_self, c_conf, c_key_geom) &
           bind (c,name='fv3jedi_io_fms_create_f90')

integer(c_int),     intent(inout) :: c_key_self
type(c_ptr), value, intent(in)    :: c_conf
integer(c_int),     intent(in)    :: c_key_geom

type(fv3jedi_io_fms), pointer :: f_self
type(fckit_configuration)     :: f_conf
type(fv3jedi_geom),   pointer :: f_geom

! Linked list
! -----------
call fv3jedi_io_fms_registry%init()
call fv3jedi_io_fms_registry%add(c_key_self)
call fv3jedi_io_fms_registry%get(c_key_self, f_self)

call fv3jedi_geom_registry%get(c_key_geom, f_geom)

! Fortran APIs
! ------------
f_conf = fckit_configuration(c_conf)

! Call implementation
! -------------------
call f_self%create(f_conf, f_geom%domain, f_geom%npz)

end subroutine c_fv3jedi_io_fms_create

! --------------------------------------------------------------------------------------------------

subroutine c_fv3jedi_io_fms_delete(c_key_self) bind (c,name='fv3jedi_io_fms_delete_f90')

integer(c_int), intent(inout) :: c_key_self  !< Change variable structure

type(fv3jedi_io_fms), pointer :: f_self

! Linked list
! -----------
call fv3jedi_io_fms_registry%get(c_key_self, f_self)

! Call implementation
! -------------------
call f_self%delete()

! Linked list
! -----------
call fv3jedi_io_fms_registry%remove(c_key_self)

end subroutine c_fv3jedi_io_fms_delete

! --------------------------------------------------------------------------------------------------

subroutine c_fv3jedi_io_fms_read_state(c_key_self, c_key_geom, c_key_state, c_fileionamesconf, &
                                       c_fileioscalingconf) &
           bind (c,name='fv3jedi_io_fms_read_state_f90')

implicit none
integer(c_int),     intent(in) :: c_key_self
integer(c_int),     intent(in) :: c_key_geom
integer(c_int),     intent(in) :: c_key_state
type(c_ptr), value, intent(in) :: c_fileionamesconf
type(c_ptr), value, intent(in) :: c_fileioscalingconf

type(fv3jedi_io_fms), pointer :: f_self
type(fv3jedi_geom),   pointer :: f_geom
type(fv3jedi_state),  pointer :: f_state
type(fckit_configuration)     :: f_fileionamesconf
type(fckit_configuration)     :: f_fileioscalingconf

! Linked list
! -----------
call fv3jedi_io_fms_registry%get(c_key_self, f_self)
call fv3jedi_geom_registry%get(c_key_geom, f_geom)
call fv3jedi_state_registry%get(c_key_state, f_state)

! APIS
! ----
f_fileionamesconf = fckit_configuration(c_fileionamesconf)
f_fileioscalingconf = fckit_configuration(c_fileioscalingconf)

! Call implementation
! -------------------
call f_self%read(f_state%time, f_geom, f_state%fields, f_fileionamesconf, f_fileioscalingconf)

end subroutine c_fv3jedi_io_fms_read_state

! --------------------------------------------------------------------------------------------------

subroutine c_fv3jedi_io_fms_read_increment(c_key_self, c_key_geom, c_key_increment, &
                                           c_fileionamesconf, c_fileioscalingconf) &
           bind (c,name='fv3jedi_io_fms_read_increment_f90')

implicit none
integer(c_int),     intent(in) :: c_key_self
integer(c_int),     intent(in) :: c_key_geom
integer(c_int),     intent(in) :: c_key_increment
type(c_ptr), value, intent(in) :: c_fileionamesconf
type(c_ptr), value, intent(in) :: c_fileioscalingconf

type(fv3jedi_io_fms),    pointer :: f_self
type(fv3jedi_geom),      pointer :: f_geom
type(fv3jedi_increment), pointer :: f_increment
type(fckit_configuration)        :: f_fileionamesconf
type(fckit_configuration)        :: f_fileioscalingconf

! Linked list
! -----------
call fv3jedi_io_fms_registry%get(c_key_self, f_self)
call fv3jedi_geom_registry%get(c_key_geom, f_geom)
call fv3jedi_increment_registry%get(c_key_increment, f_increment)

! APIS
! ----
f_fileionamesconf = fckit_configuration(c_fileionamesconf)
f_fileioscalingconf = fckit_configuration(c_fileioscalingconf)

! Call implementation
! -------------------
call f_self%read(f_increment%time, f_geom, f_increment%fields, f_fileionamesconf, &
                 f_fileioscalingconf)

end subroutine c_fv3jedi_io_fms_read_increment

! --------------------------------------------------------------------------------------------------

subroutine c_fv3jedi_io_fms_write_state(c_key_self, c_key_geom, c_key_state, &
                                        c_fileionamesconf, c_fileioscalingconf) &
           bind (c,name='fv3jedi_io_fms_write_state_f90')

implicit none
integer(c_int),     intent(in) :: c_key_self
integer(c_int),     intent(in) :: c_key_geom
integer(c_int),     intent(in) :: c_key_state
type(c_ptr), value, intent(in) :: c_fileionamesconf
type(c_ptr), value, intent(in) :: c_fileioscalingconf

type(fv3jedi_io_fms),     pointer :: f_self
type(fv3jedi_geom),       pointer :: f_geom
type(fv3jedi_state),      pointer :: f_state
type(fckit_configuration)         :: f_fileionamesconf
type(fckit_configuration)         :: f_fileioscalingconf

! Linked list
! -----------
call fv3jedi_io_fms_registry%get(c_key_self, f_self)
call fv3jedi_geom_registry%get(c_key_geom, f_geom)
call fv3jedi_state_registry%get(c_key_state, f_state)

! APIS
! ----
f_fileionamesconf = fckit_configuration(c_fileionamesconf)
f_fileioscalingconf = fckit_configuration(c_fileioscalingconf)

! Call implementation
! -------------------
call f_self%write(f_state%time, f_geom, f_state%fields, f_fileionamesconf, f_fileioscalingconf)

end subroutine c_fv3jedi_io_fms_write_state

! --------------------------------------------------------------------------------------------------

subroutine c_fv3jedi_io_fms_write_increment(c_key_self, c_key_geom, c_key_increment, &
                                            c_fileionamesconf, c_fileioscalingconf) &
           bind (c,name='fv3jedi_io_fms_write_increment_f90')

implicit none
integer(c_int),     intent(in) :: c_key_self
integer(c_int),     intent(in) :: c_key_geom
integer(c_int),     intent(in) :: c_key_increment
type(c_ptr), value, intent(in) :: c_fileionamesconf
type(c_ptr), value, intent(in) :: c_fileioscalingconf

type(fv3jedi_io_fms),     pointer :: f_self
type(fv3jedi_geom),       pointer :: f_geom
type(fv3jedi_increment),  pointer :: f_increment
type(fckit_configuration)         :: f_fileionamesconf
type(fckit_configuration)         :: f_fileioscalingconf
integer                           :: indexof_ps
integer                           :: ps_npz
logical                           :: haveps
logical                           :: havedelp
logical                           :: convert_ps_to_delp
character(len=:), allocatable     :: delp_io_name
character(len=field_clen)         :: ps_long_name
character(len=field_clen)         :: ps_model_name
real(kind=kind_real), allocatable :: ps_increment(:,:,:)

! Linked list
! -----------
call fv3jedi_io_fms_registry%get(c_key_self, f_self)
call fv3jedi_geom_registry%get(c_key_geom, f_geom)
call fv3jedi_increment_registry%get(c_key_increment, f_increment)

! APIS
! ----
f_fileionamesconf = fckit_configuration(c_fileionamesconf)
f_fileioscalingconf = fckit_configuration(c_fileioscalingconf)

! For regional FV3 restart output, convert the surface-pressure increment
! into a pressure-thickness increment. This leaves ps as the control and
! analysis variable while writing the DELP increment required by FV3.
!
! Do not perform this conversion if the Increment already contains DELP.
! This is consistent with fv3jedi_state_mod.add_increment, which updates
! state DELP from a ps increment only when DELP is not a direct increment.
haveps = hasfield(f_increment%fields, 'air_pressure_at_surface', indexof_ps)
havedelp = hasfield(f_increment%fields, 'air_pressure_thickness')

convert_ps_to_delp = (.not. f_self%use_fms_lib) .and. haveps .and. .not. havedelp

if (convert_ps_to_delp) then

  ! Report the output-only conversion once rather than from every MPI rank.
  if (f_geom%f_comm%rank() == 0) then
    write(6,'(A)') 'c_fv3jedi_io_fms_write_increment: ' // &
                   'converting ps increment to delp for regional restart output'
  endif

  ! Save the original field metadata.
  ps_long_name = f_increment%fields(indexof_ps)%long_name
  ps_model_name = f_increment%fields(indexof_ps)%model_name
  ps_npz = f_increment%fields(indexof_ps)%npz

  ! Temporarily move the ps increment out of the Increment.
  call move_alloc(f_increment%fields(indexof_ps)%array, ps_increment)

  ! Reuse the ps field position for the three-dimensional DELP increment.
  allocate(f_increment%fields(indexof_ps)%array( &
           f_increment%fields(indexof_ps)%isc: &
           f_increment%fields(indexof_ps)%iec, &
           f_increment%fields(indexof_ps)%jsc: &
           f_increment%fields(indexof_ps)%jec, &
           1:f_geom%npz))

  ! Compute:
  !
  !   delp_inc(k) = (bk(k+1) - bk(k)) * ps_inc
  !
  ! The ak contribution cancels when forming an increment.
  call ps_to_delp_tl(f_geom, ps_increment(:,:,1), f_increment%fields(indexof_ps)%array)

  ! Present the temporary field to the restart writer as DELP.
  f_increment%fields(indexof_ps)%long_name = 'air_pressure_thickness'
  f_increment%fields(indexof_ps)%npz = f_geom%npz

  if (f_fileionamesconf%get('air_pressure_thickness', delp_io_name)) then
    f_increment%fields(indexof_ps)%model_name = trim(delp_io_name)
  else
    f_increment%fields(indexof_ps)%model_name = 'delp'
  endif

endif

! Call implementation
! -------------------
call f_self%write(f_increment%time, f_geom, f_increment%fields, f_fileionamesconf, f_fileioscalingconf)

! Restore the original ps increment so writing does not modify the
! Increment held by OOPS.
if (convert_ps_to_delp) then

  deallocate(f_increment%fields(indexof_ps)%array)
  call move_alloc(ps_increment, f_increment%fields(indexof_ps)%array)

  f_increment%fields(indexof_ps)%long_name = ps_long_name
  f_increment%fields(indexof_ps)%model_name = ps_model_name
  f_increment%fields(indexof_ps)%npz = ps_npz

endif

end subroutine c_fv3jedi_io_fms_write_increment

! --------------------------------------------------------------------------------------------------

end module fv3jedi_io_fms_interface_mod
