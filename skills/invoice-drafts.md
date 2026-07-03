---
name: invoice-drafts
description: Crée les brouillons Gmail d'envoi de factures mensuelles aux clients récurrents (Frontmatec, Eddyfi, Cordé, Can-Ex)
argument-hint: "[mois année, ex: 'juin 2026', '2026-06'] — défaut: mois précédent"
---

# Brouillons de factures mensuelles

Crée un brouillon Gmail par client récurrent, avec la facture + l'annexe de temps en pièces jointes, mêmes destinataires et même format que le mois précédent, mois ajusté. Ne PAS envoyer — laisser en brouillon pour relecture par JP.

## Arguments

$ARGUMENTS — Le mois facturé. Exemples : `juin 2026`, `2026-06`, `juin`. **Défaut si absent : le mois précédent** (les factures d'un mois sont préparées au début du mois suivant).

## Étape 1 — Déterminer le mois

Résoudre le mois/année cible depuis `$ARGUMENTS`, sinon prendre le mois précédent (relatif à la date du jour). Garder :
- `mois_fr` en minuscules pour le dossier : `janvier, février, mars, avril, mai, juin, juillet, août, septembre, octobre, novembre, décembre`
- `Mois_Fr` capitalisé pour le sujet
- `Mon` abrégé anglais pour matcher les noms de fichiers d'annexe : `Jan, Feb, Mar, Apr, May, Jun, Jul, Aug, Sep, Oct, Nov, Dec`
- `année`

## Étape 2 — Localiser les fichiers

Dossier : `/home/jp/Documents/NQB/Admin/factures_clients/<année>/<mois_fr>/`

Lister le dossier. Pour chaque client, il y a normalement **2 PDF** : la facture (`NN-XXX-N - <Client>.pdf`) et l'annexe de temps (`<Client>_..._<année>-<Mon>-01-<année>-<Mon>-JJ.pdf`). Matcher par mot-clé de client, pas par nom exact (les numéros de facture changent chaque mois).

## Étape 3 — Config clients

| Client | Mot-clé fichiers | To | Cc | Corps |
|--------|------------------|----|----|-------|
| Frontmatec | `Frontmatec` | apinvoice.quebec@frontmatec.com | patrick.dallaire@nqb.ai | annexe |
| Eddyfi | `EddyFi` / `SpyneVision` | payables@eddyfi.com | mmsisto@eddyfi.com, patrick.dallaire@nqb.ai, fturgeon@eddyfi.com | annexe |
| Cordé | `Cordé` / `BOM` | mlemire@corde.ca | sdubuc@corde.ca, scormier@corde.ca | annexe de temps |
| Can-Ex | `Can-Ex` / `CAN` | payables@canex.tech | patrick.mimeault@canex.tech | annexe de temps |

Deux variantes de corps :
- **annexe** : `Voici la facture et annexe pour le mois de <mois_fr> <année>.`
- **annexe de temps** : `Voici la facture et annexe de temps pour le mois de <mois_fr> <année>.`

Sujet (tous) : `Facture <Mois_Fr> <année> - NQB AI`

> Vérification : les destinataires ci-dessus reprennent ceux du mois précédent. Si un contact a changé, chercher le dernier courriel envoyé (`search_gmail_messages` : `from:me subject:"Facture" <domaine-client>`) et ajuster.

## Étape 4 — Copier les PDF dans le dossier autorisé

workspace-mcp **ne peut pas lire** `/home/jp/Documents/...` directement (erreur "permitted directories"). Copier d'abord les PDF vers `~/.workspace-mcp/attachments/<mois_fr><année>/` et joindre depuis là.

```bash
mkdir -p ~/.workspace-mcp/attachments/<mois_fr><année>/
cp "/home/jp/Documents/NQB/Admin/factures_clients/<année>/<mois_fr>/"<fichiers> ~/.workspace-mcp/attachments/<mois_fr><année>/
```

## Étape 5 — Créer les brouillons

Pour chaque client, `draft_gmail_message` (workspace-mcp) avec :
- `body_format: "html"`, `include_signature: false`
- `attachments`: les 2 PDF (chemins sous `~/.workspace-mcp/attachments/...`)
- Corps = message + `<br><br>` + délimiteur `-- ` + signature HTML de JP

Le corps doit finir par la ligne `-- ` **directement au-dessus** de la signature (comme les courriels standards de JP). Ne PAS utiliser `include_signature: true` — le MCP colle la signature sans le `-- `.

Body HTML (remplacer `<PHRASE>` par la bonne variante) :

```html
Bonjour,<br><br><PHRASE><br><br>Merci,<br>Jean-Philippe<br><br>-- <br><div dir="ltr"><div>Jean-Philippe Mercier, PhD</div><div>Cofondateur et Scientifique Appliqué @ NQB AI | Cofounder and Applied Scientist @ NQB AI</div><img width="96" height="48" src="https://ci3.googleusercontent.com/mail-sig/AIorK4xKK8kSO6zrS_Ex1GoeAXOjvn27lOoiRipyn7HvxxYzvsbbHc0TzX2zfUZKVNygXq49Q68J5lI" data-os="https://docs.google.com/uc?export=download&amp;id=1nNQDnL2hpg0gyqr3bin9AuX3BNbUUyWq&amp;revid=0B-xjHLdA71kVbTBaVjhQenVrMTNPWEIrVkRqYXNPUXhXL0VRPQ"><br></div>
```

> L'URL `ci3.googleusercontent.com/mail-sig/...` de l'image peut périmer avec le temps. Si le logo semble brisé, re-capturer la signature depuis un courriel récemment envoyé : `get_gmail_message_content(..., body_format="html")` sur un envoi récent, copier le bloc `<div dir="ltr">...` complet.

## Étape 6 — Fichiers manquants

Si l'annexe de temps (ou la facture) d'un client manque dans le dossier, **créer quand même le brouillon avec le(s) fichier(s) disponible(s)** et le signaler dans le rapport final, pour que JP fournisse le reste et relance la commande sur ce client. Ne pas bloquer les autres.

## Étape 7 — Rapport

Afficher un tableau : client, To, pièces jointes attachées, et tout fichier manquant. Rappeler que ce sont des **brouillons à relire et envoyer manuellement**.

## Notes

- Tout en français. Respecter les règles de ponctuation de JP (pas de tirets cadratins, pas de points-virgules, pas de virgule avant "et").
- Voir la mémoire `feedback-gmail-drafts-html` (délimiteur `-- ` + signature) et `feedback-gmail-attachments-path` (copie vers le dossier autorisé).
- Tous les outils workspace-mcp : `user_google_email: jp.mercier@nqb.ai`.
- Ne rien envoyer, ne rien supprimer côté courriels (sauf d'anciens brouillons vides que la commande aurait elle-même créés).
