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
}

@test "omawsl_item_slugs lists all 10 language slugs, 8 editor slugs, 3 storage slugs" {
  [[ "$(omawsl_item_slugs language | wc -l)" -eq 10 ]]
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

@test "omawsl_uninstall_command dispatches the docker slug to uninstall/docker.sh" {
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  stub_command sudo
  stub_hide_command docker
  run omawsl_uninstall_command docker
  [ "$status" -eq 0 ]
}

@test "omawsl_uninstall_command rejects an unknown item" {
  run omawsl_uninstall_command not-a-real-item
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown item"* ]]
}

@test "omawsl_uninstall_command with no argument prints usage and fails" {
  run omawsl_uninstall_command
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage: omawsl uninstall"* ]]
}
