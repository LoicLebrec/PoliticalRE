# Raw group-mean trend, treated vs matched control -- the "eyeball it
# yourself" companion to the desert-basket TWFE estimate (same spirit as
# callaway_santanna/build_cs_eventstudy.R's cs_raw_trends figure): group
# means by election year across ALL 4 observed periods (2008/2014/2020/
# 2026), not model coefficients, one panel per cohort. Desert basket
# chosen because it's the one case in this folder with a real, bug-fix-
# surviving signal on abstention (see build_results.R history) -- this
# shows what that signal actually looks like in the raw data, not just the
# regression coefficient.
#
# Requires build_control_groups.R to have run first (reads its
# control_group_desert_cohort*.csv output).
#
# Output: figures/fig_desert_treated_vs_control.png

source(file.path(Sys.getenv("POLITICALRE_ROOT", unset = "/home/loiclebrec/ENRpolitical/Python/PoliticalRE"),
                  "simple_regression/publication/robustness/robustness_common.R"))

FIG <- file.path(ROBUST, "figures")
panel_raw <- load_panel()
case <- CLOSURE_CASES$desert
raw <- load_case_raw(case)
ELECTION_YEARS <- c(2008L, 2014L, 2020L, 2026L)

# sequential_case_splits(), not plain case_split() per cohort -- must match
# build_control_groups.R's not-yet-treated accumulation, or this figure's
# groups disagree with the regression's (see robustness_common.R header).
splits <- sequential_case_splits(case, raw, COHORTS3, panel_raw)

trend_one_cohort <- function(co) {
  split <- splits[[co$label]]
  ctrl <- read_csv(file.path(ROBUST, sprintf("data/control_group_desert_cohort%s.csv", co$label)),
                    col_types=col_spec) %>% pull(code_insee) %>% unique()
  d <- panel_raw %>% filter(annee %in% ELECTION_YEARS, code_insee %in% c(split$declined, ctrl)) %>%
    distinct(code_insee, annee, .keep_all=TRUE) %>%
    mutate(group = if_else(code_insee %in% split$declined, "Declined (treated)", "Matched control")) %>%
    filter(!is.na(pct_abstention))
  d %>% group_by(group, annee) %>%
    summarise(mean_val = mean(pct_abstention), se = sd(pct_abstention)/sqrt(n()), n = n(), .groups="drop") %>%
    mutate(cohort = sprintf("Cohort %s (treated by %d)", co$label, co$yr_hi_elec), treat_year = co$yr_hi_elec)
}

trends <- bind_rows(lapply(COHORTS3, trend_one_cohort)) %>%
  mutate(ci_low = mean_val - 1.96*se, ci_high = mean_val + 1.96*se,
         cohort = factor(cohort, levels = sapply(COHORTS3, function(co) sprintf("Cohort %s (treated by %d)", co$label, co$yr_hi_elec))))

p <- ggplot(trends, aes(x=annee, y=mean_val, color=group)) +
  geom_vline(aes(xintercept=treat_year), linetype="dashed", color="grey50", linewidth=0.5) +
  geom_line(linewidth=1) +
  geom_pointrange(aes(ymin=ci_low, ymax=ci_high), size=0.5, linewidth=0.8) +
  facet_wrap(~cohort, ncol=3) +
  scale_x_continuous(breaks=ELECTION_YEARS) +
  scale_color_manual(values=c("Declined (treated)"="#e34948", "Matched control"="#2a78d6"), name=NULL) +
  labs(title="Parallel-trends check: did the two groups move together before the service loss?",
       subtitle="Actual abstention rate by election, treated (lost services) vs matched control -- not model output. Dashed line = election when services were lost.",
       x="Election year", y="Abstention (% of registered voters)") +
  theme_bw(base_size=12) +
  theme(legend.position="bottom", strip.text=element_text(face="bold"))

ggsave(file.path(FIG, "fig_desert_treated_vs_control.png"), p, width=13, height=6, dpi=180)
cat(sprintf("Saved -> %s\n", file.path(FIG, "fig_desert_treated_vs_control.png")))
