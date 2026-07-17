#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # Isolate HOME: omawsl_install_mise exports $HOME/.local/bin onto PATH
  # itself, and this WSL instance has a real mise binary genuinely
  # installed under the real user's ~/.local/bin (from a real Task 6
  # verification run) - without this, "not already present" tests would
  # find that real binary and skip the very install path they're testing.
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/terminal/mise.sh"
  stub_command curl
  # Isolating $HOME above isn't enough on its own: omawsl_install_mise's
  # `command -v mise` check runs against the *inherited* $PATH, which
  # already contains this WSL instance's real mise install dir regardless
  # of $HOME - same class of gap already fixed for terraform/az in
  # cloud_tools_test.bats. Hide the real binary so "not already present"
  # tests actually exercise the install path instead of short-circuiting.
  stub_hide_command mise
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
