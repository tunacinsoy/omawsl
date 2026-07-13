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

@test "omawsl_uninstall_gh_copilot removes the extension when installed" {
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

@test "omawsl_uninstall_gh_copilot no-ops cleanly when it was never installed" {
  gh() { echo "gh $*" >> "$STUB_LOG"; }
  export -f gh
  run omawsl_uninstall_gh_copilot
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"remove"* ]]
  [[ "$output" == *"GitHub Copilot CLI"* ]]
}
