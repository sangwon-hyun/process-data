# covariate-scrape-process
 
Colocalize Simons CMAP environmental variables with a cruise track, assemble the results into analysis-ready matrices, and generate (and save) diagnostic plots.

## Requirements
 
- R packages: `tidyverse`, `cmap4r`
- A Simons CMAP API key
- `global_tables_vars.csv` in the same directory as the script
- Access to the UCSC Hummingbird HPC cluster (Slurm)

## Setup
 
1. Replace `YOUR_CMAP_API_KEY` in `covariate-scrape-process.R` with your actual CMAP API key
2. Set `COVERAGE_THRESHOLD` at the top of the script (default: 0.5)
3. Ensure `global_tables_vars.csv` is in the same directory as the script

## Running
 
```
sbatch --export=cruise_id=<CRUISE_ID> covariate-scrape-process.slurm
```

Replace `<CRUISE_ID>` with the CMAP cruise identifier (e.g. `KOK1606`). This single command runs the full pipeline.

## Output structure
 
```
data/
  <CRUISE_ID>/
    <variable>.csv 
    X.csv
    X_std.csv
    X_box_space.csv
    X_box_time.csv
figures/
  heatmap_coverage_1of2.png
  ...
  Line_plot_lat_1of10.png
  ...
logs/
  launcher_<job_id>.log
  colocalize_<array_id>_<task_id>.log
  assemble_<job_id>.log
```
