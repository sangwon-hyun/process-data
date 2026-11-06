#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --nodes=1
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=4GB
#SBATCH --time=2:00:00
#SBATCH --partition=128x24
#SBATCH --mail-user=daapears@ucsc.edu
#SBATCH --mail-type=ALL
#SBATCH --output=./logs/launcher_%j.log
#SBATCH --error=./logs/launcher_%j.err
#SBATCH --job-name=cov_launcher

# TODO: Change this to your output of whereis R in Hummingbird
R_BIN=/mnt/beegfs/home/daapears/.conda/envs/r_env/bin/Rscript

# Hummingbird caps array indices at 10000 (MaxArraySize = 10001).
MAX_ARRAY=10000

# Variables colocalized per array task. Each variable averaged ~106 s in
# testing, so 50 per task averages ~1.5 h against the 5 h task limit.
# Packing keeps the total task count far below the cluster-wide
# MaxJobCount (40000), which is shared by ALL Hummingbird users.
CHUNK_SIZE=${chunk_size:-50}

mkdir -p logs


### --- Catalog: reuse the existing one unless told to refresh --- ###
# Every batch must use the SAME catalog. Batches are submitted on different
# days, and a re-scrape in between could change the variable set, so some
# cruises would be colocalized against variables others never saw.

if [ ! -f catalog.csv ] || [ "${refresh_catalog:-0}" -eq 1 ]; then
  ${R_BIN} --no-save catalog-scrape.R || { echo "catalog-scrape.R failed"; exit 1; }
else
  echo "Reusing existing catalog.csv (submit with refresh_catalog=1 to re-scrape)"
fi

if [ ! -f catalog.csv ]; then
  echo "catalog.csv not found"
  exit 1
fi

# Total catalog rows.
# (n_vars can be overridden in job submission command for testing)
N_VARS=${n_vars:-$(${R_BIN} --no-save -e 'cat(nrow(read.csv("catalog.csv")))')}

# Ceiling division: the number of tasks needed to cover N_VARS rows
N_TASKS=$(( (N_VARS + CHUNK_SIZE - 1) / CHUNK_SIZE ))

if [ "${N_TASKS}" -gt "${MAX_ARRAY}" ]; then
  echo "${N_TASKS} tasks exceeds the array limit; increase chunk_size"
  exit 1
fi

echo "Catalog has ${N_VARS} variables"
echo "${CHUNK_SIZE} variables per task, ${N_TASKS} tasks per cruise"


### --- Submit one colocalization array per cruise --- ###

# Read cruise IDs from a file, one per line. cruise_file can be set at
# submission time to run a batch (e.g. cruise_file=batch_00.txt).
CRUISE_FILE=${cruise_file:-cruises.txt}

if [ ! -f "${CRUISE_FILE}" ]; then
  echo "${CRUISE_FILE} not found"
  exit 1
fi

# tr strips carriage returns; sed trims whitespace; grep drops blank lines
mapfile -t CRUISES < <(tr -d '\r' < "${CRUISE_FILE}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$')
echo "Read ${#CRUISES[@]} cruises from ${CRUISE_FILE}"

for cruise in "${CRUISES[@]}"; do

  # Slurm opens the log file before the task runs, so this must exist
  # at submission time, not inside the array task.
  mkdir -p logs/${cruise}

  # \${SLURM_ARRAY_TASK_ID} is escaped so each task fills it in at run
  # time. CHUNK_SIZE and N_VARS are not escaped: they expand now.
  ARRAY_JOB_ID=$(sbatch --parsable \
    --array=1-${N_TASKS}%100 \
    --ntasks=1 --nodes=1 --cpus-per-task=1 --mem-per-cpu=4GB \
    --time=5:00:00 --partition=128x24 \
    --mail-user=daapears@ucsc.edu --mail-type=FAIL \
    --output=./logs/${cruise}/colocalize_%A_%a.log \
    --error=./logs/${cruise}/colocalize_%A_%a.err \
    --job-name=cov_coloc_${cruise} \
    --wrap="sleep \$(( \${SLURM_ARRAY_TASK_ID} % 60 )); ${R_BIN} --no-save covariate-scrape-process.R ${cruise} colocalize \${SLURM_ARRAY_TASK_ID} ${CHUNK_SIZE} ${N_VARS}")

  if [ -z "${ARRAY_JOB_ID}" ]; then
    echo "FAILED to submit array for ${cruise}, aborting"
    exit 1
  fi

  echo "Colocalization array submitted for ${cruise}: ${ARRAY_JOB_ID}"
done

echo "All arrays submitted. Run finalize manually once every batch has finished."