#!/bin/bash
set -euo pipefail

# Parse arguments from the CTestTestfiles.cmake
# APP is optional (i-jedi dispatches via `ijedi.x <app> <yaml>`; other executables take
# just <yaml>) and is left empty by `read` when the caller passes only 5 fields.
ARGUMENTS="$1"
read TEST_NAME EXECUTABLE CONFIG_FILE PPN NODES APP <<< "$ARGUMENTS"
WORKDIR="$(pwd)"
RDASApp="${WORKDIR}/../../.."
OUTFILE="${WORKDIR}/${TEST_NAME}.out"
ERRFILE="${WORKDIR}/${TEST_NAME}.err"
NTASKS=$((NODES * PPN))

rm -f ${OUTFILE}
rm -f ${ERRFILE}

# Only i-jedi's dispatch executable takes an app argument before the yaml
if [[ -n "${APP}" ]]; then
  EXE_ARGS="\"${APP}\" \"${CONFIG_FILE}\""
else
  EXE_ARGS="\"${CONFIG_FILE}\""
fi

# Run the PBS job
qsub -Wblock=true <<EOF
#!/bin/bash
#PBS -N ${TEST_NAME}
#PBS -l place=excl,select=${NODES}:ncpus=${PPN}:mem=500GB
#PBS -l walltime=00:45:00
#PBS -o ${OUTFILE}
#PBS -e ${ERRFILE}
#PBS -A ${PBS_ACCOUNT}
#PBS -q dev
cd ${WORKDIR}
module use ${RDASApp}/modulefiles
module load RDAS/wcoss2.intel
ulimit -s unlimited
ulimit -v unlimited
ulimit -a
export OOPS_TRACE=0
export OMP_NUM_THREADS=1
export LD_LIBRARY_PATH="${RDASApp}/build/lib64:${LD_LIBRARY_PATH}"
mpirun -n ${NTASKS} -ppn ${PPN} -cpu-bind core "${RDASApp}/build/bin/${EXECUTABLE}" ${EXE_ARGS}
MPIRUN_EXIT_CODE=\$?
echo "TEST_FINISHED_WITH_EXIT_CODE \$MPIRUN_EXIT_CODE" >> "${OUTFILE}"
exit \$MPIRUN_EXIT_CODE
EOF

