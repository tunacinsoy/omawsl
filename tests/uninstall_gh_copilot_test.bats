#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/uninstall/app-gh-copilot.sh"
}

@test "omawsl_uninstall_gh_copilot uninstalls the npm package and removes the wrapper" {
  stub_command mise
  stub_command gh
  mkdir -p "$HOME/.local/bin"
  touch "$HOME/.local/bin/copilot"
  run omawsl_uninstall_gh_copilot
  [ "$status" -eq 0 ]
  [ ! -f "$HOME/.local/bin/copilot" ]
  [[ "$(stub_calls)" == *"mise exec node@lts -- npm uninstall -g @github/copilot"* ]]
}

@test "omawsl_uninstall_gh_copilot no-ops the npm step cleanly when mise isn't reachable" {
  stub_hide_command mise
  stub_command gh
  mkdir -p "$HOME/.local/bin"
  touch "$HOME/.local/bin/copilot"
  run omawsl_uninstall_gh_copilot
  [ "$status" -eq 0 ]
  [ ! -f "$HOME/.local/bin/copilot" ]
}

@test "omawsl_uninstall_gh_copilot also removes the old gh-copilot extension when present" {
  stub_command mise
  gh() {
    if [[ "$1 $2" == "extension list" ]]; then
      echo "gh copilot	github/gh-copilot	v1.2.0"
    fi
    echo "gh $*" >> "$STUB_LOG"
  }
  export -f gh
  run omawsl_uninstall_gh_copilot
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"gh extension remove gh-copilot"* ]]
}

@test "omawsl_uninstall_gh_copilot no-ops the extension removal when it was never installed" {
  stub_command mise
  gh() { echo "gh $*" >> "$STUB_LOG"; }
  export -f gh
  run omawsl_uninstall_gh_copilot
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"remove"* ]]
  [[ "$output" == *"GitHub Copilot CLI"* ]]
}

@test "omawsl_uninstall_gh_copilot removes GitHub Copilot CLI from the persisted OMAWSL_EDITORS list" {
  stub_command mise
  stub_command gh
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  omawsl_save_choice OMAWSL_EDITORS "VS Code,GitHub Copilot CLI,Neovim"
  run omawsl_uninstall_gh_copilot
  [ "$status" -eq 0 ]
  [[ "$(omawsl_load_choice OMAWSL_EDITORS)" == "VS Code,Neovim" ]]
}

@test "omawsl_uninstall_gh_copilot leaves OMAWSL_EDITORS alone when Copilot was never in it" {
  stub_command mise
  stub_command gh
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  omawsl_save_choice OMAWSL_EDITORS "VS Code,Neovim"
  run omawsl_uninstall_gh_copilot
  [ "$status" -eq 0 ]
  [[ "$(omawsl_load_choice OMAWSL_EDITORS)" == "VS Code,Neovim" ]]
}

@test "omawsl_uninstall_gh_copilot still clears the persisted OMAWSL_EDITORS entry when gh extension remove fails" {
  # Invoked via a fresh `bash -c` (not a sourced function call captured by
  # bats' `run`, which runs inside a $(...) command substitution and so
  # does not inherit errexit by default) to match how
  # bin/omawsl-sub/uninstall.sh really calls this: source the script, then
  # call the function directly under `set -euo pipefail` in the same
  # process, where an unguarded failing command genuinely aborts the
  # function.
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  omawsl_save_choice OMAWSL_EDITORS "VS Code,GitHub Copilot CLI,Neovim"

  run bash -c '
    set -euo pipefail
    mise() { return 0; }
    export -f mise
    gh() {
      case "$1 $2" in
        "extension list") echo "gh copilot	github/gh-copilot	v1.2.0" ;;
        "extension remove") return 1 ;;
      esac
      return 0
    }
    export -f gh
    source "'"$REPO_ROOT"'/install/lib.sh"
    source "'"$REPO_ROOT"'/uninstall/app-gh-copilot.sh"
    omawsl_uninstall_gh_copilot
  '
  [ "$status" -eq 0 ]
  [[ "$(omawsl_load_choice OMAWSL_EDITORS)" == "VS Code,Neovim" ]]
}
