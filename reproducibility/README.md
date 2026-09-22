# Reproducibility package

Everything needed to regenerate all 15 tables in the paper from the
cleaned, analysis-ready data in `/code`. For how the raw data becomes
those cleaned inputs (download sources, cleaning scripts, provenance),
see `/data_prep` at the repo root instead.

## Quick start

Run from the repo root:

```
Rscript reproducibility/run_pipeline.R
```

Runs all 14 steps in order, stops on the first failure (a table is only
"reproduced" if every step before it succeeded -- see caveats). Steps 1-11
take ~3.5 minutes end to end; steps 12-14 (baseline pool + placebo
robustness tables) add a few more minutes.

Paths are relative to the repo root by default. Set `POLITICALRE_ROOT` only
if you need to run from elsewhere:
```
export POLITICALRE_ROOT=/path/to/repo
```

## Table -> script manifest

`table_manifest.csv` maps all 15 tables in the paper to the script that
produced them. Summary (all paths relative to `code/`):

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

## What's in `code/`

The frozen/shared inputs every script reads, at the paths they expect:

| File | Produced by | Notes |
|---|---|---|
| `code/panel.csv` | `code/build_panel.R` | commune x election-year panel, base for every regression |
| `code/panel_maires.csv` | `code/enrich_panel_maires.R` | `panel.csv` + mayor biographical fields |
| `code/external_wind_voteshare.csv` | frozen snapshot, see caveat 1 / `/data_prep` | `wind_speed_100m` + `voix_gagnant_mean/min/max`, merged into `panel.csv` by `build_panel.R` |
| `code/control_group_matched.csv` | `code/build_control_group.R` | socio-economically matched never-treated pool |
| `code/shared_data/control_group_baseline.csv` | unknown, see caveat 2 | unmatched never-treated pool (legacy) |
| `code/shared_data/turnover_candidats.csv` | see `/data_prep` | candidate/council turnover by commune-year |
| `code/shared_data/invest_communes_2013.csv` / `invest_communes_2019.csv` | see `/data_prep` | municipal investment |
| `code/shared_data/dette_communes.csv` | see `/data_prep` | municipal debt |
| `code/shared_data/epci_communes_banatic.csv` | see `/data_prep` | intercommunality membership (BANATIC) |

Steps 13-14 additionally read `data/BPE_adisp/derived/*_by_commune_year.csv`
from the top-level `data/` directory (not part of this repo -- see
`/data_prep/README.md` for what builds those and the one open gap in that
chain).

## What's in `reference_output/`

Snapshot of the tables `run_pipeline.R` should reproduce, taken from a full
run of the pipeline. Diff your own rerun's output against these:

| File | Compare against |
|---|---|
| `table_all_specs.csv` | `code/twfe/tables/table_all_specs.csv` |
| `table_all_specs_baseline.csv` | `code/twfe/tables/table_all_specs_baseline.csv` |
| `table_balance.csv` | `code/twfe/tables/table_balance.csv` |
| `table_heckman_simple.csv` | `code/heckman/tables/table_heckman_simple.csv` |
| `table_cs_summary.csv` | `code/callaway_santanna/tables/table_cs_summary.csv` |
| `table_descriptive_stats.csv` | `code/descriptive/tables/table_descriptive_stats.csv` |
| `table_main_results.csv` | `code/tables/table_main_results.csv` |
| `table_baseline_results.csv` | `code/tables/table_baseline_results.csv` |
| `table_d705_main.csv` | `code/robustness/tables/table_d705_main.csv` |
| `table_desert_main.csv` | `code/robustness/tables/table_desert_main.csv` |
| `table_school_main.csv` | `code/robustness/tables/table_school_main.csv` |
| `table_percode_abstention.csv` | `code/robustness/tables/table_percode_abstention.csv` |

Figures aren't snapshotted (PNGs don't diff meaningfully byte-for-byte
across machines/font rendering) -- if the tables above match, figures built
from the same numbers will too.

## Pipeline order (dependency graph)

```
1.  code/build_panel.R                 -> code/panel.csv
2.  code/enrich_panel_maires.R         -> code/panel_maires.csv          (needs 1)
3.  code/build_control_group.R         -> code/control_group_matched.csv (needs 1)
4.  code/twfe/build_robustness_combined.R -> data_results_all_specs*.csv, rob_all_combined*.png  (needs 1, 3)
                                           3 cohorts (A: 2008-2014, B: 2014-2020, C: 2020-2026) x 2 control
                                           pools = 6 result sets. Cohort B keeps unsuffixed filenames (main
                                           paper result); A/C get _cohortA/_cohortC suffixes (appendix).
5.  code/twfe/build_master_singlepanel.R  -> rob_master_singlepanel.png      (needs 4; Cohort B only)
6.  code/twfe/build_results_table.R       -> table_all_specs*.{csv,tex}      (needs 4)
7.  code/twfe/build_balance_table.R       -> table_balance.{csv,tex}         (needs 1, 3)
8.  code/heckman/build_heckman_simple.R   -> table_heckman_simple.*, fig_heckman_simple.png  (needs 1;
                                           sources code/heckman_selection_instrument.R internally)
8b. code/twfe/build_ipw_selection.R       -> table_ipw_selection.{csv,tex}   (needs 1, 3, 4)
9.  code/callaway_santanna/build_cs_eventstudy.R -> cs_eventstudy_combined.png, table_cs_summary.csv,
                                           table_cs_anticipation_sensitivity.csv  (needs 1, 3)
10. code/descriptive/build_descriptive.R  -> table_descriptive_stats.{csv,tex}, treatment_map.png
                                           (needs 1, 3; downloads+caches data/geo/departements.geojson on
                                           first run)
11. code/build_main_results_table.R       -> table_main_results.{csv,tex}   (needs 4, 8, 9)
12. code/build_baseline_results_table.R   -> table_baseline_results.{csv,tex}   (needs 4, 9)
13. code/robustness/build_control_groups.R -> control_group_{d705,desert,school}_cohort*.csv
                                           (needs 1, data/BPE_adisp/derived/*)
14. code/robustness/build_results.R       -> table_{d705,desert,school}_main.csv, table_percode_abstention.csv
                                           (needs 1, 13, data/BPE_adisp/derived/*, code/shared_data/turnover_candidats.csv)
```

Step 3 must run before 4/7/8b/9/10 -- skipping it leaves them running
against whatever `control_group_matched.csv` happens to already be on disk
(see caveat 3).

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

**1. `external_wind_voteshare.csv` is half-regenerable.**
`voix_gagnant_mean/min/max` turned out to be just the national mean/min/max
of the winner's vote count per election year -- `code/shared_data/build_voix_gagnant_stats.R`
recomputes it from `election_data/VariablesY/variableY.csv` and matches
the existing file byte-for-byte. `wind_speed_100m` is still frozen, no
script -- probably the Global Wind Atlas (see `/data_prep`), just not
pinned down yet. Either way, `code/external_wind_voteshare.csv` (99.6%
coverage, keyed on `code_insee` x `annee`) is what `build_panel.R` merges
in as its last step; nothing regenerates it from scratch end to end yet.

**2. `control_group_baseline.csv` (the unmatched control pool) can't be
regenerated byte-for-byte, but `code/shared_data/build_control_group_baseline.R`
gets close.** It filters the project's own panel to rural (density 5-7),
never-treated communes -- the same two filters `code/build_control_group.R`
uses for the matched pool, just without that script's matching step.
Running it recovers 21,740 of the file's 21,744 communes (99.98%) and lets
through 5,827 more that aren't in the original -- so there's one more
filter nobody's identified yet. Doesn't affect using the frozen file as-is
(no treated communes are in it either way), just means it's not exactly
reproducible from scratch.

**3. Scripts resolve paths relative to the repo root by default**, with an
env-var override for running from elsewhere: `PROJECT <- Sys.getenv(
"POLITICALRE_ROOT", unset = ".")`. `run_pipeline.R` runs the scripts in
`code/` in place -- run it (and them) from the repo root, or set
`POLITICALRE_ROOT`.

**4. Package version pinning matters in practice.** The `did` package's
`att_gt(base_period=...)` default changed the event-study x-axis
normalization silently between package versions during this project's
development. `renv.lock` (project root) pins every package version,
including `DRDID` (a GitHub dependency, not CRAN). Restore with
`renv::restore()` before running on a fresh machine.

**5. Treatment date definition.** `code/build_panel.R` defines a commune as
"treated" from a wind park's *commissioning* date (`date_mise_en_service`
in `Parc.csv`), not its authorization or construction-start date.

**6. CS bootstrap seed.** `code/callaway_santanna/build_cs_eventstudy.R`
sets `set.seed(20260706)` once at the top -- reruns should be numerically
identical, not just similar.

**7. Steps 13-14 need `data/BPE_adisp/derived/*_by_commune_year.csv`**,
which lives in the top-level `data/` directory, not in this repo. Getting
the raw BPE zips into `data/BPE_adisp/labeled/` still isn't scripted here
(BPE is open data, see `/data_prep/README.md`), but `labeled/` into
`derived/` is: run `code/build_bpe_derived.R` first if those files are
missing.
