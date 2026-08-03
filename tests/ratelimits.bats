#!/usr/bin/env bats

load test_helper/common-setup

setup() {
	asc_test_setup
}

teardown() {
	asc_test_teardown
}

@test "refresh.sh sets per-window rate-limit options and a joined summary" {
	resets_5h="$(date -u -d '+2 hours +33 minutes' +%Y-%m-%dT%H:%M:%SZ)"
	resets_7d="$(date -u -d '+6 days +4 hours +3 minutes' +%Y-%m-%dT%H:%M:%SZ)"

	fixture="$(asc_render_fixture "$FIXTURES_DIR/ratelimits-single.json.tmpl" \
		RESETS_5H "$resets_5h" RESETS_7D "$resets_7d")"
	asc_stub_agent_status "$FIXTURES_DIR/empty.json" "$fixture"

	run "$SCRIPTS_DIR/refresh.sh"
	[ "$status" -eq 0 ]

	[ "$(asc_tmux show-options -g -v @asc_ratelimit_claudecode_5h_pct)" = "23%" ]
	[ "$(asc_tmux show-options -g -v @asc_ratelimit_claudecode_7d_pct)" = "14%" ]

	# Allow a little slack for wall-clock drift between computing the
	# fixture's resets_at and refresh.sh evaluating "now".
	resets_in_5h="$(asc_tmux show-options -g -v @asc_ratelimit_claudecode_5h_resets_in)"
	[[ "$resets_in_5h" == "2h33m" || "$resets_in_5h" == "2h32m" ]]
	resets_in_7d="$(asc_tmux show-options -g -v @asc_ratelimit_claudecode_7d_resets_in)"
	[[ "$resets_in_7d" == "6d4h3m" || "$resets_in_7d" == "6d4h2m" ]]

	[ "$(asc_tmux show-options -g -v @asc_ratelimit_claudecode_5h_resets_at)" = "$resets_5h" ]

	summary="$(asc_tmux show-options -g -v @asc_ratelimit_claudecode_summary)"
	[[ "$summary" == "5h 23% 2h3"* ]]
	[[ "$summary" == *" | 7d 14% 6d4h"* ]]
}

@test "refresh.sh omits resets_in/resets_at when a window has no resets_at" {
	cat >"$TEST_STUB_BIN/agent-status" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "list" ]; then
	cat "$FIXTURES_DIR/empty.json"
elif [ "\$1" = "rate-limits" ]; then
	echo '[{"provider":"claudecode","windows":[{"label":"5h","percent_used":10.0}],"last_updated":"2026-08-02T20:00:00Z"}]'
fi
EOF
	chmod +x "$TEST_STUB_BIN/agent-status"

	run "$SCRIPTS_DIR/refresh.sh"
	[ "$status" -eq 0 ]

	[ "$(asc_tmux show-options -g -v @asc_ratelimit_claudecode_5h_pct)" = "10%" ]
	[ -z "$(asc_tmux show-options -g -v @asc_ratelimit_claudecode_5h_resets_in 2>/dev/null)" ]
	[ -z "$(asc_tmux show-options -g -v @asc_ratelimit_claudecode_5h_resets_at 2>/dev/null)" ]
	[ "$(asc_tmux show-options -g -v @asc_ratelimit_claudecode_summary)" = "5h 10%" ]
}

@test "refresh.sh unsets rate-limit options for a provider no longer reported" {
	resets_5h="$(date -u -d '+2 hours' +%Y-%m-%dT%H:%M:%SZ)"
	resets_7d="$(date -u -d '+6 days' +%Y-%m-%dT%H:%M:%SZ)"
	fixture="$(asc_render_fixture "$FIXTURES_DIR/ratelimits-single.json.tmpl" \
		RESETS_5H "$resets_5h" RESETS_7D "$resets_7d")"
	asc_stub_agent_status "$FIXTURES_DIR/empty.json" "$fixture"
	run "$SCRIPTS_DIR/refresh.sh"
	[ "$status" -eq 0 ]
	[ -n "$(asc_tmux show-options -g -v @asc_ratelimit_claudecode_5h_pct 2>/dev/null)" ]

	asc_stub_agent_status "$FIXTURES_DIR/empty.json" "$FIXTURES_DIR/empty.json"
	run "$SCRIPTS_DIR/refresh.sh"
	[ "$status" -eq 0 ]

	[ -z "$(asc_tmux show-options -g -v @asc_ratelimit_claudecode_5h_pct 2>/dev/null)" ]
	[ -z "$(asc_tmux show-options -g -v @asc_ratelimit_claudecode_7d_pct 2>/dev/null)" ]
	[ -z "$(asc_tmux show-options -g -v @asc_ratelimit_claudecode_summary 2>/dev/null)" ]
}

@test "refresh.sh clears rate-limit options when @asc_enabled is turned off" {
	resets_5h="$(date -u -d '+2 hours' +%Y-%m-%dT%H:%M:%SZ)"
	fixture="$(asc_render_fixture "$FIXTURES_DIR/ratelimits-single.json.tmpl" \
		RESETS_5H "$resets_5h" RESETS_7D "$resets_5h")"
	asc_stub_agent_status "$FIXTURES_DIR/empty.json" "$fixture"
	run "$SCRIPTS_DIR/refresh.sh"
	[ "$status" -eq 0 ]
	[ -n "$(asc_tmux show-options -g -v @asc_ratelimit_claudecode_5h_pct 2>/dev/null)" ]

	asc_tmux set-option -g @asc_enabled off
	run "$SCRIPTS_DIR/refresh.sh"
	[ "$status" -eq 0 ]

	[ -z "$(asc_tmux show-options -g -v @asc_ratelimit_claudecode_5h_pct 2>/dev/null)" ]
	[ -z "$(asc_tmux show-options -g -v @asc_ratelimit_claudecode_summary 2>/dev/null)" ]
}
