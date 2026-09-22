# Best-known reconstruction of control_group_baseline.csv (the unmatched
# "baseline" control pool). No writer script survives for the original
# file; this implements the confirmed general method -- rural, never-
# treated, filtered from the project's own panel -- and gets to 99.98% of
# the original file's 21,744 communes (21,740 match) when checked against
# it. The remaining ~6,000 communes this rule additionally lets through
# aren't in the original file, so there's one more filter nobody has
# pinned down -- this script is the best current approximation, not a
# byte-for-byte rebuild. See reproducibility/README.md caveat 2 for the
# match-rate check.
#
# Rule: rural (INSEE density 5-7) in 2014, never treated (n_parcs_cumul==0
# at every observed year), present in the panel at all 4 election years.
#
# Usage (from the repo root): Rscript code/shared_data/build_control_group_baseline.R

suppressPackageStartupMessages({
  library(dplyr); library(readr)
})

PROJECT <- Sys.getenv("POLITICALRE_ROOT", unset = ".")
PANEL   <- file.path(PROJECT, "code/panel.csv")
OUT     <- file.path(PROJECT, "code/shared_data/control_group_baseline_rebuilt.csv")

panel <- read_csv(PANEL, col_types = cols(code_insee = col_character(), .default = col_guess()))

never_treated <- panel %>%
  group_by(code_insee) %>%
  summarise(never_treated = all(n_parcs_cumul == 0), n_years = n(), .groups = "drop") %>%
  filter(never_treated, n_years == 4) %>%
  pull(code_insee)

rural_2014 <- panel %>%
  filter(annee == 2014, categorie_dens %in% c("5", "6", "7")) %>%
  pull(code_insee)

rebuilt <- tibble(code_insee = intersect(never_treated, rural_2014)) %>% arrange(code_insee)

write_csv(rebuilt, OUT)
cat(sprintf("Rebuilt %d communes -> %s\n", nrow(rebuilt), OUT))

original_path <- file.path(PROJECT, "code/shared_data/control_group_baseline.csv")
if (file.exists(original_path)) {
  original <- read_csv(original_path, col_types = cols(code_insee = col_character())) %>% pull(code_insee) %>% unique()
  matched <- intersect(rebuilt$code_insee, original)
  cat(sprintf("Match vs. original: %d/%d original communes recovered (%.2f%%)\n",
              length(matched), length(original), 100 * length(matched) / length(original)))
  cat(sprintf("Extra communes this rule lets through, not in the original: %d\n",
              length(setdiff(rebuilt$code_insee, original))))
}
