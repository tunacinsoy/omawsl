#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/install/terminal/app-antigravity-cli.sh"
  stub_command curl
}

@test "no-ops entirely when Antigravity CLI isn't selected" {
  export OMAWSL_EDITORS=""
  run omawsl_install_antigravity_cli
  [ "$status" -eq 0 ]
  [ -z "$(stub_calls)" ]
}

@test "installs via the official installer when not already present" {
  export OMAWSL_EDITORS="Antigravity CLI"
  stub_hide_command agy
  run omawsl_install_antigravity_cli
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"curl -fsSL https://antigravity.google/cli/install.sh"* ]]
}

@test "no-ops when already installed" {
  export OMAWSL_EDITORS="Antigravity CLI"
  stub_command agy
  run omawsl_install_antigravity_cli
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"curl"* ]]
}

@test "omawsl_antigravity_cli_install_steps runs unconditionally, even if agy is already installed" {
  stub_command agy
  run omawsl_antigravity_cli_install_steps
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"antigravity.google/cli/install.sh"* ]]
}
