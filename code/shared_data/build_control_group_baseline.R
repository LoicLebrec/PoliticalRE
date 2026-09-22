# Builds control_group_baseline.csv (the unmatched "baseline" control
# pool): rural communes (INSEE density 5-7), never treated, present in
# the panel at all 4 election years.
#
# This replaces a frozen legacy file whose original construction script
# does not survive anywhere in the project's history (confirmed by an
# exhaustive search, including every archived script generation and the
# author's own note on the script that once replaced it for the matched
# pool: "construction non tracee dans le repo"). This rule recovers
# 21,740 of the legacy file's 21,744 communes (99.98%) and additionally
# selects 5,827 communes the legacy file did not include -- one further
# filter was applied at some point that could not be identified.
#
# Before adopting this as the canonical file, the impact on published
# results was checked directly: rerunning the baseline-pool TWFE and CS
# estimates (tab:baseline_results) with this pool instead of the legacy
# file changes every coefficient by at most 0.12 percentage points
# (abstention; all other outcomes changed by <=0.05pp), with identical
# N-treated, no sign changes, and no changes in statistical significance.
# The legacy file is preserved at
# code/shared_data/control_group_baseline_legacy.csv for the record.
#
# Usage (from the repo root): Rscript code/shared_data/build_control_group_baseline.R

suppressPackageStartupMessages({
  library(dplyr); library(readr)
})

PROJECT <- Sys.getenv("POLITICALRE_ROOT", unset = ".")
PANEL   <- file.path(PROJECT, "code/panel.csv")
OUT     <- file.path(PROJECT, "code/shared_data/control_group_baseline.csv")

panel <- read_csv(PANEL, col_types = cols(code_insee = col_character(), .default = col_guess()))

never_treated <- panel %>%
  group_by(code_insee) %>%
  summarise(never_treated = all(n_parcs_cumul == 0), n_years = n(), .groups = "drop") %>%
  filter(never_treated, n_years == 4) %>%
  pull(code_insee)

rural_2014 <- panel %>%
  filter(annee == 2014, categorie_dens %in% c("5", "6", "7")) %>%
  pull(code_insee)

control_pool <- tibble(code_insee = intersect(never_treated, rural_2014)) %>% arrange(code_insee)

write_csv(control_pool, OUT)
cat(sprintf("Wrote %d communes -> %s\n", nrow(control_pool), OUT))

legacy_path <- file.path(PROJECT, "code/shared_data/control_group_baseline_legacy.csv")
if (file.exists(legacy_path)) {
  legacy <- read_csv(legacy_path, col_types = cols(code_insee = col_character())) %>% pull(code_insee) %>% unique()
  matched <- intersect(control_pool$code_insee, legacy)
  cat(sprintf("Match vs. legacy file: %d/%d legacy communes recovered (%.2f%%)\n",
              length(matched), length(legacy), 100 * length(matched) / length(legacy)))
  cat(sprintf("Extra communes vs. legacy file: %d\n",
              length(setdiff(control_pool$code_insee, legacy))))
}
