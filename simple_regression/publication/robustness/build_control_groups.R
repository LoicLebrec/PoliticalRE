# Matched control groups for every publication/robustness/ case: D705
# (CADA, opening design), D107 (maternite), C104 (ecole elementaire), and
# the 12-code public-service basket (all 3 closure design). One script for
# all 4 -- see robustness_common.R for the shared matching machinery and
# CLOSURE_CASES registry.
#
# Opening vs closure design: for D705, any commune could plausibly gain a
# CADA, so "never had one" is a sensible control universe. For a closure
# (maternity ward, school, basket decline), only communes that HAD the
# thing in yr_lo are even at risk of losing it -- comparing a closure to a
# commune that never had one at all conflates "lost X" with "is the kind
# of commune that has X in the first place" (this is exactly why D705's
# first control attempt, a naive never-treated pool, was wrong -- see
# `git log` on this file). Every case here is matched via probit(treated ~
# density + log(pop) + log(income) + dept FE), P10 threshold.
#
# Output: data/control_group_{d705,hospital,school,desert}_cohort{A,B,C}.csv
#         tables/table_{hospital,school,desert}_descriptive.csv

source(file.path(Sys.getenv("POLITICALRE_ROOT", unset = "/home/loiclebrec/ENRpolitical/Python/PoliticalRE"),
                  "simple_regression/publication/robustness/robustness_common.R"))

OUT_DIR <- file.path(ROBUST, "data"); TAB_DIR <- file.path(ROBUST, "tables")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)
dir.create(TAB_DIR, showWarnings = FALSE, recursive = TRUE)

panel_raw <- load_panel()

# ── D705 (opening design) ──────────────────────────────────────────────
cat("========== D705 (CADA, opening design) ==========\n")
d705_raw <- read_csv(file.path(PROJECT, "data/BPE_adisp/derived/d705_by_commune_year.csv"),
                      col_types = cols(code_insee = col_character(), annee = col_integer(), n_d705 = col_integer())) %>%
  mutate(code_insee = pad5(code_insee))
d705_presence <- function(yr) d705_raw %>% filter(annee == yr, n_d705 > 0) %>% distinct(code_insee) %>% pull(code_insee)
d705_ever_treated <- d705_raw %>% filter(n_d705 > 0) %>% distinct(code_insee) %>% pull(code_insee)

# Rural-only pool (parity fix, see robustness_common.R::opening_codes()).
# NOT dept-filtered like wind's control pool -- see robustness_common.R
# note above dept_ok_codes' removal: D705 is too rare for that filter to
# clear any department. Department confounding still handled via
# factor(dep) inside match_control()'s probit.
for (co in COHORTS3) {
  cat(sprintf("-- Cohort %s (%d->%d) --\n", co$label, co$yr_lo, co$yr_hi))
  treated <- opening_codes(panel_raw, co$yr_lo, co$yr_hi, d705_presence(co$yr_lo), d705_presence(co$yr_hi))
  cat(sprintf("Treated: %d communes\n", length(treated)))
  pool <- panel_raw %>% filter(annee == co$yr_lo, categorie_dens %in% DENS_OK,
                                !code_insee %in% d705_ever_treated) %>% distinct(code_insee) %>% pull(code_insee)
  ctrl <- match_control(panel_raw, co$yr_lo, treated, pool, load_income(co$yr_lo))
  write_csv(tibble(code_insee = ctrl), file.path(OUT_DIR, sprintf("control_group_d705_cohort%s.csv", co$label)))
  cat(sprintf("Saved control_group_d705_cohort%s.csv (%d communes)\n", co$label, length(ctrl)))
  bal <- compute_balance(panel_raw, co$yr_lo, treated, ctrl)
  cat("Density balance -- Treated:\n"); print(bal$dens_treated); cat("Matched control:\n"); print(bal$dens_control)
}

# ── D107 / C104 / basket (closure design, shared shape) ─────────────────
# sequential_case_splits(): cohorts run IN ORDER (A, B, C) and a commune
# already "declined" in an earlier cohort is removed from BOTH later
# treated pools (first-decline-only) and later control pools (a
# once-treated commune is never used as a clean comparison again) -- see
# robustness_common.R header on sequential_case_splits() for why plain
# case_split() per cohort let the same commune be treated repeatedly.
for (case in CLOSURE_CASES) {
  cat(sprintf("\n========== %s (closure design) ==========\n", case$label))
  raw <- load_case_raw(case)
  splits <- sequential_case_splits(case, raw, COHORTS3, panel_raw)

  # Rural-only pools already enforced by case_split() (see
  # robustness_common.R). No dept-level pool restriction -- same rarity
  # issue as D705 (see robustness_common.R note above dept_ok_codes'
  # removal).
  desc_rows <- list()
  for (co in COHORTS3) {
    cat(sprintf("-- Cohort %s (%d->%d) --\n", co$label, co$yr_lo, co$yr_hi))
    split <- splits[[co$label]]
    cat(sprintf("At-risk (%s in %d): %d | Declined by %d (first time only): %d | Survived (never yet treated): %d\n",
                case$at_risk_label, co$yr_lo, length(split$at_risk), co$yr_hi, length(split$declined), length(split$survived)))
    ctrl <- match_control(panel_raw, co$yr_lo, split$declined, split$survived, load_income(co$yr_lo))
    out_path <- file.path(OUT_DIR, sprintf("control_group_%s_cohort%s.csv", case$id, co$label))
    write_csv(tibble(code_insee = ctrl), out_path)
    cat(sprintf("Saved -> %s (%d communes)\n", out_path, length(ctrl)))

    bal <- compute_balance(panel_raw, co$yr_lo, split$declined, ctrl)
    desc_rows[[length(desc_rows)+1]] <- tibble(
      cohort = co$label, treatment = case$treatment_desc(co$yr_lo, co$yr_hi), control_choice = case$control_note,
      n_at_risk = length(split$at_risk), n_treated = length(split$declined), n_control_pool = length(split$survived),
      n_matched_control = length(ctrl),
      median_inscrits_treated = bal$median_inscrits_treated, median_inscrits_control = bal$median_inscrits_control,
      dominant_density_treated = bal$dominant_density_treated, dominant_density_control = bal$dominant_density_control
    )
    cat("Density balance (declined vs matched control):\n")
    print(bal$dens_treated); print(bal$dens_control)
  }
  desc_path <- file.path(TAB_DIR, sprintf("table_%s_descriptive.csv", case$id))
  write_csv(bind_rows(desc_rows), desc_path)
  cat(sprintf("Saved -> %s\n", desc_path))
}
