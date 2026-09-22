# Master script -- runs the full publication pipeline end to end, in the
# correct dependency order. This order was NOT documented anywhere before
# this file (had to be reverse-engineered from grepping which script reads/
# writes which CSV) -- see README.md for the full dependency graph and the
# known data-provenance caveats before trusting a from-scratch run.
#
# Usage: Rscript run_pipeline.R
#
# Stops on the first error (does not try to continue with stale downstream
# inputs -- that silently happened once already: see README.md, "Why this
# script exists").

PROJECT <- Sys.getenv("POLITICALRE_ROOT", unset = "/home/loiclebrec/ENRpolitical/Python/PoliticalRE")

steps <- list(
  list(n = "1. Build base panel",                 f = "simple_regression/panel/build_panel.R"),
  list(n = "2. Enrich panel with mayor bio data",  f = "simple_regression/enrich_panel_maires.R"),
  list(n = "3. Build matched control group",       f = "simple_regression/robsocioeco/build_control_new.R"),
  list(n = "4. TWFE: full robustness grid (23 specs x 6 outcomes x 2 control pools)",
                                                    f = "simple_regression/publication/twfe/build_robustness_combined.R"),
  list(n = "5. TWFE: master single-panel figure",  f = "simple_regression/publication/twfe/build_master_singlepanel.R"),
  list(n = "6. TWFE: results tables (csv/tex)",    f = "simple_regression/publication/twfe/build_results_table.R"),
  list(n = "7. TWFE: balance table",               f = "simple_regression/publication/twfe/build_balance_table.R"),
  list(n = "8. Heckman selection model",           f = "simple_regression/publication/heckman/build_heckman_simple.R"),
  list(n = "8b. IPW selection correction (TWFE, no exclusion restriction)",
                                                    f = "simple_regression/publication/twfe/build_ipw_selection.R"),
  list(n = "9. Callaway-Sant'Anna event study",     f = "simple_regression/publication/callaway_santanna/build_cs_eventstudy.R"),
  list(n = "10. Descriptive outputs (stats table, source comparison, treatment map)",
                                                    f = "simple_regression/publication/descriptive/build_descriptive.R"),
  list(n = "11. Main results table (TWFE x CS x Heckman)",
                                                    f = "simple_regression/publication/build_main_results_table.R"),
  list(n = "12. Baseline-pool results table (appendix counterpart to step 11)",
                                                    f = "simple_regression/publication/build_baseline_results_table.R"),
  list(n = "13. Robustness: placebo control groups (D705/desert/school, per cohort)",
                                                    f = "simple_regression/publication/robustness/build_control_groups.R"),
  list(n = "14. Robustness: placebo results tables (D705/desert/school/percode-abstention)",
                                                    f = "simple_regression/publication/robustness/build_results.R")
)

cat(sprintf("=== Publication pipeline: %d steps ===\n\n", length(steps)))

t_start <- Sys.time()
for (s in steps) {
  cat(sprintf("\n########## %s ##########\n", s$n))
  cat(sprintf("Script: %s\n", s$f))
  t0 <- Sys.time()
  status <- system2("Rscript", file.path(PROJECT, s$f), stdout = "", stderr = "")
  elapsed <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1)
  if (status != 0) {
    cat(sprintf("\n!!! FAILED at step: %s (exit code %d, after %.1fs) !!!\n", s$n, status, elapsed))
    cat("Stopping -- do not trust any step after this one; downstream scripts\n")
    cat("would silently run against stale inputs (this happened once during\n")
    cat("development, see README.md).\n")
    quit(status = 1)
  }
  cat(sprintf("OK (%.1fs)\n", elapsed))
}

cat(sprintf("\n=== Pipeline complete: %d/%d steps OK, total %.1f min ===\n",
            length(steps), length(steps),
            as.numeric(difftime(Sys.time(), t_start, units = "mins"))))
