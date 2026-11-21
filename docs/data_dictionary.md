# Data Dictionary

This document describes the data files, columns and outputs in this repository. Files in `data/processed/`, `outputs/tables/` and `outputs/figures/` are created by `run_all.R`; they appear in the repository after the scripts have been run.

| Folder | Contents | Created by |
|---|---|---|
| `data/raw/` | Original spreadsheet of scraped articles | Web scraping (original study) |
| `data/dictionaries/` | Framing dictionary | Authors |
| `data/processed/` | Cleaned corpus, sample and framing scores | `R/01_prepare_data.R`, `R/02_analyze_framing.R` |
| `outputs/tables/` | Results tables (CSV) | `R/01` to `R/03` |
| `outputs/figures/` | Figures (PNG) | `R/04_create_figures.R` |
| `data/scraped/` | Spreadsheets from new scraping runs | `R/scraping/run_scraping.R` |

## 1. Original spreadsheet

**File:** `data/raw/news_corpus_2025-09-01_2025-09-12.xlsx`

One sheet per outlet, 1,189 articles in total:

| Sheet | Articles |
|---|---|
| G1 | 203 |
| Agência Brasil | 75 |
| BBC | 94 |
| Metrópoles | 327 |
| CNN Brasil | 490 |

Each sheet has the same eight columns. Column names are in Portuguese, as in the original data.

| Column | Meaning | Notes |
|---|---|---|
| `Data de Publicação` | Publication date | Text in dd/mm/yyyy format. One BBC date is stored as an Excel date instead. 6 CNN Brasil articles have no date. |
| `Tipo de Matéria` | Article type | Values in the spreadsheet: "Notícia" (news) for all outlets; also "Coluna de Opinião" (opinion column) for Metrópoles (47 articles) and "Coluna/Opinião" for CNN Brasil (56 articles). 6 CNN Brasil articles have no type. |
| `Título` | Title | |
| `Lead` | Lead (subtitle) | Empty for all BBC articles and for 6 CNN Brasil articles. |
| `Corpo do Texto` | Body text | Empty for 57 G1 and 6 CNN Brasil articles. |
| `Autoria` | Author | Empty for 20 CNN Brasil articles and 1 G1 article. 4 Metrópoles articles contain the text "NA" instead of an empty value. |
| `Data de Extração` | Date the article was scraped | dd/mm/yyyy. One date per outlet: G1 21/05/2026, Agência Brasil 24/05/2026, BBC 25/05/2026, Metrópoles 26/05/2026, CNN Brasil 27/05/2026. |
| `Link` | Article URL | G1 links are search-tracking URLs that redirect to the original articles, rather than direct article URLs. |

Four BBC articles are dated 30–31 August 2025, before the study period (see `methodology.md`, Section 10).

## 2. Framing dictionary

**File:** `data/dictionaries/framing_dictionary.csv` (57 terms)

| Column | Meaning |
|---|---|
| `term_id` | Number of the term (1–57) |
| `term` | Term in Portuguese, lower case, as searched for in the text |
| `direction` | `pro` (27 terms: frame the trial as legitimate) or `anti` (30 terms: frame it as illegitimate) |
| `category` | Sub-group of the term (see below) |
| `gloss_en` | English translation |

| `category` | Direction | Terms that… |
|---|---|---|
| `asserts_crime` | pro | state that a crime took place (e.g. *golpe de estado*) |
| `legitimises_conviction` | pro | support the conviction (e.g. *condenação*) |
| `procedural_legitimacy` | pro | use the legal vocabulary of the process (e.g. *réu*) |
| `delegitimises_trial` | anti | question the trial's legitimacy (e.g. *perseguição política*) |
| `victimises_defendant` | anti | portray the defendant as a victim (e.g. *preso político*) |
| `attacks_process` | anti | attack the institutions or the process (e.g. *ativismo judicial*) |

Only `term` and `direction` are used in the calculations.

## 3. Cleaned corpus and sample

**Files:** in `data/processed/`

| File | Rows | Content |
|---|---|---|
| `corpus_clean.rds` / `.csv` | Articles with body text | All articles that have body text |
| `sample_375.rds` / `.csv` | 375 | 75 articles per outlet, selected at random with seed 42 |

The `.rds` files are read by the next scripts; the `.csv` files are copies for viewing. Both files have the same columns:

| Column | Meaning |
|---|---|
| `id` | Unique article ID: outlet code + number, e.g. `AB_001`. Codes: `AB` Agência Brasil, `BBC` BBC, `CNN` CNN Brasil, `G1` G1, `MET` Metrópoles. Numbers follow the row order of each sheet. |
| `outlet` | Outlet (sheet name) |
| The eight original columns | As in Section 1 |
| `text` | Title and body text joined with a space |

## 4. Framing scores

**Files:** `data/processed/framing_scores.rds` and `outputs/tables/article_scores.csv`

One row per sampled article (375 rows). `framing_scores.rds` also contains the two text columns; `article_scores.csv` contains everything else.

| Column | Meaning |
|---|---|
| `id`, `outlet` | Article ID and outlet |
| `text_lower` | Title + body, lower case (`framing_scores.rds` only) |
| `text_voice` | `text_lower` with text inside quotation marks removed: the "newspaper's voice" (`framing_scores.rds` only) |
| `pro_full`, `anti_full` | Number of pro-trial and anti-trial terms in the full text |
| `raw_score_full` | `pro_full − anti_full` |
| `index_full` | Framing index on the full text: `(pro − anti) / (pro + anti)`, from −1 to +1; empty if the article has no terms |
| `pro_voice`, `anti_voice` | Number of pro-trial and anti-trial terms in the newspaper's voice |
| `raw_score_voice` | `pro_voice − anti_voice` |
| `framing_index` | Framing index on the newspaper's voice (main measure); empty if no terms |
| `framing` | Category: "Favourable to the trial", "Contrary to the trial", "Balanced (pro = anti)" or "Neutral (factual)" |

## 5. Results tables

**Folder:** `outputs/tables/`. Percentages are rounded to one decimal place. Unless stated otherwise, scores use the newspaper's voice.

### From `R/01_prepare_data.R`

| File | Columns | Content |
|---|---|---|
| `corpus_diagnostics.csv` | `outlet`, `total`, `empty_body`, `with_body` | Number of articles with and without body text per outlet |

### From `R/02_analyze_framing.R`

| File | Columns | Content |
|---|---|---|
| `article_scores.csv` | See Section 4 | Scores and category of each sampled article |
| `framing_by_outlet.csv` | `outlet`, `framing`, `n`, `pct` | Number and percentage of articles in each category, per outlet |
| `scores_by_outlet.csv` | `outlet`, `pro_mean`, `anti_mean`, `raw_score_mean`, `framing_index` | Average number of pro and anti terms, average raw score and average framing index per outlet |
| `coverage_summary.csv` | `outlet`, `total`, `n_` and `pct_` for `neutral`, `favourable`, `contrary`, `balanced` | Counts and percentages of each category per outlet, in one row |
| `framing_overall.csv` | `framing`, `n`, `pct` | Number and percentage of articles in each category, all outlets together |
| `full_text_vs_newspaper_voice.csv` | `outlet`, `raw_score_full`, `raw_score_voice`, `index_full`, `index_voice` | Average raw score and framing index per outlet, with and without quotes |

### From `R/03_analyze_text.R`

| File | Columns | Content |
|---|---|---|
| `term_frequency.csv` | `term`, `direction`, `freq_full`, `freq_voice` | Total count of each dictionary term in the full text and in the newspaper's voice |
| `term_frequency_by_outlet.csv` | `term`, `direction`, `outlet`, `n` | Count of each term per outlet (newspaper's voice) |
| `kwic_pro.csv`, `kwic_anti.csv` | `id`, `outlet`, `context` | Occurrences of five selected pro or five selected anti terms, each with up to five words before and after (full text). Overlapping occurrences may appear only once. |
| `top_bigrams.csv` | `outlet`, `bigram`, `n` | Five most frequent two-word phrases per outlet (more if tied), excluding stopwords, numbers and one-letter words |
| `top_trigrams.csv` | `outlet`, `trigram`, `n` | Five most frequent three-word phrases per outlet (more if tied), with the same exclusions |
| `key_trigrams.csv` | `outlet`, `trigram`, `n` | Counts of four key phrases ("golpe de estado", "tentativa de golpe", "defesa da democracia", "ameaça à democracia"), before stopword removal |

## 6. Figures

**Folder:** `outputs/figures/` (PNG, 300 dpi). Files starting with `figure_` correspond to the figures in the paper; files starting with `additional_` are extra charts produced by the original script.

| File | Content |
|---|---|
| `figure_1_framing_by_outlet.png` | Percentage of articles in each framing category, per outlet |
| `figure_2_framing_index_full_vs_voice.png` | Average framing index per outlet, full text vs newspaper's voice |
| `figure_3_top_framing_terms.png` | Ten most frequent pro and anti terms (newspaper's voice) |
| `figure_4_framing_terms_heatmap.png` | Use of each term per outlet (heatmap) |
| `figure_5_framing_index_distribution.png` | Distribution of the framing index per outlet (box plots) |
| `additional_1_framing_by_outlet_stacked.png` | Framing categories per outlet, stacked bars |
| `additional_2_framing_index_by_outlet.png` | Average framing index per outlet |
| `additional_3_pro_vs_anti_terms.png` | Average number of pro vs anti terms per article, per outlet |
| `additional_4_raw_score_full_vs_voice.png` | Average raw score per outlet, full text vs newspaper's voice |
| `additional_5_key_trigrams.png` | Counts of the four key phrases per outlet |