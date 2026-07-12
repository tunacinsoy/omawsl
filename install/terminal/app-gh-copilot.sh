#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"

# omawsl_install_gh_copilot
# GitHub Copilot CLI, installed as a gh extension - depends only on gh
# itself, which apps-terminal.sh now installs unconditionally regardless
# of any picker (Task 1), so there's no cross-picker dependency gap here
# (design spec §10). Idempotent via `gh extension list` (installing an
# already-present extension errors instead of no-opping). Failure-isolated
# the same way cloud-tools.sh isolates a repo-add failure: confirmed on a
# real WSL2 run that `gh extension install` itself needs an authenticated
# session, not just Copilot usage afterward - `gh auth login` hasn't run
# yet on a fresh install, so this is the default case, not an edge case.
# Without isolation, this single failure (under set -e, sourced not
# sub-shelled) silently aborted the entire rest of install.sh, including
# every script after this one in the dispatch order.
#
# The idempotency check matches on the "github/gh-copilot" repo-slug
# column, not the extension's invocation-name column - `gh extension
# list`'s first column is actually "gh copilot" (space-separated, the
# invocation name), not "gh-copilot" (hyphenated), confirmed live on a
# real WSL2 instance. A `grep -q '^gh-copilot'` check against that first
# column never matches real output, so this check was previously always
# false and `gh extension install` was attempted on every re-run.
omawsl_install_gh_copilot() {
  if ! omawsl_list_has "${OMAWSL_EDITORS:-}" "GitHub Copilot CLI"; then
    return 0
  fi

  if gh extension list 2>/dev/null | grep -q 'github/gh-copilot'; then
    return 0
  fi

  if ! gh extension install github/gh-copilot; then
    echo "omawsl: GitHub Copilot CLI install failed (gh not authenticated yet?) - skipping, continuing with the rest of the run."
    echo "Run 'gh auth login', then 'gh extension install github/gh-copilot' yourself, or re-run install.sh."
    echo "See docs/windows-setup.md#github-copilot-cli for why this needs to happen before install.sh, not after."
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_install_gh_copilot
fi
