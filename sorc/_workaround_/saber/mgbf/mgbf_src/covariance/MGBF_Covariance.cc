/*
 * (C) Copyright 2022 United States Government as represented by the Administrator of the National
 *     Aeronautics and Space Administration
 *
 * This software is licensed under the terms of the Apache Licence Version 2.0
 * which can be obtained at http://www.apache.org/licenses/LICENSE-2.0.
 */

#include "saber/mgbf/covariance/MGBF_Covariance.h"

#include <memory>
#include <string>
#include <vector>

#include "atlas/field.h"
#include "atlas/functionspace.h"
#include "atlas/grid.h"
#include "atlas/library.h"
#include "atlas/runtime/Log.h"

#include "oops/base/Variables.h"
#include "oops/util/abor1_cpp.h"
#include "oops/util/Logger.h"
#include "oops/util/Timer.h"

#include "saber/mgbf/covariance/MGBF_Covariance.interface.h"

namespace saber {
namespace mgbf {

// -------------------------------------------------------------------------------------------------

static SaberCentralBlockMaker<MGBF_Covariance> makerCovariance_("MGBF_covariance");

}  // namespace MGBF 
}  // namespace saber
