# Combined robustness -- ALL TWFE specifications (milestones, regions,
# electoral system, mayor stability, size, cohorts, installation power,
# competitiveness, income) in ONE file, faceted by outcome (6 columns),
# every specification stacked on a single Y axis (one shared reference per
# cohort, every other specification listed once with a category prefix).
#
# Runs for all 3 cohorts (A: 2008-2014, B: 2014-2020, C: 2020-2026) x both
# control pools = 6 full result sets. Cohort B is the paper's MAIN result
# (unchanged filenames/figure, exactly as before this cohort-generalization
# pass -- nothing downstream that reads data_results_all_specs*.csv or
# rob_all_combined.png changes). Cohorts A and C are new -- appendix
# material, same 23-spec grid, own output files:
#   data_results_all_specs.csv / _baseline.csv           -- Cohort B (main)
#   data_results_all_specs_cohortA.csv / _cohortA_baseline.csv
#   data_results_all_specs_cohortC.csv / _cohortC_baseline.csv
#   figures/rob_all_combined.png                          -- Cohort B (main)
#   figures/rob_all_combined_cohortA.png
#   figures/rob_all_combined_cohortC.png
#
# Reuses as-is the constructions from:
#   robsocioeco/build_robustness_newctrl.R (milestones/regions/electoral
#     system/stability/size/cohorts/power)
#   robsocioeco/build_robustness_competitivite_newctrl.R (competitiveness)
#   robsocioeco/build_robustness_socioeco.R (income)

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(fixest); library(ggplot2)
  library(tidyr); library(stringr); library(readxl)
})

PROJECT  <- Sys.getenv("POLITICALRE_ROOT", unset = "/home/loiclebrec/ENRpolitical/Python/PoliticalRE")
DATA     <- file.path(PROJECT, "simple_regression/CRcreu11/data")
MORVAN   <- file.path(PROJECT, "simple_regression/morvan")
FIG      <- file.path(PROJECT, "simple_regression/publication/twfe/figures")
PANEL    <- file.path(PROJECT, "simple_regression/panel/panel.csv")
PARC     <- file.path(PROJECT, "data/parceolien/Parc.csv")
col_spec <- cols(code_insee=col_character(), dep=col_character(), .default=col_guess())
pad5     <- function(x) str_pad(str_extract(as.character(x), "[0-9A-Za-z]+"), 5, "left", "0")
dir.create(FIG, showWarnings=FALSE, recursive=TRUE)

DENS_OK <- c("5","6","7")
OUTCOMES <- list(
  list(var="recandidature_pp",          label="Candidacy\n(pp)"),
  list(var="reconduit_pp",              label="Reelection\n(pp)"),
  list(var="pct_voix_gagnant_exprimes", label="Winner vote share\n(% valid votes)"),
  list(var="pct_abstention",            label="Abstention\n(% registered)"),
  list(var="turnover_pp",               label="Candidate turnover\n(%)"),
  list(var="pct_voix_sortant_exprimes", label="Incumbent vote share\n(% valid votes)")
)

panel_raw_full <- read_csv(PANEL, col_types=col_spec)
n_before_fusion <- n_distinct(panel_raw_full$code_insee)
# Exclude communes that merged (absorbed another commune OR were absorbed) --
# commune_fixe==1 means untouched by any fusion (COG mvt MOD=32) over the
# panel period. Absorbed communes break code_insee continuity across years;
# absorbing communes have a population/seat discontinuity that isn't organic
# growth. Filtered globally so every downstream cohort/control construction
# inherits it automatically.
panel_raw <- panel_raw_full %>% filter(commune_fixe == 1)
cat(sprintf("Communes fusionnees exclues : %d -> %d (commune_fixe==1)\n",
            n_before_fusion, n_distinct(panel_raw$code_insee)))

ctrl_codes_matched <- read_csv(file.path(PROJECT, "simple_regression/robsocioeco/data/control_group_new.csv"),
                       col_types=col_spec) %>% pull(code_insee) %>% unique()
ctrl_codes_baseline <- read_csv(file.path(DATA, "control_group.csv"), col_types=col_spec) %>%
  pull(code_insee) %>% unique()
turnover  <- read_csv(file.path(DATA,"turnover_candidats.csv"), col_types=col_spec) %>%
  select(code_insee, annee, turnover_pp)
closeness <- read_csv(file.path(MORVAN, "data/closeness.csv"),
                      col_types=cols(code_insee=col_character(), .default=col_guess()))
parc_raw <- read_csv(PARC, col_types=cols(
  id_parc=col_character(), code_insee=col_character(),
  date_depot_demande_autorisation=col_character(),
  date_delivrance_autorisation=col_character(),
  date_debut_construction=col_character(),
  date_mise_en_service=col_character(), .default=col_skip())) %>%
  mutate(code_insee=pad5(code_insee))

# ── Income data, ONE per cohort's yr_lo (never yr_hi -- a post-treatment
# income snapshot is a bad control, Angrist & Pischke, same logic as
# log_pop being baseline-only). No INSEE FiLoSoFi income snapshot exists
# before 2014, so Cohort A (yr_lo=2008) has NO income split available --
# skipped for A only, not patched with a mismatched-year proxy.
filo14 <- read_excel(
  file.path(PROJECT, "election_data/data_quentin/2026/insee_raw/filosofi_series/filo2014/indic-struct-distrib-revenu-2014-COMMUNES/FILO_DISP_COM.xls"),
  sheet="ENSEMBLE", skip=5, col_types="text") %>%
  rename(code_insee=CODGEO, rev_med=Q214) %>%
  mutate(code_insee=pad5(code_insee), rev_med=suppressWarnings(as.numeric(rev_med))) %>%
  select(code_insee, rev_med)
filo17 <- read_delim(
  file.path(PROJECT, "election_data/data_quentin/2026/insee_raw/filosofi_series/filo2017/cc_filosofi_2017_COM.CSV"),
  delim=";", col_types=cols(CODGEO=col_character(), .default=col_guess())) %>%
  rename(code_insee=CODGEO, rev_med=MED17) %>%
  mutate(code_insee=pad5(code_insee), rev_med=suppressWarnings(as.numeric(rev_med))) %>%
  select(code_insee, rev_med)
INCOME_BY_YRLO <- list(`2014`=filo14, `2020`=filo17)  # 2020 uses 2017 (closest pre-yr_lo snapshot)

inscrits_at <- function(yr) panel_raw %>% filter(annee==yr) %>% distinct(code_insee, .keep_all=TRUE) %>%
  transmute(code_insee, inscrits_ref=as.numeric(inscrits))

# log_pop : wind farm siting isn't random w.r.t. commune size, and size
# plausibly affects the outcomes directly too. Commune FE absorbs the
# average level but not within-commune growth over the panel -- added as a
# covariate for precision (same rationale as morvan's simple Heckman).
# BASELINE population only (annee==yr_lo, joined in make_panel below), not
# contemporaneous inscrits -- population can itself respond to the wind
# farm (jobs in / nuisance out), so a post-treatment value is a bad control
# (Angrist & Pischke) that could absorb part of the true treatment effect.
add_outcomes <- function(df) df %>%
  mutate(reconduit_pp=reconduit*100, recandidature_pp=recandidature*100) %>%
  left_join(turnover, by=c("code_insee","annee"))

keep_both <- function(df, yrs) df %>%
  group_by(code_insee) %>% filter(n_distinct(annee[annee %in% yrs]) == length(yrs)) %>% ungroup()

run_twfe <- function(dat, spec_lbl, is_ref=FALSE) {
  bind_rows(lapply(OUTCOMES, function(o) {
    d <- dat %>% filter(!is.na(.data[[o$var]]), !is.na(log_pop))
    if (n_distinct(d$code_insee[d$eolien_treated==1]) < 5) return(NULL)
    tryCatch({
      # log_pop is now BASELINE-only (see make_panel) -> constant within
      # commune across the 2 panel years, so it's collinear with the
      # commune FE as a main effect (feols would just drop it). Interacted
      # with `post` instead: lets control/treated units follow a different
      # OUTCOME TREND depending on their baseline size, without using a
      # post-treatment population value anywhere.
      mod <- feols(as.formula(sprintf("%s ~ eolien_treated + log_pop:post | code_insee + annee", o$var)),
                   data=d, cluster=~code_insee)
      ct <- coeftable(mod)
      tibble(spec=spec_lbl, is_ref=is_ref, outcome=o$label,
             n_trt=n_distinct(d$code_insee[d$eolien_treated==1]),
             estimate=ct["eolien_treated","Estimate"], se=ct["eolien_treated","Std. Error"],
             ci_low=ct["eolien_treated","Estimate"]-1.96*ct["eolien_treated","Std. Error"],
             ci_high=ct["eolien_treated","Estimate"]+1.96*ct["eolien_treated","Std. Error"],
             p=ct["eolien_treated","Pr(>|t|)"])
    }, error=function(e) NULL)
  }))
}

# ── Cohort membership: 0 parks at yr_lo, >=1 at yr_hi, rural throughout ────
cohort_codes <- function(yr_lo, yr_hi) {
  panel_raw %>% filter(annee %in% c(yr_lo, yr_hi)) %>%
    distinct(code_insee, annee, .keep_all=TRUE) %>%
    select(code_insee, annee, n_parcs_cumul, categorie_dens) %>%
    pivot_wider(names_from=annee, values_from=n_parcs_cumul, names_prefix="np_") %>%
    filter(categorie_dens %in% DENS_OK, !is.na(.data[[paste0("np_",yr_lo)]]), !is.na(.data[[paste0("np_",yr_hi)]]),
           as.numeric(.data[[paste0("np_",yr_lo)]])==0, as.numeric(.data[[paste0("np_",yr_hi)]])>0) %>%
    pull(code_insee)
}

COHORTS <- list(
  list(label="A", yr_lo=2008L, yr_hi=2014L, ref_lbl="Reference\n(Full Cohort A)"),
  list(label="B", yr_lo=2014L, yr_hi=2020L, ref_lbl="Reference\n(Full Cohort B)"),
  list(label="C", yr_lo=2020L, yr_hi=2026L, ref_lbl="Reference\n(Full Cohort C)")
)
COH_CODES <- setNames(lapply(COHORTS, function(co) cohort_codes(co$yr_lo, co$yr_hi)), sapply(COHORTS, `[[`, "label"))

# ── Full 9-category pipeline, parameterized by control group AND cohort ───
run_pipeline <- function(ctrl_codes, ctrl_label, cohort) {
  yr_lo <- cohort$yr_lo; yr_hi <- cohort$yr_hi; coh_lbl <- cohort$label
  coh_codes <- COH_CODES[[coh_lbl]]
  cat(sprintf("\n========== Control group: %s | Cohort %s (%d-%d) ==========\n",
              ctrl_label, coh_lbl, yr_lo, yr_hi))

  make_panel <- function(trt_codes_vec, yr_lo, yr_hi) {
    pop_base <- panel_raw %>% filter(annee==yr_lo) %>% distinct(code_insee, .keep_all=TRUE) %>%
      transmute(code_insee, log_pop=log1p(as.numeric(inscrits)))
    trt <- panel_raw %>% filter(code_insee %in% trt_codes_vec, annee %in% c(yr_lo, yr_hi)) %>%
      distinct(code_insee, annee, .keep_all=TRUE) %>%
      mutate(eolien_treated=as.integer(annee==yr_hi), post=as.integer(annee==yr_hi)) %>% add_outcomes() %>%
      left_join(pop_base, by="code_insee") %>% keep_both(c(yr_lo, yr_hi))
    ctrl <- panel_raw %>% filter(code_insee %in% ctrl_codes, annee %in% c(yr_lo, yr_hi)) %>%
      distinct(code_insee, annee, .keep_all=TRUE) %>%
      mutate(eolien_treated=0L, post=as.integer(annee==yr_hi)) %>% add_outcomes() %>%
      left_join(pop_base, by="code_insee") %>% keep_both(c(yr_lo, yr_hi))
    bind_rows(trt, ctrl)
  }

  dat_coh <- make_panel(coh_codes, yr_lo, yr_hi)
  cat(sprintf("Cohort %s [MAIN/shared reference] : %d treated | %d control\n",
              coh_lbl, n_distinct(dat_coh$code_insee[dat_coh$eolien_treated==1]),
              n_distinct(dat_coh$code_insee[dat_coh$eolien_treated==0])))

  res_ref <- run_twfe(dat_coh, cohort$ref_lbl, is_ref=TRUE)
  all_results <- list(res_ref)
  spec_order  <- c(cohort$ref_lbl)
  add_cat <- function(res, lbls) {
    all_results[[length(all_results)+1]] <<- res
    spec_order <<- c(spec_order, lbls)
  }

  # 1. MILESTONES
  cat("── 1. Milestones ──\n")
  MILESTONES <- list(
    list(col="date_depot_demande_autorisation", lbl="[Milestones] Application filed"),
    list(col="date_delivrance_autorisation",    lbl="[Milestones] Authorization granted"),
    list(col="date_mise_en_service",            lbl="[Milestones] Commissioning")
  )
  res_milestones <- bind_rows(lapply(MILESTONES, function(j) {
    p <- parc_raw %>% mutate(yr=suppressWarnings(as.integer(substr(.data[[j$col]],1,4)))) %>% filter(!is.na(yr))
    c_lo <- p %>% filter(yr<=yr_lo) %>% count(code_insee, name="n_lo")
    c_hi <- p %>% filter(yr<=yr_hi) %>% count(code_insee, name="n_hi")
    codes_j <- full_join(c_lo, c_hi, by="code_insee") %>%
      mutate(across(starts_with("n_"), ~coalesce(.,0L))) %>%
      filter(n_lo==0, n_hi>0) %>% pull(code_insee) %>%
      intersect(panel_raw %>% filter(categorie_dens %in% DENS_OK) %>% pull(code_insee))
    dat_j <- make_panel(codes_j, yr_lo, yr_hi)
    n_j <- n_distinct(dat_j$code_insee[dat_j$eolien_treated==1])
    run_twfe(dat_j, sprintf("%s (n=%d)", j$lbl, n_j))
  }))
  add_cat(res_milestones, res_milestones %>% distinct(spec) %>% pull(spec))

  # 2. REGIONS
  cat("── 2. Regions ──\n")
  REG_MAP <- c("32"="Hauts-de-France","44"="Grand Est","53"="Brittany","28"="Normandy")
  dat_coh_r <- dat_coh %>% mutate(reg_str=as.character(as.integer(reg)))
  res_regions <- bind_rows(lapply(c(names(REG_MAP),"other"), function(r) {
    d <- if (r=="other") dat_coh_r %>% filter(!reg_str %in% names(REG_MAP)) else dat_coh_r %>% filter(reg_str==r)
    nm <- if (r=="other") "Other regions" else REG_MAP[r]
    n_t <- n_distinct(d$code_insee[d$eolien_treated==1])
    if (n_t < 5) return(NULL)
    run_twfe(d, sprintf("[Regions] %s (n=%d)", nm, n_t))
  }))
  add_cat(res_regions, res_regions %>% distinct(spec) %>% pull(spec))

  # 3. ELECTORAL SYSTEM
  cat("── 3. Electoral system ──\n")
  sc_lo <- panel_raw %>% filter(annee==yr_lo) %>% distinct(code_insee, .keep_all=TRUE) %>%
    select(code_insee, type_scrutin_lo=type_scrutin)
  dat_coh_sc <- dat_coh %>% left_join(sc_lo, by="code_insee")
  res_scrutin <- bind_rows(
    run_twfe(dat_coh_sc %>% filter(type_scrutin_lo=="individuel"),
             sprintf("[Electoral system] Plurality/individual (n=%d)",
                     n_distinct(dat_coh_sc$code_insee[dat_coh_sc$eolien_treated==1 & dat_coh_sc$type_scrutin_lo=="individuel"]))),
    run_twfe(dat_coh_sc %>% filter(type_scrutin_lo=="liste"),
             sprintf("[Electoral system] List ballot (n=%d)",
                     n_distinct(dat_coh_sc$code_insee[dat_coh_sc$eolien_treated==1 & dat_coh_sc$type_scrutin_lo=="liste"])))
  )
  add_cat(res_scrutin, res_scrutin %>% distinct(spec) %>% pull(spec))

  # 4. MAYOR STABILITY
  cat("── 4. Mayor stability ──\n")
  maire_info <- panel_raw %>% filter(annee %in% c(yr_lo,yr_hi), !is.na(reconduit)) %>%
    distinct(code_insee, annee, reconduit) %>%
    pivot_wider(names_from=annee, values_from=reconduit, names_prefix="rec_")
  rec_lo_col <- paste0("rec_", yr_lo); rec_hi_col <- paste0("rec_", yr_hi)
  stable_full <- maire_info %>% filter(.data[[rec_lo_col]]==1, .data[[rec_hi_col]]==1) %>% pull(code_insee)
  chgt_lo     <- maire_info %>% filter(.data[[rec_lo_col]]==0) %>% pull(code_insee)
  chgt_hi     <- maire_info %>% filter(.data[[rec_lo_col]]==1, .data[[rec_hi_col]]==0) %>% pull(code_insee)
  make_sub <- function(codes) dat_coh %>% filter(code_insee %in% codes)
  specs_stab <- list(
    list(d=make_sub(stable_full), lbl=sprintf("[Stability] Same mayor %d-%d", yr_lo, yr_hi)),
    list(d=make_sub(chgt_lo),     lbl=sprintf("[Stability] Mayor turnover %d", yr_lo)),
    list(d=make_sub(chgt_hi),     lbl=sprintf("[Stability] Mayor turnover %d", yr_hi))
  )
  res_stab <- bind_rows(lapply(specs_stab, function(s) {
    n_t <- n_distinct(s$d$code_insee[s$d$eolien_treated==1])
    run_twfe(s$d, sprintf("%s (n=%d)", s$lbl, n_t))
  }))
  add_cat(res_stab, res_stab %>% distinct(spec) %>% pull(spec))

  # 5. MUNICIPALITY SIZE
  cat("── 5. Municipality size ──\n")
  inscrits_lo <- inscrits_at(yr_lo)
  dat_coh_sz <- dat_coh %>% left_join(inscrits_lo, by="code_insee")
  petit <- dat_coh_sz %>% filter(is.na(inscrits_ref) | inscrits_ref < 1000)
  grand <- dat_coh_sz %>% filter(!is.na(inscrits_ref) & inscrits_ref >= 1000)
  res_taille <- bind_rows(
    run_twfe(petit, sprintf("[Municipality size] < 1,000 registered voters (n=%d)", n_distinct(petit$code_insee[petit$eolien_treated==1]))),
    run_twfe(grand, sprintf("[Municipality size] >= 1,000 registered voters (n=%d)", n_distinct(grand$code_insee[grand$eolien_treated==1])))
  )
  add_cat(res_taille, res_taille %>% distinct(spec) %>% pull(spec))

  # 6. COHORTS -- the OTHER two cohorts' full-window estimate, shown as a
  # heterogeneity split inside this cohort's own grid (comparing across
  # cohorts, same as the original Cohort-B version did with A/C).
  cat("── 6. Cohorts ──\n")
  other_cohorts <- Filter(function(co) co$label != coh_lbl, COHORTS)
  res_coh <- bind_rows(lapply(other_cohorts, function(co) {
    dat_other <- make_panel(COH_CODES[[co$label]], co$yr_lo, co$yr_hi)
    run_twfe(dat_other, sprintf("[Cohorts] %s %d-%d (n=%d)", co$label, co$yr_lo, co$yr_hi,
                                 n_distinct(dat_other$code_insee[dat_other$eolien_treated==1])))
  }))
  add_cat(res_coh, res_coh %>% distinct(spec) %>% pull(spec))

  # 7. INSTALLATION POWER -- measured at yr_hi (post-period, "how big is
  # what was ultimately built" -- same rationale as the original yr_hi=2020
  # reference for Cohort B, generalized).
  cat("── 7. Installation power ──\n")
  mw_ref <- panel_raw %>% filter(annee==yr_hi) %>% distinct(code_insee, .keep_all=TRUE) %>%
    select(code_insee, mw_ref=mw_cumul) %>% mutate(mw_ref=as.numeric(mw_ref))
  med_mw <- mw_ref %>% filter(code_insee %in% coh_codes, mw_ref > 0) %>% pull(mw_ref) %>% median(na.rm=TRUE)
  size_class <- mw_ref %>% filter(code_insee %in% coh_codes) %>% mutate(grande=mw_ref>=med_mw)
  petite_codes <- size_class %>% filter(!grande) %>% pull(code_insee)
  grande_codes <- size_class %>% filter(grande) %>% pull(code_insee)
  petite_inst <- dat_coh %>% filter(eolien_treated==0 | code_insee %in% petite_codes)
  grande_inst <- dat_coh %>% filter(eolien_treated==0 | code_insee %in% grande_codes)
  res_mw <- bind_rows(
    run_twfe(petite_inst, sprintf("[Installation power] Small < %.0f MW (n=%d)", med_mw,
                                  n_distinct(petite_inst$code_insee[petite_inst$eolien_treated==1]))),
    run_twfe(grande_inst, sprintf("[Installation power] Large >= %.0f MW (n=%d)", med_mw,
                                  n_distinct(grande_inst$code_insee[grande_inst$eolien_treated==1])))
  )
  add_cat(res_mw, res_mw %>% distinct(spec) %>% pull(spec))

  # 8. COMPETITIVENESS
  cat("── 8. Competitiveness ──\n")
  cl_lo <- closeness %>% filter(annee==yr_lo) %>% select(code_insee, type_scrutin, mono_liste, closeness)
  med_by_regime <- cl_lo %>% filter(code_insee %in% coh_codes, mono_liste==0, !is.na(closeness)) %>%
    group_by(type_scrutin) %>% summarise(mediane=median(closeness), .groups="drop")
  competitif_df <- cl_lo %>% filter(code_insee %in% unique(dat_coh$code_insee)) %>%
    left_join(med_by_regime, by="type_scrutin") %>%
    mutate(competitif=case_when(mono_liste==1 ~ 0L, is.na(closeness)|is.na(mediane) ~ NA_integer_,
                                TRUE ~ as.integer(closeness<mediane))) %>%
    select(code_insee, competitif)
  dat_coh_comp <- dat_coh %>% left_join(competitif_df, by="code_insee") %>% filter(!is.na(competitif))
  res_comp <- bind_rows(
    run_twfe(dat_coh_comp %>% filter(competitif==1), sprintf("[Competitiveness] Competitive (n=%d)",
             n_distinct(dat_coh_comp$code_insee[dat_coh_comp$eolien_treated==1 & dat_coh_comp$competitif==1]))),
    run_twfe(dat_coh_comp %>% filter(competitif==0), sprintf("[Competitiveness] Non-competitive (n=%d)",
             n_distinct(dat_coh_comp$code_insee[dat_coh_comp$eolien_treated==1 & dat_coh_comp$competitif==0])))
  )
  add_cat(res_comp, res_comp %>% distinct(spec) %>% pull(spec))

  # 9. INCOME -- skipped when no snapshot is available near this cohort's
  # yr_lo (Cohort A, yr_lo=2008: no FiLoSoFi data before 2014).
  income_src <- INCOME_BY_YRLO[[as.character(yr_lo)]]
  if (is.null(income_src)) {
    cat(sprintf("── 9. Income -- SKIPPED (no income snapshot available near %d) ──\n", yr_lo))
  } else {
    cat("── 9. Income ──\n")
    fin <- inscrits_lo %>% left_join(income_src, by="code_insee")
    med_rev <- fin %>% filter(code_insee %in% coh_codes, !is.na(rev_med)) %>% pull(rev_med) %>% median()
    fin_grp <- fin %>% mutate(revenu_faible=as.integer(rev_med<med_rev)) %>% select(code_insee, revenu_faible)
    dat_coh_fin <- dat_coh %>% left_join(fin_grp, by="code_insee")
    res_fin <- bind_rows(
      run_twfe(dat_coh_fin %>% filter(revenu_faible==1), sprintf("[Income] Low (n=%d)",
               n_distinct(dat_coh_fin$code_insee[dat_coh_fin$eolien_treated==1 & dat_coh_fin$revenu_faible==1]))),
      run_twfe(dat_coh_fin %>% filter(revenu_faible==0), sprintf("[Income] High (n=%d)",
               n_distinct(dat_coh_fin$code_insee[dat_coh_fin$eolien_treated==1 & dat_coh_fin$revenu_faible==0])))
    )
    add_cat(res_fin, res_fin %>% distinct(spec) %>% pull(spec))
  }

  results <- bind_rows(all_results) %>%
    filter(!is.na(estimate)) %>%
    mutate(
      spec    = factor(spec, levels=rev(spec_order)),
      outcome = factor(outcome, levels=sapply(OUTCOMES, `[[`, "label")),
      signif  = p < 0.05,
      col     = if_else(is_ref, "Reference", if_else(signif, "p < 0.05", "p >= 0.05"))
    )
  cat(sprintf("Total specifications (excl. reference) : %d\n", length(spec_order)-1))
  results
}

theme_forest <- function() {
  theme_bw(base_size=9) +
  theme(
    panel.grid.major.y=element_line(color="grey92", linewidth=0.3),
    panel.grid.major.x=element_blank(), panel.grid.minor=element_blank(),
    panel.border=element_rect(color="grey70", linewidth=0.4),
    strip.background=element_rect(fill="grey95", color="grey70", linewidth=0.4),
    strip.text=element_text(size=8, face="bold", lineheight=0.9),
    axis.text.y=element_text(size=6.8), axis.text.x=element_text(size=7),
    axis.title.x=element_text(size=8.5), axis.title.y=element_blank(),
    legend.position="bottom", legend.text=element_text(size=8), legend.title=element_blank(),
    plot.title=element_text(size=12, face="bold"), plot.subtitle=element_text(size=8.5, color="grey40"),
    plot.caption=element_text(size=6.8, color="grey45", hjust=0), panel.spacing.x=unit(0.6,"lines")
  )
}

make_figure <- function(results_matched, coh_lbl, yr_lo, yr_hi, out_file) {
  p <- ggplot(results_matched, aes(y=spec, x=estimate, color=col, shape=col)) +
    geom_vline(xintercept=0, linetype="dashed", color="grey40", linewidth=0.6) +
    geom_pointrange(aes(xmin=ci_low, xmax=ci_high), size=0.3, linewidth=0.5) +
    facet_wrap(~outcome, nrow=1, scales="free_x") +
    scale_color_manual(values=c("Reference"="grey50","p < 0.05"="#c0392b","p >= 0.05"="#2980b9"),
                       breaks=c("Reference","p >= 0.05","p < 0.05")) +
    scale_shape_manual(values=c("Reference"=15,"p < 0.05"=18,"p >= 0.05"=16),
                       breaks=c("Reference","p >= 0.05","p < 0.05")) +
    labs(
      title=sprintf("Complete robustness — all TWFE specifications (Cohort %s)", coh_lbl),
      subtitle="Milestones, regions, electoral system, mayor stability, size, cohorts, installation power, competitiveness, income — one shared reference",
      x="Estimated effect + 95% CI",
      caption=paste(
        sprintf("TREATMENT: rural density 5-7, 0 wind farms in %d -> >=1 by %d.", yr_lo, yr_hi),
        "CONTROL (build_control_new.R): rural density 5-7, never treated, department with > 3 treated municipalities, probit-matched (wind + log(pop) + log(income) + log(investment) + department FE, P10 threshold of treated).",
        sprintf("TWFE | municipality + year FE | municipality-clustered SE. Reference = Full Cohort %s, shared across all categories.", coh_lbl),
        sep="\n")
    ) +
    theme_forest() +
    guides(color=guide_legend(override.aes=list(size=0.7), nrow=1), shape=guide_legend(nrow=1))

  h <- 2 + 0.28 * n_distinct(results_matched$spec)
  ggsave(out_file, p, width=15, height=h, dpi=150)
  cat(sprintf("Saved -> %s\n", out_file))
}

# ── Run all 3 cohorts x 2 control pools = 6 result sets ────────────────────
for (cohort in COHORTS) {
  suffix <- if (cohort$label == "B") "" else sprintf("_cohort%s", cohort$label)

  results_matched <- run_pipeline(ctrl_codes_matched, "Socioeconomically matched control", cohort)
  out_matched <- file.path(FIG, sprintf("../data_results_all_specs%s.csv", suffix))
  write_csv(results_matched %>% mutate(spec=as.character(spec), outcome=as.character(outcome)), out_matched)
  cat(sprintf("\nSaved -> %s\n", out_matched))

  results_baseline <- run_pipeline(ctrl_codes_baseline, "Baseline control", cohort)
  out_baseline <- file.path(FIG, sprintf("../data_results_all_specs%s_baseline.csv", suffix))
  write_csv(results_baseline %>% mutate(spec=as.character(spec), outcome=as.character(outcome)), out_baseline)
  cat(sprintf("Saved -> %s\n", out_baseline))

  fig_name <- if (cohort$label == "B") "rob_all_combined.png" else sprintf("rob_all_combined_cohort%s.png", cohort$label)
  make_figure(results_matched, cohort$label, cohort$yr_lo, cohort$yr_hi, file.path(FIG, fig_name))
}
