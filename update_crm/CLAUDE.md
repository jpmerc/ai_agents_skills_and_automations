# update_crm — Notes de contexte

Ce répertoire automatise la mise à jour du CRM NQB (Google Sheets) à partir des communications externes.

## Cible

Google Sheets `CRM`, ID : `1EKnRJ5jDQikHBh30JIPjdimEvxzqeKf1epNlw2D7sXI`.

V1 touche trois onglets :

| Onglet | Table MCP | Usage |
|---|---|---|
| `Companies` | `Company Pipeline` (id `1990477238`) | Pipeline commercial principal |
| `Contacts` | `Customer_contacts1` (id `256502794`) | Contacts associés au pipeline |
| `Recrutement` | (table à créer au premier run) | Candidats potentiels pour embauche chez NQB |

Onglets hors scope v1 : `Companies_ITB`, `Contacts_ITB`, `Contacts_LinkedIn_JP`, `Contacts_LinkedIn_Michel`.

### Schéma de l'onglet Recrutement (10 colonnes)

A Name, B Email, C LinkedIn, D Phone, E Source / Référé par, F Role visé, G Département, H Date premier contact, I Statut (En discussion / À contacter / Decline / Embauché), J Notes, K Next Action, L Next Action Date.

L'onglet est créé idempotemment au premier run du skill (entêtes ajoutés s'ils n'existent pas).

## Schéma des onglets (après ajout des colonnes par le skill)

### Companies (cols A→V)

A Company Name, B Stage, C Last Contact Date, D NQB owner, E Company Website (URL), F LinkedIn Page (URL), G Contacts, H Lead Source, I Industry, J Locality, K Size, L Follower Count, M Estimated value, N Estimate Length (months), O Probability, P Project Description, Q Notes, R Documents, S Notes (doublon historique, ne pas y toucher), **T Next Action**, **U Next Action Date**, **V Relationship Type**.

### Contacts (cols A→M)

A Name, B Company, C Role, D Department, E Email, F LinkedIn Profile, G Phone, H Notes, I Company Domain, J Column 1 (vide historique), **K Next Action**, **L Next Action Date**, **M Relationship Type**.

Les colonnes en gras sont ajoutées par le skill au premier run si absentes.

## Relationship Type (vocabulaire contrôlé)

Valeurs autorisées dans la colonne `Relationship Type` :

- `Client` — sous contrat / projet payé en cours
- `Client potentiel` — lead qualifié en discussion sérieuse, proposition ou pricing échangé
- `Lead direct` — prospect qu'on peut approcher directement, intérêt mutuel mais pas encore qualifié
- `Lead via partenaire` — prospect amené par un partenaire, on passe par le partenaire pour les échanges. La colonne `Lead Source` (col H) précise quel partenaire.
- `Partenaire` — entreprise qui nous référence des leads activement (ex: IP4B nous amène des leads pour l'agent IA téléphonique)
- `Partenaire potentiel` — partenariat en discussion, pas encore opérationnel (ex: CCTT, Réseau CCTT)
- `Reseau` — contact utile, pas pipeline commercial direct (ex: ressources industrielles, conseillers, mentors)

Ces valeurs sont aussi appliquées à Contacts (col M), où elles décrivent le rôle de la personne dans la relation (souvent identique à sa Company, sauf cas spéciaux).

## Conventions

- Domaine interne NQB : `@nqb.ai` (un email avec ce domaine est un membre de l'équipe, pas un contact externe à mettre dans le CRM).
- Compte Google par défaut pour tous les appels MCP : `jp.mercier@nqb.ai`.
- Fuseau utilisateur : America/New_York (EDT, UTC-4 ou UTC-5 selon DST).
- Le CRM contient des données business critiques. Les writes doivent être ciblés (cellule par cellule pour les updates) et précédés d'une preview à l'utilisateur avec confirmation.

## Liste de clients NQB (actuels + passés)

Ces noms sont reconnus comme `Relationship Type = Client` automatiquement (le Stage reste manuel pour distinguer actuel vs Former) :

INO, Eddyfi, Optel, Sodan, ULaval, NeuroSolution, MedScint, H2pRO, FrontMatec, Robitaille Équipement, Monadical, Thales, Octogone Collectif, Maisons et chalets à louer, IG Gestion de Patrimoine, Buziness.ca, Cimetière St-Charles, Point Laz, Can-Explore (alias Canex Tech, domaine canex.tech), Cordé Électrique, Cogniwaves, AGT Robotique.

Notes :
- **Can-Explore et Canex Tech sont la même entité** (domaine `canex.tech`). Le CRM a déjà la ligne `Can-Explore` (row 17). Ne pas créer de doublon.
- **AGT Robotique** : client qui va commencer (mai 2026), pas encore de ligne dans le CRM, à créer au premier signal email/calendar.
- **Cogniwaves** : ancien client redevenu actif via le projet Octogone (consortium IA hospitalier).

Le matching se fait par nom de compagnie (lowercase trim, accents normalisés) ou par domaine connu. Cette liste évolue, à mettre à jour à mesure.

## Partenaires connus

- **IP4B** (`ip4b.ca`) : nous référence des leads (ex: Notiplex). Tous les contacts IP4B = `Partenaire`. Les leads référés par IP4B = `Lead via partenaire` avec `Lead Source = IP4B`.

## Hors scope CRM commercial (à filtrer)

Certains contacts apparaissent dans Gmail/Calendar mais ne doivent PAS aller dans le CRM commercial :

- **Comptables / firmes comptables** : RCGT (Pascal Grob), Mallette (Laurie Tremblay), etc. — comptabilité interne.
- **Employés potentiels (recrutement)** : personnes en discussion d'embauche chez NQB. Ex: Philip Oligny, Pierre-Yves Mathieu (mai 2026). Si une conversation tourne autour de "abolition de mon poste", "tu cherches du monde?", "envoie-moi ton CV", c'est du recrutement, pas du commercial.
- **Cold outreach commercial automatisé** : déjà filtré par la query `in:sent` (NQB ne répond pas).
- **Leads explicitement rejetés** : si JP indique qu'un lead n'est pas intéressant (ex: Tommy Delage Légaré, formulaire web qualifié comme non pertinent), ne PAS l'ajouter au CRM. Demander confirmation avant insertion pour tout lead inbound non qualifié.

## Heuristiques de classification (apprises)

La classification automatique se trompe facilement. Le skill DOIT proposer chaque classification non-evidente comme une suggestion validable, pas comme un fait. Cas notamment ambigus :

- Une personne au domaine X qui apparait dans des meetings d'un client Y peut être : freelance / consultant pour Y, employé de X qui aide Y, ou partenaire au sens strict. Sans signal explicite, le skill ne peut pas trancher.
- "Active Conversation" entre NQB et un nouveau contact peut être : Client potentiel, Lead direct, Partenaire potentiel, ou même Employé potentiel selon le sujet.
- Les meetings Calendar avec plusieurs domaines externes ne signifient pas que tous sont du même type de relation.

Règle : pour les nouvelles compagnies / contacts non triviaux, le skill propose une classification + alternatives, et l'utilisateur valide ou corrige avant écriture.

## MCP utilisés

- `workspace-mcp` : Sheets, Gmail, Calendar
  - `get_spreadsheet_info`, `read_sheet_values`, `modify_sheet_values`, `append_table_rows`, `list_sheet_tables`
  - `search_gmail_messages`, `get_gmail_threads_content_batch`
  - `get_events`
- `claude_ai_Fireflies` : transcripts de meetings
  - `fireflies_get_transcripts`, `fireflies_get_transcript`

## Slash command

Le skill `/update-crm` est défini dans `/home/jp/ai_automations/skills/update-crm.md` (chargé automatiquement par Claude Code).

## Hors scope v1

- Cron quotidien.
- Enrichissement LinkedIn (Industry, Size, Follower Count).
- Onglets ITB et LinkedIn_*.
- Nettoyage des doublons préexistants.
