#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  export OMAWSL_WINDOWS_USERS_DIR="$BATS_TEST_TMPDIR/Users"
  WINHOME="$OMAWSL_WINDOWS_USERS_DIR/testuser"
  mkdir -p "$WINHOME/AppData"
  TOKYO="$REPO_ROOT/themes/tokyo-night"
  TOKYO_BG="$(jq -r .background "$TOKYO/vscode-palette.json")"

  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/themes/set-vscode-theme.sh"
  command -v jq &>/dev/null || skip "jq not installed on this test host"
}

@test "omawsl_theme_apply_vscode writes the theme's colors into the native Windows Code and Cursor settings.json" {
  local code_dir="$WINHOME/AppData/Roaming/Code/User"
  local cursor_dir="$WINHOME/AppData/Roaming/Cursor/User"
  mkdir -p "$code_dir" "$cursor_dir"
  echo '{"editor.fontSize": 14}' > "$code_dir/settings.json"
  echo '{"editor.fontSize": 14}' > "$cursor_dir/settings.json"

  run omawsl_theme_apply_vscode "$TOKYO"
  [ "$status" -eq 0 ]
  local f
  for f in "$code_dir/settings.json" "$cursor_dir/settings.json"; do
    [ "$(jq -r '.["workbench.colorTheme"]' "$f")" = "Default Dark Modern" ]
    [ "$(jq -r '.["workbench.colorCustomizations"]["[Default Dark Modern][Dark Modern]"]["editor.background"]' "$f")" = "$TOKYO_BG" ]
    [ "$(jq -r '.["editor.fontSize"]' "$f")" = 14 ]
  done
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

  run omawsl_theme_apply_vscode "$TOKYO"
  [ "$status" -eq 0 ]
  grep -qF '// native user settings' "$code_dir/settings.json"
  [ "$(omawsl_strip_jsonc_comments "$code_dir/settings.json" | jq -r '.["workbench.colorTheme"]')" = "Default Dark Modern" ]
  [ "$(omawsl_strip_jsonc_comments "$code_dir/settings.json" | jq -r '.["workbench.colorCustomizations"]["[Default Dark Modern][Dark Modern]"]["editor.background"]')" = "$TOKYO_BG" ]
}

@test "omawsl_theme_apply_vscode skips the native sync when neither native settings.json exists" {
  run omawsl_theme_apply_vscode "$TOKYO"
  [ "$status" -eq 0 ]
  [ ! -d "$WINHOME/AppData/Roaming/Code" ]
  [ ! -d "$WINHOME/AppData/Roaming/Cursor" ]
}

@test "omawsl_theme_apply_vscode skips the native sync entirely when the Windows profile can't be resolved, but still syncs Remote-WSL settings" {
  export OMAWSL_WINDOWS_USERS_DIR="$BATS_TEST_TMPDIR/no-such-dir"
  mkdir -p "$HOME/.vscode-server/data/Machine"
  cp "$REPO_ROOT/configs/vscode.json" "$HOME/.vscode-server/data/Machine/settings.json"

  run omawsl_theme_apply_vscode "$TOKYO"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.["workbench.colorTheme"]' "$HOME/.vscode-server/data/Machine/settings.json")" = "Default Dark Modern" ]
  [ ! -d "$WINHOME/AppData/Roaming/Code" ]
  [ ! -d "$WINHOME/AppData/Roaming/Cursor" ]
}

@test "omawsl_theme_apply_vscode creates the native settings.json when the app is installed but has never had a User settings.json" {
  # The app's own top-level data dir (Roaming/Code) already existing is the
  # signal VS Code is actually installed and has run - real-world case
  # confirmed on a live machine where VS Code has years of cache/history but
  # the user never once opened Settings UI/JSON, so no settings.json ever
  # existed for the old "only edit an existing file" logic to find.
  local code_dir="$WINHOME/AppData/Roaming/Code"
  mkdir -p "$code_dir"
  [ ! -f "$code_dir/User/settings.json" ]

  run omawsl_theme_apply_vscode "$TOKYO"
  [ "$status" -eq 0 ]
  [ -f "$code_dir/User/settings.json" ]
  [ "$(jq -r '.["workbench.colorCustomizations"]["[Default Dark Modern][Dark Modern]"]["editor.background"]' "$code_dir/User/settings.json")" = "$TOKYO_BG" ]
}

@test "omawsl_theme_apply_vscode does not create a settings.json for an app whose top-level data dir doesn't exist at all" {
  # Distinguishes "app installed, never customized" (create it) from "app
  # not installed" (don't invent config for software that isn't there).
  run omawsl_theme_apply_vscode "$TOKYO"
  [ "$status" -eq 0 ]
  [ ! -d "$WINHOME/AppData/Roaming/Code" ]
  [ ! -d "$WINHOME/AppData/Roaming/Cursor" ]
}

@test "omawsl_theme_apply_vscode never starts a program: no code, no cmd.exe, no powershell.exe" {
  mkdir -p "$WINHOME/AppData/Roaming/Code/User"
  echo '{}' > "$WINHOME/AppData/Roaming/Code/User/settings.json"
  code() { echo "code $*" >> "$STUB_LOG"; }
  cmd.exe() { echo "cmd.exe $*" >> "$STUB_LOG"; }
  powershell.exe() { echo "powershell.exe $*" >> "$STUB_LOG"; }
  export -f code cmd.exe powershell.exe
  run omawsl_theme_apply_vscode "$TOKYO"
  [ "$status" -eq 0 ]
  [ -z "$(stub_calls)" ]
}

@test "omawsl_theme_apply_vscode gives a light theme VS Code's light base, and keeps only one omawsl color block" {
  local f="$WINHOME/AppData/Roaming/Code/User/settings.json"
  mkdir -p "$(dirname "$f")"
  echo '{"workbench.colorCustomizations": {"editor.lineHighlightBorder": "#ff0000"}}' > "$f"
  omawsl_theme_apply_vscode "$TOKYO"
  run omawsl_theme_apply_vscode "$REPO_ROOT/themes/rose-pine"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.["workbench.colorTheme"]' "$f")" = "Default Light Modern" ]
  [ "$(jq -c '.["workbench.colorCustomizations"] | keys' "$f")" = '["[Default Light Modern][Light Modern]","editor.lineHighlightBorder"]' ]
  [ "$(jq -c '.["editor.tokenColorCustomizations"] | keys' "$f")" = '["[Default Light Modern][Light Modern]"]' ]
  [ "$(jq -r '.["editor.semanticTokenColorCustomizations"]["[Default Light Modern][Light Modern]"].enabled' "$f")" = true ]
  [ "$(jq -r '.["editor.tokenColorCustomizations"]["[Default Light Modern][Light Modern]"].textMateRules | length > 0' "$f")" = true ]
}

@test "omawsl_theme_apply_vscode backs up the settings once, as they were before the theme switch" {
  local f="$WINHOME/AppData/Roaming/Code/User/settings.json"
  mkdir -p "$(dirname "$f")"
  echo '{"editor.fontSize": 14}' > "$f"
  run omawsl_theme_apply_vscode "$TOKYO"
  [ "$status" -eq 0 ]
  [ "$(cat "$f.bak")" = '{"editor.fontSize": 14}' ]
}

@test "omawsl_theme_apply_vscode names both IDs VS Code has used for its built-in theme, and replaces an older one-name block" {
  # VS Code 1.134 calls it "Dark Modern"; older versions "Default Dark
  # Modern". A block scoped to only the old ID is silently skipped by the
  # new one - found on the corporate machine.
  local f="$WINHOME/AppData/Roaming/Code/User/settings.json"
  mkdir -p "$(dirname "$f")"
  echo '{"workbench.colorCustomizations": {"[Default Dark Modern]": {"editor.background": "#000000"}}}' > "$f"
  run omawsl_theme_apply_vscode "$TOKYO"
  [ "$status" -eq 0 ]
  [ "$(jq -c '.["workbench.colorCustomizations"] | keys' "$f")" = '["[Default Dark Modern][Dark Modern]"]' ]
  [ "$(jq -c '.["editor.tokenColorCustomizations"] | keys' "$f")" = '["[Default Dark Modern][Dark Modern]"]' ]
}
