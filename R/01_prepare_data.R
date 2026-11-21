# =============================================================================
# 01_prepare_data.R — Load, check, clean and sample the news corpus
# -----------------------------------------------------------------------------
#
# Steps:
#   1. Read and stack the five sheets; build the text field (title + body).
#   2. Assign a unique article ID (e.g. AB_001, BBC_001, MET_001).
#   3. Diagnose empty article bodies per outlet.
#   4. Keep articles with a body; draw 75 articles per outlet at random
#      (seed 42), giving a balanced sample of 375.
#
# Reproducibility status: running `run_all.R` with R 4.5.3 and dplyr 1.2.1
# reproduced all numerical results reported in the paper.
#
# Methodological notes:
#   - No date filter is applied. The BBC sheet contains a few articles dated
#     30–31 August 2025, outside the study period; they are eligible for
#     sampling exactly as in the original analysis.
#   - The outlet label is the sheet name of the original spreadsheet.
#   - All original columns, including lead, body and links, are preserved.
# =============================================================================

source("R/setup.R")

if (!file.exists(RAW_CORPUS_FILE)) {
  stop("Raw corpus not found: ", RAW_CORPUS_FILE, call. = FALSE)
}


# -----------------------------------------------------------------------------
# 1. Read and stack the five sheets
# -----------------------------------------------------------------------------

sheets <- excel_sheets(RAW_CORPUS_FILE)
message("Sheets found: ", paste(sheets, collapse = ", "))

corpus <- lapply(sheets, function(s) {
  read_excel(RAW_CORPUS_FILE, sheet = s) %>%
    mutate(outlet = s)
}) %>%
  bind_rows() %>%
  mutate(text = paste(`Título`, `Corpo do Texto`, sep = " "))  # title + body


# -----------------------------------------------------------------------------
# 2. Unique article ID: outlet abbreviation + sequential number
# -----------------------------------------------------------------------------
# Numbered in the row order of each sheet of the original spreadsheet, so an
# article keeps the same ID in the corpus, cleaned corpus, and sample.
OUTLET_CODES <- c(
  "Agência Brasil" = "AB",
  "BBC"            = "BBC",
  "CNN Brasil"     = "CNN",
  "G1"             = "G1",
  "Metrópoles"     = "MET"
)

unknown <- setdiff(unique(corpus$outlet), names(OUTLET_CODES))
if (length(unknown) > 0) {
  stop("No ID code defined for sheet(s): ", paste(unknown, collapse = ", "),
       call. = FALSE)
}

corpus <- corpus %>%
  group_by(outlet) %>%
  mutate(id = sprintf("%s_%03d", OUTLET_CODES[outlet], row_number())) %>%
  ungroup() %>%
  relocate(id, outlet)

stopifnot(!anyDuplicated(corpus$id))

glimpse(corpus)


# -----------------------------------------------------------------------------
# 3. Diagnostics: empty article bodies per outlet
# -----------------------------------------------------------------------------

diagnostics <- corpus %>%
  group_by(outlet) %>%
  summarise(
    total      = n(),
    empty_body = sum(is.na(`Corpo do Texto`) | `Corpo do Texto` == ""),
    with_body  = sum(!is.na(`Corpo do Texto`) & `Corpo do Texto` != "")
  )

print(diagnostics)
write.csv(diagnostics, file.path(DIR_TABLES, "corpus_diagnostics.csv"),
          row.names = FALSE, fileEncoding = "UTF-8")


# -----------------------------------------------------------------------------
# 4. Cleaning and stratified random sample (75 articles per outlet)
# -----------------------------------------------------------------------------

corpus_clean <- corpus %>%
  filter(!is.na(`Corpo do Texto`) & `Corpo do Texto` != "")

set.seed(SEED)  # set immediately before sampling, as in the original

sample_375 <- corpus_clean %>%
  group_by(outlet) %>%
  slice_sample(n = SAMPLE_SIZE_PER_OUTLET) %>%
  ungroup()

# Check: 75 articles per outlet
print(count(sample_375, outlet))
stopifnot(all(count(sample_375, outlet)$n == SAMPLE_SIZE_PER_OUTLET))

# RDS files are read by the next scripts; CSV copies are for inspection.
saveRDS(corpus_clean, file.path(DIR_PROCESSED, "corpus_clean.rds"))
saveRDS(sample_375,   file.path(DIR_PROCESSED, "sample_375.rds"))
write.csv(corpus_clean, file.path(DIR_PROCESSED, "corpus_clean.csv"),
          row.names = FALSE, fileEncoding = "UTF-8")
write.csv(sample_375, file.path(DIR_PROCESSED, "sample_375.csv"),
          row.names = FALSE, fileEncoding = "UTF-8")