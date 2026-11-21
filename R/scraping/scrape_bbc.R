# =============================================================================
# scrape_bbc.R — Collect articles from BBC News Brasil (OPTIONAL)
# -----------------------------------------------------------------------------
# Collect articles about the trial from the BBC News Brasil topic page,
# rendered in Brave through chromote.
#
# Steps:
#   1. Go through the topic page, page by page, reading each card's date.
#   2. Scrape cards dated 1–12 Sep 2025 (and cards without a date); stop after
#      the first page with a card dated before the study period.
#   3. For each article: skip excluded formats, extract the body, add the
#      headings of Flourish charts, and remove non-editorial lines.
#   4. Keep articles whose text contains a required pair of words.
#   5. Skip articles whose original publication date is outside the period.
#
# Output columns keep their original Portuguese names (spreadsheet format).
#
# Browser: this scraper opens pages in Brave through chromote, using the Brave
# configuration in web_scraping_setup.R. It was developed and run with Brave
# only; to use another browser, adjust that configuration first.
# =============================================================================

if (!exists("read_html_brave")) source("R/scraping/web_scraping_setup.R")

scrape_bbc <- function() {
  message("\n", strrep("=", 60))
  message("SCRAPING — BBC BRASIL")
  message(strrep("=", 60))

  # Helper: relevance filter. The text (title + lead + body) passes if it
  # contains at least one of seven pairs of words.
  contains_required_pairs <- function(text) {
    text <- tolower(as.character(text))
    text[is.na(text)] <- ""
    sapply(text, function(x) {
      par1 <- str_detect(x, "julgamento") & str_detect(x, "bolsonaro")
      par2 <- str_detect(x, "bolsonaro")  & str_detect(x, "golpista")
      par3 <- str_detect(x, "julgamento") & str_detect(x, "golpista")
      par4 <- str_detect(x, "processo")   & str_detect(x, "bolsonaro")
      par5 <- str_detect(x, "golpe")      & str_detect(x, "bolsonaro")
      par6 <- str_detect(x, "stf")        & str_detect(x, "bolsonaro")
      par7 <- str_detect(x, "julgamento") & str_detect(x, "stf")
      par1 | par2 | par3 | par4 | par5 | par6 | par7
    })
  }

  # Helper: formats excluded by title or link (summaries, podcasts, etc.)
  is_excluded_format <- function(title, url) {
    title_lower <- tolower(as.character(title))
    url_lower    <- tolower(as.character(url))
    patterns <- c("resumão","resumo do dia","em um minuto",
                 "em 1 minuto","podcast","quero ver de novo",
                 "o que voce precisa saber", "newsday", "mundo em fotos")
    any(str_detect(title_lower, patterns)) | any(str_detect(url_lower, patterns))
  }

  # Helper: non-editorial lines (credits, captions, calls to action,
  # "Leia também", live-coverage notices, dates, bylines)
  is_junk_text <- function(text) {
    t <- tolower(trimws(text))
    if (nchar(t) == 0) return(TRUE)
    t_norm <- iconv(t, from = "UTF-8", to = "ASCII//TRANSLIT")
    t_norm <- tolower(trimws(t_norm %||% t))
    patterns <- c(
      "^credito[,\\s]","^credito da foto","^credito da imagem",
      "^image credit","^photo credit",
      "^leia (tambem|também|tambem)\\b","^veja (tambem|também|tambem)\\b",
      "^saiba mais (sobre|aqui)$","^para se inscrever",
      "noticias que voce nao pode perder",
      "^siga a bbc","^acompanhe a bbc","^receba as principais noticias",
      "^baixe o aplicativo","^assine",
      "^fim do","fim do content","fim do mais lidas","mais lidas$",
      "reproducao deste formato de video nao e compativel",
      "nao e compativel com seu dispositivo",
      "^legenda da foto","^legenda:",
      "^foto\\s*:","^imagem\\s*:","^creditos?\\s*:",
      "^©\\s*","^reproducao$","^reproducao\\s*[/—-]",
      "bbc nao se responsabiliza","politica em relacao a links externos",
      "getty images","reuters$","^bbc$",
      "^bbc (brasil|news brasil|news)$",
      "^todos os direitos reservados",
      "acompanhe aqui","assista ao vivo","transmitir ao vivo","ao vivo\\b",
      "^\\d{2}/\\d{2}/\\d{4}",
      "atualizado\\s+\\d{2}/\\d{2}",
      "\\d{2}h\\d{2}\\s*(atualizado|—|$)",
      "^por [a-z]",
      "^carregando\\.?$","^carregando\\.\\.\\.\\.$",
      "tempo de leitura",
      "play video","play video","duration \\d",
      "^epa$","^afp$","^ap$","^reuters$","^getty$","^getty images$",
      "^[a-z ]{2,30}\\s*/\\s*(epa|afp|ap|reuters|getty)\\s*$",
      "^clique aqui$","^acesse aqui$","^saiba mais$",
      "^leia a materia$","^leia a reportagem$","^veja a materia$",
      "^assista aqui$","^ouca aqui$","^veja o video$","^assista ao video$"
    )
    any(sapply(patterns, function(p) str_detect(t_norm, p)))
  }

  # Helper: article links on a topic page, each with the date shown on its card
  # (the first <time> not marked "atualizado")
  extract_cards_with_dates <- function(html_src) {
    html <- tryCatch(read_html(html_src), error = function(e) NULL)
    if (is.null(html)) return(tibble(link = character(0), card_date = as.Date(character(0))))
    link_nodes <- html %>% html_nodes("a[href]")
    links <- character(0)
    dates <- as.Date(character(0))
    for (node in link_nodes) {
      href <- html_attr(node, "href")
      if (is.na(href)) next
      if (!grepl("bbc\\.com/portuguese/articles/|^/portuguese/articles/", href)) next
      full_url <- if (grepl("^http", href)) href else paste0("https://www.bbc.com", href)
      found_date <- NA
      current_node <- node
      for (level in 1:5) {
        current_node <- tryCatch(xml_parent(current_node), error = function(e) NULL)
        if (is.null(current_node)) break
        time_nodes <- tryCatch(
          xml_find_all(current_node, ".//time[@datetime]"),
          error = function(e) NULL
        )
        if (is.null(time_nodes) || length(time_nodes) == 0) next
        chosen_time <- NULL
        for (tn in time_nodes) {
          txt_tn <- tolower(trimws(xml_text(tn)))
          if (!str_detect(txt_tn, "atualizado")) {
            chosen_time <- tn
            break
          }
        }
        if (is.null(chosen_time)) chosen_time <- time_nodes[[1]]
        dt_str <- xml_attr(chosen_time, "datetime")
        found_date <- tryCatch(as.Date(dt_str), error = function(e) NA)
        if (!is.na(found_date)) break
      }
      links <- c(links, full_url)
      dates <- c(dates, found_date)
    }
    if (length(links) == 0)
      return(tibble(link = character(0), card_date = as.Date(character(0))))
    df <- tibble(link = links, card_date = dates)
    df <- df[!duplicated(df$link), ]
    df
  }

  # Helpers: author name (read from the rendered page) and its cleaning
  extract_author_js <- function(b) {
    js <- "(function() {
    var el = document.querySelector('span.css-eiglm1');
    if (el) {
      var txt = (el.innerText || '').trim();
      if (txt.length > 0 && txt.length < 80) return txt;
    }
    var roleSpans = document.querySelectorAll('span[role=\"text\"]');
    for (var i = 0; i < roleSpans.length; i++) {
      var children = Array.from(roleSpans[i].querySelectorAll('span'));
      for (var j = 0; j < children.length; j++) {
        var txt = (children[j].innerText || '').trim();
        var lc  = txt.toLowerCase();
        if (txt.length > 0 && txt.length < 80 &&
            !/^(author|por|by|role|editor|reporter|published|da bbc|bbc news)[,\\s]/i.test(lc) &&
            !/^\\d/.test(txt)) {
          return txt;
        }
      }
    }
    var sels = ['[class*=\"author-name\"]','[class*=\"byline-name\"]',
                '[class*=\"AuthorName\"]','[itemprop=\"author\"] [itemprop=\"name\"]',
                '[itemprop=\"author\"]'];
    for (var s = 0; s < sels.length; s++) {
      var node = document.querySelector(sels[s]);
      if (node) {
        var txt = (node.innerText || '').trim().split('\\n')[0].trim();
        txt = txt.replace(/^(por|by)\\s+/i, '').trim();
        if (txt.length > 0 && txt.length < 80) return txt;
      }
    }
    return '';
  })();"
    raw <- tryCatch(b$Runtime$evaluate(js)$result$value, error = function(e) "")
    trimws(raw %||% "")
  }

  clean_author <- function(author) {
    if (is.na(author) || nchar(trimws(author)) == 0) return(NA_character_)
    author <- trimws(author)
    author <- str_remove(author, regex("^por\\s+", ignore_case = TRUE))
    author <- str_remove(author, "\\s*[—-]\\s*.*$")
    author <- str_remove(author, ",\\s*(bbc|g1).*$")
    author <- trimws(author)
    lc <- tolower(author)
    if (str_detect(lc, "^(bbc|bbc news|bbc news brasil|bbc brasil|brasil|news brasil)$")) {
      return(NA_character_)
    }
    if (nchar(author) <= 4 && !str_detect(author, "[A-ZÁÉÍÓÚÀÂÊÔÃÕÇ]")) {
      return(NA_character_)
    }
    author
  }

  # Helper: article type from title, lead and link
  define_type <- function(title, lead, url) {
    text <- tolower(paste(title, lead, url, collapse = " "))
    if (str_detect(text, "opinion|colunistas|analise|analysis|opiniao|coluna"))
      return("Coluna de Opinião")
    return("Notícia")
  }

  # Helpers: Flourish charts (iframes). The heading of each chart is read and
  # added to the body text.
  collect_flourish_srcs <- function(b) {
    js <- "(function() {
    var srcs = [];
    document.querySelectorAll('iframe').forEach(function(f) {
      var src = f.src || f.getAttribute('src') || '';
      if (/flo\\.uri\\.sh|flourish/i.test(src)) srcs.push(src);
    });
    return JSON.stringify(srcs);
  })();"
    raw  <- tryCatch(b$Runtime$evaluate(js)$result$value, error = function(e) "[]")
    srcs <- tryCatch(jsonlite::fromJSON(raw), error = function(e) character(0))
    srcs[nchar(srcs) > 0]
  }

  extract_flourish_text <- function(b, srcs_flourish, page_url) {
    if (length(srcs_flourish) == 0) return(character(0))
    texts <- character(0)
    for (src in srcs_flourish) {
      tryCatch({
        message("    Opening Flourish chart: ", src)
        b$Page$navigate(src)
        b$Page$loadEventFired()
        Sys.sleep(4)
        b$Runtime$evaluate("window.scrollTo(0, document.body.scrollHeight)")
        Sys.sleep(2)
        b$Runtime$evaluate("window.scrollTo(0, 0)")
        Sys.sleep(1)
        js_f <- "(function() {
        var h2s = document.querySelectorAll('h2');
        for (var i = 0; i < h2s.length; i++) {
          var txt = (h2s[i].innerText || h2s[i].textContent || '').trim();
          if (txt.length > 0) return txt;
        }
        return '';
      })();"
        txt <- tryCatch(b$Runtime$evaluate(js_f)$result$value, error = function(e) "")
        txt <- trimws(txt %||% "")
        if (nchar(txt) > 0) {
          message("    Flourish heading found: ", txt)
          texts <- c(texts, paste0("\n## ", txt, "\n"))
        }
      }, error = function(e) {
        message("    WARNING Flourish (", src, "): ", e$message)
      })
    }
    # Go back to the original article page
    tryCatch({
      b$Page$navigate(page_url)
      b$Page$loadEventFired()
      Sys.sleep(2)
      b$Runtime$evaluate("window.scrollTo(0, document.body.scrollHeight)")
      Sys.sleep(3)
      b$Runtime$evaluate("window.scrollTo(0, 0)")
      Sys.sleep(1)
    }, error = function(e) NULL)
    texts
  }

  # Helper: article body. The rendered page is read with JavaScript, stopping at
  # related-content blocks; if that fails, the static HTML is read with rvest,
  # after removing related, promo, newsletter, caption and tag elements.
  extract_body <- function(html, b = NULL) {
    if (!is.null(b)) {
      js_body <- "(function() {

      var container =
        document.querySelector('main') ||
        document.querySelector('article[class]') ||
        document.querySelector('[class*=\"story-body__inner\"]') ||
        document.querySelector('[class*=\"story-body\"]') ||
        document.querySelector('[class*=\"article__body\"]') ||
        document.querySelector('article') ||
        null;

      if (!container) return JSON.stringify([]);

      var results = [];
      var limiteY = Infinity;

      function offsetTopAbs(el) {
        var top = 0;
        while (el && el !== document.body) {
          top += el.offsetTop || 0;
          el = el.offsetParent;
        }
        return top;
      }

      limiteY = Infinity;
      container.querySelectorAll(
        '[class*=\"related\"], [class*=\"topics\"], [class*=\"more-stories\"],' +
        '[class*=\"tag-list\"], [class*=\"story-footer\"], [class*=\"share\"],' +
        '[data-component=\"links-block\"], [data-component=\"see-alsos\"],' +
        'section[class*=\"related\"]'
      ).forEach(function(el) {
        var top = offsetTopAbs(el);
        if (top > 0 && top < limiteY) limiteY = top;
      });

      container.querySelectorAll('p, li').forEach(function(el) {
        var top = offsetTopAbs(el);
        if (limiteY < Infinity && top >= limiteY) return;
        var tag = el.tagName.toLowerCase();
        var txt = (el.innerText || '').trim();
        if (!txt) return;
        if (tag === 'li') {
          var anchors = el.querySelectorAll('a');
          var linkTxt = Array.from(anchors).map(function(a){ return (a.innerText||'').trim(); }).join(' ').trim();
          var livre   = txt.replace(linkTxt,'').replace(/[^\\w]/g,'').trim();
          if (!livre) return;
          if (txt.length < 60 && anchors.length > 0 && linkTxt.length > 0) {
            var ratio = linkTxt.length / txt.length;
            if (ratio >= 0.85) return;
          }
        }
        if (/^(author|role|published|da bbc|bbc news brasil)[,\\s\\n]/i.test(txt)) return;
        if (/^(author|role|published)\\s*$/i.test(txt)) return;
        if (/^\\d{1,2}\\s+(janeiro|fevereiro|marco|abril|maio|junho|julho|agosto|setembro|outubro|novembro|dezembro)\\s+\\d{4}$/i.test(txt)) return;
        if (/^\\d{1,2}\\/\\d{1,2}\\/\\d{4}/.test(txt)) return;
        if (/tempo de leitura/i.test(txt)) return;
        if (/play v.?deo|duration\\s+\\d/i.test(txt)) return;
        if (/^clique aqui$/i.test(txt)) return;
        if (tag === 'li') {
          var lines = txt.split('\\n').map(function(l){ return l.trim(); }).filter(Boolean);
          if (lines.length <= 2) {
            var ultima = lines[lines.length - 1];
            if (/^\\d{1,2}\\s+\\w+\\s+\\d{4}$/.test(ultima)) return;
            if (/^ha \\d+/i.test(ultima)) return;
          }
        }
        results.push({ tag: tag, text: txt, order: top });
      });

      var todosH = document.querySelectorAll('h2[id], h3[id], h2[tabindex], h3[tabindex], article h2, article h3, main h2, main h3');
      var h2h3Vistos = {};
      todosH.forEach(function(el) {
        var txt = (el.innerText || '').trim();
        if (!txt || h2h3Vistos[txt]) return;

        if (/tópicos relacionados|assista|histórias relacionadas|mais clicadas|principais notícias|leia mais|veja também/i.test(txt)) return;

        var noArtigo   = container.contains(el);
        var temId      = el.hasAttribute('id') && el.getAttribute('id').length > 0;
        var temTabIdx  = el.hasAttribute('tabindex');

        if (!noArtigo && !temId && !temTabIdx) return;

        var top = offsetTopAbs(el);
        if (noArtigo && limiteY < Infinity && top >= limiteY) return;

        h2h3Vistos[txt] = true;
        results.push({ tag: el.tagName.toLowerCase(), text: txt, order: top });
      });

      var iframes = document.querySelectorAll('iframe');
      for (var i = 0; i < iframes.length; i++) {
        var src = iframes[i].src || '';
        if (/flo\\.uri\\.sh|flourish/i.test(src)) {
          var top = offsetTopAbs(iframes[i]);
          results.push({ tag: '_flourish_marker_', text: '__FLOURISH__', order: top });
          break;
        }
      }

      results.sort(function(a, b){ return a.order - b.order; });
      var seen = {};
      results = results.filter(function(r) {
        var key = r.tag + '|' + r.text;
        if (seen[key]) return false;
        seen[key] = true;
        return true;
      });

      return JSON.stringify(results);
    })();"

      raw    <- tryCatch(b$Runtime$evaluate(js_body)$result$value, error = function(e) "[]")
      js_nodes <- tryCatch(jsonlite::fromJSON(raw), error = function(e) NULL)

      if (!is.null(js_nodes) && is.data.frame(js_nodes) && nrow(js_nodes) > 0) {
        lines        <- character(0)
        seen_texts <- character(0)
        inside_summary <- FALSE
        PLACEHOLDER   <- "__FLOURISH_INJECT__"

        for (k in seq_len(nrow(js_nodes))) {
          tag   <- js_nodes$tag[k]
          text <- trimws(js_nodes$text[k])
          if (nchar(text) == 0) next

          if (tag == "_flourish_marker_") {
            lines <- c(lines, PLACEHOLDER); next
          }
          if (tag %in% c("h2","h3") && str_detect(tolower(text), "resumo do dia|resumão")) {
            inside_summary <- TRUE; next
          }
          if (inside_summary) next
          if (is_junk_text(text)) next
          if (tag == "p") {
            t_lower <- tolower(text)
            if (nchar(text) < 120 && str_detect(t_lower, "\\bbbc\\b") && str_detect(t_lower, ",[[:space:]]")) next
            if (str_detect(text, "^\\d{2}/\\d{2}/\\d{4}\\s*\\d{2}h")) next
            if (str_detect(text, "^\\d{1,2}/\\d{1,2}/\\d{4}$")) next
          }
          if (text %in% seen_texts) next
          seen_texts <- c(seen_texts, text)

          if (tag %in% c("h2","h3")) {
            lines <- c(lines, paste0("\n## ", text, "\n"))
          } else if (tag == "li") {
            lines <- c(lines, paste0("* ", text))
          } else {
            lines <- c(lines, text)
          }
        }

        return(list(lines = lines, placeholder = PLACEHOLDER))
      }
    }

    # ---- Fallback: read the static HTML with rvest ----
    container_selectors <- c(
      "main",
      "article[class*='article']", ".article__body",
      ".story-body__inner", ".story-body", "article"
    )
    container <- NULL
    for (sel in container_selectors) {
      node <- tryCatch(html %>% html_node(sel), error = function(e) NULL)
      if (!is.null(node) && !inherits(node, "xml_missing") && length(xml_children(node)) > 0) {
        container <- node; break
      }
    }

    if (is.null(container)) {
      fallback_nodes <- html %>% html_nodes("p, h2, h3")
      fallback_lines <- character(0)
      for (node in fallback_nodes) {
        fallback_tag <- html_name(node)
        fallback_txt <- html_text(node, trim = TRUE)
        if (nchar(fallback_txt) == 0 || is_junk_text(fallback_txt)) next
        if (fallback_tag %in% c("h2", "h3")) {
          fallback_lines <- c(fallback_lines, paste0("\n## ", fallback_txt, "\n"))
        } else {
          fallback_lines <- c(fallback_lines, fallback_txt)
        }
      }
      if (length(fallback_lines) == 0) return(list(lines = character(0), placeholder = NULL))
      return(list(lines = fallback_lines, placeholder = NULL))
    }

    xpath_from_css_simple <- function(sel) {
      sel <- trimws(sel)
      if (str_detect(sel, "\\[.*=.*\\]")) {
        m <- str_match(sel, "\\[([^=]+)=['\"]([^'\"]+)['\"]\\]")
        if (!is.na(m[1,1])) return(paste0(".//*[@", m[1,2], "='", m[1,3], "']"))
      }
      parts   <- str_split(sel, "\\.")[[1]]
      tag     <- if (parts[1] == "" || parts[1] == "*") "*" else parts[1]
      classes <- parts[parts != "" & parts != tag]
      if (length(classes) == 0) return(paste0(".//", tag))
      cond <- paste(sapply(classes, function(c)
        paste0("contains(concat(' ',normalize-space(@class),' '),' ", c, " ')")),
        collapse = " and ")
      paste0(".//", tag, "[", cond, "]")
    }

    remove_selectors <- c(
      "[class*='related']","[class*='promo']","[class*='newsletter']","aside",
      ".media-caption__text",".media-caption",
      "[class*='image-block__caption']","[class*='Caption']","figcaption",
      "[class*='tags']","[class*='topics']"
    )
    for (sel in remove_selectors) {
      junk_nodes <- tryCatch(xml_find_all(container, xpath_from_css_simple(sel)), error = function(e) NULL)
      if (is.null(junk_nodes) || length(junk_nodes) == 0) next
      for (node in junk_nodes) tryCatch(xml_remove(node, free = TRUE), error = function(e) NULL)
    }

    nodes <- container %>% html_nodes("p, h2, h3, ul > li, ol > li")
    if (length(nodes) == 0) return(list(lines = character(0), placeholder = NULL))

    lines        <- character(0)
    seen_texts <- character(0)
    inside_summary <- FALSE

    for (node in nodes) {
      tag   <- html_name(node)
      text <- html_text(node, trim = TRUE)
      if (nchar(trimws(text)) == 0) next
      if (tag %in% c("h2","h3") && str_detect(tolower(text), "resumo do dia|resumão")) {
        inside_summary <- TRUE; next
      }
      if (inside_summary) next
      if (is_junk_text(text)) next
      if (tag == "p") {
        t_lower <- tolower(trimws(text))
        if (nchar(text) < 120 && str_detect(t_lower, "\\bbbc\\b") && str_detect(t_lower, ",[[:space:]]")) next
        if (str_detect(text, "^\\d{2}/\\d{2}/\\d{4}\\s*\\d{2}h")) next
        if (str_detect(text, "^\\d{1,2}/\\d{1,2}/\\d{4}$")) next
      }
      key <- trimws(text)
      if (key %in% seen_texts) next
      seen_texts <- c(seen_texts, key)
      if (tag %in% c("h2","h3")) {
        lines <- c(lines, paste0("\n## ", text, "\n"))
      } else if (tag == "li") {
        lines <- c(lines, paste0("* ", text))
      } else {
        lines <- c(lines, text)
      }
    }

    list(lines = lines, placeholder = NULL)
  }

  # ---------------------------------------------------------------------------
  # Helper: scrape one article
  # ---------------------------------------------------------------------------
  scrape_article <- function(url, b) {
    tryCatch({
      b$Page$navigate(url)
      tryCatch({
        b$Page$loadEventFired(timeout_ = 30)
      }, error = function(e) {
        message("    Warning: article timed out, trying to continue...")
      })
      Sys.sleep(2)
      b$Runtime$evaluate("window.scrollTo(0, document.body.scrollHeight)")
      Sys.sleep(3)
      b$Runtime$evaluate("window.scrollTo(0, 0)")
      Sys.sleep(1)

      srcs_flourish <- collect_flourish_srcs(b)
      message("    Flourish iframes found: ", length(srcs_flourish))

      html_src <- b$Runtime$evaluate("document.documentElement.outerHTML")$result$value
      html     <- read_html(html_src)

      # Title (articles without a title or in excluded formats are skipped)
      title <- html %>%
        html_node("h1[id='content'], h1.story-body__h1, h1") %>%
        html_text(trim = TRUE) %>% trimws()
      if (is.na(title) || nchar(title) == 0) {
        message("    SKIPPED (no title): ", url); return(NULL)
      }
      if (is_excluded_format(title, url)) {
        message("    EXCLUDED (format): ", title); return(NULL)
      }

      # Lead
      lead <- html %>%
        html_node(paste(
          "[class*='introduction']", "[class*='story-body__introduction']",
          "[class*='Headline-sc']", ".article__intro", sep = ", ")) %>%
        html_text(trim = TRUE)
      lead <- if (is.null(lead) || is.na(lead) || nchar(trimws(lead)) == 0)
        NA_character_ else trimws(lead)

      # Body
      body_result <- extract_body(html, b)
      body_lines    <- body_result$lines
      placeholder     <- body_result$placeholder

      # Flourish charts: insert each chart's heading into the body, at the
      # chart's position when known, otherwise at the end
      flourish_texts <- extract_flourish_text(b, srcs_flourish, url)

      if (length(flourish_texts) > 0 && !is.null(placeholder) && any(body_lines == placeholder)) {
        idx <- which(body_lines == placeholder)[1]
        body_lines <- c(
          body_lines[seq_len(idx - 1)],
          flourish_texts,
          body_lines[seq(idx + 1, length(body_lines))]
        )
      } else if (length(flourish_texts) > 0) {
        body_lines <- c(body_lines, flourish_texts)
      } else if (!is.null(placeholder)) {
        body_lines <- body_lines[body_lines != placeholder]
      }

      # Skip articles whose body is empty or has only headings (likely videos)
      useful_lines <- body_lines[!grepl("^\\s*##\\s*", body_lines)]
      useful_lines <- useful_lines[!is.na(useful_lines) & nchar(trimws(useful_lines)) > 0]
      if (length(useful_lines) == 0) {
        message("    SKIPPED (empty body or headings only - likely a video): ", url)
        return(NULL)
      }

      body <- paste(body_lines, collapse = "\n\n")

      # Relevance filter (title + lead + body)
      full_text <- paste(title, lead, body, collapse = " ")
      if (!contains_required_pairs(full_text)) {
        message("    SKIPPED (terms): ", url); return(NULL)
      }

      # Original publication date: the first <time> not marked "atualizado"
      # (updated); articles published outside the study period are skipped
      all_times <- html %>% html_nodes("time[datetime]")
      pub_date <- NA_character_
      for (tn in all_times) {
        txt_tn <- tolower(trimws(html_text(tn, trim = TRUE)))
        if (!str_detect(txt_tn, "atualizado")) {
          candidate <- html_attr(tn, "datetime")
          if (!is.na(candidate) && nchar(trimws(candidate)) > 0) {
            pub_date <- candidate
            break
          }
        }
      }
      if (is.na(pub_date) && length(all_times) > 0) {
        for (tn in all_times) {
          candidate <- html_attr(tn, "datetime")
          if (!is.na(candidate) && nchar(trimws(candidate)) > 0) {
            pub_date <- candidate
            break
          }
        }
      }
      if (is.na(pub_date) || nchar(trimws(pub_date)) == 0) {
        pub_date <- html %>%
          html_node("meta[property='article:published_time']") %>%
          html_attr("content")
      }

      orders <- c("ymd HMS z","ymd HMSz","ymd HM","dmy HM","ymd")
      pub_date_fmt <- tryCatch(
        format(parse_date_time(pub_date, orders = orders), "%d/%m/%Y"),
        error = function(e) NA_character_)

      pub_date_value <- tryCatch(
        as.Date(parse_date_time(pub_date, orders = orders)),
        error = function(e) NA
      )
      if (!is.na(pub_date_value) && (pub_date_value < STUDY_START || pub_date_value > STUDY_END)) {
        message("    SKIPPED (published on ", format(pub_date_value, "%d/%m/%Y"),
                ", outside the period): ", url)
        return(NULL)
      }

      # Author and article type
      author_raw <- extract_author_js(b)
      if (nchar(author_raw) == 0) {
        author_raw <- html %>%
          html_node("[class*='author'], [class*='byline'], address, [class*='Contributor']") %>%
          html_text(trim = TRUE) %||% ""
        author_raw <- trimws(strsplit(author_raw, "\n")[[1]][1] %||% "")
      }
      author <- clean_author(author_raw)

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
  # Main collection: go through the topic pages and scrape cards in the period
  # ---------------------------------------------------------------------------
  TOPIC_URL <- "https://www.bbc.com/portuguese/topics/cg7267qv6q0t"

  message("\n========== Collecting links from the BBC Brasil topic page ==========")

  use_brave()
  b <- ChromoteSession$new()

  all_results <- list()
  seen_links  <- character(0)
  page           <- 1

  repeat {
    page_url <- if (page == 1) TOPIC_URL else paste0(TOPIC_URL, "?page=", page)
    message("\n--- Page ", page, ": ", page_url)

    b$Page$navigate(page_url)
    tryCatch({
      b$Page$loadEventFired(timeout_ = 30)
    }, error = function(e) {
      message("  Warning: topic page timed out. Trying to continue...")
    })
    Sys.sleep(3)

    html_src <- b$Runtime$evaluate("document.documentElement.outerHTML")$result$value
    cards    <- extract_cards_with_dates(html_src)

    n_total_cards <- nrow(cards)
    new_cards <- cards[!cards$link %in% seen_links, ]

    if (n_total_cards == 0) {
      message("  No cards found on the page (probably the last page) — stopping.")
      break
    }

    if (nrow(new_cards) == 0) {
      message("  No new cards — stopping.")
      break
    }

    message("  ", nrow(new_cards), " cards found")
    message("  Card dates: ",
            paste(format(new_cards$card_date, "%d/%m/%Y"), collapse = ", "))

    cards_without_date <- new_cards[is.na(new_cards$card_date), ]
    cards_with_date <- new_cards[!is.na(new_cards$card_date), ]

    cards_to_scrape <- rbind(
      cards_with_date[!is.na(cards_with_date$card_date) &
                       cards_with_date$card_date >= STUDY_START &
                       cards_with_date$card_date <= STUDY_END, ],
      cards_without_date
    )

    has_earlier_card <- any(!is.na(cards_with_date$card_date) &
                               cards_with_date$card_date < STUDY_START)

    all_later <- nrow(cards_with_date) > 0 &&
      all(!is.na(cards_with_date$card_date) & cards_with_date$card_date > STUDY_END)

    message("  Cards in the period to scrape: ", nrow(cards_to_scrape))

    if (nrow(cards_to_scrape) > 0) {
      for (i in seq_len(nrow(cards_to_scrape))) {
        article_url <- cards_to_scrape$link[i]
        card_date_str <- if (!is.na(cards_to_scrape$card_date[i]))
          format(cards_to_scrape$card_date[i], "%d/%m/%Y") else "no date"
        message("    Scraping [", i, "/", nrow(cards_to_scrape), "] (card: ",
                card_date_str, "): ", article_url)

        article <- scrape_article(article_url, b)
        if (!is.null(article)) {
          all_results[[length(all_results) + 1]] <- article
        }

        Sys.sleep(runif(1, 1.2, 2.0))
      }
    }

    seen_links <- c(seen_links, new_cards$link)

    if (has_earlier_card) {
      message("  Card earlier than ", format(STUDY_START, "%d/%m/%Y"),
              " found — stopping pagination.")
      break
    }

    if (all_later) {
      message("  All cards are later than the study end date — going to the next page.")
    }

    page <- page + 1
  }

  b$close()
  message("BBC session closed.")

  if (length(all_results) == 0) {
    message("BBC Brasil: no articles found.")
    return(empty_corpus())
  }

  final_df <- bind_rows(all_results) %>% distinct(Link, .keep_all = TRUE)
  message("BBC Brasil: ", nrow(final_df), " articles extracted")
  return(final_df)
}

