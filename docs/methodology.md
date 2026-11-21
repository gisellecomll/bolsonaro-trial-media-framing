# Methodology 

This document summarises the research behind this repository and explains how the analysis is carried out in the R scripts. It is based on the paper *Uma análise de enquadramento do julgamento do 8 de janeiro de 2023* (A framing analysis of the January 8th 2023 trial), written for the Quantitative Methods course at the Federal University of Pernambuco (UFPE), 2026, by Arthur Alves, Emmanuel Henrique, Giselle Pinheiro, Luisa Ferramola and Marcelo Augusto.

## 1. Research question

In September 2025, Brazil's Supreme Federal Court (STF) tried former president Jair Bolsonaro and seven other defendants for their role in the attempted coup linked to the 8 January 2023 attacks. This study asks:

- **How did Brazilian news outlets frame the trial?** 
- **Did this framing vary between outlets?**

Two hypotheses guide the analysis:

- **H1:** The outlets show a tendency to frame the trial favourably.
- **H2:** There is significant variation in framing across the outlets analysed.

## 2. Data

### 2.1 Outlets

The study analyses five Brazilian news outlets: Agência Brasil, BBC News Brasil, CNN Brasil, G1 and Metrópoles. They were chosen for their relevance in spreading political and economic information, as they are free to access and reach a national audience, and for the feasibility of collecting their articles.

### 2.2 Study period

1–12 September 2025, covering the days before the trial sessions, the sessions themselves and the final verdict.

### 2.3 Collection

Articles were collected by web scraping in R, with a separate procedure for each outlet, since each website is built differently:

| Outlet | Source of articles |
|---|---|
| Agência Brasil | EBC search for "julgamento de Bolsonaro", limited to the study period |
| BBC News Brasil | BBC Portuguese topic page on the trial |
| CNN Brasil | CNN Brasil tag page for the trial |
| G1 | G1 search for "bolsonaro julgamento golpista", one day at a time |
| Metrópoles | Metrópoles tag for the trial, through the site's WordPress API |
  
  For each article, eight fields were saved: publication date, article type (news or opinion), title, lead, body text, author, extraction date and link. For most outlets, non-editorial text in the body, such as calls to action, newsletter invitations and "Leia também" (read also) links, was removed during collection. The amount of cleaning differs by outlet (see Section 10). The outlets were scraped on different days, between 21 and 27 May 2026.

Technical details for each outlet are in [`scraping.md`](scraping.md). The scraping code is not needed to reproduce the analysis. The collected articles are provided in `data/raw/`.

### 2.4 Inclusion and exclusion

The collection was designed to include news articles and opinion pieces about the trial published in the study period. In practice, the rules differ between outlets:
  
  - **Study period:** set by the search date filter (Agência Brasil), by the daily search windows (G1), by the dates on the listing pages (CNN Brasil), or by a check of each article's publication date (BBC News Brasil and Metrópoles).
- **Relevance to the trial:**
  - CNN Brasil and Metrópoles rely on their trial tag pages, with no extra filter.
  - BBC News Brasil and G1 keep only articles whose title, lead and body contain certain pairs of words, such as *julgamento* + *bolsonaro* ("trial" + "Bolsonaro").
  - Agência Brasil checks only the title and lead, with a broad filter that accepts any mention of Bolsonaro or of words such as *golpe* ("coup").
- **Excluded formats:** BBC News Brasil and G1 exclude daily summaries, podcasts and similar formats by title or link. BBC News Brasil also skips articles with no text (likely videos), and CNN Brasil skips live coverage pages. Agência Brasil keeps only links to its news sections.
- **Articles without body text:** these are not always removed during collection. They are removed before sampling, in `R/01_prepare_data.R` (see Section 3).

### 2.5 Corpus

The original spreadsheet contains **1,189 articles in total** across the five outlets: Agência Brasil 75, BBC News Brasil 94, CNN Brasil 490, G1 203 and Metrópoles 327.

## 3. Sample

The outlets published very different numbers of articles, so a balanced sample was drawn:

1. Articles without body text are removed.
2. **75 articles per outlet** are selected at random, using `set.seed(42)` so the selection can be repeated, giving a **total of 375 articles**.

The number 75 was chosen because Agência Brasil published only 75 articles in the period. Selecting the same number from each outlet makes the outlets directly comparable.

## 4. Framing dictionary

The analysis uses two dictionaries created by the authors, based on their knowledge of the Brazilian political context (`data/dictionaries/framing_dictionary.csv`). All terms are in Portuguese, with English translations in the file.

| Dictionary | Terms | What the terms do |
|---|---|---|
| **Pro-trial** | 27 | Assert that a crime took place, legitimise the judicial process or support the conviction (e.g. *golpe de estado*, "coup d'état"; *condenação*, "conviction") |
| **Anti-trial** | 30 | Question the trial's legitimacy, portray the defendant as a victim or attack the institutions involved (e.g. *perseguição política*, "political persecution"; *farsa*, "sham") |

## 5. Text preparation: the "newspaper's voice"

A news article mixes the newspaper's own words with quotes from its sources. A source quoted as calling the trial "political persecution" says nothing about how the newspaper itself frames it. To focus on the newspaper's own words, which the study calls the **newspaper's voice**:
  
  1. The title and body text are combined and converted to lower case.
2. All text between **curly quotation marks (“ ”)** and **straight quotation marks (" ")** is removed.

The main results are based on this quote-free text. Scores are also calculated on the full text, quotes included, for comparison.

## 6. Scoring

For each article, the number of pro-trial and anti-trial terms is counted. Two scores are then calculated:
  
  - **Raw score** = pro − anti. Simple, but longer articles tend to have larger scores.
- **Framing index** = (pro − anti) / (pro + anti). It ranges from **−1** (fully anti-trial) to **+1** (fully pro-trial), with 0 meaning balance. Because it does not depend on article length, it is the main measure. If an article contains no dictionary terms, the index is left empty (`NA`).

## 7. Classification

Each article is classified using its newspaper's voice:

| Category | Rule |
|---|---|
| **Favourable to the trial** | More pro-trial than anti-trial terms |
| **Contrary to the trial** | More anti-trial than pro-trial terms |
| **Balanced (pro = anti)** | Equal numbers of pro and anti terms (at least one of each) |
| **Neutral (factual)** | No dictionary terms: the article only reports facts |

## 8. Complementary analyses

To help interpret the results, the scripts also produce:

- the frequency of each dictionary term, overall and per outlet (shown as a heatmap);
- keywords in context: each selected term with up to five words on either side;
- the most frequent two- and three-word phrases per outlet, after removing common Portuguese words (stopwords), numbers and one-letter words.

## 9. Main findings

The results below are those **reported in the paper**. Running `run_all.R` with R 4.5.3 and dplyr 1.2.1 reproduced all numerical results reported in the paper (see Section 11).

| Outlet | Favourable | Neutral | Balanced | Contrary |
|---|---|---|---|---|
| Agência Brasil | 100% | 0% | 0% | 0% |
| BBC News Brasil | 92.0% | 5.3% | 2.7% | 0% |
| CNN Brasil | 94.7% | 4.0% | 0% | 1.3% |
| G1 | 98.7% | 1.3% | 0% | 0% |
| Metrópoles | 94.7% | 4.0% | 0% | 1.3% |

- **H1 is supported.** More than 95% of the articles were framed favourably to the trial. Every outlet framed most of its coverage favourably, and anti-trial terms were rare.
- **Framing index:** On the full text, the average index ranged from **0.798** (BBC News Brasil) to **0.914** (G1). In the newspaper's voice, it rose slightly in every outlet, ranging from **0.861** (BBC News Brasil) to **0.939** (Metrópoles). Removing quotes therefore changed the results only a little.
- **Consistency:** For every outlet, the middle 50% of articles had an index of about 0.75 or higher, with medians close to 1. The favourable framing is a consistent pattern, not the result of a few extreme articles.
- **H2:** The data point to variation between the outlets, although this variation is very small. Agência Brasil and G1 were the most uniform. BBC News Brasil and Metrópoles varied more internally, and CNN Brasil and Metrópoles had a few strongly contrary articles.
- **Vocabulary:** The most frequent terms are mostly legal vocabulary, such as *condenação* ("conviction"). Among anti-trial terms, only *absolvição* ("acquittal") appeared noticeably in several outlets; terms such as *farsa* ("sham") or *injusto* ("unjust") appeared only occasionally.

## 10. Limitations

- **Quote removal only covers quotation marks.** Reported speech without quotation marks (e.g. "the defence argued that the trial was unfair") stays in the newspaper's voice and may affect the scores.
- **Overlapping term counts.** Terms are counted as plain text matches, without word boundaries. A term that appears inside a longer term or word is counted too. For example, *réus* ("defendants") also counts as *réu* ("defendant"), and *perseguição política* ("political persecution") also counts as *perseguição* ("persecution").
- **BBC articles outside the study period.** Four BBC News Brasil articles in the spreadsheet were originally published on 30–31 August 2025 and updated on 1 September. The BBC scraper checks each article's original publication date and would be expected to skip them, so how they entered the spreadsheet is not known. They were kept, as in the original analysis, so they may be part of the sample. They can be identified by their publication dates (30/08/2025 and 31/08/2025) in the BBC sheet of the original spreadsheet in data/raw/.
- **Different text cleaning per outlet.** Each outlet's pages contain different non-editorial elements, so the cleaning steps were adapted to each one. Photo captions and image credits are only removed for BBC News Brasil and G1. CNN Brasil required little cleaning. For BBC News Brasil, the headings of embedded charts are kept in the body.
- **Collection dates.** The outlets were scraped on different days (21–27 May 2026), several months after the trial. The text collected is the version online at that time, which may include later updates, and articles removed before then could not be collected.
- **Dictionary scope.** The dictionaries were built specifically for this case and may not transfer to other topics or periods. A dictionary approach also cannot capture context or framing expressed without these terms.
- **Scope of the conclusions.** The study measures framing in the outlets' text, not its effect on public opinion. The results apply only to these five outlets and this period.

## 11. Reproducibility status

The analysis can be re-run from the provided spreadsheet with `run_all.R`. It uses the same data, cleaning rule, seed and sampling procedure as the original analysis. Running `run_all.R` with R 4.5.3 and dplyr 1.2.1 reproduced all numerical results reported in the paper.