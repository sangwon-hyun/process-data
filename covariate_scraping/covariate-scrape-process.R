library(tidyverse)
library(cmap4r)

# SETUP:
# ---------------------------------------------------
COVERAGE_THRESHOLD = 0

options(
  warnings = 1, # Don't hide any warnings
  nwarnings = 1000 # Print up to 1000 warnings
)

# Get user's command-line arguments
args <- commandArgs(trailingOnly = TRUE)
CRUISE_ID <- args[1] # cruise is first argument

# Get working directory (should be where this script lives)
script_dir <- getwd()

# Make data folder for RDS/CSV files
data_path <- file.path(script_dir, "data")
if (!dir.exists(data_path)) {
  dir.create(data_path)
}

# Make figures folder for any plots made
figures_path <- file.path(script_dir, "figures")
if (!dir.exists(figures_path)) {
  dir.create(figures_path)
}

# Define all global tables which will be used to colocalize
# (must have "global_tables_vars.csv" in same directory as this script)
target_tables_vars <- read.csv(file.path(script_dir, "catalog.csv"))

# API key access
set_authorization(
  cmap_key = YOUR_CMAP_API_KEY
) %>%
  suppressWarnings()

# Defining adaptive tolerances
temporalTolerances <- c(1 / 24, 1, 3.5, 14)
latLonTolerances <- c(0.1, 1, 2, 5)
depthTolerance <- 10
depth1 <- 0
depth2 <- 10


# COLOCALIZATION:
# ---------------------------------------------------

# Known table/variable combinations that hang indefinitely on the CMAP API.
# Add entries here as new hangs are identified.
KNOWN_HANGING_VARS <- c(
  "s_gp_clim_tblWOA_2018_qrtdeg_Climatology",
  "s_oa_clim_tblWOA_2018_qrtdeg_Climatology",
  "I_oa_clim_tblWOA_2018_qrtdeg_Climatology"
)

colocalize_func <- function(CRUISE_ID, i) {
  targetTable <- as.character(target_tables_vars[i, "Table_Name"])
  targetVar <- as.character(target_tables_vars[i, "Variable"])
  longVarName <- as.character(target_tables_vars[i, "Variable_Table_Name"])

  # Skip known problematic combinations before attempting along_track
  if (longVarName %in% KNOWN_HANGING_VARS) {
    cat("  Skipping known hanging variable:", longVarName, "\n")
    return(invisible(NULL))
  }

  # Skip if this variable was already colocalized in a previous run
  cruise_dir <- file.path(data_path, CRUISE_ID)
  existing_file <- file.path(cruise_dir, paste0(longVarName, ".csv"))
  if (file.exists(existing_file)) {
    cat("  Already colocalized, skipping:", longVarName, "\n")
    return(invisible(NULL))
  }

  cat(
    "Cruise:",
    CRUISE_ID,
    "| Table:",
    targetTable,
    "| Variable:",
    targetVar,
    "\n"
  )

  reslist <- list()

  tryCatch(
    {
      for (tol_idx in seq_along(temporalTolerances)) {
        cat("  Tolerance", tol_idx, "\n")

        df <- tryCatch(
          along_track(
            cruise = CRUISE_ID,
            targetTable = targetTable,
            targetVars = targetVar,
            depth1 = depth1,
            depth2 = depth2,
            temporalTolerance = temporalTolerances[tol_idx],
            latTolerance = latLonTolerances[tol_idx],
            lonTolerance = latLonTolerances[tol_idx],
            depthTolerance = depthTolerance
          ),
          error = function(e) {
            warning(paste(
              "along_track failed for",
              targetTable,
              targetVar,
              "tolerance",
              tol_idx
            ))
            warning(e)
            NULL
          }
        )

        if (is.null(df) || nrow(df) == 0) {
          cat("  No data returned. Skipping tolerance", tol_idx, "\n")
          next
        }

        # Rename to unique long variable names so columns don't clash at assembly
        names(df)[names(df) == targetVar] <- longVarName
        names(df)[names(df) == paste0(targetVar, "_std")] <- paste0(
          longVarName,
          "_std"
        )

        reslist[[tol_idx]] <- df

        if (mean(is.na(df[[longVarName]])) == 0) {
          cat("  No missing data. Ending early.\n")
          break
        }
      }
    },
    error = function(e) {
      warning(paste0(
        "Error in cruise ",
        CRUISE_ID,
        ", table ",
        targetTable,
        ", variable ",
        targetVar,
        "."
      ))
      warning(e)
    }
  )

  # Pick the last non-null tolerance result (loosest that was needed)
  valid <- Filter(is.data.frame, reslist)
  if (length(valid) == 0) {
    cat("  No valid results for", longVarName, "... Skipping save.\n")
    return(invisible(NULL))
  }
  best_df <- valid[[length(valid)]]

  # Save into data/<CRUISE_ID>/<longVarName>.csv
  cruise_dir <- file.path(data_path, CRUISE_ID)
  dir.create(cruise_dir, recursive = TRUE, showWarnings = FALSE)

  best_df$tol_idx_used <- which(!sapply(reslist, is.null)) %>% max()
  write.csv(
    best_df,
    file.path(cruise_dir, paste0(longVarName, ".csv")),
    row.names = FALSE
  )

  cat("  Saved:", longVarName, "\n")
}

# -----------------------------------------------------------------
# PLOTTING
# -----------------------------------------------------------------

# Shared helper: computes per-variable coverage across all cruises
# processed so far, and filters to variables passing COVERAGE_THRESHOLD
# in every cruise. Used by both make_heatmap() and make_line_plots().
get_filtered_vars <- function() {
  cruises <- list.dirs(data_path, full.names = FALSE, recursive = FALSE)
  cruises <- cruises[file.exists(file.path(data_path, cruises, "X.csv"))]

  freq_list <- lapply(cruises, function(cruise) {
    X <- read.csv(file.path(data_path, cruise, "X.csv"))

    X %>%
      select(-time, -lat, -lon) %>%
      pivot_longer(everything(), names_to = "variable", values_to = "value") %>%
      group_by(variable) %>%
      summarize(coverage = mean(!is.na(value))) %>%
      mutate(cruise = cruise)
  })

  freq_data <- bind_rows(freq_list) %>%
    complete(variable, cruise, fill = list(coverage = 0))

  freq_data_filtered <- freq_data %>%
    group_by(variable) %>%
    filter(all(coverage >= COVERAGE_THRESHOLD)) %>%
    ungroup()

  list(cruises = cruises, freq_data_filtered = freq_data_filtered)
}

# Heatmap: variables (x) x cruises (y), across all cruises processed so far.
# Run manually once all cruises of interest are assembled.
make_heatmap <- function() {
  result <- get_filtered_vars()
  cruises <- result$cruises
  freq_data_filtered <- result$freq_data_filtered

  unique_vars <- unique(freq_data_filtered$variable)
  chunk_size <- 40
  chunks <- split(
    unique_vars,
    ceiling(seq_len(length(unique_vars)) / chunk_size)
  )

  for (i in seq_along(chunks)) {
    chunk_data <- freq_data_filtered %>% filter(variable %in% chunks[[i]])

    p <- ggplot(chunk_data, aes(x = variable, y = cruise, fill = coverage)) +
      geom_tile(color = "lightgrey", linewidth = 0.2) +
      scale_fill_gradient(low = "white", high = "darkgreen", limits = c(0, 1)) +
      theme_minimal() +
      theme(
        axis.text.x = element_text(
          angle = 70,
          hjust = 1,
          size = 7,
          color = "black"
        )
      ) +
      labs(
        x = "Variable",
        y = "Cruise",
        fill = "Coverage",
        title = paste0(
          "Covariate Coverage: ",
          paste(cruises, collapse = ", "),
          " (",
          i,
          "/",
          length(chunks),
          ")"
        )
      )

    ggsave(
      file.path(
        figures_path,
        paste0("heatmap_coverage_", i, "of", length(chunks), ".png")
      ),
      p,
      width = 14,
      height = 6
    )
  }
}

# Line plots vs latitude, standardized to [-2, 2], for one cruise.
# Saved into figures/<CRUISE_ID>/. Runs automatically after assembly.
make_line_plots <- function(CRUISE_ID) {
  result <- get_filtered_vars()
  unique_vars <- unique(result$freq_data_filtered$variable)

  X <- read.csv(file.path(data_path, CRUISE_ID, "X.csv"))
  covariate_cols <- intersect(names(X), unique_vars)

  cruise_figures_path <- file.path(figures_path, CRUISE_ID)
  dir.create(cruise_figures_path, recursive = TRUE, showWarnings = FALSE)

  var_groups <- split(
    covariate_cols,
    ceiling(seq_along(covariate_cols) / 6)
  )

  for (i in seq_along(var_groups)) {
    current_vars <- var_groups[[i]]
    p <- X %>%
      select(time, lat, all_of(current_vars)) %>%
      pivot_longer(
        -c(time, lat),
        names_to = "variable",
        values_to = "value"
      ) %>%
      group_by(variable) %>%
      mutate(
        value = ((value - min(value, na.rm = TRUE)) /
          (max(value, na.rm = TRUE) - min(value, na.rm = TRUE))) *
          4 -
          2
      ) %>%
      ungroup() %>%
      ggplot(aes(x = lat, y = value)) +
      geom_point(size = 0.1, color = "red4") +
      geom_line(linewidth = 0.3, alpha = 0.8, color = "red4") +
      facet_wrap(
        ~variable,
        nrow = 3,
        ncol = 2
      ) +
      theme(
        axis.text.x = element_text(angle = 25, hjust = 1),
        strip.text = element_text(size = 16)
      ) +
      labs(
        title = paste0(
          CRUISE_ID,
          ": Variables ",
          (i - 1) * 6 + 1,
          " to ",
          min(i * 6, length(covariate_cols)),
          " vs Latitude"
        ),
        x = "Latitude",
        y = "Value",
      )

    ggsave(
      file.path(
        cruise_figures_path,
        paste0("Line_plot_lat_", i, "of", length(var_groups), ".png")
      ),
      p,
      width = 14,
      height = 6
    )
  }
}

# ASSEMBLY:
# ---------------------------------------------------
assemble_func <- function(CRUISE_ID) {
  # Define the cruise's folder directory
  cruise_dir <- file.path(data_path, CRUISE_ID)
  # Check if X.CSV was already made in this folder
  if (file.exists(file.path(cruise_dir, "X.csv"))) {
    cat("Already assembled X, skipping:", CRUISE_ID, "\n")
    return(invisible(NULL))
  }

  # List all CSV files
  all_files <- list.files(
    path = cruise_dir,
    pattern = "\\.csv$",
    full.names = TRUE
  )

  # Make sure the cruise folder actually has data to assemble
  if (length(all_files) == 0) {
    cat("No files found for cruise:", CRUISE_ID, "\n")
    return(invisible(NULL))
  }

  # Define files to exclude and filter them out
  to_exclude <- c("X.csv", "X_std.csv", "X_box_space.csv", "X_box_time.csv")
  all_files <- all_files[!basename(all_files) %in% to_exclude]

  # Load all CSV files in the cruise folder as dataframes
  all_results <- lapply(all_files, read.csv)

  # Extract tol_idx_used from each df, then drop the column before joining
  tol_indices <- sapply(all_results, function(df) df$tol_idx_used[1])
  all_results <- lapply(all_results, function(df) select(df, -tol_idx_used))

  # Join all the <variable>.csv files by their "time", "lon", "lat" columns
  fullres <- all_results %>%
    purrr::reduce(full_join, by = c("time", "lon", "lat"))

  # Separate mean and std columns
  std_cols <- names(fullres)[str_detect(names(fullres), "_std$")]
  mean_cols <- setdiff(names(fullres), std_cols)

  # Define X and X_std by selecting correct columns
  X <- fullres %>% select(all_of(mean_cols))
  X_std <- fullres %>% select(time, lat, lon, all_of(std_cols))

  # Prepare to build X_box_space and X_box_time
  lat_tols <- latLonTolerances[tol_indices]
  temp_tols <- temporalTolerances[tol_indices]
  varnames_used <- setdiff(mean_cols, c("time", "lat", "lon"))
  n_timepoints <- nrow(fullres)

  # Build X_box_space and X_box_time
  X_box_space <- matrix(
    rep(lat_tols, each = n_timepoints), # make the vectors to fill in each col
    nrow = n_timepoints, # T rows, one per cruise track time point
    ncol = length(varnames_used), # p columns, one per variable
    dimnames = list(NULL, varnames_used) # row names = NULL, col names = variable names
  )
  X_box_time <- matrix(
    rep(temp_tols * 24, each = n_timepoints),
    nrow = n_timepoints,
    ncol = length(varnames_used),
    dimnames = list(NULL, varnames_used)
  )

  # Make the cruise directory and save the csv files into it
  dir.create(cruise_dir, recursive = TRUE, showWarnings = FALSE)
  write.csv(X, file.path(cruise_dir, "X.csv"), row.names = FALSE)
  write.csv(X_std, file.path(cruise_dir, "X_std.csv"), row.names = FALSE)
  write.csv(
    X_box_space,
    file.path(cruise_dir, "X_box_space.csv"),
    row.names = FALSE
  )
  write.csv(
    X_box_time,
    file.path(cruise_dir, "X_box_time.csv"),
    row.names = FALSE
  )

  cat("Saved X, X_std, X_box_space, X_box_time for cruise:", CRUISE_ID, "\n")
  
  make_line_plots(CRUISE_ID)
}


# HANDLE MODES: Colocalization / Assembly of CSV files
# ---------------------------------------------------
# Determine if colocalization, assembly, or plotting mode from slurm script
mode <- args[2]

mode <- args[2]
if (mode == "colocalize") {
  i <- as.integer(args[3])
  colocalize_func(CRUISE_ID, i)
} else if (mode == "assemble") {
  assemble_func(CRUISE_ID)
} else if (mode == "lineplots") {
  make_line_plots(CRUISE_ID)
} else if (mode == "heatmap") {
  make_heatmap()
} else {
  stop(paste("Unknown mode: ", mode))
}