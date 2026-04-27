# GitHub Summary Bot

Ce dossier contient l'automatisation du resume GitHub quotidien pour l'org nqbai.

## Format de sortie

La sortie DOIT etre un JSON valide pour Google Chat webhook (cards format). Rien d'autre que le JSON.

IMPORTANT: Tout le texte rédigé dans les cards doit être en français avec les accents (é, è, ê, à, ç, etc.). Les messages de commits restent tels quels en anglais.

### Structure Google Chat Card

```json
{
  "cards": [
    {
      "header": {
        "title": "Resume GitHub - 2026-03-30 (24h)",
        "subtitle": "NQB AI"
      },
      "sections": [
        {
          "header": "nom_du_repo",
          "widgets": [
            {
              "textParagraph": {
                "text": "<b>Résumé :</b> 2-3 phrases sur l'avancement.<br><br><b>Changements effectués :</b><ul><li>[feat] <b>Ajout export CSV des factures.</b> Demande récurrente côté support (Marie)</li><li>[fix] <b>Correction calcul TPS sur remboursements</b> (Alex)</li><li>⚠ [refactor] <b>Réorganisation du module auth</b> (Tom)</li></ul><b>Commits (5) :</b><ul><li>auteur: message du commit</li></ul><b>PRs mergées :</b><ul><li>titre de la PR par auteur</li></ul>"
              }
            }
          ]
        },
        {
          "header": "Vue d'ensemble",
          "widgets": [
            {
              "textParagraph": {
                "text": "<i>1-2 phrases factuelles sur l'avancement général de l'équipe. Pas de questions, pas de "à valider".</i>"
              }
            }
          ]
        }
      ]
    }
  ]
}
```

### Section "Changements effectués"

C'est la section clé pour les dirigeants (jp + associé). Objectif : comprendre haut niveau ce qui a été fait et pourquoi sans avoir à parler aux développeurs, et détecter une dérive de direction.

- Sources autorisées **uniquement** : titres de PR, premières lignes de commits, noms de branches. Pas de bodies, pas de diffs (trop hardcore).
- Format avec pourquoi inférable : `[type] <b>Quoi.</b> Pourquoi (auteur)`
- Format sans pourquoi : `[type] <b>Quoi</b> (auteur)` (ne pas inventer une raison ni écrire "raison non documentée" partout)
- Types : `feat`, `fix`, `refactor`, `chore`, `docs`, `test`
- Préfixer avec `⚠` les changements risqués ou inhabituels (suppression massive, modif facturation/auth/données, refactor majeur sans contexte évident)
- Regrouper par changement logique, pas par commit. Max 6 entrées par repo, le reste en `[chore] Divers (N commits)`.

### Regles de formatage HTML (dans les cards)

- Gras: `<b>texte</b>`
- Italique: `<i>texte</i>`
- Lien: `<a href="url">texte</a>`
- Saut de ligne: `<br>`
- Liste: `<ul><li>item</li></ul>`
- PAS de markdown (#, **, -, etc.)

### Si aucune activite

Si aucun repo n'a eu d'activite, ecrire seulement le mot AUCUNE_ACTIVITE (pas de JSON).
