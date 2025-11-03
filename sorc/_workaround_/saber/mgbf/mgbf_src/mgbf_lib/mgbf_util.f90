module mgbf_utils
use mgbf_kinds,only: r_kind, i_kind
implicit none
private
public :: contains_nonzero

interface contains_nonzero
  module procedure contains_nonzero_real
  module procedure contains_nonzero_integer
end interface
contains

logical function contains_nonzero_real(array) result(has_nonzero)
  real(r_kind), intent(in) :: array(:, :, :)  ! Declare 3D array
  integer(i_kind) :: i, j, k

  has_nonzero = .false.
  do k = 1, size(array, 3)  ! Loop over third dimension
    do j = 1, size(array, 2)  ! Loop over second dimension
      do i = 1, size(array, 1)  ! Loop over first dimension
        if (array(i, j, k) /= 0.0) then
          has_nonzero = .true.
          return
        end if
      end do
    end do
  end do
end function contains_nonzero_real

logical function contains_nonzero_integer(array) result(has_nonzero)
  integer(i_kind), intent(in) :: array(:, :, :)  ! Declare 3D array
  integer(i_kind) :: i, j, k

  has_nonzero = .false.
  do k = 1, size(array, 3)  ! Loop over third dimension
    do j = 1, size(array, 2)  ! Loop over second dimension
      do i = 1, size(array, 1)  ! Loop over first dimension
        if (array(i, j, k) /= 0) then
          has_nonzero = .true.
          return
        end if
      end do
    end do
  end do
end function contains_nonzero_integer
end module mgbf_utils

