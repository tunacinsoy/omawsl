#!/usr/bin/env bats

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

@test "windows-terminal.json and windows-terminal-fallback.json are both valid JSON" {
  command -v jq &>/dev/null || skip "jq not installed on this test host"
  for f in windows-terminal.json windows-terminal-fallback.json; do
    run jq empty "$REPO_ROOT/windows/$f"
    [ "$status" -eq 0 ]
  done
}

@test "windows-terminal.json uses the Nerd Font Mono family name" {
  command -v jq &>/dev/null || skip "jq not installed on this test host"
  [[ "$(jq -r '.profiles.defaults.font.face' "$REPO_ROOT/windows/windows-terminal.json")" == "CaskaydiaMono Nerd Font Mono" ]]
}

@test "windows-terminal-fallback.json uses the bundled Cascadia Mono family name" {
  command -v jq &>/dev/null || skip "jq not installed on this test host"
  [[ "$(jq -r '.profiles.defaults.font.face' "$REPO_ROOT/windows/windows-terminal-fallback.json")" == "Cascadia Mono" ]]
}

@test "both windows-terminal json fragments unbind all four Alt+arrow chords identically" {
  command -v jq &>/dev/null || skip "jq not installed on this test host"
  for f in windows-terminal.json windows-terminal-fallback.json; do
    local keys
    keys="$(jq -r '[.actions[] | select(.command == "unbound") | .keys] | sort | join(",")' "$REPO_ROOT/windows/$f")"
    [[ "$keys" == "alt+down,alt+left,alt+right,alt+up" ]]
  done
}

@test "windows/fonts/README.md points at the real upstream nerd-fonts release URL" {
  grep -q "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/CascadiaMono.zip" "$REPO_ROOT/windows/fonts/README.md"
}

@test "windows/fonts/ has no vendored font binaries" {
  ! find "$REPO_ROOT/windows/fonts" -iname "*.ttf" -o -iname "*.otf" | grep -q .
}

@test "windows/setup.ps1 is never sourced or invoked by any .sh file in the repo" {
  ! grep -rl "setup\.ps1" "$REPO_ROOT" --include="*.sh" | grep -q .
}
