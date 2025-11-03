!#
!                                *********************************************
!                                *             MODULE phint                  *
!                                *  R. J. Purser, NOAA/NCEP/EMC       2018   *
!                                *          jim.purser@noaa.gov              *
!                                *                                           *
!                                *********************************************
! 
! Simple 4-point smooth interpolation from:
! (1) a uniform grid (whint and whintd);
! (2) a variable grid (whintvar and whintvard)
! based on "Hermite"-like formulas ensuring continuity of
! derivative at each node.
! The target point, x, is generally assumed to belong to the central
! interval, ([0.,1.], in the case of whnt and whntd) and derivatives (when
! applicable) are with respect to the grid index variable.
!
! COMPILE AFTER: {pietc}
!
!=============================================================================
module phint
!=============================================================================
use mgbf_kinds, only: i_kind,r_kind
use jp_pietc, only: u0,u1,u2,o2
implicit none
private
public:: hint,whint,v1_whint,wint3,v1_wint3

interface hint;  module procedure hint,hintd;    end interface
interface whint
   module procedure whint,whintd,whintvar,whintvard
end interface whint
interface wint3
   module procedure wint3,wint3d
end interface wint3
interface v1_wint3
   module procedure v1_wint3,v1_wint3d
end interface v1_wint3
interface v1_whint
   module procedure v1_whint,v1_whintd,v1_whintvar,v1_whintvard
end interface v1_whint

contains

!=============================================================================
subroutine hint(x,as,a)!                                                [hint]
!=============================================================================
! smoothly interpolate the value from four uniformly-spaced source values, as, 
! to a point located a fraction, x, into the central interval. The result is a.
!=============================================================================
implicit none
real(r_kind),                intent(in ):: x
real(r_kind),dimension(-1:2),intent(in ):: as
real(r_kind),                intent(out):: a
!-----------------------------------------------------------------------------
real(r_kind):: da0,dda0,da1,dda1,quad0,quad1,xm
!=============================================================================
da0=(as(1)-as(-1))*o2      ; da1=(as(2)-as(0))*o2
dda0=as(-1)-2*as(0)+as(1); dda1=as(0)-2*as(1)+as(2)
xm=x-u1
quad0=as(0)+x *(da0+x* dda0*o2)
quad1=as(1)+xm*(da1+xm*dda1*o2)
a=quad1*x-quad0*xm
end subroutine hint
!=============================================================================
subroutine hintd(x,as,a,da)!                                            [hint]
!=============================================================================
! smoothly interpolate the value and its derivative from four uniformly-spaced 
! source values, as, to a point located a fraction, x, into the central 
! interval. The results are a and da.
!=============================================================================
implicit none
real(r_kind),                intent(in ):: x
real(r_kind),dimension(-1:2),intent(in ):: as
real(r_kind),                intent(out):: a,da
!-----------------------------------------------------------------------------
real(r_kind):: da0,dda0,da1,dda1,quad0,quad1,dquad0,dquad1,xm
!=============================================================================
da0=(as(1)-as(-1))*o2     ; da1=(as(2)-as(0))*o2
dda0=as(-1)-u2*as(0)+as(1); dda1=as(0)-u2*as(1)+as(2)
xm=x-u1
quad0=as(0)+x *(da0+x *dda0*o2); dquad0=da0+x *dda0
quad1=as(1)+xm*(da1+xm*dda1*o2); dquad1=da1+xm*dda1
a =quad1 *x-quad0 *xm
da=dquad1*x-dquad0*xm+quad1-quad0
end subroutine hintd

!=============================================================================
subroutine whint(x,wint)!                                              [whint]
!=============================================================================
! Return the interpolation weights, wint, for smooth 4-point interpolation
! from a uniform grid to a target located a fraction, x, into the central
! of the three intervals defined by the four points.
!=============================================================================

implicit none
real(r_kind),                intent(in ):: x
real(r_kind),dimension(-1:2),intent(out):: wint
!-----------------------------------------------------------------------------
real(r_kind):: xm1,xp1,xm2
!=============================================================================
xm2=x-u2; xm1=x-u1; xp1=x+u1
wint=(/-x*xm1*o2, xm1*xp1,   -x*xp1*o2,      u0 /)*xm1+ &
     (/      u0, xm1*xm2*o2,   -xm2*x, xm1*x*o2 /)*x
end subroutine whint
subroutine v1_whint(x,wint)!                                              [whint]
!the same as wint  
!=============================================================================
! Return the interpolation weights, wint, for smooth 4-point interpolation
! from a uniform grid to a target located a fraction, x, into the central
! of the three intervals defined by the four points.
!=============================================================================

implicit none
real(r_kind),                intent(in ):: x
real(r_kind),dimension(-1:2),intent(out):: wint
!-----------------------------------------------------------------------------
real(r_kind):: xm1,xp1,xm2
!=============================================================================
xm2=x-u2; xm1=x-u1; xp1=x+u1
wint=(/-x*xm1*o2, xm1*xp1,   -x*xp1*o2,      u0 /)*xm1+ &
     (/      u0, xm1*xm2*o2,   -xm2*x, xm1*x*o2 /)*x
wint=wint(2:-1:-1)
end subroutine v1_whint
!=============================================================================
subroutine whintd(x,wint,dwint)!                                       [whint]
!=============================================================================
! Return the interpolation weights, wint, for smooth 4-point interpolation
! from a uniform grid to a target located a fraction, x, into the central
! of the three intervals defined by the four points.
!=============================================================================
implicit none
real(r_kind),                intent(in ):: x
real(r_kind),dimension(-1:2),intent(out):: wint,dwint
!-----------------------------------------------------------------------------
real(r_kind)                :: xm1,xp1,xm2
real(r_kind),dimension(-1:2):: quad0,quad1,dquad0,dquad1
!=============================================================================
xm2=x-u2; xm1=x-u1; xp1=x+u1
quad0=(/-x*xm1*o2,  xm1*xp1, -x*xp1*o2,       u0 /)
quad1=(/      u0,xm1*xm2*o2,    -xm2*x, xm1*x*o2 /)
dquad0=(/  -x+o2,      u2*x,     -x-o2,       u0 /)
dquad1=(/     u0,    xm1-o2,   -u2*xm1,   xm1+o2 /)
wint = quad0*xm1+ quad1*x
dwint=dquad0*xm1+dquad1*x+quad0+quad1
end subroutine whintd
!=============================================================================
subroutine v1_whintd(x,wint,dwint)!                                       [whint]
!the same as whint
!=============================================================================
! Return the interpolation weights, wint, for smooth 4-point interpolation
! from a uniform grid to a target located a fraction, x, into the central
! of the three intervals defined by the four points.
!=============================================================================
implicit none
real(r_kind),                intent(in ):: x
real(r_kind),dimension(-1:2),intent(out):: wint,dwint
!-----------------------------------------------------------------------------
real(r_kind)                :: xm1,xp1,xm2
real(r_kind),dimension(-1:2):: quad0,quad1,dquad0,dquad1
!=============================================================================
xm2=x-u2; xm1=x-u1; xp1=x+u1
quad0=(/-x*xm1*o2,  xm1*xp1, -x*xp1*o2,       u0 /)
quad1=(/      u0,xm1*xm2*o2,    -xm2*x, xm1*x*o2 /)
dquad0=(/  -x+o2,      u2*x,     -x-o2,       u0 /)
dquad1=(/     u0,    xm1-o2,   -u2*xm1,   xm1+o2 /)
wint = quad0*xm1+ quad1*x
dwint=dquad0*xm1+dquad1*x+quad0+quad1
wint=wint(2:-1:-1)
dwint=dwint(2:-1:-1)
end subroutine v1_whintd

!=============================================================================
subroutine whintvar(xs,x,wint)!                                        [whint]
!=============================================================================
use jp_pkind, only: dp
use jp_pietc, only: u0
implicit none
real(r_kind),dimension(0:3),intent(in ):: xs
real(r_kind),               intent(in ):: x
real(r_kind),dimension(0:3),intent(out):: wint
!-----------------------------------------------------------------------------
real(r_kind):: x01,x12,x23,x02,x13,x0,x1,x2,x3
!=============================================================================
x01=xs(1)-xs(0)
x12=xs(2)-xs(1)
x23=xs(3)-xs(2)
x02=xs(2)-xs(0)
x13=xs(3)-xs(1)
x0=x-xs(0)
x1=x-xs(1)
x2=x-xs(2)
x3=x-xs(3)
wint=-(/ x1*x2/(x01*x02),-x0*x2/(x01*x12),x0*x1/(x02*x12),u0/)*x2/x12 &
     +(/u0,x2*x3/(x12*x13),-x1*x3/(x12*x23),x1*x2/(x13*x23)/)*x1/x12
end subroutine whintvar
subroutine v1_whintvar(xs,x,wint)!                                        [whint]
!reversed xs
!0->3,1->2,2->1,3->0
!=============================================================================
use jp_pkind, only: dp
use jp_pietc, only: u0
implicit none
real(r_kind),dimension(0:3),intent(in ):: xs
real(r_kind),               intent(in ):: x
real(r_kind),dimension(0:3),intent(out):: wint
!-----------------------------------------------------------------------------
real(r_kind):: x01,x12,x23,x02,x13,x0,x1,x2,x3

!=============================================================================
!0->3,1->2,2->1,3->0
!lct x01=xs(1)-xs(0)
x01=xs(2)-xs(3)
!#x12=xs(2)-xs(1)
x12=xs(1)-xs(2)
!clt x23=xs(3)-xs(2)
x23=xs(0)-xs(1)
!clt x02=xs(2)-xs(0)
x02=xs(1)-xs(3)
!clt x13=xs(3)-xs(1)
x13=xs(0)-xs(2)
x0=x-xs(3)
x1=x-xs(2)
x2=x-xs(1)
x3=x-xs(0)
wint=-(/ x1*x2/(x01*x02),-x0*x2/(x01*x12),x0*x1/(x02*x12),u0/)*x2/x12 &
     +(/u0,x2*x3/(x12*x13),-x1*x3/(x12*x23),x1*x2/(x13*x23)/)*x1/x12
wint=wint(3:0:-1)
end subroutine v1_whintvar

!=============================================================================
subroutine whintvard(xs,x,wint,dwint)!                                 [whint]
!=============================================================================
use jp_pkind, only: dp
use jp_pietc, only: u0
implicit none
real(r_kind),dimension(0:3),intent(in ):: xs
real(r_kind),               intent(in ):: x
real(r_kind),dimension(0:3),intent(out):: wint,dwint
!-----------------------------------------------------------------------------
real(r_kind),dimension(0:3):: q1,q2
real(r_kind)               :: x01,x12,x23,x02,x13,x0,x1,x2,x3
!=============================================================================
x01=xs(1)-xs(0)
x12=xs(2)-xs(1)
x23=xs(3)-xs(2)
x02=xs(2)-xs(0)
x13=xs(3)-xs(1)
x0=x-xs(0)
x1=x-xs(1)
x2=x-xs(2)
x3=x-xs(3)
q1=-(/x1*x2/(x01*x02),-x0*x2/(x01*x12),x0*x1/(x02*x12),u0/)
q2= (/u0,x2*x3/(x12*x13),-x1*x3/(x12*x23),x1*x2/(x13*x23)/)
wint=q1*x2/x12+q2*x1/x12
dwint=-(/(x1+x2)/(x01*x02),-(x0+x2)/(x01*x12),(x0+x1)/(x02*x12),u0/)*x2/x12 &
      +(/u0,(x2+x3)/(x12*x13),-(x1+x3)/(x12*x23),(x1+x2)/(x13*x23)/)*x1/x12 &
      +(q1+q2)/x12
end subroutine whintvard
subroutine v1_whintvard(xs,x,wint,dwint)!                                 [whint]
!reversed xs,wint,dwint
!0->3,1->2,2->1,3->0
!=============================================================================
use jp_pkind, only: dp
use jp_pietc, only: u0
implicit none
real(r_kind),dimension(0:3),intent(in ):: xs
real(r_kind),               intent(in ):: x
real(r_kind),dimension(0:3),intent(out):: wint,dwint
!-----------------------------------------------------------------------------
real(r_kind),dimension(0:3):: q1,q2
real(r_kind)               :: x01,x12,x23,x02,x13,x0,x1,x2,x3
!=============================================================================
!0->3,1->2,2->1,3->0
x01=xs(2)-xs(3)
x12=xs(1)-xs(2)
x23=xs(0)-xs(1)
x02=xs(1)-xs(3)
x13=xs(0)-xs(2)
x0=x-xs(3)
x1=x-xs(2)
x2=x-xs(1)
x3=x-xs(0)
q1=-(/x1*x2/(x01*x02),-x0*x2/(x01*x12),x0*x1/(x02*x12),u0/)
q2= (/u0,x2*x3/(x12*x13),-x1*x3/(x12*x23),x1*x2/(x13*x23)/)
wint=q1*x2/x12+q2*x1/x12
dwint=-(/(x1+x2)/(x01*x02),-(x0+x2)/(x01*x12),(x0+x1)/(x02*x12),u0/)*x2/x12 &
      +(/u0,(x2+x3)/(x12*x13),-(x1+x3)/(x12*x23),(x1+x2)/(x13*x23)/)*x1/x12 &
      +(q1+q2)/x12
wint=wint(3:0:-1)
dwint=dwint(3:0:-1)
end subroutine v1_whintvard

!=============================================================================
subroutine wint3(xs,x,wint)!                                           [wint3]
!=============================================================================
! Get the weights, wint, for Lagrange 3-point interpolation to x from a
! variable-spaced grid xs
!=============================================================================
use jp_pkind, only: dp
implicit none
real(r_kind),dimension(0:2),intent(in ):: xs
real(r_kind),               intent(in ):: x
real(r_kind),dimension(0:2),intent(out):: wint
!-----------------------------------------------------------------------------
real(r_kind):: x01,x12,x02,x0,x1,x2
!=============================================================================
x01=xs(1)-xs(0)
x12=xs(2)-xs(1)
x02=xs(2)-xs(0)
x0=x-xs(0)
x1=x-xs(1)
x2=x-xs(2)
wint=(/x1*x2/(x01*x02),-x0*x2/(x01*x12),x0*x1/(x02*x12)/)
end subroutine wint3
subroutine v1_wint3(xs,x,wint)!                                           [wint3]
!the reversed order of xs
!=============================================================================
! Get the weights, wint, for Lagrange 3-point interpolation to x from a
! variable-spaced grid xs
!=============================================================================
use jp_pkind, only: dp
implicit none
real(r_kind),dimension(0:2),intent(in ):: xs
real(r_kind),               intent(in ):: x
real(r_kind),dimension(0:2),intent(out):: wint
!-----------------------------------------------------------------------------
real(r_kind):: x01,x12,x02,x0,x1,x2
!clt 0 -> 2, 1->1,2->0
!=============================================================================
x01=xs(1)-xs(2)
x12=xs(0)-xs(1)
x02=xs(0)-xs(2)
x0=x-xs(2)
x1=x-xs(1)
x2=x-xs(0)
wint=(/x1*x2/(x01*x02),-x0*x2/(x01*x12),x0*x1/(x02*x12)/)
wint=wint(2:0:-1)
end subroutine v1_wint3
  
!=============================================================================
subroutine wint3d(xs,x,wint,dwint)!                                    [wint3]
!=============================================================================
! Get the weights, wint, for Lagrange 3-point interpolation to x from a
! variable-spaced grid xs and the derivative weights dwint.
!=============================================================================
use jp_pkind, only: dp
implicit none
real(r_kind),dimension(0:2),intent(in ):: xs
real(r_kind),               intent(in ):: x
real(r_kind),dimension(0:2),intent(out):: wint,dwint
!-----------------------------------------------------------------------------
real(r_kind):: x01,x12,x02,x0,x1,x2
!=============================================================================
x01=xs(1)-xs(0)
x12=xs(2)-xs(1)
x02=xs(2)-xs(0)
x0=x-xs(0)
x1=x-xs(1)
x2=x-xs(2)
wint=(/x1*x2/(x01*x02),-x0*x2/(x01*x12),x0*x1/(x02*x12)/)
dwint=(/(x1+x2)/(x01*x02),-(x0+x2)/(x01*x12),(x0+x1)/(x02*x12)/)
end subroutine wint3d
subroutine v1_wint3d(xs,x,wint,dwint)!                                    [wint3]
!=============================================================================
! Get the weights, wint, for Lagrange 3-point interpolation to x from a
! variable-spaced grid xs and the derivative weights dwint.
!=============================================================================
!the reversed order of xs
!clt 0 -> 2, 1->1,2->0
use jp_pkind, only: dp
implicit none
real(r_kind),dimension(0:2),intent(in ):: xs
real(r_kind),               intent(in ):: x
real(r_kind),dimension(0:2),intent(out):: wint,dwint
!-----------------------------------------------------------------------------
real(r_kind):: x01,x12,x02,x0,x1,x2
!=============================================================================
x01=xs(1)-xs(0)
x12=xs(0)-xs(1)
x02=xs(0)-xs(2)
x0=x-xs(2)
x1=x-xs(1)
x2=x-xs(0)
wint=(/x1*x2/(x01*x02),-x0*x2/(x01*x12),x0*x1/(x02*x12)/)
dwint=(/(x1+x2)/(x01*x02),-(x0+x2)/(x01*x12),(x0+x1)/(x02*x12)/)
wint=wint(2:0:-1)
dwint=dwint(2:0:-1)
end subroutine v1_wint3d
  
end module phint
!#
