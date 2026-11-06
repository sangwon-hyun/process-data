library(tidyverse)
library(cmap4r)

# SETUP:
# ---------------------------------------------------
# A cruise counts as "having" a variable if the variable's coverage in
# that cruise is above COVERAGE_THRESHOLD. With 0, any data at all counts
COVERAGE_THRESHOLD <- 0

# Keep only variables present in at least this many cruises (heatmap and ine plots)
# 1 = keep every variable that has data in at least one cruise
MIN_CRUISES <- 1

options(
  warn = 1, # Print each warning immediately, as it happens
  nwarnings = 1000 # Print up to 1000 warnings
)

# Get user's command-line arguments
args <- commandArgs(trailingOnly = TRUE)
CRUISE_ID <- args[1] # cruise is first argument

# Get working directory (should be where this script lives)
script_dir <- getwd()

# Make data folder for the per-cruise CSV files
data_path <- file.path(script_dir, "data")
if (!dir.exists(data_path)) {
  dir.create(data_path)
}

# Make figures folder for any plots made
# Make figures folder for any plots made
figures_path <- file.path(script_dir, "figures")
if (!dir.exists(figures_path)) {
  dir.create(figures_path)
}

# Per-variable, per-cruise coverage table. Computed once from all X.csv
# files and reused by later plotting runs; delete it to force a recompute
coverage_file <- file.path(data_path, "coverage_by_cruise.csv")

# API key access
set_authorization(
  cmap_key = Sys.getenv("CMAP_APIKEY")
) %>%
  suppressWarnings()

# Define all global tables which will be used to colocalize
# (catalog.csv is refreshed once by catalog-scrape.R in the launcher)
target_tables_vars <- read.csv(file.path(script_dir, "catalog.csv"))


# Defining adaptive tolerances
temporalTolerances <- c(1 / 24, 1, 3.5, 14) # days
latLonTolerances <- c(0.1, 1, 2, 5) # degrees

# Every combination of the two, tightest first. expand.grid varies its FIRST
# column fastest, so this tries all spatial tolerances at the tightest
# temporal tolerance before loosening time. Swap the argument order to
# loosen time first instead.
tol_grid <- expand.grid(
  spatial = latLonTolerances,
  temporal = temporalTolerances
)

depthTolerance <- 10
depth1 <- 0
depth2 <- 150


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
      for (tol_idx in seq_len(nrow(tol_grid))) {
        temporal_tol <- tol_grid$temporal[tol_idx]
        spatial_tol <- tol_grid$spatial[tol_idx]
        cat(
          "  Tolerance",
          tol_idx,
          "of",
          nrow(tol_grid),
          ":",
          temporal_tol,
          "days,",
          spatial_tol,
          "deg\n"
        )

        df <- tryCatch(
          R.utils::withTimeout(
            along_track(
              cruise = CRUISE_ID,
              targetTable = targetTable,
              targetVars = targetVar,
              depth1 = depth1,
              depth2 = depth2,
              temporalTolerance = temporal_tol,
              latTolerance = spatial_tol,
              lonTolerance = spatial_tol,
              depthTolerance = depthTolerance
            ),
            timeout = 900, # 15 minutes
            onTimeout = "error"
          ),
          # Must come before the generic error handler: TimeoutException
          # inherits from error, and tryCatch takes the first match.
          TimeoutException = function(e) {
            cat(
              "  TIMEOUT_SKIP:",
              CRUISE_ID,
              longVarName,
              "tolerance",
              tol_idx,
              "\n"
            )
            NULL
          },
          error = function(e) {
            warning(paste(
              "along_track failed for",
              targetTable,
              targetVar,
              "tolerance",
              tol_idx,
              ":",
              conditionMessage(e)
            ))
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
        ": ",
        conditionMessage(e)
      ))
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

  # Record the actual tolerance values used rather than an index, so
  # assembly doesn't depend on the grid's ordering
  best_idx <- which(!sapply(reslist, is.null)) %>% max()
  best_df$temporal_tol_used <- tol_grid$temporal[best_idx]
  best_df$spatial_tol_used <- tol_grid$spatial[best_idx]
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

# Cruises that currently have an assembled X.csv
assembled_cruises <- function() {
  cruises <- list.dirs(data_path, full.names = FALSE, recursive = FALSE)
  cruises[file.exists(file.path(data_path, cruises, "X.csv"))]
}

# Reads every assembled X.csv, one cruise at a time, and records the
# percentage of non-NA rows for each variable. Saves the result so later
# runs can skip this slow step.
compute_coverage <- function() {
  cruises <- assembled_cruises()
  if (length(cruises) == 0) {
    stop("No cruises with an assembled X.csv found in ", data_path)
  }

  # Identify which covariates are available in each cruise's dataset
  # Each row = covariate, cruise id, coverage percentage
  cov_list <- vector("list", length(cruises))
  for (i in seq_along(cruises)) {
    cat("Coverage for", cruises[i], "(", i, "of", length(cruises), ")\n")
    X <- data.table::fread(file.path(data_path, cruises[i], "X.csv"))
    var_names <- setdiff(names(X), c("time", "lat", "lon"))

    # Fraction of non-NA rows, computed one column at a time
    coverage <- vapply(
      var_names,
      function(v) mean(!is.na(X[[v]])),
      numeric(1)
    )

    cov_list[[i]] <- tibble(
      variable = var_names,
      cruise = cruises[i],
      coverage = unname(coverage)
    )

    # Free the large table before reading the next cruise
    rm(X)
    gc()
  }

  # Combine the coverage tables from all the cruises into one coverage dataset with
  # the same structure (covariate, cruise id, coverage percentage).
  # A variable missing from a cruise's X.csv gets coverage 0 there
  coverage_data <- bind_rows(cov_list) %>%
    complete(variable, cruise, fill = list(coverage = 0))

  write.csv(coverage_data, coverage_file, row.names = FALSE)
  cat("Saved coverage table:", coverage_file, "\n")
  coverage_data
}

# Load the saved coverage table if one exists; otherwise computes it
# If the set of assembled cruises has changed since it was saved, warns
# and suggests recomputing, but still uses the saved table.
load_coverage <- function() {
  if (!file.exists(coverage_file)) {
    cat("No saved coverage table found; computing it from X.csv files.\n")
    return(compute_coverage())
  }

  coverage_data <- read.csv(coverage_file)
  cat("Loaded saved coverage table:", coverage_file, "\n")

  saved <- unique(coverage_data$cruise)
  current <- assembled_cruises()
  added <- setdiff(current, saved)
  removed <- setdiff(saved, current)

  if (length(added) > 0 || length(removed) > 0) {
    cat("WARNING: the saved coverage table may be stale.\n")
    if (length(added) > 0) {
      cat(
        "  Assembled since it was saved:",
        paste(added, collapse = ", "),
        "\n"
      )
    }
    if (length(removed) > 0) {
      cat(
        "  In the table but no longer assembled:",
        paste(removed, collapse = ", "),
        "\n"
      )
    }
    cat("  To recompute, delete", coverage_file, "and rerun.\n")
  }

  coverage_data
}

# Variables present (coverage above COVERAGE_THRESHOLD) in at least
# MIN_CRUISES cruises, sorted from most widely shared to least
get_filtered_vars <- function() {
  coverage_data <- load_coverage()

  # Filter coverage_data table to only vars above the COVERAGE_THRESHOLD in at least MIN_CRUISES cruises
  # Then sort by the number of cruises they variables are in (most to least)
  var_counts <- coverage_data %>%
    group_by(variable) %>%
    summarize(
      n_cruises = sum(coverage > COVERAGE_THRESHOLD),
      mean_coverage = mean(coverage),
      .groups = "drop"
    ) %>%
    filter(n_cruises >= MIN_CRUISES) %>%
    # Most widely shared first; ties broken by higher average coverage
    arrange(desc(n_cruises), desc(mean_coverage))

  # Define the data to be plotted in the heatmap (only vars that pass)
  freq_data_filtered <- coverage_data %>%
    filter(variable %in% var_counts$variable)

  cat(
    "Variables present in at least",
    MIN_CRUISES,
    "cruise(s):",
    nrow(var_counts),
    "\n"
  )

  list(
    cruises = sort(unique(coverage_data$cruise)),
    freq_data_filtered = freq_data_filtered,
    var_counts = var_counts,
    coverage_data = coverage_data
  )
}

# How many variables are present in at least k cruises, for k=1 to the
# number of cruises. Save a table and a line plot to inform
# MIN_CRUISES. Uses all variables, regardless of MIN_CRUISES
make_cruise_count_summary <- function(filtered) {
  # Table of how many cruises each covariate is in
  per_var <- filtered$coverage_data %>%
    group_by(variable) %>%
    summarize(
      n_cruises = sum(coverage > COVERAGE_THRESHOLD),
      .groups = "drop"
    )

  # How many crusies
  n_total <- length(filtered$cruises)
  # How many total variables will I have left to work with at each MIN_CRUISES level?
  summary_tbl <- tibble(min_cruises = seq_len(n_total)) %>%
    mutate(
      n_variables = vapply(
        min_cruises,
        function(k) sum(per_var$n_cruises >= k),
        integer(1)
      )
    )

  write.csv(
    summary_tbl,
    file.path(figures_path, "variables_by_min_cruises.csv"),
    row.names = FALSE
  )

  p <- ggplot(summary_tbl, aes(x = min_cruises, y = n_variables)) +
    geom_line() +
    geom_point(size = 0.8) +
    theme_minimal() +
    labs(
      x = "Minimum number of cruises with data",
      y = "Number of variables",
      title = paste0("Variables present in at least k of ", n_total, " cruises")
    )

  ggsave(
    file.path(figures_path, "variables_by_min_cruises.png"),
    p,
    width = 8,
    height = 5
  )

  cat("Saved variables_by_min_cruises.csv and .png to", figures_path, "\n")
}

# Heatmap: variables (x) vs. cruises (y). Variables are sorted from most
# widely shared to least, so early images show the most useful variables
make_heatmap <- function(filtered = NULL) {
  if (is.null(filtered)) {
    filtered <- get_filtered_vars()
  }
  cruises <- filtered$cruises
  freq_data_filtered <- filtered$freq_data_filtered
  var_counts <- filtered$var_counts

  # var_counts is already sorted most-shared first
  sorted_vars <- var_counts$variable
  chunk_size <- 40
  chunks <- split(
    sorted_vars,
    ceiling(seq_along(sorted_vars) / chunk_size)
  )

  for (i in seq_along(chunks)) {
    chunk_vars <- chunks[[i]]

    chunk_data <- freq_data_filtered %>%
      filter(variable %in% chunk_vars) %>%
      # Keep the sorted order on the x-axis instead of alphabetical
      mutate(variable = factor(variable, levels = chunk_vars))

    # Range of cruise counts in this chunk, for the title
    chunk_counts <- var_counts$n_cruises[var_counts$variable %in% chunk_vars]

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
          "Covariate coverage across ",
          length(cruises),
          " cruises (",
          i,
          "/",
          length(chunks),
          "): variables present in ",
          max(chunk_counts),
          " to ",
          min(chunk_counts),
          " cruises"
        )
      )

    ggsave(
      file.path(
        figures_path,
        paste0("heatmap_coverage_", i, "of", length(chunks), ".png")
      ),
      p,
      width = 14,
      height = max(6, 0.15 * length(cruises))
    )
  }
}


# Line plots vs latitude, standardized to [-2, 2], for one cruise.
# Saved into figures/<CRUISE_ID>/. Runs automatically after assembly.
make_line_plots <- function(CRUISE_ID, filtered = NULL) {
  X_path <- file.path(data_path, CRUISE_ID, "X.csv")
  if (!file.exists(X_path)) {
    cat("No X.csv, skipping line plots for:", CRUISE_ID, "\n")
    return(invisible(NULL))
  }

  if (is.null(filtered)) {
    filtered <- get_filtered_vars()
  }
  unique_vars <- unique(filtered$freq_data_filtered$variable)

  X <- read.csv(X_path)
  covariate_cols <- intersect(names(X), unique_vars)

  # Drop variables that are entirely NA for this cruise, since those
  # render as blank. Variables with partial gaps are kept.
  has_data <- vapply(
    covariate_cols,
    function(v) any(!is.na(X[[v]])),
    logical(1)
  )
  covariate_cols <- covariate_cols[has_data]

  if (length(covariate_cols) == 0) {
    cat("No non-empty variables, skipping line plots for:", CRUISE_ID, "\n")
    return(invisible(NULL))
  }

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
        # A constant variable would divide by zero here, so draw it
        # flat at the midpoint instead of producing NaN.
        value = if (max(value, na.rm = TRUE) == min(value, na.rm = TRUE)) {
          0
        } else {
          ((value - min(value, na.rm = TRUE)) /
            (max(value, na.rm = TRUE) - min(value, na.rm = TRUE))) *
            4 -
            2
        }
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

  # Read all per-variable files
  all_results <- lapply(all_files, read.csv)

  # Extract the tolerances used, then drop those columns before combining
  spatial_tols <- sapply(all_results, function(df) df$spatial_tol_used[1])
  temporal_tols <- sapply(all_results, function(df) df$temporal_tol_used[1])
  all_results <- lapply(all_results, function(df) {
    select(df, -spatial_tol_used, -temporal_tol_used)
  })

  # Fast path: every file for a cruise is colocalized against the SAME
  # track, so they should share identical time/lat/lon rows. If they do,
  # we can bind columns by position instead of a ~9,800-way full_join,
  # which is far cheaper in memory and time. We verify alignment first
  # and fall back to the join if anything is off.
  ref_keys <- all_results[[1]][, c("time", "lat", "lon")]
  aligned <- all(vapply(
    all_results,
    function(df) {
      nrow(df) == nrow(ref_keys) && identical(df$time, ref_keys$time)
    },
    logical(1)
  ))

  if (aligned) {
    # Drop the key columns from every file except the first, then bind
    value_cols <- lapply(all_results, function(df) {
      df %>% select(-time, -lat, -lon)
    })
    fullres <- bind_cols(ref_keys, value_cols)
  } else {
    cat("  Files not aligned for", CRUISE_ID, "- falling back to full_join\n")
    fullres <- all_results %>%
      purrr::reduce(full_join, by = c("time", "lon", "lat"))
  }

  # Separate mean and std columns
  std_cols <- names(fullres)[str_detect(names(fullres), "_std$")]
  mean_cols <- setdiff(names(fullres), std_cols)

  # Define X and X_std by selecting correct columns
  X <- fullres %>% select(all_of(mean_cols))
  X_std <- fullres %>% select(time, lat, lon, all_of(std_cols))

  # Prepare to build X_box_space and X_box_time
  lat_tols <- spatial_tols
  temp_tols <- temporal_tols
  varnames_used <- setdiff(mean_cols, c("time", "lat", "lon"))
  n_timepoints <- nrow(fullres)

  # The tolerance vectors are in file order; varnames_used must be too,
  # one entry per file. If they don't match, the box matrices would be
  # mislabeled, so stop rather than write wrong data.
  if (length(varnames_used) != length(lat_tols)) {
    stop(sprintf(
      "Tolerance/variable count mismatch for %s: %d variables but %d tolerance entries. A file likely has an unexpected column layout.",
      CRUISE_ID,
      length(varnames_used),
      length(lat_tols)
    ))
  }

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
}


# HANDLE MODES
# ---------------------------------------------------
# args[1] is a single cruise ID for most modes, or a comma-separated
# list of cruise IDs for "finalize"

mode <- args[2]
if (mode == "colocalize") {
  # args[3]: array task ID. args[4]: variables per task (default 1).
  # args[5]: total catalog rows to cover (default: all of them).
  # With the defaults, "colocalize 5" runs just catalog row 5, so manual
  # debugging and any already-queued single-variable tasks keep working.
  task_id <- as.integer(args[3])
  chunk_size <- if (length(args) >= 4) as.integer(args[4]) else 1
  n_vars <- if (length(args) >= 5) {
    as.integer(args[5])
  } else {
    nrow(target_tables_vars)
  }

  first_row <- (task_id - 1) * chunk_size + 1
  last_row <- min(task_id * chunk_size, n_vars)

  # Guard: in R, 5:3 counts DOWN (5, 4, 3) instead of being empty
  rows <- if (first_row <= last_row) first_row:last_row else integer(0)

  for (i in rows) {
    # One bad variable must not abort the rest of the chunk
    tryCatch(
      colocalize_func(CRUISE_ID, i),
      error = function(e) {
        cat("VARIABLE_FAILED:", CRUISE_ID, "row", i, conditionMessage(e), "\n")
      }
    )
  }
} else if (mode == "assemble") {
  assemble_func(CRUISE_ID)
} else if (mode == "lineplots") {
  make_line_plots(CRUISE_ID)
} else if (mode == "heatmap") {
  filtered <- get_filtered_vars()
  make_cruise_count_summary(filtered)
  make_heatmap(filtered)
} else if (mode == "finalize") {
  # Split "cruise1, cruise2, cruise3" into c("cruise1", "cruise2", "cruise3")
  # trimws() to get rid of extra spaces in the list
  cruises <- strsplit(CRUISE_ID, ",")[[1]] %>% trimws()

  # Pass 1: assemble every cruise, so that data/ is in its final state before any filtering happens
  for (cruise in cruises) {
    tryCatch(
      assemble_func(cruise),
      error = function(e) {
        cat("ASSEMBLE_FAILED:", cruise, conditionMessage(e), "\n")
      }
    )
  }

  # Pass 2: line plots, now that get_filtered_vars() sees all cruises
  filtered <- get_filtered_vars()
  for (cruise in cruises) {
    tryCatch(
      make_line_plots(cruise, filtered),
      error = function(e) {
        cat("LINEPLOTS_FAILED:", cruise, conditionMessage(e), "\n")
      }
    )
  }

  # Pass 3: cruise-count summary and heatmap across everything in data/
  make_cruise_count_summary(filtered)
  make_heatmap(filtered)
} else {
  stop(paste("Unknown mode: ", mode))
}
