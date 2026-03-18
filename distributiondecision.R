library(httr)
library(xml2)
library(tidyverse)

pattern_enr <- regex(
    "éol|photovolta|solaire|méthan|biogas|autorisation environnementale|énergie renouvelable|parc éolien|aérogénérateur|éolienne",
    ignore_case = TRUE
)

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
                xml_path         = xml_file,
                fichier          = basename(xml_file),
                juridiction_type = if_else(str_detect(xml_file, "/TA_|/TA/"), "TA", "CAA"),
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

download_with_retry <- function(url, dest, timeout_s = 300, n_retry = 3) {
    for (i in seq_len(n_retry)) {
        resp <- tryCatch(
            GET(url, write_disk(dest, overwrite = TRUE), timeout(timeout_s)),
            error = function(e) NULL
        )
        if (!is.null(resp) && status_code(resp) == 200) {
            return(resp)
        }
        Sys.sleep(5 * i) # backoff
    }
    NULL
}

process_month <- function(juridiction, year, month) {
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

    resp <- download_with_retry(url, tmp_zip)

    if (is.null(resp)) {
        cat(juridiction, year, sprintf("%02d", month), "| ECHEC apres 3 tentatives\n")
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

    unlink(tmp_dir, recursive = TRUE)
    unlink(tmp_zip)

    if (nrow(hits) == 0) {
        return(NULL)
    }
    hits
}

# ── Grid : bornes réelles ──
grid <- bind_rows(
    expand_grid(juridiction = "CAA", year = 2022:2024, month = 1:12) |>
        filter(!(year == 2022 & month < 3)), # CAA démarre mars 2022
    expand_grid(juridiction = "TA", year = 2022:2024, month = 1:12) |>
        filter(!(year == 2022 & month < 6)) # TA démarre juin 2022
)


cat("=== LANCEMENT FULL GRID —", nrow(grid), "mois ===\n")

results <- pmap_dfr(grid, function(juridiction, year, month) {
    process_month(juridiction, year, month)
})

cat("\nDécisions ENR trouvées:", nrow(results), "\n")
cat("dont CAA:", sum(results$juridiction_type == "CAA", na.rm = TRUE), "\n")
cat("dont TA :", sum(results$juridiction_type == "TA", na.rm = TRUE), "\n")

PATH_OUT <- "/home/loiclebrec/ENRpolitical/Python/PoliticalRE/"
write_csv(results, paste0(PATH_OUT, "opendata_decisions_ENR.csv"), na = "")
cat("Export terminé.\n")
