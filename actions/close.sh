#!/usr/bin/env bash
# Close every review pane in this workspace.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/lib/common.sh"

ws="${HERDR_WORKSPACE_ID:-}"
[ -n "$ws" ] || die "no workspace context"

existing=$(review_panes_in_ws "$ws")
[ -n "$existing" ] || { printf 'nothing open in %s\n' "$ws"; exit 0; }
printf '%s\n' "$existing" | close_panes
printf 'closed in %s\n' "$ws"
