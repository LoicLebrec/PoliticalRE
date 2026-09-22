"""
Fetches Parc.csv (the wind park registry) from Georisques' WFS service.
One request, no pagination needed -- the service's own "numberMatched"
count matched the row count returned in a single call exactly (3997/3997,
checked 2026-09-22).

Source confirmed by the author, tested and working:
https://georisques.gouv.fr/services?SERVICE=WFS&VERSION=2.0.0&REQUEST=GetFeature&TYPENAMES=ms:parc_wfs&SRSNAME=urn:ogc:def:crs:EPSG::3857&OUTPUTFORMAT=CSV
Schema matches Parc.csv's existing columns exactly (26/26). Row-level
content will drift slightly from any previously-downloaded copy since the
registry updates daily -- that's expected, not a mismatch to chase.

Usage (from the repo root): python3 code/shared_data/fetch_parc_georisques.py
"""

import os

import requests

PROJECT = os.environ.get("POLITICALRE_ROOT", ".")
OUT = os.path.join(PROJECT, "data/parceolien/Parc.csv")

URL = "https://www.georisques.gouv.fr/services"
PARAMS = {
    "SERVICE": "WFS",
    "VERSION": "2.0.0",
    "REQUEST": "GetFeature",
    "TYPENAMES": "ms:parc_wfs",
    "SRSNAME": "urn:ogc:def:crs:EPSG::3857",
    "OUTPUTFORMAT": "CSV",
}

if __name__ == "__main__":
    r = requests.get(URL, params=PARAMS, timeout=60)
    r.raise_for_status()
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "wb") as f:
        f.write(r.content)
    n_rows = r.text.count("\n") - 1
    print(f"Wrote {n_rows} rows -> {OUT}")
