"""
Electoral closeness per commune and election year, for two regimes that
are not directly comparable:

- List-system (proportional): margin = pct_votes(list 1) - pct_votes(list 2),
  as a percentage of valid votes. Same formula for 2008/2014/2020.
- Majoritarian (individuel, plurinominal with panachage): no top1-top2
  margin (not meaningful in a multi-member contest). Instead:
    * 2014/2020: seat-threshold margin, votes[rank=seats] -
      votes[rank=seats+1] -- the margin between the last seat won and the
      first seat lost. mono_liste = candidate count <= seats required
      (no seat actually contested).
    * 2008 only: the source (elections_municipales_clean.csv) records
      only elected candidates for this year/regime, so the seat-threshold
      candidate is not in the data. Falls back to
      100 - (winner's share of valid votes), which depends only on the
      winner and the valid-vote total, not on enumerating all candidates.

nb_sieges_requis (council size, needed for the majoritarian seat-cutoff
margin) is reconstructed from population (CGCT art. L2121-2) for
2008/2014. For 2020, real elected-council counts from the Repertoire
National des Elus are used instead (data.cquest.org archive, snapshot
2020-12-02, conseil municipal roster) -- validated against the
population-based model first: 88.3% exact match on 34,396 comparable
communes, confirming the model is a reasonable but imperfect proxy, with
real data used wherever available. No equivalent real source exists for
2008/2014 (RNE itself did not yet exist; data.gouv.fr's "liste-des-maires"
2014 file covers mayors only, not full council rosters).

Output: code/shared_data/closeness.csv
  (code_insee, annee, type_scrutin, n_unites, mono_liste, closeness, method)

Usage (from the repository root): python3 code/shared_data/build_closeness.py
"""

import os

import numpy as np
import pandas as pd

PROJECT = os.environ.get("POLITICALRE_ROOT", ".")
RAW = os.path.join(
    PROJECT, "election_data/data_quentin/elections_municipales_clean.csv",
    "elections_municipales_clean.csv",
)
PANEL = os.path.join(PROJECT, "code/panel.csv")
COMP = os.path.join(PROJECT, "election_data/data_quentin/2026/insee_raw/comparateur/base_cc_comparateur.csv")
REAL_SEATS_2020 = os.path.join(PROJECT, "code/shared_data/real_seats_2020.csv")
OUT = os.path.join(PROJECT, "code/shared_data/closeness.csv")

YEARS = [2008, 2014, 2020]


def nb_sieges(pop, annee):
    """Legal municipal council size (CGCT art. L2121-2)."""
    if pd.isna(pop):
        return np.nan
    pop = int(pop)
    if annee <= 2008:
        table = [(100, 9), (500, 11), (1500, 15), (2500, 19), (3500, 23),
                 (5000, 27), (9000, 29)]
        default = 33
    else:
        table = [(100, 7), (500, 11), (1500, 15), (2500, 19), (3500, 23),
                  (5000, 27), (9000, 29), (30000, 33), (40000, 35),
                  (50000, 43), (80000, 45), (100000, 49), (150000, 53),
                  (250000, 55), (300000, 59), (500000, 61)]
        default = 65
    for thresh, seats in table:
        if pop < thresh:
            return seats
    return default


if __name__ == "__main__":
    print("Loading raw candidate/list-level results...")
    raw = pd.read_csv(RAW, usecols=["code_insee", "Annee", "Tour", "Exprimés", "Voix"],
                       dtype=str)
    raw = raw.rename(columns={"Annee": "annee", "Tour": "tour",
                              "Exprimés": "exprimes", "Voix": "voix"})
    raw["code_insee"] = raw["code_insee"].str.strip().str.zfill(5)
    raw["annee"] = pd.to_numeric(raw["annee"], errors="coerce")
    raw["tour"] = pd.to_numeric(raw["tour"].str.extract(r"(\d+)", expand=False), errors="coerce")
    raw["voix"] = pd.to_numeric(raw["voix"], errors="coerce")
    raw["exprimes"] = pd.to_numeric(raw["exprimes"], errors="coerce")
    raw = raw.dropna(subset=["annee", "tour", "voix", "exprimes"])
    raw = raw[raw["annee"].isin(YEARS)]
    raw["annee"] = raw["annee"].astype(int)

    raw["last_tour"] = raw.groupby(["code_insee", "annee"])["tour"].transform("max")
    raw = raw[raw["tour"] == raw["last_tour"]]
    print(f"  {len(raw):,} rows, {raw.groupby('annee').size().to_dict()}")

    print("Loading type_scrutin from panel...")
    panel_ts = pd.read_csv(PANEL, usecols=["code_insee", "annee", "type_scrutin"],
                            dtype={"code_insee": str})
    panel_ts = panel_ts[panel_ts["annee"].isin(YEARS)].drop_duplicates(["code_insee", "annee"])

    print("Loading population (comparateur INSEE) for nb_sieges_requis...")
    comp = pd.read_csv(COMP, sep=";", dtype={"CODGEO": str}, usecols=["CODGEO", "P16_POP"])
    comp["code_insee"] = comp["CODGEO"].str.strip().str.zfill(5)
    comp["pop"] = pd.to_numeric(comp["P16_POP"], errors="coerce")
    comp = comp[["code_insee", "pop"]]

    meta = panel_ts.merge(comp, on="code_insee", how="left")
    meta["nb_sieges_requis"] = meta.apply(lambda r: nb_sieges(r["pop"], r["annee"]), axis=1)

    print("Loading real 2020 seat counts (RNE, elected council roster)...")
    real_2020 = pd.read_csv(REAL_SEATS_2020, dtype={"code_insee": str})
    n_model_2020 = (meta["annee"] == 2020).sum()
    meta = meta.merge(real_2020, on="code_insee", how="left")
    is_2020 = meta["annee"] == 2020
    meta["seats_source"] = "model"
    meta.loc[is_2020 & meta["seats_real_2020"].notna(), "seats_source"] = "rne_real"
    n_real_used = meta.loc[is_2020, "seats_real_2020"].notna().sum()
    meta.loc[is_2020, "nb_sieges_requis"] = meta.loc[is_2020, "seats_real_2020"].combine_first(
        meta.loc[is_2020, "nb_sieges_requis"])
    meta = meta.drop(columns=["seats_real_2020"])
    print(f"  2020 : {n_real_used}/{n_model_2020} communes use REAL RNE seat counts "
          f"(rest fall back to the population-based model)")

    raw = raw.merge(meta[["code_insee", "annee", "type_scrutin", "nb_sieges_requis", "seats_source"]],
                    on=["code_insee", "annee"], how="left")
    raw = raw.dropna(subset=["type_scrutin"])

    def closeness_liste(g):
        v = g["voix"].sort_values(ascending=False).values
        n = len(v)
        exprimes = g["exprimes"].iloc[0]
        if n <= 1:
            return pd.Series({"n_unites": n, "mono_liste": 1, "closeness": np.nan, "method": "list_margin"})
        marge = (v[0] - v[1]) / exprimes * 100 if exprimes > 0 else np.nan
        return pd.Series({"n_unites": n, "mono_liste": 0, "closeness": round(marge, 4), "method": "list_margin"})

    def closeness_individuel(g):
        v = g["voix"].sort_values(ascending=False).values
        n = len(v)
        exprimes = g["exprimes"].iloc[0]
        annee = g.name[1]
        sieges = g["nb_sieges_requis"].iloc[0]
        seats_source = g["seats_source"].iloc[0]
        method_label = "seat_cutoff_rne_real" if seats_source == "rne_real" else "seat_cutoff_model"

        if annee == 2008:
            if n <= 1 or exprimes <= 0:
                return pd.Series({"n_unites": n, "mono_liste": 1, "closeness": np.nan,
                                  "method": "winner_share_proxy_2008"})
            closeness = round(100 - v[0] / exprimes * 100, 4)
            return pd.Series({"n_unites": n, "mono_liste": 0, "closeness": closeness,
                              "method": "winner_share_proxy_2008"})

        if pd.isna(sieges) or n <= sieges:
            return pd.Series({"n_unites": n, "mono_liste": 1, "closeness": np.nan, "method": method_label})
        sieges = int(sieges)
        marge = (v[sieges - 1] - v[sieges]) / exprimes * 100 if exprimes > 0 else np.nan
        return pd.Series({"n_unites": n, "mono_liste": 0, "closeness": round(marge, 4), "method": method_label})

    print("Computing closeness (liste regime)...")
    liste = raw[raw["type_scrutin"] == "liste"]
    out_liste = (liste.groupby(["code_insee", "annee"])
                 .apply(closeness_liste, include_groups=False).reset_index())

    print("Computing closeness (individuel/panachage regime, seat threshold; 2008 = winner share)...")
    ind = raw[raw["type_scrutin"] == "individuel"]
    out_ind = (ind.groupby(["code_insee", "annee"])
               .apply(closeness_individuel, include_groups=False).reset_index())

    out = pd.concat([out_liste, out_ind], ignore_index=True)
    out = out.merge(panel_ts, on=["code_insee", "annee"], how="left")
    out = out[["code_insee", "annee", "type_scrutin", "n_unites", "mono_liste", "closeness", "method"]]

    print(f"\n{len(out):,} commune-year observations")
    out.to_csv(OUT, index=False)
    print(f"\nSaved -> {OUT}")
