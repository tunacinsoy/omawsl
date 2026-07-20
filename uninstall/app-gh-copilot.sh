#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../install/lib.sh
source "$SCRIPT_DIR/../install/lib.sh"

# omawsl_uninstall_gh_copilot
# Inverse of install/terminal/app-gh-copilot.sh: uninstalls the npm global
# package via the same private mise-managed Node runtime it was installed
# with, then removes the $HOME/.local/bin/copilot wrapper. Also removes the
# old deprecated `gh-copilot` gh extension (invoked as `gh copilot ...`),
# for anyone who still has it from before the switch to the standalone
# `@github/copilot` npm package - same repo-slug-column match the old
# uninstall used, since `gh extension list`'s first column is the
# space-separated invocation name ("gh copilot"), not the hyphenated
# "gh-copilot". No-ops the npm step (but still removes the wrapper) if
# mise isn't reachable, since a leftover wrapper pointing at a now-broken
# `mise exec` call is worse than nothing.
omawsl_uninstall_gh_copilot() {
  if command -v mise &>/dev/null; then
    mise exec node@lts -- npm uninstall -g @github/copilot || true
  fi
  rm -f "$HOME/.local/bin/copilot"

  if gh extension list 2>/dev/null | grep -q '^gh-copilot\|^gh copilot'; then
    gh extension remove gh-copilot
  fi

  echo "omawsl: GitHub Copilot CLI removed."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_uninstall_gh_copilot
fi
