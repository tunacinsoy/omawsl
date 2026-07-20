#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"

# omawsl_gh_copilot_install_steps
# The actual install + wrapper-write commands, no guard - same split
# rationale as omawsl_codex_cli_install_steps/omawsl_gemini_cli_install_steps.
# GitHub retired the `gh extension install github/gh-copilot` path this used
# to go through - Copilot CLI is now the standalone `@github/copilot` npm
# package, invoked as a bare `copilot` command, not `gh copilot` (confirmed
# via GitHub's own install docs). Re-running this always reinstalls at
# whatever version @github/copilot currently resolves to and rewrites the
# wrapper unconditionally, same as the codex/gemini equivalents - so
# bin/omawsl update's orphan-tool apply phase can reuse this function
# directly instead of needing its own separate update-steps function.
omawsl_gh_copilot_install_steps() {
  mise exec node@lts -- npm install -g @github/copilot

  mkdir -p "$HOME/.local/bin"
  cat > "$HOME/.local/bin/copilot" <<'WRAPPER'
#!/usr/bin/env bash
exec mise exec node@lts -- copilot "$@"
WRAPPER
  chmod +x "$HOME/.local/bin/copilot"
}

# omawsl_gh_copilot_remove_old_extension
# One-time migration cleanup: removes the deprecated `gh-copilot` gh
# extension (invoked as `gh copilot ...`) this script used to install
# before GitHub retired that path in favor of the standalone `copilot`
# npm package above. Matches on the "github/gh-copilot" repo-slug column
# like the old uninstall script did - `gh extension list`'s first column
# is actually "gh copilot" (space-separated, the invocation name), not
# "gh-copilot" (hyphenated). Silent no-op if `gh` isn't on PATH or the old
# extension was never installed.
omawsl_gh_copilot_remove_old_extension() {
  if gh extension list 2>/dev/null | grep -q '^gh-copilot\|^gh copilot'; then
    gh extension remove gh-copilot 2>/dev/null || true
  fi
}

# omawsl_install_gh_copilot
# GitHub Copilot CLI - same shape as app-codex-cli.sh/app-gemini-cli.sh:
# npm-only distribution (@github/copilot), installed via a private
# mise-managed Node runtime plus an explicit $HOME/.local/bin/copilot
# wrapper. Idempotent via a command -v guard. Always runs the old-extension
# migration cleanup first (even if `copilot` is already installed), so
# anyone who picked "GitHub Copilot CLI" before this switch doesn't end up
# with both the old gh extension and the new standalone binary.
omawsl_install_gh_copilot() {
  if ! omawsl_list_has "${OMAWSL_EDITORS:-}" "GitHub Copilot CLI"; then
    return 0
  fi

  omawsl_gh_copilot_remove_old_extension

  if command -v copilot &>/dev/null; then
    return 0
  fi

  omawsl_gh_copilot_install_steps
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_install_gh_copilot
fi
