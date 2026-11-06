library(cmap4r)
library(dplyr)

# Validate every cruise ID in cruises.txt against CMAP's cruise registry.
# This queries the registry directly, so it is far cheaper than running a
# one-variable colocalization test through Slurm.
#
# Run from the pipeline directory:
#   Rscript --no-save check-cruises.R

script_dir <- getwd()

set_authorization(
  cmap_key = Sys.getenv("CMAP_APIKEY")
) %>%
  suppressWarnings()

# ---------------------------------------------------------------
# Resolve the lookup function.
# get_cruise_by_name() shows up in cmap4r's internal call stack, but may
# not be exported, so fall back to ::: if it isn't.
# ---------------------------------------------------------------
lookup_fn <- if (exists("get_cruise_by_name", where = asNamespace("cmap4r"))) {
  get("get_cruise_by_name", envir = asNamespace("cmap4r"))
} else {
  stop("get_cruise_by_name() not found in cmap4r. Check the package version.")
}

# ---------------------------------------------------------------
# Read cruise IDs, applying the same cleaning the launcher does:
# strip comments, carriage returns, surrounding whitespace, blank lines.
# ---------------------------------------------------------------
raw <- readLines(file.path(script_dir, "cruises.txt"), warn = FALSE)
cruises <- raw %>%
  sub("#.*", "", .) %>%
  trimws() %>%
  .[. != ""]

cat("Checking", length(cruises), "cruise IDs\n\n")

# ---------------------------------------------------------------
# Check each one.
# "Invalid cruise name" arrives as a warning rather than an error, so
# catch both, and also treat an empty result as invalid.
# ---------------------------------------------------------------
check_one <- function(cruise) {
  result <- tryCatch(
    {
      res <- withCallingHandlers(
        lookup_fn(cruise),
        warning = function(w) {
          # Convert the "Invalid cruise name" warning into an error so
          # it lands in the error handler below
          if (grepl("Invalid cruise name", conditionMessage(w))) {
            stop("Invalid cruise name")
          }
          invokeRestart("muffleWarning")
        }
      )
      if (is.null(res) || (is.data.frame(res) && nrow(res) == 0)) {
        "INVALID (empty result)"
      } else {
        "OK"
      }
    },
    error = function(e) paste("INVALID:", conditionMessage(e))
  )
  result
}

status <- vapply(
  cruises,
  function(cr) {
    s <- check_one(cr)
    cat(sprintf("%-14s %s\n", cr, s))
    # Brief pause so 97 sequential requests don't hammer the API
    Sys.sleep(0.2)
    s
  },
  character(1)
)

# ---------------------------------------------------------------
# Summary
# ---------------------------------------------------------------
ok <- cruises[status == "OK"]
bad <- cruises[status != "OK"]

cat("\n----------------------------------------\n")
cat("Valid:  ", length(ok), "\n")
cat("Invalid:", length(bad), "\n")

if (length(bad) > 0) {
  cat("\nInvalid cruise IDs:\n")
  cat(paste0("  ", bad, collapse = "\n"), "\n")

  # Write them out so they're easy to comment out of cruises.txt
  writeLines(bad, file.path(script_dir, "invalid_cruises.txt"))
  cat("\nWritten to invalid_cruises.txt\n")
}
