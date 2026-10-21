#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  MIGRATION="$REPO_ROOT/migrations/1792576841.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  export OMAWSL_WINDOWS_USERS_DIR="$BATS_TEST_TMPDIR/Users"
  WINHOME="$OMAWSL_WINDOWS_USERS_DIR/testuser"
  CODE_SETTINGS="$WINHOME/AppData/Roaming/Code/User/settings.json"
  mkdir -p "$(dirname "$CODE_SETTINGS")"
  echo '{"workbench.colorTheme": "Monokai Pro (Filter Ristretto)", "editor.fontSize": 14}' > "$CODE_SETTINGS"
  code() { echo "code $*" >> "$STUB_LOG"; }
  cmd.exe() { echo "cmd.exe $*" >> "$STUB_LOG"; }
  powershell.exe() { echo "powershell.exe $*" >> "$STUB_LOG"; }
  export -f code cmd.exe powershell.exe
  command -v jq &>/dev/null || skip "jq not installed on this test host"
}

# active_theme <name> - as if `omawsl theme <name>` had run: zellij points
# at it and its theme file exists.
active_theme() {
  mkdir -p "$HOME/.config/zellij/themes"
  printf 'theme "%s"\n' "$1" > "$HOME/.config/zellij/config.kdl"
  touch "$HOME/.config/zellij/themes/$1.kdl"
}

@test "re-applies the active theme's VS Code colors through settings, starting no program" {
  active_theme ristretto
  run bash "$MIGRATION"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.["workbench.colorTheme"]' "$CODE_SETTINGS")" = "Default Dark Modern" ]
  [ "$(jq -r '.["workbench.colorCustomizations"]["[Default Dark Modern][Dark Modern]"]["editor.background"]' "$CODE_SETTINGS")" = "#2c2525" ]
  [ "$(jq -r '.["editor.fontSize"]' "$CODE_SETTINGS")" = 14 ]
  [ -z "$(stub_calls)" ]
}

@test "leaves VS Code alone for someone who never picked a theme" {
  local before; before="$(cat "$CODE_SETTINGS")"
  run bash "$MIGRATION"
  [ "$status" -eq 0 ]
  [ "$(cat "$CODE_SETTINGS")" = "$before" ]
}

@test "points at Monokai Pro when it's still installed, without uninstalling it" {
  active_theme ristretto
  mkdir -p "$WINHOME/.vscode/extensions/monokai.theme-monokai-pro-vscode-2.0.7"
  run bash "$MIGRATION"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Monokai Pro"*"Extensions"* ]]
  [ -d "$WINHOME/.vscode/extensions/monokai.theme-monokai-pro-vscode-2.0.7" ]
  [ -z "$(stub_calls)" ]
}

@test "says nothing about Monokai Pro when it isn't installed" {
  active_theme tokyo-night
  run bash "$MIGRATION"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Monokai"* ]]
}
