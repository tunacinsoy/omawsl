#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../install/lib.sh
source "$SCRIPT_DIR/../install/lib.sh"

# omawsl_uninstall_mise_tool <mise_tool>
# `mise unuse --global <tool>@latest` both removes the [tools] entry from
# ~/.config/mise/config.toml AND prunes the installed version (verified
# live: help text says "Will also prune the installed version if no other
# configurations are using it"). Confirmed idempotent on a real WSL2
# instance: calling it for a tool that was never configured exits 0
# silently rather than erroring, so no pre-check is needed here - the
# echo below is what actually satisfies design spec §14's "no-op with an
# informational message, not an error" requirement.
omawsl_uninstall_mise_tool() {
  local mise_tool="$1"
  mise unuse --global "${mise_tool}@latest"
}

# omawsl_uninstall_terraform [apt_sources_file] [keyrings_dir]
# Inverse of install/terminal/cloud-tools.sh's omawsl_install_terraform.
# Same OMAWSL_TERRAFORM_APT_*-overridable paths, for the same testability
# reason.
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
# Inverse of omawsl_install_azure_cli.
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
# Takes the exact picker label (matches OMAWSL_LANGUAGES's own comma-list
# values) rather than a mise tool name or CLI slug - callers translate a
# short slug ("go") to this label via bin/omawsl-sub/items.sh (Task 8).
omawsl_uninstall_language() {
  local label="$1"
  case "$label" in
    "Ruby on Rails") omawsl_uninstall_mise_tool ruby; echo "omawsl: Ruby on Rails removed." ;;
    "Node.js")        omawsl_uninstall_mise_tool node; echo "omawsl: Node.js removed." ;;
    "Go")             omawsl_uninstall_mise_tool go; echo "omawsl: Go removed." ;;
    "PHP")            omawsl_uninstall_mise_tool php; echo "omawsl: PHP removed." ;;
    "Python")         omawsl_uninstall_mise_tool python; echo "omawsl: Python removed." ;;
    "Elixir")         omawsl_uninstall_mise_tool elixir; echo "omawsl: Elixir removed." ;;
    "Rust")           omawsl_uninstall_mise_tool rust; echo "omawsl: Rust removed." ;;
    "Java")           omawsl_uninstall_mise_tool java; echo "omawsl: Java removed." ;;
    "Terraform")      omawsl_uninstall_terraform ;;
    "Azure CLI")      omawsl_uninstall_azure_cli ;;
    *)
      echo "omawsl: unknown language/tool '$label'" >&2
      return 1
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_uninstall_language "$@"
fi
