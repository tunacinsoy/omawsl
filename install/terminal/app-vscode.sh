#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Namespaced, not bare $SCRIPT_DIR: set-vscode-theme.sh (sourced below)
# sets its own bare (non-local) $SCRIPT_DIR from its own ${BASH_SOURCE[0]}
# when sourced, clobbering this file's copy (confirmed live - it silently
# pointed at .../themes afterward, which broke
# omawsl_install_vscode_settings's relative path below and made it fail
# its `cp` under this file's `set -e`). Captured into its own name before
# any sourcing happens, so this stays correct regardless of what else
# gets sourced after it - unlike re-deriving $SCRIPT_DIR post-source,
# which only works as long as this stays the *last* source in the file.
OMAWSL_APP_VSCODE_DIR="$SCRIPT_DIR"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"
# shellcheck source=../../themes/set-vscode-theme.sh
source "$SCRIPT_DIR/../../themes/set-vscode-theme.sh"

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
  cp "$OMAWSL_APP_VSCODE_DIR/../../configs/vscode.json" "$settings_file"
}

# omawsl_vscode_has_wsl_extension
# Whether the Windows profile's VS Code has the WSL extension
# (ms-vscode-remote.remote-wsl), found by looking in its extensions
# folder - omawsl never runs the Windows `code` CLI (CONTRIBUTING.md).
# Without the extension, `code .` opens the folder over \\wsl$ instead of
# connecting to WSL. Answers yes when the profile can't be found: there's
# nothing to look at, so no reason to nag.
omawsl_vscode_has_wsl_extension() {
  local profile ext
  profile="$(omawsl_windows_userprofile)" || return 0
  for ext in "$profile"/.vscode/extensions/ms-vscode-remote.remote-wsl-*; do
    [[ -d "$ext" ]] && return 0
  done
  return 1
}

# omawsl_install_vscode
# VS Code is a Windows-side GUI app omawsl never auto-installs (design
# spec §2, §10), and omawsl never runs its Windows `code` CLI either, so
# the WSL extension is the user's to add in VS Code. Detect-and-defer:
# the settings file above always gets deployed (inert until VS Code
# exists); if VS Code or its WSL extension is missing, it says what to do
# and points at docs/windows-setup.md. No-ops entirely if VS Code wasn't
# selected.
omawsl_install_vscode() {
  if ! omawsl_list_has "${OMAWSL_EDITORS:-}" "VS Code"; then
    return 0
  fi

  omawsl_install_vscode_settings

  if ! omawsl_code_reachable; then
    echo "omawsl: VS Code isn't reachable yet - install it on Windows and add its WSL extension."
    echo "See docs/windows-setup.md#vscode for the full steps."
  elif ! omawsl_vscode_has_wsl_extension; then
    echo "omawsl: add VS Code's WSL extension (ms-vscode-remote.remote-wsl) in VS Code on Windows: Extensions view, search \"WSL\"."
    echo "See docs/windows-setup.md#vscode for the full steps."
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_install_vscode
fi
