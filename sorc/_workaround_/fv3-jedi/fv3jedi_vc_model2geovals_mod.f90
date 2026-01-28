! (C) Copyright 2020-2024 UCAR
!
! This software is licensed under the terms of the Apache Licence Version 2.0
! which can be obtained at http://www.apache.org/licenses/LICENSE-2.0.

module fv3jedi_vc_model2geovals_mod

use iso_c_binding

use fckit_configuration_module, only: fckit_configuration
use fckit_log_module,           only: fckit_log

use datetime_mod

use fv3jedi_constants_mod, only: constant
use fv3jedi_geom_mod,      only: fv3jedi_geom
use fv3jedi_fieldfail_mod, only: field_fail
use fv3jedi_field_mod,     only: copy_subset, field_clen
use fv3jedi_kinds_mod,     only: kind_real
use fv3jedi_state_mod,     only: fv3jedi_state

use height_vt_mod
use moisture_vt_mod
use radii_vt_mod, only: crtm_ade_efr
use pressure_vt_mod
use surface_vt_mod
use temperature_vt_mod
use wind_vt_mod

implicit none

private
public :: fv3jedi_vc_model2geovals

type :: fv3jedi_vc_model2geovals
  integer :: isc, iec, jsc, jec, npz
  character(len=10) :: tropprs_method
  character(len=16) :: radii_method
  character(len=8) :: use_mask
  contains
    procedure, public :: create
    procedure, public :: delete
    procedure, public :: changevar
end type fv3jedi_vc_model2geovals

! --------------------------------------------------------------------------------------------------

contains

! --------------------------------------------------------------------------------------------------

subroutine create(self, geom, conf)

class(fv3jedi_vc_model2geovals), intent(inout) :: self
type(fv3jedi_geom),              intent(in)    :: geom
type(fckit_configuration),       intent(in)    :: conf

character(len=:), allocatable :: str

! Method to use for tropopause pressure ([gsi] or thompson)
if (.not. conf%get('tropopause pressure method', str)) str = 'gsi'
self%tropprs_method = trim(str)

! Method to use for calculating effective radii (thompson, [gfdl], or gsi)
if (.not. conf%get('hydrometeor effective radii method', str)) str = 'gfdl'
self%radii_method = trim(str)

! We can mask either the land or the sea, default is neither.
if (.not. conf%get('mask over', str)) str = 'none'
self%use_mask = trim(str)

! Grid convenience
self%isc = geom%isc
self%iec = geom%iec
self%jsc = geom%jsc
self%jec = geom%jec
self%npz = geom%npz

end subroutine create

! --------------------------------------------------------------------------------------------------

subroutine delete(self)

class(fv3jedi_vc_model2geovals), intent(inout) :: self

end subroutine delete

! --------------------------------------------------------------------------------------------------

subroutine changevar(self, geom, xm, xg)

class(fv3jedi_vc_model2geovals), intent(inout) :: self
type(fv3jedi_geom),              intent(inout) :: geom
type(fv3jedi_state),             intent(in)    :: xm
type(fv3jedi_state),             intent(inout) :: xg

integer :: f, jlev, i, j, k
character(len=field_clen), allocatable :: fields_to_do(:)
real(kind=kind_real), pointer :: field_ptr(:,:,:)

! Specific humidity
logical :: have_q
real(kind=kind_real), pointer     :: q     (:,:,:)         !Specific humidity

! moist_air_density
logical :: have_airdens
real(kind=kind_real), allocatable :: rho_air (:,:,:)       !moist_air_density
real(kind=kind_real), allocatable :: q_ge_0 (:,:,:)

! Relative humidity
logical :: have_qsat, have_rh
real(kind=kind_real), allocatable :: rh    (:,:,:)         !Relative humidity
real(kind=kind_real), allocatable :: qsat   (:,:,:)        !Saturation specific humidity

! Pressure fields
logical :: have_pressures
real(kind=kind_real), allocatable :: ps    (:,:,:)         !Surface pressure
real(kind=kind_real), allocatable :: delp  (:,:,:)         !Pressure thickness
real(kind=kind_real), allocatable :: prsi  (:,:,:)         !Pressure, interfaces
real(kind=kind_real), allocatable :: prs   (:,:,:)         !Pressure, midpoint
real(kind=kind_real), allocatable :: pkz   (:,:,:)         !Pressure to the kapaa

! Temperature fields
logical :: have_t
real(kind=kind_real), allocatable :: t     (:,:,:)         !Temperature

! Vitual temperature
logical :: have_tv
real(kind=kind_real), allocatable :: tv    (:,:,:)         !Virtual temperature

! Heights
logical :: have_geoph
real(kind=kind_real), allocatable :: geophi(:,:,:)         !Geopotential height, interfaces
real(kind=kind_real), allocatable :: geoph (:,:,:)         !Geopotential height
real(kind=kind_real), allocatable :: suralt(:,:,:)         !Surface height above mean sea level pressure
real(kind=kind_real), allocatable :: phis  (:,:,:)         !Surface geopotential height times gravity
logical,  parameter :: use_compress = .true.

! Layer thickness
logical :: have_delz
real(kind=kind_real), allocatable :: delz(:,:,:)

! Ozone
logical :: have_o3
real(kind=kind_real), allocatable :: o3mr  (:,:,:)         !Ozone mixing ratio
real(kind=kind_real), allocatable :: o3ppmv(:,:,:)         !Ozone ppmv

! Winds
logical :: have_winds
real(kind=kind_real), allocatable :: ua    (:,:,:)         !Eastward wind
real(kind=kind_real), allocatable :: va    (:,:,:)         !Northward wind
real(kind=kind_real), allocatable :: ud    (:,:,:)         !u component D-grid
real(kind=kind_real), allocatable :: vd    (:,:,:)         !v component D-grid

! Surface roughness length
logical :: have_zorl
real(kind=kind_real), pointer     :: zorl     (:,:,:)      !Incoming in centimeters
real(kind=kind_real), allocatable :: sfc_rough(:,:,:)      !Outgoing in meters

! Sea-land mask
logical :: have_slmsk
real(kind=kind_real), allocatable :: slmsk   (:,:,:)       !Land-sea mask
real(kind=kind_real), pointer     :: frocean (:,:,:)       !Fraction ocean
real(kind=kind_real), pointer     :: frlake  (:,:,:)       !Fraction lake
real(kind=kind_real), pointer     :: frseaice(:,:,:)       !Fraction seaice

!f10m
logical :: have_f10m
real(kind=kind_real), allocatable :: f10m    (:,:,:)       !Surface wind reduction factor
real(kind=kind_real), pointer     :: u_srf   (:,:,:)
real(kind=kind_real), pointer     :: v_srf   (:,:,:)
real(kind=kind_real) :: wspd

!observable_domain_mask
logical :: have_domain_mask
real(kind=kind_real), allocatable :: observable_domain_mask(:,:,:)    !domain mask

!qiql
logical :: have_qiql
real(kind=kind_real), allocatable :: qi      (:,:,:)
real(kind=kind_real), allocatable :: ql      (:,:,:)
real(kind=kind_real), pointer     :: qils    (:,:,:)
real(kind=kind_real), pointer     :: qicn    (:,:,:)
real(kind=kind_real), pointer     :: qlls    (:,:,:)
real(kind=kind_real), pointer     :: qlcn    (:,:,:)

!qr, qs, and qg (rain, snow, and graupel)
logical :: have_qr
logical :: have_qs
logical :: have_qg
real(kind=kind_real), allocatable :: qr      (:,:,:)
real(kind=kind_real), allocatable :: qs      (:,:,:)
real(kind=kind_real), allocatable :: qg      (:,:,:)
real(kind=kind_real), pointer     :: qrls    (:,:,:)
real(kind=kind_real), pointer     :: qrcn    (:,:,:)
real(kind=kind_real), pointer     :: qsls    (:,:,:)
real(kind=kind_real), pointer     :: qscn    (:,:,:)

! Number mixing ratio variables (2-moment microphysics)
logical :: have_nc
real(kind=kind_real), allocatable :: nc      (:,:,:)
logical :: have_ni
real(kind=kind_real), allocatable :: ni      (:,:,:)
logical :: have_nr
real(kind=kind_real), allocatable :: nr      (:,:,:)

!CRTM mixing ratio
logical :: have_qmr
real(kind=kind_real), allocatable :: qmr     (:,:,:)       !Land-sea mask

!CRTM moisture fields
logical :: have_crtm_cld
real(kind=kind_real), allocatable :: ql_ade  (:,:,:)
real(kind=kind_real), allocatable :: qi_ade  (:,:,:)
real(kind=kind_real), allocatable :: qr_ade  (:,:,:)
real(kind=kind_real), allocatable :: qs_ade  (:,:,:)
real(kind=kind_real), allocatable :: qg_ade  (:,:,:)
real(kind=kind_real), allocatable :: ql_efr  (:,:,:)
real(kind=kind_real), allocatable :: qi_efr  (:,:,:)
real(kind=kind_real), allocatable :: qr_efr  (:,:,:)
real(kind=kind_real), allocatable :: qs_efr  (:,:,:)
real(kind=kind_real), allocatable :: qg_efr  (:,:,:)
real(kind=kind_real), allocatable :: watercov(:,:)
real(kind=kind_real), allocatable :: ql_colm (:,:,:)
real(kind=kind_real), allocatable :: qi_colm (:,:,:)
real(kind=kind_real), allocatable :: qr_colm (:,:,:)
real(kind=kind_real), allocatable :: qs_colm (:,:,:)
real(kind=kind_real), allocatable :: qg_colm (:,:,:)

! CO2
logical :: have_co2
real(kind=kind_real), allocatable :: co2     (:,:,:)

!Salinity
logical :: have_sss
real(kind=kind_real), allocatable :: sss     (:,:,:)

!Skin Temperature
logical :: have_tskin
real(kind=kind_real), pointer     :: tskin   (:,:,:)

!CRTM surface
logical :: have_crtm_surface, have_soilt, have_soilm
integer :: sec_of_year
real(kind=kind_real) :: fractional_day_of_year
real(kind=kind_real), pointer     :: sheleg   (:,:,:)
real(kind=kind_real), pointer     :: vtype    (:,:,:)
real(kind=kind_real), pointer     :: stype    (:,:,:)
real(kind=kind_real), pointer     :: vfrac    (:,:,:)
real(kind=kind_real), allocatable :: soilt    (:,:,:)
real(kind=kind_real), allocatable :: soilm    (:,:,:)
real(kind=kind_real), pointer     :: soil_tmp (:,:,:)
real(kind=kind_real), allocatable :: land_type_index_npoess                    (:,:,:)
real(kind=kind_real), allocatable :: land_type_index_igbp                      (:,:,:)
real(kind=kind_real), allocatable :: vegetation_type_index                     (:,:,:)
real(kind=kind_real), allocatable :: soil_type                                 (:,:,:)
real(kind=kind_real), allocatable :: water_area_fraction                       (:,:,:)
real(kind=kind_real), allocatable :: land_area_fraction                        (:,:,:)
real(kind=kind_real), allocatable :: ice_area_fraction                         (:,:,:)
real(kind=kind_real), allocatable :: surface_snow_area_fraction                (:,:,:)
real(kind=kind_real), allocatable :: leaf_area_index                           (:,:,:)
real(kind=kind_real), allocatable :: skin_temperature_at_surface_where_sea     (:,:,:)
real(kind=kind_real), allocatable :: skin_temperature_at_surface_where_land    (:,:,:)
real(kind=kind_real), allocatable :: skin_temperature_at_surface_where_ice     (:,:,:)
real(kind=kind_real), allocatable :: skin_temperature_at_surface_where_snow    (:,:,:)
real(kind=kind_real), allocatable :: volume_fraction_of_condensed_water_in_soil(:,:,:)
real(kind=kind_real), allocatable :: vegetation_area_fraction                  (:,:,:)
real(kind=kind_real), allocatable :: soil_temperature                          (:,:,:)
real(kind=kind_real), allocatable :: surface_snow_thickness                    (:,:,:)
real(kind=kind_real), allocatable :: wind_speed_at_surface                     (:,:,:)
real(kind=kind_real), allocatable :: wind_from_direction_at_surface            (:,:,:)
real(kind=kind_real), allocatable :: sea_surface_salinity                      (:,:,:)
real(kind=kind_real), allocatable :: skin_temperature_at_surface               (:,:,:)

! Snow depth
logical :: have_snwdph
real(kind=kind_real), allocatable :: snwdph(:,:,:)
real(kind=kind_real), allocatable :: snwdph_meters(:,:,:)

! Vorticity
logical :: have_vort
real(kind=kind_real), allocatable :: vort     (:,:,:)
real(kind=kind_real), allocatable :: divg     (:,:,:)

! Tropopause pressure
logical :: have_tropprs
real(kind=kind_real), allocatable :: tprs     (:,:,:)

real(kind=kind_real) :: rdry, zvir
! Constants
rdry = constant('rdry')
zvir = constant('zvir')


! Identity part of the change of fields
! -------------------------------------
call copy_subset(xm%fields, xg%fields, fields_to_do)


! if (geom%f_comm%rank()==0) then
!   do f = 1, size(xm%fields)
!     print*, 'Model2GeoVaLs.changeVar, Model fields:   ', trim(xm%fields(f)%long_name)
!   enddo
!   do f = 1, size(xg%fields)
!     print*, 'Model2GeoVaLs.changeVar, GeoVaLs fields: ', trim(xg%fields(f)%long_name)
!   enddo
!   do f = 1, size(fields_to_do)
!     print*, 'Model2GeoVaLs.changeVar, GeoVaLs needed by transform: ', trim(fields_to_do(f))
!   enddo
! endif


! If variable change is the identity early exit
! ---------------------------------------------
if (.not.allocated(fields_to_do)) return


! Get pressures at edge, center & log center
! ------------------------------------------
have_pressures = .false.

if (xm%has_field('air_pressure_thickness')) then
  call xm%get_field('air_pressure_thickness', delp)
  allocate(ps(self%isc:self%iec, self%jsc:self%jec, 1))
  ps(:,:,1) = geom%ptop + sum(delp,3)
  have_pressures = .true.
elseif (xm%has_field('air_pressure_at_surface')) then
  call xm%get_field('air_pressure_at_surface', ps)
  allocate(delp(self%isc:self%iec, self%jsc:self%jec, self%npz))
  do jlev = 1,self%npz
    delp(:,:,jlev) = (geom%ak(jlev+1)-geom%ak(jlev))+(geom%bk(jlev+1)-geom%bk(jlev))*ps(:,:,1)
  enddo
  have_pressures = .true.
elseif (xm%has_field('air_pressure_levels')) then
  call xm%get_field('air_pressure_levels', prsi)
  allocate(ps(self%isc:self%iec, self%jsc:self%jec, 1))
  ps(:,:,1) = prsi(:,:,self%npz+1)
  allocate(delp(self%isc:self%iec, self%jsc:self%jec, self%npz))
  do jlev = 1,self%npz
    delp(:,:,jlev) = prsi(:,:,jlev+1) - prsi(:,:,jlev)
  enddo
  have_pressures = .true.
endif

if (have_pressures) then
  if (.not.allocated(prsi)) allocate(prsi(self%isc:self%iec,self%jsc:self%jec,self%npz+1))
  if (.not.allocated(prs )) allocate(prs (self%isc:self%iec,self%jsc:self%jec,self%npz  ))
  if (.not.allocated(pkz )) allocate(pkz (self%isc:self%iec,self%jsc:self%jec,self%npz  ))
  call delp_to_pe_p_logp(geom, delp, prsi, prs, pkz=pkz)
endif

! Temperature
! -----------
have_t = .false.
if (xm%has_field( 'air_temperature')) then
  call xm%get_field('air_temperature', t)
  have_t = .true.
endif

! Specific humidity
! -----------------
have_q = .false.
if (xm%has_field('water_vapor_mixing_ratio_wrt_moist_air')) then
  call xm%get_field('water_vapor_mixing_ratio_wrt_moist_air',  q)
  have_q = .true.
endif

! Saturation specific humidity
! ----------------------------
have_qsat = .false.
if (xm%has_field('saturation_water_vapor_mixing_ratio_wrt_moist_air')) then
  call xm%get_field('saturation_water_vapor_mixing_ratio_wrt_moist_air', qsat)
  have_qsat = .true.
elseif (have_t .and. have_pressures .and. have_q) then
  allocate(qsat(self%isc:self%iec,self%jsc:self%jec,self%npz))
  call get_qsat(geom,delp,t,q,qsat)
  have_qsat = .true.
endif

! Relative humidity
! -----------------
have_rh = .false.
if (xm%has_field('relative_humidity')) then
  call xm%get_field('relative_humidity', rh)
  have_rh = .true.
elseif (have_qsat .and. have_q) then
  allocate(rh  (self%isc:self%iec,self%jsc:self%jec,self%npz))
  call q_to_rh(geom,qsat,q,rh)
  have_rh = .true.
endif

! Geopotential height
! -------------------
have_geoph = .false.
if (have_t .and. have_pressures .and. have_q .and. &
    (xm%has_field('geopotential_height_times_gravity_at_surface') .or. &
    xm%has_field('geopotential_height_at_surface') )) then
  if (.not.allocated(phis)) allocate(phis(self%isc:self%iec,self%jsc:self%jec,1))
  if (.not.allocated(suralt)) allocate(suralt(self%isc:self%iec,self%jsc:self%jec,1))
  if ( xm%has_field( 'geopotential_height_times_gravity_at_surface') ) then
     call xm%get_field('geopotential_height_times_gravity_at_surface',  phis)
     suralt = phis / constant('grav')
  else
     call xm%get_field('geopotential_height_at_surface', suralt)
     phis = suralt * constant('grav')
  end if
  if (.not.allocated(geophi)) allocate(geophi(self%isc:self%iec,self%jsc:self%jec,self%npz+1))
  if (.not.allocated(geoph )) allocate(geoph (self%isc:self%iec,self%jsc:self%jec,self%npz  ))
  call geop_height(geom, prs, prsi, t, q, phis(:,:,1), use_compress, geoph)
  call geop_height_levels(geom, prs, prsi, t, q, phis(:,:,1), use_compress, geophi)
  have_geoph = .true.
endif

! Layer thickness
! ---------------
have_delz = .false.
if (xm%has_field('layer_thickness')) then
   call xm%get_field('layer_thickness', delz)
   have_delz = .true.
elseif (have_geoph) then
   allocate(delz(self%isc:self%iec,self%jsc:self%jec,self%npz))
   delz = geophi(:,:,2:self%npz+1) - geophi(:,:,1:self%npz)
   have_delz = .true.
endif

! Virtual temperature
! -------------------
have_tv = .false.
if (xm%has_field( 'virtual_temperature')) then
    call xm%get_field('virtual_temperature', tv)
    have_tv = .true.
elseif (have_t .and. have_q) then
  allocate(tv(self%isc:self%iec,self%jsc:self%jec,self%npz))
  call t_to_tv(geom, t, q, tv)
  have_tv = .true.
endif


! Ozone
! -----
have_o3   = .false.
if (xm%has_field( 'ozone_mass_mixing_ratio')) then
  call xm%get_field('ozone_mass_mixing_ratio', o3mr)
  allocate(o3ppmv(self%isc:self%iec,self%jsc:self%jec,self%npz))
  o3ppmv = o3mr * constant('constoz')
  have_o3 = .true.
elseif (xm%has_field('mole_fraction_of_ozone_in_air')) then
  call xm%get_field('mole_fraction_of_ozone_in_air', o3ppmv)
  allocate(o3mr(self%isc:self%iec,self%jsc:self%jec,self%npz))
  o3mr = o3ppmv / constant('constoz')
  have_o3 = .true.
endif

if (have_o3) then
  do k = 1, self%npz
    do j = self%jsc, self%jec
      do i = self%isc, self%iec
        if (o3mr(i,j,k) < 0.0_kind_real ) then
          o3mr(i,j,k)   = 0.0_kind_real
          o3ppmv(i,j,k) = 0.0_kind_real
        endif
      enddo
    enddo
  enddo
endif

! Wind transforms
! ---------------
have_winds = .false.
if (xm%has_field('eastward_wind') .and. xm%has_field('northward_wind')) then
  call xm%get_field('eastward_wind', ua)
  call xm%get_field('northward_wind', va)
  have_winds = .true.
endif

! Land sea mask
! -------------
have_slmsk = .false.
if (xm%has_field( 'slmsk')) then
  call xm%get_field('slmsk', slmsk)
  have_slmsk = .true.
elseif ( xm%has_field('fraction_of_ocean' ) .and. xm%has_field('fraction_of_lake'  ) .and. &
         xm%has_field('fraction_of_ice') .and. xm%has_field('skin_temperature_at_surface') ) then
  call xm%get_field('fraction_of_ocean' , frocean )
  call xm%get_field('fraction_of_lake'  , frlake  )
  call xm%get_field('fraction_of_ice', frseaice)
  call xm%get_field('skin_temperature_at_surface', tskin   )

  allocate(slmsk(self%isc:self%iec,self%jsc:self%jec,1))
  slmsk = 1.0_kind_real !Land
  do j = self%jsc,self%jec
    do i = self%isc,self%iec
      if ( frocean(i,j,1) + frlake(i,j,1) >= 0.6_kind_real) then
        slmsk(i,j,1) = 0.0_kind_real ! Water
      endif
      if ( slmsk(i,j,1) == 0.0_kind_real .and. frseaice(i,j,1) > 0.5_kind_real) then
        slmsk(i,j,1) = 2.0_kind_real ! Ice
      endif
      if ( slmsk(i,j,1) == 0.0_kind_real .and. tskin(i,j,1) < 271.4_kind_real ) then
        slmsk(i,j,1) = 2.0_kind_real ! Ice
      endif
    enddo
  enddo
  have_slmsk = .true.
endif


! Transform surface roughness length (zorl) from cm to meters.
! -------------
have_zorl = .false.
allocate(sfc_rough(self%isc:self%iec,self%jsc:self%jec,1))
if (xm%has_field( 'zorl')) then
  call xm%get_field('zorl', zorl)
  have_zorl = .true.
  sfc_rough = zorl*0.01
else
  sfc_rough = 0.01_kind_real
endif


! f10m
! ----
have_f10m = .false.
if (xm%has_field('f10m')) then
  call xm%get_field('f10m', f10m)
  have_f10m = .true.
elseif ( xm%has_field( 'eastward_wind_at_surface') .and. &
         xm%has_field( 'northward_wind_at_surface') .and. have_winds ) then
  call xm%get_field('eastward_wind_at_surface' , u_srf)
  call xm%get_field('northward_wind_at_surface' , v_srf)

  allocate(f10m(self%isc:self%iec,self%jsc:self%jec,1))
  f10m = sqrt(u_srf**2 + v_srf**2)

  do j = self%jsc,self%jec
    do i = self%isc,self%iec
      wspd = sqrt(ua(i,j,self%npz)**2 +  va(i,j,self%npz)**2)
      if (f10m(i,j,1) > 0.0_kind_real) then
        f10m(i,j,1) = f10m(i,j,1)/wspd
      else
        f10m(i,j,1) = 1.0_kind_real
      endif
    enddo
  enddo
  have_f10m = .true.
endif

! observable_domain_mask
! -----------
have_domain_mask = .false.
allocate(observable_domain_mask(self%isc:self%iec, self%jsc:self%jec, 1))

! the compute domain defines the interior of the domain. Set mask index = 0.
observable_domain_mask(self%isc:self%iec, self%jsc:self%jec, 1) = 0.0_kind_real
have_domain_mask = .true.

! CRTM mixing ratio
! -----------------
have_qmr = .false.
if (have_q) then
  allocate(qmr(self%isc:self%iec,self%jsc:self%jec,self%npz))
  call crtm_mixratio(geom, q, qmr)
  have_qmr = .true.
endif

! CO2
! ---
allocate(co2(self%isc:self%iec,self%jsc:self%jec,self%npz))
co2 = 4.07e-4_kind_real !mol mol-1
if (xm%has_field('co2')) then
  call xm%get_field('co2', co2)
endif
have_co2 = .true.

! Clouds
! ------
have_qiql = .false.
if (xm%has_field( 'cloud_liquid_ice') .and. xm%has_field( 'cloud_liquid_water')) then
  call xm%get_field('cloud_liquid_ice', qi)
  call xm%get_field('cloud_liquid_water', ql)
  have_qiql = .true.
elseif (xm%has_field( 'mass_fraction_of_large_scale_cloud_ice_water') .and. &
        xm%has_field( 'mass_fraction_of_convective_cloud_ice_water') .and. &
        xm%has_field( 'mass_fraction_of_large_scale_cloud_liquid_water') .and. &
        xm%has_field( 'mass_fraction_of_convective_cloud_liquid_water')) then
  call xm%get_field('mass_fraction_of_large_scale_cloud_ice_water', qils)
  call xm%get_field('mass_fraction_of_convective_cloud_ice_water', qicn)
  call xm%get_field('mass_fraction_of_large_scale_cloud_liquid_water', qlls)
  call xm%get_field('mass_fraction_of_convective_cloud_liquid_water', qlcn)
  allocate(qi(self%isc:self%iec,self%jsc:self%jec,self%npz))
  allocate(ql(self%isc:self%iec,self%jsc:self%jec,self%npz))
  qi = qils + qicn
  ql = qlls + qlcn
  have_qiql = .true.
endif
! ------ Rain, snow, and graupel
have_qr = .false.
if (xm%has_field( 'rain_water')) then
  call xm%get_field('rain_water', qr)
  have_qr = .true.
endif
! ------
have_qs = .false.
if (xm%has_field( 'snow_water')) then
  call xm%get_field('snow_water', qs)
  have_qs = .true.
endif
! ------
have_qg = .false.
if (xm%has_field('graupel')) then
  call xm%get_field('graupel', qg)
  have_qg = .true.
endif

! 2-moment microphysics number mixing ratios (concentrations)
have_nc = .false.
if (xm%has_field('cloud_droplet_number_concentration')) then
  call xm%get_field('cloud_droplet_number_concentration', nc)
  have_nc = .true.
endif
have_ni = .false.
if (xm%has_field('cloud_ice_number_concentration')) then
  call xm%get_field('cloud_ice_number_concentration', ni)
  have_ni = .true.
endif
have_nr = .false.
if (xm%has_field('rain_number_concentration')) then
  call xm%get_field('rain_number_concentration', nr)
  have_nr = .true.
endif

! Calculate moist_air_density
! ----------------------------
have_airdens = .false.
if (have_t .and. have_pressures .and. have_q) then
  allocate(rho_air(self%isc:self%iec,self%jsc:self%jec,self%npz))
  allocate(q_ge_0(self%isc:self%iec,self%jsc:self%jec,self%npz))
  q_ge_0 = q
  where(q < 0.0_kind_real) q_ge_0 = 0.0_kind_real
  rho_air = prs / (rdry * t * (1.0_kind_real + zvir * q_ge_0))
  deallocate(q_ge_0)
  have_airdens = .true.
endif

! Get CRTM moisture fields
! ------------------------
have_crtm_cld = .false.
if (have_slmsk .and. have_t .and. have_pressures .and. have_q .and. have_qiql ) then
  allocate(ql_ade(self%isc:self%iec,self%jsc:self%jec,self%npz))
  allocate(qi_ade(self%isc:self%iec,self%jsc:self%jec,self%npz))
  allocate(ql_efr(self%isc:self%iec,self%jsc:self%jec,self%npz))
  allocate(qi_efr(self%isc:self%iec,self%jsc:self%jec,self%npz))
  allocate(watercov(self%isc:self%iec,self%jsc:self%jec))
  ql_ade = 0.0_kind_real
  qi_ade = 0.0_kind_real
  ql_efr = 0.0_kind_real
  qi_efr = 0.0_kind_real
  allocate(ql_colm(self%isc:self%iec,self%jsc:self%jec,1))
  allocate(qi_colm(self%isc:self%iec,self%jsc:self%jec,1))
  ql_colm = 0.0_kind_real
  qi_colm = 0.0_kind_real

  !TODO Is it water_area_fraction or sea_coverage fed in here?
  watercov = 0.0_kind_real
  do j = self%jsc,self%jec
    do i = self%isc,self%iec
      if (slmsk(i,j,1) == 0) watercov(i,j) = 1.0_kind_real
    enddo
  enddo
  if (have_qr ) then
    allocate(qr_ade(self%isc:self%iec,self%jsc:self%jec,self%npz))
    allocate(qr_efr(self%isc:self%iec,self%jsc:self%jec,self%npz))
    qr_ade = 0.0_kind_real
    qr_efr = 0.0_kind_real
    allocate(qr_colm(self%isc:self%iec,self%jsc:self%jec,1))
    qr_colm = 0.0_kind_real
  endif
  if (have_qs ) then
    allocate(qs_ade(self%isc:self%iec,self%jsc:self%jec,self%npz))
    allocate(qs_efr(self%isc:self%iec,self%jsc:self%jec,self%npz))
    qs_ade = 0.0_kind_real
    qs_efr = 0.0_kind_real
    allocate(qs_colm(self%isc:self%iec,self%jsc:self%jec,1))
    qs_colm = 0.0_kind_real
  endif
  if (have_qg ) then
    allocate(qg_ade(self%isc:self%iec,self%jsc:self%jec,self%npz))
    allocate(qg_efr(self%isc:self%iec,self%jsc:self%jec,self%npz))
    qg_ade = 0.0_kind_real
    qg_efr = 0.0_kind_real
    allocate(qg_colm(self%isc:self%iec,self%jsc:self%jec,1))
    qg_colm = 0.0_kind_real
  endif

! Call routine that computes liquid/ice water paths and effective radii.
! Different complexity for number of species and 1- or 2-moment microphysics.
! ------------------------

  if (have_nc .and. have_ni .and. have_nr .and. have_qr .and. have_qs .and. have_qg) then
    call crtm_ade_efr(geom=geom, p=prs, t=t, delp=delp, sea_frac=watercov,         &
          q=q, rho_air=rho_air, ql=ql, qi=qi, qr=qr, qs=qs, qg=qg, nc=nc, ni=ni, nr=nr,             &
          ql_ade=ql_ade,qi_ade=qi_ade,qr_ade=qr_ade,qs_ade=qs_ade,qg_ade=qg_ade,   &
          ql_efr=ql_efr,qi_efr=qi_efr,qr_efr=qr_efr,qs_efr=qs_efr,qg_efr=qg_efr,   &
          method=self%radii_method, use_mask=self%use_mask)
  elseif (have_ni .and. have_nr .and. have_qr .and. have_qg) then
    call crtm_ade_efr(geom=geom, p=prs, t=t, delp=delp, sea_frac=watercov,         &
          q=q, rho_air=rho_air, ql=ql, qi=qi, qr=qr, qs=qs, qg=qg, ni=ni, nr=nr,                    &
          ql_ade=ql_ade,qi_ade=qi_ade,qr_ade=qr_ade,qs_ade=qs_ade,qg_ade=qg_ade,   &
          ql_efr=ql_efr,qi_efr=qi_efr,qr_efr=qr_efr,qs_efr=qs_efr,qg_efr=qg_efr,   &
          method=self%radii_method, use_mask=self%use_mask)
  elseif (have_ni .and. have_qs .and. have_qr .and. have_qg) then
    call crtm_ade_efr(geom=geom, p=prs, t=t, delp=delp, sea_frac=watercov,         &
          q=q, rho_air=rho_air, ql=ql, qi=qi, qr=qr, qs=qs, qg=qg, ni=ni,                           &
          ql_ade=ql_ade,qi_ade=qi_ade,qr_ade=qr_ade,qs_ade=qs_ade,qg_ade=qg_ade,   &
          ql_efr=ql_efr,qi_efr=qi_efr,qr_efr=qr_efr,qs_efr=qs_efr,qg_efr=qg_efr,   &
          method=self%radii_method, use_mask=self%use_mask)
  elseif (have_qr .and. have_qs .and. have_qg) then
    call crtm_ade_efr(geom=geom, p=prs, t=t, delp=delp, sea_frac=watercov,         &
          q=q, rho_air=rho_air, ql=ql, qi=qi, qr=qr, qs=qs, qg=qg,                                  &
          ql_ade=ql_ade,qi_ade=qi_ade,qr_ade=qr_ade,qs_ade=qs_ade,qg_ade=qg_ade,   &
          ql_efr=ql_efr,qi_efr=qi_efr,qr_efr=qr_efr,qs_efr=qs_efr,qg_efr=qg_efr,   &
          method=self%radii_method, use_mask=self%use_mask)
  elseif (have_qr .and. have_qs) then
    call crtm_ade_efr(geom=geom, p=prs, t=t, delp=delp, sea_frac=watercov,         &
          q=q, rho_air=rho_air, ql=ql, qi=qi, qr=qr, qs=qs,                                         &
          ql_ade=ql_ade,qi_ade=qi_ade,qr_ade=qr_ade,qs_ade=qs_ade,                 &
          ql_efr=ql_efr,qi_efr=qi_efr,qr_efr=qr_efr,qs_efr=qs_efr,                 &
          method=self%radii_method, use_mask=self%use_mask)
  elseif (have_qr .and. have_qg) then
    call crtm_ade_efr(geom=geom, p=prs, t=t, delp=delp, sea_frac=watercov,         &
          q=q, rho_air=rho_air, ql=ql, qi=qi, qr=qr, qg=qg,                                         &
          ql_ade=ql_ade,qi_ade=qi_ade,qr_ade=qr_ade,qg_ade=qg_ade,                 &
          ql_efr=ql_efr,qi_efr=qi_efr,qr_efr=qr_efr,qg_efr=qg_efr,                 &
          method=self%radii_method, use_mask=self%use_mask)
  elseif (have_qs .and. have_qg) then
    call crtm_ade_efr(geom=geom, p=prs, t=t, delp=delp, sea_frac=watercov,         &
          q=q, rho_air=rho_air, ql=ql, qi=qi, qs=qs, qg=qg,                                         &
          ql_ade=ql_ade,qi_ade=qi_ade,qs_ade=qs_ade,qg_ade=qg_ade,                 &
          ql_efr=ql_efr,qi_efr=qi_efr,qs_efr=qs_efr,qg_efr=qg_efr,                 &
          method=self%radii_method, use_mask=self%use_mask)
  elseif (have_qs) then
    call crtm_ade_efr(geom=geom, p=prs, t=t, delp=delp, sea_frac=watercov,         &
          q=q, rho_air=rho_air, ql=ql, qi=qi, qs=qs,                                                &
          ql_ade=ql_ade,qi_ade=qi_ade,qs_ade=qs_ade,                               &
          ql_efr=ql_efr,qi_efr=qi_efr,qs_efr=qs_efr,                               &
          method=self%radii_method, use_mask=self%use_mask)
  elseif (have_qr) then
    call crtm_ade_efr(geom=geom, p=prs, t=t, delp=delp, sea_frac=watercov,         &
          q=q, rho_air=rho_air, ql=ql, qi=qi, qr=qr,                                                &
          ql_ade=ql_ade,qi_ade=qi_ade,qr_ade=qr_ade,                               &
          ql_efr=ql_efr,qi_efr=qi_efr,qr_efr=qr_efr,                               &
          method=self%radii_method, use_mask=self%use_mask)
  else
    call crtm_ade_efr(geom=geom, p=prs, t=t, delp=delp, sea_frac=watercov,         &
          q=q, rho_air=rho_air, ql=ql, qi=qi,                                                       &
          ql_ade=ql_ade,qi_ade=qi_ade,                                             &
          ql_efr=ql_efr,qi_efr=qi_efr,                                             &
          method=self%radii_method, use_mask=self%use_mask)
  endif
  ql_colm(:,:,1) = sum(ql_ade,3)
  qi_colm(:,:,1) = sum(qi_ade,3)
  if( have_qr ) then
    qr_colm(:,:,1) = sum(qr_ade,3)
  endif
  if( have_qs ) then
    qs_colm(:,:,1) = sum(qs_ade,3)
  endif
  if( have_qg ) then
    qg_colm(:,:,1) = sum(qg_ade,3)
  endif
  have_crtm_cld = .true.
endif


! CRTM surface fields
! -------------------

! Soil temperature
have_soilt = .false.
if (xm%has_field( 'soilt' )) then
  call xm%get_field('soilt' , soilt )
  have_soilt = .true.
elseif (xm%has_field( 'stc' )) then
  call xm%get_field('stc' , soil_tmp )
  allocate(soilt(self%isc:self%iec,self%jsc:self%jec,1))
  soilt(:,:,1) = soil_tmp(:,:,1) ! Which of the 4 levels should we use?
  have_soilt = .true.
elseif (xm%has_field( 'tslb' )) then
  call xm%get_field('tslb' , soil_tmp )
  allocate(soilt(self%isc:self%iec,self%jsc:self%jec,1))
  soilt(:,:,1) = soil_tmp(:,:,1) ! Which of the 4 levels should we use?
  have_soilt = .true.
endif

! Soil moisture
have_soilm = .false.
if (xm%has_field( 'soilm' )) then
  call xm%get_field('soilm' , soilm )
  have_soilm = .true.
elseif (xm%has_field( 'soilMoistureVolumetric' )) then
  call xm%get_field('soilMoistureVolumetric' , soil_tmp )
  allocate(soilm(self%isc:self%iec,self%jsc:self%jec,1))
  soilm(:,:,1) = soil_tmp(:,:,1) ! Which of the 4 levels should we use?
  have_soilm = .true.
elseif (xm%has_field( 'smois' )) then
  call xm%get_field('smois' , soil_tmp )
  allocate(soilm(self%isc:self%iec,self%jsc:self%jec,1))
  soilm(:,:,1) = soil_tmp(:,:,1) ! Which of the 4 levels should we use?
  have_soilm = .true.
endif

! Skin temperature
! ----------------
have_tskin = .false.
if ( xm%has_field( 'skin_temperature_at_surface') ) then
   allocate(skin_temperature_at_surface(self%isc:self%iec,self%jsc:self%jec,1))
   call xm%get_field('skin_temperature_at_surface', skin_temperature_at_surface)
   have_tskin = .true.
endif

have_crtm_surface = .false.
have_sss = .false.
if ( have_slmsk .and. have_f10m .and. xm%has_field( 'sheleg') .and. &
     xm%has_field( 'skin_temperature_at_surface')     .and. xm%has_field( 'vtype' ) .and. &
     xm%has_field( 'stype' ) .and. xm%has_field( 'vfrac' ) .and. &
     have_soilt .and. have_soilm .and. &
     xm%has_field( 'eastward_wind_at_surface' ) .and. xm%has_field( 'northward_wind_at_surface' ) ) then

  call xm%get_field('sheleg', sheleg)
  call xm%get_field('skin_temperature_at_surface'    , tskin )
  call xm%get_field('vtype' , vtype )
  call xm%get_field('stype' , stype )
  call xm%get_field('vfrac' , vfrac )
  call xm%get_field('eastward_wind_at_surface' , u_srf )
  call xm%get_field('northward_wind_at_surface' , v_srf )

  allocate(land_type_index_npoess                    (self%isc:self%iec,self%jsc:self%jec,1))
  allocate(land_type_index_igbp                      (self%isc:self%iec,self%jsc:self%jec,1))
  allocate(vegetation_type_index                     (self%isc:self%iec,self%jsc:self%jec,1))
  allocate(soil_type                                 (self%isc:self%iec,self%jsc:self%jec,1))
  allocate(water_area_fraction                       (self%isc:self%iec,self%jsc:self%jec,1))
  allocate(land_area_fraction                        (self%isc:self%iec,self%jsc:self%jec,1))
  allocate(ice_area_fraction                         (self%isc:self%iec,self%jsc:self%jec,1))
  allocate(surface_snow_area_fraction                (self%isc:self%iec,self%jsc:self%jec,1))
  allocate(leaf_area_index                           (self%isc:self%iec,self%jsc:self%jec,1))
  allocate(skin_temperature_at_surface_where_sea     (self%isc:self%iec,self%jsc:self%jec,1))
  allocate(skin_temperature_at_surface_where_land    (self%isc:self%iec,self%jsc:self%jec,1))
  allocate(skin_temperature_at_surface_where_ice     (self%isc:self%iec,self%jsc:self%jec,1))
  allocate(skin_temperature_at_surface_where_snow    (self%isc:self%iec,self%jsc:self%jec,1))
  allocate(volume_fraction_of_condensed_water_in_soil(self%isc:self%iec,self%jsc:self%jec,1))
  allocate(vegetation_area_fraction                  (self%isc:self%iec,self%jsc:self%jec,1))
  allocate(soil_temperature                          (self%isc:self%iec,self%jsc:self%jec,1))
  allocate(surface_snow_thickness                    (self%isc:self%iec,self%jsc:self%jec,1))
  allocate(wind_speed_at_surface                     (self%isc:self%iec,self%jsc:self%jec,1))
  allocate(wind_from_direction_at_surface            (self%isc:self%iec,self%jsc:self%jec,1))
  allocate(sea_surface_salinity                      (self%isc:self%iec,self%jsc:self%jec,1))

  allocate(sss(self%isc:self%iec,self%jsc:self%jec,1))
  sss = 0.0_kind_real
  if (xm%has_field( 'sss')) then
    call xm%get_field('sss', sss)
    have_sss = .true.
  endif

  ! Compute day of year, used for surface fields with seasonal variation
  sec_of_year = datetime_seconds_since_jan1(xm%time)
  fractional_day_of_year = sec_of_year / 86400.0_kind_real

  ! Here we compute the surface data for CRTM. A particular note about the surface types:
  !
  ! We compute at once the CRTM surface types supported in fv3-jedi: land types in two possible
  ! classification schemes, soil type, and vegetation type (*). This simplifies the logic, and
  ! should only be a negligible additional expense. A minor optimization would be to pass to
  ! `crtm_surface` information about which surface type was requested from this function
  ! (changevar), so only the requested type would be computed. Typically, this would be land type
  ! (in just a single classification scheme) for vis/IR obs, or soil and vegetation types for
  ! microwave obs.
  !
  ! (*) Note: CRTM also supports the USGS land type classification -- to use this with fv3-jedi, the
  ! mapping from the fv3-jedi land type to the USGS land type must be added to `crtm_surface`. This
  ! would exactly follow the code currently in place for the NPOESS and IGBP classifications.
  call crtm_surface( geom, fractional_day_of_year, &
                     slmsk, sheleg, skin_temperature_at_surface, vtype, stype, vfrac, soilt, &
                     soilm, u_srf, v_srf, f10m, sss, land_type_index_npoess, land_type_index_igbp, &
                     vegetation_type_index, soil_type, water_area_fraction, land_area_fraction, &
                     ice_area_fraction, surface_snow_area_fraction, leaf_area_index, &
                     skin_temperature_at_surface_where_sea, &
                     skin_temperature_at_surface_where_land, &
                     skin_temperature_at_surface_where_ice, &
                     skin_temperature_at_surface_where_snow, &
                     volume_fraction_of_condensed_water_in_soil, vegetation_area_fraction, &
                     soil_temperature, surface_snow_thickness, &
                     wind_speed_at_surface, wind_from_direction_at_surface, sea_surface_salinity)

  have_crtm_surface = .true.

endif

! Snow depth
have_snwdph = .false.
if (xm%has_field('totalSnowDepth')) then
   allocate(snwdph_meters(self%isc:self%iec,self%jsc:self%jec,1))
   call xm%get_field('totalSnowDepth', snwdph)
   snwdph_meters = 1.e-3_kind_real*snwdph
   have_snwdph = .true.
elseif (xm%has_field('totalSnowDepthMeters')) then
   allocate(snwdph(self%isc:self%iec,self%jsc:self%jec,1))
   call xm%get_field('totalSnowDepthMeters', snwdph_meters)
   snwdph = 1.e+3_kind_real*snwdph_meters
   have_snwdph = .true.
end if

! Vorticity
! ---------
have_vort = .false.
if (have_winds) then
  allocate(vort(self%isc:self%iec,self%jsc:self%jec,self%npz))
  allocate(divg(self%isc:self%iec,self%jsc:self%jec,self%npz))
  allocate(ud(self%isc:self%iec  ,self%jsc:self%jec+1,self%npz))
  allocate(vd(self%isc:self%iec+1,self%jsc:self%jec  ,self%npz))
  call a_to_d(geom, ua, va, ud, vd)
  call udvd_to_vortdivg(geom, ud, vd, vort, divg)
  have_vort = .true.
endif


! Tropopause pressure
! -------------------
have_tropprs = .false.
if (trim(self%tropprs_method) == 'gsi') then
  if (have_vort .and. have_tv .and. have_pressures .and. have_o3) then
    allocate(tprs(self%isc:self%iec,self%jsc:self%jec,1))
    call tropprs(geom, ps, prs, tv, o3ppmv, vort, tprs)
    have_tropprs = .true.
  endif
elseif (trim(self%tropprs_method) == 'thompson') then
  if (have_pressures .and. have_geoph .and. have_t) then
    allocate(tprs(self%isc:self%iec,self%jsc:self%jec,1))
    call tropprs_th(geom, prs, geoph, t, tprs)
    have_tropprs = .true.
  endif
endif

! Loop over the fields not found in the input state and work through cases
! ------------------------------------------------------------------------
do f = 1, size(fields_to_do)

  call xg%get_field(trim(fields_to_do(f)),  field_ptr)

  select case (trim(fields_to_do(f)))

  case ('eastward_wind')

    if (.not. have_winds) call field_fail(fields_to_do(f))
    field_ptr = ua

  case ('northward_wind')

    if (.not. have_winds) call field_fail(fields_to_do(f))
    field_ptr = va

  case ('water_vapor_mixing_ratio_wrt_moist_air')

    if (.not. have_q) call field_fail(fields_to_do(f))
    field_ptr = q

  case ('saturation_water_vapor_mixing_ratio_wrt_moist_air')

    if (.not. have_qsat) call field_fail(fields_to_do(f))
    field_ptr = qsat

  case ("airdens", "moist_air_density")

    if (.not. have_airdens) call field_fail(fields_to_do(f))
    field_ptr = rho_air

  case ("relative_humidity")

    if (.not. have_rh) call field_fail(fields_to_do(f))
    field_ptr = rh

  case ('mole_fraction_of_ozone_in_air')

    if (.not. have_o3) call field_fail(fields_to_do(f))
    field_ptr = o3ppmv

  case ('geopotential_height_times_gravity_at_surface')

    if (.not. have_geoph) call field_fail(fields_to_do(f))
    field_ptr = phis

  case ('geopotential_height_at_surface')

    if (.not. have_geoph) call field_fail(fields_to_do(f))
    field_ptr = suralt

  case ('geopotential_height')

    if (.not. have_geoph) call field_fail(fields_to_do(f))
    field_ptr = geoph

  case ('geopotential_height_levels')

    if (.not. have_geoph) call field_fail(fields_to_do(f))
    field_ptr = geophi

  case ('height_above_mean_sea_level_at_surface')

    if (.not. have_geoph) call field_fail(fields_to_do(f))
    field_ptr = suralt

  case ('height_above_mean_sea_level')

    if (.not. have_geoph) call field_fail(fields_to_do(f))
    field_ptr = geoph

  case ('layer_thickness')

    if (.not. have_delz) call field_fail(fields_to_do(f))
    field_ptr = delz

  case ('mole_fraction_of_carbon_dioxide_in_air')

    if (.not. have_co2) call field_fail(fields_to_do(f))
    field_ptr = co2

  case ('totalSnowDepth_background_error')

    field_ptr = 30.0_kind_real

  case ('water_vapor_mixing_ratio_wrt_dry_air')

    if (.not. have_qmr) call field_fail(fields_to_do(f))
    field_ptr = qmr

  case ('mass_content_of_cloud_liquid_water_in_atmosphere_layer')

    if (.not. have_crtm_cld) call field_fail(fields_to_do(f))
    field_ptr = ql_ade

  case ('mass_content_of_cloud_ice_in_atmosphere_layer')

    if (.not. have_crtm_cld) call field_fail(fields_to_do(f))
    field_ptr = qi_ade

  case ('mass_content_of_rain_in_atmosphere_layer')

    if (.not. have_crtm_cld) call field_fail(fields_to_do(f))
    field_ptr = qr_ade

  case ('mass_content_of_snow_in_atmosphere_layer')

    if (.not. have_crtm_cld) call field_fail(fields_to_do(f))
    field_ptr = qs_ade

  case ('mass_content_of_graupel_in_atmosphere_layer')

    if (.not. have_crtm_cld) call field_fail(fields_to_do(f))
    field_ptr = qg_ade

  case ("mass_content_of_cloud_liquid_water_in_atmosphere_column")

    if (.not. have_crtm_cld) call field_fail(fields_to_do(f))
    field_ptr = ql_colm

  case ("mass_content_of_cloud_ice_in_atmosphere_column")

    if (.not. have_crtm_cld) call field_fail(fields_to_do(f))
    field_ptr = qi_colm

  case ("mass_content_of_rain_in_atmosphere_column")

    if (.not. have_crtm_cld) call field_fail(fields_to_do(f))
    field_ptr = qr_colm

  case ("mass_content_of_snow_in_atmosphere_column")

    if (.not. have_crtm_cld) call field_fail(fields_to_do(f))
    field_ptr = qs_colm

  case ("mass_content_of_graupel_in_atmosphere_column")

    if (.not. have_crtm_cld) call field_fail(fields_to_do(f))
    field_ptr = qg_colm

  case ("effective_radius_of_cloud_liquid_water_particle")

    if (.not. have_crtm_cld) call field_fail(fields_to_do(f))
    field_ptr = ql_efr

  case ('effective_radius_of_cloud_ice_particle')

    if (.not. have_crtm_cld) call field_fail(fields_to_do(f))
    field_ptr = qi_efr

  case ('effective_radius_of_rain_particle')

    if (.not. have_crtm_cld) call field_fail(fields_to_do(f))
    field_ptr = qr_efr

  case ('effective_radius_of_snow_particle')

    if (.not. have_crtm_cld) call field_fail(fields_to_do(f))
    field_ptr = qs_efr

  case ('effective_radius_of_graupel_particle')

    if (.not. have_crtm_cld) call field_fail(fields_to_do(f))
    field_ptr = qg_efr

  case ('water_area_fraction')

    if (.not. have_crtm_surface) call field_fail(fields_to_do(f))
    field_ptr = water_area_fraction

  case ('land_area_fraction')

    if (.not. have_crtm_surface) call field_fail(fields_to_do(f))
    field_ptr = land_area_fraction

  case ('ice_area_fraction')

    if (.not. have_crtm_surface) call field_fail(fields_to_do(f))
    field_ptr = ice_area_fraction

  case ('surface_snow_area_fraction')

    if (.not. have_crtm_surface) call field_fail(fields_to_do(f))
    field_ptr = surface_snow_area_fraction

  case ('sea_surface_salinity')

    if (.not. have_sss) call field_fail(fields_to_do(f))
    field_ptr = sea_surface_salinity

  case ('skin_temperature_at_surface')

    if (.not. have_tskin) call field_fail(fields_to_do(f))
    field_ptr = skin_temperature_at_surface

  case ('skin_temperature_at_surface_where_sea')

    if (.not. have_crtm_surface) call field_fail(fields_to_do(f))
    field_ptr = skin_temperature_at_surface_where_sea

  case ('skin_temperature_at_surface_where_land')

    if (.not. have_crtm_surface) call field_fail(fields_to_do(f))
    field_ptr = skin_temperature_at_surface_where_land

  case ('skin_temperature_at_surface_where_ice')

    if (.not. have_crtm_surface) call field_fail(fields_to_do(f))
    field_ptr = skin_temperature_at_surface_where_ice

  case ('skin_temperature_at_surface_where_snow')

    if (.not. have_crtm_surface) call field_fail(fields_to_do(f))
    field_ptr = skin_temperature_at_surface_where_snow

  case ('surface_snow_thickness')

    if (.not. have_crtm_surface) call field_fail(fields_to_do(f))
    field_ptr = surface_snow_thickness

  case ('vegetation_area_fraction')

    if (.not. have_crtm_surface) call field_fail(fields_to_do(f))
    field_ptr = vegetation_area_fraction

  case ('wind_speed_at_surface')

    if (.not. have_crtm_surface) call field_fail(fields_to_do(f))
    field_ptr = wind_speed_at_surface

  case ('wind_from_direction_at_surface')

    if (.not. have_crtm_surface) call field_fail(fields_to_do(f))
    field_ptr = wind_from_direction_at_surface

  case ('wind_reduction_factor_at_10m')

    if (.not. have_f10m) call field_fail(fields_to_do(f))
    field_ptr = f10m

  case ('observable_domain_mask')

    if (.not. have_domain_mask) call field_fail(fields_to_do(f))
    field_ptr = observable_domain_mask

  case ('leaf_area_index')

    if (.not. have_crtm_surface) call field_fail(fields_to_do(f))
    field_ptr = leaf_area_index

  case ('volume_fraction_of_condensed_water_in_soil')

    if (.not. have_crtm_surface) call field_fail(fields_to_do(f))
    field_ptr = volume_fraction_of_condensed_water_in_soil

  case ('soil_temperature')

    if (.not. have_crtm_surface) call field_fail(fields_to_do(f))
    field_ptr = soil_temperature

  case ('land_type_index_NPOESS')

    if (.not. have_crtm_surface) call field_fail(fields_to_do(f))
    field_ptr = land_type_index_npoess

  case ('land_type_index_IGBP')

    if (.not. have_crtm_surface) call field_fail(fields_to_do(f))
    field_ptr = land_type_index_igbp

  case ('land_type_index_USGS')

    call abor1_ftn('fv3jedi_vc_model2geovals_mod.changevar does not currently implement ' &
                   //'the variable change to the USGS land type classification. ' &
                   //'This variable change should be added to surface_variables_mod.')

  case ('surface_roughness_length')

    if (.not. have_zorl) call field_fail(fields_to_do(f))
    field_ptr = sfc_rough

  case ('vegetation_type_index')

    if (.not. have_crtm_surface) call field_fail(fields_to_do(f))
    field_ptr = vegetation_type_index

  case ('soil_type')

    if (.not. have_crtm_surface) call field_fail(fields_to_do(f))
    field_ptr = soil_type

  case ('totalSnowDepth')

    if (.not. have_snwdph) call field_fail(fields_to_do(f))
    field_ptr = snwdph

  case ('totalSnowDepthMeters')

    if (.not. have_snwdph) call field_fail(fields_to_do(f))
    field_ptr = snwdph_meters

  case ('air_upward_absolute_vorticity')

    if (.not. have_vort) call field_fail(fields_to_do(f))
    field_ptr = vort

  case ('tropopause_pressure')

    if (.not. have_tropprs) call field_fail(fields_to_do(f))
    field_ptr = tprs

  case ('average_surface_temperature_within_field_of_view')

    if (.not. have_crtm_surface) call field_fail(fields_to_do(f))
    field_ptr = skin_temperature_at_surface_where_sea

  case default

    call abor1_ftn('fv3jedi_vc_model2geovals_mod.changevar unknown field: '//trim(fields_to_do(f)) &
                   //'. Not in input field and no transform case specified.')

  end select

enddo

if (associated(sheleg)) nullify(sheleg)
if (associated(vtype)) nullify(vtype)
if (associated(stype)) nullify(stype)
if (associated(vfrac)) nullify(vfrac)
if (allocated(soilt)) deallocate(soilt)
if (allocated(soilm)) deallocate(soilm)
if (associated(zorl)) nullify(zorl)
if (associated(field_ptr)) nullify(field_ptr)
if (associated(q)) nullify(q)
if (associated(frocean)) nullify(frocean)
if (associated(frlake)) nullify(frlake)
if (associated(frseaice)) nullify(frseaice)
if (associated(tskin)) nullify(tskin)
if (associated(u_srf)) nullify(u_srf)
if (associated(v_srf)) nullify(v_srf)
if (associated(qils)) nullify(qils)
if (associated(qlls)) nullify(qlls)
if (associated(qrls)) nullify(qrls)
if (associated(qsls)) nullify(qsls)
if (associated(qicn)) nullify(qicn)
if (associated(qlcn)) nullify(qlcn)
if (associated(qrcn)) nullify(qrcn)
if (associated(qscn)) nullify(qscn)

if (allocated(ud)) deallocate(ud)
if (allocated(vd)) deallocate(vd)
if (allocated(fields_to_do)) deallocate(fields_to_do)
if (allocated(qsat)) deallocate(qsat)
if (allocated(rh)) deallocate(rh)
if (allocated(t)) deallocate(t)
if (allocated(tv)) deallocate(tv)
if (allocated(ps)) deallocate(ps)
if (allocated(delp)) deallocate(delp)
if (allocated(prsi)) deallocate(prsi)
if (allocated(prs)) deallocate(prs)
if (allocated(pkz)) deallocate(pkz)
if (allocated(phis)) deallocate(phis)
if (allocated(geophi)) deallocate(geophi)
if (allocated(geoph)) deallocate(geoph)
if (allocated(suralt)) deallocate(suralt)
if (allocated(delz)) deallocate(delz)
if (allocated(o3mr)) deallocate(o3mr)
if (allocated(o3ppmv)) deallocate(o3ppmv)
if (allocated(ua)) deallocate(ua)
if (allocated(va)) deallocate(va)
if (allocated(slmsk)) deallocate(slmsk)
if (allocated(sfc_rough)) deallocate(sfc_rough)
if (allocated(f10m)) deallocate(f10m)
if (allocated(observable_domain_mask)) deallocate(observable_domain_mask)
if (allocated(ql)) deallocate(ql)
if (allocated(qi)) deallocate(qi)
if (allocated(qr)) deallocate(qr)
if (allocated(qs)) deallocate(qs)
if (allocated(qg)) deallocate(qg)
if (allocated(qmr)) deallocate(qmr)
if (allocated(nc)) deallocate(nc)
if (allocated(ni)) deallocate(ni)
if (allocated(nr)) deallocate(nr)
if (allocated(co2)) deallocate(co2)
if (allocated(ql_ade)) deallocate(ql_ade)
if (allocated(qi_ade)) deallocate(qi_ade)
if (allocated(qr_ade)) deallocate(qr_ade)
if (allocated(qs_ade)) deallocate(qs_ade)
if (allocated(qg_ade)) deallocate(qg_ade)
if (allocated(ql_efr)) deallocate(ql_efr)
if (allocated(qi_efr)) deallocate(qi_efr)
if (allocated(qr_efr)) deallocate(qr_efr)
if (allocated(qs_efr)) deallocate(qs_efr)
if (allocated(qg_efr)) deallocate(qg_efr)
if (allocated(ql_colm)) deallocate(ql_colm)
if (allocated(qi_colm)) deallocate(qi_colm)
if (allocated(qr_colm)) deallocate(qr_colm)
if (allocated(qs_colm)) deallocate(qs_colm)
if (allocated(qg_colm)) deallocate(qg_colm)
if (allocated(watercov)) deallocate(watercov)
if (allocated(sss)) deallocate(sss)
if (allocated(land_type_index_npoess)) deallocate(land_type_index_npoess)
if (allocated(land_type_index_igbp)) deallocate(land_type_index_igbp)
if (allocated(vegetation_type_index)) deallocate(vegetation_type_index)
if (allocated(soil_type)) deallocate(soil_type)
if (allocated(water_area_fraction)) deallocate(water_area_fraction)
if (allocated(land_area_fraction)) deallocate(land_area_fraction)
if (allocated(ice_area_fraction)) deallocate(ice_area_fraction)
if (allocated(surface_snow_area_fraction)) deallocate(surface_snow_area_fraction)
if (allocated(leaf_area_index)) deallocate(leaf_area_index)
if (allocated(skin_temperature_at_surface_where_sea)) deallocate(skin_temperature_at_surface_where_sea)
if (allocated(skin_temperature_at_surface_where_land)) deallocate(skin_temperature_at_surface_where_land)
if (allocated(skin_temperature_at_surface_where_ice)) deallocate(skin_temperature_at_surface_where_ice)
if (allocated(skin_temperature_at_surface_where_snow)) deallocate(skin_temperature_at_surface_where_snow)
if (allocated(volume_fraction_of_condensed_water_in_soil)) &
                                              deallocate(volume_fraction_of_condensed_water_in_soil)
if (allocated(vegetation_area_fraction)) deallocate(vegetation_area_fraction)
if (allocated(soil_temperature)) deallocate(soil_temperature)
if (allocated(surface_snow_thickness)) deallocate(surface_snow_thickness)
if (allocated(wind_speed_at_surface)) deallocate(wind_speed_at_surface)
if (allocated(wind_from_direction_at_surface)) deallocate(wind_from_direction_at_surface)
if (allocated(sea_surface_salinity)) deallocate(sea_surface_salinity)
if (allocated(skin_temperature_at_surface)) deallocate(skin_temperature_at_surface)
if (allocated(snwdph)) deallocate(snwdph)
if (allocated(snwdph_meters)) deallocate(snwdph_meters)
if (allocated(vort)) deallocate(vort)
if (allocated(tprs)) deallocate(tprs)
if (allocated(rho_air)) deallocate(rho_air)

end subroutine changevar

! --------------------------------------------------------------------------------------------------

end module fv3jedi_vc_model2geovals_mod
