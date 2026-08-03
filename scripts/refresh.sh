#!/usr/bin/env bash
# One polling tick: query agent-status-collector for live tracked agents,
# compute per-pane/window/session state (bubbling up the highest-priority
# state per window/session), and apply/clear the corresponding @asc_* tmux
# user-options. Safe to run standalone and repeatedly (idempotent).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=./lib.sh
source "$SCRIPT_DIR/lib.sh"

PANE_SNAPSHOT="$(asc_state_dir)/last-panes"
WINDOW_SNAPSHOT="$(asc_state_dir)/last-windows"
SESSION_SNAPSHOT="$(asc_state_dir)/last-sessions"

# asc_clear_scope <flag(-p|-w|"")> <id> unsets the three @asc_<scope>_* options at <id>.
asc_clear_scope() {
	local flag="$1" id="$2" prefix="$3"
	if [ -n "$flag" ]; then
		tmux set-option "$flag" -u -t "$id" "@asc_${prefix}_state" 2>/dev/null || true
		tmux set-option "$flag" -u -t "$id" "@asc_${prefix}_icon" 2>/dev/null || true
	else
		tmux set-option -u -t "$id" "@asc_${prefix}_state" 2>/dev/null || true
		tmux set-option -u -t "$id" "@asc_${prefix}_icon" 2>/dev/null || true
	fi
}

asc_clear_all() {
	if [ -f "$PANE_SNAPSHOT" ]; then
		while IFS= read -r id; do
			[ -n "$id" ] || continue
			tmux set-option -p -u -t "$id" @asc_pane_state 2>/dev/null || true
			tmux set-option -p -u -t "$id" @asc_pane_icon 2>/dev/null || true
			tmux set-option -p -u -t "$id" @asc_pane_session_id 2>/dev/null || true
		done <"$PANE_SNAPSHOT"
	fi
	if [ -f "$WINDOW_SNAPSHOT" ]; then
		while IFS= read -r id; do
			[ -n "$id" ] || continue
			asc_clear_scope -w "$id" window
		done <"$WINDOW_SNAPSHOT"
	fi
	if [ -f "$SESSION_SNAPSHOT" ]; then
		while IFS= read -r id; do
			[ -n "$id" ] || continue
			asc_clear_scope "" "$id" session
		done <"$SESSION_SNAPSHOT"
	fi
	rm -f "$PANE_SNAPSHOT" "$WINDOW_SNAPSHOT" "$SESSION_SNAPSHOT"
}

if ! command -v tmux >/dev/null 2>&1; then
	exit 0
fi

if ! asc_enabled; then
	asc_clear_all
	exit 0
fi

BIN="$(asc_binary)"
if [ -z "$BIN" ]; then
	exit 0
fi

LIST_JSON="$("$BIN" list --json 2>/dev/null || true)"
if [ -z "$LIST_JSON" ]; then
	LIST_JSON="[]"
fi

# pane_id \t window_id \t session_id \t state \t priority \t asc_session_id
ROWS="$(printf '%s' "$LIST_JSON" | jq -r '
  .[]
  | select(.status.multiplexer.type == "tmux")
  | select((.status.multiplexer.pane_id // "") != "")
  | [.status.multiplexer.pane_id, .status.multiplexer.window_id, .status.multiplexer.session_id, .status.state, .status.session_id]
  | @tsv
' 2>/dev/null || true)"

CUR_PANES_FILE="$(mktemp)"
CUR_WINDOWS_FILE="$(mktemp)"
CUR_SESSIONS_FILE="$(mktemp)"
trap 'rm -f "$CUR_PANES_FILE" "$CUR_WINDOWS_FILE" "$CUR_SESSIONS_FILE"' EXIT

# window_id/session_id -> best (priority, state) seen so far, tracked via
# plain files (one "id\tpriority\tstate" line per id) rather than bash
# associative arrays, so this runs under bash 3.2 (stock macOS) too.
WINDOW_BEST="$(mktemp)"
SESSION_BEST="$(mktemp)"
trap 'rm -f "$CUR_PANES_FILE" "$CUR_WINDOWS_FILE" "$CUR_SESSIONS_FILE" "$WINDOW_BEST" "$SESSION_BEST"' EXIT

asc_track_best() {
	# asc_track_best <best-file> <id> <priority> <state>
	local best_file="$1" id="$2" prio="$3" state="$4"
	local existing
	existing="$(awk -F'\t' -v id="$id" '$1==id{print $2}' "$best_file" 2>/dev/null | head -n1)"
	if [ -z "$existing" ] || [ "$prio" -gt "$existing" ]; then
		grep -v -F -- "$(printf '%s\t' "$id")" "$best_file" 2>/dev/null >"${best_file}.tmp" || true
		mv "${best_file}.tmp" "$best_file"
		printf '%s\t%s\t%s\n' "$id" "$prio" "$state" >>"$best_file"
	fi
}

if [ -n "$ROWS" ]; then
	while IFS=$'\t' read -r pane_id window_id session_id state asc_session_id; do
		[ -n "$pane_id" ] || continue
		icon="$(asc_icon "$state")"
		tmux set-option -p -t "$pane_id" @asc_pane_state "$state" 2>/dev/null || true
		tmux set-option -p -t "$pane_id" @asc_pane_icon "$icon" 2>/dev/null || true
		tmux set-option -p -t "$pane_id" @asc_pane_session_id "$asc_session_id" 2>/dev/null || true
		printf '%s\n' "$pane_id" >>"$CUR_PANES_FILE"

		if [ -n "$window_id" ]; then
			prio="$(asc_priority "$state")"
			asc_track_best "$WINDOW_BEST" "$window_id" "$prio" "$state"
		fi
		if [ -n "$session_id" ]; then
			prio="$(asc_priority "$state")"
			asc_track_best "$SESSION_BEST" "$session_id" "$prio" "$state"
		fi
	done <<<"$ROWS"
fi

if [ -s "$WINDOW_BEST" ]; then
	while IFS=$'\t' read -r window_id _prio state; do
		[ -n "$window_id" ] || continue
		icon="$(asc_icon "$state")"
		tmux set-option -w -t "$window_id" @asc_window_state "$state" 2>/dev/null || true
		tmux set-option -w -t "$window_id" @asc_window_icon "$icon" 2>/dev/null || true
		printf '%s\n' "$window_id" >>"$CUR_WINDOWS_FILE"
	done <"$WINDOW_BEST"
fi

if [ -s "$SESSION_BEST" ]; then
	while IFS=$'\t' read -r session_id _prio state; do
		[ -n "$session_id" ] || continue
		icon="$(asc_icon "$state")"
		tmux set-option -t "$session_id" @asc_session_state "$state" 2>/dev/null || true
		tmux set-option -t "$session_id" @asc_session_icon "$icon" 2>/dev/null || true
		printf '%s\n' "$session_id" >>"$CUR_SESSIONS_FILE"
	done <"$SESSION_BEST"
fi

# Unset options for anything tracked last tick but absent this tick.
asc_unset_stale() {
	local prev_file="$1" cur_file="$2" flag="$3" prefix="$4"
	[ -f "$prev_file" ] || return 0
	while IFS= read -r id; do
		[ -n "$id" ] || continue
		if ! grep -qxF "$id" "$cur_file" 2>/dev/null; then
			if [ "$prefix" = "pane" ]; then
				tmux set-option -p -u -t "$id" @asc_pane_state 2>/dev/null || true
				tmux set-option -p -u -t "$id" @asc_pane_icon 2>/dev/null || true
				tmux set-option -p -u -t "$id" @asc_pane_session_id 2>/dev/null || true
			else
				asc_clear_scope "$flag" "$id" "$prefix"
			fi
		fi
	done <"$prev_file"
}

asc_unset_stale "$PANE_SNAPSHOT" "$CUR_PANES_FILE" -p pane
asc_unset_stale "$WINDOW_SNAPSHOT" "$CUR_WINDOWS_FILE" -w window
asc_unset_stale "$SESSION_SNAPSHOT" "$CUR_SESSIONS_FILE" "" session

cp "$CUR_PANES_FILE" "$PANE_SNAPSHOT" 2>/dev/null || true
cp "$CUR_WINDOWS_FILE" "$WINDOW_SNAPSHOT" 2>/dev/null || true
cp "$CUR_SESSIONS_FILE" "$SESSION_SNAPSHOT" 2>/dev/null || true

rm -f "$WINDOW_BEST" "$SESSION_BEST"
