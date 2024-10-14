## 1.Clone RDASApp
If running on Orion/Hercules/Gaea, you will need to run `module load git-lfs` before cloning. 
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
    ush/run_rrfs_tests.sh $account
```
Where `$account` is your valid slurm resource account (e.g., `fv3-cam`, `da-cpu`, `wrfruc`, `rtrr`, `nrtrr`, etc.).   
- To run ctest mannualy without using the above bash script, follow these two steps first:  
`source ush/load_rdas.sh`    
`export SLURM_ACCOUNT=$account`
