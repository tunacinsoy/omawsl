#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"

# omawsl_antigravity_cli_install_steps
# The actual install command, no guard - same split rationale as
# omawsl_claude_cli_install_steps/omawsl_opencode_install_steps above.
# Antigravity CLI (Google's agentic terminal tool, `agy`) ships its own
# native curl installer - confirmed via antigravity.google/docs/cli/install,
# no npm/mise involved (unlike the old Gemini CLI this replaces). The
# installer places the binary at $HOME/.local/bin/agy and self-updates in
# the background on its own.
omawsl_antigravity_cli_install_steps() {
  curl -fsSL https://antigravity.google/cli/install.sh | bash
}

# omawsl_install_antigravity_cli
# Antigravity CLI - purely WSL-side, no Windows dependency, same shape as
# app-claude-cli.sh. Idempotent via a command -v guard on `agy`, the
# binary the installer registers.
omawsl_install_antigravity_cli() {
  if ! omawsl_list_has "${OMAWSL_EDITORS:-}" "Antigravity CLI"; then
    return 0
  fi

  if command -v agy &>/dev/null; then
    return 0
  fi

  omawsl_antigravity_cli_install_steps
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_install_antigravity_cli
fi
