/*
 * (C) Copyright 2021 UCAR.
 *
 * This software is licensed under the terms of the Apache Licence Version 2.0
 * which can be obtained at http://www.apache.org/licenses/LICENSE-2.0.
 */

#pragma once

#include <ostream>
#include <string>
#include <vector>

#include "oops/util/DateTime.h"
#include "oops/util/parameters/OptionalParameter.h"
#include "oops/util/parameters/Parameter.h"
#include "oops/util/parameters/Parameters.h"

#include "fv3jedi/IO/Utils/IOBase.h"
#include "IOFms.interface.h"

namespace fv3jedi {

// -------------------------------------------------------------------------------------------------

class IOFmsParameters : public IOParametersBase {
  OOPS_CONCRETE_PARAMETERS(IOFmsParameters, IOParametersBase)

 public:
  // Are files to be read restarts or not?
  oops::Parameter<bool> is_restart{"is restart",
                                   "is restart",
                                   true, this};

  // Are these regional restart files (single tile)
  oops::Parameter<bool> regional_restart{"regional restart",
                                         "regional restart",
                                         false, this};

  // Data path for files being read
  oops::Parameter<std::string> datapath{"datapath", "path to location of files to be read", "./",
                                        this};

  // Filename to be read or written
  oops::Parameter<std::string> filename_nonrestart{"filename_nonrestart", "filename_nonrestart",
                                        "fms_nonrestart.nc", this};

  // Restart filenames to be read
  oops::Parameter<std::string> filename_core{"filename_core", "filename_core",
                                             "fv_core.res.nc", this};
  oops::Parameter<std::string> filename_trcr{"filename_trcr", "filename_trcr",
                                             "fv_tracer.res.nc", this};
  oops::Parameter<std::string> filename_sfcd{"filename_sfcd", "filename_sfcd",
                                             "sfc_data.nc", this};
  oops::Parameter<std::string> filename_sfcw{"filename_sfcw", "filename_sfcw",
                                             "fv_srf_wnd.res.nc", this};
  oops::Parameter<std::string> filename_cplr{"filename_cplr", "filename_cplr",
                                             "coupler.res", this};
  oops::Parameter<std::string> filename_spec{"filename_spec", "filename_spec",
                                             "null", this};
  oops::Parameter<std::string> filename_phys{"filename_phys", "filename_phys",
                                             "phy_data.nc", this};
  oops::Parameter<std::string> filename_orog{"filename_orog", "filename_orog",
                                             "oro_data.nc", this};
  oops::Parameter<std::string> filename_cold{"filename_cold", "filename_cold",
                                             "gfs_data.nc", this};

  // Input filename may be templated with datetimes
  oops::Parameter<bool> filename_is_datetime_templated{"filename is datetime templated",
                                                       "filename is datetime templated",
                                                       false, this};

  // Skip reading/writing the coupler.res file
  oops::Parameter<bool> skip_coupler_file{"skip coupler file",
                                          "skip coupler file",
                                          false, this};

  // Prepend the files with the date
  oops::Parameter<bool> prepend_files_with_date{"prepend files with date",
                                                "prepend files with date",
                                                true, this};

  // Force tell the system that surface pressure is in the file
  oops::Parameter<bool> psinfile{"psinfile",
                                 "tell the system surface pressure is in the file",
                                 false, this};

  // Optionally the config may contain member
  oops::OptionalParameter<int> member{"member", "ensemble member number", this};

  // Let user set the calendar type
  oops::Parameter<int> calendar_type{"calendar type", "calendar type", 2, this};

  // Ignore checksum for FMS restarts?
  oops::Parameter<bool> ignore_checksum{"ignore checksum",
                                        "whether to ignore restart checksums",
                                        true, this};

  // Write only a subset of fields?
  oops::OptionalParameter<std::vector<std::string>> fields_to_write{"fields to write",
                                                                    "names of fields to write",
                                                                    this};
  // Write values into pre-existing restart files instead of recreating metadata
  // (currently used only in the regional restart write path)
  oops::Parameter<bool> write_into_existing_files{"write into existing files",
                                                  "true or false",
                                                  false, this};

  // Write analysis variables in specified bit depth
  // (currently used only in the regional restart write path)
  // "native, 32bit or 64bit"
  oops::Parameter<std::string> default_output_resolution{"default output resolution",
                                                         "native, 32bit or 64bit",
                                                         "native", this};

  // Tunable for Lustre file systems
  //oops::Parameter<std::string> lustre_stripe_size{"lustre stripe size",
  oops::Parameter<int> lustre_stripe_size{"lustre stripe size",
                                          "lustre stripe size in bytes",
                                          1048576, this};

};

// -------------------------------------------------------------------------------------------------
class IOFms : public IOBase, private util::ObjectCounter<IOFms> {
 public:
  static const std::string classname() {return "fv3jedi::IOFms";}

  typedef IOFmsParameters Parameters_;

  IOFms(const Geometry &, const Parameters_ &);
  ~IOFms();
  void read(State &, const eckit::LocalConfiguration &,
            const eckit::LocalConfiguration &) const override;
  void read(Increment &, const eckit::LocalConfiguration &,
            const eckit::LocalConfiguration &) const override;
  void write(const State &, const eckit::LocalConfiguration &,
             const eckit::LocalConfiguration &) const override;
  void write(const Increment &, const eckit::LocalConfiguration &,
             const eckit::LocalConfiguration &) const override;

 private:
  F90iofms objectKeyForFortran_;
  const Geometry & geom_;
  void print(std::ostream &) const override;
};

// -------------------------------------------------------------------------------------------------

}  // namespace fv3jedi
