#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../install/lib.sh
source "$SCRIPT_DIR/../install/lib.sh"

# omawsl_uninstall_herdr
# Inverse of install/terminal/app-herdr.sh. Herdr's own installer places
# the binary at $HOME/.local/bin/herdr; its session/config state lives
# under $HOME/.config/herdr (session.json, per-named-session
# subdirectories, optional pane history - confirmed via herdr.dev's own
# config-reference docs). Removing both is a complete uninstall - Herdr's
# own CLI has no built-in self-uninstall subcommand to defer to.
omawsl_uninstall_herdr() {
  rm -f "$HOME/.local/bin/herdr"
  rm -rf "$HOME/.config/herdr"
  echo "omawsl: Herdr removed."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_uninstall_herdr
fi
