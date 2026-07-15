#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../install/lib.sh
source "$SCRIPT_DIR/../install/lib.sh"

# omawsl_uninstall_mise_tool <mise_tool> <label>
# <mise_tool> is the tool name (e.g., "go", "ruby"), <label> is the display
# label (e.g., "Go", "Ruby on Rails") for output messaging.
# `mise unuse --global <tool>@latest` both removes the [tools] entry from
# ~/.config/mise/config.toml AND prunes the installed version (verified
# live: help text says "Will also prune the installed version if no other
# configurations are using it"). Confirmed idempotent on a real WSL2
# instance: calling it for a tool that was never configured exits 0
# silently rather than erroring. However, if mise itself is not installed,
# we need to guard against a hard error and return cleanly per design spec §14.
omawsl_uninstall_mise_tool() {
  local mise_tool="$1"
  local label="$2"

  if ! command -v mise &>/dev/null; then
    echo "omawsl: mise isn't installed - nothing to remove for $mise_tool."
    return 0
  fi

  mise unuse --global "${mise_tool}@latest"
  echo "omawsl: $label removed."
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
    "Ruby on Rails") omawsl_uninstall_mise_tool ruby "Ruby on Rails" ;;
    "Node.js")        omawsl_uninstall_mise_tool node "Node.js" ;;
    "Go")             omawsl_uninstall_mise_tool go "Go" ;;
    "PHP")            omawsl_uninstall_mise_tool php "PHP" ;;
    "Python")         omawsl_uninstall_mise_tool python "Python" ;;
    "Elixir")
      omawsl_uninstall_mise_tool elixir "Elixir"
      # erlang is never independently selectable - it's only ever installed
      # as Elixir's own compiler dependency (select-dev-language.sh), so it
      # should go when Elixir does.
      omawsl_uninstall_mise_tool erlang "Erlang"
      ;;
    "Rust")           omawsl_uninstall_mise_tool rust "Rust" ;;
    "Java")           omawsl_uninstall_mise_tool java "Java" ;;
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
