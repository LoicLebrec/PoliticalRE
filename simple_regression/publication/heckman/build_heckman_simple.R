# Publication-facing output for the SIMPLE Heckman spec, the counterpart to
# twfe/build_robustness_combined.R. Same estimator now wired live into
# simple_regression/morvan/run_morvan_competitif.R (rho + corrected SE
# printed every run there) -- this script re-fits it and produces
# publication artifacts (table + coefficient plot), which that diagnostic
# printout does not.
#
# Deliberately NOT the full-control spec (competitif interaction + age/
# homme/epci/dep/income/invest/dette): that one has separation issues
# (epci_type=="0", thin dep cells) and unstable interaction cells (n<30 for
# some cohort x competitif combos, see cell_check() in run_morvan_competitif.R).
# This is the stripped-down version that stays identified (rho in [-1,1])
# for all three cohorts:
#   Selection : recandidature ~ traitement + nb_mandats (exclusion) + log_pop
#   Outcome   : reconduit    ~ traitement + log_pop
# sampleSelection::heckit(method="2step") -- LPM outcome eq (coef IS the
# marginal effect), analytic SE correction for the generated-regressor
# problem (Heckman 1979) that a manual glm 2-step ignores.
#
# Output: tables/table_heckman_simple.{csv,tex}, figures/fig_heckman_simple.png

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(stringr); library(ggplot2)
  library(kableExtra); library(sampleSelection)
})

PROJECT <- Sys.getenv("POLITICALRE_ROOT", unset = "/home/loiclebrec/ENRpolitical/Python/PoliticalRE")
MORVAN  <- file.path(PROJECT, "simple_regression/morvan")

message("Loading cohorts (source run_morvan_competitif.R)...")
# sys.source runs in THIS environment -- run_morvan_competitif.R defines its
# own PROJECT/FIG/stars/etc, which would silently clobber ours if we set
# TAB/FIG before this call. Set our output paths AFTER sourcing instead.
sys.source(file.path(MORVAN, "run_morvan_competitif.R"), envir = environment())

PROJECT <- Sys.getenv("POLITICALRE_ROOT", unset = "/home/loiclebrec/ENRpolitical/Python/PoliticalRE")
PUB     <- file.path(PROJECT, "simple_regression/publication/heckman")
TAB     <- file.path(PUB, "tables")
FIG     <- file.path(PUB, "figures")
dir.create(TAB, showWarnings = FALSE, recursive = TRUE)
dir.create(FIG, showWarnings = FALSE, recursive = TRUE)
stars <- function(p) case_when(p < .01 ~ "***", p < .05 ~ "**", p < .10 ~ "*", TRUE ~ "")

# CAUTION -- weak exclusion restriction: nb_mandats (consecutive prior
# terms) predicts candidacy but is not obviously excludable from the
# reelection equation -- more terms plausibly shifts reelection odds
# directly (voter fatigue vs. accumulated incumbency advantage), not only
# via the decision to run again. Tried and rejected as alternatives
# (rho outside [-1,1] = invalid identification, checked for all 3 cohorts):
#   nb_listes    -- rho out of bounds for cohorts A/B (mechanically affects
#                    conditional win probability once candidate, worse
#                    exclusion violation than nb_mandats)
#   age alone    -- rho out of bounds for A (-1.11) and C (-1.06), right at
#                    the boundary for B (-0.985, technically valid but
#                    fragile)
#   type_scrutin=liste alone -- rho out of bounds for all 3 (1.33 / 1.26 /
#                    SE=NaN, numerical separation on C)
#   no exclusion at all (functional form only) -- SE=NaN on A and C
#                    (near-perfect collinearity), only B stays computable
# nb_mandats is the only variable that keeps rho in [-1,1] for all 3
# cohorts simultaneously -- not an untested default, the best of 4 checked
# options, but the underlying theoretical concern (does it really affect
# reelection ONLY through candidacy?) is not resolved by numerical
# identification holding up. That's a WEAKER identification argument than
# a credible instrument -- treat estimates from this equation with that
# caveat.
sel_fml_simple <- recandidature ~ traitement + nb_mandats + log_pop
out_fml_simple <- reconduit    ~ traitement + log_pop

fit_cohort <- function(res, lbl, elec_yr) {
  d <- res$d %>% filter(!is.na(recandidature), !is.na(nb_mandats), !is.na(log_pop))
  fit <- tryCatch(
    heckit(selection = sel_fml_simple, outcome = out_fml_simple, data = d, method = "2step"),
    error = function(e) { cat("ERROR heckit (", lbl, "):", conditionMessage(e), "\n"); NULL })
  if (is.null(fit)) return(NULL)

  ct <- summary(fit)$estimate
  sel_row <- ct["traitement", , drop = FALSE]
  out_row <- ct[which(rownames(ct) == "traitement")[2], , drop = FALSE]
  rho_val <- ct["rho", "Estimate"]

  tibble(
    cohort     = lbl,
    election   = elec_yr,
    n          = nrow(d),
    n_treated  = sum(d$traitement),
    equation   = c("Selection (candidacy)", "Outcome (reelection | ran again)"),
    estimate   = c(sel_row[1,"Estimate"], out_row[1,"Estimate"]),
    se         = c(sel_row[1,"Std. Error"], out_row[1,"Std. Error"]),
    p          = c(sel_row[1,"Pr(>|t|)"], out_row[1,"Pr(>|t|)"]),
    rho        = rho_val
  )
}

res <- bind_rows(
  fit_cohort(res_a, "A", 2014L),
  fit_cohort(res_b, "B", 2020L),
  fit_cohort(res_c, "C", 2026L)
) %>%
  mutate(
    ci_low  = estimate - 1.96*se,
    ci_high = estimate + 1.96*se,
    signif  = stars(p)
  )

cat("\n=== Simple Heckman -- publication summary ===\n")
print(res %>% select(cohort, equation, n, n_treated, estimate, se, p, rho), n = 20)

# ── Table ───────────────────────────────────────────────────────────────
write_csv(
  res %>% mutate(across(c(estimate, se, ci_low, ci_high, rho), ~round(.x, 3)), p = round(p, 3)) %>%
    select(Cohort = cohort, Election = election, Equation = equation, N = n, N_treated = n_treated,
           Estimate = estimate, SE = se, CI_low = ci_low, CI_high = ci_high, p, rho, Signif = signif),
  file.path(TAB, "table_heckman_simple.csv")
)
cat(sprintf("Saved -> %s\n", file.path(TAB, "table_heckman_simple.csv")))

tab_disp <- res %>%
  mutate(
    Cohort   = sprintf("%s (%d)", cohort, election),
    Estimate = sprintf("%+.3f%s", estimate, signif),
    SE       = sprintf("%.3f", se),
    `95% CI` = sprintf("[%.3f, %.3f]", ci_low, ci_high),
    p        = sprintf("%.3f", p),
    rho      = sprintf("%.3f", rho)
  ) %>%
  select(Cohort, Equation = equation, N = n, `N treated` = n_treated, Estimate, SE, `95% CI`, p, rho)

tab_latex <- tab_disp %>%
  kbl(format = "latex", booktabs = TRUE, escape = TRUE,
      caption = "Heckman selection model: candidacy (selection) and reelection (outcome) equations, by cohort",
      label = "table_heckman_simple", linesep = "") %>%
  kable_styling(latex_options = c("hold_position"), font_size = 9) %>%
  collapse_rows(columns = 1, valign = "top") %>%
  footnote(general = paste(
    "Selection: recandidature ~ treatment + nb_mandats (exclusion restriction, consecutive prior terms) + log_pop.",
    "Outcome: reconduit ~ treatment + log_pop (linear probability, coefficient = marginal effect).",
    "sampleSelection::heckit(method=\"2step\"), analytic SE correction for the generated-regressor problem (Heckman 1979).",
    "rho = selection-outcome error correlation; identification requires rho in [-1,1] (true for all 3 cohorts here).",
    "TREATMENT: rural density 5-7, 0 wind farms -> >=1 by election year (cohort-specific window). No clustering: one row per commune per cohort (cross-section).",
    "CAUTION: nb_mandats is a weak exclusion restriction: it plausibly affects reelection directly (voter fatigue / accumulated incumbency advantage after many terms), not only through the candidacy decision. Numerical identification (rho in [-1,1]) does not by itself establish a credible exclusion restriction; read this model's estimates with that in mind.",
    "*** p<0.01, ** p<0.05, * p<0.10.",
    sep = " "),
    threeparttable = TRUE, escape = FALSE)

writeLines(as.character(tab_latex), file.path(TAB, "table_heckman_simple.tex"))
cat(sprintf("Saved -> %s\n", file.path(TAB, "table_heckman_simple.tex")))

# ── Coefficient plot ───────────────────────────────────────────────────────
plot_dat <- res %>%
  mutate(cohort_lbl = sprintf("Cohort %s (%d)", cohort, election),
         equation = factor(equation, levels = c("Selection (candidacy)", "Outcome (reelection | ran again)")))

p <- ggplot(plot_dat, aes(x = estimate, y = cohort_lbl)) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "grey50") +
  geom_pointrange(aes(xmin = ci_low, xmax = ci_high), color = "#2a78d6", size = 0.6, linewidth = 0.9) +
  geom_text(aes(label = sprintf("%+.3f%s", estimate, signif)), vjust = -1.1, size = 3.2) +
  facet_wrap(~equation, scales = "free_x") +
  labs(title = "Heckman Selection Model: Treatment Effect by Cohort",
       subtitle = "Selection: recandidature ~ treatment + nb_mandats + log_pop | Outcome: reconduit ~ treatment + log_pop",
       x = "Coefficient (probit index / LPM marginal effect) + 95% CI", y = NULL,
       caption = paste(
         "sampleSelection::heckit(method=\"2step\"). rho in [-1,1] for all 3 cohorts (identified).",
         "CAUTION: nb_mandats is a weak exclusion restriction (plausibly affects reelection directly, not only via candidacy); numerical identification is not the same as a credible restriction.",
         sep = "\n")) +
  theme_bw(base_size = 12) +
  theme(plot.caption = element_text(hjust = 0, color = "grey40"))

ggsave(file.path(FIG, "fig_heckman_simple.png"), p, width = 10, height = 5, dpi = 200)
cat(sprintf("Saved -> %s\n", file.path(FIG, "fig_heckman_simple.png")))
