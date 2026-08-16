library(cmap4r)
library(dplyr)

options(
  warnings = 1, # Don't hide any warnings
  nwarnings = 1000 # Print up to 1000 warnings
)

# Get working directory (should be where this script lives)
script_dir <- getwd()

# Make "data" folder for RDS/CSV files
data_path <- file.path(script_dir, "data")
if (!dir.exists(data_path)) {
  dir.create(data_path)
}

# API key access
set_authorization(
  cmap_key = Sys.getenv("CMAP_APIKEY")
) %>%
  suppressWarnings()

# Download current view of the catalog
catalog <- get_catalog()
catalog <- catalog %>% 
  mutate(Variable_Table_Name = paste0(Variable, "_", Table_Name))

write.csv(catalog, file.path(data_path, "catalog.csv"), row.names = FALSE)
