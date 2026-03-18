library(httr)
library(xml2)
library(tidyverse)

pattern_enr <- regex(
    "éol|photovolta|solaire|méthan|biogas|autorisation environnementale|énergie renouvelable|parc éolien|aérogénérateur|éolienne",
    ignore_case = TRUE
)

# ─────────────────────────────────────────────
# 1. PARSER UN XML
# ─────────────────────────────────────────────
parse_xml <- function(xml_file) {
    tryCatch(
        {
            doc <- read_xml(xml_file)
            get_node <- function(xpath) xml_text(xml_find_first(doc, xpath), trim = TRUE)

            all_p <- xml_find_all(doc, "//Texte_Integral/p") |> xml_text(trim = TRUE)
            full_text <- paste(all_p, collapse = "\n")
            head_text <- paste(all_p[1:min(8, length(all_p))], collapse = " ")
            is_enr <- str_detect(full_text, pattern_enr)

            tibble(
                xml_path         = xml_file, # chemin complet — corrige le bug dirname
                fichier          = basename(xml_file),
                code_juridiction = get_node("//Code_Juridiction"),
                nom_juridiction  = get_node("//Nom_Juridiction"),
                numero_dossier   = get_node("//Numero_Dossier"),
                date_lecture     = get_node("//Date_Lecture"),
                type_recours     = get_node("//Type_Recours"),
                type_decision    = get_node("//Type_Decision"),
                solution         = get_node("//Solution"),
                formation        = get_node("//Formation_Jugement"),
                head_text        = head_text,
                is_enr           = is_enr,
                texte_integral   = if (is_enr) full_text else NA_character_
            )
        },
        error = function(e) NULL
    )
}

# ─────────────────────────────────────────────
# 2. TRAITER UN MOIS
# ─────────────────────────────────────────────
process_month <- function(juridiction, year, month) {
    # URL correcte selon juridiction
    prefix <- switch(juridiction,
        "CAA" = "DCA",
        "TA" = "DTA"
    )

    url <- sprintf(
        "https://opendata.justice-administrative.fr/%s/%d/%02d/%s_%d%02d.zip",
        prefix, year, month, juridiction, year, month
    )

    tmp_zip <- tempfile(fileext = ".zip")
    tmp_dir <- file.path(tempdir(), sprintf("%s_%d%02d", juridiction, year, month))
    dir.create(tmp_dir, showWarnings = FALSE)

    resp <- tryCatch(
        GET(url, write_disk(tmp_zip, overwrite = TRUE), timeout(180)),
        error = function(e) NULL
    )

    if (is.null(resp) || status_code(resp) != 200) {
        cat(
            juridiction, year, sprintf("%02d", month),
            "| HTTP", if (!is.null(resp)) status_code(resp) else "ERROR", "\n"
        )
        unlink(tmp_zip)
        return(NULL)
    }

    unzip(tmp_zip, exdir = tmp_dir, overwrite = TRUE)
    xml_files <- list.files(tmp_dir,
        pattern = "\\.xml$",
        full.names = TRUE, recursive = TRUE
    )

    if (length(xml_files) == 0) {
        unlink(tmp_dir, recursive = TRUE)
        unlink(tmp_zip)
        return(NULL)
    }

    meta <- map_dfr(xml_files, parse_xml)
    hits <- filter(meta, is_enr)

    cat(
        juridiction, year, sprintf("%02d", month),
        "| total:", nrow(meta), "| ENR:", nrow(hits), "\n"
    )

    # Nettoyage immédiat pour ne pas saturer /tmp
    unlink(tmp_dir, recursive = TRUE)
    unlink(tmp_zip)

    if (nrow(hits) == 0) {
        return(NULL)
    }

    # texte_integral déjà dans hits via parse_xml — pas besoin de relire
    hits
}

# ─────────────────────────────────────────────
# 3. LANCEMENT — toute la data disponible
# ─────────────────────────────────────────────

# Test rapide avant full grid
cat("=== TESTS ===\n")
process_month("CAA", 2022, 1)
process_month("TA", 2022, 1)

# Full grid — ajuster year_start si 404 systématique avant une date
grid <- bind_rows(
    expand_grid(juridiction = "CAA", year = 2022:2026, month = 1:12),
    expand_grid(juridiction = "TA", year = 2022:2026, month = 1:12)
)

cat("\n=== LANCEMENT FULL GRID —", nrow(grid), "mois ===\n")

results <- pmap_dfr(grid, function(juridiction, year, month) {
    process_month(juridiction, year, month)
})

cat("\nDécisions ENR trouvées:", nrow(results), "\n")
cat("dont CAA:", sum(results$code_juridiction != "TA", na.rm = TRUE), "\n")
cat("dont TA :", sum(results$code_juridiction == "TA", na.rm = TRUE), "\n")

PATH_OUT <- "/home/loiclebrec/ENRpolitical/Python/PoliticalRE/"
write_csv(results, paste0(PATH_OUT, "opendata_decisions_ENR.csv"), na = "")
cat("Export terminé.\n")
