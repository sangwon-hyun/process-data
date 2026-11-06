library(data.table)

src <- "data/TN398"
dst <- "data/TN398_1min"
dir.create(dst, showWarnings = FALSE)

# Only the per-variable files, not any assembled outputs
skip <- c("X.csv", "X_std.csv", "X_box_space.csv", "X_box_time.csv")
files <- list.files(src, pattern = "\\.csv$", full.names = TRUE)
files <- files[!basename(files) %in% skip]
cat("Downsampling", length(files), "files\n")

# Average that returns NA (not NaN) when every value in the minute is missing
safe_mean <- function(x) {
  m <- mean(x, na.rm = TRUE)
  if (is.nan(m)) NA_real_ else m
}

for (f in files) {
  out <- file.path(dst, basename(f))
  if (file.exists(out)) {
    next
  } # resume-safe: skip files already done

  # Read time as text so we control the parsing
  var_table <- fread(f, colClasses = c(time = "character"))

  # Skip empty or malformed files (e.g. from a colocalization task killed
  # mid-write) instead of stopping the whole run
  if (nrow(var_table) == 0 || !all(c("time", "lat", "lon") %in% names(var_table))) {
    cat("Skipping empty/malformed file:", basename(f), "\n")
    next
  }

  # write.csv drops "00:00:00" at exact midnight, so add it back in so the minute key is consistent for all rows
  t <- var_table$time
  midnight <- nchar(t) == 10
  t[midnight] <- paste(t[midnight], "00:00:00")

  # Add a new "minute" col to var_table
  # Keep the first 16 characters but exclude the second chars
  var_table[, minute := substr(t, 1, 16)]

  variable_cols <- setdiff(
    names(var_table),
    c("time", "lat", "lon", "minute", "temporal_tol_used", "spatial_tol_used")
  )

  # Make a downsampled table which gets the mean of the variable cols, and the lat/lon cols for each unique minute timestamp
  agg <- var_table[,
    c(
      list(lat = mean(lat), lon = mean(lon)),
      lapply(.SD, safe_mean)
    ),
    by = minute,
    .SDcols = variable_cols
  ]

  # Rebuild a full timestamp, restore the tolerance columns, and sort
  # so every file lines up row-for-row at assembly
  agg[, time := paste0(minute, ":00")]
  agg[, minute := NULL]
  agg[, temporal_tol_used := var_table$temporal_tol_used[1]]
  agg[, spatial_tol_used := var_table$spatial_tol_used[1]]
  setcolorder(agg, c("time", "lat", "lon"))
  setorder(agg, time)

  fwrite(agg, out)
}

cat("Done.\n")
