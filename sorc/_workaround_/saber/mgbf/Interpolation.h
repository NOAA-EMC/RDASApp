/*
 * (C) Copyright 2022- UCAR
 *
 * This software is licensed under the terms of the Apache Licence Version 2.0
 * which can be obtained at http://www.apache.org/licenses/LICENSE-2.0.
 */

#pragma once

#include <memory>
#include <string>
#include <vector>

#include "atlas/field.h"
#include "atlas/interpolation.h"

#include "oops/base/GeometryData.h"
#include "oops/base/Variables.h"
#include "oops/generic/GlobalInterpolator.h"
#include "oops/util/FieldSetHelpers.h"
#include "oops/util/parameters/Parameter.h"
#include "oops/util/parameters/Parameters.h"
#include "oops/util/parameters/RequiredParameter.h"

#include "saber/blocks/SaberBlockParametersBase.h"
#include "saber/blocks/SaberOuterBlockBase.h"
#include "saber/interpolation/Geometry.h"

namespace saber {
namespace interpolation {

// -----------------------------------------------------------------------------

class InterpolationParameters : public SaberBlockParametersBase {
  OOPS_CONCRETE_PARAMETERS(InterpolationParameters, SaberBlockParametersBase)

 public:
  oops::Parameter<std::string> interpType{"interpolation type", "global", this};
  oops::RequiredParameter<eckit::LocalConfiguration> innerGeom{"inner geometry", this};
  oops::Parameter<eckit::LocalConfiguration> forwardInterpConf{"forward interpolator",
    eckit::LocalConfiguration(), this};
  oops::Parameter<eckit::LocalConfiguration> inverseInterpConf{"inverse interpolator",
    eckit::LocalConfiguration(), this};
  oops::Parameter<bool> fillMissingValues{"fill state missing values", false, this};
  oops::Variables mandatoryActiveVars() const override {return oops::Variables();}
};

// -----------------------------------------------------------------------------

class Interpolation : public SaberOuterBlockBase {
 public:
  static const std::string classname() {return "saber::Interpolation";}

  typedef InterpolationParameters Parameters_;

  Interpolation(const oops::GeometryData &,
                const oops::Variables &,
                const eckit::Configuration &,
                const Parameters_ &,
                const oops::FieldSet3D &,
                const oops::FieldSet3D &);
  virtual ~Interpolation() = default;

  const oops::GeometryData & innerGeometryData() const override {return *innerGeomData_;}
  const oops::Variables & innerVars() const override {return innerVars_;}

  void multiply(oops::FieldSet3D &) const override;
  void multiplyAD(oops::FieldSet3D &) const override;
  void leftInverseMultiply(oops::FieldSet3D & fset) const override
    {inverseMultiply(fset);}
  void rightInverseMultiply(oops::FieldSet3D & fset) const override
    {inverseMultiply(fset);}

  oops::FieldSet3D generateInnerFieldSet(const oops::GeometryData & innerGeometryData,
                                         const oops::Variables & innerVars) const override;

  oops::FieldSet3D generateOuterFieldSet(const oops::GeometryData & outerGeometryData,
                                         const oops::Variables & outerVars) const override;

 private:
  void print(std::ostream &) const override;
  void inverseMultiply(oops::FieldSet3D & fset) const;

  const Parameters_ params_;
  const oops::Variables innerVars_;
  const oops::Variables activeVars_;
  const oops::Variables invVars_;
  // pointers for delayed initialization
  std::unique_ptr<oops::GeometryData> innerGeomData_;
  std::unique_ptr<oops::GlobalInterpolator> globalInterp_;
  std::unique_ptr<atlas::Interpolation> regionalInterp_;
  mutable std::unique_ptr<oops::GlobalInterpolator> inverseGlobalInterp_;
  mutable std::unique_ptr<atlas::Interpolation> inverseRegionalInterp_;
};

}  // namespace interpolation
}  // namespace saber
