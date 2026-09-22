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
**Géorisques**'s "Éolien terrestre" database:
https://www.georisques.gouv.fr/donnees/bases-de-donnees/eolien-terrestre.
It's updated daily and downloadable as CSV/ZIP, nationally or by region.
There's no fetch script for it in this repo yet (only
`fetch_georisques_icpe.py`, which hits a related but different Géorisques
endpoint, the ICPE permits API) -- worth pinning the exact export date this
file was pulled on.

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

What's missing is the two cleaning steps in between: turning those raw
zips into `data/BPE_adisp/labeled/bpeXX_ensemble_labeled.csv`, and then
into the `derived/*_by_commune_year.csv` files the pipeline actually reads
(CADA centers, elementary schools, maternity wards, the 12-facility
basket). Neither transform script turned up anywhere in the repo. The
`derived/` files themselves are checksummed, so at least you can confirm
you're working from the same bytes, even without the script that made
them.

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

**`code/shared_data/dette_communes.csv`** -- municipal debt, 2013 and 2019.
This one's fully traced: `dette_communes_desc.py` pulls it straight from
the data.economie.gouv.fr API, dataset family
`balances-comptables-des-communes-en-{year}`, e.g.
https://data.economie.gouv.fr/api/explore/v2.1/catalog/datasets/balances-comptables-des-communes-en-2019/records
(swap the year for other vintages).

**`code/shared_data/invest_communes_2013.csv` / `invest_communes_2019.csv`**
-- municipal investment, same years. No script found for these, but
they're almost certainly the same data family as the debt figures above:
data.gouv.fr's "Comptes individuels des communes"
(https://www.data.gouv.fr/datasets/comptes-individuels-des-communes),
which keeps historical vintages back to 2012 as attachments on that same
page. Worth pulling the 2013/2019 files and diffing a few rows to confirm
before writing a fetch script.

**`code/shared_data/epci_communes_banatic.csv`** -- which intercommunality
group each commune belongs to. This is **BANATIC**, the government's own
database for this exact question: https://www.banatic.interieur.gouv.fr,
also mirrored on data.gouv.fr at
https://www.data.gouv.fr/datasets/banatic-base-nationale-sur-lintercommunalit.
The data.gouv.fr mirror is UTF-8 where our file is `latin1` -- might be
worth switching once someone confirms it's the same vintage.

**`code/shared_data/closeness.csv`** -- how close each election was, by
commune. Also home-made: `build_closeness.py` computes it from our own
election data (vote margins for list elections, seat-threshold margins for
majoritarian ones), nothing external to chase.

**`code/shared_data/control_group_baseline.csv`** -- the unmatched control
pool. No script survives, but the method is straightforward and confirmed:
filter our own commune-election panel down to communes that are rural
(INSEE density 5-7) and never treated -- exactly the same two filters
`code/build_control_group.R` applies for the matched pool, just without
that script's extra matching step. As a sanity check, applying that rule
by hand to the 2014 panel recovers 21,740 of this file's 21,744 communes
(99.98%), which confirms the method. About 6,000 communes it lets through
don't end up in the actual file, so there's one more filter in there we
haven't pinned down -- doesn't affect using the file, just means it's not
regeneratable byte-for-byte yet.

## Next steps

Roughly in order of how much they're worth doing:

1. Pin the exact `Parc.csv` export date/vintage from Géorisques and write
   a fetch script for it, same pattern as `fetch_georisques_icpe.py`.
2. Port `dette_communes_desc.py` into this package -- the source is
   already fully confirmed, it just needs to actually live here.
3. Download the 2013/2019 files from data.gouv.fr's "Comptes individuels
   des communes", confirm they match `invest_communes_2013/2019.csv`, and
   write a fetch script.
4. Check whether the BANATIC data.gouv.fr mirror matches
   `epci_communes_banatic.csv`'s vintage, and switch to it if so (it's
   UTF-8, ours is `latin1`).
5. Track down or rebuild the two missing BPE transform scripts
   (`lil-*.zip` -> `labeled/` -> `derived/`). Worth a last look outside
   this repo before rebuilding from scratch.
6. Figure out the extra filter behind `control_group_baseline.csv`'s
   ~6,000-commune gap. Not urgent -- the file works fine as-is, this is
   about full byte-for-byte reproducibility, not correctness.

Two files that used to be listed here turned out not to matter:
`data/WindFarm_France(Feuil1).csv` (superseded by `Parc.csv`, not even on
disk anymore) and the raw Global Wind Atlas raster,
`data/wind/FRA_wind-speed_100m.tif` -- not to be confused with
`wind_speed_100m` the *column* in `external_wind_voteshare.csv`, which we
do use, for control-group matching.

## Checking your copy

```
cd data_prep
bash verify_checksums.sh
```

Checks every file in `checksums.sha256` against what's on disk. If
something doesn't match, either it got edited/re-downloaded since this
snapshot, or you're missing it -- either way, worth finding out before
trusting a table built from it.
