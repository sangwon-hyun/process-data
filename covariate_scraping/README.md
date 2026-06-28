## How to download covariates from Simons CMAP in slurm
### Using 00-covariates-v2-download

### Hummingbird setup:
* Connect to `vpn.ucsc.edu` through Cisco Secure Client
* Activate hummingbird: `ssh <YOUR_CRUZ_ID>@hb.ucsc.edu`
* Load miniconda: `module load miniconda3/3.13`
* Create a virtual environment and then activate it: `conda activate <ENV_NAME>`

### Then in your terminal, run:
Run `sbatch --export=cruise_id=<CRUISE_ID> 00-covariates-v2-download.slurm` with the CRUISE_ID you want to colocalize. 
You may submit many jobs consecutively by running this command with different cruise IDs.

To test it on one cruise and one variable, run `sbatch --export=cruise_id=<CRUISE_ID> --array=1 00-covariates-download.slurm`
