# Running `covariate-scrape-process.R`
 
Colocalizes Simons CMAP environmental variables with one or more cruise tracks, assembles the results into analysis-ready matrices, and generates (and saves) diagnostic plots.

## Requirements

- R packages: `tidyverse`, `cmap4r`, `R.utils`, `data.table`
- A Simons CMAP API key, stored in `.Renviron` (copy `.Renviron.example`)
- Access to the UCSC Hummingbird HPC cluster (Slurm)

### Hummingbird setup
* Connect to `vpn.ucsc.edu` through Cisco Secure Client
* Activate hummingbird: `ssh <YOUR_CRUZ_ID>@hb.ucsc.edu`
* Load miniconda: `module load miniconda3/3.13`
* Create a virtual environment and then activate it: `conda activate <ENV_NAME>`

### Script configuration
1. Set `R_BIN` in `covariate-scrape-process.slurm` to your `whereis Rscript` output
2. Set `--mail-user` in `covariate-scrape-process.slurm` to your email
3. Copy .Renviron.example to .Renviron and fill in your CMAP API key

### Plot settings
Two settings at the top of `covariate-scrape-process.R` control which variables appear in the heatmap and line plots:

- `COVERAGE_THRESHOLD`: the coverage a variable needs in a cruise to count as present there. `0` means any data at all counts; `0.5` means more than 50% of the cruise's timepoints.
- `MIN_CRUISES`: the number of cruises a variable must be present in to appear in the plots. `1` keeps every variable that has data in any cruise.

## Running
List cruise IDs in `cruises.txt`, one per line, then:
```bash
sbatch --export=ALL covariate-scrape-process.slurm
```

To run a subset, put those IDs in another file and point to it:
```bash
sbatch --export=ALL,cruise_file=batch_00.txt covariate-scrape-process.slurm
```

Submitting all cruises at once can exceed the cluster's shared job limit; batches of ~10 cruises work well.

Optional settings, passed the same way: `chunk_size` (variables per task, default 50), `n_vars` (only the first N catalog rows, for testing), `refresh_catalog=1` (re-download the catalog).

To test on one cruise and just the first three catalog variables, put a single cruise ID in `smoke.txt` and run:
```bash
echo "KM1708" > smoke.txt
sbatch --export=ALL,cruise_file=smoke.txt,n_vars=3 covariate-scrape-process.slurm
```

## What it does

1. **Catalog** (in the launcher): the launcher reuses an existing `catalog.csv`,
   and runs `catalog-scrape.R` to download the current CMAP catalog only when
   `catalog.csv` is missing or `refresh_catalog=1` is set. Reusing it keeps every
   batch on the same variable list, so the array index to variable mapping stays
   fixed across all runs.

2. **Colocalization** (one Slurm array per cruise, 50 variables per task):
   queries CMAP via `along_track()` using adaptive space-time tolerance boxes.
   Each variable tries all 16 combinations of four temporal tolerances
   (1 hour, 1 day, 3.5 days, 14 days) and four spatial tolerances (0.1, 1, 2,
   5 degrees), tightest first, and stops at the first that gives full coverage.
   Each query has a 15-minute timeout, and values are averaged over 0 to 150 m
   depth. Results are saved as `data/<CRUISE_ID>/<variable>.csv`. Variables
   already present on disk are skipped, so reruns resume rather than restart.

3. **Finalize** (one job, run by hand once every batch has finished): assembles
   every cruise, then generates line plots for every cruise, then a cruise-count
   summary and the heatmap. The passes are separate because plot filtering
   depends on coverage across all cruises, so every cruise must be assembled
   before any plotting happens.

   Assembly produces the following (for each cruise):
   - `X.csv`: mean colocalized values (T x p)
   - `X_std.csv`: within-window standard deviations (T x p)
   - `X_box_space.csv`: lat/lon tolerance used per variable, in degrees
   - `X_box_time.csv`: temporal tolerance used per variable, in hours

   The heatmap sorts variables by how many cruises have them, most widely shared
   first, so the first images show the most broadly available variables. The
   per-cruise coverage table it uses is computed once and saved to
   `data/coverage_by_cruise.csv`; later runs load it in seconds. Delete it to
   recompute after cruises are added or rebuilt.

   **To run it:**
   ```bash
   R_BIN=/path/to/Rscript   # same path as in the .slurm file
   CRUISES=$(tr -d '\r' < cruises.txt | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$' | paste -sd,)

   sbatch --wrap="$R_BIN --no-save covariate-scrape-process.R '$CRUISES' finalize" \
     --ntasks=1 --mem-per-cpu=64GB --time=24:00:00 --partition=128x24 \
     --output=./logs/finalize_%j.log --error=./logs/finalize_%j.err
   ```

## Modes (run these to debug)

The launcher handles these automatically, but you can run these directly for debugging:

```
Rscript --no-save covariate-scrape-process.R <CRUISE_ID> colocalize <ROW_INDEX>
Rscript --no-save covariate-scrape-process.R <CRUISE_ID> assemble
Rscript --no-save covariate-scrape-process.R <CRUISE_ID> lineplots
Rscript --no-save covariate-scrape-process.R ALL heatmap
Rscript --no-save covariate-scrape-process.R "<ID1>,<ID2>" finalize
```

`heatmap` mode makes the cruise-count summary and heatmap only, with no line plots.

## Output structure

```
catalog.csv
data/
  coverage_by_cruise.csv
  <CRUISE_ID>/
    <variable>.csv
    X.csv
    X_std.csv
    X_box_space.csv
    X_box_time.csv
figures/
  heatmap_coverage_1of2.png
  variables_by_min_cruises.csv
  variables_by_min_cruises.png
  <CRUISE_ID>/
    Line_plot_lat_1of10.png
logs/
  launcher_<job_id>.log
  <CRUISE_ID>/
    colocalize_<array_id>_<task_id>.log
  finalize_<job_id>.log
```

## Known issues

- **Hanging queries:** Some CMAP queries hang rather than fail. Known ones are
  listed in `KNOWN_HANGING_VARS` and skipped; new ones show up in the logs as
  `TIMEOUT_SKIP:`.
- **Ambiguous cruise IDs:** A cruise ID can match more than one CMAP entry.
  `TN264` matched two cruises and resolved to the wrong one, so the list
  uses `TN264-265`. `check-cruises.R` validates `cruises.txt` against CMAP's cruise
  registry; nine IDs not found there are listed in `invalid_cruises.txt`.
- **TN398 is sampled per second:** It was averaged to per-minute with
  `downsample-tn398.R` and assembled as `TN398_1min`.
- **Empty or truncated files:** Colocalization tasks killed mid-write can leave
  empty or truncated per-variable files. Delete them before assembling
  (`find data/<CRUISE_ID> -name '*.csv' -empty` finds the empty ones).
- **Midnight timestamps:** `write.csv` writes midnight timestamps without the
  time (`2023-02-18`).
- **Large X.csv files:** They're unfiltered: about 9,800 columns, roughly 90% of
  which are entirely NA for any given cruise.