# Resume GitHub quotidien

Resume quotidien des avancements sur les repos de l'organisation GitHub nqbai.

## Arguments

$ARGUMENTS - Intervalle de temps (ex: "dernieres 24h", "hier", "2026-01-15", "cette semaine"). Par defaut: "dernieres 24h"

## Instructions

1. **Determiner l'intervalle de temps**
   - Si $ARGUMENTS est vide, utiliser "dernieres 24h" par defaut (fenetre glissante)
   - Le fuseau horaire de l'utilisateur est America/New_York (EDT, UTC-4)
   - **Cas "dernieres 24h" (defaut)** : fenetre glissante de maintenant - 24h jusqu'a maintenant, en UTC.
     - Debut : `date -u -d "24 hours ago" +"%Y-%m-%dT%H:%M:%SZ"`
     - Fin : `date -u +"%Y-%m-%dT%H:%M:%SZ"`
     - Pour le titre de la card, utiliser la date locale courante (EDT) avec mention "24h".
   - **Cas date specifique ("hier", "YYYY-MM-DD")** : bornes calendaires en EDT.
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
   Pour chaque branche, chercher les commits (titre / premiere ligne uniquement) :
   ```bash
   gh api "repos/nqbai/{repo}/commits?sha={branche}&since=DATE_START&until=DATE_END" --jq '.[] | "\(.commit.author.name) [\(BRANCHE)]: \(.commit.message | split("\n")[0])"'
   ```
   Dedupliquer les commits qui apparaissent sur plusieurs branches (meme SHA).
   Indiquer le nom de la branche si ce n'est pas main/master.

   ### 3c. PRs merged dans la periode
   ```bash
   gh pr list --repo nqbai/{repo} --state merged --json number,title,author,mergedAt,headRefName --jq '.[] | select(.mergedAt >= "DATE_START")'
   ```

   ### 3d. PRs ouvertes dans la periode
   ```bash
   gh pr list --repo nqbai/{repo} --state open --json number,title,author,createdAt,headRefName --jq '.[] | select(.createdAt >= "DATE_START")'
   ```

   **Important** : ne PAS recuperer les bodies de PR ni les messages complets de commits (textes souvent vides ou bruyants).

   ### 3e. Diff / fichiers modifies par PR mergee (pour la section "Changements effectues")
   Cette etape est ce qui permet de decrire avec precision le QUOI a partir du vrai code modifie, pas juste du titre.

   Pour chaque PR mergee dans la fenetre :
   1. Recuperer les stats et la liste de fichiers :
      ```bash
      gh api "repos/nqbai/{repo}/pulls/{N}" --jq '{additions, deletions, changed_files}'
      gh api "repos/nqbai/{repo}/pulls/{N}/files" --jq '.[] | {path: .filename, additions, deletions, status}'
      ```
   2. **Decision sur le diff** :
      - Si `additions + deletions <= 500` : recuperer le diff complet `gh pr diff {N} --repo nqbai/{repo}`
      - Sinon : recuperer SEULEMENT les patches des fichiers "principaux" (skip lock files, generated, migrations volumineuses, fixtures, snapshots, dossiers `dist/`, `build/`, `node_modules/`, `vendor/`).
        ```bash
        gh api "repos/nqbai/{repo}/pulls/{N}/files" --jq '.[] | select(.filename | test("(package-lock|yarn.lock|pnpm-lock|poetry.lock|Cargo.lock|\.snap$|dist/|build/|generated/|node_modules/|vendor/)") | not) | {path: .filename, patch}'
        ```
      - Si la PR est tres grosse (> 3000 lignes), se contenter de la liste de fichiers + stats sans patches.

   ### 3f. Diff des commits hors PR (commits direct-to-main, "quick-task", etc.)
   Pour les commits qui ne sont rattaches a aucune PR de la fenetre :
   ```bash
   gh api "repos/nqbai/{repo}/commits/{SHA}" --jq '{stats, files: [.files[] | {path: .filename, additions, deletions, patch}]}'
   ```
   Memes regles de taille : full patch si petit, stats seuls si gros.

   ### 3g. Limites globales
   - Skipper les patches de fichiers > 200 lignes individuellement (juste mentionner le nom).
   - Total des diffs par repo : viser < 30K caracteres ; au-dela, basculer sur "stats + noms de fichiers principaux" sans contenu.

4. **Ignorer les repos sans activite. Si AUCUN repo n'a eu d'activite, ne rien envoyer et terminer.**

5. **Pour chaque repo actif, generer le contenu**

   **(a) Resume high-level** (2-3 phrases)
   - Vision d'ensemble de l'avancement du projet sur la periode
   - Pas une liste de commits, mais une synthese du progres

   **(b) Changements effectues** (section cle pour les dirigeants)
   - Audience : dirigeants non-techniques (jp + associe) qui veulent comprendre ce qui a ete fait sans parler aux devs et detecter une derive de direction.
   - Objectif : description riche et concrete de ce qui a ete fait, pas une paraphrase du titre.
   - **Sources** : utiliser le **vrai diff** (etapes 3e/3f) en plus des titres et noms de branches. Le diff est ce qui permet de dire des choses precises comme "ajout de 4 endpoints API pour le pricing public" ou "nouvelle table `roles_permissions` avec 8 roles", au lieu de "ajout du self-serve".
   - Regrouper par changement logique, PAS par commit. Plusieurs commits/PRs qui pointent vers le meme effort vont ensemble.
   - Pour chaque entree, viser 1 a 3 phrases :
     - **Quoi** : description fonctionnelle precise, ancree dans le code reel (nouvelles routes, modeles, integrations externes, ecrans, jobs, etc.). Eviter les noms de fonctions internes, prefere les capacites visibles. Si le diff montre par exemple un nouveau modele `Role` avec des permissions, ecrire "8 roles avec permissions granulaires (admin, billing, support, ...)" et pas "modele Role.ts ajoute".
     - **Pourquoi** : seulement si raisonnablement inferable du titre, branche, ou contenu du diff (ex: nouveau code Stripe = monetisation). Si non inferable, OMETTRE le pourquoi (pas d'invention, pas de "raison non documentee" partout).
     - **Type** entre crochets : `[feat]`, `[fix]`, `[refactor]`, `[chore]`, `[docs]`, `[test]`.
     - **Auteur** principal entre parentheses a la fin.
   - Format :
     - Avec pourquoi inferable : `[type] **Quoi (description riche).** Pourquoi (auteur)`
     - Sans pourquoi : `[type] **Quoi (description riche)** (auteur)`
     - Exemples enrichis :
       - `[feat] **Lancement self-serve : 6 nouveaux endpoints API publics pour pricing/checkout, integration Stripe pour la facturation a l'usage, page d'inscription publique avec verification email.** Ouverture du produit au self-serve sans intervention commerciale (Marie)`
       - `[fix] **Correction du calcul de TPS sur remboursements partiels : la taxe etait calculee sur le montant initial au lieu du montant rembourse.** Bug remonte par la comptabilite (Alex)`
       - `[refactor] **Decoupage du module auth en 3 sous-services (sessions, tokens, MFA), avec migration des appelants** (Tom)`
   - Si un changement semble risque ou inhabituel (suppression massive de code, modif facturation/auth/donnees sensibles, refactor majeur sans contexte, secrets en clair, dependance suspecte ajoutee), prefixer la ligne avec `⚠`.
   - Limiter a 6 entrees principales par repo. Si plus, regrouper les mineurs : `[chore] Divers (N commits): tests, docs, dependances`.

   **Regles generales**
   - Ne pas mentionner Claude/AI dans les descriptions
   - Pas de em dash ni de point-virgule
   - Tout en francais avec accents

6. **Formater le message**
   La sortie finale doit etre du JSON Google Chat cards (voir CLAUDE.md du projet github-summary pour la structure exacte).
   La structure logique par repo :
   ```
   ## [Nom du repo 1]
   **Resume:** [2-3 phrases sur l'avancement du projet]

   **Changements effectues:**
   - [type] **Quoi.** Pourquoi (auteur)
   - [type] **Quoi** (auteur)
   - ...

   **Commits ([nombre]):**
   - [auteur]: [message premiere ligne]
   - ...

   **PRs (merged/ouvertes):**
   - [titre] par [auteur]

   ## [Nom du repo 2]
   ...

   ---
   **Vue d'ensemble:** [1-2 phrases factuelles sur l'avancement general de l'equipe. Pas de questions, pas de "a valider" - les changements a surveiller sont deja signales par un prefixe ⚠ dans les entrees individuelles]
   ```

7. **Poster dans Google Chat**
   Envoyer le message dans le Google Chat space "nqb_github_summaries" en utilisant l'outil send_chat_message du workspace-mcp.

## Notes

- Tout en francais
- Concis et professionnel
- Ne pas mentionner Claude/AI
- Pas de em dash ni de point-virgule
