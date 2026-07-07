#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"

# omawsl_install_vscode_settings [settings_file]
# Deploys configs/vscode.json to VS Code Remote-WSL's machine-level
# settings file. This directory doesn't exist until VS Code has connected
# to this WSL distro via Remote-WSL at least once - creating it ahead of
# time means the settings apply automatically the first time it does
# (design spec §10: "inert until VS Code exists ... pick up automatically
# once it does"), regardless of whether `code` is reachable right now.
omawsl_install_vscode_settings() {
  local settings_file="${1:-$HOME/.vscode-server/data/Machine/settings.json}"
  mkdir -p "$(dirname "$settings_file")"
  cp "$SCRIPT_DIR/../../configs/vscode.json" "$settings_file"
}

# omawsl_install_vscode
# VS Code is a Windows-side GUI app omawsl never auto-installs (design
# spec §2, §10). Detect-and-defer: the settings file above always gets
# deployed (inert until VS Code exists); if `code` isn't reachable via
# Win32 interop, only the one step needing the live binary (installing
# the Remote-WSL extension) is skipped, with a message pointing at
# docs/windows-setup.md. No-ops entirely if VS Code wasn't selected.
omawsl_install_vscode() {
  if ! omawsl_list_has "${OMAWSL_EDITORS:-}" "VS Code"; then
    return 0
  fi

  omawsl_install_vscode_settings

  if omawsl_code_reachable; then
    code --install-extension ms-vscode-remote.remote-wsl
  else
    echo "omawsl: VS Code isn't reachable yet - install it on Windows, then run 'code --install-extension ms-vscode-remote.remote-wsl' yourself, or re-run install.sh."
    echo "See docs/windows-setup.md#vscode for the full steps."
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_install_vscode
fi
