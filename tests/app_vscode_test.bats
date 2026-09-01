#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"

  # Default to "no real Windows profile reachable" for every test in this
  # file: omawsl_install_vscode now also calls
  # omawsl_vscode_disable_auto_update, which resolves a real Windows
  # profile via cmd.exe/wslpath - on a real WSL2 host (like the one this
  # suite is actually developed/run on) an unstubbed cmd.exe would resolve
  # the *real* %USERPROFILE% and edit that machine's actual native VS Code
  # settings.json. Confirmed live: running this file without this guard
  # did exactly that. Tests that need a resolvable profile stub their own
  # cmd.exe/wslpath functions (which take precedence over this hidden
  # $PATH regardless), same pattern as theme_vscode_windows_test.bats.
  stub_hide_command cmd.exe
  export OMAWSL_CMD_EXE_FALLBACK="$BATS_TEST_TMPDIR/no-such-cmd.exe"

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
  WINHOME="$BATS_TEST_TMPDIR/winhome"
  mkdir -p "$WINHOME/AppData/Roaming/Code"

  cmd.exe() {
    echo "cmd.exe $*" >> "$STUB_LOG"
    [[ "$*" == *USERPROFILE* ]] && printf 'C:\\Users\\testuser\r\n'
  }
  export -f cmd.exe
  wslpath() { echo "$WINHOME"; }
  export -f wslpath
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
  WINHOME="$BATS_TEST_TMPDIR/winhome"
  mkdir -p "$WINHOME"

  cmd.exe() {
    echo "cmd.exe $*" >> "$STUB_LOG"
    [[ "$*" == *USERPROFILE* ]] && printf 'C:\\Users\\testuser\r\n'
  }
  export -f cmd.exe
  wslpath() { echo "$WINHOME"; }
  export -f wslpath

  run omawsl_install_vscode
  [ "$status" -eq 0 ]
  [ ! -d "$WINHOME/AppData/Roaming/Code" ]
}

@test "omawsl_install_vscode skips the native update.mode sync when the Windows profile can't be resolved" {
  export OMAWSL_EDITORS="VS Code"
  stub_command code
  # cmd.exe is already unreachable by default - see setup().

  run omawsl_install_vscode
  [ "$status" -eq 0 ]
  [ -f "$HOME/.vscode-server/data/Machine/settings.json" ]
}
