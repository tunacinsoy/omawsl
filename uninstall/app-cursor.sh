#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../install/lib.sh
source "$SCRIPT_DIR/../install/lib.sh"

# omawsl_uninstall_cursor [settings_file]
# Inverse of install/terminal/app-cursor.sh. No extension-uninstall step -
# app-cursor.sh never installed one either (design spec §10: Cursor's own
# marketplace commonly blocks Microsoft-published extensions).
omawsl_uninstall_cursor() {
  local settings_file="${1:-$HOME/.cursor-server/data/Machine/settings.json}"
  rm -f "$settings_file"
  echo "omawsl: Cursor's omawsl-deployed settings removed."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_uninstall_cursor "$@"
fi
