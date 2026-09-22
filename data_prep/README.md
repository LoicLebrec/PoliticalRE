# Data preparation

This document describes the origin of the raw data used in this project
and the processing steps that produce the analysis-ready inputs consumed
by `/reproducibility`. Consult this document for the complete chain from
data acquisition to final table; consult `/reproducibility` alone to begin
from the cleaned inputs.

Every processing step is implemented as a versioned script and is
traceable in this repository's history. For the small number of files
with no corresponding script, `checksums.sha256` fixes the exact bytes so
that a copy can be verified against the version used in this analysis.
Run `bash verify_checksums.sh` to perform this check.

**Data access date.** The checksums in `checksums.sha256` were verified
current as of 2026-09-22; this is the effective accession date for every
frozen input in this document, absent a more specific date noted below.
`data/parceolien/Parc.csv` carries its own internal `date_maj`
(last-modified) field per record; the maximum value across all records in
the checksummed copy is 2026-03-16, indicating the snapshot was obtained
on or shortly after that date. Several sources in this document (notably
Géorisques and the data.economie.gouv.fr balances comptables API) are
updated by their publishers on an ongoing basis. Running the fetch
scripts described below retrieves data current as of the run date, which
will generally differ from the frozen snapshot checksummed here and used
to produce the results reported in the paper. Use the fetch scripts to
extend or update the analysis with newer data; use the checksummed files
as distributed to reproduce the paper's published results.

## 1. Elections (municipal, 2008-2026)

The base panel, `election_data/VariablesY/variableY.csv`, is constructed
by `build_variableY.py` from three election files (2008-2020 results from
the Ministry of the Interior and Wikipedia, candidate lists and round
counts, and the 2026 results), combined with the INSEE commune reference
table and density grid (Section 4). Municipal and legislative results
generally originate from data.gouv.fr's static resource mirror; this
pattern is implemented in `build_all_2024_2026.R`, which retrieves the
2024 legislative results from
`https://static.data.gouv.fr/resources/elections-legislatives-des-30-juin-et-7-juillet-2024-resultats-definitifs-du-1er-tour/20240711-075056/resultats-definitifs-par-communes.csv`.

Candidate and council turnover (`code/shared_data/turnover_candidats.csv`)
is computed rather than downloaded, but the surviving script does not
reproduce it. A script named `build_turnover_candidats.py` (present in
two copies in the full research repository, identical apart from output
path) computes turnover from candidate lists across consecutive
elections. Tested directly: its output uses different column semantics
(`n_candidats_t`/`n_candidats_prev`) and different values from the
checksummed file (`n_elus_t`/`n_elus_prev`), indicating the checksummed
file was built from elected-council rosters across all years, not
candidate lists, by a different, non-surviving script. This script is
not included in this repository, to avoid presenting a non-matching
computation as a working reconstruction.

`build_variableY.py` additionally corrects two errors present in the
source data: it recomputes `recandidature` (candidacy, as distinct from
reelection) and recovers the correct round count (`nb_tours`). Both
corrections are documented in the script header.

## 2. Mayors (biographical panel)

`data/maires_panel.csv` is derived from the **Répertoire National des
Élus** (RNE), France's official register of elected officials:
https://www.data.gouv.fr/fr/datasets/donnees-du-repertoire-national-des-elus/.
It is constructed by `code/build_maires_panel.py`, the most thoroughly
documented script in this project; its docstring specifies every input
file and the merge/fallback logic applied across RNE vintages (the
December 2025 snapshot as primary source, 2019 and 2021 as fallback, plus
2025/2026 files). It is merged into the panel by
`code/enrich_panel_maires.R`.

## 3. Wind installations

`data/parceolien/Parc.csv`, the wind park registry, is sourced from
**Géorisques** via its WFS (map data) service rather than a static file
download. `code/shared_data/fetch_parc_georisques.py` retrieves it
directly:
https://georisques.gouv.fr/services?SERVICE=WFS&VERSION=2.0.0&REQUEST=GetFeature&TYPENAMES=ms:parc_wfs&SRSNAME=urn:ogc:def:crs:EPSG::3857&OUTPUTFORMAT=CSV.
A single request returns the full dataset (no pagination required), and
the returned columns match `Parc.csv` exactly (26/26). The registry is
updated daily; a fresh pull will therefore not be row-identical to an
earlier copy. This reflects the underlying data changing over time, not
an inconsistency in the extraction method.

A commune is classified as treated from the *commissioning* date of its
first park, not its authorization date. See `/reproducibility/README.md`,
caveat 5.

`code/external_wind_voteshare.csv` contains two columns of distinct
provenance. `wind_speed_100m` is confirmed by the author to originate from
the **Global Wind Atlas** (DTU / World Bank), which publishes the
corresponding layer for France at
https://globalwindatlas.info/area/France. No extraction script exists for
this column: the source is a raster product, so reconstruction requires
downloading the GeoTIFF and performing a per-commune spatial extraction
rather than a direct file download. `voix_gagnant_mean/min/max` is the
national mean, minimum, and maximum of the winning candidate's vote count
for the corresponding election year, held constant across all communes in
that year. `code/shared_data/build_voix_gagnant_stats.R` recomputes these
three values from `election_data/VariablesY/variableY.csv` and reproduces
the existing file exactly (verified by identical checksum for all four
election years). This script updates only that column; `wind_speed_100m`
is left unchanged, as its extraction is not yet implemented.

## 4. Geography and commune reference data

- INSEE's commune reference table (COG 2024):
  https://www.insee.fr/fr/statistiques/fichier/7766585/v_commune_2024.csv
  and the corresponding `v_mvt_commune_2024.csv`.
- INSEE's density grid (rural/urban classification):
  https://www.insee.fr/fr/information/8571524. The 2021 vintage is used.
- Department boundaries:
  https://raw.githubusercontent.com/gregoiredavid/france-geojson/master/departements.geojson,
  downloaded and cached automatically on the first pipeline run.
- Commune geocoding via `geo.api.gouv.fr/communes`, a public API used by
  earlier enrichment scripts.
- FiLoSoFi (income; see Section 6):
  https://www.insee.fr/fr/metadonnees/source/serie/s1172.

## 5. BPE (facility openings and closures)

BPE denotes the **Base Permanente des Équipements**, INSEE's annual
census of facilities and services (schools, hospitals, retail, public
services) by commune. It is published as open data directly on
data.gouv.fr: https://www.data.gouv.fr/datasets/base-permanente-des-equipements.
It is used for the robustness placebo analyses: school closures, CADA
(asylum reception center) openings, and a 12-facility "desertification"
basket.

The raw files held in this project (`data/BPE_adisp/lil-XXXX.csv.zip`,
one per vintage from 2007 to 2020) are named according to Progedo/ADISP
catalogue identifiers rather than data.gouv.fr filenames: `lil-0423`
corresponds to 2007, `lil-1444` to 2019, `lil-1483` to 2020, and so on
(https://data.progedo.fr/series/adisp/base-permanente-des-equipements-bpe).
This is the same underlying INSEE data, obtained through a research-data
distribution portal rather than data.gouv.fr directly, which likely
accounts for the registration requirement.

The transform from raw archives to
`data/BPE_adisp/labeled/bpeXX_ensemble_labeled.csv` is not yet scripted
in this repository. The subsequent step, from `labeled/` to the
`derived/*_by_commune_year.csv` files consumed by the pipeline (CADA
centers, elementary schools, maternity wards, the 12-facility basket), is
implemented in `code/build_bpe_derived.R`, whose output was verified to
match the checksummed files exactly prior to being committed. The
facility-code mapping applied is identical to the one already present in
`code/robustness/robustness_common.R`, required because several BPE codes
were renamed across vintages.

## 6. Income

FiLoSoFi (Fichier localisé social et fiscal) is INSEE's standard
commune-level median disposable income measure:
https://www.insee.fr/fr/metadonnees/source/serie/s1172. The 2014 and 2017
snapshots are used as a baseline-income control in the TWFE robustness
grid and the Heckman selection model. These are read from a raw INSEE
download under `election_data/data_quentin/2026/insee_raw/filosofi_series/`,
not included in this repository; no extraction script exists yet.

## 7. Municipal finance and intercommunality

Four files feed the Heckman selection instrument.

**`code/shared_data/dette_communes.csv`** — municipal debt, 2013, 2019,
and 2024. `code/shared_data/fetch_dette_communes.py` reconstructs this
file from the data.economie.gouv.fr API, dataset family
`balances-comptables-des-communes-en-{year}`. The script was executed and
its output matches the original to floating-point rounding (differences
of a few centimes attributable to summation order, not a structural
discrepancy).

**`code/shared_data/invest_communes_2013.csv` /
`invest_communes_2019.csv`** — municipal investment, same years.
`code/shared_data/fetch_invest_communes.py` retrieves immobilisation
accounts (compte class 2) from the same API in place of debt (compte
16x). The reconstructed file has the same commune count as the original
(36,681) but values approximately 1% higher on average, checked against a
sample. Compte class 2 is therefore the correct account family but not
the exact scope used to construct the original `invest_sd` column; a
subset of sub-accounts (amortization or financial placements are
plausible candidates) likely requires exclusion. The script is retained
as a documented starting point despite not yet reproducing the original
file.

**`code/shared_data/epci_communes_banatic.csv`** — intercommunality
membership per commune, from **BANATIC**.
`code/shared_data/fetch_epci_banatic.py` retrieves this file from
data.gouv.fr's "Base nationale sur les intercommunalités" dataset,
resource `perimetre-epci-a-fp.csv`. The reconstructed file is confirmed
byte-for-byte identical to the existing file. The same dataset page also
provides BANATIC's official pre-generated export and a commune/SIREN
correspondence table, retained for reference.

**`code/shared_data/closeness.csv`** — electoral closeness by commune and
election. Not an external dataset: a candidate script, `build_closeness.py`,
derives a comparable measure from the project's own election data (vote
margins for list-system elections, seat-threshold margins for
majoritarian elections), but depends on additional source files not yet
located in this repository (a population comparateur extract, a separate
2020 seat-count file) and has not been tested against the checksummed
file. See Outstanding items below.

**`code/shared_data/control_group_baseline.csv`** — the unmatched control
pool. No original construction script survives. The general method is
confirmed and implemented in
`code/shared_data/build_control_group_baseline.R`: rural communes (INSEE
density 5-7) that were never treated, filtered from the project's own
panel — the same two filters applied by `code/build_control_group.R` for
the matched pool, without that script's subsequent matching step.
Applied to the current panel, this rule recovers 21,740 of the original
file's 21,744 communes (99.98% agreement) and additionally selects 5,827
communes not present in the original file. This constitutes the
best-available reconstruction rather than an exact match; one additional
filter present in the original construction has not been identified. Two
candidate explanations have been tested and rejected. A commune-fusion
hypothesis (that the discrepancy reflects communes excluded via the
`commune_fixe` flag used elsewhere in the pipeline) reduces the match
rate rather than improving it: 512 communes in the original file are
themselves not `commune_fixe == 1`. A department-treatment-count
hypothesis (applying the same "department with more than 3 treated
communes" filter that `code/build_control_group.R` uses for the matched
pool) reduces the match rate to 84.5%, indicating that this filter is
specific to the matched pool and not part of the baseline pool's
construction. The residual filter remains unidentified. The original
frozen file is retained as the authoritative input for all results
reported in the paper; the reconstruction script is retained as a
documented approximation, not a replacement.

Two files previously listed in this document were confirmed by the
author to be unused and were removed from the working tree:
`data/WindFarm_France(Feuil1).csv` (superseded by `Parc.csv`) and the raw
Global Wind Atlas raster, `data/wind/FRA_wind-speed_100m.tif`. Note that
this raster is distinct from `wind_speed_100m`, the column in
`external_wind_voteshare.csv`, which remains in use for control-group
matching.

## Outstanding items

Four items remain unresolved at the time of writing:

1. The extraction script for `wind_speed_100m` (Section 3). The source is
   confirmed (Global Wind Atlas); implementation requires a raster
   download and spatial join rather than a tabular fetch.
2. The residual filter accounting for the 5,827-commune discrepancy in
   `control_group_baseline.csv` (Section 7). Two candidate explanations
   (commune fusion, department treatment count) have been tested and
   ruled out (see above).
3. The construction script for `turnover_candidats.csv` (Section 1). A
   plausible candidate script was tested directly and found to compute a
   different quantity (candidate turnover, not elected-council turnover)
   than the checksummed file contains.
4. The construction script for `closeness.csv` (Section 7). A plausible
   candidate script exists but depends on additional source files (a
   population comparateur extract, a separate 2020 seat-count file) not
   yet located; it has not been tested and is not presented as verified.

None of these items affects the validity of the results reported in the
paper; all four concern exact reproducibility of auxiliary input files
from their original construction process.

## Verifying data integrity

```
cd data_prep
bash verify_checksums.sh
```

This command checks every file listed in `checksums.sha256` against the
corresponding file on disk. A mismatch indicates that the file has been
modified or re-downloaded since this snapshot, or is missing from the
current checkout. Any table built from a mismatched file should not be
trusted until the discrepancy is resolved.
