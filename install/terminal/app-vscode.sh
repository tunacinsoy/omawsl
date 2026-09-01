#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"
# shellcheck source=../../themes/set-vscode-theme.sh
source "$SCRIPT_DIR/../../themes/set-vscode-theme.sh"
# Re-derive SCRIPT_DIR: set-vscode-theme.sh sets its own bare (non-local)
# $SCRIPT_DIR from its own ${BASH_SOURCE[0]} when sourced above, clobbering
# this file's copy (confirmed live - it silently pointed at .../themes
# afterward, which broke omawsl_install_vscode_settings's relative path
# below and made it fail its `cp` under this file's `set -e`).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# omawsl_vscode_disable_auto_update
# Sets "update.mode": "none" in the native Windows-side VS Code
# settings.json - issue #32/#9's actual root cause: the WSL `code` CLI's
# own wrapper script spawns a full Electron/Node helper process on every
# single invocation (even just to locate the Remote-WSL extension), which
# is enough for VS Code's default auto-updater to silently check for,
# download, and stage a new build in the background - confirmed live, a
# single `--locate-extension` call completed a full
# checking-for-updates/downloading/downloaded/ready cycle in under 90
# seconds. Since Remote-WSL's server install is pinned to the exact
# commit of the currently-running Windows-side build, any time that
# staged update actually swaps in (which can happen on the very next
# `code` launch), the WSL side sees a "new" commit and reinstalls the
# whole server - so this can appear to happen on nearly every `code .`,
# not just after a deliberate update. Setting update.mode to "none" makes
# updating VS Code fully opt-in (the user has to trigger it themselves),
# which is exactly what stops the version drift Remote-WSL is reacting
# to. Same detect-and-defer shape as everywhere else in this file: only
# touches the native settings.json if VS Code's own data dir already
# exists (omawsl_theme_ensure_vscode_settings_exists's rule - never
# invents config for software that isn't installed), and silently no-ops
# if the Windows profile can't be resolved at all (e.g. not real WSL2).
omawsl_vscode_disable_auto_update() {
  local profile
  profile="$(omawsl_windows_userprofile)" || return 0
  local code_settings="$profile/AppData/Roaming/Code/User/settings.json"
  omawsl_theme_ensure_vscode_settings_exists "$code_settings"
  omawsl_json_set_string_value "$code_settings" "update.mode" "none"
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
  omawsl_vscode_disable_auto_update

  if omawsl_code_reachable; then
    # NODE_NO_WARNINGS=1: same fix as themes/set-vscode-theme.sh - `code`
    # is a Node.js binary and emits a `[DEP0169] DeprecationWarning:
    # url.parse()...` on a fresh extension install, confirmed Microsoft's
    # own tooling noise, unrelated to omawsl.
    NODE_NO_WARNINGS=1 code --install-extension ms-vscode-remote.remote-wsl
  else
    echo "omawsl: VS Code isn't reachable yet - install it on Windows, then run 'code --install-extension ms-vscode-remote.remote-wsl' yourself, or re-run install.sh."
    echo "See docs/windows-setup.md#vscode for the full steps."
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_install_vscode
fi
