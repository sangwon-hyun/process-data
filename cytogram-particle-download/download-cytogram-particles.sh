#!/bin/bash

# =========================================================
# Rsync Loop for Particle Level Cytogram Data
# =========================================================

# # Define the list of cruise identifiers to sync
# cruises=("TN412_130")

# Define the list of cruise identifiers to sync

cruises=("HOT302" "HOT330" "Thompson_12" "KM1906_towfish" "HOT319" "TN396_740"
"Thompson_0" "HOT308" "DeepDOM" "TN267" "HOT331" "GP15_1" "Tokyo_1" "SCOPE_9"
"HOT304" "HOT329" "Thompson_9" "SCOPE_17" "HOT317" "KM2206_740" "SCOPE_6"
"TN414" "HOT309" "KOK1805" "HOT312" "Thompson_4" "KM1923_751" "HOT335" "SCOPE_3"
"HOT299" "HOT332" "MGL1704" "SCOPE_11" "HOT324" "MBARI_3" "SCOPE_10" "HOT336"
"TN265" "SCOPE_5" "HOT300" "Tokyo_2" "SCOPE_18" "KOK1806" "MBARI_1" "Thompson_6"
"MBARI_2" "HOT326" "HOT-294" "HOT325" "TN413" "KM1713" "TN398" "Thompson_3"
"SCOPE_19" "SCOPE_1" "HOT337" "SCOPE_2" "KM1712" "HOT301" "HOT318" "HOT303"
"CMOP_3" "KM1906" "SCOPE_4" "TN412_130" "HOT315" "HOT323" "HOT338" "Thompson_11"
"HOT313" "SR1917" "SCOPE-PARAGONII" "SCOPE_Falkor2" "TN266" "KiloMoana_1"
"SCOPE-PARAGON" "Thompson_5" "Thompson_1" "SCOPE_13" "Thompson_10" "SCOPE_12"
"SCOPE_Falkor1" "KM1920" "KM1919" "KM1923_740" "HOT321" "HOT314" "HOT297"
"SCOPE_14" "HOT328" "HOT310" "HOT322" "HOT307" "MESO_SCOPE" "GP15_2" "SCOPE_15"
"TN397_740" "SCOPE_16")

# Define the local destination directory
LOCAL_DESTINATION="$HOME/Dropbox/data/ocean/raw-seaflow/particle-data-2026-9-22"

# Define the remote server connection details
REMOTE_USER="sangwonh"
REMOTE_HOST="thalassa.ocean.washington.edu"
REMOTE_PORT="3006"
SSH_KEY="~/.ssh/id_rsa"
REMOTE_BASE_PATH="/data/seaflow/seasnakemake-pipeline/seasnakemake/results"

# Start the loop
echo "Total cruises defined: ${#cruises[@]}"
echo "Starting rsync process for the following cruises: ${cruises[@]}"
echo "--------------------------------------------------------"

for cruise in "${cruises[@]}"; do

    # 1. DEFINE PATHS
    # Source: Must have a trailing slash to copy CONTENTS
    REMOTE_SOURCE="${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_BASE_PATH}/${cruise}/"

    # Destination: The full local path for this specific cruise folder
    LOCAL_CRUISE_DESTINATION="${LOCAL_DESTINATION}/${cruise}"

    echo "Syncing data for cruise: ${cruise}"
    echo "Source: ${REMOTE_SOURCE}"
    echo "Destination: ${LOCAL_CRUISE_DESTINATION}/"

    # 2. CREATE DIRECTORY
    # -p: Creates parent directories as needed
    echo "Creating destination directory if needed..."
    mkdir -p "${LOCAL_CRUISE_DESTINATION}"

    # 3. RSYNC EXECUTION
    # -a: Archive mode (recursive, links, permissions, times, group, owner)
    # -u: Update (skips files newer at destination)
    # -c: Checksum (FORCES download if files are different, use -I instead of -c for speed if you trust timestamps)
    # -v: Verbose
    rsync --progress -v -auc \
        -e "ssh -i ${SSH_KEY} -p ${REMOTE_PORT}" \
        "${REMOTE_SOURCE}" \
        "${LOCAL_CRUISE_DESTINATION}/" # Target must be the specific cruise folder

    echo "--------------------------------------------------------"
done
