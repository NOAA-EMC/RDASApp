/*
 * (C) Copyright 2022 UCAR
 *
 * This software is licensed under the terms of the Apache Licence Version 2.0
 * which can be obtained at http://www.apache.org/licenses/LICENSE-2.0.
*/

#pragma once

#include <map>
#include <string>
#include <utility>

#include "fv3jedi/FieldMetadata/FieldsMetadata.h"

namespace fv3jedi {

  // -----------------------------------------------------------------------------------------------

  // Elements to be populated for each field
  struct metadataStruct {
    std::string longName;
    std::string units;
    std::string kind;
    std::string tracer;  // Turned into bool but input as string to allow checking
    std::string levels;
    std::string space;
  };

  // -----------------------------------------------------------------------------------------------

  void setMetadataStruct(struct metadataStruct & md) {
    md.longName = "long name";
    md.units = "units";
    md.kind = "kind";
    md.tracer = "tracer";
    md.levels = "levels";
    md.space = "space";
  }

  // -----------------------------------------------------------------------------------------------

  void assertStructIsSet(struct metadataStruct & md) {
    // Check that structure contains something
    // ---------------------------------------
    ASSERT_MSG(md.longName != "long name", "long name was not set");
    ASSERT_MSG(md.units != "units", "units was not set");
    ASSERT_MSG(md.kind != "kind", "kind was not set");
    ASSERT_MSG(md.tracer != "tracer", "tracer was not set");
    ASSERT_MSG(md.levels != "levels", "levels was not set");
    ASSERT_MSG(md.space != "space", "space was not set");
  }

  // -----------------------------------------------------------------------------------------------

  void addFieldMetadata(std::map<std::string, FieldMetadata> & fieldsmetadata, const int & nlev,
                        struct metadataStruct & md) {
    // Check that structure is set
    assertStructIsSet(md);

    // Create object to hold the metadata for this field
    FieldMetadata fieldmetadata(md.longName, nlev);

    // Populate the object
    fieldmetadata.setVarUnits(md.units);
    fieldmetadata.setDataKind(md.kind);
    fieldmetadata.setNumLevls(md.levels);
    fieldmetadata.setMathSpac(md.space);
    fieldmetadata.setIsTracer(md.tracer);

    // Validate the choices
    fieldmetadata.validate();

    // Check key not already in the map
    ASSERT_MSG(fieldsmetadata.find(md.longName) == fieldsmetadata.end(),
               "FieldMetadataDefault::addFieldMetadata: Long name "+md.longName+" already used.");

    // Insert the object into the map
    fieldsmetadata.insert(std::pair<std::string, FieldMetadata>(md.longName, fieldmetadata));

    // Set back to nothing
    setMetadataStruct(md);
  }

  // -----------------------------------------------------------------------------------------------

  void setMetadata(std::map<std::string, FieldMetadata> & fieldsmetadata, const int nlev) {
    // Create structure and set to nothing
    struct metadataStruct md;
    setMetadataStruct(md);

    // Field metadata
    // --------------
    md.longName = "eastward_wind";
    md.units = "ms-1";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "northward_wind";
    md.units = "ms-1";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "air_temperature";
    md.units = "K";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "virtual_temperature";
    md.units = "K";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "air_potential_temperature";
    md.units = "K";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "air_pressure_thickness";
    md.units = "pa";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "air_pressure_to_kappa";
    md.units = "Pa";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "air_pressure_levels";
    md.units = "Pa";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "half";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "air_pressure";
    md.units = "Pa";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "air_pressure_at_surface";
    md.units = "Pa";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "ln_air_pressure_at_interface";
    md.units = "Pa";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "half";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "water_vapor_mixing_ratio_wrt_moist_air";
    md.units = "kgkg-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "water_vapor_mixing_ratio_wrt_moist_air_at_2m";
    md.units = "kgkg-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "saturation_water_vapor_mixing_ratio_wrt_moist_air";
    md.units = "kgkg-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "relative_humidity";
    md.units = "1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "cloud_liquid_ice";
    md.units = "kgkg-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "cloud_liquid_water";
    md.units = "kgkg-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "mass_fraction_of_large_scale_cloud_ice_water";
    md.units = "kgkg-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "mass_fraction_of_convective_cloud_ice_water";
    md.units = "kgkg-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "mass_fraction_of_large_scale_cloud_liquid_water";
    md.units = "kgkg-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "mass_fraction_of_convective_cloud_liquid_water";
    md.units = "kgkg-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "fraction_of_large_scale_cloud_that_is_ice";
    md.units = "1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "fraction_of_convective_cloud_that_is_ice";
    md.units = "1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "snow_water";
    md.units = "kgkg-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "rain_water";
    md.units = "kgkg-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "graupel";
    md.units = "kgkg-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "cloud_droplet_number_concentration";
    md.units = "kg-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "cloud_ice_number_concentration";
    md.units = "kg-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "rain_number_concentration";
    md.units = "kg-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "aerosol_water_number_concentration";
    md.units = "kg-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "aerosol_ice_number_concentration";
    md.units = "kg-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "cloud_area_fraction_in_atmosphere_layer";
    md.units = "1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "sgs_tke";
    md.units = "m2/s2";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "upward_air_velocity";
    md.units = "ms-1";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "layer_thickness";
    md.units = "m";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "geopotential_height_times_gravity_at_surface";
    md.units = "m";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "air_horizontal_streamfunction";
    md.units = "m+2s";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "air_horizontal_velocity_potential";
    md.units = "m+2s";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "air_upward_absolute_vorticity";
    md.units = "m+2s";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "air_horizontal_divergence";
    md.units = "m+2s";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "slmsk";
    md.units = "none";
    md.kind = "integer";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "sheleg";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "skin_temperature_at_surface";
    md.units = "K";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "sea_surface_temperature";
    md.units = "K";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "vtype";
    md.units = "none";
    md.kind = "integer";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "stype";
    md.units = "none";
    md.kind = "integer";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "vfrac";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "stc";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "4";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "tslb";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "9";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "soilt";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "soilMoistureVolumetric";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "4";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "smois";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "9";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "soilm";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "totalSnowDepth";
    md.units = "mm";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "totalSnowDepthMeters";
    md.units = "m";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "snowDensity";
    md.units = "kgm-3";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "eastward_wind_at_surface";
    md.units = "ms-1";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "northward_wind_at_surface";
    md.units = "ms-1";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

//    md.longName = "eastward_wind_at_10m";
//    md.units = "ms-1";
//    md.kind = "double";
//    md.tracer = "false";
//    md.levels = "1";
//    md.space = "magnitude";
//    addFieldMetadata(fieldsmetadata, nlev, md);

//    md.longName = "northward_wind_at_10m";
//    md.units = "ms-1";
//    md.kind = "double";
//    md.tracer = "false";
//    md.levels = "1";
//    md.space = "magnitude";
//    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "f10m";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "sea_surface_salinity";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "initial_mass_fraction_of_large_scale_cloud_condensate";
    md.units = "kgkg-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "initial_mass_fraction_of_convective_cloud_condensate";
    md.units = "kgkg-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "convective_cloud_area_fraction";
    md.units = "1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "fraction_of_ocean";
    md.units = "1";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "fraction_of_land";
    md.units = "1";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "fraction_of_landice";
    md.units = "1";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "fraction_of_lake";
    md.units = "1";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "fraction_of_ice";
    md.units = "1";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "isotropic_variance_of_filtered_topography";
    md.units = "m+2";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "surface_velocity_scale";
    md.units = "ms-1";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "surface_buoyancy_scale";
    md.units = "ms-2";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "planetary_boundary_layer_height";
    md.units = "m";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "surface_exchange_coefficient_for_momentum";
    md.units = "kgm-2s-1";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "surface_exchange_coefficient_for_heat";
    md.units = "kgm-2s-1";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "surface_exchange_coefficient_for_moisture";
    md.units = "kgm-2s-1";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "KCBL_before_moist";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "surface_temp_before_moist";
    md.units = "K";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "lower_index_where_Kh_greater_than_2";
    md.units = "1";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "upper_index_where_Kh_greater_than_2";
    md.units = "1";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "moist_air_density";
    md.units = "kgm-3";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "zorl";
    md.units = "cm";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "air_temperature_at_2m";
    md.units = "K";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "tropopause_pressure";
    md.units = "Pa";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "geopotential_height";
    md.units = "m";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "geopotential_height_levels";
    md.units = "m";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "half";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "height_above_mean_sea_level";
    md.units = "m";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "height_above_mean_sea_level_at_surface";
    md.units = "m";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "geopotential_height_at_surface";
    md.units = "m";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "water_vapor_mixing_ratio_wrt_dry_air";
    md.units = "1";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "integrated_layer_ozone_in_air";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "mass_content_of_cloud_liquid_water_in_atmosphere_layer";
    md.units = "kg m-2";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "mass_content_of_cloud_ice_in_atmosphere_layer";
    md.units = "kg m-2";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "mass_content_of_rain_in_atmosphere_layer";
    md.units = "kg m-2";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "mass_content_of_snow_in_atmosphere_layer";
    md.units = "kg m-2";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "mass_content_of_graupel_in_atmosphere_layer";
    md.units = "kg m-2";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "mass_content_of_hail_in_atmosphere_layer";
    md.units = "kg m-2";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "mass_content_of_cloud_liquid_water_in_atmosphere_column";
    md.units = "kg m-2";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "mass_content_of_cloud_ice_in_atmosphere_column";
    md.units = "kg m-2";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "mass_content_of_rain_in_atmosphere_column";
    md.units = "kg m-2";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "mass_content_of_snow_in_atmosphere_column";
    md.units = "kg m-2";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "mass_content_of_graupel_in_atmosphere_column";\
    md.units = "kg m-2";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "mass_content_of_hail_in_atmosphere_column";
    md.units = "kg m-2";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "effective_radius_of_cloud_liquid_water_particle";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "effective_radius_of_cloud_ice_particle";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "effective_radius_of_rain_particle";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "effective_radius_of_snow_particle";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "effective_radius_of_graupel_particle";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "effective_radius_of_hail_particle";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "totalSnowDepth_background_error";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "water_area_fraction";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "land_area_fraction";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "ice_area_fraction";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "surface_snow_area_fraction";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "skin_temperature_at_surface_where_sea";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "skin_temperature_at_surface_where_land";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "skin_temperature_at_surface_where_ice";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "skin_temperature_at_surface_where_snow";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "surface_snow_thickness";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "vegetation_area_fraction";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "wind_speed_at_surface";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "wind_from_direction_at_surface";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "direction";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "leaf_area_index";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "volume_fraction_of_condensed_water_in_soil";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "soil_temperature";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "land_type_index_NPOESS";
    md.units = "none";
    md.kind = "integer";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "vegetation_type_index";
    md.units = "none";
    md.kind = "integer";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "soil_type";
    md.units = "none";
    md.kind = "integer";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "surface_roughness_length";
    md.units = "m";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "wind_reduction_factor_at_10m";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "observable_domain_mask";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "surface_emissivity";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "optical_thickness_of_atmosphere_layer";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "toa_outgoing_radiance_per_unit_wavenumber";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "brightness_temperature";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "brightness_temperature_assuming_clear_sky";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "transmittances_of_atmosphere_layer";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "weightingfunction_of_atmosphere_layer";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "pressure_level_at_peak_of_weightingfunction";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "average_surface_temperature_within_field_of_view";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "equivalent_reflectivity_factor";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "sea_ice_category_area_fraction";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "sea_ice_category_thickness";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "sea_surface_height_above_geoid";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "sea_water_potential_temperature";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "sea_water_conservative_temperature";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "sea_water_absolute_salinity";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "sea_water_practical_salinity";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "sea_water_salinity";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "sea_water_cell_thickness";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "latent_heat_vaporization";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "net_downwelling_shortwave_radiation";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "upward_latent_heat_flux_in_air";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "upward_sensible_heat_flux_in_air";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "net_downwelling_longwave_radiation";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "friction_velocity_over_water";
    md.units = "none";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    // Aerosols
    md.longName = "mass_fraction_of_dust001_in_air";
    md.units = "kgkg-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "mass_fraction_of_dust002_in_air";
    md.units = "kgkg-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "mass_fraction_of_dust003_in_air";
    md.units = "kgkg-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "mass_fraction_of_dust004_in_air";
    md.units = "kgkg-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "mass_fraction_of_dust005_in_air";
    md.units = "kgkg-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "mass_fraction_of_sea_salt001_in_air";
    md.units = "kgkg-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "mass_fraction_of_sea_salt002_in_air";
    md.units = "kgkg-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "mass_fraction_of_sea_salt003_in_air";
    md.units = "kgkg-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "mass_fraction_of_sea_salt004_in_air";
    md.units = "kgkg-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "mass_fraction_of_sea_salt005_in_air";
    md.units = "kgkg-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "mass_fraction_of_hydrophobic_black_carbon_in_air";
    md.units = "kgkg-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "mass_fraction_of_hydrophilic_black_carbon_in_air";
    md.units = "kgkg-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "mass_fraction_of_hydrophobic_organic_carbon_in_air";
    md.units = "kgkg-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "mass_fraction_of_hydrophilic_organic_carbon_in_air";
    md.units = "kgkg-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "mass_fraction_of_nitrate001_in_air";
    md.units = "kgkg-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "mass_fraction_of_nitrate002_in_air";
    md.units = "kgkg-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "mass_fraction_of_nitrate003_in_air";
    md.units = "kgkg-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "mass_fraction_of_so2_in_air";
    md.units = "kgkg-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "mass_fraction_of_sulfate_in_air";
    md.units = "kgkg-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "volume_extinction_in_air_due_to_aerosol_particles_lambda1";
    md.units = "km-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "volume_extinction_in_air_due_to_aerosol_particles_lambda2";
    md.units = "km-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "volume_extinction_in_air_due_to_aerosol_particles_lambda3";
    md.units = "km-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "pm25at";
    md.units = "ugm-3";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "pm25ac";
    md.units = "ugm-3";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "pm25co";
    md.units = "ugm-3";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    // Trace gases
    md.longName = "volume_mixing_ratio_of_no2";
    md.units = "mol mol-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "volume_mixing_ratio_of_no";
    md.units = "mol mol-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "volume_mixing_ratio_of_o3";
    md.units = "mol mol-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "volume_mixing_ratio_of_oh";
    md.units = "mol mol-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "volume_mixing_ratio_of_co";
    md.units = "mol mol-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "volume_mixing_ratio_of_hcho";
    md.units = "mol mol-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "mole_fraction_of_carbon_dioxide_in_air";
    md.units = "mol mol-1";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "ech4";
    md.units = "none";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "ozone_mass_mixing_ratio";
    md.units = "kgkg-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "mole_fraction_of_ozone_in_air";
    md.units = "mole_fraction_of_ozone_in_air";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "odd_oxygen_mixing_ratio";
    md.units = "kgkg-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "full";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    // Trace Gas Emissions
    md.longName = "emissions_of_co_due_to_anthropogenic";
    md.units = "kg m-2 s-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "emissions_of_no_due_to_anthropogenic";
    md.units = "kg m-2 s-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "emissions_of_hcho_due_to_anthropogenic";
    md.units = "kg m-2 s-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "emissions_of_co_due_to_anthropogenic_agriculture";
    md.units = "kg m-2 s-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "emissions_of_no_due_to_anthropogenic_agriculture";
    md.units = "kg m-2 s-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "emissions_of_hcho_due_to_anthropogenic_agriculture";
    md.units = "kg m-2 s-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "emissions_of_co_due_to_anthropogenic_energy";
    md.units = "kg m-2 s-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "emissions_of_no_due_to_anthropogenic_energy";
    md.units = "kg m-2 s-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "emissions_of_hcho_due_to_anthropogenic_energy";
    md.units = "kg m-2 s-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "emissions_of_co_due_to_anthropogenic_industry";
    md.units = "kg m-2 s-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "emissions_of_no_due_to_anthropogenic_industry";
    md.units = "kg m-2 s-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "emissions_of_hcho_due_to_anthropogenic_industry";
    md.units = "kg m-2 s-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "emissions_of_co_due_to_anthropogenic_rco";
    md.units = "kg m-2 s-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "emissions_of_no_due_to_anthropogenic_rco";
    md.units = "kg m-2 s-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "emissions_of_hcho_due_to_anthropogenic_rco";
    md.units = "kg m-2 s-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "emissions_of_co_due_to_anthropogenic_shipping";
    md.units = "kg m-2 s-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "emissions_of_no_due_to_anthropogenic_shipping";
    md.units = "kg m-2 s-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "emissions_of_hcho_due_to_anthropogenic_shipping";
    md.units = "kg m-2 s-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "emissions_of_co_due_to_anthropogenic_solvents";
    md.units = "kg m-2 s-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "emissions_of_no_due_to_anthropogenic_solvents";
    md.units = "kg m-2 s-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "emissions_of_hcho_due_to_anthropogenic_solvents";
    md.units = "kg m-2 s-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "emissions_of_co_due_to_anthropogenic_transportation";
    md.units = "kg m-2 s-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "emissions_of_no_due_to_anthropogenic_transportation";
    md.units = "kg m-2 s-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "emissions_of_hcho_due_to_anthropogenic_transportation";
    md.units = "kg m-2 s-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "emissions_of_co_due_to_anthropogenic_waste";
    md.units = "kg m-2 s-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "emissions_of_no_due_to_anthropogenic_waste";
    md.units = "kg m-2 s-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "emissions_of_hcho_due_to_anthropogenic_waste";
    md.units = "kg m-2 s-1";
    md.kind = "double";
    md.tracer = "true";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    // Orography
    md.longName = "raw_orography";
    md.units = "m";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);

    md.longName = "filtered_orography";
    md.units = "m";
    md.kind = "double";
    md.tracer = "false";
    md.levels = "1";
    md.space = "magnitude";
    addFieldMetadata(fieldsmetadata, nlev, md);
  }
}  // namespace fv3jedi

