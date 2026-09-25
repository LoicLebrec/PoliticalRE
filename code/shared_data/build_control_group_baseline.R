# Builds control_group_baseline.csv (the unmatched "baseline" control
# pool): rural communes (INSEE density 5-7), never treated, present in
# the panel at all 4 election years, in a department with at least 3
# wind parks recorded in Parc.csv (any status, not just operational --
# adding an operational-only filter was tested and made the match worse).
#
# This replaces a frozen legacy file whose original construction script
# does not survive anywhere in the project's history (confirmed by an
# exhaustive search, including every archived script generation and the
# author's own note on the script that once replaced it for the matched
# pool: "construction non tracee dans le repo"). The department-parks
# filter was recalled by the author after the first version of this
# script (rural + never-treated only, no department filter) was checked
# against the legacy file: that version matched 99.98% of the legacy
# file's communes but over-selected by 5,827; adding this filter keeps
# the same 99.98% match while cutting the over-selection to 934 (four
# legacy communes remain unmatched, in departments with 18-49 parks,
# two of which (27486, 54590) are treated in the current panel -- the
# legacy file was built against an older Parc.csv vintage).
#
# See data_prep/README.md for the impact of this pool on published
# results, checked directly by rerunning the full pipeline.
#
# Usage (from the repo root): Rscript code/shared_data/build_control_group_baseline.R

suppressPackageStartupMessages({
  library(dplyr); library(readr)
})

PROJECT <- Sys.getenv("POLITICALRE_ROOT", unset = ".")
PANEL   <- file.path(PROJECT, "code/panel.csv")
PARC    <- file.path(PROJECT, "data/parceolien/Parc.csv")
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

parc <- read_csv(PARC, col_types = cols(code_dept = col_character(), .default = col_guess()))
dep_ok <- parc %>%
  count(code_dept, name = "n_parcs") %>%
  filter(n_parcs >= 3) %>%
  pull(code_dept)

dep_2014 <- panel %>% filter(annee == 2014) %>% distinct(code_insee, dep)

control_pool <- tibble(code_insee = intersect(never_treated, rural_2014)) %>%
  left_join(dep_2014, by = "code_insee") %>%
  filter(dep %in% dep_ok) %>%
  select(code_insee) %>%
  arrange(code_insee)

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
