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
  run "$REPO_ROOT/bin/omawsl-claude-notify" "$1" <<< "$2"
}

no_alert() {
  [ "$status" -eq 0 ]
  [ -z "$(stub_calls)" ]
}

done_sound() {
  [ "$status" -eq 0 ]
  [ "$(stub_calls)" = "paplay /sounds/complete.oga" ]
}

needs_you_sound() {
  [ "$status" -eq 0 ]
  [ "$(stub_calls)" = "paplay /sounds/message-new-instant.oga" ]
}

@test "stop with nothing running plays the done sound" {
  hook stop "{\"cwd\":\"$PROJECT\"}"
  done_sound
}

@test "stop with empty background_tasks and session_crons still alerts" {
  hook stop "{\"cwd\":\"$PROJECT\",\"background_tasks\":[],\"session_crons\":[]}"
  done_sound
}

@test "a subagent's stop doesn't alert" {
  hook stop "{\"cwd\":\"$PROJECT\",\"agent_id\":\"a1\"}"
  no_alert
}

@test "stop while a background task runs doesn't alert" {
  hook stop "{\"cwd\":\"$PROJECT\",\"background_tasks\":[{\"id\":\"b1\"}]}"
  no_alert
}

@test "stop with only artifact watches running still alerts" {
  # Claude Code arms one of these per published artifact and re-arms them
  # on resume - they never finish, so they aren't work in progress.
  hook stop "{\"cwd\":\"$PROJECT\",\"background_tasks\":[{\"id\":\"m1\",\"type\":\"monitor\",\"status\":\"running\",\"description\":\"live updates for artifact https://claude.ai/artifact/abc (re-armed on session resume)\"}]}"
  done_sound
}

@test "stop with an artifact watch and another background task doesn't alert" {
  hook stop "{\"cwd\":\"$PROJECT\",\"background_tasks\":[{\"id\":\"m1\",\"type\":\"monitor\",\"description\":\"live updates for artifact https://claude.ai/artifact/abc (auto-armed on publish)\"},{\"id\":\"m2\",\"type\":\"monitor\",\"description\":\"CI checks on PR 12\"}]}"
  no_alert
}

@test "stop with a scheduled wakeup left doesn't alert" {
  hook stop "{\"cwd\":\"$PROJECT\",\"session_crons\":[{\"id\":\"c1\"}]}"
  no_alert
}

@test "a permission prompt plays the needs-you sound" {
  hook notify "{\"cwd\":\"$PROJECT\",\"notification_type\":\"permission_prompt\",\"message\":\"Claude needs your permission to use Bash\"}"
  needs_you_sound
}

@test "an idle reminder doesn't alert" {
  hook notify "{\"cwd\":\"$PROJECT\",\"notification_type\":\"idle_prompt\",\"message\":\"Claude is waiting for your input\"}"
  no_alert
}

@test "a notification about AskUserQuestion is left to the ask hook" {
  hook notify "{\"cwd\":\"$PROJECT\",\"notification_type\":\"permission_prompt\",\"message\":\"Claude needs your permission to use AskUserQuestion\"}"
  no_alert
}

@test "the permission prompt Claude sends for an open question is left to the ask hook" {
  local t="$BATS_TEST_TMPDIR/t.jsonl"
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"q1","name":"AskUserQuestion","input":{}}]}}' > "$t"
  hook notify "{\"cwd\":\"$PROJECT\",\"transcript_path\":\"$t\",\"notification_type\":\"permission_prompt\",\"message\":\"Claude needs your permission\"}"
  no_alert
}

@test "a permission prompt after an answered question still alerts" {
  local t="$BATS_TEST_TMPDIR/t.jsonl"
  printf '%s\n' \
    '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"q1","name":"AskUserQuestion","input":{}}]}}' \
    '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"q1","content":"ok"}]}}' \
    '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"b1","name":"Bash","input":{}}]}}' > "$t"
  hook notify "{\"cwd\":\"$PROJECT\",\"transcript_path\":\"$t\",\"notification_type\":\"permission_prompt\",\"message\":\"Claude needs your permission\"}"
  needs_you_sound
}

@test "a question plays the needs-you sound" {
  hook ask "{\"cwd\":\"$PROJECT\",\"tool_input\":{\"questions\":[{\"question\":\"Which one?\",\"options\":[]}]}}"
  needs_you_sound
}

@test "outside Herdr nothing happens" {
  unset HERDR_ENV
  hook stop "{\"cwd\":\"$PROJECT\"}"
  no_alert
}

@test "off, no choice, or an old popup/both choice: nothing happens" {
  local c
  for c in off popup both; do
    omawsl_save_choice OMAWSL_HERDR_NOTIFICATIONS "$c"
    hook stop "{\"cwd\":\"$PROJECT\"}"
    echo "choice: $c"
    no_alert
  done
  rm -rf "$OMAWSL_STATE_DIR"
  hook stop "{\"cwd\":\"$PROJECT\"}"
  no_alert
}

@test "garbage or empty input exits 0 without alerting" {
  hook stop "not json"
  no_alert
  hook stop ""
  no_alert
  hook bogus "{\"cwd\":\"$PROJECT\"}"
  no_alert
  hook ask "not json"
  no_alert
  hook ask ""
  no_alert
  hook ask "[1,2]"
  no_alert
}
