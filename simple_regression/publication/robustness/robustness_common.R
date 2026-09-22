# Shared helpers for the publication/robustness/ pipelines (D705 opening,
# D107/C104/basket closures, per-code decomposition) -- probit-matched TWFE
# effect of a BPE facility change on French mayoral elections. Extracted
# after 5 near-identical copies of the same matching/regression/figure code
# had drifted across build_*_control.R / build_*_twfe.R /
# build_percode_abstention.R (caught by /simplify review). Source this
# file; don't re-copy its functions into a new script.

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(stringr); library(readxl); library(fixest); library(ggplot2)
})

PROJECT <- Sys.getenv("POLITICALRE_ROOT", unset = "/home/loiclebrec/ENRpolitical/Python/PoliticalRE")
ROBUST  <- file.path(PROJECT, "simple_regression/publication/robustness")

col_spec  <- cols(code_insee = col_character(), dep = col_character(), .default = col_guess())
clean_dep <- function(x) str_remove(x, "\\.0$")
pad5      <- function(x) str_pad(str_extract(as.character(x), "[0-9A-Za-z]+"), 5, "left", "0")

# Rural-only universe, matching robsocioeco/build_control_new.R's (wind)
# hard density restriction -- applied at yr_lo (baseline), same
# baseline-only convention as log_pop/log_rev elsewhere in this repo.
DENS_OK <- c("5", "6", "7")
rural_codes <- function(panel_raw, yr) {
  panel_raw %>% filter(annee == yr, categorie_dens %in% DENS_OK) %>% distinct(code_insee) %>% pull(code_insee)
}

# Same single 2013 investment snapshot used by robsocioeco/build_control_new.R
# (wind's matched control) -- no per-cohort equivalent exists, so every case/
# cohort here uses the same snapshot as the wind pipeline does for its own
# (single, Cohort-B-based) control match.
INVEST_2013 <- read_csv(file.path(PROJECT, "simple_regression/CRcreu11/data/invest_communes_2013.csv"),
                         col_types = col_spec) %>% rename(invest_2013 = invest_sd)

OUTCOMES <- list(
  list(var="recandidature_pp",          label="Candidacy (pp)"),
  list(var="reconduit_pp",              label="Reelection (pp)"),
  list(var="pct_voix_gagnant_exprimes", label="Winner vote share (%)"),
  list(var="pct_abstention",            label="Abstention (%)"),
  list(var="turnover_pp",               label="Candidate turnover (%)"),
  list(var="pct_voix_sortant_exprimes", label="Incumbent vote share (%)")
)

# Election-year cohorts shared by every pipeline here. yr_hi = BPE
# facility-snapshot year (treatment definition). yr_hi_elec = actual
# election year in panel.csv used for outcomes/post/FE -- these differ only
# for Cohort C: BPE's newest vintage is 2025 (~1y before the March 2026
# election), and panel.csv has no 2025 row at all (only election years are
# recorded: 2008/2014/2020/2026).
COHORTS3 <- list(
  list(label="A", yr_lo=2008L, yr_hi=2014L, yr_hi_elec=2014L, method_lbl="TWFE (Cohort A, 2008-2014)"),
  list(label="B", yr_lo=2014L, yr_hi=2020L, yr_hi_elec=2020L, method_lbl="TWFE (Cohort B, 2014-2020)"),
  list(label="C", yr_lo=2020L, yr_hi=2025L, yr_hi_elec=2026L, method_lbl="TWFE (Cohort C, 2020-2025)")
)

load_panel <- function() {
  read_csv(file.path(PROJECT, "simple_regression/panel/panel.csv"), col_types = col_spec) %>%
    mutate(dep = clean_dep(dep)) %>% filter(commune_fixe == 1)
}

load_turnover <- function() {
  read_csv(file.path(PROJECT, "simple_regression/CRcreu11/data/turnover_candidats.csv"), col_types = col_spec) %>%
    select(code_insee, annee, turnover_pp)
}

# Income snapshot closest to a given yr_lo. 2008: pre-FiLoSoFi INSEE
# "Revenus fiscaux localises des menages" (RFLM) series (FiLoSoFi itself
# only starts 2014). 2014: FiLoSoFi 2014. 2020: FiLoSoFi 2017 (closest
# pre-2020 snapshot, same choice the wind pipeline makes for its Cohort C).
load_income <- function(yr_lo) {
  if (yr_lo == 2008L) {
    read_excel(
      file.path(PROJECT, "election_data/data_quentin/2026/insee_raw/filosofi_series/filo2008/RFDU2008COM.xls"),
      sheet = "D_UC", skip = 6, col_types = "text") %>%
      rename(code_insee = COM, rev_med = RFUCQ208) %>%
      mutate(code_insee = pad5(code_insee), rev_med = suppressWarnings(as.numeric(rev_med))) %>%
      select(code_insee, rev_med)
  } else if (yr_lo == 2014L) {
    read_excel(
      file.path(PROJECT, "election_data/data_quentin/2026/insee_raw/filosofi_series/filo2014/indic-struct-distrib-revenu-2014-COMMUNES/FILO_DISP_COM.xls"),
      sheet = "ENSEMBLE", skip = 5, col_types = "text") %>%
      rename(code_insee = CODGEO, rev_med = Q214) %>%
      mutate(code_insee = pad5(code_insee), rev_med = suppressWarnings(as.numeric(rev_med))) %>%
      select(code_insee, rev_med)
  } else {
    read_delim(
      file.path(PROJECT, "election_data/data_quentin/2026/insee_raw/filosofi_series/filo2017/cc_filosofi_2017_COM.CSV"),
      delim = ";", col_types = cols(CODGEO = col_character(), .default = col_guess())) %>%
      rename(code_insee = CODGEO, rev_med = MED17) %>%
      mutate(code_insee = pad5(code_insee), rev_med = suppressWarnings(as.numeric(rev_med))) %>%
      select(code_insee, rev_med)
  }
}

# BPE facility-code identity by year -- the nomenclature drifts across
# vintages (138 types in 2007 -> 229 by 2024+) and codes get silently
# renamed or split without warning. Checked against each vintage's own
# varmod/metadata, never assumed -- this is exactly the class of bug that
# undercounted pharmacies for 2020 (D301 silently renamed to D307 that
# year; the desert basket used D301 unconditionally until caught). One
# lookup here instead of every script re-solving it its own way.
#   d705           CADA, unchanged 2008-2025
#   d107           Maternite, unchanged
#   c_maternelle   Ecole maternelle: C101 (2008-2020) -> C107 (2025)
#   c_elementaire  Ecole elementaire: C104 (2008-2020) -> C108+C109 (2025 --
#                  the 2019+ maternelle/elementaire merger reform split it
#                  into "ecole primaire" C108 + standalone C109; C109 alone
#                  would misread every relabeled commune as a closure, so
#                  both codes count as "elementary-level schooling present")
#   c201           College, unchanged
#   d101/d102/d103 Hopital court/moyen/long sejour, unchanged
#   d106           Urgences, unchanged
#   d201           Medecin: D201 (2008-2020) -> D265 "medecin generaliste" (2025)
#   d301           Pharmacie: D301 (2008-2014) -> D307 (2020-2025)
#   a101           Police: A101 (2008-2020) -> A140 (2025)
#   a104           Gendarmerie, unchanged
#   a102           Tresorerie: discontinued nationwide by 2014 (consolidated
#                  into DDFIP/DRFIP) -- genuinely no successor, not a rename.
bpe_codes_for_year <- function(concept, yr) {
  switch(concept,
    d705          = "D705",
    d107          = "D107",
    c_maternelle  = if (yr >= 2025) "C107" else "C101",
    c_elementaire = if (yr >= 2025) c("C108","C109") else "C104",
    c201          = "C201",
    d101          = "D101",
    d102          = "D102",
    d103          = "D103",
    d106          = "D106",
    d201          = if (yr >= 2025) "D265" else "D201",
    d301          = if (yr >= 2020) "D307" else "D301",
    a101          = if (yr >= 2025) "A140" else "A101",
    a104          = "A104",
    a102          = "A102",
    stop("unknown BPE concept: ", concept)
  )
}

keep_both <- function(df, yrs) df %>%
  group_by(code_insee) %>% filter(n_distinct(annee[annee %in% yrs]) == length(yrs)) %>% ungroup()

# Election-outcome derived columns shared by every pipeline.
add_election_outcomes <- function(df, turnover) df %>%
  mutate(reconduit_pp = reconduit*100, recandidature_pp = recandidature*100) %>%
  left_join(turnover, by = c("code_insee","annee"))

# Facility-presence transitions, shared by every closure design (D107,
# C104, basket, per-code): a commune is only "at risk" of losing something
# it had, so the control pool is survivors, not never-had communes (see
# any build_*_control.R header for the full rationale).
closure_split <- function(has_lo, has_hi) list(
  at_risk  = has_lo,
  closed   = setdiff(has_lo, has_hi),
  survived = intersect(has_lo, has_hi)
)

# Opening-design counterpart (D705): 0 in yr_lo, present by yr_hi, among
# communes that actually appear in panel_raw (commune_fixe==1) at yr_lo or
# yr_hi -- restricts to valid, non-fused commune boundaries, same as every
# other case here. Without this restriction a handful of fused/invalid
# commune codes present in the raw BPE facility file but absent from the
# panel leak into the treated set (caught by rerunning and diffing: it
# silently inflated D705 Cohort A from 25 to 30 treated communes).
# Also rural-only (categorie_dens at yr_lo in DENS_OK) -- matches the wind
# TWFE pipeline, which restricts its treated cohort to rural density 5-7
# from the start (cohort_codes() in build_robustness_combined.R), not just
# the control pool.
opening_codes <- function(panel_raw, yr_lo, yr_hi, has_lo, has_hi) {
  universe <- panel_raw %>% filter(annee %in% c(yr_lo, yr_hi)) %>% distinct(code_insee) %>% pull(code_insee)
  intersect(setdiff(has_hi, has_lo), universe) %>% intersect(rural_codes(panel_raw, yr_lo))
}

# Generalized closure/decline split for a per-commune COUNT (facility n, or
# a whole basket's total n): "at risk" = count>0 in yr_lo, "declined" =
# count_hi < count_lo, "survived" = count_hi >= count_lo. A single facility
# (n in {0,1,2,...}) is just the n=1 special case of this -- closure_split()
# above is kept as a thin binary-code convenience wrapper, this is what it
# and the basket case both reduce to.
decline_split <- function(counts_lo, counts_hi) {
  at_risk <- names(counts_lo)[counts_lo > 0]
  n_lo <- counts_lo[at_risk]
  n_hi <- counts_hi[at_risk]; n_hi[is.na(n_hi)] <- 0L
  list(at_risk = at_risk, declined = at_risk[n_hi < n_lo], survived = at_risk[n_hi >= n_lo])
}

# code_insee -> count named vector for one year, from a long (code_insee,
# annee, n) frame (facility count or basket total).
counts_at <- function(raw, yr) {
  d <- raw %>% filter(annee == yr) %>% group_by(code_insee) %>% summarise(n = sum(n), .groups = "drop")
  setNames(d$n, d$code_insee)
}

# The 4 closure/decline-design cases share a shape, but NOT the same split
# semantics: hospital/school are "binary" -- a commune with 2 maternites in
# yr_lo and 1 in yr_hi still HAS one, so it's a survivor, not a closure
# (the research question is "did this commune lose its LAST one"). desert
# is "count" -- ANY net decrease across the basket counts as declined
# (losing the gendarmerie while keeping the school still counts, by design
# -- see build header). Conflating these split semantics during
# consolidation was a real bug caught by rerunning and diffing: it
# silently changed school's closure count from 604 to 1090 (multi-school
# communes whose count merely dropped, not zeroed, got miscounted as
# closures).
#
# Basket is 12 codes, not 13: A102 (tresorerie) is EXCLUDED from the
# basket data itself (see data/BPE_adisp/derived/
# public_service_basket_by_commune_year.csv, rebuilt without it) after
# checking impact -- A102 was discontinued NATIONWIDE by 2014
# (consolidated into DDFIP/DRFIP), so every commune that had one in 2008
# mechanically "loses" it by Cohort A's yr_hi regardless of any local
# desertification story. 16% of Cohort A's declined communes were declined
# ONLY because of this uniform national shock (verified by recomputing the
# split with A102 removed) -- a nationwide administrative reform isn't a
# locally-variable "desertification" signal, so it doesn't belong in the
# basket at all, not just in the per-code decomposition (which already
# excluded it for the same reason).
#
# (D705's opening design stays a separate small block in each driver --
# genuinely a different mechanism: gaining rather than losing, pool =
# never-ever-treated rather than survivors.)
CLOSURE_CASES <- list(
  hospital = list(id="hospital", label="D107 Maternite", treat_var="closed", at_risk_label="D107", mode="binary",
    data_path="data/BPE_adisp/derived/D107_maternite_by_commune_year.csv", count_col="n_equip",
    title="Maternity ward closures (D107) and mayoral elections",
    treatment_desc=function(lo,hi) sprintf("D107 (maternite) present %d, closed by %d", lo, hi),
    control_note="Survivor-matched: at-risk universe = had D107 in yr_lo; control = kept it through yr_hi; probit(closed ~ density + log(pop) + log(income) + dept FE), P10 threshold"),
  school = list(id="school", label="C104 Ecole elementaire", treat_var="closed", at_risk_label="C104", mode="binary",
    data_path="data/BPE_adisp/derived/C104_ecole_elementaire_by_commune_year.csv", count_col="n_equip",
    title="Elementary school closures (C104) and mayoral elections",
    treatment_desc=function(lo,hi) sprintf("C104 (ecole elementaire) present %d, closed by %d", lo, hi),
    control_note="Survivor-matched: at-risk universe = had C104 in yr_lo; control = kept it through yr_hi; probit(closed ~ density + log(pop) + log(income) + dept FE), P10 threshold"),
  desert = list(id="desert", label="Public-service basket (12 codes)", treat_var="declined", at_risk_label="basket>0", mode="count",
    data_path="data/BPE_adisp/derived/public_service_basket_by_commune_year.csv", count_col="n_basket",
    title="Do communes that lose public services vote differently?",
    subtitle="Effect of losing >=1 of 12 local services vs matched communes that kept theirs",
    treatment_desc=function(lo,hi) sprintf("Public-service basket (12 codes) net decline, %d->%d", lo, hi),
    control_note="Survivor-matched: at-risk universe = basket>0 in yr_lo; control = basket stable-or-grew through yr_hi; probit(declined ~ density + log(pop) + log(income) + dept FE), P10 threshold")
)

load_case_raw <- function(case) {
  read_csv(file.path(PROJECT, case$data_path),
           col_types = cols(code_insee = col_character(), annee = col_integer(), .default = col_integer())) %>%
    mutate(code_insee = pad5(code_insee)) %>% rename(n = !!case$count_col)
}

# Split for one CLOSURE_CASES entry, respecting its mode (see comment
# above CLOSURE_CASES for why binary != count). Always returns
# list(at_risk, declined, survived) regardless of mode -- closure_split()'s
# "closed" is renamed to "declined" here so callers don't need to branch.
# Rural-only (categorie_dens at yr_lo in DENS_OK), same parity rationale as
# opening_codes() above -- the wind TWFE cohort is rural-restricted from
# the start, not just its control pool.
case_split <- function(case, raw, yr_lo, yr_hi, panel_raw) {
  counts_lo <- counts_at(raw, yr_lo); counts_hi <- counts_at(raw, yr_hi)
  s <- if (case$mode == "count") {
    decline_split(counts_lo, counts_hi)
  } else {
    has_lo <- names(counts_lo)[counts_lo > 0]; has_hi <- names(counts_hi)[counts_hi > 0]
    cs <- closure_split(has_lo, has_hi)
    list(at_risk = cs$at_risk, declined = cs$closed, survived = cs$survived)
  }
  rural <- rural_codes(panel_raw, yr_lo)
  list(at_risk = intersect(s$at_risk, rural), declined = intersect(s$declined, rural),
       survived = intersect(s$survived, rural))
}

# case_split() run independently per cohort lets the SAME commune be
# "declined" in every cohort it appears in (checked empirically: 1,553
# communes decline in all 3 desert-basket cohorts; 40% of Cohort A's
# treated communes reappear as Cohort B's "matched control", i.e. a
# commune with its own decline history gets used as a clean comparison
# unit a few years later). Fixed here the same way Callaway & Sant'Anna's
# "not-yet-treated" comparison group works (already used elsewhere in this
# repo for wind): run the cohorts IN ORDER, and once a commune is
# "declined" in one cohort it is permanently removed from both later
# treated pools (first-decline-only) and later control pools (a
# once-treated commune is never a clean control again). Returns a named
# list keyed by cohort label, each element list(at_risk, declined,
# survived) like case_split(), already filtered.
sequential_case_splits <- function(case, raw, cohorts, panel_raw) {
  already_treated <- character(0)
  out <- list()
  for (co in cohorts) {
    s <- case_split(case, raw, co$yr_lo, co$yr_hi, panel_raw)
    declined <- setdiff(s$declined, already_treated)
    survived <- setdiff(s$survived, already_treated)
    out[[co$label]] <- list(at_risk = s$at_risk, declined = declined, survived = survived)
    already_treated <- union(already_treated, declined)
  }
  out
}

# Probit-matched control group: treated vs a candidate pool (never-treated
# for an opening design, survivors for a closure design -- this function
# doesn't care which, it just needs the two code vectors), matched on
# log(pop) + log(income) + log(investment) + department FE, P10 threshold
# of treated propensities. Same formula as robsocioeco/build_control_new.R
# (wind), minus its wind_speed_100m term (no equivalent siting-exposure
# variable exists for a BPE facility). Density is NOT a covariate here --
# callers already hard-restrict treated_codes/pool_codes to rural (DENS_OK)
# before calling this, same as the wind pipeline restricts its cohort to
# rural from the start rather than matching on density as a covariate.
match_control <- function(panel_raw, yr_ref, treated_codes, pool_codes, income_src, verbose = TRUE) {
  ref <- panel_raw %>% filter(annee == yr_ref) %>% distinct(code_insee, .keep_all = TRUE) %>%
    mutate(log_inscrits = log(as.numeric(inscrits)))
  if (verbose) cat(sprintf("  Control candidate pool: %d communes\n", length(pool_codes)))

  cross <- ref %>% filter(code_insee %in% c(treated_codes, pool_codes)) %>%
    mutate(treated = as.integer(code_insee %in% treated_codes)) %>%
    left_join(income_src, by = "code_insee") %>%
    left_join(INVEST_2013, by = "code_insee") %>%
    mutate(log_rev = log1p(rev_med), invest_pc = invest_2013 / pmax(as.numeric(inscrits), 1),
           log_invest = log1p(invest_pc)) %>%
    filter(!is.na(dep), !is.na(log_inscrits), !is.na(log_rev), !is.na(log_invest))
  if (verbose) cat(sprintf("  Matching sample (treated + pool, complete cases): %d\n", nrow(cross)))

  s <- glm(treated ~ log_inscrits + log_rev + log_invest + factor(dep),
           data = cross, family = binomial("probit"))
  p_hat <- predict(s, type = "response")
  thresh <- quantile(p_hat[cross$treated == 1], 0.10)
  matched <- cross$code_insee[cross$treated == 0 & p_hat >= thresh]
  if (verbose) cat(sprintf("  P10 threshold = %.4f | matched control: %d / %d candidates\n",
                           thresh, length(matched), sum(cross$treated == 0)))
  matched
}

# NOTE on wind's "dept > 3 treated" pool filter (build_control_new.R step 2,
# "no wind deserts"): deliberately NOT ported here. Checked empirically --
# D705's best department has only 3 ever-treated communes nationwide (rural,
# across all 3 cohorts combined), so a literal >3 threshold clears zero
# departments and empties the control pool entirely. The filter's rationale
# (exclude departments where the treatment essentially never occurs, so
# never-treated communes there aren't structurally comparable) doesn't
# transfer to events this rare -- any nonzero threshold either excludes
# nothing or breaks matching. Department-level confounding is still
# addressed via `factor(dep)` in the probit itself.

# Density/size balance (treated vs matched control), used by every
# _control.R script's descriptive table + printed diagnostic.
compute_balance <- function(panel_raw, yr_ref, treated_codes, matched_codes) {
  ref <- panel_raw %>% filter(annee == yr_ref) %>% distinct(code_insee, .keep_all = TRUE)
  dens_treated <- ref %>% filter(code_insee %in% treated_codes) %>% count(categorie_dens) %>% mutate(pct = round(100*n/sum(n),1))
  dens_control <- ref %>% filter(code_insee %in% matched_codes) %>% count(categorie_dens) %>% mutate(pct = round(100*n/sum(n),1))
  list(
    dens_treated = dens_treated, dens_control = dens_control,
    median_inscrits_treated = ref %>% filter(code_insee %in% treated_codes) %>% pull(inscrits) %>% as.numeric() %>% median(na.rm=TRUE),
    median_inscrits_control = ref %>% filter(code_insee %in% matched_codes) %>% pull(inscrits) %>% as.numeric() %>% median(na.rm=TRUE),
    dominant_density_treated = dens_treated$categorie_dens[which.max(dens_treated$n)],
    dominant_density_control = dens_control$categorie_dens[which.max(dens_control$n)]
  )
}

# One TWFE cohort: build the treated+control 2-period panel (yr_lo,
# yr_hi_elec), regress `outcome ~ [treat_var] + log_pop:post | commune +
# year FE`, commune-clustered SE. Returns one row per outcome in `outcomes`
# (pass a single-element list, e.g. list(OUTCOMES[[4]]), for one outcome).
run_twfe_cohort <- function(panel_raw, turnover, cohort, treat_var, treated_codes, control_codes, outcomes = OUTCOMES) {
  yr_lo <- cohort$yr_lo; yr_hi_elec <- cohort$yr_hi_elec
  pop_base <- panel_raw %>% filter(annee == yr_lo) %>% distinct(code_insee, .keep_all = TRUE) %>%
    transmute(code_insee, log_pop = log1p(as.numeric(inscrits)))
  build_side <- function(codes, is_treated) {
    panel_raw %>% filter(code_insee %in% codes, annee %in% c(yr_lo, yr_hi_elec)) %>%
      distinct(code_insee, annee, .keep_all = TRUE) %>%
      mutate(!!treat_var := if (is_treated) as.integer(annee == yr_hi_elec) else 0L,
             post = as.integer(annee == yr_hi_elec)) %>%
      add_election_outcomes(turnover) %>%
      left_join(pop_base, by = "code_insee") %>% keep_both(c(yr_lo, yr_hi_elec))
  }
  dat <- bind_rows(build_side(treated_codes, TRUE), build_side(control_codes, FALSE))
  cat(sprintf("Cohort %s (%d-%d): %d treated | %d matched control\n", cohort$label, yr_lo, cohort$yr_hi,
              n_distinct(dat$code_insee[dat[[treat_var]]==1]), n_distinct(dat$code_insee[dat[[treat_var]]==0])))

  coh <- cohort  # local copy: tibble() below creates a "cohort" column that
  # would mask the `cohort` argument if referenced again by that name mid-call.
  bind_rows(lapply(outcomes, function(o) {
    d <- dat %>% filter(!is.na(.data[[o$var]]), !is.na(log_pop))
    tryCatch({
      fml <- as.formula(sprintf("%s ~ %s + log_pop:post | code_insee + annee", o$var, treat_var))
      mod <- feols(fml, data = d, cluster = ~code_insee)
      ct <- coeftable(mod)
      if (!treat_var %in% rownames(ct)) return(NULL)
      tibble(cohort = coh$label, method = coh$method_lbl, outcome = o$label,
             n_trt = n_distinct(d$code_insee[d[[treat_var]]==1]),
             estimate = ct[treat_var,"Estimate"], se = ct[treat_var,"Std. Error"], p = ct[treat_var,"Pr(>|t|)"])
    }, error = function(e) NULL)
  }))
}

# Continuous-dose counterpart to run_twfe_cohort(): the binary "declined"
# dummy treats losing 1-of-2 facilities the same as losing 1-of-20 -- a
# much bigger relative shock in an already-sparsely-equipped commune.
# `severity` is a named numeric vector (code_insee -> dose, 0 for the
# untreated/control group, e.g. (n_lo-n_hi)/n_lo = fraction of baseline
# lost for treated communes) applied only in the post period, same FE/
# clustering as the binary version. `sample_codes` = every code that
# should enter the regression (treated ∪ control).
#
# `fe_extra` (optional string, e.g. "baseline_bucket^annee" in fixest's
# interacted-FE syntax) adds a fixed effect on top of the default
# code_insee + annee -- e.g. a baseline-severity-tercile x year FE, so
# communes that started sparsely-equipped are allowed their own secular
# trend instead of being forced to share one with well-equipped communes.
# Note this is NOT the same thing as commune FE controlling for baseline
# LEVEL (code_insee already does that, for free, in every spec here) --
# `fe_extra` controls for baseline-dependent DIFFERENTIAL TRENDS, which
# plain commune FE cannot. If used, `extra_data` must supply that column
# (a tibble with code_insee + whatever fe_extra references), left-joined
# in before the regression.
run_twfe_cohort_dose <- function(panel_raw, turnover, cohort, treat_var, severity, sample_codes, outcomes = OUTCOMES,
                                  fe_extra = NULL, extra_data = NULL) {
  yr_lo <- cohort$yr_lo; yr_hi_elec <- cohort$yr_hi_elec
  pop_base <- panel_raw %>% filter(annee == yr_lo) %>% distinct(code_insee, .keep_all = TRUE) %>%
    transmute(code_insee, log_pop = log1p(as.numeric(inscrits)))
  dat <- panel_raw %>% filter(code_insee %in% sample_codes, annee %in% c(yr_lo, yr_hi_elec)) %>%
    distinct(code_insee, annee, .keep_all = TRUE) %>%
    mutate(post = as.integer(annee == yr_hi_elec),
           !!treat_var := unname(severity[code_insee]) * post) %>%
    add_election_outcomes(turnover) %>%
    left_join(pop_base, by = "code_insee") %>% keep_both(c(yr_lo, yr_hi_elec))
  if (!is.null(extra_data)) dat <- dat %>% left_join(extra_data, by = "code_insee")
  cat(sprintf("Cohort %s (%d-%d): %d communes, mean dose (treated only) = %.3f\n", cohort$label, yr_lo, cohort$yr_hi,
              n_distinct(dat$code_insee), mean(severity[severity > 0])))

  fe_part <- if (is.null(fe_extra)) "code_insee + annee" else paste("code_insee + annee +", fe_extra)
  coh <- cohort
  bind_rows(lapply(outcomes, function(o) {
    d <- dat %>% filter(!is.na(.data[[o$var]]), !is.na(log_pop))
    tryCatch({
      fml <- as.formula(sprintf("%s ~ %s + log_pop:post | %s", o$var, treat_var, fe_part))
      mod <- feols(fml, data = d, cluster = ~code_insee)
      ct <- coeftable(mod)
      if (!treat_var %in% rownames(ct)) return(NULL)
      tibble(cohort = coh$label, method = coh$method_lbl, outcome = o$label,
             n_trt = sum(severity[unique(d$code_insee)] > 0, na.rm=TRUE),
             estimate = ct[treat_var,"Estimate"], se = ct[treat_var,"Std. Error"], p = ct[treat_var,"Pr(>|t|)"])
    }, error = function(e) NULL)
  }))
}

COHORT_COLORS <- c("TWFE (Cohort A, 2008-2014)"="#eda100", "TWFE (Cohort B, 2014-2020)"="#2a78d6",
                    "TWFE (Cohort C, 2020-2025)"="#1baf7a")

# Shared slide-figure template: dot + 95% CI per outcome, one color per
# cohort, faceted by outcome. Used by every _twfe.R main-result figure.
make_slide_figure <- function(results, title, subtitle, out_path, width=15, height=10.5, ncol=3) {
  title_wrap <- round(width * 3.6)     # bold 22pt is wider per char than subtitle's 15pt
  subtitle_wrap <- round(width * 5.8)
  p <- ggplot(results, aes(x=estimate, y=method, color=method)) +
    geom_vline(xintercept=0, linetype="dashed", color="grey55", linewidth=0.7) +
    geom_pointrange(aes(xmin=ci_low, xmax=ci_high), linewidth=1.3, size=1.3) +
    facet_wrap(~outcome, scales="free_x", ncol=ncol) +
    scale_color_manual(values=COHORT_COLORS, guide="none") +
    labs(title=str_wrap(title, title_wrap), subtitle=str_wrap(subtitle, subtitle_wrap), x="Estimated effect (pp / %)", y=NULL) +
    theme_minimal(base_size=20) +
    theme(
      strip.text=element_text(face="bold", size=15),
      axis.text.y=element_text(size=14, face="bold"),
      axis.text.x=element_text(size=11),
      axis.title.x=element_text(size=14),
      plot.title=element_text(face="bold", size=22),
      plot.subtitle=element_text(size=15, color="grey35"),
      panel.grid.minor=element_blank(),
      panel.spacing=unit(1.3, "lines"),
      plot.margin=margin(15,20,15,15)
    )
  ggsave(out_path, p, width=width, height=height, dpi=200)
  cat(sprintf("Saved -> %s\n", out_path))
}
