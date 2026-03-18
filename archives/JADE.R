library(httr)
library(jsonlite)
library(dplyr)
library(stringr)

`%||%` <- function(a, b) if (!is.null(a)) a else b

# ---- 1. Token PRODUCTION ----
token_response <- POST(
  "https://oauth.piste.gouv.fr/api/oauth/token",
  body = list(
    grant_type    = "client_credentials",
    client_id     = "432fb3c1-7883-4810-bed5-e39a7a9b6ff8",
    client_secret = "82ef0348-f293-418b-86c4-f96bcbd76641",
    scope         = "openid"
  ),
  encode = "form"
)
token <- content(token_response)$access_token
cat("Token OK:", substr(token, 1, 20), "...\n")

headers <- add_headers(
  Authorization  = paste("Bearer", token),
  `Content-Type` = "application/json"
)

# ---- 2. Fetch page search ----
fetch_page <- function(page_number) {
  payload <- list(
    fond = "CETAT",
    recherche = list(
      champs = list(
        list(
          typeChamp = "ALL",
          criteres = list(
            list(
              typeRecherche = "TOUS_LES_MOTS_DANS_UN_CHAMP",
              valeur        = "autorisation environnementale éolien",
              operateur     = "ET"
            )
          ),
          operateur = "ET"
        )
      ),
      pageNumber = page_number,
      pageSize = 100,
      operateur = "ET",
      sort = "PERTINENCE",
      typePagination = "DEFAUT"
    )
  )
  resp <- POST(
    "https://api.piste.gouv.fr/dila/legifrance/lf-engine-app/search",
    headers,
    body   = toJSON(payload, auto_unbox = TRUE),
    encode = "raw"
  )
  if (status_code(resp) != 200) {
    cat("Erreur page", page_number, "- HTTP", status_code(resp), "\n")
    return(NULL)
  }
  content(resp, as = "text", encoding = "UTF-8")
}

# ---- 3. Fetch texte intégral ----
fetch_full_text <- function(id_cetat) {
  payload <- list(textId = id_cetat)
  resp <- POST(
    "https://api.piste.gouv.fr/dila/legifrance/lf-engine-app/consult/juri",
    headers,
    body   = toJSON(payload, auto_unbox = TRUE),
    encode = "raw"
  )
  if (status_code(resp) != 200) {
    return(NA_character_)
  }

  parsed <- fromJSON(content(resp, as = "text", encoding = "UTF-8"),
    simplifyVector = FALSE
  )

  # Cherche le texte dans toutes les clés possibles
  texte <- parsed$text$texte %||%
    parsed$text$content %||%
    parsed$texte %||%
    parsed$content %||%
    NA_character_

  as.character(texte)
}

# ---- 4. Extraire métadonnées ----
extract_metadata <- function(raw_json) {
  parsed <- fromJSON(raw_json, simplifyVector = FALSE)
  results <- parsed$results
  if (is.null(results) || length(results) == 0) {
    return(NULL)
  }

  bind_rows(lapply(results, function(r) {
    titles <- r$titles[[1]]

    id <- titles$id %||% NA_character_
    titre <- titles$titre %||% titles$title %||% NA_character_
    juridiction <- titles$juridiction %||% r$juridiction %||% NA_character_
    ville_juri <- titles$ville %||% r$ville %||% NA_character_
    date_decision <- titles$dateDecision %||% titles$date %||% NA_character_
    num_affaire <- titles$numeroAffaire %||% NA_character_
    au_recueil <- isTRUE(titles$publishedInRecueil)
    texte_extrait <- r$extract %||% NA_character_
    url <- paste0("https://www.legifrance.gouv.fr/ceta/id/", id)

    data.frame(
      id_cetat = id,
      titre = titre,
      juridiction = juridiction,
      ville_juri = ville_juri,
      date_decision = date_decision,
      num_affaire = num_affaire,
      au_recueil = au_recueil,
      texte_extrait = texte_extrait,
      url_decision = url,
      stringsAsFactors = FALSE
    )
  }))
}

# ---- 5. Collecte search ----
first_raw <- fetch_page(1)
first_json <- fromJSON(first_raw, simplifyVector = FALSE)
total <- first_json$totalResultNumber
n_pages <- ceiling(total / 100)
cat("Total:", total, "| Pages:", n_pages, "\n")

meta_list <- vector("list", n_pages)
meta_list[[1]] <- extract_metadata(first_raw)

for (p in seq(2, n_pages)) {
  cat("Page", p, "/", n_pages, "\r")
  raw <- fetch_page(p)
  if (!is.null(raw)) meta_list[[p]] <- extract_metadata(raw)
  Sys.sleep(0.4)
}

df_meta <- bind_rows(meta_list) |> distinct(id_cetat, .keep_all = TRUE)
cat("\nMétadonnées:", nrow(df_meta), "décisions\n")

# ---- 6. DEBUG structure JSON (1 seule décision) ----
cat("\n--- DEBUG structure JSON ---\n")
r_debug <- POST(
  "https://api.piste.gouv.fr/dila/legifrance/lf-engine-app/consult/juri",
  headers,
  body   = toJSON(list(textId = df_meta$id_cetat[1]), auto_unbox = TRUE),
  encode = "raw"
)
parsed_debug <- fromJSON(content(r_debug, as = "text", encoding = "UTF-8"),
  simplifyVector = FALSE
)
cat("Clés racine      :", paste(names(parsed_debug), collapse = ", "), "\n")
cat("Clés $text       :", paste(names(parsed_debug$text), collapse = ", "), "\n")

# ---- 7. Fetch textes intégraux ----
n <- nrow(df_meta)
textes_full <- vector("character", n)

for (i in seq_len(n)) {
  if (i %% 50 == 0) cat("Texte intégral", i, "/", n, "\n")
  textes_full[i] <- fetch_full_text(df_meta$id_cetat[i])
  Sys.sleep(0.4)
}

df_meta$texte_full <- textes_full

cat("\nTextes récupérés :", sum(!is.na(df_meta$texte_full)), "/", n, "\n")
cat("Longueur médiane :", median(nchar(df_meta$texte_full[!is.na(df_meta$texte_full)])), "car.\n")

# ---- 8. Aperçu ----
cat("\n--- Aperçu décision 1 ---\n")
cat(substr(df_meta$texte_full[1], 1, 800), "\n")

# ---- 9. Export ----
write.csv(df_meta, "jurisprudence_eolien_full.csv",
  row.names = FALSE, fileEncoding = "UTF-8"
)
cat("Export : jurisprudence_eolien_full.csv\n")
