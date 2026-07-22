#!/usr/bin/env bash
# Open the review pane, or close it if one is already open in this workspace.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/lib/common.sh"

ws="${HERDR_WORKSPACE_ID:-}"
[ -n "$ws" ] || die "no workspace context"

existing=$(review_panes_in_ws "$ws")
if [ -n "$existing" ]; then
  printf '%s\n' "$existing" | close_panes
  printf 'closed in %s\n' "$ws"
else
  exec bash "$ROOT/actions/open.sh"
fi
