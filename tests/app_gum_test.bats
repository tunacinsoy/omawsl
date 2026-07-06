#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  stub_command sudo
}

@test "installs gum via apt-get" {
  run bash "$REPO_ROOT/install/terminal/required/app-gum.sh"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"sudo apt-get install -y gum"* ]]
}

@test "refreshes the apt cache before installing" {
  run bash "$REPO_ROOT/install/terminal/required/app-gum.sh"
  [[ "$(stub_calls)" == *"sudo apt-get update -qq"* ]]
}
