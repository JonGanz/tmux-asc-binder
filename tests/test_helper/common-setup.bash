#!/usr/bin/env bash
# Shared bats setup/teardown: an isolated tmux server + a stubbed
# `agent-status` (and, where needed, `fzf`) placed earlier on PATH, so tests
# never touch the developer's real tmux session or a real ASC install.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." >/dev/null 2>&1 && pwd)"
SCRIPTS_DIR="$REPO_ROOT/scripts"
FIXTURES_DIR="$REPO_ROOT/tests/fixtures"

asc_test_setup() {
	TEST_SOCKET="asc-test-$$-${BATS_TEST_NUMBER:-0}-$RANDOM"
	TEST_STATE_HOME="$(mktemp -d)"
	TEST_STUB_BIN="$(mktemp -d)"
	TMUX_CALL_LOG="$(mktemp)"
	REAL_TMUX="$(command -v tmux)"
	export XDG_STATE_HOME="$TEST_STATE_HOME"
	export PATH="$TEST_STUB_BIN:$PATH"

	# Every script under test calls bare `tmux` (as it would for real, inside
	# a live session where $TMUX routes it to the right server). Since bats
	# doesn't run inside tmux, put a wrapper on PATH that always targets our
	# throwaway test server and records every invocation's args, so tests can
	# both drive real tmux state and assert on exactly what was asked of it.
	cat >"$TEST_STUB_BIN/tmux" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$TMUX_CALL_LOG"
exec "$REAL_TMUX" -L "$TEST_SOCKET" "\$@"
EOF
	chmod +x "$TEST_STUB_BIN/tmux"

	# -f /dev/null: don't source the developer's real tmux.conf (which may
	# itself configure this very plugin, e.g. @asc_refresh_interval) into
	# our throwaway test server -- tests must control every option value
	# themselves for isolation.
	"$REAL_TMUX" -L "$TEST_SOCKET" -f /dev/null new-session -d -s main -x 80 -y 24
}

asc_test_teardown() {
	"$REAL_TMUX" -L "$TEST_SOCKET" kill-server 2>/dev/null || true
	rm -rf "$TEST_STATE_HOME" "$TEST_STUB_BIN"
	rm -f "$TMUX_CALL_LOG"
}

# asc_tmux runs tmux against the isolated test server, bypassing the
# recording wrapper (useful for setup/assertions that shouldn't pollute
# TMUX_CALL_LOG).
asc_tmux() {
	"$REAL_TMUX" -L "$TEST_SOCKET" "$@"
}

# asc_stub_agent_status <list-fixture-file> [<ratelimits-fixture-file>]
# installs a fake `agent-status` executable on PATH that prints the given
# fixture file's contents for `list --json` / `list --json --all`, a fixed
# string for `show <id>`, and (if given) the second fixture's contents for
# `rate-limits --json` (defaulting to "[]" when omitted).
asc_stub_agent_status() {
	local fixture="$1"
	local ratelimits_fixture="${2:-}"
	cat >"$TEST_STUB_BIN/agent-status" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "list" ]; then
	cat "$fixture"
elif [ "\$1" = "show" ]; then
	echo "stub show output for \$2"
elif [ "\$1" = "rate-limits" ]; then
	if [ -n "$ratelimits_fixture" ]; then
		cat "$ratelimits_fixture"
	else
		echo '[]'
	fi
fi
EOF
	chmod +x "$TEST_STUB_BIN/agent-status"
}

# asc_stub_fzf_select <line> installs a fake `fzf` that ignores stdin/prompt
# and just echoes back the given line, simulating a non-interactive
# "user selected this row" run.
asc_stub_fzf_select() {
	local line="$1"
	cat >"$TEST_STUB_BIN/fzf" <<EOF
#!/usr/bin/env bash
cat >/dev/null
printf '%s\n' '$line'
EOF
	chmod +x "$TEST_STUB_BIN/fzf"
}

# asc_render_fixture <template-path> <PLACEHOLDER> <value> [<PLACEHOLDER> <value> ...]
# substitutes {{PLACEHOLDER}} tokens in the template (real tmux ids like
# %3/@2/$1 are only known at test run-time) and prints the path to the
# rendered temp file.
asc_render_fixture() {
	local template="$1"
	shift
	local out
	out="$(mktemp)"
	cp "$template" "$out"
	while [ "$#" -ge 2 ]; do
		local placeholder="$1" value="$2"
		# Escape sed/regex-sensitive characters in the replacement value.
		local escaped
		escaped="$(printf '%s' "$value" | sed -e 's/[&/\]/\\&/g')"
		sed -i "s/{{${placeholder}}}/${escaped}/g" "$out"
		shift 2
	done
	printf '%s' "$out"
}
