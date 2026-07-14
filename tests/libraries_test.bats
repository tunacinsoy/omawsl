#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  stub_command sudo
}

@test "installs the full Omakub-parity native-build/library set" {
  run bash "$REPO_ROOT/install/terminal/libraries.sh"
  [ "$status" -eq 0 ]
  local calls; calls="$(stub_calls)"
  [[ "$calls" == *"build-essential"* ]]
  [[ "$calls" == *"pkg-config autoconf bison clang rustc pipx"* ]]
  [[ "$calls" == *"libssl-dev"* ]]
  [[ "$calls" == *"libvips imagemagick"* ]]
  [[ "$calls" == *"libsqlite3-dev"* ]]
  [[ "$calls" == *"libmysqlclient-dev libpq-dev"* ]]
  [[ "$calls" == *"postgresql-client-common"* ]]
}
