#!/bin/bash
# Test du resume GitHub - sans envoi Google Chat
# Vérifie que claude -p + gh fonctionne avec le GH_TOKEN

export PATH="$HOME/.local/bin:$HOME/.nvm/versions/node/v22.11.0/bin:$PATH"

set -uo pipefail

DATE_SHORT=$(date -d "yesterday" +"%Y-%m-%d")
LOG_DIR="/home/jp/ai_automations/github-summary/logs"

source /home/jp/mcp/.env
export GOOGLE_OAUTH_CLIENT_ID GOOGLE_OAUTH_CLIENT_SECRET FIREFLIES_API_KEY GOOGLE_CHAT_WEBHOOK_URL GH_TOKEN

SKILL=$(cat /home/jp/ai_automations/skills/github-summary.md)
PROMPT="Exécute ces instructions pour hier. La sortie DOIT être UNIQUEMENT un JSON valide pour Google Chat cards. Aucun texte avant ou après le JSON. Si aucune activité, écris seulement AUCUNE_ACTIVITE.

$SKILL"

CARD_FORMAT=$(cat /home/jp/ai_automations/github-summary/CLAUDE.md)

echo "=== TEST resume GitHub pour ${DATE_SHORT} ==="
echo "Lancement de claude -p avec timeout de 600s..."

cd /home/jp/ai_automations/github-summary

SUMMARY_FILE="$LOG_DIR/test-summary-${DATE_SHORT}.txt"
rm -f "$SUMMARY_FILE"

timeout 600 claude -p "$PROMPT" --dangerously-skip-permissions --effort max \
  --append-system-prompt "$CARD_FORMAT" \
  >> "$SUMMARY_FILE" 2>&1
EXIT_CODE=$?

echo "Exit code: $EXIT_CODE"
echo "Summary ($(wc -c < "$SUMMARY_FILE") bytes):"
echo "---"
cat "$SUMMARY_FILE"
echo "---"
