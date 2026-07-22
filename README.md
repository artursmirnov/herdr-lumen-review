# herdr-lumen-review

Review your agent's diff with [lumen](https://github.com/jnsahaj/lumen) in a
side pane and send the line annotations straight back into the agent's prompt —
a [herdr](https://herdr.dev) plugin.

Your agent writes code in one pane. A keystroke opens `lumen diff --watch` in a
right split; you walk the diff, annotate lines/hunks/files, and press `s` →
`Enter`. lumen's annotations land in the agent's input and submit. Optionally,
the pane opens itself the moment the agent leaves plan mode, and closes itself
once you send.

## Prerequisites

- `herdr` ≥ 0.7.5
- `lumen` on `PATH` — [install instructions](https://github.com/jnsahaj/lumen).
  **Not bundled**; the plugin calls your system binary.
- `jq` (used by the action scripts)
- `fzf` (only for choosing among multiple agents; without it, that case runs
  detached — see Behavior)

## Install

```sh
herdr plugin install artursmirnov/herdr-lumen-review
```

## Keybinding

Bind the toggle action in `~/.config/herdr/config.toml`:

```toml
[[keys.command]]
key = "prefix+l"
type = "plugin_action"
command = "artursmirnov.lumen-review.toggle"
```

Reload with `herdr server reload-config`.

## Behavior

- **Toggle / open / close** — the pane opens as a **right split** of the focused
  pane and runs `lumen diff --watch`.
- **Target agent** — the agent that receives annotations is inferred, never the
  focused pane: the single agent in the **current tab**, else the **workspace**.
  If several agents qualify, an **fzf** picker lets you choose one; if none are
  running, the pane runs **detached** (see below).
- **What's reviewed** — the resolved **agent's** git diff: the pane `cd`s into
  the agent's working dir, so you review what *that* agent changed, not wherever
  you triggered from. The agent's dir must be inside a **git repo** — if it
  isn't, the pane shows a "not a git repository" notice and stays open (it never
  just blinks shut).
- **On send** (`s` → `Enter` in lumen) — annotations are submitted into the
  resolved agent via `herdr agent prompt`. In manual mode the viewer
  **relaunches** so you keep reviewing; quit with `q` to close the pane.
- **Annotations never vanish** — with no agent to send to, lumen runs detached
  and prints annotations to stdout (this pane's scrollback). If a send fails
  (e.g. the agent exited), the text is shown and the pane is held open until you
  dismiss it.
- **Auto-open on plan approval** (optional) — install the Claude Code hook and a
  review **popup** (a floating window over the agent pane, not a split) opens
  automatically when the agent exits plan mode, then **closes itself** after you
  send once:

  ```sh
  # via the command palette / action runner:
  lumen review: install plan-exit hook (Claude Code)
  lumen review: uninstall plan-exit hook (Claude Code)
  ```

  These edit `~/.claude/settings.json` (backup written alongside) to add a
  `PostToolUse` hook matching `ExitPlanMode`. Restart your Claude session to
  pick it up. The hook is a plain script, deliberately **not** exposed as a
  triggerable action.

## Plan-exit hook for other agents

The `install-hook` action wires the auto-open into **Claude Code**
(`~/.claude/settings.json`). Any other agent can use the *same script* — point
its own hook config at it and herdr does the rest.

Find the hook path (works for both `link` and GitHub installs):

```sh
root=$(jq -r '.[]|select(.plugin_id=="artursmirnov.lumen-review").plugin_root' \
  ~/.config/herdr/plugins.json)
echo "$root/hooks/on-plan-exit.sh"
```

Configure your agent's harness to run `bash <root>/hooks/on-plan-exit.sh` on
whatever event should open the review — its plan-approved / pre-edit / turn-end
hook. Then:

- **No arguments.** Stdin is optional: if the harness pipes hook JSON with a
  `.cwd`, that's used as the review's repo; otherwise it's read from the pane.
- **Requires a herdr pane.** herdr sets `HERDR_ENV` / `HERDR_PANE_ID` /
  `HERDR_SOCKET_PATH` for the agent's pane; without them the hook exits 0 as a
  no-op — safe to attach even for runs outside herdr.
- It opens the `[plan-review]` pane targeting the current agent pane in
  send-once mode, and won't stack if a review pane is already open.

The bundled `install-hook`/`uninstall-hook` actions only touch Claude Code's
settings; other agents are wired through their own hook config, not those.

## How it works

- Plugin panes get no herdr identity env, so the opener passes context via
  `herdr plugin pane open --env`: the mode, and either an explicit target (the
  plan-exit hook targets the agent that just exited plan mode) or the tab +
  workspace for the wrapper to infer one.
- Agent inference and the fzf picker run **inside the pane** (which has a TTY) —
  action commands run on the herdr server without one.
- lumen routes its TUI to `/dev/tty` when stdout is captured, so the wrapper can
  render the viewer in the pane **and** capture the annotation text from the
  same run.

## Configuration

Optional `config.toml` in the plugin config dir (read at open time — edits apply
on the next open, no reload):

```sh
cp config.example.toml "$(herdr plugin config-dir artursmirnov.lumen-review)/config.toml"
```

| Key | Default | Notes |
|---|---|---|
| `theme` | *(lumen default)* | `lumen --theme` |
| `[changes] placement` | `split` | `split` \| `popup` \| `overlay` |
| `[changes] direction` | `right` | `right` \| `down` (split only) |
| `[changes] ratio` | `0.6` | split **width** fraction, side-by-side only (approximate) |
| `[plan-review] placement` | `popup` | `popup` \| `split` \| `overlay` |
| `[plan-review] direction` | `right` | split only |
| `[plan-review] ratio` | `0.6` | split only |

Sizing caveats: `plugin pane open` has no size flag, so split width is applied
**after** open via `pane resize` (approximate, side-by-side splits only). **Popup
size is not runtime-configurable** — it lives in `herdr-plugin.toml` (the
`plan-review` pane `width`/`height`).

- `LUMEN_REVIEW_EXTRA_ARGS` (env) — extra args appended to the `lumen` invocation
  (e.g. `--wrap`).

## Limitations

- herdr splits are `right` or `down` only; the manual split uses `right`.
- The plan-exit popup is a herdr `popup` pane: id-less, absent from `pane list`,
  and it relies on auto-closing when the wrapper exits (there's no way to close
  it by id). It's declared as a separate `review-popup` manifest entrypoint
  since `popup` can't be set on the `plugin pane open` CLI, only in the
  manifest.
- Agent inference is resolved once at open time. If the chosen agent later
  exits, the next send fails gracefully (text shown, pane held) rather than
  re-picking.
- The plan-exit trigger comes from the agent's hook system — herdr has no
  "exited plan mode" event of its own. `install-hook` covers Claude Code; other
  agents wire the script themselves (see *Plan-exit hook for other agents*).
