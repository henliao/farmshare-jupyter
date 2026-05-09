#!/bin/bash
#SBATCH --job-name=jupyter
#SBATCH --partition=gpu
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --time=2-00:00:00
#SBATCH --output=%x-%j.log

module load python/3.13.11
module load cuda/12.9.0
module load cudnn/9.8.0.87-12

# Activate venv (check both home and scratch)
if [ -d "$HOME/jupyter-env" ]; then
    source "$HOME/jupyter-env/bin/activate"
elif [ -d "/scratch/users/$(whoami)/jupyter-env" ]; then
    source "/scratch/users/$(whoami)/jupyter-env/bin/activate"
else
    echo "ERROR: No jupyter-env found. Run setup.sh first."
    exit 1
fi

# Pick a random port to avoid collisions
PORT=$(shuf -i 8000-9999 -n 1)
NODE=$(hostname)
TOKEN=$(python3 -c "import secrets; print(secrets.token_hex(24))")

# Write connection info for the start script to read
LOG_DIR="${HOME}/jupyter-logs"
mkdir -p "$LOG_DIR"
cat > "${LOG_DIR}/jupyter_${SLURM_JOB_ID}.info" << EOF
NODE=${NODE}
PORT=${PORT}
TOKEN=${TOKEN}
URL=http://localhost:${PORT}/lab?token=${TOKEN}
EOF

echo "============================================"
echo "Jupyter is running on ${NODE}:${PORT}"
echo ""
echo "Run this on your laptop:"
echo "  ssh -L ${PORT}:${NODE}:${PORT} $(whoami)@rice.stanford.edu"
echo ""
echo "Then open:"
echo "  http://localhost:${PORT}/lab?token=${TOKEN}"
echo "============================================"

jupyter lab \
    --ip=0.0.0.0 \
    --port="${PORT}" \
    --no-browser \
    --NotebookApp.token="${TOKEN}" \
    --NotebookApp.allow_origin='*'
