#!/bin/bash
# Resume GitHub quotidien pour l'org nqbai
# Cron: 7 9 * * * /home/jp/ai_automations/github-summary/daily-github-summary.sh

set -uo pipefail

DATE_SHORT=$(date -d "yesterday" +"%Y-%m-%d")
LOG_DIR="/home/jp/ai_automations/github-summary/logs"
LOG_FILE="$LOG_DIR/github-summary-${DATE_SHORT}.log"
TIMEOUT=600
LOCK_FILE="$LOG_DIR/.done-${DATE_SHORT}"
RUN_LOCK="/tmp/claude-github-summary.lock"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

if [ -f "$LOCK_FILE" ]; then
  log "Resume GitHub pour ${DATE_SHORT} deja envoye, on skip."
  exit 0
fi

if ! mkdir "$RUN_LOCK" 2>/dev/null; then
  log "Une autre instance est deja en cours, on skip."
  exit 0
fi
trap 'rmdir "$RUN_LOCK" 2>/dev/null' EXIT

source /home/jp/mcp/.env
export GOOGLE_OAUTH_CLIENT_ID GOOGLE_OAUTH_CLIENT_SECRET FIREFLIES_API_KEY GOOGLE_CHAT_WEBHOOK_URL

PROMPT="Résumé quotidien des avancements GitHub pour l'organisation nqbai. Tout en français avec les accents. Pas de em dash ni de point-virgule. 1) Déterminer la date d'hier en format ISO. 2) Lister tous les repos nqbai avec gh repo list. 3) Pour chaque repo, vérifier les commits et PRs d'hier avec gh api et gh pr list. 4) Ignorer les repos sans activité. Si aucun repo actif, écrire seulement AUCUNE_ACTIVITE. 5) Pour chaque repo actif, générer un résumé high-level en 2-3 phrases. 6) IMPORTANT: La sortie DOIT être UNIQUEMENT un JSON valide pour Google Chat webhook au format cards, tel que décrit dans le CLAUDE.md de ce répertoire. Aucun texte avant ou après le JSON."

log "=== DEBUT resume GitHub pour ${DATE_SHORT} ==="
log "Lancement de claude -p avec timeout de ${TIMEOUT}s..."

cd /home/jp/ai_automations/github-summary

SUMMARY_FILE="$LOG_DIR/summary-${DATE_SHORT}.txt"

CARD_FORMAT=$(cat /home/jp/ai_automations/github-summary/CLAUDE.md)

timeout "$TIMEOUT" claude -p "$PROMPT" --dangerously-skip-permissions \
  --append-system-prompt "$CARD_FORMAT" \
  >> "$SUMMARY_FILE" 2>&1
EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 124 ]; then
  log "=== TIMEOUT apres ${TIMEOUT}s ==="
  log "=== FIN ==="
  exit 1
elif [ "$EXIT_CODE" -ne 0 ]; then
  log "=== ERREUR (exit code: $EXIT_CODE) ==="
  log "=== FIN ==="
  exit 1
fi

log "Claude termine. Summary file: $(wc -c < "$SUMMARY_FILE") bytes"

if [ ! -s "$SUMMARY_FILE" ] || grep -q "AUCUNE_ACTIVITE" "$SUMMARY_FILE"; then
  log "Aucune activite detectee, pas de message envoye."
else
  # Nettoyer les backticks markdown et envoyer dans Google Chat via webhook
  PAYLOAD=$(sed 's/^```json//;s/^```//' "$SUMMARY_FILE")
  HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' \
    -X POST "$GOOGLE_CHAT_WEBHOOK_URL" \
    -H 'Content-Type: application/json' \
    -d "$PAYLOAD")
  if [ "$HTTP_CODE" = "200" ]; then
    log "Message envoye dans Google Chat (HTTP $HTTP_CODE)"
  else
    log "Erreur envoi Google Chat (HTTP $HTTP_CODE)"
  fi
fi

touch "$LOCK_FILE"
log "=== SUCCES ==="

log "=== FIN ==="
