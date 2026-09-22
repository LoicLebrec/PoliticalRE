# Data preparation

Where the raw data behind this paper comes from, and how it gets cleaned
into the inputs `/reproducibility` runs on. Read this if you want the full
chain from download to final table; skip straight to `/reproducibility` if
you're happy starting from already-cleaned data.

Every cleaning step is a script you can read in this repo's history, not a
hand-edit nobody can check. For the handful of files with no script
attached, `checksums.sha256` pins the exact bytes so you can at least
verify you're working from the same copy we did. Run
`bash verify_checksums.sh` to check.

## 1. Elections (municipal, 2008-2026)

The base panel, `election_data/VariablesY/variableY.csv`, is built by
`build_variableY.py` out of three election files (2008-2020 results from
the Ministry of the Interior + Wikipedia, candidate lists and round counts,
and the 2026 results) plus the INSEE commune reference and density grid
(§4). Municipal and legislative results generally come from data.gouv.fr's
static resource mirror -- you can see this pattern working in
`build_all_2024_2026.R`, which pulls the 2024 legislative results straight
from
`https://static.data.gouv.fr/resources/elections-legislatives-des-30-juin-et-7-juillet-2024-resultats-definitifs-du-1er-tour/20240711-075056/resultats-definitifs-par-communes.csv`.

Candidate/council turnover (`code/shared_data/turnover_candidats.csv`) is
computed, not downloaded: `build_turnover_candidats.py` looks at who ran in
2014/2020/2026 vs. the prior election and counts how many names changed.

`build_variableY.py` also fixes two things in the source data: it
recomputes `recandidature` properly (candidacy, not just reelection) and
recovers the real round count (`nb_tours`), both documented in the
script's header.

## 2. Mayors (biographical panel)

`data/maires_panel.csv` comes from the **Répertoire National des Élus**
(RNE), France's official register of elected officials:
https://www.data.gouv.fr/fr/datasets/donnees-du-repertoire-national-des-elus/.
It's built by `code/build_maires_panel.py`, which is honestly the
best-documented script in the whole project -- its docstring spells out
every input file and the merge/fallback logic between RNE vintages
(December 2025 primarily, 2019 and 2021 as fallback, plus 2025/2026 files).
Merged into the panel by `code/enrich_panel_maires.R`.

## 3. Wind installations

`data/parceolien/Parc.csv`, the wind park registry, comes from
**Géorisques**, via its WFS (map data) service rather than a plain file
download -- `code/shared_data/fetch_parc_georisques.py` hits it directly:
https://georisques.gouv.fr/services?SERVICE=WFS&VERSION=2.0.0&REQUEST=GetFeature&TYPENAMES=ms:parc_wfs&SRSNAME=urn:ogc:def:crs:EPSG::3857&OUTPUTFORMAT=CSV.
One request, no pagination, and the columns match Parc.csv exactly (26/26).
The registry updates daily, so a fresh pull won't be row-identical to any
older copy -- that's the live data changing, not a mismatch to chase.

A commune counts as "treated" from its first park's *commissioning* date,
not its authorization date -- see `/reproducibility/README.md` caveat 5.

`code/external_wind_voteshare.csv` has two columns of very different
provenance. `wind_speed_100m` is almost certainly from the **Global Wind
Atlas** (DTU / World Bank), which publishes exactly this kind of layer for
France at https://globalwindatlas.info/area/France -- no fetch script yet,
but the name and height match too well to be a coincidence.
`voix_gagnant_mean/min/max` is different: it's home-made, counted directly
from our own election data rather than downloaded from anywhere. The
script that did the counting didn't survive, so it can't be rebuilt
byte-for-byte yet, but there's no external source to chase here.

## 4. Geography / commune reference data

- INSEE's commune reference table (COG 2024):
  https://www.insee.fr/fr/statistiques/fichier/7766585/v_commune_2024.csv
  and the matching `v_mvt_commune_2024.csv`.
- INSEE's density grid (rural/urban classification):
  https://www.insee.fr/fr/information/8571524. We use the 2021 vintage.
- Department boundaries, from
  https://raw.githubusercontent.com/gregoiredavid/france-geojson/master/departements.geojson
  -- downloaded and cached automatically the first time the pipeline runs.
- Commune geocoding via `geo.api.gouv.fr/communes`, a free public API, used
  in some of the older enrichment scripts.
- FiLoSoFi (income, see §6): https://www.insee.fr/fr/metadonnees/source/serie/s1172.

## 5. BPE (facility closures/openings)

BPE stands for **Base Permanente des Équipements** -- INSEE's yearly census
of facilities and services (schools, hospitals, shops, public services...)
by commune. It's open data, published directly on data.gouv.fr:
https://www.data.gouv.fr/datasets/base-permanente-des-equipements. We use
it for the robustness placebo checks: school closures, CADA (asylum
reception center) openings, and a 12-facility "desertification" basket.

The files we actually have (`data/BPE_adisp/lil-XXXX.csv.zip`, one per
vintage from 2007 to 2020) are named after Progedo/ADISP catalogue IDs
rather than the data.gouv.fr filenames -- `lil-0423` is 2007, `lil-1444` is
2019, `lil-1483` is 2020, and so on
(https://data.progedo.fr/series/adisp/base-permanente-des-equipements-bpe).
Same underlying INSEE data, just pulled through a research-data portal
instead of data.gouv.fr directly, which is probably why it needed
registration rather than a plain download.

Turning the raw zips into `data/BPE_adisp/labeled/bpeXX_ensemble_labeled.csv`
still isn't scripted here. But the next step -- `labeled/` into the
`derived/*_by_commune_year.csv` files the pipeline actually reads (CADA
centers, elementary schools, maternity wards, the 12-facility basket) --
is: `code/build_bpe_derived.R` rebuilds all four, and its output matches
the checksummed files exactly (verified byte-for-byte before that script
was committed). The facility-code mapping it uses is the same one
`code/robustness/robustness_common.R` already had, since a couple of BPE
codes were renamed across vintages (2020's pharmacy code, 2025's several).

## 6. Income

FiLoSoFi (Fichier localisé social et fiscal) is INSEE's standard
commune-level median income figure --
https://www.insee.fr/fr/metadonnees/source/serie/s1172. We use the 2014
and 2017 snapshots as a baseline-income control in the TWFE robustness
grid and the Heckman selection model. Read from a raw INSEE download under
`election_data/data_quentin/2026/insee_raw/filosofi_series/`, not part of
this repo, no fetch script yet.

## 7. Municipal finance and intercommunality

Three files that feed the Heckman selection instrument:

**`code/shared_data/dette_communes.csv`** -- municipal debt, 2013, 2019 and
2024. `code/shared_data/fetch_dette_communes.py` rebuilds it from the
data.economie.gouv.fr API, dataset family
`balances-comptables-des-communes-en-{year}` -- run and checked: matches
the original to floating-point rounding (a handful of centimes off from
summation order, nothing structural).

**`code/shared_data/invest_communes_2013.csv` / `invest_communes_2019.csv`**
-- municipal investment, same years. `code/shared_data/fetch_invest_communes.py`
pulls the same API's immobilisation accounts (compte class 2) instead of
debt (compte 16x) -- same commune count as the original (36,681), values
close but consistently about 1% off, checked against a sample. So compte
class 2 is the right neighborhood but not the exact account scope the
original `invest_sd` used (probably needs some sub-accounts excluded --
amortization or financial placements are the likely candidates, not
capital spending). Left the script in even though it doesn't match yet:
it's a real starting point for whoever narrows this down, not a guess
from nothing.

**`code/shared_data/epci_communes_banatic.csv`** -- which intercommunality
group each commune belongs to. This is **BANATIC**, the government's own
database for this exact question: https://www.banatic.interieur.gouv.fr,
also listed on data.gouv.fr at
https://www.data.gouv.fr/datasets/banatic-base-nationale-sur-lintercommunalit
-- but neither one exposes a plain downloadable file or API; both hand you
an interactive query tool. No fetch script for this one; download it by
hand from either site.

**`code/shared_data/closeness.csv`** -- how close each election was, by
commune. Also home-made: `build_closeness.py` computes it from our own
election data (vote margins for list elections, seat-threshold margins for
majoritarian ones), nothing external to chase.

**`code/shared_data/control_group_baseline.csv`** -- the unmatched control
pool. No original script survives, but
`code/shared_data/build_control_group_baseline.R` rebuilds it from the
confirmed method: rural (INSEE density 5-7) and never treated, filtered
from our own panel -- the same two filters `code/build_control_group.R`
applies for the matched pool, just without that script's extra matching
step. Running it against the current panel recovers 21,740 of the
original file's 21,744 communes (99.98%) and lets through 5,827 more that
aren't in the original -- so this is the best-known reconstruction, not a
byte-for-byte match. Good enough to use as-is; there's one more filter in
the original nobody has identified.

Two files that used to be listed here turned out not to matter:
`data/WindFarm_France(Feuil1).csv` (superseded by `Parc.csv`, not even on
disk anymore) and the raw Global Wind Atlas raster,
`data/wind/FRA_wind-speed_100m.tif` -- not to be confused with
`wind_speed_100m` the *column* in `external_wind_voteshare.csv`, which we
do use, for control-group matching.

## What's still not scripted

Everything above either has a working fetch/build script now or a
confirmed source you can pull from by hand. Two things don't, and
probably won't without new information:

- **`epci_communes_banatic.csv`** -- BANATIC is confirmed, but the
  official site and its data.gouv.fr mirror are both query tools, not
  downloadable files. Checked the export page's underlying API namespace
  and its JS bundles for the actual data-fetch call -- it's a Next.js app,
  the real request most likely only fires after picking options and
  clicking "export" in the browser, not a plain URL.
- **`voix_gagnant_mean/min/max`** (in `external_wind_voteshare.csv`) and
  the extra ~5,800-commune gap in `control_group_baseline.csv` -- both
  have a confirmed method (home-made vote counting; a filter rule) but no
  surviving script to run. The numbers work, they're just not
  regeneratable from scratch without rewriting that logic.

## Checking your copy

```
cd data_prep
bash verify_checksums.sh
```

Checks every file in `checksums.sha256` against what's on disk. If
something doesn't match, either it got edited/re-downloaded since this
snapshot, or you're missing it -- either way, worth finding out before
trusting a table built from it.
