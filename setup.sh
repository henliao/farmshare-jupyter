#!/usr/bin/env bash
# One-time setup: create a Python venv with Jupyter + ML packages on FarmShare.
# Run this on a rice login node.
#
# Usage: bash setup.sh [--scratch]
#   --scratch  Install venv on /scratch instead of home (saves quota)

set -euo pipefail

# Where to put the venv
if [[ "${1:-}" == "--scratch" ]]; then
    VENV_DIR="/scratch/users/$(whoami)/jupyter-env"
    echo "Installing to scratch: $VENV_DIR"
else
    VENV_DIR="$HOME/jupyter-env"
fi

if [ -d "$VENV_DIR" ]; then
    echo "Venv already exists at $VENV_DIR"
    echo "To reinstall, remove it first: rm -rf $VENV_DIR"
    exit 1
fi

echo "[1/4] Loading Python module..."
module load python/3.13.11

echo "[2/4] Creating virtual environment (without pip)..."
python3 -m venv --without-pip "$VENV_DIR"
source "$VENV_DIR/bin/activate"

echo "[3/4] Bootstrapping pip..."
curl -sS https://bootstrap.pypa.io/get-pip.py | python3

echo "[4/4] Installing packages..."
pip install jupyter jupyterlab ipykernel \
    torch --index-url https://download.pytorch.org/whl/cu128
pip install numpy pandas scikit-learn matplotlib

echo ""
echo "Installed packages:"
pip list 2>&1 | grep -iE "torch|jupyter|numpy|pandas|scikit|matplotlib"
echo ""
echo "Venv size: $(du -sh "$VENV_DIR" | cut -f1)"
echo ""
echo "Done. Start a Jupyter session with:"
echo "  bash ~/farmshare-jupyter/start.sh"
