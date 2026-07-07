#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/install/terminal/cloud-tools.sh"
  stub_command sudo
  stub_command gpg
}

# --- omawsl_install_terraform ------------------------------------------------

@test "terraform: installs via apt when not already present" {
  stub_command curl
  sources_file="$BATS_TEST_TMPDIR/hashicorp.list"
  keyrings_dir="$BATS_TEST_TMPDIR/keyrings"
  run omawsl_install_terraform "$sources_file" "$keyrings_dir"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"curl -fsSL https://apt.releases.hashicorp.com/gpg"* ]]
  [[ "$(stub_calls)" == *"sudo gpg --dearmor -o $keyrings_dir/hashicorp.gpg"* ]]
  [[ "$(stub_calls)" == *"sudo tee $sources_file"* ]]
  [[ "$(stub_calls)" == *"sudo apt-get install -y terraform"* ]]
}

@test "terraform: no-ops when already installed" {
  stub_command curl
  stub_command terraform
  run omawsl_install_terraform "$BATS_TEST_TMPDIR/hashicorp.list" "$BATS_TEST_TMPDIR/keyrings"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"curl"* ]]
}

@test "terraform: skips the repo-add step when the sources file already exists" {
  stub_command curl
  sources_file="$BATS_TEST_TMPDIR/hashicorp-existing.list"
  : > "$sources_file"
  run omawsl_install_terraform "$sources_file" "$BATS_TEST_TMPDIR/keyrings"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"curl"* ]]
  [[ "$(stub_calls)" == *"sudo apt-get install -y terraform"* ]]
}

@test "terraform: isolates a repo-add failure instead of aborting" {
  stub_command curl 1
  sources_file="$BATS_TEST_TMPDIR/hashicorp-fail.list"
  run omawsl_install_terraform "$sources_file" "$BATS_TEST_TMPDIR/keyrings"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Terraform install failed"* ]]
  [[ "$(stub_calls)" != *"apt-get install -y terraform"* ]]
}

# --- omawsl_install_azure_cli -------------------------------------------------

@test "azure-cli: installs via apt when not already present" {
  stub_command curl
  sources_file="$BATS_TEST_TMPDIR/azure-cli.list"
  keyrings_dir="$BATS_TEST_TMPDIR/keyrings"
  run omawsl_install_azure_cli "$sources_file" "$keyrings_dir"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"curl -fsSL https://packages.microsoft.com/keys/microsoft.asc"* ]]
  [[ "$(stub_calls)" == *"sudo gpg --dearmor -o $keyrings_dir/microsoft.gpg"* ]]
  [[ "$(stub_calls)" == *"sudo tee $sources_file"* ]]
  [[ "$(stub_calls)" == *"sudo apt-get install -y azure-cli"* ]]
}

@test "azure-cli: no-ops when already installed" {
  stub_command curl
  stub_command az
  run omawsl_install_azure_cli "$BATS_TEST_TMPDIR/azure-cli.list" "$BATS_TEST_TMPDIR/keyrings"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"curl"* ]]
}

@test "azure-cli: skips the repo-add step when the sources file already exists" {
  stub_command curl
  sources_file="$BATS_TEST_TMPDIR/azure-cli-existing.list"
  : > "$sources_file"
  run omawsl_install_azure_cli "$sources_file" "$BATS_TEST_TMPDIR/keyrings"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"curl"* ]]
  [[ "$(stub_calls)" == *"sudo apt-get install -y azure-cli"* ]]
}

@test "azure-cli: isolates a repo-add failure instead of aborting" {
  stub_command curl 1
  sources_file="$BATS_TEST_TMPDIR/azure-cli-fail.list"
  run omawsl_install_azure_cli "$sources_file" "$BATS_TEST_TMPDIR/keyrings"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Azure CLI install failed"* ]]
  [[ "$(stub_calls)" != *"apt-get install -y azure-cli"* ]]
}

# --- omawsl_cloud_tools --------------------------------------------------------

@test "cloud_tools: installs both when both are selected" {
  stub_command curl
  export OMAWSL_LANGUAGES="Terraform,Azure CLI"
  omawsl_cloud_tools
  [[ "$(stub_calls)" == *"apt-get install -y terraform"* ]]
  [[ "$(stub_calls)" == *"apt-get install -y azure-cli"* ]]
}

@test "cloud_tools: installs only the one selected" {
  stub_command curl
  export OMAWSL_LANGUAGES="Terraform"
  omawsl_cloud_tools
  [[ "$(stub_calls)" == *"apt-get install -y terraform"* ]]
  [[ "$(stub_calls)" != *"azure-cli"* ]]
}

@test "cloud_tools: selecting neither installs nothing" {
  export OMAWSL_LANGUAGES="Go,Rust"
  omawsl_cloud_tools
  [[ "$(stub_calls)" != *"terraform"* ]]
  [[ "$(stub_calls)" != *"azure-cli"* ]]
}

@test "cloud_tools: a failed terraform repo-add doesn't prevent azure-cli from being attempted" {
  stub_command curl 1
  export OMAWSL_LANGUAGES="Terraform,Azure CLI"
  omawsl_cloud_tools
  [[ "$(stub_calls)" == *"curl -fsSL https://apt.releases.hashicorp.com/gpg"* ]]
  [[ "$(stub_calls)" == *"curl -fsSL https://packages.microsoft.com/keys/microsoft.asc"* ]]
}
