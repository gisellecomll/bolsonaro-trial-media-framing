# =============================================================================
# 04_create_figures.R — Figures
# -----------------------------------------------------------------------------
#
# Steps:
#   1. Framing by outlet (grouped and stacked bars).
#   2. Average framing index per outlet and its distribution.
#   3. Most frequent framing terms and their use per outlet.
#   4. Full text vs newspaper's voice.
#   5. Key trigrams.
# =============================================================================

source("R/setup.R")

framing_scores           <- readRDS(file.path(DIR_PROCESSED, "framing_scores.rds"))
term_frequency           <- read.csv(file.path(DIR_TABLES, "term_frequency.csv"),
                                     fileEncoding = "UTF-8")
term_frequency_by_outlet <- read.csv(file.path(DIR_TABLES, "term_frequency_by_outlet.csv"),
                                     fileEncoding = "UTF-8")
key_trigrams             <- read.csv(file.path(DIR_TABLES, "key_trigrams.csv"),
                                     fileEncoding = "UTF-8")

save_figure <- function(plot, file_name, width = 10, height = 6) {
  ggsave(file.path(DIR_FIGURES, file_name), plot,
         width = width, height = height, dpi = 300, bg = "white")
}

framing_colours <- c(
  "Contrary to the trial"   = "#d62728",
  "Balanced (pro = anti)"   = "#ffbb78",
  "Neutral (factual)"       = "#aec7e8",
  "Favourable to the trial" = "#2ca02c"
)


# -----------------------------------------------------------------------------
# 1. Framing by outlet
# -----------------------------------------------------------------------------

framing_pct <- framing_scores %>%
  group_by(outlet, framing) %>%
  summarise(n = n(), .groups = "drop") %>%
  group_by(outlet) %>%
  mutate(pct = round(n / sum(n) * 100, 1))

fig_framing_by_outlet <- ggplot(framing_pct, aes(x = outlet, y = pct, fill = framing)) +
  geom_bar(stat = "identity", position = "dodge") +
  geom_text(
    aes(label = paste0(pct, "%")),
    position = position_dodge(width = 0.9),
    vjust = -0.5, size = 3.5
  ) +
  scale_fill_manual(values = framing_colours) +
  labs(
    title    = "Framing of Bolsonaro's trial by outlet",
    subtitle = "Newspaper's voice | Neutral = reports facts only, no framing",
    x = "Outlet", y = "% of articles", fill = "Framing"
  ) +
  theme_minimal(base_size = 13) +
  theme(
    plot.title      = element_text(face = "bold"),
    legend.position = "top"
  ) +
  ylim(0, 105)

save_figure(fig_framing_by_outlet, "figure_1_framing_by_outlet.png")

fig_framing_stacked <- ggplot(
  framing_scores %>%
    count(outlet, framing) %>%
    group_by(outlet) %>%
    mutate(pct = round(n / sum(n) * 100, 1)),
  aes(x = outlet, y = pct, fill = framing)
) +
  geom_bar(stat = "identity", position = "stack") +
  geom_text(
    aes(label = ifelse(pct >= 5, paste0(pct, "%"), "")),
    position = position_stack(vjust = 0.5), size = 3.5
  ) +
  scale_fill_manual(values = framing_colours) +
  labs(
    title    = "Distribution of framing by outlet (stacked)",
    subtitle = "Neutral = the newspaper only reports facts, without taking a position",
    x = "Outlet", y = "% of articles", fill = ""
  ) +
  theme_minimal(base_size = 13) +
  theme(
    plot.title      = element_text(face = "bold"),
    legend.position = "top"
  )

save_figure(fig_framing_stacked, "additional_1_framing_by_outlet_stacked.png")


# -----------------------------------------------------------------------------
# 2. Framing index per outlet
# -----------------------------------------------------------------------------

fig_index_by_outlet <- framing_scores %>%
  group_by(outlet) %>%
  summarise(
    mean_index = round(mean(framing_index, na.rm = TRUE), 2),
    .groups = "drop"
  ) %>%
  ggplot(aes(x = reorder(outlet, mean_index), y = mean_index, fill = mean_index)) +
  geom_bar(stat = "identity") +
  geom_text(aes(label = mean_index), hjust = -0.2, size = 4) +
  coord_flip() +
  scale_fill_gradient2(
    low = "#d62728", mid = "#ffbb78", high = "#2ca02c",
    midpoint = 0, limits = c(-1, 1)
  ) +
  scale_y_continuous(limits = c(-1.1, 1.1)) +
  labs(
    title    = "Average framing index by outlet",
    subtitle = "-1 = fully anti-trial | +1 = fully pro-trial",
    x = "Outlet", y = "Framing index", fill = "Index"
  ) +
  theme_minimal(base_size = 13) +
  theme(
    plot.title      = element_text(face = "bold"),
    legend.position = "right"
  )

save_figure(fig_index_by_outlet, "additional_2_framing_index_by_outlet.png")

fig_index_distribution <- framing_scores %>%
  filter(!is.na(framing_index)) %>%
  ggplot(aes(x = outlet, y = framing_index, fill = outlet)) +
  geom_boxplot(width = 0.5, outlier.shape = 21, outlier.size = 2) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "gray40") +
  scale_fill_manual(values = c(
    "#2ca02c", "#2ca02c", "#2ca02c", "#2ca02c", "#2ca02c"
  )) +
  labs(
    title    = "Distribution of the framing index by outlet",
    subtitle = "Each box shows the middle 50% of articles | Line = median | Points = outliers",
    x = "Outlet",
    y = "Index (-1 to +1)"
  ) +
  theme_minimal(base_size = 13) +
  theme(
    plot.title      = element_text(face = "bold"),
    legend.position = "none"
  )

save_figure(fig_index_distribution, "figure_5_framing_index_distribution.png")


# -----------------------------------------------------------------------------
# 3. Framing terms
# -----------------------------------------------------------------------------

# Top 10 pro and top 10 anti terms (newspaper's voice)
top_terms <- term_frequency %>%
  filter(freq_voice > 0) %>%
  group_by(direction) %>%
  slice_max(freq_voice, n = 10) %>%
  ungroup()

fig_top_terms <- ggplot(top_terms, aes(x = reorder(term, freq_voice), y = freq_voice, fill = direction)) +
  geom_bar(stat = "identity") +
  geom_text(aes(label = freq_voice), hjust = -0.2, size = 3.5) +
  coord_flip() +
  scale_fill_manual(
    values = c("pro" = "#2ca02c", "anti" = "#d62728"),
    labels = c("pro" = "Pro-trial", "anti" = "Anti-trial")
  ) +
  labs(
    title    = "Most frequent framing terms (newspaper's voice)",
    subtitle = "Pro terms legitimise the trial | Anti terms delegitimise it",
    x = "", y = "Total frequency", fill = ""
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title      = element_text(face = "bold"),
    legend.position = "top"
  )

save_figure(fig_top_terms, "figure_3_top_framing_terms.png")

# Use of each term per outlet
fig_terms_heatmap <- ggplot(term_frequency_by_outlet %>% filter(n > 0),
                            aes(x = outlet, y = reorder(term, n), fill = n)) +
  geom_tile() +
  scale_fill_viridis_c() +
  facet_wrap(~direction, scales = "free_y") +
  labs(title = "Heatmap: use of framing terms by outlet")

save_figure(fig_terms_heatmap, "figure_4_framing_terms_heatmap.png", height = 8)

# Average number of pro vs anti terms per article
fig_pro_vs_anti <- framing_scores %>%
  group_by(outlet) %>%
  summarise(pro = mean(pro_voice), anti = -mean(anti_voice)) %>%
  pivot_longer(c(pro, anti)) %>%
  ggplot(aes(x = outlet, y = value, fill = name)) +
  geom_bar(stat = "identity") +
  geom_hline(yintercept = 0) +
  scale_fill_manual(values = c("pro" = "#2ca02c", "anti" = "#d62728")) +
  labs(title = "Average pro vs anti terms by outlet (newspaper's voice)")

save_figure(fig_pro_vs_anti, "additional_3_pro_vs_anti_terms.png")


# -----------------------------------------------------------------------------
# 4. Full text vs newspaper's voice
# -----------------------------------------------------------------------------

label_full  <- "Full text (with quotes)"
label_voice <- "Newspaper's voice (without quotes)"

raw_score_comparison <- bind_rows(
  framing_scores %>%
    group_by(outlet) %>%
    summarise(score = round(mean(raw_score_full), 2), .groups = "drop") %>%
    mutate(type = label_full),
  framing_scores %>%
    group_by(outlet) %>%
    summarise(score = round(mean(raw_score_voice), 2), .groups = "drop") %>%
    mutate(type = label_voice)
)

fig_raw_score_comparison <- ggplot(raw_score_comparison, aes(x = outlet, y = score, fill = type)) +
  geom_bar(stat = "identity", position = "dodge") +
  geom_text(
    aes(label = score),
    position = position_dodge(width = 0.9),
    vjust = -0.5, size = 3.5
  ) +
  scale_fill_manual(values = c("#1f77b4", "#ff7f0e")) +
  labs(
    title    = "Raw score: full text vs newspaper's voice",
    subtitle = "Raw score = pro - anti | The difference shows the effect of quotes",
    x = "Outlet", y = "Average raw score", fill = ""
  ) +
  theme_minimal(base_size = 13) +
  theme(plot.title = element_text(face = "bold"), legend.position = "top")

save_figure(fig_raw_score_comparison, "additional_4_raw_score_full_vs_voice.png")

index_comparison <- bind_rows(
  framing_scores %>%
    group_by(outlet) %>%
    summarise(index = round(mean(index_full, na.rm = TRUE), 3), .groups = "drop") %>%
    mutate(type = label_full),
  framing_scores %>%
    group_by(outlet) %>%
    summarise(index = round(mean(framing_index, na.rm = TRUE), 3), .groups = "drop") %>%
    mutate(type = label_voice)
)

fig_index_comparison <- ggplot(index_comparison, aes(x = outlet, y = index, fill = type)) +
  geom_bar(stat = "identity", position = "dodge") +
  geom_text(
    aes(label = index),
    position = position_dodge(width = 0.9),
    vjust = -0.5, size = 3.5
  ) +
  scale_fill_manual(values = c("#1f77b4", "#ff7f0e")) +
  coord_cartesian(ylim = c(-1, 1)) +
  labs(
    title    = "Framing index: full text vs newspaper's voice",
    subtitle = "Index from -1 to +1 | The difference shows the effect of quotes",
    x = "Outlet", y = "Average framing index", fill = ""
  ) +
  theme_minimal(base_size = 13) +
  theme(plot.title = element_text(face = "bold"), legend.position = "top")

save_figure(fig_index_comparison, "figure_2_framing_index_full_vs_voice.png")


# -----------------------------------------------------------------------------
# 5. Key trigrams
# -----------------------------------------------------------------------------

fig_key_trigrams <- ggplot(key_trigrams, aes(x = outlet, y = n, fill = trigram)) +
  geom_bar(stat = "identity", position = "dodge") +
  geom_text(
    aes(label = n),
    position = position_dodge(width = 0.9),
    vjust = -0.5, size = 3
  ) +
  labs(
    title    = "Key trigrams: framing favourable to the trial",
    subtitle = "Institutional expressions that legitimise the process",
    x = "Outlet", y = "Frequency", fill = ""
  ) +
  theme_minimal(base_size = 13) +
  theme(
    plot.title      = element_text(face = "bold"),
    legend.position = "bottom"
  )

save_figure(fig_key_trigrams, "additional_5_key_trigrams.png")