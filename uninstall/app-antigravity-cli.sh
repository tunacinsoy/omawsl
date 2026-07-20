#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../install/lib.sh
source "$SCRIPT_DIR/../install/lib.sh"

# omawsl_uninstall_antigravity_cli
# Inverse of install/terminal/app-antigravity-cli.sh. Antigravity CLI's own
# installer places the binary at $HOME/.local/bin/agy (confirmed via
# antigravity.google/docs/cli/install) and its background self-updater
# keeps state under $HOME/.gemini/antigravity-cli/ (confirmed via
# antigravity.google/docs/cli/troubleshooting) - removing both is a
# complete uninstall.
omawsl_uninstall_antigravity_cli() {
  rm -f "$HOME/.local/bin/agy"
  rm -rf "$HOME/.gemini/antigravity-cli"
  echo "omawsl: Antigravity CLI removed."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_uninstall_antigravity_cli
fi
