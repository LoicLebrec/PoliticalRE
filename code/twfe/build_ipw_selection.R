# Inverse-probability-weighted TWFE, the counterpart to heckman/build_heckman_simple.R
# for the SAME problem (reconduit only observed for communes whose mayor
# recandidature -- selection into the outcome sample) but solved directly
# inside the TWFE regression instead of a separate cross-sectional Heckman
# 2-step.
#
# Why IPW over Heckman here: heckit's rho identification depends on an
# exclusion restriction (nb_mandats) that build_heckman_simple.R itself
# flags as weak (plausibly affects reconduit directly, not only via the
# candidacy decision -- see caveat in that script). IPW needs no exclusion
# restriction at all: weight each observed (candidate) commune by
# 1/P(recandidature=1 | X), so the weighted sample represents the FULL
# treated+control population, not just self-selected candidates. Tradeoff:
# still assumes selection is ignorable given X (eolien_treated, log_pop,
# election-year) -- unobserved determinants of BOTH candidacy and
# reelection are not corrected for the way Heckman's rho attempts to (that
# is Heckman's whole point). Neither estimator dominates; reported
# side-by-side as a robustness pair, not a replacement.
#
# Selection stage: pooled logit (both panel periods stacked, NOT
# commune-FE -- a 2-period panel logit-with-unit-FE has severe incidental-
# parameter bias, and recandidature is constant across the 2 observed
# periods for most communes, i.e. near-perfect separation once a unit FE
# is added; same reason build_heckman_simple.R's heckit has no unit FE
# either). recandidature ~ eolien_treated + log_pop + election-year FE.
# Propensities trimmed to [0.05, 0.95] before inverting (Crump et al.
# 2009-style) -- uncapped 1/phat blows up for communes near-certain not to
# run again, a handful of huge weights would otherwise dominate the
# weighted TWFE estimate.
#
# Outcome stage: same TWFE spec as build_robustness_combined.R's reference
# (reconduit_pp ~ eolien_treated + log_pop:post | code_insee + annee,
# commune-clustered SE), run twice per cohort x control pool -- unweighted
# (status quo, selection-uncorrected) and IPW-weighted -- so the selection
# correction's effect on the point estimate is visible directly.
#
# Output: tables/table_ipw_selection.{csv,tex}, figures/fig_ipw_selection.png

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(fixest); library(ggplot2)
  library(tidyr); library(kableExtra)
})

PROJECT  <- Sys.getenv("POLITICALRE_ROOT", unset = ".")
PANEL    <- file.path(PROJECT, "code/panel.csv")
PUB      <- file.path(PROJECT, "code/twfe")
TAB      <- file.path(PUB, "tables")
FIG      <- file.path(PUB, "figures")
dir.create(TAB, showWarnings = FALSE, recursive = TRUE)
dir.create(FIG, showWarnings = FALSE, recursive = TRUE)
col_spec <- cols(code_insee = col_character(), dep = col_character(), .default = col_guess())
stars    <- function(p) case_when(p < .01 ~ "***", p < .05 ~ "**", p < .10 ~ "*", TRUE ~ "")

DENS_OK <- c("5","6","7")
COHORTS <- list(
  list(label="A", yr_lo=2008L, yr_hi=2014L),
  list(label="B", yr_lo=2014L, yr_hi=2020L),
  list(label="C", yr_lo=2020L, yr_hi=2026L)
)

panel_raw <- read_csv(PANEL, col_types = col_spec) %>% filter(commune_fixe == 1)

ctrl_codes_matched  <- read_csv(file.path(PROJECT, "code/control_group_matched.csv"),
                                 col_types = col_spec) %>% pull(code_insee) %>% unique()
ctrl_codes_baseline <- read_csv(file.path(PROJECT, "code/shared_data/control_group_baseline.csv"),
                                 col_types = col_spec) %>% pull(code_insee) %>% unique()
CTRL_POOLS <- list(
  list(codes = ctrl_codes_matched,  label = "Socioeconomically matched control"),
  list(codes = ctrl_codes_baseline, label = "Baseline control")
)

cohort_codes <- function(yr_lo, yr_hi) {
  panel_raw %>% filter(annee %in% c(yr_lo, yr_hi)) %>%
    distinct(code_insee, annee, .keep_all = TRUE) %>%
    select(code_insee, annee, n_parcs_cumul, categorie_dens) %>%
    pivot_wider(names_from = annee, values_from = n_parcs_cumul, names_prefix = "np_") %>%
    filter(categorie_dens %in% DENS_OK, !is.na(.data[[paste0("np_",yr_lo)]]), !is.na(.data[[paste0("np_",yr_hi)]]),
           as.numeric(.data[[paste0("np_",yr_lo)]]) == 0, as.numeric(.data[[paste0("np_",yr_hi)]]) > 0) %>%
    pull(code_insee)
}

keep_both <- function(df, yrs) df %>%
  group_by(code_insee) %>% filter(n_distinct(annee[annee %in% yrs]) == length(yrs)) %>% ungroup()

make_panel <- function(trt_codes_vec, ctrl_codes_vec, yr_lo, yr_hi) {
  pop_base <- panel_raw %>% filter(annee == yr_lo) %>% distinct(code_insee, .keep_all = TRUE) %>%
    transmute(code_insee, log_pop = log1p(as.numeric(inscrits)))
  trt <- panel_raw %>% filter(code_insee %in% trt_codes_vec, annee %in% c(yr_lo, yr_hi)) %>%
    distinct(code_insee, annee, .keep_all = TRUE) %>%
    mutate(eolien_treated = as.integer(annee == yr_hi), post = as.integer(annee == yr_hi),
           reconduit_pp = reconduit * 100) %>%
    left_join(pop_base, by = "code_insee") %>% keep_both(c(yr_lo, yr_hi))
  ctrl <- panel_raw %>% filter(code_insee %in% ctrl_codes_vec, annee %in% c(yr_lo, yr_hi)) %>%
    distinct(code_insee, annee, .keep_all = TRUE) %>%
    mutate(eolien_treated = 0L, post = as.integer(annee == yr_hi), reconduit_pp = reconduit * 100) %>%
    left_join(pop_base, by = "code_insee") %>% keep_both(c(yr_lo, yr_hi))
  bind_rows(trt, ctrl)
}

# ── Selection stage: P(recandidature=1 | eolien_treated, log_pop, year) ────
# Trimmed at [0.05, 0.95] before inverting -- see header note on why an
# uncapped 1/phat is not used.
add_ipw <- function(dat) {
  d_sel <- dat %>% filter(!is.na(recandidature), !is.na(log_pop))
  sel_fit <- glm(recandidature ~ eolien_treated + log_pop + factor(annee), data = d_sel, family = binomial())
  phat <- predict(sel_fit, newdata = d_sel, type = "response")
  d_sel$phat <- pmin(pmax(phat, 0.05), 0.95)
  d_sel$ipw  <- 1 / d_sel$phat
  d_sel
}

run_reconduit <- function(dat_ipw, weighted) {
  d <- dat_ipw %>% filter(recandidature == 1, !is.na(reconduit_pp), !is.na(log_pop))
  if (n_distinct(d$code_insee[d$eolien_treated == 1]) < 5) return(NULL)
  fml <- as.formula("reconduit_pp ~ eolien_treated + log_pop:post | code_insee + annee")
  mod <- tryCatch(
    if (weighted) feols(fml, data = d, weights = ~ipw, cluster = ~code_insee)
    else          feols(fml, data = d, cluster = ~code_insee),
    error = function(e) NULL)
  if (is.null(mod)) return(NULL)
  ct <- coeftable(mod)
  tibble(spec = if (weighted) "IPW-weighted" else "Unweighted",
         n = nrow(d), n_treated = n_distinct(d$code_insee[d$eolien_treated == 1]),
         estimate = ct["eolien_treated","Estimate"], se = ct["eolien_treated","Std. Error"],
         p = ct["eolien_treated","Pr(>|t|)"])
}

res_rows <- list()
for (cohort in COHORTS) {
  coh_codes <- cohort_codes(cohort$yr_lo, cohort$yr_hi)
  cat(sprintf("\n========== Cohort %s (%d-%d): %d treated communes ==========\n",
              cohort$label, cohort$yr_lo, cohort$yr_hi, length(coh_codes)))
  for (pool in CTRL_POOLS) {
    dat <- make_panel(coh_codes, pool$codes, cohort$yr_lo, cohort$yr_hi)
    dat_ipw <- add_ipw(dat)
    cat(sprintf("  %s | mean phat=%.3f, mean ipw=%.2f (post-trim)\n",
                pool$label, mean(dat_ipw$phat), mean(dat_ipw$ipw)))
    for (w in c(FALSE, TRUE)) {
      r <- run_reconduit(dat_ipw, w)
      if (!is.null(r)) res_rows[[length(res_rows)+1]] <- r %>% mutate(cohort = cohort$label, control = pool$label)
    }
  }
}

res <- bind_rows(res_rows) %>%
  mutate(ci_low = estimate - 1.96*se, ci_high = estimate + 1.96*se, signif = stars(p)) %>%
  select(cohort, control, spec, n, n_treated, estimate, se, ci_low, ci_high, p, signif)

cat("\n=== IPW-weighted TWFE (reconduit) -- publication summary ===\n")
print(res, n = 20)

# ── Table ───────────────────────────────────────────────────────────────
write_csv(res %>% mutate(across(c(estimate, se, ci_low, ci_high), ~round(.x, 3)), p = round(p, 3)),
          file.path(TAB, "table_ipw_selection.csv"))
cat(sprintf("Saved -> %s\n", file.path(TAB, "table_ipw_selection.csv")))

tab_disp <- res %>%
  mutate(Cohort = cohort, Estimate = sprintf("%+.3f%s", estimate, signif), SE = sprintf("%.3f", se),
         `95% CI` = sprintf("[%.3f, %.3f]", ci_low, ci_high), p = sprintf("%.3f", p)) %>%
  select(Cohort, Control = control, Spec = spec, N = n, `N treated` = n_treated, Estimate, SE, `95% CI`, p)

tab_latex <- tab_disp %>%
  kbl(format = "latex", booktabs = TRUE, escape = TRUE,
      caption = "IPW-weighted TWFE -- reelection outcome, unweighted vs. selection-corrected, by cohort and control pool",
      label = "table_ipw_selection", linesep = "") %>%
  kable_styling(latex_options = c("hold_position"), font_size = 9) %>%
  collapse_rows(columns = 1:2, valign = "top") %>%
  footnote(general = paste(
    "Selection: logit(recandidature ~ eolien_treated + log_pop + election-year FE), pooled across both panel periods (no commune FE -- incidental-parameter bias / near-perfect separation on a 2-period panel).",
    "Weight: 1/P(recandidature=1|X), propensities trimmed to [0.05, 0.95] before inverting.",
    "Outcome: reconduit_pp ~ eolien_treated + log_pop:post | commune + year FE, commune-clustered SE, sample restricted to observed candidates (recandidature==1).",
    "No exclusion restriction required (unlike the Heckman spec in heckman/build_heckman_simple.R) -- IPW instead assumes selection is ignorable given eolien_treated, log_pop and election-year; not directly comparable identifying assumptions, reported side-by-side as a robustness pair.",
    "*** p<0.01, ** p<0.05, * p<0.10.",
    sep = " "),
    threeparttable = TRUE, escape = FALSE)

writeLines(as.character(tab_latex), file.path(TAB, "table_ipw_selection.tex"))
cat(sprintf("Saved -> %s\n", file.path(TAB, "table_ipw_selection.tex")))

# ── Coefficient plot ───────────────────────────────────────────────────────
plot_dat <- res %>% mutate(cohort_lbl = sprintf("Cohort %s", cohort))

p <- ggplot(plot_dat, aes(x = estimate, y = spec, color = spec)) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "grey50") +
  geom_pointrange(aes(xmin = ci_low, xmax = ci_high), size = 0.6, linewidth = 0.9) +
  geom_text(aes(label = sprintf("%+.3f%s", estimate, signif)), vjust = -1.1, size = 3.2) +
  facet_grid(control ~ cohort_lbl, scales = "free_x") +
  scale_color_manual(values = c("Unweighted" = "#e34948", "IPW-weighted" = "#2a78d6"), name = NULL) +
  labs(title = "TWFE reelection effect -- unweighted vs. IPW selection-corrected",
       subtitle = "reconduit_pp ~ eolien_treated + log_pop:post | commune + year FE, sample = observed candidates only",
       x = "Estimated effect (pp) + 95% CI", y = NULL,
       caption = paste(
         "IPW weight = 1/P(recandidature=1 | eolien_treated, log_pop, election-year), logit, propensities trimmed to [0.05, 0.95].",
         "No exclusion restriction required (contrast with Heckman spec, heckman/build_heckman_simple.R) -- relies instead on selection-on-observables.",
         sep = "\n")) +
  theme_bw(base_size = 11) +
  theme(legend.position = "none", plot.caption = element_text(hjust = 0, size = 8, color = "grey40"))

ggsave(file.path(FIG, "fig_ipw_selection.png"), p, width = 11, height = 6.5, dpi = 200)
cat(sprintf("Saved -> %s\n", file.path(FIG, "fig_ipw_selection.png")))
