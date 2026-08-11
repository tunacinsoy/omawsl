#!/usr/bin/env bats

load 'helpers/stubs'

@test "stub_command logs an invocation and returns the requested exit code" {
  stub_init
  stub_command sudo 1
  run sudo apt-get update
  [ "$status" -eq 1 ]
  [[ "$(stub_calls)" == *"sudo apt-get update"* ]]
}

@test "stub_command's exported function survives a real subprocess boundary, not just bats' internal fork" {
  stub_init
  stub_command sudo
  run bash -c 'sudo apt-get update'
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"sudo apt-get update"* ]]
}

@test "gum stub returns queued responses in order" {
  gum_stub_init
  gum_stub_respond "first"
  gum_stub_respond "second"
  [ "$(gum choose)" = "first" ]
  [ "$(gum choose)" = "second" ]
}

# Regression coverage for issue #13: stub_init/gum_stub_init/stub_hide_command
# used to call bare `mktemp`/`mktemp -d`, which land in system tmp completely
# outside bats' own $BATS_RUN_TMPDIR (cleaned up in one shot by bats' EXIT
# trap). That made every one of these directories permanent, unmanaged
# debris - most severely stub_hide_command's PATH shadow dir, which symlinks
# nearly every binary on the system (1000+ inodes) and is called ~90+ times
# across the suite, eventually exhausting tmpfs inodes. Scoping them under
# $BATS_TEST_TMPDIR ties their lifetime to bats' own cleanup instead.
@test "stub_init scopes its temp files under BATS_TEST_TMPDIR instead of leaking to system tmp" {
  stub_init
  [[ "$STUB_LOG" == "$BATS_TEST_TMPDIR"/* ]]
  [[ "$STUB_OUTPUT_REGISTRY_ROOT" == "$BATS_TEST_TMPDIR"/* ]]
}

@test "gum_stub_init scopes its response dir under BATS_TEST_TMPDIR instead of leaking to system tmp" {
  gum_stub_init
  [[ "$GUM_RESPONSE_DIR" == "$BATS_TEST_TMPDIR"/* ]]
}

@test "stub_hide_command scopes its shadow PATH dir under BATS_TEST_TMPDIR instead of leaking to system tmp" {
  stub_hide_command docker
  [[ "$PATH" == "$BATS_TEST_TMPDIR"/* ]]
}
