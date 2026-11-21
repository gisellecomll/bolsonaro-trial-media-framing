# =============================================================================
# scrape_metropoles.R — Collect articles from Metrópoles (OPTIONAL)
# -----------------------------------------------------------------------------
# Collect articles about the trial from the Metrópoles tag
# "julgamento-de-bolsonaro-no-stf", using plain HTTP requests.
#
# Steps:
#   1. Get the tag's article links from the WordPress API
#      (/wp-json/news/content); stop at the first post dated before the period.
#   2. Download each article page and extract date, type, title, lead, body
#      and author.
#   3. Skip articles that fail to download, have no date, or are dated outside
#      1–12 Sep 2025.
#
# No separate relevance filter is applied: the tag is limited to the trial.
#
# Output columns keep their original Portuguese names (spreadsheet format).
#
# Browser: this scraper does not open a browser; it downloads pages over HTTP.
# It loads web_scraping_setup.R only for shared helpers (pauses, extraction
# date); Brave is not needed to run it.
# =============================================================================

if (!exists("random_pause")) source("R/scraping/web_scraping_setup.R")

scrape_metropoles <- function() {
  message("\n", strrep("=", 60))
  message("SCRAPING — METRÓPOLES")
  message(strrep("=", 60))

  # Trial tag page and browser-like HTTP headers (JSON accepted)
  tag_url <- "https://www.metropoles.com/tag/julgamento-de-bolsonaro-no-stf"

  headers_http <- add_headers(
    `User-Agent`      = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
    `Accept`          = "application/json, text/html, */*; q=0.8",
    `Accept-Language` = "pt-BR,pt;q=0.9,en-US;q=0.8",
    `Referer`         = "https://www.metropoles.com/"
  )

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------
  # Download a page and parse its HTML; NULL unless the status is 200
  make_request <- function(url) {
    tryCatch({
      resp <- GET(url, headers_http, timeout(30))
      if (status_code(resp) == 200)
        return(read_html(content(resp, "text", encoding = "UTF-8")))
      message("HTTP ", status_code(resp), " at: ", url)
      NULL
    }, error = function(e) { message("Failed: ", e$message); NULL })
  }

  # Collect article links for the tag through the WordPress API
  # (/wp-json/news/content), 10 posts per page, up to 100 pages; stop at the
  # first post dated before the study period
  collect_tag_links <- function(base_url, start_date, end_date) {
    message("\n========================================")
    message("Collecting links via /wp-json/news/content ...")
    message("========================================\n")

    tag_slug  <- str_extract(base_url, "(?<=/tag/)[^/]+$")
    uri_param <- utils::URLencode(paste0("/tag/", tag_slug), reserved = TRUE)

    all_links <- character(0)
    paged       <- 1

    repeat {
      url_api <- paste0(
        "https://www.metropoles.com/wp-json/news/content",
        "?uri=", uri_param,
        "&posts_per_page=10",
        "&paged=", paged
      )

      message("Page ", paged, ": ", url_api)

      resp <- tryCatch(
        GET(url_api, headers_http, timeout(30)),
        error = function(e) { message("  Error: ", e$message); NULL }
      )

      if (is.null(resp)) break
      if (status_code(resp) %in% c(400, 404)) { message("  End of pagination (HTTP ", status_code(resp), ")."); break }
      if (status_code(resp) != 200) { message("  Unexpected HTTP ", status_code(resp), "."); break }

      response_data <- tryCatch(
        fromJSON(content(resp, "text", encoding = "UTF-8"), simplifyVector = FALSE),
        error = function(e) { message("  Invalid JSON: ", e$message); NULL }
      )
      if (is.null(response_data)) break

      posts <- tryCatch(response_data$data$Tags$noticias, error = function(e) NULL)

      if (is.null(posts) || length(posts) == 0) {
        message("  No posts returned — end of pagination.")
        break
      }

      message("  ", length(posts), " posts on this page")

      stop_paging <- FALSE
      for (post in posts) {
        post_uri  <- post$uri
        post_link <- if (!is.null(post_uri) && nchar(post_uri) > 1)
          paste0("https://www.metropoles.com", post_uri)
        else
          NA_character_

        post_date <- tryCatch(
          as.Date(substr(post$datePublished, 1, 10)),
          error = function(e) as.Date(NA)
        )

        if (!is.na(post_date) && post_date < start_date) {
          message("  Post from ", format(post_date, "%d/%m/%Y"),
                  " is before the period — stopping pagination.")
          stop_paging <- TRUE
          break
        }

        if (!is.na(post_link))
          all_links <- c(all_links, post_link)
      }

      if (stop_paging) break

      paged <- paged + 1
      random_pause(0.8, 1.5)

      if (paged > 100) { message("Limit of 100 pages reached."); break }
    }

    all_links <- unique(all_links)
    message("\nTotal links collected: ", length(all_links))
    return(all_links)
  }

  # Scrape one article page (date, type, title, lead, body, author)
  scrape_article <- function(article_url) {
    page <- make_request(article_url)
    if (is.null(page)) return(NULL)

    # Publication date: <time>, then the page's publication-date tag, then JSON-LD
    pub_date <- tryCatch({
      dt <- page %>% html_element("time[datetime]") %>% html_attr("datetime")
      if (is.na(dt) || dt == "")
        dt <- page %>% html_element("meta[property='article:published_time']") %>% html_attr("content")
      if (is.na(dt) || dt == "") {
        for (s in page %>% html_elements("script[type='application/ld+json']") %>% html_text()) {
          m <- str_extract(s, '"datePublished"\\s*:\\s*"([^"]+)"', group = 1)
          if (!is.na(m)) { dt <- m; break }
        }
      }
      if (!is.na(dt) && dt != "") as.Date(substr(dt, 1, 10)) else NA
    }, error = function(e) NA)

    # Article type: "Coluna de Opinião" for column/opinion links or labels
    type <- tryCatch({
      if (str_detect(article_url, "/colunas?/|/opiniao/|/colunistas/")) {
        "Coluna de Opinião"
      } else {
        cat_text <- page %>%
          html_element(".breadcrumb a:last-of-type, [class*='category'], [class*='kicker']") %>%
          html_text2() %>% str_trim()
        if (!is.na(cat_text) && str_detect(tolower(cat_text), "coluna|opinião|editorial|análise"))
          "Coluna de Opinião"
        else
          "Notícia"
      }
    }, error = function(e) "Notícia")

    # Title (falls back to og:title)
    title <- tryCatch({
      t <- page %>%
        html_element("h1.entry-title, h1.post-title, h1[class*='title'], h1[class*='headline'], article h1, h1") %>%
        html_text2() %>% str_trim()
      if (is.na(t) || t == "")
        page %>% html_element("meta[property='og:title']") %>% html_attr("content") %>% str_trim()
      else t
    }, error = function(e) NA_character_)

    # Lead (falls back to the page description)
    lead <- tryCatch({
      l <- page %>%
        html_element(paste0(".entry-subtitle, .post-subtitle, .lead, .excerpt,",
                            "[class*='subtitle'], [class*='deck'], [class*='summary']")) %>%
        html_text2() %>% str_trim()
      if (is.na(l) || l == "")
        l <- page %>%
          html_element("meta[name='description'], meta[property='og:description']") %>%
          html_attr("content") %>% str_trim()
      if (is.na(l) || l == "") NA_character_ else l
    }, error = function(e) NA_character_)

    # Body: paragraphs and subheadings; lines matching calls to action,
    # newsletters, "Leia também", sharing or ads are dropped, and paragraphs
    # shorter than 25 characters are dropped
    body <- tryCatch({
      junk_regex <- paste0(
        "^\\d{2}/\\d{2}/\\d{4}",
        "|[Rr]eceba\\s+not[íi]cias|[Aa]cesse o canal",
        "|[Ss]iga.*[Tt]elegram|[Tt]elegram.*[Mm]etr[óo]poles",
        "|[Mm]etr[óo]poles.*[Tt]elegram",
        "|[Ss]e inscreva|[Nn]ewsletter|[Nn]otifica[çc][õo]es",
        "|[Cc]lique aqui e receba|[Ee]ntre no grupo",
        "|[Ll]eia (mais|tamb[ée]m)\\s*:|^LEIA (MAIS|TAMBÉM)\\s*:?$",
        "|[Ll]eia tamb[ée]m|[Ll]eia mais",
        "|^Saiba mais\\s*:?$|^Veja (mais|tamb[ée]m)\\s*:?$",
        "|^Publicidade$|^Anúncio$",
        "|[Cc]ompartilhar?\\s*(not[íi]cia[s]?)?\\s*:?$",
        "|^Compartilhar?$|[Cc]ompartilhe"
      )
      nodes <- NULL
      for (sel in c(".entry-content", ".post-content", ".article-body",
                    "[class*='article-content']", "[class*='post-body']", "article .content")) {
        container <- page %>% html_element(sel)
        if (length(container) > 0 && !is.na(html_name(container))) {
          nodes <- container %>% html_elements("p, h2, h3, h4")
          if (length(nodes) > 0) break
        }
      }
      if (is.null(nodes) || length(nodes) == 0)
        nodes <- page %>% html_elements("article p, article h4, article h3")
      # No body text found: the body is stored as NA and the article keeps its
      # other fields (bug fix: the original return() ended the whole function)
      if (length(nodes) == 0) {
        NA_character_
      } else {
        pieces <- character(0)
        for (node in nodes) {
          tag <- html_name(node)
          txt <- str_trim(html_text2(node))
          if (txt == "" || str_detect(txt, junk_regex)) next
          if (tag %in% c("h2", "h3", "h4"))
            pieces <- c(pieces, paste0("## ", txt))
          else if (nchar(txt) >= 25)
            pieces <- c(pieces, txt)
        }
        if (length(pieces) == 0) NA_character_ else paste(pieces, collapse = "\n\n")
      }
    }, error = function(e) NA_character_)

    # Author (falls back to JSON-LD)
    author <- tryCatch({
      a <- page %>%
        html_elements(".author, .byline, [class*='author'], [rel='author'], [class*='reporter']") %>%
        html_text2() %>% str_trim()
      a <- unique(a[a != "" & !str_detect(tolower(a),
                                          "^por$|^author$|^autor$|publicado|atualizado|redação")])
      if (length(a) == 0) {
        author_ld <- NA_character_
        for (s in page %>% html_elements("script[type='application/ld+json']") %>% html_text()) {
          m <- str_extract(s, '"name"\\s*:\\s*"([^"]+)"', group = 1)
          if (!is.na(m) && !str_detect(tolower(m), "metrópoles|metropoles")) {
            author_ld <- m; break
          }
        }
        author_ld
      } else paste(a, collapse = ", ")
    }, error = function(e) NA_character_)

    list(pub_date = pub_date, type = type, title = title,
         lead = lead, body = body, author = author, link = article_url)
  }

  # ---------------------------------------------------------------------------
  # Main collection
  # ---------------------------------------------------------------------------
  # Articles that fail to download, have no date, or are dated outside the
  # study period are skipped.
  message("\n============================================================")
  message("SCRAPING - METRÓPOLES | Bolsonaro trial at the STF")
  message("Period: ", format(STUDY_START, "%d/%m/%Y"), " to ", format(STUDY_END, "%d/%m/%Y"))
  message("============================================================\n")

  all_links <- collect_tag_links(tag_url, STUDY_START, STUDY_END)

  if (length(all_links) == 0) {
    message("Metrópoles: no links collected.")
    return(empty_corpus())
  }

  message("\n========================================")
  message("Extracting article content...")
  message("========================================\n")

  results <- list()
  skipped  <- 0

  for (i in seq_along(all_links)) {
    current_url <- all_links[i]
    message("[", i, "/", length(all_links), "] ", current_url)

    article <- scrape_article(current_url)

    if (is.null(article)) {
      message("  -> Failed. Skipping.")
      skipped <- skipped + 1; random_pause(1, 2); next
    }

    article_date <- article$pub_date

    if (is.na(article_date)) {
      message("  -> No date. Skipping.")
      skipped <- skipped + 1; random_pause(1, 2); next
    }

    if (article_date < STUDY_START || article_date > STUDY_END) {
      message("  -> Outside the period (", format(article_date, "%d/%m/%Y"), "). Skipping.")
      skipped <- skipped + 1; random_pause(1, 2); next
    }

    message("  -> OK | ", format(article_date, "%d/%m/%Y"), " | ", str_trunc(article$title, 60))

    results[[length(results) + 1]] <- data.frame(
      `Data de Publicação` = format(article_date, "%d/%m/%Y"),
      `Tipo de Matéria`    = if (is.na(article$type))    NA_character_ else article$type,
      `Título`             = if (is.na(article$title))  NA_character_ else article$title,
      `Lead`               = if (is.na(article$lead))    NA_character_ else article$lead,
      `Corpo do Texto`     = if (is.na(article$body))   NA_character_ else article$body,
      `Autoria`            = if (is.na(article$author)) NA_character_ else article$author,
      `Data de Extração`   = EXTRACTION_DATE,
      `Link`               = article$link,
      check.names = FALSE, stringsAsFactors = FALSE
    )

    random_pause(1, 3)
  }

  if (length(results) == 0) {
    message("Metrópoles: no articles in the period.")
    return(empty_corpus())
  }

  # Missing lead and author are stored as the text "NA"; rows are sorted by date
  final_df <- bind_rows(results) %>%
    mutate(
      Lead    = if_else(is.na(Lead),    "NA", Lead),
      Autoria = if_else(is.na(Autoria), "NA", Autoria)
    ) %>%
    arrange(as.Date(`Data de Publicação`, "%d/%m/%Y"))

  message("Metrópoles: ", nrow(final_df), " articles extracted")
  message("Skipped (outside the period or error): ", skipped)
  return(final_df)
}

