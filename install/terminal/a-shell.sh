#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMAWSL_REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

omawsl_install_shell_config() {
  cp "$OMAWSL_REPO_ROOT/configs/bashrc" "$HOME/.bashrc"
  cp "$OMAWSL_REPO_ROOT/configs/inputrc" "$HOME/.inputrc"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_install_shell_config
fi
