#!/usr/bin/env bats

load test_helper/common-setup

setup() {
	asc_test_setup
}

teardown() {
	asc_test_teardown
}

@test "refresh.sh sets pane/window/session state+icon from a single active agent" {
	pane_id="$(asc_tmux display-message -p -t main:0.0 '#{pane_id}')"
	window_id="$(asc_tmux display-message -p -t main:0.0 '#{window_id}')"
	session_id="$(asc_tmux display-message -p -t main:0.0 '#{session_id}')"

	fixture="$(asc_render_fixture "$FIXTURES_DIR/single-active.json.tmpl" \
		PANE_ID "$pane_id" WINDOW_ID "$window_id" SESSION_ID "$session_id")"
	asc_stub_agent_status "$fixture"

	run "$SCRIPTS_DIR/refresh.sh"
	[ "$status" -eq 0 ]

	[ "$(asc_tmux show-options -p -v -t "$pane_id" @asc_pane_state)" = "active" ]
	[ "$(asc_tmux show-options -w -v -t "$window_id" @asc_window_state)" = "active" ]
	[ "$(asc_tmux show-options -v -t "$session_id" @asc_session_state)" = "active" ]
	[ "$(asc_tmux show-options -p -v -t "$pane_id" @asc_pane_session_id)" = "asc-sess-1" ]
}

@test "refresh.sh bubbles up the highest-priority state to window and session" {
	asc_tmux split-window -t main:0 -d
	asc_tmux new-window -t main -d

	pane1="$(asc_tmux list-panes -t main:0 -F '#{pane_id}' | sed -n 1p)"
	pane2="$(asc_tmux list-panes -t main:0 -F '#{pane_id}' | sed -n 2p)"
	window1="$(asc_tmux display-message -p -t main:0 '#{window_id}')"
	window2="$(asc_tmux display-message -p -t main:1 '#{window_id}')"
	pane3="$(asc_tmux display-message -p -t main:1.0 '#{pane_id}')"
	session_id="$(asc_tmux display-message -p -t main '#{session_id}')"

	fixture="$(asc_render_fixture "$FIXTURES_DIR/multi-bubble-up.json.tmpl" \
		SESSION_ID "$session_id" \
		WINDOW1_ID "$window1" WINDOW2_ID "$window2" \
		PANE1_ID "$pane1" PANE2_ID "$pane2" PANE3_ID "$pane3")"
	asc_stub_agent_status "$fixture"

	run "$SCRIPTS_DIR/refresh.sh"
	[ "$status" -eq 0 ]

	# window1 has a done pane and an active pane -> active wins
	[ "$(asc_tmux show-options -w -v -t "$window1" @asc_window_state)" = "active" ]
	# window2 only has the blocked pane
	[ "$(asc_tmux show-options -w -v -t "$window2" @asc_window_state)" = "blocked" ]
	# session bubbles up the highest of the two windows
	[ "$(asc_tmux show-options -v -t "$session_id" @asc_session_state)" = "blocked" ]
}

@test "refresh.sh unsets options for a pane whose agent has gone away" {
	pane_id="$(asc_tmux display-message -p -t main:0.0 '#{pane_id}')"
	window_id="$(asc_tmux display-message -p -t main:0.0 '#{window_id}')"
	session_id="$(asc_tmux display-message -p -t main:0.0 '#{session_id}')"

	fixture="$(asc_render_fixture "$FIXTURES_DIR/single-active.json.tmpl" \
		PANE_ID "$pane_id" WINDOW_ID "$window_id" SESSION_ID "$session_id")"
	asc_stub_agent_status "$fixture"
	run "$SCRIPTS_DIR/refresh.sh"
	[ "$status" -eq 0 ]
	[ "$(asc_tmux show-options -p -v -t "$pane_id" @asc_pane_state)" = "active" ]

	# Next tick: the agent is gone.
	asc_stub_agent_status "$FIXTURES_DIR/empty.json"
	run "$SCRIPTS_DIR/refresh.sh"
	[ "$status" -eq 0 ]

	[ -z "$(asc_tmux show-options -p -v -t "$pane_id" @asc_pane_state 2>/dev/null)" ]
	[ -z "$(asc_tmux show-options -w -v -t "$window_id" @asc_window_state 2>/dev/null)" ]
	[ -z "$(asc_tmux show-options -v -t "$session_id" @asc_session_state 2>/dev/null)" ]
}

@test "refresh.sh clears everything when @asc_enabled is turned off" {
	pane_id="$(asc_tmux display-message -p -t main:0.0 '#{pane_id}')"
	window_id="$(asc_tmux display-message -p -t main:0.0 '#{window_id}')"
	session_id="$(asc_tmux display-message -p -t main:0.0 '#{session_id}')"

	fixture="$(asc_render_fixture "$FIXTURES_DIR/single-active.json.tmpl" \
		PANE_ID "$pane_id" WINDOW_ID "$window_id" SESSION_ID "$session_id")"
	asc_stub_agent_status "$fixture"
	run "$SCRIPTS_DIR/refresh.sh"
	[ "$status" -eq 0 ]
	[ "$(asc_tmux show-options -p -v -t "$pane_id" @asc_pane_state)" = "active" ]

	asc_tmux set-option -g @asc_enabled off
	run "$SCRIPTS_DIR/refresh.sh"
	[ "$status" -eq 0 ]

	[ -z "$(asc_tmux show-options -p -v -t "$pane_id" @asc_pane_state 2>/dev/null)" ]
	[ -z "$(asc_tmux show-options -w -v -t "$window_id" @asc_window_state 2>/dev/null)" ]
	[ -z "$(asc_tmux show-options -v -t "$session_id" @asc_session_state 2>/dev/null)" ]
}

@test "refresh.sh no-ops cleanly when agent-status cannot be resolved" {
	# No stub installed and PATH has nothing named agent-status.
	run "$SCRIPTS_DIR/refresh.sh"
	[ "$status" -eq 0 ]
}
