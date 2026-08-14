#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  gum_stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/bin/omawsl-sub/items.sh"
  source "$REPO_ROOT/bin/omawsl-sub/install.sh"
  stub_command sudo
  stub_command git
  stub_hide_command docker terraform az gcloud aws code cursor claude codex agy opencode copilot herdr
}

@test "one editor's failed npm install does not abort the rest of the editor chain" {
  # Both Neovim (tree-sitter-cli) and GitHub Copilot CLI go through
  # `mise exec node@lts -- npm install -g ...`; stubbing mise to fail
  # simulates a flaky npm registry. Before the isolation fix, the first
  # failure (Neovim) would abort omawsl_install_apply_editor under
  # set -euo pipefail and Copilot CLI's install would never even run.
  stub_command mise 1
  run omawsl_install_apply_editor "Neovim,GitHub Copilot CLI" ""
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"mise exec node@lts -- npm install -g tree-sitter-cli"* ]]
  [[ "$(stub_calls)" == *"mise exec node@lts -- npm install -g @github/copilot"* ]]
  [[ "$output" == *"failed to install Neovim - skipping, continuing with the rest."* ]]
  [[ "$output" == *"failed to install GitHub Copilot CLI - skipping, continuing with the rest."* ]]
  # Picked editors are still persisted even though both installs failed -
  # matches every other _apply_* function's "save first" ordering.
  [[ "$(omawsl_load_choice OMAWSL_EDITORS)" == "Neovim,GitHub Copilot CLI" ]]
}

@test "all editors still install normally when nothing fails" {
  stub_command mise
  run omawsl_install_apply_editor "Neovim,GitHub Copilot CLI" ""
  [ "$status" -eq 0 ]
  [[ "$output" != *"failed to install"* ]]
  [[ "$(stub_calls)" == *"mise exec node@lts -- npm install -g tree-sitter-cli"* ]]
  [[ "$(stub_calls)" == *"mise exec node@lts -- npm install -g @github/copilot"* ]]
}
