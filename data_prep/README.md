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
every input is either (a) a script you can read, (b) a file with a
confirmed public source, or (c) a frozen file whose remaining provenance
gap is disclosed below, not hidden.

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
- **Candidate/council turnover**: `code/shared_data/turnover_candidats.csv`
  -- confirmed source, built by `build_turnover_candidats.py` (kept in the
  full research repo's history, not part of this package): for
  2014/2020/2026, computed from `elections_municipales_clean.csv` candidate
  lists (2026: from the RNE's full elected-council list) as the share of
  candidate names not present in the same commune the prior election.
- **Enrichment**: `build_variableY.py` also recomputes `recandidature`
  (candidacy, not just reelection) and `nb_tours` against
  `elections_municipales_clean.csv`, correcting bugs present in the
  original source notebook (documented in the script's own header).

## 2. Mayors (biographical panel)

- `data/maires_panel.csv`, built by `code/build_maires_panel.py`. This is
  the best-documented dataset in the repo -- its docstring lists every
  input file, date, and exact merge/fallback logic.
- Source: **Répertoire National des Élus** (RNE), published at
  `https://www.data.gouv.fr/fr/datasets/donnees-du-repertoire-national-des-elus/`
  (confirmed via `data/RNE/RNE/RNE 20XX/README.md`, which also has the
  scraper: `bash run.sh` after `pip3 install -r src/requirements.txt`).
- Vintages used: RNE Dec-2025 snapshot (primary, for 2020 cohort), RNE 2019
  and 2021 snapshots (fallback), plus 2025/2026 files under
  `election_data/data_quentin/`.
- Merged into the main panel by `code/enrich_panel_maires.R`.

## 3. Wind installations

- **Wind park registry**: `data/parceolien/Parc.csv` -- author-confirmed
  source: **Géorisques** (georisques.gouv.fr), same portal as the ICPE
  permits file below. No fetch script for this exact export is in this
  repo (only `fetch_georisques_icpe.py`, which hits a related but
  different endpoint -- see below); pin the exact Géorisques dataset/export
  used before treating this as a from-scratch download step.
- **Treatment definition**: a commune is "treated" from its first park's
  *commissioning* date (`date_mise_en_service`), computed in
  `code/build_panel.R` directly from `Parc.csv` -- deliberately not the
  authorization or construction-start date (see `/reproducibility/README.md`
  caveat 5).
- **ICPE permits (Géorisques)**: `data/parceolien/georisques_icpe_wind.csv`
  -- confirmed source, `data/parceolien/fetch_georisques_icpe.py` line 22:
  `https://georisques.gouv.fr/api/v1/installations_classees`. Run that
  script to regenerate; not part of the 15-table pipeline itself (used for
  cross-checking `Parc.csv`, see `join_coverage.R` in git history).
- **External wind-speed / vote-share snapshot**: `code/external_wind_voteshare.csv`
  -- two columns, two different confidence levels:
  - `wind_speed_100m`: very likely the **Global Wind Atlas** (DTU Technical
    University of Denmark / World Bank Group), which publishes a free
    100m-height wind speed layer for France at `globalwindatlas.info/area/France`.
    No fetch script for it exists in this repo, so this is not yet pinned
    to an exact export/version -- but the column name and height match
    exactly, and it's the standard free source for this kind of variable.
  - `voix_gagnant_mean/min/max`: **author-confirmed: home-made**, computed
    in-house by counting votes directly from this project's own election
    data (§1) -- not an external download. The exact aggregation script
    wasn't located in this repo, so it can't be regenerated byte-for-byte
    yet, but the source is internal and understood, not an unknown
    third-party dataset.
  - `build_panel.R` flags this with a `TODO` at the point it merges this
    file in, and kept the frozen file rather than silently regenerating
    `panel.csv` without these columns (which previously broke the
    pipeline once -- see `/reproducibility/README.md` caveat 1).

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
  source (3 build scripts, e.g. `build_parc_map.R` in the full research
  repo's history): `https://raw.githubusercontent.com/gregoiredavid/france-geojson/master/departements.geojson`,
  auto-downloaded and cached on first pipeline run.
- **Commune geocoding**: `geo.api.gouv.fr/communes` (public API, no key),
  used by historical enrichment scripts (full research repo history only).

## 5. Socio-demographic (BPE, facility closures/openings)

BPE = **Base Permanente des Équipements**, INSEE's national census of
facilities and services (schools, hospitals, shops, public services...) by
commune and year. Used here for the robustness placebo tests: school
closures, CADA (asylum reception center) openings, and a 12-facility
"desertification" basket.

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

## 6. Income (control variable)

- **FiLoSoFi** (Fichier localisé social et fiscal), INSEE's standard
  commune-level median disposable income product. Used by
  `code/twfe/build_robustness_combined.R` and
  `code/heckman_selection_instrument.R` as a baseline-income control
  (2014 and 2017 snapshots, `FILO_DISP_COM.xls` / `cc_filosofi_2017_COM.CSV`
  filenames match INSEE's own naming exactly). Read from
  `election_data/data_quentin/2026/insee_raw/filosofi_series/` -- not part
  of this repo (raw INSEE download), no fetch script found, standard public
  INSEE product available from insee.fr.

## 7. Municipal finance and intercommunality (Heckman selection instrument)

All four confirmed by web search against data.gouv.fr / the source portal
directly (not inferred from filenames alone):

- **`code/shared_data/dette_communes.csv`** -- municipal debt (compte 16x,
  "Emprunts et dettes assimilées"), 2013 and 2019 snapshots. Confirmed
  source and working script: `dette_communes_desc.py` (full research
  repo's history), which calls the **data.economie.gouv.fr API**,
  dataset family `balances-comptables-des-communes-en-{year}`
  (`https://data.economie.gouv.fr/api/explore/v2.1/catalog/datasets/...`).
- **`code/shared_data/invest_communes_2013.csv` / `invest_communes_2019.csv`**
  -- municipal investment spending, same years. No writer script found in
  this repo, but confirmed via web search: data.gouv.fr hosts "Comptes
  individuels des communes" (DGFiP source, aggregated by OFGL), the same
  underlying data family as the debt figures above, covering exactly this
  period and these fields. Treat as strongly likely but not script-pinned.
- **`code/shared_data/epci_communes_banatic.csv`** -- intercommunality
  (EPCI) membership and type per commune. Confirmed via web search:
  **BANATIC** ("Base Nationale sur l'Intercommunalité"), published by
  France's Direction Générale des Collectivités Locales at
  `banatic.interieur.gouv.fr`, also mirrored on data.gouv.fr as "Banatic -
  base nationale sur l'intercommunalité". No writer script in this repo,
  but the dataset itself is unambiguously identified.
- **`code/shared_data/closeness.csv`** -- electoral closeness/margin by
  commune and election, used as a competitiveness control in the same two
  scripts. Confirmed source and working script: `build_closeness.py` (full
  research repo's history), computed from `elections_municipales_clean.csv`
  (list-system vote margins) and the panel's own seat/candidate counts
  (majoritarian-system seat-threshold margins) -- no external dataset, pure
  derivation from data already documented in §1. Script not included in
  this package; the frozen output is checksummed.
- **`code/shared_data/control_group_baseline.csv`** -- unmatched
  ("baseline") never-treated control pool. No writer script survives, but
  the construction method is author-confirmed and explicit: filter the
  project's own commune-election panel (`election_data/data_quentin/` /
  `code/panel.csv`'s ancestor data) down to communes that are (a) rural
  (INSEE density category 5-7) and (b) never treated (no wind park in
  exploitation) -- the project's standard control-group filter pair, the
  same logic `code/build_control_group.R` applies for the matched pool.
  This is not an external dataset -- it's a filtered view of data already
  documented in §1, built by hand rather than a saved script. Independently
  reverse-engineered from the data itself: the rule "rural (density 5-7) in
  2014, never treated, present in the panel at all 4 election years"
  recovers 21,740 of its 21,744 communes (99.98% match, confirming the
  method above), but over-generates by ~6,000 communes vs. some additional
  unidentified filter -- so the general method is confirmed, exact
  byte-for-byte regeneration is not yet possible.

## Open gaps (confirm before treating as a clean from-scratch pipeline)

| File | Gap | Suggested next step |
|---|---|---|
| `data/parceolien/Parc.csv` | source confirmed (Géorisques), exact export/URL not pinned | pin the exact Géorisques dataset/export, add a fetch script |
| `data/BPE_adisp/lil-*.csv.zip` | access route inferred from filename only | confirm ADISP/Progedo registration path or public alternative |
| `data/BPE_adisp/labeled/*` | raw-to-labeled transform script missing | locate (may be in an untracked local copy) or rebuild |
| `data/BPE_adisp/derived/*` | labeled-to-derived transform script missing | same as above |
| `code/shared_data/invest_communes_2013.csv` / `_2019.csv` | plausible source identified (data.gouv.fr, OFGL/DGFiP), no writer script | pin the exact dataset/API call, add a fetch script |
| `code/shared_data/epci_communes_banatic.csv` | dataset identified (BANATIC), no writer script | pin the exact vintage/export used, add a fetch script |
| `code/shared_data/control_group_baseline.csv` | method confirmed, exact script lost | see explicit method notes above and reverse-engineering notes in `/reproducibility/README.md` |

Two files formerly listed here were confirmed unused by the author and
removed from tracking: `data/WindFarm_France(Feuil1).csv` (superseded by
`Parc.csv`, not present locally anymore) and `data/wind/FRA_wind-speed_100m.tif`
(the raw Global Wind Atlas raster -- note this is different from
`wind_speed_100m` the *column* in `code/external_wind_voteshare.csv`, which
**is** used, for control-group matching, and stays).

## Verifying you have the right bytes

```
cd data_prep
bash verify_checksums.sh
```

Checks every file in `checksums.sha256` against what's on disk. A mismatch
means either the file was edited/re-downloaded since this snapshot, or
your checkout is missing it -- either way, don't trust a table built from
it without finding out which.
