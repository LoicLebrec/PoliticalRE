# Nouveau groupe de controle, remplace control_group.csv (construction non
# tracee dans le repo) pour toutes les figures de robustesse. Criteres :
#
#   1. Rural, densite 5-7 (meme filtre que le groupe traite)
#   2. Jamais traite (n_parcs_cumul == 0 a toutes les annees observees)
#   3. Departement avec > 3 communes traitees (jamais un desert eolien --
#      dep nettoye : panel.csv porte "24" et "24.0" pour le meme
#      departement, 109 valeurs au lieu de 102, corrige ici)
#   4. Proximite socio-economique avec le groupe traite (Cohorte B, annee
#      de reference 2014) : probit(traite ~ vent + log(pop) + log(revenu)
#      + log(investissement) + dep), seuil = P10 des traites -- meme
#      logique que hp_control_codes dans run_morvan_competitif.R, mais ICI
#      un seul groupe de controle partage pour toutes les figures TWFE
#      (comme control_group.csv l'etait), pas un matching par cohorte.
#      Dette ECARTEE (desc. stats : pas de difference traite/controle
#      significative sur la dette, cf. discussion).
#
# Sortie : data/control_group_new.csv (code_insee)

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(tidyr); library(stringr); library(readxl)
})

PROJECT <- Sys.getenv("POLITICALRE_ROOT", unset = ".")
DATA    <- file.path(PROJECT, "code/shared_data")
OUT_DIR <- file.path(PROJECT, "code")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

col_sp    <- cols(code_insee = col_character(), dep = col_character(), .default = col_guess())
clean_dep <- function(x) str_remove(x, "\\.0$")
pad5      <- function(x) str_pad(str_extract(as.character(x), "[0-9A-Za-z]+"), 5, "left", "0")

panel_raw_full <- read_csv(file.path(PROJECT, "code/panel.csv"), col_types = col_sp) %>%
  mutate(dep = clean_dep(dep))
# Exclude fused communes (absorbed or absorbing another commune) -- breaks
# code_insee continuity / population discontinuity not organic. Filtered
# globally, all downstream constructions inherit it.
n_before_fusion <- n_distinct(panel_raw_full$code_insee)
panel_raw <- panel_raw_full %>% filter(commune_fixe == 1)
cat(sprintf("Communes fusionnees exclues : %d -> %d (commune_fixe==1)\n",
            n_before_fusion, n_distinct(panel_raw$code_insee)))

DENS_OK <- c("5", "6", "7")

# ── 1. Univers rural, jamais traite ────────────────────────────────────────
ever_treated_codes <- panel_raw %>%
  group_by(code_insee) %>%
  summarise(ever_treated = any(as.numeric(n_parcs_cumul) > 0, na.rm = TRUE), .groups = "drop") %>%
  filter(ever_treated) %>% pull(code_insee)

rural_2014 <- panel_raw %>% filter(annee == 2014L, categorie_dens %in% DENS_OK) %>%
  distinct(code_insee, .keep_all = TRUE)

# Cohorte B (traites, reference pour le matching socio-eco)
coh_b_codes <- panel_raw %>%
  filter(annee %in% c(2014L, 2020L)) %>%
  distinct(code_insee, annee, .keep_all = TRUE) %>%
  select(code_insee, annee, n_parcs_cumul, categorie_dens) %>%
  pivot_wider(names_from = annee, values_from = n_parcs_cumul, names_prefix = "np_") %>%
  filter(categorie_dens %in% DENS_OK, !is.na(np_2014), !is.na(np_2020),
         as.numeric(np_2014) == 0, as.numeric(np_2020) > 0) %>%
  pull(code_insee)

pool_never_treated <- rural_2014 %>%
  filter(!code_insee %in% ever_treated_codes) %>% pull(code_insee)
cat(sprintf("1. Rural dens 5-7, jamais traite : %d communes\n", length(pool_never_treated)))

# ── 2. Departement avec > 3 communes traitees ──────────────────────────────
treated_by_dep <- panel_raw %>% filter(annee == 2020L) %>% distinct(code_insee, .keep_all = TRUE) %>%
  mutate(ever_treated = as.numeric(n_parcs_cumul) > 0) %>%
  group_by(dep) %>% summarise(n_treated_comm = sum(ever_treated, na.rm = TRUE), .groups = "drop")

dep_ok <- treated_by_dep %>% filter(n_treated_comm > 3) %>% pull(dep)
cat(sprintf("2. Departements avec > 3 communes traitees : %d / %d\n",
            length(dep_ok), n_distinct(treated_by_dep$dep)))

pool_dep <- rural_2014 %>%
  filter(code_insee %in% pool_never_treated, dep %in% dep_ok) %>% pull(code_insee)
cat(sprintf("   Pool apres filtre departement : %d communes\n", length(pool_dep)))

# ── 3. Matching socio-economique (Cohorte B, reference 2014) ──────────────
filo14 <- read_excel(
  file.path(PROJECT, "election_data/data_quentin/2026/insee_raw/filosofi_series/filo2014/indic-struct-distrib-revenu-2014-COMMUNES/FILO_DISP_COM.xls"),
  sheet = "ENSEMBLE", skip = 5, col_types = "text") %>%
  rename(code_insee = CODGEO, rev_med = Q214) %>%
  mutate(code_insee = pad5(code_insee), rev_med = suppressWarnings(as.numeric(rev_med))) %>%
  select(code_insee, rev_med)

inv13 <- read_csv(file.path(DATA, "invest_communes_2013.csv"), col_types = col_sp) %>%
  rename(invest_2013 = invest_sd)

cross <- rural_2014 %>%
  filter(code_insee %in% c(coh_b_codes, pool_dep)) %>%
  mutate(ever_treated = as.integer(code_insee %in% coh_b_codes),
         log_inscrits  = log(as.numeric(inscrits))) %>%
  left_join(filo14, by = "code_insee") %>%
  left_join(inv13, by = "code_insee") %>%
  mutate(invest_pc = invest_2013 / pmax(as.numeric(inscrits), 1),
         log_rev    = log1p(rev_med),
         log_invest = log1p(invest_pc)) %>%
  filter(!is.na(wind_speed_100m), !is.na(dep), !is.na(log_inscrits),
         !is.na(log_rev), !is.na(log_invest))

s_hp  <- glm(ever_treated ~ wind_speed_100m + log_inscrits + log_rev + log_invest + factor(dep),
             data = cross, family = binomial("probit"))
p_hat  <- predict(s_hp, type = "response")
thresh <- quantile(p_hat[cross$ever_treated == 1], 0.10)

control_new <- cross$code_insee[cross$ever_treated == 0 & p_hat >= thresh]
cat(sprintf("3. Matching socio-eco (P10 traites) : %d communes retenues sur %d candidates\n",
            length(control_new), sum(cross$ever_treated == 0)))

write_csv(tibble(code_insee = control_new), file.path(OUT_DIR, "control_group_new.csv"))
cat(sprintf("\nSaved -> %s (%d communes)\n", file.path(OUT_DIR, "control_group_new.csv"), length(control_new)))
