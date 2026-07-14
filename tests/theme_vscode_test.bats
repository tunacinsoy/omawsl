#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  WINHOME="$BATS_TEST_TMPDIR/winhome"
  mkdir -p "$WINHOME"

  cmd.exe() {
    if [[ "$*" == *USERPROFILE* ]]; then
      printf 'C:\\Users\\testuser\r\n'
    fi
  }
  export -f cmd.exe

  wslpath() {
    echo "$WINHOME"
  }
  export -f wslpath

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

@test "omawsl_theme_set_vscode_settings backs up the file before editing" {
  mkdir -p "$HOME/.vscode-server/data/Machine"
  local settings="$HOME/.vscode-server/data/Machine/settings.json"
  cp "$REPO_ROOT/configs/vscode.json" "$settings"
  run omawsl_theme_set_vscode_settings "$settings" "Tokyo Night"
  [ "$status" -eq 0 ]
  [ -f "$settings.bak" ]
  [[ "$(jq -r '.["workbench.colorTheme"]' "$settings.bak")" == "Default Dark Modern" ]]
}

@test "omawsl_theme_set_vscode_settings adds workbench.colorTheme to a JSONC file and preserves its comments" {
  local settings="$BATS_TEST_TMPDIR/settings.json"
  cat > "$settings" <<'EOF'
{
  // editor settings
  "editor.fontSize": 14,
  "editor.tabSize": 2
}
EOF
  run omawsl_theme_set_vscode_settings "$settings" "Tokyo Night"
  [ "$status" -eq 0 ]
  grep -qF '// editor settings' "$settings"
  [[ "$(omawsl_strip_jsonc_comments "$settings" | jq -r '.["workbench.colorTheme"]')" == "Tokyo Night" ]]
  [[ "$(omawsl_strip_jsonc_comments "$settings" | jq -r '.["editor.tabSize"]')" == "2" ]]
}

@test "omawsl_theme_set_vscode_settings replaces an existing workbench.colorTheme in a JSONC file and preserves its comments" {
  local settings="$BATS_TEST_TMPDIR/settings.json"
  cat > "$settings" <<'EOF'
{
  "workbench.colorTheme": "Default Dark Modern", // active theme
  "editor.fontSize": 14
}
EOF
  run omawsl_theme_set_vscode_settings "$settings" "Tokyo Night"
  [ "$status" -eq 0 ]
  grep -qF '// active theme' "$settings"
  [[ "$(omawsl_strip_jsonc_comments "$settings" | jq -r '.["workbench.colorTheme"]')" == "Tokyo Night" ]]
  [[ "$(omawsl_strip_jsonc_comments "$settings" | jq -r '.["editor.fontSize"]')" == "14" ]]
}

@test "omawsl_theme_set_vscode_settings skips gracefully when the file isn't valid JSON even after stripping comments" {
  local settings="$BATS_TEST_TMPDIR/settings.json"
  printf 'not valid json {{{\n' > "$settings"
  run omawsl_theme_set_vscode_settings "$settings" "Tokyo Night"
  [ "$status" -eq 0 ]
  [[ "$output" == *"isn't valid JSON"* ]]
  [[ "$(cat "$settings")" == "not valid json {{{" ]]
}

@test "omawsl_theme_set_vscode_settings rolls back and leaves the file untouched if its own edit would corrupt the JSON" {
  local settings="$BATS_TEST_TMPDIR/settings.json"
  cat > "$settings" <<'EOF'
// use { as a note
{
  "editor.fontSize": 14
}
EOF
  local original; original="$(cat "$settings")"
  run omawsl_theme_set_vscode_settings "$settings" "Tokyo Night"
  [ "$status" -eq 0 ]
  [[ "$output" == *"invalid JSON"* ]]
  [ -f "$settings.bak" ]
  [[ "$(cat "$settings")" == "$original" ]]
}
