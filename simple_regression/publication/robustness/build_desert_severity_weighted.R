# Rarity-weighted dose: build_desert_severity.R's severity treats losing a
# gendarmerie the same as losing a pharmacy, as long as the FRACTION of the
# commune's own basket lost is the same -- it ignores that some of the 12
# facility types are nationally scarce (maternite: ~500 nationwide) and
# others are common (GP doctor: ~60k nationwide). Losing the rare one is
# arguably a bigger loss of access than losing one of many common ones,
# even at the same personal/commune-level fraction.
#
# Fixed here: each facility type is weighted by the inverse of its OWN
# national total at yr_lo (rare type -> large weight), so
#   weighted_severity = [sum_k (n_lo_k - n_hi_k) * weight_k]
#                      / [sum_k n_lo_k * weight_k]
#                      , weight_k = 1 / national_total_k(yr_lo)
# -- a weighted fraction-lost, same (0, 1]-ish scale as the unweighted
# severity, but rare-type losses now dominate the numerator. A102
# (tresorerie) is excluded from BASKET_CONCEPTS entirely, not just
# weighted to 0 -- it was discontinued NATIONWIDE by 2014, so every
# commune that had one in 2008 loses it regardless of any local
# desertification story (see robustness_common.R::CLOSURE_CASES for the
# 16%-of-Cohort-A-declined-communes impact this had before it was
# excluded from the basket data itself, not just here).
#
# Same treated/control sample as build_desert_severity.R (sequential,
# not-yet-treated -- see build_control_groups.R), only the severity
# formula changes.
#
# Output: tables/table_desert_severity_weighted.csv,
#         figures/fig_desert_severity_weighted.png

source(file.path(Sys.getenv("POLITICALRE_ROOT", unset = "/home/loiclebrec/ENRpolitical/Python/PoliticalRE"),
                  "simple_regression/publication/robustness/robustness_common.R"))

FIG <- file.path(ROBUST, "figures"); TAB <- file.path(ROBUST, "tables")
LABELED <- file.path(PROJECT, "data/BPE_adisp/labeled")
BPE25   <- file.path(PROJECT, "data/BPE_adisp/bpe2025/DS_BPE_CSV_FR.zip")
panel_raw <- load_panel()
turnover  <- load_turnover()
case <- CLOSURE_CASES$desert
raw  <- load_case_raw(case)

# ── Raw BPE facility data, read once per year (basket's 12 concepts) ──────
YEAR_DATA <- list(
  `2008` = read_delim(file.path(LABELED, "bpe08_ensemble_labeled.csv"), delim=";", col_types=cols(.default="c"), progress=FALSE) %>%
    transmute(code_insee=pad5(DEPCOM), TYPEQU, NB_EQUIP=as.integer(NB_EQUIP)),
  `2014` = read_delim(file.path(LABELED, "bpe14_ensemble_labeled.csv"), delim=";", col_types=cols(.default="c"), progress=FALSE) %>%
    transmute(code_insee=pad5(DEPCOM), TYPEQU, NB_EQUIP=as.integer(NB_EQUIP)),
  `2020` = read_delim(file.path(LABELED, "bpe20_ensemble_labeled.csv"), delim=";", col_types=cols(.default="c"), progress=FALSE) %>%
    transmute(code_insee=pad5(DEPCOM), TYPEQU, NB_EQUIP=as.integer(NB_EQUIP))
)
unzip(BPE25, "DS_BPE_2025_data.csv", exdir=tempdir())
YEAR_DATA[["2025"]] <- read_delim(file.path(tempdir(),"DS_BPE_2025_data.csv"), delim=";", col_types=cols(.default="c"), progress=FALSE) %>%
  filter(GEO_OBJECT=="COM") %>% transmute(code_insee=pad5(GEO), TYPEQU=FACILITY_TYPE, NB_EQUIP=as.integer(OBS_VALUE))

BASKET_CONCEPTS <- c("a101","a104","c_maternelle","c_elementaire","c201",
                     "d101","d102","d103","d106","d107","d201","d301")

commune_counts <- function(concept, yr) {
  codes <- bpe_codes_for_year(concept, yr)
  YEAR_DATA[[as.character(yr)]] %>% filter(TYPEQU %in% codes) %>%
    group_by(code_insee) %>% summarise(n=sum(NB_EQUIP), .groups="drop")
}
national_total <- function(concept, yr) {
  codes <- bpe_codes_for_year(concept, yr)
  YEAR_DATA[[as.character(yr)]] %>% filter(TYPEQU %in% codes) %>% pull(NB_EQUIP) %>% sum(na.rm=TRUE)
}

# ── Reuse the SAME (already-fixed, sequential) treated/control sets ───────
splits <- sequential_case_splits(case, raw, COHORTS3, panel_raw)

# Weighted severity for the DECLINED communes only (control severity=0 is
# assigned by the caller, no need to compute it here).
weighted_severity_declined <- function(co, declined_codes) {
  per_commune <- tibble(code_insee = declined_codes)
  for (concept in BASKET_CONCEPTS) {
    nat_lo <- national_total(concept, co$yr_lo)
    if (nat_lo == 0) next  # e.g. A102 post-2008: excluded, no rare-type signal to weight
    w <- 1 / nat_lo
    c_lo <- commune_counts(concept, co$yr_lo) %>% rename(n_lo = n)
    c_hi <- commune_counts(concept, co$yr_hi) %>% rename(n_hi = n)
    per_commune <- per_commune %>%
      left_join(c_lo, by="code_insee") %>% left_join(c_hi, by="code_insee") %>%
      mutate(n_lo = coalesce(n_lo, 0L), n_hi = coalesce(n_hi, 0L),
             !!paste0("wloss_", concept) := (n_lo - n_hi) * w,
             !!paste0("wbase_", concept) := n_lo * w) %>%
      select(-n_lo, -n_hi)
  }
  wloss_cols <- grep("^wloss_", names(per_commune), value=TRUE)
  wbase_cols <- grep("^wbase_", names(per_commune), value=TRUE)
  per_commune <- per_commune %>%
    mutate(weighted_loss = rowSums(across(all_of(wloss_cols))),
           weighted_base  = rowSums(across(all_of(wbase_cols))))
  setNames(with(per_commune, weighted_loss / pmax(weighted_base, 1e-9)), per_commune$code_insee)
}

results <- bind_rows(lapply(COHORTS3, function(co) {
  declined <- splits[[co$label]]$declined
  ctrl <- read_csv(file.path(ROBUST, sprintf("data/control_group_desert_cohort%s.csv", co$label)), col_types=col_spec) %>%
    pull(code_insee) %>% unique()
  severity_declined <- weighted_severity_declined(co, declined)
  cat(sprintf("Cohort %s: weighted severity range [%.4f, %.4f], median %.4f (treated only)\n",
              co$label, min(severity_declined), max(severity_declined), median(severity_declined)))
  severity <- c(severity_declined, setNames(rep(0, length(ctrl)), ctrl))
  run_twfe_cohort_dose(panel_raw, turnover, co, "severity", severity, c(declined, ctrl))
})) %>%
  mutate(ci_low=estimate-1.96*se, ci_high=estimate+1.96*se,
         outcome=factor(outcome, levels=sapply(OUTCOMES, `[[`, "label")),
         method=factor(method, levels=sapply(COHORTS3, `[[`, "method_lbl")))

write_csv(results %>% mutate(across(c(estimate,se,ci_low,ci_high), ~round(.x,4))),
          file.path(TAB, "table_desert_severity_weighted.csv"))
cat(sprintf("Saved -> %s\n", file.path(TAB, "table_desert_severity_weighted.csv")))
print(results, n=20)

make_slide_figure(results,
  title="Rare services count more: dose weighted by national scarcity",
  subtitle="Same treated/control sample, but losing a rare service (e.g. maternity ward) counts more than losing a common one (e.g. GP), 95% CI",
  out_path=file.path(FIG, "fig_desert_severity_weighted.png"))
