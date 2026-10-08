#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  gum_stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  mkdir -p "$HOME/.config/herdr"
  printf '[keys]\nprefix = "ctrl+g"\n' > "$HOME/.config/herdr/config.toml"
  source "$REPO_ROOT/install/lib.sh"
  stub_command paplay
  stub_hide_command herdr
}

@test "asks existing Herdr users once and applies their pick" {
  omawsl_save_choice OMAWSL_MULTIPLEXER herdr
  gum_stub_respond "Sound + Windows popup"
  run bash "$REPO_ROOT/migrations/1791449932.sh"
  [ "$status" -eq 0 ]
  [ "$(omawsl_load_choice OMAWSL_HERDR_NOTIFICATIONS)" = "both" ]
  grep -qx 'delivery = "system"' "$HOME/.config/herdr/config.toml"
  [ -L "$HOME/.local/bin/notify-send" ]
}

@test "doesn't ask zellij users" {
  omawsl_save_choice OMAWSL_MULTIPLEXER zellij
  run bash "$REPO_ROOT/migrations/1791449932.sh"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"gum"* ]]
  [ -z "$(omawsl_load_choice OMAWSL_HERDR_NOTIFICATIONS)" ]
}

@test "doesn't ask again once a choice is saved" {
  omawsl_save_choice OMAWSL_MULTIPLEXER herdr
  omawsl_save_choice OMAWSL_HERDR_NOTIFICATIONS off
  run bash "$REPO_ROOT/migrations/1791449932.sh"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"gum"* ]]
  [ "$(omawsl_load_choice OMAWSL_HERDR_NOTIFICATIONS)" = "off" ]
}

@test "cancelling the question still succeeds and says how to choose later" {
  omawsl_save_choice OMAWSL_MULTIPLEXER herdr
  gum_stub_respond ""
  run bash "$REPO_ROOT/migrations/1791449932.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"omawsl notifications"* ]]
  [ -z "$(omawsl_load_choice OMAWSL_HERDR_NOTIFICATIONS)" ]
}

@test "a failed pulseaudio-utils install still succeeds, so later migrations aren't blocked" {
  omawsl_save_choice OMAWSL_MULTIPLEXER herdr
  unset -f paplay
  stub_hide_command paplay herdr
  stub_command sudo 100
  gum_stub_respond "Sound only"
  run bash "$REPO_ROOT/migrations/1791449932.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"retry with: omawsl notifications"* ]]
  [ -z "$(omawsl_load_choice OMAWSL_HERDR_NOTIFICATIONS)" ]
}
