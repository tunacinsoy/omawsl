#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"

  # No real Windows profile is reachable by default (tests/helpers/stubs.bash
  # points the lookup at a folder that doesn't exist): omawsl_install_vscode
  # also writes the native settings.json, and on the real WSL machine this
  # suite runs on, an unguarded lookup once edited the user's actual VS Code
  # settings. Tests that need a profile build one under BATS_TEST_TMPDIR.

  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/install/terminal/app-vscode.sh"
}

@test "no-ops entirely when VS Code isn't selected" {
  export OMAWSL_EDITORS=""
  run omawsl_install_vscode
  [ "$status" -eq 0 ]
  [ ! -f "$HOME/.vscode-server/data/Machine/settings.json" ]
}

@test "deploys settings and installs the Remote-WSL extension when code is reachable" {
  export OMAWSL_EDITORS="VS Code"
  stub_command code
  run omawsl_install_vscode
  [ "$status" -eq 0 ]
  [ -f "$HOME/.vscode-server/data/Machine/settings.json" ]
  diff "$HOME/.vscode-server/data/Machine/settings.json" "$REPO_ROOT/configs/vscode.json"
  [[ "$(stub_calls)" == *"code --install-extension ms-vscode-remote.remote-wsl"* ]]
}

@test "deploys settings but defers the extension install when code isn't reachable" {
  stub_hide_command code
  export OMAWSL_EDITORS="VS Code"
  run omawsl_install_vscode
  [ "$status" -eq 0 ]
  [ -f "$HOME/.vscode-server/data/Machine/settings.json" ]
  [[ "$(stub_calls)" != *"code --install-extension"* ]]
  [[ "$output" == *"VS Code isn't reachable yet"* ]]
  [[ "$output" == *"docs/windows-setup.md#vscode"* ]]
}

@test "omawsl_install_vscode sets update.mode to manual in the native settings.json when VS Code is installed on Windows (issue #32/#9)" {
  export OMAWSL_EDITORS="VS Code"
  stub_command code
  export OMAWSL_WINDOWS_USERS_DIR="$BATS_TEST_TMPDIR/Users"
  WINHOME="$OMAWSL_WINDOWS_USERS_DIR/testuser"
  mkdir -p "$WINHOME/AppData/Roaming/Code"
  command -v jq &>/dev/null || skip "jq not installed on this test host"

  run omawsl_install_vscode
  [ "$status" -eq 0 ]
  local code_settings="$WINHOME/AppData/Roaming/Code/User/settings.json"
  [ -f "$code_settings" ]
  [[ "$(jq -r '.["update.mode"]' "$code_settings")" == "manual" ]]
}

@test "omawsl_install_vscode does not create native settings.json for a VS Code that isn't actually installed on Windows" {
  export OMAWSL_EDITORS="VS Code"
  stub_command code
  export OMAWSL_WINDOWS_USERS_DIR="$BATS_TEST_TMPDIR/Users"
  WINHOME="$OMAWSL_WINDOWS_USERS_DIR/testuser"
  mkdir -p "$WINHOME/AppData"

  run omawsl_install_vscode
  [ "$status" -eq 0 ]
  [ ! -d "$WINHOME/AppData/Roaming/Code" ]
}

@test "omawsl_install_vscode skips the native update.mode sync when the Windows profile can't be resolved" {
  export OMAWSL_EDITORS="VS Code"
  stub_command code
  # No Windows profile is reachable by default - see setup().

  run omawsl_install_vscode
  [ "$status" -eq 0 ]
  [ -f "$HOME/.vscode-server/data/Machine/settings.json" ]
}
