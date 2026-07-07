#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  source "$REPO_ROOT/install/terminal/mise.sh"
  stub_command curl
}

@test "installs mise via the official installer when not already present" {
  run omawsl_install_mise
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"curl -fsSL https://mise.run"* ]]
}

@test "no-ops when mise is already on PATH" {
  stub_command mise
  run omawsl_install_mise
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"curl"* ]]
}

@test "adds \$HOME/.local/bin to PATH for the current session" {
  omawsl_install_mise
  [[ ":$PATH:" == *":$HOME/.local/bin:"* ]]
}
