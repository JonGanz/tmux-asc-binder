#!/usr/bin/env bats

load test_helper/common-setup

setup() {
	asc_test_setup
}

teardown() {
	# Best-effort: kill any daemon we may have left running.
	if [ -n "${DAEMON_PID:-}" ]; then
		kill "$DAEMON_PID" 2>/dev/null || true
		wait "$DAEMON_PID" 2>/dev/null || true
	fi
	asc_test_teardown
}

# asc_stub_counting_refresh replaces refresh.sh with a fake that just
# appends a line to a call-count file each time it's invoked, so the daemon
# loop's cadence/behavior can be asserted without depending on the real
# agent-status/tmux plumbing refresh.sh drives.
asc_stub_counting_refresh() {
	CALL_LOG="$(mktemp)"
	FAKE_SCRIPTS_DIR="$(mktemp -d)"
	cp "$SCRIPTS_DIR/lib.sh" "$FAKE_SCRIPTS_DIR/lib.sh"
	cp "$SCRIPTS_DIR/daemon.sh" "$FAKE_SCRIPTS_DIR/daemon.sh"
	cat >"$FAKE_SCRIPTS_DIR/refresh.sh" <<EOF
#!/usr/bin/env bash
echo tick >>"$CALL_LOG"
EOF
	chmod +x "$FAKE_SCRIPTS_DIR/refresh.sh"
}

@test "daemon.sh invokes refresh.sh repeatedly on the configured interval" {
	asc_stub_counting_refresh
	asc_tmux set-option -g @asc_refresh_interval 1

	"$FAKE_SCRIPTS_DIR/daemon.sh" &
	DAEMON_PID=$!

	# Up to ~3.5s for at least 3 ticks (1s interval + scheduling slack).
	for _ in $(seq 1 35); do
		count="$(wc -l <"$CALL_LOG" 2>/dev/null || echo 0)"
		[ "$count" -ge 3 ] && break
		sleep 0.1
	done

	kill "$DAEMON_PID" 2>/dev/null || true
	wait "$DAEMON_PID" 2>/dev/null || true
	unset DAEMON_PID

	count="$(wc -l <"$CALL_LOG")"
	[ "$count" -ge 3 ]
}

@test "daemon.sh kills a stale/duplicate daemon before starting its own loop" {
	asc_stub_counting_refresh
	asc_tmux set-option -g @asc_refresh_interval 1

	"$FAKE_SCRIPTS_DIR/daemon.sh" &
	first_pid=$!
	sleep 0.3
	kill -0 "$first_pid" 2>/dev/null

	"$FAKE_SCRIPTS_DIR/daemon.sh" &
	DAEMON_PID=$!

	# The second daemon's startup guard sends TERM then, if needed, waits up
	# to ~3s before escalating to KILL, so give this up to ~4.5s total.
	for _ in $(seq 1 45); do
		kill -0 "$first_pid" 2>/dev/null || break
		sleep 0.1
	done
	run kill -0 "$first_pid"
	[ "$status" -ne 0 ]
	# The second (current) daemon should still be alive.
	run kill -0 "$DAEMON_PID"
	[ "$status" -eq 0 ]

	kill "$DAEMON_PID" 2>/dev/null || true
	wait "$DAEMON_PID" 2>/dev/null || true
	unset DAEMON_PID
}
