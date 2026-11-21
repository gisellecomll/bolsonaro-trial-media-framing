# =============================================================================
# web_scraping_setup.R — Shared helpers for the web scrapers (OPTIONAL)
# -----------------------------------------------------------------------------
#
# BROWSER REQUIREMENT: the original scraping workflow was developed and run
# with the Brave browser, which the author uses personally, and it has only
# been tested with Brave. It is not guaranteed to work with other browsers.
# Users without Brave may need to modify the browser configuration in the
# "Brave browser for chromote" section below before running the scrapers.
# =============================================================================

if (!exists("load_packages")) source("R/setup.R")
load_packages(PACKAGES_SCRAPING)


# -----------------------------------------------------------------------------
# Extraction date (recorded in the "Data de Extração" column, dd/mm/yyyy)
# -----------------------------------------------------------------------------

EXTRACTION_DATE <- format(Sys.Date(), "%d/%m/%Y")


# -----------------------------------------------------------------------------
# Brave browser for chromote
# -----------------------------------------------------------------------------
# The author uses Brave, and the original scraping workflow was configured
# around it: the candidate paths below are Brave's default install locations,
# and the scrapers were only run and tested with Brave.
#
# Called only by the scrapers that render JavaScript (Agência Brasil, BBC, G1).
# - A different browser: you may need to change this configuration yourself
#   (for example, point BRAVE_PATH to another Chromium-based browser, which is
#   what chromote requires). This has not been tested, and compatibility with
#   other browsers is not guaranteed; page loading and timing may behave
#   differently.

use_brave <- function() {
  if (exists("BRAVE_PATH")) {
    path <- BRAVE_PATH
  } else {
    candidates <- c(
      "C:/Program Files/BraveSoftware/Brave-Browser/Application/brave.exe",
      "C:/Program Files (x86)/BraveSoftware/Brave-Browser/Application/brave.exe",
      paste0(Sys.getenv("LOCALAPPDATA"),
             "/BraveSoftware/Brave-Browser/Application/brave.exe"),
      "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser",
      "/usr/bin/brave-browser",
      "/usr/bin/brave"
    )
    found <- candidates[file.exists(candidates)]
    if (length(found) == 0) {
      stop("Brave not found. Set it manually: BRAVE_PATH <- 'C:/path/brave.exe'",
           call. = FALSE)
    }
    path <- found[1]
  }
  message("Using browser: ", path)
  Sys.setenv(CHROMOTE_CHROME = path)
}


# -----------------------------------------------------------------------------
# Page loading
# -----------------------------------------------------------------------------

# Load a page in a chromote session (renders JavaScript) and parse its HTML.
# Returns NULL on failure.
read_html_brave <- function(url, session, timeout = 15) {
  tryCatch({
    session$Page$navigate(url)
    Sys.sleep(timeout * 0.4)
    session$Runtime$evaluate(expression = "document.readyState")
    html_raw <- session$Runtime$evaluate(
      expression = "document.documentElement.outerHTML"
    )$result$value
    read_html(html_raw)
  }, error = function(e) {
    message("Error loading: ", url, "\n  ", conditionMessage(e))
    NULL
  })
}

# Browser-like headers for plain HTTP requests (CNN Brasil).
HTTP_HEADERS <- add_headers(
  `User-Agent`      = paste0("Mozilla/5.0 (Windows NT 10.0; Win64; x64) ",
                             "AppleWebKit/537.36 (KHTML, like Gecko) ",
                             "Chrome/124.0.0.0 Safari/537.36"),
  `Accept-Language` = "pt-BR,pt;q=0.9,en-US;q=0.8",
  `Accept`          = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
)

# Fetch a page over HTTP and parse its HTML. Returns NULL unless status is 200.
fetch_page <- function(url) {
  tryCatch({
    resp <- GET(url, HTTP_HEADERS, timeout(30))
    if (status_code(resp) == 200) {
      read_html(content(resp, "text", encoding = "UTF-8"))
    } else {
      message("  [WARNING] Status ", status_code(resp), " at: ", url)
      NULL
    }
  }, error = function(e) {
    message("  [ERROR] Could not access: ", url, "\n  Detail: ", e$message)
    NULL
  })
}


# -----------------------------------------------------------------------------
# Small helpers
# -----------------------------------------------------------------------------

# Random pause between requests, to avoid overloading the servers.
random_pause <- function(min = 1.5, max = 3.5) {
  Sys.sleep(runif(1, min, max))
}

# Return `a` unless it is NULL, NA or an empty string; otherwise `b`.
# (Overrides base R's %||%, which only checks for NULL — as in the original.)
`%||%` <- function(a, b) {
  if (!is.null(a) && !is.na(a) && nchar(as.character(a)) > 0) a else b
}

# Empty result with the standard column layout, returned by a scraper when it
# finds no articles.
empty_corpus <- function() {
  tibble(
    `Data de Publicação` = character(), `Tipo de Matéria` = character(),
    `Título`             = character(), `Lead`            = character(),
    `Corpo do Texto`     = character(), `Autoria`         = character(),
    `Data de Extração`   = character(), `Link`            = character()
  )
}