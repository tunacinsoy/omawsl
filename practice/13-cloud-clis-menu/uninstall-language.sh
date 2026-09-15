#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

# Given, as of the START of this lesson - a trimmed copy of the real
# project's uninstall/dev-language.sh, frozen right before this phase.
# omawsl_uninstall_language currently handles both "Terraform" and
# "Azure CLI", because uninstall has always mirrored install's category
# boundaries - and until now, Azure CLI installed through this same
# category.
#
# Your job: move omawsl_uninstall_azure_cli OUT of this file (into the
# new uninstall-cloud-clis.sh you're writing), and remove its case arm
# from omawsl_uninstall_language below. When you're done, passing
# "Azure CLI" to omawsl_uninstall_language here should fall through to
# the unknown-label error case, exactly like passing any other made-up
# label would.

# omawsl_uninstall_terraform [apt_sources_file] [keyrings_dir]
# Inverse of cloud-tools.sh's omawsl_install_terraform. Stays as-is.
omawsl_uninstall_terraform() {
  local apt_sources_file="${1:-${OMAWSL_TERRAFORM_APT_SOURCES_FILE:-/etc/apt/sources.list.d/hashicorp.list}}"
  local keyrings_dir="${2:-${OMAWSL_TERRAFORM_APT_KEYRINGS_DIR:-/etc/apt/keyrings}}"

  if ! command -v terraform &>/dev/null; then
    echo "omawsl: Terraform isn't installed - nothing to do."
    return 0
  fi

  sudo apt-get purge -y terraform
  sudo rm -f "$apt_sources_file" "$keyrings_dir/hashicorp.gpg"
  echo "omawsl: Terraform removed."
}

# omawsl_uninstall_azure_cli [apt_sources_file] [keyrings_dir]
# TODO: DELETE this function from this file - move it (adapted or
# verbatim, your call) into the new uninstall-cloud-clis.sh instead.
omawsl_uninstall_azure_cli() {
  local apt_sources_file="${1:-${OMAWSL_AZURE_CLI_APT_SOURCES_FILE:-/etc/apt/sources.list.d/azure-cli.list}}"
  local keyrings_dir="${2:-${OMAWSL_AZURE_CLI_APT_KEYRINGS_DIR:-/etc/apt/keyrings}}"

  if ! command -v az &>/dev/null; then
    echo "omawsl: Azure CLI isn't installed - nothing to do."
    return 0
  fi

  sudo apt-get purge -y azure-cli
  sudo rm -f "$apt_sources_file" "$keyrings_dir/microsoft.gpg"
  echo "omawsl: Azure CLI removed."
}

# omawsl_uninstall_language <label>
# TODO: remove the "Azure CLI" case arm below - it doesn't belong to this
# category's dispatcher anymore.
omawsl_uninstall_language() {
  local label="$1"
  case "$label" in
    "Terraform") omawsl_uninstall_terraform ;;
    "Azure CLI") omawsl_uninstall_azure_cli ;;
    *)
      echo "omawsl: unknown language/tool '$label'" >&2
      return 1
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_uninstall_language "$@"
fi
