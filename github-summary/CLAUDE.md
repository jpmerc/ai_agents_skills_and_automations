# GitHub Summary Bot

Ce dossier contient l'automatisation du resume GitHub quotidien pour l'org nqbai.

## Format de sortie

La sortie DOIT etre un JSON valide pour Google Chat webhook (cards format). Rien d'autre que le JSON.

### Structure Google Chat Card

```json
{
  "cards": [
    {
      "header": {
        "title": "Resume GitHub - 2026-03-30",
        "subtitle": "NQB AI"
      },
      "sections": [
        {
          "header": "nom_du_repo",
          "widgets": [
            {
              "textParagraph": {
                "text": "<b>Resume:</b> 2-3 phrases sur l'avancement.<br><br><b>Commits (5):</b><ul><li>auteur: message du commit</li><li>auteur: message du commit</li></ul><b>PRs mergees:</b><ul><li>titre de la PR par auteur</li></ul>"
              }
            }
          ]
        },
        {
          "header": "Vue d'ensemble",
          "widgets": [
            {
              "textParagraph": {
                "text": "<i>1-2 phrases sur l'avancement general de l'equipe.</i>"
              }
            }
          ]
        }
      ]
    }
  ]
}
```

### Regles de formatage HTML (dans les cards)

- Gras: `<b>texte</b>`
- Italique: `<i>texte</i>`
- Lien: `<a href="url">texte</a>`
- Saut de ligne: `<br>`
- Liste: `<ul><li>item</li></ul>`
- PAS de markdown (#, **, -, etc.)

### Si aucune activite

Si aucun repo n'a eu d'activite, ecrire seulement le mot AUCUNE_ACTIVITE (pas de JSON).
