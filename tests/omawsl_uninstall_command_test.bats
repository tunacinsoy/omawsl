#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/bin/omawsl-sub/items.sh"
  source "$REPO_ROOT/bin/omawsl-sub/uninstall.sh"
}

@test "omawsl_item_category classifies every known slug correctly" {
  [[ "$(omawsl_item_category go)" == "language" ]]
  [[ "$(omawsl_item_category terraform)" == "language" ]]
  [[ "$(omawsl_item_category azure)" == "cloud" ]]
  [[ "$(omawsl_item_category aws)" == "cloud" ]]
  [[ "$(omawsl_item_category gcp)" == "cloud" ]]
  [[ "$(omawsl_item_category vscode)" == "editor" ]]
  [[ "$(omawsl_item_category gh-copilot)" == "editor" ]]
  [[ "$(omawsl_item_category mysql)" == "storage" ]]
  [[ "$(omawsl_item_category docker)" == "docker" ]]
  ! omawsl_item_category not-a-real-slug
}

@test "omawsl_item_label maps every slug to its exact picker label" {
  [[ "$(omawsl_item_label ruby)" == "Ruby on Rails" ]]
  [[ "$(omawsl_item_label vscode)" == "VS Code" ]]
  [[ "$(omawsl_item_label gh-copilot)" == "GitHub Copilot CLI" ]]
  [[ "$(omawsl_item_label postgresql)" == "PostgreSQL" ]]
  [[ "$(omawsl_item_label azure)" == "Azure CLI" ]]
  [[ "$(omawsl_item_label aws)" == "AWS CLI" ]]
  [[ "$(omawsl_item_label gcp)" == "GCP CLI" ]]
}

@test "omawsl_item_slugs lists all 9 language slugs, 3 cloud slugs, 8 editor slugs, 3 storage slugs" {
  [[ "$(omawsl_item_slugs language | wc -l)" -eq 9 ]]
  [[ "$(omawsl_item_slugs language)" != *"azure"* ]]
  [[ "$(omawsl_item_slugs cloud | wc -l)" -eq 3 ]]
  [[ "$(omawsl_item_slugs cloud)" == *"azure"* ]]
  [[ "$(omawsl_item_slugs cloud)" == *"aws"* ]]
  [[ "$(omawsl_item_slugs cloud)" == *"gcp"* ]]
  [[ "$(omawsl_item_slugs editor | wc -l)" -eq 8 ]]
  [[ "$(omawsl_item_slugs storage | wc -l)" -eq 3 ]]
}

@test "omawsl_uninstall_command dispatches a language slug to uninstall/dev-language.sh" {
  stub_command sudo
  stub_command mise
  run omawsl_uninstall_command go
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"mise unuse --global go@latest"* ]]
}

@test "omawsl_uninstall_command removes the item from its choices.env list after a successful uninstall" {
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  stub_command sudo
  stub_command mise
  omawsl_save_choice OMAWSL_LANGUAGES "Go,Rust"
  run omawsl_uninstall_command go
  [ "$status" -eq 0 ]
  [[ "$(omawsl_load_choice OMAWSL_LANGUAGES)" == "Rust" ]]
}

@test "omawsl_uninstall_command deselects an editor from OMAWSL_EDITORS" {
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  stub_hide_command code
  omawsl_save_choice OMAWSL_EDITORS "VS Code,Neovim"
  run omawsl_uninstall_command vscode
  [ "$status" -eq 0 ]
  [[ "$(omawsl_load_choice OMAWSL_EDITORS)" == "Neovim" ]]
}

@test "omawsl_uninstall_command deselects a storage option from OMAWSL_STORAGE" {
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  stub_command sudo
  stub_hide_command docker
  omawsl_save_choice OMAWSL_STORAGE "MySQL,Redis"
  run omawsl_uninstall_command mysql
  [ "$status" -eq 0 ]
  [[ "$(omawsl_load_choice OMAWSL_STORAGE)" == "Redis" ]]
}

@test "omawsl_uninstall_command dispatches azure to uninstall/cloud-clis.sh" {
  stub_command sudo
  stub_command az
  run omawsl_uninstall_command azure
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"sudo apt-get purge -y azure-cli"* ]]
}

@test "omawsl_uninstall_command deselects a cloud CLI from OMAWSL_CLOUD_CLIS" {
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  stub_command sudo
  stub_command az
  omawsl_save_choice OMAWSL_CLOUD_CLIS "Azure CLI,AWS CLI"
  run omawsl_uninstall_command azure
  [ "$status" -eq 0 ]
  [[ "$(omawsl_load_choice OMAWSL_CLOUD_CLIS)" == "AWS CLI" ]]
}

@test "omawsl_uninstall_command does not touch choices.env at all for the docker slug" {
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  stub_command sudo
  stub_hide_command docker
  omawsl_save_choice OMAWSL_DOCKER_MODE "Docker Engine only, inside WSL (recommended)"
  run omawsl_uninstall_command docker
  [ "$status" -eq 0 ]
  [[ "$(omawsl_load_choice OMAWSL_DOCKER_MODE)" == "Docker Engine only, inside WSL (recommended)" ]]
}

@test "omawsl_uninstall_command does not deselect when the item was never selected in the first place" {
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  stub_command sudo
  stub_command mise
  run omawsl_uninstall_command go
  [ "$status" -eq 0 ]
  [[ "$(omawsl_load_choice OMAWSL_LANGUAGES)" == "" ]]
}

@test "omawsl_uninstall_command does not deselect anything when dispatch fails for an unknown item" {
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  omawsl_save_choice OMAWSL_LANGUAGES "Go"
  BATS_RUN_ERREXIT=1 run omawsl_uninstall_command not-a-real-item
  [ "$status" -ne 0 ]
  [[ "$(omawsl_load_choice OMAWSL_LANGUAGES)" == "Go" ]]
}

@test "omawsl_uninstall_command dispatches the docker slug to uninstall/docker.sh" {
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  stub_command sudo
  stub_hide_command docker
  run omawsl_uninstall_command docker
  [ "$status" -eq 0 ]
}

@test "omawsl_uninstall_command rejects an unknown item" {
  # omawsl_uninstall_command now has two sequential statements (dispatch,
  # then deselect); bats' run disables errexit by default, which would
  # mask set -e correctly stopping at the first failing statement in real
  # usage - force it back on so this test reflects real set -e behavior.
  BATS_RUN_ERREXIT=1 run omawsl_uninstall_command not-a-real-item
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown item"* ]]
}

@test "omawsl_uninstall_command with no argument prints usage and fails" {
  run omawsl_uninstall_command
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage: omawsl uninstall"* ]]
}
