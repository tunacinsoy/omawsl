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

themes() {
  find "$REPO_ROOT/themes" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort
}

@test "every theme has a VS Code palette with a value for every slot in Omarchy's template" {
  local tokens t tok
  tokens="$(grep -oE '\{\{[^}]*\}\}' "$REPO_ROOT/themes/vscode-theme.json.tpl" | sed -E 's/^\{\{ *//; s/ *\}\}$//' | sort -u)"
  [ -n "$tokens" ]
  for t in $(themes); do
    while IFS= read -r tok; do
      jq -e --arg k "$tok" '.[$k] | test("^(#[0-9a-f]{6}|dark|light)$")' "$REPO_ROOT/themes/$t/vscode-palette.json" >/dev/null ||
        { echo "$t: no value for '$tok'"; return 1; }
    done <<< "$tokens"
  done
}

@test "every theme renders to valid VS Code theme JSON with nothing left unfilled" {
  local t out
  for t in $(themes); do
    out="$(omawsl_vscode_theme_render "$REPO_ROOT/themes/$t/vscode-palette.json")" || { echo "$t: render failed"; return 1; }
    [[ "$out" != *"{{"* ]] || { echo "$t: unfilled slot"; return 1; }
    jq -e '.colors["editor.background"] and (.tokenColors | length > 0) and (.semanticTokenColors | length > 0)' <<< "$out" >/dev/null ||
      { echo "$t: not a theme"; return 1; }
  done
}

@test "VS Code gets the same background and text color as Windows Terminal, for every theme" {
  local t scheme palette
  for t in $(themes); do
    scheme="$REPO_ROOT/themes/$t/windows-terminal-scheme.json"
    palette="$REPO_ROOT/themes/$t/vscode-palette.json"
    [ "$(jq -r '.background | ascii_downcase' "$scheme")" = "$(jq -r .background "$palette")" ] || { echo "$t: background"; return 1; }
    [ "$(jq -r '.foreground | ascii_downcase' "$scheme")" = "$(jq -r .foreground "$palette")" ] || { echo "$t: foreground"; return 1; }
  done
}

@test "a light theme is marked light, so VS Code gets a light base theme" {
  [ "$(jq -r .theme_type "$REPO_ROOT/themes/rose-pine/vscode-palette.json")" = light ]
  [ "$(omawsl_vscode_theme_render "$REPO_ROOT/themes/rose-pine/vscode-palette.json" | jq -r .type)" = light ]
}
