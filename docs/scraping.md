# Web Scraping

This document describes how the articles were collected from the five outlets and how to run the scraping scripts in `R/scraping/`.

**Scraping is optional.** The analysis (`run_all.R`) uses the original spreadsheet in `data/raw/` and does not need the scrapers. Running them today might not recreate that spreadsheet, because the websites, their search results and their page layouts change over time.

## Files

| File | Purpose |
|---|---|
| `web_scraping_setup.R` | Shared helpers: Brave configuration, page loading, HTTP requests, pauses, extraction date, empty output table |
| `scrape_agencia_brasil.R` | Agência Brasil scraper |
| `scrape_bbc.R` | BBC News Brasil scraper |
| `scrape_cnn.R` | CNN Brasil scraper |
| `scrape_g1.R` | G1 scraper |
| `scrape_metropoles.R` | Metrópoles scraper |
| `run_scraping.R` | Runs all five scrapers and saves the spreadsheet |

## Overview of the five scrapers

| Outlet | Method | Browser | Source of articles | Period set by | Relevance filter |
|---|---|---|---|---|---|
| Agência Brasil | `chromote` | Brave | EBC search for "julgamento de Bolsonaro" | Search date filter | Title + lead (broad) |
| BBC News Brasil | `chromote` | Brave | BBC Portuguese topic page | Card dates + check of each article's original publication date | Title + lead + body, 7 word pairs |
| CNN Brasil | HTTP (`httr`) | None | Tag page `julgamento-bolsonaro` | Listing dates | None (tag page) |
| G1 | `chromote` | Brave | G1 internal search for "bolsonaro julgamento golpista", one day at a time | Daily search windows only | Title + lead + body, 3 word pairs |
| Metrópoles | HTTP (`httr`) + WordPress API | None | Tag `julgamento-de-bolsonaro-no-stf` | Each article's publication date | None (tag) |

The study period is 1–12 September 2025 (`STUDY_START` and `STUDY_END` in `R/setup.R`).

## Browser requirements

The original scraping was developed and run with the **Brave** browser, and the code reflects this configuration.

- **Agência Brasil, BBC and G1** open pages in Brave through `chromote`, because their pages load content with JavaScript. The browser is set by `use_brave()` in `web_scraping_setup.R`, which looks for Brave in its default install locations. If Brave is installed elsewhere, set its path before running: `BRAVE_PATH <- "C:/path/to/brave.exe"`.
- **CNN Brasil and Metrópoles** do not open a browser; they download pages over HTTP. They load `web_scraping_setup.R` only for shared helpers. Brave is not needed to run them.

The scrapers have only been run with Brave. Users who prefer another browser may need to adjust the browser configuration in `web_scraping_setup.R`. `chromote` requires a Chromium-based browser, but other browsers have not been tested.

## Output format

Each scraper returns a table with the same eight columns, in this order. The names are in Portuguese because they are the column names of the original spreadsheet, which the analysis reads.

| Column | Content |
|---|---|
| `Data de Publicação` | Publication date (dd/mm/yyyy, date only) |
| `Tipo de Matéria` | Article type (labels vary by outlet; see below) |
| `Título` | Title |
| `Lead` | Lead (subtitle) |
| `Corpo do Texto` | Body text |
| `Autoria` | Author |
| `Data de Extração` | Date the article was scraped (dd/mm/yyyy, date only) |
| `Link` | Article URL |

Article type labels: Agência Brasil uses "Notícia" / "Opinião"; CNN Brasil uses "Notícia" / "Coluna/Opinião"; BBC, G1 and Metrópoles use "Notícia" / "Coluna de Opinião".

## Outlet details

### Agência Brasil

- **Collection:** EBC search (`busca.ebc.com.br`) for "julgamento de Bolsonaro", limited to 01/09/2025–12/09/2025, result pages 0 to 35 (36 pages).
- **Links kept:** Agência Brasil article links in news sections (`/noticia/`, `/politica/`, `/justica/`, `/geral/`, `/economia/`, `/internacional/`). Radio, TV, PDF and tag links are dropped.
- **Cleaning:** feedback bars, sharing blocks, tags, related links, menus, headers, footers and scripts are removed from the page. Lines with social media links, calls to action, newsletter invitations, "Leia também", "Compartilhe", privacy and feedback text are dropped, as are lines of five characters or fewer. Photo captions and image credits are not specifically removed.
- **Relevance filter:** applied to the title and lead only. It is broad: an article passes if it contains "bolsonaro", "golpe", "golpista" or "ex-presidente" on its own, so no pair of words is actually required.
- **Other:** duplicates and articles without a title are removed. No separate check of each article's date is made; the period comes from the search filter.

### BBC News Brasil

- **Collection:** the BBC Portuguese topic page (`bbc.com/portuguese/topics/cg7267qv6q0t`), page by page. The date of each card is read from its `<time>` element, skipping dates marked "atualizado" (updated). Cards dated in the period, and cards without a date, are scraped. Collection stops after the first page containing a card dated before 1 September.
- **Excluded formats:** titles or links containing "resumão", "resumo do dia", "em um minuto", "em 1 minuto", "podcast", "quero ver de novo", "o que voce precisa saber", "newsday" or "mundo em fotos".
- **Body:** read from the page as displayed in the browser, using JavaScript, stopping at related-content blocks. If that fails, the page's HTML is read directly after removing related, promotional, newsletter, caption and tag elements. Articles whose body is empty or contains only headings (likely videos) are skipped.
- **Flourish charts:** the heading of each embedded Flourish chart is read and **added to the body text**, at the chart's position when known. (An earlier draft of the paper described these charts as excluded; the code includes their headings.)
- **Cleaning:** lines with photo credits, captions, agency credits (Getty, Reuters, AFP, EPA, AP), calls to action, "Leia também", live-coverage notices, dates and bylines are dropped.
- **Relevance filter:** title + lead + body must contain at least one of seven pairs: julgamento + bolsonaro, bolsonaro + golpista, julgamento + golpista, processo + bolsonaro, golpe + bolsonaro, stf + bolsonaro, julgamento + stf.
- **Date check:** each article's **original publication date** (not the update date) is checked, and articles published outside 1–12 September are skipped.
- **Sheet name:** `run_scraping.R` saves this outlet's sheet as **"BBC"**, matching the original spreadsheet, so a newly scraped file can be read by `01_prepare_data.R`. The original script named this sheet "BBC Brasil".

### CNN Brasil

- **Collection:** plain HTTP requests to the tag page `cnnbrasil.com.br/tudo-sobre/julgamento-bolsonaro/`, up to 58 listing pages. Links dated in the period are kept, and collection stops at the first item dated before 1 September. Tag, author, live-coverage (`/ao-vivo`) and blog index links are skipped.
- **Browser:** none. CNN Brasil does not require Brave. It relies on shared helpers from `web_scraping_setup.R` (HTTP requests with browser-like headers, pauses and the extraction date).
- **Date:** taken from the page's publication-date tag, then the `<time>` element, then the date shown on the listing page.
- **Cleaning:** minimal. Lines shorter than 10 characters, "Publicado por" lines and repeated consecutive lines are dropped; bodies shorter than 50 characters are left empty. Captions, credits, calls to action and related-article blocks are not specifically removed.
- **Relevance filter:** none; the tag page is limited to the trial.
- **Pages that cannot be downloaded:** a row containing only the link and the extraction date is still kept, with the other fields empty. This can result in articles with an empty body.

### G1

- **Collection:** G1's internal search for "bolsonaro julgamento golpista", restricted to news items, run **one day at a time** from 1 to 12 September (midnight to midnight, Brasília time). Each results page is scrolled until no more results load.
- **Period:** defined **only by the daily search windows**. There is no additional check of each article's publication date.
- **Excluded formats:** titles or links containing "resumão", "resumao", "resumo do dia", "em um minuto", "em 1 minuto", "podcast", "quero ver de novo" or "o que você precisa saber". Live coverage ("ao vivo") is **not** excluded as a format; only lines mentioning it are removed from the body.
- **Cleaning:** related-content blocks, newsletter and subscription boxes, banners, sidebars, semantic tags, photo captions, embedded media and summary cards are removed. Lines with calls to action, "Leia também", photo and image credits, live-coverage notices, dates and bylines are dropped, as are list items that contain only links and repeated lines. Text after a "resumo do dia" / "resumão" heading is skipped.
- **Relevance filter:** title + lead + body must contain at least one of three pairs: julgamento + bolsonaro, bolsonaro + golpista, julgamento + golpista.
- **Empty bodies:** if no body text is found, the article is still kept when its title or lead passes the relevance filter. This can result in articles with an empty body.

### Metrópoles

- **Collection:** the WordPress API (`metropoles.com/wp-json/news/content`) is used to **get the list of article links** for the tag `julgamento-de-bolsonaro-no-stf`, 10 posts per page, up to 100 pages. Paging stops at the first post dated before 1 September. Each article page is then downloaded and read as HTML.
- **Browser:** none. Metrópoles does not require Brave. It sends its own HTTP requests and uses `web_scraping_setup.R` only for shared helpers (pauses and the extraction date).
- **Date check:** each article's date is taken from the `<time>` element, then the page's publication-date tag, then the page's structured data (JSON-LD). Articles without a date, or dated outside 1–12 September, are skipped.
- **Cleaning:** lines with calls to action, newsletter and Telegram invitations, "Leia também", "Saiba mais", sharing text and ads are dropped, as are paragraphs shorter than 25 characters. Photo captions and image credits are not specifically removed.
- **Relevance filter:** none; the tag is limited to the trial.
- **Missing values:** a missing lead or author is stored as the **text "NA"**, not as an empty value. This is why some Metrópoles cells in the spreadsheet contain "NA".
- **Bug fix:** in the original code, an article page with no body text caused the function to stop early (`return()` inside the body step), which would interrupt the entire Metrópoles run. The code now stores the body as `NA` and keeps the article's other fields.

## Differences between the code and the original spreadsheet

The spreadsheet in `data/raw/` was not produced by a single run of `run_scraping.R` in its current form:

- Each sheet has a different extraction date (21–27 May 2026), so the outlets were scraped on different days.
- One BBC publication date is stored as an Excel date rather than as text.
- **Four BBC articles** in the spreadsheet were originally published on 30–31 August 2025 and updated on 1 September. The BBC scraper checks each article's original publication date and should skip articles published before 1 September, so these four would not be expected in its output. Their origin is not known. They were kept in the analysis, as in the original study. They can be identified by their publication dates (30/08/2025 and 31/08/2025) in the BBC sheet of the original spreadsheet in `data/raw/`.

## Requirements

- **R packages:** `chromote`, `rvest`, `xml2`, `httr`, `stringr`, `stringi`, `dplyr`, `purrr`, `tibble`, `lubridate`, `jsonlite`, `glue`, `openxlsx` (listed in `PACKAGES_SCRAPING` in `R/setup.R`). If a package is missing, the scripts stop and print the install command.
- **stringr 1.5.0 or later:** the Metrópoles scraper uses `str_extract(..., group = 1)`, which requires this version.
- **Brave browser** for Agência Brasil, BBC and G1 (see above).

## How to run

1. Open `bolsonaro-trial-media-framing.Rproj` in RStudio, so the working directory is the repository root.
2. Run all five scrapers:

   ```r
   source("R/scraping/run_scraping.R")
   ```

   The scrapers run in order: Agência Brasil, BBC, CNN Brasil, G1, Metrópoles. If one stops with an error or finds no articles, a warning is printed and the others still run.

3. The spreadsheet is saved to `data/scraped/scraped_corpus_YYYYMMDD.xlsx`, with one sheet per outlet (sheet names match the original spreadsheet). Outlets with no articles get no sheet. The original spreadsheet in `data/raw/` is never overwritten, and `data/scraped/` is excluded from Git.

To run a single scraper:

```r
source("R/scraping/scrape_cnn.R")   # loads the setup and helpers if needed
cnn <- scrape_cnn()
```

To analyse a newly scraped spreadsheet instead of the original one, change `RAW_CORPUS_FILE` in `R/setup.R` to its path. The results will differ from the paper, because the collected articles will differ.
