#!/usr/bin/env bash
# Claude Code PostToolUse:ExitPlanMode hook. Intentionally NOT a plugin action — users must not be
# able to trigger it by hand. Opens the review pane in auto mode when a plan is approved inside a
# herdr pane. Always exits 0 so it can never block the agent.
set -u
input=$(cat 2>/dev/null || true)

[ "${HERDR_ENV:-}" = "1" ] || exit 0
[ -n "${HERDR_PANE_ID:-}" ] || exit 0
[ -n "${HERDR_SOCKET_PATH:-}" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/lib/common.sh" 2>/dev/null || exit 0

self="$HERDR_PANE_ID"
info=$("$H" pane get "$self" 2>/dev/null) || exit 0
ws=$(printf '%s' "$info" | jq -r '.result.pane.workspace_id // empty')
[ -n "$ws" ] || exit 0

# don't stack a second review pane if one is already open in this workspace.
[ -n "$(review_panes_in_ws "$ws")" ] && exit 0

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$cwd" ] || cwd=$(printf '%s' "$info" | jq -r '.result.pane.cwd // empty')

# Target the agent that exited plan mode explicitly ($self) — no inference — so it always reaches
# the right agent even when several run in the workspace. Placement/theme come from the plugin
# config ([plan-review] section); default is a floating popup that auto-closes after you send.
theme=$(cfg_get "" theme "")
placement=$(cfg_get plan-review placement popup)
direction=$(cfg_get plan-review direction right)
ratio=$(cfg_get plan-review ratio 0.6)

new=$(open_review_pane "$placement" "$direction" "$self" "$cwd" --focus \
  "LUMEN_REVIEW_MODE=auto" "LUMEN_REVIEW_TARGET=$self" "LUMEN_REVIEW_THEME=$theme") || true
[ "$placement" = split ] && [ "$direction" = right ] && [ -n "$new" ] && resize_to_fraction "$new" "$ratio"
exit 0
