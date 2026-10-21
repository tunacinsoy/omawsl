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

@test "omawsl_theme_apply_vscode gives both Remote-WSL settings files the theme's colors" {
  mkdir -p "$HOME/.vscode-server/data/Machine" "$HOME/.cursor-server/data/Machine"
  cp "$REPO_ROOT/configs/vscode.json" "$HOME/.vscode-server/data/Machine/settings.json"
  cp "$REPO_ROOT/configs/vscode.json" "$HOME/.cursor-server/data/Machine/settings.json"
  run omawsl_theme_apply_vscode "$REPO_ROOT/themes/tokyo-night"
  [ "$status" -eq 0 ]
  local f bg
  bg="$(jq -r .background "$REPO_ROOT/themes/tokyo-night/vscode-palette.json")"
  for f in "$HOME/.vscode-server/data/Machine/settings.json" "$HOME/.cursor-server/data/Machine/settings.json"; do
    [ "$(jq -r '.["workbench.colorTheme"]' "$f")" = "Default Dark Modern" ]
    [ "$(jq -r '.["workbench.colorCustomizations"]["[Default Dark Modern][Dark Modern]"]["editor.background"]' "$f")" = "$bg" ]
  done
}

@test "omawsl_theme_apply_vscode carries on past a broken settings file, even under set -e" {
  mkdir -p "$HOME/.vscode-server/data/Machine" "$HOME/.cursor-server/data/Machine"
  printf 'not valid json {{{\n' > "$HOME/.vscode-server/data/Machine/settings.json"
  cp "$REPO_ROOT/configs/vscode.json" "$HOME/.cursor-server/data/Machine/settings.json"
  # theme.sh/set-vscode-theme.sh run under `set -euo pipefail`; bats' `run`
  # normally turns errexit off, so force it back on.
  BATS_RUN_ERREXIT=1 run omawsl_theme_apply_vscode "$REPO_ROOT/themes/tokyo-night"
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.vscode-server/data/Machine/settings.json")" = "not valid json {{{" ]
  [ "$(jq -r '.["workbench.colorTheme"]' "$HOME/.cursor-server/data/Machine/settings.json")" = "Default Dark Modern" ]
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

@test "omawsl_theme_ensure_vscode_settings_exists creates an empty settings.json when the app's data dir exists but the file doesn't" {
  local app_dir="$BATS_TEST_TMPDIR/AppRoot"
  mkdir -p "$app_dir"
  local settings="$app_dir/User/settings.json"
  run omawsl_theme_ensure_vscode_settings_exists "$settings"
  [ "$status" -eq 0 ]
  [ -f "$settings" ]
  [[ "$(jq -c '.' "$settings")" == "{}" ]]
}

@test "omawsl_theme_ensure_vscode_settings_exists does nothing when the app's data dir doesn't exist" {
  local settings="$BATS_TEST_TMPDIR/NoSuchApp/User/settings.json"
  run omawsl_theme_ensure_vscode_settings_exists "$settings"
  [ "$status" -eq 0 ]
  [ ! -f "$settings" ]
  [ ! -d "$BATS_TEST_TMPDIR/NoSuchApp" ]
}

@test "omawsl_theme_ensure_vscode_settings_exists does nothing when the settings.json already exists" {
  local app_dir="$BATS_TEST_TMPDIR/AppRoot"
  mkdir -p "$app_dir/User"
  local settings="$app_dir/User/settings.json"
  echo '{"editor.fontSize": 14}' > "$settings"
  run omawsl_theme_ensure_vscode_settings_exists "$settings"
  [ "$status" -eq 0 ]
  [[ "$(cat "$settings")" == '{"editor.fontSize": 14}' ]]
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

@test "omawsl_theme_set_vscode_settings handles a theme name with parentheses and spaces (Monokai Pro (Filter Ristretto))" {
  local settings="$BATS_TEST_TMPDIR/settings.json"
  cat > "$settings" <<'EOF'
{
  // editor settings
  "editor.fontSize": 14
}
EOF
  run omawsl_theme_set_vscode_settings "$settings" "Monokai Pro (Filter Ristretto)"
  [ "$status" -eq 0 ]
  grep -qF '// editor settings' "$settings"
  [[ "$(omawsl_strip_jsonc_comments "$settings" | jq -r '.["workbench.colorTheme"]')" == "Monokai Pro (Filter Ristretto)" ]]
}

@test "omawsl_theme_set_vscode_settings handles a theme name with a colon (Ocean Green: Dark)" {
  local settings="$BATS_TEST_TMPDIR/settings.json"
  cat > "$settings" <<'EOF'
{
  "workbench.colorTheme": "Default Dark Modern", // active theme
  "editor.fontSize": 14
}
EOF
  run omawsl_theme_set_vscode_settings "$settings" "Ocean Green: Dark"
  [ "$status" -eq 0 ]
  grep -qF '// active theme' "$settings"
  [[ "$(omawsl_strip_jsonc_comments "$settings" | jq -r '.["workbench.colorTheme"]')" == "Ocean Green: Dark" ]]
}

@test "omawsl_json_update_value merges into an object setting and keeps the user's own entries" {
  local settings="$BATS_TEST_TMPDIR/settings.json"
  echo '{"workbench.colorCustomizations": {"editor.background": "#000000"}, "editor.fontSize": 14}' > "$settings"
  run omawsl_json_update_value "$settings" workbench.colorCustomizations '(. // {}) + {"[Default Dark Modern]": $v}' '{"focusBorder": "#f38d70"}'
  [ "$status" -eq 0 ]
  [ "$(jq -c '.["workbench.colorCustomizations"]' "$settings")" = '{"editor.background":"#000000","[Default Dark Modern]":{"focusBorder":"#f38d70"}}' ]
  [ "$(jq -r '.["editor.fontSize"]' "$settings")" = 14 ]
}

@test "omawsl_json_update_value adds a missing object setting to a JSONC file on one line, keeping comments" {
  local settings="$BATS_TEST_TMPDIR/settings.json"
  printf '{\n  // mine\n  "editor.fontSize": 14\n}\n' > "$settings"
  run omawsl_json_update_value "$settings" workbench.colorCustomizations '(. // {}) + {"[Default Dark Modern]": $v}' '{"focusBorder": "#f38d70"}'
  [ "$status" -eq 0 ]
  grep -qF '// mine' "$settings"
  grep -qxF '  "workbench.colorCustomizations": {"[Default Dark Modern]":{"focusBorder":"#f38d70"}},' "$settings"
  [ "$(omawsl_strip_jsonc_comments "$settings" | jq -r '.["editor.fontSize"]')" = 14 ]
}

@test "omawsl_json_update_value updates a one-line object setting in a JSONC file in place" {
  local settings="$BATS_TEST_TMPDIR/settings.json"
  printf '{\n  // mine\n  "workbench.colorCustomizations": {"editor.background":"#000000","[Default Dark Modern]":{"focusBorder":"#111111"}},\n  "editor.fontSize": 14\n}\n' > "$settings"
  run omawsl_json_update_value "$settings" workbench.colorCustomizations '(. // {}) + {"[Default Dark Modern]": $v}' '{"focusBorder": "#f38d70"}'
  [ "$status" -eq 0 ]
  grep -qF '// mine' "$settings"
  [ "$(omawsl_strip_jsonc_comments "$settings" | jq -c '.["workbench.colorCustomizations"]')" = '{"editor.background":"#000000","[Default Dark Modern]":{"focusBorder":"#f38d70"}}' ]
}

@test "omawsl_json_update_value leaves a hand-written multi-line setting in a JSONC file alone and says so" {
  local settings="$BATS_TEST_TMPDIR/settings.json"
  printf '{\n  // mine\n  "workbench.colorCustomizations": {\n    "editor.background": "#000000"\n  }\n}\n' > "$settings"
  local before; before="$(cat "$settings")"
  run omawsl_json_update_value "$settings" workbench.colorCustomizations '(. // {}) + {"[Default Dark Modern]": $v}' '{"focusBorder": "#f38d70"}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"workbench.colorCustomizations"*"spans several lines"* ]]
  [ "$(cat "$settings")" = "$before" ]
}
