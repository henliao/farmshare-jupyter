#!/usr/bin/env bash
# Run a Jupyter notebook headlessly on a GPU node via SLURM.
# The notebook executes start-to-finish and saves output to a new file.
#
# Usage: bash run-notebook.sh <notebook.ipynb> [--cpu] [--timeout SECONDS]
#
# The output notebook is saved as <notebook>_output.ipynb in the same directory.
# If a cell fails, execution stops and the error is captured in the output notebook.

set -euo pipefail

# Parse args
NOTEBOOK=""
PARTITION="gpu"
GPU_LINE="#SBATCH --gres=gpu:1"
TIMEOUT=3600  # default 1 hour per cell

while [ $# -gt 0 ]; do
    case "$1" in
        --cpu)
            PARTITION="normal"
            GPU_LINE=""
            shift
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        -*)
            echo "Unknown option: $1"
            exit 1
            ;;
        *)
            NOTEBOOK="$1"
            shift
            ;;
    esac
done

if [ -z "$NOTEBOOK" ]; then
    echo "Usage: bash run-notebook.sh <notebook.ipynb> [--cpu] [--timeout SECONDS]"
    exit 1
fi

if [ ! -f "$NOTEBOOK" ]; then
    echo "ERROR: $NOTEBOOK not found."
    exit 1
fi

NOTEBOOK_ABS="$(cd "$(dirname "$NOTEBOOK")" && pwd)/$(basename "$NOTEBOOK")"
NOTEBOOK_DIR="$(dirname "$NOTEBOOK_ABS")"
NOTEBOOK_NAME="$(basename "$NOTEBOOK" .ipynb)"
OUTPUT_NOTEBOOK="${NOTEBOOK_DIR}/${NOTEBOOK_NAME}_output.ipynb"

# Generate the SLURM script
SBATCH_FILE=$(mktemp /tmp/run-notebook-XXXX.sbatch)
cat > "$SBATCH_FILE" << EOF
#!/bin/bash
#SBATCH --job-name=nb-${NOTEBOOK_NAME}
#SBATCH --partition=${PARTITION}
${GPU_LINE}
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --time=2-00:00:00
#SBATCH --output=${NOTEBOOK_DIR}/nb-${NOTEBOOK_NAME}-%j.log

module load python/3.13.11
if [ "${PARTITION}" = "gpu" ]; then
    module load cuda/12.9.0
    module load cudnn/9.8.0.87-12
fi

# Activate venv
if [ -d "\$HOME/jupyter-env" ]; then
    source "\$HOME/jupyter-env/bin/activate"
elif [ -d "/scratch/users/\$(whoami)/jupyter-env" ]; then
    source "/scratch/users/\$(whoami)/jupyter-env/bin/activate"
else
    echo "ERROR: No jupyter-env found. Run setup.sh first."
    exit 1
fi

echo "Running notebook: ${NOTEBOOK_ABS}"
echo "Output: ${OUTPUT_NOTEBOOK}"
echo "Node: \$(hostname)"
echo "Start: \$(date)"
echo ""

jupyter nbconvert \
    --to notebook \
    --execute \
    --ExecutePreprocessor.timeout=${TIMEOUT} \
    --output "${OUTPUT_NOTEBOOK}" \
    "${NOTEBOOK_ABS}"

STATUS=\$?
echo ""
echo "Finished: \$(date)"
if [ \$STATUS -eq 0 ]; then
    echo "Success. Output saved to: ${OUTPUT_NOTEBOOK}"
else
    echo "Failed with exit code \$STATUS. Partial output may be in: ${OUTPUT_NOTEBOOK}"
fi
EOF

echo "Submitting notebook: $NOTEBOOK"
echo "Output will be saved to: $OUTPUT_NOTEBOOK"
echo ""

JOBID=$(sbatch "$SBATCH_FILE" 2>&1 | grep -o '[0-9]*')
rm -f "$SBATCH_FILE"

if [ -z "$JOBID" ]; then
    echo "Failed to submit job."
    exit 1
fi

echo "Job $JOBID submitted."
echo ""
echo "Monitor:"
echo "  squeue -j $JOBID                              # job status"
echo "  tail -f ${NOTEBOOK_DIR}/nb-${NOTEBOOK_NAME}-${JOBID}.log   # live output"
echo ""
echo "When done, your output notebook is:"
echo "  $OUTPUT_NOTEBOOK"
