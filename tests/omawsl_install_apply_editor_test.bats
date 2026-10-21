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
  stub_hide_command docker terraform az gcloud aws code cursor claude codex agy opencode copilot cmd.exe
  # VS Code's installer resolves the Windows profile through cmd.exe, and
  # omawsl_resolve_cmd_exe falls back to the real /mnt/c path even when
  # cmd.exe is hidden from PATH - point the fallback nowhere so no test
  # here can touch the real Windows-side VS Code settings.
  export OMAWSL_CMD_EXE_FALLBACK="$BATS_TEST_TMPDIR/no-such-cmd.exe"
}

@test "installing one editor does not re-run installers for editors picked earlier" {
  # Issue #16: `omawsl install editor gh-copilot` re-ran VS Code's install
  # step (its `code --install-extension` call then installed the VS Code Server)
  # just because VS Code was already in the saved list.
  stub_command mise
  omawsl_save_choice OMAWSL_EDITORS "VS Code"
  run omawsl_install_apply_editor "GitHub Copilot CLI" "VS Code"
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.vscode-server/data/Machine/settings.json" ]
  [[ "$output" != *"VS Code"* ]]
  [[ "$(stub_calls)" == *"mise exec node@lts -- npm install -g @github/copilot"* ]]
  # The saved list still keeps both.
  [[ "$(omawsl_load_choice OMAWSL_EDITORS)" == "VS Code,GitHub Copilot CLI" ]]
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
