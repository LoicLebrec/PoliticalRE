"""
Fetches epci_communes_banatic.csv (intercommunality membership per
commune) from data.gouv.fr. Confirmed byte-for-byte identical to the
existing file (after CRLF normalization, which git does automatically on
commit) -- this is not a guess, it was diffed.

Source: data.gouv.fr dataset "Base nationale sur les intercommunalités"
(https://www.data.gouv.fr/datasets/base-nationale-sur-les-intercommunalites),
resource "perimetre-epci-a-fp.csv". That dataset also has BANATIC's own
official pre-generated export
(https://www.banatic.interieur.gouv.fr/consultation/api/export/pregenere/telecharger/France,
xlsx) and a plain commune<->SIREN correspondence table, in case either is
more useful than this one for something else later.

Usage (from the repo root): python3 code/shared_data/fetch_epci_banatic.py
"""

import os

import requests

PROJECT = os.environ.get("POLITICALRE_ROOT", ".")
OUT = os.path.join(PROJECT, "code/shared_data/epci_communes_banatic.csv")

URL = "https://static.data.gouv.fr/resources/base-nationale-sur-les-intercommunalites/20250203-144053/perimetre-epci-a-fp.csv"

if __name__ == "__main__":
    r = requests.get(URL, timeout=60)
    r.raise_for_status()
    # normalize CRLF -> LF to match what's already committed
    text = r.content.decode("latin1").replace("\r\n", "\n")
    with open(OUT, "w", encoding="latin1", newline="\n") as f:
        f.write(text)
    print(f"Wrote {text.count(chr(10))} lines -> {OUT}")
