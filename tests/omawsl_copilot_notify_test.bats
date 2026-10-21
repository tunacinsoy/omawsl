#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/lib.sh"
  omawsl_save_choice OMAWSL_HERDR_NOTIFICATIONS sound
  export HERDR_ENV=1
  export OMAWSL_NOTIFY_SOUND_DIR="/sounds"
  stub_command paplay
  PROJECT="$BATS_TEST_TMPDIR/myproj"
  mkdir -p "$PROJECT"
}

hook() {
  run "$REPO_ROOT/bin/omawsl-copilot-notify" "$@"
}

no_alert() {
  [ "$status" -eq 0 ]
  [ -z "$(stub_calls)" ]
}

@test "agentStop at the end of a turn plays the done sound" {
  hook stop <<< "{\"sessionId\":\"s1\",\"cwd\":\"$PROJECT\",\"stopReason\":\"end_turn\"}"
  [ "$status" -eq 0 ]
  [ "$(stub_calls)" = "paplay /sounds/complete.oga" ]
}

@test "agentStop without a stopReason still plays the done sound" {
  hook stop <<< "{\"cwd\":\"$PROJECT\"}"
  [ "$(stub_calls)" = "paplay /sounds/complete.oga" ]
}

@test "agentStop for any other stopReason (Esc, an error) stays quiet" {
  local r
  for r in aborted cancelled error max_turns; do
    hook stop <<< "{\"cwd\":\"$PROJECT\",\"stopReason\":\"$r\"}"
    echo "stopReason: $r"
    no_alert
  done
}

@test "the sounds come from Ubuntu's sound theme, not from Windows" {
  unset OMAWSL_NOTIFY_SOUND_DIR
  hook stop <<< "{\"cwd\":\"$PROJECT\"}"
  [ "$(stub_calls)" = "paplay /usr/share/sounds/freedesktop/stereo/complete.oga" ]
}

@test "a permission prompt plays the needs-you sound" {
  hook notify <<< "{\"cwd\":\"$PROJECT\",\"notification_type\":\"permission_prompt\",\"message\":\"Allow bash: npm test?\"}"
  [ "$(stub_calls)" = "paplay /sounds/message-new-instant.oga" ]
}

@test "a question (elicitation dialog) needs you" {
  hook notify <<< "{\"cwd\":\"$PROJECT\",\"notification_type\":\"elicitation_dialog\",\"message\":\"Which database?\"}"
  [ "$(stub_calls)" = "paplay /sounds/message-new-instant.oga" ]
}

@test "other notification types don't alert - agentStop covers done" {
  local t
  for t in agent_completed agent_idle shell_completed shell_detached_completed; do
    hook notify <<< "{\"cwd\":\"$PROJECT\",\"notification_type\":\"$t\",\"message\":\"x\"}"
    echo "type: $t"
    no_alert
  done
}

@test "outside Herdr nothing happens" {
  unset HERDR_ENV
  hook stop <<< "{\"cwd\":\"$PROJECT\"}"
  no_alert
}

@test "off, no choice, or an old popup/both choice: nothing happens" {
  local c
  for c in off popup both; do
    omawsl_save_choice OMAWSL_HERDR_NOTIFICATIONS "$c"
    hook stop <<< "{\"cwd\":\"$PROJECT\"}"
    echo "choice: $c"
    no_alert
  done
  rm -rf "$OMAWSL_STATE_DIR"
  hook stop <<< "{\"cwd\":\"$PROJECT\"}"
  no_alert
}

@test "garbage input, an unknown event or no event exits 0 without alerting" {
  hook stop <<< "not json"
  no_alert
  hook stop <<< ""
  no_alert
  hook stop <<< "[1,2]"
  no_alert
  hook bogus <<< "{\"cwd\":\"$PROJECT\"}"
  no_alert
  hook <<< "{\"cwd\":\"$PROJECT\"}"
  no_alert
}
