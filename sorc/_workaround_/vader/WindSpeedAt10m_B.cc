/*
 * (C) Copyright 2026 UCAR
 *
 * This software is licensed under the terms of the Apache Licence Version 2.0
 * which can be obtained at http://www.apache.org/licenses/LICENSE-2.0.
 */

#include <cmath>
#include <iostream>
#include <vector>

#include "oops/util/for_each.h"
#include "oops/util/Logger.h"
#include "vader/betaNames_CRTMRecipes/WindSpeedAt10m.h"

namespace vader
{
// ------------------------------------------------------------------------------------------------

// Static attribute initialization
const char WindSpeedAt10m_B::Name[] = "WindSpeedAt10m_B";
const oops::Variables WindSpeedAt10m_B::Ingredients{std::vector<std::string>{
                            "eastward_wind_at_surface", "northward_wind_at_surface",
                            "ratio_of_wind_at_surface_adjacent_layer_to_wind_at_10m"}};

// Register the maker
static RecipeMaker<WindSpeedAt10m_B> makerWindSpeedAt10m_B_(
                                WindSpeedAt10m_B::Name);

WindSpeedAt10m_B::WindSpeedAt10m_B(const Parameters_ & params,
                   const VaderConfigVars & configVariables) {
  oops::Log::trace() << "WindSpeedAt10m_B::WindSpeedAt10m_B(params)"
                     << std::endl;
}

std::string WindSpeedAt10m_B::name() const {
  return WindSpeedAt10m_B::Name;
}

oops::Variable WindSpeedAt10m_B::product() const {
  // CRTM requests this scaled 10 m wind as wind_speed_at_surface.
  return oops::Variable{"wind_speed_at_surface"};
}

oops::Variables WindSpeedAt10m_B::ingredients() const {
  return WindSpeedAt10m_B::Ingredients;
}

size_t WindSpeedAt10m_B::productLevels(const atlas::FieldSet & afieldset) const {
  return 1;
}

atlas::FunctionSpace WindSpeedAt10m_B::productFunctionSpace(const atlas::FieldSet &
                                          afieldset) const {
  return afieldset.field("eastward_wind_at_surface").functionspace();
}

// -------------------------------------------------------------------------------------------------

void WindSpeedAt10m_B::executeNL(atlas::FieldSet & afieldset) {
  oops::Log::trace() << "WindSpeedAt10m_B::executeNL starting" << std::endl;

  util::for_each_value(
      [](const double ratio, const double u, const double v, double& spd) {
          spd = ratio * std::sqrt(u * u + v * v);
      },
      afieldset.field("ratio_of_wind_at_surface_adjacent_layer_to_wind_at_10m"),
      afieldset.field("eastward_wind_at_surface"),
      afieldset.field("northward_wind_at_surface"),
      afieldset.field("wind_speed_at_surface"));

  oops::Log::trace() << "WindSpeedAt10m_B::executeNL done" << std::endl;
}

}  // namespace vader
