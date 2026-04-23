/*
 * (C) Copyright 2022- UCAR
 *
 * This software is licensed under the terms of the Apache Licence Version 2.0
 * which can be obtained at http://www.apache.org/licenses/LICENSE-2.0.
 */

#include "saber/interpolation/Interpolation.h"

#include "atlas/util/Config.h"

#include "oops/util/FieldSetOperations.h"
#include "oops/util/Logger.h"
#include "oops/util/missingValues.h"

namespace saber {
namespace interpolation {

// -----------------------------------------------------------------------------

static SaberOuterBlockMaker<Interpolation> makerInterpolation_("interpolation");

namespace {
void fillMissingValuesNearest(const atlas::FieldSet & sourceFieldSet,
                              atlas::FieldSet & targetFieldSet,
                              const oops::Variables & vars,
                              const atlas::FunctionSpace & sourceFs,
                              const atlas::FunctionSpace & targetFs) {
  if (vars.size() == 0) {
    oops::Log::trace()
        << Interpolation::classname()
        << "fillMissingValuesNearest: no variables to process"
        << std::endl;
    return;
  }

  const auto src_lonlat = atlas::array::make_view<double, 2>(sourceFs.lonlat());
  const auto src_ghost = atlas::array::make_view<int, 1>(sourceFs.ghost());
  std::vector<double> lons;
  std::vector<double> lats;
  std::vector<atlas::idx_t> indices;
  lons.reserve(src_lonlat.shape(0));
  lats.reserve(src_lonlat.shape(0));
  indices.reserve(src_lonlat.shape(0));
  for (atlas::idx_t jj = 0; jj < src_lonlat.shape(0); ++jj) {
    if (src_ghost(jj) == 0) {
      lons.push_back(src_lonlat(jj, 0));
      lats.push_back(src_lonlat(jj, 1));
      indices.push_back(jj);
    }
  }
  if (indices.empty()) {
    oops::Log::trace()
          << Interpolation::classname()
          << "fillMissingValuesNearest: no owned source points"
          << std::endl;
    return;
  }

  const atlas::Geometry earth(atlas::util::Earth::radius());
  atlas::util::IndexKDTree2D tree(earth);
  tree.build(lons, lats, indices);

  const auto tgt_lonlat = atlas::array::make_view<double, 2>(targetFs.lonlat());
  const auto tgt_ghost = atlas::array::make_view<int, 1>(targetFs.ghost());
  const double missing = util::missingValue<double>();


  for (const auto & var : vars) {
    if (!targetFieldSet.has(var.name()) || !sourceFieldSet.has(var.name())) {
      oops::Log::trace()
            << Interpolation::classname()
            << "fillMissingValuesNearest: skipping var (missing in fset)" <<var.name()
            << std::endl;
      continue;
    }
    auto tgt_view = atlas::array::make_view<double, 2>(targetFieldSet[var.name()]);
    const auto src_view = atlas::array::make_view<double, 2>(
        sourceFieldSet.field(var.name()));

    for (atlas::idx_t jloc = 0; jloc < tgt_view.shape(0); ++jloc) {
      if (tgt_ghost(jloc) != 0) {
        continue;
      }
      bool has_missing = false;
      for (atlas::idx_t jlev = 0; jlev < tgt_view.shape(1); ++jlev) {
        if (tgt_view(jloc, jlev) == missing) {
          has_missing = true;
          break;
        }
      }
      if (!has_missing) {
        continue;
      }
      atlas::PointLonLat pll(tgt_lonlat(jloc, 0), tgt_lonlat(jloc, 1));
      const auto item = tree.closestPoint(pll);
      const atlas::idx_t src_index = item.payload();
      for (atlas::idx_t jlev = 0; jlev < tgt_view.shape(1); ++jlev) {
        if (tgt_view(jloc, jlev) == missing) {
          tgt_view(jloc, jlev) = src_view(src_index, jlev);
       }
      }
    }
  }
}
}  // namespace
// -----------------------------------------------------------------------------

Interpolation::Interpolation(const oops::GeometryData & outerGeometryData,
                             const oops::Variables & outerVars,
                             const eckit::Configuration & covarConf,
                             const Parameters_ & params,
                             const oops::FieldSet3D & xb,
                             const oops::FieldSet3D & fg)
  : SaberOuterBlockBase(params, xb.validTime(), outerGeometryData, outerVars),
    params_(params), innerVars_(outerVars),
    activeVars_(params.activeVars.value().get_value_or(outerVars)),
    invVars_(params.inverseVars.value())
{
  oops::Log::trace() << classname() << "::Interpolation starting" << std::endl;

  // Set up GeometryData
  Geometry geom(params.innerGeom, outerGeometryData.comm());
  innerGeomData_.reset(new oops::GeometryData(geom.functionSpace(), geom.fields(),
                                              true, outerGeometryData.comm()));

  if (params.interpType.value() == "global") {
    globalInterp_.reset(new oops::GlobalInterpolator(
      params.forwardInterpConf.value(), *innerGeomData_,
      outerGeometryData.functionSpace(), outerGeometryData.comm()));
  } else if (params.interpType.value() == "regional") {
    regionalInterp_.reset(new atlas::Interpolation(
       atlas::util::Config("type", "regional-linear-2d"),
       innerGeomData_->functionSpace(), outerGeometryData.functionSpace()));
  } else {
    throw eckit::UserError("wrong interpolator type: " + params.interpType.value(), Here());
  }

  oops::Log::trace() << classname() << "::Interpolation done" << std::endl;
}

// -----------------------------------------------------------------------------

void Interpolation::multiply(oops::FieldSet3D & fieldSet) const {
  oops::Log::trace() << classname() << "::multiply starting" << std::endl;

  // Temporary FieldSet of active variables for interpolation source
  atlas::FieldSet sourceFieldSet;
  for (const auto & var : activeVars_) {
    sourceFieldSet.add(fieldSet[var.name()]);
  }

  // Interpolate to target/outer grid
  atlas::FieldSet targetFieldSet;
  if (globalInterp_) {
    globalInterp_->apply(sourceFieldSet, targetFieldSet);
  }
  if (regionalInterp_) {
    for (const auto & var : activeVars_) {
      const atlas::Field sourceField = sourceFieldSet[var.name()];
      atlas::Field targetField = outerGeometryData_.functionSpace().createField<double>(
          atlas::option::name(var.name()) | atlas::option::levels(sourceField.levels()));
      targetField.metadata() = sourceField.metadata();
      auto targetView = atlas::array::make_view<double, 2>(targetField);
      targetView.assign(0.0);
      targetFieldSet.add(targetField);
    }
    regionalInterp_->execute(sourceFieldSet, targetFieldSet);
  }

  // Add passive variables
  for (const auto & f : fieldSet) {
    if (!activeVars_.has(f.name())) {
      targetFieldSet.add(f);
    }
  }

  // Reset
  fieldSet.fieldSet() = targetFieldSet;

  oops::Log::trace() << classname() << "::multiply done" << std::endl;
}

// -----------------------------------------------------------------------------

void Interpolation::multiplyAD(oops::FieldSet3D & fieldSet) const {
  oops::Log::trace() << classname() << "::multiplyAD starting" << std::endl;

  // Temporary FieldSet of active variables for interpolation target
  atlas::FieldSet targetFieldSet;
  for (const auto & var : activeVars_) {
    targetFieldSet.add(fieldSet[var.name()]);
  }

  // (Adjoint of:) Interpolate to target/outer grid
  atlas::FieldSet sourceFieldSet;
  if (globalInterp_) {
    globalInterp_->applyAD(sourceFieldSet, targetFieldSet);
  }
  if (regionalInterp_) {
    for (const auto & var : activeVars_) {
      const atlas::Field targetField = targetFieldSet[var.name()];
      atlas::Field sourceField = innerGeomData_->functionSpace().createField<double>(
          atlas::option::name(var.name()) | atlas::option::levels(targetField.levels()));
      sourceField.metadata() = targetField.metadata();
      auto sourceView = atlas::array::make_view<double, 2>(sourceField);
      sourceView.assign(0.0);
      sourceFieldSet.add(sourceField);
    }
    regionalInterp_->execute_adjoint(sourceFieldSet, targetFieldSet);
  }

  // Copy passive variables
  for (const auto & f : fieldSet) {
    if (!activeVars_.has(f.name())) {
      sourceFieldSet.add(f);
    }
  }

  fieldSet.fieldSet() = sourceFieldSet;

  oops::Log::trace() << classname() << "::multiplyAD done" << std::endl;
}

// -----------------------------------------------------------------------------

void Interpolation::inverseMultiply(oops::FieldSet3D & fieldSet) const {
  // If specific `state variables to inverse` were requested in the yaml, apply the (inverse)
  // interpolator to those variables only. Otherwise, apply the (inverse) interpolator to the
  // whole fieldset.
  // NOTE that in a SaberOuterBlockChain, the logic to call Interpolation::inverseMultiply
  // includes checking for the existence of the `state variables to inverse` key. Thus, omitting
  // the yaml key is likely to skip the inverseMultiply completely.
  const oops::Variables invVars = (invVars_.size() > 0 ? invVars_ : fieldSet.variables());

  // Prepare inverse interpolator
  if (!inverseGlobalInterp_ && globalInterp_) {
    inverseGlobalInterp_.reset(new oops::GlobalInterpolator(
      params_.inverseInterpConf.value(), outerGeometryData_,
      innerGeomData_->functionSpace(), innerGeomData_->comm()));
  }
  if (!inverseRegionalInterp_ && regionalInterp_) {
    inverseRegionalInterp_.reset(new atlas::Interpolation(
       atlas::util::Config("type", "regional-linear-2d"),
       outerGeometryData_.functionSpace(), innerGeomData_->functionSpace()));
  }
  // Temporary FieldSet of active variables for interpolation source
  atlas::FieldSet sourceFieldSet;
  for (const auto & var : invVars) {
    sourceFieldSet.add(fieldSet[var.name()]);
  }

  // Interpolate to target/inner grid
  atlas::FieldSet targetFieldSet;
  if (inverseGlobalInterp_) {
    inverseGlobalInterp_->apply(sourceFieldSet, targetFieldSet);
  }
  if (inverseRegionalInterp_) {
    for (const auto & var : invVars) {
      const atlas::Field sourceField = sourceFieldSet[var.name()];
      atlas::Field targetField = outerGeometryData_.functionSpace().createField<double>(
          atlas::option::name(var.name()) | atlas::option::levels(sourceField.levels()));
      targetField.metadata() = sourceField.metadata();
      auto targetView = atlas::array::make_view<double, 2>(targetField);
      targetView.assign(0.0);
      targetFieldSet.add(targetField);
    }
    inverseRegionalInterp_->execute(sourceFieldSet, targetFieldSet);
  }
  if (params_.fillMissingValues.value()) {
    fillMissingValuesNearest(sourceFieldSet, targetFieldSet, invVars,
                             outerGeometryData_.functionSpace(),
                             innerGeomData_->functionSpace());
    // Update halos after filling missing values so boundary points are consistent
    targetFieldSet.haloExchange();
  }

  // Reset
  fieldSet.fieldSet() = targetFieldSet;

  oops::Log::trace() << classname() << "::inverseMultiply done" << std::endl;
}

// -----------------------------------------------------------------------------

oops::FieldSet3D Interpolation::generateInnerFieldSet(const oops::GeometryData & innerGeometryData,
                                                      const oops::Variables & innerVars) const {
  oops::FieldSet3D fset(validTime_, innerGeometryData.comm());
  fset.deepCopy(util::createSmoothFieldSet(innerGeometryData.comm(),
                                           innerGeometryData.functionSpace(),
                                           innerVars));
  return fset;
}

// -----------------------------------------------------------------------------

oops::FieldSet3D Interpolation::generateOuterFieldSet(const oops::GeometryData & outerGeometryData,
                                                      const oops::Variables & outerVars) const {
  oops::FieldSet3D fset(validTime_, outerGeometryData.comm());
  fset.deepCopy(util::createSmoothFieldSet(outerGeometryData.comm(),
                                           outerGeometryData.functionSpace(),
                                           outerVars));
  return fset;
}

// -----------------------------------------------------------------------------

void Interpolation::print(std::ostream & os) const {
  os << classname();
}

}  // namespace interpolation
}  // namespace saber
