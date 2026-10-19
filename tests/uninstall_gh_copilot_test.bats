#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/uninstall/app-gh-copilot.sh"
  # Hides any real `copilot` on this host (a mise shim, a Windows-side
  # copy via /mnt/c interop, ...) so the leftover-on-PATH check below
  # only ever sees what each test puts there itself.
  stub_hide_command copilot
}

@test "omawsl_uninstall_gh_copilot uninstalls the npm package and removes the wrapper" {
  stub_command_output_for mise "ls --installed node" "node  24.18.0"
  stub_command gh
  mkdir -p "$HOME/.local/bin"
  touch "$HOME/.local/bin/copilot"
  run omawsl_uninstall_gh_copilot
  [ "$status" -eq 0 ]
  [ ! -f "$HOME/.local/bin/copilot" ]
  [[ "$(stub_calls)" == *"mise exec node@24.18.0 -- npm uninstall -g @github/copilot"* ]]
}

@test "omawsl_uninstall_gh_copilot uninstalls the npm package from every installed mise Node, not just node@lts" {
  # Issue #16: npm printed "up to date" (nothing to remove) under node@lts
  # while a copilot installed under another Node kept running.
  stub_command_output_for mise "ls --installed node" "node  22.11.0
node  24.18.0"
  stub_command gh
  run omawsl_uninstall_gh_copilot
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"mise exec node@22.11.0 -- npm uninstall -g @github/copilot"* ]]
  [[ "$(stub_calls)" == *"mise exec node@24.18.0 -- npm uninstall -g @github/copilot"* ]]
  [[ "$(stub_calls)" != *"node@lts"* ]]
}

@test "omawsl_uninstall_gh_copilot warns with the path instead of claiming success when another copilot is still on PATH" {
  # Issue #16: a copilot omawsl didn't install (Windows side via /mnt/c,
  # GitHub's install script, ...) survived, but uninstall still said
  # "removed".
  stub_command mise
  stub_command gh
  # A space in the dir, like a Windows "Program Files" path via /mnt/c.
  mkdir -p "$BATS_TEST_TMPDIR/else where"
  printf '#!/bin/sh\n' > "$BATS_TEST_TMPDIR/else where/copilot"
  chmod +x "$BATS_TEST_TMPDIR/else where/copilot"
  export PATH="$BATS_TEST_TMPDIR/else where:$PATH"
  run omawsl_uninstall_gh_copilot
  [ "$status" -eq 0 ]
  [[ "$output" != *"GitHub Copilot CLI removed."* ]]
  [[ "$output" == *"$BATS_TEST_TMPDIR/else where/copilot"* ]]
  # Never deletes a copy omawsl didn't install.
  [ -x "$BATS_TEST_TMPDIR/else where/copilot" ]
}

@test "omawsl_uninstall_gh_copilot reports success when no copilot is left on PATH" {
  stub_command mise
  stub_command gh
  run omawsl_uninstall_gh_copilot
  [ "$status" -eq 0 ]
  [[ "$output" == *"GitHub Copilot CLI removed."* ]]
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

@test "omawsl_uninstall_gh_copilot clears the persisted autopilot choice" {
  stub_command mise
  stub_command gh
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  omawsl_save_choice OMAWSL_COPILOT_AUTOPILOT "Yes - autopilot + allow-all"
  run omawsl_uninstall_gh_copilot
  [ "$status" -eq 0 ]
  run omawsl_load_choice OMAWSL_COPILOT_AUTOPILOT
  [ "$output" = "" ]
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

@test "omawsl_uninstall_gh_copilot still clears persisted state when gh extension remove fails" {
  # Invoked via a fresh `bash -c` (not a sourced function call captured by
  # bats' `run`, which runs inside a $(...) command substitution and so
  # does not inherit errexit by default) to match how
  # bin/omawsl-sub/uninstall.sh really calls this: source the script, then
  # call the function directly under `set -euo pipefail` in the same
  # process, where an unguarded failing command genuinely aborts the
  # function.
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  omawsl_save_choice OMAWSL_COPILOT_AUTOPILOT "Yes - autopilot + allow-all"
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

  run omawsl_load_choice OMAWSL_COPILOT_AUTOPILOT
  [ "$output" = "" ]
  [[ "$(omawsl_load_choice OMAWSL_EDITORS)" == "VS Code,Neovim" ]]
}
