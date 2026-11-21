# =============================================================================
# setup.R — Project setup: packages, parameters and paths
# -----------------------------------------------------------------------------
# Project : Media framing of Jair Bolsonaro's Supreme Court trial
#           (Brazil, 1–12 September 2025)

# -----------------------------------------------------------------------------
# 1. Packages
# -----------------------------------------------------------------------------

PACKAGES_ANALYSIS <- c("readxl", "dplyr", "tibble", "stringr",
                   "tidyr", "tidytext", "ggplot2")

PACKAGES_SCRAPING <- c("chromote", "rvest", "xml2", "httr", "stringr", "stringi",
                   "dplyr", "purrr", "tibble", "lubridate", "jsonlite",
                   "glue", "openxlsx")


load_packages <- function(packages) {
  missing <- packages[!packages %in% rownames(installed.packages())]
  if (length(missing) > 0) {
    stop("Missing packages. Install them with:\n  install.packages(c(",
         paste0('"', missing, '"', collapse = ", "), "))", call. = FALSE)
  }
  for (p in packages) library(p, character.only = TRUE)
}

load_packages(PACKAGES_ANALYSIS)


# -----------------------------------------------------------------------------
# 2. Shared parameters
# -----------------------------------------------------------------------------

# Study period: September 1–12, 2025.
# Covers the days preceding Bolsonaro's trial sessions
# before the Brazilian Supreme Federal Court (STF)
# and the date of the final ruling.

STUDY_START <- as.Date("2025-09-01") 
STUDY_END   <- as.Date("2025-09-12")

SEED                   <- 42  # random seed for the stratified sample
SAMPLE_SIZE_PER_OUTLET <- 75  # 5 outlets x 75 = 375 articles
# Since Agência Brasil had the fewest eligible articles (75), the same number
# was selected from each outlet to ensure comparability.

# -----------------------------------------------------------------------------
# 3. Paths
# -----------------------------------------------------------------------------

DIR_RAW          <- "data/raw"
DIR_PROCESSED    <- "data/processed"
DIR_DICTIONARIES <- "data/dictionaries"
DIR_FIGURES      <- "outputs/figures"
DIR_TABLES       <- "outputs/tables"

RAW_CORPUS_FILE <- file.path(DIR_RAW, "news_corpus_2025-09-01_2025-09-12.xlsx")
DICTIONARY_FILE <- file.path(DIR_DICTIONARIES, "framing_dictionary.csv")

if (!file.exists(DICTIONARY_FILE)) {
  stop("Framing dictionary not found in data/dictionaries.")
}

# Create required directories
for (d in c(DIR_RAW, DIR_PROCESSED, DIR_FIGURES, DIR_TABLES)) {
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
}