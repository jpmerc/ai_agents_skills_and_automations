---
name: write-email-draft
description: Crée un brouillon de courriel dans le Gmail de JP avec sa vraie signature (logo nqb), sans l'envoyer
argument-hint: "[destinataire + sujet + points à couvrir, ou 'du contexte de la conversation']"
---

# Créer un brouillon de courriel Gmail

Crée un brouillon dans le Gmail de JP (`jp.mercier@nqb.ai`) avec sa signature habituelle (bloc HTML + logo nqb). **Ne jamais envoyer** : laisser en brouillon pour relecture. JP attache lui-même les pièces jointes et clique Envoyer.

## Arguments

`$ARGUMENTS` : destinataire, sujet, et points à couvrir. Si absents, les tirer du contexte de la conversation (ex: « prépare un brouillon pour X »). Toujours confirmer le corps avec JP avant de créer le brouillon si le contenu n'est pas trivial.

## Constantes

- Compte Google : `jp.mercier@nqb.ai`
- Outil : `mcp__workspace-mcp__draft_gmail_message`

## Ce qui fonctionne (méthode validée)

Le paramètre `include_signature: true` n'ajoute PAS la vraie signature avec le logo. Il faut créer le brouillon **en HTML** et **embarquer soi-même le bloc de signature**.

Appel type :

```
draft_gmail_message(
  to = "destinataire@exemple.com",
  subject = "Sujet sans tiret cadratin",
  body_format = "html",
  include_signature = false,
  body = "<div dir=\"ltr\">...paragraphes...<div><br></div>SIGNATURE_HTML</div>"
)
```

### Bloc de signature à coller tel quel (SIGNATURE_HTML)

**Toujours mettre le délimiteur `-- ` (span `gmail_signature_prefix`) juste avant le bloc de signature.** C'est le séparateur standard que Gmail attend.

```html
<span class="gmail_signature_prefix">-- </span><br><div class="gmail_signature" data-smartmail="gmail_signature"><div dir="ltr"><div>Jean-Philippe Mercier, PhD</div><div>Cofondateur et Scientifique Appliqué @ NQB AI | Cofounder and Applied Scientist @ NQB AI</div><img width="96" height="48" src="https://ci3.googleusercontent.com/mail-sig/AIorK4xKK8kSO6zrS_Ex1GoeAXOjvn27lOoiRipyn7HvxxYzvsbbHc0TzX2zfUZKVNygXq49Q68J5lI"><br></div></div>
```

Le logo est hébergé (URL googleusercontent). Si l'URL est morte ou que le logo ne s'affiche plus, la re-récupérer : prendre un courriel récent **écrit par JP (pas une réponse)** et lire son corps en HTML (`get_gmail_messages_content_batch(..., body_format="html")`), puis copier le bloc `data-smartmail="gmail_signature"`. Bon candidat : une facture mensuelle (sujet « Facture … NQB AI »).

### Structure du corps HTML

- Envelopper dans `<div dir="ltr">…</div>`.
- Un `<div>` par paragraphe, séparés par `<div><br></div>`.
- Échapper les entités HTML : `R&D` → `R&amp;D`, `<` → `&lt;`, etc. Les accents UTF-8 passent tels quels.
- Terminer par une salutation (« Au plaisir, ») + `<div><br></div>` + le bloc SIGNATURE_HTML.

## Règles de rédaction (voir aussi le CLAUDE.md global de JP)

- **Pas de tiret cadratin (`—`)** ni de double tiret, pas de point-virgule, pas de virgule avant « et ». Fractionner en deux phrases au besoin.
- Français par défaut. Vouvoiement sauf indication contraire (vérifier le ton des échanges précédents du contact).
- Ton concis et direct, comme JP.

## Procédure

1. Déterminer destinataire, sujet, langue, ton (tu/vous) à partir de `$ARGUMENTS` ou du fil existant.
2. Rédiger le corps, faire valider par JP si non trivial.
3. Créer le brouillon avec la méthode HTML ci-dessus (`include_signature: false`, bloc signature embarqué).
4. Confirmer à JP : destinataire, sujet, et rappels utiles (ex: « attache le deck/la pièce jointe avant d'envoyer », l'outil de brouillon ne gère pas toujours les pièces jointes).

## Limites connues

- Pas d'outil pour **supprimer** un brouillon : si on en a créé un mauvais, demander à JP de l'effacer manuellement dans Gmail.
- Les pièces jointes ne sont pas toujours disponibles côté agent : le dire à JP pour qu'il les ajoute à la main.
- Ne jamais envoyer le courriel automatiquement. Brouillon seulement.
