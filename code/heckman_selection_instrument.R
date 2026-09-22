# Extension de run_morvan.R : interaction traitement x competitivite
# electorale, 3 cohortes, Stage 1 (candidature) + Stage 2 (reelection).
#
# competitif construit a partir de closeness.csv (build_closeness.py) :
#   - regime liste      : marge liste1-liste2 / exprimes (Eggers 2015 ;
#                          Tricaud & Wacziarg 2025), memes 3 annees
#   - regime individuel  : 2014/2020 = marge au seuil du dernier siege
#                          (analogue Folke 2014, JEEA) ; 2008 SEUL = repli
#                          sur 100 - part du vainqueur des exprimes (source
#                          tronquee aux elus cette annee -- documente,
#                          verifie empiriquement). PAS de marge top1-top2,
#                          invalide en multi-membre (Tricaud & Wacziarg
#                          2025). Methode unique testee et abandonnee : elle
#                          dilue le mono_liste reel de 2014/2020 et efface
#                          l'effet significatif de la cohorte B.
#   - mono_liste (aucun adversaire / seuil non dispute) : indicateur SEPARE,
#     closeness=NA, pas force a 100 (David, Jayet & Revelli 2019)
#
# closeness mesuree a t-6 (election precedente, avant le parc) : evite le
# biais post-traitement. Seuil = mediane par regime, calculee sur les
# communes traitees (futures) uniquement (echelles non comparables entre
# regimes -- Eggers 2015).
#
# Interaction non-lineaire (probit) : lecture directe du coefficient
# d'interaction invalide (Ai & Norton 2003, Econ. Letters). Le modele de
# base est un Heckman 2-step (pas un probit simple) : la correction Ai-Norton
# ne s'applique pas telle quelle -- on suit Frondel & Vance ("On Interaction
# Effects: The Case of Heckit and Two-Part Models") et on calcule le
# contraste d'AME par delta method via marginaleffects::avg_slopes(...,
# hypothesis = ~pairwise, by = competitif).
suppressPackageStartupMessages({
  library(dplyr); library(readr); library(tidyr); library(stringr)
  library(readxl); library(ggplot2); library(marginaleffects)
})

PROJECT <- Sys.getenv("POLITICALRE_ROOT", unset = ".")
DATA    <- file.path(PROJECT, "code/shared_data")
ELEC    <- file.path(PROJECT, "election_data/data_quentin")
MORVAN  <- file.path(PROJECT, "code")
FIG     <- file.path(MORVAN, "figures")
dir.create(FIG, showWarnings = FALSE, recursive = TRUE)

col_sp <- cols(code_insee = col_character(), dep = col_character(), .default = col_guess())
pad5   <- function(x) str_pad(str_extract(as.character(x), "[0-9A-Za-z]+"), 5, "left", "0")
stars  <- function(p) case_when(p < .01 ~ "***", p < .05 ~ "**", p < .10 ~ "*", TRUE ~ "")

# ─── Raw data (identique a run_morvan.R) ───────────────────────────────────
# dep porte deux formats pour le meme departement ("24" et "24.0") dans
# panel.csv/panel_maires.csv -> 109 valeurs distinctes au lieu de 102,
# corrompt tout regroupement departemental (FE, matching controle). Corrige
# a la lecture.
clean_dep <- function(x) str_remove(x, "\\.0$")
pm_full        <- read_csv(file.path(PROJECT, "code/panel_maires.csv"), col_types = col_sp) %>%
  mutate(dep = clean_dep(dep))
panel_raw_full <- read_csv(file.path(PROJECT, "code/panel.csv"), col_types = col_sp) %>%
  mutate(dep = clean_dep(dep))
# Exclude fused communes (absorbed or absorbing another commune) -- breaks
# code_insee continuity / population discontinuity not organic.
pm         <- pm_full %>% filter(commune_fixe == 1)
panel_raw  <- panel_raw_full %>% filter(commune_fixe == 1)
cat(sprintf("Communes fusionnees exclues (pm) : %d -> %d\n",
            n_distinct(pm_full$code_insee), n_distinct(pm$code_insee)))
cat(sprintf("Communes fusionnees exclues (panel_raw) : %d -> %d\n",
            n_distinct(panel_raw_full$code_insee), n_distinct(panel_raw$code_insee)))
ctrl_codes <- read_csv(file.path(DATA, "control_group.csv"), col_types = col_sp) %>%
  pull(code_insee) %>% unique()

closeness <- read_csv(file.path(MORVAN, "shared_data/closeness.csv"),
                      col_types = cols(code_insee = col_character(), .default = col_guess()))

rne26 <- read_csv(file.path(ELEC, "2026/processed/maires_rne_2026.csv"),
                  col_types = cols(code_insee = col_character(), .default = col_guess())) %>%
  mutate(maire_dob   = as.Date(maire_dob),
         age_rne26   = 2026L - as.integer(format(maire_dob, "%Y")),
         homme_rne26 = as.integer(maire_sexe == "M")) %>%
  select(code_insee, age_rne26, homme_rne26)

filo14 <- read_excel(
  file.path(ELEC, "2026/insee_raw/filosofi_series/filo2014/indic-struct-distrib-revenu-2014-COMMUNES/FILO_DISP_COM.xls"),
  sheet = "ENSEMBLE", skip = 5, col_types = "text") %>%
  rename(code_insee = CODGEO, rev_med = Q214) %>%
  mutate(code_insee = pad5(code_insee), rev_med = suppressWarnings(as.numeric(rev_med))) %>%
  select(code_insee, rev_med)

filo17 <- read_delim(
  file.path(ELEC, "2026/insee_raw/filosofi_series/filo2017/cc_filosofi_2017_COM.CSV"),
  delim = ";", col_types = cols(CODGEO = col_character(), .default = col_double()),
  locale = locale(decimal_mark = ",")) %>%
  rename(code_insee = CODGEO, rev_med = MED17) %>%
  mutate(code_insee = pad5(code_insee)) %>%
  select(code_insee, rev_med)

filo21 <- read_delim(
  file.path(ELEC, "2026/insee_raw/filosofi2021/FILO2021_DISP_COM.csv"),
  delim = ";", col_types = cols(CODGEO = col_character(), .default = col_character()),
  locale = locale(decimal_mark = ",")) %>%
  rename(code_insee = CODGEO) %>%
  mutate(code_insee = pad5(code_insee),
         rev_med    = suppressWarnings(as.numeric(str_replace(Q221, ",", ".")))) %>%
  select(code_insee, rev_med)

epci_raw <- read_delim(file.path(DATA, "epci_communes_banatic.csv"), delim = ";",
  col_types = cols(insee = col_character(), .default = col_guess()),
  locale = locale(encoding = "latin1")) %>%
  mutate(code_insee = pad5(insee),
         epci_type  = case_when(
           nature_juridique %in% c("METRO", "CU", "MET69") ~ 2L,
           nature_juridique %in% c("CC", "CA", "SAN")       ~ 1L,
           TRUE ~ 0L)) %>%
  group_by(code_insee) %>% summarise(epci_type = max(epci_type), .groups = "drop")

dette_raw <- read_csv(
  file.path(DATA, "dette_communes.csv"),
  col_types = cols(code_insee = col_character(), .default = col_guess())) %>%
  pivot_wider(names_from = year, values_from = dette, names_prefix = "dette_") %>%
  select(code_insee, any_of(c("dette_2013", "dette_2019")))
inv13 <- read_csv(file.path(DATA, "invest_communes_2013.csv"),
  col_types = cols(code_insee = col_character(), .default = col_guess())) %>%
  rename(invest_2013 = invest_sd)
inv19 <- read_csv(file.path(DATA, "invest_communes_2019.csv"),
  col_types = cols(code_insee = col_character(), .default = col_guess())) %>%
  rename(invest_2019 = invest_sd)

# ─── Cohortes + controle haute potentialite (identique a run_morvan.R) ────
cohorte_codes <- function(yr_lo, yr_hi) {
  panel_raw %>%
    filter(annee %in% c(yr_lo, yr_hi), categorie_dens %in% c("5", "6", "7")) %>%
    distinct(code_insee, annee, .keep_all = TRUE) %>%
    select(code_insee, annee, n_parcs_cumul) %>%
    pivot_wider(names_from = annee, values_from = n_parcs_cumul, names_prefix = "np_") %>%
    filter(!is.na(.[[paste0("np_", yr_lo)]]), !is.na(.[[paste0("np_", yr_hi)]]),
           as.numeric(.[[paste0("np_", yr_lo)]]) == 0, as.numeric(.[[paste0("np_", yr_hi)]]) > 0) %>%
    pull(code_insee)
}
coh_a <- cohorte_codes(2008L, 2014L)
coh_b <- cohorte_codes(2014L, 2020L)
coh_c <- cohorte_codes(2020L, 2026L)
cat(sprintf("Cohortes brutes (panel.csv, rural dens 5-7, transition) : A=%d  B=%d  C=%d\n",
            length(coh_a), length(coh_b), length(coh_c)))

# Controle "haute potentialite" : probit(traite ~ vent + pop + dep), et
# quand une proxy de revenu/investissement existe pour l'annee de matching
# (2014 pour B, 2020->filo17/inv19 pour C), on l'ajoute -- desc. stats
# (cf. discussion) montrent que traites vs controle brut different sur le
# revenu et l'investissement (pas sur la dette, abandonnee). Pour A (annee
# de matching 2008), aucune proxy revenu/investissement n'existe dans le
# repo avant 2013-2014 -> matching vent+pop+dep seul, comme avant.
hp_control_codes <- function(coh_codes, ctrl_pool, yr, fin_dat = NULL) {
  cross <- panel_raw %>%
    filter(annee == yr, code_insee %in% c(coh_codes, ctrl_pool),
           categorie_dens %in% c("5", "6", "7")) %>%
    distinct(code_insee, .keep_all = TRUE) %>%
    mutate(ever_treated = as.integer(code_insee %in% coh_codes),
           log_inscrits = log(as.numeric(inscrits)))

  if (!is.null(fin_dat)) {
    cross <- cross %>% left_join(fin_dat, by = "code_insee") %>%
      mutate(log_rev_m = log1p(rev_med), log_inv_m = log1p(invest_pc_m))
    cross <- cross %>%
      filter(!is.na(wind_speed_100m), !is.na(dep), !is.na(log_inscrits),
             !is.na(log_rev_m), !is.na(log_inv_m))
    s_hp <- glm(ever_treated ~ wind_speed_100m + log_inscrits + log_rev_m + log_inv_m + factor(dep),
                data = cross, family = binomial("probit"))
  } else {
    cross <- cross %>% filter(!is.na(wind_speed_100m), !is.na(dep), !is.na(log_inscrits))
    s_hp <- glm(ever_treated ~ wind_speed_100m + log_inscrits + factor(dep),
                data = cross, family = binomial("probit"))
  }
  p_hat  <- predict(s_hp, type = "response")
  thresh <- quantile(p_hat[cross$ever_treated == 1], 0.10)
  cross$code_insee[cross$ever_treated == 0 & p_hat >= thresh]
}

fin_b <- filo14 %>% left_join(inv13, by = "code_insee") %>%
  left_join(panel_raw %>% filter(annee == 2014L) %>% distinct(code_insee, .keep_all = TRUE) %>%
              select(code_insee, inscrits) %>% mutate(inscrits = as.numeric(inscrits)),
            by = "code_insee") %>%
  mutate(invest_pc_m = invest_2013 / pmax(inscrits, 1)) %>%
  select(code_insee, rev_med, invest_pc_m)

fin_c <- filo17 %>% left_join(inv19, by = "code_insee") %>%
  left_join(panel_raw %>% filter(annee == 2020L) %>% distinct(code_insee, .keep_all = TRUE) %>%
              select(code_insee, inscrits) %>% mutate(inscrits = as.numeric(inscrits)),
            by = "code_insee") %>%
  mutate(invest_pc_m = invest_2019 / pmax(inscrits, 1)) %>%
  select(code_insee, rev_med, invest_pc_m)

ctrl_a <- hp_control_codes(coh_a, ctrl_codes, 2008L)
ctrl_b <- hp_control_codes(coh_b, ctrl_codes, 2014L, fin_dat = fin_b)
ctrl_c <- hp_control_codes(coh_c, ctrl_codes, 2020L, fin_dat = fin_c)

# ─── Competitif : mediane par regime, sur les traites, closeness a t-6 ────
# t-6 : cohorte A (elec.2014) -> closeness 2008 ; B (elec.2020) -> 2014 ;
#       C (elec.2026) -> 2020.
build_competitif <- function(coh_codes, ctrl_hp_codes, ref_yr) {
  cl <- closeness %>% filter(annee == ref_yr) %>%
    select(code_insee, type_scrutin, mono_liste, closeness)

  med_by_regime <- cl %>%
    filter(code_insee %in% coh_codes, mono_liste == 0, !is.na(closeness)) %>%
    group_by(type_scrutin) %>%
    summarise(mediane = median(closeness), .groups = "drop")

  all_codes <- unique(c(coh_codes, ctrl_hp_codes))
  cl %>%
    filter(code_insee %in% all_codes) %>%
    left_join(med_by_regime, by = "type_scrutin") %>%
    mutate(
      competitif = case_when(
        mono_liste == 1                        ~ 0L,
        is.na(closeness) | is.na(mediane)       ~ NA_integer_,
        TRUE                                    ~ as.integer(closeness < mediane)
      )
    ) %>%
    select(code_insee, competitif, mono_liste, closeness, type_scrutin_ref = type_scrutin)
}
comp_a <- build_competitif(coh_a, ctrl_a, 2008L)
comp_b <- build_competitif(coh_b, ctrl_b, 2014L)
comp_c <- build_competitif(coh_c, ctrl_c, 2020L)

cat(sprintf("Competitif dispo (non-NA) : A=%d/%d  B=%d/%d  C=%d/%d\n",
            sum(!is.na(comp_a$competitif)), nrow(comp_a),
            sum(!is.na(comp_b$competitif)), nrow(comp_b),
            sum(!is.na(comp_c$competitif)), nrow(comp_c)))
cat("Repartition mono_liste x regime (reference t-6) :\n")
for (cc in list(list(comp_a, "A"), list(comp_b, "B"), list(comp_c, "C"))) {
  print(cc[[1]] %>% count(type_scrutin_ref, mono_liste) %>% mutate(cohort = cc[[2]]))
}

# ─── Diagnostic taille de cellule : traitement x competitif (S1 + S2) ─────
# Une cellule trop petite (ex. cohorte A, panachage 2008 quasi tout mono-
# liste -> 138 communes disputees seulement) produit un AME d'interaction
# instable (quasi-separation), pas un effet reel. Seuil arbitraire mais
# conservateur : n < 30 candidats traites-competitifs = cellule signalee.
cell_check <- function(coh_codes, ctrl_hp_codes, comp_dat, elec_yr, lbl) {
  all_codes <- unique(c(coh_codes, ctrl_hp_codes))
  d <- pm %>% filter(annee == elec_yr, code_insee %in% all_codes) %>%
    mutate(traitement = as.integer(code_insee %in% coh_codes)) %>%
    left_join(comp_dat %>% select(code_insee, competitif), by = "code_insee") %>%
    filter(!is.na(recandidature), !is.na(reconduit), !is.na(competitif))
  cand <- d %>% filter(recandidature == 1L)
  n_s2_trt_comp <- sum(cand$traitement == 1 & cand$competitif == 1)
  cat(sprintf("%s : n(traite x competitif, S2 candidats) = %d%s\n",
              lbl, n_s2_trt_comp, if (n_s2_trt_comp < 30) "  <-- CELLULE TROP FAIBLE, AME non fiable" else ""))
  n_s2_trt_comp
}
cat("\n=== Diagnostic taille de cellule (seuil n<30 = non fiable) ===\n")
n_cell_a <- cell_check(coh_a, ctrl_a, comp_a, 2014L, "Cohorte A")
n_cell_b <- cell_check(coh_b, ctrl_b, comp_b, 2020L, "Cohorte B")
n_cell_c <- cell_check(coh_c, ctrl_c, comp_c, 2026L, "Cohorte C")
cell_flag <- c("Cohorte A" = n_cell_a < 30, "Cohorte B" = n_cell_b < 30, "Cohorte C" = n_cell_c < 30)

# ─── Variable d'exclusion Stage 1 : nb_mandats, pas nb_listes ─────────────
# nb_listes (nb de candidats/listes dans la course) viole l'exclusion par
# construction : un champ dispute affecte MECANIQUEMENT la probabilite de
# gagner une fois candidat, pas seulement la decision de se representer.
# Teste (heckit_nbmandats_check.R) : avec nb_listes, rho hors bornes
# [-1,1] (identification invalide) pour les cohortes A et B. Avec
# nb_mandats (nb de mandats consecutifs deja obtenus, cumsum du reconduit
# retarde -- fatigue de carriere, effet plus ambigu sur la victoire
# conditionnelle), rho revient dans [-1,1] pour les deux cohortes.
# panel_maires.csv porte 88 doublons code_insee x annee (artefact de fusion
# de communes en amont) ; certains donnent des nb_mandats DIFFERENTS selon
# l'ordre des lignes -> distinct() apres coup pour eviter un join
# many-to-many qui dupliquerait des lignes de d en aval.
nb_mandats_tbl <- pm %>%
  filter(!is.na(recandidature)) %>%
  arrange(code_insee, annee) %>%
  group_by(code_insee) %>%
  mutate(nb_mandats = cumsum(lag(reconduit, default = 0))) %>%
  ungroup() %>%
  distinct(code_insee, annee, .keep_all = TRUE) %>%
  select(code_insee, annee, nb_mandats)

# ─── Heckman 2-step avec interaction traitement x competitif ──────────────
run_heckman_int <- function(coh_codes, ctrl_hp_codes, comp_dat, elec_yr, lbl) {
  pre_yr    <- elec_yr - 6L
  all_codes <- unique(c(coh_codes, ctrl_hp_codes))

  filo <- switch(as.character(elec_yr), "2014" = filo14, "2020" = filo17, "2026" = filo21)
  inv  <- if (elec_yr <= 2014L) inv13 %>% rename(invest = invest_2013) else inv19 %>% rename(invest = invest_2019)
  det  <- if (elec_yr <= 2014L) dette_raw %>% transmute(code_insee, dette = dette_2013) else
                                 dette_raw %>% transmute(code_insee, dette = dette_2019)

  d <- pm %>%
    filter(annee == elec_yr, code_insee %in% all_codes) %>%
    mutate(traitement = as.integer(code_insee %in% coh_codes),
           inscrits   = as.numeric(inscrits),
           log_pop    = log1p(inscrits)) %>%
    left_join(comp_dat %>% select(code_insee, competitif), by = "code_insee") %>%
    left_join(nb_mandats_tbl, by = c("code_insee", "annee"))

  if (elec_yr == 2026L) {
    d <- d %>% left_join(rne26, by = "code_insee") %>%
      mutate(age = age_rne26, homme = homme_rne26)
  } else {
    d <- d %>% mutate(age   = as.numeric(age_maire_election),
                      homme = as.integer(sexe_maire == "M"))
  }

  d <- d %>%
    mutate(age2 = age^2) %>%
    left_join(filo,     by = "code_insee") %>%
    left_join(epci_raw, by = "code_insee") %>%
    mutate(epci_type = as.factor(coalesce(as.integer(epci_type), 0L))) %>%
    left_join(det, by = "code_insee") %>%
    left_join(inv, by = "code_insee") %>%
    mutate(log_rev    = log1p(rev_med),
           invest_pc  = invest / pmax(inscrits, 1),
           dette_pc   = dette  / pmax(inscrits, 1),
           log_invest = log1p(invest_pc),
           log_dette  = log1p(dette_pc)) %>%
    filter(!is.na(recandidature), !is.na(reconduit), !is.na(age), !is.na(nb_mandats),
           !is.na(rev_med), !is.na(invest_pc), !is.na(dette_pc), !is.na(competitif),
           # epci_type=="0" : categorie residuelle quasi-vide, separation
           # parfaite decouverte sur Cohorte B (n=3, toutes recandidature==1)
           # -> faisait exploser tout ajustement Heckman (SE=Inf, rho hors
           # bornes). Exclue partout, perte negligeable.
           epci_type != "0") %>%
    mutate(competitif = factor(competitif, levels = c(0, 1), labels = c("Non-compet.", "Competitif")),
           epci_type  = droplevels(epci_type))

  cat(sprintf("=== %s (election %d) : n=%d  traites=%d  contreles=%d  competitifs=%d ===\n",
              lbl, elec_yr, nrow(d), sum(d$traitement), sum(!d$traitement),
              sum(d$competitif == "Competitif")))

  s1 <- glm(recandidature ~ traitement * competitif + age + age2 + nb_mandats + homme +
              log_pop + log_rev + epci_type + log_invest + log_dette + factor(dep),
            data = d, family = binomial("probit"))
  xb    <- predict(s1, newdata = d, type = "link")
  d$imr <- dnorm(xb) / pnorm(xb)

  cand <- d %>% filter(recandidature == 1L, !is.na(reconduit))
  s2 <- glm(reconduit ~ traitement * competitif + age + homme + imr +
              log_pop + log_rev + epci_type + log_invest + log_dette + factor(dep),
            data = cand, family = binomial("probit"))

  list(s1 = s1, s2 = s2, d = d, cand = cand, lbl = lbl, elec_yr = elec_yr)
}

res_a <- run_heckman_int(coh_a, ctrl_a, comp_a, 2014L, "Cohorte A")
res_b <- run_heckman_int(coh_b, ctrl_b, comp_b, 2020L, "Cohorte B")
res_c <- run_heckman_int(coh_c, ctrl_c, comp_c, 2026L, "Cohorte C")

# ─── AME de traitement, par niveau de competitif, delta method ────────────
# Ai & Norton (2003) : coefficient d'interaction probit brut non interpretable.
# Frondel & Vance : meme logique pour Heckit -> avg_slopes(by=competitif) +
# contraste pairwise (Non-compet. vs Competitif) par delta method.
ame_by_group <- function(model, newdata, stage_lbl, cohort_lbl) {
  out <- avg_slopes(model, variables = "traitement", by = "competitif", newdata = newdata)
  counts <- newdata %>%
    count(competitif, traitement) %>%
    tidyr::pivot_wider(names_from = traitement, values_from = n, values_fill = 0,
                       names_prefix = "trt_") %>%
    rename(n_ctrl = trt_0, n_trt = trt_1) %>%
    mutate(n_tot = n_ctrl + n_trt)
  tibble(competitif = out$competitif, estimate = out$estimate * 100, se = out$std.error * 100,
         p = out$p.value, ci_lo = out$conf.low * 100, ci_hi = out$conf.high * 100,
         stage = stage_lbl, cohort = cohort_lbl) %>%
    left_join(counts, by = "competitif")
}

fig_dat <- bind_rows(
  ame_by_group(res_a$s1, res_a$d,    "Stage 1 -- Candidature", res_a$lbl),
  ame_by_group(res_a$s2, res_a$cand, "Stage 2 -- Reelection",  res_a$lbl),
  ame_by_group(res_b$s1, res_b$d,    "Stage 1 -- Candidature", res_b$lbl),
  ame_by_group(res_b$s2, res_b$cand, "Stage 2 -- Reelection",  res_b$lbl),
  ame_by_group(res_c$s1, res_c$d,    "Stage 1 -- Candidature", res_c$lbl),
  ame_by_group(res_c$s2, res_c$cand, "Stage 2 -- Reelection",  res_c$lbl)
) %>%
  mutate(
    fiable = !cell_flag[cohort],
    cohort = factor(cohort, levels = c("Cohorte A", "Cohorte B", "Cohorte C"),
                    labels = c("A (2014)", "B (2020)", "C (2026)")),
    stage  = factor(stage, levels = c("Stage 1 -- Candidature", "Stage 2 -- Reelection")),
    lbl    = sprintf("%+.1f pp%s%s\n(%d/%d)",
                     estimate, stars(p), if_else(fiable, "", " n<30"), n_trt, n_ctrl)
  )

print(fig_dat %>% select(stage, cohort, competitif, estimate, se, p))
write_csv(fig_dat, file.path(MORVAN, "tables/tab3_ame_competitif.csv"))

# ─── Contraste (Competitif - Non-compet.), pour annotation / verif ────────
contrast_by_group <- function(model, newdata) {
  avg_slopes(model, variables = "traitement", by = "competitif", newdata = newdata,
             hypothesis = ~pairwise)
}
cat("\n=== Contraste Competitif - Non-compet. (delta method) ===\n")
for (r in list(res_a, res_b, res_c)) {
  cat(sprintf("\n-- %s --\n", r$lbl))
  cat("S1:\n"); print(contrast_by_group(r$s1, r$d))
  cat("S2:\n"); print(contrast_by_group(r$s2, r$cand))
}

# ─── Figure : 2 panneaux (Stage 1 / Stage 2), 3 cohortes, competitif ──────
DODGE <- 0.65
p <- ggplot(fig_dat, aes(x = cohort, y = estimate, color = competitif, alpha = fiable)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "grey60", linewidth = 0.7) +
  geom_pointrange(aes(ymin = ci_lo, ymax = ci_hi),
                  position = position_dodge(width = DODGE), size = 0.75, linewidth = 1.0) +
  geom_text(aes(y = ci_hi, label = lbl), position = position_dodge(width = DODGE),
            vjust = -0.3, size = 2.9, fontface = "bold", lineheight = 0.85, show.legend = FALSE) +
  facet_wrap(~stage) +
  scale_color_manual(values = c("Non-compet." = "#e57373", "Competitif" = "#b71c1c"), name = NULL) +
  scale_alpha_manual(values = c(`TRUE` = 1, `FALSE` = 0.35), guide = "none") +
  coord_cartesian(ylim = c(-30, 45)) +
  labs(
    title    = "Effet differentiel de l'eolien : competitif vs non-competitif (AME)",
    subtitle = "Ecart d'effet marginal (points de %) -- Heckman 2-step, interaction delta method (Ai & Norton 2003 ; Frondel & Vance, extension Heckit)",
    x = NULL, y = "AME traitement (points de %)",
    caption = paste(
      "Competitif = closeness_(t-6) < mediane du regime electoral (individuel/liste), parmi les communes traitees. Sous chaque effet : (n traite / n controle).",
      "Mono-liste / pas de siege disputable -> competitif=0 (David, Jayet & Revelli 2019).",
      "Regime individuel (panachage) : marge au seuil du dernier siege (adapte de Folke 2014), pas top1-top2 (invalide en multi-membre, Tricaud & Wacziarg 2025).",
      "Cohorte A, regime individuel 2008 : source tronquee aux elus (perdants absents) -> repli sur la part du vainqueur des exprimes (100-pct_voix_gagnant), pas la marge au seuil.",
      "Cohorte C : regime individuel disparait en 2026 (reforme liste universelle) -> quasi-placebo, non comparable a A/B.",
      "Exclusion Stage 1 : nb_mandats (mandats consecutifs deja obtenus), pas nb_listes -- nb_listes affecte mecaniquement la victoire conditionnelle, viole l'exclusion. Avec nb_mandats, rho revient dans [-1,1] (heckit_nbmandats_check.R) ; avec nb_listes, rho hors bornes (identification invalide) pour A et B.",
      "Etoiles = significativite du point lui-meme (H0: effet=0), pas du contraste Competitif-Non-compet. Contraste B (delta method) : p=0.109 (non significatif) malgre le point Competitif seul a p=0.031.",
      "*** p<0.01  ** p<0.05  * p<0.10", sep = "\n")
  ) +
  theme_light(base_size = 12) +
  theme(legend.position = "bottom", plot.caption = element_text(hjust = 0, size = 7.5, color = "grey40"))

# Annotation textuelle pour les points hors echelle (coord_cartesian les
# coupe sans avertissement -> on rappelle la vraie valeur pres du bord).
off_scale <- fig_dat %>% filter(estimate < -30 | estimate > 45)
if (nrow(off_scale) > 0) {
  p <- p + geom_text(data = off_scale %>% mutate(estimate = if_else(estimate < -30, -27, 42)),
                     aes(label = lbl), color = "grey40", size = 2.7, fontface = "italic",
                     lineheight = 0.9, position = position_dodge(width = DODGE), show.legend = FALSE)
}

ggsave(file.path(FIG, "fig2_interaction_cohorts.png"), p, width = 13, height = 8, dpi = 150)
cat("\nSaved -> figures/fig2_interaction_cohorts.png\n")

# ─── Simple Heckman (every run, publication baseline) ─────────────────────
# The Stage 1/Stage 2 estimates above (competitif interaction, full control
# set) come from a MANUAL 2-step (glm probit S1 -> IMR by hand -> glm probit
# S2 with imr as a regressor). glm() treats imr as observed data, so it
# ignores S1's estimation uncertainty (generated regressor problem, Heckman
# 1979) -- those S2 SEs are understated. A full-control heckit() validation
# was tried first (competitif interaction + age/homme/epci/dep/income/
# invest/dette) but epci_type + factor(dep) cause separation in some
# cohorts and the interaction cells are too thin (n<30) for a stable
# estimate either way (see cell_check() above).
#
# Simplest possible spec instead -- no competitif interaction, no
# epci/dep/income/invest/dette controls, just:
#   Selection : recandidature ~ traitement + nb_mandats (exclusion) + log_pop
#   Outcome   : reconduit    ~ traitement + log_pop
# log_pop added : wind farm siting isn't random w.r.t. commune size, and
# size plausibly affects both candidacy and reelection odds directly
# (bigger communes = more contested races, more career politicians) --
# omitting it risks confounding the treatment coefficient. log_pop =
# log1p(inscrits), already built into res$d above (no separation risk,
# single continuous covariate).
# sampleSelection::heckit(method="2step") implements Heckman's analytic SE
# correction for the outcome equation (LPM, not probit -- coef IS the
# marginal effect, no Ai-Norton correction needed). rho printed every run
# as a standing identification check (must stay in [-1,1]).
# No clustering: one row per commune per cohort (cross-section), not a
# pooled panel within a cohort -- no repeated observations to cluster over.
suppressPackageStartupMessages(library(sampleSelection))

sel_fml_simple <- recandidature ~ traitement + nb_mandats + log_pop
out_fml_simple <- reconduit    ~ traitement + log_pop

run_heckit_simple <- function(res, lbl) {
  cat(sprintf("\n-- %s --\n", lbl))
  d <- res$d %>% filter(!is.na(recandidature), !is.na(nb_mandats), !is.na(log_pop))
  cat(sprintf("  n=%d, traites=%d\n", nrow(d), sum(d$traitement)))

  fit <- tryCatch(
    heckit(selection = sel_fml_simple, outcome = out_fml_simple, data = d, method = "2step"),
    error = function(e) { cat("  ERROR heckit:", conditionMessage(e), "\n"); NULL })
  if (is.null(fit)) return(invisible(NULL))

  ct <- summary(fit)$estimate
  cat("  Selection eq, traitement (candidacy decision):\n")
  print(round(ct["traitement", , drop = FALSE], 4))
  out_row <- which(rownames(ct) == "traitement")[2]
  cat("  Outcome eq, traitement (reelection effect | ran again):\n")
  print(round(ct[out_row, , drop = FALSE], 4))
  rho_val <- ct["rho", "Estimate"]
  cat(sprintf("  rho = %.4f %s\n", rho_val,
              if (abs(rho_val) > 1) "<-- OUT OF [-1,1], IDENTIFICATION INVALID" else "<-- within [-1,1], OK"))
  invisible(fit)
}

cat("\n=== Simple Heckman (recandidature ~ traitement + nb_mandats + log_pop | reconduit ~ traitement + log_pop) ===\n")
heckit_a <- run_heckit_simple(res_a, "Cohorte A")
heckit_b <- run_heckit_simple(res_b, "Cohorte B")
heckit_c <- run_heckit_simple(res_c, "Cohorte C")
