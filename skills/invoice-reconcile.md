# Rapprochement factures / transactions (banque + cartes de crédit)

Extrait toutes les transactions des relevés de carte de crédit et du compte bancaire d'un trimestre, les rapproche avec les factures/reçus classés par fournisseur, et produit un CSV listant chaque transaction avec une colonne `MISSING` (facture absente). But : identifier les transactions pour lesquelles il manque une facture, afin d'aller les télécharger.

## Arguments

$ARGUMENTS - Chemin du dossier du trimestre (ex: `/home/jp/Documents/NQB/Admin/Taxes/2026-Q3`). Par défaut : le dossier courant.

Le dossier doit contenir cette structure (identique d'un trimestre à l'autre) :
```
<trimestre>/
├── cartes_credit/        PDF des relevés VISA (ex: ...1000-avril-2026.pdf)
├── compte_banque/        CSV (et PDF) des relevés bancaires Desjardins
└── factures/
    └── Reçues/
        └── <Fournisseur>/  un sous-dossier par fournisseur, PDF + parfois images
```

## Principe (important : aucun fournisseur n'est présumé fixe)

Les fournisseurs changent d'un trimestre à l'autre. Le script **ne suppose aucune liste de fournisseurs**. Il :
1. découvre automatiquement les sous-dossiers présents dans `factures/Reçues/` ;
2. rapproche chaque transaction **par montant** (CAD ou USD) trouvé dans le texte des PDF, quel que soit le dossier. Le montant est le signal fiable ; l'identité du fournisseur est secondaire (sert juste au rapport).

Statuts :
- **OK** : le montant (CAD ou USD) apparaît dans un PDF d'un dossier fournisseur.
- **MISSING** (`X`) : montant introuvable dans tout dossier PDF, et rien n'indique qu'une facture existe.
- **A_VERIFIER** : soit le dossier plausible ne contient que des reçus image (montant non extractible), soit plusieurs dossiers partagent ce montant (ambigu), soit facture combinée/trimestrielle. À confirmer à l'œil.
- Crédits/remboursements (`CR`), paie, remises gouvernementales, paiements VISA (déjà détaillés sur les relevés carte) et frais bancaires ne requièrent pas de facture → `N/A` / `Crédit` / `Revenu`.

La table `ALIASES` du script n'est **pas** la liste des fournisseurs : ce sont seulement des indices optionnels pour (a) les libellés marchands qui diffèrent du nom de dossier (ex: `CLAUDE.AI` → `Anthropic`, `PADDLE` → `Plausible`, `INTUIT` → `Quickbooks`) et (b) les dossiers-catégories (ex: un resto → `Restaurants`). Le rapprochement par montant fonctionne même sans alias ; on ne les complète que pour améliorer le nommage ou lever une ambiguïté.

## Instructions

### 1. Déterminer le dossier

`QDIR` = $ARGUMENTS ou dossier courant. Vérifier que `cartes_credit/`, `compte_banque/` et `factures/Reçues/` existent. `pdftotext` (poppler-utils) doit être installé.

### 2. Écrire et lancer le script

Écrire le script ci-dessous dans `<scratchpad>/reconcile.py`, puis `python3 reconcile.py "<QDIR>"`. Il écrit `<QDIR>/transactions_<trimestre>.csv` (UTF-8-BOM) et imprime le résumé par fournisseur.

```python
#!/usr/bin/env python3
import os, re, sys, glob, csv, subprocess
from collections import defaultdict

QDIR = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else '.')
FACT = os.path.join(QDIR, 'factures', 'Reçues')
BANK = os.path.join(QDIR, 'compte_banque')
CCDIR = os.path.join(QDIR, 'cartes_credit')
QNAME = os.path.basename(QDIR)
OUT = os.path.join(QDIR, f'transactions_{QNAME}.csv')

def pdftext(path):
    try: return subprocess.run(['pdftotext', '-layout', path, '-'],
                               capture_output=True, text=True, errors='replace').stdout
    except Exception: return ''

# Montants robustes aux séparateurs de milliers : "4 230,15", "1,209.10", "294.00" -> "4230.15"...
NUM = re.compile(r'\d{1,3}(?: \d{3})+[.,]\d{2}|\d{1,3}(?:,\d{3})+\.\d{2}|\d+[.,]\d{2}')
def canon(s):
    s = re.sub(r'\s', '', s); i = max(s.rfind('.'), s.rfind(','))
    return f"{int(re.sub(r'[.,]', '', s[:i]) or 0)}.{s[i+1:]}"
def amounts(text): return set(canon(m) for m in NUM.findall(text))

# --- découverte automatique des dossiers + index des montants PAR FICHIER ---
# folder_files[folder] = liste de (nom_fichier, set_de_montants, est_image)
folder_files, folder_amts, folder_img, FOLDERS = {}, {}, {}, []
for d in sorted(glob.glob(f'{FACT}/*')):
    if not os.path.isdir(d): continue
    name = os.path.basename(d); FOLDERS.append(name)
    files, allamts, img = [], set(), False
    for f in sorted(glob.glob(f'{d}/*')):
        fn, low = os.path.basename(f), f.lower()
        if low.endswith('.pdf'):
            amts = amounts(pdftext(f))
            files.append((fn, amts, False)); allamts |= amts
        elif low.endswith(('.jpg', '.jpeg', '.png', '.webp', '.heic', '.gif')):
            files.append((fn, set(), True)); img = True
    folder_files[name] = files; folder_amts[name] = allamts; folder_img[name] = img
def has(folder, v): return folder in folder_amts and f'{v:.2f}' in folder_amts[folder]
def files_with(folder, cad, usd):
    """Fichier(s) du dossier dont les montants contiennent cad ou usd (chemin relatif à Reçues)."""
    out = []
    for fn, amts, img in folder_files.get(folder, []):
        if f'{cad:.2f}' in amts or (usd and f'{usd:.2f}' in amts): out.append(f'{folder}/{fn}')
    return out
def all_files(folder):
    return [f'{folder}/{fn}' for fn, _, _ in folder_files.get(folder, [])]

# Indices OPTIONNELS (libellé marchand != nom de dossier, ou dossier-catégorie).
# NE PAS y voir la liste des fournisseurs. Complèter seulement si un cas ne se résout pas seul.
ALIASES = {
    'CLAUDE': 'Anthropic', 'ANTHROPIC': 'Anthropic', 'PADDLE': 'Plausible', 'INTUIT': 'Quickbooks',
    'QBOOKS': 'Quickbooks', 'FACEBK': 'Facebook_Ads', 'NAME-CHEAP': 'Namecheap',
    'GOOGLE *WORKSPACE': 'Google_Workspace',
    'BIAGIO': 'Restaurants', 'STEAK': 'Restaurants', 'KITCHEN': 'Restaurants', 'LONDON JACK': 'Restaurants',
    'PORT DE QU': 'Stationnements', 'INDIGO': 'Stationnements', 'TRILLIUM': 'Stationnements',
    'STATIONNEMENT': 'Stationnements', 'PARKING': 'Stationnements',
}
def name_matches(desc):
    """Tous les dossiers plausibles d'après le nom (alias + tokens de nom de dossier). Gère les fournisseurs à plusieurs dossiers (ex: OpenAI + OpenAI-Ads)."""
    u = desc.upper(); found = []
    for k, folder in ALIASES.items():
        if k in u and folder in folder_amts and folder not in found: found.append(folder)
    for name in FOLDERS:
        for tok in re.split(r'[ _\-]+', name):
            if len(tok) >= 4 and tok.upper() in u and name not in found: found.append(name); break
    return found

SEP = ' | '   # séparateur multi-fichiers (pas de point-virgule)
def classify(desc, cad, usd):
    """Retourne (statut, fournisseur, missing, fichiers). Priorité au nom, confirmation par le montant."""
    named = name_matches(desc)
    if named:
        for f in named:                       # montant présent dans un des dossiers du fournisseur
            fw = files_with(f, cad, usd)
            if fw: return 'OK', f, '', SEP.join(fw)
        imgf = [f for f in named if folder_img.get(f)]
        if imgf:                              # reçu image, montant non extractible
            return 'A_VERIFIER (reçu image)', imgf[0], '', SEP.join(x for f in imgf for x in all_files(f))
        return 'A_VERIFIER (dossier sans ce montant)', named[0], '', SEP.join(all_files(named[0]))  # facture combinée ?
    cands = [f for f in FOLDERS if has(f, cad) or (usd and has(f, usd))]   # sans indice de nom : montant seul
    if len(cands) == 1:
        return 'OK', cands[0], '', SEP.join(files_with(cands[0], cad, usd))
    if len(cands) > 1:
        return 'A_VERIFIER (montant ambigu)', cands[0], '', SEP.join(x for c in cands for x in files_with(c, cad, usd))
    return 'MISSING (aucun dossier)', '', 'X', ''

# --- relevés de carte ---
LINE = re.compile(r'^\s*(\d{2})\s+(\d{2})\s+(\d{2})\s+(\d{2})\s+(\d{3})\s+(.*?)\s+([\d\s]+,\d{2})(CR)?\s*$')
USD  = re.compile(r'([\d\s]+,\d{2})\s+DOLLAR AMERICAIN')
def num(s): return float(s.replace(' ', '').replace(',', '.'))

def parse_cc(path):
    txs, on = [], False
    for line in pdftext(path).splitlines():
        if 'DESCRIPTION DES TRANSACTIONS' in line: on = True; continue
        if 'Opérations au compte' in line or 'AVIS IMPORTANT' in line: on = False; continue
        if not on: continue
        m = LINE.match(line)
        if m:
            dd, mm = m.group(1), m.group(2)
            desc, amt, cr = m.group(6), m.group(7), m.group(8)
            txs.append({'date': f'{mm}-{dd}', 'desc': re.sub(r'\s{2,}', ' ', desc.strip()),
                        'cad': num(amt), 'usd': None, 'credit': bool(cr)})
        else:
            u = USD.search(line)
            if u and txs: txs[-1]['usd'] = num(u.group(1))
    return txs

rows = []  # Source,Date,Description,Montant_CAD,Montant_USD,Type,Fournisseur,Statut,MISSING,Fichier
def year_from(path):
    m = re.search(r'(20\d{2})', os.path.basename(path)); return m.group(1) if m else '2026'
for path in sorted(glob.glob(f'{CCDIR}/*.pdf')):
    base = os.path.basename(path); yr = year_from(path)
    m = re.search(r'(\d{4})', base.replace(yr, ''))
    src = f'CC-{m.group(1)}' if m else 'CC'
    for tx in parse_cc(path):
        date = f'{yr}-{tx["date"]}'; usd = tx['usd']
        cads, usds = f"{tx['cad']:.2f}", ('' if usd is None else f"{usd:.2f}")
        if tx['credit']:
            rows.append([src, date, tx['desc'], cads, usds, 'Crédit', '', 'Crédit/remboursement', '', '']); continue
        st, fol, miss, files = classify(tx['desc'], tx['cad'], usd)
        rows.append([src, date, tx['desc'], cads, usds, 'Débit', fol, st, miss, files])

# --- relevés bancaires (CSV Desjardins, latin-1) ---
# Types de débits qui NE requièrent PAS de facture (mots-clés Desjardins stables, pas des fournisseurs).
NO_INVOICE = ['VISA DESJARDINS', 'SERVICES DE PAIE', 'PAIE /', 'REVQC', 'REMISE GOUVERNEMENTALE',
              'TPS-TVQ', 'FRAIS', 'RISTOURNE', 'VIREMENT INTERAC À /JEAN-PHILIPPE']
def bank_needs_invoice(desc):
    u = desc.upper()
    return not any(k in u for k in NO_INVOICE)
for csvf in sorted(glob.glob(f'{BANK}/*.csv')):
    for r in csv.reader(open(csvf, encoding='latin-1')):
        if len(r) < 9 or not r[3].startswith('20'): continue
        date = r[3].replace('/', '-'); desc = re.sub(r'\s{2,}', ' ', r[5].strip())
        debit, credit = r[7].strip(), r[8].strip()
        if credit:
            rows.append(['Banque', date, desc, credit, '', 'Crédit (dépôt)', '', 'Revenu / dépôt', '', '']); continue
        amt = float(debit)
        if not bank_needs_invoice(desc):
            rows.append(['Banque', date, desc, f"{amt:.2f}", '', 'Débit', '', 'N/A (paie/impôt/VISA/frais)', '', '']); continue
        st, fol, miss, files = classify(desc, amt, None)
        rows.append(['Banque', date, desc, f"{amt:.2f}", '', 'Débit', fol, st, miss, files])

rows.sort(key=lambda x: (x[0], x[1]))
with open(OUT, 'w', newline='', encoding='utf-8-sig') as fh:
    w = csv.writer(fh)
    w.writerow(['Source','Date','Description','Montant_CAD','Montant_USD','Type','Fournisseur','Statut','MISSING','Fichier'])
    w.writerows(rows)

# --- résumé par fournisseur ---
summ = defaultdict(lambda: [0,0,0,0.0])   # [n, missing, a_verifier, $manquant]
for src,date,desc,cad,usd,typ,fol,st,miss,files in rows:
    if typ.startswith('Crédit') or 'Revenu' in st or st.startswith('N/A'): continue
    key = fol or desc
    s = summ[key]; s[0]+=1
    if miss == 'X': s[1]+=1; s[3]+=float(cad)
    elif st.startswith('A_VER'): s[2]+=1
print(f"CSV -> {OUT}  ({len(rows)} lignes)\n")
print(f"{'FOURNISSEUR':30} {'TX':>3} {'MANQ':>5} {'VERIF':>6} {'$ MANQUANT':>11}")
for k in sorted(summ, key=lambda x: (-summ[x][1], -summ[x][2], str(x).lower())):
    n,mi,av,mo = summ[k]
    tag = '  <-- MANQUANT' if mi else ('  <-- a verifier' if av else '')
    print(f"{str(k)[:30]:30} {n:>3} {mi:>5} {av:>6} {mo:>11.2f}{tag}")
```

### 3. Traiter les cas signalés

Le script résout la majorité seul. Examiner ensuite :
- **`A_VERIFIER (dossier sans ce montant)`** : le libellé pointe vers un dossier mais le montant n'y est pas. Cas typiques : **facture combinée/trimestrielle** (un seul PDF couvre plusieurs transactions), **fournisseur à plusieurs dossiers** (le montant est dans un dossier voisin), ou vraie facture manquante. Ouvrir les PDF du dossier pour trancher.
- **`A_VERIFIER (montant ambigu)`** : plusieurs dossiers contiennent ce montant (ex: deux abonnements au même prix). Confirmer lequel via le libellé/date.
- **`A_VERIFIER (reçu image)`** : reçu photo/scan non-OCR. Ouvrir l'image pour lire le montant.
- **`MISSING (aucun dossier)`** : aucune facture nulle part. Si le libellé correspond en fait à un dossier existant sous un autre nom marchand, ajouter un alias dans `ALIASES` et relancer. Sinon, c'est bien à télécharger.
- **Reçus hors trimestre** : signaler tout reçu dont la date tombe dans un autre trimestre (à déplacer).

Relancer après chaque ajustement.

### 4. Compte rendu

En français : chemin du CSV, tableau **par fournisseur** (tx / manquantes / montant), liste des vrais **MISSING** à télécharger, liste séparée des **A_VERIFIER**, et toute anomalie (reçu hors trimestre, dossier inexistant).

## Notes

- Contexte fiscal : ne jamais marquer OK sans montant confirmé dans un PDF.
- Débits bancaires ne requérant PAS de facture : paie, paiements VISA (détaillés sur les relevés carte), remises gouvernementales (TPS-TVQ, RevQC), virements au propriétaire, frais. Ces mots-clés Desjardins sont stables. Tout autre débit est traité comme une dépense fournisseur et rapproché par montant.
- Le rapprochement est piloté par le montant et découvre les dossiers présents : aucun fournisseur n'est codé en dur. `ALIASES` et `NO_INVOICE` ne sont que des indices, à compléter au besoin.
- Respecter les règles de ponctuation de l'utilisateur (pas de tirets cadratins, pas de points-virgules) dans le compte rendu.
- Colonne `Fichier` du CSV : chemin(s) du/des reçu(s) rapproché(s), relatif à `factures/Reçues/`, séparés par ` | `. Vide pour les MISSING. Pour les `A_VERIFIER`, liste les fichiers du dossier candidat à inspecter.
