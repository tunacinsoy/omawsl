#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  gum_stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/bin/omawsl-sub/notifications.sh"
  stub_command paplay
  stub_hide_command herdr
  export OMAWSL_NOTIFY_SOUND_DIR="$BATS_TEST_TMPDIR/sounds"
  mkdir -p "$OMAWSL_NOTIFY_SOUND_DIR"
  touch "$OMAWSL_NOTIFY_SOUND_DIR/complete.oga" "$OMAWSL_NOTIFY_SOUND_DIR/message-new-instant.oga"
}

@test "without a Herdr config, only saves the choice" {
  run omawsl_notifications_command sound
  [ "$status" -eq 0 ]
  [ "$(omawsl_load_choice OMAWSL_HERDR_NOTIFICATIONS)" = "sound" ]
  [[ "$output" == *"omawsl multiplexer herdr"* ]]
}

@test "with a Herdr config, sets it up and saves the choice" {
  mkdir -p "$HOME/.config/herdr" "$HOME/.claude"
  printf '[keys]\nprefix = "ctrl+g"\n' > "$HOME/.config/herdr/config.toml"
  run omawsl_notifications_command sound
  [ "$status" -eq 0 ]
  [ "$(omawsl_load_choice OMAWSL_HERDR_NOTIFICATIONS)" = "sound" ]
  grep -qx 'delivery = "off"' "$HOME/.config/herdr/config.toml"
  grep -qx 'enabled = false' "$HOME/.config/herdr/config.toml"
  grep -qF 'bin/omawsl-claude-notify' "$HOME/.claude/settings.json"
}

@test "a failed setup keeps the previous choice" {
  mkdir -p "$HOME/.config/herdr"
  touch "$HOME/.config/herdr/config.toml"
  omawsl_save_choice OMAWSL_HERDR_NOTIFICATIONS off
  unset -f paplay
  stub_hide_command paplay herdr
  stub_command sudo 100
  run omawsl_notifications_command sound
  [ "$status" -ne 0 ]
  [ "$(omawsl_load_choice OMAWSL_HERDR_NOTIFICATIONS)" = "off" ]
}

@test "rejects an unknown choice, including the old popup and both" {
  local c
  for c in loud popup both; do
    run omawsl_notifications_command "$c"
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown notifications choice '$c' - choose sound or off"* ]]
  done
}

@test "the picker offers only sound and off" {
  gum_stub_respond "Off"
  run omawsl_notifications_command
  [ "$status" -eq 0 ]
  [ "$(stub_calls)" = "gum choose --header Herdr agent notifications (currently: not set) Sound Off" ]
  [ "$(omawsl_load_choice OMAWSL_HERDR_NOTIFICATIONS)" = "off" ]
}

@test "with no argument, asks via gum and applies the pick" {
  gum_stub_respond "Sound"
  run omawsl_notifications_command
  [ "$status" -eq 0 ]
  [ "$(omawsl_load_choice OMAWSL_HERDR_NOTIFICATIONS)" = "sound" ]
}

@test "with no argument, cancelling the picker changes nothing" {
  gum_stub_respond ""
  run omawsl_notifications_command
  [ "$status" -eq 0 ]
  [ -z "$(omawsl_load_choice OMAWSL_HERDR_NOTIFICATIONS)" ]
}
