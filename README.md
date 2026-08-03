# tmux-asc-binder

A tmux plugin that wraps [`agent-status-collector`](../agent-status-collector) (ASC) — a local
CLI tracking the status of AI coding agents (Claude Code, etc.) — and surfaces it inside tmux as
scoped `@asc_*` user-options on panes, windows, and sessions, plus an optional fzf-based
jump-to-agent picker.

By design (see `GOAL.md`), installing this plugin changes **nothing visible** by default: no
status-bar or window-label output is added until you reference an `@asc_*` option in your own
`tmux.conf`. Every feature can be turned off independently.

## Requirements

- [`agent-status-collector`](../agent-status-collector) (the `agent-status` binary) on `PATH`, or
  pointed to via `@asc_binary`.
- `jq` (for parsing `agent-status list --json` output).
- `fzf`, only if you want the jump-to-agent feature.

## Install

### Via TPM

```tmux
set -g @plugin 'JonGanz/tmux-asc-binder'
```

Then press `prefix + I` to fetch and source it.

### Manual

```sh
git clone https://github.com/JonGanz/tmux-asc-binder ~/.tmux/plugins/tmux-asc-binder
```

```tmux
run-shell ~/.tmux/plugins/tmux-asc-binder/tmux-asc-binder.tmux
```

## Options

### Config (`@asc_*`, set in your `tmux.conf`, all optional)

| Option                  | Default | Description                                              |
|-------------------------|---------|------------------------------------------------------------|
| `@asc_enabled`          | `on`    | Master switch. When `off`, the refresh daemon isn't started (or is stopped and all `@asc_*` output options are cleared on the next tick if already running) and no keybinding is registered. |
| `@asc_refresh_interval` | `5`     | Seconds between polls of `agent-status list --json`.       |
| `@asc_binary`           | *(PATH)*| Override path to the `agent-status` binary.                |
| `@asc_jump_enabled`     | `on`    | Whether the jump-to-agent keybinding is registered at all.  |
| `@asc_jump_key`         | `a`     | Key bound under `prefix` to open the jump-to-agent popup.   |
| `@asc_icon_active`      | `*`     | Icon for `active` state.                                    |
| `@asc_icon_idle`        | `-`     | Icon for `idle` state.                                      |
| `@asc_icon_waiting_for_input` | `?` | Icon for `waiting_for_input` state.                       |
| `@asc_icon_stopped`     | `x`     | Icon for `stopped` state.                                    |
| `@asc_icon_unknown`     | `.`     | Icon for `unknown` state (and any state this plugin doesn't recognize). |

### Output (set automatically by the refresh loop; reference these in your own config)

| Option                    | Scope   | Description                                          |
|---------------------------|---------|-------------------------------------------------------|
| `@asc_pane_state`         | pane    | Raw ASC state of the agent tracked in this pane.       |
| `@asc_pane_icon`          | pane    | Configured icon for that state.                        |
| `@asc_pane_session_id`    | pane    | The ASC session id for that agent (useful for scripting/debugging, e.g. `agent-status show <id>`). |
| `@asc_window_state`       | window  | Highest-priority state among all tracked agents in this window. |
| `@asc_window_icon`        | window  | Configured icon for that state.                        |
| `@asc_session_state`      | session | Highest-priority state among all tracked agents in this session. |
| `@asc_session_icon`       | session | Configured icon for that state.                        |

Priority order (highest wins when bubbling a pane's state up to its window/session):
`waiting_for_input > active > idle > unknown > stopped`.

These options are only set on panes/windows/sessions that currently have a tracked agent, and are
unset again once that agent stops being tracked (agent exits, or `@asc_enabled` is turned off) —
so a config like the following only ever shows something when there's actually an agent to report:

```tmux
set -g window-status-format '#{window_index}#{?@asc_window_icon, #{@asc_window_icon},}: #{window_name}'
set -g status-right '#{?@asc_session_icon,#{@asc_session_icon} ,}%H:%M'
```

### Rate limits (`agent-status rate-limits`)

Rate limits (e.g. Claude's 5h/7d usage windows) are account-level, not tied to any pane/window/
session, so they're exposed as **global** options keyed by provider and window label instead:

| Option                                              | Description                                  |
|------------------------------------------------------|-----------------------------------------------|
| `@asc_ratelimit_<provider>_<window>_pct`             | Usage for that window, e.g. `23%`.             |
| `@asc_ratelimit_<provider>_<window>_resets_in`       | Time until reset, e.g. `2h33m` or `6d4h3m` (unset if the provider didn't report a reset time). |
| `@asc_ratelimit_<provider>_<window>_resets_at`       | Raw RFC3339 reset timestamp (unset if unavailable). |
| `@asc_ratelimit_<provider>_summary`                  | All of that provider's windows pre-joined with `\| `, e.g. `5h 23% 2h33m \| 7d 14% 6d4h3m`. |

`<provider>` and `<window>` are the raw values from `agent-status rate-limits --json`
(e.g. `claudecode`, `5h`, `7d`) with any non-alphanumeric characters replaced by `_`. To render
exactly `claude | 5h 23% 2h33m | 7d 14% 6d4h3m` in your status bar:

```tmux
set -g status-right 'claude | #{@asc_ratelimit_claudecode_summary}'
```

Like the pane/window/session options, these are only set while the provider is actually reporting
rate limits, and are unset again if that stops (or `@asc_enabled` is turned off).

## Jump to agent

`prefix + a` (configurable via `@asc_jump_key`) opens an fzf popup listing every tracked agent
(live and stale). Each row shows the agent's state, a label (its task summary, falling back to
`session:window` when no summary is available), provider, and working directory; the preview
pane shows a live capture of the agent's actual tmux pane. Selecting a row switches the current
client to that agent's session, window, and pane — across sessions if needed. Set
`@asc_jump_enabled off` to disable the binding entirely.

## Development

```sh
# in ../agent-status-collector
go test ./... && go vet ./... && gofmt -l .

# in this repo (requires bats-core: https://github.com/bats-core/bats-core)
./tests/run.sh   # or: bats tests/
```
