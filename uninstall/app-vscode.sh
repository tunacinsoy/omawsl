#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../install/lib.sh
source "$SCRIPT_DIR/../install/lib.sh"

# omawsl_uninstall_vscode [settings_file]
# Inverse of install/terminal/app-vscode.sh: removes the deployed
# configs/vscode.json copy and uninstalls the Remote-WSL extension if
# `code` is reachable (best-effort - if it isn't, the settings file
# removal below is still the meaningful part).
omawsl_uninstall_vscode() {
  local settings_file="${1:-$HOME/.vscode-server/data/Machine/settings.json}"

  if omawsl_code_reachable; then
    code --uninstall-extension ms-vscode-remote.remote-wsl || true
  fi

  rm -f "$settings_file"
  echo "omawsl: VS Code's omawsl-deployed settings removed."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_uninstall_vscode "$@"
fi
