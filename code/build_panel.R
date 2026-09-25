# Build panel.csv -- commune x election municipale, base pour les regressions.
#
# === SOURCES ===
#   variableY.csv                       -- panel commune x election (Y de base)
#   maires_election_final_rescraped.csv -- Blancs&Nuls / Inscrits 2008-2020
#   maires_election_2026.csv            -- Blancs&Nuls / Inscrits 2026
#   Parc.csv                            -- parcs eoliens (date, puissance)
#
# === AJOUTS PAR RAPPORT A variableY.csv ===
#   pct_voix_gagnant          -- (voix_gagnant / inscrits) * 100 -- score du
#                                 gagnant en pp d'inscrits (utile pour voir si
#                                 le maire sortant reconduit perd des voix
#                                 quand une eolienne s'installe)
#   pct_voix_sortant_inscrits -- (voix_sortant_candidature / inscrits) * 100 --
#                                 idem pour le score du maire sortant (NA si
#                                 le sortant n'etait pas candidat)
#   pct_blancs_nuls    -- (Blancs&Nuls / Inscrits) * 100
#
#   Variables eoliennes cumulees ("stock a la date de l'election") :
#   date de reference du parc = date_mise_en_service (mise en service reelle,
#   pas la date de depot/autorisation -- un parc autorise mais jamais
#   construit ne doit pas compter comme "installe"). Si cette date tombe
#   l'annee meme d'une election, le parc est compte comme deja existant
#   pour cette election (associe au mandat precedent) -> cumul avec
#   date_ref <= annee. Parcs sans date de mise en service (~35% de
#   Parc.csv -- encore en instruction/construction/jamais realises) sont
#   exclus du cumul (corrige un bug ou date_debut_construction ou, a
#   defaut, date_delivrance_autorisation etait utilisee comme proxy :
#   ~18% des communes traitees l'etaient en realite sur un parc encore
#   non construit).
#
#   n_parcs_cumul     -- nb de parcs distincts (id_parc) avec date_ref <= annee
#   mw_cumul          -- somme puissance_parc_mw des parcs avec date_ref <= annee
#                         (NB: parc multi-communes -> puissance pleine comptee
#                         dans chaque commune concernee, pas de repartition)
#   mw_added_period   -- mw_cumul(annee) - mw_cumul(annee_precedente) :
#                         puissance installee durant la periode (mandat
#                         precedent) ; pour 2008 = mw_cumul(2008)
#   n_aero_cumul      -- somme nombre_aerogenerateur des parcs avec date_ref <= annee
#   year_premier_parc -- annee (date_ref) du premier parc de la commune
#   eolien_treated    -- 1 si n_parcs_cumul > 0, sinon 0 (variable temporelle,
#                         a distinguer de "eolien" qui est statique)

# %% Setup -------------------------------------------------------------------
library(dplyr)
library(readr)
library(stringr)

PROJECT <- Sys.getenv("POLITICALRE_ROOT", unset = ".")
BASE_Q  <- file.path(PROJECT, "election_data/data_quentin")
OUT     <- file.path(PROJECT, "code/panel.csv")

ELECTION_YEARS <- c(2008, 2014, 2020, 2026)

pad5 <- function(x) {
  x <- trimws(as.character(x))
  ifelse(
    grepl("[A-Za-z]", x),
    toupper(str_pad(x, width = 5, side = "left", pad = "0")),
    str_pad(as.character(as.integer(suppressWarnings(as.numeric(x)))), width = 5, side = "left", pad = "0")
  )
}

# %% 1. Base panel = variableY.csv -------------------------------------------
cat("Loading variableY.csv...\n")
panel <- read_csv(
  file.path(PROJECT, "election_data/VariablesY/variableY.csv"),
  col_types = cols(code_insee = col_character(), .default = col_guess())
) %>%
  select(-any_of(c("nb_listes_equiv", "nb_sieges_requis",
                    "nb_listes_corr", "nb_candidats_corr"))) %>%
  mutate(pct_voix_gagnant = round(voix_gagnant / inscrits * 100, 4),
         pct_voix_sortant_inscrits = round(voix_sortant_candidature / inscrits * 100, 4),
         deuxieme_tour = as.integer(nb_tours == 2))
cat(sprintf("  %d rows, %d communes\n", nrow(panel), n_distinct(panel$code_insee)))


# %% 2. Vote blanc et nul ------------------------------------------------------
cat("Computing pct_blancs_nuls...\n")
hist <- read_csv(
  file.path(BASE_Q, "maires_election_250125.csv/maires_election_final_rescraped.csv"),
  col_types = cols_only(code_insee = col_character(), Annee = col_integer(),
                         Inscrits_x = col_double(), `Blancs&Nuls` = col_double())
) %>% rename(Inscrits = Inscrits_x)

y26 <- read_csv(
  file.path(BASE_Q, "2026/elecmaj2026/maires_election_2026.csv"),
  col_types = cols_only(code_insee = col_character(), Annee = col_integer(),
                         Inscrits = col_double(), `Blancs&Nuls` = col_double())
)

bn <- bind_rows(hist, y26) %>%
  mutate(
    code_insee = pad5(code_insee),
    pct_blancs_nuls = round(`Blancs&Nuls` / Inscrits * 100, 4)
  ) %>%
  rename(annee = Annee) %>%
  select(code_insee, annee, pct_blancs_nuls) %>%
  distinct()

panel <- panel %>% left_join(bn, by = c("code_insee", "annee"))
cat(sprintf("  pct_blancs_nuls coverage: %d/%d rows\n",
            sum(!is.na(panel$pct_blancs_nuls)), nrow(panel)))


# %% 3. Variables eoliennes cumulees depuis Parc.csv ---------------------------
cat("Computing wind park cumulative variables from Parc.csv...\n")
parc <- read_csv(
  file.path(PROJECT, "data/parceolien/Parc.csv"),
  col_types = cols_only(id_parc = col_character(), code_insee = col_character(),
                         puissance_parc_mw = col_double(),
                         nombre_aerogenerateur = col_double(),
                         date_mise_en_service = col_character())
) %>%
  mutate(
    code_insee = pad5(code_insee),
    ref_date = date_mise_en_service,
    ref_year = as.integer(format(as.Date(substr(ref_date, 1, 10)), "%Y"))
  )

n_excluded <- sum(is.na(parc$ref_year))
cat(sprintf("  Parks excluded (not yet commissioned / no date_mise_en_service): %d/%d\n",
            n_excluded, nrow(parc)))
parc <- parc %>% filter(!is.na(ref_year))

# Multi-commune parks: Parc.csv gives one row per (id_parc, hosting commune)
# with the FULL project puissance_parc_mw / nombre_aerogenerateur repeated
# identically on every row (no per-commune breakdown available -- confirmed
# zero within-parc variance across ~1,031/2,556 multi-commune parks, up to
# 8 communes for one project). Summing as-is overcounts installed capacity
# by up to 8x for any commune sharing a project, and inflates the median
# used by the "[Installation power]" Small/Large heterogeneity split
# downstream. Split MW/turbines evenly across a park's hosting communes --
# an approximation (true per-commune siting isn't in the source data), but
# unbiased in aggregate (sum across communes still equals the true project
# total) unlike full duplication.
n_communes_per_parc <- parc %>% distinct(id_parc, code_insee) %>%
  count(id_parc, name = "n_communes")
parc <- parc %>%
  left_join(n_communes_per_parc, by = "id_parc") %>%
  mutate(puissance_parc_mw = puissance_parc_mw / n_communes,
         nombre_aerogenerateur = nombre_aerogenerateur / n_communes)
cat(sprintf("  Multi-commune parks (MW/turbines split evenly across hosting communes): %d/%d\n",
            sum(n_communes_per_parc$n_communes > 1), nrow(n_communes_per_parc)))

# year_premier_parc per commune
year_premier <- parc %>%
  group_by(code_insee) %>%
  summarise(year_premier_parc = min(ref_year), .groups = "drop")

# Cumulative n_parcs / mw / n_aero per commune, for each election year
wind <- bind_rows(lapply(ELECTION_YEARS, function(annee) {
  parc %>%
    filter(ref_year <= annee) %>%
    group_by(code_insee) %>%
    summarise(
      n_parcs_cumul = n_distinct(id_parc),
      mw_cumul = sum(puissance_parc_mw, na.rm = TRUE),
      n_aero_cumul = sum(nombre_aerogenerateur, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    mutate(annee = annee)
}))

# Full grid (commune x annee) so mw_added_period = diff(mw_cumul) is correct
# even for the first election year a commune ever shows up with a park.
wind_full <- expand.grid(
  code_insee = unique(wind$code_insee),
  annee = ELECTION_YEARS,
  stringsAsFactors = FALSE
) %>%
  left_join(wind, by = c("code_insee", "annee")) %>%
  mutate(
    n_parcs_cumul = coalesce(n_parcs_cumul, 0L),
    mw_cumul = coalesce(mw_cumul, 0),
    n_aero_cumul = coalesce(n_aero_cumul, 0)
  ) %>%
  arrange(code_insee, annee) %>%
  group_by(code_insee) %>%
  mutate(mw_added_period = mw_cumul - lag(mw_cumul, default = 0)) %>%
  ungroup()

panel <- panel %>%
  left_join(wind_full, by = c("code_insee", "annee")) %>%
  left_join(year_premier, by = "code_insee") %>%
  mutate(
    n_parcs_cumul = coalesce(n_parcs_cumul, 0L),
    mw_cumul = coalesce(mw_cumul, 0),
    n_aero_cumul = coalesce(n_aero_cumul, 0),
    mw_added_period = coalesce(mw_added_period, 0),
    eolien_treated = as.integer(n_parcs_cumul > 0)
  )

cat(sprintf("  Communes ever treated: %d\n",
            n_distinct(panel$code_insee[panel$eolien_treated == 1])))


# %% 3b. External columns (wind_speed_100m, voix_gagnant_mean/min/max) -------
# These 4 columns come from a source outside this repo (no internal script
# computes them -- confirmed, see code/replication/
# README.md caveat 1). Used downstream by build_control_group.R, run_morvan*.R,
# and build_balance_table.R. Without this merge, panel.csv silently loses
# them every time build_panel.R is rerun (variableY.csv doesn't have them),
# which broke the pipeline once already -- merging a frozen snapshot back in
# here so `run_pipeline.R` doesn't depend on a manual recovery step.
# TODO: replace external_wind_voteshare.csv with the actual fetch script (or
# at minimum the source URL) if/when that's known.
external <- read_csv(
  file.path(PROJECT, "code/external_wind_voteshare.csv"),
  col_types = cols(code_insee = col_character(), .default = col_guess())
)
panel <- panel %>% left_join(external, by = c("code_insee", "annee"))
cat(sprintf("  External columns merged (wind_speed_100m, voix_gagnant_mean/min/max): %.1f%% coverage\n",
            100 * mean(!is.na(panel$wind_speed_100m))))


# %% 3c. Impossible vote-share values -> NA -----------------------------------
# pct_voix_gagnant_exprimes and pct_voix_sortant_exprimes are shares of valid
# votes cast; a value above 100% is not a modeling edge case, it is
# arithmetically impossible (a candidate cannot receive more votes than there
# are valid ballots) and can only reflect an error upstream, in variableY.csv
# itself (this repo does not compute these two columns -- see header). We do
# not know the true value for the affected rows, so we set it to NA rather
# than guess or silently keep an impossible number in every downstream table
# and regression. Confirmed narrow in scope: 22 rows / 21 communes out of
# 137,867 (0.016%), spread across 2014/2020/2026 and both ballot types, not
# concentrated in any one source file or year.
n_bad_gagnant <- sum(panel$pct_voix_gagnant_exprimes > 100, na.rm = TRUE)
n_bad_sortant <- sum(panel$pct_voix_sortant_exprimes > 100, na.rm = TRUE)
panel <- panel %>%
  mutate(
    pct_voix_gagnant_exprimes = if_else(pct_voix_gagnant_exprimes > 100, NA_real_, pct_voix_gagnant_exprimes),
    pct_voix_sortant_exprimes = if_else(pct_voix_sortant_exprimes > 100, NA_real_, pct_voix_sortant_exprimes)
  )
cat(sprintf("  Impossible vote shares (>100%%) set to NA: %d pct_voix_gagnant_exprimes, %d pct_voix_sortant_exprimes\n",
            n_bad_gagnant, n_bad_sortant))


# %% 4. Save -------------------------------------------------------------------
write_csv(panel, OUT)
cat(sprintf("\nSaved -> %s\n", OUT))
cat(sprintf("Shape: %d x %d\n", nrow(panel), ncol(panel)))
cat("New columns: pct_voix_gagnant, pct_blancs_nuls, n_parcs_cumul, mw_cumul, mw_added_period, n_aero_cumul, year_premier_parc, eolien_treated\n")
