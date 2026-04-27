#!/bin/bash
# Resume GitHub quotidien pour l'org nqbai
# Cron: 15 21 * * * /home/jp/ai_automations/github-summary/daily-github-summary.sh

export PATH="$HOME/.local/bin:$HOME/.nvm/versions/node/v22.11.0/bin:$PATH"

set -uo pipefail

DATE_SHORT=$(date +"%Y-%m-%d")
LOG_DIR="/home/jp/ai_automations/github-summary/logs"
LOG_FILE="$LOG_DIR/github-summary-${DATE_SHORT}.log"
TIMEOUT=600
LOCK_FILE="$LOG_DIR/.done-${DATE_SHORT}"
RUN_LOCK="/tmp/claude-github-summary.lock"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

if [ -f "$LOCK_FILE" ]; then
  log "Resume GitHub deja envoye pour la run du ${DATE_SHORT}, on skip."
  exit 0
fi

if ! mkdir "$RUN_LOCK" 2>/dev/null; then
  log "Une autre instance est deja en cours, on skip."
  exit 0
fi
trap 'rmdir "$RUN_LOCK" 2>/dev/null' EXIT

source /home/jp/mcp/.env
export GOOGLE_OAUTH_CLIENT_ID GOOGLE_OAUTH_CLIENT_SECRET FIREFLIES_API_KEY GOOGLE_CHAT_WEBHOOK_URL GH_TOKEN

SKILL=$(cat /home/jp/ai_automations/skills/github-summary.md)
PROMPT="Exécute ces instructions pour les dernières 24 heures (fenêtre glissante: maintenant - 24h jusqu'à maintenant, en UTC). La sortie DOIT être UNIQUEMENT un JSON valide pour Google Chat cards. Aucun texte avant ou après le JSON. Si aucune activité, écris seulement AUCUNE_ACTIVITE.

$SKILL"

log "=== DEBUT resume GitHub (24h glissantes) - run ${DATE_SHORT} ==="
log "Lancement de claude -p avec timeout de ${TIMEOUT}s..."

cd /home/jp/ai_automations/github-summary

SUMMARY_FILE="$LOG_DIR/summary-${DATE_SHORT}.txt"

CARD_FORMAT=$(cat /home/jp/ai_automations/github-summary/CLAUDE.md)

timeout "$TIMEOUT" claude -p "$PROMPT" --dangerously-skip-permissions --effort max \
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
  # Extraire le JSON du summary (ignorer texte et backticks autour)
  PAYLOAD=$(python3 -c "
import re, sys
text = open('$SUMMARY_FILE').read()
match = re.search(r'\{.*\}', text, re.DOTALL)
if match:
    print(match.group())
else:
    sys.exit(1)
" 2>/dev/null)
  if [ -z "$PAYLOAD" ]; then
    log "Erreur: impossible d'extraire le JSON du summary"
    touch "$LOCK_FILE"
    log "=== FIN ==="
    exit 1
  fi
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
