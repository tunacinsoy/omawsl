#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
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
