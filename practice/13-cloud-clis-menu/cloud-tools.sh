#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

# Given, as of the START of this lesson - a trimmed copy of the real
# project's install/terminal/cloud-tools.sh, frozen right before this
# phase. It currently installs BOTH Terraform and Azure CLI, reading the
# same OMAWSL_LANGUAGES picker string, because that's the only picker
# Azure CLI has ever lived in until now.
#
# Your job in this lesson: move omawsl_install_azure_cli OUT of this file
# entirely (it's going into a new file, cloud-clis.sh, that you'll write -
# see docs/curriculum/13-cloud-clis-menu.md, section 3), and shrink
# omawsl_cloud_tools below to only handle Terraform. When you're done,
# this file should not define omawsl_install_azure_cli at all, and
# omawsl_cloud_tools should no longer look at "Azure CLI" in
# OMAWSL_LANGUAGES.
#
# omawsl_install_terraform stays exactly as-is - Terraform never moves.

# omawsl_install_terraform [apt_sources_file] [keyrings_dir]
# Idempotent (skips the repo-add once the sources file exists) and
# failure-isolated: because this whole flow runs under set -e, one
# unreachable third-party repo must not cascade into failing every later
# step in the run. The `{ ... } || ok=0` block catches any failure inside
# it without killing the script.
omawsl_install_terraform() {
  local apt_sources_file="${1:-${OMAWSL_TERRAFORM_APT_SOURCES_FILE:-/etc/apt/sources.list.d/hashicorp.list}}"
  local keyrings_dir="${2:-${OMAWSL_TERRAFORM_APT_KEYRINGS_DIR:-/etc/apt/keyrings}}"

  if command -v terraform &>/dev/null; then
    return 0
  fi

  local ok=1
  {
    if [[ ! -f "$apt_sources_file" ]]; then
      sudo install -m 0755 -d "$keyrings_dir" &&
      curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --yes --dearmor -o "$keyrings_dir/hashicorp.gpg" &&
      sudo tee "$apt_sources_file" >/dev/null <<< "deb [arch=$(dpkg --print-architecture) signed-by=$keyrings_dir/hashicorp.gpg] https://apt.releases.hashicorp.com $(. /etc/os-release && echo "$VERSION_CODENAME") main" &&
      sudo apt-get update -qq
    fi &&
    sudo apt-get install -y terraform
  } || ok=0

  if [[ "$ok" -eq 0 ]]; then
    sudo rm -f "$apt_sources_file"
    echo "omawsl: Terraform install failed (repo unreachable?) - skipping, continuing with the rest of the run."
  fi
}

# omawsl_install_azure_cli [apt_sources_file] [keyrings_dir]
# TODO: DELETE this function from this file - move it (adapted or
# verbatim, your call) into the new cloud-clis.sh instead.
omawsl_install_azure_cli() {
  local apt_sources_file="${1:-${OMAWSL_AZURE_CLI_APT_SOURCES_FILE:-/etc/apt/sources.list.d/azure-cli.list}}"
  local keyrings_dir="${2:-${OMAWSL_AZURE_CLI_APT_KEYRINGS_DIR:-/etc/apt/keyrings}}"

  if command -v az &>/dev/null; then
    return 0
  fi

  local ok=1
  {
    if [[ ! -f "$apt_sources_file" ]]; then
      sudo install -m 0755 -d "$keyrings_dir" &&
      curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --yes --dearmor -o "$keyrings_dir/microsoft.gpg" &&
      sudo tee "$apt_sources_file" >/dev/null <<< "deb [arch=$(dpkg --print-architecture) signed-by=$keyrings_dir/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ $(. /etc/os-release && echo "$VERSION_CODENAME") main" &&
      sudo apt-get update -qq
    fi &&
    sudo apt-get install -y azure-cli
  } || ok=0

  if [[ "$ok" -eq 0 ]]; then
    sudo rm -f "$apt_sources_file"
    echo "omawsl: Azure CLI install failed (repo unreachable?) - skipping, continuing with the rest of the run."
  fi
}

# omawsl_cloud_tools
# TODO: edit this so it ONLY reads OMAWSL_LANGUAGES for "Terraform" and
# calls omawsl_install_terraform. The "Azure CLI" branch below needs to
# go away from here - Azure CLI now lives in its own OMAWSL_CLOUD_CLIS
# picker, handled by cloud-clis.sh's own omawsl_cloud_clis instead.
omawsl_cloud_tools() {
  local languages="${OMAWSL_LANGUAGES:-}"

  if omawsl_list_has "$languages" "Terraform"; then
    omawsl_install_terraform
  fi

  if omawsl_list_has "$languages" "Azure CLI"; then
    omawsl_install_azure_cli
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_cloud_tools
fi
