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
