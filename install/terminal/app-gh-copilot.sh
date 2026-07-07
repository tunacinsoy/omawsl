#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"

# omawsl_install_gh_copilot
# GitHub Copilot CLI, installed as a gh extension - depends only on gh
# itself, which apps-terminal.sh now installs unconditionally regardless
# of any picker (Task 1), so there's no cross-picker dependency gap here
# (design spec §10). Actual usability still depends on an authenticated
# gh session and an active Copilot subscription - a README-level runtime
# concern, not an install-time failure.
omawsl_install_gh_copilot() {
  if ! omawsl_list_has "${OMAWSL_EDITORS:-}" "GitHub Copilot CLI"; then
    return 0
  fi

  gh extension install github/gh-copilot
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_install_gh_copilot
fi
