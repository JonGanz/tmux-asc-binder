#!/usr/bin/env bash
# Background polling loop: calls refresh.sh every @asc_refresh_interval
# seconds. Guards against duplicate daemons (e.g. across a tmux config
# reload) via a pidfile: a stale/duplicate daemon is killed before this one
# starts looping.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=./lib.sh
source "$SCRIPT_DIR/lib.sh"

PIDFILE="$(asc_state_dir)/daemon.pid"

asc_kill_stale_daemon() {
	[ -f "$PIDFILE" ] || return 0
	local old_pid
	old_pid="$(cat "$PIDFILE" 2>/dev/null || true)"
	if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
		kill "$old_pid" 2>/dev/null || true
		# The old daemon may be mid-refresh (or otherwise deferring the
		# signal until its current foreground command completes), so give
		# it a bounded grace period to exit on its own before escalating.
		local waited=0
		while kill -0 "$old_pid" 2>/dev/null && [ "$waited" -lt 30 ]; do
			sleep 0.1
			waited=$((waited + 1))
		done
		kill -9 "$old_pid" 2>/dev/null || true
	fi
	rm -f "$PIDFILE"
}

asc_kill_stale_daemon
echo $$ >"$PIDFILE"

cleanup() {
	rm -f "$PIDFILE"
}
trap cleanup EXIT
trap 'cleanup; exit 0' INT TERM

while true; do
	"$SCRIPT_DIR/refresh.sh" || true
	interval="$(asc_get_option refresh_interval 5)"
	case "$interval" in
	'' | *[!0-9]*) interval=5 ;;
	esac
	sleep "$interval"
done
