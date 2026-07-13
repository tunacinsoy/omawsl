#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"

# omawsl_gh_copilot_install_steps
# The actual first-time install command, no guard. Not reused for
# updates: `gh extension install` errors on an already-present extension
# rather than upgrading it in place, so bin/omawsl update's apply phase
# calls omawsl_gh_copilot_update_steps below instead of this function.
omawsl_gh_copilot_install_steps() {
  gh extension install github/gh-copilot
}

# omawsl_gh_copilot_update_steps
# The actual update command for an already-installed GitHub Copilot CLI.
# Genuinely a different command from the install step above, not just
# the same command with a guard removed - `gh extension upgrade` is
# gh's own dedicated update path for an extension already present.
omawsl_gh_copilot_update_steps() {
  gh extension upgrade gh-copilot
}

# omawsl_install_gh_copilot
# GitHub Copilot CLI, installed as a gh extension - depends only on gh
# itself, which apps-terminal.sh installs unconditionally regardless of
# any picker. Idempotent via `gh extension list` (installing an
# already-present extension errors instead of no-opping). Failure-isolated
# the same way cloud-tools.sh isolates a repo-add failure: confirmed on a
# real WSL2 run that `gh extension install` itself needs an authenticated
# session, not just Copilot usage afterward - `gh auth login` hasn't run
# yet on a fresh install, so this is the default case, not an edge case.
#
# The idempotency check matches on the "github/gh-copilot" repo-slug
# column, not the extension's invocation-name column - `gh extension
# list`'s first column is actually "gh copilot" (space-separated, the
# invocation name), not "gh-copilot" (hyphenated).
omawsl_install_gh_copilot() {
  if ! omawsl_list_has "${OMAWSL_EDITORS:-}" "GitHub Copilot CLI"; then
    return 0
  fi

  if gh extension list 2>/dev/null | grep -q 'github/gh-copilot'; then
    return 0
  fi

  if ! omawsl_gh_copilot_install_steps; then
    echo "omawsl: GitHub Copilot CLI install failed (gh not authenticated yet?) - skipping, continuing with the rest of the run."
    echo "Run 'gh auth login', then 'gh extension install github/gh-copilot' yourself, or re-run install.sh."
    echo "See docs/windows-setup.md#github-copilot-cli for why this needs to happen before install.sh, not after."
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_install_gh_copilot
fi
