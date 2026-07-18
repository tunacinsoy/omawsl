#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/install/terminal/cloud-clis.sh"
  stub_command sudo
  stub_command gpg
  stub_hide_command az gcloud aws
  export OMAWSL_AZURE_CLI_APT_SOURCES_FILE="$BATS_TEST_TMPDIR/azure-cli-default.list"
  export OMAWSL_AZURE_CLI_APT_KEYRINGS_DIR="$BATS_TEST_TMPDIR/keyrings-default"
  export OMAWSL_GCP_CLI_APT_SOURCES_FILE="$BATS_TEST_TMPDIR/google-cloud-sdk-default.list"
  export OMAWSL_GCP_CLI_APT_KEYRINGS_DIR="$BATS_TEST_TMPDIR/keyrings-default"
}

# --- omawsl_install_azure_cli (moved from cloud-tools.sh, same behavior) ---

@test "azure-cli: installs via apt when not already present" {
  stub_command curl
  sources_file="$BATS_TEST_TMPDIR/azure-cli.list"
  keyrings_dir="$BATS_TEST_TMPDIR/keyrings"
  run omawsl_install_azure_cli "$sources_file" "$keyrings_dir"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"curl -fsSL -o /dev/null https://packages.microsoft.com/repos/azure-cli/dists/"*"/Release"* ]]
  [[ "$(stub_calls)" == *"curl -fsSL https://packages.microsoft.com/keys/microsoft.asc"* ]]
  [[ "$(stub_calls)" == *"sudo gpg --yes --dearmor -o $keyrings_dir/microsoft.gpg"* ]]
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

@test "azure-cli: isolates a repo-add failure instead of aborting" {
  stub_command curl 1
  sources_file="$BATS_TEST_TMPDIR/azure-cli-fail.list"
  run omawsl_install_azure_cli "$sources_file" "$BATS_TEST_TMPDIR/keyrings"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Azure CLI install failed"* ]]
  [[ "$(stub_calls)" != *"apt-get install -y azure-cli"* ]]
}

# --- omawsl_install_gcp_cli -------------------------------------------------

@test "gcp-cli: installs via apt when not already present" {
  stub_command curl
  sources_file="$BATS_TEST_TMPDIR/google-cloud-sdk.list"
  keyrings_dir="$BATS_TEST_TMPDIR/keyrings"
  run omawsl_install_gcp_cli "$sources_file" "$keyrings_dir"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg"* ]]
  [[ "$(stub_calls)" == *"sudo gpg --yes --dearmor -o $keyrings_dir/google.gpg"* ]]
  [[ "$(stub_calls)" == *"sudo tee $sources_file"* ]]
  [[ "$(stub_calls)" == *"sudo apt-get install -y google-cloud-cli"* ]]
}

@test "gcp-cli: no-ops when already installed" {
  stub_command curl
  stub_command gcloud
  run omawsl_install_gcp_cli "$BATS_TEST_TMPDIR/google-cloud-sdk.list" "$BATS_TEST_TMPDIR/keyrings"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"curl"* ]]
}

@test "gcp-cli: skips the repo-add step when the sources file already exists" {
  stub_command curl
  sources_file="$BATS_TEST_TMPDIR/google-cloud-sdk-existing.list"
  : > "$sources_file"
  run omawsl_install_gcp_cli "$sources_file" "$BATS_TEST_TMPDIR/keyrings"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"curl"* ]]
  [[ "$(stub_calls)" == *"sudo apt-get install -y google-cloud-cli"* ]]
}

@test "gcp-cli: isolates a repo-add failure instead of aborting" {
  stub_command curl 1
  sources_file="$BATS_TEST_TMPDIR/google-cloud-sdk-fail.list"
  run omawsl_install_gcp_cli "$sources_file" "$BATS_TEST_TMPDIR/keyrings"
  [ "$status" -eq 0 ]
  [[ "$output" == *"GCP CLI install failed"* ]]
  [[ "$(stub_calls)" != *"apt-get install -y google-cloud-cli"* ]]
}

@test "gcp-cli: removes the sources file when apt-get itself fails, so a retry doesn't inherit a broken repo listing" {
  sudo() {
    echo "sudo $*" >> "$STUB_LOG"
    if [[ "$1" == "apt-get" ]]; then
      return 1
    fi
    if [[ "$1" == "rm" ]]; then
      shift
      command rm "$@"
      return $?
    fi
    return 0
  }
  export -f sudo
  sources_file="$BATS_TEST_TMPDIR/google-cloud-sdk-preexisting.list"
  : > "$sources_file"
  run omawsl_install_gcp_cli "$sources_file" "$BATS_TEST_TMPDIR/keyrings"
  [ "$status" -eq 0 ]
  [ ! -f "$sources_file" ]
  [[ "$output" == *"GCP CLI install failed"* ]]
}

# --- AWS CLI -----------------------------------------------------------------

@test "aws-cli-arch: maps dpkg's arm64 to aarch64, everything else to x86_64" {
  dpkg() { echo "arm64"; }
  export -f dpkg
  [ "$(omawsl_aws_cli_arch)" = "aarch64" ]

  dpkg() { echo "amd64"; }
  export -f dpkg
  [ "$(omawsl_aws_cli_arch)" = "x86_64" ]
}

@test "aws-cli: install_steps downloads the right arch zip, unzips, and runs the installer" {
  dpkg() { echo "amd64"; }
  export -f dpkg
  stub_command curl
  stub_command unzip
  omawsl_aws_cli_install_steps
  [[ "$(stub_calls)" == *"curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o "* ]]
  [[ "$(stub_calls)" == *"unzip -q"* ]]
  [[ "$(stub_calls)" == *"sudo"*"/aws/install --update"* ]]
}

@test "aws-cli: install_steps isolates a download failure instead of aborting" {
  dpkg() { echo "amd64"; }
  export -f dpkg
  stub_command curl 1
  run omawsl_aws_cli_install_steps
  [ "$status" -eq 1 ]
  [[ "$output" == *"AWS CLI install failed"* ]]
}

@test "aws-cli: omawsl_install_aws_cli no-ops when already installed" {
  stub_command aws
  run omawsl_install_aws_cli
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"curl"* ]]
}

@test "aws-cli: omawsl_install_aws_cli calls install_steps when not already installed" {
  omawsl_aws_cli_install_steps() { echo "aws-install-steps-called" >> "$STUB_LOG"; }
  export -f omawsl_aws_cli_install_steps
  run omawsl_install_aws_cli
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"aws-install-steps-called"* ]]
}

@test "aws-cli: omawsl_install_aws_cli swallows a real install_steps failure so a fresh install run isn't aborted" {
  dpkg() { echo "amd64"; }
  export -f dpkg
  stub_command curl 1
  run omawsl_install_aws_cli
  [ "$status" -eq 0 ]
  [[ "$output" == *"AWS CLI install failed"* ]]
}

# --- omawsl_cloud_clis ---------------------------------------------------------

@test "cloud_clis: installs all three when all three are selected" {
  stub_command curl
  omawsl_aws_cli_install_steps() { echo "aws-installed" >> "$STUB_LOG"; }
  export -f omawsl_aws_cli_install_steps
  export OMAWSL_CLOUD_CLIS="Azure CLI,AWS CLI,GCP CLI"
  omawsl_cloud_clis
  [[ "$(stub_calls)" == *"apt-get install -y azure-cli"* ]]
  [[ "$(stub_calls)" == *"aws-installed"* ]]
  [[ "$(stub_calls)" == *"apt-get install -y google-cloud-cli"* ]]
}

@test "cloud_clis: installs only the one selected" {
  stub_command curl
  export OMAWSL_CLOUD_CLIS="Azure CLI"
  omawsl_cloud_clis
  [[ "$(stub_calls)" == *"apt-get install -y azure-cli"* ]]
  [[ "$(stub_calls)" != *"google-cloud-cli"* ]]
  [[ "$(stub_calls)" != *"aws"* ]]
}

@test "cloud_clis: selecting none installs nothing" {
  export OMAWSL_CLOUD_CLIS=""
  omawsl_cloud_clis
  [[ "$(stub_calls)" != *"azure-cli"* ]]
  [[ "$(stub_calls)" != *"google-cloud-cli"* ]]
  [[ "$(stub_calls)" != *"aws"* ]]
}
