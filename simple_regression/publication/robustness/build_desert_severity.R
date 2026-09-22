# Continuous-dose robustness for the desert-basket result: does the effect
# scale with HOW MUCH of the basket a commune lost, relative to its own
# baseline -- not just whether it lost anything?
#
# The main desert result (build_results.R) treats "declined" as binary:
# losing 1 of 2 basket facilities counts identically to losing 1 of 20,
# even though the first is a much bigger relative shock to an already
# sparsely-equipped commune. Fixed here by replacing the 0/1 "declined"
# dummy with a continuous dose:
#   severity = (n_lo - n_hi) / n_lo   for treated (declined) communes
#              -- fraction of the yr_lo basket lost, in (0, 1]
#            = 0                      for matched-control communes
# Same matched-control sample as the binary case (build_control_groups.R's
# control_group_desert_cohort*.csv), same FE/clustering -- only the
# treatment column changes from indicator to dose, via
# robustness_common.R::run_twfe_cohort_dose().
#
# Caveat carried over from the option-1/option-2 discussion: severity is
# undefined-in-spirit for a commune with a tiny baseline (n_lo=1 losing it
# = severity 1.0, same ceiling as a commune with n_lo=20 losing all 20) --
# not floored/winsorized here, so a handful of tiny-baseline communes can
# sit at the severity=1 ceiling alongside genuinely catastrophic large
# losses. Read the "Candidacy"-style outcomes with that in mind if n_trt is
# small for a given cohort.
#
# A second run adds a baseline-severity-tercile x year fixed effect
# ("code_insee + annee + baseline_bucket^annee" in fixest's interacted-FE
# syntax): commune FE alone controls for each commune's baseline LEVEL
# (it's a dummy per commune, that's automatic), but NOT for the
# possibility that sparsely-equipped communes were already on a different
# secular trend than well-equipped ones, treatment or no treatment.
# baseline_bucket = tercile of n_lo (basket count at yr_lo), computed once
# per cohort among that cohort's own sample (treated + matched control).
#
# Output: tables/table_desert_severity.csv, figures/fig_desert_severity.png
#         tables/table_desert_severity_buckettrend.csv, figures/fig_desert_severity_buckettrend.png

source(file.path(Sys.getenv("POLITICALRE_ROOT", unset = "/home/loiclebrec/ENRpolitical/Python/PoliticalRE"),
                  "simple_regression/publication/robustness/robustness_common.R"))

FIG <- file.path(ROBUST, "figures"); TAB <- file.path(ROBUST, "tables")
panel_raw <- load_panel()
turnover  <- load_turnover()
case <- CLOSURE_CASES$desert
raw <- load_case_raw(case)

# Per cohort: severity vector + sample codes + baseline_bucket (tercile of
# n_lo, computed among that cohort's own treated+control sample so the
# tercile cutpoints aren't distorted by communes never entering the
# regression). Shared by both runs below. sequential_case_splits(), not
# plain case_split() per cohort -- must match build_control_groups.R's
# not-yet-treated accumulation (see that script + robustness_common.R
# header on sequential_case_splits for why: without it a commune already
# declined in an earlier cohort could re-enter later as "declined" again
# or as a "clean" control).
splits_seq <- sequential_case_splits(case, raw, COHORTS3, panel_raw)
cohort_inputs <- lapply(COHORTS3, function(co) {
  counts_lo <- counts_at(raw, co$yr_lo); counts_hi <- counts_at(raw, co$yr_hi)
  split <- splits_seq[[co$label]]
  ctrl <- read_csv(file.path(ROBUST, sprintf("data/control_group_desert_cohort%s.csv", co$label)),
                    col_types=col_spec) %>% pull(code_insee) %>% unique()

  n_lo_declined <- counts_lo[split$declined]
  n_hi_declined <- counts_hi[split$declined]; n_hi_declined[is.na(n_hi_declined)] <- 0L
  severity <- setNames((n_lo_declined - n_hi_declined) / n_lo_declined, split$declined)
  severity <- c(severity, setNames(rep(0, length(ctrl)), ctrl))
  sample_codes <- c(split$declined, ctrl)

  baseline_n <- counts_lo[sample_codes]; baseline_n[is.na(baseline_n)] <- 0L
  baseline_bucket <- tibble(code_insee = sample_codes,
                             baseline_bucket = factor(ntile(baseline_n, 3), labels = c("Low baseline","Mid baseline","High baseline")))

  cat(sprintf("Cohort %s: severity range [%.3f, %.3f], median %.3f (treated only)\n",
              co$label, min(severity[severity>0]), max(severity[severity>0]), median(severity[severity>0])))
  list(cohort=co, severity=severity, sample_codes=sample_codes, baseline_bucket=baseline_bucket)
})

finalize <- function(res) res %>%
  mutate(ci_low=estimate-1.96*se, ci_high=estimate+1.96*se,
         outcome=factor(outcome, levels=sapply(OUTCOMES, `[[`, "label")),
         method=factor(method, levels=sapply(COHORTS3, `[[`, "method_lbl")))

results <- finalize(bind_rows(lapply(cohort_inputs, function(ci)
  run_twfe_cohort_dose(panel_raw, turnover, ci$cohort, "severity", ci$severity, ci$sample_codes))))

write_csv(results %>% mutate(across(c(estimate,se,ci_low,ci_high), ~round(.x,3))),
          file.path(TAB, "table_desert_severity.csv"))
cat(sprintf("Saved -> %s\n", file.path(TAB, "table_desert_severity.csv")))
print(results, n=20)

make_slide_figure(results,
  title="Public-service desertification, DOSE not indicator -- severity = fraction of basket lost",
  subtitle="Continuous treatment (0 for control, (n_lo-n_hi)/n_lo for declined), same matched sample as the binary result, 95% CI",
  out_path=file.path(FIG, "fig_desert_severity.png"))

# ── Second run: + baseline-severity-tercile x year FE ────────────────────
results_trend <- finalize(bind_rows(lapply(cohort_inputs, function(ci)
  run_twfe_cohort_dose(panel_raw, turnover, ci$cohort, "severity", ci$severity, ci$sample_codes,
                        fe_extra="baseline_bucket^annee", extra_data=ci$baseline_bucket))))

write_csv(results_trend %>% mutate(across(c(estimate,se,ci_low,ci_high), ~round(.x,3))),
          file.path(TAB, "table_desert_severity_buckettrend.csv"))
cat(sprintf("Saved -> %s\n", file.path(TAB, "table_desert_severity_buckettrend.csv")))
print(results_trend, n=20)

make_slide_figure(results_trend,
  title="Public-service desertification, dose + baseline-tercile x year FE",
  subtitle="Same as above, plus a fixed effect letting low/mid/high baseline-equipment communes follow their own secular trend, 95% CI",
  out_path=file.path(FIG, "fig_desert_severity_buckettrend.png"))

# ── Side-by-side comparison, all 3 specs ─────────────────────────────────
binary <- read_csv(file.path(TAB, "table_desert_main.csv"), show_col_types=FALSE) %>%
  mutate(spec="Binary (declined 0/1)")
dose <- results %>% mutate(outcome=as.character(outcome), method=as.character(method),
                            across(c(estimate,se,ci_low,ci_high), ~round(.x,3)), spec="Continuous (severity dose)")
dose_trend <- results_trend %>% mutate(outcome=as.character(outcome), method=as.character(method),
                            across(c(estimate,se,ci_low,ci_high), ~round(.x,3)), spec="Continuous + baseline-tercile x year FE")
compare <- bind_rows(binary %>% select(cohort,outcome,estimate,se,p,ci_low,ci_high,spec),
                      dose %>% select(cohort,outcome,estimate,se,p,ci_low,ci_high,spec),
                      dose_trend %>% select(cohort,outcome,estimate,se,p,ci_low,ci_high,spec))
write_csv(compare, file.path(TAB, "table_desert_binary_vs_severity.csv"))
cat(sprintf("Saved -> %s\n", file.path(TAB, "table_desert_binary_vs_severity.csv")))
