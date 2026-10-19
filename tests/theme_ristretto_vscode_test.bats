#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  WINHOME="$BATS_TEST_TMPDIR/winhome"
  mkdir -p "$WINHOME"
  export WINHOME

  # Logs the working directory and whether the staged .vsix is there at
  # call time, so the native-install tests can check `code` really runs
  # from the folder the .vsix was copied into.
  cmd.exe() {
    echo "cmd.exe [$PWD] $*" >> "$STUB_LOG"
    if [[ "$*" == *USERPROFILE* ]]; then
      printf 'C:\\Users\\testuser\r\n'
    fi
    if [[ "$*" == *"omawsl-ristretto-theme.vsix"* && -f "$PWD/omawsl-ristretto-theme.vsix" ]]; then
      echo "vsix-staged" >> "$STUB_LOG"
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

  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/themes/set-vscode-theme.sh"
  command -v jq &>/dev/null || skip "jq not installed on this test host"
  command -v python3 &>/dev/null || skip "python3 not installed on this test host"
}

@test "the Ristretto VS Code theme is valid JSON using the Ristretto palette, with no template slots left unfilled" {
  local theme="$REPO_ROOT/themes/ristretto/vscode-extension/themes/ristretto-color-theme.json"
  jq empty "$theme"
  [[ "$(jq -r '.colors["editor.background"]' "$theme")" == "#2c2525" ]]
  [[ "$(jq -r '.colors["editor.foreground"]' "$theme")" == "#e6d9db" ]]
  [[ "$(jq -r '.type' "$theme")" == "dark" ]]
  ! grep -q '{{' "$theme"
}

@test "the Ristretto VS Code extension contributes the theme label omawsl selects" {
  local pkg="$REPO_ROOT/themes/ristretto/vscode-extension/package.json"
  [[ "$(jq -r '.contributes.themes[0].label' "$pkg")" == "Ristretto (omawsl)" ]]
  [[ "$(jq -r '.contributes.themes[0].uiTheme' "$pkg")" == "vs-dark" ]]
  [ -f "$REPO_ROOT/themes/ristretto/vscode-extension/$(jq -r '.contributes.themes[0].path' "$pkg")" ]
}

@test "omawsl_theme_build_vsix packages the extension under extension/, the layout code --install-extension reads" {
  local out="$BATS_TEST_TMPDIR/out/omawsl-ristretto-theme.vsix"
  mkdir -p "$(dirname "$out")"
  run omawsl_theme_build_vsix "$REPO_ROOT/themes/ristretto/vscode-extension" "$out"
  [ "$status" -eq 0 ]
  local listing; listing="$(python3 -m zipfile -l "$out")"
  [[ "$listing" == *"extension/package.json"* ]]
  [[ "$listing" == *"extension/themes/ristretto-color-theme.json"* ]]
}

@test "omawsl_theme_apply_vscode never hands a .vsix's Linux path to the WSL-side code CLI" {
  # From a WSL shell, `code` is VS Code's Windows CLI (/mnt/c/...), which
  # refuses \\wsl.localhost paths (ERR_UNC_HOST_NOT_ALLOWED) - confirmed
  # live. Color themes load from the Windows side even in Remote-WSL
  # windows, so the native install below is the only one needed.
  stub_command code
  local vsix="$BATS_TEST_TMPDIR/omawsl-ristretto-theme.vsix"
  touch "$vsix"
  run omawsl_theme_apply_vscode "Ristretto (omawsl)" "$vsix"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"code --install-extension $vsix"* ]]
}

@test "omawsl_theme_apply_vscode installs a .vsix natively even when code isn't on the WSL PATH" {
  stub_hide_command code
  local vsix="$BATS_TEST_TMPDIR/omawsl-ristretto-theme.vsix"
  touch "$vsix"
  run omawsl_theme_apply_vscode "Ristretto (omawsl)" "$vsix"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"/c set NODE_NO_WARNINGS=1&&code --install-extension omawsl-ristretto-theme.vsix --force"* ]]
}

@test "omawsl_theme_apply_vscode installs a .vsix natively by running code from the Windows temp folder it was copied to" {
  stub_command code
  local vsix="$BATS_TEST_TMPDIR/omawsl-ristretto-theme.vsix"
  touch "$vsix"
  run omawsl_theme_apply_vscode "Ristretto (omawsl)" "$vsix"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"cmd.exe [$WINHOME/AppData/Local/Temp] /c set NODE_NO_WARNINGS=1&&code --install-extension omawsl-ristretto-theme.vsix --force"* ]]
  [[ "$(stub_calls)" == *"vsix-staged"* ]]
  [ ! -f "$WINHOME/AppData/Local/Temp/omawsl-ristretto-theme.vsix" ]
}

@test "themes/ristretto/vscode.sh selects the omawsl Ristretto theme and never installs Monokai Pro" {
  mkdir -p "$HOME/.vscode-server/data/Machine"
  echo '{}' > "$HOME/.vscode-server/data/Machine/settings.json"
  stub_command code
  run bash -c "set -euo pipefail; source '$REPO_ROOT/themes/ristretto/vscode.sh'"
  [ "$status" -eq 0 ]
  [[ "$(jq -r '.["workbench.colorTheme"]' "$HOME/.vscode-server/data/Machine/settings.json")" == "Ristretto (omawsl)" ]]
  [[ "$(stub_calls)" == *"code --install-extension omawsl-ristretto-theme.vsix --force"* ]]
  [[ "$(stub_calls)" != *"monokai"* ]]
}

@test "omawsl_theme_vscode_uses finds a theme set in any VS Code or Cursor settings file" {
  mkdir -p "$WINHOME/AppData/Roaming/Cursor/User"
  echo '{"workbench.colorTheme": "Monokai Pro (Filter Ristretto)"}' > "$WINHOME/AppData/Roaming/Cursor/User/settings.json"
  run omawsl_theme_vscode_uses "Monokai Pro (Filter Ristretto)"
  [ "$status" -eq 0 ]
  run omawsl_theme_vscode_uses "Tokyo Night"
  [ "$status" -ne 0 ]
}

@test "omawsl_vscode_uninstall_extension removes the extension on both the WSL and Windows sides" {
  stub_command code
  run omawsl_vscode_uninstall_extension monokai.theme-monokai-pro-vscode
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"code --uninstall-extension monokai.theme-monokai-pro-vscode"* ]]
  [[ "$(stub_calls)" == *"/c set NODE_NO_WARNINGS=1&&code --uninstall-extension monokai.theme-monokai-pro-vscode"* ]]
}

@test "omawsl_vscode_uninstall_extension ignores 'not installed' failures" {
  code() { echo "code $*" >> "$STUB_LOG"; return 1; }
  export -f code
  BATS_RUN_ERREXIT=1 run omawsl_vscode_uninstall_extension monokai.theme-monokai-pro-vscode
  [ "$status" -eq 0 ]
}
