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
chmod +x ~/farmshare-jupyter/*.sh
bash ~/farmshare-jupyter/setup.sh
```

This creates `~/jupyter-env` with Python 3.13, Jupyter Lab, PyTorch + CUDA, numpy, pandas, scikit-learn, matplotlib (~4.6 GB).

To install on scratch instead (optional, saves home quota):
```bash
bash ~/farmshare-jupyter/setup.sh --scratch
```

## Usage

### Option A: One command from your laptop

```bash
./launch.sh yoursunetid
```

This does everything: submits the SLURM job, waits for it to start, opens an SSH tunnel, and opens Jupyter in your browser. Output looks like:

```
[1/5] Uploading scripts to FarmShare...
[2/5] Submitting SLURM job...
  Job ID: 12345
[3/5] Waiting for job to start...
  PENDING (0s)
  PENDING (5s)
[4/5] Reading connection info...
  Node: oat-03, Port: 8542
[5/5] Opening SSH tunnel (localhost:8888 -> oat-03:8542)...

============================================
Jupyter is ready at:
  http://localhost:8888/lab?token=a1b2c3d4e5f6...
============================================
```

On macOS it auto-opens that URL in your browser. If not, copy/paste the full URL (including the token).

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

## Getting notebooks onto FarmShare

Your home directory (`/home/users/yoursunetid/`) is shared across all login and compute nodes. Any file you put there is accessible everywhere. A few ways to get notebooks there:

### Option 1: scp (copy files over SSH)

From your laptop terminal:

```bash
# Copy a single notebook
scp my_notebook.ipynb yoursunetid@rice.stanford.edu:~/

# Copy a whole folder
scp -r my_project/ yoursunetid@rice.stanford.edu:~/

# Copy it into a specific directory
scp my_notebook.ipynb yoursunetid@rice.stanford.edu:~/notebooks/
```

To download results back to your laptop:

```bash
# Copy output notebook back
scp yoursunetid@rice.stanford.edu:~/my_notebook_output.ipynb .

# Copy a whole folder back
scp -r yoursunetid@rice.stanford.edu:~/my_project/ .
```

### Option 2: git clone

From a rice login node (or a Jupyter terminal):

```bash
ssh yoursunetid@rice.stanford.edu
git clone https://github.com/youruser/yourrepo.git ~/yourrepo
```

If the repo is private, you'll need to set up a GitHub personal access token or SSH key on FarmShare.

### Option 3: Jupyter upload

Once you have a Jupyter session running (Option A or B above), use the Jupyter Lab file browser to drag and drop or click the upload button.

### Storage locations

| Path | Quota | Backed up | Use for |
|------|-------|-----------|---------|
| `~/` (home) | ~15-20 GB | Yes | Code, notebooks, small datasets |
| `/scratch/users/yoursunetid/` | Larger | No | Large datasets, temp files |
| `/farmshare/user_data/yoursunetid/` | Varies | No | Shared project data |

## Running a notebook as a batch job

Run an existing `.ipynb` headlessly on a GPU node, no browser needed. The notebook executes start-to-finish and saves results to a new output file.

From a rice login node:

```bash
bash ~/farmshare-jupyter/run-notebook.sh ~/my_notebook.ipynb
```

Output:
```
Submitting notebook: /home/users/yoursunetid/my_notebook.ipynb
Output will be saved to: /home/users/yoursunetid/my_notebook_output.ipynb

Job 12345 submitted.

Monitor:
  squeue -j 12345                                # job status
  tail -f ~/nb-my_notebook-12345.log             # live output

When done, your output notebook is:
  /home/users/yoursunetid/my_notebook_output.ipynb
```

The output notebook (`*_output.ipynb`) contains all cell outputs, including plots and print statements. If a cell fails, execution stops and the error is captured in the output.

Options:
```bash
bash run-notebook.sh notebook.ipynb --cpu          # CPU-only (no GPU)
bash run-notebook.sh notebook.ipynb --timeout 7200 # 2-hour timeout per cell (default: 1 hour)
```

Download the output to view locally:
```bash
scp yoursunetid@rice.stanford.edu:~/my_notebook_output.ipynb .
```

## Submitting training jobs from Jupyter (optional)

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

## Resource tuning (optional)

Pass resource flags when submitting. The defaults are:

| Flag | GPU default | CPU default |
|------|-------------|-------------|
| `--gres` | `gpu:1` | (none) |
| `--mem` | `32G` | `16G` |
| `--cpus-per-task` | `4` | `4` |
| `--time` | `2-00:00:00` | `2-00:00:00` |

To request more GPUs or memory, edit `jupyter.sbatch` or pass flags directly:
```bash
sbatch --partition=gpu --gres=gpu:2 --mem=64G ~/farmshare-jupyter/jupyter.sbatch
```

## Job management

```bash
squeue -u yoursunetid           # list your jobs
scancel JOBID                   # kill a specific job
scancel -u yoursunetid          # kill all your jobs
sinfo -p gpu                    # GPU node availability
cat jupyter-JOBID.log           # Jupyter log (has token URL)
```

## Adding packages (optional)

From rice, a Jupyter terminal, or a notebook cell:
```bash
source ~/jupyter-env/bin/activate
pip install somepackage
```

From a notebook cell:
```python
%pip install somepackage
```

No Jupyter restart needed, just restart the notebook kernel.

## Troubleshooting

**Job stuck in PENDING.** All 6 GPU nodes may be occupied. The script waits up to 5 minutes, then shows current GPU availability and your options:
- Keep waiting: your job stays in the queue and will start when a node frees up. Re-run the script to resume.
- Switch to CPU: `./launch.sh yoursunetid --cpu` (or `bash start.sh --cpu`). More nodes available, rarely queued.
- Request fewer resources: lower GPU/memory requirements.
- Check availability: `sinfo -p gpu` shows which nodes are allocated/idle.

**SSH tunnel dies.** Re-run the `ssh -L` command. Jupyter keeps running on the compute node.

**Token lost.** Find your job ID with `squeue -u yoursunetid`, then:
```bash
cat ~/jupyter-logs/jupyter_JOBID.info
```

**Disk quota.** Venv is ~4.6 GB. Reinstall on scratch: `rm -rf ~/jupyter-env && bash setup.sh --scratch`

## Files

| File | Runs on | Purpose |
|------|---------|---------|
| `setup.sh` | rice | One-time: creates venv with Jupyter + PyTorch |
| `start.sh` | rice | Submits SLURM job, prints connection info |
| `launch.sh` | your laptop | All-in-one: submit + tunnel + open browser |
| `run-notebook.sh` | rice | Run a .ipynb headlessly as a SLURM batch job |
| `jupyter.sbatch` | compute node | SLURM script (handles both GPU and CPU) |
| `example.ipynb` | compute node | GPU smoke test notebook |
