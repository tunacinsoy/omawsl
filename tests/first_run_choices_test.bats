#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  gum_stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/install/first-run-choices.sh"
}

@test "persists all seven choices and exports them for the current run" {
  gum_stub_respond "Personal / unrestricted"
  gum_stub_respond "Docker Engine only, inside WSL (recommended)"
  gum_stub_respond $'VS Code\nNeovim'
  gum_stub_respond $'Go\nRust'
  gum_stub_respond $'Azure CLI\nAWS CLI'
  gum_stub_respond "PostgreSQL"
  gum_stub_respond "Nerd Font (enhanced)"

  omawsl_first_run_choices

  [ "$OMAWSL_NETWORK_MODE" = "Personal / unrestricted" ]
  [ "$OMAWSL_DOCKER_MODE" = "Docker Engine only, inside WSL (recommended)" ]
  [ "$OMAWSL_EDITORS" = "VS Code,Neovim" ]
  [ "$OMAWSL_LANGUAGES" = "Go,Rust" ]
  [ "$OMAWSL_CLOUD_CLIS" = "Azure CLI,AWS CLI" ]
  [ "$OMAWSL_STORAGE" = "PostgreSQL" ]
  [ "$OMAWSL_FONT_MODE" = "Nerd Font (enhanced)" ]

  run omawsl_load_choice OMAWSL_LANGUAGES
  [ "$output" = "Go,Rust" ]
  run omawsl_load_choice OMAWSL_CLOUD_CLIS
  [ "$output" = "Azure CLI,AWS CLI" ]
  run omawsl_load_choice OMAWSL_STORAGE
  [ "$output" = "PostgreSQL" ]
  run omawsl_load_choice OMAWSL_FONT_MODE
  [ "$output" = "Nerd Font (enhanced)" ]
}

@test "selecting nothing in a multi-select persists an empty string, not an error" {
  gum_stub_respond "Corporate / restricted network"
  gum_stub_respond "Docker Desktop for Windows"
  gum_stub_respond ""
  gum_stub_respond ""
  gum_stub_respond ""
  gum_stub_respond ""
  gum_stub_respond "Cascadia Mono (zero install)"

  run omawsl_first_run_choices
  [ "$status" -eq 0 ]

  omawsl_first_run_choices
  [ "$OMAWSL_EDITORS" = "" ]
  [ "$OMAWSL_LANGUAGES" = "" ]
  [ "$OMAWSL_CLOUD_CLIS" = "" ]
  [ "$OMAWSL_STORAGE" = "" ]
}
