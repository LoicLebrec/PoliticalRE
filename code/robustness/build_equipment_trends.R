# Equipment-count trend, per BPE facility type, 2008/2014/2020/2025 --
# descriptive companion to the robustness pipelines (not a regression),
# split by TREATED vs MATCHED CONTROL communes (desert-basket Cohort B --
# the repo's convention main cohort) so the panels show whether the two
# groups' underlying equipment levels/trends actually look different, not
# just the electoral-outcome regression coefficient. Same 12 concepts used
# elsewhere here (the 12-code desert basket -- A102/tresorerie is excluded
# from the basket itself, see robustness_common.R::CLOSURE_CASES -- plus
# D705). Per-year code identity resolved via
# robustness_common.R::bpe_codes_for_year().
#
# Requires build_control_groups.R to have run first (reads its
# control_group_desert_cohortB.csv output).
#
# Output: figures/fig_equipment_trends.png, tables/table_equipment_trends.csv

source(file.path(Sys.getenv("POLITICALRE_ROOT", unset = "."),
                  "code/robustness/robustness_common.R"))

FIG <- file.path(ROBUST, "figures"); TAB <- file.path(ROBUST, "tables")
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

# ── Treated vs control commune sets (desert basket, Cohort B) ─────────────
panel_raw <- load_panel()
case <- CLOSURE_CASES$desert
raw <- load_case_raw(case)
co_b <- COHORTS3[[2]]
# sequential_case_splits(), not plain case_split() -- must match
# build_control_groups.R's not-yet-treated accumulation (see
# robustness_common.R header), or "treated" here disagrees with which
# communes control_group_desert_cohortB.csv was actually matched against.
split_b <- sequential_case_splits(case, raw, COHORTS3, panel_raw)[["B"]]
treated_codes <- split_b$declined
control_codes <- read_csv(file.path(ROBUST, "data/control_group_desert_cohortB.csv"), col_types=col_spec) %>%
  pull(code_insee) %>% unique()
cat(sprintf("Desert Cohort B: %d treated (declined) | %d matched control\n", length(treated_codes), length(control_codes)))

group_total <- function(concept, yr, codes) {
  bpe_codes <- bpe_codes_for_year(concept, yr)
  d <- YEAR_DATA[[as.character(yr)]] %>% filter(TYPEQU %in% bpe_codes)
  if (!is.null(codes)) d <- d %>% filter(code_insee %in% codes)
  sum(d$NB_EQUIP, na.rm=TRUE)
}

CONCEPTS <- list(
  list(concept="d705",          label="D705 Asylum reception (CADA)"),
  list(concept="d107",          label="D107 Maternity ward"),
  list(concept="c_elementaire", label="Elementary school"),
  list(concept="c201",          label="College"),
  list(concept="a101",          label="Police"),
  list(concept="a104",          label="Gendarmerie"),
  list(concept="d101",          label="Hospital (short stay)"),
  list(concept="d102",          label="Hospital (medium stay)"),
  list(concept="d103",          label="Hospital (long stay)"),
  list(concept="d106",          label="Emergency (urgences)"),
  list(concept="d201",          label="GP doctor"),
  list(concept="d301",          label="Pharmacy")
)
YEARS <- c(2008L, 2014L, 2020L, 2025L)

trends <- bind_rows(lapply(CONCEPTS, function(cc) {
  bind_rows(
    tibble(type=cc$label, group="National",           annee=YEARS, total=sapply(YEARS, function(y) group_total(cc$concept, y, NULL))),
    tibble(type=cc$label, group="Declined (treated)", annee=YEARS, total=sapply(YEARS, function(y) group_total(cc$concept, y, treated_codes))),
    tibble(type=cc$label, group="Matched control",     annee=YEARS, total=sapply(YEARS, function(y) group_total(cc$concept, y, control_codes)))
  )
})) %>% mutate(type = factor(type, levels = sapply(CONCEPTS, `[[`, "label")))

write_csv(trends, file.path(TAB, "table_equipment_trends.csv"))
cat(sprintf("Saved -> %s\n", file.path(TAB, "table_equipment_trends.csv")))
print(trends, n=100)

# National (~35k communes) dwarfs the treated (~200-400) and control
# (~2-3k) subsets by 10-100x -- a shared count axis would flatten the two
# group lines to near-zero. Indexed to each SERIES' OWN 2008 level = 100
# instead (same fix as the earlier all-in-one-panel chart): all 3 lines
# read as "% change since 2008" on one axis, comparable regardless of
# absolute size.
indexed <- trends %>% group_by(type, group) %>% mutate(index = 100 * total / total[annee == 2008L]) %>% ungroup()

p <- ggplot(indexed, aes(x=annee, y=index, color=group)) +
  geom_hline(yintercept=100, linetype="dashed", color="grey75", linewidth=0.4) +
  geom_line(linewidth=0.9) +
  geom_point(size=1.8) +
  facet_wrap(~type, scales="free_y", ncol=4) +
  scale_x_continuous(breaks=YEARS) +
  scale_color_manual(values=c("National"="#52514e", "Declined (treated)"="#e34948", "Matched control"="#2a78d6"), name=NULL) +
  labs(title="How has each type of public service changed since 2008?",
       subtitle="France-wide total vs. the two commune groups compared above (declined vs matched control). Each line set to 100 in 2008 so trends are comparable.",
       x=NULL, y="Change since 2008 (2008 = 100)") +
  theme_bw(base_size=11) +
  theme(
    strip.text=element_text(face="bold", size=9),
    panel.grid.minor=element_blank(),
    axis.text.x=element_text(size=8),
    legend.position="bottom",
    plot.title=element_text(face="bold", size=15),
    plot.subtitle=element_text(size=9, color="grey40")
  )

ggsave(file.path(FIG, "fig_equipment_trends.png"), p, width=13, height=8, dpi=180)
cat(sprintf("Saved -> %s\n", file.path(FIG, "fig_equipment_trends.png")))
