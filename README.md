# Farmshare Jupyter + GPU

Run Jupyter Lab on Stanford Farmshare with GPU access via SLURM.

## Cluster overview

| | GPU (oat) | CPU (barley, wheat) |
|---|---|---|
| Nodes | 6 (oat-01 to oat-06) | 12 (barley-01..04, wheat-01..08) |
| GPUs/node | 4x NVIDIA L40S (48 GB VRAM) | None |
| CPUs/node | 64 | 64 |
| RAM/node | 256 GB | varies |
| Max job time | **48 hours** | **48 hours** |
| CUDA | 12.9.0 | N/A |
| cuDNN | 9.8.0 | N/A |

Shared NFS filesystem: home directories are visible from both login and compute nodes.

## Why a venv?

Farmshare's spack-built Python modules ship with a broken `ensurepip`, so `python3 -m venv` fails out of the box. The workaround:

1. Create venv with `--without-pip`
2. Bootstrap pip via `get-pip.py`
3. Everything works normally after that

The setup script handles this automatically.

## Setup (one-time, ~5 min)

```bash
ssh yoursunetid@rice.stanford.edu

git clone https://github.com/henliao/farmshare-jupyter.git ~/farmshare-jupyter
bash ~/farmshare-jupyter/setup.sh
```

This creates `~/jupyter-env` with Python 3.13, Jupyter Lab, PyTorch + CUDA, numpy, pandas, scikit-learn, matplotlib (~4.6 GB).

To install on scratch instead (saves home quota):
```bash
bash ~/farmshare-jupyter/setup.sh --scratch
```

## Usage

### Option A: One command from your laptop

```bash
./launch.sh yoursunetid
```

This does everything: submits the SLURM job, waits for it to start, opens an SSH tunnel, and opens Jupyter in your browser.

For CPU-only: `./launch.sh yoursunetid --cpu`

### Option B: Manual (from rice)

**1. SSH into rice and start the job:**

```bash
ssh yoursunetid@rice.stanford.edu
bash ~/farmshare-jupyter/start.sh
```

Output:
```
Job 12345 running on oat-03

Run this on your laptop:
  ssh -L 8542:oat-03:8542 yoursunetid@rice.stanford.edu

Then open:
  http://localhost:8542/lab?token=abc123...
```

For CPU-only: `bash ~/farmshare-jupyter/start.sh --cpu`

**2. Open the SSH tunnel** (second terminal on your laptop):

```bash
ssh -L 8542:oat-03:8542 yoursunetid@rice.stanford.edu
```

**3. Open the URL** in your browser.

## Submitting training jobs from Jupyter

You can train directly in the notebook (you already have a GPU allocated). For longer runs that should outlive your Jupyter session, submit a separate SLURM job from a cell:

```python
import subprocess

with open("train.sbatch", "w") as f:
    f.write("""#!/bin/bash
#SBATCH --job-name=train
#SBATCH --partition=gpu
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --time=2-00:00:00
#SBATCH --output=train-%j.log

module load python/3.13.11
module load cuda/12.9.0
module load cudnn/9.8.0.87-12
source ~/jupyter-env/bin/activate

python3 train.py
""")

result = subprocess.run(["sbatch", "train.sbatch"], capture_output=True, text=True)
print(result.stdout)
```

Monitor from a cell:
```python
!squeue -u $USER
!tail -20 train-12346.log
```

## Resource tuning

Edit `jupyter-gpu.sbatch` (or `jupyter-cpu.sbatch`):

```bash
#SBATCH --gres=gpu:1          # 1-4 GPUs
#SBATCH --cpus-per-task=4     # CPU cores
#SBATCH --mem=32G             # RAM
#SBATCH --time=2-00:00:00     # max 2 days
```

## Job management

```bash
squeue -u yoursunetid           # list your jobs
scancel JOBID                   # kill a specific job
scancel -u yoursunetid          # kill all your jobs
sinfo -p gpu                    # GPU node availability
cat jupyter-JOBID.log           # Jupyter log (has token URL)
```

## Adding packages

From rice or a Jupyter terminal:
```bash
source ~/jupyter-env/bin/activate
pip install somepackage
```

No Jupyter restart needed, just restart the notebook kernel.

## Troubleshooting

**Job stuck in PENDING.** All GPU nodes may be busy. Check `sinfo -p gpu`. Use `--cpu` for CPU-only, or request fewer resources.

**SSH tunnel dies.** Re-run the `ssh -L` command. Jupyter keeps running on the compute node.

**Token lost.** `grep token jupyter-JOBID.log` or `cat ~/jupyter-logs/jupyter_JOBID.info`

**Disk quota.** Venv is ~4.6 GB. Reinstall on scratch: `rm -rf ~/jupyter-env && bash setup.sh --scratch`

## Files

| File | Runs on | Purpose |
|------|---------|---------|
| `setup.sh` | rice | One-time: creates venv with Jupyter + PyTorch |
| `start.sh` | rice | Submits SLURM job, prints connection info |
| `launch.sh` | your laptop | All-in-one: submit + tunnel + open browser |
| `jupyter-gpu.sbatch` | compute node | SLURM script for GPU sessions |
| `jupyter-cpu.sbatch` | compute node | SLURM script for CPU-only sessions |
