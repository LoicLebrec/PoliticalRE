# Reproducibility package

Everything needed to regenerate all 15 tables in the paper
(`simple_regression/publication/textoverleaf/maintext.tex`) from the cleaned,
analysis-ready data. For how the raw data becomes these cleaned inputs
(download sources, cleaning scripts, provenance), see `/data_prep` at the
repo root instead -- this folder starts from already-cleaned data.

## Quick start

```
Rscript run_pipeline.R
```

Runs all 14 steps in order, stops on the first failure (a table is only
"reproduced" if every step before it succeeded -- see caveats). Steps 1-11
take ~3.5 minutes end to end; steps 12-14 (baseline pool + placebo
robustness tables) add a few more minutes.

Set `POLITICALRE_ROOT` if this repo isn't at the default path:
```
export POLITICALRE_ROOT=/path/to/repo
```

## Table -> script manifest

`table_manifest.csv` maps all 15 tables in the paper to the script that
produced them. Summary:

| Table label | What it is | Built by |
|---|---|---|
| `tab:cohorts` | Treatment cohorts (design table) | hand-written, no script |
| `tab:wind_stats` | Wind development descriptive stats | `descriptive/build_descriptive.R` |
| `tab:balance` | Treatment vs. control pre-treatment balance | `twfe/build_balance_table.R` |
| `tab:main_results` | Headline estimate, 3 methods | `build_main_results_table.R` |
| `tab:cs_anticipation` | CS anticipation-window sensitivity | `callaway_santanna/build_cs_eventstudy.R` |
| `tab:table_heckman_simple` | Heckman selection model | `heckman/build_heckman_simple.R` |
| `tab:baseline_results` | Headline estimate, baseline control pool | `build_baseline_results_table.R` |
| `tab:hetero_region` | Heterogeneity by region | `twfe/build_results_table.R` |
| `tab:hetero_size_income` | Heterogeneity by size/income/competitiveness | `twfe/build_results_table.R` |
| `tab:hetero_milestone_stability` | Heterogeneity by milestone/turnover/system/cohort | `twfe/build_results_table.R` |
| `tab:rob_d705` | Placebo: CADA (D705) opening | `robustness/build_results.R` |
| `tab:rob_desert` | Placebo: public-service desertification | `robustness/build_results.R` |
| `tab:rob_school` | Placebo: school closure | `robustness/build_results.R` |
| `tab:percode_abstention` | Abstention by facility type | `robustness/build_results.R` |
| `tab:table_ipw_selection` | IPW-weighted vs. unweighted reelection effect | `twfe/build_ipw_selection.R` |

All script paths in the table above are relative to
`simple_regression/publication/`.

## What's in `data/`

Frozen copies of the cleaned, analysis-ready datasets, as of this package's
creation date. These are what every publication script actually reads (via
their hardcoded paths into `simple_regression/panel/`,
`simple_regression/robsocioeco/data/`, `simple_regression/CRcreu11/data/` --
see caveat 3). Copied here so the inputs are documented and portable
without needing the full raw-data tree.

| File | Produced by | Notes |
|---|---|---|
| `panel.csv` | `panel/build_panel.R` | commune x election-year panel, base for every regression |
| `panel_maires.csv` | `enrich_panel_maires.R` | `panel.csv` + mayor biographical fields |
| `external_wind_voteshare.csv` | frozen snapshot, see caveat 1 / `data_prep` | `wind_speed_100m` + `voix_gagnant_mean/min/max`, merged into `panel.csv` by `build_panel.R` |
| `control_group_matched.csv` | `robsocioeco/build_control_new.R` | socio-economically matched never-treated pool |
| `control_group_baseline.csv` | unknown, see caveat 2 | unmatched never-treated pool (legacy); live path is `simple_regression/CRcreu11/data/control_group.csv` (confirmed byte-identical), renamed here for clarity |
| `turnover_candidats.csv` | not in this repo, see `data_prep` | candidate turnover by commune-year |
| `invest_communes_2013.csv` | not in this repo, see `data_prep` | municipal investment, 2013 baseline |

Steps 12-14 additionally read `data/BPE_adisp/derived/*_by_commune_year.csv`
directly from the live tree (not frozen here -- see `data_prep/README.md`
for what builds those and the one open gap in that chain).

## What's in `reference_output/`

Snapshot of the tables `run_pipeline.R` should reproduce, taken from a full
run of the live pipeline. Diff your own rerun's output against these:

| File | Compare against |
|---|---|
| `table_all_specs.csv` | `twfe/tables/table_all_specs.csv` |
| `table_all_specs_baseline.csv` | `twfe/tables/table_all_specs_baseline.csv` |
| `table_balance.csv` | `twfe/tables/table_balance.csv` |
| `table_heckman_simple.csv` | `heckman/tables/table_heckman_simple.csv` |
| `table_cs_summary.csv` | `callaway_santanna/tables/table_cs_summary.csv` |
| `table_descriptive_stats.csv` | `descriptive/tables/table_descriptive_stats.csv` |
| `table_main_results.csv` | `tables/table_main_results.csv` |
| `table_baseline_results.csv` | `tables/table_baseline_results.csv` |
| `table_d705_main.csv` | `robustness/tables/table_d705_main.csv` |
| `table_desert_main.csv` | `robustness/tables/table_desert_main.csv` |
| `table_school_main.csv` | `robustness/tables/table_school_main.csv` |
| `table_percode_abstention.csv` | `robustness/tables/table_percode_abstention.csv` |

Figures aren't snapshotted (PNGs don't diff meaningfully byte-for-byte
across machines/font rendering) -- if the tables above match, figures built
from the same numbers will too.

## Pipeline order (dependency graph)

```
1. build_panel.R                    -> panel/panel.csv
2. enrich_panel_maires.R            -> panel/panel_maires.csv          (needs 1)
3. robsocioeco/build_control_new.R  -> robsocioeco/data/control_group_new.csv   (needs 1)
4. twfe/build_robustness_combined.R -> data_results_all_specs*.csv, rob_all_combined*.png  (needs 1, 3)
                                        3 cohorts (A: 2008-2014, B: 2014-2020, C: 2020-2026) x 2 control
                                        pools = 6 result sets. Cohort B keeps unsuffixed filenames (main
                                        paper result); A/C get _cohortA/_cohortC suffixes (appendix).
5. twfe/build_master_singlepanel.R  -> rob_master_singlepanel.png      (needs 4; Cohort B only)
6. twfe/build_results_table.R       -> table_all_specs*.{csv,tex}      (needs 4)
7. twfe/build_balance_table.R       -> table_balance.{csv,tex}         (needs 1, 3)
8. heckman/build_heckman_simple.R   -> table_heckman_simple.*, fig_heckman_simple.png  (needs 1)
8b. twfe/build_ipw_selection.R      -> table_ipw_selection.{csv,tex}   (needs 1, 3, 4)
9. callaway_santanna/build_cs_eventstudy.R -> cs_eventstudy_combined.png, table_cs_summary.csv,
                                        table_cs_anticipation_sensitivity.csv  (needs 1, 3)
10. descriptive/build_descriptive.R  -> table_descriptive_stats.{csv,tex}, treatment_map.png
                                        (needs 1, 3; downloads+caches data/geo/departements.geojson on
                                        first run)
11. build_main_results_table.R       -> table_main_results.{csv,tex}   (needs 4, 8, 9)
12. build_baseline_results_table.R   -> table_baseline_results.{csv,tex}   (needs 4, 9)
13. robustness/build_control_groups.R -> control_group_{d705,desert,school}_cohort*.csv
                                        (needs 1, data/BPE_adisp/derived/*)
14. robustness/build_results.R       -> table_{d705,desert,school}_main.csv, table_percode_abstention.csv
                                        (needs 1, 13, data/BPE_adisp/derived/*, CRcreu11/data/turnover_candidats.csv)
```

Step 3 must run before 4/7/8b/9/10 -- skipping it leaves them running against
whatever `control_group_new.csv` happens to already be on disk (see caveat
3).

## Required R packages

Pinned in `renv.lock` at the project root. From the project root:

```r
install.packages("renv")
renv::restore()
```

Without renv, the minimum set is:

```r
install.packages(c("dplyr", "readr", "tidyr", "stringr", "fixest", "ggplot2",
                    "ggrepel", "readxl", "kableExtra", "sampleSelection",
                    "did", "marginaleffects", "jsonlite"))
```
but versions won't be pinned (caveat 4). `jsonlite` is used only by
`build_descriptive.R`'s treatment-map section. That script needs internet
on first run to download+cache `data/geo/departements.geojson` (~3.4MB,
one-time).

## Known caveats (read before trusting a from-scratch run)

**1. `external_wind_voteshare.csv` is a frozen external snapshot.**
`wind_speed_100m` and `voix_gagnant_mean/min/max` come from a source outside
this project -- no internal script computes them. Frozen in
`simple_regression/panel/external_wind_voteshare.csv` (checked into the
repo, 99.6% coverage, `code_insee` x `annee` keyed) and merged back into
`panel.csv` automatically as `build_panel.R`'s last step. If the true
source is ever identified, this file should be replaced with the real fetch
script -- see `data_prep/README.md`.

**2. `control_group_baseline.csv` (the "unmatched" control pool) is a
frozen legacy file**, not reproducible by any current script (no writer
script anywhere in the repo, including `archives/`; identical byte-for-byte
in `simple_regression/archives/CRcreu10/data/` and the live
`simple_regression/CRcreu11/data/` copy, so it predates even the oldest
archived pipeline generation; never tracked in git). Reverse-engineered as
far as the data supports: the rule "rural (density 5-7) in 2014, never
treated, present in the panel at all 4 election years" recovers 21,740 of
its 21,744 communes (99.98%), but over-generates by ~6,000 communes vs. an
unidentified extra filter. Internally consistent and safe to use as-is
(no communes in it are actually treated under the corrected treatment
definition), just not regeneratable from source.

**3. Scripts hardcode the project path**, with an env-var override.
The scripts `run_pipeline.R` calls read `PROJECT <- Sys.getenv(
"POLITICALRE_ROOT", unset = "/home/loiclebrec/ENRpolitical/Python/PoliticalRE")`
-- portable via `export POLITICALRE_ROOT=/path/to/repo`.
`run_pipeline.R` runs the live scripts in place against `$POLITICALRE_ROOT`
(or its default), not against this folder's `data/` copy -- that copy is a
reference snapshot for comparison, not the live input.

**4. Package version pinning matters in practice.** The `did` package's
`att_gt(base_period=...)` default changed the event-study x-axis
normalization silently between package versions during this project's
development. `renv.lock` (project root) pins every package version,
including `DRDID` (a GitHub dependency, not CRAN). Restore with
`renv::restore()` before running on a fresh machine.

**5. Treatment date definition.** `panel/build_panel.R` defines a commune as
"treated" from a wind park's *commissioning* date (`date_mise_en_service`
in `Parc.csv`), not its authorization or construction-start date.

**6. CS bootstrap seed.** `callaway_santanna/build_cs_eventstudy.R` sets
`set.seed(20260706)` once at the top -- reruns should be numerically
identical, not just similar.

**7. Steps 12-14 read `data/BPE_adisp/derived/*_by_commune_year.csv`
directly from the live tree**, not from a frozen copy in this folder (those
files total tens of MB and are themselves derived from restricted-access
BPE microdata -- see `data_prep/README.md`). If those derived files are
missing or the transform script that builds them from `labeled/` isn't
found, steps 12-14 will fail -- this is a known open gap, not a bug in
`run_pipeline.R`.
