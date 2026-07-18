#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/uninstall/dev-language.sh"
  stub_command sudo
  stub_command mise
}

@test "omawsl_uninstall_language unpins a mise-managed tool via mise unuse --global" {
  run omawsl_uninstall_language "Go"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"mise unuse --global go@latest"* ]]
  [[ "$output" == *"Go"* ]]
}

@test "omawsl_uninstall_language handles Ruby on Rails by unpinning ruby" {
  run omawsl_uninstall_language "Ruby on Rails"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"mise unuse --global ruby@latest"* ]]
}

@test "omawsl_uninstall_language handles Elixir by unpinning both elixir and erlang" {
  run omawsl_uninstall_language "Elixir"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"mise unuse --global elixir@latest"* ]]
  [[ "$(stub_calls)" == *"mise unuse --global erlang@latest"* ]]
}

@test "omawsl_uninstall_language purges terraform and removes its apt source" {
  # Override sudo to actually perform rm operations (needed to verify file
  # deletion in tests), while still logging calls for stub_calls assertions
  sudo() {
    echo "sudo $*" >> "$STUB_LOG"
    if [[ "$1" == "rm" ]]; then
      shift
      command rm "$@"
      return $?
    fi
    return 0
  }
  export -f sudo
  export OMAWSL_TERRAFORM_APT_SOURCES_FILE="$BATS_TEST_TMPDIR/hashicorp.list"
  export OMAWSL_TERRAFORM_APT_KEYRINGS_DIR="$BATS_TEST_TMPDIR/keyrings"
  touch "$OMAWSL_TERRAFORM_APT_SOURCES_FILE"
  stub_command terraform
  run omawsl_uninstall_language "Terraform"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"sudo apt-get purge -y terraform"* ]]
  [ ! -f "$OMAWSL_TERRAFORM_APT_SOURCES_FILE" ]
}

@test "omawsl_uninstall_language no-ops cleanly when terraform was never installed" {
  stub_hide_command terraform
  run omawsl_uninstall_language "Terraform"
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to do"* ]]
  [[ "$(stub_calls)" != *"apt-get purge"* ]]
}

@test "omawsl_uninstall_language no-ops cleanly when mise was never installed" {
  unset -f mise
  stub_hide_command mise
  run omawsl_uninstall_language "Go"
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to remove"* ]]
  [[ "$(stub_calls)" != *"mise unuse"* ]]
}

@test "omawsl_uninstall_language rejects an unknown label" {
  run omawsl_uninstall_language "Not A Real Language"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown"* ]]
}
