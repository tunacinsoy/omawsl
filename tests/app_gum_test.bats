#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  source "$REPO_ROOT/install/terminal/required/app-gum.sh"
  stub_command sudo
  stub_command curl
  stub_command gpg
}

@test "installs gum via apt-get" {
  sources_file="$BATS_TEST_TMPDIR/charm.list"
  keyrings_dir="$BATS_TEST_TMPDIR/keyrings"
  run omawsl_install_gum "$sources_file" "$keyrings_dir"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"sudo apt-get install -y gum"* ]]
}

@test "refreshes the apt cache before installing" {
  sources_file="$BATS_TEST_TMPDIR/charm.list"
  keyrings_dir="$BATS_TEST_TMPDIR/keyrings"
  run omawsl_install_gum "$sources_file" "$keyrings_dir"
  [[ "$(stub_calls)" == *"sudo apt-get update -qq"* ]]
}

@test "adds the charm apt repo and key when the sources file doesn't exist yet" {
  sources_file="$BATS_TEST_TMPDIR/charm.list"
  keyrings_dir="$BATS_TEST_TMPDIR/keyrings"
  run omawsl_install_gum "$sources_file" "$keyrings_dir"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"sudo install -m 0755 -d $keyrings_dir"* ]]
  [[ "$(stub_calls)" == *"curl -fsSL https://repo.charm.sh/apt/gpg.key"* ]]
  [[ "$(stub_calls)" == *"sudo gpg --yes --dearmor -o $keyrings_dir/charm.gpg"* ]]
  [[ "$(stub_calls)" == *"sudo tee $sources_file"* ]]
}

@test "skips the repo-add step when the sources file already exists" {
  sources_file="$BATS_TEST_TMPDIR/charm.list"
  keyrings_dir="$BATS_TEST_TMPDIR/keyrings"
  : > "$sources_file"
  run omawsl_install_gum "$sources_file" "$keyrings_dir"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"curl -fsSL"* ]]
  [[ "$(stub_calls)" != *"gpg --dearmor"* ]]
  [[ "$(stub_calls)" == *"sudo apt-get install -y gum"* ]]
}

@test "installs gum via apt-get with real default paths when run as the entrypoint script" {
  run bash "$REPO_ROOT/install/terminal/required/app-gum.sh"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"sudo apt-get install -y gum"* ]]
}
