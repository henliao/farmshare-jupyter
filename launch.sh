#!/usr/bin/env bash
# One-command launcher: submit job, wait, open SSH tunnel, open browser.
# Run this from your local machine (Mac/Linux).
#
# Usage: ./launch.sh <sunetid> [--cpu]
#   --cpu    Use CPU-only partition

set -euo pipefail

# Parse args
SUNET=""
CPU_MODE=false
for arg in "$@"; do
    if [ "$arg" = "--cpu" ]; then
        CPU_MODE=true
    elif [ -z "$SUNET" ]; then
        SUNET="$arg"
    fi
done

if [ -z "$SUNET" ]; then
    echo "Usage: ./launch.sh <sunetid> [--cpu]"
    echo "Example: ./launch.sh yoursunetid"
    exit 1
fi

REMOTE="${SUNET}@rice.stanford.edu"
LOCAL_PORT="${LOCAL_PORT:-8888}"
POLL_INTERVAL=5
MAX_WAIT=300

if [ "$CPU_MODE" = true ]; then
    SBATCH_ARGS="--partition=normal --mem=16G"
    echo "[1/5] Uploading scripts to FarmShare (CPU mode)..."
else
    SBATCH_ARGS="--partition=gpu --gres=gpu:1 --mem=32G"
    echo "[1/5] Uploading scripts to FarmShare..."
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
scp -q "$SCRIPT_DIR/jupyter.sbatch" "$REMOTE:~/farmshare-jupyter/jupyter.sbatch"

echo "[2/5] Submitting SLURM job..."
JOB_OUTPUT=$(ssh "$REMOTE" "bash -l -c 'sbatch $SBATCH_ARGS ~/farmshare-jupyter/jupyter.sbatch'")
JOBID=$(echo "$JOB_OUTPUT" | grep -o '[0-9]\+')

if [ -z "$JOBID" ]; then
    echo "Failed to submit job:"
    echo "$JOB_OUTPUT"
    exit 1
fi
echo "  Job ID: $JOBID"

echo "[3/5] Waiting for job to start..."
ELAPSED=0
while [ $ELAPSED -lt $MAX_WAIT ]; do
    STATE=$(ssh "$REMOTE" "squeue -j $JOBID -o %T -h 2>/dev/null" || echo "UNKNOWN")
    if [ "$STATE" = "RUNNING" ]; then
        break
    elif [ "$STATE" = "PENDING" ]; then
        echo "  PENDING (${ELAPSED}s)"
    elif [ -z "$STATE" ] || [ "$STATE" = "UNKNOWN" ]; then
        echo "Job $JOBID not found. It may have failed."
        echo "Check: ssh $REMOTE 'cat jupyter-${JOBID}.log'"
        exit 1
    fi
    sleep $POLL_INTERVAL
    ELAPSED=$((ELAPSED + POLL_INTERVAL))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo ""
    echo "Job $JOBID is still queued after ${MAX_WAIT}s. All GPU nodes may be busy."
    echo ""
    echo "Current GPU availability:"
    ssh "$REMOTE" "sinfo -p gpu -o '  %N  %G  %C  %t'" 2>/dev/null
    echo ""
    echo "Your job is still in the queue and will start when a node frees up."
    echo "You can:"
    echo "  - Wait: run this script again (it will pick up the same job)"
    echo "  - Check status: ssh $REMOTE 'squeue -j $JOBID'"
    echo "  - Use CPU instead: ./launch.sh $SUNET --cpu"
    echo "  - Cancel: ssh $REMOTE 'scancel $JOBID'"
    exit 1
fi

sleep 4

echo "[4/5] Reading connection info..."
INFO=$(ssh "$REMOTE" "cat ~/jupyter-logs/jupyter_${JOBID}.info 2>/dev/null" || echo "")

# Retry if info file not ready yet
if [ -z "$INFO" ]; then
    sleep 5
    INFO=$(ssh "$REMOTE" "cat ~/jupyter-logs/jupyter_${JOBID}.info 2>/dev/null" || echo "")
fi

if [ -z "$INFO" ]; then
    echo "Could not read connection info."
    echo "Check: ssh $REMOTE 'cat jupyter-${JOBID}.log'"
    exit 1
fi

NODE=$(echo "$INFO" | grep '^NODE=' | cut -d= -f2)
PORT=$(echo "$INFO" | grep '^PORT=' | cut -d= -f2)
TOKEN=$(echo "$INFO" | grep '^TOKEN=' | cut -d= -f2)

echo "  Node: $NODE, Port: $PORT"

echo "[5/5] Opening SSH tunnel (localhost:${LOCAL_PORT} -> ${NODE}:${PORT})..."
echo ""
echo "============================================"
echo "Jupyter is ready at:"
echo "  http://localhost:${LOCAL_PORT}/lab?token=${TOKEN}"
echo "============================================"
echo ""
echo "Press Ctrl+C to close the tunnel."
echo "(Jupyter keeps running. Cancel with: ssh $REMOTE 'scancel $JOBID')"
echo ""

# Open browser on macOS
if command -v open &>/dev/null; then
    open "http://localhost:${LOCAL_PORT}/lab?token=${TOKEN}" 2>/dev/null &
fi

# Keep tunnel open in foreground
ssh -N -L "${LOCAL_PORT}:${NODE}:${PORT}" "$REMOTE"
