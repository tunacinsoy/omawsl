#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../install/lib.sh
source "$SCRIPT_DIR/../install/lib.sh"

# omawsl_uninstall_gemini_cli
# Same shape as omawsl_uninstall_codex_cli, for @google/gemini-cli.
omawsl_uninstall_gemini_cli() {
  if command -v mise &>/dev/null; then
    mise exec node@lts -- npm uninstall -g @google/gemini-cli || true
  fi
  rm -f "$HOME/.local/bin/gemini"
  echo "omawsl: Gemini CLI removed."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_uninstall_gemini_cli
fi
