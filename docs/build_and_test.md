## 1.Clone RDASApp
```
git clone --recurse-submodules https://github.com/NOAA-EMC/RDASApp.git
```
## 2.Build RDASApp
```
    cd RDASApp
    ./build.sh
```
Run `./build.sh -h` to learn more about command line options supported by build.sh

## 3. RRFS CTest
```
module use modulefiles
module load RDAS/hera.intel
export SLURM_ACCOUNT=$account
cd build
ctest -VV -R rrfs_fv3jedi_hyb_2022052619
ctest -VV -R rrfs_fv3jedi_letkf_2022052619
ctest -VV -R rrfs_mpasjedi_2022052619_Ens3Dvar
ctest -VV -R rrfs_mpasjedi_2022052619_letkf
```
Where `hera.intel` should be replaced with a correct platform-dependent module file, such as `jet.intel`, `orion.intel`, `hercules.intel` etc. And `$account` is the slurm resource account (e.g., `fv3-cam`, `da-cpu`, `wrfruc`, etc.). 
