# Callaway & Sant'Anna (2021) staggered-adoption DiD, the counterpart to
# twfe/build_robustness_combined.R and heckman/build_heckman_simple.R.
#
# Why: the TWFE pipeline runs each cohort (A: 2008->2014, B: 2014->2020,
# C: 2020->2026) as a SEPARATE 2-period 2x2 DiD -- clean by construction,
# not exposed to the Goodman-Bacon staggered-timing negative-weighting
# problem (that requires a SINGLE regression pooling multiple treatment
# cohorts across many periods, which nothing in build_robustness_combined.R
# does). But that guarantee is implicit/undocumented, and it throws away
# real pre-treatment information: each cohort only ever sees ONE pre-period
# (t-1) and ONE post-period (t+1), no pre-trend check beyond that. CS gives
# the full event-time (t-n ... t+n) picture across all 3 cohorts pooled
# properly (group-time ATT(g,t), then aggregated to an event-study), and is
# the standard modern robustness check a referee will expect given cohorts
# span 2008-2026.
#
# Periods: 2008, 2014, 2020, 2026 (the 4 election years, ~6y apart) --
# recoded to an election index 1..4 for att_gt()'s tname/gname (see
# ELEC_IDX below). Using the raw calendar year as tname "worked" (att_gt
# just needs consistently-spaced values) but two things were off: (1) the
# event-study x-axis came out in year-diffs (-12,-6,0,6,12) instead of the
# standard integer event-time researchers expect (-2,-1,0,1,2); (2)
# att_gt()'s `anticipation` arg counts in tname units, so anticipation=1
# would silently mean "1 calendar year early" (not aligned to any real
# period) instead of "one election early". Election-index tname fixes both.
# Group (first.treat) = index of the first election at which n_parcs_cumul
# > 0 (0 = never treated in the sample window). Universe: rural density 5-7
# in EVERY period observed (same rural-only restriction as the cohort
# construction elsewhere), commune_fixe==1 (fusion exclusion, as everywhere
# else in this pipeline).
#
# Run TWICE, once per control pool (never-treated communes restricted to
# the matched vs baseline pool) -- same "socio-eco matched vs not" split as
# the rest of the TWFE pipeline. control_group="nevertreated" in att_gt:
# not-yet-treated units are EXCLUDED as comparisons for earlier cohorts,
# to avoid contaminating comparisons with units that get treated later
# (same logic as excluding future-treated from control pools elsewhere).
#
# Output: figures/cs_eventstudy_combined.png (t-n..t+n event study, all outcomes x both control pools)
#         figures/cs_raw_trends_cohortB.png (group means by year, Cohort B -- intuitive companion figure)
#         tables/table_cs_summary.csv (simple ATT + dynamic ATT per (g,e))
#         tables/table_cs_anticipation_sensitivity.csv (anticipation=1 robustness check)

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(tidyr)
  library(did); library(ggplot2)
})

# att_gt() uses a multiplier bootstrap for inference -- without a fixed
# seed, SE/p vary slightly run to run. Fixed once here so results are
# reproducible.
set.seed(20260706)

PROJECT <- Sys.getenv("POLITICALRE_ROOT", unset = ".")
PANEL   <- file.path(PROJECT, "code/panel.csv")
PUB     <- file.path(PROJECT, "code/callaway_santanna")
FIG     <- file.path(PUB, "figures")
TAB     <- file.path(PUB, "tables")
dir.create(FIG, showWarnings = FALSE, recursive = TRUE)
dir.create(TAB, showWarnings = FALSE, recursive = TRUE)

col_spec <- cols(code_insee = col_character(), dep = col_character(), .default = col_guess())
DENS_OK  <- c("5","6","7")
PERIODS  <- c(2008L, 2014L, 2020L, 2026L)
ELEC_IDX <- setNames(seq_along(PERIODS), PERIODS)  # year -> election index (1..4)

panel_raw <- read_csv(PANEL, col_types = col_spec) %>% filter(commune_fixe == 1)

OUTCOMES <- list(
  list(var="recandidature_pp",          label="Candidacy (pp)"),
  list(var="reconduit_pp",              label="Reelection (pp)"),
  list(var="pct_voix_gagnant_exprimes", label="Winner vote share (%)"),
  list(var="pct_abstention",            label="Abstention (%)"),
  list(var="turnover_pp",               label="Candidate turnover (%)"),
  list(var="pct_voix_sortant_exprimes", label="Incumbent vote share (%)")
)

# ── Rural-throughout universe, first.treat group ───────────────────────────
# rural (density 5-7) in EVERY period the commune has data for, among PERIODS
rural_stable <- panel_raw %>% filter(annee %in% PERIODS) %>%
  distinct(code_insee, annee, .keep_all=TRUE) %>%
  group_by(code_insee) %>%
  summarise(n_obs = n(), n_rural = sum(categorie_dens %in% DENS_OK), .groups="drop") %>%
  filter(n_obs == n_rural) %>% pull(code_insee)

first_treat <- panel_raw %>% filter(annee %in% PERIODS, code_insee %in% rural_stable) %>%
  distinct(code_insee, annee, .keep_all=TRUE) %>%
  mutate(treated_now = as.numeric(n_parcs_cumul) > 0) %>%
  group_by(code_insee) %>%
  summarise(first_treat_year = if (any(treated_now)) min(annee[treated_now]) else 0L, .groups="drop") %>%
  mutate(first.treat = if_else(first_treat_year == 0L, 0L, unname(ELEC_IDX[as.character(first_treat_year)])))

cat(sprintf("Rural-throughout universe: %d communes\n", length(rural_stable)))
cat(sprintf("Election index -> year: %s\n",
            paste(sprintf("%d=%s", ELEC_IDX, names(ELEC_IDX)), collapse=", ")))
cat("Group sizes (first.treat, election index, 0 = never treated):\n")
print(table(first_treat$first.treat))

turnover <- read_csv(file.path(PROJECT, "code/shared_data/turnover_candidats.csv"),
                      col_types = col_spec) %>% select(code_insee, annee, turnover_pp)

# Baseline population covariate, same rationale as TWFE's log_pop:post --
# but here it's just a per-unit covariate in the DR estimator's xformla
# (not interacted with a period FE), no collinearity risk since att_gt does
# not include a unit FE the way feols does. Measured at each commune's
# EARLIEST observed period (not tied to any one cohort's treatment year),
# so it works as a single time-invariant covariate across all first.treat
# groups pooled together.
pop_baseline <- panel_raw %>% filter(annee %in% PERIODS, code_insee %in% rural_stable) %>%
  distinct(code_insee, annee, .keep_all=TRUE) %>%
  group_by(code_insee) %>% slice_min(annee, n=1, with_ties=FALSE) %>% ungroup() %>%
  transmute(code_insee, log_pop=log1p(as.numeric(inscrits)))

base_long <- panel_raw %>% filter(annee %in% PERIODS, code_insee %in% rural_stable) %>%
  distinct(code_insee, annee, .keep_all=TRUE) %>%
  mutate(reconduit_pp=reconduit*100, recandidature_pp=recandidature*100) %>%
  left_join(turnover, by=c("code_insee","annee")) %>%
  left_join(first_treat, by="code_insee") %>%
  left_join(pop_baseline, by="code_insee") %>%
  mutate(id_num = as.integer(factor(code_insee)), elec_idx = unname(ELEC_IDX[as.character(annee)]))

ctrl_matched  <- read_csv(file.path(PROJECT, "code/control_group_matched.csv"),
                           col_types=col_spec) %>% pull(code_insee) %>% unique()
ctrl_baseline <- read_csv(file.path(PROJECT, "code/shared_data/control_group_baseline.csv"),
                           col_types=col_spec) %>% pull(code_insee) %>% unique()

# ── Run CS for one control pool, all outcomes ──────────────────────────────
run_cs_pool <- function(ctrl_pool, ctrl_label, anticipation = 0, dynamic = TRUE) {
  cat(sprintf("\n========== Control group: %s ==========\n", ctrl_label))
  never_treated_codes <- base_long %>% filter(first.treat == 0L, code_insee %in% ctrl_pool) %>%
    distinct(code_insee) %>% pull(code_insee)
  treated_codes <- base_long %>% filter(first.treat > 0L) %>% distinct(code_insee) %>% pull(code_insee)
  d_sample <- base_long %>% filter(code_insee %in% c(treated_codes, never_treated_codes))
  cat(sprintf("Sample: %d treated communes | %d never-treated (%s) communes\n",
              length(treated_codes), length(never_treated_codes), ctrl_label))
  # 2008 (election index 1) is the panel's first period -> group
  # first.treat==1 has NO observable pre-period. att_gt() drops these
  # silently every run (visible only as a generic warning) -- surfaced
  # explicitly here instead.
  n_dropped_2008 <- d_sample %>% filter(first.treat == 1L) %>% distinct(code_insee) %>% nrow()
  cat(sprintf("  NOTE: %d communes first-treated in 2008 (panel's first period) have no observable\n",
              n_dropped_2008))
  cat("        pre-period -- att_gt() drops them from every outcome below.\n")

  summary_rows <- list()
  ev_rows <- list()
  for (o in OUTCOMES) {
    d_out <- d_sample %>% filter(!is.na(.data[[o$var]]), !is.na(log_pop))
    att <- tryCatch(
      att_gt(yname = o$var, tname = "elec_idx", idname = "id_num", gname = "first.treat",
             xformla = ~log_pop, data = d_out, control_group = "nevertreated",
             base_period = "universal", anticipation = anticipation,
             allow_unbalanced_panel = TRUE, clustervars = "id_num", print_details = FALSE),
      error = function(e) { cat(sprintf("  ERROR att_gt (%s): %s\n", o$label, conditionMessage(e))); NULL })
    if (is.null(att)) next

    agg_simple  <- tryCatch(aggte(att, type = "simple"),  error = function(e) NULL)
    if (is.null(agg_simple)) next
    agg_dynamic <- if (dynamic) tryCatch(aggte(att, type = "dynamic"), error = function(e) NULL) else NULL
    if (dynamic && is.null(agg_dynamic)) next

    cat(sprintf("  %-28s overall ATT = %+.3f (SE %.3f, p=%.3f)\n", o$label,
                agg_simple$overall.att, agg_simple$overall.se,
                2*pnorm(-abs(agg_simple$overall.att/agg_simple$overall.se))))

    # Formal joint pre-trend test (Callaway & Sant'Anna's integrated CvM
    # test, conditional_did_pretest()) was tried and DROPPED: its Step 1
    # resamples X-weighted group-time ATTs independently of `biters` (that
    # arg only controls Step 2's critical value), so on this sample
    # (~9-30k communes) it ran 8 cores at 100% for 6+ minutes without
    # finishing even once. The package's own deprecation notice agrees:
    # "most users find the pre-tests already reported by att_gt already
    # sufficient" -- i.e. the individual pre-period ATT(e) estimates below
    # (event_time < 0, already computed for free as part of the dynamic
    # aggregation, no extra bootstrap), each with its own 95% CI, visible
    # directly on the event-study plot. Cheap substitute here: flag if ANY
    # individual pre-period point is significant at 5% (not a joint test,
    # just a quick screen -- read the plot for the real picture).
    # base_period="universal" (set above) pins event_time == -1 to exactly
    # 0 with se=NA (mechanical normalization, not an estimate) -- excluded
    # here so it can't produce a spurious NA/TRUE in the any() check below.
    pre_sig <- NA
    if (dynamic) {
      pre_idx <- agg_dynamic$egt < -1
      pre_sig <- if (any(pre_idx)) any(2*pnorm(-abs(agg_dynamic$att.egt[pre_idx]/agg_dynamic$se.egt[pre_idx])) < .05, na.rm = TRUE) else NA
      cat(sprintf("    Pre-period check: %d pre-treatment event-time points, any individually sig at 5%%: %s\n",
                  sum(pre_idx), if (is.na(pre_sig)) "n/a" else pre_sig))
    }

    summary_rows[[length(summary_rows)+1]] <- tibble(
      control = ctrl_label, outcome = o$label,
      overall_att = agg_simple$overall.att, overall_se = agg_simple$overall.se,
      overall_p = 2*pnorm(-abs(agg_simple$overall.att/agg_simple$overall.se)),
      any_presig = pre_sig
    )

    # Only the combined figure (all outcomes x both control pools, built
    # below from ev_rows) ships in the publication folder -- no per-outcome
    # PNG here, to avoid 12 near-duplicate single-outcome images alongside it.
    if (dynamic) {
      ev <- tibble(event_time = agg_dynamic$egt, estimate = agg_dynamic$att.egt,
                   se = agg_dynamic$se.egt) %>%
        mutate(ci_low = estimate - 1.96*se, ci_high = estimate + 1.96*se)
      ev_rows[[length(ev_rows)+1]] <- ev %>% mutate(outcome = o$label, control = ctrl_label)
    }
  }
  list(summary = bind_rows(summary_rows), ev = bind_rows(ev_rows))
}

res_matched  <- run_cs_pool(ctrl_matched,  "Socioeconomically matched control")
res_baseline <- run_cs_pool(ctrl_baseline, "Baseline control")

res_all <- bind_rows(res_matched$summary, res_baseline$summary) %>%
  mutate(across(c(overall_att, overall_se), ~round(.x,3)), overall_p = round(overall_p,3))
write_csv(res_all, file.path(TAB, "table_cs_summary.csv"))
cat(sprintf("\nSaved -> %s\n", file.path(TAB, "table_cs_summary.csv")))
print(res_all, n=20)

# ── Anticipation sensitivity check (main spec above uses anticipation=0)
# anticipation=1 (in elec_idx units) means treated units can already react
# 1 full election (~6y) before their recorded commissioning date. That's not
# an arbitrary probe: descriptive/tables/table_descriptive_stats.csv shows
# permit-filed -> commissioned takes a median 5.0y across commissioned
# parks (authorization-granted -> commissioned is shorter, ~3.0y) -- so 6y
# of anticipation is roughly the "a mayor could plausibly know about this
# from the permit filing" horizon, not a token/placebo value. Simple ATT
# only (no event-study/figure -- this is a sensitivity check on the
# headline number, not a second full analysis) -- dynamic=FALSE skips the
# extra aggte(type="dynamic") bootstrap this doesn't need.
cat("\n========== Sensitivity: anticipation = 1 election (~6y) ==========\n")
res_matched_a1  <- run_cs_pool(ctrl_matched,  "Socioeconomically matched control", anticipation = 1, dynamic = FALSE)
res_baseline_a1 <- run_cs_pool(ctrl_baseline, "Baseline control", anticipation = 1, dynamic = FALSE)
res_anticipation <- bind_rows(res_matched_a1$summary, res_baseline_a1$summary) %>%
  mutate(anticipation = 1, across(c(overall_att, overall_se), ~round(.x,3)), overall_p = round(overall_p,3)) %>%
  select(control, outcome, anticipation, overall_att, overall_se, overall_p)
write_csv(res_anticipation, file.path(TAB, "table_cs_anticipation_sensitivity.csv"))
cat(sprintf("Saved -> %s\n", file.path(TAB, "table_cs_anticipation_sensitivity.csv")))
print(res_anticipation, n=20)

# ── Combined event-study: all 6 outcomes x 2 control pools, one figure ────
# Event time on x (shared, same scale/interpretation for all outcomes),
# ATT(e) on y, faceted by outcome (all in pp/% units, comparable), color =
# control pool. Same design logic as twfe/build_master_singlepanel.R: one
# shared axis instead of 12 separate images.
ev_all <- bind_rows(res_matched$ev, res_baseline$ev) %>%
  mutate(outcome = factor(outcome, levels = sapply(OUTCOMES, function(o) o$label)))

# "e-1"/"e0"/"e+1" style tick labels instead of bare integers -- clearer at
# a glance that this is event-time (elections since first treatment), not
# a raw count or a year.
e_labeller <- function(x) sub("^e\\+0$", "e0", sprintf("e%+d", x))

p_combined <- ggplot(ev_all, aes(x = event_time, y = estimate, color = control)) +
  geom_vline(xintercept = -0.5, linetype = "dashed", color = "grey50", linewidth = 0.4) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "grey50", linewidth = 0.4) +
  geom_line(aes(group = control), alpha = 0.5, position = position_dodge(width = 0.8)) +
  geom_pointrange(aes(ymin = ci_low, ymax = ci_high), size = 0.4, linewidth = 0.7,
                   position = position_dodge(width = 0.8)) +
  facet_wrap(~outcome, scales = "free_y", ncol = 3) +
  scale_x_continuous(breaks = function(lims) seq(ceiling(lims[1]), floor(lims[2])), labels = e_labeller) +
  scale_color_manual(values = c("Socioeconomically matched control" = "#2a78d6", "Baseline control" = "#e34948"),
                      name = "Control group") +
  labs(title = "Callaway-Sant'Anna event study -- all outcomes, both control groups",
       subtitle = "e0 = each commune's own first-treatment election, not a shared calendar year",
       x = "Event time (elections relative to first treatment, t-n = pre, t+n = post; 1 election ~ 6y)",
       y = "ATT(e) (pp / % depending on outcome)",
       caption = paste(
         "Group-time ATT aggregated dynamically (Callaway & Sant'Anna 2021), xformla = ~log_pop (baseline population).",
         "3 cohorts pooled at each event time: e0 = 2014 for Cohort A, 2020 for Cohort B, 2026 for Cohort C (first.treat = 2014/2020/2026).",
         "Bars = 95% CI. Free y-scale per panel (outcomes not on the same units). 2008-first-treated communes dropped (no observable pre-period).",
         sep = "\n")) +
  theme_bw(base_size = 12) +
  theme(legend.position = "bottom", plot.caption = element_text(hjust = 0, size = 8, color = "grey40"))

ggsave(file.path(FIG, "cs_eventstudy_combined.png"), p_combined, width = 13, height = 8, dpi = 200)
cat(sprintf("Saved -> %s\n", file.path(FIG, "cs_eventstudy_combined.png")))

# ── Raw outcome trends, Cohort B: intuitive companion to the event-study
# above -- group means by election year (all 4 observed periods, not just
# the 2x2 window), not model coefficients. Meant as the "eyeball the
# pre-trends yourself" figure before the formal ATT(e) estimates, e.g. for
# a talk. Reuses base_long/first.treat/ctrl_matched already built above
# (same CS universe -- rural EVERY period observed -- rather than the
# TWFE-cohort definition, so this stays consistent with the event-study
# figure it sits next to, not a second slightly-different sample).
cat("\n========== Raw trends figure (Cohort B, matched control) ==========\n")
treated_b_codes <- base_long %>% filter(first.treat == ELEC_IDX[["2020"]]) %>%
  distinct(code_insee) %>% pull(code_insee)
never_treated_matched <- base_long %>% filter(first.treat == 0L, code_insee %in% ctrl_matched) %>%
  distinct(code_insee) %>% pull(code_insee)

trends_dat <- base_long %>% filter(code_insee %in% c(treated_b_codes, never_treated_matched)) %>%
  mutate(group = if_else(code_insee %in% treated_b_codes, "Treated (Cohort B)", "Matched control"))

trends <- bind_rows(lapply(OUTCOMES, function(o) {
  trends_dat %>% filter(!is.na(.data[[o$var]])) %>%
    group_by(group, annee) %>%
    summarise(mean_val = mean(.data[[o$var]], na.rm = TRUE),
              se = sd(.data[[o$var]], na.rm = TRUE) / sqrt(n()), .groups = "drop") %>%
    mutate(outcome = o$label)
})) %>% mutate(outcome = factor(outcome, levels = sapply(OUTCOMES, `[[`, "label")))

p_trends <- ggplot(trends, aes(x = annee, y = mean_val, color = group)) +
  geom_vline(xintercept = 2020, linetype = "dashed", color = "grey50", linewidth = 0.5) +
  geom_line(linewidth = 1) +
  geom_pointrange(aes(ymin = mean_val - 1.96*se, ymax = mean_val + 1.96*se), size = 0.5, linewidth = 0.8) +
  facet_wrap(~outcome, scales = "free_y", ncol = 3) +
  scale_x_continuous(breaks = PERIODS) +
  scale_color_manual(values = c("Treated (Cohort B)" = "#e34948", "Matched control" = "#2a78d6"), name = NULL) +
  labs(title = "Raw outcome trends -- Cohort B treated vs matched control",
       subtitle = "Group means, 95% CI. Dashed line = treatment realized (2020, first commissioned park).",
       x = "Election year", y = "Mean (pp / %)") +
  theme_bw(base_size = 12) +
  theme(legend.position = "bottom")

ggsave(file.path(FIG, "cs_raw_trends_cohortB.png"), p_trends, width = 11, height = 6.5, dpi = 180)
cat(sprintf("Saved -> %s\n", file.path(FIG, "cs_raw_trends_cohortB.png")))
