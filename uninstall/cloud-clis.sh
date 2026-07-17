#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../install/lib.sh
source "$SCRIPT_DIR/../install/lib.sh"

# omawsl_uninstall_azure_cli [apt_sources_file] [keyrings_dir]
# Moved verbatim from uninstall/dev-language.sh - inverse of
# install/terminal/cloud-clis.sh's omawsl_install_azure_cli.
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

# omawsl_uninstall_gcp_cli [apt_sources_file] [keyrings_dir]
# Inverse of omawsl_install_gcp_cli.
omawsl_uninstall_gcp_cli() {
  local apt_sources_file="${1:-${OMAWSL_GCP_CLI_APT_SOURCES_FILE:-/etc/apt/sources.list.d/google-cloud-sdk.list}}"
  local keyrings_dir="${2:-${OMAWSL_GCP_CLI_APT_KEYRINGS_DIR:-/etc/apt/keyrings}}"

  if ! command -v gcloud &>/dev/null; then
    echo "omawsl: GCP CLI isn't installed - nothing to do."
    return 0
  fi

  sudo apt-get purge -y google-cloud-cli
  sudo rm -f "$apt_sources_file" "$keyrings_dir/google.gpg"
  echo "omawsl: GCP CLI removed."
}

# omawsl_uninstall_aws_cli
# Removes the three paths AWS's own v2 installer documents
# (https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html#cliv2-linux-uninstall) -
# the install directory plus its two symlinks.
omawsl_uninstall_aws_cli() {
  if ! command -v aws &>/dev/null; then
    echo "omawsl: AWS CLI isn't installed - nothing to do."
    return 0
  fi

  sudo rm -rf /usr/local/aws-cli /usr/local/bin/aws /usr/local/bin/aws_completer
  echo "omawsl: AWS CLI removed."
}

# omawsl_uninstall_cloud_cli <label>
# Takes the exact picker label (matches OMAWSL_CLOUD_CLIS's own comma-list
# values), same shape as uninstall/dev-language.sh's omawsl_uninstall_language.
omawsl_uninstall_cloud_cli() {
  local label="$1"
  case "$label" in
    "Azure CLI") omawsl_uninstall_azure_cli ;;
    "AWS CLI")   omawsl_uninstall_aws_cli ;;
    "GCP CLI")   omawsl_uninstall_gcp_cli ;;
    *)
      echo "omawsl: unknown cloud CLI '$label'" >&2
      return 1
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_uninstall_cloud_cli "$@"
fi
