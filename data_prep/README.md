# Data preparation

How the raw data behind this paper was obtained and cleaned, ending at the
inputs consumed by `/reproducibility`. Read this before `/reproducibility`
if you want the full raw-to-final chain; read `/reproducibility` alone if
you're happy starting from already-cleaned data.

Every transform below is a versioned script in this repo -- diffable in git
history, not a hand-edit. `checksums.sha256` (this folder) fixes the exact
bytes of every raw/frozen file that has **no** transform script attached,
so a rerun can be checked against them. Run `bash verify_checksums.sh` to
check your copy matches. That is the actual guarantee this folder can make:
every step that touches data is either (a) a script you can read, or (b) a
frozen file whose checksum is pinned and whose provenance gap is disclosed
below, not hidden.

## 1. Elections (municipal, 2008-2026)

- **Base panel**: `election_data/VariablesY/variableY.csv`, built by
  `election_data/VariablesY/build_variableY.py`. Combines:
  - `maires_election_final_rescraped.csv` (2008-2020 participation +
    mayor names, Ministry of the Interior + Wikipedia)
  - `elections_municipales_clean.csv` (candidate lists, round counts)
  - `maires_election_2026.csv` (2026 results)
  - INSEE COG 2024 (commune names/dept/region, see §4)
  - INSEE density grid (see §4)
- **2024 legislative / general election-portal pattern**: municipal and
  legislative results in this project come from data.gouv.fr's static
  resource mirror. Confirmed working example (used for the 2024
  legislative first round, same portal pattern as the municipal files):
  `election_data/data_quentin/2026/build_all_2024_2026.R` downloads from
  `https://static.data.gouv.fr/resources/elections-legislatives-des-30-juin-et-7-juillet-2024-resultats-definitifs-du-1er-tour/20240711-075056/resultats-definitifs-par-communes.csv`
  automatically if the local cache is missing.
- **Enrichment**: `build_variableY.py` also recomputes `recandidature`
  (candidacy, not just reelection) and `nb_tours` against
  `elections_municipales_clean.csv`, correcting bugs present in the
  original source notebook (documented in the script's own header).

## 2. Mayors (biographical panel)

- `data/maires_panel.csv`, built by `scripts/build_maires_panel.py`. This
  is the best-documented dataset in the repo -- its docstring lists every
  input file, date, and exact merge/fallback logic.
- Source: **Répertoire National des Élus** (RNE), published at
  `https://www.data.gouv.fr/fr/datasets/donnees-du-repertoire-national-des-elus/`
  (confirmed via `data/RNE/RNE/RNE 20XX/README.md`, which also has the
  scraper: `bash run.sh` after `pip3 install -r src/requirements.txt`).
- Vintages used: RNE Dec-2025 snapshot (primary, for 2020 cohort), RNE 2019
  and 2021 snapshots (fallback), plus 2025/2026 files under
  `election_data/data_quentin/`.
- Merged into the main panel by `simple_regression/enrich_panel_maires.R`.

## 3. Wind installations

- **Wind park registry**: `data/parceolien/Parc.csv` -- **raw input, no
  acquisition script found in this repo** (see Open gaps below). Columns
  (`id_parc`, `puissance_parc_mw`, `date_mise_en_service`, `etat_parc`,
  etc.) match the French national wind-farm register schema. Confirm and
  document the exact download URL/portal here before treating this as a
  clean pipeline start point.
- **Treatment definition**: a commune is "treated" from its first park's
  *commissioning* date (`date_mise_en_service`), computed in
  `simple_regression/panel/build_panel.R` directly from `Parc.csv` --
  deliberately not the authorization or construction-start date (see
  `/reproducibility/README.md` caveat 5).
- **ICPE permits (Géorisques)**: `data/parceolien/georisques_icpe_wind.csv`
  -- confirmed source, `data/parceolien/fetch_georisques_icpe.py` line 22:
  `https://georisques.gouv.fr/api/v1/installations_classees`. Run that
  script to regenerate; not part of the 15-table pipeline itself (used for
  cross-checking `Parc.csv`, see `join_coverage.R` in git history).
- **External wind-speed / vote-share snapshot**:
  `simple_regression/panel/external_wind_voteshare.csv` -- frozen, no
  fetch script found (open gap, flagged in-script by `build_panel.R` with
  a `TODO`). Checksum pinned.

## 4. Geography / commune reference data

- **INSEE COG (commune codes/names) 2024**: `data/1.commune/cog_commune_2024.csv`,
  `cog_mvt_commune_2024.csv`. Confirmed direct public download (from
  `communeinstallation.R`, still in git history at the repo root):
  `https://www.insee.fr/fr/statistiques/fichier/7766585/v_commune_2024.csv`
  and `.../v_mvt_commune_2024.csv`.
- **INSEE density grid** (`grille de densité`, 7 levels):
  `data/insee_rural/grille_densite_7_niveaux_2021.xlsx`. Standard public
  INSEE product; no scraper in-repo, manual portal download (insee.fr,
  search "grille communale de densité 2021").
- **Department boundaries**: `data/geo/departements.geojson`. Confirmed
  source (3 build scripts, e.g.
  `simple_regression/publication/descriptive/build_parc_map.R` line 72):
  `https://raw.githubusercontent.com/gregoiredavid/france-geojson/master/departements.geojson`,
  auto-downloaded and cached on first pipeline run.
- **Commune geocoding**: `geo.api.gouv.fr/communes` (public API, no key),
  used by historical enrichment scripts under `simple_regression/archives/phase_1/`.

## 5. Socio-demographic (BPE, facility closures/openings)

- **Raw microdata**: `data/BPE_adisp/lil-XXXX.csv.zip` (9 files, one per
  BPE vintage 2007-2020). `lil-XXXX` are ADISP/Réseau Quetelet-Progedo
  catalogue identifiers -- **this is an inference from the folder name and
  file-naming convention, not a confirmed source** (no README found in
  `data/BPE_adisp/`). BPE (Base Permanente des Équipements) microdata at
  this vintage granularity is typically restricted-access (registration
  required via a Progedo/ADISP-style portal), unlike the aggregated BPE
  data INSEE publishes openly -- confirm the exact access route before
  relying on this for a fresh pull.
- **Labeled intermediate**: `data/BPE_adisp/labeled/bpeXX_ensemble_labeled.csv`
  (2007-2020, one file per vintage). Transform script from raw `lil-*.zip`
  to `labeled/` **not found in the active tree** (open gap).
- **Derived, commune x year**: `data/BPE_adisp/derived/*_by_commune_year.csv`
  (`d705_by_commune_year.csv` = CADA/asylum reception centers,
  `C104_ecole_elementaire_by_commune_year.csv` = elementary schools,
  `D107_maternite_by_commune_year.csv` = maternity wards,
  `public_service_basket_by_commune_year.csv` = 12-facility basket).
  Transform script from `labeled/` to `derived/` **also not found in the
  active tree** (open gap -- these 4 files are read directly by
  `reproducibility` pipeline steps 13-14; checksums pinned so at least the
  exact bytes used are verifiable even though the build step isn't).

## 6. Other frozen/raw inputs with no writer script (checksummed, not rebuilt)

- `simple_regression/CRcreu11/data/turnover_candidats.csv` -- candidate
  turnover by commune-year. No writer script anywhere in the repo.
- `simple_regression/CRcreu11/data/invest_communes_2013.csv` -- municipal
  investment, 2013 baseline. No writer script anywhere in the repo.
- `simple_regression/CRcreu11/data/control_group.csv` -- unmatched
  ("baseline") never-treated control pool. No writer script; reverse-
  engineering attempt and partial-match rule documented in
  `/reproducibility/README.md` caveat 2.

## Open gaps (confirm before treating as a clean from-scratch pipeline)

| File | Gap | Suggested next step |
|---|---|---|
| `data/parceolien/Parc.csv` | acquisition script/URL not found | confirm exact data.gouv.fr dataset and pin a download script |
| `data/BPE_adisp/lil-*.csv.zip` | access route inferred from filename only | confirm ADISP/Progedo registration path or public alternative |
| `data/BPE_adisp/labeled/*` | raw-to-labeled transform script missing | locate (may be in an untracked local copy) or rebuild |
| `data/BPE_adisp/derived/*` | labeled-to-derived transform script missing | same as above |
| `simple_regression/panel/external_wind_voteshare.csv` | fetch script/source unknown | identify true source, replace frozen file with a real script |
| `simple_regression/CRcreu11/data/turnover_candidats.csv` | no writer script | locate or document as permanently frozen |
| `simple_regression/CRcreu11/data/invest_communes_2013.csv` | no writer script | locate or document as permanently frozen |
| `simple_regression/CRcreu11/data/control_group.csv` | no writer script | see reverse-engineering notes in `/reproducibility/README.md` |
| `data/WindFarm_France(Feuil1).csv` | origin unconfirmed (English-header spreadsheet); not used by the 15-table pipeline, superseded by `Parc.csv` | none needed unless this file is revived |
| `data/wind/FRA_wind-speed_100m.tif` | likely Global Wind Atlas, unconfirmed; not used by the 15-table pipeline | none needed unless this file is revived |

Files listed as "not used by the 15-table pipeline" showed up in earlier
exploratory work (`simple_regression/archives/`, `phase_1/`) and are not
inputs to anything in `/reproducibility`. Listed for completeness, not
because the current pipeline depends on them.

## Verifying you have the right bytes

```
cd data_prep
bash verify_checksums.sh
```

Checks every file in `checksums.sha256` against what's on disk. A mismatch
means either the file was edited/re-downloaded since this snapshot, or
your checkout is missing it -- either way, don't trust a table built from
it without finding out which.
