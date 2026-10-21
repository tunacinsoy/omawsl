#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../install/lib.sh
source "$SCRIPT_DIR/../install/lib.sh"

# omawsl_uninstall_gh_copilot
# Inverse of install/terminal/app-gh-copilot.sh: uninstalls the npm global
# package from every installed mise Node, not just the one node@lts
# resolves to today, then removes the $HOME/.local/bin/copilot wrapper.
# Sweeping every version (issue #16): the reported uninstall's npm step
# printed "up to date" - npm's "nothing to remove" - under node@lts while
# a `copilot` elsewhere kept running, e.g. one installed under an older
# Node or by hand with a mise-activated global Node. Also removes the
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
# omawsl_uninstall_deselect step - without this, a direct-invoked uninstall
# would leave Copilot listed as still selected. `gh extension remove` is
# best-effort (`|| true`) for the same reason the npm uninstall above is:
# under `set -euo pipefail`, an unguarded failure there (auth/network/broken
# extension state) would abort the function before the state cleanup below
# ever runs, leaving choices.env stale. Finally re-checks PATH: a
# `copilot` omawsl never installed (Windows side via /mnt/c interop,
# GitHub's install script in /usr/local/bin, ...) is never deleted - it
# isn't omawsl's to remove - but it's named instead of claiming the CLI
# is gone, which is what made issue #16 look like a no-op uninstall.
omawsl_uninstall_gh_copilot() {
  if command -v mise &>/dev/null; then
    local version
    for version in $(mise ls --installed node --no-header 2>/dev/null | awk '{print $2}'); do
      mise exec "node@$version" -- npm uninstall -g @github/copilot || true
    done
  fi
  rm -f "$HOME/.local/bin/copilot"

  # A string, not a pipe - see omawsl_theme_is_valid in bin/omawsl-sub/theme.sh.
  if grep -q '^gh-copilot\|^gh copilot' <<< "$(gh extension list 2>/dev/null)"; then
    gh extension remove gh-copilot || true
  fi

  local editors
  editors="$(omawsl_load_choice OMAWSL_EDITORS)"
  omawsl_save_choice OMAWSL_EDITORS "$(omawsl_remove_from_csv "$editors" "GitHub Copilot CLI")"

  hash -r
  local leftover
  leftover="$(type -ap copilot 2>/dev/null || true)"
  if [[ -n "$leftover" ]]; then
    echo "omawsl: removed omawsl's GitHub Copilot CLI, but another \`copilot\` that omawsl didn't install is still on PATH:"
    local path
    while IFS= read -r path; do echo "  $path"; done <<< "$leftover"
    echo "omawsl: remove it yourself (e.g. winget/npm on Windows, or 'sudo rm' for /usr/local/bin), then open a new terminal."
    return 0
  fi
  echo "omawsl: GitHub Copilot CLI removed."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_uninstall_gh_copilot
fi
