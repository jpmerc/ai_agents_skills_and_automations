# Update CRM

Met a jour le CRM NQB (Google Sheets) a partir des communications externes des derniers jours (Gmail, Google Calendar, Fireflies). Ajoute les nouveaux contacts et compagnies, met a jour la date de dernier contact, et signale les relances a planifier quand un meeting a ete evoque sans suivi.

## Arguments

`$ARGUMENTS` : nombre de jours a regarder en arriere. Defaut : 14. Exemple : `/update-crm 7` pour la derniere semaine.

Mode `dry-run` : si `$ARGUMENTS` contient `dry-run` (ex: `/update-crm 14 dry-run`), afficher le diff propose sans ecrire dans le sheet. **Pour le tout premier run, l'utilisateur doit toujours utiliser dry-run.**

## Constantes

- Spreadsheet ID : `1EKnRJ5jDQikHBh30JIPjdimEvxzqeKf1epNlw2D7sXI`
- Compte Google : `jp.mercier@nqb.ai`
- Fuseau utilisateur : America/New_York
- Domaine interne (a exclure) : `@nqb.ai`
- Onglets cibles : `Companies` (table id `1990477238`), `Contacts` (table id `256502794`), `Recrutement` (a creer si absent)

## Instructions

### 1. Determiner la fenetre temporelle

- Parser `$ARGUMENTS`. Defaut : 14 jours, dry-run desactive.
- Calculer borne basse en UTC : `date -u -d "${N} days ago" +"%Y-%m-%dT%H:%M:%SZ"`.
- Borne haute : maintenant UTC.

### 2. Verifier / preparer le sheet (idempotent)

Lire la ligne d'entete des onglets via `mcp__workspace-mcp__read_sheet_values` :

- `Companies!A1:V1`
- `Contacts!A1:M1`
- `Recrutement!A1:L1` (peut echouer si l'onglet n'existe pas, dans ce cas le creer)

Si necessaire, ecrire les en-tetes manquants via `modify_sheet_values` :
- `Companies!T1:V1` = `["Next Action", "Next Action Date", "Relationship Type"]`
- `Contacts!K1:M1`  = `["Next Action", "Next Action Date", "Relationship Type"]`
- Si `Recrutement` n'existe pas, demander a l'utilisateur de le creer manuellement (le MCP `workspace-mcp` n'a pas de tool `create_sheet_tab` direct), OU utiliser l'API si disponible. Ensuite ecrire `Recrutement!A1:L1` = `["Name", "Email", "LinkedIn", "Phone", "Source / Refere par", "Role vise", "Departement", "Date premier contact", "Statut", "Notes", "Next Action", "Next Action Date"]`.

Ne pas toucher aux autres colonnes.

### 3. Charger l'etat actuel du CRM

Lire en parallele :

- `Companies!A1:V1000`
- `Contacts!A1:M500`

Construire trois index en memoire :

- `contacts_by_email` : email lowercase -> numero de ligne (1-indexed) + valeurs
- `companies_by_domain` : domaine normalise (sans www., sans trailing slash, lowercase) -> numero de ligne + valeurs. Extraire le domaine de la colonne E (`Company Website (URL)`).
- `companies_by_name` : nom lowercase trim -> numero de ligne (fallback fuzzy).

Identifier les **partenaires actifs** dans Companies : toute ligne avec `Relationship Type` = `Partenaire`. Construire `partner_domains` = ensemble des domaines de ces partenaires. Cet ensemble sert plus loin a detecter les "Lead via partenaire".

### 4. Collecter l'activite externe

Lancer en parallele :

**Gmail — query principale (source de verite)**

La cle anti-spam et anti-bruit : on ne regarde QUE les threads ou NQB a deja envoye au moins un message. Ca elimine ~100% du cold outreach automatise (Eolakai, Replyteam, Momeld, Jakubzajicek, etc.) parce que JP ne repond jamais a ces mailers. Et c'est aussi la ou la valeur est : les engagements ("je te reviens", "on se reparle", "je t'envoie ca", "fixons une date") sont dans les messages SORTANTS de NQB.

```
mcp__workspace-mcp__search_gmail_messages
  query: "in:sent newer_than:${N}d -to:@nqb.ai"
  page_size: 100
```

Paginer si `next_page_token` est retourne, jusqu'a couvrir toute la fenetre. Recuperer les `thread_id` uniques (ATTENTION : un thread peut apparaitre plusieurs fois, dedupliquer).

**Gmail — query secondaire (rattraper les nouveaux entrants connus)**

Pour ne pas rater les reponses entrantes de contacts deja dans le CRM (qui n'ont pas encore re-suscite une reponse de NQB), faire une seconde query restreinte aux domaines deja connus :

```
mcp__workspace-mcp__search_gmail_messages
  query: "in:inbox newer_than:${N}d -list:* -category:promotions -category:updates -category:forums -category:social"
  page_size: 100
```

Filtrer les resultats en gardant SEULEMENT les threads dont l'expediteur a un domaine present dans `companies_by_domain` ou un email present dans `contacts_by_email`. Tout le reste (cold outreach inconnu) est ignore.

**Fetch des threads**

Concatener les `thread_id` uniques des deux queries (dedup), puis :
```
mcp__workspace-mcp__get_gmail_threads_content_batch
  thread_ids: [...]
  body_format: "text"
```

Le batch a une limite de 25 threads par appel et le resultat peut depasser le contexte. Strategie :
- Si plus de 25 threads, faire plusieurs appels.
- Si le resultat d'un batch depasse le contexte (l'outil renvoie un fichier `persisted-output`), **ne pas relire en entier**. Utiliser `python3` pour parser le fichier et n'extraire que `From`, `To`, `Date`, `Subject` + 500 premiers caracteres du body de chaque message. Le code complet d'extraction est dans la section "Annexe : extraction efficace".

**Calendar**
```
mcp__workspace-mcp__get_events
  time_min: borne_basse, time_max: borne_haute
```
Garder seulement les events avec au moins un attendee dont l'email ne finit PAS par `@nqb.ai`.

**Fireflies**
```
mcp__claude_ai_Fireflies__fireflies_get_transcripts
  fromDate: borne_basse, toDate: borne_haute
```
Pour chaque meeting avec un participant externe, recuperer le transcript :
```
mcp__claude_ai_Fireflies__fireflies_get_transcript
  transcript_id: ...
```

### 5. Extraire les interlocuteurs externes

Pour chaque thread / event / transcript, extraire les `(nom, email, domaine, societe_probable, date_dernier_contact, dernier_msg_NQB, dernier_msg_externe)` :

- Nom : depuis le From / display name / signature.
- Email : extraire avec regex standard.
- Filtrer : pas `@nqb.ai`, pas d'addresses no-reply / notifications, pas de listes (`*-noreply@`, `mailer-daemon@`, `executiveassistant@*`, `*@news.*`, `*@e.read.ai`, `fred@fireflies.ai`, etc.).
- Domaine : partie apres `@`, normalisee.
- Societe probable : depuis signature email, sinon nom du domaine sans TLD (ex: `frontmatec.com` -> `Frontmatec`).
- Dates : capturer separement la date du dernier message envoye par NQB et la date du dernier message envoye par l'externe. C'est cette difference qui drive la decision Next Action.

Dedoublonner : cle primaire = email lowercase. Si plusieurs occurrences, garder les dates les plus recentes et fusionner les autres champs.

**Filtre anti-spam complementaire (sur les threads de la query secondaire)** : si un message entrant a un header `List-Unsubscribe` ou `Precedence: bulk`, ou si son body contient des marqueurs de cold outreach (`Unsubscribe`, `If you'd rather not hear from me`, `book a slot`, `30 min on my calendar`), ignorer le thread sauf si NQB y a deja repondu.

### 6. Matcher avec le CRM existant

Pour chaque interlocuteur externe :

- **Contact match** : lookup dans `contacts_by_email`. Si miss, fallback sur `(nom_lower + domaine)` matche contre les contacts existants (col A + col I).
- **Company match** : lookup dans `companies_by_domain` avec le domaine email (souvent egal au site web). Si miss, fallback `companies_by_name` avec la societe probable (matching trim lowercase exact, pas de fuzzy aggressif).

### 7. Croiser les sources par interlocuteur

Avant de decider quoi que ce soit, **agreger toutes les interactions** par interlocuteur (cle = email lowercase) en croisant les trois sources :

- **Gmail** : threads ou cette personne est in From / To / Cc, avec les bodies (resume des engagements).
- **Calendar** : tous les events ou cet email est attendee, passes et futurs (jusqu'a +60j). Marquer chaque event comme `tenu`, `a_venir`, `annule`, `reporte`. Detecter les visites en personne via le champ `location` (adresse physique) plutot que `Google Meet` / `Zoom`.
- **Fireflies** : transcripts ou cette personne est participante. Extraire les action items qui mentionnent NQB ou cette personne.

Pour chaque interlocuteur, produire un mini-historique chronologique :
```
2026-04-21 [calendar:in_person] Visite Celertech (3500 Chem. des Quatre-Bourgeois)
2026-04-22 [email:nqb_sent] "merci pour la visite, voici le doc..."
2026-04-25 [email:ext_received] "voici nos commentaires"
2026-05-01 [calendar:meet] Octogone X NQB (meet.google.com)
2026-05-01 [fireflies:transcript] action items: NQB envoie liste questions techniques
```

Ce timeline est ce qui permet de prendre une decision informee. **Ne pas regarder qu'un seul email isole.**

### 8. Classifier le Relationship Type

La classification est conservatrice. Beaucoup de cas qui semblent evidents depuis les emails sont en fait ambigus (freelance vs employe vs partenaire vs ancien client de retour). **Ne JAMAIS auto-classifier sauf cas trivialement evidents**. Pour le reste, **proposer une suggestion + alternatives** dans la preview et laisser l'utilisateur trancher.

**Auto-classification autorisee (sans validation utilisateur)** :

1. **Match contre la liste de clients connus** (voir CLAUDE.md du repertoire `update_crm`) : si le nom de la compagnie ou son domaine matche un client documente, `Relationship Type = Client`. Le matching se fait sur :
   - nom lowercase trim exact ou variante triviale (ex: "Frontmatec" matche "FrontMatec" ; "Cordé Électrique" matche "Corde Electrique" sans accents)
   - domaine principal du site web
   La liste fait foi. La mettre a jour quand l'utilisateur mentionne de nouveaux clients ou anciens clients.

2. **Stage explicite dans Companies** :
   - `Client`, `Former Client` -> `Client`
   - `Ressources` -> `Reseau`

**Cas a router ailleurs ou filtrer** :

- **Comptables / firmes comptables internes** (RCGT, Mallette, etc.) : filtrer du CRM commercial. Detection par domaine connu et par contenu ("fiscalite", "RS&DE", "TPS", "comptabilite", "approbation taxes").
- **Recrutement / employes potentiels** : si un thread tourne autour d'embauche chez NQB ("abolition de mon poste", "tu cherches du monde?", "ton CV", "tu serais interesse par un poste", "Brigade", discussion de carriere apres meeting) -> ROUTER vers l'onglet `Recrutement` au lieu de l'onglet `Contacts`. Le skill demande validation utilisateur pour chaque ajout en Recrutement et demande quel `Statut` mettre.
- **Cold outreach automatise** (deja filtre par la query `in:sent`).
- **Leads explicitement rejetes** par l'utilisateur dans une session anterieure : skipper. Si on detecte un nouveau lead ambigu, demander a l'utilisateur s'il est interessant avant insertion.

**Tous les autres cas** (Lead potentiel, Partenaire potentiel, Lead via partenaire, etc.) : **proposer + alternatives + validation utilisateur**.

Format de proposition dans la preview :
```
[CONTACT] Eric Ste-Marie <eric@cogniwaves.com>
  Signaux : meeting Octogone X NQB 2026-05-01, thread Priorisation Octogone
  Proposition : Partenaire potentiel
  Alternatives : Client potentiel, Lead via partenaire (Lead Source: Octogone), Reseau
  -> Choix : ?
```

Heuristiques de proposition (juste pour la suggestion, pas pour l'ecriture auto) :
- Visite physique recente (event Calendar avec adresse) + thread email actif -> proposer `Client potentiel` ou `Lead direct` selon contenu.
- Domaine qui refere d'autres prospects ("j'ai un de mes clients", "je vous presente") -> proposer `Partenaire`.
- Personne en CC d'un thread NQB-Partenaire sans participer en direct -> proposer `Lead via partenaire` avec Lead Source = nom du Partenaire identifie.
- Contact uniquement en Calendar sans email -> proposer en bas de priorite, signaler "info insuffisante".

**Backfill seulement les lignes touchees** : si une ligne existante recoit un update (Last Contact, Next Action, ou nouveau contact lie), profiter pour aussi remplir `Relationship Type` SI il est vide. Ne pas ecraser une valeur deja presente. Pour le backfill aussi, valider avec l'utilisateur sauf si c'est un match trivial contre la liste clients.

### 9. Analyser et decider l'action

Pour chaque interlocuteur, on analyse en priorite **les messages envoyes par NQB**. C'est la qu'on prend des engagements : c'est donc la qu'on detecte les promesses de relance.

**Detecter une promesse / engagement dans les messages SORTANTS de NQB** :
- FR : "je te reviens", "je reviens vers toi", "on se reparle", "je te recontacte", "je t'envoie ca", "je propose une date", "fixons un meeting", "trouvons un creneau", "on devrait se voir", "on se rencontre", "prenons un cafe", "a suivre".
- EN : "I'll get back to you", "I'll follow up", "I'll send you", "let's meet", "let's grab", "let's catch up", "I'll propose a date", "find a time", "book a meeting".

Si NQB a fait une promesse et que la condition n'a pas encore ete realisee (pas de meeting Calendar planifie, pas de message subsequent de NQB qui livre la promesse), c'est un signal fort de relance.

**Detecter une demande / question de l'externe restee sans reponse** :
- L'externe pose une question concrete dans le dernier message du thread.
- NQB n'a pas repondu depuis > 3j ouvres.
- Signal : `Repondre au courriel`.

**OBLIGATOIRE — Verifier que la relance n'est pas deja faite ou inutile** :

Avant de proposer ANY Next Action de relance pour un interlocuteur, faire les deux verifications suivantes (dans cet ordre) :

1. **Calendar futur (jusqu'a +60j)** : `mcp__workspace-mcp__get_events` avec `time_min=aujourdhui`, `time_max=aujourdhui+60j`, `query=<nom de famille du contact>` (ou parcourir les events pour matcher l'email dans les attendees). Si un meeting est planifie avec cet email, **NE PAS proposer de relance**. La rencontre est deja confirmee. Indiquer dans Notes "Meeting cedule <date>".

2. **Emails sortants recents** : `mcp__workspace-mcp__search_gmail_messages` avec `query="to:<email> newer_than:<N>d"` (N = la fenetre du run). Si un message NQB plus recent que ce qu'on avait detecte existe, le contact a deja ete relance. **NE PAS proposer de nouvelle relance**.

**Cette double verification est non-negociable**. Une relance proposee a tort est pire qu'une relance manquee : elle fait perdre confiance dans le skill et oblige l'utilisateur a tout double-checker manuellement.

**Decider Next Action** (par ordre de priorite) :
1. NQB a promis quelque chose, pas livre, et la promesse date de > 5j : `Honorer promesse` ou `Relance courriel`, date = `aujourdhui + 1j`.
2. NQB a propose une rencontre, pas de meeting Calendar planifie, dernier message NQB > 5j : `Relance courriel`, date = `dernier_msg_NQB + 7j`.
3. Externe a pose une question, pas de reponse de NQB depuis > 3j : `Repondre au courriel`, date = `aujourdhui`.
4. Meeting Calendar planifie mais aucune confirmation par email : `Confirmer date meeting`, date = `meeting - 2j`.
5. Dernier message de NQB sans reponse depuis > 10j (sans promesse explicite) : `En attente reponse`, date = `dernier_msg_NQB + 14j`.
6. Sinon : laisser vide (pas d'action requise).

**Last Contact Date (Companies seulement)** : format `Mois Annee` coherent avec l'existant (ex : `September 2025`). Mettre a jour seulement si la date detectee est plus recente que la valeur courante.

### 10. Construire le diff

Deux structures :

**Updates** (lignes existantes) :
- Companies : `(row, "C", new_last_contact)`, `(row, "T", new_next_action)`, `(row, "U", new_next_action_date)`, `(row, "V", new_relationship_type)` seulement si la nouvelle valeur differe de l'actuelle. Pour `Relationship Type`, ne pas ecraser si la cellule actuelle n'est pas vide.
- Contacts : `(row, "K", new_next_action)`, `(row, "L", new_next_action_date)`, `(row, "M", new_relationship_type)` seulement si differe. Meme regle de non-ecrasement pour `Relationship Type`.
- **Ne JAMAIS ecrire dans Stage, Notes, Estimated value, Project Description, Documents, Lead Source (sauf cas explicite "Lead via partenaire" ou Lead Source est rempli avec le nom du partenaire).**

**Inserts** :
- Nouveau Contact : ligne `[Name, Company, Role, Department, Email, LinkedIn, Phone, Notes, Company_Domain, "", Next_Action, Next_Action_Date, Relationship_Type]` (13 colonnes).
- Nouvelle Company : ligne `[Company_Name, Stage_initial, "", "Jean-Philippe Mercier", Website, "", Premier_contact, Lead_Source, "", "", "", "", "", "", "", "", "", "", "", Next_Action, Next_Action_Date, Relationship_Type]` (22 colonnes).
  - Stage initial selon le Relationship Type :
    - `Lead direct` ou `Lead via partenaire` -> `Active Conversation` si echange recent (< 7j), sinon `Dating`
    - `Client potentiel` -> `Active Conversation`
    - `Partenaire potentiel` -> `Dating`
    - `Reseau` -> `Ressources`

### 11. Preview et confirmation

Afficher a l'utilisateur :

```
=== Plan d'update CRM (fenetre: N jours) ===

Companies (X updates, Y inserts) :
  UPDATE row 12 [Frontmatec] : Last Contact Date "" -> "May 2026", Next Action "" -> "Relance courriel" (2026-05-10)
  INSERT [Acme Robotics] : Contact initial, owner JP, contact David Tremblay
  ...

Contacts (X updates, Y inserts) :
  UPDATE row 5 [Mathieu Hamel] : Next Action "" -> "En attente reponse" (2026-05-13)
  INSERT [Sarah Cote / Acme Robotics] : sarah.cote@acmerobotics.ca, Directrice Operations
  ...

Total : Z modifications.

Confirmer l'ecriture ? (oui/non)
```

Si mode `dry-run` ou si l'utilisateur dit non, terminer ici sans ecrire.

### 12. Ecrire dans le sheet

- **Updates ciblees** : pour chaque update, `mcp__workspace-mcp__modify_sheet_values` avec un range d'une seule cellule (ex : `Companies!T12`) et une seule valeur. Ne JAMAIS passer un range qui couvre plusieurs colonnes pour eviter d'ecraser des donnees adjacentes.
- **Inserts** : `mcp__workspace-mcp__append_table_rows` avec le `table_id` correspondant (`1990477238` pour Companies, `256502794` pour Contacts), en envoyant la liste des nouvelles lignes en un seul appel par onglet.

### 13. Resume final

Afficher :

```
CRM mis a jour.
- Companies : X updates, Y inserts
- Contacts : X updates, Y inserts

Relances a faire dans les 7 prochains jours :
- 2026-05-08 : Relance courriel a Mathieu Hamel (Frontmatec)
- 2026-05-10 : Confirmer date meeting avec David Tremblay (Acme Robotics)
- ...
```

## Notes

- Tout en francais.
- Pas de em dash ni de point-virgule dans les notes / messages ecrits dans le sheet.
- Toujours passer `user_google_email: jp.mercier@nqb.ai` aux outils workspace-mcp.
- Ne jamais ecrire dans les onglets `Companies_ITB`, `Contacts_ITB`, `Contacts_LinkedIn_JP`, `Contacts_LinkedIn_Michel` dans cette v1.
- Toujours faire la preview avant ecriture, meme si dry-run est faux. La confirmation utilisateur est obligatoire.

## Annexe : extraction efficace d'un batch Gmail

Quand `get_gmail_threads_content_batch` retourne un fichier `persisted-output` parce que le resultat depasse le contexte, ne pas relire le fichier en entier. Utiliser ce script :

```python
import json, re, sys
PATH = "<chemin du persisted-output>"
with open(PATH) as f:
    data = json.load(f)
text = data["result"]

NQB_DOMAIN = "nqb.ai"
threads = re.split(r'\nThread ID: ', text)
out = []
for tblock in threads[1:]:
    tid = re.match(r'(\S+)', tblock).group(1)
    subj = (re.search(r'^Subject:\s*(.+?)$', tblock, re.M) or [None,""])[1].strip()
    msgs = re.split(r'=== Message \d+ ===', tblock)
    parsed = []
    for msg in msgs[1:]:
        frm = (re.search(r'^From:\s*(.+?)$', msg, re.M) or [None,""])[1].strip()
        date = (re.search(r'^Date:\s*(.+?)$', msg, re.M) or [None,""])[1].strip()
        # body = ce qui suit la derniere ligne d'en-tete
        body_start = re.search(r'\n\n', msg)
        body = msg[body_start.end():body_start.end()+800] if body_start else ""
        is_nqb = NQB_DOMAIN in frm.lower()
        parsed.append({"from": frm, "date": date, "is_nqb": is_nqb, "body_excerpt": body.strip()})
    out.append({"thread_id": tid, "subject": subj, "messages": parsed})

# print just summary, keep dict in memory for further analysis
print(f"Threads parsed: {len(out)}")
for t in out:
    nqb_msgs = [m for m in t["messages"] if m["is_nqb"]]
    ext_msgs = [m for m in t["messages"] if not m["is_nqb"]]
    last_nqb = nqb_msgs[0]["date"] if nqb_msgs else "-"
    last_ext = ext_msgs[0]["date"] if ext_msgs else "-"
    print(f"  {t['thread_id']} | {t['subject'][:50]} | NQB:{len(nqb_msgs)} ext:{len(ext_msgs)} | lastNQB={last_nqb[:25]} lastExt={last_ext[:25]}")
```

Adapter le script pour ecrire les resultats dans un fichier JSON intermediaire si plusieurs batches sont necessaires, puis charger l'agregat pour l'analyse Next Action.
