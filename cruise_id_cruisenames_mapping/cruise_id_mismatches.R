x_cruises_dir <- file.path("/home", "daapears", "Hyun_lab_NEW", "covariate_scraping", "data")

y_cruises <- c(
  "SCOPE_16", ## G1
  "MGL1704", ## G2
  "KM1906", ## G3
  "TN397_740", ## G4
  "TN412_130", ## G5
  "HOT302",
  "CMOP_3",
  "GP15_1",
  "HOT297",
  "HOT299",
  "HOT300",
  "HOT301",
  "HOT303",
  "HOT307",
  "HOT308",
  "HOT309",
  "HOT310",
  "HOT312",
  "HOT313",
  "HOT314",
  "HOT315",
  "HOT317",
  "HOT318",
  "HOT319",
  "HOT321",
  "HOT323",
  "HOT324",
  "HOT325",
  "HOT326",
  "HOT328",
  "HOT329",
  "HOT330",
  "HOT331",
  "HOT332",
  "HOT335",
  "HOT336",
  "HOT337",
  "HOT338",
  "HOT-294",
  "KM1712",
  "KM1906_towfish",
  "KM1919",
  "KM1923_751",
  "KOK1806",
  "MBARI_2",
  "SCOPE_1",
  "TN265",
  "TN266",
  "TN267",
  "TN396_740",
  "TN413",
  "TN414",
  "Thompson_0",
  "Thompson_1",
  "Thompson_3",
  "Thompson_4",
  "Thompson_5",
  "Thompson_6",
  "Thompson_9",
  "Thompson_10",
  "Thompson_11",
  "Thompson_12",
  "Tokyo_1",
  "Tokyo_2",
  "SCOPE_4",
  "SCOPE_5",
  "SCOPE_9",
  "SCOPE_10",
  "SCOPE_11",
  "SCOPE_12",
  "SCOPE_13",
  "SCOPE_14",
  "SCOPE_15",
  "SCOPE_17",
  "SCOPE_18",
  "SCOPE_19",
  "SCOPE-PARAGON",
  "SCOPE-PARAGONII",
  "DeepDOM",       
  "GP15_2",        
  "HOT304",        
  "HOT322",        
  "KiloMoana_1",   
  "KM1713",        
  "KM1920",        
  "KM1923_740",    
  "KM2206_740",    
  "KOK1805",       
  "MBARI_1",       
  "MBARI_3",       
  "MESO_SCOPE",    
  "SCOPE_2",       
  "TN398",         
  "SCOPE_3",       
  "SCOPE_6",       
  "SCOPE_Falkor1", 
  "SCOPE_Falkor2", 
  "SR1917"         
)

x_cruises <- list.files(x_cruises_dir, include.dirs = TRUE)

mapping <- read.csv(file.path("cruise_id_cruisenames_mapping", "cruise_id_mapping.csv"))

cruisenames <- mapping$cruise
cruise_ids <- mapping$cruise_id

names(cruisenames) <- cruise_ids
names(cruise_ids) <- cruisenames

# If cruise == CMOP_3, then cruise_id == "W1005A"
# If      y == CMOP_3, then         x == "W1005A"

x_cruisenames <- cruisenames[x_cruises]
x_cruises[is.na(x_cruisenames)] # TN264-265

x_cruisenames <- unname(x_cruisenames)

setdiff(x_cruisenames, y_cruises)
# [X] TN397_130 (we have y data for TN397_740)
# [X] TN412_740 (we have y data for TN412_130)

setdiff(y_cruises, x_cruisenames)
# [X] HOT335 (KM2204; not in CMAP)
# [X] HOT336 (KM2205; not in CMAP)
# [X] KM2206_740 (KM2206; not in CMAP)
# [X] HOT337 (KM2207; not in CMAP)
# [X] HOT338 (KM2208; not in CMAP)
# [X] TN396_740 (TN396; not in CMAP)
# [X] TN413 (TN413; not in CMAP)
# [X] TN414 (TN414; not in CMAP)
# [X] KM1906_towfish (KM1906-tf; not in CMAP)

# [X] TN397_740 (we have x data for TN397_130)
# [X] TN412_130 (we have x data for TN412_740)
# [X] KM1923_740 (we have x data for KM1923_751)

# [X] Thompson_6 (we have x data for TN264-265, which is the same)

# Explanations from Dane:

# TN264 matched two different CMAP entries, and along_track() (the colocalizer 
# function) picked the Puget Sound mooring deployment survey instead of the 
# Thompson_6 research cruise. I've replaced it with "TN264-265" in the list, 
# which resolves unambiguously to the Thompson cruise.

# TN265 is a separate CMAP entry but overlaps heavily with TN264-265. 
# Same ship, dates 2011-05-22 to 2011-06-24 vs 2011-05-28 to 2011-06-25. 
# I am not sure if those are two separate cruises or if they're duplicates- 
# I imagine we'd end up with two nearly identical covariate sets treated as 
# independent cruises.