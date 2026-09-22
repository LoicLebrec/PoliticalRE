# THE main results table -- the one table for the paper's Results section,
# not a robustness grid. Pulls the headline estimate from each of the 3
# empirical strategies (already computed by their own scripts, this just
# assembles them side by side):
#   TWFE     Cohort B (2014-2020) only, socioeconomically matched control
#            (twfe/data_results_all_specs.csv, Reference row)
#   CS       Pooled across all 3 cohorts (2014/2020/2026), matched control
#            (callaway_santanna/tables/table_cs_summary.csv)
#   Heckman  Cohort B (2014-2020) only, same window as TWFE
#            (heckman/tables/table_heckman_simple.csv) -- covers only 2 of
#            the 6 outcomes (candidacy = selection eq, reelection = outcome
#            eq); NA elsewhere, Heckman was never specified for the other 4.
#
# NOT an apples-to-apples panel: TWFE and Heckman are both Cohort-B-only
# (same 2x2 window), CS pools all 3 cohorts (different, larger sample) --
# flagged in the table footnote so a reader doesn't misread row-consistency
# across columns as sameness of sample.
#
# Output: tables/table_main_results.{csv,tex}
#         figures/fig_main_results_slide.png -- slide-ready coefficient
#         plot version of the same table, for a talk (not the paper itself):
#         big text, minimal chrome, readable projected from the back of a
#         room in ~10s.

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(tidyr); library(stringr); library(kableExtra); library(ggplot2)
})

PROJECT <- Sys.getenv("POLITICALRE_ROOT", unset = "/home/loiclebrec/ENRpolitical/Python/PoliticalRE")
PUB     <- file.path(PROJECT, "simple_regression/publication")
TAB     <- file.path(PUB, "tables")
FIG     <- file.path(PUB, "figures")
dir.create(TAB, showWarnings = FALSE, recursive = TRUE)
dir.create(FIG, showWarnings = FALSE, recursive = TRUE)

OUT_ORDER <- c("Candidacy (pp)","Reelection (pp)","Winner vote share (% valid votes)",
              "Abstention (% registered)","Candidate turnover (%)","Incumbent vote share (% valid votes)")
# Values here must match table_cs_summary.csv's own outcome strings exactly
# (that's the join key used below) -- CS keeps "(pp)" for Candidacy/
# Reelection, unlike the other 4 which drop the "valid votes"/"registered"
# qualifier down to a bare "(%)".
OUT_SHORT <- c("Candidacy (pp)"="Candidacy (pp)", "Reelection (pp)"="Reelection (pp)",
               "Winner vote share (% valid votes)"="Winner vote share (%)",
               "Abstention (% registered)"="Abstention (%)",
               "Candidate turnover (%)"="Candidate turnover (%)",
               "Incumbent vote share (% valid votes)"="Incumbent vote share (%)")

stars <- function(p) case_when(p < .01 ~ "***", p < .05 ~ "**", p < .10 ~ "*", TRUE ~ "")
fmt <- function(est, p) sprintf("%+.2f%s", est, stars(p))

# ── TWFE: Cohort B reference row, matched control ──────────────────────────
# outcome labels in this file embed a literal newline ("Candidacy\n(pp)"),
# not a space -- normalize before matching against OUT_SHORT/OUT_ORDER.
twfe <- read_csv(file.path(PUB, "twfe/data_results_all_specs.csv"), show_col_types = FALSE) %>%
  filter(is_ref) %>%
  mutate(outcome = str_replace_all(outcome, "\n", " ")) %>%
  transmute(outcome, twfe_est = estimate, twfe_se = se, twfe_p = p, twfe_n = n_trt)

# ── CS: pooled ATT, matched control ─────────────────────────────────────────
cs <- read_csv(file.path(PUB, "callaway_santanna/tables/table_cs_summary.csv"), show_col_types = FALSE) %>%
  filter(control == "Socioeconomically matched control") %>%
  transmute(outcome_short = outcome, cs_est = overall_att, cs_se = overall_se, cs_p = overall_p)

# ── Heckman: Cohort B only, mapped onto Candidacy/Reelection (coefficients
# are on the 0-1 probability scale -- x100 to match the pp scale used
# everywhere else in this table) ────────────────────────────────────────────
heck_raw <- read_csv(file.path(PUB, "heckman/tables/table_heckman_simple.csv"), show_col_types = FALSE) %>%
  filter(Cohort == "B")
heck <- tibble(
  outcome_short = c("Candidacy (pp)", "Reelection (pp)"),
  heck_est = c(heck_raw$Estimate[heck_raw$Equation == "Selection (candidacy)"],
               heck_raw$Estimate[heck_raw$Equation == "Outcome (reelection | ran again)"]) * 100,
  heck_se  = c(heck_raw$SE[heck_raw$Equation == "Selection (candidacy)"],
               heck_raw$SE[heck_raw$Equation == "Outcome (reelection | ran again)"]) * 100,
  heck_p   = c(heck_raw$p[heck_raw$Equation == "Selection (candidacy)"],
               heck_raw$p[heck_raw$Equation == "Outcome (reelection | ran again)"])
)

main <- twfe %>%
  mutate(outcome_short = recode(outcome, !!!OUT_SHORT)) %>%
  left_join(cs, by = "outcome_short") %>%
  left_join(heck, by = "outcome_short") %>%
  mutate(outcome_short = factor(outcome_short, levels = unname(OUT_SHORT[OUT_ORDER]))) %>%
  arrange(outcome_short) %>%
  transmute(
    Outcome = outcome_short,
    `N treated` = twfe_n,
    `TWFE (Cohort B)` = fmt(twfe_est, twfe_p),
    `TWFE SE` = sprintf("%.2f", twfe_se),
    `CS (pooled)` = fmt(cs_est, cs_p),
    `CS SE` = sprintf("%.2f", cs_se),
    `Heckman (Cohort B)` = if_else(is.na(heck_est), "--", fmt(heck_est, heck_p)),
    `Heckman SE` = if_else(is.na(heck_se), "--", sprintf("%.2f", heck_se))
  )

write_csv(main, file.path(TAB, "table_main_results.csv"))
cat(sprintf("Saved -> %s\n", file.path(TAB, "table_main_results.csv")))
print(main)

tab_latex <- main %>%
  kbl(format = "latex", booktabs = TRUE, escape = TRUE,
      caption = "Main results: headline estimate by outcome, across all 3 empirical strategies",
      label = "main_results", linesep = "") %>%
  kable_styling(latex_options = c("hold_position"), font_size = 9) %>%
  add_header_above(c(" " = 2, "TWFE" = 2, "Callaway-Sant'Anna" = 2, "Heckman selection" = 2)) %>%
  footnote(general = paste(
    "TWFE and Heckman: Cohort B only (2014-2020, single 2x2 window). CS: pooled across all 3 cohorts (2014/2020/2026); NOT the same sample as the other two columns, shown together for comparison, not as three estimates of an identical parameter.",
    "All 3 use the socioeconomically matched control pool. Heckman coefficients are LPM marginal effects, rescaled x100 to the same pp units as TWFE/CS.",
    "N treated is the TWFE treated-commune count per outcome (varies with outcome-specific missingness); Heckman (Cohort B) has 496 treated communes of 7,415 total; CS pools 1,733 treated communes across all 3 cohorts before per-outcome missingness.",
    "Heckman covers only Candidacy (selection equation) and Reelection (outcome equation); '--' where not estimated.",
    "*** p<0.01, ** p<0.05, * p<0.10.",
    sep = " "),
    threeparttable = TRUE, escape = FALSE)

writeLines(as.character(tab_latex), file.path(TAB, "table_main_results.tex"))
cat(sprintf("Saved -> %s\n", file.path(TAB, "table_main_results.tex")))

# ── Slide-ready coefficient plot: same numbers as the table above, long
# format for geom_pointrange (one row per method x outcome, not per outcome)
# ────────────────────────────────────────────────────────────────────────
# Plot-only method labels spell out which elections feed each estimate --
# table_main_results.tex keeps the shorter "Cohort B"/"pooled" column
# headers (footnote already gives the years), but a standalone figure gets
# copied out of that context, so it needs the years on its own face. TWFE
# and Heckman both use only the 2014->2020 window (Cohort B); CS pools all
# 3 cohorts, meaning all 4 election years including 2026 (Cohort C).
main_long <- twfe %>%
  mutate(outcome_short = recode(outcome, !!!OUT_SHORT)) %>%
  left_join(cs, by = "outcome_short") %>%
  left_join(heck, by = "outcome_short") %>%
  mutate(outcome_short = factor(outcome_short, levels = unname(OUT_SHORT[OUT_ORDER]))) %>%
  transmute(
    outcome_short,
    `TWFE (2014→2020)`         = twfe_est, `TWFE (2014→2020)_se`         = twfe_se,
    `CS (2008–2026, pooled)`   = cs_est,   `CS (2008–2026, pooled)_se`   = cs_se,
    `Heckman (2014→2020)`      = heck_est, `Heckman (2014→2020)_se`      = heck_se
  ) %>%
  pivot_longer(-outcome_short, names_to = "method", values_to = "value") %>%
  mutate(is_se = str_detect(method, "_se$"), method = str_remove(method, "_se$")) %>%
  group_by(outcome_short, method) %>%
  summarise(estimate = value[!is_se], se = value[is_se], .groups = "drop") %>%
  filter(!is.na(estimate)) %>%
  mutate(ci_low = estimate - 1.96*se, ci_high = estimate + 1.96*se,
         method = factor(method, levels = c("TWFE (2014→2020)", "CS (2008–2026, pooled)", "Heckman (2014→2020)")))

p_slide <- ggplot(main_long, aes(x = estimate, y = method, color = method)) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "grey55", linewidth = 0.7) +
  geom_pointrange(aes(xmin = ci_low, xmax = ci_high), linewidth = 1.3, size = 1.3) +
  facet_wrap(~outcome_short, scales = "free_x", ncol = 3) +
  scale_color_manual(values = c("TWFE (2014→2020)" = "#2a78d6", "CS (2008–2026, pooled)" = "#e34948",
                                 "Heckman (2014→2020)" = "#1baf7a"), guide = "none") +
  labs(title = "Wind farms and mayoral elections",
       subtitle = "Main estimate, 3 methods, 95% CI — election years shown per method",
       x = "Estimated effect (pp / %)", y = NULL) +
  theme_minimal(base_size = 20) +
  theme(
    strip.text = element_text(face = "bold", size = 15),
    axis.text.y = element_text(size = 14, face = "bold"),
    axis.text.x = element_text(size = 11),
    axis.title.x = element_text(size = 14),
    plot.title = element_text(face = "bold", size = 24),
    plot.subtitle = element_text(size = 15, color = "grey35"),
    panel.grid.minor = element_blank(),
    panel.spacing = unit(1.3, "lines"),
    plot.margin = margin(15, 20, 15, 15)
  )

ggsave(file.path(FIG, "fig_main_results_slide.png"), p_slide, width = 15, height = 8.5, dpi = 200)
cat(sprintf("Saved -> %s\n", file.path(FIG, "fig_main_results_slide.png")))
