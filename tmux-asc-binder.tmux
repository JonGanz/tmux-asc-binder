#!/usr/bin/env bash
# tmux-asc-binder entrypoint. Sourced by TPM (`set -g @plugin '.../tmux-asc-binder'`)
# or manually (`run-shell '~/path/to/tmux-asc-binder.tmux'`).
#
# Per GOAL.md's design philosophy, this adds *zero* default status-bar/window
# output: it only sets @asc_* user-options for the user's own config to
# reference, plus an optional daemon and an optional jump-to-agent keybinding
# (both individually toggleable and both off-by-default-safe: the daemon
# no-ops if agent-status isn't found, and the keybinding is only registered
# when @asc_jump_enabled is on).
set -uo pipefail

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
SCRIPTS_DIR="$CURRENT_DIR/scripts"

# shellcheck source=./scripts/lib.sh
source "$SCRIPTS_DIR/lib.sh"

main() {
	if ! asc_enabled; then
		return 0
	fi

	local bin
	bin="$(asc_binary)"
	if [ -z "$bin" ]; then
		tmux display-message "tmux-asc-binder: agent-status not found on PATH (set @asc_binary to override)"
	else
		nohup "$SCRIPTS_DIR/daemon.sh" >/dev/null 2>&1 &
		disown 2>/dev/null || true
	fi

	if asc_bool jump_enabled on; then
		local jump_key
		jump_key="$(asc_get_option jump_key a)"
		tmux bind-key "$jump_key" display-popup -w 80% -h 80% -E "$SCRIPTS_DIR/jump.sh"
	fi
}

main
