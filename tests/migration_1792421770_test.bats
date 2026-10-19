#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.vscode-server/data/Machine"
  WINHOME="$BATS_TEST_TMPDIR/winhome"
  mkdir -p "$WINHOME/AppData/Roaming/Code/User"
  export WINHOME

  cmd.exe() {
    echo "cmd.exe $*" >> "$STUB_LOG"
    if [[ "$*" == *USERPROFILE* ]]; then
      printf 'C:\\Users\\testuser\r\n'
    fi
  }
  export -f cmd.exe

  wslpath() {
    echo "$WINHOME"
  }
  export -f wslpath

  # Never let a test reach the real Windows side via cmd.exe's fixed
  # fallback path (see tests/theme_vscode_test.bats).
  export OMAWSL_CMD_EXE_FALLBACK="$BATS_TEST_TMPDIR/no-such-cmd.exe"

  stub_command code
  command -v jq &>/dev/null || skip "jq not installed on this test host"
  command -v python3 &>/dev/null || skip "python3 not installed on this test host"
}

@test "moves a Monokai Pro Ristretto user onto omawsl's own Ristretto theme everywhere" {
  echo '{"workbench.colorTheme": "Monokai Pro (Filter Ristretto)"}' > "$WINHOME/AppData/Roaming/Code/User/settings.json"
  echo '{"workbench.colorTheme": "Monokai Pro (Filter Ristretto)"}' > "$HOME/.vscode-server/data/Machine/settings.json"
  run bash "$REPO_ROOT/migrations/1792421770.sh"
  [ "$status" -eq 0 ]
  [[ "$(jq -r '.["workbench.colorTheme"]' "$WINHOME/AppData/Roaming/Code/User/settings.json")" == "Ristretto (omawsl)" ]]
  [[ "$(jq -r '.["workbench.colorTheme"]' "$HOME/.vscode-server/data/Machine/settings.json")" == "Ristretto (omawsl)" ]]
  [[ "$(stub_calls)" == *"code --install-extension omawsl-ristretto-theme.vsix --force"* ]]
}

@test "uninstalls Monokai Pro on both sides after installing the replacement theme" {
  echo '{"workbench.colorTheme": "Monokai Pro (Filter Ristretto)"}' > "$WINHOME/AppData/Roaming/Code/User/settings.json"
  run bash "$REPO_ROOT/migrations/1792421770.sh"
  [ "$status" -eq 0 ]
  local calls; calls="$(stub_calls)"
  [[ "$calls" == *"code --uninstall-extension monokai.theme-monokai-pro-vscode"* ]]
  [[ "$calls" == *"cmd.exe /c set NODE_NO_WARNINGS=1&&code --uninstall-extension monokai.theme-monokai-pro-vscode"* ]]
  # The replacement is installed before Monokai Pro is removed.
  local before_uninstall="${calls%%--uninstall-extension*}"
  [[ "$before_uninstall" == *"omawsl-ristretto-theme.vsix"* ]]
}

@test "uninstalls Monokai Pro but leaves the theme alone for someone on a different theme" {
  echo '{"workbench.colorTheme": "Tokyo Night"}' > "$WINHOME/AppData/Roaming/Code/User/settings.json"
  run bash "$REPO_ROOT/migrations/1792421770.sh"
  [ "$status" -eq 0 ]
  [[ "$(jq -r '.["workbench.colorTheme"]' "$WINHOME/AppData/Roaming/Code/User/settings.json")" == "Tokyo Night" ]]
  [[ "$(stub_calls)" != *"omawsl-ristretto-theme.vsix"* ]]
  [[ "$(stub_calls)" == *"code --uninstall-extension monokai.theme-monokai-pro-vscode"* ]]
}

@test "no-ops cleanly when neither VS Code nor Windows is reachable" {
  unset -f cmd.exe code
  stub_hide_command cmd.exe code
  run bash "$REPO_ROOT/migrations/1792421770.sh"
  [ "$status" -eq 0 ]
  [ -z "$(stub_calls)" ]
}

@test "version is bumped to this migration so fresh installs don't rerun it" {
  [[ "$(cat "$REPO_ROOT/version")" -ge 1792421770 ]]
}
