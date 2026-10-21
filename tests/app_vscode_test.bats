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

@test "deploys settings and never runs the Windows code CLI" {
  export OMAWSL_EDITORS="VS Code"
  stub_command code
  run omawsl_install_vscode
  [ "$status" -eq 0 ]
  [ -f "$HOME/.vscode-server/data/Machine/settings.json" ]
  diff "$HOME/.vscode-server/data/Machine/settings.json" "$REPO_ROOT/configs/vscode.json"
  [[ "$(stub_calls)" != *"code "* ]]
}

@test "points at docs/windows-setup.md when code isn't reachable" {
  stub_hide_command code
  export OMAWSL_EDITORS="VS Code"
  run omawsl_install_vscode
  [ "$status" -eq 0 ]
  [ -f "$HOME/.vscode-server/data/Machine/settings.json" ]
  [[ "$output" == *"VS Code isn't reachable yet"* ]]
  [[ "$output" == *"docs/windows-setup.md#vscode"* ]]
  [[ "$output" != *"code --"* ]]
}

@test "asks for VS Code's WSL extension when the Windows profile doesn't have it" {
  export OMAWSL_EDITORS="VS Code"
  stub_command code
  export OMAWSL_WINDOWS_USERS_DIR="$BATS_TEST_TMPDIR/Users"
  mkdir -p "$OMAWSL_WINDOWS_USERS_DIR/testuser/AppData/Roaming/Code" "$OMAWSL_WINDOWS_USERS_DIR/testuser/.vscode/extensions"
  run omawsl_install_vscode
  [ "$status" -eq 0 ]
  [[ "$output" == *"WSL extension"* ]]
  [[ "$output" == *"docs/windows-setup.md#vscode"* ]]
}

@test "says nothing about the WSL extension when the Windows profile has it" {
  export OMAWSL_EDITORS="VS Code"
  stub_command code
  export OMAWSL_WINDOWS_USERS_DIR="$BATS_TEST_TMPDIR/Users"
  mkdir -p "$OMAWSL_WINDOWS_USERS_DIR/testuser/AppData/Roaming/Code" \
    "$OMAWSL_WINDOWS_USERS_DIR/testuser/.vscode/extensions/ms-vscode-remote.remote-wsl-0.99.0"
  run omawsl_install_vscode
  [ "$status" -eq 0 ]
  [[ "$output" != *"WSL extension"* ]]
}

@test "omawsl_install_vscode leaves VS Code's native settings.json alone" {
  export OMAWSL_EDITORS="VS Code"
  stub_command code
  export OMAWSL_WINDOWS_USERS_DIR="$BATS_TEST_TMPDIR/Users"
  local code_settings="$OMAWSL_WINDOWS_USERS_DIR/testuser/AppData/Roaming/Code/User/settings.json"
  mkdir -p "$(dirname "$code_settings")"
  echo '{}' > "$code_settings"
  run omawsl_install_vscode
  [ "$status" -eq 0 ]
  [ "$(cat "$code_settings")" = "{}" ]
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

