#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/install/terminal/app-codex-cli.sh"
  stub_command mise
}

@test "no-ops entirely when Codex CLI isn't selected" {
  export OMAWSL_EDITORS=""
  run omawsl_install_codex_cli
  [ "$status" -eq 0 ]
  [ -z "$(stub_calls)" ]
  [ ! -f "$HOME/.local/bin/codex" ]
}

@test "installs via a private mise-managed Node and writes a wrapper" {
  export OMAWSL_EDITORS="Codex CLI"
  stub_hide_command codex
  run omawsl_install_codex_cli
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"mise exec node@lts -- npm install -g @openai/codex"* ]]
  [ -x "$HOME/.local/bin/codex" ]
  [[ "$(cat "$HOME/.local/bin/codex")" == *"exec mise exec node@lts -- codex"* ]]
}

@test "no-ops when already installed" {
  export OMAWSL_EDITORS="Codex CLI"
  stub_command codex
  run omawsl_install_codex_cli
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"npm install"* ]]
}

@test "omawsl_codex_cli_install_steps runs unconditionally and (re)writes the wrapper" {
  stub_command codex
  rm -f "$HOME/.local/bin/codex"
  run omawsl_codex_cli_install_steps
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"mise exec node@lts -- npm install -g @openai/codex"* ]]
  [ -x "$HOME/.local/bin/codex" ]
}
