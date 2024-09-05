## 1.Clone RDASApp
If running on Orion, you will also need to run `module load git-lfs` before cloning. 
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
