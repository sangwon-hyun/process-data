library(tidyverse)
library(cmap4r)

options(
  warnings = 1, # Don't hide any warnings
  nwarnings = 1000 # Print up to 1000 warnings
)

args <- commandArgs(trailingOnly = TRUE)
cruise <- args[1]

i <- as.integer(args[2]) # 1-1784

# Get the directory where this script lives
script_path <- tryCatch(
  normalizePath(sys.frames()[[1]]$ofile),
  error = function(e) NULL
)

script_dir <- if (!is.null(script_path)) {
  dirname(script_path)
} else {
  getwd()
}

# Set the directory for the colocalized data to live
results_path <- file.path(script_dir, "covariate-data-v2")
if (!dir.exists(results_path)) {
  dir.create(results_path)
}

# All global tables which will be used to colocalize
target_Tables_Vars <- read.csv(file.path(script_dir, "global_tables_vars.csv"))

# API key access
set_authorization(
  cmap_key = Sys.getenv("CMAP_API_KEY")
) %>%
  suppressWarnings()

# Defining adaptive tolerances
temporalTolerances <- c(1 / 24, 1, 3.5, 14) 
latLonTolerances <- c(0.1, 1, 2, 5)
depthTolerance <- 10
depth1 <- 0
depth2 <- 10

cat("Cruise", cruise, "\n\n")
reslist <- list()
tryCatch(
  {
    targetTable <- target_Tables_Vars[i, "Table_Name"] %>% as.character()
    targetVar <- target_Tables_Vars[i, "Variable"] %>% as.character()
    longVarName <- target_Tables_Vars[i, "Variable_Table_Name"] %>%
      as.character()

    cat("Table ", targetTable, ", Variable ", targetVar, "\n", sep = "")

    for (tol_idx in 1:length(temporalTolerances)) {
      cat("Tolerance", tol_idx, "\n")

      # Start colocalization
      df <- tryCatch(
        {
          along_track(
            cruise = cruise,
            targetTable = targetTable,
            targetVars = targetVar,
            depth1 = depth1,
            depth2 = depth2,
            temporalTolerance = temporalTolerances[tol_idx],
            latTolerance = latLonTolerances[tol_idx],
            lonTolerance = latLonTolerances[tol_idx],
            depthTolerance = depthTolerance
          )
        },
        error = function(e) {
          warning(
            paste(
              "along_track failed for",
              targetTable,
              targetVar,
              "tolerance",
              tol_idx
            )
          )
          warning(e)
          return(NULL)
        }
      )

      # Skip if no data returned
      if (is.null(df) || nrow(df) == 0) {
        cat("No data returned. Skipping tolerance", tol_idx, "\n")
        next
      }

      # Impose unique varnames
      names(df)[names(df) == targetVar] <- longVarName
      names(df)[names(df) == paste0(targetVar, "_std")] <- paste0(
        longVarName,
        "_std"
      )

      reslist[[tol_idx]] <- df

      # Check the missing proportion
      df_missing_prop <- mean(is.na(df[[longVarName]]))
      if (df_missing_prop == 0) {
        cat("No missing data! Ending early.", "\n")
        break
      }
    }
  },
  error = function(e) {
    warning_msg <- paste0(
      "Error in cruise ",
      cruise,
      ", table ",
      targetTable,
      ", variable",
      targetVar,
      ", tolerance",
      tol_idx,
      "."
    )
    warning(warning_msg)
    warning(e)
  }
)

# Create cruise-specific directory
cruise_dir <- file.path(results_path, cruise)
if (!dir.exists(cruise_dir)) {
  dir.create(cruise_dir, recursive = TRUE)
}

# Save RDS file inside cruise folder
fname <- paste0(longVarName, ".RDS")
fpath <- file.path(cruise_dir, fname)

# This will produce a folder for each cruise, named as the respective cruise.
# All of each cruise's respective RDS files will be saved into that folder.
saveRDS(reslist, fpath)
cat("Completed. Results written to", fpath, "\n")