# Resume GitHub quotidien

Resume quotidien des avancements sur les repos de l'organisation GitHub nqbai.

## Arguments

$ARGUMENTS - Intervalle de temps (ex: "hier", "2026-01-15", "cette semaine"). Par defaut: "hier"

## Instructions

1. **Determiner l'intervalle de temps**
   - Si $ARGUMENTS est vide, utiliser "hier" par defaut
   - Le fuseau horaire de l'utilisateur est America/New_York (EDT, UTC-4)
   - Calculer les bornes UTC en tenant compte du fuseau EDT :
     - Debut : YYYY-MM-DDT04:00:00Z (minuit EDT = 04:00 UTC)
     - Fin : YYYY-MM-(DD+1)T04:00:00Z (minuit EDT suivant = 04:00 UTC du jour suivant)
   - Exemple pour "hier" le 1er avril : debut = 2026-03-31T04:00:00Z, fin = 2026-04-01T04:00:00Z

2. **Lister tous les repos de l'org nqbai**
   ```bash
   gh repo list nqbai --limit 50 --json name -q '.[].name'
   ```

3. **Pour chaque repo, verifier l'activite sur TOUTES les branches**

   ### 3a. Lister les branches du repo
   ```bash
   gh api repos/nqbai/{repo}/branches --jq '.[].name'
   ```

   ### 3b. Commits dans la periode (toutes les branches)
   Pour chaque branche, chercher les commits :
   ```bash
   gh api "repos/nqbai/{repo}/commits?sha={branche}&since=DATE_START&until=DATE_END" --jq '.[] | "\(.commit.author.name) [\(BRANCHE)]: \(.commit.message | split("\n")[0])"'
   ```
   Dedupliquer les commits qui apparaissent sur plusieurs branches (meme SHA).
   Indiquer le nom de la branche si ce n'est pas main/master.

   ### 3b. PRs merged dans la periode
   ```bash
   gh pr list --repo nqbai/{repo} --state merged --json title,author,mergedAt --jq '.[] | select(.mergedAt >= "DATE_START")'
   ```

   ### 3c. PRs ouvertes dans la periode
   ```bash
   gh pr list --repo nqbai/{repo} --state open --json title,author,createdAt --jq '.[] | select(.createdAt >= "DATE_START")'
   ```

4. **Ignorer les repos sans activite. Si AUCUN repo n'a eu d'activite, ne rien envoyer et terminer.**

5. **Pour chaque repo actif, generer un resume high-level**
   - 2-3 phrases qui expliquent comment le projet avance
   - Ne pas juste lister les commits, mais expliquer le progres
   - Ne pas mentionner Claude/AI dans les descriptions
   - Pas de em dash ni de point-virgule

6. **Formater le message**
   ```
   # Resume GitHub - [date]

   ## [Nom du repo 1]
   **Resume:** [2-3 phrases sur l'avancement du projet]

   **Commits:** [nombre]
   - [auteur]: [message]
   - ...

   **PRs:** [merged/ouvertes]
   - [titre] par [auteur]

   ## [Nom du repo 2]
   ...

   ---
   **Vue d'ensemble:** [1-2 phrases sur l'avancement general de l'equipe]
   ```

7. **Poster dans Google Chat**
   Envoyer le message dans le Google Chat space "nqb_github_summaries" en utilisant l'outil send_chat_message du workspace-mcp.

## Notes

- Tout en francais
- Concis et professionnel
- Ne pas mentionner Claude/AI
- Pas de em dash ni de point-virgule
