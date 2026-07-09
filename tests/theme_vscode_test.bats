#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/themes/set-vscode-theme.sh"
  command -v jq &>/dev/null || skip "jq not installed on this test host"
}

@test "omawsl_theme_set_vscode_settings merges workbench.colorTheme without touching other keys" {
  mkdir -p "$HOME/.vscode-server/data/Machine"
  local settings="$HOME/.vscode-server/data/Machine/settings.json"
  cp "$REPO_ROOT/configs/vscode.json" "$settings"
  run omawsl_theme_set_vscode_settings "$settings" "Tokyo Night"
  [ "$status" -eq 0 ]
  [[ "$(jq -r '.["workbench.colorTheme"]' "$settings")" == "Tokyo Night" ]]
  [[ "$(jq -r '.["editor.formatOnSave"]' "$settings")" == "true" ]]
}

@test "omawsl_theme_set_vscode_settings no-ops when the settings file doesn't exist" {
  run omawsl_theme_set_vscode_settings "$HOME/.vscode-server/data/Machine/settings.json" "Tokyo Night"
  [ "$status" -eq 0 ]
  [ ! -f "$HOME/.vscode-server/data/Machine/settings.json" ]
}

@test "omawsl_theme_apply_vscode patches both VS Code and Cursor settings, installs only the VS Code extension" {
  mkdir -p "$HOME/.vscode-server/data/Machine" "$HOME/.cursor-server/data/Machine"
  cp "$REPO_ROOT/configs/vscode.json" "$HOME/.vscode-server/data/Machine/settings.json"
  cp "$REPO_ROOT/configs/vscode.json" "$HOME/.cursor-server/data/Machine/settings.json"
  stub_command code
  run omawsl_theme_apply_vscode "Tokyo Night" "enkia.tokyo-night"
  [ "$status" -eq 0 ]
  [[ "$(jq -r '.["workbench.colorTheme"]' "$HOME/.vscode-server/data/Machine/settings.json")" == "Tokyo Night" ]]
  [[ "$(jq -r '.["workbench.colorTheme"]' "$HOME/.cursor-server/data/Machine/settings.json")" == "Tokyo Night" ]]
  [[ "$(stub_calls)" == *"code --install-extension enkia.tokyo-night"* ]]
}

@test "omawsl_theme_apply_vscode skips the extension install when code isn't reachable" {
  stub_hide_command code
  run omawsl_theme_apply_vscode "Tokyo Night" "enkia.tokyo-night"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"code --install-extension"* ]]
}
