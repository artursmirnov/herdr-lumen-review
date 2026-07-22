# Shared helpers for the lumen-review herdr plugin.
# Sourced by the action scripts, the pane wrapper, and the Claude hook.

# herdr launches plugin commands with a minimal PATH; make lumen/jq/fzf resolve on common installs.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"

H="${HERDR_BIN_PATH:-herdr}"
# HERDR_PLUGIN_ID is present for actions/pane; the hook runs outside plugin context, so hardcode a fallback.
PLUGIN_ID="${HERDR_PLUGIN_ID:-artursmirnov.lumen-review}"
# Manifest pane entrypoint ids (herdr-plugin.toml [[panes]]).
SPLIT_ENTRYPOINT="changes"       # placement = split: persistent, listed in `pane list`
POPUP_ENTRYPOINT="plan-review"   # placement = popup: id-less, not listed, auto-closes on exit
# The split pane carries its manifest title as .label in `pane list`; keep in sync with the
# "changes" pane title.
PANE_LABEL="changes"

die() { printf 'lumen-review: %s\n' "$1" >&2; exit 1; }

# ---- config (config.toml in the plugin config dir; read by openers, not the pane) -----------------

_config_file() {  # cached; located via env in actions, via `plugin config-dir` in the hook
  if [ -z "${_CONFIG_FILE_CACHED:-}" ]; then
    local dir="${HERDR_PLUGIN_CONFIG_DIR:-}"
    [ -n "$dir" ] || dir=$("$H" plugin config-dir "$PLUGIN_ID" 2>/dev/null)
    _CONFIG_FILE_CACHED="${LUMEN_REVIEW_CONFIG:-$dir/config.toml}"
  fi
  printf '%s' "$_CONFIG_FILE_CACHED"
}

# Read one scalar from a flat TOML section. Section "" reads top-level keys (before the first [x]).
cfg_get() {  # $1 section  $2 key  $3 default
  local sec="$1" key="$2" def="$3" file val
  file=$(_config_file)
  [ -f "$file" ] || { printf '%s' "$def"; return; }
  val=$(awk -v sec="$sec" -v key="$key" '
    BEGIN { insec = (sec == "") }
    { line = $0 }
    line ~ /^[[:space:]]*#/ { next }
    line ~ /^[[:space:]]*\[/ {
      s = line; sub(/^[[:space:]]*\[/, "", s); sub(/\].*$/, "", s); gsub(/[[:space:]]/, "", s)
      insec = (s == sec); next
    }
    insec && line ~ ("^[[:space:]]*" key "[[:space:]]*=") {
      sub("^[[:space:]]*" key "[[:space:]]*=[[:space:]]*", "", line)
      sub(/[[:space:]]*#.*$/, "", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      gsub(/^"|"$/, "", line); gsub(/^\047|\047$/, "", line)
      print line; exit
    }
  ' "$file")
  [ -n "$val" ] && printf '%s' "$val" || printf '%s' "$def"
}

# ---- pane helpers --------------------------------------------------------------------------------

review_panes_in_ws() {  # $1 = workspace id -> newline-separated pane ids of our split review panes
  "$H" pane list --workspace "$1" 2>/dev/null \
    | jq -r --arg l "$PANE_LABEL" '.result.panes[] | select(.label == $l) | .pane_id'
}

close_panes() {  # pane ids on stdin. Plain `pane close`, not `plugin pane close`: the plugin-pane
                 # registry does not survive a herdr restart and would strand the pane.
  local p
  while IFS= read -r p; do [ -n "$p" ] && "$H" pane close "$p" >/dev/null 2>&1; done
}

# Width fraction of pane $1 within its tab (empty if unknown).
_pane_wfrac() {
  "$H" pane layout --pane "$1" 2>/dev/null \
    | jq -r --arg p "$1" '.result.layout as $l | (($l.panes[]|select(.pane_id==$p).rect.width)/$l.area.width) // empty'
}
_close_enough() { awk -v f="$1" -v t="$2" 'BEGIN{d=f-t; d=(d<0?-d:d); exit !(d<0.03)}'; }

# Size a side-by-side split so $1 occupies ~$2 of the tab width. `plugin pane open` has no size flag,
# and `pane resize --amount` is a layout-relative delta whose growth direction depends on where the
# pane sits (the review pane is rightmost, so "grow" is not simply "right"). So we PROBE to learn the
# grow direction, then converge — and stop (reverting the step) if a resize moves away from target,
# so a layout we can't control cleanly never diverges. Approximate; side-by-side splits only.
resize_to_fraction() {  # $1 pane  $2 target(0..1)
  local pane="$1" target="$2" grow shrink frac before after d dir prev now i
  awk -v t="$target" 'BEGIN{exit !(t ~ /^[0-9.]+$/ && t+0>0 && t+0<1)}' 2>/dev/null || return 0
  sleep 0.3
  frac=$(_pane_wfrac "$pane"); [ -n "$frac" ] || return 0
  _close_enough "$frac" "$target" && return 0

  before="$frac"
  "$H" pane resize --pane "$pane" --direction right --amount 0.08 >/dev/null 2>&1; sleep 0.2
  after=$(_pane_wfrac "$pane"); [ -n "$after" ] || return 0
  awk -v a="$after" -v b="$before" 'BEGIN{d=a-b; d=(d<0?-d:d); exit !(d<0.005)}' && return 0  # no effect
  if awk -v a="$after" -v b="$before" 'BEGIN{exit !(a>b)}'; then grow=right; shrink=left; else grow=left; shrink=right; fi

  for i in 1 2 3 4 5 6; do
    frac=$(_pane_wfrac "$pane"); [ -n "$frac" ] || return 0
    _close_enough "$frac" "$target" && return 0
    if awk -v t="$target" -v f="$frac" 'BEGIN{exit !(t>f)}'; then dir="$grow"; else dir="$shrink"; fi
    d=$(awk -v t="$target" -v f="$frac" 'BEGIN{d=t-f; d=(d<0?-d:d); if(d>0.3)d=0.3; printf "%.3f", d}')
    prev="$frac"
    "$H" pane resize --pane "$pane" --direction "$dir" --amount "$d" >/dev/null 2>&1; sleep 0.2
    now=$(_pane_wfrac "$pane"); [ -n "$now" ] || return 0
    if awk -v t="$target" -v n="$now" -v p="$prev" 'BEGIN{dn=(t-n<0?n-t:t-n); dp=(t-p<0?p-t:t-p); exit !(dn>dp+0.02)}'; then
      "$H" pane resize --pane "$pane" --direction "$([ "$dir" = right ] && echo left || echo right)" --amount "$d" >/dev/null 2>&1
      return 0   # moved away -> revert this step and stop rather than diverge
    fi
  done
}

# ---- agent resolution ----------------------------------------------------------------------------

# Agents scoped to a tab or workspace, as TSV "<pane_id>\t<display>". Display carries status, cwd and
# the terminal title so the fzf picker can tell several agents apart.
agents_in() {  # $1 scope(tab|workspace)  $2 id
  local field
  case "$1" in
    tab)       field="tab_id" ;;
    workspace) field="workspace_id" ;;
    *)         return 0 ;;
  esac
  [ -n "$2" ] || return 0
  "$H" agent list 2>/dev/null | jq -r --arg f "$field" --arg id "$2" '
    .result.agents[]
    | select(.[$f] == $id)
    | [ .pane_id,
        ( .pane_id + "  [" + (.agent_status // "?") + "]  "
          + (.cwd // "") + "  " + (.terminal_title_stripped // "") ) ]
    | @tsv'
}

# Resolve which agent pane to send annotations to. Prefer agents in the current tab, then the
# workspace. One candidate -> use it silently; several -> fzf pick (needs the pane's TTY); none, or
# fzf missing/cancelled -> echo nothing so the caller runs detached. Never guesses among several.
resolve_agent_target() {  # $1 tab(may be empty)  $2 ws(may be empty)  -> echoes a pane id or nothing
  local tab="$1" ws="$2" rows n choice
  rows=$(agents_in tab "$tab")
  [ -n "$rows" ] || rows=$(agents_in workspace "$ws")
  [ -n "$rows" ] || return 0
  n=$(printf '%s\n' "$rows" | grep -c .)
  if [ "$n" -eq 1 ]; then
    printf '%s\n' "$rows" | cut -f1
    return 0
  fi
  if ! command -v fzf >/dev/null 2>&1; then
    printf 'lumen-review: %s agents found but fzf is not installed; running detached.\n' "$n" >&2
    return 0
  fi
  choice=$(printf '%s\n' "$rows" \
    | fzf --delimiter='\t' --with-nth=2 --reverse --cycle --no-multi --no-sort \
          --prompt='send annotations to > ' \
          --header='pick the agent to attach to - esc = detached') || true
  [ -n "$choice" ] || return 0
  printf '%s\n' "$choice" | cut -f1
}

# ---- opening -------------------------------------------------------------------------------------

# Open a review pane. Any "KEY=VALUE" args after the fixed ones are passed through as --env, so the
# opener hands the wrapper exactly what it needs (mode, theme, and either an explicit target or the
# tab+ws to infer one). split -> a right/down split of $split_from (persistent, listed; size via
# resize_to_fraction afterwards); overlay -> a floating zoom over the active pane; popup -> a
# floating window sized from the manifest (id-less, auto-closes on exit).
open_review_pane() {  # $1 placement(split|popup|overlay)  $2 direction  $3 split_from  $4 cwd  $5 focus  $6.. KEY=VALUE
  local placement="$1" direction="$2" split_from="$3" cwd="$4" focus="$5"
  shift 5
  local entrypoint="$SPLIT_ENTRYPOINT"
  local -a args
  case "$placement" in
    popup)   entrypoint="$POPUP_ENTRYPOINT"; args=() ;;
    overlay) args=(--placement overlay) ;;
    *)       args=(--placement split --target-pane "$split_from" --direction "${direction:-right}") ;;
  esac
  local -a envs=()
  local kv
  for kv in "$@"; do envs+=(--env "$kv"); done
  "$H" plugin pane open --plugin "$PLUGIN_ID" --entrypoint "$entrypoint" \
    ${args[@]+"${args[@]}"} --cwd "$cwd" ${envs[@]+"${envs[@]}"} "$focus" 2>/dev/null \
    | jq -r '.result.plugin_pane.pane.pane_id // empty'
}
