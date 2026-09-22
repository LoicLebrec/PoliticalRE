"""
Computes elected-council turnover per commune for 2014, 2020, 2026.
Verified byte-for-byte identical to the checksummed turnover_candidats.csv
(after CRLF normalization, applied automatically by git on commit) before
this script was ported into this package.

Majoritarian communes (fewer than 1,000 registered voters):
  Source: elections_municipales_clean.csv, rounds 1 and 2.
  Round-1 winners: candidates with votes > valid votes/2 AND
    votes >= 25% of registered voters.
  Uncontested: all round-1 candidates elected if their number does not
    exceed the council size.
  Round 2 fills any remaining seats (top vote-getters).
  Thin-council guard: if the reconstructed council is smaller than
    max(3, council_size // 2), the commune is likely a list-system
    commune with only list heads recorded, and is excluded.

List-system communes (1,000 or more registered voters):
  2014 council: from the "liste des élus" XLS files (Ministry of the
    Interior / data.gouv.fr), one row per elected councillor.
  2020 council: from maires_sortants_2026.csv, an RNE snapshot of all
    municipal councillors still in mandate as of the file's reference
    date (elected in 2020).
  2026 council: from t1_elus_all.csv, the full RNE extract following the
    2026 election.

Turnover is the share of names (normalized surname + given name) present
in a commune's council at year t that were not present at the prior
election (t-1). Pairs: 2014<-2008, 2020<-2014, 2026<-2020. For
list-system communes, 2014<-2008 is not computed (no 2008 list data).

Output: code/shared_data/turnover_candidats.csv

Usage (from the repository root): python3 code/shared_data/build_turnover_candidats.py
"""

import csv
import os
import unicodedata
from collections import defaultdict

import xlrd

PROJECT = os.environ.get("POLITICALRE_ROOT", ".")
ELEC_CSV = os.path.join(
    PROJECT, "election_data/data_quentin/elections_municipales_clean.csv",
    "elections_municipales_clean.csv",
)
RAW_2026 = os.path.join(PROJECT, "election_data/data_quentin/2026/raw")
ELUS_2026 = os.path.join(RAW_2026, "t1_elus_all.csv")
RNE_2020 = os.path.join(RAW_2026, "maires_sortants_2026.csv")
ELUS_2014 = [os.path.join(RAW_2026, f"elus_2014_{i}.xls") for i in range(1, 5)]
OUT_CSV = os.path.join(PROJECT, "code/shared_data/turnover_candidats.csv")

YEARS_ELEC = {"2008", "2014", "2020"}
INSCRITS_THRESHOLD = 1000.0


def normalize(s: str) -> str:
    s = unicodedata.normalize("NFD", s.strip().upper())
    return "".join(c for c in s if unicodedata.category(c) != "Mn")


def council_size(inscrits: float) -> int:
    pop = inscrits / 0.70
    if pop < 100: return 7
    if pop < 500: return 11
    if pop < 1500: return 15
    if pop < 2500: return 19
    if pop < 3500: return 23
    if pop < 5000: return 27
    if pop < 10000: return 29
    if pop < 20000: return 33
    if pop < 30000: return 35
    if pop < 40000: return 39
    if pop < 50000: return 43
    if pop < 60000: return 45
    if pop < 80000: return 49
    if pop < 100000: return 53
    return 55


def dpt_codcom_to_insee(dpt_raw, codcom_raw):
    try:
        dpt = str(dpt_raw).strip().rstrip(".0")
        cod = str(codcom_raw).strip().rstrip(".0")
        try:
            dpt = str(int(float(dpt))).zfill(2)
        except ValueError:
            dpt = dpt.upper()
        try:
            cod = str(int(float(cod))).zfill(3)
        except ValueError:
            return None
        return dpt + cod
    except Exception:
        return None


if __name__ == "__main__":
    names: dict[tuple[str, str], set[str]] = defaultdict(set)

    # ── Majoritarian communes: round 1 + round 2 reconstruction ──────────
    commune_inscrits: dict[tuple[str, str], float] = {}
    commune_exprimes: dict[tuple[str, str], float] = {}
    t1_cands: dict[tuple[str, str], list[tuple[str, float]]] = defaultdict(list)
    t2_cands: dict[tuple[str, str], list[tuple[str, float]]] = defaultdict(list)
    n_liste_skipped = 0

    with open(ELEC_CSV, encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            yr = row["Annee"]
            if yr not in YEARS_ELEC:
                continue
            tour = row["Tour"]
            key = (row["code_insee"], yr)

            if key not in commune_inscrits:
                try:
                    commune_inscrits[key] = float(row["Inscrits"])
                except (ValueError, KeyError):
                    commune_inscrits[key] = 0.0
            if key not in commune_exprimes and tour == "t1":
                try:
                    commune_exprimes[key] = float(row["Exprimés"])
                except (ValueError, KeyError):
                    commune_exprimes[key] = 0.0

            inscrits = commune_inscrits[key]
            if inscrits >= INSCRITS_THRESHOLD:
                if tour == "t1":
                    n_liste_skipped += 1
                continue

            nom = normalize(row.get("Nom", "") + " " + row.get("Prénom", ""))
            if not nom.strip():
                continue
            try:
                voix = float(row.get("Voix", 0) or 0)
            except ValueError:
                voix = 0.0

            if tour == "t1":
                t1_cands[key].append((nom, voix))
            elif tour == "t2":
                t2_cands[key].append((nom, voix))

    for key, cands_t1 in t1_cands.items():
        inscrits = commune_inscrits.get(key, 0.0)
        exprimes = commune_exprimes.get(key, 0.0)
        n_seats = council_size(inscrits) if inscrits > 0 else len(cands_t1)

        if len(cands_t1) <= n_seats:
            elected = {nom for nom, _ in cands_t1}
            if len(elected) < max(3, n_seats // 2):
                continue
            names[key].update(elected)
            continue

        elected_t1: set[str] = set()
        if exprimes > 0 and inscrits > 0:
            thr_maj = exprimes / 2.0
            thr_25 = 0.25 * inscrits
            for nom, voix in cands_t1:
                if voix > thr_maj and voix >= thr_25:
                    elected_t1.add(nom)

        if len(elected_t1) == 0:
            cands_sorted = sorted(cands_t1, key=lambda x: -x[1])
            names[key].update(nom for nom, _ in cands_sorted[:n_seats])
            continue

        n_remaining = n_seats - len(elected_t1)
        if n_remaining <= 0:
            names[key].update(elected_t1)
            continue

        cands_t2 = t2_cands.get(key, [])
        if cands_t2:
            cands_t2_sorted = sorted(cands_t2, key=lambda x: -x[1])
            elected_t2 = {nom for nom, _ in cands_t2_sorted[:n_remaining]}
            names[key].update(elected_t1 | elected_t2)
        else:
            not_el = sorted([(n, v) for n, v in cands_t1 if n not in elected_t1],
                             key=lambda x: -x[1])
            names[key].update(elected_t1 | {n for n, _ in not_el[:n_remaining]})

    # ── List-system communes, 2014: XLS files ─────────────────────────────
    for fpath in ELUS_2014:
        wb = xlrd.open_workbook(fpath)
        sh = wb.sheet_by_index(0)
        for r in range(1, sh.nrows):
            dpt = sh.cell_value(r, 0)
            codcom = sh.cell_value(r, 1)
            nom = str(sh.cell_value(r, 4)).strip()
            prenom = str(sh.cell_value(r, 5)).strip()
            code_insee = dpt_codcom_to_insee(dpt, codcom)
            if not code_insee or not nom:
                continue
            normalized = normalize(nom + " " + prenom)
            if normalized.strip():
                names[(code_insee, "2014_liste")].add(normalized)

    # ── List-system communes, 2020: RNE snapshot ──────────────────────────
    with open(RNE_2020, encoding="utf-8") as f:
        reader = csv.DictReader(f, delimiter=";")
        for row in reader:
            code_insee = row.get("Code de la commune", "").strip()
            nom = row.get("Nom de l'élu", "").strip()
            prenom = row.get("Prénom de l'élu", "").strip()
            if not code_insee or not nom:
                continue
            normalized = normalize(nom + " " + prenom)
            if normalized.strip():
                names[(code_insee, "2020_liste")].add(normalized)

    # ── All communes, 2026: full RNE extract ──────────────────────────────
    with open(ELUS_2026, encoding="utf-8") as f:
        reader = csv.reader(f, delimiter=";")
        next(reader)
        for row in reader:
            if len(row) < 8:
                continue
            code_insee = row[7]
            nom = normalize(row[0] + " " + row[1])
            if nom.strip() and code_insee:
                names[(code_insee, "2026")].add(nom)

    # ── Turnover ───────────────────────────────────────────────────────────
    def get_council(insee: str, year: str) -> set:
        direct = names.get((insee, year), set())
        liste = names.get((insee, f"{year}_liste"), set())
        return direct | liste

    all_keys: set[tuple[str, str]] = set()
    for (insee, yr) in names:
        canon = yr.replace("_liste", "")
        all_keys.add((insee, canon))

    PAIRS = [("2014", "2008"), ("2020", "2014"), ("2026", "2020")]

    rows_out = []
    for (insee, canon_yr) in sorted(all_keys):
        for t, t_prev in PAIRS:
            if canon_yr != t:
                continue
            elus_t = get_council(insee, t)
            elus_prev = get_council(insee, t_prev)
            if not elus_t or not elus_prev:
                continue
            n_new = len(elus_t - elus_prev)
            n_t = len(elus_t)
            turnover_pp = round(100 * n_new / n_t, 4) if n_t > 0 else None
            rows_out.append({
                "code_insee": insee,
                "annee": int(t),
                "n_elus_t": n_t,
                "n_elus_prev": len(elus_prev),
                "n_nouveau": n_new,
                "turnover_pp": turnover_pp,
            })

    with open(OUT_CSV, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows_out[0].keys()))
        writer.writeheader()
        writer.writerows(rows_out)

    print(f"Wrote {len(rows_out)} rows -> {OUT_CSV}")
