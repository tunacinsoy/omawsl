#!/usr/bin/env bats

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

@test "every ported theme has all 7 required files" {
  for name in catppuccin dracula everforest gruvbox kanagawa matte-black nord one-dark osaka-jade ristretto rose-pine solarized tokyo-night; do
    for f in neovim.lua zellij.kdl btop.theme vscode.sh windows-terminal-scheme.json starship.toml starship-plain.toml; do
      [ -f "$REPO_ROOT/themes/$name/$f" ] || { echo "missing themes/$name/$f"; return 1; }
    done
  done
}

@test "every windows-terminal-scheme.json is valid JSON with all required keys" {
  command -v jq &>/dev/null || skip "jq not installed on this test host"
  for name in catppuccin dracula everforest gruvbox kanagawa matte-black nord one-dark osaka-jade ristretto rose-pine solarized tokyo-night; do
    local f="$REPO_ROOT/themes/$name/windows-terminal-scheme.json"
    run jq -e '.name and .background and .foreground and .cursorColor and .selectionBackground and .black and .red and .green and .yellow and .blue and .purple and .cyan and .white and .brightBlack and .brightRed and .brightGreen and .brightYellow and .brightBlue and .brightPurple and .brightCyan and .brightWhite' "$f"
    [ "$status" -eq 0 ]
  done
}

@test "catppuccin windows-terminal-scheme.json matches the researched alacritty hex values" {
  command -v jq &>/dev/null || skip "jq not installed on this test host"
  local f="$REPO_ROOT/themes/catppuccin/windows-terminal-scheme.json"
  [[ "$(jq -r .background "$f")" == "#24273a" ]]
  [[ "$(jq -r .foreground "$f")" == "#cad3f5" ]]
  [[ "$(jq -r .purple "$f")" == "#f5bde6" ]]
}

@test "gruvbox windows-terminal-scheme.json converts 0x-prefixed hex to #-prefixed" {
  command -v jq &>/dev/null || skip "jq not installed on this test host"
  local f="$REPO_ROOT/themes/gruvbox/windows-terminal-scheme.json"
  [[ "$(jq -r .background "$f")" == "#282828" ]]
  [[ "$(jq -r .red "$f")" == "#ea6962" ]]
}

@test "catppuccin vscode.sh calls the shared helper with the right theme and extension" {
  grep -q 'omawsl_theme_apply_vscode "Catppuccin Macchiato" "Catppuccin.catppuccin-vsc"' "$REPO_ROOT/themes/catppuccin/vscode.sh"
}

@test "tokyo-night starship.toml palette matches its zellij.kdl hex values" {
  local f="$REPO_ROOT/themes/tokyo-night/starship.toml"
  grep -q 'red = "#F93357"' "$f"
  grep -q 'green = "#9ECE6A"' "$f"
  grep -q 'blue = "#7AA2F7"' "$f"
}

@test "new themes' starship palettes match their windows-terminal backgrounds" {
  grep -q 'bg = "#282A36"' "$REPO_ROOT/themes/dracula/starship.toml"
  grep -q 'bg = "#282C34"' "$REPO_ROOT/themes/one-dark/starship.toml"
  grep -q 'bg = "#002B36"' "$REPO_ROOT/themes/solarized/starship.toml"
  command -v jq &>/dev/null || skip "jq not installed on this test host"
  [ "$(jq -r .background "$REPO_ROOT/themes/dracula/windows-terminal-scheme.json")" = "#282A36" ]
  [ "$(jq -r .background "$REPO_ROOT/themes/one-dark/windows-terminal-scheme.json")" = "#282C34" ]
  [ "$(jq -r .background "$REPO_ROOT/themes/solarized/windows-terminal-scheme.json")" = "#002B36" ]
}
