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
  source "$REPO_ROOT/bin/omawsl-sub/windows-terminal.sh"
  command -v jq &>/dev/null || skip "jq not installed on this test host"
}

@test "omawsl_windows_userprofile resolves via cmd.exe and wslpath" {
  run omawsl_windows_userprofile
  [ "$status" -eq 0 ]
  [ "$output" = "$WINHOME" ]
}

@test "omawsl_windows_userprofile fails cleanly when cmd.exe isn't reachable" {
  unset -f cmd.exe
  run omawsl_windows_userprofile
  [ "$status" -ne 0 ]
}

@test "omawsl_windows_terminal_settings_path finds the Store-package path first" {
  local store_dir="$WINHOME/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState"
  mkdir -p "$store_dir"
  echo '{"schemes":[],"profiles":{"defaults":{}}}' > "$store_dir/settings.json"
  run omawsl_windows_terminal_settings_path
  [ "$status" -eq 0 ]
  [ "$output" = "$store_dir/settings.json" ]
}

@test "omawsl_windows_terminal_settings_path falls back to the unpackaged path" {
  local unpackaged_dir="$WINHOME/AppData/Local/Microsoft/Windows Terminal"
  mkdir -p "$unpackaged_dir"
  echo '{"schemes":[],"profiles":{"defaults":{}}}' > "$unpackaged_dir/settings.json"
  run omawsl_windows_terminal_settings_path
  [ "$status" -eq 0 ]
  [ "$output" = "$unpackaged_dir/settings.json" ]
}

@test "omawsl_windows_terminal_settings_path fails when neither path exists" {
  run omawsl_windows_terminal_settings_path
  [ "$status" -ne 0 ]
}

@test "omawsl_theme_apply_windows_terminal merges the scheme, backs up first, and sets the default colorScheme" {
  local store_dir="$WINHOME/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState"
  mkdir -p "$store_dir"
  echo '{"schemes":[{"name":"Other Scheme","background":"#000000"}],"profiles":{"defaults":{"colorScheme":"Other Scheme"}}}' > "$store_dir/settings.json"

  run omawsl_theme_apply_windows_terminal "$REPO_ROOT/themes/tokyo-night/windows-terminal-scheme.json"
  [ "$status" -eq 0 ]

  [ -f "$store_dir/settings.json.bak" ]
  [[ "$(jq -r '.profiles.defaults.colorScheme' "$store_dir/settings.json")" == "Tokyo Night" ]]
  [[ "$(jq -r '.schemes | map(.name) | sort | join(",")' "$store_dir/settings.json")" == "Other Scheme,Tokyo Night" ]]
  [[ "$(jq -r '.schemes[] | select(.name == "Tokyo Night") | .background' "$store_dir/settings.json")" == "#1a1b26" ]]
}

@test "omawsl_theme_apply_windows_terminal replaces a same-named scheme instead of duplicating it" {
  local store_dir="$WINHOME/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState"
  mkdir -p "$store_dir"
  echo '{"schemes":[{"name":"Tokyo Night","background":"#000000"}],"profiles":{"defaults":{}}}' > "$store_dir/settings.json"

  run omawsl_theme_apply_windows_terminal "$REPO_ROOT/themes/tokyo-night/windows-terminal-scheme.json"
  [ "$status" -eq 0 ]
  [[ "$(jq -r '.schemes | length' "$store_dir/settings.json")" == "1" ]]
  [[ "$(jq -r '.schemes[0].background' "$store_dir/settings.json")" == "#1a1b26" ]]
}

@test "omawsl_theme_apply_windows_terminal skips gracefully when settings.json can't be found" {
  run omawsl_theme_apply_windows_terminal "$REPO_ROOT/themes/tokyo-night/windows-terminal-scheme.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"docs/windows-setup.md"* ]]
}

@test "omawsl_theme_apply_windows_terminal skips gracefully when jq isn't reachable" {
  stub_hide_command jq wslpath
  wslpath() { echo "$WINHOME"; }
  export -f wslpath
  run omawsl_theme_apply_windows_terminal "$REPO_ROOT/themes/tokyo-night/windows-terminal-scheme.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"jq"* ]]
}

@test "omawsl_theme_apply_windows_terminal skips gracefully when settings.json is invalid JSON" {
  local store_dir="$WINHOME/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState"
  mkdir -p "$store_dir"
  echo 'not valid json {{{' > "$store_dir/settings.json"

  run omawsl_theme_apply_windows_terminal "$REPO_ROOT/themes/tokyo-night/windows-terminal-scheme.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"isn't valid JSON"* ]]

  [ ! -f "$store_dir/settings.json.bak" ]
  [[ "$(cat "$store_dir/settings.json")" == "not valid json {{{" ]]
}
