#!/usr/bin/env bash
# fzf-based "jump to agent": lists every tracked agent (live and stale) via
# agent-status, lets the user fuzzy-search with a live preview, then
# switches the current tmux client to the selected agent's
# session/window/pane.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=./lib.sh
source "$SCRIPT_DIR/lib.sh"

BIN="$(asc_binary)"
if [ -z "$BIN" ]; then
	echo "tmux-asc-binder: agent-status not found (set @asc_binary or PATH)" >&2
	exit 1
fi

if ! command -v fzf >/dev/null 2>&1; then
	echo "tmux-asc-binder: fzf not found; jump-to-agent requires fzf on PATH" >&2
	exit 1
fi

LIST_JSON="$("$BIN" list --json --all 2>/dev/null || true)"
[ -n "$LIST_JSON" ] || LIST_JSON="[]"

# Displayed columns: state/label/provider/cwd, where label is the agent's
# task_summary, falling back to "session:window" (tmux names, not stable
# ids) when no summary is available. Trailing hidden fields carry the ASC
# session id and the stable tmux session_id/window_id/pane_id so the
# selection can be mapped back to a real tmux target and previewed after
# fzf returns.
ROWS="$(printf '%s' "$LIST_JSON" | jq -r '
  .[]
  | select(.status.multiplexer.type == "tmux")
  | select((.status.multiplexer.pane_id // "") != "")
  | (.status.task_summary // "") as $summary
  | (if $summary != "" then $summary
     else (.status.multiplexer.session + ":" + .status.multiplexer.window)
     end) as $label
  | [
      .status.state,
      $label,
      .status.provider,
      (.status.working_dir // "")
    ] as $cols
  | ($cols | @tsv) + "\t" + .status.session_id + "\t" + .status.multiplexer.session_id + "\t" + .status.multiplexer.window_id + "\t" + .status.multiplexer.pane_id
' 2>/dev/null || true)"

if [ -z "$ROWS" ]; then
	echo "tmux-asc-binder: no tracked agents found" >&2
	exit 0
fi

SELECTED="$(printf '%s\n' "$ROWS" | fzf \
	--delimiter='\t' \
	--with-nth=1,2,3,4 \
	--preview='tmux capture-pane -pt {8} -S -200' \
	--preview-window=right:50%)"

[ -n "$SELECTED" ] || exit 0

TARGET_SESSION="$(printf '%s' "$SELECTED" | cut -f6)"
TARGET_WINDOW="$(printf '%s' "$SELECTED" | cut -f7)"
TARGET_PANE="$(printf '%s' "$SELECTED" | cut -f8)"

[ -n "$TARGET_SESSION" ] && tmux switch-client -t "$TARGET_SESSION"
[ -n "$TARGET_WINDOW" ] && tmux select-window -t "$TARGET_WINDOW"
[ -n "$TARGET_PANE" ] && tmux select-pane -t "$TARGET_PANE"
