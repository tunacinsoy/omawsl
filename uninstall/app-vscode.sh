#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../install/lib.sh
source "$SCRIPT_DIR/../install/lib.sh"

# omawsl_uninstall_vscode [settings_file]
# Inverse of install/terminal/app-vscode.sh: removes the deployed
# configs/vscode.json copy. VS Code itself and its WSL extension are the
# user's, on Windows: omawsl never runs the Windows `code` CLI.
omawsl_uninstall_vscode() {
  local settings_file="${1:-$HOME/.vscode-server/data/Machine/settings.json}"

  rm -f "$settings_file"
  echo "omawsl: VS Code's omawsl-deployed settings removed."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_uninstall_vscode "$@"
fi
