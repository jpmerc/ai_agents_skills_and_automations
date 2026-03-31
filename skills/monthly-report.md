---
name: monthly-report
description: Génère un rapport mensuel d'avancement client (HTML + PDF) à partir de l'historique git
argument-hint: "[mois année, ex: 'février 2026', '2026-02'] [--en pour anglais]"
---

# Monthly Report

Génère un rapport mensuel d'avancement destiné au client, basé sur les commits git du mois ciblé. Produit un fichier HTML stylé + un PDF via wkhtmltopdf.

## Arguments

$ARGUMENTS — Le mois cible et options. Exemples : `février 2026`, `mars 2025`, `2026-02`, `february 2026 --en`.

- Si `--en` est présent, produire le rapport en anglais. Sinon, français par défaut.
- Si le mois est absent ou ambigu, demander à l'utilisateur via AskUserQuestion.

## Instructions

### Étape 1 : Déterminer le mois

Parser `$ARGUMENTS` pour extraire le mois et l'année. Formats acceptés :
- `février 2026`, `fevrier 2026`, `february 2026`
- `2026-02`, `02/2026`
- `fév 2026`, `feb 2026`

Calculer les bornes : premier jour du mois 00:00:00 → premier jour du mois suivant 00:00:00.

Si le mois ne peut pas être déterminé, demander via AskUserQuestion.

### Étape 2 : Détecter le contexte projet

Chercher le nom du projet et une courte description. Essayer dans l'ordre :

1. `.planning/PROJECT.md` — lire le titre (premier `#`) et la section "What This Is" (premier paragraphe après ce heading)
2. `README.md` — lire le premier heading et le premier paragraphe
3. `pyproject.toml` — champs `name` et `description` sous `[project]`
4. `package.json` — champs `name` et `description`

Si aucune info trouvée, demander le nom du projet au client via AskUserQuestion.

### Étape 3 : Collecter les commits

Exécuter ces commandes git :

```bash
# Tous les commits du mois avec dates et messages
git log --after="<début>" --before="<fin>" --pretty=format:"%ad | %s" --date=short

# Nombre de jours actifs
git log --after="<début>" --before="<fin>" --pretty=format:"%ad" --date=short | sort -u | wc -l

# Nombre total de commits
git log --oneline --after="<début>" --before="<fin>" | wc -l

# Stats lignes (pour info interne, ne pas mettre dans le rapport)
git log --after="<début>" --before="<fin>" --shortstat | grep "files changed" | awk '{ins+=$4; del+=$6} END {print "+" ins, "-" del}'
```

### Étape 4 : Analyser et regrouper

À partir des messages de commits, regrouper le travail par thème/fonctionnalité. Ne PAS lister les commits individuellement. Identifier 3 à 6 catégories de travail (ex: "Données", "Interface", "Entraînement", "Évaluation").

Pour chaque catégorie, rédiger 1 à 3 paragraphes courts et factuels décrivant ce qui a été fait. Si une catégorie contient des sous-items distincts, utiliser une liste à puces.

Construire aussi une table chronologique regroupant les périodes de travail (par jour ou groupes de jours) avec une description courte du travail effectué.

### Étape 5 : Générer le HTML

Créer le fichier `docs/rapport-<mois>-<année>.html` (ex: `docs/rapport-fevrier-2026.html`). Créer le dossier `docs/` s'il n'existe pas.

Le HTML doit utiliser exactement ce template (adapter le contenu, garder le CSS tel quel) :

```html
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Rapport d'avancement — [Mois Année] — [Projet]</title>
<style>
  @page { size: A4; margin: 20mm 25mm; }
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    font-family: "Segoe UI", "Helvetica Neue", Arial, sans-serif;
    font-size: 11pt; line-height: 1.6; color: #1a1a1a;
    max-width: 210mm; margin: 0 auto; padding: 40px 50px; background: #fff;
  }
  .header { border-bottom: 3px solid #1a365d; padding-bottom: 20px; margin-bottom: 24px; }
  .header h1 { font-size: 22pt; font-weight: 700; color: #1a365d; margin-bottom: 4px; }
  .header .subtitle { font-size: 12pt; color: #4a5568; margin-bottom: 12px; }
  .header .meta { font-size: 9.5pt; color: #718096; }
  .header .meta span { display: block; margin-bottom: 2px; }
  h2 { font-size: 13pt; font-weight: 700; color: #1a365d; margin-top: 22px; margin-bottom: 8px; padding-bottom: 3px; border-bottom: 1.5px solid #e2e8f0; }
  p { margin-bottom: 8px; text-align: justify; }
  ul { margin: 6px 0 10px 20px; padding: 0; }
  li { margin-bottom: 4px; }
  table { width: 100%; border-collapse: collapse; margin: 12px 0 16px; font-size: 10pt; }
  thead th { background: #1a365d; color: #fff; font-weight: 600; padding: 7px 12px; text-align: left; }
  tbody td { padding: 6px 12px; border-bottom: 1px solid #e2e8f0; }
  tbody tr:nth-child(even) { background: #f7fafc; }
  .footer { margin-top: 30px; padding-top: 14px; border-top: 1.5px solid #e2e8f0; font-size: 9pt; color: #a0aec0; display: flex; justify-content: space-between; }
  @media print { body { padding: 0; } table { break-inside: avoid; } h2 { break-after: avoid; } }
</style>
</head>
<body>

<div class="header">
  <h1>[Rapport d'avancement | Progress Report]</h1>
  <div class="subtitle">[Nom du projet] — [Description courte]</div>
  <div class="meta">
    <span><strong>[Préparé par | Prepared by] :</strong> NQB AI</span>
    <span><strong>[Période | Period] :</strong> [1er au X mois année | Month 1–X, Year]</span>
    <span><strong>[Remis le | Submitted] :</strong> [date du jour]</span>
  </div>
</div>

<h2>[Sommaire | Summary]</h2>
<p>[Paragraphe factuel résumant le mois. Mentionner le nombre de jours actifs.]</p>

<h2>[1. Catégorie 1]</h2>
<p>[Description factuelle du travail effectué]</p>

<!-- Répéter pour chaque catégorie -->

<h2>[Chronologie | Timeline]</h2>
<table>
  <thead>
    <tr>
      <th>[Période | Period]</th>
      <th>[Travail effectué | Work done]</th>
    </tr>
  </thead>
  <tbody>
    <tr><td>[dates]</td><td>[description]</td></tr>
    <!-- ... -->
  </tbody>
</table>

<div class="footer">
  <span>NQB AI — [Confidentiel | Confidential]</span>
  <span>[Rapport d'avancement | Progress Report] — [Mois Année]</span>
</div>

</body>
</html>
```

### Étape 6 : Générer le PDF

Vérifier que `wkhtmltopdf` est installé (`which wkhtmltopdf`). Si oui, exécuter :

```bash
wkhtmltopdf --enable-local-file-access --page-size A4 --margin-top 20mm --margin-bottom 20mm --margin-left 25mm --margin-right 25mm docs/rapport-<mois>-<année>.html docs/rapport-<mois>-<année>.pdf
```

Si wkhtmltopdf n'est pas disponible, informer l'utilisateur qu'il peut ouvrir le HTML dans un navigateur et imprimer en PDF (Ctrl+P).

## Règles de rédaction

- **Ton factuel** : décrire ce qui a été fait, sans qualificatifs marketing (éviter "majeur", "significatif", "impressionnant", "complet", etc.)
- **Compréhensible** : un client non-technique doit comprendre le rapport. Expliquer les termes techniques si nécessaire.
- **Concis** : le rapport doit tenir sur environ une page. Pas plus de 6 sections thématiques.
- **Pas de mention de Claude/AI** dans le contenu du rapport (sauf "NQB AI" comme auteur)
- **Pas de notion de "versions livrées"** — parler de travail effectué, pas de livraisons
- **Regrouper** par thème, pas par commit
