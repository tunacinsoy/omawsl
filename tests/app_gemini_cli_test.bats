#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/install/terminal/app-gemini-cli.sh"
  stub_command mise
}

@test "no-ops entirely when Gemini CLI isn't selected" {
  export OMAWSL_EDITORS=""
  run omawsl_install_gemini_cli
  [ "$status" -eq 0 ]
  [ -z "$(stub_calls)" ]
  [ ! -f "$HOME/.local/bin/gemini" ]
}

@test "installs via a private mise-managed Node and writes a wrapper" {
  export OMAWSL_EDITORS="Gemini CLI"
  stub_hide_command gemini
  run omawsl_install_gemini_cli
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"mise exec node@lts -- npm install -g @google/gemini-cli"* ]]
  [ -x "$HOME/.local/bin/gemini" ]
  [[ "$(cat "$HOME/.local/bin/gemini")" == *"exec mise exec node@lts -- gemini"* ]]
}

@test "no-ops when already installed" {
  export OMAWSL_EDITORS="Gemini CLI"
  stub_command gemini
  run omawsl_install_gemini_cli
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"npm install"* ]]
}

@test "omawsl_gemini_cli_install_steps runs unconditionally and (re)writes the wrapper" {
  stub_command gemini
  rm -f "$HOME/.local/bin/gemini"
  run omawsl_gemini_cli_install_steps
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"mise exec node@lts -- npm install -g @google/gemini-cli"* ]]
  [ -x "$HOME/.local/bin/gemini" ]
}
