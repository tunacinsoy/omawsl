#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/install/terminal/app-gh-copilot.sh"
  stub_command gh
}

@test "no-ops entirely when GitHub Copilot CLI isn't selected" {
  export OMAWSL_EDITORS=""
  run omawsl_install_gh_copilot
  [ "$status" -eq 0 ]
  [ -z "$(stub_calls)" ]
}

@test "installs the gh-copilot extension when selected" {
  export OMAWSL_EDITORS="GitHub Copilot CLI"
  run omawsl_install_gh_copilot
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"gh extension install github/gh-copilot"* ]]
}

@test "skips a redundant install when the gh-copilot extension is already present" {
  export OMAWSL_EDITORS="GitHub Copilot CLI"
  gh() {
    echo "gh $*" >> "$STUB_LOG"
    if [[ "$1" == "extension" && "$2" == "list" ]]; then
      echo "gh-copilot	github/gh-copilot	v1.2.3"
    fi
  }
  export -f gh
  run omawsl_install_gh_copilot
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"gh extension install"* ]]
}

@test "isolates an install failure (e.g. gh not authenticated yet) instead of aborting the run" {
  export OMAWSL_EDITORS="GitHub Copilot CLI"
  gh() {
    echo "gh $*" >> "$STUB_LOG"
    if [[ "$1" == "extension" && "$2" == "install" ]]; then
      return 1
    fi
  }
  export -f gh
  run omawsl_install_gh_copilot
  [ "$status" -eq 0 ]
  [[ "$output" == *"GitHub Copilot CLI install failed"* ]]
  [[ "$output" == *"docs/windows-setup.md#github-copilot-cli"* ]]
}
