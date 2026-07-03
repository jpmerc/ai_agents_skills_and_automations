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

IMPORTANT confirmation d'envoi: une fois le courriel RÉELLEMENT envoyé avec succès (outil d'envoi retourné sans erreur), imprime en toute dernière ligne, seule sur sa ligne, le marqueur exact: EMAIL_SENT_OK
Si l'envoi échoue ou est impossible (outil non connecté, etc.), n'imprime PAS ce marqueur et explique le problème.

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

set +e
timeout "$TIMEOUT" claude -p "$PROMPT" --dangerously-skip-permissions \
  --mcp-config /home/jp/mcp/mcp-config.json \
  >> "$LOG_FILE" 2>&1
EXIT_CODE=$?
set -e

# Le succes n'est reel que si le courriel a ete envoye. On ne cree le marqueur .done
# QUE si Claude a confirme l'envoi (marqueur EMAIL_SENT_OK), sinon le job reessaiera
# au prochain passage au lieu de croire a tort que c'est fait.
if [ "$EXIT_CODE" -eq 124 ]; then
  log "=== TIMEOUT après ${TIMEOUT}s (courriel non envoyé) ==="
elif [ "$EXIT_CODE" -ne 0 ]; then
  log "=== ERREUR (exit code: $EXIT_CODE, courriel non envoyé) ==="
elif grep -q "EMAIL_SENT_OK" "$LOG_FILE"; then
  touch "$LOCK_FILE"
  log "=== SUCCÈS (courriel envoyé) ==="
else
  log "=== ERREUR ENVOI: claude a terminé sans confirmer l'envoi (workspace-mcp déconnecté?). Pas de .done, réessai au prochain passage. ==="
fi

log "=== FIN ==="
