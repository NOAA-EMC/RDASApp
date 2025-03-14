#!/bin/bash

# use nccmp or odc to compare the output of a ioda-converter
#
# argument 1: what type of file to compare; netcdf or odb
# argument 2: the command to run the ioda converter
# argument 3: the reference file name 
# argument 4: the test file name to compare against
# argument 5: the tolerance for differences between the files
# argument 6: verbose option

set -eu

file_type=$1
cmd=$2
file_name_ref=$3
file_name_test=$4
tol=${5:-"0.0"}
verbose=${6:-${VERBOSE:-"N"}}

[[ $verbose == [YyTt] || \
   $verbose == [Yy][Ee][Ss] || \
   $verbose == [Tt][Rr][Uu][Ee] ]] && set -x

rc="-1"
case $file_type in
  netcdf)
    $cmd && \
    nccmp $file_name_ref $file_name_test -d -f -S -T ${tol} -x longitude_latitude_pressure
    rc=${?}
    ;;
   odb)
    $cmd && \
    odc compare $file_name_ref $file_name_test
    rc=${?}
    ;;
  ascii)
    $cmd && \
    diff $file_name_ref $file_name_test
    rc=${?}
    ;;
   *)
    echo "ERROR: iodaconv_comp_rrfs.sh: Unrecognized file type: ${file_type}"
    rc="-2"
    ;;
esac

exit $rc
