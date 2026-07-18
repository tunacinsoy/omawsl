#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/uninstall/cloud-clis.sh"
  stub_command sudo
}

@test "omawsl_uninstall_azure_cli purges azure-cli and removes its apt source" {
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
  export OMAWSL_AZURE_CLI_APT_SOURCES_FILE="$BATS_TEST_TMPDIR/azure-cli.list"
  export OMAWSL_AZURE_CLI_APT_KEYRINGS_DIR="$BATS_TEST_TMPDIR/keyrings"
  touch "$OMAWSL_AZURE_CLI_APT_SOURCES_FILE"
  stub_command az
  run omawsl_uninstall_azure_cli
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"sudo apt-get purge -y azure-cli"* ]]
  [ ! -f "$OMAWSL_AZURE_CLI_APT_SOURCES_FILE" ]
}

@test "omawsl_uninstall_azure_cli no-ops cleanly when never installed" {
  stub_hide_command az
  run omawsl_uninstall_azure_cli
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to do"* ]]
  [[ "$(stub_calls)" != *"apt-get purge"* ]]
}

@test "omawsl_uninstall_gcp_cli purges google-cloud-cli and removes its apt source" {
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
  export OMAWSL_GCP_CLI_APT_SOURCES_FILE="$BATS_TEST_TMPDIR/google-cloud-sdk.list"
  export OMAWSL_GCP_CLI_APT_KEYRINGS_DIR="$BATS_TEST_TMPDIR/keyrings"
  touch "$OMAWSL_GCP_CLI_APT_SOURCES_FILE"
  stub_command gcloud
  run omawsl_uninstall_gcp_cli
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"sudo apt-get purge -y google-cloud-cli"* ]]
  [ ! -f "$OMAWSL_GCP_CLI_APT_SOURCES_FILE" ]
}

@test "omawsl_uninstall_gcp_cli no-ops cleanly when never installed" {
  stub_hide_command gcloud
  run omawsl_uninstall_gcp_cli
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to do"* ]]
  [[ "$(stub_calls)" != *"apt-get purge"* ]]
}

@test "omawsl_uninstall_aws_cli removes the documented install paths" {
  sudo() {
    echo "sudo $*" >> "$STUB_LOG"
    return 0
  }
  export -f sudo
  stub_command aws
  run omawsl_uninstall_aws_cli
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"sudo rm -rf /usr/local/aws-cli /usr/local/bin/aws /usr/local/bin/aws_completer"* ]]
}

@test "omawsl_uninstall_aws_cli no-ops cleanly when never installed" {
  stub_hide_command aws
  run omawsl_uninstall_aws_cli
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to do"* ]]
  [[ "$(stub_calls)" != *"rm -rf"* ]]
}

@test "omawsl_uninstall_cloud_cli dispatches by label" {
  omawsl_uninstall_azure_cli() { echo "azure-uninstalled" >> "$STUB_LOG"; }
  export -f omawsl_uninstall_azure_cli
  run omawsl_uninstall_cloud_cli "Azure CLI"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"azure-uninstalled"* ]]
}

@test "omawsl_uninstall_cloud_cli rejects an unknown label" {
  run omawsl_uninstall_cloud_cli "Not A Real Cloud CLI"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown"* ]]
}
