#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  source "$REPO_ROOT/install/lib.sh"
}

@test "omawsl_version_ge: greater major version" {
  run omawsl_version_ge "26.04" "24.04"
  [ "$status" -eq 0 ]
}

@test "omawsl_version_ge: equal version" {
  run omawsl_version_ge "24.04" "24.04"
  [ "$status" -eq 0 ]
}

@test "omawsl_version_ge: greater minor, same major" {
  run omawsl_version_ge "24.10" "24.04"
  [ "$status" -eq 0 ]
}

@test "omawsl_version_ge: lesser major version" {
  run omawsl_version_ge "22.04" "24.04"
  [ "$status" -eq 1 ]
}

@test "omawsl_version_ge: lesser minor, same major" {
  run omawsl_version_ge "24.02" "24.04"
  [ "$status" -eq 1 ]
}

@test "omawsl_list_has: item present" {
  run omawsl_list_has "Go,Python,Rust" "Go"
  [ "$status" -eq 0 ]
}

@test "omawsl_list_has: item absent" {
  run omawsl_list_has "Go,Python,Rust" "Java"
  [ "$status" -eq 1 ]
}

@test "omawsl_list_has: does not match as a bare substring" {
  run omawsl_list_has "GoLang,Python" "Go"
  [ "$status" -eq 1 ]
}

@test "omawsl_list_has: empty list never matches" {
  run omawsl_list_has "" "Go"
  [ "$status" -eq 1 ]
}

@test "omawsl_is_wsl2_kernel: real WSL2 kernel string matches" {
  run omawsl_is_wsl2_kernel "6.18.33.2-microsoft-standard-WSL2"
  [ "$status" -eq 0 ]
}

@test "omawsl_is_wsl2_kernel: WSL1-style kernel string does not match" {
  run omawsl_is_wsl2_kernel "4.4.0-19041-Microsoft"
  [ "$status" -eq 1 ]
}

@test "omawsl_is_wsl2_kernel: bare Linux kernel string does not match" {
  run omawsl_is_wsl2_kernel "5.4.0-91-generic"
  [ "$status" -eq 1 ]
}

@test "omawsl_save_choice + omawsl_load_choice: round-trips a value" {
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  omawsl_save_choice OMAWSL_LANGUAGES "Go,Python"
  run omawsl_load_choice OMAWSL_LANGUAGES
  [ "$status" -eq 0 ]
  [ "$output" = "Go,Python" ]
}

@test "omawsl_save_choice: overwrites a prior value for the same key" {
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  omawsl_save_choice OMAWSL_LANGUAGES "Go"
  omawsl_save_choice OMAWSL_LANGUAGES "Go,Rust"
  run omawsl_load_choice OMAWSL_LANGUAGES
  [ "$output" = "Go,Rust" ]
  [ "$(grep -c '^OMAWSL_LANGUAGES=' "$OMAWSL_STATE_DIR/choices.env")" -eq 1 ]
}

@test "omawsl_save_choice: two different keys are both loadable independently" {
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  omawsl_save_choice OMAWSL_LANGUAGES "Go"
  omawsl_save_choice OMAWSL_STORAGE "MySQL"
  run omawsl_load_choice OMAWSL_LANGUAGES
  [ "$output" = "Go" ]
  run omawsl_load_choice OMAWSL_STORAGE
  [ "$output" = "MySQL" ]
}

@test "omawsl_load_choice: unset key returns empty string" {
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  run omawsl_load_choice OMAWSL_NEVER_SET
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}
