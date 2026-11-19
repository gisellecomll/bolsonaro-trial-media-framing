# Media Framing of Jair Bolsonaro's Supreme Court Trial

A quantitative framing analysis, in R, of how five Brazilian news outlets covered the trial of former president Jair Bolsonaro before Brazil's Supreme Federal Court (STF), 1–12 September 2025.

This project was developed for the Quantitative Methods course at the Federal University of Pernambuco (UFPE), 2026.

## Overview

**Research questions**

- How did Brazilian news outlets frame the trial?
- Did this framing vary between outlets?

**Data:** 1,189 articles collected by web scraping from Agência Brasil, BBC News Brasil, CNN Brasil, G1 and Metrópoles. A balanced random sample of 375 articles (75 per outlet) was analysed.

**Method**

1. Text inside quotation marks is removed, to focus on the newspaper's own words (the "newspaper's voice").
2. Each article is scored with two dictionaries created by the authors: 27 pro-trial and 30 anti-trial terms.
3. A framing index, `(pro − anti) / (pro + anti)`, is calculated for each article, from −1 (fully anti-trial) to +1 (fully pro-trial).
4. Each article is classified as favourable, contrary, balanced or neutral.
5. Complementary text analyses: term frequencies, keywords in context, and frequent two- and three-word phrases.

**Main findings (as reported in the paper)**

- More than 95% of the articles were framed favourably to the trial, from 92.0% (BBC News Brasil) to 100% (Agência Brasil).
- The average framing index in the newspaper's voice ranged from 0.861 (BBC News Brasil) to 0.939 (Metrópoles).
- The data point to variation between the outlets, although this variation is very small.

Running `run_all.R` with R 4.5.3 and dplyr 1.2.1 reproduced all numerical results reported in the paper (see [Reproducibility status](#reproducibility-status)).

## Repository structure

```
bolsonaro-trial-media-framing/
├── README.md
├── run_all.R                         # runs the full analysis
├── bolsonaro-trial-media-framing.Rproj
├── R/
│   ├── setup.R                       # packages, parameters and paths
│   ├── 01_prepare_data.R             # load, clean and sample the articles
│   ├── 02_analyze_framing.R          # framing scores and classification
│   ├── 03_analyze_text.R             # term frequencies, keywords in context, phrases
│   ├── 04_create_figures.R           # figures
│   └── scraping/                     # optional: web scrapers for the five outlets
├── data/
│   ├── raw/                          # original spreadsheet of scraped articles
│   ├── dictionaries/                 # framing dictionary
│   └── processed/                    # cleaned corpus, sample and scores (created by the scripts)
├── outputs/
│   ├── tables/                       # results tables (CSV)
│   └── figures/                      # figures (PNG)
└── docs/
    ├── methodology.md                # research summary and methodology
    ├── scraping.md                   # how the articles were collected
    └── data_dictionary.md            # description of files and columns
```

## How to reproduce the analysis

1. Clone or download this repository.
2. Open `bolsonaro-trial-media-framing.Rproj` in RStudio, so the working directory is the repository root.
3. Install the required packages:

   ```r
   install.packages(c("readxl", "dplyr", "tibble", "stringr",
                      "tidyr", "tidytext", "ggplot2"))
   ```

4. Run the full analysis:

   ```r
   source("run_all.R")
   ```

The scripts run in order (`01` to `04`) in the same R session. Tables are saved to `outputs/tables/` and figures to `outputs/figures/`. Each script can also be run on its own, as long as the previous ones have been run at least once.

## Web scraping (optional)

The analysis uses the original spreadsheet in `data/raw/` and does not need web scraping. The scraping scripts in `R/scraping/` are included to document how the articles were collected. Running them today might not recreate the original spreadsheet, because the websites change over time.

**Browser:** the original scraping was developed and run with the **Brave** browser, and the scripts are configured for it. The Agência Brasil, BBC and G1 scrapers open pages in Brave; the CNN Brasil and Metrópoles scrapers download pages directly and do not need a browser. Users who prefer another browser may need to adjust the browser configuration in `R/scraping/web_scraping_setup.R` before running the scrapers. The scrapers have not been tested with other browsers.

See [`docs/scraping.md`](docs/scraping.md) for details and instructions.

## Software environment

The repository was prepared with RStudio 2026.01.2+418, R 4.5.3, dplyr 1.2.1 and stringr 1.6.0.

## Documentation

- [`docs/methodology.md`](docs/methodology.md): research question, data, sampling, dictionary, scoring, classification, findings and limitations.
- [`docs/scraping.md`](docs/scraping.md): collection procedures for each outlet, browser requirements and how to run the scrapers.
- [`docs/data_dictionary.md`](docs/data_dictionary.md): description of the data files, columns, tables and figures.

## Reproducibility status

The analysis uses the same data, cleaning rule, random seed (42) and sampling procedure as the original analysis. Running `run_all.R` with R 4.5.3 and dplyr 1.2.1 reproduced all numerical results reported in the paper.

## Authors

Arthur Alves, Emmanuel Henrique, Giselle Pinheiro, Luisa Ferramola and Marcelo Augusto.

Based on the paper *Uma análise de enquadramento do julgamento do 8 de janeiro de 2023* (A framing analysis of the January 8th 2023 trial), Quantitative Methods course, Federal University of Pernambuco (UFPE), 2026.

## Data note

The articles in `data/raw/` and `data/processed/` were collected from the websites of the five outlets for academic research. The article texts remain the property of their respective publishers.
