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
# `mise exec` call is worse than nothing. Also removes "GitHub Copilot CLI"
# from the persisted OMAWSL_EDITORS list directly: this script supports
# direct invocation (footer below, and tests/uninstall_gh_copilot_test.bats
# calls it that way), which bypasses bin/omawsl-sub/uninstall.sh's separate
# omawsl_uninstall_deselect step - without this, a later reinstall would see
# Copilot as "already existing" in OMAWSL_EDITORS and
# omawsl_notice_ai_autopilot_if_needed
# (docs/superpowers/specs/2026-08-14-ai-cli-autopilot-mode-design.md) would
# skip the one-time notice on that reinstall. `gh extension remove` is
# best-effort (`|| true`) for the same reason the npm uninstall above is:
# under `set -euo pipefail`, an unguarded failure there (auth/network/broken
# extension state) would abort the function before the state cleanup below
# ever runs, leaving choices.env stale.
omawsl_uninstall_gh_copilot() {
  if command -v mise &>/dev/null; then
    mise exec node@lts -- npm uninstall -g @github/copilot || true
  fi
  rm -f "$HOME/.local/bin/copilot"

  if gh extension list 2>/dev/null | grep -q '^gh-copilot\|^gh copilot'; then
    gh extension remove gh-copilot || true
  fi

  local editors
  editors="$(omawsl_load_choice OMAWSL_EDITORS)"
  omawsl_save_choice OMAWSL_EDITORS "$(omawsl_remove_from_csv "$editors" "GitHub Copilot CLI")"

  echo "omawsl: GitHub Copilot CLI removed."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_uninstall_gh_copilot
fi
