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

@test "omawsl_theme_apply_vscode patches the native Windows Code and Cursor settings.json when they exist" {
  local code_dir="$WINHOME/AppData/Roaming/Code/User"
  local cursor_dir="$WINHOME/AppData/Roaming/Cursor/User"
  mkdir -p "$code_dir" "$cursor_dir"
  echo '{"editor.fontSize": 14}' > "$code_dir/settings.json"
  echo '{"editor.fontSize": 14}' > "$cursor_dir/settings.json"

  run omawsl_theme_apply_vscode "Tokyo Night" "enkia.tokyo-night"
  [ "$status" -eq 0 ]
  [[ "$(jq -r '.["workbench.colorTheme"]' "$code_dir/settings.json")" == "Tokyo Night" ]]
  [[ "$(jq -r '.["workbench.colorTheme"]' "$cursor_dir/settings.json")" == "Tokyo Night" ]]
  [ -f "$code_dir/settings.json.bak" ]
  [ -f "$cursor_dir/settings.json.bak" ]
}

@test "omawsl_theme_apply_vscode preserves comments in a native settings.json with JSONC content" {
  local code_dir="$WINHOME/AppData/Roaming/Code/User"
  mkdir -p "$code_dir"
  cat > "$code_dir/settings.json" <<'EOF'
{
  // native user settings
  "editor.fontSize": 14
}
EOF

  run omawsl_theme_apply_vscode "Tokyo Night" "enkia.tokyo-night"
  [ "$status" -eq 0 ]
  grep -qF '// native user settings' "$code_dir/settings.json"
  [[ "$(omawsl_strip_jsonc_comments "$code_dir/settings.json" | jq -r '.["workbench.colorTheme"]')" == "Tokyo Night" ]]
}

@test "omawsl_theme_apply_vscode skips the native sync when neither native settings.json exists" {
  run omawsl_theme_apply_vscode "Tokyo Night" "enkia.tokyo-night"
  [ "$status" -eq 0 ]
  [ ! -d "$WINHOME/AppData/Roaming/Code" ]
  [ ! -d "$WINHOME/AppData/Roaming/Cursor" ]
}

@test "omawsl_theme_apply_vscode skips the native sync entirely when the Windows profile can't be resolved, but still syncs Remote-WSL settings" {
  unset -f cmd.exe
  stub_hide_command cmd.exe
  mkdir -p "$HOME/.vscode-server/data/Machine"
  cp "$REPO_ROOT/configs/vscode.json" "$HOME/.vscode-server/data/Machine/settings.json"

  run omawsl_theme_apply_vscode "Tokyo Night" "enkia.tokyo-night"
  [ "$status" -eq 0 ]
  [[ "$(jq -r '.["workbench.colorTheme"]' "$HOME/.vscode-server/data/Machine/settings.json")" == "Tokyo Night" ]]
  [ ! -d "$WINHOME/AppData/Roaming/Code" ]
  [ ! -d "$WINHOME/AppData/Roaming/Cursor" ]
}
