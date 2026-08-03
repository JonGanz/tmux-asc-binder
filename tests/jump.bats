#!/usr/bin/env bats

load test_helper/common-setup

setup() {
	asc_test_setup
}

teardown() {
	asc_test_teardown
}

@test "jump.sh switches session/window/pane to the fzf-selected agent" {
	asc_tmux new-session -d -s other -x 80 -y 24
	asc_tmux new-window -t other -d
	pane1="$(asc_tmux display-message -p -t main:0.0 '#{pane_id}')"
	window1="$(asc_tmux display-message -p -t main:0.0 '#{window_id}')"
	session1="$(asc_tmux display-message -p -t main '#{session_id}')"
	pane2="$(asc_tmux display-message -p -t other:1.0 '#{pane_id}')"
	window2="$(asc_tmux display-message -p -t other:1.0 '#{window_id}')"
	session2="$(asc_tmux display-message -p -t other '#{session_id}')"

	fixture="$(asc_render_fixture "$FIXTURES_DIR/jump-list.json.tmpl" \
		SESSION1_ID "$session1" WINDOW1_ID "$window1" PANE1_ID "$pane1" \
		SESSION2_ID "$session2" WINDOW2_ID "$window2" PANE2_ID "$pane2")"
	asc_stub_agent_status "$fixture"

	# Select the second row (asc-sess-2 / project-b).
	selected_line="$(printf 'asc-sess-2\tclaudecode\twaiting_for_input\tWaiting on permission to run tests\t/home/dev/project-b\t%s\t%s\t%s' \
		"$session2" "$window2" "$pane2")"
	asc_stub_fzf_select "$selected_line"

	run "$SCRIPTS_DIR/jump.sh"
	[ "$status" -eq 0 ]

	grep -qF "switch-client -t $session2" "$TMUX_CALL_LOG"
	grep -qF "select-window -t $window2" "$TMUX_CALL_LOG"
	grep -qF "select-pane -t $pane2" "$TMUX_CALL_LOG"
	! grep -qF "switch-client -t $session1" "$TMUX_CALL_LOG"
}

@test "jump.sh exits cleanly with no action when the user cancels the picker" {
	pane1="$(asc_tmux display-message -p -t main:0.0 '#{pane_id}')"
	window1="$(asc_tmux display-message -p -t main:0.0 '#{window_id}')"
	session1="$(asc_tmux display-message -p -t main '#{session_id}')"

	fixture="$(asc_render_fixture "$FIXTURES_DIR/jump-list.json.tmpl" \
		SESSION1_ID "$session1" WINDOW1_ID "$window1" PANE1_ID "$pane1" \
		SESSION2_ID "$session1" WINDOW2_ID "$window1" PANE2_ID "$pane1")"
	asc_stub_agent_status "$fixture"
	asc_stub_fzf_select ""

	run "$SCRIPTS_DIR/jump.sh"
	[ "$status" -eq 0 ]

	! grep -q "switch-client" "$TMUX_CALL_LOG"
	! grep -q "select-window" "$TMUX_CALL_LOG"
	! grep -q "select-pane" "$TMUX_CALL_LOG"
}

@test "jump.sh fails clearly when fzf is not on PATH" {
	asc_stub_agent_status "$FIXTURES_DIR/empty.json"

	# A real fzf may be installed system-wide, so the only reliable way to
	# simulate "not on PATH" is a PATH made of symlinks to every real
	# executable except fzf (plus our stub dir), rather than just omitting a
	# system bin dir wholesale (which would also hide dirname/cut/etc that
	# jump.sh needs before it even gets to the fzf check).
	no_fzf_bin="$(mktemp -d)"
	for dir in /usr/bin /bin; do
		[ -d "$dir" ] || continue
		for exe in "$dir"/*; do
			name="$(basename "$exe")"
			[ "$name" = "fzf" ] && continue
			[ -e "$no_fzf_bin/$name" ] && continue
			ln -s "$exe" "$no_fzf_bin/$name" 2>/dev/null || true
		done
	done

	PATH="$TEST_STUB_BIN:$no_fzf_bin" run "$SCRIPTS_DIR/jump.sh"
	[ "$status" -ne 0 ]
	[[ "$output" == *fzf* ]]
}

@test "jump.sh reports no tracked agents without invoking fzf" {
	asc_stub_agent_status "$FIXTURES_DIR/empty.json"
	# Deliberately no fzf stub with a selection behavior needed; if jump.sh
	# tried to invoke fzf here it would hang/fail since none is installed.
	run "$SCRIPTS_DIR/jump.sh"
	[ "$status" -eq 0 ]
	[[ "$output" == *"no tracked agents"* ]]
}
