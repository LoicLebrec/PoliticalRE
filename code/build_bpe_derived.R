# Rebuilds data/BPE_adisp/derived/*_by_commune_year.csv from the raw BPE
# labeled files (data/BPE_adisp/labeled/bpeXX_ensemble_labeled.csv, plus
# the 2025 vintage in data/BPE_adisp/bpe2025/DS_BPE_CSV_FR.zip). Verified
# byte-for-byte against the checksummed files in data_prep/checksums.sha256
# before this script was written -- this is the actual transform, not a
# guess.
#
# Facility-type codes changed name across BPE vintages for some concepts
# (see the per-concept comment in code/robustness/robustness_common.R,
# bpe_codes_for_year() -- this script uses the same mapping):
#   D705 (CADA), D107 (maternite), C201 (college), D101/D102/D103
#     (hopital), D106 (urgences), A104 (gendarmerie) -- unchanged
#   C101 -> C107 (ecole maternelle, 2025)
#   C104 -> C108+C109 (ecole elementaire, 2025 -- the 2019+ reform split
#     it into "ecole primaire" + standalone "elementaire"; both count)
#   D201 -> D265 (medecin generaliste, 2025)
#   D301 -> D307 (pharmacie, 2020+)
#   A101 -> A140 (police, 2025)
#
# Output: one row per (code_insee, annee) with a nonzero count -- these
# are presence tables, not a zero-filled panel.
#
# Usage (from the repo root): Rscript code/build_bpe_derived.R

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(stringr)
})

PROJECT <- Sys.getenv("POLITICALRE_ROOT", unset = ".")
LABELED <- file.path(PROJECT, "data/BPE_adisp/labeled")
BPE25   <- file.path(PROJECT, "data/BPE_adisp/bpe2025/DS_BPE_CSV_FR.zip")
OUT     <- file.path(PROJECT, "data/BPE_adisp/derived")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

pad5 <- function(x) str_pad(x, 5, "left", "0")

load_year <- function(yr) {
  if (yr == 2025) {
    tmp <- tempfile(fileext = ".csv")
    unzip(BPE25, "DS_BPE_2025_data.csv", exdir = dirname(tmp))
    f <- file.path(dirname(tmp), "DS_BPE_2025_data.csv")
    read_delim(f, delim = ";", col_types = cols(.default = "c"), progress = FALSE) %>%
      filter(GEO_OBJECT == "COM") %>%
      transmute(code_insee = pad5(GEO), TYPEQU = FACILITY_TYPE,
                NB_EQUIP = as.integer(OBS_VALUE))
  } else {
    f <- file.path(LABELED, sprintf("bpe%02d_ensemble_labeled.csv", yr %% 100))
    read_delim(f, delim = ";", col_types = cols(.default = "c"), progress = FALSE) %>%
      transmute(code_insee = pad5(DEPCOM), TYPEQU, NB_EQUIP = as.integer(NB_EQUIP))
  }
}

YEARS <- c(2008, 2014, 2020, 2025)
YEAR_DATA <- setNames(lapply(YEARS, load_year), YEARS)

# codes_for(concept, yr): same mapping as robustness_common.R::bpe_codes_for_year
codes_for <- function(concept, yr) {
  switch(concept,
    d705          = "D705",
    d107          = "D107",
    c_maternelle  = if (yr >= 2025) "C107" else "C101",
    c_elementaire = if (yr >= 2025) c("C108", "C109") else "C104",
    c201          = "C201",
    d101          = "D101", d102 = "D102", d103 = "D103", d106 = "D106",
    d201          = if (yr >= 2025) "D265" else "D201",
    d301          = if (yr >= 2020) "D307" else "D301",
    a101          = if (yr >= 2025) "A140" else "A101",
    a104          = "A104",
    stop("unknown BPE concept: ", concept)
  )
}

# One (code_insee, annee, count) table per output, summing NB_EQUIP for the
# matching codes each year and keeping only communes with a nonzero count.
build_derived <- function(concepts, col_name) {
  bind_rows(lapply(YEARS, function(yr) {
    codes <- unlist(lapply(concepts, codes_for, yr = yr))
    YEAR_DATA[[as.character(yr)]] %>%
      filter(TYPEQU %in% codes) %>%
      group_by(code_insee) %>%
      summarise(n = sum(NB_EQUIP), .groups = "drop") %>%
      filter(n > 0) %>%
      transmute(code_insee, annee = yr, !!col_name := n)
  })) %>% arrange(code_insee, annee)
}

write_csv(build_derived("d705", "n_d705"),
          file.path(OUT, "d705_by_commune_year.csv"))
write_csv(build_derived("d107", "n_equip"),
          file.path(OUT, "D107_maternite_by_commune_year.csv"))
write_csv(build_derived("c_elementaire", "n_equip"),
          file.path(OUT, "C104_ecole_elementaire_by_commune_year.csv"))
write_csv(build_derived(
    c("a101", "a104", "c_maternelle", "c_elementaire", "c201",
      "d101", "d102", "d103", "d106", "d107", "d201", "d301"),
    "n_basket"),
  file.path(OUT, "public_service_basket_by_commune_year.csv"))

cat("Wrote 4 derived files to", OUT, "\n")
