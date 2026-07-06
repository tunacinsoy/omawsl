#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  gum_stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  stub_command git
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/install/terminal/identification.sh"
}

@test "sets git config and persists both values" {
  gum_stub_respond "Ada Lovelace"
  gum_stub_respond "ada@example.com"

  omawsl_identification

  [ "$OMAWSL_USER_NAME" = "Ada Lovelace" ]
  [ "$OMAWSL_USER_EMAIL" = "ada@example.com" ]
  [[ "$(stub_calls)" == *"git config --global user.name Ada Lovelace"* ]]
  [[ "$(stub_calls)" == *"git config --global user.email ada@example.com"* ]]

  run omawsl_load_choice OMAWSL_USER_NAME
  [ "$output" = "Ada Lovelace" ]
  run omawsl_load_choice OMAWSL_USER_EMAIL
  [ "$output" = "ada@example.com" ]
}
