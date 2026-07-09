#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../install/lib.sh
source "$SCRIPT_DIR/../install/lib.sh"

# omawsl_theme_set_vscode_settings <settings_file> <color_theme>
# Merges "workbench.colorTheme" into an existing VS Code/Cursor-shaped
# settings.json via jq, never a blind sed (design spec §11 - jq is the
# safer choice, though the real risk there is the Windows Terminal
# edit's nested schemes array; kept consistent here too). No-ops if the
# settings file doesn't exist yet (VS Code/Cursor not selected in
# Phase 4's picker, so app-vscode.sh/app-cursor.sh never deployed it) or
# if jq itself isn't reachable.
omawsl_theme_set_vscode_settings() {
  local settings_file="$1" color_theme="$2"
  [[ -f "$settings_file" ]] || return 0
  command -v jq &>/dev/null || return 0
  local tmp
  tmp="$(mktemp)"
  jq --arg theme "$color_theme" '.["workbench.colorTheme"] = $theme' "$settings_file" > "$tmp"
  mv "$tmp" "$settings_file"
}

# omawsl_theme_apply_vscode <color_theme> <extension_id>
# Applies the theme to both VS Code's and Cursor's Remote settings.json,
# whichever exist (design spec §11: "VS Code theme step also covers
# Cursor", since Cursor reads the same settings.json keys). Installs the
# VS Code extension via `code --install-extension` only when `code` is
# reachable - matches app-vscode.sh's own detect-and-defer shape
# (Phase 4). Deliberately does NOT attempt `cursor --install-extension`,
# same reasoning as app-cursor.sh (Phase 4): Cursor has its own
# extension distribution and commonly blocks Microsoft-published
# extensions from its marketplace, so this only touches what's clearly
# specified (shared settings keys).
omawsl_theme_apply_vscode() {
  local color_theme="$1" extension_id="$2"

  omawsl_theme_set_vscode_settings "$HOME/.vscode-server/data/Machine/settings.json" "$color_theme"
  omawsl_theme_set_vscode_settings "$HOME/.cursor-server/data/Machine/settings.json" "$color_theme"

  if omawsl_code_reachable; then
    code --install-extension "$extension_id" >/dev/null
  fi
}
