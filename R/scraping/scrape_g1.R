# =============================================================================
# scrape_g1.R — Collect articles from G1 (OPTIONAL)
# -----------------------------------------------------------------------------
# Collect articles about the trial from the G1 internal search, rendered in
# Brave through chromote.
#
# Steps:
#   1. Search G1 for "bolsonaro julgamento golpista" one day at a time
#      (1–12 Sep 2025), news items only, scrolling until all results load.
#   2. For each article: skip excluded formats (summaries, podcasts, etc.),
#      extract the body and remove non-editorial elements and lines.
#   3. Keep articles whose text contains a required pair of words.
#
# No separate publication date check is applied: the period is set by the
# daily search windows.
#
# Output columns keep their original Portuguese names (spreadsheet format).
#
# Browser: this scraper opens pages in Brave through chromote, using the Brave
# configuration in web_scraping_setup.R. It was developed and run with Brave
# only; to use another browser, adjust that configuration first.
# =============================================================================

if (!exists("read_html_brave")) source("R/scraping/web_scraping_setup.R")

scrape_g1 <- function() {
  message("\n", strrep("=", 60))
  message("SCRAPING — G1")
  message(strrep("=", 60))

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------
  # Relevance filter: the text (title + lead + body) passes if it contains at
  # least one of three pairs of words.
  contains_required_pairs <- function(text) {
    text <- tolower(as.character(text))
    text[is.na(text)] <- ""
    sapply(text, function(x) {
      par1 <- str_detect(x, "julgamento") & str_detect(x, "bolsonaro")
      par2 <- str_detect(x, "bolsonaro")  & str_detect(x, "golpista")
      par3 <- str_detect(x, "julgamento") & str_detect(x, "golpista")
      par1 | par2 | par3
    })
  }

  # Formats excluded by title or link (summaries, podcasts, etc.)
  is_excluded_format <- function(title, url) {
    title_lower <- tolower(as.character(title))
    url_lower    <- tolower(as.character(url))
    patterns <- c("resumão","resumao","resumo do dia","em um minuto",
                 "em 1 minuto","podcast","quero ver de novo",
                 "o que você precisa saber")
    any(str_detect(title_lower, patterns)) | any(str_detect(url_lower, patterns))
  }

  # Scroll the search results page until no more results load
  scroll_to_end <- function(b, max_attempts = 80, pause = 2.5) {
    previous_height <- 0
    for (i in seq_len(max_attempts)) {
      b$Runtime$evaluate("window.scrollTo(0, document.body.scrollHeight)")
      Sys.sleep(pause)
      current_height <- b$Runtime$evaluate("document.body.scrollHeight")$result$value
      if (current_height == previous_height) { message("  Scrolling finished after ", i, " scrolls."); break }
      previous_height <- current_height
      message("  Scroll ", i, " — height: ", current_height)
    }
  }

  # Article links (.ghtml) on the search results page
  extract_search_cards <- function(html_src) {
    html  <- read_html(html_src)
    links <- html %>% html_nodes("a[href*='.ghtml']") %>% html_attr("href")
    links <- unique(links[grepl("g1\\.globo\\.com", links)])
    tibble(link = links)
  }

  # TRUE if a node sits inside a non-editorial block (related content,
  # newsletter, banners, sidebars, semantic tags, summary cards)
  is_structural_junk <- function(node) {
    current <- node
    for (i in 1:10) {
      current <- tryCatch(xml_parent(current), error = function(e) NULL)
      if (is.null(current) || inherits(current, "xml_document") || inherits(current, "xml_missing")) break
      node_class <- tolower(xml_attr(current, "class") %||% "")
      node_id  <- tolower(xml_attr(current, "id")    %||% "")
      track  <- tolower(xml_attr(current, "data-track-category") %||% "")
      track2 <- tolower(xml_attr(current, "data-track-action")   %||% "")
      if (any(str_detect(node_class, c(
        "entities", "related", "recommendation", "newsletter",
        "subscription", "banner", "aside", "sidebar",
        "content-related", "story-related",
        "widget-relacionadas", "widget-newsletter", "widget-subscription",
        "mc-summary", "mc-summary-card"
      )))) return(TRUE)
      if (str_detect(track,  "tag semantica")) return(TRUE)
      if (str_detect(track2, "tag semantica")) return(TRUE)
      if (str_detect(node_id,  "related|aside|sidebar|entities|newsletter")) return(TRUE)
    }
    FALSE
  }

  # Non-editorial lines (calls to action, "Leia também", photo credits,
  # live-coverage notices, dates, bylines)
  is_junk_text <- function(text) {
    t <- tolower(trimws(text))
    if (nchar(t) == 0) return(TRUE)
    patterns <- c(
      "^leia (também|tambem)\\b", "^veja (também|tambem)\\b",
      "^saiba mais (sobre|aqui)$",
      "^para se inscrever", "^crie uma conta globo", "^entre ou crie",
      "notícias que você não pode perder", "diretamente no seu e-mail",
      "de segunda a sábado", "^assine o g1", "^baixe o aplicativo",
      "^siga o g1 no", "^acompanhe o g1", "^receba as principais notícias",
      "^—?\\s*foto\\s*:", "^foto\\s*:", "^imagem\\s*:", "^crédito[s]?\\s*:",
      "^credito[s]?\\s*:", "^©\\s*", "^reprodução$", "^reprodução\\s*[/—-]",
      "todos os direitos reservados", "— foto:", "— foto :", "/foto:",
      "^g1\\.globo\\.com$", "^g1$",
      "^resumo do dia$", "^resumão$",
      "^leia mais notícias sobre a região",
      "acompanhe aqui", "assista ao vivo", "transmitir ao vivo",
      "\U0001F534", "ao vivo\\b",
      "^\\d{2}/\\d{2}/\\d{4}",
      "atualizado\\s+\\d{2}/\\d{2}",
      "\\d{2}h\\d{2}\\s*(atualizado|—|$)",
      "^por [a-záàâãéêíóôõúüç]",
      "^carregando\\.?$", "^carregando\\.\\.\\.\\.$"
    )
    any(sapply(patterns, function(p) str_detect(t, p)))
  }

  # Convert a simple CSS selector to XPath
  xpath_from_css <- function(sel) {
    sel <- trimws(sel)
    if (str_detect(sel, "\\[.*=.*\\]")) {
      attr_match <- str_match(sel, "\\[([^=]+)=['\"]([^'\"]+)['\"]\\]")
      if (!is.na(attr_match[1,1])) {
        return(paste0(".//*[@", attr_match[1,2], "='", attr_match[1,3], "']"))
      }
    }
    parts  <- str_split(sel, "\\.")[[1]]
    tag    <- if (parts[1] == "" || parts[1] == "*") "*" else parts[1]
    classes <- parts[parts != "" & parts != tag]
    if (length(classes) == 0) return(paste0(".//", tag))
    cond <- paste(
      sapply(classes, function(c)
        paste0("contains(concat(' ',normalize-space(@class),' '),' ", c, " ')")),
      collapse = " and "
    )
    paste0(".//", tag, "[", cond, "]")
  }

  # Remove non-editorial elements (related, newsletter, banners, captions,
  # embedded media, summary cards) from the article container
  remove_junk_nodes <- function(container) {
    remove_selectors <- c(
      ".entities", ".related-content", ".content-related",
      ".story-related", ".related", ".newsletter",
      ".subscription-box", ".banner", "aside", ".mc-column.entities",
      ".content-media__description",
      ".codex-caption",
      ".cxm-block-video__caption-container",
      ".content-media",
      ".mc-summary",
      ".mc-summary-card"
    )
    for (sel in remove_selectors) {
      junk_nodes <- tryCatch(
        xml_find_all(container, xpath_from_css(sel)),
        error = function(e) { message("  xpath failed for: ", sel); NULL }
      )
      if (is.null(junk_nodes) || length(junk_nodes) == 0) next
      for (node in junk_nodes) {
        tryCatch(xml_remove(node, free = TRUE), error = function(e) NULL)
      }
    }
    container
  }

  # TRUE if a list item is editorial text rather than a list of links
  is_editorial_li <- function(node) {
    full_text <- trimws(html_text(node, trim = TRUE))
    if (nchar(full_text) == 0) return(FALSE)
    children <- xml_children(node)
    child_names <- sapply(children, html_name)
    if (length(children) == 1 && child_names[1] == "a") return(FALSE)
    link_nodes   <- xml_find_all(node, ".//a")
    link_text <- paste(sapply(link_nodes, function(x) trimws(html_text(x, trim = TRUE))),
                     collapse = " ")
    if (nchar(link_text) > 0) {
      free_text <- trimws(str_remove_all(full_text, fixed(link_text)))
    } else {
      free_text <- full_text
    }
    free_text <- trimws(str_remove_all(free_text, "[[:punct:]]"))
    if (nchar(free_text) == 0) return(FALSE)
    has_uppercase_label <- FALSE
    strong_nodes <- xml_find_all(node, ".//strong")
    if (length(strong_nodes) > 0) {
      strong_text <- trimws(html_text(strong_nodes[[1]], trim = TRUE))
      if (str_detect(strong_text, "^[A-ZÁÀÂÃÉÊÍÓÔÕÚÜÇ0-9\\s]+:?$")) {
        has_uppercase_label <- TRUE
      }
    }
    if (has_uppercase_label && length(link_nodes) >= 1) {
      strong_label <- trimws(html_text(strong_nodes[[1]], trim = TRUE))
      text_without_label <- trimws(str_remove(free_text, fixed(
        str_remove(strong_label, ":$")
      )))
      if (nchar(text_without_label) < 5) return(FALSE)
    }
    TRUE
  }

  # Article body: paragraphs, subheadings and editorial list items, after
  # removing non-editorial elements and lines; repeated lines are dropped
  extract_body <- function(html) {
    container_selectors <- c(
      ".content-text__container", ".mc-body", ".post-content",
      ".entry-content", "article"
    )
    container <- NULL
    for (sel in container_selectors) {
      node <- tryCatch(html %>% html_node(sel), error = function(e) NULL)
      if (!is.null(node) && length(xml_children(node)) > 0) {
        container <- node
        break
      }
    }
    if (is.null(container)) {
      paragraphs <- html %>% html_nodes("p") %>% html_text(trim = TRUE)
      paragraphs <- paragraphs[!sapply(paragraphs, is_junk_text)]
      return(paste(paragraphs, collapse = "\n\n"))
    }
    container <- remove_junk_nodes(container)
    nodes <- container %>%
      html_nodes(paste(
        "p",
        ".content-intertitle h2",
        ".content-intertitle h3",
        "ul > li",
        "ol > li",
        sep = ", "
      ))
    if (length(nodes) == 0) return(NA_character_)
    lines <- character(0)
    inside_summary <- FALSE
    for (node in nodes) {
      tag   <- html_name(node)
      text <- html_text(node, trim = TRUE)
      if (nchar(trimws(text)) == 0) next
      if (tag %in% c("h2", "h3") &&
          str_detect(tolower(text), "resumo do dia|resumão")) {
        inside_summary <- TRUE
        next
      }
      if (inside_summary) next
      if (is_structural_junk(node)) next
      if (tag == "li" && !is_editorial_li(node)) next
      if (is_junk_text(text)) next
      if (tag == "p") {
        t_lower <- tolower(trimws(text))
        if (nchar(text) < 120 &&
            str_detect(t_lower, "\\bg1\\b") &&
            str_detect(t_lower, ",[[:space:]]")) next
        if (str_detect(text, "^\\d{2}/\\d{2}/\\d{4}\\s*\\d{2}h")) next
        if (str_detect(text, "^\\d{1,2}/\\d{1,2}/\\d{4}$")) next
      }
      if (tag %in% c("h2", "h3")) {
        lines <- c(lines, paste0("\n## ", text, "\n"))
      } else if (tag == "li") {
        lines <- c(lines, paste0("• ", text))
      } else {
        lines <- c(lines, text)
      }
    }
    if (length(lines) > 1) {
      mask   <- c(TRUE, lines[-1] != lines[-length(lines)])
      lines <- lines[mask]
    }
    if (length(lines) == 0) return(NA_character_)
    paste(lines, collapse = "\n\n")
  }

  # Author cleaning ("Por", suffixes and ", g1" removed)
  clean_author <- function(author) {
    if (is.na(author) || nchar(trimws(author)) == 0) return(NA_character_)
    author <- trimws(author)
    author <- str_remove(author, regex("^por\\s+", ignore_case = TRUE))
    author <- str_remove(author, "\\s*[—-]\\s*.*$")
    author <- str_remove(author, ",\\s*g1.*$")
    trimws(author)
  }

  # Article type: "Coluna de Opinião" for blog posts, otherwise "Notícia"
  define_type <- function(title, lead, url) {
    text <- tolower(paste(title, lead, url, collapse = " "))
    if (str_detect(text, "blog do|blog da|blog de")) return("Coluna de Opinião")
    return("Notícia")
  }

  # ---------------------------------------------------------------------------
  # Helper: scrape one article
  # ---------------------------------------------------------------------------
  scrape_article <- function(url, b) {
    tryCatch({
      b$Page$navigate(url)
      b$Page$loadEventFired()
      Sys.sleep(2)
      html_src <- b$Runtime$evaluate("document.documentElement.outerHTML")$result$value
      html     <- read_html(html_src)

      # Title (excluded formats are skipped)
      title <- html %>% html_node("h1.content-head__title, h1") %>% html_text(trim = TRUE)
      title <- trimws(title)
      if (is_excluded_format(title, url)) {
        message("    EXCLUDED (format): ", title)
        return(NULL)
      }

      # Lead
      lead <- html %>% html_node("h2.content-head__subtitle, h2") %>% html_text(trim = TRUE)
      if (length(lead) == 0 || is.na(lead)) lead <- NA_character_

      # Body
      body <- extract_body(html)

      # Relevance filter (title + lead + body)
      full_text <- paste(title, lead, body, collapse = " ")
      if (!contains_required_pairs(full_text)) {
        message("    SKIPPED (terms): ", url)
        return(NULL)
      }

      # Publication date (first <time> element)
      pub_date <- html %>% html_node("time") %>% html_attr("datetime")
      if (is.na(pub_date))
        pub_date <- html %>% html_node("time") %>% html_text(trim = TRUE)
      pub_date_fmt <- tryCatch({
        format(parse_date_time(pub_date,
                               orders = c("ymd HMS z","ymd HMSz","ymd HM","dmy HM")), "%d/%m/%Y")
      }, error = function(e) NA_character_)

      # Author
      author <- html %>%
        html_node(".content-publication-data__from, [class*='author'], .byline, address") %>%
        html_text(trim = TRUE)
      author <- clean_author(author)

      # Article type
      type <- define_type(title, lead, url)

      tibble(
        `Data de Publicação` = pub_date_fmt,
        `Tipo de Matéria`    = type,
        `Título`             = title,
        `Lead`               = lead,
        `Corpo do Texto`     = body,
        `Autoria`            = author,
        `Data de Extração`   = EXTRACTION_DATE,
        `Link`               = url
      )

    }, error = function(e) { message("    ERROR: ", e$message); NULL })
  }

  # ---------------------------------------------------------------------------
  # Main loop: one search per day, 1–12 Sep 2025
  # ---------------------------------------------------------------------------
  # Each day is searched separately (03:00 UTC to 02:59 UTC the next day,
  # i.e. midnight to midnight in Brasília time), restricted to news items.
  search_dates <- seq(STUDY_START, STUDY_END, by = "day")
  all_results <- list()
  use_brave()
  b <- ChromoteSession$new()

  for (search_day in as.list(search_dates)) {
    search_day <- as.Date(search_day)
    message("\n========== ", format(search_day, "%d/%m/%Y"), " ==========")

    from_enc <- paste0(format(search_day,           "%Y-%m-%d"), "T03%3A00%3A00.000Z")
    to_enc   <- paste0(format(search_day + days(1), "%Y-%m-%d"), "T02%3A59%3A59.999Z")

    search_url <- paste0(
      "https://g1.globo.com/busca/?q=bolsonaro+julgamento+golpista",
      "&species=noticias",
      "&from=", from_enc, "&to=", to_enc
    )

    message("Opening: ", search_url)
    b$Page$navigate(search_url)
    b$Page$loadEventFired()
    Sys.sleep(3)

    scroll_to_end(b)

    html_src <- b$Runtime$evaluate("document.documentElement.outerHTML")$result$value
    cards    <- extract_search_cards(html_src)
    message("Links found: ", nrow(cards))
    if (nrow(cards) == 0) next

    day_results <- list()

    for (i in seq_len(nrow(cards))) {
      article_url <- cards$link[i]
      message("  [", i, "/", nrow(cards), "] ", article_url)

      article <- scrape_article(article_url, b)
      if (!is.null(article)) day_results[[length(day_results) + 1]] <- article

      Sys.sleep(runif(1, 1.5, 2.5))
    }

    if (length(day_results) > 0) {
      day_df <- bind_rows(day_results)
      all_results[[as.character(search_day)]] <- day_df
      message("Articles saved: ", nrow(day_df))
    }
  }

  b$close()
  message("G1 session closed.")

  if (length(all_results) == 0) {
    message("G1: no articles found.")
    return(empty_corpus())
  }

  final_df <- bind_rows(all_results) %>% distinct(Link, .keep_all = TRUE)
  message("G1: ", nrow(final_df), " articles extracted")
  return(final_df)
}

