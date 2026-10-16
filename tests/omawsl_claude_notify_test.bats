#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/lib.sh"
  omawsl_save_choice OMAWSL_HERDR_NOTIFICATIONS both
  export HERDR_ENV=1
  unset HERDR_PANE_ID
  POPUPS="$BATS_TEST_TMPDIR/popups"
  export OMAWSL_NOTIFY_SEND="$BATS_TEST_TMPDIR/notify-send"
  printf '#!/usr/bin/env bash\nprintf "%%s|%%s\\n" "$2" "$3" >> %q\n' "$POPUPS" > "$OMAWSL_NOTIFY_SEND"
  chmod +x "$OMAWSL_NOTIFY_SEND"
  export OMAWSL_NOTIFY_SOUND_DIR="/sounds"
  stub_command paplay
  PROJECT="$BATS_TEST_TMPDIR/myproj"
  mkdir -p "$PROJECT"
}

# in_herdr_pane <pane json> - run as if inside Herdr pane w1:p1 of
# workspace "magdalani", with <pane json> as the pane `herdr pane get` returns.
in_herdr_pane() {
  export HERDR_PANE_ID=w1:p1
  stub_command_output_for herdr "pane get w1:p1" "{\"result\":{\"pane\":$1}}"
  stub_command_output_for herdr "workspace get w1" '{"result":{"workspace":{"label":"magdalani"}}}'
}

hook() {
  run "$REPO_ROOT/bin/omawsl-claude-notify" "$1" <<< "$2"
}

no_alert() {
  [ "$status" -eq 0 ]
  [ ! -e "$POPUPS" ]
  [ -z "$(stub_calls)" ]
}

@test "stop with nothing running: done popup and done sound" {
  hook stop "{\"cwd\":\"$PROJECT\"}"
  [ "$status" -eq 0 ]
  [ "$(cat "$POPUPS")" = "Claude Code — done|myproj" ]
  [ "$(stub_calls)" = "paplay /sounds/Windows Notify System Generic.wav" ]
}

@test "stop with empty background_tasks and session_crons still alerts" {
  hook stop "{\"cwd\":\"$PROJECT\",\"background_tasks\":[],\"session_crons\":[]}"
  [ "$(cat "$POPUPS")" = "Claude Code — done|myproj" ]
}

@test "in a Herdr pane the title is the agent's note and the body its workspace" {
  in_herdr_pane '{"label":"Admin redesign","terminal_title_stripped":"Resume previous session","workspace_id":"w1"}'
  hook stop "{\"cwd\":\"$PROJECT\"}"
  [ "$(cat "$POPUPS")" = "Admin redesign — done|magdalani" ]
}

@test "in a Herdr pane without a note the title is the agent's sidebar title" {
  in_herdr_pane '{"label":null,"terminal_title_stripped":"Night mode for public page","workspace_id":"w1"}'
  hook stop "{\"cwd\":\"$PROJECT\"}"
  [ "$(cat "$POPUPS")" = "Night mode for public page — done|magdalani" ]
}

@test "without a Herdr name the title is the session title, custom title first" {
  local t="$BATS_TEST_TMPDIR/t.jsonl"
  printf '%s\n' '{"type":"ai-title","aiTitle":"Auto name"}' '{"type":"user","message":{}}' > "$t"
  hook stop "{\"cwd\":\"$PROJECT\",\"transcript_path\":\"$t\"}"
  [ "$(cat "$POPUPS")" = "Auto name — done|myproj" ]
  rm -f "$POPUPS"
  printf '%s\n' '{"type":"custom-title","customTitle":"My name"}' >> "$t"
  hook stop "{\"cwd\":\"$PROJECT\",\"transcript_path\":\"$t\"}"
  [ "$(cat "$POPUPS")" = "My name — done|myproj" ]
}

@test "a subagent's stop doesn't alert" {
  hook stop "{\"cwd\":\"$PROJECT\",\"agent_id\":\"a1\"}"
  no_alert
}

@test "stop while a background task runs doesn't alert" {
  hook stop "{\"cwd\":\"$PROJECT\",\"background_tasks\":[{\"id\":\"b1\"}]}"
  no_alert
}

@test "stop with a scheduled wakeup left doesn't alert" {
  hook stop "{\"cwd\":\"$PROJECT\",\"session_crons\":[{\"id\":\"c1\"}]}"
  no_alert
}

@test "a permission prompt: needs-you popup and request sound" {
  hook notify "{\"cwd\":\"$PROJECT\",\"notification_type\":\"permission_prompt\",\"message\":\"Claude needs your permission to use Bash\"}"
  [ "$(cat "$POPUPS")" = "Claude Code — needs you|Claude needs your permission to use Bash" ]
  [ "$(stub_calls)" = "paplay /sounds/Windows Proximity Notification.wav" ]
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
  [ "$(cat "$POPUPS")" = "Claude Code — needs you|Claude needs your permission" ]
}

@test "a question shows the question text" {
  hook ask "{\"cwd\":\"$PROJECT\",\"tool_input\":{\"questions\":[{\"question\":\"Which one?\",\"options\":[]}]}}"
  [ "$(cat "$POPUPS")" = "Claude Code — needs you|Which one?" ]
}

@test "long bodies are clipped to 200 characters" {
  local long; long="$(printf 'x%.0s' $(seq 300))"
  hook notify "{\"cwd\":\"$PROJECT\",\"notification_type\":\"permission_prompt\",\"message\":\"$long\"}"
  local body; body="$(cut -d'|' -f2 "$POPUPS")"
  [ "${#body}" -eq 200 ]
}

@test "outside Herdr nothing happens" {
  unset HERDR_ENV
  hook stop "{\"cwd\":\"$PROJECT\"}"
  no_alert
}

@test "sound choice plays only the sound" {
  omawsl_save_choice OMAWSL_HERDR_NOTIFICATIONS sound
  hook stop "{\"cwd\":\"$PROJECT\"}"
  [ ! -e "$POPUPS" ]
  [ "$(stub_calls)" = "paplay /sounds/Windows Notify System Generic.wav" ]
}

@test "popup choice shows only the popup" {
  omawsl_save_choice OMAWSL_HERDR_NOTIFICATIONS popup
  hook stop "{\"cwd\":\"$PROJECT\"}"
  [ "$(cat "$POPUPS")" = "Claude Code — done|myproj" ]
  [ -z "$(stub_calls)" ]
}

@test "off or no choice: nothing happens" {
  omawsl_save_choice OMAWSL_HERDR_NOTIFICATIONS off
  hook stop "{\"cwd\":\"$PROJECT\"}"
  no_alert
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
