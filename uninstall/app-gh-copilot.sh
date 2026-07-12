#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../install/lib.sh
source "$SCRIPT_DIR/../install/lib.sh"

# omawsl_uninstall_gh_copilot
# Inverse of install/terminal/app-gh-copilot.sh. `gh extension list`'s
# machine-parseable output starts each line with the invocation name
# ("gh copilot"), but the argument `gh extension remove` actually takes is
# the extension's own directory/repo-derived name ("gh-copilot", confirmed
# on the real test WSL2 instance via
# ~/.local/share/gh/extensions/gh-copilot).
omawsl_uninstall_gh_copilot() {
  if gh extension list 2>/dev/null | grep -q '^gh-copilot\|^gh copilot'; then
    gh extension remove gh-copilot
  fi
  echo "omawsl: GitHub Copilot CLI extension removed (or was already not installed)."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_uninstall_gh_copilot
fi
