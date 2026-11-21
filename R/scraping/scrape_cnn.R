# =============================================================================
# scrape_cnn.R — Collect articles from CNN Brasil (OPTIONAL)
# -----------------------------------------------------------------------------
# Collect articles about the trial from the CNN Brasil tag page
# "julgamento-bolsonaro", using plain HTTP requests.
#
# Steps:
#   1. Go through the tag listing pages (up to 58), keeping links dated
#      1–12 Sep 2025; stop at the first item dated before the period.
#   2. For each article, extract date, type, title, lead, author and body.
#
# No separate relevance filter is applied: the tag page is limited to the
# trial.
#
# Output columns keep their original Portuguese names (spreadsheet format).
#
# Browser: this scraper does not open a browser; it downloads pages over HTTP.
# It loads web_scraping_setup.R only for shared helpers (HTTP requests,
# pauses, extraction date); Brave is not needed to run it.
# =============================================================================

if (!exists("fetch_page")) source("R/scraping/web_scraping_setup.R")

scrape_cnn <- function() {
  message("\n", strrep("=", 60))
  message("SCRAPING — CNN BRASIL")
  message(strrep("=", 60))

  URL_BASE    <- "https://www.cnnbrasil.com.br/tudo-sobre/julgamento-bolsonaro/"
  MAX_PAGES <- 58  # maximum number of listing pages

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------
  # Clean text of the first element matching a CSS selector
  clean_text <- function(page, selector) {
    node <- html_element(page, selector)
    if (is.na(node) || is.null(node)) return(NA_character_)
    str_squish(html_text2(node))
  }

  # Article type: "Coluna/Opinião" for blog, opinion or columnist links
  classify_type <- function(url, author) {
    if (str_detect(url, "/blogs/|/opiniao/|/colunistas/")) {
      return("Coluna/Opinião")
    }
    return("Notícia")
  }

  # Article body: paragraphs, subheadings, quotes and list items; lines shorter
  # than 10 characters, "Publicado por" lines and repeated lines are dropped
  extract_body <- function(html) {
    container_selectors <- c(
      ".post-content", ".article-content", ".entry-content",
      ".post__content", "article .content", "article"
    )
    container <- NULL
    for (sel in container_selectors) {
      container <- html_element(html, sel)
      if (!is.na(container) && !is.null(container)) break
    }
    if (is.na(container) || is.null(container)) return(NA_character_)

    nodes <- html_elements(
      container,
      "p, h2.text-2xl, h3, h4, blockquote, ul.list-none li"
    )
    if (length(nodes) == 0) return(NA_character_)

    lines <- c()
    for (node in nodes) {
      tag <- html_name(node)
      txt <- str_squish(html_text2(node))
      if (nchar(txt) < 10) next
      if (str_detect(txt, regex("^\\*?Publicado por", ignore_case = TRUE))) next
      line <- switch(
        tag,
        "h2"         = paste0("\n## ", txt),
        "h3"         = paste0("\n### ", txt),
        "h4"         = paste0("\n#### ", txt),
        "li"         = paste0("• ", txt),
        "blockquote" = paste0("> ", txt),
        txt
      )
      lines <- c(lines, line)
    }
    if (length(lines) > 1) {
      lines <- lines[c(TRUE, lines[-1] != lines[-length(lines)])]
    }
    body <- paste(lines, collapse = "\n\n")
    body <- str_trim(body)
    body <- str_replace_all(body, "\n{3,}", "\n\n")
    if (nchar(body) < 50) return(NA_character_)
    return(body)
  }

  # ---------------------------------------------------------------------------
  # Step 1: collect links from the tag listing pages
  # ---------------------------------------------------------------------------
  # Links in the period are kept; collection stops at the first item dated
  # before the study period. Tag, author, live-coverage and blog-index links
  # are skipped.
  cat("\n========================================================\n")
  cat("  SCRAPING CNN BRASIL — BOLSONARO TRIAL\n")
  cat(glue("  Period: {format(STUDY_START,'%d/%m/%Y')} to {format(STUDY_END,'%d/%m/%Y')}\n"))
  cat("========================================================\n\n")
  cat("▶ STEP 1: Collecting article links from the listing pages...\n")

  collected_links <- tibble(url = character(), pub_date = as.Date(character()))
  stop_collection <- FALSE

  for (page_num in 1:MAX_PAGES) {
    if (stop_collection) break
    page_url <- if (page_num == 1) URL_BASE else paste0(URL_BASE, "pagina/", page_num, "/")
    cat(glue("  → Page {page_num}: {page_url}\n"))

    html <- fetch_page(page_url)
    if (is.null(html)) break

    items <- html_elements(html, "li")
    dates_found_on_page <- c()

    for (item in items) {
      link_node <- html_element(item, "a[href]")
      if (is.na(link_node)) next
      href <- html_attr(link_node, "href")
      if (is.na(href) || !str_detect(href, "cnnbrasil\\.com\\.br")) next
      if (str_detect(href, "/tudo-sobre/|/autor/|/ao-vivo|/blogs$|#")) next
      item_text <- html_text2(item)
      date_match <- str_extract(item_text,
                                "\\b(0?[1-9]|[12][0-9]|3[01])/(0?[1-9]|1[0-2])/202[0-9]\\b")
      if (!is.na(date_match)) {
        pub_date <- dmy(date_match)
        if (!is.na(pub_date) && pub_date < STUDY_START) {
          cat(glue("  ✓ Date {format(pub_date,'%d/%m/%Y')} < start of the period. Stopping collection.\n"))
          stop_collection <- TRUE
          break
        }
        if (!is.na(pub_date) && pub_date >= STUDY_START && pub_date <= STUDY_END) {
          if (!href %in% collected_links$url) {
            collected_links <- bind_rows(collected_links, tibble(url = href, pub_date = pub_date))
            dates_found_on_page <- c(dates_found_on_page, format(pub_date, "%d/%m/%Y"))
          }
        }
      }
    }
    cat(glue("    Found on this page: {length(dates_found_on_page)} articles in the period\n"))
    random_pause(1, 2)
  }

  cat(glue("\n  ✅ Total links collected in the period: {nrow(collected_links)}\n\n"))

  if (nrow(collected_links) == 0) {
    message("CNN Brasil: no links found in the period.")
    return(empty_corpus())
  }

  # ---------------------------------------------------------------------------
  # Step 2: scrape each article
  # ---------------------------------------------------------------------------
  # If a page cannot be downloaded, a row with only the link and extraction
  # date is kept.
  cat("▶ STEP 2: Scraping each article...\n\n")

  scrape_article <- function(url, listing_pub_date) {
    cat(glue("  → {url}\n"))
    random_pause()
    html <- fetch_page(url)
    if (is.null(html)) {
      return(tibble(
        `Data de Publicação` = NA_character_, `Tipo de Matéria` = NA_character_,
        `Título` = NA_character_, `Lead` = NA_character_,
        `Corpo do Texto` = NA_character_, `Autoria` = NA_character_,
        `Data de Extração` = EXTRACTION_DATE, `Link` = url
      ))
    }

    # Publication date: the page's publication-date tag, then <time>, then the date shown
    # on the listing page
    pub_date_raw <- NA_character_
    meta_date <- html_element(html, "meta[property='article:published_time']")
    if (!is.na(meta_date)) {
      content_attr <- html_attr(meta_date, "content")
      if (!is.na(content_attr)) {
        pub_date_raw <- tryCatch(
          format(ymd_hms(content_attr, tz = "America/Sao_Paulo"), "%d/%m/%Y"),
          error = function(e) NA_character_
        )
      }
    }
    if (is.na(pub_date_raw)) {
      time_el <- html_element(html, "time")
      if (!is.na(time_el)) {
        datetime_attr <- html_attr(time_el, "datetime")
        if (!is.na(datetime_attr)) {
          pub_date_raw <- tryCatch(
            format(ymd_hms(datetime_attr, tz = "America/Sao_Paulo"), "%d/%m/%Y"),
            error = function(e) {
              tryCatch(
                format(ymd(datetime_attr), "%d/%m/%Y"),
                error = function(e2) NA_character_
              )
            }
          )
        }
        if (is.na(pub_date_raw)) {
          txt_time <- str_extract(html_text2(time_el), "\\d{2}/\\d{2}/\\d{4}")
          if (!is.na(txt_time)) pub_date_raw <- txt_time
        }
      }
    }
    if (is.na(pub_date_raw) && !is.na(listing_pub_date)) {
      pub_date_raw <- format(listing_pub_date, "%d/%m/%Y")
    }

    # Article type
    author_check <- html_element(html, ".post-header .author a, .article-author a, .post__authors a")
    author_name <- if (!is.na(author_check)) str_squish(html_text2(author_check)) else NA_character_
    type <- classify_type(url, author_name)

    # Title
    title <- clean_text(html, "h1.post-header__title, h1.title, h1")

    # Lead
    lead <- clean_text(html, paste0(
      "h2.post-header__subtitle, ",
      ".post-header__subtitle, ",
      ".article-subtitle, ",
      ".entry-subtitle, ",
      "header h2"
    ))

    # Author (", da CNN" suffix removed)
    author_text <- NA_character_
    author_node <- html_element(
      html,
      "div[data-single-author='true'] a span.text-sm.font-medium"
    )
    if (!is.na(author_node) && !is.null(author_node)) {
      author_text <- str_squish(html_text2(author_node))
    }
    if (is.na(author_text) || nchar(author_text) == 0) {
      author_blog <- html_element(html, "a[href*='/blogs/'] h5")
      if (!is.na(author_blog) && !is.null(author_blog)) {
        author_text <- str_squish(html_text2(author_blog))
      }
    }
    if (!is.na(author_text)) {
      author_text <- author_text |>
        str_remove(",\\s*da CNN.*") |>
        str_squish()
    }
    if (!is.na(author_text)) {
      author_text <- author_text |>
        str_replace(regex("^Da CNN Brasil$", ignore_case = TRUE), "CNN Brasil") |>
        str_squish()
    }

    # Body
    body <- extract_body(html)

    tibble(
      `Data de Publicação` = pub_date_raw,
      `Tipo de Matéria`    = type,
      `Título`             = title,
      `Lead`               = lead,
      `Corpo do Texto`     = body,
      `Autoria`            = author_text,
      `Data de Extração`   = EXTRACTION_DATE,
      `Link`               = url
    )
  }

  results <- map_dfr(
    seq_len(nrow(collected_links)),
    function(i) {
      cat(glue("[{i}/{nrow(collected_links)}] "))
      scrape_article(collected_links$url[i], collected_links$pub_date[i])
    }
  )

  message("CNN Brasil: ", nrow(results), " articles extracted")
  return(results)
}

