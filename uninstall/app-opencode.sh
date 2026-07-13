#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../install/lib.sh
source "$SCRIPT_DIR/../install/lib.sh"

# omawsl_uninstall_opencode
# Inverse of install/terminal/app-opencode.sh: opencode's own installer
# places everything under $HOME/.opencode (bin/ + node_modules/, confirmed
# on the real test WSL2 instance), so removing that directory is a
# complete uninstall.
omawsl_uninstall_opencode() {
  rm -rf "$HOME/.opencode"
  echo "omawsl: opencode removed."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_uninstall_opencode
fi
