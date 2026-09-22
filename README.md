# Wind farms and local elections in France — replication package

Reproduces every table in the paper studying the local political effects
of communes building or planning wind farms.

## Reproduce the tables

```
git clone <this repo>
cd PoliticalRE
Rscript -e 'install.packages("renv"); renv::restore()'
Rscript reproducibility/run_pipeline.R
```

Runs all 14 build steps in dependency order and stops on the first
failure. Takes roughly 10 minutes end to end. See
`reproducibility/README.md` for the full pipeline breakdown, requirements,
and caveats worth reading before trusting a from-scratch run.

`reproducibility/table_manifest.csv` maps each of the paper's 15 tables to
the exact script that builds it, and `reproducibility/reference_output/`
has known-good output to diff your rerun against.

## Where the data comes from

`/data_prep` documents every input this pipeline reads: what it is, where
to download it, what cleans it, and checksums to verify you have the right
bytes. A few inputs have no confirmed source or writer script — those gaps
are disclosed there rather than hidden.

## Layout

- `code/` — the analysis: panel construction, control-group matching, and
  one subfolder per method (`twfe/`, `heckman/`, `callaway_santanna/`,
  `descriptive/`, `robustness/`), each producing the tables attributed to
  it in the paper.
- `reproducibility/` — the table manifest, pipeline runner, and reference
  output described above.
- `data_prep/` — data sources and provenance, described above.

This is a trimmed, publication-scoped snapshot of a larger research
repository: exploratory analysis, drafts, and unrelated side-projects are
not included.
