module mg_tools
!!from codex :
!the filtering grid is anchored to the same physical domain as the analysis grid, 
!with both sharing the left/right boundaries at 0 and lengthx (and top/bottom at lengthy).
! In init_mg_parameter, the domain length is set to lengthx = nm and 
!lengthy = mm (src/saber/mgbf/mgbf_lib/mg_parameter.f90:946-957). 
!Analysis points sit at midpoints of unit cells: xa(n) = xa0 + dxa*(n-1) with xa0 = dxa/2 = 0.5 
!(src/saber/mgbf/mgbf_lib/mg_parameter.f90:952-961). Filtering points use the same origin convention: xf(i) = xf0 + dxf*(i-1) with xf0 = dxf/2 (src/saber/mgbf/mgbf_lib/mg_parameter.f90:952-964). 
!So both grids start half a grid spacing from the boundary; no global offset is applied.    
use mgbf_kinds, only: r_kind,i_kind

contains
subroutine interp_analysis_to_filter(yy, nm, mm, im, jm, zz)
  ! Bilinear interpolation from analysis grid (nm×mm) to filter grid (im×jm).
  ! Assumes both grids span the same physical domain and are cell-centered.

  implicit none
  integer(i_kind), intent(in) :: nm, mm        ! analysis grid dimensions
  integer(i_kind), intent(in) :: im, jm        ! filter grid dimensions
  real(r_kind),    intent(in) :: yy(nm, mm)    ! analysis field
  real(r_kind),    intent(out):: zz(im, jm)    ! interpolated field on filter grid

  integer(i_kind) :: i, j, n0, n1, m0, m1
  real(r_kind)    :: dxA, dyA, dxF, dyF
  real(r_kind)    :: xa0, ya0, xf0, yf0
  real(r_kind)    :: xf, yf, xa, ya, tx, ty
  real(r_kind)    :: w00, w10, w01, w11

  dxA = 1.0            ! analysis spacing (arbitrary scale)
  dyA = 1.0
  xa0 = 0.5*dxA        ! analysis centers
  ya0 = 0.5*dyA

  dxF = (nm*dxA)/im    ! filter spacing so domains align
  dyF = (mm*dyA)/jm
  xf0 = 0.5*dxF
  yf0 = 0.5*dyF

  do j = 1, jm
    yf = yf0 + (j-1)*dyF
    ya = (yf - ya0)/dyA + 1.0          ! fractional analysis index
    m0 = max(1, min(mm-1, int(floor(ya))))
    m1 = m0 + 1
    ty = ya - m0

    do i = 1, im
      xf = xf0 + (i-1)*dxF
      xa = (xf - xa0)/dxA + 1.0         ! fractional analysis index
      n0 = max(1, min(nm-1, int(floor(xa))))
      n1 = n0 + 1
      tx = xa - n0

      w00 = (1.0-tx)*(1.0-ty)
      w10 = tx*(1.0-ty)
      w01 = (1.0-tx)*ty
      w11 = tx*ty

      zz(i,j) = w00*yy(n0,m0) + w10*yy(n1,m0) &
              + w01*yy(n0,m1) + w11*yy(n1,m1)
    end do
  end do
end subroutine interp_analysis_to_filter
subroutine mg_sphere_dist(lon_i, lat_i, lon_f, lat_f, dist)
  implicit none
  real(r_kind), intent(in)  :: lon_i   ! radians
  real(r_kind), intent(in)  :: lat_i   ! radians
  real(r_kind), intent(in)  :: lon_f   ! radians
  real(r_kind), intent(in)  :: lat_f   ! radians
  real(r_kind), intent(out) :: dist    ! radians on the unit sphere
  real(r_kind) :: dlon, dlat, sin_half_dlon, sin_half_dlat
  real(r_kind) :: cos_lat_i, cos_lat_f, hav

  dlon = lon_f - lon_i
  dlat = lat_f - lat_i
  sin_half_dlon = sin(0.5_r_kind * dlon)
  sin_half_dlat = sin(0.5_r_kind * dlat)
  cos_lat_i = cos(lat_i)
  cos_lat_f = cos(lat_f)

  hav = sin_half_dlat*sin_half_dlat + cos_lat_i*cos_lat_f*sin_half_dlon*sin_half_dlon
  hav = min(1.0_r_kind, max(0.0_r_kind, hav))      ! numerical safety
  dist = 2.0_r_kind * atan2(sqrt(hav), sqrt(max(0.0_r_kind, 1.0_r_kind - hav)))
end subroutine mg_sphere_dist

end module mg_tools
