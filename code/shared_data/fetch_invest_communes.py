"""
Rebuilds invest_communes_2013.csv / invest_communes_2019.csv (municipal
investment) from the data.economie.gouv.fr balances-comptables API --
same API and code pattern as fetch_dette_communes.py, immobilisation
accounts (compte class 2) instead of debt (compte 16x), debit balance
("sd", matching this file's own column name `invest_sd`) instead of
credit balance ("sc").

Unlike dette_communes.csv, this one does NOT reproduce the original file:
tested against invest_communes_2013.csv, it gets the same commune count
(36,681) but values consistently about 1% off, meaning compte class 2 is
too broad or the wrong subset. Left in as a starting point, not a working
fetch script yet -- see data_prep/README.md before trusting its output.

Usage (from the repo root): python3 code/shared_data/fetch_invest_communes.py
"""

import io
import os

import pandas as pd
import requests

OUT_DIR = os.path.dirname(os.path.abspath(__file__))
BASE_URL = "https://data.economie.gouv.fr/api/explore/v2.1/catalog/datasets"
YEARS = [2013, 2019]


def fetch_compte(year: int, compte_prefix: str, field: str) -> pd.DataFrame:
    dataset = f"balances-comptables-des-communes-en-{year}"
    url = f"{BASE_URL}/{dataset}/exports/csv"

    if year >= 2016:
        where = f"startswith(compte,'{compte_prefix}') AND categ='Commune' AND cbudg='1'"
        ndept_3digit = True
    else:
        where = f"startswith(compte,'{compte_prefix}') AND type='Commune' AND budget='BP'"
        ndept_3digit = False

    params = {"where": where, "select": f"ndept,insee,{field}", "use_labels": "false"}
    r = requests.get(url, params=params, timeout=300, stream=True)
    r.raise_for_status()
    content = r.content.lstrip(b"\xef\xbb\xbf")
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
    df["invest_sd"] = df[field]
    return df[["code_insee", "invest_sd"]].copy()


if __name__ == "__main__":
    for year in YEARS:
        df = fetch_compte(year, "2", "sd")
        out = os.path.join(OUT_DIR, f"invest_communes_{year}.csv")
        df.to_csv(out, index=False)
        print(f"{year}: wrote {len(df)} rows -> {out}")
