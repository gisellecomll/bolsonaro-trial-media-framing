# =============================================================================
# scrape_agencia_brasil.R — Collect articles from Agência Brasil (OPTIONAL)
# -----------------------------------------------------------------------------
# Collect articles about the trial from Agência Brasil using the EBC search
# page, rendered in Brave through chromote.
#
# Steps:
#   1. Search busca.ebc.com.br for "julgamento de Bolsonaro" (1–12 Sep 2025),
#      result pages 0 to 35.
#   2. Keep links to Agência Brasil news sections only.
#   3. Extract date, type, title, lead, body and author from each article.
#   4. Remove non-editorial lines from the body (social links, calls to
#      action, "Leia também", sharing and feedback blocks).
#   5. Keep articles whose title or lead mention the trial or Bolsonaro.
#
# Output columns keep their original Portuguese names (spreadsheet format).
#
# Browser: this scraper opens pages in Brave through chromote, using the Brave
# configuration in web_scraping_setup.R. It was developed and run with Brave
# only; to use another browser, adjust that configuration first.
# =============================================================================

if (!exists("read_html_brave")) source("R/scraping/web_scraping_setup.R")

scrape_agencia_brasil <- function() {
  message("\n", strrep("=", 60))
  message("SCRAPING — AGÊNCIA BRASIL")
  message(strrep("=", 60))

  # Start a chromote session in Brave
  use_brave()
  b <- ChromoteSession$new()
  b$Page$navigate("about:blank")
  Sys.sleep(1)
  message("Chromote session started for Agência Brasil.")


  # ---------------------------------------------------------------------------
  # Helper: collect article links from one search results page
  # ---------------------------------------------------------------------------
  extract_search_links <- function(page_num = 0, session = b) {
    cat("\nCollecting page:", page_num, "\n")
    search_url <- paste0(
      "https://busca.ebc.com.br/nodes?utf8=%E2%9C%93",
      "&start_date=01%2F09%2F2025",
      "&end_date=12%2F09%2F2025",
      "&site_id=agenciabrasil",
      "&q=julgamento+de+Bolsonaro",
      "&commit=Aplicar",
      "&page=", page_num
    )
    page <- read_html_brave(search_url, session)
    if (is.null(page)) return(character(0))
    links <- page %>%
      html_elements("a") %>%
      html_attr("href")
    links <- links[!is.na(links)]
    links <- links[str_detect(links, "agenciabrasil\\.ebc\\.com\\.br")]
    links <- links[!str_detect(links, "radioagencia|tvbrasil|pdf|/tags/")]
    links <- ifelse(
      str_detect(links, "^http"),
      links,
      paste0("https://agenciabrasil.ebc.com.br", links)
    )
    unique(links)
  }


  # ---------------------------------------------------------------------------
  # Helper: remove non-editorial lines from the body
  # ---------------------------------------------------------------------------
  # Lines with ">>" that point to social media or calls to action, and lines
  # with sharing, "Leia também", privacy or feedback text.
  remove_junk_lines <- function(lines) {
    junk_with_arrow <- str_detect(lines, ">>") &
      str_detect(lines, regex(
        paste0(
          "whatsapp|telegr|instagram|facebook|twitter|youtube|",
          "clique aqui|acompanhe ao vivo|assista ao vivo|ao vivo|",
          "siga o canal|siga a cobertura|acesse o canal|",
          "receba nossas|ative as notifica|assine|newsletter"
        ),
        ignore_case = TRUE
      ))
    junk_without_arrow <- str_detect(lines, regex(
      paste0(
        "Compartilhe|Leia também|Edição:|",
        "cookies|Política de Privacidade|Fala\\.BR|",
        "Ouvidoria|Dê sua opinião|Escolha sua manifestação|",
        "Você será direcionado|Sua opinião ajuda"
      ),
      ignore_case = TRUE
    ))
    lines[!(junk_with_arrow | junk_without_arrow)]
  }


  # ---------------------------------------------------------------------------
  # Helper: scrape one article
  # ---------------------------------------------------------------------------
  scrape_article <- function(link, session = b) {
    cat("\nExtracting:", link, "\n")
    page <- read_html_brave(link, session)
    if (is.null(page)) return(NULL)

    # Title
    title <- page %>% html_element("h1") %>% html_text2()
    if (length(title) == 0 || is.na(title)) title <- NA

    # Lead
    lead <- page %>% html_element(".linha-fina-noticia") %>% html_text2()
    if (length(lead) == 0 || is.na(lead)) lead <- NA

    # Publication date (dd/mm/yyyy)
    pub_date <- page %>%
      html_elements("meta[property='article:published_time']") %>%
      html_attr("content")
    if (length(pub_date) == 0) {
      pub_date <- page %>%
        html_elements("time") %>%
        html_attr("datetime")
    }
    pub_date <- if (length(pub_date) == 0) NA else pub_date[1]
    if (!is.na(pub_date)) {
      pub_date <- format(as.Date(substr(pub_date, 1, 10)), "%d/%m/%Y")
    }

    # Author (text before " - ")
    author <- page %>% html_element(".autor-noticia") %>% html_text2()
    if (length(author) == 0 || is.na(author)) {
      author <- NA
    } else {
      author <- str_trim(author)
      author <- str_split(author, " - ", simplify = TRUE)[, 1]
      author <- str_trim(author)
    }

    # Article type: "Opinião" if the section label mentions opinion,
    # otherwise "Notícia"
    type_raw <- page %>%
      html_elements(".editoria, .categoria, .channel, .tipo-materia, .label-opiniao") %>%
      html_text2()
    type_raw <- str_trim(type_raw[type_raw != ""])
    type <- if (
      length(type_raw) > 0 &&
      any(str_detect(str_to_lower(type_raw), "opinião|opinion|coluna|editorial|artigo"))
    ) {
      "Opinião"
    } else {
      "Notícia"
    }

    # Body: remove page elements that are not part of the article, then keep
    # paragraphs, subheadings (## ) and list items (- )
    article <- page %>%
      html_element("article, .content, .field-item, .content__text")

    if (!is.null(article)) {
      junk_selectors <- c(
        "#barraManifestacao", ".eouv-manifestacoes", ".d-print-none",
        ".compartilhe", ".tags", ".related", "script", "style",
        "nav", "footer", "header"
      )
      for (selector in junk_selectors) {
        nodes <- html_elements(article, selector)
        xml_remove(nodes)
      }

      nodes <- article %>% html_elements("p, h2, li")
      body_parts <- nodes %>%
        map_chr(function(node) {
          tag <- html_name(node)
          txt <- html_text2(node)
          txt <- str_trim(txt)
          if (nchar(txt) == 0) return(NA_character_)
          if (tag == "h2") return(paste0("## ", txt))
          if (tag == "li") return(paste0("- ", txt))
          return(txt)
        })
      body_parts <- body_parts[!is.na(body_parts)]
      body_parts <- body_parts[nchar(body_parts) > 5]
      body_parts <- remove_junk_lines(body_parts)
      body <- if (length(body_parts) == 0) NA else paste(body_parts, collapse = "\n\n")
    } else {
      body <- NA
    }

    tibble(
      `Data de Publicação` = pub_date,
      `Tipo`               = type,
      `Título`             = title,
      `Lead`               = lead,
      `Corpo do Texto`     = body,
      `Autoria`            = author,
      `Data de Extração`   = EXTRACTION_DATE,
      `Link`               = link
    )
  }


  # ---------------------------------------------------------------------------
  # Helpers: relevance filter (title + lead, accents removed)
  # ---------------------------------------------------------------------------
  normalise <- function(x) {
    x %>%
      str_to_lower() %>%
      stri_trans_general("Latin-ASCII")
  }

  contains_pair <- function(text, p1, p2) {
    str_detect(text, p1) & str_detect(text, p2)
  }

  is_relevant <- function(title, lead) {
    field <- paste(
      ifelse(is.na(title), "", title),
      ifelse(is.na(lead),  "", lead)
    )
    field <- normalise(field)
    contains_pair(field, "julgamento", "bolsonaro") |
      contains_pair(field, "bolsonaro",  "golpista")  |
      contains_pair(field, "julgamento", "golpista")  |
      str_detect(field, "\\bgolpe\\b")                |
      str_detect(field, "\\bbolsonaro\\b")            |
      str_detect(field, "\\bgolpista\\b")             |
      str_detect(field, "ex-presidente")
  }


  # ---------------------------------------------------------------------------
  # 1. Collect links from all search pages
  # ---------------------------------------------------------------------------
  cat("\n===============================\n")
  cat("COLLECTING LINKS — AGÊNCIA BRASIL\n")
  cat("===============================\n")

  all_links <- c()
  for (i in 0:35) {
    page_links <- extract_search_links(i, b)
    all_links <- c(all_links, page_links)
    Sys.sleep(1)
  }
  all_links <- unique(all_links)
  all_links <- all_links[
    str_detect(all_links,
               "/noticia/|/politica/|/justica/|/geral/|/economia/|/internacional/")
  ]
  cat("\nTOTAL LINKS FOUND:", length(all_links), "\n")


  # ---------------------------------------------------------------------------
  # 2. Scrape every article
  # ---------------------------------------------------------------------------
  cat("\n===============================\n")
  cat("EXTRACTING ARTICLES — AGÊNCIA BRASIL\n")
  cat("===============================\n")

  articles <- map_dfr(
    all_links,
    ~ tryCatch(
      scrape_article(.x, b),
      error = function(e) {
        cat("\nERROR:", .x, "\n")
        return(NULL)
      }
    )
  )


  # ---------------------------------------------------------------------------
  # 3. Final cleaning and relevance filter
  # ---------------------------------------------------------------------------
  # Remove duplicates, turn empty strings into NA, drop articles without title.
  articles <- articles %>%
    distinct() %>%
    mutate(across(everything(), ~ ifelse(. == "", NA, .))) %>%
    filter(!is.na(`Título`))

  n_before <- nrow(articles)
  articles <- articles %>%
    filter(is_relevant(`Título`, `Lead`))
  n_after <- nrow(articles)
  cat("\n--- RELEVANCE FILTER ---\n")
  cat("Articles before filter : ", n_before, "\n")
  cat("Articles after filter  : ", n_after,  "\n")
  cat("Removed                : ", n_before - n_after, "\n")

  # Close the browser session
  b$close()
  message("Agência Brasil session closed.")

  # Standard column names
  articles <- articles %>%
    rename(`Tipo de Matéria` = `Tipo`) %>%
    mutate(`Data de Extração` = EXTRACTION_DATE)

  message("Agência Brasil: ", nrow(articles), " articles extracted")
  return(articles)
}
