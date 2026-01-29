/*
 * (C) Copyright 2021 UCAR.
 *
 * This software is licensed under the terms of the Apache Licence Version 2.0
 * which can be obtained at http://www.apache.org/licenses/LICENSE-2.0.
 */

#include <ostream>
#include <string>

#include "oops/util/Logger.h"
#include "oops/util/Timer.h"

#include "fv3jedi/Geometry/Geometry.h"
#include "fv3jedi/Increment/Increment.h"
#include "fv3jedi/IO/FV3Restart/IOFms.h"
#include "fv3jedi/State/State.h"

namespace fv3jedi {
// -------------------------------------------------------------------------------------------------
static IOMaker<IOFms> makerIOFms_("fms restart");
// -------------------------------------------------------------------------------------------------
IOFms::IOFms(const Geometry & geom, const Parameters_ & params)
  : IOBase(geom, params.toConfiguration()), geom_(geom) {
  util::Timer timer(classname(), "IOFms");
  oops::Log::trace() << classname() << " constructor starting" << std::endl;
  fv3jedi_io_fms_create_f90(objectKeyForFortran_, params.toConfiguration(), geom.toFortran());
  oops::Log::trace() << classname() << " constructor done" << std::endl;
}
// -------------------------------------------------------------------------------------------------
IOFms::~IOFms() {
  util::Timer timer(classname(), "~IOFms");
  oops::Log::trace() << classname() << " destructor starting" << std::endl;
  fv3jedi_io_fms_delete_f90(objectKeyForFortran_);
  oops::Log::trace() << classname() << " destructor done" << std::endl;
}
// -------------------------------------------------------------------------------------------------
void IOFms::read(State & x, const eckit::LocalConfiguration & fileionames,
                 const eckit::LocalConfiguration & fileioscaling) const {
  util::Timer timer(classname(), "read state");
  oops::Log::trace() << classname() << " read state starting" << std::endl;
  fv3jedi_io_fms_read_state_f90(objectKeyForFortran_, geom_.toFortran(), x.toFortran(),
                                fileionames, fileioscaling);
  oops::Log::trace() << classname() << " read state done" << std::endl;
}
// -------------------------------------------------------------------------------------------------
void IOFms::read(Increment & dx, const eckit::LocalConfiguration & fileionames,
                 const eckit::LocalConfiguration & fileioscaling) const {
  util::Timer timer(classname(), "read increment");
  oops::Log::trace() << classname() << " read increment starting" << std::endl;
  fv3jedi_io_fms_read_increment_f90(objectKeyForFortran_, geom_.toFortran(), dx.toFortran(),
                                    fileionames, fileioscaling);
  oops::Log::trace() << classname() << " read increment done" << std::endl;
}
// -------------------------------------------------------------------------------------------------
void IOFms::write(const State & x, const eckit::LocalConfiguration & fileionames,
                  const eckit::LocalConfiguration & fileioscaling) const {
  util::Timer timer(classname(), "write state");
  oops::Log::trace() << classname() << " write state starting" << std::endl;
  fv3jedi_io_fms_write_state_f90(objectKeyForFortran_, geom_.toFortran(), x.toFortran(),
                                 fileionames, fileioscaling);
  oops::Log::trace() << classname() << " write state done" << std::endl;
}
// -------------------------------------------------------------------------------------------------
void IOFms::write(const Increment & dx, const eckit::LocalConfiguration & fileionames,
                  const eckit::LocalConfiguration & fileioscaling) const {
  util::Timer timer(classname(), "write increment");
  oops::Log::trace() << classname() << " write increment starting" << std::endl;
  fv3jedi_io_fms_write_increment_f90(objectKeyForFortran_, geom_.toFortran(), dx.toFortran(),
                                     fileionames, fileioscaling);
  oops::Log::trace() << classname() << " write increment done" << std::endl;
}
// -------------------------------------------------------------------------------------------------
void IOFms::print(std::ostream & os) const {
  os << classname() << " IO using FMS RESTART";
}
// -------------------------------------------------------------------------------------------------
}  // namespace fv3jedi
