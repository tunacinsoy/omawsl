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
  run "$REPO_ROOT/bin/omawsl-copilot-notify" "$@"
}

no_alert() {
  [ "$status" -eq 0 ]
  [ ! -e "$POPUPS" ]
  [ -z "$(stub_calls)" ]
}

@test "agentStop: done popup and done sound" {
  hook stop <<< "{\"sessionId\":\"s1\",\"cwd\":\"$PROJECT\",\"stopReason\":\"end_turn\"}"
  [ "$status" -eq 0 ]
  [ "$(cat "$POPUPS")" = "GitHub Copilot — done|myproj" ]
  [ "$(stub_calls)" = "paplay /sounds/Windows Notify System Generic.wav" ]
}

@test "in a Herdr pane the title is the agent's note and the body its workspace" {
  in_herdr_pane '{"label":"Corp API","terminal_title_stripped":"copilot","workspace_id":"w1"}'
  hook stop <<< "{\"cwd\":\"$PROJECT\"}"
  [ "$(cat "$POPUPS")" = "Corp API — done|magdalani" ]
}

@test "a permission prompt: needs-you popup with Copilot's message and the request sound" {
  hook notify <<< "{\"cwd\":\"$PROJECT\",\"notification_type\":\"permission_prompt\",\"message\":\"Allow bash: npm test?\"}"
  [ "$(cat "$POPUPS")" = "GitHub Copilot — needs you|Allow bash: npm test?" ]
  [ "$(stub_calls)" = "paplay /sounds/Windows Proximity Notification.wav" ]
}

@test "a question (elicitation dialog) needs you" {
  hook notify <<< "{\"cwd\":\"$PROJECT\",\"notification_type\":\"elicitation_dialog\",\"message\":\"Which database?\"}"
  [ "$(cat "$POPUPS")" = "GitHub Copilot — needs you|Which database?" ]
}

@test "a needs-you notification without a message still alerts" {
  hook notify <<< "{\"cwd\":\"$PROJECT\",\"notification_type\":\"permission_prompt\"}"
  [ "$(cat "$POPUPS")" = "GitHub Copilot — needs you|" ]
}

@test "other notification types don't alert - agentStop covers done" {
  local t
  for t in agent_completed agent_idle shell_completed shell_detached_completed; do
    hook notify <<< "{\"cwd\":\"$PROJECT\",\"notification_type\":\"$t\",\"message\":\"x\"}"
    echo "type: $t"
    no_alert
  done
}

@test "long bodies are clipped to 200 characters" {
  local long; long="$(printf 'x%.0s' $(seq 300))"
  hook notify <<< "{\"cwd\":\"$PROJECT\",\"notification_type\":\"permission_prompt\",\"message\":\"$long\"}"
  local body; body="$(cut -d'|' -f2 "$POPUPS")"
  [ "${#body}" -eq 200 ]
}

@test "outside Herdr nothing happens" {
  unset HERDR_ENV
  hook stop <<< "{\"cwd\":\"$PROJECT\"}"
  no_alert
}

@test "sound choice plays only the sound, popup choice shows only the popup" {
  omawsl_save_choice OMAWSL_HERDR_NOTIFICATIONS sound
  hook stop <<< "{\"cwd\":\"$PROJECT\"}"
  [ ! -e "$POPUPS" ]
  [ "$(stub_calls)" = "paplay /sounds/Windows Notify System Generic.wav" ]
  stub_init
  omawsl_save_choice OMAWSL_HERDR_NOTIFICATIONS popup
  hook stop <<< "{\"cwd\":\"$PROJECT\"}"
  [ "$(cat "$POPUPS")" = "GitHub Copilot — done|myproj" ]
  [ -z "$(stub_calls)" ]
}

@test "off or no choice: nothing happens" {
  omawsl_save_choice OMAWSL_HERDR_NOTIFICATIONS off
  hook stop <<< "{\"cwd\":\"$PROJECT\"}"
  no_alert
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
