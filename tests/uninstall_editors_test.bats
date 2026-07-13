#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/uninstall/app-vscode.sh"
  source "$REPO_ROOT/uninstall/app-cursor.sh"
}

@test "omawsl_uninstall_vscode removes the deployed settings file and uninstalls the extension when code is reachable" {
  local settings="$HOME/.vscode-server/data/Machine/settings.json"
  mkdir -p "$(dirname "$settings")"
  echo '{}' > "$settings"
  stub_command code
  run omawsl_uninstall_vscode "$settings"
  [ "$status" -eq 0 ]
  [ ! -f "$settings" ]
  [[ "$(stub_calls)" == *"code --uninstall-extension ms-vscode-remote.remote-wsl"* ]]
}

@test "omawsl_uninstall_vscode removes the settings file even when code isn't reachable" {
  local settings="$HOME/.vscode-server/data/Machine/settings.json"
  mkdir -p "$(dirname "$settings")"
  echo '{}' > "$settings"
  stub_hide_command code
  run omawsl_uninstall_vscode "$settings"
  [ "$status" -eq 0 ]
  [ ! -f "$settings" ]
}

@test "omawsl_uninstall_cursor removes the deployed settings file" {
  local settings="$HOME/.cursor-server/data/Machine/settings.json"
  mkdir -p "$(dirname "$settings")"
  echo '{}' > "$settings"
  run omawsl_uninstall_cursor "$settings"
  [ "$status" -eq 0 ]
  [ ! -f "$settings" ]
}
