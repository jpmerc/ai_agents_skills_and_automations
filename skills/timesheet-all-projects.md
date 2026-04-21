# Timesheet - Tous les projets

Génère une feuille de temps pour TOUS les projets sur lesquels l'utilisateur a travaillé durant la période spécifiée.

## Arguments

$ARGUMENTS - Intervalle de temps (ex: "hier", "2026-01-15", "cette semaine", "15-16 janvier")

## Instructions

1. **Déterminer l'intervalle de temps**
   - Si $ARGUMENTS est vide, utiliser "hier" par défaut
   - Interpréter les expressions comme "hier", "cette semaine", "les 3 derniers jours"
   - Le fuseau horaire de l'utilisateur est America/New_York (EDT, UTC-4)
   - Calculer les bornes UTC correspondantes (ex: 8h EDT = 12:00 UTC, minuit EDT = 04:00 UTC du jour suivant)

2. **Chercher TOUS les projets avec activité dans la période**

   ### 2a. Sessions Claude (toutes les sessions, tous les projets)
   Chercher dans `~/.claude/projects/` TOUS les dossiers de projets.
   Chercher les fichiers .jsonl (exclure subagents/) avec des timestamps dans la période.
   Extraire les messages type "user" pour comprendre le travail effectué.
   Calculer le temps actif : somme des gaps entre messages consécutifs <= 15min.
   - IMPORTANT : les timestamps dans les .jsonl sont en UTC. Convertir en EDT pour l'affichage.
   - IMPORTANT : vérifier aussi les timestamps UTC du jour SUIVANT avant 04:00 (= soirée EDT du jour cible)
   - IMPORTANT : chercher dans TOUS les dossiers de projets, incluant ceux liés à ~/Documents/NQB/dev/ ET ~/ai_automations/
   - Ne pas ignorer les périodes où des réunions ont lieu, l'utilisateur peut travailler en parallèle

   ### 2b. Commits git (tous les repos)
   Chercher dans TOUS les repos git sous `~/Documents/NQB/dev/` ET `~/ai_automations/` :
   ```bash
   find ~/Documents/NQB/dev -maxdepth 6 -name ".git" -type d | while read gitdir; do
     repo=$(dirname "$gitdir")
     commits=$(cd "$repo" && git log --all --since="<date_debut>" --until="<date_fin>" --format="%h %ai %s")
     if [ -n "$commits" ]; then echo "=== $repo ==="; echo "$commits"; fi
   done
   ```

   ### 2c. Réunions (Google Calendar)
   Utiliser `mcp__claude_ai_Google_Calendar__gcal_list_events` pour lister les événements de la journée.

   ### 2d. Transcripts de réunions (Fireflies)
   Utiliser `mcp__claude_ai_Fireflies__fireflies_search` avec `from:<date> to:<date+1> mine:true` pour trouver les réunions enregistrées et leurs résumés.

   ### 2e. ActivityWatch (temps ecran par app/site)
   DB: `~/.local/share/activitywatch/aw-server/peewee-sqlite.v2.db`
   Tables: `bucketmodel` (buckets) et `eventmodel` (events)
   - bucket_id=1 : aw-watcher-window (app active et titre de fenetre)
   - bucket_id=2 : aw-watcher-afk (status actif/inactif)
   - Chaque event : timestamp (UTC), duration (secondes), datastr (JSON avec "app" et "title")
   - Requete pour une journee :
     ```sql
     SELECT timestamp, duration, datastr FROM eventmodel
     WHERE bucket_id = 1
     AND timestamp >= '<date_debut_utc>' AND timestamp < '<date_fin_utc>'
     ORDER BY timestamp
     ```
   - IMPORTANT : les timestamps AW sont en UTC mais la journee de travail est en EST/EDT. Filtrer STRICTEMENT avec les bornes UTC converties (ex: 2 avril 8h EDT = 2 avril 12:00 UTC, 2 avril minuit EDT = 3 avril 04:00 UTC). Ne jamais inclure des events hors de ces bornes. Si aucun event ne tombe dans la periode, ne pas utiliser AW pour cette timesheet.
   - Grouper par app/titre pour identifier le temps passe sur chaque site/outil
   - Particulierement utile pour le temps sur des onglets web (Heyreach, Gojiberry, LinkedIn, etc.) non captures par sessions Claude ou commits git
   - Croiser avec bucket_id=2 (afk) pour exclure le temps inactif

3. **Estimer le temps réel par projet**
   - Temps actif = somme des gaps entre messages consécutifs <= 15 min
   - Ajouter ~20% pour réflexion/tests entre les interactions
   - Pour les réunions : utiliser la durée Fireflies ou la durée Calendar
   - Utiliser ActivityWatch pour valider/completer les estimations et capturer le travail web non trace ailleurs
   - Afficher aussi l'activité par heure si utile pour la validation

4. **Générer le résumé**

   Format de sortie :
   ```
   ## Période: [dates]

   ### [Projet 1]
   **Commits:** [nombre]
   - [liste des commits pertinents]

   **Travail effectué:** [résumé en 1-2 lignes pour feuille de temps]

   **Temps estimé:** [X]h - [Y]h

   ### [Réunion 1]
   **Durée:** [X] min ([heure début]-[heure fin] EDT)
   **Participants:** [liste]

   **Travail effectué:** [résumé basé sur Fireflies si disponible]

   **Temps estimé:** [X]h

   ### Total
   **Temps total estimé:** [X]h - [Y]h
   ```

5. **Envoyer par courriel (si demandé ou si --email)**
   Utiliser `mcp__workspace-mcp__send_gmail_message` pour envoyer à jp.mercier@nqb.ai avec :
   - Sujet : "Feuille de temps - [date(s)]"
   - `body_format: "html"` (OBLIGATOIRE, Gmail ne rend pas le markdown)
   - `body` : convertir la feuille de temps en HTML simple et lisible dans Gmail :
     - `##` devient `<h2>`, `###` devient `<h3>`
     - `**texte**` devient `<strong>texte</strong>`
     - Listes `-` deviennent `<ul><li>...</li></ul>`
     - Paragraphes entourés de `<p>...</p>`
     - Séparer les sections avec des sauts de ligne HTML, pas des `---`
     - Garder le HTML minimal, pas de CSS inline complexe, Gmail s'occupe du rendu

## Notes

- Tout en français
- Les résumés doivent être concis et professionnels (pour client)
- Ne pas mentionner Claude/AI dans les descriptions
- Grouper le travail par fonctionnalité/thème plutôt que par commit
- Ne pas utiliser de em dash (—) ni de point-virgule (;)
- À la fin du résumé, ajouter une ligne unique résumant tous les travaux en une énumération séparée par des virgules
