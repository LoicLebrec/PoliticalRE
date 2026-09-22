# Descriptive/orientation outputs for the paper -- everything that isn't a
# regression result: case-study numbers at a glance, a cross-source sanity
# check, and a map of where the identifying variation comes from. Merged
# into one file (was 3: build_descriptive_stats.R, build_source_comparison.R,
# build_treatment_map.R) -- each individually was too small/thematically
# identical (same data, no regression) to justify its own file, unlike
# twfe/'s separate build_*.R scripts, which each run a genuinely distinct
# analysis (23-spec robustness grid, balance table, etc.).
#
# Output:
#   tables/table_descriptive_stats.{csv,tex}
#   figures/cumulative_capacity_3sources.png
#   figures/treatment_map.png

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(tidyr); library(stringr); library(kableExtra)
  library(jsonlite); library(ggplot2)
})

PROJECT <- Sys.getenv("POLITICALRE_ROOT", unset = "/home/loiclebrec/ENRpolitical/Python/PoliticalRE")
PANEL   <- file.path(PROJECT, "simple_regression/panel/panel.csv")
PARC    <- file.path(PROJECT, "data/parceolien/Parc.csv")
GEO_DIR <- file.path(PROJECT, "data/geo")
PUB     <- file.path(PROJECT, "simple_regression/publication/descriptive")
TAB     <- file.path(PUB, "tables")
FIG     <- file.path(PUB, "figures")
dir.create(TAB, showWarnings = FALSE, recursive = TRUE)
dir.create(FIG, showWarnings = FALSE, recursive = TRUE)
dir.create(GEO_DIR, showWarnings = FALSE, recursive = TRUE)

col_spec <- cols(code_insee = col_character(), dep = col_character(), .default = col_guess())
pad5 <- function(x) str_pad(str_extract(as.character(x), "[0-9A-Za-z]+"), 5, "left", "0")
DENS_OK <- c("5","6","7")
PERIODS <- c(2008L, 2014L, 2020L, 2026L)

REG_MAP <- c("11"="Ile-de-France","24"="Centre-Val de Loire","27"="Bourgogne-Franche-Comte",
             "28"="Normandy","32"="Hauts-de-France","44"="Grand Est","52"="Pays de la Loire",
             "53"="Brittany","75"="Nouvelle-Aquitaine","76"="Occitanie",
             "84"="Auvergne-Rhone-Alpes","93"="Provence-Alpes-Cote d'Azur","94"="Corsica")

panel_full <- read_csv(PANEL, col_types = col_spec)
panel_raw  <- panel_full %>% filter(commune_fixe == 1)
ctrl_matched  <- read_csv(file.path(PROJECT, "simple_regression/robsocioeco/data/control_group_new.csv"), col_types = col_spec) %>%
  pull(code_insee) %>% unique()
ctrl_baseline <- read_csv(file.path(PROJECT, "simple_regression/CRcreu11/data/control_group.csv"), col_types = col_spec) %>%
  pull(code_insee) %>% unique()

# ══════════════════════════════════════════════════════════════════════════
# 1. DESCRIPTIVE STATS TABLE -- milestone timelines, installation counts,
#    geography, sample sizes. Park-level dates come from the raw Parc.csv
#    (each commissioned park counted once, not per hosting commune -- see
#    panel/build_panel.R for why summing panel.csv's per-commune mw_cumul
#    would double-count multi-commune parks' national total).
# ══════════════════════════════════════════════════════════════════════════
cat("=== 1. Descriptive stats table ===\n")

parc <- read_csv(PARC, col_types = cols(
    id_parc = col_character(), code_insee = col_character(),
    puissance_parc_mw = col_double(), nombre_aerogenerateur = col_double(),
    date_depot_demande_autorisation = col_character(),
    date_delivrance_avis_autorite_environnementale = col_character(),
    date_delivrance_autorisation = col_character(),
    date_debut_construction = col_character(),
    date_mise_en_service = col_character(), .default = col_skip())) %>%
  mutate(code_insee = pad5(code_insee)) %>%
  distinct(id_parc, .keep_all = TRUE) %>%
  mutate(
    d_depot  = as.Date(substr(date_depot_demande_autorisation, 1, 10)),
    d_avis   = as.Date(substr(date_delivrance_avis_autorite_environnementale, 1, 10)),
    d_auth   = as.Date(substr(date_delivrance_autorisation, 1, 10)),
    d_constr = as.Date(substr(date_debut_construction, 1, 10)),
    d_mes    = as.Date(substr(date_mise_en_service, 1, 10)),
    lag_depot_mes = as.numeric(d_mes - d_depot) / 365.25,
    lag_auth_mes  = as.numeric(d_mes - d_auth) / 365.25,
    lag_depot_auth = as.numeric(d_auth - d_depot) / 365.25
  )

# Non-commissioned parks stuck at their last known milestone for a long time
# -- the closest available proxy for an abandoned project (Parc.csv has no
# explicit abandonment flag). 1990/today bounds guard against a handful of
# corrupted date fields (e.g. a single row with an implausible multi-century
# gap).
today <- Sys.Date()
stuck <- parc %>% filter(is.na(d_mes)) %>%
  rowwise() %>%
  mutate(last_stage_date = suppressWarnings(max(c(d_depot, d_avis, d_auth, d_constr), na.rm = TRUE))) %>%
  ungroup() %>%
  mutate(last_stage_date = as.Date(ifelse(is.infinite(last_stage_date), NA, last_stage_date), origin = "1970-01-01")) %>%
  filter(!is.na(last_stage_date), last_stage_date > as.Date("1990-01-01"), last_stage_date <= today) %>%
  mutate(yrs_stuck = as.numeric(today - last_stage_date) / 365.25)
n_stuck_6y <- sum(stuck$yrs_stuck > 6, na.rm = TRUE)

parc_commissioned <- parc %>% filter(!is.na(d_mes))
n_parks_total <- n_distinct(parc$id_parc)
n_parks_commissioned <- nrow(parc_commissioned)

rural_2026 <- panel_raw %>% filter(annee == 2026L, categorie_dens %in% DENS_OK) %>% distinct(code_insee, .keep_all = TRUE)
treated_communes <- panel_raw %>% filter(annee == 2026L, as.numeric(n_parcs_cumul) > 0) %>%
  distinct(code_insee, .keep_all = TRUE)
treated_rural <- treated_communes %>% filter(categorie_dens %in% DENS_OK)

reg_dist <- treated_rural %>% mutate(reg_str = as.character(as.integer(reg))) %>%
  count(reg_str, name = "n") %>%
  mutate(region = coalesce(REG_MAP[reg_str], "Other")) %>%
  arrange(desc(n))
top3_regions <- reg_dist %>% slice_head(n = 3) %>%
  mutate(txt = sprintf("%s (%d)", region, n)) %>% pull(txt) %>% paste(collapse = ", ")

fmt_yrs <- function(x) sprintf("%.1f y", median(x, na.rm = TRUE))

rows <- tribble(
  ~Category, ~Statistic, ~Value,
  "Installations", "Wind parks on record (all statuses)", as.character(n_parks_total),
  "Installations", "Wind parks commissioned", as.character(n_parks_commissioned),
  "Installations", "Total installed capacity, commissioned (MW)", sprintf("%.0f", sum(parc_commissioned$puissance_parc_mw, na.rm = TRUE)),
  "Installations", "Total turbines, commissioned", sprintf("%.0f", sum(parc_commissioned$nombre_aerogenerateur, na.rm = TRUE)),
  "Installations", "Median park size (MW)", sprintf("%.1f", median(parc_commissioned$puissance_parc_mw, na.rm = TRUE)),
  "Installations", "Median turbines per park", sprintf("%.0f", median(parc_commissioned$nombre_aerogenerateur, na.rm = TRUE)),
  "Milestones", "Permit filed -> authorization granted", fmt_yrs(parc_commissioned$lag_depot_auth),
  "Milestones", "Authorization granted -> commissioned", fmt_yrs(parc_commissioned$lag_auth_mes),
  "Milestones", "Permit filed -> commissioned", fmt_yrs(parc_commissioned$lag_depot_mes),
  "Milestones", "Non-commissioned parks stalled 6+y at last known stage", sprintf("%d (of %d never commissioned)", n_stuck_6y, n_parks_total - n_parks_commissioned),
  "Geography", "Rural communes in sample (density 5-7)", as.character(n_distinct(rural_2026$code_insee)),
  "Geography", "Treated rural communes (>=1 park commissioned)", as.character(n_distinct(treated_rural$code_insee)),
  "Geography", "Top 3 regions, treated rural communes", top3_regions,
  "Sample", "Never-treated pool, socioeconomically matched", as.character(n_distinct(ctrl_matched)),
  "Sample", "Never-treated pool, baseline", as.character(n_distinct(ctrl_baseline))
)

write_csv(rows, file.path(TAB, "table_descriptive_stats.csv"))
cat(sprintf("Saved -> %s (%d rows)\n", file.path(TAB, "table_descriptive_stats.csv"), nrow(rows)))

tab_latex <- rows %>%
  kbl(format = "latex", booktabs = TRUE, escape = TRUE,
      caption = "Case study at a glance: installations, milestone timelines, geography, sample sizes",
      label = "tab:descriptive_stats", linesep = "") %>%
  kable_styling(latex_options = c("hold_position"), font_size = 9) %>%
  collapse_rows(columns = 1, valign = "top") %>%
  footnote(general = paste(
    "Installations: commissioned = has a date_mise_en_service (see panel/build_panel.R). MW/turbines counted once per park (not per hosting commune).",
    "Milestones: median years between stages, commissioned parks with both dates observed. Stalled = never-commissioned park whose latest known stage (filed/env. review/authorized/construction started) is 6+ years old as of today -- closest available proxy for an abandoned project, no explicit status field for this in the source data.",
    "Geography/Sample: rural = INSEE density category 5-7, as of 2026; treated = >=1 commissioned park.",
    sep = " "),
    threeparttable = TRUE, escape = FALSE)

writeLines(as.character(tab_latex), file.path(TAB, "table_descriptive_stats.tex"))
cat(sprintf("Saved -> %s\n", file.path(TAB, "table_descriptive_stats.tex")))

# ══════════════════════════════════════════════════════════════════════════
# 2. CUMULATIVE CAPACITY, 3 INDEPENDENT SOURCES -- sanity check that Parc,
#    Registre, and WindProject broadly agree on how much capacity existed
#    when. Rebuild of a graph that existed earlier in this project
#    (graphscarteEoliendepetcum.R, cumulative_wind_power.png), removed from
#    disk before this repo's current publication/ structure existed --
#    recovered from git history (commit 344cb9e) and adapted (portable
#    paths, window extended from a 2022 cap to the full data).
# ══════════════════════════════════════════════════════════════════════════
cat("\n=== 2. Cumulative capacity, 3 sources ===\n")

CUR_YEAR <- as.integer(format(Sys.Date(), "%Y"))

parc_base <- read.csv(file.path(PROJECT, "data/parceolien/Parc_merged_multi_communes.csv"), check.names = FALSE) %>%
  filter(etat_parc == "En exploitation", !is.na(date_mise_en_service), date_mise_en_service != "") %>%
  transmute(source = "Parc", year = as.integer(substr(date_mise_en_service, 1, 4)),
            mw = as.numeric(puissance_parc_mw))

wind_base <- read.csv(file.path(PROJECT, "data/WindFarm_France_merged_projects.csv"), check.names = FALSE) %>%
  filter(!is.na(`Commissioning date`), `Commissioning date` != "") %>%
  transmute(source = "WindProject", year = as.integer(substr(`Commissioning date`, 1, 4)),
            mw = as.numeric(`Total power`) / 1000)

registre_base <- read.csv(file.path(PROJECT, "data/parceolien/registre-national-installation-production-stockage-electricite-agrege.csv"),
                           sep = ";", check.names = FALSE) %>%
  filter(codeFiliere == "EOLIE", !is.na(`dateMiseEnservice (format date)`), `dateMiseEnservice (format date)` != "") %>%
  transmute(source = "Registre", year = as.integer(substr(`dateMiseEnservice (format date)`, 1, 4)),
            mw = as.numeric(puisMaxInstallee) / 1000)

cum_capacity <- bind_rows(parc_base, wind_base, registre_base) %>%
  filter(!is.na(year), !is.na(mw), mw > 0, year >= 2000, year <= CUR_YEAR) %>%
  group_by(source, year) %>%
  summarise(mw = sum(mw), .groups = "drop") %>%
  arrange(source, year) %>%
  group_by(source) %>%
  mutate(cumulative_gw = cumsum(mw) / 1000) %>%
  ungroup()

cat("Latest cumulative capacity (GW) per source:\n")
print(cum_capacity %>% group_by(source) %>% slice_max(year, n = 1) %>% select(source, year, cumulative_gw))

p_sources <- ggplot(cum_capacity, aes(x = year, y = cumulative_gw, color = source)) +
  geom_line(linewidth = 1) +
  geom_point(size = 1.3, alpha = 0.6) +
  scale_color_manual(values = c("Parc" = "#2a78d6", "Registre" = "#e34948", "WindProject" = "#1baf7a"),
                      name = "Source") +
  labs(title = "Cumulative installed wind capacity -- 3 independent sources",
       subtitle = sprintf("France, %d-%d", min(cum_capacity$year), max(cum_capacity$year)),
       x = "Year", y = "Cumulative capacity (GW)",
       caption = paste(
         "Sources: Parc (French wind park registry, deduplicated per park), Registre (national grid-connection registry, EOLIE filiere),",
         "WindProject (third-party wind farm database). Each uses its own commissioning-date field/coverage -- shown together as a",
         "cross-source sanity check, not a precision reconciliation.",
         sep = "\n")) +
  theme_bw(base_size = 12) +
  theme(legend.position = "right", plot.caption = element_text(hjust = 0, size = 7.5, color = "grey40"))

ggsave(file.path(FIG, "cumulative_capacity_3sources.png"), p_sources, width = 9, height = 5.5, dpi = 200)
cat(sprintf("Saved -> %s\n", file.path(FIG, "cumulative_capacity_3sources.png")))

# ══════════════════════════════════════════════════════════════════════════
# 3. TREATMENT/CONTROL MAP -- where the identifying variation actually
#    comes from. No `sf`/GDAL: this environment has GEOS/GDAL RUNTIME libs
#    but not the `-dev` headers / `cmake` / `libabsl-dev` that `sf`'s `s2`
#    dependency needs to compile, and installing those needs sudo (skipped
#    rather than doing that without asking). Department boundaries parsed
#    by hand from a plain GeoJSON (gregoiredavid/france-geojson,
#    MIT-licensed, cached locally) into the (long, lat, group) shape
#    ggplot2::geom_polygon expects -- same shape the old `maps` package
#    produced, but from an accurate, actively maintained source. Communes
#    plotted as centroid points (data/communes_centroids.csv), not filled
#    polygons -- avoids needing commune-level boundaries (35k of those
#    would dwarf 96 departments in file size).
# ══════════════════════════════════════════════════════════════════════════
cat("\n=== 3. Treatment/control map ===\n")

geojson_path <- file.path(GEO_DIR, "departements.geojson")
if (!file.exists(geojson_path)) {
  download.file("https://raw.githubusercontent.com/gregoiredavid/france-geojson/master/departements.geojson",
                geojson_path, quiet = TRUE)
}
geo <- fromJSON(geojson_path, simplifyVector = FALSE)

# A Polygon's coordinates are list(ring1, ring2, ...) where ring1 is the
# outer boundary (holes ignored -- irrelevant at this map scale). A
# MultiPolygon is list(polygon1, polygon2, ...), each shaped like a Polygon.
# Every distinct ring gets its own `group` so ggplot doesn't draw a spurious
# line connecting unrelated rings (e.g. Belle-Ile-en-Mer to the Morbihan
# mainland).
ring_to_df <- function(ring, dept_code, dept_name, group_id) {
  # simplifyVector=FALSE keeps every coordinate pair as a 2-element list (not
  # a numeric vector), so do.call(rbind, ring) alone yields a list-mode
  # matrix, not numeric -- unlist() each point first.
  coords <- do.call(rbind, lapply(ring, function(pt) unlist(pt, use.names = FALSE)))
  tibble(long = coords[,1], lat = coords[,2], dept_code = dept_code, dept_name = dept_name, group = group_id)
}
dept_polys <- bind_rows(lapply(seq_along(geo$features), function(i) {
  f <- geo$features[[i]]
  code <- f$properties$code; nom <- f$properties$nom
  if (f$geometry$type == "Polygon") {
    ring_to_df(f$geometry$coordinates[[1]], code, nom, sprintf("%s.1", code))
  } else {
    bind_rows(lapply(seq_along(f$geometry$coordinates), function(j) {
      ring_to_df(f$geometry$coordinates[[j]][[1]], code, nom, sprintf("%s.%d", code, j))
    }))
  }
}))
cat(sprintf("Department boundary: %d departments, %d polygon rings, %d vertices\n",
            n_distinct(dept_polys$dept_code), n_distinct(dept_polys$group), nrow(dept_polys)))

rural_stable <- panel_raw %>% filter(annee %in% PERIODS) %>%
  distinct(code_insee, annee, .keep_all = TRUE) %>%
  group_by(code_insee) %>%
  summarise(n_obs = n(), n_rural = sum(categorie_dens %in% DENS_OK), .groups = "drop") %>%
  filter(n_obs == n_rural) %>% pull(code_insee)

first_treat <- panel_raw %>% filter(annee %in% PERIODS, code_insee %in% rural_stable) %>%
  distinct(code_insee, annee, .keep_all = TRUE) %>%
  mutate(treated_now = as.numeric(n_parcs_cumul) > 0) %>%
  group_by(code_insee) %>%
  summarise(first_treat_year = if (any(treated_now)) min(annee[treated_now]) else 0L, .groups = "drop")

status <- first_treat %>%
  mutate(status = case_when(
    first_treat_year == 2008L ~ "Treated -- Cohort A (2008, dropped from CS: no pre-period)",
    first_treat_year == 2014L ~ "Treated -- Cohort A (2008-2014)",
    first_treat_year == 2020L ~ "Treated -- Cohort B (2014-2020)",
    first_treat_year == 2026L ~ "Treated -- Cohort C (2020-2026)",
    code_insee %in% ctrl_matched  ~ "Control -- Socioeconomically matched",
    code_insee %in% ctrl_baseline ~ "Control -- Baseline",
    TRUE ~ "Rural, not in any control pool"
  ))

centroids <- read_csv(file.path(PROJECT, "data/communes_centroids.csv"),
                       col_types = cols(code_insee = col_character(), .default = col_guess()))
map_points <- status %>% inner_join(centroids, by = "code_insee") %>%
  filter(lon > -6, lon < 10, lat > 41, lat < 51.5)  # metropolitan France bounding box, drop DROM/errors

cat("Communes plotted by status:\n"); print(table(map_points$status))

STATUS_LEVELS <- c("Treated -- Cohort A (2008-2014)", "Treated -- Cohort B (2014-2020)",
                    "Treated -- Cohort C (2020-2026)", "Treated -- Cohort A (2008, dropped from CS: no pre-period)",
                    "Control -- Socioeconomically matched", "Control -- Baseline",
                    "Rural, not in any control pool")
STATUS_COLORS <- c(
  "Treated -- Cohort A (2008-2014)"        = "#e34948",
  "Treated -- Cohort B (2014-2020)"        = "#a51c1c",
  "Treated -- Cohort C (2020-2026)"        = "#5e0d0d",
  "Treated -- Cohort A (2008, dropped from CS: no pre-period)" = "#f0a3a2",
  "Control -- Socioeconomically matched"   = "#2a78d6",
  "Control -- Baseline"                    = "#a8c8ec",
  "Rural, not in any control pool"         = "grey85"
)
STATUS_SIZE <- c(
  "Treated -- Cohort A (2008-2014)" = 0.7, "Treated -- Cohort B (2014-2020)" = 0.7,
  "Treated -- Cohort C (2020-2026)" = 0.7, "Treated -- Cohort A (2008, dropped from CS: no pre-period)" = 0.7,
  "Control -- Socioeconomically matched" = 0.35, "Control -- Baseline" = 0.2,
  "Rural, not in any control pool" = 0.15
)
map_points <- map_points %>% mutate(status = factor(status, levels = STATUS_LEVELS)) %>% arrange(desc(status))

p_map <- ggplot() +
  geom_polygon(data = dept_polys, aes(x = long, y = lat, group = group),
               fill = "grey97", color = "grey75", linewidth = 0.2) +
  geom_point(data = map_points, aes(x = lon, y = lat, color = status, size = status), alpha = 0.75) +
  coord_quickmap() +
  scale_color_manual(values = STATUS_COLORS, name = NULL) +
  scale_size_manual(values = STATUS_SIZE, guide = "none") +
  guides(color = guide_legend(override.aes = list(size = 2.5))) +
  labs(title = "Treatment and control communes",
       subtitle = "Rural communes (INSEE density 5-7), by first-treatment cohort and control pool",
       caption = paste(
         "Treated = first commissioned wind park in that election-year window (panel/build_panel.R, commissioning-date definition).",
         "Control pools as used in the TWFE/CS pipeline (robsocioeco/build_control_new.R, CRcreu11/control_group.csv).",
         sep = "\n")) +
  theme_void(base_size = 12) +
  # theme_void() blanks ALL non-data chrome, legend text/background included
  # (not just axes) -- restore what's needed explicitly, and pin explicit
  # white backgrounds rather than relying on theme_void's (transparent)
  # default, which rendered as invisible-text-on-black in some viewers.
  theme(legend.position = "right",
        legend.text = element_text(size = 9, color = "grey15"),
        plot.title = element_text(face = "bold", size = 15, color = "grey10"),
        plot.subtitle = element_text(color = "grey40", size = 10.5),
        plot.caption = element_text(hjust = 0, size = 7.5, color = "grey45"),
        plot.background = element_rect(fill = "white", color = NA),
        panel.background = element_rect(fill = "white", color = NA),
        legend.background = element_rect(fill = "white", color = NA),
        legend.key = element_rect(fill = "white", color = NA),
        plot.margin = margin(10, 10, 10, 10))

ggsave(file.path(FIG, "treatment_map.png"), p_map, width = 10, height = 8.5, dpi = 220)
cat(sprintf("Saved -> %s\n", file.path(FIG, "treatment_map.png")))

# ══════════════════════════════════════════════════════════════════════════
# 4. SAMPLE FLOW DIAGRAM -- France's ~35,000 communes down to the Cohort B
# analytic sample, for the paper appendix. Every N recomputed HERE with the
# same filters as the live pipeline scripts (build_control_new.R,
# twfe/build_robustness_combined.R) -- not read from a per-outcome-filtered
# output table (that's what made an earlier version of this kind of figure,
# cohort_timeline.png, cite a different N than the rest of the pipeline;
# dropped for that reason -- see replication/README.md).
# ══════════════════════════════════════════════════════════════════════════
cat("\n=== 4. Sample flow diagram ===\n")

n_total <- n_distinct(panel_full$code_insee)
n_fixe  <- n_distinct(panel_raw$code_insee)

rural_2014 <- panel_raw %>% filter(annee == 2014L, categorie_dens %in% DENS_OK) %>% distinct(code_insee, .keep_all = TRUE)
n_rural <- n_distinct(rural_2014$code_insee)

coh_b_elig <- panel_raw %>% filter(annee %in% c(2014L, 2020L)) %>%
  distinct(code_insee, annee, .keep_all = TRUE) %>%
  select(code_insee, annee, n_parcs_cumul, categorie_dens) %>%
  pivot_wider(names_from = annee, values_from = n_parcs_cumul, names_prefix = "np_") %>%
  filter(categorie_dens %in% DENS_OK, !is.na(np_2014), !is.na(np_2020))
n_eligible <- nrow(coh_b_elig)

n_treated <- coh_b_elig %>% filter(as.numeric(np_2014) == 0, as.numeric(np_2020) > 0) %>% nrow()
n_control <- length(ctrl_matched)
n_final <- n_treated + n_control

cat(sprintf("Total: %d | Fusion-free: %d | Rural: %d | Cohort B eligible: %d | Treated: %d | Matched control: %d | Final: %d\n",
            n_total, n_fixe, n_rural, n_eligible, n_treated, n_control, n_final))

flow_steps <- tibble(
  step = factor(c("All French\ncommunes", "Fusion-free\n(commune_fixe==1)", "Rural\n(density 5-7)",
                   "Cohort B eligible\n(observed 2014 & 2020)", "Final sample\n(treated + matched control)"),
                levels = rev(c("All French\ncommunes", "Fusion-free\n(commune_fixe==1)", "Rural\n(density 5-7)",
                   "Cohort B eligible\n(observed 2014 & 2020)", "Final sample\n(treated + matched control)"))),
  n = c(n_total, n_fixe, n_rural, n_eligible, n_final),
  detail = c("", "", "", "", sprintf("%d treated + %d matched control", n_treated, n_control))
)

p_flow <- ggplot(flow_steps, aes(x = n, y = step)) +
  geom_col(fill = "#2a78d6", width = 0.55) +
  geom_text(aes(label = sprintf("%s%s", format(n, big.mark = ","),
                                 if_else(detail == "", "", sprintf("  (%s)", detail))),
                x = n), hjust = -0.02, size = 4.3, fontface = "bold") +
  scale_x_continuous(expand = expansion(mult = c(0, 0.55))) +
  labs(title = "Sample construction -- Cohort B, matched control",
       subtitle = "France's ~35,000 communes down to the final analytic sample",
       x = "Communes (N)", y = NULL) +
  theme_minimal(base_size = 13) +
  theme(panel.grid.major.y = element_blank(), panel.grid.minor = element_blank(),
        axis.text.y = element_text(size = 11.5, face = "bold"),
        plot.title = element_text(face = "bold", size = 16))

ggsave(file.path(FIG, "sample_flow.png"), p_flow, width = 10, height = 5, dpi = 180)
cat(sprintf("Saved -> %s\n", file.path(FIG, "sample_flow.png")))
