# Tri automatique des factures

Parcourt les courriels non-lus de Gmail, identifie les reçus et factures, télécharge les PDFs et les organise dans Google Drive.

## Arguments

$ARGUMENTS - Options (ex: "last 7 days", "depuis lundi"). Par défaut: tous les non-lus.

## Instructions

### 1. Chercher les courriels
Utiliser `search_gmail_messages` avec **toujours** `is:unread` ET `-category:promotions -category:social`. Si $ARGUMENTS precise une periode (ex: "30 derniers jours", "derniere semaine"), ajouter aussi un filtre temporel (ex: `newer_than:30d`). La requete combine toujours les deux : `is:unread newer_than:30d -category:promotions -category:social`. Recuperer un bon volume (page_size 30+).

### 2. Lire et filtrer
Utiliser `get_gmail_messages_content_batch` pour lire tous les courriels trouves. **Attention** : le resultat peut etre tres volumineux. Si le fichier est trop gros pour etre lu directement, extraire les metadonnees (subject, from, montants) avec un script Python.

A partir des sujets et expediteurs, identifier ceux qui sont des recus ou factures. Mots-cles typiques : receipt, invoice, facture, recu, payment, billing, statement, charge, confirmation de paiement, order confirmation, subscription, votre commande, releve d'honoraires, etc. Expediteurs typiques : adresses Stripe (`invoice+statements+...@stripe.com`), Paddle, PayPal, tito.io, etc.

Ignorer les newsletters, alertes securite, invitations calendrier, promos et marketing.

### 4. Identifier le fournisseur
Extraire le nom du fournisseur (ex: Twilio, Nutcache, Paddle, Google, etc.) à partir de l'expéditeur ou du contenu. Normaliser le nom (pas d'espaces, underscores si nécessaire, ex: "Clay_Labs" -> "Clay").

### 5. Telecharger les PDFs
Deux cas possibles :

**Cas A - Piece jointe PDF** : Telecharger avec `get_gmail_attachment_content` (workspace-mcp).

**Cas B - Lien de telechargement dans le body (cas le plus frequent)** : La plupart des recus Stripe, Paddle, Tito etc. n'ont pas de PDF attache mais contiennent des liens "Download invoice" ou "Download receipt" dans le body. Extraire ces URLs (ex: `pay.stripe.com/.../pdf`, `dashboard.stripe.com/receipts/.../pdf`, `ti.to/receipts/...`) et telecharger avec `curl -sL -o fichier.pdf "URL"`.

Les fichiers doivent etre sauvegardes dans `~/.workspace-mcp/attachments/` (pas dans `/tmp/`, car workspace-mcp n'a acces qu'aux chemins sous `/home/jp/`).

Nommage : `Fournisseur_NumeroRecu_YYYY-MM-DD.pdf`

Si le courriel contient a la fois un lien "Download invoice" ET un lien "Download receipt" (courant avec Stripe), telecharger les deux PDFs et les mettre tous les deux dans le dossier Drive du fournisseur. Nommer : `Fournisseur_NumeroRecu_YYYY-MM-DD_invoice.pdf` et `Fournisseur_NumeroRecu_YYYY-MM-DD_receipt.pdf`.

### 6. Organiser dans Google Drive
Le dossier de référence stable est **Factures** (ID: `1OhCwGZzMqNrv8_Fx_jS1uaBD6uSGHPH8`).

Etapes :
1. Chercher le sous-dossier **Recues** dans Factures :
   ```
   search_drive_files: name = 'Reçues' and '1OhCwGZzMqNrv8_Fx_jS1uaBD6uSGHPH8' in parents and mimeType = 'application/vnd.google-apps.folder'
   ```

2. Lister les sous-dossiers fournisseurs existants avec `list_drive_items(folder_id=ID_RECUES, file_type='folder')`. C'est plus fiable que `search_drive_files` pour trouver les dossiers fournisseurs.

3. Si le dossier fournisseur n'existe pas, le creer avec `create_drive_folder` dans Recues.

4. Uploader le PDF dans le dossier du fournisseur :
   ```
   create_drive_file(file_name, folder_id=ID_FOURNISSEUR, mime_type='application/pdf', fileUrl='file:///home/jp/.workspace-mcp/attachments/fichier.pdf')
   ```
   **Important** : le fileUrl doit pointer vers `/home/jp/...`, pas `/tmp/`. workspace-mcp n'a pas acces aux chemins hors de `/home/jp/`.

### 7. Marquer comme lu
Si le PDF a été uploadé avec succès dans Drive, marquer le courriel comme lu avec `modify_gmail_message_labels` (retirer le label UNREAD).
Si échec, laisser en non-lu.

### 8. Rapport
À la fin, afficher un résumé :
- Nombre de courriels traités
- Pour chaque : fournisseur, montant (si trouvé), fichier uploadé, statut
- Courriels ignorés (non pertinents)

### 9. Nettoyage
Supprimer les fichiers téléchargés dans `~/.workspace-mcp/attachments/` après upload réussi.

## Outils utilisés (workspace-mcp)

| Étape | Outil |
|-------|-------|
| Chercher courriels | `search_gmail_messages` |
| Lire courriel | `get_gmail_message_content` |
| Telecharger piece jointe | `get_gmail_attachment_content` |
| Telecharger PDF via lien | `curl -sL` (Stripe, Paddle, Tito, etc.) |
| Chercher dossier Drive | `search_drive_files` |
| Lister contenu dossier | `list_drive_items` |
| Créer dossier | `create_drive_folder` |
| Uploader fichier | `create_drive_file` |
| Marquer comme lu | `modify_gmail_message_labels` |

Tous les outils nécessitent `user_google_email: jp.mercier@nqb.ai`.

## Notes

- Tout en français
- Ne pas traiter les courriels marketing/promo comme des factures
- Si un courriel est une facture mais sans PDF attache ET sans lien de telechargement, le signaler sans le marquer comme lu
- Ne pas supprimer de courriels
- Attention aux doublons de dossiers fournisseurs (ex: 2x "Clay"), utiliser celui le plus récent
