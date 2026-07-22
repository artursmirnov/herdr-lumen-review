#!/usr/bin/env bash
# Add the PostToolUse:ExitPlanMode hook to Claude Code settings so plan approval auto-opens the
# review pane. Idempotent; backs up settings first.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/lib/common.sh"
command -v jq >/dev/null 2>&1 || die "jq is required"

SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
SCRIPT="$ROOT/hooks/on-plan-exit.sh"
CMD="bash '$SCRIPT'"

mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || printf '{}\n' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.lumen-review.bak"

tmp=$(mktemp)
jq --arg cmd "$CMD" '
  .hooks //= {}
  | .hooks.PostToolUse //= []
  | if any(.hooks.PostToolUse[]?; (.hooks // [])[]?.command == $cmd)
    then .
    else .hooks.PostToolUse += [{matcher: "ExitPlanMode", hooks: [{type: "command", command: $cmd, timeout: 10}]}]
    end
' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"

printf 'installed PostToolUse:ExitPlanMode hook in %s\n' "$SETTINGS"
printf '(backup: %s.lumen-review.bak)\n' "$SETTINGS"
printf 'restart your Claude Code session to pick it up.\n'
