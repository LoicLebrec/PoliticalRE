# Appendix counterpart to build_main_results_table.R -- same headline
# estimates, but under the BASELINE control pool (all rural, never-treated
# communes in a wind-developed department, no further matching) instead of
# the socioeconomically selected pool used as the paper's main
# specification. Lets a reader see directly that the null result does not
# depend on which control group is used.
#
#   TWFE  Cohort B (2014-2020), baseline control
#         (twfe/data_results_all_specs_baseline.csv, Reference row)
#   CS    Pooled across all 3 cohorts, baseline control
#         (callaway_santanna/tables/table_cs_summary.csv, "Baseline control" rows)
#   Heckman was never run on the baseline pool (main text only reports it
#   under selected control) -- omitted here rather than filled with NA.
#
# Output: tables/table_baseline_results.{csv,tex}

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(stringr); library(kableExtra)
})

PROJECT <- Sys.getenv("POLITICALRE_ROOT", unset = "/home/loiclebrec/ENRpolitical/Python/PoliticalRE")
PUB     <- file.path(PROJECT, "simple_regression/publication")
TAB     <- file.path(PUB, "tables")
dir.create(TAB, showWarnings = FALSE, recursive = TRUE)

OUT_ORDER <- c("Candidacy (pp)","Reelection (pp)","Winner vote share (% valid votes)",
              "Abstention (% registered)","Candidate turnover (%)","Incumbent vote share (% valid votes)")
OUT_SHORT <- c("Candidacy (pp)"="Candidacy (pp)", "Reelection (pp)"="Reelection (pp)",
               "Winner vote share (% valid votes)"="Winner vote share (%)",
               "Abstention (% registered)"="Abstention (%)",
               "Candidate turnover (%)"="Candidate turnover (%)",
               "Incumbent vote share (% valid votes)"="Incumbent vote share (%)")

stars <- function(p) case_when(p < .01 ~ "***", p < .05 ~ "**", p < .10 ~ "*", TRUE ~ "")
fmt <- function(est, p) sprintf("%+.2f%s", est, stars(p))

twfe <- read_csv(file.path(PUB, "twfe/data_results_all_specs_baseline.csv"), show_col_types = FALSE) %>%
  filter(is_ref) %>%
  mutate(outcome = str_replace_all(outcome, "\n", " ")) %>%
  transmute(outcome, twfe_est = estimate, twfe_se = se, twfe_p = p, twfe_n = n_trt)

cs <- read_csv(file.path(PUB, "callaway_santanna/tables/table_cs_summary.csv"), show_col_types = FALSE) %>%
  filter(control == "Baseline control") %>%
  transmute(outcome_short = outcome, cs_est = overall_att, cs_se = overall_se, cs_p = overall_p)

main <- twfe %>%
  mutate(outcome_short = recode(outcome, !!!OUT_SHORT)) %>%
  left_join(cs, by = "outcome_short") %>%
  mutate(outcome_short = factor(outcome_short, levels = unname(OUT_SHORT[OUT_ORDER]))) %>%
  arrange(outcome_short) %>%
  transmute(
    Outcome = outcome_short,
    `N treated` = twfe_n,
    `TWFE (Cohort B)` = fmt(twfe_est, twfe_p),
    `TWFE SE` = sprintf("%.2f", twfe_se),
    `CS (pooled)` = fmt(cs_est, cs_p),
    `CS SE` = sprintf("%.2f", cs_se)
  )

write_csv(main, file.path(TAB, "table_baseline_results.csv"))
cat(sprintf("Saved -> %s\n", file.path(TAB, "table_baseline_results.csv")))
print(main)

tab_latex <- main %>%
  kbl(format = "latex", booktabs = TRUE, escape = TRUE,
      caption = "Headline estimates under the baseline control group (Appendix counterpart to Table~\\ref{tab:main_results})",
      label = "baseline_results", linesep = "") %>%
  kable_styling(latex_options = c("hold_position"), font_size = 9) %>%
  add_header_above(c(" " = 2, "TWFE" = 2, "Callaway-Sant'Anna" = 2)) %>%
  footnote(general = paste(
    "Same specifications as Table~\\ref{tab:main_results}, baseline control group instead of selected control (Section~\\ref{sec:data}).",
    "TWFE: Cohort B only (2014-2020, single 2x2 window). CS: pooled across all 3 cohorts (2014/2020/2026); NOT the same sample as the TWFE column.",
    "Heckman was not re-estimated on the baseline pool and is omitted here (main text reports it under selected control only).",
    "N treated is the TWFE treated-commune count per outcome (varies with outcome-specific missingness); CS pools 1,733 treated communes across all 3 cohorts before per-outcome missingness.",
    "*** p<0.01, ** p<0.05, * p<0.10.",
    sep = " "),
    threeparttable = TRUE, escape = FALSE)

writeLines(as.character(tab_latex), file.path(TAB, "table_baseline_results.tex"))
cat(sprintf("Saved -> %s\n", file.path(TAB, "table_baseline_results.tex")))
