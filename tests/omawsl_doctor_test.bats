#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/bin/omawsl-sub/items.sh"
  source "$REPO_ROOT/bin/omawsl-sub/doctor.sh"
  stub_command sudo
}

@test "omawsl_doctor reports OK for an installed, configured language" {
  omawsl_save_choice OMAWSL_LANGUAGES "Go"
  mise() {
    [[ "$1 $2" == "ls --current" ]] && echo "go      1.26.4  ~/.config/mise/config.toml  latest"
  }
  export -f mise
  run omawsl_doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"[OK]      Go"* ]]
}

@test "omawsl_doctor reports PENDING with the exact install command for a selected-but-missing item" {
  omawsl_save_choice OMAWSL_LANGUAGES "Rust"
  stub_hide_command mise
  run omawsl_doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"[PENDING] Rust - run: omawsl install language rust"* ]]
}

@test "omawsl_doctor skips categories where nothing was selected" {
  run omawsl_doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"none selected"* ]]
}

@test "omawsl_doctor flags a still-unreachable Docker Desktop selection" {
  omawsl_save_choice OMAWSL_DOCKER_MODE "Docker Desktop for Windows"
  stub_hide_command docker
  run omawsl_doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"Docker Desktop for Windows"* ]]
}
