# Wind farms and local elections in France — replication package

This repository reproduces every table in the paper examining the local
political effects of communes that build or plan wind farms.

## Reproducing the tables

Raw data is not included in this repository and must be obtained first;
see `/data_prep` for sources, fetch scripts, and checksums. Once the raw
data is in place:

```
git clone <this repo>
cd PoliticalRE
Rscript -e 'install.packages("renv"); renv::restore()'
Rscript reproducibility/run_pipeline.R
```

This executes all pipeline steps in dependency order and halts on the
first failure. Total runtime is approximately 10 minutes given the raw
data is already present. See `reproducibility/README.md` for the complete
pipeline breakdown, requirements, and caveats that should be reviewed
before relying on a from-scratch run.

`reproducibility/table_manifest.csv` maps each of the paper's 15 tables
to the script that produces it. `reproducibility/reference_output/`
contains verified output for comparison against a subsequent run.

## Data sources

`/data_prep` documents every input consumed by this pipeline: its origin,
how to obtain it, how it is processed, and checksums to verify data
integrity. A small number of inputs lack a fully confirmed source or a
surviving construction script; these are disclosed explicitly in that
document rather than omitted.

## Repository layout

- `code/` — the analysis code: panel construction, control-group
  matching, and one subdirectory per method (`twfe/`, `heckman/`,
  `callaway_santanna/`, `descriptive/`, `robustness/`), each producing
  the tables attributed to it in the paper.
- `reproducibility/` — the table manifest, pipeline runner, and reference
  output described above.
- `data_prep/` — data sources and provenance, described above.

This repository is a trimmed, publication-scoped extract of a larger
research repository. Exploratory analysis, drafts, and unrelated
side-projects are not included.
