# Clone and Build RDASapp
##  Currently supported platforms
-   NOAA RDHPCS Hera
-   NOAA RDHPCS Jet
-   NOAA RDHPCS Orion

##  Clone RDASApp
In the directory that you want to install RDASApp:  
```
git clone --recurse-submodules https://github.com/NOAA-EMC/RDASApp.git
```
##  Build RDASApp
Navigate to the RDASApp root directory and then build using the  `build.sh`  script:

    cd RDASApp
    ./build.sh

Run `./build.sh -h` to learn more about command line options supported by build.sh
