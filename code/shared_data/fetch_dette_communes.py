"""
Rebuilds dette_communes.csv (municipal debt, compte 16x "Emprunts et
dettes assimilees") from the data.economie.gouv.fr balances-comptables
API. Same source and logic as the project's original
dette_communes_desc.py, ported here with portable paths.

Usage (from the repo root): python3 code/shared_data/fetch_dette_communes.py
"""

import io
import os

import pandas as pd
import requests

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "dette_communes.csv")
BASE_URL = "https://data.economie.gouv.fr/api/explore/v2.1/catalog/datasets"
YEARS = [2013, 2019, 2024]


def fetch_compte(year: int, compte_prefix: str, field: str) -> pd.DataFrame:
    """Sum `field` (sd or sc) over accounts starting with compte_prefix,
    for the commune principal budget, for one year. Field/filter names
    changed once, in 2016 -- see the two branches below."""
    dataset = f"balances-comptables-des-communes-en-{year}"
    url = f"{BASE_URL}/{dataset}/records"

    if year >= 2016:
        where = f"startswith(compte,'{compte_prefix}') AND categ='Commune' AND cbudg='1'"
        ndept_3digit = True
    else:
        where = f"startswith(compte,'{compte_prefix}') AND type='Commune' AND budget='BP'"
        ndept_3digit = False

    export_url = url.replace("/records", "/exports/csv")
    params = {"where": where, "select": f"ndept,insee,{field}", "use_labels": "false"}
    r = requests.get(export_url, params=params, timeout=180, stream=True)
    r.raise_for_status()
    content = r.content.lstrip(b"\xef\xbb\xbf")  # strip BOM
    raw = pd.read_csv(io.BytesIO(content), sep=";", dtype={"ndept": str, "insee": str})
    raw[field] = pd.to_numeric(raw[field], errors="coerce").fillna(0)
    df = raw.groupby(["ndept", "insee"], as_index=False)[field].sum()

    if ndept_3digit:
        df["dep_str"] = df["ndept"].astype(str).str.lstrip("0").str.zfill(2)
        overseas = df["ndept"].astype(str).str.lstrip("0").isin(["971", "972", "973", "974", "976"])
        df.loc[overseas, "dep_str"] = df.loc[overseas, "ndept"].astype(str).str.lstrip("0")
    else:
        df["dep_str"] = df["ndept"].astype(str).str.zfill(2)
        overseas = df["ndept"].astype(str).isin(["971", "972", "973", "974", "976"])
        df.loc[overseas, "dep_str"] = df.loc[overseas, "ndept"].astype(str)

    df["com_str"] = df["insee"].astype(str).str.zfill(3)
    df["code_insee"] = df["dep_str"] + df["com_str"]
    df["year"] = year
    df["dette"] = df[field]
    return df[["code_insee", "year", "dette"]].copy()


if __name__ == "__main__":
    all_dette = pd.concat([fetch_compte(y, "16", "sc") for y in YEARS], ignore_index=True)
    all_dette.to_csv(OUT, index=False)
    print(f"Wrote {len(all_dette)} rows -> {OUT}")
