#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Script unique et complet :
1. Scanne RNA pour associations avec opposition à éoliennes/solaire
2. Cherche groupes Facebook correspondants via SearxNG
3. Exporte résultats CSV

Usage:
    python scripts/main.py --rna-dir data/assos2025 --output results/assos_fb.csv
    python scripts/main.py --rna-dir data/assos2025 --output results/assos_fb.csv --search-fb
"""

import argparse
import csv
import glob
import os
import requests
import time


def search_rna_associations(rna_dir):
    """Scanne TOUS les ~1.2M d'associations RNA pour opposition énergies renouvelables"""
    
    opposition_patterns = [
        'anti eol', 'anti éol', 'anti solai',
        'contre eol', 'contre éol', 'contre solai',
        'non aux eol', 'non aux éol', 'non aux solai',
        'non au eol', 'non au éol', 'non au solai',
        'non a l eol', 'non a l éol', 'non a la solai',
        'non au parc', 'contre parc eol', 'contre parc solai',
        'contre panneau', 'contre photovolta',
        'stop eol', 'stop éol', 'stop solai',
        'opposition eol', 'opposition éol', 'opposition solai',
        'refus eol', 'refus éol', 'refus solai',
        'defense contre eol', 'defense contre solai',
        'defense eol', 'defense solai', 'defence eol', 'defence solai',
        'collectif contre eol', 'collectif contre solai',
        'association contre eol', 'association contre solai',
        'non au projet eol', 'non au projet solai',
        'sauvegarde contre eol', 'sauvegarde paysage eol',
        'sauvegarde eol', 'sauvegarde solai', 'sauvegarde paysage solai',
        'vigilance eol', 'vigilance solai', 'vigilance paysage',
        'preserve eol', 'preserve solai', 'preservation eol', 'preservation solai',
        'paysage eol', 'paysage solai', 'paysage panneau',
        'patrimoine eol', 'patrimoine solai', 'patrimoine panneau',
        'protection paysage eol', 'protection paysage solai',
        'contre l eol', 'contre l éol', 'contre la solai',
        'contre les eol', 'contre les éol', 'contre les solai',
        'collectif eol', 'collectif solai',
        'comite contre eol', 'comite contre solai',
        'groupe d opposition', 'groupe opposition eol'
    ]
    
    results = []
    all_files = glob.glob(f"{rna_dir}/rna_import_*.csv")
    
    print(f"Scannage de {len(all_files)} fichiers départementaux...")
    
    for i, rna_file in enumerate(sorted(all_files)):
        with open(rna_file, 'r', encoding='utf-8', errors='ignore', newline='') as f:
            reader = csv.DictReader(f, delimiter=';')
            
            for row in reader:
                libcom = (row.get('libcom') or '').strip()
                dept = (row.get('adrs_codepostal') or '')[:2]
                
                titre = (row.get('titre') or '').lower()
                objet = (row.get('objet') or '').lower()
                text = titre + ' ' + objet
                
                has_opposition_energy = any(p in text for p in opposition_patterns)
                
                if has_opposition_energy:
                    results.append({
                        'id': row.get('id', ''),
                        'titre': row.get('titre', ''),
                        'commune': libcom,
                        'departement': dept,
                        'code_postal': row.get('adrs_codepostal', ''),
                        'objet': row.get('objet', ''),
                        'date_creation': row.get('date_creat', ''),
                        'siteweb': row.get('siteweb', ''),
                        'facebook_url': '',
                        'facebook_found': False
                    })
        
        if (i + 1) % 20 == 0:
            print(f"  [{i+1}/{len(all_files)}] {len(results)} assos trouvées")
    
    return results


def search_facebook_group(titre, commune):
    """Cherche groupe Facebook pour association via SearxNG"""
    
    query = f'"{titre}" facebook'
    
    try:
        url = "https://searx.be/search"
        params = {
            'q': query,
            'format': 'json',
            'pageno': 1,
            'lang': 'fr'
        }
        
        response = requests.get(url, params=params, timeout=5)
        response.raise_for_status()
        
        data = response.json()
        results = data.get('results', [])
        
        for result in results:
            url_result = result.get('url', '').lower()
            if 'facebook.com' in url_result and ('group' in url_result or 'page' in url_result):
                return url_result, True
        
        return '', False
    
    except Exception as e:
        return '', False


def main():
    parser = argparse.ArgumentParser(description="Scanne RNA + cherche groupes Facebook")
    parser.add_argument('--rna-dir', required=True, help='Répertoire données RNA')
    parser.add_argument('--output', required=True, help='Fichier résultat CSV')
    parser.add_argument('--search-fb', action='store_true', help='Chercher groupes Facebook (lent)')
    args = parser.parse_args()
    
    print("=== ÉTAPE 1: Scanner RNA ===")
    associations = search_rna_associations(args.rna_dir)
    print(f"✓ {len(associations)} associations trouvées\n")
    
    if args.search_fb and len(associations) > 0:
        print("=== ÉTAPE 2: Chercher groupes Facebook ===")
        for i, asso in enumerate(associations):
            print(f"  [{i+1}/{len(associations)}] Cherche: {asso['titre'][:50]}")
            url, found = search_facebook_group(asso['titre'], asso['commune'])
            if found:
                asso['facebook_url'] = url
                asso['facebook_found'] = True
            time.sleep(1)  # Rate limit
    
    # Sauvegarder résultats
    os.makedirs(os.path.dirname(args.output) or '.', exist_ok=True)
    
    with open(args.output, 'w', encoding='utf-8', newline='') as f:
        if associations:
            fieldnames = list(associations[0].keys())
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(associations)
    
    print(f"\n✓ Résultats sauvegardés: {args.output}")
    
    # Résumé
    found_fb = sum(1 for a in associations if a['facebook_found'])
    print(f"\n=== RÉSUMÉ ===")
    print(f"Associations trouvées: {len(associations)}")
    print(f"Avec groupes Facebook: {found_fb}")


if __name__ == "__main__":
    main()
