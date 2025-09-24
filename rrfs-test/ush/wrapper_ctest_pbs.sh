#!/bin/bash
set -euo pipefail

# Parse arguments from the CTestTestfiles.cmake
ARGUMENTS="$1"
read TEST_NAME EXECUTABLE CONFIG_FILE PPN NODES <<< "$ARGUMENTS"
WORKDIR="$(pwd)"
RDASApp="${WORKDIR}/../../.."
OUTFILE="${WORKDIR}/${TEST_NAME}.out"
ERRFILE="${WORKDIR}/${TEST_NAME}.err"
NTASKS=$((NODES * PPN))

rm -f ${OUTFILE}
rm -f ${ERRFILE}

# Run the PBS job
qsub -Wblock=true <<EOF
#!/bin/bash
#PBS -N ${TEST_NAME}
#PBS -l place=excl,select=${NODES}:ncpus=${PPN}:mem=500GB
#PBS -l walltime=00:30:00
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
export LD_LIBRARY_PATH="${RDASApp}/build/lib64:${RDASApp}/build/lib:${LD_LIBRARY_PATH}"
mpirun -n ${NTASKS} -ppn ${PPN} -cpu-bind core "${RDASApp}/build/bin/${EXECUTABLE}" "${CONFIG_FILE}"
MPIRUN_EXIT_CODE=\$?
echo "TEST_FINISHED_WITH_EXIT_CODE \$MPIRUN_EXIT_CODE" >> "${OUTFILE}"
exit \$MPIRUN_EXIT_CODE
EOF

