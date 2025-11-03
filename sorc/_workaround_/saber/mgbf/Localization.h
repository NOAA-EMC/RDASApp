/*
 * (C) Copyright 2021 UCAR
 *
 * This software is licensed under the terms of the Apache Licence Version 2.0
 * which can be obtained at http://www.apache.org/licenses/LICENSE-2.0.
 */

#pragma once

#include <memory>
#include <sstream>
#include <string>
#include <vector>

#include "atlas/field.h"

#include "eckit/config/Configuration.h"

#include "oops/base/FieldSets.h"
#include "oops/base/State4D.h"
#include "oops/base/Variables.h"
#include "oops/generic/LocalizationBase.h"
#include "oops/util/Duration.h"
#include "oops/util/Logger.h"
#include "oops/util/Timer.h"

#include "saber/blocks/SaberParametricBlockChain.h"
#include "saber/oops/Utilities.h"

namespace saber {

// -----------------------------------------------------------------------------

template<typename MODEL>
class Localization : public oops::LocalizationBase<MODEL> {
  typedef oops::Geometry<MODEL>               Geometry_;
  typedef oops::Increment<MODEL>              Increment_;
  typedef oops::State<MODEL>                  State_;

 public:
  Localization(const Geometry_ &,
               const oops::Variables &,
               const eckit::Configuration &);
  ~Localization();
  static const std::string classname() {return "saber::Localization";}

  void randomize(Increment_ &) const override;
  void multiply(Increment_ &) const override;

 private:
  void print(std::ostream &) const override;
  std::unique_ptr<SaberParametricBlockChain> loc_;
};

// -----------------------------------------------------------------------------

template<typename MODEL>
Localization<MODEL>::Localization(const Geometry_ & geom,
                                  const oops::Variables & incVarsNoMeta,
                                  const eckit::Configuration & conf)
  : loc_()
{
  oops::Log::trace() << "Localization::Localization starting" << std::endl;
  util::Timer timer(classname(), "Localization");

  // Create dummy time
  util::DateTime dummyTime(1977, 5, 25, 0, 0, 0);

  // Initialize
  const std::vector<std::size_t> vlevs = geom.variableSizes(incVarsNoMeta);
  oops::Variables incVars(incVarsNoMeta);
  for (std::size_t i = 0; i < vlevs.size() ; ++i) {
    incVars[i].setLevels(vlevs[i]);
  }

  // Create dummy xb and fg
  const State_ xb_state(geom, incVars, dummyTime);
  oops::FieldSet3D xb(dummyTime, geom.getComm());
  xb.shallowCopy(xb_state.fieldSet());
  oops::FieldSet4D xb4d(xb);
  const State_ fg_state(geom, incVars, dummyTime);
  oops::FieldSet3D fg(dummyTime, geom.getComm());
  fg.shallowCopy(fg_state.fieldSet());
  oops::FieldSet4D fg4d(fg);

  oops::FieldSets emptyFsetEns({}, oops::mpi::myself(), {}, oops::mpi::myself());
  // TODO(AS): revisit what configuration needs to be passed to SaberParametricBlockChain.
  eckit::LocalConfiguration covarConf;
  eckit::LocalConfiguration ensembleConf;
  ensembleConf.set("ensemble size", 0);
  covarConf.set("ensemble configuration", ensembleConf);
  covarConf.set("adjoint test", conf.getBool("adjoint test", false));
  covarConf.set("adjoint tolerance", conf.getDouble("adjoint tolerance", 1.0e-12));
  covarConf.set("inverse test", conf.getBool("inverse test", false));
  covarConf.set("inverse tolerance", conf.getDouble("inverse tolerance", 1.0e-12));
  covarConf.set("square-root test", conf.getBool("square-root test", false));
  covarConf.set("square-root tolerance", conf.getDouble("square-root tolerance", 1.0e-12));
  covarConf.set("iterative ensemble loading", false);

  // 3D localization always used here (4D aspects handled in oops::Localization),
  // so this parameter can be anything.
  covarConf.set("time covariance", "univariate");
  // Initialize localization blockchain
  loc_ = std::make_unique<SaberParametricBlockChain>(geom, geom,
              incVars, xb4d, fg4d,
              emptyFsetEns, emptyFsetEns, covarConf, conf);

  oops::Log::trace() << "Localization:Localization done" << std::endl;
}

// -----------------------------------------------------------------------------

template<typename MODEL>
Localization<MODEL>::~Localization() {
  util::Timer timer(classname(), "~Localization");
  oops::Log::trace() << "Localization:~Localization destructed" << std::endl;
}

// -----------------------------------------------------------------------------

template<typename MODEL>
void Localization<MODEL>::randomize(Increment_ & dx) const {
  util::Timer timer(classname(), "randomize");
  oops::Log::trace() << "Localization:randomize starting" << std::endl;

  // SABER block chain randomization
  oops::FieldSet3D fset3d(dx.validTime(), dx.geometry().getComm());
  oops::FieldSet4D fset4d(fset3d);
  loc_->randomize(fset4d);

  // ATLAS fieldset to Increment_
  dx.fromFieldSet(fset4d[0].fieldSet());

  oops::Log::trace() << "Localization:randomize done" << std::endl;
}

// -----------------------------------------------------------------------------

template<typename MODEL>
void Localization<MODEL>::multiply(Increment_ & dx) const {
  util::Timer timer(classname(), "multiply");
  oops::Log::trace() << "Localization:multiply starting" << std::endl;

  // SABER block chain multiplication
  oops::FieldSet4D fset4d({dx.validTime(), dx.geometry().getComm()});
  fset4d[0].shallowCopy(dx.fieldSet());
  auto & src_fset = dx.fieldSet().fieldSet();
  auto & dst_fset = fset4d[0].fieldSet();
  if (src_fset.metadata().has("ensemble member index")) {
  oops::Log::trace() << "Localization:multiply starting 2 999yes" << std::endl;
    dst_fset.metadata().template set<int>("ensemble member index", src_fset.metadata().template get<int>("ensemble member index"));
}
  if (dst_fset.metadata().has("ensemble member index")) {
  oops::Log::trace() << "Localization:multiply startign 3 999 yes" << std::endl; }

  oops::Log::trace()<<dx << std::endl;
  loc_->multiply(fset4d);
  dx.fromFieldSet(fset4d[0].fieldSet());

  oops::Log::trace() << "Localization:multiply done" << std::endl;
}

// -----------------------------------------------------------------------------

template<typename MODEL>
void Localization<MODEL>::print(std::ostream & os) const {
  util::Timer timer(classname(), "print");
  os << "Localization:print not implemeted yet";
}

// -----------------------------------------------------------------------------

}  // namespace saber
