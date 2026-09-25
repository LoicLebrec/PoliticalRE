# Two tables per cohort (A/B/C), same N/estimate/SE/CI/p/stars format:
#   1. table_all_specs*.{csv,tex}          -- main robustness (milestones,
#      regions, electoral system, mayor stability, size, cohorts,
#      installation power, competitiveness, income), socioeconomically
#      matched control group throughout.
#   2. table_all_specs*_baseline.{csv,tex} -- IDENTICAL structure/rows to
#      table 1, but every specification recomputed against the BASELINE
#      (unmatched) control group instead. Full parallel comparison.
#
# Cohort B keeps its original (unsuffixed) filenames -- the paper's main
# result, nothing downstream that reads table_all_specs.csv changes.
# Cohorts A and C are appendix material: table_all_specs_cohortA.csv,
# table_all_specs_cohortC.csv (+ baseline variants).
#
# Source: data_results_all_specs*.csv (cached by build_robustness_combined.R)

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(stringr); library(kableExtra)
})

PROJECT <- Sys.getenv("POLITICALRE_ROOT", unset = ".")
PUB     <- file.path(PROJECT, "code/twfe")
TAB     <- file.path(PUB, "tables")
dir.create(TAB, showWarnings = FALSE, recursive = TRUE)

stars <- function(p) case_when(p < .01 ~ "***", p < .05 ~ "**", p < .10 ~ "*", TRUE ~ "")

CAT_ORDER <- c("Reference","Milestones","Regions","Electoral system","Mayor stability",
              "Municipality size","Installation power","Cohorts","Competitiveness","Income")
OUT_ORDER <- c("Candidacy (pp)","Reelection (pp)","Winner vote share (% valid votes)",
              "Abstention (% registered)","Candidate turnover (%)","Incumbent vote share (% valid votes)")

prep <- function(res) {
  res %>%
    mutate(
      category = case_when(
        is_ref                                        ~ "Reference",
        str_detect(spec, "^\\[Milestones\\]")         ~ "Milestones",
        str_detect(spec, "^\\[Regions\\]")            ~ "Regions",
        str_detect(spec, "^\\[Electoral system\\]")   ~ "Electoral system",
        str_detect(spec, "^\\[Stability\\]")          ~ "Mayor stability",
        str_detect(spec, "^\\[Municipality size\\]")  ~ "Municipality size",
        str_detect(spec, "^\\[Installation power\\]") ~ "Installation power",
        str_detect(spec, "^\\[Cohorts\\]")            ~ "Cohorts",
        str_detect(spec, "^\\[Competitiveness\\]")    ~ "Competitiveness",
        str_detect(spec, "^\\[Income\\]")             ~ "Income",
        str_detect(spec, "^\\[Control group definition\\]") ~ "Control group definition",
        TRUE ~ "Other"
      ),
      specification = str_remove(spec, "^\\[[^]]+\\]\\s*") %>% str_remove("\\s*\\(n[^)]*\\)$") %>%
        str_replace_all("\n", " "),
      outcome_short = str_replace_all(outcome, "\n", " "),
      N         = n_trt,
      Estimate  = sprintf("%+.2f%s", estimate, stars(p)),
      SE        = sprintf("%.2f", se),
      CI95      = sprintf("[%.2f, %.2f]", ci_low, ci_high),
      p_value   = sprintf("%.3f", p)
    )
}

write_table <- function(dat, csv_name, tex_name, caption, group_cols, has_category, control_note) {
  csv_cols <- if (has_category)
    c("Outcome" = "outcome_short", "Category" = "category", "Specification" = "specification",
      "N" = "N", "Estimate" = "estimate", "SE" = "se", "CI_low" = "ci_low", "CI_high" = "ci_high",
      "p" = "p", "Signif" = "signif")
  else
    c("Outcome" = "outcome_short", "Specification" = "specification",
      "N" = "N", "Estimate" = "estimate", "SE" = "se", "CI_low" = "ci_low", "CI_high" = "ci_high",
      "p" = "p", "Signif" = "signif")

  write_csv(
    dat %>% mutate(across(c(estimate, se, ci_low, ci_high), ~round(.x, 2)), p = round(p, 3)) %>%
      select(all_of(csv_cols)),
    file.path(TAB, csv_name)
  )
  cat(sprintf("Saved -> %s (%d rows)\n", file.path(TAB, csv_name), nrow(dat)))

  cols_sel <- if (has_category)
    c("Outcome" = "outcome_short", "Category" = "category", "Specification" = "specification",
      "N" = "N", "Estimate" = "Estimate", "SE" = "SE", "95% CI" = "CI95", "p" = "p_value")
  else
    c("Outcome" = "outcome_short", "Specification" = "specification",
      "N" = "N", "Estimate" = "Estimate", "SE" = "SE", "95% CI" = "CI95", "p" = "p_value")

  tab_latex <- dat %>% select(all_of(cols_sel)) %>%
    kbl(format = "latex", booktabs = TRUE, longtable = TRUE, escape = TRUE,
        caption = caption, label = paste0("tab:", tools::file_path_sans_ext(tex_name)), linesep = "") %>%
    kable_styling(latex_options = c("repeat_header", "hold_position"), font_size = 8) %>%
    collapse_rows(columns = group_cols, valign = "top") %>%
    footnote(general = paste(
      control_note$treatment,
      control_note$control,
      "TWFE: Y ~ eolien\\_treated | municipality + year, municipality-clustered SE.",
      "N = treated municipalities. *** p<0.01, ** p<0.05, * p<0.10.",
      sep = " "),
      threeparttable = TRUE, escape = FALSE)

  writeLines(as.character(tab_latex), file.path(TAB, tex_name))
  cat(sprintf("Saved -> %s\n", file.path(TAB, tex_name)))
}

MATCHED_CONTROL_NOTE  <- "CONTROL: rural density 5-7, never treated, department with > 3 treated municipalities, probit-matched (wind + log(pop) + log(income) + log(investment) + department FE, P10 threshold of treated)."
BASELINE_CONTROL_NOTE <- "CONTROL: rural density 5-7, never treated, department with >= 3 wind parks in Parc.csv, present at all 4 elections, NO income/investment/wind matching (baseline pool, control_group_baseline.csv)."

build_cohort_tables <- function(coh_label, yr_lo, yr_hi, suffix) {
  treatment_note <- sprintf("TREATMENT: rural density 5-7, 0 wind farms in %d -> >=1 by %d.", yr_lo, yr_hi)

  res1 <- prep(read_csv(file.path(PUB, sprintf("data_results_all_specs%s.csv", suffix)), show_col_types = FALSE))
  res1_main <- res1 %>% filter(category != "Control group definition") %>%
    mutate(category = factor(category, levels = CAT_ORDER),
           outcome_short = factor(outcome_short, levels = OUT_ORDER)) %>%
    arrange(outcome_short, category, specification)
  write_table(res1_main, sprintf("table_all_specs%s.csv", suffix), sprintf("table_all_specs%s.tex", suffix),
             sprintf("Complete robustness check -- all outcome variables x all heterogeneity specifications, socioeconomically matched control (Cohort %s)", coh_label),
             group_cols = 1:2, has_category = TRUE,
             control_note = list(treatment = treatment_note, control = MATCHED_CONTROL_NOTE))

  res2 <- prep(read_csv(file.path(PUB, sprintf("data_results_all_specs%s_baseline.csv", suffix)), show_col_types = FALSE))
  res2_main <- res2 %>% filter(category != "Control group definition") %>%
    mutate(category = factor(category, levels = CAT_ORDER),
           outcome_short = factor(outcome_short, levels = OUT_ORDER)) %>%
    arrange(outcome_short, category, specification)
  write_table(res2_main, sprintf("table_all_specs%s_baseline.csv", suffix), sprintf("table_all_specs%s_baseline.tex", suffix),
             sprintf("Complete robustness check -- all outcome variables x all heterogeneity specifications, baseline control (Cohort %s)", coh_label),
             group_cols = 1:2, has_category = TRUE,
             control_note = list(treatment = treatment_note, control = BASELINE_CONTROL_NOTE))
}

# ── Cohort B: main result, unsuffixed filenames (unchanged) ────────────────
build_cohort_tables("B", 2014L, 2020L, "")

# ── Cohorts A/C: appendix material ──────────────────────────────────────────
build_cohort_tables("A", 2008L, 2014L, "_cohortA")
build_cohort_tables("C", 2020L, 2026L, "_cohortC")
