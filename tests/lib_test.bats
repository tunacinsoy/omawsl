#!/usr/bin/env bats

load 'helpers/stubs'

@test "stub_command logs an invocation and returns the requested exit code" {
  stub_init
  stub_command sudo 1
  run sudo apt-get update
  [ "$status" -eq 1 ]
  [[ "$(stub_calls)" == *"sudo apt-get update"* ]]
}

@test "gum stub returns queued responses in order" {
  gum_stub_init
  gum_stub_respond "first"
  gum_stub_respond "second"
  [ "$(gum choose)" = "first" ]
  [ "$(gum choose)" = "second" ]
}
