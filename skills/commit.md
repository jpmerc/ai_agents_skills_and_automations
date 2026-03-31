# Commit

Crée un ou plusieurs commits git avec les changements actuels.

## Instructions

1. Exécute `git status` et `git diff` pour analyser les changements
2. Ignore les fichiers temporaires, .zip, .pyc, __pycache__, etc.
3. **Segmente en plusieurs commits** si:
   - Les changements concernent des fonctionnalités différentes
   - Certains fichiers sont de la documentation vs du code
   - Les modifications sont indépendantes et plus claires séparément
4. Pour chaque commit:
   - Ajoute uniquement les fichiers concernés
   - Crée un message court et descriptif en anglais
   - Ne mentionne PAS "Claude", "Anthropic", ou "Co-Authored-By"
5. Garde les messages concis (une ligne, max 72 caractères)

## Format du message

```
<type>: <description courte>
```

Types: feat, fix, docs, refactor, style, test, chore

## Exemples de segmentation

- `docs: update README and Claude.md` (documentation seule)
- `feat: add JSON export mode` (nouvelle fonctionnalité)
- `refactor: optimize PDF rendering` (amélioration code existant)
