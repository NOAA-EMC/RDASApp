#!/bin/bash -xvf
set -x
ulimit -s unlimited
ulimit -a

#########################################################################
#                                                                       #
#   There are four inputs required for convert bufr to IODA for AMSUA   #
#   1  rap.t${hh}z.esamua.tm00.bufr_d
#   2  rap.t${hh}z.1bamua.tm00.bufr_d                                        #
#   3  RDASApp/rrfs-test/IODA/yaml/bufr_esamua_mapping.yaml
#   4  RDASApp/rrfs-test/IODA/yaml/bufr_1bamua_mapping.yaml
#                                                                       #
#########################################################################
readonly RDASApp_dir=$(cd "$(dirname "$(readlink -f -n "${BASH_SOURCE[0]}" )" )/../../.." && pwd -P)

# ===============================
# Load obsForge required modules
# ===============================
module purge
source ${RDASApp_dir}/ush/load_rdas.sh
module list

# ==============================
# Set bufr-query python library
# ==============================
export LD_LIBRARY_PATH="${RDASApp_dir}/build/lib:${LD_LIBRARY_PATH}"
export PYTHONPATH="${PYTHONPATH}:${RDASApp_dir}/build/lib/python3.10/site-packages"
python3 -c "import bufr"


# ========================
# Set ioda python library
# =========================
export PYTHONPATH="${PYTHONPATH}:${RDASApp_dir}/build/lib/python3.10"

# ============
# Set wxfloww
# ============
export PYTHONPATH="${PYTHONPATH}:${RDASApp_dir}/sorc/wxflow/src"



cdate=2024052700
y4=`echo $cdate | cut -c1-4`
m2=`echo $cdate | cut -c5-6`
d2=`echo $cdate | cut -c7-8`
h2=`echo $cdate | cut -c9-10`

work_dir=$PWD

input_es=$cdate.rap.t${h2}z.esamua.tm00.bufr_d
input_1b=$cdate.rap.t${h2}z.1bamua.tm00.bufr_d
output_file=$cdate.rap.t${h2}z.amsua_{splits/satId}.tm00.nc
yaml_1b=../yaml/bufr_1bamua_mapping.yaml
yaml_es=../yaml/bufr_esamua_mapping.yaml


python bufr2ioda_amsua.py $input_es $input_1b  $yaml_1b $yaml_es $output_file

