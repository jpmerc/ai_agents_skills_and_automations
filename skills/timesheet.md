# Timesheet

Génère un résumé du travail effectué sur le projet pour une feuille de temps.

## Arguments

$ARGUMENTS - Intervalle de temps (ex: "hier", "2026-01-15", "cette semaine", "15-16 janvier")

## Instructions

1. **Déterminer l'intervalle de temps**
   - Si $ARGUMENTS est vide, demande à l'utilisateur la période souhaitée
   - Interpréter les expressions comme "hier", "cette semaine", "les 3 derniers jours"

2. **Analyser l'historique des commits git**
   ```bash
   git log --since="<date_debut>" --until="<date_fin>" --format="%h %ad %s" --date=short
   ```
   - Regrouper les commits par sous-projet/dossier si applicable
   - Noter les types de travail (feat, fix, docs, refactor)

3. **Consulter l'historique des sessions Claude**
   - Chercher dans `~/.claude/projects/` le dossier correspondant au projet courant
   - Lire le fichier `sessions-index.json` pour trouver les sessions dans l'intervalle
   - Extraire les messages utilisateur des fichiers `.jsonl` pour comprendre le travail effectué
   - Noter les timestamps created/modified de chaque session

4. **Consulter ActivityWatch (temps ecran par app/site)**
   - DB: `~/.local/share/activitywatch/aw-server/peewee-sqlite.v2.db`
   - Tables: `bucketmodel` (buckets) et `eventmodel` (events)
   - bucket_id=1 : aw-watcher-window (app et titre de fenetre active)
   - bucket_id=2 : aw-watcher-afk (status actif/inactif)
   - Chaque event a: timestamp (UTC), duration (secondes), datastr (JSON avec "app" et "title")
   - Requete pour une journee :
     ```sql
     SELECT timestamp, duration, datastr FROM eventmodel
     WHERE bucket_id = 1
     AND timestamp >= '<date_debut_utc>' AND timestamp < '<date_fin_utc>'
     ORDER BY timestamp
     ```
   - Grouper par app/titre pour identifier le temps passe sur chaque site/outil
   - Particulierement utile pour le temps passe sur des onglets web (Heyreach, Gojiberry, LinkedIn, etc.) qui ne sont pas captures par les sessions Claude ou les commits git
   - Croiser avec bucket_id=2 (afk) pour exclure le temps inactif

5. **Estimer le temps réel**
   Pour chaque session:
   - Temps session = modified - created
   - Si "continuation" mentionnée, ajouter ~30-60 min pour la session précédente
   - Ajouter ~20% pour réflexion/tests entre les interactions
   - Croiser avec les donnees ActivityWatch pour valider/completer les estimations

   Facteurs à considérer:
   - Nombre de messages (plus = plus de temps)
   - Complexité des tâches (création vs correction)
   - Gaps entre sessions (temps de test/réflexion)
   - Temps ActivityWatch sur des apps/sites non captures par Claude ou git

5. **Générer le résumé**

   Format de sortie:
   ```
   ## Période: [dates]

   ### [Sous-projet 1]
   **Commits:** [nombre]
   - [liste des commits pertinents]

   **Travail effectué:** [résumé en 1-2 lignes pour feuille de temps]

   **Temps estimé:** [X]h - [Y]h

   ### [Sous-projet 2]
   ...

   ### Total
   **Temps total estimé:** [X]h - [Y]h
   ```

## Notes

- Les résumés doivent être concis et professionnels (pour client)
- Ne pas mentionner Claude/AI dans les descriptions
- Grouper le travail par fonctionnalité/thème plutôt que par commit
- À la fin du résumé, ajouter une ligne unique résumant tous les travaux en une énumération séparée par des virgules (ex: "Maintenance env dev, développement API auth, correction bug filtrage, refactoring module X")
