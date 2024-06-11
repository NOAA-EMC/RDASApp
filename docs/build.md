## 1.Clone RDASApp
In the directory that you want to install RDASApp:  
```
git clone --recurse-submodules https://github.com/NOAA-EMC/RDASApp.git
```
## 2.Build RDASApp
Navigate to the RDASApp root directory and then build using the  `build.sh`  script:
```
    cd RDASApp
    ./build.sh
```
Run `./build.sh -h` to learn more about command line options supported by build.sh

## 3. RRFS CTest
### load modules for ctest
The compiling step can load the modules needed for running the ctest. If running the ctest with a new terminal, extra steps are needed to load the modules:
```
module use modulefiles/
module load RDAS/hera.intel
```
Where `hera.intel` should be replaced with a correct platform-dependent module file, such as `jet.intel`, `orion.intel`, `hercules.intel`

### Run ctest
```
export SLURM_ACCOUNT=$account
cd RDASApp/build
ctest -VV -R rrfs_fv3jedi_hyb_2022052619
ctest -VV -R rrfs_fv3jedi_letkf_2022052619
ctest -VV -R rrfs_mpasjedi_2022052619_Ens3Dvar
ctest -VV -R rrfs_mpasjedi_2022052619_letkf
```
Where `$account` is the slurm resource account (e.g., `fv3-cam`, `da-cpu`, `wrfruc`, etc.). 
