#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/install/terminal/app-opencode.sh"
  stub_command curl
}

@test "no-ops entirely when opencode isn't selected" {
  export OMAWSL_EDITORS=""
  run omawsl_install_opencode
  [ "$status" -eq 0 ]
  [ -z "$(stub_calls)" ]
}

@test "installs via the official installer when not already present" {
  export OMAWSL_EDITORS="opencode"
  stub_hide_command opencode
  run omawsl_install_opencode
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"curl -fsSL https://opencode.ai/install"* ]]
}

@test "no-ops when already installed" {
  export OMAWSL_EDITORS="opencode"
  stub_command opencode
  run omawsl_install_opencode
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"curl"* ]]
}

@test "omawsl_opencode_install_steps runs unconditionally, even if opencode is already installed" {
  stub_command opencode
  run omawsl_opencode_install_steps
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"opencode.ai/install"* ]]
}

@test "no-ops when installed but not yet on PATH in the current shell" {
  export OMAWSL_EDITORS="opencode"
  stub_hide_command opencode
  mkdir -p "$HOME/.opencode/bin"
  : > "$HOME/.opencode/bin/opencode"
  chmod +x "$HOME/.opencode/bin/opencode"
  run omawsl_install_opencode
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"curl"* ]]
}
