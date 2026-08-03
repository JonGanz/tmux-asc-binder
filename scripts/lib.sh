#!/usr/bin/env bash
# Shared helpers for tmux-asc-binder scripts: option getters with defaults,
# state priority ordering, and icon lookup. Sourced by refresh.sh, daemon.sh,
# jump.sh, and tmux-asc-binder.tmux.
set -uo pipefail

ASC_OPT_PREFIX="@asc_"

# asc_default_binary_dir prints the directory this script lives in, resolved
# through symlinks, so callers can find sibling scripts/binaries reliably
# regardless of cwd or how the plugin was sourced (TPM vs manual clone).
asc_script_dir() {
	local src="${BASH_SOURCE[0]}"
	while [ -h "$src" ]; do
		local dir
		dir="$(cd -P "$(dirname "$src")" >/dev/null 2>&1 && pwd)"
		src="$(readlink "$src")"
		[[ $src != /* ]] && src="$dir/$src"
	done
	cd -P "$(dirname "$src")" >/dev/null 2>&1 && pwd
}

# asc_get_option <name> <default> prints the global tmux user-option value,
# or <default> if unset/empty. Never fails the caller (falls back to default
# if tmux itself is unavailable, e.g. under bats unit tests without a server).
asc_get_option() {
	local name="$1" default="${2:-}" value=""
	if command -v tmux >/dev/null 2>&1; then
		value="$(tmux show-options -gqv "${ASC_OPT_PREFIX}${name}" 2>/dev/null || true)"
	fi
	if [ -z "$value" ]; then
		printf '%s' "$default"
	else
		printf '%s' "$value"
	fi
}

# asc_enabled reports (via exit status) whether @asc_enabled is on (default: on).
asc_enabled() {
	local v
	v="$(asc_get_option enabled on)"
	[ "$v" = "on" ] || [ "$v" = "1" ] || [ "$v" = "true" ]
}

# asc_bool <option-name> <default-on|off> reports via exit status.
asc_bool() {
	local v
	v="$(asc_get_option "$1" "$2")"
	[ "$v" = "on" ] || [ "$v" = "1" ] || [ "$v" = "true" ]
}

# asc_binary prints the resolved path to the agent-status binary: the
# @asc_binary override if set, else whatever `agent-status` resolves to on
# PATH (may print nothing if neither is available).
asc_binary() {
	local override
	override="$(asc_get_option binary "")"
	if [ -n "$override" ]; then
		printf '%s' "$override"
		return 0
	fi
	command -v agent-status 2>/dev/null || true
}

# asc_priority <state> prints an integer priority for a Status.State value;
# higher wins when bubbling up pane -> window -> session. "blocked" (needs a
# decision from you) outranks "active" (working, nothing needed from you
# yet), which outranks "done" (turn finished, nothing pending either way).
# Unknown/unrecognized state strings get the lowest priority (same as
# "unknown").
asc_priority() {
	case "$1" in
	blocked) printf '4' ;;
	active) printf '3' ;;
	done) printf '2' ;;
	unknown) printf '1' ;;
	stopped) printf '0' ;;
	*) printf '0' ;;
	esac
}

# asc_icon <state> prints the configured icon for a state, honoring
# @asc_icon_<state> overrides, falling back to a built-in default glyph.
asc_icon() {
	local state="$1" default=""
	case "$state" in
	blocked) default='?' ;;
	active) default='*' ;;
	done) default='-' ;;
	stopped) default='x' ;;
	*) default='.' ;;
	esac
	asc_get_option "icon_${state}" "$default"
}

# asc_sanitize_key <string> prints <string> with every character outside
# [A-Za-z0-9_] replaced with "_", for safely embedding arbitrary provider
# names/rate-limit window labels into a tmux user-option name.
asc_sanitize_key() {
	printf '%s' "$1" | tr -c 'A-Za-z0-9_' '_'
}

# asc_state_dir prints (and ensures exists) the scratch directory used to
# persist state across refresh ticks (e.g. the previous-targets snapshot),
# honoring $XDG_STATE_HOME per XDG Base Directory conventions.
asc_state_dir() {
	local base="${XDG_STATE_HOME:-$HOME/.local/state}"
	local dir="$base/tmux-asc-binder"
	mkdir -p "$dir" 2>/dev/null || true
	printf '%s' "$dir"
}
