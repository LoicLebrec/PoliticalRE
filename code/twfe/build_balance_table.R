# Table 1 -- descriptive statistics / balance table, national scope.
# TREATMENT: rural density 5-7, 0 wind farms in 2014 -> >=1 by 2020 (Cohort B,
#   the shared reference cohort used throughout code).
# CONTROL: rural density 5-7, never treated, department with > 3 treated
#   municipalities, probit-matched on wind + log(pop) + log(income) +
#   log(investment) + department FE (control_group_new.csv).
# All variables measured at 2014 (pre-treatment baseline), standard practice
# for a balance table (parallel-trends / matching-quality check).
#
# Output: tables/table_balance.{csv,tex}

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(tidyr); library(stringr)
  library(readxl); library(kableExtra)
})

PROJECT <- Sys.getenv("POLITICALRE_ROOT", unset = ".")
DATA    <- file.path(PROJECT, "code/shared_data")
PUB     <- file.path(PROJECT, "code/twfe")
TAB     <- file.path(PUB, "tables")
PANEL   <- file.path(PROJECT, "code/panel.csv")
dir.create(TAB, showWarnings = FALSE, recursive = TRUE)

col_spec <- cols(code_insee = col_character(), dep = col_character(), .default = col_guess())
pad5     <- function(x) str_pad(str_extract(as.character(x), "[0-9A-Za-z]+"), 5, "left", "0")
DENS_OK  <- c("5", "6", "7")

panel_raw_full <- read_csv(PANEL, col_types = col_spec)
panel_raw <- panel_raw_full %>% filter(commune_fixe == 1)

ctrl_codes <- read_csv(file.path(PROJECT, "code/control_group_matched.csv"),
                        col_types = col_spec) %>% pull(code_insee) %>% unique()

coh_b_codes <- panel_raw %>% filter(annee %in% c(2014L, 2020L)) %>%
  distinct(code_insee, annee, .keep_all = TRUE) %>%
  select(code_insee, annee, n_parcs_cumul, categorie_dens) %>%
  pivot_wider(names_from = annee, values_from = n_parcs_cumul, names_prefix = "np_") %>%
  filter(categorie_dens %in% DENS_OK, !is.na(np_2014), !is.na(np_2020),
         as.numeric(np_2014) == 0, as.numeric(np_2020) > 0) %>%
  pull(code_insee)

inv13 <- read_csv(file.path(DATA, "invest_communes_2013.csv"), col_types = col_spec) %>%
  rename(invest_2013 = invest_sd)
filo14 <- read_excel(
  file.path(PROJECT, "election_data/data_quentin/2026/insee_raw/filosofi_series/filo2014/indic-struct-distrib-revenu-2014-COMMUNES/FILO_DISP_COM.xls"),
  sheet = "ENSEMBLE", skip = 5, col_types = "text") %>%
  rename(code_insee = CODGEO, rev_med = Q214) %>%
  mutate(code_insee = pad5(code_insee), rev_med = suppressWarnings(as.numeric(rev_med))) %>%
  select(code_insee, rev_med)

base14 <- panel_raw %>% filter(annee == 2014L) %>% distinct(code_insee, .keep_all = TRUE) %>%
  mutate(
    group = case_when(
      code_insee %in% coh_b_codes ~ "Treatment",
      code_insee %in% ctrl_codes  ~ "Control",
      TRUE ~ NA_character_
    )
  ) %>%
  filter(!is.na(group)) %>%
  mutate(
    inscrits           = as.numeric(inscrits),
    invest_pc_num       = NA_real_,
    wind_speed_100m     = as.numeric(wind_speed_100m),
    pct_abstention      = as.numeric(pct_abstention),
    pct_voix_gagnant_exprimes = as.numeric(pct_voix_gagnant_exprimes),
    recandidature_pp    = as.numeric(recandidature) * 100,
    reconduit_pp        = as.numeric(reconduit) * 100
  ) %>%
  left_join(inv13, by = "code_insee") %>%
  left_join(filo14, by = "code_insee") %>%
  mutate(invest_pc = invest_2013 / pmax(inscrits, 1))

cat(sprintf("N communes -- Treatment: %d | Control: %d\n",
            n_distinct(base14$code_insee[base14$group == "Treatment"]),
            n_distinct(base14$code_insee[base14$group == "Control"])))

VARS <- list(
  list(var = "inscrits",                  label = "Registered voters (2014)"),
  list(var = "rev_med",                   label = "Median household income (EUR, 2014)"),
  list(var = "invest_pc",                 label = "Municipal investment per capita (EUR, 2013)"),
  list(var = "wind_speed_100m",           label = "Wind speed at 100m (m/s)"),
  list(var = "recandidature_pp",          label = "Incumbent candidacy rate (%, 2014)"),
  list(var = "reconduit_pp",              label = "Incumbent reelection rate (%, 2014)"),
  list(var = "pct_voix_gagnant_exprimes", label = "Winner vote share (% valid votes, 2014)"),
  list(var = "pct_abstention",            label = "Abstention rate (% registered, 2014)")
)

stars <- function(p) case_when(p < .01 ~ "***", p < .05 ~ "**", p < .10 ~ "*", TRUE ~ "")

balance_row <- function(v, lbl) {
  trt <- base14 %>% filter(group == "Treatment") %>% pull(.data[[v]])
  ctl <- base14 %>% filter(group == "Control")   %>% pull(.data[[v]])
  trt <- trt[!is.na(trt)]; ctl <- ctl[!is.na(ctl)]
  tt <- tryCatch(t.test(trt, ctl), error = function(e) NULL)
  tibble(
    Variable      = lbl,
    N_treatment   = length(trt),
    Mean_treatment = mean(trt), SD_treatment = sd(trt),
    N_control     = length(ctl),
    Mean_control  = mean(ctl), SD_control = sd(ctl),
    Diff          = mean(trt) - mean(ctl),
    p             = if (is.null(tt)) NA_real_ else tt$p.value
  )
}

bal <- bind_rows(lapply(VARS, function(v) balance_row(v$var, v$label)))

n_row <- tibble(
  Variable = "Municipalities (N)",
  N_treatment = n_distinct(base14$code_insee[base14$group == "Treatment"]),
  Mean_treatment = NA_real_, SD_treatment = NA_real_,
  N_control = n_distinct(base14$code_insee[base14$group == "Control"]),
  Mean_control = NA_real_, SD_control = NA_real_,
  Diff = NA_real_, p = NA_real_
)
bal <- bind_rows(n_row, bal)

# ── CSV ─────────────────────────────────────────────────────────────────
write_csv(
  bal %>% mutate(across(c(Mean_treatment, SD_treatment, Mean_control, SD_control, Diff),
                        ~round(.x, 2)), p = round(p, 3)),
  file.path(TAB, "table_balance.csv")
)
cat(sprintf("Saved -> %s\n", file.path(TAB, "table_balance.csv")))

# ── LaTeX ───────────────────────────────────────────────────────────────
fmt_cell <- function(m, s) ifelse(is.na(m), "", sprintf("%.2f (%.2f)", m, s))
bal_tex <- bal %>%
  mutate(
    Treatment = ifelse(Variable == "Municipalities (N)", sprintf("%d", N_treatment),
                        fmt_cell(Mean_treatment, SD_treatment)),
    Control   = ifelse(Variable == "Municipalities (N)", sprintf("%d", N_control),
                        fmt_cell(Mean_control, SD_control)),
    `Diff. (T-C)` = ifelse(is.na(Diff), "", sprintf("%+.2f%s", Diff, stars(p))),
    p_value   = ifelse(is.na(p), "", sprintf("%.3f", p))
  ) %>%
  select(Variable, Treatment, Control, `Diff. (T-C)`, p_value)

tab_latex <- bal_tex %>%
  kbl(format = "latex", booktabs = TRUE, escape = TRUE,
      caption = "Descriptive statistics -- treatment vs. control municipalities, national sample (Cohort B, 2014 baseline)",
      label = "table_balance", linesep = "",
      col.names = c("Variable", "Treatment\nmean (SD)", "Control\nmean (SD)", "Diff. (T$-$C)", "p")) %>%
  kable_styling(latex_options = c("hold_position"), font_size = 9) %>%
  row_spec(1, bold = TRUE) %>%
  footnote(general = paste(
    "TREATMENT: rural density 5-7, 0 wind farms in 2014 -> >=1 by 2020 (Cohort B).",
    "CONTROL: rural density 5-7, never treated, department with > 3 treated municipalities,",
    "probit-matched on wind speed + log(pop) + log(income) + log(investment) + department FE (P10 threshold of treated).",
    "All variables measured at 2014 (pre-treatment baseline). Diff. = Treatment mean - Control mean, two-sample t-test.",
    "*** p<0.01, ** p<0.05, * p<0.10.",
    sep = " "),
    threeparttable = TRUE, escape = FALSE)

writeLines(as.character(tab_latex), file.path(TAB, "table_balance.tex"))
cat(sprintf("Saved -> %s\n", file.path(TAB, "table_balance.tex")))
