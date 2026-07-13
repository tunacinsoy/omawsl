#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/install/terminal/app-claude-cli.sh"
  stub_command curl
}

@test "no-ops entirely when Claude Code CLI isn't selected" {
  export OMAWSL_EDITORS=""
  run omawsl_install_claude_cli
  [ "$status" -eq 0 ]
  [ -z "$(stub_calls)" ]
}

@test "installs via the official installer when not already present" {
  export OMAWSL_EDITORS="Claude Code CLI"
  stub_hide_command claude
  run omawsl_install_claude_cli
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"curl -fsSL https://claude.ai/install.sh"* ]]
}

@test "no-ops when already installed" {
  export OMAWSL_EDITORS="Claude Code CLI"
  stub_command claude
  run omawsl_install_claude_cli
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"curl"* ]]
}

@test "omawsl_claude_cli_install_steps runs unconditionally, even if claude is already installed" {
  stub_command claude
  run omawsl_claude_cli_install_steps
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"claude.ai/install.sh"* ]]
}
