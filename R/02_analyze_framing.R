# =============================================================================
# 02_analyze_framing.R — Framing scores and classification of each article
# -----------------------------------------------------------------------------
#
# Steps:
#   1. Load the framing dictionary.
#   2. Remove quoted text to keep the "newspaper's voice".
#   3. Count pro and anti terms; compute the raw score and framing index.
#   4. Classify each article.
#   5. Summarise the results per outlet.
# =============================================================================

source("R/setup.R")

sample_375 <- readRDS(file.path(DIR_PROCESSED, "sample_375.rds"))


# -----------------------------------------------------------------------------
# 1. Framing dictionary
# -----------------------------------------------------------------------------
# Pro-trial terms frame the trial as legitimate (e.g. "golpe de estado").
# Anti-trial terms frame it as illegitimate (e.g. "perseguição política").

dictionary <- read.csv(DICTIONARY_FILE, fileEncoding = "UTF-8")

terms_pro  <- dictionary$term[dictionary$direction == "pro"]
terms_anti <- dictionary$term[dictionary$direction == "anti"]

cat("Pro-trial terms:", length(terms_pro), "\n")    # 27
cat("Anti-trial terms:", length(terms_anti), "\n")  # 30


# -----------------------------------------------------------------------------
# 2. The "newspaper's voice": remove quoted text
# -----------------------------------------------------------------------------
# Goal: separate what the newspaper says from what its sources say.
# Text between quotation marks is removed.

sample_375 <- sample_375 %>%
  mutate(
    text_lower = tolower(text),
    text_no_quotes = str_remove_all(text_lower, "\u201c[^\u201d]*\u201d"),
    text_no_quotes = str_remove_all(text_no_quotes, '"[^"]*"'),         
    text_voice = text_no_quotes
  )


# -----------------------------------------------------------------------------
# 3. Term counts and scores
# -----------------------------------------------------------------------------
# Raw score     = pro - anti (depends on text length)
# Framing index = (pro - anti) / (pro + anti), from -1 (anti) to +1 (pro);
#                 NA when the article has no framing terms.


count_terms <- function(texts, terms) {
  counts <- sapply(terms, function(t) str_count(texts, fixed(t)))
  if (is.matrix(counts)) rowSums(counts) else counts
}

framing_scores <- sample_375 %>%
  select(id, outlet, text_lower, text_voice) %>%
  mutate(
    # Full text (quotes included)
    pro_full       = count_terms(text_lower, terms_pro),
    anti_full      = count_terms(text_lower, terms_anti),
    raw_score_full = pro_full - anti_full,
    index_full     = case_when(
      pro_full == 0 & anti_full == 0 ~ NA_real_,
      TRUE ~ (pro_full - anti_full) / (pro_full + anti_full)
    ),
    
    # Newspaper's voice (quotes removed)
    pro_voice       = count_terms(text_voice, terms_pro),
    anti_voice      = count_terms(text_voice, terms_anti),
    raw_score_voice = pro_voice - anti_voice,
    framing_index   = case_when(
      pro_voice == 0 & anti_voice == 0 ~ NA_real_,
      TRUE ~ (pro_voice - anti_voice) / (pro_voice + anti_voice)
    ),
    
    # -------------------------------------------------------------------------
    # 4. Classification (based on the newspaper's voice)
    # -------------------------------------------------------------------------
    framing = case_when(
      pro_voice == 0 & anti_voice == 0 ~ "Neutral (factual)",
      raw_score_voice > 0              ~ "Favourable to the trial",
      raw_score_voice < 0              ~ "Contrary to the trial",
      TRUE                             ~ "Balanced (pro = anti)"
    )
  )

saveRDS(framing_scores, file.path(DIR_PROCESSED, "framing_scores.rds"))

write.csv(select(framing_scores, -text_lower, -text_voice),
          file.path(DIR_TABLES, "article_scores.csv"),
          row.names = FALSE, fileEncoding = "UTF-8")


# -----------------------------------------------------------------------------
# 5. Results per outlet
# -----------------------------------------------------------------------------

save_table <- function(table, file_name) {
  write.csv(table, file.path(DIR_TABLES, file_name),
            row.names = FALSE, fileEncoding = "UTF-8")
}

# Share of each framing category per outlet
framing_by_outlet <- framing_scores %>%
  group_by(outlet, framing) %>%
  summarise(n = n(), .groups = "drop") %>%
  group_by(outlet) %>%
  mutate(pct = round(n / sum(n) * 100, 1)) %>%
  arrange(outlet, framing)

print(framing_by_outlet, n = Inf)
save_table(framing_by_outlet, "framing_by_outlet.csv")

# Average scores and framing index per outlet
scores_by_outlet <- framing_scores %>%
  group_by(outlet) %>%
  summarise(
    pro_mean        = round(mean(pro_voice), 2),
    anti_mean       = round(mean(anti_voice), 2),
    raw_score_mean  = round(mean(raw_score_voice), 2),
    framing_index   = round(mean(framing_index, na.rm = TRUE), 3),
    .groups = "drop"
  ) %>%
  arrange(desc(framing_index))

print(scores_by_outlet)
save_table(scores_by_outlet, "scores_by_outlet.csv")

# Counts and shares of each category per outlet
coverage_summary <- framing_scores %>%
  group_by(outlet) %>%
  summarise(
    total            = n(),
    n_neutral        = sum(framing == "Neutral (factual)"),
    pct_neutral      = round(n_neutral / total * 100, 1),
    n_favourable     = sum(framing == "Favourable to the trial"),
    pct_favourable   = round(n_favourable / total * 100, 1),
    n_contrary       = sum(framing == "Contrary to the trial"),
    pct_contrary     = round(n_contrary / total * 100, 1),
    n_balanced       = sum(framing == "Balanced (pro = anti)"),
    pct_balanced     = round(n_balanced / total * 100, 1),
    .groups = "drop"
  ) %>%
  arrange(desc(pct_neutral))

print(coverage_summary, width = Inf)
save_table(coverage_summary, "coverage_summary.csv")

# Share of each framing category across all outlets
framing_overall <- framing_scores %>%
  count(framing) %>%
  mutate(pct = round(n / sum(n) * 100, 1)) %>%
  arrange(desc(n))

print(framing_overall)
save_table(framing_overall, "framing_overall.csv")

# Full text vs newspaper's voice
full_text_vs_voice <- framing_scores %>%
  group_by(outlet) %>%
  summarise(
    raw_score_full  = round(mean(raw_score_full), 2),
    raw_score_voice = round(mean(raw_score_voice), 2),
    index_full      = round(mean(index_full, na.rm = TRUE), 3),
    index_voice     = round(mean(framing_index, na.rm = TRUE), 3),
    .groups = "drop"
  )

print(full_text_vs_voice)
save_table(full_text_vs_voice, "full_text_vs_newspaper_voice.csv")