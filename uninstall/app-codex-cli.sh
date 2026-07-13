#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../install/lib.sh
source "$SCRIPT_DIR/../install/lib.sh"

# omawsl_uninstall_codex_cli
# Inverse of install/terminal/app-codex-cli.sh: uninstalls the npm global
# package via the same private mise-managed Node runtime it was installed
# with, then removes the $HOME/.local/bin/codex wrapper. No-ops the npm
# step (but still removes the wrapper) if mise isn't reachable, since a
# leftover wrapper pointing at a now-broken `mise exec` call is worse than
# nothing.
omawsl_uninstall_codex_cli() {
  if command -v mise &>/dev/null; then
    mise exec node@lts -- npm uninstall -g @openai/codex || true
  fi
  rm -f "$HOME/.local/bin/codex"
  echo "omawsl: Codex CLI removed."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_uninstall_codex_cli
fi
