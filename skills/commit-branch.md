# Commit Branch

Crée une branche, fait les commits, revient à la branche d'origine, merge, et attend confirmation pour push.

## Instructions

1. Exécute `git status` et `git diff` pour analyser les changements
2. Ignore les fichiers temporaires, .zip, .pyc, __pycache__, etc.
3. Détermine la branche courante (`git branch --show-current`) — c'est la **branche d'origine**
4. **Crée une nouvelle branche** à partir des changements détectés:
   - Nomme-la selon le pattern: `<type>/<description-courte-en-kebab-case>`
   - Types: `feature`, `fix`, `refactor`, `chore`, `docs`
   - Exemple: `feature/add-json-export`, `fix/incoming-call-routing`
5. **Segmente en plusieurs commits** si nécessaire:
   - Les changements concernent des fonctionnalités différentes
   - Certains fichiers sont de la documentation vs du code
   - Les modifications sont indépendantes et plus claires séparément
6. Pour chaque commit:
   - Ajoute uniquement les fichiers concernés
   - Crée un message court et descriptif en anglais
   - Ne mentionne PAS "Claude", "Anthropic", ou "Co-Authored-By"
7. Garde les messages concis (une ligne, max 72 caractères)
8. **Reviens à la branche d'origine** (`git checkout <branche-origine>`)
9. **Merge la branche** (`git merge <nouvelle-branche>`)
10. **Affiche un résumé** de ce qui a été fait et **demande confirmation avant de push**

## Format du message de commit

```
<type>: <description courte>
```

Types: feat, fix, docs, refactor, style, test, chore

## Format du résumé final

```
Branche créée: <nom-branche>
Commits: <nombre> commit(s)
Merge dans: <branche-origine>

Prêt à push. Confirmer ? (git push origin <branche-origine>)
```
