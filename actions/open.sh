#!/usr/bin/env bash
# Open the review pane. The forward target is NOT decided here (a non-agent pane may be focused);
# the wrapper infers it from the tab/workspace we pass. Placement/direction/ratio/theme come from
# the plugin config (config.toml, [changes] section). We split beside the focused pane for layout.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/lib/common.sh"

ws="${HERDR_WORKSPACE_ID:-}"
[ -n "$ws" ] || die "no workspace context (invoke inside herdr)"

if [ -n "$(review_panes_in_ws "$ws")" ]; then
  printf 'already open in %s\n' "$ws"; exit 0
fi

split_from="${HERDR_PANE_ID:-}"
[ -n "$split_from" ] || split_from=$("$H" pane list --workspace "$ws" 2>/dev/null | jq -r '.result.panes[0].pane_id // empty')
[ -n "$split_from" ] || die "no pane to split from in $ws"

tab="${HERDR_TAB_ID:-}"
[ -n "$tab" ] || tab=$("$H" pane get "$split_from" 2>/dev/null | jq -r '.result.pane.tab_id // empty')

cwd=""
[ -n "${HERDR_PLUGIN_CONTEXT_JSON:-}" ] &&
  cwd=$(printf '%s' "$HERDR_PLUGIN_CONTEXT_JSON" | jq -r '.focused_pane_cwd // .workspace_cwd // empty')
[ -n "$cwd" ] || cwd=$("$H" pane get "$split_from" 2>/dev/null | jq -r '.result.pane.cwd // empty')

theme=$(cfg_get "" theme "")
placement=$(cfg_get changes placement split)
direction=$(cfg_get changes direction right)
ratio=$(cfg_get changes ratio 0.6)

new=$(open_review_pane "$placement" "$direction" "$split_from" "$cwd" --focus \
  "LUMEN_REVIEW_MODE=manual" "LUMEN_REVIEW_WS=$ws" "LUMEN_REVIEW_TAB=$tab" "LUMEN_REVIEW_THEME=$theme")
[ -n "$new" ] || die "herdr plugin pane open failed"

# Apply the configured width for a side-by-side split (herdr has no size flag at open time).
[ "$placement" = split ] && [ "$direction" = right ] && resize_to_fraction "$new" "$ratio"

printf 'opened %s in %s\n' "$new" "$ws"
