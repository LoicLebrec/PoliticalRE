# Rebuilds the voix_gagnant_mean/min/max columns of external_wind_voteshare.csv
# -- confirmed by construction, not guessed: these are the NATIONAL
# mean/min/max of voix_gagnant (winner's vote count) for each election
# year, broadcast onto every commune row (every commune in a given year
# carries the same triple). Verified exactly against the existing file
# for all 4 election years before this script was written:
#   2008: mean=443.5511 min=8    max=57303  (33,431 communes)
#   2014: mean=435.9445 min=6    max=51653  (34,873 communes)
#   2020: mean=338.3646 min=0    max=31940  (34,727 communes)
#   2026: mean=380.8542 min=4    max=30425  (33,465 communes)
#
# wind_speed_100m (the file's other column) is NOT rebuilt here -- its
# source is still unconfirmed (see data_prep/README.md), so this script
# only replaces voix_gagnant_mean/min/max in the existing file, keeping
# wind_speed_100m as-is.
#
# Usage (from the repo root): Rscript code/shared_data/build_voix_gagnant_stats.R

suppressPackageStartupMessages({
  library(dplyr); library(readr)
})

PROJECT <- Sys.getenv("POLITICALRE_ROOT", unset = ".")
VARIABLEY <- file.path(PROJECT, "election_data/VariablesY/variableY.csv")
EXISTING  <- file.path(PROJECT, "code/external_wind_voteshare.csv")
OUT       <- file.path(PROJECT, "code/external_wind_voteshare.csv")

elec <- read_csv(VARIABLEY, col_types = cols(code_insee = col_character(), .default = col_guess()))

national_stats <- elec %>%
  group_by(annee) %>%
  summarise(voix_gagnant_mean = round(mean(voix_gagnant, na.rm = TRUE), 4),
            voix_gagnant_min  = min(voix_gagnant, na.rm = TRUE),
            voix_gagnant_max  = max(voix_gagnant, na.rm = TRUE),
            .groups = "drop")

existing <- read_csv(EXISTING, col_types = cols(code_insee = col_character(), .default = col_guess()))

rebuilt <- existing %>%
  select(code_insee, annee, wind_speed_100m) %>%
  left_join(national_stats, by = "annee")

write_csv(rebuilt, OUT)
cat(sprintf("Rewrote voix_gagnant_mean/min/max for %d rows -> %s\n", nrow(rebuilt), OUT))
cat("National stats by year:\n")
print(national_stats)
