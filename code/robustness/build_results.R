# TWFE results + slide figures for every publication/robustness/ case
# (D705 opening; D107/C104/basket closures; then a per-BPE-code abstention
# decomposition of the basket result). One script for all of it -- see
# robustness_common.R for the shared regression/figure machinery and
# CLOSURE_CASES registry. Requires build_control_groups.R to have run
# first (reads its control_group_*.csv output).
#
# Output: data_results_{d705,hospital,school,desert}_main.csv
#         tables/table_{d705,hospital,school,desert}_main.csv
#         tables/table_percode_abstention.csv
#         figures/fig_{d705,hospital,school,desert}_main_slide.png
#         figures/fig_percode_abstention.png

source(file.path(Sys.getenv("POLITICALRE_ROOT", unset = "."),
                  "code/robustness/robustness_common.R"))

FIG <- file.path(ROBUST, "figures"); TAB <- file.path(ROBUST, "tables")
dir.create(FIG, showWarnings=FALSE, recursive=TRUE); dir.create(TAB, showWarnings=FALSE, recursive=TRUE)

panel_raw <- load_panel()
turnover  <- load_turnover()

# `figure_outcome` (optional label string, e.g. "Abstention (%)"): the
# table/CSV always keeps all 6 outcomes, but the FIGURE narrows to just
# that one -- used for desert, where 5 of 6 outcomes are null and showing
# them alongside the one real signal buries it.
save_case_results <- function(id, treatment_fn, title, subtitle, figure_outcome=NULL) {
  results_raw <- bind_rows(lapply(COHORTS3, function(co) {
    trt_ctrl <- treatment_fn(co)
    run_twfe_cohort(panel_raw, turnover, co, trt_ctrl$treat_var, trt_ctrl$treated, trt_ctrl$control)
  }))
  if (nrow(results_raw) == 0) {
    cat(sprintf("!!! %s: 0 usable rows in all %d cohorts (every outcome dropped for collinearity/insufficient variation) -- skipping table/figure, NOT identifiable with current data.\n",
                id, length(COHORTS3)))
    return(results_raw)
  }
  results <- results_raw %>%
    mutate(ci_low=estimate-1.96*se, ci_high=estimate+1.96*se,
           outcome=factor(outcome, levels=sapply(OUTCOMES, `[[`, "label")),
           method=factor(method, levels=sapply(COHORTS3, `[[`, "method_lbl")))
  write_csv(results %>% mutate(outcome=as.character(outcome), method=as.character(method)),
            file.path(ROBUST, sprintf("data_results_%s_main.csv", id)))
  write_csv(results %>% mutate(across(c(estimate,se,ci_low,ci_high), ~round(.x,3))),
            file.path(TAB, sprintf("table_%s_main.csv", id)))
  cat(sprintf("Saved -> %s\n", file.path(TAB, sprintf("table_%s_main.csv", id))))
  if (is.null(figure_outcome)) {
    make_slide_figure(results, title, subtitle, file.path(FIG, sprintf("fig_%s_main_slide.png", id)))
  } else {
    make_slide_figure(results %>% filter(as.character(outcome) == figure_outcome), title, subtitle,
                       file.path(FIG, sprintf("fig_%s_main_slide.png", id)), width=10, height=6.5, ncol=1)
  }
  results
}

read_ctrl <- function(id, cohort_label) read_csv(file.path(ROBUST, sprintf("data/control_group_%s_cohort%s.csv", id, cohort_label)),
                                                  col_types=col_spec) %>% pull(code_insee) %>% unique()

# ── D705 (opening design) ──────────────────────────────────────────────
cat("========== D705 ==========\n")
d705_raw <- read_csv(file.path(PROJECT, "data/BPE_adisp/derived/d705_by_commune_year.csv"),
                      col_types = cols(code_insee = col_character(), annee = col_integer(), n_d705 = col_integer())) %>%
  mutate(code_insee = pad5(code_insee))
d705_presence <- function(yr) d705_raw %>% filter(annee == yr, n_d705 > 0) %>% distinct(code_insee) %>% pull(code_insee)

save_case_results("d705",
  function(co) list(treat_var="d705_treated",
                     treated=opening_codes(panel_raw, co$yr_lo, co$yr_hi, d705_presence(co$yr_lo), d705_presence(co$yr_hi)),
                     control=read_ctrl("d705", co$label)),
  title="Asylum-seeker reception centers (D705/CADA) and mayoral elections",
  subtitle="Main estimate, matched control (density + income + department FE), 95% CI")

# ── D107 / C104 / basket (closure design) ────────────────────────────────
# sequential_case_splits(): must match build_control_groups.R's cohort-order
# accumulation exactly, or the "treated" set here would disagree with which
# communes that script actually matched a control for (see its header).
for (case in CLOSURE_CASES) {
  cat(sprintf("\n========== %s ==========\n", case$label))
  raw <- load_case_raw(case)
  splits <- sequential_case_splits(case, raw, COHORTS3, panel_raw)
  save_case_results(case$id,
    function(co) list(treat_var=case$treat_var, treated=splits[[co$label]]$declined, control=read_ctrl(case$id, co$label)),
    title=case$title,
    subtitle=if (!is.null(case$subtitle)) case$subtitle else "Main estimate, survivor-matched control (density + income + department FE), 95% CI")
}

# ── Per-code abstention decomposition -- does ONE facility type drive the
# basket result, or is it spread across the basket? Same closure/survivor
# design, ABSTENTION ONLY (the one outcome with a real, bug-fix-surviving
# signal in the basket) to keep this fast. D107/C104 abstention rows above
# are reused, not recomputed. A102 (tresorerie) excluded -- discontinued
# nationwide by 2014, no survivor group for Cohort B/C.
cat("\n========== Per-code abstention decomposition ==========\n")
ABSTENTION <- list(OUTCOMES[[4]])
stopifnot(OUTCOMES[[4]]$var == "pct_abstention")

LABELED <- file.path(PROJECT, "data/BPE_adisp/labeled")
BPE25   <- file.path(PROJECT, "data/BPE_adisp/bpe2025/DS_BPE_CSV_FR.zip")
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

presence_for <- function(concept, yr) {
  codes <- bpe_codes_for_year(concept, yr)
  YEAR_DATA[[as.character(yr)]] %>% filter(TYPEQU %in% codes) %>%
    group_by(code_insee) %>% summarise(n=sum(NB_EQUIP), .groups="drop") %>%
    filter(n > 0) %>% pull(code_insee)
}

PERCODE <- list(
  list(concept="a101", name="A101 Police"), list(concept="a104", name="A104 Gendarmerie"),
  list(concept="c_maternelle", name="C101 Ecole maternelle"), list(concept="c201", name="C201 College"),
  list(concept="d101", name="D101 Hopital court sejour"), list(concept="d102", name="D102 Hopital moyen sejour"),
  list(concept="d103", name="D103 Hopital long sejour"), list(concept="d106", name="D106 Urgences"),
  list(concept="d201", name="D201 Medecin generaliste"), list(concept="d301", name="D307 Pharmacie")
)

# Same not-yet-treated fix as the CLOSURE_CASES loop above: run each
# code's 3 cohorts in order, a commune closed in an earlier cohort is
# dropped from later treated AND control pools. Rural-restricted (DENS_OK
# at yr_lo), same parity fix as case_split()/opening_codes() -- this
# diagnostic doesn't get the dept-level ">3 treated" pool filter the main
# CLOSURE_CASES results do (would need computing per facility code, 10x
# the bookkeeping for a secondary decomposition figure, not the published
# main table).
run_one <- function(spec, cohort, already_treated) {
  split <- closure_split(presence_for(spec$concept, cohort$yr_lo), presence_for(spec$concept, cohort$yr_hi))
  rural <- rural_codes(panel_raw, cohort$yr_lo)
  closed <- setdiff(intersect(split$closed, rural), already_treated)
  survived <- setdiff(intersect(split$survived, rural), already_treated)
  if (length(closed) < 5) return(list(result=NULL, closed=closed))
  ctrl <- tryCatch(match_control(panel_raw, cohort$yr_lo, closed, survived, load_income(cohort$yr_lo), verbose=FALSE),
                    error=function(e) NULL)
  if (is.null(ctrl) || length(ctrl) < 5) return(list(result=NULL, closed=closed))
  list(result=run_twfe_cohort(panel_raw, turnover, cohort, "closed", closed, ctrl, outcomes=ABSTENTION), closed=closed)
}

percode_results <- bind_rows(lapply(PERCODE, function(spec) {
  cat(sprintf("-- %s --\n", spec$name))
  already_treated <- character(0)
  out <- list()
  for (co in COHORTS3) {
    r <- run_one(spec, co, already_treated)
    if (!is.null(r$result)) out[[length(out)+1]] <- r$result
    already_treated <- union(already_treated, r$closed)
  }
  if (length(out) == 0) {
    cat(sprintf("  !!! %s: 0 usable cohorts (rural + n>=5 closed threshold) -- skipped.\n", spec$name))
    return(NULL)
  }
  bind_rows(out) %>% mutate(code = spec$name) %>% select(code, cohort, n_trt, estimate, se, p)
}))

# D107 (hospital) intentionally excluded here if save_case_results() skipped
# it (0 usable rows in every cohort, see that block's !!! warning) -- no
# table_hospital_main.csv to read in that case.
read_case_abstention <- function(id, label) {
  path <- file.path(TAB, sprintf("table_%s_main.csv", id))
  if (!file.exists(path)) {
    cat(sprintf("  !!! %s: table_%s_main.csv not found (case not identifiable, see above) -- excluded from per-code figure.\n", label, id))
    return(NULL)
  }
  read_csv(path, show_col_types=FALSE) %>% filter(outcome=="Abstention (%)") %>%
    transmute(code=label, cohort, n_trt, estimate, se, p)
}
extra <- bind_rows(
  read_case_abstention("hospital", "D107 Maternite"),
  read_case_abstention("school", "C104 Ecole elementaire"),
  read_case_abstention("desert", "ALL 12 (basket, net)")
)
percode_results <- bind_rows(percode_results, extra) %>%
  mutate(ci_low=estimate-1.96*se, ci_high=estimate+1.96*se, signif=p<0.05)

write_csv(percode_results, file.path(TAB, "table_percode_abstention.csv"))
cat(sprintf("Saved -> %s\n", file.path(TAB, "table_percode_abstention.csv")))

p <- ggplot(percode_results, aes(x=estimate, y=code, color=signif)) +
  geom_vline(xintercept=0, linetype="dashed", color="grey50") +
  geom_pointrange(aes(xmin=ci_low, xmax=ci_high), size=0.4, linewidth=0.7) +
  facet_wrap(~sprintf("Cohort %s", cohort), ncol=3) +
  scale_color_manual(values=c(`TRUE`="#c0392b", `FALSE`="#2980b9"), guide="none") +
  labs(title="Abstention effect by facility type -- is one service driving the basket result?",
       subtitle="Closure/decline vs survivor-matched control (density+income+dept FE), 95% CI. Red = p<0.05.",
       x="Estimated effect on abstention (pp)", y=NULL,
       caption="ALL 13 (basket, net) = the aggregate desert-basket result. Individual rows = single-facility closure, same design as hospital/school.") +
  theme_bw(base_size=11) +
  theme(plot.caption=element_text(hjust=0, size=8, color="grey40"))
ggsave(file.path(FIG, "fig_percode_abstention.png"), p, width=13, height=6.5, dpi=180)
cat(sprintf("Saved -> %s\n", file.path(FIG, "fig_percode_abstention.png")))
