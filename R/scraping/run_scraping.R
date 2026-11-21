# =============================================================================
# run_scraping.R — Run all five scrapers and save the scraped spreadsheet
# -----------------------------------------------------------------------------
# OPTIONAL: scraping is not needed to reproduce the analysis, which uses the
# original spreadsheet in data/raw/. This script is not called by run_all.R.
#
# Steps:
#   1. Load the setup, shared helpers and the five scrapers.
#   2. Run the scrapers in order: Agência Brasil, BBC, CNN Brasil, G1,
#      Metrópoles. If one fails or finds nothing, the others still run.
#   3. Save one spreadsheet with one sheet per outlet, each with the same
#      eight columns, in data/scraped/ (never overwriting data/raw/).
#      Sheet names match the original spreadsheet (the BBC sheet is "BBC"),
#      so the file can be read by 01_prepare_data.R.
#
# Browser: the Agência Brasil, BBC and G1 scrapers open pages in Brave, using
# the Brave configuration in web_scraping_setup.R. They were developed and run
# with Brave only; to use another browser, adjust that configuration first.
# =============================================================================

source("R/setup.R")
source("R/scraping/web_scraping_setup.R")
source("R/scraping/scrape_agencia_brasil.R")
source("R/scraping/scrape_bbc.R")
source("R/scraping/scrape_cnn.R")
source("R/scraping/scrape_g1.R")
source("R/scraping/scrape_metropoles.R")

DIR_SCRAPED  <- "data/scraped"
dir.create(DIR_SCRAPED, recursive = TRUE, showWarnings = FALSE)
SCRAPED_FILE <- file.path(DIR_SCRAPED,
                          paste0("scraped_corpus_", format(Sys.Date(), "%Y%m%d"), ".xlsx"))

# The eight columns of the spreadsheet, in order
COLUMNS <- names(empty_corpus())


# -----------------------------------------------------------------------------
# 1. Run the scrapers
# -----------------------------------------------------------------------------
# Each scraper runs inside tryCatch: an error returns an empty table, so the
# remaining scrapers still run. Every result is checked for the eight columns.

run_scraper <- function(outlet, scraper) {
  result <- tryCatch(
    scraper(),
    error = function(e) {
      message("  ⚠ ", outlet, ": scraper stopped with an error: ", conditionMessage(e))
      empty_corpus()
    }
  )
  if (is.null(result)) result <- empty_corpus()
  missing_cols <- setdiff(COLUMNS, names(result))
  if (length(missing_cols) > 0) {
    message("  ⚠ ", outlet, ": missing columns (", paste(missing_cols, collapse = ", "),
            "). Result discarded.")
    return(empty_corpus())
  }
  as_tibble(result)[, COLUMNS]
}

message("\n", strrep("#", 60))
message("SCRAPING ALL OUTLETS")
message("Period: ", format(STUDY_START, "%d/%m/%Y"), " to ", format(STUDY_END, "%d/%m/%Y"))
message(strrep("#", 60))

scraped <- list(
  "Agência Brasil" = run_scraper("Agência Brasil", scrape_agencia_brasil),
  "BBC"            = run_scraper("BBC",            scrape_bbc),
  "CNN Brasil"     = run_scraper("CNN Brasil",     scrape_cnn),
  "G1"             = run_scraper("G1",             scrape_g1),
  "Metrópoles"     = run_scraper("Metrópoles",     scrape_metropoles)
)


# -----------------------------------------------------------------------------
# 2. Save the spreadsheet (one sheet per outlet, as in the original)
# -----------------------------------------------------------------------------
# Outlets with no articles get no sheet, as in the original script.

message("\n", strrep("=", 60))
message("SAVING THE SCRAPED SPREADSHEET")
message(strrep("=", 60))

wb <- createWorkbook()

header_style <- createStyle(
  fontName = "Arial", fontSize = 11, fontColour = "white",
  fgFill = "#1A3A5C", halign = "center", valign = "center",
  textDecoration = "bold", wrapText = TRUE
)

add_sheet <- function(wb, sheet_name, data) {
  if (is.null(data) || nrow(data) == 0) {
    message("  ⚠ ", sheet_name, ": no data. Sheet not created.")
    return(invisible(NULL))
  }
  addWorksheet(wb, sheet_name)
  writeData(wb, sheet_name, data, startRow = 1, startCol = 1, headerStyle = header_style)
  setColWidths(wb, sheet_name, cols = 1:ncol(data), widths = c(18, 20, 45, 40, 80, 25, 18, 60))
  freezePane(wb, sheet_name, firstRow = TRUE)
  addFilter(wb, sheet_name, rows = 1, cols = 1:ncol(data))
  message("  ✅ ", sheet_name, ": ", nrow(data), " articles")
}

for (outlet in names(scraped)) {
  add_sheet(wb, outlet, scraped[[outlet]])
}

if (length(sheets(wb)) == 0) {
  message("\nNo articles were scraped. No spreadsheet saved.")
} else {
  saveWorkbook(wb, SCRAPED_FILE, overwrite = TRUE)
  message("\n✅ Spreadsheet saved to: ", SCRAPED_FILE)
}

message("\nSummary:")
for (outlet in names(scraped)) {
  message("  ", format(outlet, width = 15), nrow(scraped[[outlet]]), " articles")
}
message("  ", format("TOTAL", width = 15), sum(sapply(scraped, nrow)), " articles")
