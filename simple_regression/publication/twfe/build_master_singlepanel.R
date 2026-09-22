# Master graph -- a single x-axis (estimated effect), a single y-axis (the
# 6 outcome variables), each heterogeneity test in its own color, direct
# labels for every specification. Size split into 9 categories (not 8):
# Municipality size and Installation power kept separate.
#
# Palette: 9 validated categorical hues (scripts/validate_palette.js, ALL
# CHECKS PASS, 9th hue #a0522d added and tested -- initial brown/teal
# candidates failed the chroma floor, sienna passes). Still not 23
# individual hues: the skill's rule stands -- past ~9 series, a generated
# hue per series is no longer CVD-reliable. Each individual specification
# stays identifiable via a direct label (ggrepel), not a unique hue.
#
# Full-page (paper) format: 18 x 24 in, dpi 200.
#
# Source: data_results_all_specs.csv (cache from build_robustness_combined.R)

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(ggplot2); library(stringr); library(ggrepel)
})

PROJECT <- Sys.getenv("POLITICALRE_ROOT", unset = "/home/loiclebrec/ENRpolitical/Python/PoliticalRE")
PUB     <- file.path(PROJECT, "simple_regression/publication/twfe")
FIG     <- file.path(PUB, "figures")

res <- read_csv(file.path(PUB, "data_results_all_specs.csv"), show_col_types = FALSE)

# ── Test category (Municipality size and Installation power SEPARATED,
# 9 categories) ────────────────────────────────────────────────────────────
res <- res %>%
  mutate(
    category = case_when(
      is_ref                              ~ "Reference",
      str_detect(spec, "^\\[Milestones\\]")          ~ "Milestones",
      str_detect(spec, "^\\[Regions\\]")             ~ "Regions",
      str_detect(spec, "^\\[Electoral system\\]")    ~ "Electoral system",
      str_detect(spec, "^\\[Stability\\]")           ~ "Mayor stability",
      str_detect(spec, "^\\[Municipality size\\]")   ~ "Municipality size",
      str_detect(spec, "^\\[Installation power\\]")  ~ "Installation power",
      str_detect(spec, "^\\[Cohorts\\]")             ~ "Cohorts",
      str_detect(spec, "^\\[Competitiveness\\]")     ~ "Competitiveness",
      str_detect(spec, "^\\[Income\\]")              ~ "Income",
      TRUE ~ "Other"
    ),
    spec_short = str_remove(spec, "^\\[[^]]+\\]\\s*") %>% str_remove("\\s*\\(n[^)]*\\)$")
  )

CAT_LEVELS <- c("Milestones","Regions","Electoral system","Mayor stability","Municipality size",
               "Installation power","Cohorts","Competitiveness","Income")
CAT_COLORS <- c(
  "Milestones"                = "#2a78d6",  # blue
  "Regions"                   = "#1baf7a",  # aqua
  "Electoral system"          = "#eda100",  # yellow
  "Mayor stability"           = "#008300",  # green
  "Municipality size"         = "#4a3aa7",  # violet
  "Cohorts"                   = "#e34948",  # red
  "Competitiveness"           = "#e87ba4",  # magenta
  "Income"                    = "#eb6834",  # orange
  "Installation power"        = "#a0522d",  # sienna (9th hue, validated)
  "Reference"                 = "grey45"
)

OUT_LEVELS <- c("Candidacy\n(pp)", "Reelection\n(pp)", "Winner vote share\n(% valid votes)",
                "Abstention\n(% registered)", "Candidate turnover\n(%)", "Incumbent vote share\n(% valid votes)")
res <- res %>% mutate(
  category = factor(category, levels = c(CAT_LEVELS, "Reference")),
  outcome = factor(outcome, levels = OUT_LEVELS),
  outcome_y = as.integer(outcome),
  signif = p < 0.05
)

spec_rank <- res %>% distinct(spec, category, is_ref) %>%
  arrange(is_ref, category, spec) %>%
  mutate(rank = row_number() - 1,
         offset = (rank - (n()-1)/2) / (n()-1) * 0.85)

res <- res %>% left_join(spec_rank %>% select(spec, offset), by = "spec") %>%
  mutate(y_pos = outcome_y + offset)

cat(sprintf("Categories: %s\n", paste(levels(res$category), collapse=", ")))
cat(sprintf("Total specifications (incl. reference): %d\n", n_distinct(res$spec)))

p <- ggplot(res, aes(x = estimate, y = y_pos, color = category, shape = signif)) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "grey70", linewidth = 0.6) +
  geom_hline(yintercept = seq(1.5, 5.5, 1), color = "grey88", linewidth = 0.4) +
  geom_linerange(aes(xmin = ci_low, xmax = ci_high), linewidth = 0.45, alpha = 0.55,
                 orientation = "y") +
  geom_point(size = 2.6, stroke = 0.5) +
  # direction="x" keeps each label pinned to its own row's y (already unique
  # per spec via the rank offset above) -- repel only nudges left/right, so
  # a label can never drift onto a neighboring outcome row's point/text
  # (the failure mode seen before: e.g. "Mayor turnover 2020" bleeding onto
  # the row above). bg.color gives labels an opaque halo so the x=0
  # reference line (and gridlines/points) don't visually merge into the
  # glyphs when a label sits on top of them.
  geom_text_repel(aes(label = spec_short), size = 2.3, max.overlaps = 60,
                  segment.size = 0.25, segment.alpha = 0.5, seed = 42,
                  min.segment.length = 0.1, show.legend = FALSE,
                  direction = "x", force = 2, force_pull = 0.5,
                  box.padding = 0.15, bg.color = "white", bg.r = 0.12) +
  scale_color_manual(values = CAT_COLORS, breaks = c(CAT_LEVELS, "Reference"), name = "Category") +
  scale_shape_manual(values = c(`FALSE` = 16, `TRUE` = 18), name = "p < 0.05",
                     labels = c("n.s.", "p < 0.05")) +
  scale_y_continuous(breaks = 1:6, labels = OUT_LEVELS, limits = c(0.3, 6.75), expand = c(0,0)) +
  coord_cartesian(xlim = c(-27, 27)) +
  labs(
    title = "TWFE Specification Curve — All Robustness Checks (Cohort B)",
    subtitle = "All outcome variables (Y axis) x all heterogeneity tests (color = category, label = specification)",
    x = "Estimated effect (pp / % depending on the variable) + 95% CI",
    y = NULL,
    caption = paste(
      "9 test categories (color, CVD-validated palette -- 9th hue #a0522d added and re-validated) instead of 23 individual hues: past ~9 series, a generated hue is no longer reliable (dataviz skill).",
      "Each individual specification identified by its direct label (ggrepel), not a unique hue. Shape = significance (circle = n.s., diamond = p<0.05), not color.",
      "TREATMENT: rural density 5-7, 0 wind farms 2014 -> >=1 by 2020. CONTROL: rural density 5-7, never treated, department with > 3 treated municipalities, matched (wind+pop+income+investment+department FE).",
      "TWFE | municipality + year FE | municipality-clustered SE. Shared X axis across all variables -- readable since all are in comparable pp / % units.",
      sep = "\n")
  ) +
  theme_bw(base_size = 13) +
  theme(
    panel.grid.major.y = element_blank(),
    panel.grid.minor   = element_blank(),
    axis.text.y        = element_text(size = 13, face = "bold"),
    legend.position    = "right",
    plot.title         = element_text(size = 17, face = "bold"),
    plot.subtitle      = element_text(size = 11.5, color = "grey40"),
    plot.caption       = element_text(size = 8.5, color = "grey45", hjust = 0)
  )

ggsave(file.path(FIG, "rob_master_singlepanel.png"), p, width = 22, height = 24, dpi = 200, limitsize = FALSE)
cat(sprintf("Saved -> %s\n", file.path(FIG, "rob_master_singlepanel.png")))
