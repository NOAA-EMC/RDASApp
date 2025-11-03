!#
!                                *********************************************
!                                *             MODULE phint1                 *
!                                *  R. J. Purser, NOAA/NCEP/EMC       2025   *
!                                *          jim.purser@noaa.gov              *
!                                *                                           *
!                                *********************************************
! Use interpolations of phint.f90 to construct a grid uniform in units of
! the "scale" given by a gridded profile. Also, use the interpolation of
! the logarithm of a given profile, followed by application of the exponential
! function, to ensure that the interpolation of a positive gridded function
! from one grid to another remains both smooth and positive.
!
! COMPILE AFTER: { phint.f90 }
!
!============================================================================
module phint1
!============================================================================
use mgbf_kinds, only: i_kind,r_kind
use phint, only: wint3,whint,v1_wint3,v1_whint
implicit none
public:: make_ssf, make_ssgrid, zsigtossig, interpftos, sstosig, intgrid, &
     logintgrid, wintgrid, monotonicrefine,sofztozofs 

interface make_ssf
   module procedure make_ssf
end interface make_ssf
interface make_ssgrid
   module procedure make_ssgrid, make_sfgrid
end interface make_ssgrid
interface zsigtossig
   module procedure zsigtossig, zsigtosfsig
end interface zsigtossig
interface interpftos
   module procedure interpftos
end interface interpftos
interface sstosig
   module procedure sstosig
end interface sstosig
interface intgrid
   module procedure intgrid, intgridw
end interface intgrid
interface wintgrid
   module procedure wintgrid
end interface wintgrid
interface logintgrid
   module procedure logintgrid, logintgridw
end interface logintgrid
interface sofztozofs
   module procedure sofztozofs, sofztozofs_f
end interface sofztozofs
interface monotonicrefine
   module procedure monotonicrefine
end interface monotonicrefine
contains
   
!============================================================================
subroutine make_ssf(nz,nf,sigofz,ssofzf)!                          [make_ssf]
!============================================================================
! Use the scales, in original [0:nz] "z-grid" units, sigofz, to define an
! effective integrated distance, ss, in these scale units, for every level
! of a refined version [0:nz*nf] of that original z grid. This is done by
! regarding each sigofz as the inverse of the derivative of ss wrt the
! z-index, and integrating the interpolated inverse of sigofz on a uniformly
! refined version [0:nz*nf] of the z grid. To avoid small or negative values
! occurring in the interpolation, it is actually the logarithm of (1/sigofz)
! (i.e., -log(sigofz) ) that we interpolate. The fine grid of values of ss
! are returned as the array ssf.
!============================================================================
use jp_pietc, only: u1,o2
implicit none
integer(i_kind),               intent(in ):: nz,nf
real(r_kind),dimension(0:nz),   intent(in ):: sigofz
real(r_kind),dimension(0:nz*nf),intent(out):: ssofzf
!-----------------------------------------------------------------------------
real(r_kind),dimension(0:nz*nf):: zofzf,sigiofzf
real(r_kind)                   :: dzf,s
integer(i_kind)               :: izf,nzf
!=============================================================================
! Assume sigofz is given on a unit grid, [0:nz]
! Logarithmically Interpolate the 1/sigofz distribution to a uniform finer grid,
! [0:nz*nf] and integrate it along this finer grid to get ssofzf.
! (interpolating the logarithm avoids the possibility of negative undershoots
! of the interpolated values).
!=============================================================================
nzf=nz*nf
dzf=u1/nf
do izf=0,nzf
   zofzf(izf)=izf*dzf
enddo
call logintgrid(nz,nzf,zofzf,u1/sigofz, sigiofzf)
! Integrate sigiofzf
s=0; ssofzf(0)=s
do izf=1,nzf
   s=s+sigiofzf(izf-1)+sigiofzf(izf); ssofzf(izf)=s
enddo
ssofzf=ssofzf*dzf*o2
end subroutine make_ssf

!============================================================================
subroutine make_sfgrid(nz,nfz,ns,nfs,sigofz, sstop,dssf,sfofz,&
     zofsf)!                                                    [make_ssgrid]
!============================================================================
use jp_pietc, only: u1,o2
implicit none
integer(i_kind),                intent(in ):: nz,nfz,ns,nfs
real(r_kind),dimension(0:nz),    intent(in ):: sigofz
real(r_kind),                    intent(out):: sstop,dssf
real(r_kind),dimension(0:nz),    intent(out):: sfofz
real(r_kind),dimension(0:ns*nfs),intent(out):: zofsf
!----------------------------------------------------------------------------
integer(i_kind)                :: nsf
!============================================================================
nsf=ns*nfs
call make_ssgrid(nz,nfz,nsf,sigofz, sstop,dssf,sfofz,zofsf)
end subroutine make_sfgrid
!============================================================================
subroutine make_ssgrid(nz,nf,ns,sigofz, sstop,dss,sofz,zofs)!   [make_ssgrid]
!============================================================================
! Use the vertical profile, sigofs, of idealized correlation scale
! on the unit-spaced model grid of nz spaces to derive the total integrated
! depth, sstop, of the vertical domain in these scale units. Then,
! by using careful interpolations of the log of sigofz on the grid refined
! in the vertical by a factor of nf, divide the vertical domain into
! a new grid whose spacing is uniform in these scale units and which
! possesses ns grid spaces. On this grid, the correlation scale is
! constant, and can be taken to be sstopons=sstop/ns.
! Also, output the array, sofz, defining the index-coordinate of
! the new grid that corresponds to each model grid level, and the
! model grid index coordinate, zofs, that corresponds to each level of
! out new scale-grid. All grids are assumed to go from index 0.
!============================================================================
use jp_pietc, only: u1,o2
implicit none
integer(i_kind),            intent(in ):: nz,nf,ns
real(r_kind),dimension(0:nz),intent(in ):: sigofz
real(r_kind),                intent(out):: sstop,dss
real(r_kind),dimension(0:nz),intent(out):: sofz
real(r_kind),dimension(0:ns),intent(out):: zofs
!----------------------------------------------------------------------------
real(r_kind),dimension(0:nz)   :: zs
real(r_kind),dimension(0:nz*nf):: zsf,ssf
real(r_kind),dimension(0:ns)   :: ss
real(r_kind)                   :: r,s,z,dzf
integer(i_kind)               :: iz,izf,izfm,izfp,is,nzf
!============================================================================
! Interpolate the log of the sigofz distribution to a finer grid:
dzf=u1/nf
nzf=nz*nf
call make_ssf(nz,nf,sigofz,ssf)
sstop=ssf(nzf)
! define the new grid of ns spaces that uniformly divides the
! range of ss:
dss=sstop/ns
sofz(0)=0
sofz(nz)=ns
do iz=1,nz-1
   izf=iz*nf
   sofz(iz)=ssf(izf)/dss
enddo
do is=0,ns
   ss(is)=is*dss
enddo
zofs(0)=0
zofs(ns)=nz
izfp=1
do is=1,ns-1
   s=ss(is)
   do
      if(ssf(izfp)>=s)exit
      izfp=izfp+1
   enddo
   izf=izfp-1
   r=(s-ssf(izf))/(ssf(izfp)-ssf(izf))
   zofs(is)=(izf+r)/nf
enddo
end subroutine make_ssgrid

!===========================================================================
subroutine zsigtossig(nz,nf,ns,zofs,sigofz, sigofs)!            [zsigtossig]
!===========================================================================
! Interpolate the sigma in z-grid units from the z-grid to the
! equivalent sigma in s-grid unit in the s-grid. The z-grid index
! coordinates of the each s-grid level is given by zofs. zofs is prepared
! beforehand by calling subroutine make_ssgrid with, in general, a
! possibly different profile of sigma.
! The index range of the z-grid is [0:nz], of the s-grid it is [0:ns] and an
! intermediate refined version of the z-grid has index range, [0:nz*nf]
! where nf is a positive integer refinement factor to ensure that the
! intermediate calculations have only small truncation errors.
! sigofz is the z-grid sigma that is being interpolated, but note that
! it is generally not the same sigma that was used to construct the
! regularized s-grid. sigofs is the interpolated s-grid sigma. A version
! of this algorithm that goes through an intermediate refined s-grid (to
! further reduce truncation errors in the final part of the computation)
! is found in the overloaded subroutine zsigtosfsig.
!============================================================================
implicit none
integer(i_kind),            intent(in ):: nz,nf,ns
real(r_kind),dimension(0:ns),intent(in ):: zofs
real(r_kind),dimension(0:nz),intent(in ):: sigofz
real(r_kind),dimension(0:ns),intent(out):: sigofs
!----------------------------------------------------------------------------
real(r_kind),dimension(0:nz*nf):: ssf
real(r_kind),dimension(0:ns)   :: sss
!============================================================================
call make_ssf(nz,nf,sigofz,ssf)
call interpftos(nz,nf,ns,zofs,ssf,sss)
call sstosig(ns,sss,sigofs)
end subroutine zsigtossig
!===========================================================================
subroutine zsigtosfsig(nz,nfz,ns,nfs,zofsf,sigofz, sigofs)!      [zsigtossig]
!===========================================================================
! Interpolate the sigma in z-grid units from the z-grid to the
! equivalent sigma in s-grid unit in the s-grid, via a refined version,
! sf, of the final s-grid. The z-grid index
! coordinates of the each sf-grid level is given by zofsf, and this zofsf
! array musy have been constructed prior by a call to the make_sfgrid
! version of make_ssgrid. The index range of the z-grid is [0:nz], of the
! sf-grid it is [0:ns*nfs] and an intermediate refined version of the
! z-grid has index range, [0:nz*nfz] where nfz and nfs are both positive
! integer refinement factors to ensure that the intermediate calculations
! have only small truncation errors.
! sigofz is the z-grid sigma being interpolated (not generally the same as
! the sigma that was used to construct the sf and s grids).
! sigofs is the computed s-grid sigma obtained finally by picking every
! nfs_th value of the inetrmediate refined-grid (sf) version of the
! corresponding quantity (rescaled by the factor of nsf, though).
!============================================================================
implicit none
integer(i_kind),                intent(in ):: nz,nfz,ns,nfs
real(r_kind),dimension(0:ns*nfs),intent(in ):: zofsf
real(r_kind),dimension(0:nz),    intent(in ):: sigofz
real(r_kind),dimension(0:ns),    intent(out):: sigofs
!----------------------------------------------------------------------------
real(r_kind),dimension(0:nz*nfz):: ssf
real(r_kind),dimension(0:ns*nfs):: sss,sigofsf
integer(i_kind)                :: is,isf,nsf
!============================================================================
nsf=ns*nfs
call make_ssf(nz,nfz,sigofz,ssf)
call interpftos(nz,nfz,nsf,zofsf,ssf,sss)
call sstosig(nsf,sss,sigofsf)
do is=0,ns
   isf=is*nfs
   sigofs(is)=sigofsf(isf)/nfs
enddo
end subroutine zsigtosfsig

!============================================================================
subroutine interpftos(nz,nf,ns,zofs,ssf,sss)!                    [interpftos]
!============================================================================
! Linearly interpolate values ssf on the fine grid [0:nz*nf] to the ss grid
! [0:ns] whose coordinates in fine grid index units are zofs*nf, where nf
! is the refinement factor that was used to generate the fine grid for the
! original [0:nz] grid. (zofs are the index coordinate in that original
! [0:nz] grid.)
!============================================================================
implicit none
integer(i_kind),               intent(in ):: nz,nf,ns
real(r_kind),dimension(0:ns),   intent(in ):: zofs
real(r_kind),dimension(0:nz*nf),intent(in ):: ssf
real(r_kind),dimension(0:ns),   intent(out):: sss
!----------------------------------------------------------------------------
real(r_kind)    :: w1,w2,zf
integer(i_kind):: is,izf,izfp,nzf
!============================================================================
nzf=nz*nf
do is=0,ns
   zf=zofs(is)*nf
   izf=min(nzf-1,max(0,floor(zf)))
   izfp=izf+1
   w1=izfp-zf
   w2=zf-izf
   sss(is)=w1*ssf(izf)+w2*ssf(izfp)! <- linearly interpolate
enddo
end subroutine interpftos

!===========================================================================
subroutine sstosig(ns,ss,sig)!                                     [sstosig]
!===========================================================================
! Given the effective distance in correlation scale units ss of each grid
! s-gridpoint in [0:ns], from the datum (usually from gridpoint 0), use
! simple finite differences to convert the information in ss to the
! corresponding sigma values, sig, at each grid point, where sig measures
! the correlation scale at each point in the grid units.
!===========================================================================
use jp_pietc, only: u1,u2
implicit none
integer(i_kind),            intent(in ):: ns
real(r_kind),dimension(0:ns),intent(in ):: ss
real(r_kind),dimension(0:ns),intent(out):: sig
!----------------------------------------------------------------------------
integer(i_kind):: is
!============================================================================
sig(0)=u1/(ss(1)-ss(0))
do is=1,ns-1
   sig(is)=u2/(ss(is+1)-ss(is-1))
enddo
sig(ns)=u1/(ss(ns)-ss(ns-1))
end subroutine sstosig

!===========================================================================
subroutine intgrid(nz,ns,zofs,az, as)!                             [intgrid]
!===========================================================================
! From a source grid [0:nz] of values, az, interpolate to a target grid [0:ns]
! of values as using smooth linearly-weighted quadratic (4-point) except
! near ends where 3-point quadratic is necessitated to avoid overshooting.
! Array zofs defines the index z-grid coordinates of each of the s-grid points.
!============================================================================
use phint, only: wint3,whint
implicit none
integer(i_kind),            intent(in ):: nz,ns
real(r_kind),dimension(0:ns),intent(in ):: zofs
real(r_kind),dimension(0:nz),intent(in ):: az
real(r_kind),dimension(0:ns),intent(out):: as
!----------------------------------------------------------------------------
real(r_kind),dimension(0:nz):: zs
real(r_kind),dimension(3)   :: w3! 3-point interpolation weights (at ends)
real(r_kind),dimension(4)   :: w4! 4-point interpolation weights (interior)
real(r_kind)                :: z
integer(i_kind)            :: is,iz,liz,miz
!============================================================================
do iz=0,nz
   zs(iz)=iz
enddo
do is=0,ns
   z=zofs(is); iz=min(nz-1,max(0,floor(z)))
   if(iz==0)       then; liz=0;    miz=2
   elseif(iz==nz-1)then; liz=nz-2; miz=nz
   else;                 liz=iz-1; miz=iz+2
   endif
   if(miz==liz+2)then
      call wint3(zs(liz:miz),z,w3);as(is)=dot_product(w3,az(liz:miz))
   else
      call whint(zs(liz:miz),z,w4);as(is)=dot_product(w4,az(liz:miz))
   endif
enddo
end subroutine intgrid
!===========================================================================
subroutine intgridw(nz,ns,lizs,mizs,ws,az,as)!                     [intgrid]
!===========================================================================
implicit none
integer(i_kind),                intent(in ):: nz,ns
integer(i_kind),dimension(0:ns),intent(in ):: lizs,mizs
real(r_kind),dimension(4,0:ns),  intent(in ):: ws
real(r_kind),dimension(0:nz),    intent(in ):: az
real(r_kind),dimension(0:ns),    intent(out):: as
!---------------------------------------------------------------------------
integer(i_kind):: is,liz,miz
!===========================================================================
do is=0,ns
   liz=lizs(is); miz=mizs(is)
   if(liz+2==miz)then; as(is)=dot_product(ws(1:3,is),az(liz:miz))
   else              ; as(is)=dot_product(ws(:  ,is),az(liz:miz))
   endif
enddo
end subroutine intgridw

!===========================================================================
subroutine wintgrid(nz,ns,zofs, lizs,mizs,ws)!                    [wintgrid]
!===========================================================================
! Collect the stencil index limits lizs and mizs and the weights ws for
! smooth interpolation from the z-grid [0:nz] to the s-grid [0:ns]
!===========================================================================
  use phint, only: wint3,whint
implicit none
integer(i_kind),                intent(in ):: nz,ns
real(r_kind),dimension(0:ns),    intent(in ):: zofs
integer(i_kind),dimension(0:ns),intent(out):: lizs,mizs
real(r_kind),dimension(4,0:ns),  intent(out):: ws
!---------------------------------------------------------------------------
real(r_kind),dimension(0:nz):: zs
real(r_kind)                :: z
integer(i_kind)            :: is,iz,liz,miz
!===========================================================================
do iz=0,nz
   zs(iz)=iz
enddo
do is=0,ns
   z=zofs(is); iz=min(nz-1,max(0,floor(z)))
   if(iz==0)       then; liz=0;    miz=2
   elseif(iz==nz-1)then; liz=nz-2; miz=nz
   else;                 liz=iz-1; miz=iz+2
   endif
   if(miz==liz+2)then; call wint3(zs(liz:miz),z,ws(1:3,is)); ws(4,is)=0
   else;               call whint(zs(liz:miz),z,ws(:,is))
   endif
   lizs(is)=liz
   mizs(is)=miz
enddo
end subroutine wintgrid

!===========================================================================
subroutine logintgrid(nz,ns,zofs,az, as)!                       [logintgrid]
!===========================================================================
! From a grid [0:nz] of positive values, az, use logarithms
! to ensure that the smooth interpolation to a new grid [0:ns]
! of target values, as, all remain positive. The array zofs
! defines the index z-grid coordinates of each of the s-grid points.
!============================================================================
use phint, only: wint3,whint
implicit none
integer(i_kind),            intent(in ):: nz,ns
real(r_kind),dimension(0:ns),intent(in ):: zofs
real(r_kind),dimension(0:nz),intent(in ):: az
real(r_kind),dimension(0:ns),intent(out):: as
!----------------------------------------------------------------------------
real(r_kind),dimension(0:nz):: logaz
!============================================================================
logaz=log(az)
call intgrid(nz,ns,zofs,logaz, as)
as=exp(as)
end subroutine logintgrid
!===========================================================================
subroutine logintgridw(nz,ns,lizs,mizs,ws,az, as)!              [logintgrid]
!===========================================================================
! From a grid [0:nz] of positive values, az, use logarithms
! to ensure that the smooth interpolation to a new grid [0:ns]
! of target values, as, all remain positive. The interpolation parameters
! are supplied in the arrays of stencil index limits, lizs, mizs, and
! associated interpolation weights, ws.
!============================================================================
use phint, only: wint3,whint
implicit none
integer(i_kind),                intent(in ):: nz,ns
integer(i_kind),dimension(0:ns),intent(in ):: lizs,mizs
real(r_kind),  dimension(4,0:ns),intent(in ):: ws
real(r_kind),dimension(0:nz),    intent(in ):: az
real(r_kind),dimension(0:ns),    intent(out):: as
!----------------------------------------------------------------------------
real(r_kind),dimension(0:nz):: logaz
!============================================================================
logaz=log(az)
call intgridw(nz,ns,lizs,mizs,ws,logaz, as)
as=exp(as)
end subroutine logintgridw

!============================================================================
subroutine sofztozofs_f(nz,nfz,ns,sofz,s0,ds,zofs)!              [sofztoztos]
!============================================================================
! From monotonic profile sofz, use smooth interpolation and a z-grid
! refined by a factor of nfz, to derive the inverse monotonic profile
! zofs of the index-coordinate of z in a grid that uniformly resolves
! the range of s. The s grid starts at s=s0 (at index is =0) and
! increases by increments ds.
!============================================================================
implicit none
integer(i_kind)            ,intent(in ):: nz,nfz,ns
real(r_kind),dimension(0:nz),intent(in ):: sofz
real(r_kind),                intent(out):: s0,ds
real(r_kind),dimension(0:ns),intent(out):: zofs
!---------------------------------------------------------------------------
real(r_kind),dimension(0:nz*nfz):: sofzf
integer(i_kind)                :: nzf
!============================================================================
nzf=nz*nfz
call monotonicrefine(nz,nfz,sofz,sofzf)
call sofztozofs(nzf,ns,sofzf, s0,ds,zofs)
zofs=zofs/nfz
end subroutine sofztozofs_f
!============================================================================
subroutine sofztozofs(nz,ns,sofzu, s0,ds,zofs)!                  [sofztozofs]
!============================================================================
! Given a monotonic profile, sofzu, on the z-grid [0:nz], and assuming
! piecewise linearity in each interval, get the reciprocal relationship,
! a profile of z index coordinates zofs at each of a uniform grid [0:ns] of
! the s spanning the range sofzu(0):sofzu(nz), and return s0=sofzu(0)
! and the s-grid interval ds=(sofzu(nz)-s0)/ns.
!============================================================================
implicit none
integer(i_kind),            intent(in ):: nz,ns
real(r_kind),dimension(0:nz),intent(in ):: sofzu
real(r_kind),                intent(out):: s0,ds
real(r_kind),dimension(0:ns),intent(out):: zofs
!----------------------------------------------------------------------------
real(r_kind),dimension(0:nz):: sofz
real(r_kind)                :: s
integer(i_kind)            :: iz,izp,is,jzp
!============================================================================
s0=sofzu(0); ds=(sofzu(nz)-s0)/ns
sofz=(sofzu-s0)/ds
zofs(0)=0
zofs(ns)=nz
jzp=1
do is=1,ns-1
   s=is
   ! Search izp=iz+1 that ensures s belongs in interval sofz[iz,izp]
   do izp=jzp,nz-1
      if(sofz(izp)>=s)exit
   enddo
   jzp=izp; iz=izp-1
   zofs(is)=iz+(s-sofz(iz))/(sofz(izp)-sofz(iz))! <- Linear interpolation
enddo
end subroutine sofztozofs

!============================================================================
subroutine monotonicrefine(nz,nfz,sofz,sofzf)!              [monotonicrefine]
!============================================================================
! Refine the monotonic gridded values sofz from z-grid [0:nz] to a
! uniformly refined zf-grid [0:nzf], nzf=nz*nfz. The method involves
! iterative interpolations and corrections of logarithms of finite
! differences, and the numerical integration of the exponentials
! of the interpolated values in such a way that non-positive amounts
! in the integration are not possible, thus preserving monotonicity.
! The nonlinearity of exponentials and logarithms necessitates the
! iterations. Once a convergence criterion, slightly larger than
! typical roundoff, is attained, we continue to allow a few
! additional iterations to let the final result get closer to its
! own characteristic round-off limit.
!============================================================================
use jp_pietc, only: u1,o2
implicit none
integer(i_kind),                intent(in ):: nz,nfz
real(r_kind),dimension(0:nz),    intent(in ):: sofz
real(r_kind),dimension(0:nz*nfz),intent(out):: sofzf
!----------------------------------------------------------------------------
integer(i_kind),parameter        :: nit=100
real(r_kind),parameter            :: eps=1.e-12
real(r_kind),dimension(nz)        :: dsdz,dsdzt,ldsdz,ldsdzt
real(r_kind),dimension(4,nz*nfz)  :: wzf
real(r_kind),dimension(nz*nfz)    :: zofzf,dsdzf,ldsdzf
real(r_kind)                      :: dzf,norm,r
integer(i_kind),dimension(nz*nfz):: lizzf,mizzf
integer(i_kind)                  :: iz,izm,izf,it,nzm,nzf,nzfm,lizf,mizf,mit
!============================================================================
nzm=nz-1; nzf=nz*nfz; nzfm=nzf-1
dzf=u1/nfz! <- interval of uniform fine grid zf
! Set up fine staggered z-grid:
do izf=1,nzf
   zofzf(izf)=dzf*(izf-o2)-o2
enddo
! Set up weights and index parameters for interpolation to zofzf targets: 
call wintgrid(nzm,nzfm,zofzf, lizzf,mizzf,wzf)
! compute coarse finite difference dsdz on staggered grid and take its log:
do iz=1,nz
   dsdz(iz)=sofz(iz)-sofz(iz-1)
   ldsdz(iz)=log(dsdz(iz))
enddo
ldsdzt=0
! Iterative adjust an approximation ldsdzt of staggered log(dsdz) such that,
! when interpolated to a finer grid, exponentiated, and intergated in
! each successive coarse interval, it reproduces the staggered dsdz
! (if possible)
mit=nit+1
do it=1,nit ! Iterate up to nit times, but exit early if possible

! Increment profile ldsdzt by ldsdz to improve match of next dsdzt to dsdz:   
   do iz=1,nz
      ldsdzt(iz)=ldsdzt(iz)+ldsdz(iz)
   enddo
   
   ! Interpolate ldsdzt to a staggered refined grid:
   call intgrid(nzm,nzfm,lizzf,mizzf,wzf,ldsdzt,ldsdzf)
   dsdzf=exp(ldsdzf)! <-get corresponding dsdzf by taking the exponential
   
   ! integrate to get dsdzt in each is interval for comparison with dsdz:
   do iz=1,nz
      mizf=iz*nfz; lizf=mizf-nfz+1
      dsdzt(iz)=dzf*sum(dsdzf(lizf:mizf))
      ldsdz(iz)=log(dsdz(iz)/dsdzt(iz))
   enddo
   norm=sum(abs(ldsdz))/nz
   if(norm<eps)mit=min(mit,it+it/3)! <- Anticipate full convergence soon
   if(it>=mit)exit ! <- Full convergence presumed achieved at this point
enddo! it

! Integrate dsdzf on the fine grid to get monotonic sofzf consitent with
! the original coarse grid sofz
do iz=1,nz
   izm=iz-1
   r=dzf*dsdz(iz)/dsdzt(iz)! <- r approximates dzf if convergence succeeded.
   sofzf(izm*nfz)=sofz(izm)! <- Match fine grid sofzf to coarse grid sofz
   ! Integrate fine-grid dsdzf across the interior of coarse interval iz:
   do izf=izm*nfz+1,iz*nfz-1
      sofzf(izf)=sofzf(izf-1)+r*dsdzf(izf)
   enddo
enddo
sofzf(nzf)=sofz(nz)! <- Match last fine grid sofzf to last coarse grid sofz
end subroutine monotonicrefine
subroutine intgrid_f2a_3d(nz, ns, nx, ny, zofs, az,as)
!------------------------------------------------------------------------------
! Interpolates in vertical (first) dimension using zofs(0:ns,nx,ny)
! Output: az(0:nz, nx, ny)
!------------------------------------------------------------------------------
implicit none

integer(i_kind),               intent(in)  :: nz, ns, nx, ny
real(r_kind), dimension(0:ns), intent(in)  :: zofs
real(r_kind), dimension(0:ns,nx,ny), intent(in)  :: as
real(r_kind), dimension(0:nz,nx,ny), intent(out) :: az

! Local
real(r_kind), dimension(3) :: w3
real(r_kind), dimension(4) :: w4
real(r_kind)               :: z
integer(i_kind)           :: i, j, k, s

!------------------------------------------------------------------------------
!write(6,*)'thinkdeb10000  zofs in interpolation zofs ',zofs
do j = 1, ny
  do i = 1, nx
    do k = 0, nz
      z = real(k, r_kind)  ! target vertical level index

      ! Find s such that zofs(s+1,i,j) > z ≥ zofs(s,i,j)
      s = 0
      do while (s < ns-1 .and. zofs(s+1) < z)
        s = s + 1
      end do

      if (s <= 1) then
        call wint3(zofs(0:2), z, w3)
        az(k,i,j) = dot_product(w3, as(0:2,i,j))
      elseif (s >= ns-1) then
        call wint3(zofs(ns-2:ns), z, w3)
        az(k,i,j) = dot_product(w3, as(ns-2:ns,i,j))
      else
        call whint(zofs(s-1:s+2), z, w4)
        az(k,i,j) = dot_product(w4, as(s-1:s+2,i,j))
      end if

    end do
  end do
end do

end subroutine intgrid_f2a_3d
subroutine intgrid_f2a_3d_top2bot(nz, ns, nx, ny, zofs, az, as)
!------------------------------------------------------------------------------
! Interpolates in vertical (first) dimension using zofs(0:ns,nx,ny)
! Arrays are stored from top (0) to bottom (ns/nz)
! Output: az(0:nz, nx, ny)
!------------------------------------------------------------------------------
implicit none

integer(i_kind),               intent(in)  :: nz, ns, nx, ny
real(r_kind), dimension(0:ns), intent(in)  :: zofs
real(r_kind), dimension(0:ns,nx,ny), intent(in)  :: as
real(r_kind), dimension(0:nz,nx,ny), intent(out) :: az

! Local
real(r_kind), dimension(3) :: w3
real(r_kind), dimension(4) :: w4
real(r_kind)               :: z
integer(i_kind)           :: i, j, k, s

!------------------------------------------------------------------------------
do j = 1, ny
  do i = 1, nx
    do k = 0, nz
      z = real(nz - k+1, r_kind)  ! Map k (top-to-bottom) to physical z (bottom-to-top)

      ! Find s such that zofs(s+1) < z ≤ zofs(s)
      s = 0
      do while (s < ns-1 .and. zofs(s+1) > z)
        s = s + 1
      end do

      if (s <= 1) then
        call v1_wint3(zofs(0:2), z, w3)
        az(k,i,j) = dot_product(w3, as(0:2,i,j))
      elseif (s >= ns-1) then
        call v1_wint3(zofs(ns-2:ns), z, w3)
        az(k,i,j) = dot_product(w3, as(ns-2:ns,i,j))
      else
        call v1_whint(zofs(s-1:s+2), z, w4)
        az(k,i,j) = dot_product(w4, as(s-1:s+2,i,j))
      end if

    end do
  end do
end do

end subroutine intgrid_f2a_3d_top2bot

subroutine intgrid_f2a_3d_top2bot_fast(nz, ns, nx, ny, zofs, az, as)
!------------------------------------------------------------------------------
! Optimized vertical interpolation (top-to-bottom storage)
! Precomputes mapping and weights, then applies to all horizontal points
!------------------------------------------------------------------------------
use phint, only: v1_wint3, v1_whint
implicit none

integer(i_kind),               intent(in)  :: nz, ns, nx, ny
real(r_kind), dimension(0:ns), intent(in)  :: zofs
real(r_kind), dimension(0:ns,nx,ny), intent(in)  :: as
real(r_kind), dimension(0:nz,nx,ny), intent(out) :: az

! Local
integer :: k, s, m, i, j
real(r_kind) :: z
integer, parameter :: wint3_type=1, wint3_top_type=2, whint_type=3
integer, dimension(0:nz) :: interp_type
integer, dimension(4,0:nz) :: src_inds
real(r_kind), dimension(4,0:nz) :: weights
real(r_kind), dimension(3) :: w3
real(r_kind), dimension(4) :: w4

!------------------ Precompute indices and weights ----------------------------
do k = 0, nz
  z = real(nz - k+1, r_kind)  ! Map k (top-to-bottom) to physical z (bottom-to-top)
  s = 0
  do while (s < ns-1 .and. zofs(s+1) > z)
    s = s + 1
  end do

  if (s <= 1) then
    call v1_wint3(zofs(0:2), z, w3)
    interp_type(k) = wint3_type
    src_inds(1:3,k) = (/0,1,2/)
    weights(1:3,k) = w3
    src_inds(4,k) = -1
    weights(4,k) = 0.0_r_kind
  elseif (s >= ns-1) then
    call v1_wint3(zofs(ns-2:ns), z, w3)
    interp_type(k) = wint3_top_type
    src_inds(1:3,k) = (/ns-2, ns-1, ns/)
    weights(1:3,k) = w3
    src_inds(4,k) = -1
    weights(4,k) = 0.0_r_kind
  else
    call v1_whint(zofs(s-1:s+2), z, w4)
    interp_type(k) = whint_type
    src_inds(1:4,k) = (/s-1, s, s+1, s+2/)
    weights(1:4,k) = w4
  end if
end do

!------------------ Apply interpolation using precomputed weights -------------
do j = 1, ny
  do i = 1, nx
    do k = 0, nz
      select case (interp_type(k))
      case (wint3_type, wint3_top_type)
        az(k,i,j) = 0.0_r_kind
        do m = 1, 3
          az(k,i,j) = az(k,i,j) + weights(m,k) * as(src_inds(m,k),i,j)
        end do
      case (whint_type)
        az(k,i,j) = 0.0_r_kind
        do m = 1, 4
          az(k,i,j) = az(k,i,j) + weights(m,k) * as(src_inds(m,k),i,j)
        end do
      end select
    end do
  end do
end do

end subroutine intgrid_f2a_3d_top2bot_fast

subroutine intgrid_f2a_3d_ad_top2bot_fast(nz, ns, nx, ny, zofs, az_ad, as_ad)
!------------------------------------------------------------------------------
! Optimized adjoint of vertical interpolation (top-to-bottom storage)
! Precomputes mapping and weights, then applies to all horizontal points
! Input: az_ad(0:nz, nx, ny)
! Output: as_ad(0:ns, nx, ny) (accumulated)
!------------------------------------------------------------------------------
use phint, only: wint3, whint
implicit none

integer(i_kind),               intent(in)  :: nz, ns, nx, ny
real(r_kind), dimension(0:ns), intent(in)  :: zofs
real(r_kind), dimension(0:nz,nx,ny), intent(in)  :: az_ad
real(r_kind), dimension(0:ns,nx,ny), intent(inout) :: as_ad

! Local
integer :: k, s, m, i, j
real(r_kind) :: z
integer, parameter :: wint3_type=1, wint3_top_type=2, whint_type=3
integer, dimension(0:nz) :: interp_type
integer, dimension(4,0:nz) :: src_inds
real(r_kind), dimension(4,0:nz) :: weights
real(r_kind), dimension(3) :: w3
real(r_kind), dimension(4) :: w4

!------------------ Precompute indices and weights ----------------------------
do k = 0, nz
  z = real(nz - k+1, r_kind)  ! Map k (top-to-bottom) to physical z (bottom-to-top)
  s = 0
  do while (s < ns-1 .and. zofs(s+1) > z)
    s = s + 1
  end do

  if (s <= 1) then
    call v1_wint3(zofs(0:2), z, w3)
    interp_type(k) = wint3_type
    src_inds(1:3,k) = (/0,1,2/)
    weights(1:3,k) = w3
    src_inds(4,k) = -1
    weights(4,k) = 0.0_r_kind
  elseif (s >= ns-1) then
    call v1_wint3(zofs(ns-2:ns), z, w3)
    interp_type(k) = wint3_top_type
    src_inds(1:3,k) = (/ns-2, ns-1, ns/)
    weights(1:3,k) = w3
    src_inds(4,k) = -1
    weights(4,k) = 0.0_r_kind
  else
    call v1_whint(zofs(s-1:s+2), z, w4)
    interp_type(k) = whint_type
    src_inds(1:4,k) = (/s-1, s, s+1, s+2/)
    weights(1:4,k) = w4
  end if
end do

!------------------ Apply adjoint interpolation using precomputed weights -------------
! as_ad should be initialized to zero before accumulation
as_ad(:,:,:) = 0.0_r_kind

do j = 1, ny
  do i = 1, nx
    do k = 0, nz
      select case (interp_type(k))
      case (wint3_type, wint3_top_type)
        do m = 1, 3
          if (src_inds(m,k) >= 0 .and. src_inds(m,k) <= ns) then
            as_ad(src_inds(m,k),i,j) = as_ad(src_inds(m,k),i,j) + weights(m,k) * az_ad(k,i,j)
          end if
        end do
      case (whint_type)
        do m = 1, 4
          if (src_inds(m,k) >= 0 .and. src_inds(m,k) <= ns) then
            as_ad(src_inds(m,k),i,j) = as_ad(src_inds(m,k),i,j) + weights(m,k) * az_ad(k,i,j)
          end if
        end do
      end select
    end do
  end do
end do

end subroutine intgrid_f2a_3d_ad_top2bot_fast



subroutine intgrid_f2a_3d_ad(nz, ns, nx, ny, zofs, az_ad, as_ad)
!------------------------------------------------------------------------------
! Adjoint of intgrid_synthesis_3d
! Accumulates az_ad(0:nz,nx,ny) into as_ad(0:ns,nx,ny)
!------------------------------------------------------------------------------
implicit none

integer(i_kind),               intent(in)    :: nz, ns, nx, ny
real(r_kind), dimension(0:ns), intent(in)  :: zofs
real(r_kind), dimension(0:nz,nx,ny), intent(in)  :: az_ad
real(r_kind), dimension(0:ns,nx,ny), intent(inout) :: as_ad  ! inout to accumulate

! Local
real(r_kind), dimension(3) :: w3
real(r_kind), dimension(4) :: w4
real(r_kind)               :: z
integer(i_kind)           :: i, j, k, s

!------------------------------------------------------------------------------
write(6,*)'intgrid_f2a_3d_ad 1 ',ny,nx,nz
!clt todo some optimization could be done, when the interpolation coeff is homogeneous
do j = 1, ny
  do i = 1, nx
    do k = 0, nz
      z = real(k, r_kind)

      s = 0
      do while (s < ns-1 .and. zofs(s+1) < z)
        s = s + 1
      end do

      if (s <= 1) then
        call wint3(zofs(0:2), z, w3)
        as_ad(0:2,i,j) = as_ad(0:2,i,j) + az_ad(k,i,j) * w3
      elseif (s >= ns-1) then
        call wint3(zofs(ns-2:ns), z, w3)
        as_ad(ns-2:ns,i,j) = as_ad(ns-2:ns,i,j) + az_ad(k,i,j) * w3
      else
        call whint(zofs(s-1:s+2), z, w4)
        as_ad(s-1:s+2,i,j) = as_ad(s-1:s+2,i,j) + az_ad(k,i,j) * w4
      end if

    end do
  end do
end do
write(6,*)'intgrid_f2a_3d_ad 100'
call flush(6)

end subroutine intgrid_f2a_3d_ad
subroutine intgrid_f2a_3d_ad_top2bot(nz, ns, nx, ny, zofs, az, as)
!------------------------------------------------------------------------------
! Adjoint of vertical interpolation: accumulates from az (on z) to as (on s)
! Arrays are stored from top (0) to bottom (ns/nz)
! Input: az(0:nz, nx, ny)
! Output: as(0:ns, nx, ny) (accumulated)
!------------------------------------------------------------------------------
implicit none

integer(i_kind),               intent(in)  :: nz, ns, nx, ny
real(r_kind), dimension(0:ns), intent(in)  :: zofs
real(r_kind), dimension(0:nz,nx,ny), intent(in)  :: az
real(r_kind), dimension(0:ns,nx,ny), intent(inout) :: as

! Local
real(r_kind), dimension(3) :: w3
real(r_kind), dimension(4) :: w4
real(r_kind)               :: z
integer(i_kind)           :: i, j, k, s, m

!------------------------------------------------------------------------------
! Zero out as (if not already done)
as(:,:,:) = 0.0_r_kind

do j = 1, ny
  do i = 1, nx
    do k = 0, nz
!clttothink
      z = real(nz - k+1, r_kind)  ! Map k (top-to-bottom) to physical z (bottom-to-top)

      ! Find s such that zofs(s+1) < z ≤ zofs(s)
      s = 0
      do while (s < ns-1 .and. zofs(s+1) > z)
        s = s + 1
      end do

      if (s <= 1) then
        call v1_wint3(zofs(0:2), z, w3)
        do m = 0, 2
          as(m,i,j) = as(m,i,j) + w3(m+1) * az(k,i,j)
        end do
      elseif (s >= ns-1) then
        call v1_wint3(zofs(ns-2:ns), z, w3)
        do m = ns-2, ns
          as(m,i,j) = as(m,i,j) + w3(m-ns+3) * az(k,i,j)
        end do
      else
        call v1_whint(zofs(s-1:s+2), z, w4)
        do m = s-1, s+2
          as(m,i,j) = as(m,i,j) + w4(m-s+2) * az(k,i,j)
        end do
      end if

    end do
  end do
end do

end subroutine intgrid_f2a_3d_ad_top2bot

end module phint1
!#

