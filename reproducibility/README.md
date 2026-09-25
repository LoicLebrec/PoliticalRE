# Reproducibility package

This package contains everything required to regenerate all 15 tables in
the paper from the cleaned, analysis-ready data in `/code`. For the
provenance of the raw data and the transformation from raw to cleaned
inputs, see `/data_prep` at the repository root.

## Quick start

This package presumes the raw data described in `/data_prep` is already
present at the paths that document specifies; it is not included in this
repository. With that in place, run from the repository root:

```
Rscript reproducibility/run_pipeline.R
```

This executes all 16 steps in dependency order and halts on the first
failure; a table is considered reproduced only if every preceding step
succeeded (see Caveats). Steps 1-11 require approximately 3.5 minutes;
steps 12-14 (baseline-pool and placebo robustness tables) add several
additional minutes.

Paths resolve relative to the repository root by default. Set
`POLITICALRE_ROOT` only if execution from a different working directory
is required:
```
export POLITICALRE_ROOT=/path/to/repo
```

## Table-to-script manifest

`table_manifest.csv` maps all 15 tables in the paper to the script that
produces each one. Summary (paths relative to `code/`):

| Table label | Description | Script |
|---|---|---|
| `tab:cohorts` | Treatment cohorts (design table) | not script-generated |
| `tab:wind_stats` | Wind development, descriptive statistics | `descriptive/build_descriptive.R` |
| `tab:balance` | Treatment vs. control pre-treatment balance | `twfe/build_balance_table.R` |
| `tab:main_results` | Headline estimate, three methods | `build_main_results_table.R` |
| `tab:cs_anticipation` | Callaway-Sant'Anna anticipation-window sensitivity | `callaway_santanna/build_cs_eventstudy.R` |
| `tab:table_heckman_simple` | Heckman selection model | `heckman/build_heckman_simple.R` |
| `tab:baseline_results` | Headline estimate, baseline control pool | `build_baseline_results_table.R` |
| `tab:hetero_region` | Heterogeneity by region | `twfe/build_results_table.R` |
| `tab:hetero_size_income` | Heterogeneity by size, income, competitiveness | `twfe/build_results_table.R` |
| `tab:hetero_milestone_stability` | Heterogeneity by milestone, turnover, electoral system, cohort | `twfe/build_results_table.R` |
| `tab:rob_d705` | Placebo: CADA (D705) opening | `robustness/build_results.R` |
| `tab:rob_desert` | Placebo: public-service desertification | `robustness/build_results.R` |
| `tab:rob_school` | Placebo: school closure | `robustness/build_results.R` |
| `tab:percode_abstention` | Abstention effect by facility type | `robustness/build_results.R` |
| `tab:table_ipw_selection` | IPW-weighted vs. unweighted reelection effect | `twfe/build_ipw_selection.R` |

## Inputs in `code/`

The shared inputs read by every script, at the paths expected:

| File | Produced by | Description |
|---|---|---|
| `code/panel.csv` | `code/build_panel.R` | commune x election-year panel, base for every regression |
| `code/panel_maires.csv` | `code/enrich_panel_maires.R` | `panel.csv` with mayor biographical fields |
| `code/external_wind_voteshare.csv` | see caveat 1 and `/data_prep` | `wind_speed_100m` and `voix_gagnant_mean/min/max`, merged into `panel.csv` by `build_panel.R` |
| `code/control_group_matched.csv` | `code/build_control_group.R` | socio-economically matched never-treated pool |
| `code/shared_data/control_group_baseline.csv` | see caveat 2 | unmatched never-treated pool |
| `code/shared_data/turnover_candidats.csv` | see `/data_prep` | candidate/council turnover by commune-year |
| `code/shared_data/invest_communes_2013.csv` / `invest_communes_2019.csv` | see `/data_prep` | municipal investment |
| `code/shared_data/dette_communes.csv` | see `/data_prep` | municipal debt |
| `code/shared_data/epci_communes_banatic.csv` | see `/data_prep` | intercommunality membership (BANATIC) |

Steps 13-14 additionally require
`data/BPE_adisp/derived/*_by_commune_year.csv`, located in the top-level
`data/` directory outside this repository. See `/data_prep/README.md` for
the construction of these files and the remaining gap in that chain.

## Contents of `reference_output/`

A snapshot of the tables that `run_pipeline.R` should reproduce, taken
from a verified full 15/15 run against the checksummed inputs pinned in
`/data_prep/checksums.sha256` (data access date 2026-09-22; see that
document for per-file detail). Run against those same frozen inputs, the
pipeline is numerically stable: N-treated counts and coefficients in
these reference tables match the paper's published numbers exactly, or
to within floating-point summation-order noise. A discrepancy larger than
that indicates a genuine problem and should be investigated.

Re-fetching `Parc.csv` or `dette_communes.csv` via the scripts in
`code/shared_data/` retrieves current data from sources the French
government updates on an ongoing basis, and will shift cohort composition
and downstream coefficients away from these reference values. This is
expected when deliberately pulling fresh data to extend the analysis, but
it means a rerun against re-fetched inputs should not be compared against
this reference snapshot; compare against a fresh run of the full pipeline
instead.

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
| `table_ipw_selection.csv` | `code/twfe/tables/table_ipw_selection.csv` |
| `table_cs_anticipation_sensitivity.csv` | `code/callaway_santanna/tables/table_cs_anticipation_sensitivity.csv` |
| `table_percode_abstention.csv` | `code/robustness/tables/table_percode_abstention.csv` |

Figures are not included in this snapshot, as PNG output does not compare
meaningfully byte-for-byte across machines or font rendering
environments. Agreement on the tables above implies agreement on figures
derived from the same underlying values.

## Pipeline order (dependency graph)

```
1.  code/build_panel.R                 -> code/panel.csv
2.  code/enrich_panel_maires.R         -> code/panel_maires.csv          (requires 1)
3.  code/build_control_group.R         -> code/control_group_matched.csv (requires 1)
4.  code/twfe/build_robustness_combined.R -> data_results_all_specs*.csv, rob_all_combined*.png  (requires 1, 3)
                                           3 cohorts (A: 2008-2014, B: 2014-2020, C: 2020-2026) x 2 control
                                           pools = 6 result sets. Cohort B retains unsuffixed filenames
                                           (main paper result); A/C receive _cohortA/_cohortC suffixes
                                           (appendix material).
5.  code/twfe/build_master_singlepanel.R  -> rob_master_singlepanel.png      (requires 4; Cohort B only)
6.  code/twfe/build_results_table.R       -> table_all_specs*.{csv,tex}      (requires 4)
7.  code/twfe/build_balance_table.R       -> table_balance.{csv,tex}         (requires 1, 3)
8.  code/heckman/build_heckman_simple.R   -> table_heckman_simple.*, fig_heckman_simple.png  (requires 1;
                                           sources code/heckman_selection_instrument.R)
8b. code/twfe/build_ipw_selection.R       -> table_ipw_selection.{csv,tex}   (requires 1, 3, 4)
9.  code/callaway_santanna/build_cs_eventstudy.R -> cs_eventstudy_combined.png, table_cs_summary.csv,
                                           table_cs_anticipation_sensitivity.csv  (requires 1, 3)
10. code/descriptive/build_descriptive.R  -> table_descriptive_stats.{csv,tex}, treatment_map.png
                                           (requires 1, 3; downloads and caches
                                           data/geo/departements.geojson on first run)
10b. code/descriptive/build_parks_evolution.R -> cumulative_parks_evolution.png (requires Parc.csv only)
11. code/build_main_results_table.R       -> table_main_results.{csv,tex}   (requires 4, 8, 9)
12. code/build_baseline_results_table.R   -> table_baseline_results.{csv,tex}   (requires 4, 9)
13. code/robustness/build_control_groups.R -> control_group_{d705,desert,school}_cohort*.csv
                                           (requires 1, data/BPE_adisp/derived/*)
14. code/robustness/build_results.R       -> table_{d705,desert,school}_main.csv, table_percode_abstention.csv
                                           (requires 1, 13, data/BPE_adisp/derived/*, code/shared_data/turnover_candidats.csv)
```

Step 3 must precede steps 4, 7, 8b, 9, and 10. Omitting it causes those
steps to run against whatever `control_group_matched.csv` is already
present on disk (see caveat 3).

## Required R packages

Package versions are pinned in `renv.lock` at the project root. From the
project root:

```r
install.packages("renv")
renv::restore()
```

Without renv, the minimum package set is:

```r
install.packages(c("dplyr", "readr", "tidyr", "stringr", "fixest", "ggplot2",
                    "ggrepel", "readxl", "kableExtra", "sampleSelection",
                    "did", "marginaleffects", "jsonlite"))
```
Versions will not be pinned under this approach (see caveat 4). `jsonlite`
is used only by the treatment-map section of `build_descriptive.R`, which
requires network access on first run to download and cache
`data/geo/departements.geojson` (approximately 3.4MB, one-time).

## Caveats

**1. `external_wind_voteshare.csv` is partially regenerable.**
`voix_gagnant_mean/min/max` is the national mean, minimum, and maximum of
the winning candidate's vote count for the corresponding election year.
`code/shared_data/build_voix_gagnant_stats.R` recomputes these values from
`election_data/VariablesY/variableY.csv` and reproduces the existing file
exactly. `wind_speed_100m` remains a frozen value with no extraction
script; its confirmed source is the Global Wind Atlas (see
`/data_prep`), but reconstruction requires a GeoTIFF download and a
per-commune spatial join rather than a tabular fetch.
`code/external_wind_voteshare.csv` (99.6% coverage, keyed on `code_insee`
x `annee`) is merged into `panel.csv` as the final step of
`build_panel.R`. No script currently regenerates this file end to end.

**2. `control_group_baseline.csv` is generated by a script, replacing a
frozen legacy file as of 2026-09-22.**
`code/shared_data/build_control_group_baseline.R` filters the project's
own panel to rural (density 5-7), never-treated communes present at all
4 election years, in a department with at least 3 wind parks recorded in
`Parc.csv` — the last filter recalled by the author specifically to close
a gap found by the first two filters alone. This does not byte-for-byte
reproduce the legacy file (no construction script for it survives), but
recovers 21,740 of its 21,744 communes (99.98%) and over-selects by only
934, versus 5,827 without the department filter.

The effect on published results was checked directly by rerunning the
full pipeline under each version of this rule against the legacy pool as
reference. Without the department filter, two numbers moved beyond
rounding noise: `tab:main_results`' Heckman Reelection coefficient lost
significance (-3.00\*, p=0.098 -> -2.60), and `tab:baseline_results`'
Callaway-Sant'Anna Abstention coefficient gained it in the opposite
direction (+0.352, p=0.109 -> +0.488, p=0.024). Adding the department
filter resolves the second (+0.348, p=0.112 -- matches the legacy pool to
within noise) and improves but does not fully resolve the first (-2.80,
closer to -3.00 but still short of p<0.10). Every other headline number
across all 15 tables now matches the legacy pool closely. The paper
reports the script-generated values: Heckman Reelection -2.80, not
significant (p=0.125), with the Heckman cohort sample sizes as produced
here -- see `/data_prep/README.md` for the full account. The legacy file is preserved at
`code/shared_data/control_group_baseline_legacy.csv` but is no longer
read by the pipeline.

**3. Scripts resolve paths relative to the repository root by default**,
with an environment-variable override for execution elsewhere:
`PROJECT <- Sys.getenv("POLITICALRE_ROOT", unset = ".")`.
`run_pipeline.R` executes the scripts in `code/` in place; run it, and
the scripts it calls, from the repository root, or set
`POLITICALRE_ROOT`.

**4. Package version pinning is material to the results.** The `did`
package's `att_gt(base_period=...)` default changed the event-study
x-axis normalization between package versions during development of this
project. `renv.lock` (project root) pins every package version, including
`DRDID` (a GitHub dependency not distributed via CRAN). Restore with
`renv::restore()` before running on a new machine.

**5. Treatment date definition.** `code/build_panel.R` defines a commune
as treated from the *commissioning* date of a wind park
(`date_mise_en_service` in `Parc.csv`), not its authorization or
construction-start date.

**6. Callaway-Sant'Anna bootstrap seed.**
`code/callaway_santanna/build_cs_eventstudy.R` sets `set.seed(20260706)`
once at the top of the script; reruns should be numerically identical,
not merely similar.

**7. Steps 13-14 require `data/BPE_adisp/derived/*_by_commune_year.csv`**,
located in the top-level `data/` directory outside this repository. The
transform from raw BPE archives to `data/BPE_adisp/labeled/` is not yet
scripted here (BPE is open data; see `/data_prep/README.md`). The
subsequent transform from `labeled/` to `derived/` is implemented in
`code/build_bpe_derived.R`; run it first if the derived files are
missing.
