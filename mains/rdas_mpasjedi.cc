// -------------------------------------------------------------------------------------------------

#include <functional>
#include <map>

#include "oops/generic/instantiateModelFactory.h"
#include "saber/oops/instantiateCovarFactory.h"
#include "saber/oops/ErrorCovarianceToolbox.h"
#include "saber/oops/instantiateLocalizationFactory.h"
#include "ufo/instantiateObsErrorFactory.h"
#include "ufo/instantiateObsFilterFactory.h"
#include "ufo/instantiateObsLocFactory.h"
#include "ufo/ObsTraits.h"

#include "oops/runs/ConvertState.h"
#include "oops/runs/HofX4D.h"
#include "oops/runs/LocalEnsembleDA.h"
#include "oops/runs/Run.h"
#include "oops/runs/Variational.h"
#include "mpasjedi/Traits.h"

// -------------------------------------------------------------------------------------------------

template<typename Traits>
int runApp(int argc, char** argv, const std::string traits, const std::string appName) {

  // Create the Run object
  oops::Run run(argc, argv);

  // Instantiate oops factories
  oops::instantiateModelFactory<mpas::Traits>();

  // Instantiate saber factories
  saber::instantiateCovarFactory<mpas::Traits>();

  // Intantiate ufo factories
  ufo::instantiateObsErrorFactory();
  ufo::instantiateObsFilterFactory();

  // Localization for ensemble DA
  if (appName == "localensembleda") {
    if (traits == "mpasjedi") {
      ufo::instantiateObsLocFactory<mpas::Traits>();
    }
  }

  // Localization for variational DA
  if (appName == "variational") {
    if (traits == "mpasjedi") {
      saber::instantiateLocalizationFactory<mpas::Traits>();
    } 
  }

  // Intantiate ufo factories
  ufo::instantiateObsErrorFactory();
  ufo::instantiateObsFilterFactory();

  // Application pointer
  std::unique_ptr<oops::Application> app;

  // Define a map from app names to lambda functions that create unique_ptr to Applications
  std::map<std::string, std::function<std::unique_ptr<oops::Application>()>> apps;

  apps["convertstate"] = []() {
      return std::make_unique<oops::ConvertState<mpas::Traits>>();
  };
  apps["bump"] = []() {
      return std::make_unique<saber::ErrorCovarianceToolbox<mpas::Traits>>();
  };
  apps["hofx4d"] = []() {
      return std::make_unique<oops::HofX4D<mpas::Traits, ufo::ObsTraits>>();
  };
  apps["localensembleda"] = []() {
      return std::make_unique<oops::LocalEnsembleDA<mpas::Traits, ufo::ObsTraits>>();
  };
  apps["variational"] = []() {
    return std::make_unique<oops::Variational<mpas::Traits, ufo::ObsTraits>>();
  };

  // Create application object and point to it
  auto it = apps.find(appName);

  // Run the application
  return run.execute(*(it->second()));
}

// -------------------------------------------------------------------------------------------------

int main(int argc,  char ** argv) {
  // Check that the number of arguments is correct
  // ----------------------------------------------
  ASSERT_MSG(argc >= 3, "Usage: " + std::string(argv[0]) + " <traits> <application> <options>");

  // Get traits from second argument passed to executable
  // ----------------------------------------------------
  std::string traits = argv[1];
  for (char &c : traits) {c = std::tolower(c);}

  // Get the application to be run
  std::string app = argv[2];
  for (char &c : app) {c = std::tolower(c);}

  // Check that the traits are recognized
  // ------------------------------------
  const std::set<std::string> validTraits = {"mpasjedi"};
  ASSERT_MSG(validTraits.find(traits) != validTraits.end(), "Traits not recognized: " + traits);

  // Check that the application is recognized
  // ----------------------------------------
  const std::set<std::string> validApps = {
    "convertstate",
    "bump",
    "hofx4d",
    "localensembleda",
    "variational"
  };
  ASSERT_MSG(validApps.find(app) != validApps.end(), "Application not recognized: " + app);

  // Remove traits and program from argc and argv
  // --------------------------------------------
  argv[2] = argv[0];  // Move executable name to third position
  argv += 2;          // Move pointer up two
  argc -= 2;          // Remove 2 from count

  // Call application specific main functions
  // ----------------------------------------
  if (traits == "mpasjedi") {
    return runApp<mpas::Traits>(argc, argv, traits, app);
  }
}

// -------------------------------------------------------------------------------------------------
