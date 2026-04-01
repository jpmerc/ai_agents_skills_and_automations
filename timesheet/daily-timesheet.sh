#!/bin/bash
# Feuille de temps quotidienne automatique
# Cron: 3 8 * * * /home/jp/ai_automations/timesheet/daily-timesheet.sh

export PATH="$HOME/.local/bin:$HOME/.nvm/versions/node/v22.11.0/bin:$PATH"

set -euo pipefail

DATE_SHORT=$(date -d "yesterday" +"%Y-%m-%d")
LOG_DIR="/home/jp/ai_automations/timesheet/logs"
LOG_FILE="$LOG_DIR/timesheet-${DATE_SHORT}.log"
TIMEOUT=600  # 10 minutes max

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

SKILL=$(cat /home/jp/ai_automations/skills/timesheet-all-projects.md)
PROMPT="Exécute ces instructions pour hier. Envoyer le courriel directement (pas un brouillon) à jp.mercier@nqb.ai via gmail_send_message (PAS gmail_create_draft). Sujet: Feuille de temps - ${DATE_SHORT}

$SKILL"

LOCK_FILE="$LOG_DIR/.done-${DATE_SHORT}"
RUN_LOCK="/tmp/claude-timesheet.lock"

if [ -f "$LOCK_FILE" ]; then
  log "Timesheet pour ${DATE_SHORT} deja envoye, on skip."
  exit 0
fi

if ! mkdir "$RUN_LOCK" 2>/dev/null; then
  log "Une autre instance est deja en cours, on skip."
  exit 0
fi
trap 'rmdir "$RUN_LOCK" 2>/dev/null' EXIT

source /home/jp/mcp/.env
export GOOGLE_OAUTH_CLIENT_ID GOOGLE_OAUTH_CLIENT_SECRET FIREFLIES_API_KEY

log "=== DÉBUT timesheet pour ${DATE_SHORT} ==="
log "Lancement de claude -p avec timeout de ${TIMEOUT}s..."

cd /home/jp/ai_automations/timesheet

if timeout "$TIMEOUT" claude -p "$PROMPT" --dangerously-skip-permissions --effort max \
  --mcp-config /home/jp/mcp/mcp-config.json \
  >> "$LOG_FILE" 2>&1; then
  touch "$LOCK_FILE"
  log "=== SUCCÈS ==="
else
  EXIT_CODE=$?
  if [ "$EXIT_CODE" -eq 124 ]; then
    log "=== TIMEOUT après ${TIMEOUT}s ==="
  else
    log "=== ERREUR (exit code: $EXIT_CODE) ==="
  fi
fi

log "=== FIN ==="
