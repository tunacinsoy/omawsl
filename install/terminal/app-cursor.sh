#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"

# omawsl_install_cursor
# Cursor is a Windows-side GUI app (a VS Code fork) omawsl never
# auto-installs (design spec §2, §10) - same detect-and-defer shape as
# app-vscode.sh. Cursor reads the same settings.json keys as VS Code, so
# it shares the exact same configs/vscode.json baseline (design spec
# §11). Deliberately does NOT attempt a `cursor --install-extension`
# step the way app-vscode.sh does for VS Code: Cursor has its own
# extension distribution, and Microsoft's marketplace commonly blocks
# non-VS-Code products from installing Microsoft-published extensions -
# not specified precisely enough in the design spec to assume it works,
# so this only deploys what's clearly specified (shared settings).
omawsl_install_cursor() {
  if ! omawsl_list_has "${OMAWSL_EDITORS:-}" "Cursor"; then
    return 0
  fi

  local settings_file="$HOME/.cursor-server/data/Machine/settings.json"
  mkdir -p "$(dirname "$settings_file")"
  cp "$SCRIPT_DIR/../../configs/vscode.json" "$settings_file"

  if ! omawsl_cursor_reachable; then
    echo "omawsl: Cursor isn't reachable yet - install it on Windows and connect to this WSL distro once; the settings above will apply automatically."
    echo "See docs/windows-setup.md#cursor for the full steps."
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_install_cursor
fi
