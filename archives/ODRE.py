import requests
import pandas as pd
import time

# Liste de communes/départements avec projets éoliens connus
communes = [
    "éolien Vendée",
    "éolien Bretagne",
    "éolien Normandie",
    "éolien Hauts-de-France",
    "éolien Grand Est",
    "éolien Occitanie",
    "éolien Centre-Val de Loire",
    "éolien Nouvelle-Aquitaine",
    "éolien Bourgogne",
    "éolien Pays de la Loire"
]

BASE_URL = "https://api.gdeltproject.org/api/v2/doc/doc"

def fetch_gdelt(query, maxrecords=250):
    params = {
        "query": query,
        "mode": "artlist",
        "maxrecords": maxrecords,
        "format": "json",
        "sourcelang": "French"
    }
    try:
        response = requests.get(BASE_URL, params=params, timeout=30)
        response.raise_for_status()
        data = response.json()
        articles = data.get("articles", [])
        for art in articles:
            art["query"] = query
        return articles
    except Exception as e:
        print(f"Erreur pour '{query}': {e}")
        return []

all_articles = []

for query in communes:
    print(f"Fetching: {query}")
    articles = fetch_gdelt(query)
    print(f"  → {len(articles)} articles")
    all_articles.extend(articles)
    time.sleep(2)  # respecter le rate limit

df = pd.DataFrame(all_articles)

# Dédoublonner sur l'URL
df = df.drop_duplicates(subset=["url"])

print(f"\nTotal articles uniques : {len(df)}")
print(df.columns.tolist())

df.to_csv("gdelt_eolien_france.csv", index=False)
print("Sauvegardé : gdelt_eolien_france.csv")
