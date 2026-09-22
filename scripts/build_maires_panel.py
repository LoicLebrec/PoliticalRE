"""
Build mayor enrichment table for the panel.

Sources:
  - data/rne_archives/rne_maires_2019.txt.gz  : RNE July 2019 (2014-era mayors, tab-sep, Latin-1)
  - data/rne_archives/rne_maires_2021.csv.gz  : RNE April 2021 (2020-era mayors, tab-sep, UTF-8)
  - election_data/data_quentin/Archive/elus-maires-mai_dec2025.csv  : RNE Dec 2025 (2020-era + replacements, semicolons, UTF-8)
  - election_data/data_quentin/2026/rne/elus-maires-mai.csv          : RNE May 2026 (semicolons, UTF-8)
  - election_data/data_quentin/maires_entrantsortant_all_250124.csv  : Wikipedia name scrape (2001/2008/2014/2020)

Outputs:
  data/maires_panel.csv  — one row per (code_insee, annee)
  Columns: code_insee, annee, nom_entrant, prenom_entrant, date_naissance, annee_naissance,
           age_election, sexe, csp_code, source_rne

Logic:
  - Election 2020 → RNE Dec 2025 (primary) or 2021 (fallback): mandate_year 2020
  - Election 2026 → RNE May 2026: mandate_year 2026
  - Election 2014 → RNE 2019: mandate_year 2014 (still in office July 2019)
    + also people with mandate 2008 who are still there (rare)
  - Election 2008 → RNE 2019 mandate_year 2008 (survived to 2019) + Wikipedia names only

  Code INSEE construction:
    2019 file: dep (2-char) + code_commune (3-char zero-padded) = 5-char
    2021/2025 files: 5-char code directly in the commune column
"""

import gzip
import io
import re
import unicodedata
from pathlib import Path

import pandas as pd

ROOT = Path("/home/loiclebrec/ENRpolitical/Python/PoliticalRE")
DATA = ROOT / "data"
ELEC = ROOT / "election_data/data_quentin"

# ── helpers ────────────────────────────────────────────────────────────────────

def pad_insee(dep, commune):
    dep = str(dep).strip().zfill(2)
    commune = str(commune).strip().zfill(3)
    return dep + commune

def norm_insee(code):
    code = str(code).strip()
    if len(code) < 5:
        code = code.zfill(5)
    return code

def parse_date_naissance(s):
    """Return (year, month, day) or (None, None, None)."""
    s = str(s).strip()
    # Formats: 4/3/1951  04/03/1951  1951-03-04
    m = re.match(r'^(\d{1,2})[/\-](\d{1,2})[/\-](\d{4})$', s)
    if m:
        a, b, c = m.groups()
        # ambiguous: could be D/M/Y or M/D/Y but RNE uses D/M/Y
        return int(c), int(b), int(a)
    m = re.match(r'^(\d{4})[/\-](\d{2})[/\-](\d{2})$', s)
    if m:
        return int(m.group(1)), int(m.group(2)), int(m.group(3))
    return None, None, None

def parse_mandate_year(s):
    s = str(s).strip()
    m = re.search(r'(\d{4})', s)
    return int(m.group(1)) if m else None

# ── parse 2019 TXT (Latin-1, tab-sep, skip first 2 rows) ─────────────────────

def load_rne_2019():
    path = DATA / "rne_archives/rne_maires_2019.txt.gz"
    with gzip.open(path, 'rb') as f:
        raw = f.read().decode('latin-1')
    lines = raw.splitlines()
    # Row 0 = "Titre du rapport", Row 1 = header, Row 2+ = data
    header = lines[1].split('\t')
    # cols: dep, dep_lib, commune_code, commune_lib, nom, prenom, sexe, naissance, csp_code, csp_lib, debut_mandat, debut_fonction
    rows = []
    for line in lines[2:]:
        parts = line.split('\t')
        if len(parts) < 8:
            continue
        dep           = parts[0].strip()
        commune_code  = parts[2].strip()
        nom           = parts[4].strip()
        prenom        = parts[5].strip()
        sexe          = parts[6].strip()
        naissance     = parts[7].strip()
        csp_code      = parts[8].strip() if len(parts) > 8 else ''
        debut_mandat  = parts[10].strip() if len(parts) > 10 else ''

        code_insee = pad_insee(dep, commune_code)
        year_n, month_n, _ = parse_date_naissance(naissance)
        mandate_year = parse_mandate_year(debut_mandat)

        rows.append(dict(
            code_insee    = code_insee,
            nom           = nom,
            prenom        = prenom,
            sexe          = sexe,
            annee_naissance = year_n,
            csp_code      = csp_code,
            mandate_year  = mandate_year,
            source        = 'rne_2019'
        ))
    return pd.DataFrame(rows)

# ── parse 2021 CSV (UTF-8, tab-sep, first row = header) ──────────────────────

def load_rne_2021():
    path = DATA / "rne_archives/rne_maires_2021.csv.gz"
    with gzip.open(path, 'rb') as f:
        raw = f.read().decode('utf-8')
    lines = raw.splitlines()
    rows = []
    for line in lines[1:]:
        parts = line.split('\t')
        if len(parts) < 10:
            continue
        # dep, dep_lib, csp_code, csp_lib, commune_code, commune_lib, nom, prenom, sexe, naissance, csp_code2, csp_lib2, debut_mandat, debut_fonction
        commune_code = parts[4].strip()
        nom          = parts[6].strip()
        prenom       = parts[7].strip()
        sexe         = parts[8].strip()
        naissance    = parts[9].strip()
        csp_code     = parts[10].strip() if len(parts) > 10 else ''
        debut_mandat = parts[12].strip() if len(parts) > 12 else ''

        code_insee = norm_insee(commune_code)
        year_n, _, _ = parse_date_naissance(naissance)
        mandate_year = parse_mandate_year(debut_mandat)

        rows.append(dict(
            code_insee    = code_insee,
            nom           = nom,
            prenom        = prenom,
            sexe          = sexe,
            annee_naissance = year_n,
            csp_code      = csp_code,
            mandate_year  = mandate_year,
            source        = 'rne_2021'
        ))
    return pd.DataFrame(rows)

# ── parse semicolon-sep RNE (Dec 2025 and May 2026) ─────────────────────────

def load_rne_semicolon(path, source_label):
    df = pd.read_csv(path, sep=';', dtype=str, encoding='utf-8', on_bad_lines='skip')
    df.columns = [c.strip().strip('"') for c in df.columns]
    # Try to find columns by partial name
    def col(kw):
        for c in df.columns:
            if kw.lower() in c.lower():
                return c
        return None

    c_dep    = col('département') or col('departement')
    c_com    = col('commune')
    c_nom    = col('Nom')
    c_prenom = col('rénom') or col('Prenom') or col('Prénom')
    c_sexe   = col('sexe')
    c_naiss  = col('naissance')
    c_csp    = col('catégorie socio') or col('profession')
    c_mandat = col('début du mandat') or col('debut du mandat')

    rows = []
    for _, r in df.iterrows():
        commune_code = str(r.get(c_com, '') or '').strip().strip('"')
        nom          = str(r.get(c_nom, '') or '').strip().strip('"')
        prenom       = str(r.get(c_prenom, '') or '').strip().strip('"')
        sexe         = str(r.get(c_sexe, '') or '').strip().strip('"')
        naissance    = str(r.get(c_naiss, '') or '').strip().strip('"')
        csp_code     = str(r.get(c_csp, '') or '').strip().strip('"')
        debut_mandat = str(r.get(c_mandat, '') or '').strip().strip('"')

        if not commune_code or commune_code in ('nan', ''):
            continue
        code_insee = norm_insee(commune_code)
        year_n, _, _ = parse_date_naissance(naissance)
        mandate_year = parse_mandate_year(debut_mandat)

        rows.append(dict(
            code_insee    = code_insee,
            nom           = nom,
            prenom        = prenom,
            sexe          = sexe,
            annee_naissance = year_n,
            csp_code      = csp_code,
            mandate_year  = mandate_year,
            source        = source_label
        ))
    return pd.DataFrame(rows)

# ── Wikipedia name scrape ─────────────────────────────────────────────────────

def load_wikipedia_names():
    path = ELEC / "maires_entrantsortant_all_250124.csv"
    df = pd.read_csv(path, dtype=str)
    df = df.rename(columns={'INSEE': 'code_insee', 'year': 'annee'})
    df['code_insee'] = df['code_insee'].apply(norm_insee)
    df = df[df['code_insee'].notna() & (df['code_insee'] != 'nan')].copy()
    df['annee'] = pd.to_numeric(df['annee'], errors='coerce').astype('Int64')
    df = df[df['annee'].isin([2008, 2014, 2020, 2026])].copy()
    # Keep one row per commune×year (first)
    df = df.drop_duplicates(subset=['code_insee', 'annee'], keep='first')
    return df[['code_insee', 'annee', 'entrant', 'sortant']].copy()

# ── main ──────────────────────────────────────────────────────────────────────

print("Loading RNE archives...")
rne_2019 = load_rne_2019()
rne_2021 = load_rne_2021()
rne_2025 = load_rne_semicolon(
    ELEC / "Archive/elus-maires-mai_dec2025.csv", "rne_2025")
rne_2026 = load_rne_semicolon(
    ELEC / "2026/rne/elus-maires-mai.csv", "rne_2026")

for name, df in [("2019", rne_2019), ("2021", rne_2021), ("2025", rne_2025), ("2026", rne_2026)]:
    print(f"  {name}: {len(df)} rows  mandate_years={sorted(df['mandate_year'].dropna().unique().astype(int).tolist()[:10])}")

# Map RNE snapshot → election year:
#  2019 snapshot: trust mayors with mandate_year in {2014, 2008} still in office
#  2021 snapshot: mandate_year 2020
#  2025 snapshot: mandate_year 2020 (+ some 2021-2025 replacements → ignore, keep 2020)
#  2026 snapshot: mandate_year 2026

rne_by_election = pd.concat([
    rne_2019[rne_2019['mandate_year'].isin([2008, 2014])].assign(annee=lambda d: d['mandate_year']),
    rne_2021[rne_2021['mandate_year'] == 2020].assign(annee=2020),
    rne_2025[rne_2025['mandate_year'] == 2020].assign(annee=2020),
    rne_2026[rne_2026['mandate_year'] == 2026].assign(annee=2026),
], ignore_index=True)

# Deduplicate: for same code_insee + annee, prefer 2025 > 2021 > 2019 > 2026
source_priority = {'rne_2025': 1, 'rne_2021': 2, 'rne_2019': 3, 'rne_2026': 4}
rne_by_election['priority'] = rne_by_election['source'].map(source_priority)
rne_by_election = (rne_by_election
    .sort_values('priority')
    .drop_duplicates(subset=['code_insee', 'annee'], keep='first')
    .drop(columns='priority'))

# ── Load Wikipedia names ───────────────────────────────────────────────────────
print("Loading Wikipedia names...")
wiki = load_wikipedia_names()

# ── Merge ──────────────────────────────────────────────────────────────────────
print("Merging...")
rne_by_election['annee'] = rne_by_election['annee'].astype('Int64')
wiki['annee'] = wiki['annee'].astype('Int64')

result = wiki.merge(
    rne_by_election[['code_insee','annee','nom','prenom','sexe','annee_naissance','csp_code','source']],
    on=['code_insee','annee'],
    how='left'
)

# Age at election year
result['age_election'] = result.apply(
    lambda r: int(r['annee']) - int(r['annee_naissance'])
        if pd.notna(r['annee']) and pd.notna(r['annee_naissance']) else None,
    axis=1
)

# Coverage report
total = len(result)
has_birth = result['annee_naissance'].notna().sum()
print(f"\nCoverage: {has_birth}/{total} ({100*has_birth/total:.1f}%) have birth year")
print(result.groupby('annee')[['nom', 'annee_naissance']].apply(
    lambda g: pd.Series({'rows': len(g), 'pct_birth': 100*g['annee_naissance'].notna().mean()})
))

# ── Save ───────────────────────────────────────────────────────────────────────
out = DATA / "maires_panel.csv"
result.to_csv(out, index=False)
print(f"\nSaved → {out}")
print(result.head(10).to_string())

# ── Backfill 2008 from 2014 for re-elected mayors ─────────────────────────────
# If the 2008 entrant is the same person elected in 2014 (name match), borrow birth year.
df_2014 = result[result['annee'] == 2014][['code_insee', 'entrant', 'annee_naissance', 'nom', 'prenom', 'sexe', 'csp_code', 'source']].copy()
df_2014 = df_2014.rename(columns={
    'annee_naissance': 'annee_naissance_2014',
    'nom': 'nom_2014', 'prenom': 'prenom_2014',
    'sexe': 'sexe_2014', 'csp_code': 'csp_code_2014', 'source': 'source_2014'
})

df_2008 = result[result['annee'] == 2008].copy()
# Match: same commune, same entrant name
df_2008 = df_2008.merge(df_2014, on=['code_insee', 'entrant'], how='left')

# Fill missing birth years from 2014 match
mask = df_2008['annee_naissance'].isna() & df_2008['annee_naissance_2014'].notna()
for col in ['annee_naissance', 'nom', 'prenom', 'sexe', 'csp_code', 'source']:
    col2014 = col + '_2014' if col != 'nom' else 'nom_2014'
    col2014_map = {
        'annee_naissance': 'annee_naissance_2014', 'nom': 'nom_2014',
        'prenom': 'prenom_2014', 'sexe': 'sexe_2014',
        'csp_code': 'csp_code_2014', 'source': 'source_2014'
    }
    df_2008.loc[mask, col] = df_2008.loc[mask, col2014_map[col]]

df_2008['source'] = df_2008['source'].str.replace('rne_2019', 'rne_2019')
df_2008.loc[mask, 'source'] = 'rne_2019_backfill_from_2014'
df_2008['age_election'] = df_2008.apply(
    lambda r: int(r['annee']) - int(r['annee_naissance'])
        if pd.notna(r['annee']) and pd.notna(r['annee_naissance']) else None, axis=1)

# Drop helper columns
df_2008 = df_2008.drop(columns=[c for c in df_2008.columns if c.endswith('_2014')])

# ── Add remplace_mandat (mid-mandate replacement 2015-2019) ──────────────────
import gzip, re
rne_rows = []
with gzip.open(DATA / "rne_archives/rne_maires_2019.txt.gz", 'rb') as f:
    raw = f.read().decode('latin-1')
for line in raw.splitlines()[2:]:
    parts = line.split('\t')
    if len(parts) < 11:
        continue
    dep, com = parts[0].strip(), parts[2].strip().zfill(3)
    debut = parts[10].strip()
    yr = re.search(r'(\d{4})', debut)
    if yr:
        rne_rows.append({'code_insee': dep + com, 'mandate_year_2019': int(yr.group(1))})

rne_2019_df = pd.DataFrame(rne_rows)
remplace = rne_2019_df[rne_2019_df['mandate_year_2019'].between(2015, 2019)][['code_insee']].copy()
remplace['remplace_mandat_2014'] = 1

# ── Reassemble final result ───────────────────────────────────────────────────
result_others = result[result['annee'] != 2008]
result_final = pd.concat([df_2008, result_others], ignore_index=True)
result_final = result_final.merge(remplace, on='code_insee', how='left')
result_final['remplace_mandat_2014'] = result_final['remplace_mandat_2014'].fillna(0).astype(int)

# Final coverage
total = len(result_final)
has_birth = result_final['annee_naissance'].notna().sum()
print(f"\n=== Final coverage ===")
print(f"Total: {total}  with birth year: {has_birth} ({100*has_birth/total:.1f}%)")
print(result_final.groupby('annee')[['nom', 'annee_naissance']].apply(
    lambda g: pd.Series({'rows': len(g), 'pct_birth_pct': round(100*g['annee_naissance'].notna().mean(), 1)})
))

remplace_2014_communes = result_final[
    (result_final['annee'] == 2014) & (result_final['remplace_mandat_2014'] == 1)
]['code_insee'].nunique()
print(f"\nCommunes with mid-mandate replacement 2015-2019: {remplace_2014_communes}")

result_final.to_csv(out, index=False)
print(f"\nFinal saved → {out}  ({len(result_final)} rows)")
print(f"Columns: {list(result_final.columns)}")
