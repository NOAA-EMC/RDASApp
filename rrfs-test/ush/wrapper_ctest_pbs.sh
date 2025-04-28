#!/bin/bash
set -euo pipefail

ARGUMENTS="$1"
read TEST_NAME EXECUTABLE CONFIG_FILE PPN NODES <<< "$ARGUMENTS"
WORKDIR="$(pwd)"
RDASApp="${WORKDIR}/../../.."
OUTFILE="${WORKDIR}/${TEST_NAME}.out"
ERRFILE="${WORKDIR}/${TEST_NAME}.err"
NTASKS=$((NODES * PPN))

rm -f ${OUTFILE}
rm -f ${ERRFILE}

# Create the PBS job script
PBS_SCRIPT="${WORKDIR}/pbs_job.sh"
cat <<EOF > "$PBS_SCRIPT"
#!/bin/bash
#PBS -N ${TEST_NAME}
#PBS -l place=excl,select=${NODES}:ncpus=${PPN}
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
export LD_LIBRARY_PATH="\${LD_LIBRARY_PATH}:${RDASApp}/build/lib"
/opt/cray/pals/1.3.2/bin/mpirun -n ${NTASKS} -ppn ${PPN} -cpu-bind core "${RDASApp}/build/bin/${EXECUTABLE}" "${CONFIG_FILE}"
MPIRUN_EXIT_CODE=\$?
echo "TEST_FINISHED_WITH_EXIT_CODE \$MPIRUN_EXIT_CODE" >> "${OUTFILE}"
exit \$MPIRUN_EXIT_CODE
EOF

# Submit job and get Job ID
JOBID=$(qsub "$PBS_SCRIPT")
echo "Submitted job $JOBID"
echo "Waiting for job to complete..."

# Check for the job to finish
INTERVAL=5
while true; do
    JOB_STATUS=$(qstat "$JOBID" 2>&1)
    if echo "$JOB_STATUS" | grep -q "Unknown Job Id" || echo "$JOB_STATUS" | grep -q "Job has finished"; then
        break
    fi
    sleep $INTERVAL
done

# Extract and return the exit code
RAW_EXIT_LINE=$(grep -E "^TEST_FINISHED_WITH_EXIT_CODE [0-9]+$" "$OUTFILE" | tail -n1)
EXIT_CODE=$(echo "$RAW_EXIT_LINE" | awk '{print $2}' | tr -d '\r')

# Fallback in case EXIT_CODE is empty
if [[ -z "$EXIT_CODE" ]]; then
    echo "Failed to extract numeric exit code. Assuming failure." >&2
    EXIT_CODE=1
fi

echo "Test completed with exit code: $EXIT_CODE"
exit "$EXIT_CODE"
