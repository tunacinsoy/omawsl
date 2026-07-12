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
  stub_command mise
  stub_command gem
  stub_hide_command docker terraform az code cursor claude codex gemini opencode
}

@test "omawsl install language go - installs go directly and merges it into OMAWSL_LANGUAGES" {
  omawsl_save_choice OMAWSL_LANGUAGES "Rust"
  run omawsl_install_command language go
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"mise use --global go@latest"* ]]
  [[ "$(omawsl_load_choice OMAWSL_LANGUAGES)" == "Rust,Go" ]]
}

@test "omawsl install editor vscode - installs vscode directly and merges it into OMAWSL_EDITORS" {
  run omawsl_install_command editor vscode
  [ "$status" -eq 0 ]
  [[ "$(omawsl_load_choice OMAWSL_EDITORS)" == "VS Code" ]]
}

@test "omawsl install storage mysql - installs mysql directly" {
  stub_hide_command docker
  run omawsl_install_command storage mysql
  [ "$status" -eq 0 ]
  [[ "$(omawsl_load_choice OMAWSL_STORAGE)" == "MySQL" ]]
}

@test "omawsl install rejects an item that doesn't belong to the given category" {
  run omawsl_install_command editor go
  [ "$status" -ne 0 ]
  [[ "$output" == *"isn't in the 'editor' category"* ]]
}

@test "omawsl install rejects an unknown item" {
  run omawsl_install_command language not-a-real-item
  [ "$status" -ne 0 ]
}

@test "omawsl install with a category but no item prints usage" {
  run omawsl_install_command language
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage: omawsl install"* ]]
}

@test "omawsl install with no args runs the interactive category picker, pre-checking existing choices" {
  omawsl_save_choice OMAWSL_LANGUAGES "Go"
  # Custom override, not the shared gum_stub_respond queue: both
  # omawsl_install_interactive's category picker and
  # omawsl_install_prompt_multi's item picker pass their options as plain
  # arguments (never piped into gum), unlike theme.sh's `... | gum choose`
  # pattern - so no stdin draining is needed here, just two distinct
  # responses keyed off which prompt is being asked.
  gum() {
    echo "gum $*" >> "$STUB_LOG"
    if [[ "$*" == *"What do you want to add"* ]]; then
      echo "Language/tool"
    else
      echo "Go
Python"
    fi
  }
  export -f gum
  run omawsl_install_command
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"--selected Go"* ]]
  [[ "$(omawsl_load_choice OMAWSL_LANGUAGES)" == "Go,Python" ]]
}

@test "omawsl install with no args returns cleanly when the category picker is cancelled" {
  gum() { echo "gum $*" >> "$STUB_LOG"; return 1; }
  export -f gum
  BATS_RUN_ERREXIT=1 run omawsl_install_command
  [ "$status" -eq 0 ]
}
