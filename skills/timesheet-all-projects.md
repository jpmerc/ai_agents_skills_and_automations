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
   Chercher dans `~/.claude/projects/` TOUS les dossiers de projets :
   ```python
   # Pour chaque fichier .jsonl (exclure subagents/), chercher les timestamps dans la période
   # Extraire les messages type "user" pour comprendre le travail effectué
   # Calculer le temps actif : somme des gaps entre messages consécutifs <= 15min
   ```
   - IMPORTANT : les timestamps dans les .jsonl sont en UTC. Convertir en EDT pour l'affichage.
   - IMPORTANT : vérifier aussi les timestamps UTC du jour SUIVANT avant 04:00 (= soirée EDT du jour cible)

   ### 2b. Commits git (tous les repos)
   Chercher dans TOUS les repos git sous `~/Documents/NQB/dev/` :
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

3. **Estimer le temps réel par projet**
   - Temps actif = somme des gaps entre messages consécutifs <= 15 min
   - Ajouter ~20% pour réflexion/tests entre les interactions
   - Pour les réunions : utiliser la durée Fireflies ou la durée Calendar
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
   Utiliser `mcp__claude_ai_Gmail__gmail_create_draft` ou envoyer directement à jp.mercier@nqb.ai avec :
   - Sujet : "Feuille de temps - [date(s)]"
   - Corps : la feuille de temps complète

## Notes

- Tout en français
- Les résumés doivent être concis et professionnels (pour client)
- Ne pas mentionner Claude/AI dans les descriptions
- Grouper le travail par fonctionnalité/thème plutôt que par commit
- Ne pas utiliser de em dash (—) ni de point-virgule (;)
- À la fin du résumé, ajouter une ligne unique résumant tous les travaux en une énumération séparée par des virgules
