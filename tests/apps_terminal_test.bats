#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  stub_command sudo
}

@test "installs the full Omakub-parity terminal tool set" {
  run bash "$REPO_ROOT/install/terminal/apps-terminal.sh"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"sudo apt-get install -y fzf ripgrep bat eza zoxide plocate apache2-utils fd-find"* ]]
}
