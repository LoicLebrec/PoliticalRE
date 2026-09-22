# Wind farms and local elections in France — replication package

Code to reproduce every table in the paper studying the local political
effects of communes building or planning wind farms. This is a trimmed,
publication-focused snapshot: exploratory analysis, drafts, and unrelated
side-projects from the working research repo are not included here.

## Start here

- **`/reproducibility`** — the 15 tables in the paper, mapped to the exact
  script that builds each one, plus a runnable pipeline (`run_pipeline.R`)
  and reference outputs to check your rerun against.
- **`/data_prep`** — where the raw data comes from, how it's cleaned, and
  checksums for every raw/frozen input, so the chain from download to
  final table is traceable end to end.

## What's in `simple_regression/`

The live analysis scripts `reproducibility/run_pipeline.R` actually calls:
panel construction (`panel/`, `enrich_panel_maires.R`), the matched control
group (`robsocioeco/`), the closeness-based selection model
(`morvan/run_morvan_competitif.R`), and the table-building scripts for each
method (`publication/{twfe,heckman,callaway_santanna,descriptive,
robustness}/`, plus the two cross-method summary tables at
`publication/build_main_results_table.R` and
`publication/build_baseline_results_table.R`). A handful of frozen data
files with no writer script (`CRcreu11/data/*.csv`) are included at the
paths these scripts expect them at — see `/data_prep` for what's known and
not known about their provenance.

Figures and the paper manuscript itself aren't included here — this
package is scoped to the tables.

## Requirements

R packages are pinned in `renv.lock`. See `/reproducibility/README.md` for
the full setup and known caveats before running anything end to end.
