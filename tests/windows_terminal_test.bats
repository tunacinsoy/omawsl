#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  export OMAWSL_WINDOWS_USERS_DIR="$BATS_TEST_TMPDIR/Users"
  WINHOME="$OMAWSL_WINDOWS_USERS_DIR/testuser"
  mkdir -p "$WINHOME/AppData" "$OMAWSL_WINDOWS_USERS_DIR/Public" "$OMAWSL_WINDOWS_USERS_DIR/Default/AppData" \
    "$OMAWSL_WINDOWS_USERS_DIR/Default User" "$OMAWSL_WINDOWS_USERS_DIR/All Users"
  touch "$OMAWSL_WINDOWS_USERS_DIR/desktop.ini"

  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/bin/omawsl-sub/windows-terminal.sh"
  command -v jq &>/dev/null || skip "jq not installed on this test host"
}

@test "omawsl_windows_userprofile finds the one real profile, skipping Windows' own folders" {
  run omawsl_windows_userprofile
  [ "$status" -eq 0 ]
  [ "$output" = "$WINHOME" ]
}

@test "omawsl_windows_userprofile never starts a Windows program" {
  local log="$BATS_TEST_TMPDIR/windows-calls"
  cmd.exe() { echo "cmd.exe $*" >> "$log"; }
  powershell.exe() { echo "powershell.exe $*" >> "$log"; }
  export -f cmd.exe powershell.exe
  run omawsl_windows_userprofile
  [ "$status" -eq 0 ]
  [ ! -e "$log" ]
}

@test "omawsl_windows_userprofile picks the profile named like the Linux user when there are several" {
  mkdir -p "$OMAWSL_WINDOWS_USERS_DIR/admin-account/AppData" "$OMAWSL_WINDOWS_USERS_DIR/Me/AppData"
  USER=me run omawsl_windows_userprofile
  [ "$status" -eq 0 ]
  [ "$output" = "$OMAWSL_WINDOWS_USERS_DIR/Me" ]
}

@test "omawsl_windows_userprofile fails with a hint when it can't tell which profile is yours" {
  mkdir -p "$OMAWSL_WINDOWS_USERS_DIR/admin-account/AppData"
  USER=someone-else run omawsl_windows_userprofile
  [ "$status" -ne 0 ]
  [[ "$output" == *"several Windows profiles"*"admin-account"*"testuser"* ]]
}

@test "omawsl_windows_userprofile fails quietly without a Windows side" {
  export OMAWSL_WINDOWS_USERS_DIR="$BATS_TEST_TMPDIR/no-such-dir"
  run omawsl_windows_userprofile
  [ "$status" -ne 0 ]
  [ -z "$output" ]
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
  stub_hide_command jq
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
