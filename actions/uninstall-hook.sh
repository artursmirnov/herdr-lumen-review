#!/usr/bin/env bash
# Remove the PostToolUse:ExitPlanMode hook this plugin installed from Claude Code settings.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/lib/common.sh"
command -v jq >/dev/null 2>&1 || die "jq is required"

SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
SCRIPT="$ROOT/hooks/on-plan-exit.sh"
CMD="bash '$SCRIPT'"

[ -f "$SETTINGS" ] || { printf 'nothing to remove (%s not found)\n' "$SETTINGS"; exit 0; }
cp "$SETTINGS" "$SETTINGS.lumen-review.bak"

tmp=$(mktemp)
jq --arg cmd "$CMD" '
  if .hooks.PostToolUse
  then .hooks.PostToolUse |= (map(.hooks |= map(select(.command != $cmd)))
                             | map(select((.hooks // []) | length > 0)))
  else .
  end
' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"

printf 'removed lumen-review hook from %s\n' "$SETTINGS"
printf 'restart your Claude Code session to apply.\n'
