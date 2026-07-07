#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/install/terminal/app-cursor.sh"
}

@test "no-ops entirely when Cursor isn't selected" {
  export OMAWSL_EDITORS=""
  run omawsl_install_cursor
  [ "$status" -eq 0 ]
  [ ! -f "$HOME/.cursor-server/data/Machine/settings.json" ]
}

@test "deploys the shared settings file when cursor is reachable" {
  export OMAWSL_EDITORS="Cursor"
  stub_command cursor
  run omawsl_install_cursor
  [ "$status" -eq 0 ]
  [ -f "$HOME/.cursor-server/data/Machine/settings.json" ]
  diff "$HOME/.cursor-server/data/Machine/settings.json" "$REPO_ROOT/configs/vscode.json"
}

@test "deploys settings and prints a deferral message when cursor isn't reachable" {
  stub_hide_command cursor
  export OMAWSL_EDITORS="Cursor"
  run omawsl_install_cursor
  [ "$status" -eq 0 ]
  [ -f "$HOME/.cursor-server/data/Machine/settings.json" ]
  [[ "$output" == *"Cursor isn't reachable yet"* ]]
  [[ "$output" == *"docs/windows-setup.md#cursor"* ]]
}
