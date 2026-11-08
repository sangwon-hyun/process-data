#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --nodes=1
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=4GB
#SBATCH --time=1:00:00
#SBATCH --partition=128x24
#SBATCH --mail-user=YOUR_EMAIL
#SBATCH --mail-type=ALL
#SBATCH --output=./logs/launcher_%j.log
#SBATCH --error=./logs/launcher_%j.err
#SBATCH --job-name=cov_launcher

# TODO: Change this to your output of whereis R
R_BIN=/mnt/beegfs/home/daapears/.conda/envs/r_env/bin/Rscript

mkdir -p logs successes failures

# Submit the colocalization array and capture its job ID.
# --parsable makes sbatch return just the numeric job ID.
ARRAY_JOB_ID=$(sbatch --parsable \
  --array=1-1784%200 \
  --ntasks=1 --nodes=1 --cpus-per-task=1 --mem-per-cpu=4GB \
  --time=2:00:00 --partition=128x24 \
  --mail-user=YOUR_EMAIL --mail-type=FAIL \
  --output=./logs/colocalize_%A_%a.log \
  --error=./logs/colocalize_%A_%a.err \
  --job-name=cov_colocalize \
  --wrap="${R_BIN} --no-save covariate-scrape-process.R ${cruise_id} colocalize \${SLURM_ARRAY_TASK_ID} \
    && touch successes/\${SLURM_ARRAY_TASK_ID} \
    || touch failures/\${SLURM_ARRAY_TASK_ID}")

echo "Colocalization array submitted: $ARRAY_JOB_ID"

# Submit the assembly job, held until every array task above succeeds.
# afterok:<id> means: start only if all tasks in the array exit with code 0.
sbatch \
  --dependency=afterok:${ARRAY_JOB_ID} \
  --ntasks=1 --nodes=1 --cpus-per-task=1 --mem-per-cpu=8GB \
  --time=0:30:00 --partition=128x24 \
  --mail-user=YOUR_EMAIL --mail-type=ALL \
  --output=./logs/assemble_%j.log \
  --error=./logs/assemble_%j.err \
  --job-name=cov_assemble \
  --wrap="${R_BIN} --no-save covariate-scrape-process.R ${cruise_id} assemble"

echo "Assembly job submitted with dependency on $ARRAY_JOB_ID"