#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --nodes=1
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=4GB
#SBATCH --time=2:00:00
#SBATCH --partition=128x24
#SBATCH --mail-user=YOUR_EMAIL_HERE
#SBATCH --mail-type=ALL
#SBATCH --output=./many-cruises-logs/%x_%A_%a.log
#SBATCH --error=./many-cruises-logs/%x_%A_%a.err 
#SBATCH --job-name=many-cruises-covs 
#SBATCH --array=1-1784%200

# TODO: change to your output of whereis R
R_BIN=/mnt/beegfs/home/daapears/.conda/envs/r_env/bin/Rscript

success_dir=successes 
fail_dir=failures

mkdir -p ${success_dir}
mkdir -p ${fail_dir}

${R_BIN} 00-covariates-v2-download.R ${cruise_id} ${SLURM_ARRAY_TASK_ID} && touch ${success_dir}/${SLURM_ARRAY_TASK_ID} || touch ${fail_dir}/${SLURM_ARRAY_TASK_ID}