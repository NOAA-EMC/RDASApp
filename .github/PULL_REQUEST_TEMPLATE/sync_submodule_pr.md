> **NOTE:** To use this template, remove any sections or lines that are not needed, and delete this line before submitting your PR.

> **NOTE:** If you would like to switch templates, you can manually change the URL by selecting a different template or removing the template parameter entirely. Example: To return to a generic PR, remove the "?expand=1&template=xxx.md" from the URL, then you can reselect the template.

Updated instructions for syncing submodules with upstream repositories can be found [here](https://github.com/NOAA-EMC/RDASApp/wiki/Sync-RDASApp-submodule-with-upstream-repositories).
Instructions for working with submodule can be found [here](https://github.com/NOAA-EMC/RDASApp/wiki/Working-with-RDASApp-submodules)

## Overview
This PR updates the RDASApp submodules to align with the latest changes in their respective upstream repositories. Each submodule has been synchronized to the head of their `develop` branches.

## Summary of Changes

#### 1. Submodule Updates (required)
> Copy and paste the result of `git submodule summary | grep sorc` in the space below.
```
```

#### 2. Staged `ctest-data` Updates (if applicable)
> What staged data were updated? Clearly state current and updated hases for each.
```
```
#### 3. Test Reference Updates (if applicable)
```
```

#### 4. Ctest Results (required)
> All ctests (e.g., ufo, fv3jedi, mpasjedi, etc.) must be run on at least one machine (e.g., Hera, Jet, Orion).
> The `rrfs-test` ctest must be run on all supported machines.
> Copy and paste the result of any failed ctests below and double check with the documentation if failing tests are expected.
```
```

#### 5. Notable Exclusions
> List exclusions here. Usually CRTM, MPAS, and gsibec.
-
-
-

#### 6. Checklist
- [ ] Submodules updated to latest `develop` branches.
- [ ] Staged ctest-data synchronized to all machines (if needed).
- [ ] Test references (rrfs-test) updated (if needed).
- [ ] Verified no unintended updates to locked submodules (e.g., CRTM, MPAS, gsibec).
- [ ] Validation and testing completed on all machines.


