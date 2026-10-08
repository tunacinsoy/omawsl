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
}

@test "without a Herdr config, only saves the choice" {
  run omawsl_notifications_command popup
  [ "$status" -eq 0 ]
  [ "$(omawsl_load_choice OMAWSL_HERDR_NOTIFICATIONS)" = "popup" ]
  [ ! -e "$HOME/.local/bin/notify-send" ]
  [[ "$output" == *"omawsl multiplexer herdr"* ]]
}

@test "with a Herdr config, sets it up and saves the choice" {
  mkdir -p "$HOME/.config/herdr"
  printf '[keys]\nprefix = "ctrl+g"\n' > "$HOME/.config/herdr/config.toml"
  run omawsl_notifications_command both
  [ "$status" -eq 0 ]
  [ "$(omawsl_load_choice OMAWSL_HERDR_NOTIFICATIONS)" = "both" ]
  grep -qx 'delivery = "system"' "$HOME/.config/herdr/config.toml"
  grep -qx 'enabled = true' "$HOME/.config/herdr/config.toml"
  [ -L "$HOME/.local/bin/notify-send" ]
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

@test "rejects an unknown choice" {
  run omawsl_notifications_command loud
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown notifications choice 'loud'"* ]]
}

@test "with no argument, asks via gum and applies the pick" {
  gum_stub_respond "Sound only"
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

@test "omawsl-notify-send hands title and body to PowerShell and returns at once" {
  local out="$BATS_TEST_TMPDIR/ps.out"
  export OMAWSL_POWERSHELL_FALLBACK="$BATS_TEST_TMPDIR/powershell.exe"
  printf '#!/usr/bin/env bash\nprintf "%%s|%%s|%%s" "$OMAWSL_NOTIFY_TITLE" "$OMAWSL_NOTIFY_BODY" "$WSLENV" > %q\n' "$out" > "$OMAWSL_POWERSHELL_FALLBACK"
  chmod +x "$OMAWSL_POWERSHELL_FALLBACK"
  stub_hide_command powershell.exe
  export WSLENV="WT_SESSION:"
  run "$REPO_ROOT/bin/omawsl-notify-send" --app-name Herdr -- 'claude finished' 'ws · "1" <&>'
  [ "$status" -eq 0 ]
  local i
  for i in $(seq 50); do [ -s "$out" ] && break; sleep 0.1; done
  [ "$(cat "$out")" = 'claude finished|ws · "1" <&>|OMAWSL_NOTIFY_TITLE:OMAWSL_NOTIFY_BODY:WT_SESSION:' ]
}
