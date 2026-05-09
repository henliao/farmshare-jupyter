#!/usr/bin/env bash
# Submit a Jupyter SLURM job and wait for connection info.
# Run this on a rice login node.
#
# Usage: bash start.sh [--cpu]
#   --cpu  Use CPU-only partition (more nodes available, no GPU)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
POLL_INTERVAL=5
MAX_WAIT=300

if [[ "${1:-}" == "--cpu" ]]; then
    SBATCH_FILE="${SCRIPT_DIR}/jupyter-cpu.sbatch"
    echo "Submitting CPU-only Jupyter job..."
else
    SBATCH_FILE="${SCRIPT_DIR}/jupyter-gpu.sbatch"
    echo "Submitting GPU Jupyter job..."
fi

if [ ! -f "$SBATCH_FILE" ]; then
    echo "ERROR: $SBATCH_FILE not found."
    exit 1
fi

JOBID=$(sbatch "$SBATCH_FILE" 2>&1 | grep -o '[0-9]*')
if [ -z "$JOBID" ]; then
    echo "Failed to submit job."
    exit 1
fi

echo "Job $JOBID submitted. Waiting for it to start..."

ELAPSED=0
while [ $ELAPSED -lt $MAX_WAIT ]; do
    STATE=$(squeue -j "$JOBID" -h -o "%T" 2>/dev/null)
    if [ "$STATE" = "RUNNING" ]; then
        break
    elif [ -z "$STATE" ]; then
        echo "Job $JOBID disappeared. It may have failed."
        echo "Check: cat jupyter-${JOBID}.log"
        exit 1
    fi
    echo "  $STATE (${ELAPSED}s)"
    sleep $POLL_INTERVAL
    ELAPSED=$((ELAPSED + POLL_INTERVAL))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo "Still waiting after ${MAX_WAIT}s. Job is queued."
    echo "Check: squeue -j $JOBID"
    exit 1
fi

# Wait for Jupyter to write the info file
sleep 4

INFO_FILE="$HOME/jupyter-logs/jupyter_${JOBID}.info"
for i in $(seq 1 15); do
    if [ -f "$INFO_FILE" ]; then
        break
    fi
    sleep 2
done

if [ ! -f "$INFO_FILE" ]; then
    echo "Could not read connection info."
    echo "Check: cat jupyter-${JOBID}.log"
    exit 1
fi

NODE=$(grep '^NODE=' "$INFO_FILE" | cut -d= -f2)
PORT=$(grep '^PORT=' "$INFO_FILE" | cut -d= -f2)
TOKEN=$(grep '^TOKEN=' "$INFO_FILE" | cut -d= -f2)

echo ""
echo "============================================"
echo "Job $JOBID running on $NODE"
echo ""
echo "Run this on your laptop:"
echo "  ssh -L ${PORT}:${NODE}:${PORT} $(whoami)@rice.stanford.edu"
echo ""
echo "Then open:"
echo "  http://localhost:${PORT}/lab?token=${TOKEN}"
echo "============================================"
echo ""
echo "To stop: scancel $JOBID"
