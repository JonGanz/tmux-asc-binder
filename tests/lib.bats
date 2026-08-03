#!/usr/bin/env bats

load test_helper/common-setup

setup() {
	asc_test_setup
	source "$SCRIPTS_DIR/lib.sh"
}

teardown() {
	asc_test_teardown
}

@test "asc_priority orders states highest-to-lowest as designed" {
	[ "$(asc_priority blocked)" -gt "$(asc_priority active)" ]
	[ "$(asc_priority active)" -gt "$(asc_priority done)" ]
	[ "$(asc_priority done)" -gt "$(asc_priority unknown)" ]
	[ "$(asc_priority unknown)" -gt "$(asc_priority stopped)" ]
}

@test "asc_priority treats an unrecognized state as lowest priority" {
	[ "$(asc_priority some_future_state)" -eq "$(asc_priority stopped)" ]
}

@test "asc_icon returns a built-in default when no override is configured" {
	result="$(asc_icon active)"
	[ -n "$result" ]
}

@test "asc_icon honors a configured @asc_icon_<state> override" {
	asc_tmux set-option -g @asc_icon_active 'ROCKET'
	result="$(asc_icon active)"
	[ "$result" = "ROCKET" ]
}

@test "asc_get_option falls back to the given default when unset" {
	result="$(asc_get_option refresh_interval 5)"
	[ "$result" = "5" ]
}

@test "asc_get_option returns the configured global value when set" {
	asc_tmux set-option -g @asc_refresh_interval 10
	result="$(asc_get_option refresh_interval 5)"
	[ "$result" = "10" ]
}

@test "asc_enabled defaults to true" {
	asc_enabled
}

@test "asc_enabled reports false when @asc_enabled is off" {
	asc_tmux set-option -g @asc_enabled off
	! asc_enabled
}

@test "asc_binary prefers the @asc_binary override over PATH resolution" {
	fake_bin="$(mktemp -d)/agent-status"
	touch "$fake_bin"
	chmod +x "$fake_bin"
	asc_tmux set-option -g @asc_binary "$fake_bin"
	result="$(asc_binary)"
	[ "$result" = "$fake_bin" ]
}

@test "asc_state_dir creates and returns a directory under XDG_STATE_HOME" {
	dir="$(asc_state_dir)"
	[ -d "$dir" ]
	[[ "$dir" == "$XDG_STATE_HOME"* ]]
}
