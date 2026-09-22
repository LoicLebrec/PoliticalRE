# Enrich panel.csv with mayor characteristics
#
# Source: data/maires_panel.csv (built by code/build_maires_panel.py)
#   nom_maire, prenom_maire, sexe_maire, annee_naissance_maire,
#   age_maire_election, csp_maire, source_rne,
#   remplace_mandat_2014 (proxy: new mayor installed 2015-2019, not via election)
#
# Join key: code_insee + annee
# Output: code/panel_maires.csv

library(dplyr)
library(readr)

PROJECT <- Sys.getenv("POLITICALRE_ROOT", unset = ".")
PANEL   <- file.path(PROJECT, "code/panel.csv")
MAIRES  <- file.path(PROJECT, "data/maires_panel.csv")
OUT     <- file.path(PROJECT, "code/panel_maires.csv")

col_sp <- cols(code_insee = col_character(), dep = col_character(), .default = col_guess())

panel  <- read_csv(PANEL,  col_types = col_sp)
maires <- read_csv(MAIRES, col_types = cols(code_insee = col_character(), .default = col_guess())) %>%
  rename(
    nom_maire          = nom,
    prenom_maire       = prenom,
    sexe_maire         = sexe,
    annee_naissance_maire = annee_naissance,
    age_maire_election = age_election,
    csp_maire          = csp_code,
    source_rne         = source,
    nom_entrant_wiki   = entrant,
    nom_sortant_wiki   = sortant
  ) %>%
  mutate(annee = as.integer(annee))

cat(sprintf("Panel : %d rows\n", nrow(panel)))
cat(sprintf("Maires : %d rows  (%d communes × years)\n",
            nrow(maires), n_distinct(paste(maires$code_insee, maires$annee))))

panel_enr <- panel %>%
  left_join(
    maires %>% select(code_insee, annee, nom_maire, prenom_maire, sexe_maire,
                      annee_naissance_maire, age_maire_election, csp_maire,
                      source_rne, nom_entrant_wiki, nom_sortant_wiki,
                      remplace_mandat_2014),
    by = c("code_insee", "annee")
  )

# Coverage summary
cat(sprintf("\n=== Enrichment coverage ===\n"))
cat(sprintf("nom_maire           : %d/%d (%.1f%%)\n",
  sum(!is.na(panel_enr$nom_maire)), nrow(panel_enr),
  100*mean(!is.na(panel_enr$nom_maire))))
cat(sprintf("age_maire_election  : %d/%d (%.1f%%)\n",
  sum(!is.na(panel_enr$age_maire_election)), nrow(panel_enr),
  100*mean(!is.na(panel_enr$age_maire_election))))
cat(sprintf("sexe_maire (F)      : %d communes\n",
  sum(panel_enr$sexe_maire == "F", na.rm=TRUE)))

print(panel_enr %>%
  group_by(annee) %>%
  summarise(
    n               = n(),
    pct_nom         = round(100*mean(!is.na(nom_maire)), 1),
    pct_age         = round(100*mean(!is.na(age_maire_election)), 1),
    age_moy         = round(mean(age_maire_election, na.rm=TRUE), 1),
    pct_femme       = round(100*mean(sexe_maire=="F", na.rm=TRUE), 1),
    .groups = "drop"
  ))

write_csv(panel_enr, OUT)
cat(sprintf("\nSaved → %s  (%d cols)\n", OUT, ncol(panel_enr)))
cat(sprintf("New columns: %s\n",
  paste(setdiff(names(panel_enr), names(panel)), collapse=", ")))
