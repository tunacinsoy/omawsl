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
