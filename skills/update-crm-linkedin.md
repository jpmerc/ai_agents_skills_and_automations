# Update CRM from LinkedIn backup

Met a jour le CRM NQB (Google Sheets) a partir d'un backup local LinkedIn (`Connections.csv` + `messages.csv`). Deux objectifs distincts du skill `/update-crm` (qui couvre Gmail / Calendar / Fireflies) :

1. **Enrichir les contacts CRM existants** avec leur URL de profil LinkedIn (depuis `Connections.csv`).
2. **Detecter et ajouter les nouveaux interlocuteurs** rencontres uniquement par DM LinkedIn (depuis `messages.csv`), en se limitant aux conversations ou il y a eu au moins un message entrant (filtre : si JP a envoye sans reponse, on n'ajoute rien).

Important : le chevauchement avec Gmail est attendu (la plupart des intros LinkedIn passent ensuite au courriel). Le skill **doit dedupliquer agressivement** contre les contacts deja crees par `/update-crm`.

## Arguments

`$ARGUMENTS` :
- Chemin optionnel du backup, par defaut le plus recent dans `/home/jp/Documents/NQB/LinkedIn/backups/`. Detecter via `ls -t`.
- Mot-cle `dry-run` pour preview seulement (recommande au premier run).
- Optionnel : `since:YYYY-MM-DD` pour filtrer les messages LinkedIn anterieurs a cette date. Par defaut : `since:2024-01-01` (ignore l'historique LinkedIn pre-NQB).

Exemples :
- `/update-crm-linkedin` : backup le plus recent, since 2024-01-01
- `/update-crm-linkedin dry-run`
- `/update-crm-linkedin since:2025-01-01`

## Constantes

- Spreadsheet ID : `1EKnRJ5jDQikHBh30JIPjdimEvxzqeKf1epNlw2D7sXI`
- Compte Google : `jp.mercier@nqb.ai`
- Onglets cibles : `Companies` (table id `1990477238`), `Contacts` (table id `256502794`)
- Profil LinkedIn de JP (a exclure des FROM externes) : `Jean-Philippe Mercier` / `https://www.linkedin.com/in/jpmercier87`

## Instructions

### 1. Localiser le backup

- Si `$ARGUMENTS` contient un chemin absolu vers un dossier, l'utiliser.
- Sinon, lister `/home/jp/Documents/NQB/LinkedIn/backups/` et prendre le dossier le plus recent par date de modification.
- Verifier l'existence de `Connections.csv` et `messages.csv` dans le dossier. Si absents, abandonner avec un message clair.

### 2. Charger l'etat actuel du CRM

Lire en parallele :

- `Companies!A1:V1100` (le pipeline a deja > 1000 lignes apres les runs precedents)
- `Contacts!A1:M500`

Construire les index :

- `contacts_by_email` : email lowercase -> row + valeurs (col A name, col B company, col F linkedin)
- `contacts_by_name_company` : `(nom_normalise, company_normalise)` -> row + valeurs. Normalisation : lowercase, trim, accents enleves (`unicodedata.normalize('NFKD').encode('ascii','ignore')`).
- `contacts_by_linkedin` : URL LinkedIn normalisee (sans trailing slash, sans `?utm`, partie `linkedin.com/in/<slug>` lowercase) -> row.
- `companies_by_name` : nom lowercase trim accents enleves -> row.

### 3. Pass A — Enrichir contacts existants depuis Connections.csv

Le fichier commence par 3 lignes `Notes:` puis l'entete `First Name,Last Name,URL,Email Address,Company,Position,Connected On`. Skip les 3 premieres.

```python
import csv, re, unicodedata
def norm(s):
    if not s: return ""
    s = unicodedata.normalize('NFKD', s).encode('ascii','ignore').decode().lower().strip()
    return re.sub(r'\s+', ' ', s)

def norm_li(url):
    if not url: return ""
    m = re.search(r'linkedin\.com/in/([^/?#]+)', url.lower())
    return m.group(1) if m else ""
```

Pour chaque connection :
- Cle de matching prioritaire : `(norm("First Last"), norm("Company"))` -> lookup dans `contacts_by_name_company`.
- Fallback : `norm("First Last")` seul -> si exactement un contact CRM porte ce nom, match. Si plusieurs, skip (ambigu).
- Si `Email Address` est present et matche un `contacts_by_email`, c'est un match prioritaire.

Pour chaque match trouve :
- Si `Contacts!F<row>` (LinkedIn Profile) est vide, preparer un update -> URL LinkedIn de la connection.
- Si `Contacts!F<row>` deja rempli mais avec un slug different, **ne pas ecraser** (laisser la valeur existante). Logguer un avertissement dans la preview.

Ne JAMAIS inserer un contact a partir de `Connections.csv` seule. Une connection LinkedIn sans message ni echange courriel n'est pas un signal commercial. On ne fait que de l'enrichissement de lignes existantes.

### 4. Pass B — Nouveaux interlocuteurs depuis messages.csv

Format CSV : `CONVERSATION ID,CONVERSATION TITLE,FROM,SENDER PROFILE URL,TO,RECIPIENT PROFILE URLS,DATE,SUBJECT,CONTENT,FOLDER,ATTACHMENTS,IS MESSAGE DRAFT`. La date est `YYYY-MM-DD HH:MM:SS UTC`.

```python
import csv
from collections import defaultdict
convs = defaultdict(list)
with open(f"{BACKUP}/messages.csv") as f:
    r = csv.reader(f)
    next(r)  # header
    for row in r:
        if len(row) < 7: continue
        if row[11] == "TRUE": continue  # skip drafts
        convs[row[0]].append(row)
```

Filtrage des conversations a retenir :

1. **Au moins un message FROM != "Jean-Philippe Mercier"** dans la conversation (au moins une reponse de l'externe). C'est la regle stricte demandee par JP : si JP a envoye et personne n'a repondu, on ignore.
2. **Au moins un message dans la fenetre `since`** (par defaut 2024-01-01). Compter sur le DATE le plus recent du conv.
3. **Pas un message a JP lui-meme** (sender == JP et recipient == JP).
4. **Skip group conversations** : si plus d'un participant externe distinct, regarder le titre `CONVERSATION TITLE` et decider au cas par cas. Pour la v1, **skipper les conversations de groupe** (>1 distinct external sender) et signaler leur compte dans la preview pour traitement manuel ulterieur.

Pour chaque conversation retenue, extraire `interlocuteur` :
- Nom : le `FROM` non-JP le plus frequent (ou le `TO` si JP est `FROM` partout).
- LinkedIn URL : `SENDER PROFILE URL` correspondant a ce nom.
- Compagnie : NON disponible directement dans messages.csv. La recuperer en croisant avec `Connections.csv` par URL LinkedIn ou par nom (Pass A index). Si pas dans Connections, laisser vide et essayer de l'inferer depuis le contenu (signature dans `CONTENT`, mention de domaine email).
- Date dernier contact : `max(DATE)` de la conversation.
- Date premier contact : `min(DATE)`.
- Resume du contenu : concatener les 3 derniers messages tronques a 300 chars chacun, garder pour aider la classification.

### 5. Matcher avec le CRM (Pass B)

Pour chaque interlocuteur :

1. **Match par LinkedIn URL** : lookup dans `contacts_by_linkedin` (rapide, sans ambiguite). Si deja en CRM via `/update-crm`, c'est ce match qui evite le doublon.
2. **Match par nom + compagnie** : si compagnie connue depuis Connections.csv, lookup dans `contacts_by_name_company`.
3. **Match par nom seul** : si un seul contact CRM porte ce nom, c'est probable.
4. **Match par email** : si on a reussi a inferer un email (rare depuis LinkedIn), lookup `contacts_by_email`.

Si match :
- Update `Last Contact Date` (col C de Companies) au mois/annee du dernier message LinkedIn, **seulement si plus recent** que la valeur existante.
- Update `LinkedIn Profile` (col F de Contacts) si vide.
- **Ne pas modifier Next Action** depuis ce skill (LinkedIn est rarement un canal d'engagement formel comme un courriel pro).

Si pas de match :
- Candidat insertion (a presenter en preview pour validation, **avec le meme protocole de classification que `/update-crm`**).

### 6. Classification des nouveaux contacts (Pass B)

Memes regles que `/update-crm` (voir `/home/jp/ai_automations/update_crm/CLAUDE.md`) :

- **Recrutement** : si la conversation tourne autour d'embauche, de carriere chez NQB, ou si la personne est un candidat actif (recruteur sollicitant JP, ou JP recrutant), router vers l'onglet `Recrutement` (pas Contacts). Pour la v1 du skill LinkedIn, signaler ces cas dans la preview et **demander confirmation** avant tout ajout (le volume sur LinkedIn est surtout du recrutement passif).
- **Comptables / sales reps generiques** : filtrer.
- **Cold outreach automatise entrant** (pitchs vendeurs ou agences) : filtrer.
- **Reseau / contacts informels** : `Reseau` plutot que `Lead direct`.
- **Lead via partenaire** : si l'intro vient via un partenaire connu (IP4B, etc.), proposer ce type avec `Lead Source = nom du partenaire`.

**Ne JAMAIS auto-classifier**. Toujours proposer + alternatives + validation utilisateur, sauf cas trivial (match contre liste de clients connus -> `Client`).

Le contenu LinkedIn est souvent **plus pauvre en signaux** que les emails (DM courts, peu de contexte). Etre encore plus conservateur que sur `/update-crm` : en cas de doute, preferer `Reseau` ou demander explicitement.

### 7. Construire le diff

**Updates** (lignes existantes) :
- Contacts col F (LinkedIn Profile) : seulement si actuellement vide.
- Companies col C (Last Contact Date) : seulement si la nouvelle date est plus recente.
- **Ne JAMAIS toucher** les autres colonnes (Stage, Notes, Estimated value, Relationship Type deja rempli, etc.).

**Inserts** :
- Contacts : `[Name, Company, Role, Department, Email, LinkedIn, Phone, Notes, Company_Domain, "", "", "", Relationship_Type]`. Le Role vient de `Position` dans Connections.csv si dispo.
- Companies : seulement si la compagnie est inconnue ET la conversation montre un signal commercial clair. Sinon, ne pas creer de Company depuis LinkedIn (eviter la pollution).

### 8. Preview et confirmation

Format :

```
=== Plan d'update CRM depuis LinkedIn (backup: 4_mai_2026, since: 2024-01-01) ===

PASS A — Enrichissement LinkedIn URL :
  Contacts (X updates) :
    UPDATE row 12 [Mathieu Hamel] : LinkedIn "" -> "https://www.linkedin.com/in/mathieu-hamel-xxx"
    UPDATE row 45 [David Tremblay] : LinkedIn "" -> "https://www.linkedin.com/in/dtrembla"
    ...
  Conflits ignores (URL deja presente, differente) : 0

PASS B — Nouveaux interlocuteurs LinkedIn :
  Conversations retenues : N (filtres: bidirectional, since 2024)
  Conversations skip (uniquement JP -> autre, pas de reponse) : M
  Conversations groupe skippees : K

  Matchs avec CRM existant (X updates Last Contact + LinkedIn) :
    UPDATE [Sarah Cote / Acme Robotics] : Last Contact "" -> "Apr 2026", LinkedIn rempli
    ...

  Nouveaux contacts proposes (Y inserts a valider) :
    [1] Marc Dubois (Director, Tribute Technology)
        LinkedIn : https://www.linkedin.com/in/marcdubois
        Echange : 2024-09-12 -> 2025-03-04 (4 messages, dernier de Marc le 2025-03-04)
        Resume : "intro mutuelle via X, suite discussion sur RAG enterprise..."
        Proposition : Reseau
        Alternatives : Lead direct, Partenaire potentiel, Skip
        -> Choix : ?

    [2] ...

Total : Z updates, Y inserts a valider.

Confirmer l'ecriture ? (oui/non, ou commenter par ID)
```

L'utilisateur peut repondre `oui`, `non`, ou commenter individuellement (ex : `1=Lead direct, 2=skip, 3=Reseau`).

### 9. Ecrire dans le sheet

Apres confirmation :

- **Updates ciblees** : `mcp__workspace-mcp__modify_sheet_values` cellule par cellule (jamais de range multi-colonnes).
- **Inserts** : `mcp__workspace-mcp__append_table_rows` avec le `table_id` correspondant.

### 10. Resume final

```
CRM mis a jour depuis LinkedIn.
- Pass A (enrichissement LinkedIn URL) : X contacts mis a jour
- Pass B (nouveaux contacts) : Y contacts ajoutes, Z conversations retenues, M ignorees (filtres)

Recommendation : lancer aussi /update-crm pour capter les engagements courriel sur les memes contacts.
```

## Notes

- Tout en francais.
- Pas de em dash ni de point-virgule dans les notes / messages ecrits dans le sheet.
- Toujours passer `user_google_email: jp.mercier@nqb.ai` aux outils workspace-mcp.
- Le skill ne touche PAS aux onglets `Companies_ITB`, `Contacts_ITB`, `Contacts_LinkedIn_*`.
- Toujours faire la preview avant ecriture, meme si dry-run est faux. Confirmation utilisateur obligatoire.
- Ce skill est complementaire a `/update-crm` (qui couvre Gmail / Calendar / Fireflies). Lancer les deux periodiquement pour une vue complete. La deduplication entre les deux se fait par email + nom + URL LinkedIn (cles redondantes).

## Annexe : preprocessing CSV efficace

Les fichiers `messages.csv` (~3000 lignes) et `Connections.csv` (~3500 lignes) ne sont pas enormes mais charger 539 conversations dans le contexte LLM serait inefficace. Faire le preprocessing en Python local et n'envoyer au LLM que :
- la liste des matchs CRM existants (pour validation des updates),
- la liste des nouveaux candidats avec leur resume (pour validation des inserts).

Sauvegarder l'etat intermediaire dans `/tmp/crm_linkedin_<timestamp>.json` pour ne pas tout reparser si le user iterre sur la preview.
