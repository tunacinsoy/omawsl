#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../install/lib.sh
source "$SCRIPT_DIR/../install/lib.sh"

# omawsl_uninstall_herdr
# Inverse of install/terminal/app-herdr.sh. Herdr's installer places the
# binary at $HOME/.local/bin/herdr; its config, sessions and sockets live
# under $HOME/.config/herdr - removing both is a complete uninstall
# (Herdr has no self-uninstall command). Refuses to run inside a Herdr
# pane: stopping Herdr's server would end the very session this runs in.
# If Herdr was the chosen multiplexer, new terminals go back to zellij.
omawsl_uninstall_herdr() {
  if [[ -n "${HERDR_ENV:-}" ]]; then
    echo "omawsl: you're inside Herdr right now - uninstalling would end this session. Run 'omawsl multiplexer zellij', open a new terminal, and uninstall from there." >&2
    return 1
  fi
  if command -v herdr &>/dev/null; then
    herdr server stop >/dev/null 2>&1 || true
  fi
  rm -f "$HOME/.local/bin/herdr"
  rm -rf "$HOME/.config/herdr"
  if [[ "$(omawsl_load_choice OMAWSL_MULTIPLEXER)" == herdr ]]; then
    omawsl_save_choice OMAWSL_MULTIPLEXER zellij
    echo "omawsl: new terminals will open zellij again."
  fi
  echo "omawsl: Herdr removed."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_uninstall_herdr
fi
