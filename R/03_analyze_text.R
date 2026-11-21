# =============================================================================
# 03_analyze_text.R — Complementary analyses
# -----------------------------------------------------------------------------
#
# Steps:
#   1. Frequency of each dictionary term, overall and per outlet.
#   2. Keywords in context: the five words before and after selected terms.
#   3. Most frequent two-word (bigram) and three-word (trigram) phrases.
# =============================================================================

source("R/setup.R")

framing_scores <- readRDS(file.path(DIR_PROCESSED, "framing_scores.rds"))
dictionary     <- read.csv(DICTIONARY_FILE, fileEncoding = "UTF-8") %>%
  select(term, direction)

save_table <- function(table, file_name) {
  write.csv(table, file.path(DIR_TABLES, file_name),
            row.names = FALSE, fileEncoding = "UTF-8")
}


# -----------------------------------------------------------------------------
# 1. Frequency of each dictionary term
# -----------------------------------------------------------------------------

# Overall: in the full text and in the newspaper's voice
term_frequency <- dictionary %>%
  rowwise() %>%
  mutate(
    freq_full  = sum(str_count(framing_scores$text_lower, fixed(term))),
    freq_voice = sum(str_count(framing_scores$text_voice, fixed(term)))
  ) %>%
  ungroup() %>%
  arrange(direction, desc(freq_voice))

cat("\nMost frequent pro-trial terms (newspaper's voice)\n")
term_frequency %>%
  filter(direction == "pro", freq_voice > 0) %>%
  arrange(desc(freq_voice)) %>%
  print(n = 30)

cat("\nMost frequent anti-trial terms (newspaper's voice)\n")
term_frequency %>%
  filter(direction == "anti", freq_voice > 0) %>%
  arrange(desc(freq_voice)) %>%
  print(n = 30)

save_table(term_frequency, "term_frequency.csv")

# Per outlet, in the newspaper's voice
term_frequency_by_outlet <- dictionary %>%
  rowwise() %>%
  mutate(freq = list(
    framing_scores %>%
      group_by(outlet) %>%
      summarise(n = sum(str_count(text_voice, fixed(term))))
  )) %>%
  unnest(freq)

save_table(term_frequency_by_outlet, "term_frequency_by_outlet.csv")


# -----------------------------------------------------------------------------
# 2. Keywords in context (KWIC)
# -----------------------------------------------------------------------------
# For each selected term, extract the term with up to five words on each side,
# from the full text.

extract_contexts <- function(terms) {
  framing_scores %>%
    select(id, outlet, text_lower) %>%
    rowwise() %>%
    mutate(
      context = list(
        unlist(lapply(terms, function(t) {
          pattern <- paste0("(?:\\S+\\s+){0,5}", t, "(?:\\s+\\S+){0,5}")
          str_extract_all(text_lower, pattern)[[1]]
        }))
      )
    ) %>%
    ungroup() %>%
    unnest(context) %>%
    select(id, outlet, context)
}

kwic_terms_pro  <- c("golpe", "condenação", "ameaça à democracia",
                     "crime contra a democracia", "criminoso")
kwic_terms_anti <- c("perseguição", "ilegítimo", "inocente",
                     "injusto", "censura")

kwic_pro <- extract_contexts(kwic_terms_pro)

cat("\nKeywords in context: pro-trial terms (sample)\n")
kwic_pro %>%
  group_by(outlet) %>%
  slice_sample(n = 5) %>%
  print(n = 30)

kwic_anti <- extract_contexts(kwic_terms_anti)

cat("\nKeywords in context: anti-trial terms (sample)\n")
kwic_anti %>%
  group_by(outlet) %>%
  slice_sample(n = 5) %>%
  print(n = 30)

save_table(kwic_pro,  "kwic_pro.csv")
save_table(kwic_anti, "kwic_anti.csv")


# -----------------------------------------------------------------------------
# 3. Bigrams and trigrams
# -----------------------------------------------------------------------------
# Phrases are counted in the full text (title + body, lower case). Phrases
# containing a stopword, a number or a single-character word are removed.

stopwords_pt <- c(
  "de", "a", "o", "que", "e", "do", "da", "em", "um", "para",
  "com", "uma", "os", "no", "se", "na", "por", "mais", "as",
  "dos", "como", "mas", "ao", "ele", "das", "à", "seu", "sua",
  "ou", "quando", "muito", "nos", "já", "também", "pelo", "pela",
  "até", "isso", "ela", "entre", "depois", "sem", "mesmo", "aos",
  "seus", "suas", "num", "nem", "nas", "me", "esse", "eles",
  "essa", "este", "desta", "foi", "está", "são", "ser", "ter",
  "eu", "tu", "nós", "vós", "lhe", "lhes", "meu", "minha",
  "teu", "tua", "nosso", "nossa", "deste", "desse", "daquele",
  "neste", "nesse", "naquele", "aquele", "aquela", "aquilo",
  "isto", "ali", "aqui", "lá", "cá", "onde", "então", "assim",
  "ainda", "só", "sobre", "desde", "ante", "sob", "após",
  "tem", "era", "foram", "será", "seria", "pode", "havia",
  "tinha", "disse", "afirmou", "segundo", "conforme",
  "zero", "um", "dois", "três", "quatro", "cinco", "seis",
  "sete", "oito", "nove", "dez", "onze", "doze", "treze",
  "catorze", "quatorze", "quinze", "vinte", "trinta", "cem", "mil",
  "janeiro", "fevereiro", "março", "abril", "maio", "junho",
  "julho", "agosto", "setembro", "outubro", "novembro", "dezembro",
  "dia", "mês", "ano", "hora", "horas", "dias", "anos",
  "foto", "vídeo", "imagem", "reprodução", "leia", "veja",
  "publicado", "atualizado", "compartilhar", "comentários",
  "fonte", "agência", "reportagem", "notícia", "publicação"
)

is_number <- function(x) grepl("^[0-9]+$", x)

# Bigrams
bigrams <- framing_scores %>%
  select(id, outlet, text_lower) %>%
  unnest_ngrams(bigram, text_lower, n = 2) %>%
  count(outlet, bigram, sort = TRUE)

bigrams_clean <- bigrams %>%
  separate(bigram, into = c("word1", "word2"), sep = " ") %>%
  filter(!word1 %in% stopwords_pt, !word2 %in% stopwords_pt) %>%
  filter(!is_number(word1), !is_number(word2)) %>%
  filter(nchar(word1) > 1, nchar(word2) > 1) %>%
  unite(bigram, word1, word2, sep = " ")

top_bigrams <- bigrams_clean %>%
  group_by(outlet) %>%
  slice_max(n, n = 5)

cat("\nTop 5 bigrams per outlet\n")
print(top_bigrams, n = 100)
save_table(top_bigrams, "top_bigrams.csv")

# Trigrams
trigrams <- framing_scores %>%
  select(id, outlet, text_lower) %>%
  unnest_ngrams(trigram, text_lower, n = 3) %>%
  count(outlet, trigram, sort = TRUE)

trigrams_clean <- trigrams %>%
  separate(trigram, into = c("word1", "word2", "word3"), sep = " ") %>%
  filter(!word1 %in% stopwords_pt,
         !word2 %in% stopwords_pt,
         !word3 %in% stopwords_pt) %>%
  filter(!is_number(word1), !is_number(word2), !is_number(word3)) %>%
  filter(nchar(word1) > 1, nchar(word2) > 1, nchar(word3) > 1) %>%
  unite(trigram, word1, word2, word3, sep = " ")

top_trigrams <- trigrams_clean %>%
  group_by(outlet) %>%
  slice_max(n, n = 5)

cat("\nTop 5 trigrams per outlet\n")
print(top_trigrams, n = 100)
save_table(top_trigrams, "top_trigrams.csv")

# Key trigrams (counted before stopword removal)
key_trigrams <- trigrams %>%
  filter(trigram %in% c("golpe de estado", "tentativa de golpe",
                        "defesa da democracia", "ameaça à democracia"))

save_table(key_trigrams, "key_trigrams.csv")